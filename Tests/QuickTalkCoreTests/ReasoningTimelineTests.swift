import XCTest
@testable import QuickTalkCore

/// v0.31 — 사고 과정(thinking 모델) 표시.
///
/// ① 스텝별 사고 구간(`AgentEvent.reasoningBefore`)을 저장·복원한다.
/// ② 표시 방식 설정(`ReasoningDisplayMode`)이 기본값·왕복·미지 값에서 안전하다.
final class ReasoningTimelineTests: XCTestCase {

  // MARK: - AgentEvent.reasoningBefore

  private func sampleEvent() -> AgentEvent {
    AgentEvent(id: "e1", toolName: "shell", title: "셸 — 목록 조회",
               command: "ls -1", level: .read, risk: .normal,
               state: .done, output: "3개", elapsedMs: 120)
  }

  func testEventWithoutReasoningRoundTrips() throws {
    // 사고 과정이 없는 도구 카드 — 인코딩/디코딩 모두 nil 로 유지된다.
    let event = sampleEvent()
    XCTAssertNil(event.reasoningBefore)
    let back = try JSONDecoder().decode(AgentEvent.self, from: try JSONEncoder().encode(event))
    XCTAssertEqual(back, event)
    XCTAssertNil(back.reasoningBefore)
  }

  func testEventWithReasoningRoundTrips() throws {
    var event = sampleEvent()
    event.reasoningBefore = "먼저 목록을 확인한다.\n그 다음 정리한다."
    let back = try JSONDecoder().decode(AgentEvent.self, from: try JSONEncoder().encode(event))
    XCTAssertEqual(back, event)
    XCTAssertEqual(back.reasoningBefore, event.reasoningBefore)
  }

  func testLegacyEventWithoutReasoningKeyDecodesNil() throws {
    // v0.30 이하 기록에는 키 자체가 없다 — 깨지지 않고 nil 이어야 한다.
    // (옵셔널은 인코딩에서 빠지므로 "구버전 기록과 같은 모양"이 그대로 만들어진다)
    let data = try JSONEncoder().encode(sampleEvent())
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    XCTAssertNil(object["reasoningBefore"], "값이 없으면 키도 저장되지 않는다")

    let event = try JSONDecoder().decode(AgentEvent.self, from: data)
    XCTAssertNil(event.reasoningBefore)
    XCTAssertEqual(event.id, "e1")
    XCTAssertEqual(event.state, .done)
  }

  // MARK: - ReasoningDisplayMode

  func testReasoningDisplayDefaultIsCollapseWhenDone() {
    XCTAssertEqual(QuickTalkSettings().reasoningDisplay, .collapseWhenDone)
  }

  func testReasoningDisplayRoundTrips() throws {
    for mode in ReasoningDisplayMode.allCases {
      var settings = QuickTalkSettings()
      settings.reasoningDisplay = mode
      let back = try JSONDecoder().decode(QuickTalkSettings.self,
                                          from: try JSONEncoder().encode(settings))
      XCTAssertEqual(back.reasoningDisplay, mode)
    }
  }

  func testUnknownReasoningDisplayFallsBackToDefault() throws {
    // 다른 버전에서 저장한 모르는 값이어도 기본값으로 폴백하고 앱은 뜬다.
    let json = #"{"reasoningDisplay":"showEverything"}"#.data(using: .utf8)!
    XCTAssertEqual(try JSONDecoder().decode(QuickTalkSettings.self, from: json).reasoningDisplay,
                   .collapseWhenDone)
  }

  func testLegacySettingsWithoutReasoningDisplayFallsBack() throws {
    let json = #"{"agentShowExecution":false}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertEqual(settings.reasoningDisplay, .collapseWhenDone)
    XCTAssertFalse(settings.agentShowExecution, "다른 설정은 그대로 유지된다")
  }
}
