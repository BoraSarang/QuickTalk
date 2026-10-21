import XCTest
@testable import QuickTalkCore

/// 상대 시간 문구 — 사용자가 요청한 "10분 전 / 한 시간 전 / 일주일 전" 표기.
final class RelativeTimeTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func ago(_ seconds: TimeInterval) -> Date {
    now.addingTimeInterval(-seconds)
  }

  func testUnderOneMinuteIsJustNow() {
    XCTAssertEqual(RelativeTime.text(for: ago(0), now: now), L("방금"))
    XCTAssertEqual(RelativeTime.text(for: ago(59), now: now), L("방금"))
    // 시계 오차로 미래 시각이 와도 "방금"
    XCTAssertEqual(RelativeTime.text(for: now.addingTimeInterval(120), now: now), L("방금"))
  }

  func testMinutesHoursDaysWeeks() {
    XCTAssertEqual(RelativeTime.text(for: ago(60), now: now), Lf("%d분 전", 1))
    XCTAssertEqual(RelativeTime.text(for: ago(10 * 60), now: now), Lf("%d분 전", 10))
    XCTAssertEqual(RelativeTime.text(for: ago(3 * 60 * 60), now: now), Lf("%d시간 전", 3))
    XCTAssertEqual(RelativeTime.text(for: ago(2 * 24 * 60 * 60), now: now), Lf("%d일 전", 2))
    XCTAssertEqual(RelativeTime.text(for: ago(7 * 24 * 60 * 60), now: now), Lf("%d주 전", 1))
    XCTAssertEqual(RelativeTime.text(for: ago(14 * 24 * 60 * 60), now: now), Lf("%d주 전", 2))
  }

  func testOlderThanFiveWeeksShowsDate() {
    let text = RelativeTime.text(for: ago(60 * 24 * 60 * 60), now: now)
    // 언어에 따라 표기는 달라지지만, 상대 시간 접미사가 아니라 날짜 문자열이어야 한다.
    XCTAssertFalse(text.hasSuffix("전"))
    XCTAssertFalse(text.isEmpty)
  }

  func testTurnCreatedAtIsOptionalForOldRecords() throws {
    let old = """
    {"id":"11111111-1111-1111-1111-111111111111","role":"user","text":"안녕",
     "attachments":[],"status":"done"}
    """
    let turn = try JSONDecoder().decode(Turn.self, from: Data(old.utf8))
    XCTAssertNil(turn.createdAt, "구버전 기록에는 createdAt이 없으므로 nil로 읽혀야 한다")
  }

  func testTurnCreatedAtRoundTrips() throws {
    let stamp = Date(timeIntervalSince1970: 1_700_000_000)
    let turn = Turn(role: .assistant, text: "응답", elapsedMs: 1200, createdAt: stamp)
    let data = try JSONEncoder().encode(turn)
    let back = try JSONDecoder().decode(Turn.self, from: data)
    XCTAssertEqual(back.createdAt, stamp)
  }

  func testSubmittedTurnStampsTime() throws {
    let store = ConversationStore()
    let turn = try store.submit(text: "질문")
    XCTAssertNotNil(turn.createdAt)
    let id = store.beginAssistantTurn()
    XCTAssertNotNil(store.conversation.turns.first(where: { $0.id == id })?.createdAt)
  }
}
