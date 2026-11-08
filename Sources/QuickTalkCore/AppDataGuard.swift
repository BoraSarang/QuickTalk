import Foundation

// [FEATURE] 앱 자기 데이터 보호 (2026-11-08)
//
// 배경: 모델이 `history.json` 을 셸로 직접 읽어 **다른 대화의 내용**을 답변에
// 끌어온 사례가 있었다(`agent-audit.log` 2026-11-05 12:16Z — read_file/shell 7회).
// 공통 메모리(🧠)와 무관하게 대화 사이가 섞여 보이는 원인이므로, 앱이 스스로 쓰는
// 데이터 폴더는 **자동 허용에서 제외**하고 어떤 경로로 접근하든 승인 카드를 거친다.
//
// 보호 범위
//   · ~/Library/Application Support/QuickTalk (history·memory·schedules·secrets·audit …)
//   · ~/Library/Preferences/com.borasarang.QuickTalk.plist (UserDefaults 설정)
//
// 한계(정직): 셸 명령 문자열에 경로가 **드러난 경우**만 잡는다. 변수 조합·난독화·
// `find ~ -name history.json` 처럼 경로 없이 찾는 우회까지 막지는 못한다(최소 가드).
public enum AppDataGuard {
  /// 앱 데이터 폴더(정규화된 절대 경로).
  public static func appDataDirectory(home: String = NSHomeDirectory()) -> String {
    URL(fileURLWithPath: home)
      .appendingPathComponent("Library/Application Support/QuickTalk", isDirectory: true)
      .standardizedFileURL.path
  }

  /// 이 경로가 앱 자기 데이터인가 — 파일 하나든 폴더 하나든 하위 전부 포함.
  public static func isProtected(path: String, home: String = NSHomeDirectory()) -> Bool {
    guard !path.isEmpty else { return false }
    let target = URL(fileURLWithPath: expand(path, home: home)).standardizedFileURL.path
    let dir = appDataDirectory(home: home)
    if target == dir || target.hasPrefix(dir + "/") { return true }
    let prefs = URL(fileURLWithPath: home)
      .appendingPathComponent("Library/Preferences/com.borasarang.QuickTalk.plist")
      .standardizedFileURL.path
    return target == prefs
  }

  /// 셸 명령이 보호 대상 경로를 직접 건드리는가.
  ///
  /// `~`·`$HOME`·따옴표·이스케이프된 공백은 모두 같은 문자열로 취급한다.
  /// `QuickTalkReport` 처럼 이름이 겹치는 **다른 폴더**는 잡지 않는다(경계 검사).
  public static func commandTouchesProtectedData(_ command: String,
                                                 home: String = NSHomeDirectory()) -> Bool {
    guard !command.isEmpty else { return false }
    let flattened = command
      .replacingOccurrences(of: "\\ ", with: " ")
      .replacingOccurrences(of: "\\~", with: "~")
    if containsPathReference(flattened, "Library/Application Support/QuickTalk") { return true }
    // 설정(UserDefaults) 도메인을 직접 읽는 명령 — `defaults read com.borasarang.QuickTalk`
    if containsPathReference(flattened, "com.borasarang.QuickTalk") { return true }
    return false
  }

  /// 정책이 자동 허용한 셸 명령을 **승인 카드**로 승격한다.
  ///
  /// 정책이 이미 확인을 요구(`.ask`)했거나 차단(`.deny`)했으면 그 판정을 그대로 둔다 —
  /// 보호 데이터라도 사용자가 거부한 명령을 되살리지 않는다.
  public static func guardedPlan(_ plan: AgentPlan, command: String,
                                 home: String = NSHomeDirectory()) -> AgentPlan {
    guard commandTouchesProtectedData(command, home: home) else { return plan }
    switch plan {
    case .deny:
      return plan
    case .ask(let request):
      // 이미 확인을 요구한 명령도 **이유**를 앱 데이터 접근으로 바꾸고 '항상 허용'을 숨긴다.
      return .ask(AgentApprovalRequest(
        command: request.command, level: request.level, risk: request.risk,
        capability: request.capability, writablePaths: request.writablePaths,
        reason: L("QuickTalk의 저장 데이터(대화 기록·공통 메모리)에 접근하려면 확인이 필요합니다."),
        uiAppName: request.uiAppName, uiAppBundleID: request.uiAppBundleID,
        irreversible: request.irreversible, detail: request.detail,
        allowsAlwaysAllow: false))
    case .allow:
      return .ask(AgentApprovalRequest(
        command: command, level: .read, risk: .normal,
        capability: .unprobed, writablePaths: [],
        reason: L("QuickTalk의 저장 데이터(대화 기록·공통 메모리)에 접근하려면 확인이 필요합니다."),
        allowsAlwaysAllow: false))
    }
  }

  // MARK: - 내부

  /// `~` 를 **주어진 home** 으로만 확장한다(테스트가 실제 홈을 건드리지 않게).
  private static func expand(_ path: String, home: String) -> String {
    if path == "~" { return home }
    if path.hasPrefix("~/") { return home + String(path.dropFirst(1)) }
    return path
  }

  /// 경로 조각 뒤에 이름이 이어지면 다른 폴더다 — `…/QuickTalkReport` 오탐 방지.
  private static func containsPathReference(_ text: String, _ needle: String) -> Bool {
    var start = text.startIndex
    while let range = text.range(of: needle, range: start..<text.endIndex) {
      let rest = text[range.upperBound...]
      guard let next = rest.first else { return true }
      if !next.isLetter && !next.isNumber && next != "." && next != "_" && next != "-" {
        return true
      }
      start = range.upperBound
    }
    return false
  }
}
