import Foundation

/// 모델이 부른 `schedule_task` 인자를 **검증된 제안**으로 바꾼다 (v0.26 4단계, v0.27 확장).
///
/// 모델은 작은 경우가 많아 JSON 모양을 자주 틀린다. 그래서 여기서는
/// ① 중첩(`rule: {...}`)과 ② 평평한(`kind`,`hour`,…) 두 모양을 모두 받고,
/// ③ 시각·요일·간격 범위를 검사한 뒤 ④ **미래 시각인지**까지 확인한다.
///
/// v0.27: `weekly(days:)` · `everyNDays` · `interval` 과 `skip`(주말·공휴일·날짜)을 받는다.
///
/// 이 타입은 **등록하지 않는다** — 확인 카드에서 사용자가 승인해야
/// `SchedulerService.upsert` 로 등록된다(도구가 곧바로 일정을 만들지 않는다).
public struct ScheduleProposal: Equatable {
  public var title: String
  public var instruction: String
  public var rule: ScheduleRule
  /// 건너뛸 날 (v0.27) — 주말·공휴일·직접 지정한 날짜.
  public var skip: ScheduleSkip
  /// 이름으로 지정된 비서(없으면 `기본`).
  public var personaID: UUID?
  public var personaName: String?

  public init(title: String, instruction: String, rule: ScheduleRule,
              skip: ScheduleSkip = .none,
              personaID: UUID? = nil, personaName: String? = nil) {
    self.title = title
    self.instruction = instruction
    self.rule = rule
    self.skip = skip
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
    case badDays
    case badInterval
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
        return Lf("반복 종류를 알 수 없습니다: %@ (daily·weekly·everyNDays·interval·once 중 하나)", kind)
      case .badTime:
        return L("시각이 올바르지 않습니다(시 0~23, 분 0~59).")
      case .badWeekday:
        return L("요일이 올바르지 않습니다(1=일요일 … 7=토요일, 여러 개 가능).")
      case .badDays:
        return L("N일 간격이 올바르지 않습니다(1~365일).")
      case .badInterval:
        return L("구간 반복 설정이 올바르지 않습니다(시작 < 끝, 간격 5~720분).")
      case .pastDate:
        return L("이미 지난 시각입니다. 앞으로의 시각을 지정하세요.")
      case .badDate:
        return L("실행할 날짜를 읽지 못했습니다.")
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

    let rule = try parseRuleObject(ruleObject, now: now, calendar: calendar)
    // `skip` 은 rule 안/밖 어디에 와도 받는다.
    let skip = parseSkipObject(root["skip"] ?? ruleObject["skip"], calendar: calendar)
    let (personaID, personaName) = try resolvePersona(root["persona"], personas: personas)

    return ScheduleProposal(title: title, instruction: limitedInstruction, rule: rule,
                            skip: skip, personaID: personaID, personaName: personaName)
  }

  /// 사람이 읽는 한 줄 — 확인 카드에 쓴다.
  public func summaryLine(calendar: Calendar = .current) -> String {
    var parts = [rule.humanDescription(calendar: calendar)]
    if let skip = skip.normalized().humanDescription() { parts.append(skip) }
    return parts.joined(separator: " · ")
  }

  // MARK: - 규칙

  /// 규칙 JSON 한 덩어리 → `ScheduleRule`. 등록 제안·변경 제안이 **같은 검증**을 쓰도록 공개한다.
  public static func parseRuleObject(_ object: [String: Any], now: Date,
                                     calendar: Calendar = .current) throws -> ScheduleRule {
    let rawKind = (object["kind"] as? String
                   ?? object["frequency"] as? String
                   ?? object["repeat"] as? String
                   ?? "daily")
    let kind = rawKind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

    switch kind {
    case "daily", "everyday", "매일":
      let (hour, minute) = try time(from: object)
      return .daily(hour: hour, minute: minute)

    case "weekly", "매주":
      let (hour, minute) = try time(from: object)
      if let days = weekdays(from: object), !days.isEmpty {
        return .weekly(days: days, hour: hour, minute: minute)
      }
      guard let weekday = weekdayNumber(object["weekday"]), (1...7).contains(weekday) else {
        throw ParseError.badWeekday
      }
      return .weekly(days: [weekday], hour: hour, minute: minute)

    case "everyndays", "every_n_days", "every-n-days", "ndays", "n_days", "n-days",
         "everydays", "n일마다", "매n일":
      return try everyNDaysRule(object, kind: kind, now: now, calendar: calendar)

    case "interval", "window", "range", "구간", "구간 반복":
      return try intervalRule(object)

    case "once", "한번", "한 번", "one":
      guard let raw = object["date"] as? String ?? object["at"] as? String,
            let date = parseDate(raw, calendar: calendar) else {
        throw ParseError.badDate
      }
      guard date > now else { throw ParseError.pastDate }
      return .once(date)

    default:
      // "every2days" 처럼 숫자가 kind 안에 들어온 경우도 받는다.
      if kind.hasPrefix("every"), kind.hasSuffix("days"),
         let n = Int(kind.dropFirst("every".count).dropLast("days".count)
           .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))), n > 0 {
        return try everyNDaysRule(object, kind: kind, now: now, calendar: calendar)
      }
      throw ParseError.badKind(rawKind)
    }
  }

  private static func everyNDaysRule(_ object: [String: Any], kind: String,
                                     now: Date, calendar: Calendar) throws -> ScheduleRule {
    let count = everyNDaysCount(from: object, kind: kind) ?? 2
    guard (1...365).contains(count) else { throw ParseError.badDays }

    var hour = int(object["hour"])
    var minute = int(object["minute"])
    let rawAnchor = object["anchor"] as? String
      ?? object["firstDate"] as? String
      ?? object["first_date"] as? String
      ?? object["startDate"] as? String
      ?? object["start_date"] as? String
      ?? object["date"] as? String
    var anchor: Date
    if let rawAnchor, let parsed = parseDate(rawAnchor, calendar: calendar) {
      anchor = parsed
      if hour == nil { hour = calendar.component(.hour, from: parsed) }
      if minute == nil { minute = calendar.component(.minute, from: parsed) }
    } else {
      let h = hour ?? 9
      let m = minute ?? 0
      guard ScheduleRule.validTime(hour: h, minute: m) else { throw ParseError.badTime }
      anchor = firstFutureTime(now: now, hour: h, minute: m, calendar: calendar)
    }
    let h = hour ?? 9
    let m = minute ?? 0
    guard ScheduleRule.validTime(hour: h, minute: m) else { throw ParseError.badTime }
    return .everyNDays(days: count, hour: h, minute: m, anchor: anchor)
  }

  private static func intervalRule(_ object: [String: Any]) throws -> ScheduleRule {
    guard let start = clock(object["start"]) ?? clockFrom(object, prefix: "start"),
          let end = clock(object["end"]) ?? clockFrom(object, prefix: "end") else {
      throw ParseError.badInterval
    }
    let every = int(object["everyMinutes"])
      ?? int(object["every_minutes"])
      ?? int(object["intervalMinutes"])
      ?? int(object["interval_minutes"])
      ?? int(object["cadence"])
      ?? int(object["every"])
      ?? 60
    guard ScheduleRule.validInterval(startHour: start.0, startMinute: start.1,
                                     endHour: end.0, endMinute: end.1,
                                     everyMinutes: every) else {
      throw ParseError.badInterval
    }
    return .interval(startHour: start.0, startMinute: start.1,
                     endHour: end.0, endMinute: end.1, everyMinutes: every)
  }

  private static func time(from object: [String: Any]) throws -> (Int, Int) {
    let hour = int(object["hour"]) ?? 9
    let minute = int(object["minute"]) ?? 0
    guard ScheduleRule.validTime(hour: hour, minute: minute) else { throw ParseError.badTime }
    return (hour, minute)
  }

  // MARK: - 제외

  /// `skip` 인자 → `ScheduleSkip`.
  ///
  /// 받는 모양:
  /// - `{"weekends":true,"holidays":true,"extraDates":["2026-11-05"]}`
  /// - `["weekends","holidays","2026-11-05"]`
  public static func parseSkipObject(_ raw: Any?, calendar: Calendar = .current) -> ScheduleSkip {
    guard let raw else { return .none }
    var skip = ScheduleSkip.none
    if let object = raw as? [String: Any] {
      skip.weekends = bool(object["weekends"]) ?? bool(object["weekend"]) ?? false
      skip.holidays = bool(object["holidays"]) ?? bool(object["holiday"]) ?? false
      let dates = object["extraDates"] ?? object["extra_dates"]
        ?? object["dates"] ?? object["skipDates"] ?? object["skip_dates"]
      skip.extraDates = dateStrings(from: dates)
    } else if let list = raw as? [Any] {
      for item in list {
        if let flag = item as? Bool {
          // `{"weekends": true}` 같은 불리언 목록은 의미가 모호하므로 무시한다.
          _ = flag
        } else if let text = item as? String {
          let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
          if ["weekends", "weekend", "주말", "주말 제외"].contains(key) {
            skip.weekends = true
          } else if ["holidays", "holiday", "공휴일", "공휴일 제외"].contains(key) {
            skip.holidays = true
          } else {
            skip.extraDates += dateStrings(from: [text])
          }
        }
      }
    }
    return skip.normalized()
  }

  private static func dateStrings(from raw: Any?) -> [String] {
    guard let raw else { return [] }
    if let list = raw as? [String] { return list }
    if let list = raw as? [Any] {
      return list.compactMap { $0 as? String }
    }
    if let single = raw as? String {
      return single.split(whereSeparator: { ",; ".contains($0) }).map(String.init)
    }
    return []
  }

  // MARK: - 요일·시각

  private static func weekdays(from object: [String: Any]) -> [Int]? {
    let raw = object["days"] ?? object["weekdays"]
    guard let raw else { return nil }
    var out: [Int] = []
    if let list = raw as? [Any] {
      out = list.compactMap { weekdayNumber($0) }
    } else if let text = raw as? String {
      let separators = CharacterSet(charactersIn: ",·/ ")
      out = text.components(separatedBy: separators)
        .filter { !$0.isEmpty }
        .compactMap { weekdayNumber($0) }
    } else if let n = weekdayNumber(raw) {
      out = [n]
    }
    let unique = Array(Set(out)).sorted()
    return unique.isEmpty ? nil : unique
  }

  static func weekdayNumber(_ raw: Any?) -> Int? {
    if let n = raw as? Int { return n }
    if let d = raw as? Double { return Int(d) }
    guard let text = raw as? String else { return nil }
    let key = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if let n = Int(key) { return n }
    let names: [String: Int] = [
      "sun": 1, "sunday": 1, "일": 1, "일요일": 1,
      "mon": 2, "monday": 2, "월": 2, "월요일": 2,
      "tue": 3, "tues": 3, "tuesday": 3, "화": 3, "화요일": 3,
      "wed": 4, "wednesday": 4, "수": 4, "수요일": 4,
      "thu": 5, "thur": 5, "thurs": 5, "thursday": 5, "목": 5, "목요일": 5,
      "fri": 6, "friday": 6, "금": 6, "금요일": 6,
      "sat": 7, "saturday": 7, "토": 7, "토요일": 7
    ]
    return names[key]
  }

  /// "09:00" · `{"hour":9,"minute":0}` → (9, 0)
  private static func clock(_ raw: Any?) -> (Int, Int)? {
    guard let raw else { return nil }
    if let object = raw as? [String: Any] {
      guard let hour = int(object["hour"]), let minute = int(object["minute"]) else { return nil }
      return (hour, minute)
    }
    if let text = raw as? String {
      let parts = text.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: ":", omittingEmptySubsequences: false)
      guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
      return (hour, minute)
    }
    return nil
  }

  /// `startHour`·`startMinute` 처럼 나뉜 키 — 둘 다 있어야 한다.
  private static func clockFrom(_ object: [String: Any], prefix: String) -> (Int, Int)? {
    guard let hour = int(object[prefix + "Hour"] ?? object[prefix + "_hour"]),
          let minute = int(object[prefix + "Minute"] ?? object[prefix + "_minute"]) else {
      return nil
    }
    return (hour, minute)
  }

  private static func everyNDaysCount(from object: [String: Any], kind: String) -> Int? {
    for key in ["days", "n", "every", "intervalDays", "interval_days", "everyNDays"] {
      if let n = int(object[key]) { return n }
    }
    // kind = "every2days" / "every_2_days"
    guard kind.hasPrefix("every"), kind.hasSuffix("days") else { return nil }
    let middle = kind.dropFirst("every".count).dropLast("days".count)
      .trimmingCharacters(in: CharacterSet(charactersIn: "_- "))
    return Int(middle)
  }

  private static func firstFutureTime(now: Date, hour: Int, minute: Int,
                                      calendar: Calendar) -> Date {
    let today = calendar.startOfDay(for: now)
    let candidate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)
      ?? now
    if candidate > now { return candidate }
    return calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
  }

  // MARK: - 날짜

  /// ISO8601 · "yyyy-MM-dd HH:mm" · "yyyy-MM-dd'T'HH:mm" · epoch 초를 모두 받는다.
  public static func parseDate(_ raw: String, calendar: Calendar = .current) -> Date? {
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

  /// `persona` 인자(이름 또는 UUID) → (ID, 이름). `기본`·빈 값은 (nil, nil).
  public static func resolvePersona(_ raw: Any?,
                                    personas: [Persona]) throws -> (UUID?, String?) {
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
  static func clean(_ raw: String) -> String {
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

  static func int(_ value: Any?) -> Int? {
    if let n = value as? Int { return n }
    if let d = value as? Double { return Int(d) }
    if let s = value as? String { return Int(s) }
    return nil
  }

  private static func bool(_ value: Any?) -> Bool? {
    if let b = value as? Bool { return b }
    if let n = value as? Int { return n != 0 }
    if let s = value as? String {
      switch s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
      case "true", "yes", "1", "on", "예", "네": return true
      case "false", "no", "0", "off", "아니오": return false
      default: return nil
      }
    }
    return nil
  }
}
