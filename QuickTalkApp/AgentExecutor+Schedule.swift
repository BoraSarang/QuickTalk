import Foundation

// [FEATURE] 예약 작업 도구 — 목록·등록·변경·삭제 (v0.26 4단계, v0.27 확장)
//
// 모델은 일정을 **직접** 바꾸지 못한다. 인자를 검증한 뒤 확인 카드를 띄우고,
// 사용자가 [등록]/[변경]/[삭제]를 눌렀을 때만 `SchedulerService` 에 저장한다.
// `schedule_list` 는 읽기 전용이라 카드가 없다 — 변경·삭제 대상 UUID 를 여기서 얻는다.

extension AgentExecutor {
  // MARK: - 목록 (읽기)

  func listSchedules(_ call: AgentToolCall) async -> AgentToolOutcome {
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    guard let service = store.schedulerService else {
      let text = L("예약 작업을 읽을 수 없습니다. 앱을 다시 실행해 주세요.")
      appendEvent(AgentEvent(id: call.id, toolName: call.name, title: text,
                                        command: "", level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }
    let started = Date()
    appendEvent(AgentEvent(id: call.id, toolName: call.name,
                                      title: L("예약 작업 목록"),
                                      command: "", level: level, risk: risk,
                                      state: .running))
    let names = Dictionary(uniqueKeysWithValues: store.settings.personas.map { ($0.id, $0.name) })
    let text = ScheduleListText.render(service.tasks, personaNames: names)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    updateEvent(call.id) {
      $0.state = .done
      $0.output = Lf("예약 작업 %d개", service.tasks.count)
      $0.elapsedMs = elapsed
    }
    recordAudit(command: "schedule_list", level: level, risk: risk,
                decision: "allow", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, level: level, risk: risk)
  }

  // MARK: - 등록 (쓰기 + 확인 카드)

  func proposeSchedule(_ call: AgentToolCall) async -> AgentToolOutcome {
    if let blocked = scheduleMutationBlockReason() { return blocked }
    guard store.schedulerService != nil else {
      return AgentToolOutcome(output: L("예약 작업을 저장할 수 없습니다. 앱을 다시 실행해 주세요."),
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
                   proposal.title, proposal.summaryLine())
    appendEvent(AgentEvent(
      id: call.id, toolName: call.name, title: title,
      command: proposal.instruction, level: .write, risk: .normal,
      state: .pending, output: L("사용자 확인을 기다립니다.")))

    let started = Date()
    let accepted = await store.requestScheduleConfirmation(proposal)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let text = accepted
      ? Lf("등록했습니다: %@ (%@)", proposal.title, proposal.summaryLine())
      : L("사용자가 등록을 취소했습니다.")
    updateEvent(call.id) {
      $0.state = accepted ? .done : .denied
      $0.output = text
      $0.elapsedMs = elapsed
    }
    recordAudit(command: "schedule_task \(proposal.title)", level: .write, risk: .normal,
                decision: accepted ? "allow" : "deny", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, denied: !accepted, level: .write, risk: .normal)
  }

  // MARK: - 변경 (쓰기 + 확인 카드)

  func proposeScheduleChange(_ call: AgentToolCall) async -> AgentToolOutcome {
    if let blocked = scheduleMutationBlockReason() { return blocked }
    guard let service = store.schedulerService else {
      return AgentToolOutcome(output: L("예약 작업을 변경할 수 없습니다. 앱을 다시 실행해 주세요."),
                              denied: true, level: .write, risk: .normal)
    }

    let change: ScheduleChangeProposal
    do {
      change = try ScheduleChangeProposal.parse(call.arguments,
                                                personas: store.settings.personas,
                                                tasks: service.tasks)
    } catch {
      let text = (error as? ScheduleChangeProposal.ParseError)?.message
        ?? error.localizedDescription
      recordAudit(command: "schedule_update \(proposalTitle(from: call.arguments))",
                  level: .write, risk: .normal, decision: "deny",
                  exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: .write, risk: .normal)
    }
    if service.isRunning(change.taskID) {
      let text = L("실행 중인 일정은 변경할 수 없습니다. 실행이 끝난 뒤 다시 시도하세요.")
      recordAudit(command: "schedule_update \(change.before.title)",
                  level: .write, risk: .normal, decision: "deny",
                  exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: .write, risk: .normal)
    }

    appendEvent(AgentEvent(
      id: call.id, toolName: call.name,
      title: Lf("일정 변경 제안 — %@", change.after.title),
      command: change.changes.map { "\($0.label): \($0.before) → \($0.after)" }
        .joined(separator: "\n"),
      level: .write, risk: .normal,
      state: .pending, output: L("사용자 확인을 기다립니다.")))

    let started = Date()
    let accepted = await store.requestScheduleChangeConfirmation(change)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let text = accepted
      ? Lf("일정을 변경했습니다: %@ (%@)", change.after.title, change.summaryLine())
      : L("사용자가 변경을 취소했습니다.")
    updateEvent(call.id) {
      $0.state = accepted ? .done : .denied
      $0.output = text
      $0.elapsedMs = elapsed
    }
    recordAudit(command: "schedule_update \(change.before.title)",
                level: .write, risk: .normal,
                decision: accepted ? "allow" : "deny", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, denied: !accepted, level: .write, risk: .normal)
  }

  // MARK: - 삭제 (쓰기 + 확인 카드)

  func proposeScheduleDeletion(_ call: AgentToolCall) async -> AgentToolOutcome {
    if let blocked = scheduleMutationBlockReason() { return blocked }
    guard let service = store.schedulerService else {
      return AgentToolOutcome(output: L("예약 작업을 삭제할 수 없습니다. 앱을 다시 실행해 주세요."),
                              denied: true, level: .write, risk: .normal)
    }

    let deletion: ScheduleDeletionProposal
    do {
      deletion = try ScheduleDeletionProposal.parse(call.arguments,
                                                    personas: store.settings.personas,
                                                    tasks: service.tasks)
    } catch {
      let text = (error as? ScheduleDeletionProposal.ParseError)?.message
        ?? error.localizedDescription
      recordAudit(command: "schedule_delete \(proposalTitle(from: call.arguments))",
                  level: .write, risk: .normal, decision: "deny",
                  exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: .write, risk: .normal)
    }
    if service.isRunning(deletion.taskID) {
      let text = L("실행 중인 일정은 삭제할 수 없습니다. 실행이 끝난 뒤 다시 시도하세요.")
      recordAudit(command: "schedule_delete \(deletion.title)",
                  level: .write, risk: .normal, decision: "deny",
                  exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: .write, risk: .normal)
    }

    appendEvent(AgentEvent(
      id: call.id, toolName: call.name,
      title: Lf("일정 삭제 제안 — %@", deletion.title),
      command: deletion.rule.humanDescription(),
      level: .write, risk: .normal,
      state: .pending, output: L("사용자 확인을 기다립니다.")))

    let started = Date()
    let accepted = await store.requestScheduleDeletionConfirmation(deletion)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let text = accepted
      ? Lf("일정을 삭제했습니다: %@", deletion.title)
      : L("사용자가 삭제를 취소했습니다.")
    updateEvent(call.id) {
      $0.state = accepted ? .done : .denied
      $0.output = text
      $0.elapsedMs = elapsed
    }
    recordAudit(command: "schedule_delete \(deletion.title)",
                level: .write, risk: .normal,
                decision: accepted ? "allow" : "deny", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, denied: !accepted, level: .write, risk: .normal)
  }

  /// 예약 실행·자가진단 중에는 일정을 바꾸지 않는다(사람이 없는 자리).
  private func scheduleMutationBlockReason() -> AgentToolOutcome? {
    if store.scheduledRun != nil {
      return AgentToolOutcome(output: L("예약 실행 중에는 일정을 등록·변경·삭제할 수 없습니다. 목록만 볼 수 있습니다."),
                              denied: true, level: .write, risk: .normal)
    }
    if store.agentSelfTestMode {
      return AgentToolOutcome(output: L("자가진단 모드에서는 일정을 등록·변경·삭제하지 않습니다."),
                              denied: true, level: .write, risk: .normal)
    }
    return nil
  }

  /// 실패 감사 기록에는 **제목만** 남긴다(지시문 전문은 로그에 쓰지 않는다).
  private func proposalTitle(from arguments: String) -> String {
    guard let data = arguments.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let title = object["title"] as? String else { return "(제목 없음)" }
    return String(title.prefix(60))
  }

  // MARK: - 웹 페이지 읽기 (읽기)

  func runWebFetch(_ call: AgentToolCall) async -> AgentToolOutcome {
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    let raw = call.stringArgument("url") ?? ""
    guard let url = WebFetchTool.url(from: call.arguments) else {
      let text = WebFetchError.badURL.userText
      appendEvent(AgentEvent(id: call.id, toolName: call.name,
                                        title: text, command: raw,
                                        level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }
    guard let key = SecretStore.load(account: store.settings.exaSecretID), !key.isEmpty else {
      let text = WebFetchError.missingKey.userText
      appendEvent(AgentEvent(id: call.id, toolName: call.name,
                                        title: text, command: url,
                                        level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }
    let maxCharacters = min(max(call.intArgument("max_characters") ?? 8_000, 500), 20_000)
    appendEvent(AgentEvent(id: call.id, toolName: call.name,
                                      title: Lf("웹 페이지 읽기 — %@", url), command: url,
                                      level: level, risk: risk, state: .running))
    let started = Date()
    do {
      let page = try await ExaContentsClient(apiKey: key)
        .fetch(url: url, maxCharacters: maxCharacters)
      let elapsed = Int(Date().timeIntervalSince(started) * 1000)
      addTurnSource(TurnSource(title: page.title, url: page.url,
                               domain: WebText.domain(of: page.url),
                               publishedAt: page.publishedAt,
                               snippet: String(page.text.prefix(120))))
      updateEvent(call.id) {
        $0.state = .done
        $0.output = Lf("본문 %d자", page.text.count)
        $0.elapsedMs = elapsed
      }
      recordAudit(command: "web_fetch \(url)", level: level, risk: risk,
                  decision: "allow", exitCode: nil, elapsedMs: elapsed)
      return AgentToolOutcome(output: WebFetchTool.toolOutput(page, maxCharacters: maxCharacters),
                              level: level, risk: risk)
    } catch {
      let elapsed = Int(Date().timeIntervalSince(started) * 1000)
      let text = (error as? WebFetchError)?.userText ?? error.localizedDescription
      updateEvent(call.id) {
        $0.state = .failed
        $0.output = text
        $0.elapsedMs = elapsed
      }
      recordAudit(command: "web_fetch \(url)", level: level, risk: risk,
                  decision: "deny", exitCode: nil, elapsedMs: elapsed)
      return AgentToolOutcome(output: text, level: level, risk: risk)
    }
  }
}
