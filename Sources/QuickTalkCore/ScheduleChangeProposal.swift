import Foundation

/// 모델이 부른 `schedule_update` 인자를 **변경 전 → 변경 후** 제안으로 바꾼다 (v0.27).
///
/// 안전 원칙:
/// - 대상은 **`schedule_list` 에서 받은 UUID 로만** 지정한다(제목 매칭 금지).
/// - 바꿀 필드만 전달한다. 아무것도 바뀌지 않으면 오류로 돌려준다.
/// - 실제 저장은 확인 카드에서 사용자가 [변경]을 눌렀을 때만 일어난다.
public struct ScheduleChangeProposal: Equatable {
  /// 카드에 한 줄씩 보여 줄 변경 내역.
  public struct Change: Equatable, Identifiable {
    public let id: String
    public let label: String
    public let before: String
    public let after: String

    public init(id: String, label: String, before: String, after: String) {
      self.id = id
      self.label = label
      self.before = before
      self.after = after
    }
  }

  public let taskID: UUID
  public let before: ScheduledTask
  public let after: ScheduledTask
  public let changes: [Change]

  public init(taskID: UUID, before: ScheduledTask, after: ScheduledTask, changes: [Change]) {
    self.taskID = taskID
    self.before = before
    self.after = after
    self.changes = changes
  }

  public enum ParseError: Error, Equatable, LocalizedError {
    case notJSON
    case missingID
    case badID
    case notFound
    case noChanges
    case emptyTitle
    case emptyInstruction
    case badRule
    case unknownPersona(String)

    public var errorDescription: String? { message }

    public var message: String {
      switch self {
      case .notJSON:
        return L("변경 인자를 읽지 못했습니다(JSON 형식이 아닙니다).")
      case .missingID:
        return L("바꿀 일정의 id 가 없습니다. schedule_list 로 id 를 먼저 확인하세요.")
      case .badID:
        return L("일정 id 가 올바른 UUID 가 아닙니다.")
      case .notFound:
        return L("그 id 의 일정을 찾지 못했습니다. schedule_list 로 다시 확인하세요.")
      case .noChanges:
        return L("바꿀 내용이 없습니다. title·instruction·rule·skip·persona·enabled 중 하나를 지정하세요.")
      case .emptyTitle:
        return L("일정 제목이 비어 있습니다.")
      case .emptyInstruction:
        return L("일정 지시문이 비어 있습니다.")
      case .badRule:
        return L("바꾸려는 규칙이 올바르지 않거나 다음 실행 시각이 없습니다.")
      case .unknownPersona(let name):
        return Lf("그런 비서가 없습니다: %@", name)
      }
    }
  }

  /// `tasks` 는 `SchedulerService.tasks` — 여기서 id 로 실제 일정을 찾는다.
  public static func parse(_ arguments: String, personas: [Persona] = [],
                           tasks: [ScheduledTask], now: Date = Date(),
                           calendar: Calendar = .current) throws -> ScheduleChangeProposal {
    guard let data = arguments.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParseError.notJSON
    }
    guard let rawID = (root["id"] as? String) ?? (root["task_id"] as? String)
      ?? (root["taskID"] as? String) else {
      throw ParseError.missingID
    }
    guard let taskID = UUID(uuidString: rawID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw ParseError.badID
    }
    guard let before = tasks.first(where: { $0.id == taskID }) else {
      throw ParseError.notFound
    }

    var after = before

    if let rawTitle = root["title"] as? String {
      let title = ScheduleProposal.clean(rawTitle)
      guard !title.isEmpty else { throw ParseError.emptyTitle }
      after.title = String(title.prefix(ScheduleProposal.Limits.title))
    }
    if let rawInstruction = root["instruction"] as? String {
      let instruction = ScheduleProposal.clean(rawInstruction)
      guard !instruction.isEmpty else { throw ParseError.emptyInstruction }
      after.instruction = String(instruction.prefix(ScheduleProposal.Limits.instruction))
    }
    if let ruleObject = root["rule"] as? [String: Any] {
      do {
        after.rule = try ScheduleProposal.parseRuleObject(ruleObject, now: now, calendar: calendar)
      } catch {
        throw ParseError.badRule
      }
    } else if root["kind"] != nil {
      do {
        after.rule = try ScheduleProposal.parseRuleObject(root, now: now, calendar: calendar)
      } catch {
        throw ParseError.badRule
      }
    }
    if root.keys.contains("skip") {
      after.skip = ScheduleProposal.parseSkipObject(root["skip"], calendar: calendar)
    }
    if root.keys.contains("persona") {
      do {
        let (id, _) = try ScheduleProposal.resolvePersona(root["persona"], personas: personas)
        after.personaID = id
      } catch ScheduleProposal.ParseError.unknownPersona(let name) {
        throw ParseError.unknownPersona(name)
      }
    }
    if let enabled = root["enabled"] as? Bool {
      after.enabled = enabled
    } else if let paused = root["pause"] as? Bool {
      after.enabled = !paused
    }

    after = after.normalized()
    guard after.rule.isValid else { throw ParseError.badRule }
    if after.rule != before.rule || after.skip != before.skip || after.enabled != before.enabled {
      // 규칙·제외가 바뀌면 다음 시각을 다시 계산한다(기존 예약 시각을 그대로 두면 틀어진다).
      after.nextFireAt = nil
      guard after.rule.next(after: now, calendar: calendar, skip: after.skip) != nil else {
        throw ParseError.badRule
      }
    }

    let changes = diff(before: before, after: after, personas: personas, calendar: calendar)
    guard !changes.isEmpty else { throw ParseError.noChanges }
    return ScheduleChangeProposal(taskID: taskID, before: before, after: after, changes: changes)
  }

  /// 카드에 보여 줄 한 줄 — "매주 월·수·금 09:00 · 주말 제외".
  public func summaryLine(calendar: Calendar = .current) -> String {
    var parts = [after.rule.humanDescription(calendar: calendar)]
    if let skip = after.skip.normalized().humanDescription() { parts.append(skip) }
    return parts.joined(separator: " · ")
  }

  private static func diff(before: ScheduledTask, after: ScheduledTask,
                           personas: [Persona], calendar: Calendar) -> [Change] {
    var out: [Change] = []
    if before.title != after.title {
      out.append(Change(id: "title", label: L("제목"),
                        before: before.title, after: after.title))
    }
    if before.instruction != after.instruction {
      out.append(Change(id: "instruction", label: L("지시문"),
                        before: before.instruction, after: after.instruction))
    }
    if before.rule != after.rule {
      out.append(Change(id: "rule", label: L("규칙"),
                        before: before.rule.humanDescription(calendar: calendar),
                        after: after.rule.humanDescription(calendar: calendar)))
    }
    if before.skip.normalized() != after.skip.normalized() {
      out.append(Change(id: "skip", label: L("제외"),
                        before: before.skip.normalized().humanDescription() ?? L("없음"),
                        after: after.skip.normalized().humanDescription() ?? L("없음")))
    }
    if before.personaID != after.personaID {
      out.append(Change(id: "persona", label: L("비서"),
                        before: personaName(before.personaID, personas: personas),
                        after: personaName(after.personaID, personas: personas)))
    }
    if before.enabled != after.enabled {
      out.append(Change(id: "enabled", label: L("상태"),
                        before: before.enabled ? L("사용 중") : L("중지"),
                        after: after.enabled ? L("사용 중") : L("중지")))
    }
    return out
  }

  static func personaName(_ id: UUID?, personas: [Persona]) -> String {
    guard let id, let p = personas.first(where: { $0.id == id }) else {
      return L("기본(비서 없음)")
    }
    return p.name
  }
}

/// 모델이 부른 `schedule_delete` 인자 — **"취소"는 삭제**다(v0.27).
public struct ScheduleDeletionProposal: Equatable {
  public let taskID: UUID
  public let title: String
  public let rule: ScheduleRule
  public let skip: ScheduleSkip
  public let personaName: String?
  public let nextFireAt: Date?

  public init(taskID: UUID, title: String, rule: ScheduleRule, skip: ScheduleSkip,
              personaName: String?, nextFireAt: Date?) {
    self.taskID = taskID
    self.title = title
    self.rule = rule
    self.skip = skip
    self.personaName = personaName
    self.nextFireAt = nextFireAt
  }

  public enum ParseError: Error, Equatable, LocalizedError {
    case notJSON
    case missingID
    case badID
    case notFound

    public var errorDescription: String? { message }

    public var message: String {
      switch self {
      case .notJSON:
        return L("삭제 인자를 읽지 못했습니다(JSON 형식이 아닙니다).")
      case .missingID:
        return L("삭제할 일정의 id 가 없습니다. schedule_list 로 id 를 먼저 확인하세요.")
      case .badID:
        return L("일정 id 가 올바른 UUID 가 아닙니다.")
      case .notFound:
        return L("그 id 의 일정을 찾지 못했습니다. schedule_list 로 다시 확인하세요.")
      }
    }
  }

  public static func parse(_ arguments: String, personas: [Persona] = [],
                           tasks: [ScheduledTask]) throws -> ScheduleDeletionProposal {
    guard let data = arguments.data(using: .utf8),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ParseError.notJSON
    }
    guard let rawID = (root["id"] as? String) ?? (root["task_id"] as? String)
      ?? (root["taskID"] as? String) else {
      throw ParseError.missingID
    }
    guard let taskID = UUID(uuidString: rawID.trimmingCharacters(in: .whitespacesAndNewlines)) else {
      throw ParseError.badID
    }
    guard let task = tasks.first(where: { $0.id == taskID }) else {
      throw ParseError.notFound
    }
    return ScheduleDeletionProposal(
      taskID: taskID,
      title: task.title,
      rule: task.rule,
      skip: task.skip.normalized(),
      personaName: task.personaID == nil
        ? nil
        : ScheduleChangeProposal.personaName(task.personaID, personas: personas),
      nextFireAt: task.nextFireAt)
  }
}
