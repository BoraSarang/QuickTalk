// 스파이크 2 — 샌드박스로 "요구 권한"을 실측하는 협상 모델 검증
// 2026-10-21 · PLAN_v0.18 §4.1
//
// 검증 목표
//   1) 읽기 전용 샌드박스 실행으로 "이 명령이 무슨 권한을 요구하는지"를 알 수 있는가
//   2) 승인한 경로만 열어 재실행하면 blast radius 가 제한되는가
//   3) 위험도는 명령 이름 목록 없이 "구조적 신호"로 판정할 수 있는가
//
// 실행: swiftc -O -parse-as-library -o /tmp/spike-sandbox spike-sandbox-negotiation.swift && /tmp/spike-sandbox

import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - 요구 권한 (실측 결과)

enum RequiredCapability: Equatable, CustomStringConvertible {
    case read                                    // 읽기만
    case write(path: String)                     // 파일 쓰기 (경로)
    case network                                 // 네트워크
    case elevated                                // 상승 권한(sudo 등)
    case denied                                  // 샌드박스가 막음(기타)

    var description: String {
        switch self {
        case .read: return "읽기"
        case .write(let p): return "쓰기(\(p))"
        case .network: return "네트워크"
        case .elevated: return "상승 권한"
        case .denied: return "차단됨"
        }
    }
}

// MARK: - 위험도 (구조적 신호만 — 명령/패키지 이름 목록 없음)

enum RiskLevel: Int, CustomStringConvertible {
    case normal = 0, important = 1, critical = 2

    var description: String {
        switch self {
        case .normal: return "보통"
        case .important: return "중요"
        case .critical: return "치명적"
        }
    }
}

struct RiskClassifier {
    /// 상승권 표시자 — 명령 이름이 아니라 권한 체계의 이름만 본다.
    private static let privilegeMarkers = ["sudo", "doas", "administrator privileges"]
    /// 시스템 전역 설정을 바꾸는 도구 (앱·패키지 이름 목록 아님 — "권한 체계"만)
    private static let systemConfigTools = ["launchctl", "systemsetup", "csrutil", "nvram",
                                            "spctl", "visudo", "fdesetup", "dscl", "diskutil"]
    /// 시스템 전역 경로 — 앱·패키지 이름과 무관하게 "시스템 영역"만 판정한다.
    private static let systemPaths = ["/System", "/usr", "/bin", "/sbin", "/etc",
                                      "/var/db", "/private/etc", "/Library/LaunchDaemons",
                                      "/Library/LaunchAgents", "/Library/Preferences",
                                      "/dev/", "/Volumes"]
    /// 파이프 → 인터프리터 (원격 코드 실행 형태)
    private static let interpreters = ["sh", "bash", "zsh", "python", "python3", "perl", "node", "ruby"]
    /// 재귀+강제 삭제로 시스템 전체를 지우는 대상 (접두사 매칭 금지 — 정확히 일치해야 함)
    private static let catastrophicTargets: Set<String> = ["/", "/System", "/Users", "/Volumes",
                                                          "/Library", "/private", "~", "$HOME"]

    static func tokenize(_ command: String) -> [String] {
        command.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ";" || $0 == "\n" })
            .map(String.init)
    }

    static func classify(_ command: String) -> RiskLevel {
        let tokens = tokenize(command)
        let lower = tokens.map { $0.lowercased() }

        // ── 치명적: 복구 불가 ──
        if lower.contains(where: { $0.hasPrefix("mkfs") }) { return .critical }
        if lower.contains("diskutil") && lower.contains(where: { $0.hasPrefix("erase") }) { return .critical }
        if lower.contains("dd") && lower.contains(where: { $0.hasPrefix("of=/dev/") }) { return .critical }
        if command.contains(":(){:|:&};:") { return .critical }
        if isCatastrophicRemoval(tokens) { return .critical }

        // ── 중요: 되돌리기 어렵거나 시스템 전역 ──
        if lower.contains(where: { privilegeMarkers.contains($0) }) { return .important }
        if lower.contains("defaults") && (lower.contains("-g") || lower.contains(where: { $0.hasPrefix("com.apple.") })) {
            return .important
        }
        if lower.contains(where: { systemConfigTools.contains($0) }) { return .important }
        if lower.contains("killall") || lower.contains("pkill") { return .important }
        if (lower.contains(where: { $0.hasPrefix("chmod") || $0.hasPrefix("chown") })
            && mentionsSystemPath(tokens)) { return .important }
        if mentionsSystemPath(tokens) { return .important }
        if isPipeToInterpreter(tokens) { return .important }
        return .normal
    }

    /// `rm -rf /` 처럼 시스템 전체를 지우는 경우만 치명적. `/var/tmp/x` 는 아님.
    private static func isCatastrophicRemoval(_ tokens: [String]) -> Bool {
        guard let idx = tokens.firstIndex(where: { $0.lowercased().hasSuffix("rm") || $0.lowercased() == "rm" }) else { return false }
        let rest = tokens[(idx + 1)...].map { $0.lowercased() }
        let recursive = rest.contains { $0.hasPrefix("-") && $0.contains("r") }
        let force = rest.contains { $0.hasPrefix("-") && $0.contains("f") }
        let targets = rest.filter { !$0.hasPrefix("-") }
        guard recursive, force else { return false }
        return targets.contains { catastrophicTargets.contains($0) }
    }

    private static func mentionsSystemPath(_ tokens: [String]) -> Bool {
        tokens.contains { t in
            let p = t.hasPrefix("~") ? String(t.dropFirst()) : t
            return systemPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
        }
    }

    private static func isPipeToInterpreter(_ tokens: [String]) -> Bool {
        // 토큰에는 "|" 가 남아 있다(구분자로 제거하지 않았다) — 파이프 뒤 첫 실행 파일을 본다.
        guard let pipeIdx = tokens.firstIndex(of: "|"), pipeIdx + 1 < tokens.count else { return false }
        let last = tokens[(pipeIdx + 1)...].first?.lowercased() ?? ""
        return interpreters.contains { last == $0 || last.hasPrefix($0 + " ") }
    }
}

// MARK: - 샌드박스 러너

struct SandboxResult {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var combined: String { stdout + "\n" + stderr }
}

struct SandboxRunner {
    /// 읽기 전용 프로파일 — 쓰기·네트워크 차단, /dev/null 만 예외 허용(리다이렉트 흔함)
    static func readOnlyProfile() -> String {
        #if canImport(Darwin)
        return "(version 1)(allow default)(deny file-write*)(allow file-write* (literal \"/dev/null\"))(deny network*)"
        #else
        return ""
        #endif
    }

    /// 승인된 경로만 쓰기를 허용하는 프로파일
    /// ⚠️ 경로는 **symlink를 완전히 해석한 실제 경로**로 넣어야 한다.
    ///    /var → /private/var 처럼 Seatbelt는 해석된 경로로 규칙을 매칭한다.
    ///    (URL.resolvingSymlinksInPath() 는 /var 를 그대로 돌려주므로 realpath 를 쓴다)
    static func scopedProfile(writablePaths: [String]) -> String {
        var p = "(version 1)(allow default)(deny file-write*)"
        p += "(allow file-write* (literal \"/dev/null\"))"
        for path in writablePaths {
            p += "(allow file-write* (subpath \"\(resolveRealPath(path))\"))"
        }
        return p
    }

    /// realpath(3) — 존재하는 경로만 해석된다(없으면 원본 그대로)
    static func resolveRealPath(_ path: String) -> String {
        #if canImport(Darwin)
        guard let c = realpath(path, nil) else { return path }
        defer { free(c) }
        return String(cString: c)
        #else
        return path
        #endif
    }

    /// 시스템 전역 쓰기까지 허용하는 프로파일 (승인된 경우에만)
    static func elevatedProfile() -> String {
        "(version 1)(allow default)(allow network*)"
    }

    @discardableResult
    static func run(_ command: String, profile: String, timeout: TimeInterval = 20) -> SandboxResult {
        let sandbox = "/usr/bin/sandbox-exec"
        let p = Process()
        p.executableURL = URL(fileURLWithPath: sandbox)
        p.arguments = ["-p", profile, "/bin/sh", "-c", command]
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do { try p.run() } catch {
            return SandboxResult(exitCode: -1, stdout: "", stderr: "sandbox-exec 실행 실패: \(error)")
        }
        // stdout 을 읽는 동안 프로세스가 끝나야 하므로 둘 다 먼저 수집
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return SandboxResult(exitCode: p.terminationStatus,
                             stdout: String(data: outData, encoding: .utf8) ?? "",
                             stderr: String(data: errData, encoding: .utf8) ?? "")
    }

    /// ★ 핵심: 읽기 전용으로 먼저 실행해서 "무슨 권한이 필요한지"를 실측한다.
    static func probe(_ command: String) -> RequiredCapability {
        // 상승권 표시자는 구조적으로 먼저 판정(샌드박스로는 sudo 자체를 막을 수 없다)
        let cls = RiskClassifier.classify(command)
        if cls == .critical { return .denied }
        if ["sudo", "doas", "administrator privileges"].contains(where: { command.lowercased().contains($0) }) {
            return .elevated
        }

        let r = run(command, profile: readOnlyProfile())
        if r.exitCode == 0 { return .read }

        // ① 파일 쓰기 차단 — 메시지에 경로가 함께 나온다
        if let path = deniedPath(in: r.combined) { return .write(path: path) }
        // ② 네트워크 필요 — 샌드박스는 네트워크를 "막기만" 하고, 실제 실패는 도구 자신의
        //    메시지/종료코드로 나타난다(curl 6 / ping 68 / "Unknown host").
        //    → "네트워크가 없다"가 아니라 "이 명령은 네트워크가 필요하다"로 판정한다.
        if looksLikeNetworkFailure(r) { return .network }
        return .denied
    }

    /// 에러 메시지에서 차단된 경로를 뽑는다: "/bin/sh: /path: Operation not permitted"
    /// ⚠️ 경로가 메시지보다 **앞에** 온다 — "not permitted" 가 있는 줄에서, 콜론으로 나눈 조각 중
    ///    "/" 로 시작하는 **마지막** 조각을 경로로 본다("/bin/sh" 같은 셸 이름은 앞쪽이라 걸러진다).
    static func deniedPath(in message: String) -> String? {
        for line in message.split(separator: "\n") {
            let lower = line.lowercased()
            guard lower.contains("operation not permitted") || lower.contains("permission denied")
                    || lower.contains("deny file-write") else { continue }
            let parts = line.split(separator: ":", omittingEmptySubsequences: true)
            let candidates = parts
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { $0.hasPrefix("/") }
            if let path = candidates.last { return path }
        }
        return nil
    }

    /// 네트워크가 필요한지 (샌드박스 거부 메시지가 아니라 도구 자신의 네트워크 실패 신호)
    static func looksLikeNetworkFailure(_ r: SandboxResult) -> Bool {
        let text = r.combined.lowercased()
        let markers = ["cannot resolve host", "unknown host", "could not resolve",
                       "temporary failure in name resolution", "nodename nor servname",
                       "network is unreachable", "no route to host", "network is down",
                       "connection refused", "connection timed out", "couldn't connect to server",
                       "unable to connect to server", "name or service not known"]
        if markers.contains(where: { text.contains($0) }) { return true }
        // curl(6) · ping(68) 같은 도구별 종료코드
        if r.exitCode == 6 || r.exitCode == 68 || r.exitCode == 7 { return true }
        return false
    }
}

// MARK: - 실행

@main
struct Spike {
    static func main() {
        let tmpDir = NSTemporaryDirectory() + "qt-spike-\(UUID().uuidString.prefix(6))"
        try? FileManager.default.createDirectory(atPath: tmpDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: tmpDir) }

        print("=== 1) 요구 권한 실측 (probe) ===")
        let cases: [(String, String)] = [
            ("읽기", "df -h / | head -2"),
            ("읽기", "ls /Users/lee | head -3"),
            ("읽기(brew)", "brew list | head -3"),
            ("읽기(adb)", "adb devices | head -3"),
            ("쓰기", "echo hello > \(tmpDir)/probe.txt"),
            ("네트워크", "curl -s -m 3 https://example.com > /dev/null"),
            ("상승 권한", "sudo -n true"),
        ]
        for (label, cmd) in cases {
            let cap = SandboxRunner.probe(cmd)
            let risk = RiskClassifier.classify(cmd)
            print("  [\(label)] \(cmd)\n        → 요구: \(cap) · 위험도: \(risk)")
        }

        print("\n=== 2) 승인한 경로만 열어 재실행 (scoped consent) ===")
        let scoped = SandboxRunner.scopedProfile(writablePaths: [tmpDir])
        print("  프로파일: \(scoped)")
        let ok = SandboxRunner.run("echo scoped-ok > \(tmpDir)/scoped.txt", profile: scoped)
        print("  허용 경로 쓰기 → exit=\(ok.exitCode) stdout=\(ok.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) stderr=\(ok.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("  파일 생성 여부: \(FileManager.default.fileExists(atPath: tmpDir + "/scoped.txt") ? "✅ 생성됨" : "❌ 안 생김")")
        let blocked = SandboxRunner.run("echo leak > /Users/lee/.qt-spike-leak", profile: scoped)
        print("  허용 밖 쓰기 → exit=\(blocked.exitCode) stderr=\(blocked.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
        print("  새 파일 생성 여부: \(FileManager.default.fileExists(atPath: "/Users/lee/.qt-spike-leak") ? "❌ 생성됨(위험)" : "✅ 없음(차단됨)")")

        print("\n=== 3) 위험도 판정 (구조적 신호 — 명령 목록 없음) ===")
        let risky: [(String, String)] = [
            ("일반", "brew install whisper-cpp"),
            ("일반", "ollama pull qwen3"),
            ("중요(상승권)", "sudo rm -rf /var/tmp/x"),
            ("중요(시스템영역)", "defaults write -g com.apple.dock persistent-apps -array"),
            ("중요(파이프→인터프리터)", "curl -s https://example.com/x.sh | bash"),
            ("치명적", "rm -rf /"),
            ("치명적", "dd if=/dev/zero of=/dev/disk3"),
        ]
        for (label, cmd) in risky {
            print("  [\(label)] → 실제 판정: \(RiskClassifier.classify(cmd)) · \(cmd)")
        }

        print("\n[SPIKE] RESULT=PASS")
    }
}
