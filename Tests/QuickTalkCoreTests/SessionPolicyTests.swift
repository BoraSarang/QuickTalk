import XCTest
@testable import QuickTalkCore

/// ⌘Space 세션 규칙(2026-10-20) — 마지막 대화가 유지 시간 안이면 이어서, 지났으면 새 대화.
/// `0` = 사용 안 함(언제나 새 대화). 기본 10분.
final class SessionPolicyTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func minutesAgo(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }

  func testDefaultIsTenMinutes() {
    XCTAssertEqual(QuickTalkSettings().shortcutSessionMinutes, 10)
    XCTAssertEqual(QuickTalkSettings.sessionMinuteOptions, [5, 10, 30, 0])
  }

  func testWithinWindowContinues() {
    let s = QuickTalkSettings()
    XCTAssertTrue(s.continuesSession(lastActivity: minutesAgo(9.9), now: now))
    XCTAssertTrue(s.continuesSession(lastActivity: minutesAgo(0), now: now))
  }

  func testAfterWindowStartsNew() {
    let s = QuickTalkSettings()
    XCTAssertFalse(s.continuesSession(lastActivity: minutesAgo(10), now: now))
    XCTAssertFalse(s.continuesSession(lastActivity: minutesAgo(120), now: now))
  }

  func testZeroMeansAlwaysNew() {
    var s = QuickTalkSettings()
    s.shortcutSessionMinutes = 0
    XCTAssertFalse(s.continuesSession(lastActivity: minutesAgo(0.1), now: now))
    XCTAssertEqual(s.sessionMinutesLabel, "사용 안 함")
  }

  func testFiveAndThirtyMinuteWindows() {
    var s = QuickTalkSettings()
    s.shortcutSessionMinutes = 5
    XCTAssertTrue(s.continuesSession(lastActivity: minutesAgo(4), now: now))
    XCTAssertFalse(s.continuesSession(lastActivity: minutesAgo(6), now: now))

    s.shortcutSessionMinutes = 30
    XCTAssertTrue(s.continuesSession(lastActivity: minutesAgo(25), now: now))
    XCTAssertFalse(s.continuesSession(lastActivity: minutesAgo(31), now: now))
  }

  func testNoActivityMeansNewConversation() {
    XCTAssertFalse(QuickTalkSettings().continuesSession(lastActivity: nil, now: now))
  }

  // MARK: - 저장/불러오기

  func testSettingsRoundTripKeepsSessionMinutes() throws {
    var s = QuickTalkSettings()
    s.shortcutSessionMinutes = 30
    let data = try JSONEncoder().encode(s)
    let loaded = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(loaded.shortcutSessionMinutes, 30)
    XCTAssertEqual(loaded.alwaysOnTop, s.alwaysOnTop)
  }

  func testLegacySettingsWithoutSessionKeyDefaultsToTen() throws {
    let json = Data("{}".utf8)
    let loaded = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertEqual(loaded.shortcutSessionMinutes, 10, "구버전 설정에는 키가 없으니 기본 10분")
  }

  // MARK: - 응답 시간(elapsedMs)

  func testAssistantTurnRecordsElapsed() {
    let store = ConversationStore()
    let turn = store.appendAssistant(text: "답", elapsedMs: 3210)
    XCTAssertEqual(turn.elapsedMs, 3210)
    XCTAssertEqual(store.conversation.turns.last?.elapsedMs, 3210)
  }

  func testTurnRoundTripKeepsElapsed() throws {
    let turn = Turn(role: .assistant, text: "답", elapsedMs: 940)
    let loaded = try JSONDecoder().decode(Turn.self, from: JSONEncoder().encode(turn))
    XCTAssertEqual(loaded.elapsedMs, 940)
  }

  func testLegacyTurnWithoutElapsedDecodes() throws {
    let id = UUID().uuidString
    let json = Data("""
    {"id":"\(id)","role":"assistant","text":"옛 답","attachments":[],"status":"done"}
    """.utf8)
    let loaded = try JSONDecoder().decode(Turn.self, from: json)
    XCTAssertNil(loaded.elapsedMs, "구버전 기록에는 응답 시간이 없다 — nil로 읽고 표시만 생략")
    XCTAssertEqual(loaded.text, "옛 답")
  }
}
