import XCTest
@testable import QuickTalkCore

// [FEATURE] v0.26 예약 작업 — 파일 이름·요약 카드·이력 상한
//
// 파일 이름은 사용자가 쓴 제목에서 만들어진다. 경로 구분자·`..`·이모지가 남으면
// 리포트가 의도한 폴더 밖에 쓰일 수 있으므로 여기서 막는다.

final class ScheduledTaskTests: XCTestCase {
  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
  }()

  override func setUp() {
    super.setUp()
    L10n.language = .korean
  }

  override func tearDown() {
    L10n.language = .system
    super.tearDown()
  }

  private var day: Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 9, minute: 0))!
  }

  private func task(title: String = "아침 테크 리포트",
                    rule: ScheduleRule = .daily(hour: 9, minute: 0)) -> ScheduledTask {
    ScheduledTask(title: title, instruction: "새 소식 5건을 요약하라", rule: rule)
  }

  // MARK: - 파일 이름

  func testFileNameUsesDateAndSlug() {
    XCTAssertEqual(ReportNaming.fileName(title: "아침 테크 리포트", date: day, calendar: calendar),
                   "2026-11-04-아침-테크-리포트.md")
  }

  func testFileNameStripsPathSeparators() {
    let name = ReportNaming.fileName(title: "a/b\\c:d", date: day, calendar: calendar)
    XCTAssertFalse(name.contains("/"))
    XCTAssertFalse(name.contains("\\"))
    XCTAssertFalse(name.contains(":"))
    XCTAssertEqual(name, "2026-11-04-a-b-c-d.md")
  }

  func testFileNameCannotEscapeWithDotDot() {
    let name = ReportNaming.fileName(title: "../../etc/passwd", date: day, calendar: calendar)
    XCTAssertFalse(name.contains(".."), "상위 폴더 참조가 남으면 안 된다")
    XCTAssertFalse(name.hasPrefix("."))
    XCTAssertEqual(name, "2026-11-04-etc-passwd.md")
  }

  func testFileNameStripsEmoji() {
    let name = ReportNaming.fileName(title: "정리 🦾", date: day, calendar: calendar)
    XCTAssertFalse(name.contains("🦾"))
    XCTAssertEqual(name, "2026-11-04-정리.md")
  }

  func testFileNameFallsBackWhenTitleIsEmpty() {
    XCTAssertEqual(ReportNaming.fileName(title: "   ", date: day, calendar: calendar),
                   "2026-11-04-report.md")
    XCTAssertEqual(ReportNaming.fileName(title: "...", date: day, calendar: calendar),
                   "2026-11-04-report.md")
  }

  func testFileNameCapsSlugLength() {
    let long = String(repeating: "가", count: 200)
    let name = ReportNaming.fileName(title: long, date: day, calendar: calendar)
    let slug = name.replacingOccurrences(of: "2026-11-04-", with: "")
      .replacingOccurrences(of: ".md", with: "")
    XCTAssertLessThanOrEqual(slug.count, ReportNaming.maxSlugLength)
  }

  func testUniqueFileNameAddsSuffix() {
    let existing: Set<String> = ["2026-11-04-a.md", "2026-11-04-a-2.md"]
    XCTAssertEqual(ReportNaming.unique("2026-11-04-a.md", existing: existing), "2026-11-04-a-3.md")
    XCTAssertEqual(ReportNaming.unique("2026-11-04-b.md", existing: existing), "2026-11-04-b.md")
  }

  func testUniqueFileNameIsCaseInsensitive() {
    let existing: Set<String> = ["2026-11-04-Report.md"]
    XCTAssertEqual(ReportNaming.unique("2026-11-04-report.md", existing: existing),
                   "2026-11-04-report-2.md")
  }

  // MARK: - 요약 카드

  func testSuccessCardHasFileAndSummary() {
    let t = task()
    let run = RunRecord(startedAt: day, finishedAt: day.addingTimeInterval(12),
                        status: .succeeded,
                        filePath: "~/Documents/Reports/2026-11-04-아침-테크-리포트.md",
                        summary: "새 소식 3건\n가격 인하 1건")
    let text = ScheduleSummaryCard.text(task: t, run: run)
    XCTAssertTrue(text.contains("완료"))
    XCTAssertTrue(text.contains("2026-11-04-아침-테크-리포트.md"))
    XCTAssertTrue(text.contains("• 새 소식 3건"))
    XCTAssertTrue(text.contains("• 가격 인하 1건"))
  }

  func testSummaryCardShowsAtMostThreePoints() {
    let run = RunRecord(status: .succeeded, summary: "1\n2\n3\n4\n5")
    let text = ScheduleSummaryCard.text(task: task(), run: run)
    XCTAssertTrue(text.contains("• 3"))
    XCTAssertFalse(text.contains("• 4"))
  }

  func testFailureCardHasReason() {
    let run = RunRecord(status: .failed, failureReason: "승인 대기 만료")
    let text = ScheduleSummaryCard.text(task: task(), run: run)
    XCTAssertTrue(text.contains("실패"))
    XCTAssertTrue(text.contains("사유: 승인 대기 만료"))
  }

  func testAwaitingApprovalCardExplainsNextStep() {
    let text = ScheduleSummaryCard.text(task: task(), run: RunRecord(status: .awaitingApproval))
    XCTAssertTrue(text.contains("승인 대기"))
    XCTAssertTrue(text.contains("승인하면 이어서 실행"))
  }

  func testHeadlineCoversEveryStatus() {
    for status in RunStatus.allCases {
      XCTAssertFalse(ScheduleSummaryCard.headline(status).isEmpty)
    }
  }

  // MARK: - 이력

  func testHistoryIsCappedAt30() {
    var t = task()
    for i in 0..<35 {
      t.record(RunRecord(startedAt: Date(timeIntervalSince1970: TimeInterval(i)),
                         status: .succeeded, summary: "\(i)"))
    }
    XCTAssertEqual(t.history.count, ScheduledTask.historyLimit)
    XCTAssertEqual(t.history.first?.summary, "5")
    XCTAssertEqual(t.lastRun?.summary, "34")
  }

  // MARK: - 다음 시각

  func testAdvanceDailySkipsToNextDayAfterLateCatchUp() {
    var t = task(rule: .daily(hour: 9, minute: 0))
    t.nextFireAt = day
    t.advanceNextFire(after: day, now: day.addingTimeInterval(10 * 60), calendar: calendar)
    XCTAssertEqual(t.nextFireAt, calendar.date(byAdding: .day, value: 1, to: day))
  }

  func testAdvanceWeeklyUsesNextWeekday() {
    var t = task(rule: .weekly(weekday: 5, hour: 9, minute: 0)) // 목요일
    t.nextFireAt = day // 수요일
    t.advanceNextFire(after: day, now: day, calendar: calendar)
    XCTAssertEqual(t.nextFireAt,
                   calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))
  }

  func testAdvanceOnceDisablesTask() {
    var t = task(rule: .once(day))
    t.nextFireAt = day
    t.advanceNextFire(after: day, now: day, calendar: calendar)
    XCTAssertNil(t.nextFireAt)
    XCTAssertFalse(t.enabled)
  }

  func testFillNextFireDoesNotOverwriteExisting() {
    var t = task()
    let existing = day.addingTimeInterval(3600)
    t.nextFireAt = existing
    t.fillNextFireIfNeeded(now: day, calendar: calendar)
    XCTAssertEqual(t.nextFireAt, existing)
  }

  func testFillNextFireComputesWhenMissing() {
    var t = task(rule: .daily(hour: 9, minute: 0))
    t.fillNextFireIfNeeded(now: calendar.date(from: DateComponents(year: 2026, month: 11, day: 4, hour: 10))!,
                           calendar: calendar)
    XCTAssertEqual(t.nextFireAt,
                   calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 9)))
  }

  // MARK: - 정규화 · Codable

  func testNormalizedTitleFallsBack() {
    XCTAssertEqual(task(title: "   ").normalized().title, "예약 작업")
    XCTAssertEqual(task(title: "  아침\n리포트 ").normalized().title, "아침 리포트")
  }

  func testCodableRoundTripKeepsHistory() throws {
    var t = task()
    t.record(RunRecord(status: .succeeded, filePath: "/tmp/a.md", summary: "ok"))
    let data = try JSONEncoder().encode(t)
    let decoded = try JSONDecoder().decode(ScheduledTask.self, from: data)
    XCTAssertEqual(decoded, t)
  }

  func testMissingOptionalKeysDecode() throws {
    let json = Data(#"{"title":"t","instruction":"i","rule":{"kind":"daily","hour":9,"minute":0}}"#.utf8)
    let decoded = try JSONDecoder().decode(ScheduledTask.self, from: json)
    XCTAssertTrue(decoded.enabled)
    XCTAssertNil(decoded.personaID)
    XCTAssertTrue(decoded.history.isEmpty)
  }
}
