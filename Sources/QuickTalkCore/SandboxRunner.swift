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
    // stdout 을 먼저 읽어야 파이프가 차서 멈추지 않는다
    let outData = out.fileHandleForReading.readDataToEndOfFile()
    let errData = err.fileHandleForReading.readDataToEndOfFile()

    let deadline = Date().addingTimeInterval(timeout)
    while p.isRunning && Date() < deadline {
      usleep(20_000)
    }
    if p.isRunning {
      p.terminate()
      usleep(100_000)
      if p.isRunning { kill(p.processIdentifier, SIGKILL) }
      p.waitUntilExit()
      return SandboxResult(exitCode: -1,
                           stdout: clip(String(data: outData, encoding: .utf8) ?? "", limit: outputLimit),
                           stderr: "시간 초과(\(Int(timeout))초)")
    }
    p.waitUntilExit()
    return SandboxResult(exitCode: p.terminationStatus,
                         stdout: clip(String(data: outData, encoding: .utf8) ?? "", limit: outputLimit),
                         stderr: clip(String(data: errData, encoding: .utf8) ?? "", limit: outputLimit))
  }

  private static func clip(_ text: String, limit: Int) -> String {
    text.count <= limit ? text : String(text.prefix(limit)) + "\n… (출력 잘림)"
  }

  // MARK: - 요구 권한 실측

  /// ★ 핵심 — 읽기 전용으로 먼저 실행해 요구 권한을 알아낸다.
  public static func probe(_ command: String, timeout: TimeInterval = 20) -> SandboxProbe {
    // 상승권은 구조적으로 먼저 판정한다(샌드박스로는 sudo 자체를 막을 수 없다).
    if RiskClassifier.requiresElevation(command) {
      return SandboxProbe(command: command, capability: .elevated,
                          result: SandboxResult(exitCode: -1, stdout: "", stderr: ""))
    }
    let r = run(command, profile: readOnlyProfile(), timeout: timeout)
    if r.succeeded { return SandboxProbe(command: command, capability: .read, result: r) }

    // ① 파일 쓰기 차단 — 메시지에 경로가 함께 나온다(/bin/sh: /path: Operation not permitted)
    if let path = deniedPath(in: r.combined) {
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
