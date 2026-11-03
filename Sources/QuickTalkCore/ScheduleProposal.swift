import Foundation

/// 모델이 부른 `schedule_task` 인자를 **검증된 제안**으로 바꾼다 (v0.26 4단계).
///
/// 모델은 작은 경우가 많아 JSON 모양을 자주 틀린다. 그래서 여기서는
/// ① 중첩(`rule: {...}`)과 ② 평평한(`kind`,`hour`,…) 두 모양을 모두 받고,
/// ③ 시각·요일 범위를 검사한 뒤 ④ **미래 시각인지**까지 확인한다.
///
/// 이 타입은 **등록하지 않는다** — 확인 카드에서 사용자가 승인해야
/// `SchedulerService.upsert` 로 등록된다(도구가 곧바로 일정을 만들지 않는다).
public struct ScheduleProposal: Equatable {
  public var title: String
  public var instruction: String
  public var rule: ScheduleRule
  /// 이름으로 지정된 비서(없으면 `기본`).
  public var personaID: UUID?
  public var personaName: String?

  public init(title: String, instruction: String, rule: ScheduleRule,
              personaID: UUID? = nil, personaName: String? = nil) {
    self.title = title
    self.instruction = instruction
    self.rule = rule
    self.personaID = personaID
    self.personaName = personaName
  }

  public enum Limits {
    public static let title = 60
    public static let instruction = 4000
  }

  public enum ParseError: Error, Equatable, LocalizedError {
    case notJSON
    case emptyTitle
    case emptyInstruction
    case badKind(String)
    case badTime
    case badWeekday
    case pastDate
    case badDate
    case unknownPersona(String)

    public var errorDescription: String? { message }

    public var message: String {
      switch self {
      case .notJSON:
        return L("일정 인자를 읽지 못했습니다(JSON 형식이 아닙니다).")
      case .emptyTitle:
        return L("일정 제목이 비어 있습니다.")
      case .emptyInstruction:
        return L("일정 지시문이 비어 있습니다.")
      case .badKind(let kind):
        return Lf("반복 종류를 알 수 없습니다: %@ (daily·weekly·once 중 하나)", kind)
      case .badTime:
        return L("시각이 올바르지 않습니다(시 0~23, 분 0~59).")
      case .badWeekday:
        return L("요일이 올바르지 않습니다(1=일요일 … 7=토요일).")
      case .pastDate:
        return L("이미 지난 시각입니다. 앞으로의 시각을 지정하세요.")
      case .badDate:
        return L("한 번 실행할 날짜를 읽지 못했습니다.")
      case .unknownPersona(let name):
        return Lf("그런 비서가 없습니다: %@", name)
      }
    }
  }

  /// 모델 인자(JSON 문자열) → 제안. `personas` 는 이름 매칭에만 쓴다.
  public static func parse(_ arguments: String, personas: [Persona] = [],
                           now: Date = Date(),
                           calendar: Calendar = .current) throws -> ScheduleProposal {
    guard let data = arguments.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParseError.notJSON
    }
    // 중첩 rule 이 있으면 그쪽을 우선하고, 없으면 평평한 키를 본다.
    let ruleObject = root["rule"] as? [String: Any] ?? root

    // 제목을 지시문 첫 줄에서 만들 수 있도록 **정리 전 원문**을 남겨 둔다
    // (정리하면서 개행이 공백으로 바뀌면 첫 줄 경계를 잃는다).
    let rawInstruction = root["instruction"] as? String ?? ""
    let instruction = clean(rawInstruction)
    guard !instruction.isEmpty else { throw ParseError.emptyInstruction }

    var title = clean(root["title"] as? String ?? "")
    if title.isEmpty { title = derivedTitle(from: rawInstruction) }
    guard !title.isEmpty else { throw ParseError.emptyTitle }
    if title.count > Limits.title { title = String(title.prefix(Limits.title)) }
    var limitedInstruction = instruction
    if limitedInstruction.count > Limits.instruction {
      limitedInstruction = String(limitedInstruction.prefix(Limits.instruction))
    }

    let rule = try parseRule(ruleObject, now: now, calendar: calendar)
    let (personaID, personaName) = try resolvePersona(root["persona"], personas: personas)

    return ScheduleProposal(title: title, instruction: limitedInstruction, rule: rule,
                            personaID: personaID, personaName: personaName)
  }

  /// 사람이 읽는 한 줄 — 확인 카드에 쓴다.
  public func summaryLine(calendar: Calendar = .current) -> String {
    rule.humanDescription(calendar: calendar)
  }

  // MARK: - 규칙

  private static func parseRule(_ object: [String: Any], now: Date,
                                calendar: Calendar) throws -> ScheduleRule {
    let kind = (object["kind"] as? String
                ?? object["frequency"] as? String
                ?? object["repeat"] as? String
                ?? "daily").lowercased()

    switch kind {
    case "daily", "everyday", "매일":
      let hour = int(object["hour"]) ?? 9
      let minute = int(object["minute"]) ?? 0
      guard ScheduleRule.validTime(hour: hour, minute: minute) else { throw ParseError.badTime }
      return .daily(hour: hour, minute: minute)

    case "weekly", "매주":
      guard let weekday = int(object["weekday"]), (1...7).contains(weekday) else {
        throw ParseError.badWeekday
      }
      let hour = int(object["hour"]) ?? 9
      let minute = int(object["minute"]) ?? 0
      guard ScheduleRule.validTime(hour: hour, minute: minute) else { throw ParseError.badTime }
      return .weekly(weekday: weekday, hour: hour, minute: minute)

    case "once", "한번", "한 번", "one":
      guard let raw = object["date"] as? String ?? object["at"] as? String,
            let date = parseDate(raw, calendar: calendar) else {
        throw ParseError.badDate
      }
      guard date > now else { throw ParseError.pastDate }
      return .once(date)

    default:
      throw ParseError.badKind(kind)
    }
  }

  /// ISO8601 · "yyyy-MM-dd HH:mm" · "yyyy-MM-dd'T'HH:mm" · epoch 초를 모두 받는다.
  static func parseDate(_ raw: String, calendar: Calendar = .current) -> Date? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if let seconds = Double(text), seconds > 1_000_000_000 {
      return Date(timeIntervalSince1970: seconds)
    }
    let iso = ISO8601DateFormatter()
    iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = iso.date(from: text) { return d }
    iso.formatOptions = [.withInternetDateTime]
    if let d = iso.date(from: text) { return d }
    for format in ["yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd"] {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.calendar = calendar
      f.timeZone = calendar.timeZone
      f.dateFormat = format
      if let d = f.date(from: text) { return d }
    }
    return nil
  }

  // MARK: - 비서

  private static func resolvePersona(_ raw: Any?, personas: [Persona]) throws -> (UUID?, String?) {
    guard let raw else { return (nil, nil) }
    let text = (raw as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    // 빈 값·"기본"·"default" 는 비서 없음.
    if text.isEmpty || ["기본", "default", "none", "없음"].contains(text.lowercased()) {
      return (nil, nil)
    }
    if let id = UUID(uuidString: text), let p = personas.first(where: { $0.id == id }) {
      return (p.id, p.name)
    }
    if let p = personas.first(where: { $0.name.caseInsensitiveCompare(text) == .orderedSame }) {
      return (p.id, p.name)
    }
    throw ParseError.unknownPersona(text)
  }

  // MARK: - 문자열

  /// 공백·개행 정리(제목용) — 지시문은 개행을 유지한다.
  private static func clean(_ raw: String) -> String {
    raw.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespaces)
  }

  /// 제목이 없을 때 지시문 첫 줄에서 만든다 — 모델이 title 을 빠뜨려도 등록할 수 있게.
  private static func derivedTitle(from instruction: String) -> String {
    let first = instruction.components(separatedBy: .newlines)
      .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
    return String(clean(first).prefix(40))
  }

  private static func int(_ value: Any?) -> Int? {
    if let n = value as? Int { return n }
    if let d = value as? Double { return Int(d) }
    if let s = value as? String { return Int(s) }
    return nil
  }
}
