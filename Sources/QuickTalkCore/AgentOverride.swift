import Foundation

// [FEATURE] 대화별 권한 오버라이드 (PLAN_v0.18 v0.22)
//
// 전역 설정(설정 › 도구)은 **모든 대화**에 적용된다.
// 그런데 "이 대화에서는 쓰기를 매번 확인하고 싶다" 또는 "이 대화만 실행을 자동 허용" 같은
// 요구가 생긴다. 그래서 대화마다 **설정을 덮어쓰는 값**을 따로 둔다.
//
// 원칙
//   · nil = "설정 따름" — 값이 없으면 전역 설정이 그대로 쓰인다(구버전 기록 호환).
//   · 오버라이드는 **좁히는 쪽도, 넓히는 쪽도** 가능하지만 치명적 차단은 전역 설정만 따른다.
//     (대화 하나가 `allowCritical` 을 켜서 앱 전체 안전장치를 우회하면 안 된다)
//   · 승인된 폴더 범위는 오버라이드가 아니라 `Conversation.approvedWriteScopes` 에 따로 쌓인다.

public struct AgentOverride: Codable, Equatable {
  /// nil = 설정 따름
  public var readPolicy: AgentAutoApprove?
  public var writePolicy: AgentAutoApprove?
  public var executePolicy: AgentAutoApprove?
  /// 이 대화만 전역 자동 수락(치명적·상승 권한 차단은 그대로)
  public var autoAcceptAll: Bool?

  public init(readPolicy: AgentAutoApprove? = nil,
              writePolicy: AgentAutoApprove? = nil,
              executePolicy: AgentAutoApprove? = nil,
              autoAcceptAll: Bool? = nil) {
    self.readPolicy = readPolicy
    self.writePolicy = writePolicy
    self.executePolicy = executePolicy
    self.autoAcceptAll = autoAcceptAll
  }

  /// 아무것도 덮어쓰지 않는가 — UI 에서 "설정 따름"으로 표시한다.
  public var isEmpty: Bool {
    readPolicy == nil && writePolicy == nil && executePolicy == nil && autoAcceptAll == nil
  }

  /// 전역 정책 위에 이 대화의 값을 얹는다.
  /// **치명적·상승 권한 제한은 전역 값을 그대로 쓴다**(대화가 안전장치를 끄지 못한다).
  public func merged(into base: AgentPolicy) -> AgentPolicy {
    var p = base
    if let v = readPolicy { p.readPolicy = v }
    if let v = writePolicy { p.writePolicy = v }
    if let v = executePolicy { p.executePolicy = v }
    if let v = autoAcceptAll { p.autoAcceptAll = v }
    return p
  }

  /// 화면에 보여줄 한 줄 요약 — 없으면 nil.
  public var summary: String? {
    guard !isEmpty else { return nil }
    var parts: [String] = []
    if let v = readPolicy { parts.append(Lf("읽기 %@", v.displayName)) }
    if let v = writePolicy { parts.append(Lf("쓰기 %@", v.displayName)) }
    if let v = executePolicy { parts.append(Lf("실행 %@", v.displayName)) }
    if autoAcceptAll == true { parts.append(L("자동 수락")) }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }
}
