import Foundation

/// 예약 반복 규칙 (v0.26).
///
/// 시간대는 **시스템 로컬**이고, 다음 시각 계산은 `Calendar` 를 주입받아 순수 함수로 유지한다
/// (테스트에서 서울·뉴욕 DST 를 고정할 수 있다).
public enum ScheduleRule: Codable, Equatable, Hashable {
  case daily(hour: Int, minute: Int)
  /// `weekday` 는 `Calendar` 규칙과 같다 — **1 = 일요일 … 7 = 토요일**.
  case weekly(weekday: Int, hour: Int, minute: Int)
  case once(Date)

  /// 따라잡기 허용 창 — 최근 24시간.
  public static let catchUpWindow: TimeInterval = 24 * 60 * 60

  // MARK: - 다음 실행 시각

  /// `date` **엄격히 이후**의 다음 실행 시각. 규칙이 잘못됐거나 한 번짜리가 지났으면 nil.
  public func next(after date: Date, calendar: Calendar = .current) -> Date? {
    switch self {
    case let .daily(hour, minute):
      guard Self.validTime(hour: hour, minute: minute) else { return nil }
      return calendar.nextDate(after: date,
                               matching: DateComponents(hour: hour, minute: minute),
                               matchingPolicy: .nextTime)
    case let .weekly(weekday, hour, minute):
      guard Self.validTime(hour: hour, minute: minute), (1...7).contains(weekday) else { return nil }
      return calendar.nextDate(after: date,
                               matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                               matchingPolicy: .nextTime)
    case let .once(fireAt):
      return fireAt > date ? fireAt : nil
    }
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
    case let .weekly(weekday, hour, minute):
      return c.weekday == weekday && c.hour == hour && c.minute == minute
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

  /// "매일 09:00" / "Every day at 09:00".
  public func humanDescription(calendar: Calendar = .current) -> String {
    switch self {
    case let .daily(hour, minute):
      return Lf("매일 %@", Self.timeText(hour: hour, minute: minute))
    case let .weekly(weekday, hour, minute):
      return Lf("매주 %@ %@", Self.weekdayName(weekday), Self.timeText(hour: hour, minute: minute))
    case let .once(fireAt):
      return Lf("한 번 · %@", Self.dateText(fireAt, calendar: calendar))
    }
  }

  /// 목록 칩에 쓰는 짧은 이름 — "매일" / "매주" / "한 번".
  public var frequencyLabel: String {
    switch self {
    case .daily: return L("매일")
    case .weekly: return L("매주")
    case .once: return L("한 번")
    }
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

  // MARK: - 검증

  public static func validTime(hour: Int, minute: Int) -> Bool {
    (0...23).contains(hour) && (0...59).contains(minute)
  }

  /// 시간·요일이 범위를 벗어난 규칙인가 — 저장 전 검증에 쓴다.
  public var isValid: Bool {
    switch self {
    case let .daily(hour, minute):
      return Self.validTime(hour: hour, minute: minute)
    case let .weekly(weekday, hour, minute):
      return Self.validTime(hour: hour, minute: minute) && (1...7).contains(weekday)
    case .once:
      return true
    }
  }

  // MARK: - Codable (태그 + 해당 필드만)

  private enum Kind: String, Codable { case daily, weekly, once }

  private enum CodingKeys: String, CodingKey {
    case kind, hour, minute, weekday, date
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    switch try c.decode(Kind.self, forKey: .kind) {
    case .daily:
      self = .daily(hour: try c.decode(Int.self, forKey: .hour),
                    minute: try c.decode(Int.self, forKey: .minute))
    case .weekly:
      self = .weekly(weekday: try c.decode(Int.self, forKey: .weekday),
                     hour: try c.decode(Int.self, forKey: .hour),
                     minute: try c.decode(Int.self, forKey: .minute))
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
    case let .weekly(weekday, hour, minute):
      try c.encode(Kind.weekly, forKey: .kind)
      try c.encode(weekday, forKey: .weekday)
      try c.encode(hour, forKey: .hour)
      try c.encode(minute, forKey: .minute)
    case let .once(date):
      try c.encode(Kind.once, forKey: .kind)
      try c.encode(date, forKey: .date)
    }
  }
}
