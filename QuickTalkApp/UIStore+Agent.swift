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

  /// 실행 1건을 카드에 붙인다.
  @MainActor
  func appendAgentEvent(_ event: AgentEvent) {
    agentEvents.append(event)
  }

  /// 카드 한 건을 고친다(상태·출력·경과시간).
  @MainActor
  func updateAgentEvent(id: String, _ mutate: (inout AgentEvent) -> Void) {
    guard let idx = agentEvents.firstIndex(where: { $0.id == id }) else { return }
    mutate(&agentEvents[idx])
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

  /// 사용자가 카드의 버튼을 눌렀다.
  @MainActor
  func resolveAgentApproval(_ choice: AgentApprovalChoice) {
    agentExecutor?.resolveApproval(choice)
  }

  // MARK: - 클라이언트

  /// 프로바이더별 에이전트 클라이언트를 만든다(키 없음·주소 오류면 nil).
  func makeAgentClient(provider: LLMProviderConfig,
                       executor: any AgentToolExecutor) -> AgentClient? {
    let system = AgentInstructions.text + "\n\n" + AgentInstructions.selfKnowledge(settings: settings)
    switch provider.type {
    case .appleFM:
      if #available(macOS 26.0, *) {
        return AppleFMAgentClient(executor: executor, systemPrompt: system,
                                   tools: AgentToolCatalog.all)
      }
      return nil
    case .ollama:
      guard let base = URL(string: provider.baseURL), !provider.model.isEmpty else { return nil }
      return OllamaAgentClient(host: base, model: provider.model, systemPrompt: system)
    case .openAICompatible:
      guard let base = URL(string: provider.baseURL), !provider.model.isEmpty,
            !provider.secretID.isEmpty,
            let key = SecretStore.load(account: provider.secretID), !key.isEmpty else { return nil }
      return OpenAICompatibleAgentClient(
        client: OpenAIClient(baseURL: base, apiKey: key, model: provider.model),
        systemPrompt: system)
    }
  }

  // MARK: - 도구 필요 판정

  /// "이 질문에 도구가 필요한가"를 **모델**에게 짧게 묻는다.
  /// 같은 질문·직전 맥락이면 10분간 캐시한다(추가 지연 방지).
  func decidesToUseTools(_ prompt: String, history: [Turn] = []) async -> Bool {
    guard settings.agentToolsEnabled, let provider = settings.activeProvider else { return false }
    let previous = history.last(where: { $0.role == .user })?.text
    let key = Self.agentDecisionKey(providerID: provider.id, previous: previous, prompt: prompt)
    if let hit = agentDecisionCache[key], Date().timeIntervalSince(hit.at) < agentDecisionTTL {
      return hit.needed
    }
    let question = """
      이 질문에 답하려면 이 컴퓨터를 직접 확인하거나 명령을 실행해야 하나요?
      (디스크 용량, 프로세스, 네트워크 속도, 일정, 파일 찾기, 기기 연결, 도구 설치 등)
      질문: \(prompt)
      답은 YES 또는 NO 중 하나만 적으세요.
      """
    // 타임아웃은 프로바이더별 — 온디바이스 8초, 원격 8초, Ollama 25초(콜드 로드 포함)
    let timeout: TimeInterval = provider.type == .ollama ? 25 : 8
    do {
      let answer = try await Self.classifierAnswer(provider: provider, prompt: question,
                                                   timeout: timeout)
      let needed = WebSearchQuery.parseNeed(answer)
      if agentDecisionCache.count >= 50 { agentDecisionCache.removeAll() }
      agentDecisionCache[key] = (needed, Date())
      NSLog("[QuickTalk] 도구 필요 판정 %@", needed ? "YES" : "NO")
      return needed
    } catch {
      NSLog("[QuickTalk] 도구 필요 판정 실패 → 도구 미사용")
      return false
    }
  }

  static func agentDecisionKey(providerID: String, previous: String?, prompt: String) -> String {
    let norm: (String) -> String = { s in
      s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    return "agent|\(providerID)|\(norm(previous ?? ""))|\(norm(prompt))"
  }

  // MARK: - 에이전트 턴

  /// 에이전트 루프 실행 — 최종 답변 문자열을 돌려준다(실행 카드는 UIStore 에 쌓인다).
  @MainActor
  func runAgentTurn(provider: LLMProviderConfig, prompt: String, history: [Turn],
                    turnID: UUID) async throws -> String {
    let executor = AgentExecutor(store: self)
    agentExecutor = executor
    agentEvents = []
    agentTurnID = turnID
    defer { agentApproval = nil }

    guard let client = makeAgentClient(provider: provider, executor: executor) else {
      throw QuickTalkError.detailed(L("이 프로바이더에서는 도구를 쓸 수 없습니다."),
                                    code: "E-MAC-AGENT-0001")
    }
    let runner = AgentRunner(client: client, executor: executor, maxSteps: 12)
    let result = try await runner.run(prompt: prompt, history: history, tools: AgentToolCatalog.all)
    NSLog("[QuickTalk] 에이전트 종료 — 스텝 %d · 실행 %d건 · 거부 %@",
          result.steps, result.events.count, result.hadDenial ? "있음" : "없음")
    if result.answer.isEmpty {
      return L("작업을 마쳤습니다.")
    }
    return result.answer
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
