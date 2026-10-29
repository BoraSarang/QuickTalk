import Foundation

// [FEATURE] 도우미 도구 — UIStore 확장 (PLAN_v0.18)
//
// 흐름
//   질문 → "도구가 필요한가?"를 **모델에게** 짧게 물어본다(키워드 규칙 아님)
//        → 필요 없으면 **기존 경로 그대로**(스트리밍 유지)
//        → 필요 있으면 에이전트 루프: 모델 → 도구 실행(권한 게이트) → 관찰 → 반복 → 최종 답
//
// 앱은 명령어 이름을 모른다. 모델이 정한 명령을 그대로 실행하고,
// 그 명령이 무슨 권한을 요구하는지는 샌드박스로 **실측**한다.

extension UIStore {
  // MARK: - 실행 카드

  /// 실행 1건을 카드에 붙인다 — **턴에도 저장**한다(대화 기록에 함께 남아 다음에 다시 보인다)
  @MainActor
  func appendAgentEvent(_ event: AgentEvent) {
    agentEvents.append(event)
    if let turnID = agentTurnID {
      appendAgentEventToTurn(event, turnID: turnID)
    }
  }

  /// 카드 한 건을 고친다(상태·출력·경과시간).
  @MainActor
  func updateAgentEvent(id: String, _ mutate: (inout AgentEvent) -> Void) {
    guard let idx = agentEvents.firstIndex(where: { $0.id == id }) else { return }
    mutate(&agentEvents[idx])
    if let turnID = agentTurnID {
      updateAgentEventInTurn(id: id, turnID: turnID, mutate)
    }
  }

  /// "항시 허용"을 눌렀을 때 — 그 명령을 허용 규칙으로 저장한다.
  @MainActor
  func addAgentRule(pattern: String) {
    let p = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !p.isEmpty else { return }
    if !settings.agentPolicy.rules.contains(p) {
      settings.agentPolicy.rules.append(p)
    }
    NSLog("[QuickTalk] 도구 허용 규칙 추가 (명령은 로그에 남기지 않는다)")
  }

  /// "이 폴더 허용" — 이번 대화에서 그 폴더의 쓰기는 다시 묻지 않는다(v0.19).
  /// 승인은 대화 기록과 함께 저장되고 7일 뒤 만료되며, 다시 승인하면 기간이 갱신된다(2026-10-29).
  @MainActor
  func approveWriteScopes(_ scopes: [String]) {
    guard !scopes.isEmpty else { return }
    let grants = WriteScopeGrant.approve(scopes, into: conversation.approvedWriteScopes ?? [])
    setWriteScopeGrants(grants)
    NSLog("[QuickTalk] 쓰기 폴더 승인 — %d개 범위", approvedWriteScopes.count)
  }

  /// 진행 중인 셸 실행 중지(v0.20) — 카드 [중단] 버튼·응답 중지가 함께 쓴다.
  @MainActor
  func cancelAgentRun() {
    guard let handle = agentRunHandle else { return }
    NSLog("[QuickTalk] 도구 실행 중지 요청")
    handle.cancel()
  }

  /// 시스템 영역 쓰기·상승 권한 명령을 터미널로 넘긴다(v0.20) — 앱은 실행하지 않는다.
  @MainActor
  func handoffToTerminal(_ command: String) {
    agentHandoffNotice = TerminalHandoffService.open(command: command)
  }

  /// Shortcuts/AppIntent가 채운 질문을 입력창에 넣는다 — 기본은 **자동 전송하지 않는다**.
  @MainActor
  func fillDraft(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    draft = trimmed
    composerFocusToken = UUID()
  }

  /// Shortcuts/AppIntent가 보낸 질문 — '질문하고 보내기'는 옵트인 설정이 켜져 있을 때만 바로 전송한다(2026-10-29).
  @MainActor
  func receiveShortcutQuestion(_ text: String, autoSend: Bool) {
    fillDraft(text)
    guard ShortcutAutoSend.shouldSend(requested: autoSend, enabled: settings.shortcutAutoSend) else { return }
    NSLog("[QuickTalk] Shortcuts 자동 전송 — 설정에 따라 확인 없이 전송")
    send()
  }

  /// 쓰기 실행이 끝나면 되돌리기 스냅샷을 카드와 연결한다.
  @MainActor
  func registerAgentUndo(_ entry: UndoEntry, eventID: String) {
    agentUndoEntries[eventID] = entry
    agentUndoMessages[eventID] = nil
  }

  /// 카드에 보여 줄 되돌리기 항목 — 이번 세션에서 만든 것만(앱을 다시 켜면 사라진다).
  func agentUndoEntry(for events: [AgentEvent]) -> UndoEntry? {
    for event in events.reversed() {
      // 스냅샷은 **이벤트 ID** 로 붙는다(undoID 는 스냅샷 쪽 식별자)
      if event.undoID != nil, let entry = agentUndoEntries[event.id] { return entry }
    }
    return nil
  }

  /// 되돌리기 대상 이벤트 ID — 카드의 [되돌리기] 가 어느 스냅샷을 쓸지 찾는다.
  func agentUndoEventID(for events: [AgentEvent]) -> String? {
    for event in events.reversed() {
      if event.undoID != nil, agentUndoEntries[event.id] != nil { return event.id }
    }
    return nil
  }

  func agentUndoMessage(for events: [AgentEvent]) -> String? {
    guard let id = agentUndoEventID(for: events) else { return nil }
    return agentUndoMessages[id]
  }

  /// [되돌리기] — 스냅샷 시점으로 파일을 되돌린다.
  @MainActor
  func undoAgentWrite(eventID: String) async {
    guard let entry = agentUndoEntries[eventID] else { return }
    let result = await UndoStack.shared.undo(id: entry.id)
    if let updated = await UndoStack.shared.entry(id: entry.id) {
      agentUndoEntries[eventID] = updated
    }
    if result.succeeded {
      agentUndoMessages[eventID] = Lf("되돌렸습니다 — %d개 복원 · %d개 삭제",
                                      result.restored, result.removed)
    } else if result.alreadyUndone {
      agentUndoMessages[eventID] = L("이미 되돌렸습니다.")
    } else if result.notFound {
      agentUndoMessages[eventID] = L("되돌리기 기록을 찾지 못했습니다.")
    } else {
      agentUndoMessages[eventID] = Lf("일부만 되돌렸습니다(%d개 실패).", result.failed.count)
    }
    NSLog("[QuickTalk] 되돌리기 — 복원 %d · 삭제 %d · 실패 %d",
          result.restored, result.removed, result.failed.count)
  }

  /// 사용자가 카드의 버튼을 눌렀다.
  @MainActor
  func resolveAgentApproval(_ choice: AgentApprovalChoice) {
    agentExecutor?.resolveApproval(choice)
  }

  // MARK: - 클라이언트

  /// 프로바이더별 에이전트 클라이언트를 만든다(키 없음·주소 오류면 nil).
  /// 온디바이스(Apple FM)는 **짧은 지시문**을 쓴다 — 작은 모델은 긴 지시문을 따라가지 못한다.
  func makeAgentClient(provider: LLMProviderConfig,
                       executor: any AgentToolExecutor) -> AgentClient? {
    let instructions: String
    switch provider.type {
    case .appleFM:
      instructions = AgentInstructions.compactText
    case .ollama, .openAICompatible:
      instructions = AgentInstructions.text + "\n\n" + AgentInstructions.selfKnowledge(settings: settings)
    }
    switch provider.type {
    case .appleFM:
      if #available(macOS 26.0, *) {
        return AppleFMAgentClient(executor: executor, systemPrompt: instructions,
                                   tools: AgentToolCatalog.all)
      }
      return nil
    case .ollama:
      guard let base = URL(string: provider.baseURL), !provider.model.isEmpty else { return nil }
      return OllamaAgentClient(host: base, model: provider.model, systemPrompt: instructions)
    case .openAICompatible:
      guard let base = URL(string: provider.baseURL), !provider.model.isEmpty,
            !provider.secretID.isEmpty,
            let key = SecretStore.load(account: provider.secretID), !key.isEmpty else { return nil }
      return OpenAICompatibleAgentClient(
        client: OpenAIClient(baseURL: base, apiKey: key, model: provider.model),
        systemPrompt: instructions)
    }
  }

  // MARK: - 도구 필요 판정

  // MARK: - 에이전트 턴

  /// 에이전트 루프 실행 — 최종 답변을 토큰 단위로 흘려보내면서 카드도 쌓는다.
  /// **도구 필요 판정은 따로 하지 않는다** — 작은 분류기 모델이 "메모리"를 앱의 '기억'으로
  /// 오해해 도구를 안 쓰는 일이 있었다(2026-10-22). 판정 없이 **본 모델이 직접 고르게** 한다.
  @MainActor
  func runAgentTurn(client: AgentClient,
                    prompt: String,
                    history: [Turn],
                    turnID: UUID,
                    tools: [AgentTool] = AgentToolCatalog.all,
                    attachments: [OutgoingAttachment] = [],
                    onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    let executor = AgentExecutor(store: self)
    agentExecutor = executor
    agentEvents = []
    agentSearchSources = []
    agentTurnID = turnID
    agentHandoffNotice = nil
    defer {
      agentApproval = nil
      agentRunHandle = nil
    }

    let runner = AgentRunner(client: client, executor: executor, maxSteps: 12)
    let result = try await runner.run(prompt: prompt, history: history,
                                      tools: tools, attachments: attachments,
                                      onDelta: onDelta)
    // 모델이 `web_search` 로 확인한 출처 — 답변 아래 출처 카드로 남긴다.
    agentSearchSources = executor.turnSources
    NSLog("[QuickTalk] 에이전트 종료 — 스텝 %d · 실행 %d건 · 검색 출처 %d · 거부 %@",
          result.steps, result.events.count, agentSearchSources.count,
          result.hadDenial ? "있음" : "없음")
    if result.answer.isEmpty {
      return L("작업을 마쳤습니다.")
    }
    return result.answer
  }

  /// 도구를 쓸 수 있는 클라이언트를 만든다(도구 사용이 꺼져 있으면 nil).
  @MainActor
  func makeAgentClientIfEnabled(provider: LLMProviderConfig) -> AgentClient? {
    guard settings.agentToolsEnabled else { return nil }
    let executor = AgentExecutor(store: self)
    agentExecutor = executor
    return makeAgentClient(provider: provider, executor: executor)
  }

  /// 도구를 **실제로** 쓸 수 있는가 — `makeAgentClient` 와 같은 조건(모델·주소·키).
  /// 사전 검색(주입/툴 콜링/Y-N 판정)을 건너뛰고 에이전트 루프로 갈지 판단한다.
  @MainActor
  func canUseAgentTools(_ provider: LLMProviderConfig) -> Bool {
    guard settings.agentToolsEnabled else { return false }
    switch provider.type {
    case .appleFM:
      if #available(macOS 26.0, *) { return true }
      return false
    case .ollama:
      return !provider.model.isEmpty && URL(string: provider.baseURL) != nil
    case .openAICompatible:
      return !provider.model.isEmpty && !provider.secretID.isEmpty
        && SecretStore.has(account: provider.secretID)
        && URL(string: provider.baseURL) != nil
    }
  }

  /// 이번 턴에 `web_search` 도구를 넘길 수 있는가(검색이 켜져 있고 Exa 키가 있을 때).
  var webSearchToolAvailable: Bool {
    settings.webSearchEnabled && webSearchKeyReady
  }

  /// 지금 설정에서 모델이 **도구 루프 안에서** 웹 검색을 하는가 — 설정 화면 안내용(2026-10-29).
  /// 참이면 앱의 사전 검색·Exa `/answer` 초안은 쓰이지 않는다.
  @MainActor
  var isAgentDrivenWebSearch: Bool {
    guard let provider = settings.activeProvider else { return false }
    return WebSearchRouting.skipsPreSearch(agentTools: canUseAgentTools(provider),
                                            searchToolReady: webSearchToolAvailable,
                                            providerType: provider.type)
  }

  /// QA: 헤드리스 에이전트 1회 — 도구 실행·권한 판정·최종 답을 로그로 남긴다.
  /// 승인이 필요한 명령은 **거부**로 처리한다(헤드리스에서 대면 창이 없으므로).
  @MainActor
  func agentSelfTest(query: String) async -> String {
    guard let provider = settings.activeProvider else { return "FAIL no-provider" }
    agentSelfTestMode = true
    defer { agentSelfTestMode = false }
    let executor = AgentExecutor(store: self)
    agentExecutor = executor
    agentEvents = []
    guard let client = makeAgentClient(provider: provider, executor: executor) else {
      return "FAIL client-unavailable"
    }
    let runner = AgentRunner(client: client, executor: executor, maxSteps: 8)
    do {
      let result = try await runner.run(prompt: query, history: [], tools: AgentToolCatalog.all)
      var lines = ["OK steps=\(result.steps) tools=\(result.events.count) denied=\(result.hadDenial ? 1 : 0)"]
      for e in result.events {
        lines.append("tool=\(e.toolName) level=\(e.level.rawValue) risk=\(e.risk.rawValue) state=\(e.state.rawValue) cmd=\(e.command.prefix(60))")
      }
      lines.append("answer=\(result.answer.prefix(200))")
      return lines.joined(separator: " | ")
    } catch {
      // 실패 원인 코드까지 남긴다(본문은 남기지 않는다).
      var detail = "FAIL code=\(AIErrorText.code(for: error))"
      if case QuickTalkError.serverFailure(let failure) = error {
        detail += " server=\(failure.serverCode ?? "-") status=\(failure.httpStatus)"
      }
      return detail
    }
  }
}
