import Foundation

// [FEATURE] 위험도 판정 — 구조적 신호만 (PLAN_v0.18 §4.3)
//
// **명령·패키지 이름 목록을 두지 않는다.** `brew`·`adb`·`ollama` 같은 이름을 알면 목록이 늘기만 하고
// (`pip`·`uv`·`npx`·`cargo`…) 새 형태(`curl | sh`, `python -c`)는 계속 빠져나간다.
// 대신 **권한 체계**에서만 판단한다: 상승권·시스템 전역 경로·파이프→인터프리터·재귀 삭제 대상.
//
// 실측 근거: docs/qa/t18-spike/spike-sandbox-negotiation.log (7/7 정확)

public enum RiskClassifier {
  /// 상승권 표시자 — 권한 체계의 이름만 본다(앱·패키지 이름이 아님).
  private static let privilegeMarkers = ["sudo", "doas", "administrator privileges"]
  /// 시스템 전역 설정을 바꾸는 도구(권한 체계).
  private static let systemConfigTools = ["launchctl", "systemsetup", "csrutil", "nvram",
                                          "spctl", "visudo", "fdesetup", "dscl", "diskutil"]
  /// 시스템 전역 경로 — "시스템 영역"만 판정한다.
  private static let systemPaths = ["/System", "/usr", "/bin", "/sbin", "/etc",
                                    "/var/db", "/private/etc", "/Library/LaunchDaemons",
                                    "/Library/LaunchAgents", "/Library/Preferences",
                                    "/dev/", "/Volumes"]
  /// 파이프 → 인터프리터(원격 코드 실행 형태).
  private static let interpreters = ["sh", "bash", "zsh", "python", "python3", "perl", "node", "ruby"]
  /// 재귀+강제 삭제로 시스템 전체를 지우는 대상(정확히 일치할 때만).
  /// **소문자로만 쓴다** — 비교 대상도 소문자로 정규화한다.
  /// (2026-10-22 수정: "/Users" 가 대문자라 `rm -rf /Users` 이 치명적으로 잡히지 않았다)
  private static let catastrophicTargets: Set<String> = ["/", "/system", "/users", "/volumes",
                                                           "/library", "/private", "~", "$home"]
  /// **파일을 바꾸는** 명령 — 시스템 경로를 "대상으로" 다룰 때만 위험 신호가 된다.
  /// (/usr/bin/df 처럼 **실행 경로를 참조**하는 것은 읽기라 문제가 없다)
  private static let mutatingCommands: Set<String> = [
    "rm", "mv", "cp", "chmod", "chown", "tee", "dd", "install", "ln", "mkdir", "touch",
    "rmdir", "truncate", "shred", "defaults", "launchctl", "systemsetup", "csrutil",
    "nvram", "spctl", "dscl", "visudo", "fdesetup", "diskutil"
  ]

  /// 공백 기준으로 자른다 — `|` 는 **남겨 둔다**(파이프 판정에 쓴다).
  public static func tokenize(_ command: String) -> [String] {
    command.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == ";" || $0 == "\n" })
      .map(String.init)
  }

  /// 위험도 판정.
  public static func classify(_ command: String) -> AgentRiskLevel {
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
    // `defaults`는 **쓰기일 때만** 위험하다 — `defaults read com.apple.dock` 은 읽기다.
    // (2026-10-26: 읽기까지 중요로 잡혀 "항상 허용"을 눌러도 매번 다시 묻던 원인)
    if lower.contains("defaults"), isDefaultsMutation(lower),
       lower.contains("-g") || lower.contains(where: { $0.hasPrefix("com.apple.") }) {
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

  /// 상승권이 필요한가 — 샌드박스로는 막을 수 없어 미리 판정한다.
  public static func requiresElevation(_ command: String) -> Bool {
    let lower = command.lowercased()
    return privilegeMarkers.contains { lower.contains($0) }
  }

  /// ★ 쓰기 범위로 절대 열면 안 되는 경로 — 루트와 시스템 전역.
  ///
  /// 실측이 "쓰기 대상"으로 뽑은 경로가 이 목록에 있으면 앱은 쓰기를 열지 않는다.
  /// (`rm -rf /` 가 실측에서 "/" 를 잡으면 그대로 열면 디스크 전체가 지워진다)
  public static let systemScopeRoots: Set<String> = [
    "/", "/System", "/usr", "/bin", "/sbin", "/etc", "/var", "/private",
    "/Library", "/Volumes", "/Users", "/opt", "/home", "/cores", "/pkg"
  ]

  /// 경로가 시스템 전역(루트 포함)인가 — 이 경로에는 쓰기를 열지 않는다.
  public static func isSystemScopePath(_ path: String) -> Bool {
    var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if p.count > 1 && p.hasSuffix("/") { p.removeLast() }
    if p == "~" || p == "$HOME" { return true }
    if p.hasPrefix("~/") { p = NSHomeDirectory() + String(p.dropFirst()) }
    if p == "/" { return true }
    if p == NSHomeDirectory() { return true }
    return systemScopeRoots.contains(p)
  }

  /// `rm -rf /` 처럼 시스템 전체를 지우는 경우만 치명적. `/var/tmp/x` 는 아니다.
  private static func isCatastrophicRemoval(_ tokens: [String]) -> Bool {
    guard let idx = tokens.firstIndex(where: { $0.lowercased().hasSuffix("rm") }) else { return false }
    let rest = tokens[(idx + 1)...].map { $0.lowercased() }
    let recursive = rest.contains { $0.hasPrefix("-") && $0.contains("r") }
    let force = rest.contains { $0.hasPrefix("-") && $0.contains("f") }
    guard recursive, force else { return false }
    let targets = rest.filter { !$0.hasPrefix("-") }
    return targets.contains { catastrophicTargets.contains($0) }
  }

  private static func mentionsSystemPath(_ tokens: [String]) -> Bool {
    // 시스템 경로를 **대상으로** 다루는 변경 명령이 있을 때만 위험 신호다.
    // (/usr/bin/df 처럼 실행 경로를 참조하는 것은 읽기다)
    let lower = tokens.map { $0.lowercased() }
    for (index, token) in lower.enumerated() {
      guard mutatingCommands.contains(token) else { continue }
      // `defaults` 는 write 일 때만(읽기는 무해), `diskutil` 은 위에서 이미 걸렸다.
      if token == "defaults" && !lower.contains("write") { continue }
      let targets = lower[(index + 1)...].filter { !$0.hasPrefix("-") }
      if targets.contains(where: { isSystemPath($0) }) { return true }
    }
    return false
  }

  private static func isSystemPath(_ token: String) -> Bool {
    let p = token.hasPrefix("~") ? String(token.dropFirst()) : token
    return systemPaths.contains { p == $0 || p.hasPrefix($0 + "/") }
  }

  private static func isPipeToInterpreter(_ tokens: [String]) -> Bool {
    guard let pipeIdx = tokens.firstIndex(of: "|"), pipeIdx + 1 < tokens.count else { return false }
    let rest = tokens[(pipeIdx + 1)...].map { $0.lowercased() }
    let first = rest.first ?? ""
    guard interpreters.contains(where: { first == $0 || first.hasPrefix($0 + " ") }) else {
      return false
    }
    // `python3 -c "…"` 처럼 코드를 **인자로** 받는 경우는 파이프 내용을 실행하지 않는다.
    // (`curl … | sh` 는 그대로 중요 — 인터프리터가 표준입력을 코드로 읽는다)
    let inlineCodeFlags: Set<String> = ["-c", "-e", "--eval", "-E"]
    return !rest.contains(where: { inlineCodeFlags.contains($0) })
  }

  /// `defaults` 가 값을 바꾸는 호출인가 — `read`/`read-type`/`domains`/`find`/`export` 는 읽기다.
  private static func isDefaultsMutation(_ lower: [String]) -> Bool {
    guard let idx = lower.firstIndex(of: "defaults") else { return false }
    // `defaults -currentHost write …` 처럼 플래그가 먼저 올 수 있다.
    for token in lower[(idx + 1)...] where !token.hasPrefix("-") {
      return token == "write" || token == "delete" || token == "rename"
    }
    return false
  }
}
