import XCTest
@testable import QuickTalkCore

/// v0.27 2단계 — 일정 도구(`schedule_list`·`schedule_update`·`schedule_delete`)의
/// **순수 검증 계층**. 실제 저장은 확인 카드에서 사용자가 승인해야 한다.
final class ScheduleToolsTests: XCTestCase {

  private var seoul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
  }

  /// 2026-11-04(수) 09:00 KST — 요일 계산을 고정한다.
  private var now: Date {
    var c = DateComponents()
    c.year = 2026; c.month = 11; c.day = 4; c.hour = 9; c.minute = 0
    return seoul.date(from: c)!
  }

  private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = seoul.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
  }

  private func task(id: UUID = UUID(), title: String = "뉴스", personaID: UUID? = nil,
                    rule: ScheduleRule = .daily(hour: 7, minute: 0),
                    skip: ScheduleSkip = .none,
                    enabled: Bool = true, nextFireAt: Date? = nil,
                    lastRun: RunRecord? = nil, createdAt: Date? = nil) -> ScheduledTask {
    ScheduledTask(id: id, personaID: personaID, title: title, instruction: "요약해 줘",
                  rule: rule, skip: skip, enabled: enabled, nextFireAt: nextFireAt,
                  lastRun: lastRun, createdAt: createdAt ?? now)
  }

  // MARK: - 등록 제안 · v2 규칙

  func testWeeklyMultipleDaysFromNestedRule() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"회의","instruction":"정리","rule":{"kind":"weekly","days":[2,4,6],"hour":8,"minute":30}}"#,
      now: now, calendar: seoul)
    XCTAssertEqual(p.rule, .weekly(days: [2, 4, 6], hour: 8, minute: 30))
  }

  func testWeeklyDaysFromNamesAndDedupe() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"회의","instruction":"정리","rule":{"kind":"weekly","days":["월","수","월"],"hour":8}}"#,
      now: now, calendar: seoul)
    XCTAssertEqual(p.rule, .weekly(days: [2, 4], hour: 8, minute: 0))
  }

  func testEveryNDaysWithoutAnchorStartsAtNextOccurrence() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"점검","instruction":"확인","rule":{"kind":"everyNDays","days":3,"hour":10,"minute":0}}"#,
      now: now, calendar: seoul)
    guard case let .everyNDays(days, hour, minute, anchor) = p.rule else {
      return XCTFail("everyNDays 가 아닙니다: \(p.rule)")
    }
    XCTAssertEqual(days, 3)
    XCTAssertEqual(hour, 10)
    XCTAssertEqual(minute, 0)
    XCTAssertEqual(anchor, date("2026-11-04 10:00"), "오늘 10시가 지나지 않았으므로 오늘")
  }

  func testEveryNDaysAnchorKeepsItsTime() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"점검","instruction":"확인","rule":{"kind":"everyNDays","days":2,"anchor":"2026-11-10 18:30"}}"#,
      now: now, calendar: seoul)
    XCTAssertEqual(p.rule, .everyNDays(days: 2, hour: 18, minute: 30,
                                       anchor: date("2026-11-10 18:30")))
  }

  func testEveryTwoDaysKindVariant() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"점검","instruction":"확인","rule":{"kind":"every2days","hour":7}}"#,
      now: now, calendar: seoul)
    guard case let .everyNDays(days, _, _, _) = p.rule else {
      return XCTFail("everyNDays 가 아닙니다: \(p.rule)")
    }
    XCTAssertEqual(days, 2)
  }

  func testIntervalRule() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"시세","instruction":"확인","rule":{"kind":"interval","start":"09:00","end":"15:00","everyMinutes":30}}"#,
      now: now, calendar: seoul)
    XCTAssertEqual(p.rule, .interval(startHour: 9, startMinute: 0,
                                     endHour: 15, endMinute: 0, everyMinutes: 30))
  }

  func testIntervalRejectsBackwardsWindow() {
    XCTAssertThrowsError(try ScheduleProposal.parse(
      #"{"title":"시세","instruction":"확인","rule":{"kind":"interval","start":"15:00","end":"09:00","everyMinutes":30}}"#,
      now: now, calendar: seoul)) { error in
      XCTAssertEqual(error as? ScheduleProposal.ParseError, .badInterval)
    }
  }

  func testSkipObjectAndArray() throws {
    let object = try ScheduleProposal.parse(
      #"{"title":"보고","instruction":"정리","rule":{"kind":"daily","hour":9},"skip":{"weekends":true,"holidays":true,"extraDates":["2026-11-05","2026-11-05","2026-13-01"]}}"#,
      now: now, calendar: seoul)
    XCTAssertTrue(object.skip.weekends)
    XCTAssertTrue(object.skip.holidays)
    XCTAssertEqual(object.skip.extraDates, ["2026-11-05"], "중복·잘못된 날짜는 버린다")

    let array = try ScheduleProposal.parse(
      #"{"title":"보고","instruction":"정리","rule":{"kind":"daily","hour":9},"skip":["주말","2026-11-06"]}"#,
      now: now, calendar: seoul)
    XCTAssertTrue(array.skip.weekends)
    XCTAssertFalse(array.skip.holidays)
    XCTAssertEqual(array.skip.extraDates, ["2026-11-06"])
  }

  func testSummaryLineIncludesSkip() throws {
    let p = try ScheduleProposal.parse(
      #"{"title":"보고","instruction":"정리","rule":{"kind":"weekly","days":[2,4],"hour":9},"skip":{"weekends":true}}"#,
      now: now, calendar: seoul)
    XCTAssertTrue(p.summaryLine(calendar: seoul).contains("09:00"))
    XCTAssertTrue(p.summaryLine(calendar: seoul).contains("주말"))
  }

  // MARK: - 변경 제안

  func testChangeTitleAndRuleDiff() throws {
    let id = UUID()
    let before = task(title: "뉴스", rule: .daily(hour: 7, minute: 0))
    let change = try ScheduleChangeProposal.parse(
      #"{"id":"\#(id.uuidString)","title":"아침 뉴스","rule":{"kind":"weekly","days":[2,4],"hour":8}}"#,
      tasks: [task(id: id, title: before.title, rule: before.rule)],
      now: now, calendar: seoul)
    XCTAssertEqual(change.taskID, id)
    XCTAssertEqual(change.after.title, "아침 뉴스")
    XCTAssertEqual(change.after.rule, .weekly(days: [2, 4], hour: 8, minute: 0))
    XCTAssertEqual(Set(change.changes.map(\.id)), ["title", "rule"])
    XCTAssertNil(change.after.nextFireAt, "규칙이 바뀌면 다음 시각을 다시 계산한다")
  }

  func testChangePauseAndSkip() throws {
    let id = UUID()
    let change = try ScheduleChangeProposal.parse(
      #"{"task_id":"\#(id.uuidString)","enabled":false,"skip":{"holidays":true}}"#,
      tasks: [task(id: id)], now: now, calendar: seoul)
    XCTAssertFalse(change.after.enabled)
    XCTAssertTrue(change.after.skip.holidays)
    XCTAssertEqual(Set(change.changes.map(\.id)), ["skip", "enabled"])
  }

  func testChangePersonaByName() throws {
    let id = UUID()
    let persona = Persona(name: "리서처")
    let change = try ScheduleChangeProposal.parse(
      #"{"id":"\#(id.uuidString)","persona":"리서처"}"#,
      personas: [persona], tasks: [task(id: id)], now: now, calendar: seoul)
    XCTAssertEqual(change.after.personaID, persona.id)
    XCTAssertEqual(change.changes.map(\.id), ["persona"])
  }

  func testChangeRejectsMissingUnknownAndEmpty() {
    let id = UUID()
    let existing = [task(id: id)]

    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"title":"새 제목"}"#, tasks: existing, now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .missingID)
    }
    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"id":"not-a-uuid"}"#, tasks: existing, now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .badID)
    }
    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"id":"\#(UUID().uuidString)"}"#, tasks: existing, now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .notFound)
    }
    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"id":"\#(id.uuidString)"}"#, tasks: existing, now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .noChanges)
    }
    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"id":"\#(id.uuidString)","title":"   "}"#, tasks: existing, now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .emptyTitle)
    }
  }

  func testChangeUnknownPersona() {
    let id = UUID()
    XCTAssertThrowsError(try ScheduleChangeProposal.parse(
      #"{"id":"\#(id.uuidString)","persona":"없는비서"}"#,
      tasks: [task(id: id)], now: now, calendar: seoul)) {
      XCTAssertEqual($0 as? ScheduleChangeProposal.ParseError, .unknownPersona("없는비서"))
    }
  }

  // MARK: - 삭제 제안

  func testDeletionProposalLooksUpTask() throws {
    let persona = Persona(name: "리서처")
    let id = UUID()
    let deletion = try ScheduleDeletionProposal.parse(
      #"{"id":"\#(id.uuidString)"}"#, personas: [persona],
      tasks: [task(id: id, title: "저녁 보고", personaID: persona.id,
                   skip: ScheduleSkip(weekends: true))])
    XCTAssertEqual(deletion.taskID, id)
    XCTAssertEqual(deletion.title, "저녁 보고")
    XCTAssertEqual(deletion.personaName, "리서처")
    XCTAssertEqual(deletion.skip, ScheduleSkip(weekends: true))
  }

  func testDeletionRejectsBadID() {
    XCTAssertThrowsError(try ScheduleDeletionProposal.parse(
      #"{"id":"nope"}"#, tasks: [])) {
      XCTAssertEqual($0 as? ScheduleDeletionProposal.ParseError, .badID)
    }
    XCTAssertThrowsError(try ScheduleDeletionProposal.parse(
      #"{}"#, tasks: [])) {
      XCTAssertEqual($0 as? ScheduleDeletionProposal.ParseError, .missingID)
    }
    XCTAssertThrowsError(try ScheduleDeletionProposal.parse(
      #"{"id":"\#(UUID().uuidString)"}"#, tasks: [])) {
      XCTAssertEqual($0 as? ScheduleDeletionProposal.ParseError, .notFound)
    }
  }

  // MARK: - 목록 텍스트

  func testListTextIncludesIDsAndState() {
    let persona = Persona(name: "리서처")
    let id = UUID()
    let run = RunRecord(startedAt: date("2026-11-03 07:00"),
                        finishedAt: date("2026-11-03 07:02"),
                        status: .succeeded)
    let text = ScheduleListText.render(
      [task(id: id, title: "아침 뉴스", personaID: persona.id,
            nextFireAt: date("2026-11-05 07:00"), lastRun: run)],
      now: now, calendar: seoul,
      personaNames: [persona.id: persona.name])
    XCTAssertTrue(text.contains(id.uuidString), "변경·삭제는 UUID 로만 지정한다")
    XCTAssertTrue(text.contains("아침 뉴스"))
    XCTAssertTrue(text.contains("리서처"))
    XCTAssertTrue(text.contains("07:00"))
    XCTAssertTrue(text.contains("성공"))
    XCTAssertTrue(text.contains("지시문"))
  }

  func testListTextEmptyAndDisabled() {
    XCTAssertEqual(ScheduleListText.render([], now: now, calendar: seoul),
                   L("예약 작업이 없습니다."))
    let text = ScheduleListText.render([task(enabled: false, nextFireAt: nil)],
                                       now: now, calendar: seoul)
    XCTAssertTrue(text.contains(L("중지")))
    XCTAssertTrue(text.contains(L("없음")))
  }

  func testListTextClipsLongInstruction() {
    var t = task()
    t.instruction = String(repeating: "가", count: 500)
    let text = ScheduleListText.render([t], now: now, calendar: seoul)
    XCTAssertTrue(text.contains("…"), "긴 지시문은 잘라서 넘긴다")
  }

  // MARK: - 비서 모델 덮어쓰기

  func testPersonaModelNormalizationAndCodable() throws {
    var p = Persona(name: "리서처", model: "  gpt-5-mini  ")
    p = p.normalized()
    XCTAssertEqual(p.model, "gpt-5-mini")

    let blank = Persona(name: "리서처", model: "   ").normalized()
    XCTAssertNil(blank.model)

    let data = try JSONEncoder().encode(p)
    let back = try JSONDecoder().decode(Persona.self, from: data)
    XCTAssertEqual(back.model, "gpt-5-mini")
  }
}
