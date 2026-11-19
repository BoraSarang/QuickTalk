import XCTest
@testable import QuickTalkCore

/// v0.41 오타 노트 저장소 — 발생률·교정률 정의, 90일 정리, 무시 목록.
final class ProofreadHistoryTests: XCTestCase {
  private var tempDir: URL!
  private var current = Date(timeIntervalSince1970: 1_700_000_000)   // 2023-11-14 (UTC)

  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
  }

  override func setUpWithError() throws {
    tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("proofread-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: tempDir)
  }

  private func makeHistory(fileURL: URL? = nil, data: ProofreadData? = nil) -> ProofreadHistory {
    if let data {
      return ProofreadHistory(data: data, now: { self.current }, calendar: calendar)
    }
    return ProofreadHistory(fileURL: fileURL, now: { self.current }, calendar: calendar)
  }

  private func issue(_ wrong: String = "몇일", _ right: String = "며칠",
                     category: ProofreadCategory = .spelling,
                     ruleID: String = "spelling.myeochil") -> ProofreadIssue {
    ProofreadIssue(ruleID: ruleID, category: category,
                   location: 0, length: wrong.utf16.count,
                   original: wrong, replacement: right)
  }

  // MARK: - 카운터

  func testSummaryRates() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    history.recordCheck(hinted: false, issues: [], source: "composer")
    let token = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    history.recordAccepted(token)

    let summary = history.summary(days: 30)
    XCTAssertEqual(summary.checks, 2)
    XCTAssertEqual(summary.hints, 1)
    XCTAssertEqual(summary.accepted, 1)
    XCTAssertEqual(summary.occurrenceRate ?? -1, 0.5, accuracy: 0.001)
    XCTAssertEqual(summary.acceptanceRate ?? -1, 1.0, accuracy: 0.001)
    XCTAssertTrue(summary.isLowSample)
  }

  func testAsIsAndDismissedAreSeparate() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    let a = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    let b = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    let c = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    history.recordAsIs(a)
    history.recordDismissed(b)
    history.recordAccepted(c)

    let summary = history.summary(days: 30)
    XCTAssertEqual(summary.hints, 3)
    XCTAssertEqual(summary.asIs, 1)
    XCTAssertEqual(summary.dismissed, 1)
    XCTAssertEqual(summary.accepted, 1)
  }

  func testAcceptedMarksEntries() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    let token = history.recordCheck(hinted: true,
                                    issues: [issue("이번주", "이번 주", category: .spacing,
                                                   ruleID: "spacing.this-week"),
                                             issue()],
                                    source: "composer")
    history.recordAccepted(token)
    XCTAssertEqual(history.expressions(days: 30).count, 2)
    XCTAssertEqual(history.expressions(days: 30).first?.accepted, 1)
  }

  func testExpressionsGroupedAndSorted() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    for _ in 0..<3 {
      let t = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
      history.recordAccepted(t)
    }
    let t = history.recordCheck(hinted: true,
                                issues: [issue("할께", "할게")], source: "composer")
    history.recordAsIs(t)

    let list = history.expressions(days: 30)
    XCTAssertEqual(list.count, 2)
    XCTAssertEqual(list[0].original, "몇일")
    XCTAssertEqual(list[0].count, 3)
    XCTAssertEqual(list[0].accepted, 3)
    XCTAssertEqual(list[1].original, "할께")
    XCTAssertEqual(list[1].accepted, 0)
  }

  func testCategoryCounts() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    _ = history.recordCheck(hinted: true,
                            issues: [issue("이번주", "이번 주", category: .spacing),
                                     issue("할께", "할게", category: .spelling),
                                     issue("안녕 ,", "안녕,", category: .punctuation)],
                            source: "composer")
    let counts = Dictionary(uniqueKeysWithValues: history.categoryCounts(days: 30).map { ($0.category, $0.count) })
    XCTAssertEqual(counts[.spacing], 1)
    XCTAssertEqual(counts[.spelling], 1)
    XCTAssertEqual(counts[.punctuation], 1)
  }

  // MARK: - 보존·정리

  func testPersistenceRoundTrip() throws {
    let url = tempDir.appendingPathComponent("proofread.json")
    let history = makeHistory(fileURL: url)
    let token = history.recordCheck(hinted: true, issues: [issue()], source: "pill")
    history.recordAccepted(token)
    history.ignore("회사명")

    let reloaded = makeHistory(fileURL: url)
    XCTAssertEqual(reloaded.summary(days: 30).checks, 1)
    XCTAssertEqual(reloaded.summary(days: 30).accepted, 1)
    XCTAssertTrue(reloaded.isIgnored("회사명"))
    XCTAssertEqual(reloaded.expressions(days: 30).first?.accepted, 1)
  }

  func testPruneRemovesOldEntries() {
    let old = current.addingTimeInterval(-120 * 86_400)
    let data = ProofreadData(
      entries: [ProofreadEntry(at: old, category: .spelling, original: "옛말",
                               replacement: "옛 말", ruleID: "old", source: "composer"),
                ProofreadEntry(at: current, category: .spelling, original: "몇일",
                               replacement: "며칠", ruleID: "spelling.myeochil",
                               source: "composer")],
      daily: [ProofreadDay(day: "2020-01-01", checks: 9, hints: 9)])
    let history = makeHistory(data: data)
    XCTAssertEqual(history.summary(days: 400).checks, 0)   // 400일 이전 카운터도 정리
    XCTAssertEqual(history.expressions(days: 400).count, 1)
    XCTAssertEqual(history.expressions(days: 400).first?.original, "몇일")
  }

  func testMaximumEntries() {
    let entries = (0..<2_100).map { i in
      ProofreadEntry(at: current.addingTimeInterval(Double(-i)),
                     category: .spelling, original: "낱\(i)",
                     replacement: "낫\(i)", ruleID: "r", source: "composer")
    }
    let history = makeHistory(data: ProofreadData(entries: entries))
    XCTAssertEqual(history.expressions(days: 30, limit: 5_000).count <= ProofreadHistory.maximumEntries, true)
    // 가장 최근 것이 남는다.
    XCTAssertEqual(history.expressions(days: 30, limit: 5_000).first?.original, "낱0")
  }

  func testClearAll() {
    let url = tempDir.appendingPathComponent("proofread.json")
    let history = makeHistory(fileURL: url)
    _ = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    history.ignore("몇일")
    history.clearAll()
    XCTAssertEqual(history.summary(days: 30).checks, 0)
    XCTAssertTrue(history.ignored.isEmpty)
    let reloaded = makeHistory(fileURL: url)
    XCTAssertEqual(reloaded.summary(days: 30).checks, 0)
  }

  func testIgnoreAndUnignore() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    history.ignore("몇일")
    history.ignore("몇일")
    XCTAssertEqual(history.ignored, ["몇일"])
    history.unignore("몇일")
    XCTAssertTrue(history.ignored.isEmpty)
  }

  func testUnignoreAll() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    history.ignore("몇일")
    history.ignore("이번주")
    XCTAssertEqual(history.ignored.count, 2)
    history.unignoreAll()
    XCTAssertTrue(history.ignored.isEmpty)
  }

  /// v0.41 이전 파일(또는 손상된 파일)에서 새 키가 없어도 기본값으로 읽는다.
  func testDecodingWithoutOptionalSections() throws {
    let raw = #"{"version":1,"entries":[]}"#.data(using: .utf8)!
    let decoded = try JSONDecoder().decode(ProofreadData.self, from: raw)
    XCTAssertTrue(decoded.daily.isEmpty)
    XCTAssertTrue(decoded.ignored.isEmpty)
  }

  // MARK: - 주별 차트

  func testWeeklyBuckets() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    // 오늘 · 3일 전 · 10일 전
    let base = Date(timeIntervalSince1970: 1_700_000_000)
    current = base
    for daysAgo in [0, 3, 10] {
      current = calendar.date(byAdding: .day, value: -daysAgo, to: base)!
      _ = history.recordCheck(hinted: true, issues: [issue()], source: "composer")
    }
    current = base
    let weeks = history.weekly(weeks: 3)
    XCTAssertEqual(weeks.count, 3)
    XCTAssertEqual(weeks[2].checks, 2)   // 오늘 + 3일 전
    XCTAssertEqual(weeks[1].checks, 1)   // 10일 전
    XCTAssertEqual(weeks[0].checks, 0)
  }

  func testZeroDenominatorsAreNil() {
    let history = makeHistory(fileURL: tempDir.appendingPathComponent("proofread.json"))
    let summary = history.summary(days: 30)
    XCTAssertNil(summary.occurrenceRate)
    XCTAssertNil(summary.acceptanceRate)
  }
}
