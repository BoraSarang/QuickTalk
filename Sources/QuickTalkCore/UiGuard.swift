import Foundation

// [FEATURE] 화면 조작 안전 판정 — 순수 함수 (PLAN_v0.25 Phase 2)
//
// 화면 제어는 **셸·파일과 승인 모델을 분리한다**(2026-10-31 단순화).
//   ① 마스터 토글(도구 등록 자체를 막는다 — 호출부)
//   ② 대상 앱 승인(대화별 7일, `UiAppGrant`) — 승인 뒤에는 동작마다 다시 묻지 않는다.
// 전역 읽기/쓰기/실행 정책은 **셸·파일 도구 전용**이다. 화면 읽기(`ui_snapshot`)는
// 마스터 토글만 보고, 화면 조작(`ui_action`)은 앱 승인만 본다.
// 여기에 금지 앱·금지 키·보안 필드·실행 한도를 더한다.
//
// 이 파일은 AX·CGEvent 를 모른다 — 그래서 권한 없이 단위 테스트로 계약을 고정한다.

/// 조작할 수 없는 앱 1건 — 번들 ID 접두어로도 막는다(비밀번호 관리자 변형 대비).
public struct UiDeniedApp: Equatable, Sendable {
  public let bundleID: String
  /// 접두어 일치인가(`com.1password.*` 같은 계열).
  public let prefix: Bool
  /// 사용자에게 보여 줄 이유.
  public let reason: String

  public init(bundleID: String, prefix: Bool = false, reason: String) {
    self.bundleID = bundleID
    self.prefix = prefix
    self.reason = reason
  }
}

/// 판정 결과.
public enum UiGuardDecision: Equatable {
  case allow
  /// 사용자 확인 필요 — 사유를 카드에 그대로 보여 준다.
  case ask(String)
  /// 실행하지 않음 — 사유를 모델에게 돌려준다.
  case deny(String)
}

public enum UiGuard {
  /// 한 번의 요청에서 허용하는 화면 조작 수 — 폭주·무한 루프 차단.
  public static let maxActionsPerTurn = 30
  /// 동작 사이 최소 간격(초) — UI 가 따라오지 못해 엉뚱한 곳을 누르는 것 방지.
  public static let minimumInterval: TimeInterval = 0.15
  /// 한 번에 입력할 수 있는 글자 수.
  public static let maxTextLength = 2_000

  /// 텍스트를 입력할 수 있는 역할 — 버튼·링크에 "입력"하면 엉뚱한 동작이 된다.
  public static let textRoles: Set<String> = [
    "textfield", "textarea", "searchfield", "combobox",
  ]

  /// 금지 앱 — 코드에 고정한다. 설정에서 끌 수 없게 한다(끄면 게이트가 무너진다).
  public static let deniedApps: [UiDeniedApp] = [
    .init(bundleID: "com.apple.SecurityAgent", reason: L("관리자 암호·인증 대화상자")),
    .init(bundleID: "com.apple.loginwindow", reason: L("로그인·잠금 화면")),
    .init(bundleID: "com.apple.keychainaccess", reason: L("키체인 접근")),
    .init(bundleID: "com.apple.Passwords", reason: L("암호 앱")),
    .init(bundleID: "com.1password", prefix: true, reason: L("비밀번호 관리자")),
    .init(bundleID: "com.agilebits.onepassword", prefix: true, reason: L("비밀번호 관리자")),
    .init(bundleID: "com.bitwarden", prefix: true, reason: L("비밀번호 관리자")),
    .init(bundleID: "com.lastpass", prefix: true, reason: L("비밀번호 관리자")),
    .init(bundleID: "com.apple.Terminal", reason: L("터미널 — 셸 우회 차단")),
    .init(bundleID: "com.googlecode.iterm2", reason: L("터미널 — 셸 우회 차단")),
    .init(bundleID: "dev.warp", prefix: true, reason: L("터미널 — 셸 우회 차단")),
    .init(bundleID: "com.apple.systempreferences", reason: L("시스템 설정 — 권한·보안 변경 차단")),
    .init(bundleID: "com.apple.SystemSettings", reason: L("시스템 설정 — 권한·보안 변경 차단")),
    .init(bundleID: "com.borasarang.QuickTalk", reason: L("QuickTalk 자신 — 자기 참조 차단")),
  ]

  /// 수정자 키 이름(정규화 후).
  public static let allowedModifiers: Set<String> = ["cmd", "opt", "ctrl", "shift"]

  /// 허용하는 키 이름 — 그 외 키는 거부한다(모르면 막는다).
  public static let allowedKeyTokens: Set<String> = [
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m",
    "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "return", "enter", "escape", "esc", "tab", "space",
    "delete", "backspace", "forwarddelete", "home", "end", "pageup", "pagedown",
    "left", "right", "up", "down",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
    "-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`",
  ]

  /// 절대 허용하지 않는 조합 — 로그아웃·강제 종료·잠금·잠자기.
  /// 정규화된 토큰 집합으로 비교한다(순서·동의어 무관).
  public static let forbiddenCombos: [Set<String>] = [
    ["cmd", "q"],
    ["cmd", "opt", "esc"],
    ["ctrl", "cmd", "q"],
    ["cmd", "shift", "q"],
    ["ctrl", "opt", "cmd", "power"],
  ]

  // MARK: - 금지 앱

  /// 금지 앱이면 이유를, 아니면 nil.
  public static func deniedReason(bundleID: String, appName: String = "") -> String? {
    let id = bundleID.lowercased()
    let name = appName.lowercased()
    for app in deniedApps {
      let target = app.bundleID.lowercased()
      let matched = app.prefix ? id.hasPrefix(target) : id == target
      if matched { return app.reason }
    }
    // 번들 ID 가 비어 있는 옛 앱은 이름으로도 막는다(터미널·암호 앱).
    if id.isEmpty {
      if name.contains("terminal") || name.contains("iterm") || name.contains("warp") {
        return L("터미널 — 셸 우회 차단")
      }
      if name.contains("keychain") || name.contains("password") || name.contains("1password")
          || name.contains("bitwarden") || name.contains("lastpass") {
        return L("비밀번호 관리자")
      }
    }
    return nil
  }

  // MARK: - 키

  /// `cmd + shift + s` → ["cmd", "shift", "s"]. 형식이 이상하면 nil.
  public static func keyTokens(_ keys: String) -> [String]? {
    let raw = keys
      .lowercased()
      .replacingOccurrences(of: " ", with: "")
      .split(separator: "+")
      .map(String.init)
      .map(canonicalToken)
    guard !raw.isEmpty, raw.allSatisfy({ !$0.isEmpty }) else { return nil }
    return raw
  }

  private static func canonicalToken(_ token: String) -> String {
    switch token {
    case "command", "⌘": return "cmd"
    case "option", "alt", "⌥": return "opt"
    case "control", "⌃": return "ctrl"
    case "⇧": return "shift"
    case "escape": return "esc"
    case "enter": return "return"
    default: return token
    }
  }

  /// 키 조합이 정책을 통과하는가. 실패 사유를 돌려준다.
  public static func keyViolation(_ keys: String) -> String? {
    guard let tokens = keyTokens(keys) else {
      return Lf("키 조합 형식이 올바르지 않습니다: %@", keys)
    }
    let modifiers = Set(tokens.filter { allowedModifiers.contains($0) })
    let keysOnly = tokens.filter { !allowedModifiers.contains($0) }
    guard keysOnly.count == 1 else {
      return Lf("키 하나와 수정자만 쓸 수 있습니다: %@", keys)
    }
    let key = keysOnly[0]
    guard allowedKeyTokens.contains(key) else {
      return Lf("허용되지 않는 키입니다: %@", key)
    }
    let combo = modifiers.union([key])
    if forbiddenCombos.contains(combo) {
      return Lf("이 키 조합은 시스템을 바꿀 수 있어 허용하지 않습니다: %@", keys)
    }
    return nil
  }

  // MARK: - 판정

  /// 세 겹의 문 + 금지 목록 + 한도를 순서대로 본다.
  ///
  /// - Parameters:
  ///   - spec: 검증된 조작 명세
  ///   - target: 참조를 푼 요소(없으면 앱/창 수준 조작)
  ///   - appBundleID: 대상 앱 번들 ID
  ///   - actionsThisTurn: 이번 턴에 이미 실행한 조작 수
  ///   - hasAppGrant: 이 대화에서 대상 앱을 승인했는가(7일 유효)
  ///
  /// 전역 실행 정책(`AgentAutoApprove`)은 받지 않는다 — 화면 제어는 앱 승인으로만 판정한다.
  public static func evaluate(spec: UiActionSpec,
                              target: UiActionTarget?,
                              appBundleID: String,
                              appName: String,
                              actionsThisTurn: Int,
                              hasAppGrant: Bool) -> UiGuardDecision {
    // ① 한도 — 31번째 동작은 나가지 않는다.
    if actionsThisTurn >= maxActionsPerTurn {
      return .deny(Lf("한 번의 요청에서 화면 조작은 %d번까지 할 수 있습니다.", maxActionsPerTurn))
    }
    // ② 금지 앱
    if let reason = deniedReason(bundleID: appBundleID, appName: appName) {
      return .deny(Lf("%@ 앱은 조작할 수 없습니다 — %@.", appName.isEmpty ? appBundleID : appName, reason))
    }
    // ③ 금지 키
    if let keys = spec.keys, let violation = keyViolation(keys) {
      return .deny(violation)
    }
    // ④ 보안 텍스트 필드 — 읽기도 쓰기도 거부한다.
    if spec.kind == .type, target?.isSecure == true {
      return .deny(L("비밀번호 필드에는 입력할 수 없습니다."))
    }
    // ④-b 텍스트가 아닌 요소에 입력하지 않는다(버튼 이름을 덮어쓰는 사고 방지).
    if spec.kind == .type, let target, !textRoles.contains(target.role) {
      return .deny(Lf("%@ 요소에는 텍스트를 입력할 수 없습니다 — 입력란을 고르세요.", target.label))
    }
    // ⑤ 앱 승인 — 없으면 카드에서 [이 앱 허용]을 받는다. 승인 뒤에는 묻지 않는다.
    if !hasAppGrant {
      return .ask(Lf("%@ 앱을 처음 조작합니다 — 이 대화에서 허용할지 확인해 주세요.", appName))
    }
    return .allow
  }

  /// 설정 화면에 보여 줄 금지 앱 목록(이유 포함).
  public static var deniedAppSummary: String {
    deniedApps.map(\.reason).reduce(into: [String]()) { result, reason in
      if !result.contains(reason) { result.append(reason) }
    }.joined(separator: " · ")
  }
}
