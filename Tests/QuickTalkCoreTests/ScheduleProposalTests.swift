import XCTest
@testable import QuickTalkCore

/// v0.26 4단계 — 모델이 부른 `schedule_task` 인자 검증.
/// **등록은 하지 않는다** — 제안만 만들고, 등록은 확인 카드에서 사용자가 결정한다.
final class ScheduleProposalTests: XCTestCase {

  private var seoul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
  }

  private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Seoul")!
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
  }

  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func parse(_ json: String, personas: [Persona] = [],
                     now: Date? = nil) throws -> ScheduleProposal {
    try ScheduleProposal.parse(json, personas: personas,
                               now: now ?? self.now, calendar: seoul)
  }

  // MARK: - 반복 규칙

  func testDailyFromNestedRule() throws {
    let p = try parse(#"{"title":"뉴스","instruction":"요약해 줘","rule":{"kind":"daily","hour":7,"minute":30}}"#)
    XCTAssertEqual(p.rule, .daily(hour: 7, minute: 30))
    XCTAssertEqual(p.title, "뉴스")
    XCTAssertEqual(p.instruction, "요약해 줘")
  }

  func testFlatArgumentsAccepted() throws {
    // 작은 모델이 `rule` 중첩을 빠뜨리는 경우 — 평평한 키도 받는다.
    let p = try parse(#"{"title":"뉴스","instruction":"요약","kind":"daily","hour":8,"minute":5}"#)
    XCTAssertEqual(p.rule, .daily(hour: 8, minute: 5))
  }

  func testDailyDefaultsToNineOClock() throws {
    let p = try parse(#"{"title":"뉴스","instruction":"요약","rule":{"kind":"daily"}}"#)
    XCTAssertEqual(p.rule, .daily(hour: 9, minute: 0))
  }

  func testWeeklyKeepsWeekday() throws {
    let p = try parse(#"{"title":"회의","instruction":"정리","rule":{"kind":"weekly","weekday":2,"hour":10,"minute":0}}"#)
    XCTAssertEqual(p.rule, .weekly(weekday: 2, hour: 10, minute: 0))
  }

  func testWeeklyWithoutWeekdayFails() {
    XCTAssertThrowsError(try parse(#"{"title":"회의","instruction":"정리","rule":{"kind":"weekly"}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .badWeekday)
    }
  }

  func testInvalidTimeFails() {
    XCTAssertThrowsError(try parse(#"{"title":"뉴스","instruction":"요약","rule":{"kind":"daily","hour":24}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .badTime)
    }
    XCTAssertThrowsError(try parse(#"{"title":"뉴스","instruction":"요약","rule":{"kind":"daily","minute":60}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .badTime)
    }
  }

  func testUnknownKindFailsWithName() {
    XCTAssertThrowsError(try parse(#"{"title":"뉴스","instruction":"요약","rule":{"kind":"hourly"}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .badKind("hourly"))
    }
  }

  // MARK: - 한 번 실행

  func testOnceInFutureAccepted() throws {
    let raw = #"{"title":"한 번","instruction":"확인","rule":{"kind":"once","date":"2026-11-05 09:00"}}"#
    let p = try parse(raw, now: date("2026-11-04 09:00"))
    XCTAssertEqual(p.rule, .once(date("2026-11-05 09:00")))
  }

  func testOnceInPastRejected() {
    let raw = #"{"title":"한 번","instruction":"확인","rule":{"kind":"once","date":"2026-11-03 09:00"}}"#
    XCTAssertThrowsError(try parse(raw, now: date("2026-11-04 09:00"))) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .pastDate)
    }
  }

  func testOnceWithoutDateRejected() {
    XCTAssertThrowsError(try parse(#"{"title":"한 번","instruction":"확인","rule":{"kind":"once"}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .badDate)
    }
  }

  func testOnceAcceptsISOAndEpoch() throws {
    let iso = try parse(#"{"title":"a","instruction":"b","rule":{"kind":"once","date":"2026-11-05T09:00:00+09:00"}}"#,
                        now: date("2026-11-04 09:00"))
    if case .once(let d) = iso.rule {
      XCTAssertEqual(d, date("2026-11-05 09:00"))
    } else {
      XCTFail("once 가 아님")
    }

    let epoch = try parse(#"{"title":"a","instruction":"b","rule":{"kind":"once","date":"1800000000"}}"#,
                          now: Date(timeIntervalSince1970: 1_700_000_000))
    if case .once(let d) = epoch.rule {
      XCTAssertEqual(d.timeIntervalSince1970, 1_800_000_000, accuracy: 1)
    } else {
      XCTFail("once 가 아님")
    }
  }

  // MARK: - 제목·지시문

  func testMissingTitleDerivedFromInstruction() throws {
    let p = try parse(#"{"instruction":"최신 AI 뉴스를 정리해 줘\n자세히","rule":{"kind":"daily"}}"#)
    XCTAssertEqual(p.title, "최신 AI 뉴스를 정리해 줘")
  }

  func testLongTitleIsTruncated() throws {
    let title = String(repeating: "가", count: 100)
    let p = try parse(#"{"title":"\#(title)","instruction":"요약","rule":{"kind":"daily"}}"#)
    XCTAssertEqual(p.title.count, ScheduleProposal.Limits.title)
  }

  func testLongInstructionIsTruncated() throws {
    let instruction = String(repeating: "나", count: 5000)
    let p = try parse(#"{"title":"t","instruction":"\#(instruction)","rule":{"kind":"daily"}}"#)
    XCTAssertEqual(p.instruction.count, ScheduleProposal.Limits.instruction)
  }

  func testWhitespaceCollapsed() throws {
    let p = try parse(#"{"title":"  뉴스   정리 ","instruction":"  요약\n\n 해  줘 ","rule":{"kind":"daily"}}"#)
    XCTAssertEqual(p.title, "뉴스 정리")
    XCTAssertEqual(p.instruction, "요약 해 줘")
  }

  func testEmptyInstructionFails() {
    XCTAssertThrowsError(try parse(#"{"title":"t","instruction":"   ","rule":{"kind":"daily"}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .emptyInstruction)
    }
  }

  func testNotJSONFails() {
    XCTAssertThrowsError(try parse("그냥 문장")) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .notJSON)
    }
  }

  // MARK: - 비서

  func testPersonaMatchedByName() throws {
    let persona = Persona(name: "돌쇠", role: "비서")
    let p = try parse(#"{"title":"뉴스","instruction":"요약","persona":"돌쇠","rule":{"kind":"daily"}}"#,
                      personas: [persona])
    XCTAssertEqual(p.personaID, persona.id)
    XCTAssertEqual(p.personaName, "돌쇠")
  }

  func testPersonaMatchedCaseInsensitivelyAndByID() throws {
    let persona = Persona(name: "Dolsoe", role: "비서")
    let byName = try parse(#"{"title":"뉴스","instruction":"요약","persona":"dolsoe","rule":{"kind":"daily"}}"#,
                           personas: [persona])
    XCTAssertEqual(byName.personaID, persona.id)
    let byID = try parse(#"{"title":"뉴스","instruction":"요약","persona":"\#(persona.id.uuidString)","rule":{"kind":"daily"}}"#,
                         personas: [persona])
    XCTAssertEqual(byID.personaID, persona.id)
  }

  func testDefaultPersonaAliasesMeanNoPersona() throws {
    for name in ["", "기본", "default", "none", "없음"] {
      let p = try parse(#"{"title":"뉴스","instruction":"요약","persona":"\#(name)","rule":{"kind":"daily"}}"#)
      XCTAssertNil(p.personaID, name)
      XCTAssertNil(p.personaName, name)
    }
  }

  func testUnknownPersonaFails() {
    XCTAssertThrowsError(try parse(#"{"title":"뉴스","instruction":"요약","persona":"졸쇠","rule":{"kind":"daily"}}"#)) {
      XCTAssertEqual($0 as? ScheduleProposal.ParseError, .unknownPersona("졸쇠"))
    }
  }

  // MARK: - 표시

  func testSummaryLineMatchesRuleDescription() throws {
    let p = try parse(#"{"title":"뉴스","instruction":"요약","rule":{"kind":"daily","hour":7,"minute":30}}"#)
    XCTAssertEqual(p.summaryLine(calendar: seoul), p.rule.humanDescription(calendar: seoul))
  }

  func testParseDateFormats() {
    let expected = date("2026-11-05 09:00")
    for raw in ["2026-11-05 09:00", "2026-11-05T09:00"] {
      XCTAssertEqual(ScheduleProposal.parseDate(raw, calendar: seoul), expected, raw)
    }
    XCTAssertNil(ScheduleProposal.parseDate("내일 아침", calendar: seoul))
  }
}
