import Foundation

/// 예약 반복 규칙 (v0.27).
///
/// 시간대는 **시스템 로컬**이고, 다음 시각 계산은 `Calendar` 를 주입받아 순수 함수로 유지한다
/// (테스트에서 서울·뉴욕 DST 를 고정할 수 있다).
///
/// v0.27 추가: 요일 여러 개(`weekly(days:)`) · N일 간격(`everyNDays`) ·
/// 하루 구간 반복(`interval`). 기존 `daily`/`weekly(weekday:)`/`once` 는 그대로 읽힌다.
public enum ScheduleRule: Codable, Equatable, Hashable {
  case daily(hour: Int, minute: Int)
  /// `days` 는 `Calendar` 규칙과 같다 — **1 = 일요일 … 7 = 토요일**. 비어 있으면 무효.
  case weekly(days: [Int], hour: Int, minute: Int)
  /// `anchor` 가 첫 실행일 — 그 날짜에서 `days`일 간격으로 반복한다.
  case everyNDays(days: Int, hour: Int, minute: Int, anchor: Date)
  /// 같은 날 `start…`~`end…` 사이를 `everyMinutes` 간격으로 반복한다(양끝 포함).
  case interval(startHour: Int, startMinute: Int,
                endHour: Int, endMinute: Int, everyMinutes: Int)
  case once(Date)

  /// 따라잡기 허용 창 — 최근 24시간.
  public static let catchUpWindow: TimeInterval = 24 * 60 * 60

  /// 기존 호출부 호환 — 요일 하나짜리 매주.
  public static func weekly(weekday: Int, hour: Int, minute: Int) -> ScheduleRule {
    .weekly(days: [weekday], hour: hour, minute: minute)
  }

  // MARK: - 다음 실행 시각

  /// `date` **엄격히 이후**의 다음 실행 시각. 규칙이 잘못됐거나 한 번짜리가 지났으면 nil.
  public func next(after date: Date, calendar: Calendar = .current) -> Date? {
    switch self {
    case let .daily(hour, minute):
      guard Self.validTime(hour: hour, minute: minute) else { return nil }
      return calendar.nextDate(after: date,
                               matching: DateComponents(hour: hour, minute: minute),
                               matchingPolicy: .nextTime)

    case let .weekly(days, hour, minute):
      guard Self.validTime(hour: hour, minute: minute),
            !days.isEmpty,
            days.allSatisfy({ (1...7).contains($0) }) else { return nil }
      var best: Date?
      for weekday in Set(days) {
        guard let candidate = calendar.nextDate(
          after: date,
          matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
          matchingPolicy: .nextTime) else { continue }
        if best == nil || candidate < best! { best = candidate }
      }
      return best

    case let .everyNDays(days, hour, minute, anchor):
      guard (1...365).contains(days), Self.validTime(hour: hour, minute: minute) else { return nil }
      let anchorDay = calendar.startOfDay(for: anchor)
      let dateDay = calendar.startOfDay(for: date)
      var diff = calendar.dateComponents([.day], from: anchorDay, to: dateDay).day ?? 0
      if diff < 0 { diff = 0 }
      let remainder = diff % days
      if remainder != 0 { diff += days - remainder }
      var offset = diff
      for _ in 0..<400 {
        guard let day = calendar.date(byAdding: .day, value: offset, to: anchorDay),
              let candidate = calendar.date(bySettingHour: hour, minute: minute,
                                            second: 0, of: day) else { return nil }
        if candidate > date { return candidate }
        offset += days
      }
      return nil

    case let .interval(startHour, startMinute, endHour, endMinute, everyMinutes):
      guard Self.validInterval(startHour: startHour, startMinute: startMinute,
                               endHour: endHour, endMinute: endMinute,
                               everyMinutes: everyMinutes) else { return nil }
      let firstDay = calendar.startOfDay(for: date)
      for dayOffset in 0..<370 {
        guard let day = calendar.date(byAdding: .day, value: dayOffset, to: firstDay),
              let start = calendar.date(bySettingHour: startHour, minute: startMinute,
                                        second: 0, of: day),
              let end = calendar.date(bySettingHour: endHour, minute: endMinute,
                                      second: 0, of: day),
              end >= start else { continue }
        var slot = start
        var guardCount = 0
        while slot <= end && guardCount < 2_000 {
          if slot > date { return slot }
          guard let nextSlot = calendar.date(byAdding: .minute, value: everyMinutes, to: slot),
                nextSlot > slot else { break }
          slot = nextSlot
          guardCount += 1
        }
      }
      return nil

    case let .once(fireAt):
      return fireAt > date ? fireAt : nil
    }
  }

  /// 제외 규칙을 적용한 다음 실행 시각. 제외일은 **건너뛰고** 그 다음 유효 시각을 찾는다.
  public func next(after date: Date, calendar: Calendar = .current,
                   skip: ScheduleSkip) -> Date? {
    guard skip.isActive else { return next(after: date, calendar: calendar) }
    var cursor = date
    // 하루 7회짜리 구간 반복도 400회면 약 57일을 덮는다(연휴 최대치보다 넉넉하다).
    for _ in 0..<400 {
      guard let candidate = next(after: cursor, calendar: calendar) else { return nil }
      if !skip.isSkipped(candidate, calendar: calendar) { return candidate }
      cursor = candidate
    }
    return nil
  }

  /// 이미 지난 한 번짜리인가 — 목록에서 "만료" 표시에 쓴다.
  public func isExpired(now: Date) -> Bool {
    if case let .once(fireAt) = self { return fireAt <= now }
    return false
  }

  /// 이 시각이 규칙에 맞는가 — 테스트·디버그용.
  public func matches(_ date: Date, calendar: Calendar = .current) -> Bool {
    let c = calendar.dateComponents([.weekday, .hour, .minute], from: date)
    switch self {
    case let .daily(hour, minute):
      return c.hour == hour && c.minute == minute

    case let .weekly(days, hour, minute):
      return days.contains(c.weekday ?? 0) && c.hour == hour && c.minute == minute

    case let .everyNDays(days, hour, minute, anchor):
      guard (1...365).contains(days), c.hour == hour, c.minute == minute else { return false }
      let anchorDay = calendar.startOfDay(for: anchor)
      let dateDay = calendar.startOfDay(for: date)
      let diff = calendar.dateComponents([.day], from: anchorDay, to: dateDay).day ?? 0
      return diff >= 0 && diff % days == 0

    case let .interval(startHour, startMinute, endHour, endMinute, everyMinutes):
      guard Self.validInterval(startHour: startHour, startMinute: startMinute,
                               endHour: endHour, endMinute: endMinute,
                               everyMinutes: everyMinutes) else { return false }
      let day = calendar.startOfDay(for: date)
      guard let start = calendar.date(bySettingHour: startHour, minute: startMinute,
                                      second: 0, of: day),
            let end = calendar.date(bySettingHour: endHour, minute: endMinute,
                                    second: 0, of: day),
            date >= start, date <= end else { return false }
      let minutes = calendar.dateComponents([.minute], from: start, to: date).minute ?? -1
      return minutes >= 0 && minutes % everyMinutes == 0

    case let .once(fireAt):
      return calendar.compare(fireAt, to: date, toGranularity: .minute) == .orderedSame
    }
  }

  /// 놓친 1회를 지금 따라잡아도 되는가 — **정확히 24시간까지 허용**하고 1초라도 넘으면 아니다.
  /// 미래 시각이거나 시계가 뒤로 간 경우도 따라잡지 않는다.
  public static func shouldCatchUp(now: Date, scheduled: Date,
                                   window: TimeInterval = ScheduleRule.catchUpWindow) -> Bool {
    let delta = now.timeIntervalSince(scheduled)
    return delta >= 0 && delta <= window
  }

  // MARK: - 표시 문구

  /// "09:05" — 로캘과 무관하게 24시간 표기(오전/오후 혼동 방지).
  public static func timeText(hour: Int, minute: Int) -> String {
    String(format: "%02d:%02d", hour, minute)
  }

  /// "매일 09:00" / "매주 월·수·금 09:00" / "2일마다 09:00" / "매일 09:00~21:00 2시간마다".
  public func humanDescription(calendar: Calendar = .current) -> String {
    switch self {
    case let .daily(hour, minute):
      return Lf("매일 %@", Self.timeText(hour: hour, minute: minute))

    case let .weekly(days, hour, minute):
      let sorted = Array(Set(days)).sorted()
      let time = Self.timeText(hour: hour, minute: minute)
      if sorted.count == 1 {
        return Lf("매주 %@ %@", Self.weekdayName(sorted[0]), time)
      }
      let names = sorted.map { Self.weekdayShortName($0) }.joined(separator: "·")
      return Lf("매주 %@ %@", names, time)

    case let .everyNDays(days, hour, minute, _):
      return Lf("%d일마다 %@", days, Self.timeText(hour: hour, minute: minute))

    case let .interval(startHour, startMinute, endHour, endMinute, everyMinutes):
      let start = Self.timeText(hour: startHour, minute: startMinute)
      let end = Self.timeText(hour: endHour, minute: endMinute)
      return Lf("매일 %@~%@ %@", start, end, Self.cadenceText(minutes: everyMinutes))

    case let .once(fireAt):
      return Lf("한 번 · %@", Self.dateText(fireAt, calendar: calendar))
    }
  }

  /// 목록 칩에 쓰는 짧은 이름 — "매일" / "매주" / "2일마다" / "구간 반복" / "한 번".
  public var frequencyLabel: String {
    switch self {
    case .daily: return L("매일")
    case .weekly: return L("매주")
    case let .everyNDays(days, _, _, _): return Lf("%d일마다", days)
    case .interval: return L("구간 반복")
    case .once: return L("한 번")
    }
  }

  /// "2시간마다" / "30분마다".
  public static func cadenceText(minutes: Int) -> String {
    if minutes % 60 == 0 {
      return Lf("%d시간마다", minutes / 60)
    }
    return Lf("%d분마다", minutes)
  }

  /// "2026-11-04 15:00" — 파일 이름·요약 카드와 같은 표기.
  public static func dateText(_ date: Date, calendar: Calendar = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: date)
  }

  /// 1 = 일요일 … 7 = 토요일.
  public static func weekdayName(_ weekday: Int) -> String {
    let names = [L("일요일"), L("월요일"), L("화요일"), L("수요일"), L("목요일"), L("금요일"), L("토요일")]
    guard (1...7).contains(weekday) else { return "" }
    return names[weekday - 1]
  }

  /// 요일 칩용 짧은 이름 — "일" … "토".
  public static func weekdayShortName(_ weekday: Int) -> String {
    let names = [L("일"), L("월"), L("화"), L("수"), L("목"), L("금"), L("토")]
    guard (1...7).contains(weekday) else { return "" }
    return names[weekday - 1]
  }

  // MARK: - 검증

  public static func validTime(hour: Int, minute: Int) -> Bool {
    (0...23).contains(hour) && (0...59).contains(minute)
  }

  public static func validInterval(startHour: Int, startMinute: Int,
                                   endHour: Int, endMinute: Int,
                                   everyMinutes: Int) -> Bool {
    guard validTime(hour: startHour, minute: startMinute),
          validTime(hour: endHour, minute: endMinute) else { return false }
    let start = startHour * 60 + startMinute
    let end = endHour * 60 + endMinute
    return end > start && (5...720).contains(everyMinutes) && everyMinutes <= end - start
  }

  /// 시간·요일이 범위를 벗어난 규칙인가 — 저장 전 검증에 쓴다.
  public var isValid: Bool {
    switch self {
    case let .daily(hour, minute):
      return Self.validTime(hour: hour, minute: minute)
    case let .weekly(days, hour, minute):
      return Self.validTime(hour: hour, minute: minute)
        && !days.isEmpty
        && days.allSatisfy { (1...7).contains($0) }
        && Set(days).count == days.count
    case let .everyNDays(days, hour, minute, _):
      return (1...365).contains(days) && Self.validTime(hour: hour, minute: minute)
    case let .interval(startHour, startMinute, endHour, endMinute, everyMinutes):
      return Self.validInterval(startHour: startHour, startMinute: startMinute,
                                endHour: endHour, endMinute: endMinute,
                                everyMinutes: everyMinutes)
    case .once:
      return true
    }
  }

  // MARK: - Codable (태그 + 해당 필드만)

  private enum Kind: String, Codable { case daily, weekly, everyNDays, interval, once }

  private enum CodingKeys: String, CodingKey {
    case kind, hour, minute, weekday, days, anchor
    case startHour, startMinute, endHour, endMinute, everyMinutes, date
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .daily:
      self = .daily(hour: try c.decode(Int.self, forKey: .hour),
                    minute: try c.decode(Int.self, forKey: .minute))
    case .weekly:
      let hour = try c.decode(Int.self, forKey: .hour)
      let minute = try c.decode(Int.self, forKey: .minute)
      if let days = try c.decodeIfPresent([Int].self, forKey: .days) {
        self = .weekly(days: days, hour: hour, minute: minute)
      } else {
        self = .weekly(days: [try c.decode(Int.self, forKey: .weekday)],
                       hour: hour, minute: minute)
      }
    case .everyNDays:
      self = .everyNDays(days: try c.decode(Int.self, forKey: .days),
                         hour: try c.decode(Int.self, forKey: .hour),
                         minute: try c.decode(Int.self, forKey: .minute),
                         anchor: try c.decodeIfPresent(Date.self, forKey: .anchor) ?? Date())
    case .interval:
      self = .interval(startHour: try c.decode(Int.self, forKey: .startHour),
                       startMinute: try c.decode(Int.self, forKey: .startMinute),
                       endHour: try c.decode(Int.self, forKey: .endHour),
                       endMinute: try c.decode(Int.self, forKey: .endMinute),
                       everyMinutes: try c.decode(Int.self, forKey: .everyMinutes))
    case .once:
      self = .once(try c.decode(Date.self, forKey: .date))
    }
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .daily(hour, minute):
      try c.encode(Kind.daily, forKey: .kind)
      try c.encode(hour, forKey: .hour)
      try c.encode(minute, forKey: .minute)
    case let .weekly(days, hour, minute):
      try c.encode(Kind.weekly, forKey: .kind)
      try c.encode(Array(Set(days)).sorted(), forKey: .days)
      try c.encode(hour, forKey: .hour)
      try c.encode(minute, forKey: .minute)
    case let .everyNDays(days, hour, minute, anchor):
      try c.encode(Kind.everyNDays, forKey: .kind)
      try c.encode(days, forKey: .days)
      try c.encode(hour, forKey: .hour)
      try c.encode(minute, forKey: .minute)
      try c.encode(anchor, forKey: .anchor)
    case let .interval(startHour, startMinute, endHour, endMinute, everyMinutes):
      try c.encode(Kind.interval, forKey: .kind)
      try c.encode(startHour, forKey: .startHour)
      try c.encode(startMinute, forKey: .startMinute)
      try c.encode(endHour, forKey: .endHour)
      try c.encode(endMinute, forKey: .endMinute)
      try c.encode(everyMinutes, forKey: .everyMinutes)
    case let .once(date):
      try c.encode(Kind.once, forKey: .kind)
      try c.encode(date, forKey: .date)
    }
  }
}

// MARK: - 제외 규칙

/// 예약 실행에서 **건너뛸 날** (v0.27).
///
/// - `weekends`: 토·일
/// - `holidays`: 대한민국 공휴일 자동(양력·음력·대체공휴일)
/// - `extraDates`: 사용자가 직접 추가한 `yyyy-MM-dd` (임시공휴일·회사 휴무일)
public struct ScheduleSkip: Codable, Equatable, Hashable {
  public var weekends: Bool
  public var holidays: Bool
  public var extraDates: [String]

  public init(weekends: Bool = false, holidays: Bool = false, extraDates: [String] = []) {
    self.weekends = weekends
    self.holidays = holidays
    self.extraDates = extraDates
  }

  public static let none = ScheduleSkip()

  public var isActive: Bool {
    weekends || holidays || !extraDates.isEmpty
  }

  /// 저장 직전 정규화 — 잘못된 날짜를 버리고, 중복을 없애고, 오름차순으로 정렬한다.
  public func normalized() -> ScheduleSkip {
    var seen = Set<String>()
    let cleaned = extraDates.compactMap { Self.normalizedDayKey($0) }
      .filter { seen.insert($0).inserted }
      .sorted()
    return ScheduleSkip(weekends: weekends, holidays: holidays, extraDates: cleaned)
  }

  public func isSkipped(_ date: Date, calendar: Calendar = .current) -> Bool {
    if weekends {
      let weekday = calendar.component(.weekday, from: date)
      if weekday == 1 || weekday == 7 { return true }
    }
    if holidays, KoreanHolidays.isHoliday(date, calendar: calendar) { return true }
    if !extraDates.isEmpty {
      return extraDates.contains(Self.dayKey(date, calendar: calendar))
    }
    return false
  }

  /// "주말·공휴일 제외 · 특정 날짜 2개 제외" — 없으면 nil.
  public func humanDescription() -> String? {
    var parts: [String] = []
    if weekends && holidays {
      parts.append(L("주말·공휴일 제외"))
    } else if weekends {
      parts.append(L("주말 제외"))
    } else if holidays {
      parts.append(L("공휴일 제외"))
    }
    if !extraDates.isEmpty {
      parts.append(Lf("특정 날짜 %d개 제외", extraDates.count))
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  // MARK: - 날짜 키

  public static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
  }

  /// `yyyy-MM-dd` 만 받는다. 실제로 존재하는 날짜인지까지 확인한다.
  public static func normalizedDayKey(_ raw: String,
                                      calendar: Calendar = .current) -> String? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let parts = text.split(separator: "-", omittingEmptySubsequences: false)
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          (1900...2200).contains(year), (1...12).contains(month), (1...31).contains(day) else {
      return nil
    }
    guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
      return nil
    }
    let check = calendar.dateComponents([.year, .month, .day], from: date)
    guard check.year == year, check.month == month, check.day == day else { return nil }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }

  // 구버전/미래 파일에 키가 없어도 읽는다.
  private enum CodingKeys: String, CodingKey { case weekends, holidays, extraDates }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    weekends = try c.decodeIfPresent(Bool.self, forKey: .weekends) ?? false
    holidays = try c.decodeIfPresent(Bool.self, forKey: .holidays) ?? false
    extraDates = try c.decodeIfPresent([String].self, forKey: .extraDates) ?? []
  }
}

// MARK: - 대한민국 공휴일

/// 대한민국 공휴일 계산 (v0.27).
///
/// 양력 고정 공휴일 + 음력(설날·추석 연휴, 부처님오신날) + 대체공휴일을 계산한다.
/// **임시공휴일·선거일은 계산하지 않는다** — 사용자가 `ScheduleSkip.extraDates` 로 추가한다.
///
/// 음력은 `Foundation.Calendar(.chinese)` 로 구한다(서울 시간대). 결과는 연도별로 캐시한다.
public enum KoreanHolidays {
  private static let lock = NSLock()
  private static var cache: [Int: Set<String>] = [:]

  private static let seoul: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
  }()

  private static let lunar: Calendar = {
    var c = Calendar(identifier: .chinese)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
  }()

  public static func isHoliday(_ date: Date, calendar: Calendar = .current) -> Bool {
    let year = calendar.component(.year, from: date)
    return dates(inYear: year).contains(ScheduleSkip.dayKey(date, calendar: calendar))
  }

  /// 그 해의 공휴일 날짜 키(`yyyy-MM-dd`, 서울 기준 날짜 라벨) 집합.
  public static func dates(inYear year: Int) -> Set<String> {
    lock.lock()
    let cached = cache[year]
    lock.unlock()
    if let cached { return cached }

    let computed = compute(year)
    lock.lock()
    cache[year] = computed
    lock.unlock()
    return computed
  }

  // MARK: 계산

  private static func compute(_ year: Int) -> Set<String> {
    guard (1900...2100).contains(year) else { return fixedHolidays(year) }

    var set = fixedHolidays(year)
    var counts: [String: Int] = [:]
    for key in set { counts[key, default: 0] += 1 }

    func add(_ date: Date) {
      let key = key(date)
      set.insert(key)
      counts[key, default: 0] += 1
    }

    let buddha = lunarDate(year: year, lunarMonth: 4, lunarDay: 8)
    let seollal = lunarDate(year: year, lunarMonth: 1, lunarDay: 1)
    let chuseok = lunarDate(year: year, lunarMonth: 8, lunarDay: 15)

    if let buddha { add(buddha) }

    var blocks: [(days: [Date], start: Date, end: Date)] = []
    if let seollal {
      let days = [-1, 0, 1].map { addDays(seollal, $0) }
      for day in days { add(day) }
      blocks.append((days, days[0], days[2]))
    }
    if let chuseok {
      let days = [-1, 0, 1].map { addDays(chuseok, $0) }
      for day in days { add(day) }
      blocks.append((days, days[0], days[2]))
    }

    struct Candidate {
      let start: Date
      let end: Date
      let days: [Date]
      let kind: Kind
      enum Kind { case lunarBlock, children, weekendOnly }
    }

    var candidates: [Candidate] = blocks.map {
      Candidate(start: $0.start, end: $0.end, days: $0.days, kind: .lunarBlock)
    }
    let children = makeDate(year: year, month: 5, day: 5)
    candidates.append(Candidate(start: children, end: children,
                                days: [children], kind: .children))
    for (month, day) in [(3, 1), (8, 15), (10, 3), (10, 9), (12, 25)] {
      let date = makeDate(year: year, month: month, day: day)
      candidates.append(Candidate(start: date, end: date,
                                  days: [date], kind: .weekendOnly))
    }
    if let buddha {
      candidates.append(Candidate(start: buddha, end: buddha,
                                  days: [buddha], kind: .weekendOnly))
    }
    candidates.sort { $0.start < $1.start }

    var handled = Set<String>()
    for candidate in candidates {
      if candidate.days.allSatisfy({ handled.contains(key($0)) }) { continue }
      let needsSubstitute: Bool
      switch candidate.kind {
      case .lunarBlock:
        needsSubstitute = candidate.days.contains {
          weekday($0) == 1 || counts[key($0), default: 0] > 1
        }
      case .children:
        needsSubstitute = candidate.days.contains {
          isWeekend($0) || counts[key($0), default: 0] > 1
        }
      case .weekendOnly:
        needsSubstitute = candidate.days.contains { isWeekend($0) }
      }
      guard needsSubstitute else { continue }

      var substitute = addDays(candidate.end, 1)
      var guardCount = 0
      while (set.contains(key(substitute)) || isWeekend(substitute)) && guardCount < 60 {
        substitute = addDays(substitute, 1)
        guardCount += 1
      }
      add(substitute)
      for day in candidate.days { handled.insert(key(day)) }
      handled.insert(key(substitute))
    }

    return set
  }

  private static func fixedHolidays(_ year: Int) -> Set<String> {
    let dates = [(1, 1), (3, 1), (5, 5), (6, 6), (8, 15), (10, 3), (10, 9), (12, 25)]
    return Set(dates.map { key(makeDate(year: year, month: $0.0, day: $0.1)) })
  }

  /// 음력 `month/day` 에 해당하는 양력 날짜를 그 해에서 찾는다(윤달 제외).
  private static func lunarDate(year: Int, lunarMonth: Int, lunarDay: Int) -> Date? {
    for month in 1...12 {
      for day in 1...31 {
        guard let date = seoul.date(from: DateComponents(year: year, month: month, day: day)) else {
          continue
        }
        let c = lunar.dateComponents([.month, .day, .isLeapMonth], from: date)
        if c.month == lunarMonth, c.day == lunarDay, c.isLeapMonth != true {
          return date
        }
      }
    }
    return nil
  }

  private static func makeDate(year: Int, month: Int, day: Int) -> Date {
    seoul.date(from: DateComponents(year: year, month: month, day: day)) ?? Date()
  }

  private static func addDays(_ date: Date, _ days: Int) -> Date {
    seoul.date(byAdding: .day, value: days, to: date) ?? date
  }

  private static func key(_ date: Date) -> String {
    ScheduleSkip.dayKey(date, calendar: seoul)
  }

  private static func weekday(_ date: Date) -> Int {
    seoul.component(.weekday, from: date)
  }

  private static func isWeekend(_ date: Date) -> Bool {
    let w = weekday(date)
    return w == 1 || w == 7
  }
}
