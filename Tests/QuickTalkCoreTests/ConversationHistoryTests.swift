import XCTest
@testable import QuickTalkCore

/// 대화 기록 규칙(2026-10-20) — "대화가 하나도 기록되지 않는다" 보고로 자동 저장·보관일수 정리를 도입했다.
final class ConversationHistoryTests: XCTestCase {

  private let now = Date(timeIntervalSince1970: 1_800_000_000)
  private func daysAgo(_ d: Double) -> Date { now.addingTimeInterval(-d * 86_400) }

  private func conversation(_ title: String, pinned: Bool = false, days: Double = 0,
                            id: UUID = UUID()) -> Conversation {
    Conversation(id: id, title: title, turns: [Turn(role: .user, text: title)],
                 pinned: pinned, updatedAt: daysAgo(days))
  }

  func testOrderedPutsPinnedFirstThenRecent() {
    let old = conversation("보관된 옛 대화", pinned: true, days: 40)
    let recent = conversation("최근 대화", days: 0.1)
    let older = conversation("조금 전 대화", days: 2)

    let ordered = ConversationHistory.ordered([older, recent, old])
    XCTAssertEqual(ordered.map(\.title), ["보관된 옛 대화", "최근 대화", "조금 전 대화"])
  }

  func testOrderedDeduplicatesByIdKeepingTheNewest() {
    let id = UUID()
    let stale = conversation("예전 제목", days: 3, id: id)
    let fresh = conversation("최신 제목", days: 0, id: id)

    let ordered = ConversationHistory.ordered([stale, fresh])
    XCTAssertEqual(ordered.count, 1)
    XCTAssertEqual(ordered.first?.title, "최신 제목")
  }

  func testPrunedKeepsPinnedRegardlessOfAge() {
    let pinned = conversation("보관", pinned: true, days: 400)
    let fresh = conversation("최근", days: 1)

    let kept = ConversationHistory.pruned([pinned, fresh], keepDays: 30, now: now)
    XCTAssertEqual(kept.map(\.title), ["보관", "최근"])
  }

  func testPrunedDropsExpiredUnpinned() {
    let expired = conversation("30일 지난 대화", days: 31)
    let fresh = conversation("29일 전 대화", days: 29)

    let kept = ConversationHistory.pruned([expired, fresh], keepDays: 30, now: now)
    XCTAssertEqual(kept.map(\.title), ["29일 전 대화"])
  }

  func testPrunedZeroMeansUnlimited() {
    let old = conversation("아주 옛 대화", days: 900)
    XCTAssertEqual(ConversationHistory.pruned([old], keepDays: 0, now: now).count, 1)
  }

  func testMostRecentIgnoresPin() {
    let pinnedOld = conversation("보관", pinned: true, days: 10)
    let recent = conversation("최근", days: 1)
    XCTAssertEqual(ConversationHistory.mostRecent([pinnedOld, recent])?.title, "최근")
    XCTAssertNil(ConversationHistory.mostRecent([]))
  }

  // MARK: - 파일 왕복 (임시 경로 — 실제 기록 파일은 건드리지 않는다)

  func testSaveAndLoadRoundTripIncludingPinnedOrder() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("quicktalk-history-\(UUID().uuidString)")
    let url = dir.appendingPathComponent("history.json")
    defer { try? FileManager.default.removeItem(at: dir) }

    let id = UUID()
    let pinned = Conversation(id: id, title: "보관 대화",
                              turns: [Turn(role: .user, text: "질문"), Turn(role: .assistant, text: "답변")],
                              pinned: true, updatedAt: daysAgo(5))
    let recent = conversation("최근 대화", days: 1)

    try PersistenceService.save([recent, pinned], to: url)
    let loaded = PersistenceService.load(keepDays: 30, from: url)

    XCTAssertEqual(loaded.map(\.title), ["보관 대화", "최근 대화"])
    XCTAssertEqual(loaded.first?.turns.count, 2)
    XCTAssertEqual(loaded.first?.turns.last?.text, "답변")
    XCTAssertTrue(loaded.first?.pinned == true)
  }

  func testLoadMissingFileReturnsEmpty() {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("quicktalk-none-\(UUID().uuidString).json")
    XCTAssertEqual(PersistenceService.load(keepDays: 30, from: url), [])
  }
}
