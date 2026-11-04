import Foundation

/// `schedule_list` 도구가 모델에게 돌려줄 목록 텍스트 (v0.27).
///
/// 모델은 이 목록에서 **UUID** 를 얻어 `schedule_update`·`schedule_delete` 의 대상으로 쓴다.
/// 사람이 읽는 카드가 아니라 **모델 입력**이므로 한 줄에 필요한 정보만 담는다.
public enum ScheduleListText {
  public static func render(_ tasks: [ScheduledTask], now: Date = Date(),
                            calendar: Calendar = .current,
                            personaNames: [UUID: String] = [:]) -> String {
    guard !tasks.isEmpty else { return L("예약 작업이 없습니다.") }
    let sorted = tasks.sorted { $0.createdAt < $1.createdAt }
    var lines: [String] = [Lf("예약 작업 %d개", sorted.count)]
    for task in sorted {
      lines.append("")
      lines.append(Lf("- id: %@", task.id.uuidString))
      lines.append(Lf("  제목: %@", task.title))
      lines.append(Lf("  규칙: %@", task.rule.humanDescription(calendar: calendar)))
      if let skip = task.skip.normalized().humanDescription() {
        lines.append(Lf("  제외: %@", skip))
      }
      lines.append(Lf("  비서: %@", personaName(task.personaID, personaNames)))
      lines.append(Lf("  상태: %@", task.enabled ? L("사용 중") : L("중지")))
      if let next = task.nextFireAt {
        lines.append(Lf("  다음 실행: %@", ScheduleRule.dateText(next, calendar: calendar)))
      } else if !task.enabled {
        lines.append(Lf("  다음 실행: %@", L("없음")))
      } else if let next = task.rule.next(after: now, calendar: calendar, skip: task.skip) {
        lines.append(Lf("  다음 실행: %@", ScheduleRule.dateText(next, calendar: calendar)))
      } else {
        lines.append(Lf("  다음 실행: %@", L("없음")))
      }
      if let last = task.lastRun {
        let when = last.finishedAt ?? last.startedAt
        lines.append(Lf("  마지막 실행: %@ · %@",
                        statusText(last.status),
                        ScheduleRule.dateText(when, calendar: calendar)))
      } else {
        lines.append(Lf("  마지막 실행: %@", L("없음")))
      }
      let instruction = task.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
      let clipped = instruction.count > 300 ? String(instruction.prefix(300)) + "…" : instruction
      lines.append(Lf("  지시문: %@", clipped.replacingOccurrences(of: "\n", with: " ")))
    }
    lines.append("")
    lines.append(L("변경·삭제는 위 id 로만 지정하세요. 사용자가 확인 카드에서 승인해야 반영됩니다."))
    return lines.joined(separator: "\n")
  }

  public static func statusText(_ status: RunStatus) -> String {
    switch status {
    case .running: return L("실행 중")
    case .succeeded: return L("성공")
    case .failed: return L("실패")
    case .awaitingApproval: return L("승인 대기")
    case .cancelled: return L("취소됨")
    case .missed: return L("놓침")
    case .interrupted: return L("중단됨")
    }
  }

  private static func personaName(_ id: UUID?, _ names: [UUID: String]) -> String {
    guard let id else { return L("기본(비서 없음)") }
    return names[id] ?? L("삭제된 비서")
  }
}
