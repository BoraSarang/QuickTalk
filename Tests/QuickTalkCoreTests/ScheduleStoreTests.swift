import XCTest
@testable import QuickTalkCore

// [FEATURE] v0.26 예약 저장·판정 — 왕복·손상 복구·따라잡기
//
// 일정 파일은 대화 기록과 별개다. 손상돼도 **백업을 남기고** 빈 목록으로 시작해
// 앱이 부팅을 막지 않는다.

final class ScheduleStoreTests: XCTestCase {
  private var directory: URL!
  private var file: URL!

  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
  }()

  override func setUpWithError() throws {
    try super.setUpWithError()
    L10n.language = .korean
    directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-schedule-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    file = directory.appendingPathComponent("schedules.json")
  }

  override func tearDownWithError() throws {
    L10n.language = .system
    try? FileManager.default.removeItem(at: directory)
    try super.tearDownWithError()
  }

  private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
  }

  private func task(title: String = "리포트",
                    rule: ScheduleRule = .daily(hour: 9, minute: 0),
                    nextFireAt: Date? = nil, enabled: Bool = true) -> ScheduledTask {
    ScheduledTask(title: title, instruction: "요약", rule: rule, enabled: enabled,
                  nextFireAt: nextFireAt)
  }

  // MARK: - 저장·로드

  func testSaveLoadRoundTrip() throws {
    let snapshot = ScheduleSnapshot(tasks: [task(title: "하나"), task(title: "둘")])
    try ScheduleStore.save(snapshot, to: file)
    XCTAssertEqual(ScheduleStore.load(from: file), snapshot)
  }

  func testMissingFileReturnsEmpty() {
    XCTAssertTrue(ScheduleStore.load(from: file).tasks.isEmpty)
    XCTAssertEqual(ScheduleStore.load(from: file).schemaVersion, ScheduleSnapshot.currentVersion)
  }

  func testCorruptFileIsBackedUpAndIgnored() throws {
    try Data("{not json".utf8).write(to: file)
    let loaded = ScheduleStore.load(from: file)
    XCTAssertTrue(loaded.tasks.isEmpty)

    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix("schedules.corrupt-") }
    XCTAssertEqual(backups.count, 1, "손상 파일은 지우지 않고 백업한다")
    XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "원본도 남긴다")
  }

  func testBackupNamesDoNotCollide() throws {
    try Data("bad".utf8).write(to: file)
    let now = at(2026, 11, 3, 10, 0)
    let first = ScheduleStore.backup(file, now: now)
    let second = ScheduleStore.backup(file, now: now)
    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    XCTAssertNotEqual(first, second)
  }

  func testFutureSchemaIsBackedUpNotOverwritten() throws {
    let json = Data(#"{"schemaVersion":99,"tasks":[]}"#.utf8)
    try json.write(to: file)
    let loaded = ScheduleStore.load(from: file)
    XCTAssertTrue(loaded.tasks.isEmpty)
    let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
      .filter { $0.hasPrefix("schedules.corrupt-") }
    XCTAssertEqual(backups.count, 1)
    XCTAssertEqual(try Data(contentsOf: file), json, "모르는 버전의 원본을 덮어쓰지 않는다")
  }

  func testMissingSchemaVersionDefaultsToCurrent() throws {
    try Data(#"{"tasks":[]}"#.utf8).write(to: file)
    XCTAssertEqual(ScheduleStore.load(from: file).schemaVersion, ScheduleSnapshot.currentVersion)
  }

  // MARK: - 판정

  func testDueWhenNextFireHasPassed() {
    let now = at(2026, 11, 3, 9, 1)
    let tick = SchedulePlanner.tick([task(nextFireAt: at(2026, 11, 3, 9, 0))],
                                    now: now, calendar: calendar)
    XCTAssertEqual(tick.due.count, 1)
    XCTAssertTrue(tick.missed.isEmpty)
    XCTAssertEqual(tick.due.first?.fireAt, at(2026, 11, 3, 9, 0))
  }

  func testNotDueBeforeTime() {
    let tick = SchedulePlanner.tick([task(nextFireAt: at(2026, 11, 4, 9, 0))],
                                    now: at(2026, 11, 3, 9, 0), calendar: calendar)
    XCTAssertTrue(tick.isEmpty)
  }

  func testMissedBeyond24HoursIsSkipped() {
    let scheduled = at(2026, 11, 1, 9, 0)
    let tick = SchedulePlanner.tick([task(nextFireAt: scheduled)],
                                    now: at(2026, 11, 3, 9, 0), calendar: calendar)
    XCTAssertTrue(tick.due.isEmpty)
    XCTAssertEqual(tick.missed.count, 1)
  }

  func testExactly24HoursIsStillDue() {
    let scheduled = at(2026, 11, 2, 9, 0)
    let tick = SchedulePlanner.tick([task(nextFireAt: scheduled)],
                                    now: at(2026, 11, 3, 9, 0), calendar: calendar)
    XCTAssertEqual(tick.due.count, 1)
  }

  func testDisabledTaskNeverFires() {
    let tick = SchedulePlanner.tick([task(nextFireAt: at(2026, 11, 3, 9, 0), enabled: false)],
                                    now: at(2026, 11, 4, 9, 0), calendar: calendar)
    XCTAssertTrue(tick.isEmpty)
  }

  func testTaskWithoutNextFireDoesNotFire() {
    let tick = SchedulePlanner.tick([task()], now: at(2026, 11, 4, 9, 0), calendar: calendar)
    XCTAssertTrue(tick.isEmpty)
  }

  func testDueTasksAreSortedByFireTime() {
    let early = task(title: "early", nextFireAt: at(2026, 11, 3, 8, 0))
    let late = task(title: "late", nextFireAt: at(2026, 11, 3, 9, 0))
    let tick = SchedulePlanner.tick([late, early], now: at(2026, 11, 3, 10, 0), calendar: calendar)
    XCTAssertEqual(tick.due.map(\.task.title), ["early", "late"])
  }

  func testReconciledFillsMissingNextFire() {
    let now = at(2026, 11, 4, 10, 0)
    let result = SchedulePlanner.reconciled([task(rule: .daily(hour: 9, minute: 0))],
                                            now: now, calendar: calendar)
    XCTAssertEqual(result.first?.nextFireAt, at(2026, 11, 5, 9, 0))
  }

  func testReconciledKeepsExistingNextFire() {
    let existing = at(2026, 11, 5, 9, 0)
    let result = SchedulePlanner.reconciled([task(nextFireAt: existing)],
                                            now: at(2026, 11, 4, 10, 0), calendar: calendar)
    XCTAssertEqual(result.first?.nextFireAt, existing)
  }

  func testAdvancedOnceTaskBecomesDisabled() {
    let fire = at(2026, 11, 4, 9, 0)
    var t = task(rule: .once(fire), nextFireAt: fire)
    t = SchedulePlanner.advanced(t, fireAt: fire, now: fire, calendar: calendar)
    XCTAssertNil(t.nextFireAt)
    XCTAssertFalse(t.enabled)
  }

  func testAdvancedDailyTaskMovesForward() {
    let fire = at(2026, 11, 3, 9, 0)
    let t = SchedulePlanner.advanced(task(nextFireAt: fire), fireAt: fire,
                                     now: at(2026, 11, 3, 9, 1), calendar: calendar)
    XCTAssertEqual(t.nextFireAt, at(2026, 11, 4, 9, 0))
  }
}
