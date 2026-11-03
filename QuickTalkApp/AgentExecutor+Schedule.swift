import Foundation

// [FEATURE] `schedule_task` — 예약 작업 **제안** (v0.26 4단계)
//
// 모델은 일정을 직접 등록하지 못한다. 인자를 검증한 뒤 확인 카드를 띄우고,
// 사용자가 [등록]을 눌렀을 때만 `SchedulerService` 에 저장한다.
// 삭제·수정 도구는 없다 — 그건 `/할일` 시트에서만 한다(PLAN §7).

extension AgentExecutor {
  func proposeSchedule(_ call: AgentToolCall) async -> AgentToolOutcome {
    // 예약 실행 중에는 사람이 없다 — 무인 등록을 막는다.
    if store.scheduledRun != nil {
      return AgentToolOutcome(output: L("예약 실행 중에는 새 일정을 만들 수 없습니다."),
                              denied: true, level: .write, risk: .normal)
    }
    if store.agentSelfTestMode {
      return AgentToolOutcome(output: L("자가진단 모드에서는 일정을 등록하지 않습니다."),
                              denied: true, level: .write, risk: .normal)
    }

    let proposal: ScheduleProposal
    do {
      proposal = try ScheduleProposal.parse(call.arguments,
                                            personas: store.settings.personas)
    } catch {
      let text = (error as? ScheduleProposal.ParseError)?.message
        ?? error.localizedDescription
      recordAudit(command: "schedule_task \(proposalTitle(from: call.arguments))",
                  level: .write, risk: .normal, decision: "deny",
                  exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: .write, risk: .normal)
    }

    let title = Lf("일정 등록 제안 — %@ · %@",
                   proposal.title, proposal.rule.humanDescription())
    store.appendAgentEvent(AgentEvent(
      id: call.id, toolName: call.name, title: title,
      command: proposal.instruction, level: .write, risk: .normal,
      state: .pending, output: L("사용자 확인을 기다립니다.")))

    let started = Date()
    let accepted = await store.requestScheduleConfirmation(proposal)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let text = accepted
      ? Lf("등록했습니다: %@ (%@)", proposal.title, proposal.rule.humanDescription())
      : L("사용자가 등록을 취소했습니다.")
    store.updateAgentEvent(id: call.id) {
      $0.state = accepted ? .done : .denied
      $0.output = text
      $0.elapsedMs = elapsed
    }
    recordAudit(command: "schedule_task \(proposal.title)", level: .write, risk: .normal,
                decision: accepted ? "allow" : "deny", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, denied: !accepted, level: .write, risk: .normal)
  }

  /// 실패 감사 기록에는 **제목만** 남긴다(지시문 전문은 로그에 쓰지 않는다).
  private func proposalTitle(from arguments: String) -> String {
    guard let data = arguments.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let title = object["title"] as? String else { return "(제목 없음)" }
    return String(title.prefix(60))
  }
}
