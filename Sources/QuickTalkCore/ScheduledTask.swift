import Foundation

/// 실행 1회의 상태 (v0.26).
public enum RunStatus: String, Codable, CaseIterable, Equatable, Hashable {
  case running
  case succeeded
  case failed
  case awaitingApproval
  case cancelled
  case missed
  case interrupted

  /// 사용자가 다시 누를 것이 없는 상태인가.
  public var isTerminal: Bool {
    switch self {
    case .running, .awaitingApproval: return false
    case .succeeded, .failed, .cancelled, .missed, .interrupted: return true
    }
  }

  /// 목록 상태 점 색상 이름 — 뷰가 색으로 옮긴다.
  public enum Tone: String { case ok, warn, error, idle }
  public var tone: Tone {
    switch self {
    case .succeeded: return .ok
    case .awaitingApproval, .running: return .warn
    case .failed, .interrupted: return .error
    case .cancelled, .missed: return .idle
    }
  }
}

/// 실행을 누가 시작했는가 — "지금 실행"은 예약 시각을 앞당기지 않는다.
public enum RunTrigger: String, Codable, Equatable, Hashable {
  case scheduled
  case manual
}

/// 실행 1회의 기록. 최근 30건만 남긴다.
public struct RunRecord: Codable, Identifiable, Equatable, Hashable {
  public var id: UUID
  public var startedAt: Date
  public var finishedAt: Date?
  public var status: RunStatus
  /// 저장된 Markdown 리포트 경로(성공 시)
  public var filePath: String?
  /// 핵심 2~3줄 — 대화 요약 카드에 그대로 쓴다.
  public var summary: String?
  public var failureReason: String?
  public var trigger: RunTrigger

  public init(id: UUID = UUID(), startedAt: Date = Date(), finishedAt: Date? = nil,
              status: RunStatus = .running, filePath: String? = nil, summary: String? = nil,
              failureReason: String? = nil, trigger: RunTrigger = .scheduled) {
    self.id = id
    self.startedAt = startedAt
    self.finishedAt = finishedAt
    self.status = status
    self.filePath = filePath
    self.summary = summary
    self.failureReason = failureReason
    self.trigger = trigger
  }

  public var duration: TimeInterval? {
    guard let finishedAt else { return nil }
    return max(0, finishedAt.timeIntervalSince(startedAt))
  }

  // 구버전/미래 기록에 키가 없어도 읽는다.
  private enum CodingKeys: String, CodingKey {
    case id, startedAt, finishedAt, status, filePath, summary, failureReason, trigger
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt) ?? Date()
    finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    status = try c.decodeIfPresent(RunStatus.self, forKey: .status) ?? .failed
    filePath = try c.decodeIfPresent(String.self, forKey: .filePath)
    summary = try c.decodeIfPresent(String.self, forKey: .summary)
    failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
    trigger = try c.decodeIfPresent(RunTrigger.self, forKey: .trigger) ?? .scheduled
  }
}

/// 예약 작업 하나 (v0.26).
///
/// `personaID == nil` 은 **기본(비서 없음)** — 지금과 같은 프롬프트로 실행되고
/// 리포트 작성자만 `QuickTalk` 이 된다.
public struct ScheduledTask: Codable, Identifiable, Equatable {
  /// 이력 상한 — 무한히 자라지 않게.
  public static let historyLimit = 30

  public var id: UUID
  public var personaID: UUID?
  public var title: String
  /// 실제 지시문 — 매번 **그대로** 실행된다.
  public var instruction: String
  public var rule: ScheduleRule
  /// 건너뛸 날 (v0.27) — 주말·공휴일·직접 지정한 날짜.
  public var skip: ScheduleSkip
  public var enabled: Bool
  public var nextFireAt: Date?
  public var lastRun: RunRecord?
  /// 최근 실행 기록(오래된 것 → 새 것).
  public var history: [RunRecord]
  public var createdAt: Date
  /// 결과 카드를 남길 대화 — nil 이면 실행할 때 비서 전용 대화를 만든다.
  public var conversationID: UUID?

  public init(id: UUID = UUID(), personaID: UUID? = nil, title: String, instruction: String,
              rule: ScheduleRule, skip: ScheduleSkip = .none,
              enabled: Bool = true, nextFireAt: Date? = nil,
              lastRun: RunRecord? = nil, history: [RunRecord] = [], createdAt: Date = Date(),
              conversationID: UUID? = nil) {
    self.id = id
    self.personaID = personaID
    self.title = title
    self.instruction = instruction
    self.rule = rule
    self.skip = skip
    self.enabled = enabled
    self.nextFireAt = nextFireAt
    self.lastRun = lastRun
    self.history = history
    self.createdAt = createdAt
    self.conversationID = conversationID
  }

  // 새 키(history·nextFireAt·skip)가 없어도 읽는다.
  private enum CodingKeys: String, CodingKey {
    case id, personaID, title, instruction, rule, skip, enabled, nextFireAt, lastRun, history,
         createdAt, conversationID
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    personaID = try c.decodeIfPresent(UUID.self, forKey: .personaID)
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
    rule = try c.decode(ScheduleRule.self, forKey: .rule)
    skip = try c.decodeIfPresent(ScheduleSkip.self, forKey: .skip) ?? .none
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    nextFireAt = try c.decodeIfPresent(Date.self, forKey: .nextFireAt)
    lastRun = try c.decodeIfPresent(RunRecord.self, forKey: .lastRun)
    history = try c.decodeIfPresent([RunRecord].self, forKey: .history) ?? []
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    conversationID = try c.decodeIfPresent(UUID.self, forKey: .conversationID)
  }

  // MARK: - 상태

  public var isExpired: Bool { rule.isExpired(now: Date()) }

  /// 지금 실행해야 하는가 — 24시간을 넘긴 것은 `SchedulePlanner` 가 `missed` 로 보낸다.
  public func isDue(now: Date) -> Bool {
    guard enabled, let nextFireAt else { return false }
    return nextFireAt <= now
  }

  /// 저장 직전 정규화 — 제목·지시문 공백 정리, 빈 제목 방지, 제외 날짜 정리.
  public func normalized() -> ScheduledTask {
    var t = self
    t.title = Self.clean(title, limit: 60)
    if t.title.isEmpty { t.title = L("예약 작업") }
    t.instruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    t.skip = skip.normalized()
    return t
  }

  // MARK: - 실행 기록

  /// 기록을 더하고 **최근 30건만** 남긴다.
  public mutating func record(_ run: RunRecord) {
    history.append(run)
    if history.count > Self.historyLimit {
      history.removeFirst(history.count - Self.historyLimit)
    }
    lastRun = run
  }

  /// 다음 실행 시각을 다시 계산한다.
  ///
  /// - 한 번짜리는 실행 후 **꺼진다**(`enabled = false`).
  /// - 반복 작업은 `max(실행 시각, 지금)` 이후로 잡아, 늦게 따라잡아도 같은 시각을 두 번 실행하지 않는다.
  public mutating func advanceNextFire(after fireAt: Date, now: Date,
                                       calendar: Calendar = .current) {
    switch rule {
    case .once:
      nextFireAt = nil
      enabled = false
    case .daily, .weekly, .everyNDays, .interval:
      nextFireAt = rule.next(after: max(fireAt, now), calendar: calendar, skip: skip)
    }
  }

  /// `nextFireAt` 이 비어 있으면 채운다(앱을 새로 켰을 때). 이미 있으면 건드리지 않는다.
  public mutating func fillNextFireIfNeeded(now: Date, calendar: Calendar = .current) {
    guard enabled, nextFireAt == nil else { return }
    nextFireAt = rule.next(after: now, calendar: calendar, skip: skip)
  }

  private static func clean(_ raw: String, limit: Int) -> String {
    let collapsed = raw.components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }.joined(separator: " ")
    return String(collapsed.prefix(limit))
  }
}

// MARK: - 리포트 파일 이름

/// 리포트 파일 이름 규칙 — **경로를 벗어나지 못하게** 여기서만 만든다.
public enum ReportNaming {
  public static let maxSlugLength = 60

  /// `2026-11-04-아침-테크-리포트.md`
  public static func fileName(title: String, date: Date, calendar: Calendar = .current) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.calendar = calendar
    f.timeZone = calendar.timeZone
    f.dateFormat = "yyyy-MM-dd"

    let slug = self.slug(title)
    return "\(f.string(from: date))-\(slug.isEmpty ? "report" : slug).md"
  }

  /// 제목 → 파일 이름 조각. 공백·경로 구분자·제어문자·이모지를 정리한다.
  public static func slug(_ title: String) -> String {
    var out = ""
    for ch in title.trimmingCharacters(in: .whitespacesAndNewlines) {
      if ch.isWhitespace { out.append("-"); continue }
      if "/\\:*?\"<>|#%\u{0}".contains(ch) { out.append("-"); continue }
      if ch.unicodeScalars.contains(where: { $0.properties.isEmojiPresentation }) { continue }
      if ch == "\u{FE0F}" || ch == "\u{200D}" { continue }
      out.append(ch)
    }
    // `..` 는 상위 폴더 참조가 될 수 있으므로 한 개로 접는다.
    while out.contains("..") { out = out.replacingOccurrences(of: "..", with: ".") }
    while out.contains("--") { out = out.replacingOccurrences(of: "--", with: "-") }
    out = out.trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
    if out.count > maxSlugLength {
      out = String(out.prefix(maxSlugLength))
        .trimmingCharacters(in: CharacterSet(charactersIn: "-. "))
    }
    return out
  }

  /// 같은 이름이 이미 있으면 `-2`, `-3` … 을 붙인다.
  ///
  /// APFS 기본이 대소문자를 구분하지 않으므로 비교도 소문자로 한다.
  public static func unique(_ fileName: String, existing: Set<String>) -> String {
    let taken = Set(existing.map { $0.lowercased() })
    guard taken.contains(fileName.lowercased()) else { return fileName }

    let ns = fileName as NSString
    let ext = ns.pathExtension
    let base = ns.deletingPathExtension
    var index = 2
    while true {
      let candidate = ext.isEmpty ? "\(base)-\(index)" : "\(base)-\(index).\(ext)"
      if !taken.contains(candidate.lowercased()) { return candidate }
      index += 1
    }
  }
}

// MARK: - 대화 요약 카드

/// 예약 실행이 대화에 남기는 **한 장** — 성공/실패 · 핵심 · 파일 경로.
public enum ScheduleSummaryCard {
  public static func headline(_ status: RunStatus) -> String {
    switch status {
    case .running: return Lf("%@ — 실행 중", "🔄")
    case .succeeded: return Lf("%@ — 완료", "✅")
    case .failed: return Lf("%@ — 실패", "⚠️")
    case .awaitingApproval: return Lf("%@ — 승인 대기", "⏸")
    case .cancelled: return Lf("%@ — 취소됨", "⏹")
    case .missed: return Lf("%@ — 건너뜀", "⏭")
    case .interrupted: return Lf("%@ — 중단됨", "⚠️")
    }
  }

  /// 카드 본문. `summary` 는 최대 3줄만 옮긴다(카드가 길어지면 대화가 묻힌다).
  public static func text(task: ScheduledTask, run: RunRecord) -> String {
    var lines = [headline(run.status) + " · " + task.title]

    if let summary = run.summary {
      let points = summary.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
        .prefix(3)
      for point in points { lines.append("• " + point) }
    }

    if let reason = run.failureReason, !reason.isEmpty {
      lines.append(Lf("사유: %@", reason))
    }
    if let path = run.filePath, !path.isEmpty {
      lines.append(Lf("📄 %@", path))
    }
    if run.status == .awaitingApproval {
      lines.append(L("승인하면 이어서 실행합니다. 알림을 눌러 확인하세요."))
    }
    return lines.joined(separator: "\n")
  }
}
