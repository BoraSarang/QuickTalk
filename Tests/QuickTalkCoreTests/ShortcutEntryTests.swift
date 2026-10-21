import XCTest
@testable import QuickTalkCore

/// T-21 포인터 pill — ⌘Space 표시 판단.
/// pill은 별개 창이 아니라 "새 대화"일 때의 빈 대화 창 대체 표현이다.
final class ShortcutEntryTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func minutesAgo(_ m: Double) -> Date { now.addingTimeInterval(-m * 60) }

  private func decide(_ s: QuickTalkSettings, last: Date?, turns: Bool = true) -> ShortcutEntryPresentation {
    ShortcutEntryPresentation.decide(settings: s, lastActivity: last, hasTurns: turns, now: now)
  }

  func testWithinWindowKeepsChatWindow() {
    XCTAssertEqual(decide(QuickTalkSettings(), last: minutesAgo(3)), .conversation)
  }

  func testAfterWindowShowsPill() {
    XCTAssertEqual(decide(QuickTalkSettings(), last: minutesAgo(10)), .pill)
    XCTAssertEqual(decide(QuickTalkSettings(), last: minutesAgo(120)), .pill)
  }

  func testZeroMeansAlwaysPill() {
    var s = QuickTalkSettings()
    s.shortcutSessionMinutes = 0
    // 1분도 지나지 않았어도 "사용 안 함" = 언제나 새 대화 → pill
    XCTAssertEqual(decide(s, last: minutesAgo(0.1)), .pill)
  }

  func testNoTurnsAlwaysShowsPill() {
    // 첫 실행·빈 대화 — 이어갈 것이 없으므로 빈 대화 창 대신 pill
    XCTAssertEqual(decide(QuickTalkSettings(), last: minutesAgo(0), turns: false), .pill)
    XCTAssertEqual(decide(QuickTalkSettings(), last: nil, turns: false), .pill)
  }

  func testNoActivityMeansPill() {
    XCTAssertEqual(decide(QuickTalkSettings(), last: nil), .pill)
  }

  func testBoundaryIsExclusive() {
    var s = QuickTalkSettings()
    s.shortcutSessionMinutes = 5
    XCTAssertEqual(decide(s, last: minutesAgo(4.9)), .conversation)
    XCTAssertEqual(decide(s, last: minutesAgo(5)), .pill)
  }
}
