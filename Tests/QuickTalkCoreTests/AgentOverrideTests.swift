import XCTest
@testable import QuickTalkCore

// [FEATURE] 대화별 권한 오버라이드 · 전역 자동 수락 (v0.22 · v0.20)
//
// 핵심 계약
//   · 오버라이드는 **설정한 항목만** 덮어쓴다(nil = 설정 따름).
//   · 대화가 앱 전체 안전장치(치명적 차단·상승 권한)를 끄지 못한다.
//   · 전역 자동 수락은 일반 명령만 통과시키고, 중요·치명적·상승 권한은 그대로 확인/차단한다.
//   · 구버전 기록(키 없음)은 기본값으로 읽힌다.

final class AgentOverrideTests: XCTestCase {
  // MARK: - 병합

  func testEmptyOverrideKeepsBasePolicy() {
    let base = AgentPolicy()
    let merged = AgentOverride().merged(into: base)
    XCTAssertEqual(merged, base)
    XCTAssertTrue(AgentOverride().isEmpty)
    XCTAssertNil(AgentOverride().summary)
  }

  func testOverrideReplacesOnlySetKeys() {
    var base = AgentPolicy()
    base.readPolicy = .alwaysAllow
    base.writePolicy = .alwaysAsk
    base.executePolicy = .alwaysAsk
    let override = AgentOverride(writePolicy: .alwaysAllow)
    let merged = override.merged(into: base)
    XCTAssertEqual(merged.writePolicy, .alwaysAllow)
    // 설정하지 않은 값은 그대로
    XCTAssertEqual(merged.readPolicy, .alwaysAllow)
    XCTAssertEqual(merged.executePolicy, .alwaysAsk)
    XCTAssertFalse(override.isEmpty)
    XCTAssertEqual(override.summary, Lf("쓰기 %@", AgentAutoApprove.alwaysAllow.displayName))
  }

  func testConversationCannotDisableCriticalOrElevationLimits() {
    var base = AgentPolicy()
    base.allowCritical = false
    base.allowElevated = false
    let override = AgentOverride(readPolicy: .alwaysAllow, autoAcceptAll: true)
    let merged = override.merged(into: base)
    // 오버라이드에 그 키가 없으므로 전역 값이 유지된다
    XCTAssertFalse(merged.allowCritical)
    XCTAssertFalse(merged.allowElevated)
    // 병합 결과로도 치명적 명령은 여전히 차단
    let decision = PolicyEngine.decide(command: "rm -rf /", capability: .unprobed,
                                       risk: .critical, policy: merged)
    guard case .deny = decision else {
      return XCTFail("치명적 명령은 대화 오버라이드로도 차단되어야 한다: \(decision)")
    }
  }

  func testMergedOverrideAffectsDecisions() {
    var base = AgentPolicy()
    base.writePolicy = .alwaysAsk
    let merged = AgentOverride(writePolicy: .alwaysAllow).merged(into: base)
    XCTAssertEqual(PolicyEngine.decide(command: "echo x > /tmp/a.txt",
                                       capability: .write(path: "/tmp/a.txt"),
                                       risk: .normal, policy: merged), .allow)
  }

  // MARK: - 저장 호환

  func testConversationDecodesWithoutAgentOverride() throws {
    let original = Conversation(title: "테스트")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object.removeValue(forKey: "agentOverride")
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertNil(decoded.agentOverride)
  }

  func testConversationRoundTripsAgentOverride() throws {
    let override = AgentOverride(readPolicy: .alwaysAsk, autoAcceptAll: true)
    let original = Conversation(title: "테스트", agentOverride: override)
    let decoded = try JSONDecoder().decode(Conversation.self,
                                           from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded.agentOverride, override)
  }

  // MARK: - 전역 자동 수락

  func testAutoAcceptAllAllowsNormalCommand() {
    var policy = AgentPolicy()
    policy.autoAcceptAll = true
    XCTAssertEqual(PolicyEngine.decide(command: "df -h", capability: .read,
                                       risk: .normal, policy: policy), .allow)
    XCTAssertEqual(PolicyEngine.decide(command: "echo x > /tmp/a.txt",
                                       capability: .write(path: "/tmp/a.txt"),
                                       risk: .normal, policy: policy), .allow)
  }

  func testAutoAcceptAllStillAsksForImportant() {
    var policy = AgentPolicy()
    policy.autoAcceptAll = true
    guard case .ask = PolicyEngine.decide(command: "defaults write com.apple.dock x y",
                                          capability: .unprobed, risk: .important,
                                          policy: policy) else {
      return XCTFail("중요 위험은 자동 수락이어도 확인해야 한다")
    }
  }

  func testAutoAcceptAllStillDeniesCriticalAndElevated() {
    var policy = AgentPolicy()
    policy.autoAcceptAll = true
    guard case .deny = PolicyEngine.decide(command: "rm -rf /", capability: .unprobed,
                                           risk: .critical, policy: policy) else {
      return XCTFail("치명적 명령은 자동 수락으로 열리지 않는다")
    }
    guard case .deny = PolicyEngine.decide(command: "sudo -n true", capability: .elevated,
                                           risk: .normal, policy: policy) else {
      return XCTFail("상승 권한은 자동 수락으로 열리지 않는다")
    }
  }

  func testPolicyDecodesWithoutAutoAcceptKey() throws {
    let data = try JSONEncoder().encode(AgentPolicy())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "autoAcceptAll")
    let decoded = try JSONDecoder().decode(
      AgentPolicy.self, from: try JSONSerialization.data(withJSONObject: object))
    XCTAssertFalse(decoded.autoAcceptAll)
  }

  // MARK: - 설정 (v0.20)

  func testSettingsDefaultsForStreamingAndTimeout() throws {
    let data = try JSONEncoder().encode(QuickTalkSettings())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "agentStreamOutput")
    object.removeValue(forKey: "agentTimeoutSeconds")
    let decoded = try JSONDecoder().decode(
      QuickTalkSettings.self, from: try JSONSerialization.data(withJSONObject: object))
    XCTAssertTrue(decoded.agentStreamOutput)
    XCTAssertEqual(decoded.agentTimeoutSeconds, 60)
  }

  func testSettingsRoundTripsStreamingAndTimeout() throws {
    var settings = QuickTalkSettings()
    settings.agentStreamOutput = false
    settings.agentTimeoutSeconds = 120
    let decoded = try JSONDecoder().decode(
      QuickTalkSettings.self, from: JSONEncoder().encode(settings))
    XCTAssertFalse(decoded.agentStreamOutput)
    XCTAssertEqual(decoded.agentTimeoutSeconds, 120)
  }
}
