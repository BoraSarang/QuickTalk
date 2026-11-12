import Foundation

// [FEATURE] 예약 작업 1회 실행 (v0.26 3단계)
//
// 흐름 (`docs/plans/PLAN_v0.26` §5)
//   ① 비서·일정 → 비서 전용 대화 확보(없으면 만들고 핀)
//   ② "실행 중" 카드 1장 + 지시문 턴
//   ③ 기존 에이전트 루프 재사용 — 비서 프롬프트·도구 필터만 다르다
//   ④ 승인이 필요하면 **멈추고** 10분 기다린다(승인 없이는 아무것도 실행하지 않는다)
//   ⑤ 끝나면 Markdown 리포트 저장 → 카드 갱신 → 대화·기록 저장
//
// ★ 이 파일은 **현재 대화를 건드리지 않는다**. 상태는 `ScheduledRunContext` 로 갈라지고
//   `UIStore.applyScheduledConversation` 이 보관함에만 반영한다.

@MainActor
final class ScheduledRunRunner {
  /// 실행 1회의 결과 — 기록 + 결과가 쌓인 대화 ID(일정에 저장해 다음에 이어 쓴다).
  struct Outcome {
    var run: RunRecord
    var conversationID: UUID
  }

  private unowned let store: UIStore

  init(store: UIStore) {
    self.store = store
  }

  /// 예약 작업 1회 실행. 실패해도 **던지지 않는다** — 결과는 `RunRecord` 로 돌려준다.
  func run(task: ScheduledTask, fireAt: Date, trigger: RunTrigger) async -> Outcome {
    let started = Date()
    var run = RunRecord(startedAt: started, status: .running, trigger: trigger)
    let persona = store.settings.persona(task.personaID)

    // ① 대화 확보 — 같은 비서·같은 일정의 결과가 한 대화에 쌓인다.
    let session = makeSession(task: task, persona: persona)
    let context = ScheduledRunContext(taskID: task.id, session: session,
                                      policy: store.settings.agentPolicy)
    context.writeScopes = (session.conversation.approvedWriteScopes ?? [])
      .filter { $0.isActive() }.map(\.path)
    context.uiGrants = (session.conversation.approvedUiApps ?? []).filter { $0.isActive() }

    store.scheduledRun = context
    store.scheduledRunPersonaID = persona?.id
    defer {
      // 남은 원격 승인 메시지가 있으면 취소로 닫는다 — 실행이 끝난 뒤 누르는 오탭 방지.
      store.remoteApproval?.cancelPending()
      store.scheduledRun = nil
      store.scheduledRunPersonaID = nil
      store.scheduledApproval = nil
    }

    _ = try? session.submit(text: task.instruction)
    let cardTurnID = session.appendAssistant(text: ScheduleSummaryCard.text(task: task, run: run)).id
    let agentTurnID = session.beginAssistantTurn()
    context.turnID = agentTurnID
    store.applyScheduledConversation(session.conversation)

    // ② 모델·도구 준비 — 없으면 실패 카드로 끝낸다.
    guard let provider = provider(for: persona) else {
      return finish(task: task, run: &run, session: session, cardTurnID: cardTurnID,
                    reason: L("AI 프로바이더가 설정되지 않았습니다."))
    }
    let executor = AgentExecutor(store: store, session: store.activeSession)
    guard let client = store.makeAgentClient(provider: provider, executor: executor,
                                             persona: persona) else {
      return finish(task: task, run: &run, session: session, cardTurnID: cardTurnID,
                    reason: L("AI 클라이언트를 만들지 못했습니다 — 설정 › AI의 모델·키를 확인하세요."))
    }

    let tools = AgentToolCatalog.available(
      for: persona,
      includingWebSearch: store.settings.webSearchEnabled && store.webSearchKeyReady
        && provider.type != .appleFM,
      includingUI: store.settings.uiControlEnabled && provider.type != .appleFM,
      // 예약 실행 중에는 **목록만** — 사람이 없는 자리에서 일정이 늘거나 지워지면 안 된다.
      includingSchedule: true,
      includingScheduleMutations: false,
      includingBrowser: store.settings.browserEnabled && provider.type != .appleFM)

    // ③ 실행 — 최종 답변은 턴에 흘려 넣는다(사용자가 나중에 열어 봐도 그대로 남는다).
    let runner = AgentRunner(client: client, executor: executor, maxSteps: 12)
    var streamed = ""
    do {
      let result = try await runner.run(
        prompt: Self.memoryPrefix(store: store, session: session, query: task.instruction)
          + Self.prompt(task: task, persona: persona),
        history: [], tools: tools,
        onDelta: { delta in
          streamed += delta
          session.appendStreaming(delta, to: agentTurnID)
        })
      context.sources = executor.turnSources
      let answer = result.answer.isEmpty ? streamed : result.answer
      session.finishAssistantTurn(agentTurnID,
                                  elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
                                  sources: context.sources.isEmpty ? nil : context.sources)

      // 승인 대기 만료는 실패로 남긴다(파일을 만들지 않는다).
      // 도구 하나가 거부됐어도 답을 끝냈으면 성공으로 본다 — 부분 거부로 리포트를 버리지 않는다.
      if context.cancelled {
        run.status = .cancelled
        run.failureReason = L("사용자가 중단했습니다.")
      } else if context.approvalTimedOut {
        run.status = .failed
        run.failureReason = L("승인 대기 시간(10분)이 만료되었습니다.")
      } else if result.hadDenial && answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        run.status = .failed
        run.failureReason = L("승인이 거부되어 작업을 마치지 못했습니다.")
      } else {
        run.status = .succeeded
      }
      run.summary = ReportDocument.summary(from: answer)

      // ④ 리포트 파일 — 파일 쓰기를 켠 비서만.
      if run.status == .succeeded, persona?.tools.write ?? true,
         !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        let document = ReportDocument(
          title: task.title,
          personaName: persona?.name,
          instruction: task.instruction,
          body: answer,
          sources: context.sources,
          ranAt: started,
          ruleText: task.rule.humanDescription())
        do {
          let url = try ReportWriter.write(markdown: document.markdown(),
                                           title: task.title, date: started,
                                           folder: Self.folder(for: persona, settings: store.settings))
          run.filePath = ReportWriter.displayPath(url.path)
          // 감사 기록 — 어떤 일정이 어떤 파일을 남겼는지 추적할 수 있게(PLAN §6).
          AgentAudit.record(command: "report \(url.path)", level: .write, risk: .normal,
                            decision: "allow", exitCode: 0, elapsedMs: 0,
                            note: "task:\(task.id.uuidString.prefix(8))")
        } catch {
          run.status = .failed
          run.failureReason = (error as? ReportWriteError)?.message ?? error.localizedDescription
        }
      }
    } catch {
      session.setAssistantText(AIErrorText.userText(for: error), id: agentTurnID)
      return finish(task: task, run: &run, session: session, cardTurnID: cardTurnID,
                    reason: AIErrorText.userText(for: error))
    }

    return finish(task: task, run: &run, session: session, cardTurnID: cardTurnID, reason: nil)
  }

  // MARK: - 준비

  /// 결과를 쌓을 대화 — 기존 대화가 있으면 이어 쓰고, 없으면 새로 만든다.
  private func makeSession(task: ScheduledTask, persona: Persona?) -> ConversationStore {
    if let id = task.conversationID,
       let existing = store.archive.first(where: { $0.id == id })
        ?? (store.conversation.id == id ? store.conversation : nil) {
      return ConversationStore(conversation: existing)
    }
    let name = persona?.name ?? L("기본(비서 없음)")
    let emoji = persona?.displayEmoji ?? "🗓"
    var conversation = Conversation(title: "\(emoji) \(name) · \(task.title)",
                                    pinned: true, personaID: persona?.id)
    conversation.titleEdited = true   // 비서 대화 제목은 자동 제목이 덮지 않게.
    return ConversationStore(conversation: conversation)
  }

  private func provider(for persona: Persona?) -> LLMProviderConfig? {
    // 대화와 **같은 해석**을 쓴다(v0.35) — 비서 프로바이더/모델이 예약에도 그대로 적용된다.
    ProviderResolver.provider(settings: store.settings, persona: persona)
  }

  /// 리포트 폴더 — 비서별 해석은 `PersonaReports` 한 곳에서만 한다(v0.35).
  static func folder(for persona: Persona?, settings: QuickTalkSettings) -> String {
    PersonaReports.folder(settings: settings, persona: persona)
  }

  /// 공통 메모리 + 이 대화의 요약 — **모든 비서가 같은 기억**을 본다(PLAN §14.8).
  /// 예약 실행은 사람이 그 자리에 없으므로 대화 기록 원문은 싣지 않고,
  /// 사용자가 저장한 사실과 지난 실행의 요약만 붙인다(토큰 보호).
  static func memoryPrefix(store: UIStore, session: ConversationStore,
                           query: String) -> String {
    var text = ""
    if store.settings.globalMemoryEnabled,
       session.conversation.commonMemoryDisabled != true {
      text += GlobalMemory.prompt(store.memoryEntries, query: query,
                                  mode: store.settings.globalMemoryMode,
                                  budget: store.settings.globalMemoryBudgetTokens).text
    }
    text += ConversationMemory.memoryPromptPrefix(session.conversation)
    return text
  }

  /// 모델에게 주는 지시문 — 사용자의 지시 + **리포트 형식**(쓰기를 켠 비서만).
  static func prompt(task: ScheduledTask, persona: Persona?) -> String {
    let instruction = task.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    guard persona?.tools.write ?? true else { return instruction }
    return """
      \(instruction)

      [리포트 형식]
      답변은 아래 형식으로 쓴다. 다른 머리말은 붙이지 않는다.
      - 핵심 1 (한 줄, 80자 이내)
      - 핵심 2
      - 핵심 3

      ## 상세
      확인한 사실·숫자를 중심으로 정리한다. 확인하지 못한 것은 "추정"이라고 표시한다.
      """
  }

  // MARK: - 마무리

  /// 카드 갱신 → 대화 저장. `reason` 이 있으면 실패로 기록한다.
  private func finish(task: ScheduledTask, run: inout RunRecord,
                      session: ConversationStore, cardTurnID: UUID,
                      reason: String?) -> Outcome {
    if let reason {
      run.status = .failed
      run.failureReason = reason
    }
    run.finishedAt = Date()
    session.setAssistantText(ScheduleSummaryCard.text(task: task, run: run), id: cardTurnID)
    store.applyScheduledConversation(session.conversation)
    NSLog("[QuickTalk] 예약 실행 종료 — 상태=%@ 파일=%@",
          run.status.rawValue, run.filePath ?? "없음")
    return Outcome(run: run, conversationID: session.conversation.id)
  }
}
