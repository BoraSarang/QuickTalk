import XCTest
@testable import QuickTalkCore

// [FEATURE] v0.26 예약 규칙 — 다음 시각·따라잡기·표시 문구
//
// 시각 계산은 Calendar 를 주입받는 순수 함수다. 테스트는 서울/뉴욕을 고정해
// 자정 경계·DST·월말에서 흔들리지 않게 한다.

final class ScheduleRuleTests: XCTestCase {
  private var seoul: Calendar = {
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

  private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0,
                  _ s: Int = 0, calendar: Calendar? = nil) -> Date {
    let cal = calendar ?? seoul
    return cal.date(from: DateComponents(year: y, month: mo, day: d,
                                         hour: h, minute: mi, second: s))!
  }

  // MARK: - 매일

  func testDailyNextIsLaterToday() {
    let rule = ScheduleRule.daily(hour: 18, minute: 30)
    let next = rule.next(after: at(2026, 11, 3, 9, 0), calendar: seoul)
    XCTAssertEqual(next, at(2026, 11, 3, 18, 30))
  }

  func testDailyNextIsTomorrowAfterTimePassed() {
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    let next = rule.next(after: at(2026, 11, 3, 9, 0, 1), calendar: seoul)
    XCTAssertEqual(next, at(2026, 11, 4, 9, 0))
  }

  func testDailyExactlyAtTimeMovesToTomorrow() {
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 9, 0), calendar: seoul),
                   at(2026, 11, 4, 9, 0), "이미 실행한 시각을 다시 돌려주면 중복 실행된다")
  }

  func testDailyRejectsInvalidHour() {
    XCTAssertNil(ScheduleRule.daily(hour: 24, minute: 0).next(after: at(2026, 11, 3), calendar: seoul))
    XCTAssertNil(ScheduleRule.daily(hour: 9, minute: 60).next(after: at(2026, 11, 3), calendar: seoul))
  }

  func testDailyCrossesMonthEnd() {
    let rule = ScheduleRule.daily(hour: 8, minute: 15)
    XCTAssertEqual(rule.next(after: at(2026, 11, 30, 12, 0), calendar: seoul),
                   at(2026, 12, 1, 8, 15))
  }

  func testDailyKeepsLocalHourAcrossDST() {
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = TimeZone(identifier: "America/New_York")!
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    // 2026-03-08 은 미국 동부 DST 시작일 — 9시는 그대로 9시여야 한다.
    let next = rule.next(after: at(2026, 3, 7, 12, 0, calendar: ny), calendar: ny)
    XCTAssertNotNil(next)
    XCTAssertEqual(ny.component(.hour, from: next!), 9)
  }

  func testDailyNonexistentDSTTimeStillReturnsNextOccurrence() {
    var ny = Calendar(identifier: .gregorian)
    ny.timeZone = TimeZone(identifier: "America/New_York")!
    let rule = ScheduleRule.daily(hour: 2, minute: 30)
    // 2026-03-08 02:30 은 존재하지 않는다 — nil 이 아니라 다음 유효 시각을 돌려야 한다.
    let next = rule.next(after: at(2026, 3, 8, 0, 0, calendar: ny), calendar: ny)
    XCTAssertNotNil(next)
    XCTAssertGreaterThan(next!, at(2026, 3, 8, 0, 0, calendar: ny))
  }

  // MARK: - 매주

  func testWeeklyNextSameWeek() {
    // 2026-11-03 은 화요일. 다음 월요일은 11-09.
    let rule = ScheduleRule.weekly(weekday: 2, hour: 9, minute: 0)
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 10, 0), calendar: seoul),
                   at(2026, 11, 9, 9, 0))
  }

  func testWeeklyTodayAfterTimePassedGoesToNextWeek() {
    // 화요일 10:00, 화요일 09:00 규칙 → 다음 주 화요일.
    let rule = ScheduleRule.weekly(weekday: 3, hour: 9, minute: 0)
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 10, 0), calendar: seoul),
                   at(2026, 11, 10, 9, 0))
  }

  func testWeeklyRejectsInvalidWeekday() {
    XCTAssertNil(ScheduleRule.weekly(weekday: 0, hour: 9, minute: 0)
      .next(after: at(2026, 11, 3), calendar: seoul))
    XCTAssertNil(ScheduleRule.weekly(weekday: 8, hour: 9, minute: 0)
      .next(after: at(2026, 11, 3), calendar: seoul))
  }

  // MARK: - 한 번

  func testOnceFutureIsReturned() {
    let fire = at(2026, 11, 4, 15, 0)
    XCTAssertEqual(ScheduleRule.once(fire).next(after: at(2026, 11, 3), calendar: seoul), fire)
  }

  func testOncePastIsNil() {
    let fire = at(2026, 11, 1, 15, 0)
    XCTAssertNil(ScheduleRule.once(fire).next(after: at(2026, 11, 3), calendar: seoul))
  }

  func testOnceExpired() {
    XCTAssertTrue(ScheduleRule.once(at(2026, 11, 1)).isExpired(now: at(2026, 11, 3)))
    XCTAssertFalse(ScheduleRule.once(at(2026, 11, 5)).isExpired(now: at(2026, 11, 3)))
  }

  // MARK: - 따라잡기 24시간 경계

  func testCatchUpAllowsExactly24Hours() {
    let scheduled = at(2026, 11, 3, 9, 0)
    XCTAssertTrue(ScheduleRule.shouldCatchUp(now: scheduled.addingTimeInterval(24 * 3600),
                                             scheduled: scheduled))
  }

  func testCatchUpRejectsOneSecondOver24Hours() {
    let scheduled = at(2026, 11, 3, 9, 0)
    XCTAssertFalse(ScheduleRule.shouldCatchUp(now: scheduled.addingTimeInterval(24 * 3600 + 1),
                                              scheduled: scheduled))
  }

  func testCatchUpRejectsFutureSchedule() {
    let scheduled = at(2026, 11, 3, 9, 0)
    XCTAssertFalse(ScheduleRule.shouldCatchUp(now: scheduled.addingTimeInterval(-60),
                                              scheduled: scheduled))
  }

  // MARK: - 표시 문구

  func testKoreanDescriptions() {
    XCTAssertEqual(ScheduleRule.daily(hour: 9, minute: 0).humanDescription(calendar: seoul), "매일 09:00")
    XCTAssertEqual(ScheduleRule.weekly(weekday: 2, hour: 9, minute: 5)
      .humanDescription(calendar: seoul), "매주 월요일 09:05")
    XCTAssertEqual(ScheduleRule.once(at(2026, 11, 4, 15, 0))
      .humanDescription(calendar: seoul), "한 번 · 2026-11-04 15:00")
  }

  func testEnglishDescriptions() {
    L10n.language = .english
    XCTAssertEqual(ScheduleRule.daily(hour: 9, minute: 0).humanDescription(calendar: seoul),
                   "Every day at 09:00")
    XCTAssertEqual(ScheduleRule.weekly(weekday: 2, hour: 9, minute: 0)
      .humanDescription(calendar: seoul), "Every Monday at 09:00")
  }

  func testFrequencyLabels() {
    L10n.language = .korean
    XCTAssertEqual(ScheduleRule.daily(hour: 9, minute: 0).frequencyLabel, "매일")
    XCTAssertEqual(ScheduleRule.weekly(weekday: 1, hour: 9, minute: 0).frequencyLabel, "매주")
    XCTAssertEqual(ScheduleRule.once(Date()).frequencyLabel, "한 번")
  }

  // MARK: - Codable

  func testCodableRoundTripForEveryKind() throws {
    let rules: [ScheduleRule] = [
      .daily(hour: 9, minute: 30),
      .weekly(weekday: 5, hour: 18, minute: 0),
      .once(at(2026, 11, 4, 15, 0))
    ]
    for rule in rules {
      let data = try JSONEncoder().encode(rule)
      XCTAssertEqual(try JSONDecoder().decode(ScheduleRule.self, from: data), rule)
    }
  }

  func testDecodingUnknownKindThrows() {
    let json = Data(#"{"kind":"yearly","hour":9,"minute":0}"#.utf8)
    XCTAssertThrowsError(try JSONDecoder().decode(ScheduleRule.self, from: json))
  }

  func testDecodedInvalidTimeIsNotValid() throws {
    let json = Data(#"{"kind":"daily","hour":25,"minute":0}"#.utf8)
    let rule = try JSONDecoder().decode(ScheduleRule.self, from: json)
    XCTAssertFalse(rule.isValid)
    XCTAssertNil(rule.next(after: Date(), calendar: seoul))
  }

  func testMatches() {
    XCTAssertTrue(ScheduleRule.daily(hour: 9, minute: 0).matches(at(2026, 11, 3, 9, 0), calendar: seoul))
    XCTAssertFalse(ScheduleRule.daily(hour: 9, minute: 0).matches(at(2026, 11, 3, 9, 1), calendar: seoul))
    XCTAssertTrue(ScheduleRule.weekly(weekday: 3, hour: 9, minute: 0)
      .matches(at(2026, 11, 3, 9, 0), calendar: seoul))
  }

  // MARK: - v0.27 새 규칙

  /// 2026-11-03 은 화요일 — 월·수·금 중 가장 가까운 수요일로 간다.
  func testWeeklyMultipleDaysPicksNearest() {
    let rule = ScheduleRule.weekly(days: [2, 4, 6], hour: 9, minute: 0)
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 0, 0), calendar: seoul),
                   at(2026, 11, 4, 9, 0))
  }

  func testWeeklyRejectsEmptyOrDuplicateDays() {
    XCTAssertFalse(ScheduleRule.weekly(days: [], hour: 9, minute: 0).isValid)
    XCTAssertFalse(ScheduleRule.weekly(days: [2, 2], hour: 9, minute: 0).isValid)
    XCTAssertNil(ScheduleRule.weekly(days: [], hour: 9, minute: 0)
      .next(after: at(2026, 11, 3), calendar: seoul))
  }

  /// 09:00~21:00 2시간마다 = 09, 11, 13, 15, 17, 19, 21.
  func testIntervalSlotsWithinSameDay() {
    let rule = ScheduleRule.interval(startHour: 9, startMinute: 0,
                                     endHour: 21, endMinute: 0, everyMinutes: 120)
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 8, 59), calendar: seoul),
                   at(2026, 11, 3, 9, 0))
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 9, 0), calendar: seoul),
                   at(2026, 11, 3, 11, 0))
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 20, 59), calendar: seoul),
                   at(2026, 11, 3, 21, 0))
    // 구간이 끝나면 다음 날 첫 슬롯.
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 21, 0), calendar: seoul),
                   at(2026, 11, 4, 9, 0))
  }

  func testIntervalRejectsCadenceLongerThanWindow() {
    let rule = ScheduleRule.interval(startHour: 9, startMinute: 0,
                                     endHour: 10, endMinute: 0, everyMinutes: 120)
    XCTAssertFalse(rule.isValid)
    XCTAssertNil(rule.next(after: at(2026, 11, 3), calendar: seoul))
  }

  func testEveryNDaysUsesAnchor() {
    let rule = ScheduleRule.everyNDays(days: 2, hour: 9, minute: 0,
                                       anchor: at(2026, 11, 3, 9, 0))
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 9, 0), calendar: seoul),
                   at(2026, 11, 5, 9, 0))
    XCTAssertEqual(rule.next(after: at(2026, 11, 4, 18, 0), calendar: seoul),
                   at(2026, 11, 5, 9, 0))
  }

  func testEveryNDaysBeforeAnchorStartsAtAnchor() {
    let rule = ScheduleRule.everyNDays(days: 3, hour: 9, minute: 0,
                                       anchor: at(2026, 11, 10, 9, 0))
    XCTAssertEqual(rule.next(after: at(2026, 11, 1, 0, 0), calendar: seoul),
                   at(2026, 11, 10, 9, 0))
  }

  // MARK: - v0.27 제외

  /// 금요일 09:00 다음은 월요일 09:00 — 토·일을 건너뛴다.
  func testSkipWeekends() {
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    let next = rule.next(after: at(2026, 11, 6, 9, 0), calendar: seoul,
                         skip: ScheduleSkip(weekends: true))
    XCTAssertEqual(next, at(2026, 11, 9, 9, 0))
  }

  func testSkipExtraDate() {
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    let skip = ScheduleSkip(extraDates: ["2026-11-04"])
    XCTAssertEqual(rule.next(after: at(2026, 11, 3, 9, 0), calendar: seoul, skip: skip),
                   at(2026, 11, 5, 9, 0))
  }

  func testKoreanHolidaySubstitutes2025() {
    let dates = KoreanHolidays.dates(inYear: 2025)
    XCTAssertTrue(dates.contains("2025-05-05"), "어린이날·부처님오신날")
    XCTAssertTrue(dates.contains("2025-05-06"), "겹친 공휴일의 대체공휴일")
    XCTAssertTrue(dates.contains("2025-10-08"), "추석 연휴 대체공휴일")
  }

  func testSkipHolidaysSkipsSubstitute() {
    let rule = ScheduleRule.daily(hour: 9, minute: 0)
    let skip = ScheduleSkip(holidays: true)
    XCTAssertEqual(rule.next(after: at(2025, 5, 5, 9, 0), calendar: seoul, skip: skip),
                   at(2025, 5, 7, 9, 0))
  }

  func testSkipNormalizesInvalidDates() {
    let skip = ScheduleSkip(extraDates: ["2026-11-04", "2026-11-04", "2026-02-30", "x"])
      .normalized()
    XCTAssertEqual(skip.extraDates, ["2026-11-04"])
  }

  // MARK: - v0.27 Codable

  func testLegacyWeeklyWeekdayDecoding() throws {
    let json = Data(#"{"kind":"weekly","weekday":2,"hour":9,"minute":0}"#.utf8)
    let rule = try JSONDecoder().decode(ScheduleRule.self, from: json)
    XCTAssertEqual(rule, .weekly(days: [2], hour: 9, minute: 0))
  }

  func testV2RulesRoundTrip() throws {
    let rules: [ScheduleRule] = [
      .weekly(days: [2, 4, 6], hour: 9, minute: 0),
      .everyNDays(days: 2, hour: 9, minute: 0, anchor: at(2026, 11, 3, 9, 0)),
      .interval(startHour: 9, startMinute: 0, endHour: 21, endMinute: 0, everyMinutes: 120)
    ]
    for rule in rules {
      let data = try JSONEncoder().encode(rule)
      XCTAssertEqual(try JSONDecoder().decode(ScheduleRule.self, from: data), rule)
    }
  }

  func testScheduleSkipDecodesMissingKeysAsNone() throws {
    let skip = try JSONDecoder().decode(ScheduleSkip.self, from: Data("{}".utf8))
    XCTAssertEqual(skip, .none)
  }
}
