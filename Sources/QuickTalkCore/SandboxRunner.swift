import Foundation

// [FEATURE] 샌드박스 실행 · 요구 권한 실측 (PLAN_v0.18 §4.1)
//
// 앱은 명령어 이름을 모른다. 대신 **읽기 전용 샌드박스로 먼저 실행**해
// "이 명령이 무슨 권한을 요구하는지"를 OS에 물어본다.
// 쓰기가 막히면 에러 메시지에 **경로가 같이** 나오므로, 승인 시 그 경로만 열어 재실행할 수 있다.
//
// 실측 근거: docs/qa/t18-spike/spike-sandbox-negotiation.log
//   df/ls/brew list/adb devices → 읽기 · echo > 파일 → 쓰기(경로) · curl → 네트워크 · sudo → 상승 권한

#if canImport(Darwin)
import Darwin
#endif

/// 명령이 요구하는 권한 — 샌드박스 실행 결과에서 실측한다.
public enum AgentCapability: Equatable {
  /// 읽기만으로 충분
  case read
  /// 파일 쓰기 필요(차단된 경로)
  case write(path: String)
  /// 네트워크 필요
  case network
  /// 상승 권한 필요(sudo 등)
  case elevated
  /// 샌드박스 외의 이유로 실패
  case blocked

  /// 이 요구를 충족시키기 위해 필요한 권한 단계.
  public var level: AgentPermissionLevel {
    switch self {
    case .read: return .read
    case .write: return .write
    case .network, .elevated: return .execute
    case .blocked: return .execute
    }
  }

  public var summary: String {
    switch self {
    case .read: return L("읽기")
    case .write(let path): return Lf("쓰기(%@)", path)
    case .network: return L("네트워크")
    case .elevated: return L("상승 권한")
    case .blocked: return L("차단됨")
    }
  }
}

/// 실행 결과.
public struct SandboxResult: Equatable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String

  public var combined: String { stdout + "\n" + stderr }
  public var succeeded: Bool { exitCode == 0 }
}

/// 실측 결과(명령 + 요구 권한 + 실행 결과).
public struct SandboxProbe: Equatable {
  public let command: String
  public let capability: AgentCapability
  public let result: SandboxResult
}

public enum SandboxRunner {
  /// 샌드박스 실행 경로 — 시스템 도구(sandbox-exec)가 없으면 없다.
  public static var sandboxExecPath: String { "/usr/bin/sandbox-exec" }

  public static var isAvailable: Bool {
    FileManager.default.isExecutableFile(atPath: sandboxExecPath)
  }

  // MARK: - 프로파일

  /// 읽기 전용 — 쓰기·네트워크 차단. `/dev/null` 만 예외 허용(리다이렉트가 흔함).
  public static func readOnlyProfile() -> String {
    "(version 1)(allow default)(deny file-write*)(allow file-write* (literal \"/dev/null\"))(deny network*)"
  }

  /// 승인된 경로만 쓰기를 허용 — 그 밖은 계속 막는다(승인이 스코프로 제한된다).
  /// 경로는 **symlink를 완전히 해석**해 넣어야 한다(/var → /private/var).
  public static func scopedProfile(writablePaths: [String], allowNetwork: Bool = false) -> String {
    var p = "(version 1)(allow default)(deny file-write*)"
    p += "(allow file-write* (literal \"/dev/null\"))"
    for path in writablePaths {
      // ★ 시스템 전역(루트 포함) 경로에는 쓰기를 열지 않는다 — 이 경로가 열리면
      //   앱이 디스크 전체를 지울 수 있다(2026-10-22 사고).
      if RiskClassifier.isSystemScopePath(path) { continue }
      p += "(allow file-write* (subpath \"\(resolveRealPath(path))\"))"
    }
    if allowNetwork { p += "(allow network*)" }
    return p
  }

  /// 상승 권한까지 허용하는 프로파일 — `sudo` 는 샌드박스로 막을 수 없어 별도다.
  public static func elevatedProfile(writablePaths: [String]) -> String {
    var p = "(version 1)(allow default)(allow network*)"
    if !writablePaths.isEmpty {
      p += "(deny file-write*)"
      p += "(allow file-write* (literal \"/dev/null\"))"
      for path in writablePaths {
        p += "(allow file-write* (subpath \"\(resolveRealPath(path))\"))"
      }
    }
    return p
  }

  /// realpath(3) — 존재하는 경로만 해석된다. `URL.resolvingSymlinksInPath()` 는 /var 를 못 푼다.
  public static func resolveRealPath(_ path: String) -> String {
    #if canImport(Darwin)
    guard let c = realpath(path, nil) else { return path }
    defer { free(c) }
    return String(cString: c)
    #else
    return path
    #endif
  }

  // MARK: - 실행

  /// 명령 실행. 출력이 지나치면 잘라낸다(메모리·화면 폭주 방지).
  ///
  /// ★ 타임아웃이 **반드시** 동작해야 한다(2026-10-22 사고: `rm -rf /` 실측이 끝나지 않아 앱이 멈췄다).
  ///   이전 구현은 `readDataToEndOfFile()` 를 먼저 불러 프로세스가 끝날 때까지 블로킹했다
  ///   → 기한 검사에 도달하지 못했다. 이제는 파이프를 **별도 스레드에서 비동기로** 읽고
  ///   기한이 오면 먼저 죽인다. 한쪽 파이프를 끝까지 읽으면 다른 쪽이 차서 멈추는
  ///   교착도 같이 사라진다(stdout·stderr 를 동시에 읽는다).
  public static func run(_ command: String,
                         profile: String,
                         timeout: TimeInterval = 30,
                         outputLimit: Int = 64_000) -> SandboxResult {
    guard isAvailable else {
      return SandboxResult(exitCode: -1, stdout: "",
                           stderr: "샌드박스를 사용할 수 없습니다(sandbox-exec 없음).")
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: sandboxExecPath)
    p.arguments = ["-p", profile, "/bin/sh", "-c", command]
    let out = Pipe(), err = Pipe()
    p.standardOutput = out
    p.standardError = err
    do {
      try p.run()
    } catch {
      return SandboxResult(exitCode: -1, stdout: "", stderr: "실행 실패: \(error.localizedDescription)")
    }
    // stdout·stderr 를 **동시에** 비동기로 읽는다(한쪽을 끝까지 읽으면 다른 쪽이 막힘).
    let collector = OutputCollector()
    collector.drain(out.fileHandleForReading, stream: .stdout)
    collector.drain(err.fileHandleForReading, stream: .stderr)

    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline {
      usleep(20_000)
    }
    var timedOut = false
    if p.isRunning {
      timedOut = true
      p.terminate()
      usleep(200_000)
      if p.isRunning { kill(p.processIdentifier, SIGKILL) }
    }
    p.waitUntilExit()
    // 파이프를 붙든 자식이 남아 있을 수 있어 잠깐만 기다린다(늦어도 2초).
    collector.wait(timeout: 2)
    let stdout = clip(collector.stdout, limit: outputLimit)
    let stderr = clip(collector.stderr, limit: outputLimit)
    if timedOut {
      return SandboxResult(exitCode: -1, stdout: stdout,
                           stderr: "시간 초과(\(Int(timeout))초)")
    }
    return SandboxResult(exitCode: p.terminationStatus,
                         stdout: stdout,
                         stderr: stderr)
  }

  /// 파이프 출력을 모아두는 도우미 — 교착 없이 읽기 위해 스레드를 쓴다.
  private final class OutputCollector: @unchecked Sendable {
    enum Stream { case stdout, stderr }
    private let lock = NSLock()
    private var buffers: [Stream: Data] = [.stdout: Data(), .stderr: Data()]
    private let group = DispatchGroup()
    private let queue = DispatchQueue(label: "quicktalk.sandbox.io", attributes: .concurrent)

    func drain(_ handle: FileHandle, stream: Stream) {
      group.enter()
      queue.async { [self] in
        let data = handle.readDataToEndOfFile()
        self.lock.lock()
        self.buffers[stream, default: Data()].append(data)
        self.lock.unlock()
        self.group.leave()
      }
    }

    var stdout: String { text(.stdout) }
    var stderr: String { text(.stderr) }

    private func text(_ stream: Stream) -> String {
      lock.lock()
      defer { lock.unlock() }
      return String(data: buffers[stream] ?? Data(), encoding: .utf8) ?? ""
    }

    /// 기한이 있으면 그때 포기한다.
    func wait(timeout: TimeInterval) {
      _ = group.wait(timeout: .now() + timeout)
    }
  }

  private static func clip(_ text: String, limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit)) + "\n… (출력 잘림)"
  }

  // MARK: - 요구 권한 실측

  /// ★ 실측(실행)해도 되는 명령인가 — 위험 판정으로 정한다.
  ///
  /// 실측은 **실제로 명령을 실행한다**(읽기 전용 샌드박스). 그래서 위험·중요 명령은
  /// 승인받기 **전에** 실행하면 안 된다(2026-10-22 사고: `rm -rf /` 가 실측에서 실행돼
  /// 앱이 멈췄다 — 파일은 읽기 전용 샌드박스라 지워지지 않았지만 명령이 끝나지 않았다).
  public static func isSafeToProbe(_ command: String) -> Bool {
    RiskClassifier.classify(command) == .normal
  }

  /// ★ 핵심 — 읽기 전용으로 먼저 실행해 요구 권한을 알아낸다.
  ///
  /// 위험·중요 명령은 **실행하지 않고** 막는다(승인을 먼저 받고 `probeApproved` 로 실측한다).
  public static func probe(_ command: String, timeout: TimeInterval = 20) -> SandboxProbe {
    // 상승권은 **실행 없이** 판정할 수 있다(샌드박스로는 sudo 자체를 막을 수 없다).
    if RiskClassifier.requiresElevation(command) {
      return SandboxProbe(command: command, capability: .elevated,
                          result: SandboxResult(exitCode: -1, stdout: "", stderr: ""))
    }
    guard isSafeToProbe(command) else {
      return SandboxProbe(command: command, capability: .blocked,
                          result: SandboxResult(exitCode: -1, stdout: "",
                                                stderr: "위험한 명령은 승인 전에 실행하지 않습니다."))
    }
    return runProbe(command, timeout: timeout)
  }

  /// 승인을 **받은 뒤에만** 쓰는 실측 — 위험 판정을 이미 통과한 명령이다.
  public static func probeApproved(_ command: String, timeout: TimeInterval = 20) -> SandboxProbe {
    runProbe(command, timeout: timeout)
  }

  private static func runProbe(_ command: String, timeout: TimeInterval) -> SandboxProbe {
    // 상승권은 구조적으로 먼저 판정한다(샌드박스로는 sudo 자체를 막을 수 없다).
    if RiskClassifier.requiresElevation(command) {
      return SandboxProbe(command: command, capability: .elevated,
                          result: SandboxResult(exitCode: -1, stdout: "", stderr: ""))
    }
    let r = run(command, profile: readOnlyProfile(), timeout: timeout)
    if r.succeeded { return SandboxProbe(command: command, capability: .read, result: r) }

    // ① 파일 쓰기 차단 — 메시지에 경로가 함께 나온다(/bin/sh: /path: Operation not permitted)
    if let path = deniedPath(in: r.combined) {
      // ★ 시스템 전역(루트 포함) 경로의 쓰기는 **절대 열지 않는다.**
      //   실측이 "/" 를 뽑아내면 그대로 열면 디스크 전체가 지워질 수 있다.
      if RiskClassifier.isSystemScopePath(path) {
        return SandboxProbe(command: command, capability: .blocked, result: r)
      }
      return SandboxProbe(command: command, capability: .write(path: path), result: r)
    }
    // ② 네트워크 — 샌드박스는 "막기만" 하고 실패는 도구 자신의 신호로 온다
    if looksLikeNetworkFailure(r) {
      return SandboxProbe(command: command, capability: .network, result: r)
    }
    // ③ 그 밖의 실패(명령 없음·옵션 오류 등)는 **권한 문제가 아니다**
    //    → 읽기 권한으로 분류한다. 실행은 읽기 전용 프로필로 가고(쓰기는 샌드박스가 막는다),
    //    오류는 그대로 모델에게 돌아가 다음 시도를 시킨다.
    //    (요청하지 않은 승인을 떠올리면 안 된다 — 2026-10-22 실측)
    return SandboxProbe(command: command, capability: .read, result: r)
  }

  /// 차단된 경로 추출 — 콜론으로 나눈 조각 중 "/" 로 시작하는 **마지막** 조각.
  public static func deniedPath(in message: String) -> String? {
    for line in message.split(separator: "\n") {
      let lower = line.lowercased()
      guard lower.contains("operation not permitted") || lower.contains("permission denied")
              || lower.contains("deny file-write") else { continue }
      let parts = line.split(separator: ":", omittingEmptySubsequences: true)
      let candidates = parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { $0.hasPrefix("/") }
      if let path = candidates.last { return path }
    }
    return nil
  }

  /// 네트워크가 필요한지 — 도구 자신의 실패 신호로 판정한다.
  public static func looksLikeNetworkFailure(_ r: SandboxResult) -> Bool {
    let text = r.combined.lowercased()
    let markers = ["cannot resolve host", "unknown host", "could not resolve",
                   "temporary failure in name resolution", "nodename nor servname",
                   "network is unreachable", "no route to host", "network is down",
                   "connection refused", "connection timed out", "couldn't connect to server",
                   "unable to connect to server", "name or service not known"]
    if markers.contains(where: { text.contains($0) }) { return true }
    // curl(6) · ping(68) 등 도구별 종료코드
    if r.exitCode == 6 || r.exitCode == 68 || r.exitCode == 7 { return true }
    return false
  }
}
