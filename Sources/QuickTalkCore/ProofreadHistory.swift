import Foundation
import Combine

// 입력 교정 기록 — 오타 노트·통계의 정본.
//
// 프라이버시(PLAN_v0.41 §9.3):
//   · **문장 전체를 저장하지 않는다.** 틀린 구간·고친 구간·분류만.
//   · 이 Mac 안에만(`~/Library/Application Support/QuickTalk/proofread.json`), 90일 뒤 자동 삭제.
//   · 로그에는 개수만 남기고 원문은 남기지 않는다.
//
// 스레드: UIStore(메인)에서만 읽고 쓴다. 파일 쓰기는 원자적이며 실패해도 앱 동작을 막지 않는다.

/// 오타 노트 목록 한 줄 — 한 번의 교정 후보.
public struct ProofreadEntry: Codable, Identifiable, Equatable, Sendable {
  public var id: UUID
  public var at: Date
  public var category: ProofreadCategory
  public var original: String
  public var replacement: String
  public var accepted: Bool
  public var ruleID: String
  /// "composer" | "pill"
  public var source: String

  public init(id: UUID = UUID(), at: Date = Date(),
              category: ProofreadCategory, original: String, replacement: String,
              accepted: Bool = false, ruleID: String, source: String) {
    self.id = id
    self.at = at
    self.category = category
    self.original = original
    self.replacement = replacement
    self.accepted = accepted
    self.ruleID = ruleID
    self.source = source
  }
}

/// 하루 단위 카운터 — 차트·요약의 분모/분자.
public struct ProofreadDay: Codable, Identifiable, Equatable, Sendable {
  /// "yyyy-MM-dd" (로컬 시간)
  public var day: String
  public var checks: Int
  public var hints: Int
  public var accepted: Int
  public var asIs: Int
  public var dismissed: Int

  public var id: String { day }

  public init(day: String, checks: Int = 0, hints: Int = 0,
              accepted: Int = 0, asIs: Int = 0, dismissed: Int = 0) {
    self.day = day
    self.checks = checks
    self.hints = hints
    self.accepted = accepted
    self.asIs = asIs
    self.dismissed = dismissed
  }
}

/// `proofread.json` 한 파일의 내용.
public struct ProofreadData: Codable, Equatable, Sendable {
  public static let currentVersion = 1

  public var version: Int
  public var entries: [ProofreadEntry]
  public var daily: [ProofreadDay]
  public var ignored: [String]

  public init(version: Int = ProofreadData.currentVersion,
              entries: [ProofreadEntry] = [],
              daily: [ProofreadDay] = [],
              ignored: [String] = []) {
    self.version = version
    self.entries = entries
    self.daily = daily
    self.ignored = ignored
  }

  private enum CodingKeys: String, CodingKey {
    case version, entries, daily, ignored
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
    entries = try c.decodeIfPresent([ProofreadEntry].self, forKey: .entries) ?? []
    daily = try c.decodeIfPresent([ProofreadDay].self, forKey: .daily) ?? []
    ignored = try c.decodeIfPresent([String].self, forKey: .ignored) ?? []
  }
}

/// 한 번의 검사에 대한 영수증 — 사용자가 [교정]/[그대로]/[닫기] 중 무엇을 골랐는지 나중에 붙인다.
public struct ProofreadRecordToken: Equatable, Sendable {
  public let day: String
  public let entryIDs: [UUID]
  public let hinted: Bool
}

/// 기간별 요약 — 발생률·교정률은 **분모가 0이면 nil**.
public struct ProofreadSummary: Equatable, Sendable {
  public let checks: Int
  public let hints: Int
  public let accepted: Int
  public let asIs: Int
  public let dismissed: Int

  public var occurrenceRate: Double? { checks > 0 ? Double(hints) / Double(checks) : nil }
  public var acceptanceRate: Double? { hints > 0 ? Double(accepted) / Double(hints) : nil }
  public var isLowSample: Bool { checks < ProofreadHistory.lowSampleThreshold }
}

/// 주별 차트 한 점(7일 묶음, 오늘에서 거꾸로).
public struct ProofreadWeekPoint: Identifiable, Equatable, Sendable {
  public let start: Date
  public let end: Date
  public let checks: Int
  public let hints: Int
  public var id: Date { start }
}

/// 자주 틀리는 표현 한 줄.
public struct ProofreadExpression: Identifiable, Equatable, Sendable {
  public let original: String
  public let replacement: String
  public let category: ProofreadCategory
  public let count: Int
  public let accepted: Int
  public let lastSeen: Date

  public var id: String { "\(original)→\(replacement)" }
  public var acceptanceRate: Double? { count > 0 ? Double(accepted) / Double(count) : nil }
}

// MARK: - 저장소

public final class ProofreadHistory: ObservableObject {
  /// 보존 기간 — 이보다 오래된 구간 기록은 지운다.
  public static let retentionDays = 90
  /// 일별 카운터 보존 — 차트·연간 비교용으로 조금 더 남긴다.
  public static let dailyRetentionDays = 400
  /// 파일이 무한정 커지지 않게.
  public static let maximumEntries = 2_000
  /// 표본이 이보다 적으면 비율 카드에 "표본이 적어요"를 붙인다.
  public static let lowSampleThreshold = 20

  public static var defaultFileURL: URL? {
    PersistenceService.directory.appendingPathComponent("proofread.json")
  }

  @Published public private(set) var data: ProofreadData
  /// nil 이면 메모리 전용(테스트).
  private let fileURL: URL?
  private let now: () -> Date
  private var calendar: Calendar

  public init(fileURL: URL? = ProofreadHistory.defaultFileURL,
              now: @escaping () -> Date = Date.init,
              calendar: Calendar = .current) {
    self.fileURL = fileURL
    self.now = now
    self.calendar = calendar
    if let fileURL,
       let raw = try? Data(contentsOf: fileURL),
       let decoded = try? ProofreadHistory.decoder.decode(ProofreadData.self, from: raw) {
      self.data = decoded
    } else {
      self.data = ProofreadData()
    }
    let changed = prune()
    if changed && fileURL != nil { save() }
  }

  /// 테스트용 — 데이터를 직접 넣고 시작한다(파일을 쓰지 않는다).
  public init(data: ProofreadData, now: @escaping () -> Date = Date.init,
              calendar: Calendar = .current) {
    self.fileURL = nil
    self.now = now
    self.calendar = calendar
    self.data = data
    _ = prune()
  }

  // MARK: 읽기

  public var ignored: Set<String> { Set(data.ignored) }

  public func isIgnored(_ original: String) -> Bool { data.ignored.contains(original) }

  public func summary(days: Int = 30) -> ProofreadSummary {
    let cutoff = dayKey(daysAgo: max(0, days - 1))
    let rows = data.daily.filter { $0.day >= cutoff }
    return ProofreadSummary(checks: rows.reduce(0) { $0 + $1.checks },
                            hints: rows.reduce(0) { $0 + $1.hints },
                            accepted: rows.reduce(0) { $0 + $1.accepted },
                            asIs: rows.reduce(0) { $0 + $1.asIs },
                            dismissed: rows.reduce(0) { $0 + $1.dismissed })
  }

  /// 오래된 것 → 최신 순서로 7일 묶음 `weeks` 개(마지막이 오늘까지).
  public func weekly(weeks: Int = 8) -> [ProofreadWeekPoint] {
    guard weeks > 0 else { return [] }
    let today = calendar.startOfDay(for: now())
    return (0..<weeks).reversed().compactMap { offset -> ProofreadWeekPoint? in
      guard let end = calendar.date(byAdding: .day, value: -offset * 7, to: today),
            let start = calendar.date(byAdding: .day, value: -6, to: end) else { return nil }
      let startKey = dayKey(for: start)
      let endKey = dayKey(for: end)
      let rows = data.daily.filter { $0.day >= startKey && $0.day <= endKey }
      return ProofreadWeekPoint(start: start, end: end,
                                checks: rows.reduce(0) { $0 + $1.checks },
                                hints: rows.reduce(0) { $0 + $1.hints })
    }
  }

  public func expressions(days: Int = 30, limit: Int = 20) -> [ProofreadExpression] {
    guard limit > 0 else { return [] }
    let cutoff = cutoffDate(daysAgo: max(0, days - 1))
    var grouped: [String: (entry: ProofreadEntry, count: Int, accepted: Int, last: Date)] = [:]
    for entry in data.entries where entry.at >= cutoff {
      let key = "\(entry.original)→\(entry.replacement)"
      if var existing = grouped[key] {
        existing.count += 1
        existing.accepted += entry.accepted ? 1 : 0
        if entry.at > existing.last {
          existing.last = entry.at
          existing.entry = entry
        }
        grouped[key] = existing
      } else {
        grouped[key] = (entry, 1, entry.accepted ? 1 : 0, entry.at)
      }
    }
    return grouped.values
      .sorted {
        if $0.count != $1.count { return $0.count > $1.count }
        return $0.last > $1.last
      }
      .prefix(limit)
      .map {
        ProofreadExpression(original: $0.entry.original,
                            replacement: $0.entry.replacement,
                            category: $0.entry.category,
                            count: $0.count, accepted: $0.accepted,
                            lastSeen: $0.last)
      }
  }

  /// 기간 내 발견 횟수 — 카테고리 칩.
  public func categoryCounts(days: Int = 30) -> [(category: ProofreadCategory, count: Int)] {
    let cutoff = cutoffDate(daysAgo: max(0, days - 1))
    var counts: [ProofreadCategory: Int] = [:]
    for entry in data.entries where entry.at >= cutoff {
      counts[entry.category, default: 0] += 1
    }
    return ProofreadCategory.allCases.map { ($0, counts[$0] ?? 0) }
  }

  // MARK: 쓰기

  /// 메시지 한 건을 검사했다 — `hinted` 면 발견한 구간도 함께 기록한다.
  @discardableResult
  public func recordCheck(hinted: Bool, issues: [ProofreadIssue],
                          source: String) -> ProofreadRecordToken {
    let date = now()
    let key = dayKey(for: date)
    var row = data.daily.first(where: { $0.day == key })
      ?? ProofreadDay(day: key)
    row.checks += 1
    if hinted { row.hints += 1 }
    data.daily.removeAll { $0.day == key }
    data.daily.append(row)
    data.daily.sort { $0.day < $1.day }

    var ids: [UUID] = []
    if hinted {
      for issue in issues.prefix(20) {
        let entry = ProofreadEntry(at: date, category: issue.category,
                                   original: issue.original,
                                   replacement: issue.replacement,
                                   accepted: false, ruleID: issue.ruleID,
                                   source: source)
        ids.append(entry.id)
        data.entries.append(entry)
      }
    }
    trim()
    save()
    return ProofreadRecordToken(day: key, entryIDs: ids, hinted: hinted)
  }

  /// [교정해서 보내기]
  public func recordAccepted(_ token: ProofreadRecordToken) {
    adjust(token, accepted: 1)
    let ids = Set(token.entryIDs)
    if !ids.isEmpty {
      for i in data.entries.indices where ids.contains(data.entries[i].id) {
        data.entries[i].accepted = true
      }
    }
    save()
  }

  /// [그대로 보내기]
  public func recordAsIs(_ token: ProofreadRecordToken) {
    adjust(token, asIs: 1)
    save()
  }

  /// 카드 닫기(Esc·×) — 입력으로 돌아가 스스로 고친다.
  public func recordDismissed(_ token: ProofreadRecordToken) {
    adjust(token, dismissed: 1)
    save()
  }

  public func ignore(_ original: String) {
    let value = original.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty, !data.ignored.contains(value) else { return }
    data.ignored.append(value)
    save()
  }

  public func unignore(_ original: String) {
    data.ignored.removeAll { $0 == original }
    save()
  }

  /// 무시한 표현을 모두 되돌린다 — 오타 노트의 [모두 해제].
  public func unignoreAll() {
    guard !data.ignored.isEmpty else { return }
    data.ignored.removeAll()
    save()
  }

  public func clearAll() {
    data = ProofreadData()
    save()
  }

  // MARK: 정리

  /// 90일 지난 구간·400일 지난 카운터·2,000개 초과분을 지운다. 바뀌었으면 true.
  @discardableResult
  public func prune() -> Bool {
    let oldEntries = data.entries
    let oldDaily = data.daily
    let entryCutoff = cutoffDate(daysAgo: ProofreadHistory.retentionDays)
    let dayCutoff = dayKey(daysAgo: ProofreadHistory.dailyRetentionDays)
    data.entries.removeAll { $0.at < entryCutoff }
    data.daily.removeAll { $0.day < dayCutoff }
    if data.entries.count > ProofreadHistory.maximumEntries {
      // 배열 순서에 기대지 않는다 — 최신 것만 남긴다.
      data.entries = Array(data.entries.sorted { $0.at < $1.at }
        .suffix(ProofreadHistory.maximumEntries))
    }
    return data.entries != oldEntries || data.daily != oldDaily
  }

  // MARK: 내부

  private func adjust(_ token: ProofreadRecordToken, accepted: Int = 0,
                      asIs: Int = 0, dismissed: Int = 0) {
    guard let index = data.daily.firstIndex(where: { $0.day == token.day }) else { return }
    data.daily[index].accepted += accepted
    data.daily[index].asIs += asIs
    data.daily[index].dismissed += dismissed
  }

  private func trim() {
    prune()
  }

  private func save() {
    guard let fileURL else { return }
    do {
      let data = try ProofreadHistory.encoder.encode(data)
      try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                              withIntermediateDirectories: true)
      try data.write(to: fileURL, options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                             ofItemAtPath: fileURL.path)
    } catch {
      NSLog("[QuickTalk] 오타 노트 저장 실패: %@", error.localizedDescription)
    }
  }

  private func dayKey(daysAgo: Int) -> String {
    dayKey(for: cutoffDate(daysAgo: daysAgo))
  }

  private func cutoffDate(daysAgo: Int) -> Date {
    let start = calendar.startOfDay(for: now())
    return calendar.date(byAdding: .day, value: -max(0, daysAgo), to: start) ?? start
  }

  private func dayKey(for date: Date) -> String {
    let c = calendar.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
  }

  private static let encoder: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return e
  }()

  private static let decoder: JSONDecoder = {
    let d = JSONDecoder()
    d.dateDecodingStrategy = .iso8601
    return d
  }()
}
