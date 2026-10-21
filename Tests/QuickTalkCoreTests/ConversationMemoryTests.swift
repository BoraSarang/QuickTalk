import XCTest
@testable import QuickTalkCore

/// 대화 기억 정리 (T-71) — 토큰 예산·경계·요약 프롬프트·구버전 호환을 네트워크 없이 검증한다.
final class ConversationMemoryTests: XCTestCase {

  private func provider(_ type: LLMProviderType, context: Int? = nil) -> LLMProviderConfig {
    LLMProviderConfig(name: "test", type: type, contextTokens: context)
  }

  private func conversation(turns: Int, chars: Int,
                            summary: String? = nil,
                            summaryThrough: Int? = nil) -> Conversation {
    var list: [Turn] = []
    for i in 0..<turns {
      let role: TurnRole = i % 2 == 0 ? .user : .assistant
      list.append(Turn(role: role, text: String(repeating: role == .user ? "가" : "나", count: chars)))
    }
    var c = Conversation(turns: list)
    if let summary, let summaryThrough, list.indices.contains(summaryThrough) {
      c.summary = summary
      c.summaryThroughTurnID = list[summaryThrough].id
    }
    return c
  }

  // MARK: - 토큰 추정

  func testKoreanCountsOneTokenPerCharacter() {
    XCTAssertEqual(ConversationMemory.estimateTokens("가나다라마"), 5)
    XCTAssertEqual(ConversationMemory.estimateTokens(""), 0)
  }

  func testASCIIFourCharactersPerToken() {
    XCTAssertEqual(ConversationMemory.estimateTokens("abcdefgh"), 2)
    XCTAssertEqual(ConversationMemory.estimateTokens("abc"), 1)
    XCTAssertEqual(ConversationMemory.estimateTokens("안녕 abcdefgh"), 5) // 2 + 3
  }

  func testTurnsIncludeOverheadAndAttachmentNames() {
    let turns = [Turn(role: .user, text: "가나다"),
                 Turn(role: .assistant, text: "라마바사",
                      attachments: [Attachment(name: "a.txt", kind: .text)])]
    // 4 + 3 + 4 + 4 + (첨부 이름 5자는 2토큰) + 2 = 19
    XCTAssertEqual(ConversationMemory.estimateTokens(turns), 19)
  }

  // MARK: - 예산

  func testAppleFMBudgetReservesOutput() {
    let p = provider(.appleFM)
    XCTAssertEqual(ConversationMemory.totalBudget(for: p), 4_096)
    XCTAssertEqual(ConversationMemory.inputBudget(for: p), 2_816)
  }

  func testOllamaAndRemoteDefaults() {
    XCTAssertEqual(ConversationMemory.totalBudget(for: provider(.ollama)), 8_192)
    XCTAssertEqual(ConversationMemory.totalBudget(for: provider(.openAICompatible)), 32_768)
    XCTAssertEqual(ConversationMemory.totalBudget(for: provider(.openAICompatible, context: 128_000)),
                   128_000)
  }

  // MARK: - 경계

  func testBoundaryKeepsEvenPairs() {
    XCTAssertEqual(ConversationMemory.boundaryIndex(turnCount: 10, keepTurns: 6), 4)
    XCTAssertEqual(ConversationMemory.boundaryIndex(turnCount: 9, keepTurns: 6), 2)
    XCTAssertEqual(ConversationMemory.boundaryIndex(turnCount: 5, keepTurns: 6), 0)
    XCTAssertEqual(ConversationMemory.boundaryIndex(turnCount: 20, keepTurns: 3), 16)
  }

  // MARK: - 요약된 요청은 요약 + 최근만 센다

  func testRequestHistoryUsesSummaryBoundaryAndDropsCurrentTurn() {
    let c = conversation(turns: 10, chars: 10, summary: "요약", summaryThrough: 3)
    let history = ConversationMemory.requestHistory(c)
    XCTAssertEqual(history.count, 5) // 4...9 중 현재 질문(마지막) 제외
    XCTAssertEqual(history.first?.id, c.turns[4].id)
    XCTAssertEqual(history.last?.id, c.turns[8].id)
    XCTAssertTrue(ConversationMemory.memoryPromptPrefix(c).contains("요약"))
  }

  func testRequestHistoryWithoutSummaryKeepsAllButLast() {
    let c = conversation(turns: 4, chars: 10)
    let history = ConversationMemory.requestHistory(c)
    XCTAssertEqual(history.count, 3)
    XCTAssertEqual(history.last?.id, c.turns[2].id)
    XCTAssertTrue(ConversationMemory.memoryPromptPrefix(c).isEmpty)
  }

  func testContextTokensUsesSummaryAndRecentOnly() {
    let c = conversation(turns: 10, chars: 100, summary: "요약", summaryThrough: 3)
    let recentTokens = ConversationMemory.estimateTokens(Array(c.turns[4...]))
    XCTAssertEqual(ConversationMemory.contextTokens(c), 16 + 2 + recentTokens)
    XCTAssertLessThan(ConversationMemory.contextTokens(c),
                      ConversationMemory.estimateTokens(c.turns))
  }

  func testStaleSummaryBoundaryIsIgnored() {
    var c = conversation(turns: 4, chars: 10)
    c.summary = "남은 요약"
    c.summaryThroughTurnID = UUID()
    XCTAssertNil(c.activeSummary)
    XCTAssertEqual(ConversationMemory.contextTokens(c),
                   ConversationMemory.estimateTokens(c.turns))
  }

  // MARK: - 자동 정리 트리거

  func testShouldCompactOnlyOverThreshold() {
    let big = conversation(turns: 40, chars: 200)
    XCTAssertTrue(ConversationMemory.shouldCompact(big, provider: provider(.appleFM), keepTurns: 6))

    let small = conversation(turns: 8, chars: 20)
    XCTAssertFalse(ConversationMemory.shouldCompact(small, provider: provider(.appleFM), keepTurns: 6))
    XCTAssertFalse(ConversationMemory.shouldCompact(small, provider: provider(.openAICompatible),
                                                     keepTurns: 6))
  }

  func testShouldCompactNeedsOlderTurns() {
    // 최근 6개만 있으면 정리할 과거가 없다
    let c = conversation(turns: 6, chars: 400)
    XCTAssertFalse(ConversationMemory.shouldCompact(c, provider: provider(.appleFM), keepTurns: 6))
  }

  func testSummaryLowersContextBelowTrigger() {
    let c = conversation(turns: 40, chars: 200, summary: "핵심 요약", summaryThrough: 33)
    let p = provider(.appleFM)
    XCTAssertFalse(ConversationMemory.shouldCompact(c, provider: p, keepTurns: 6))
  }

  // MARK: - 예산을 넘는 장문 기록의 강제 축약

  func testFitHistoryDropsOldestWhenRecentTurnsOverBudget() {
    var c = conversation(turns: 20, chars: 400)
    c.turns.append(Turn(role: .user, text: "이번 질문"))
    let fitted = ConversationMemory.fitHistory(c, prompt: "이번 질문",
                                               provider: provider(.appleFM))
    XCTAssertGreaterThan(fitted.dropped, 0)
    XCTAssertLessThan(fitted.history.count,
                      ConversationMemory.requestHistory(c).count)
    XCTAssertEqual(fitted.history.last?.id, c.turns[c.turns.count - 2].id,
                   "최근 기록은 남는다")
  }

  func testFitHistoryReservesExtraTokensForGlobalMemory() {
    let c = conversation(turns: 20, chars: 200)
    let p = provider(.appleFM)
    let without = ConversationMemory.fitHistory(c, prompt: "질문", provider: p)
    let with = ConversationMemory.fitHistory(c, prompt: "질문", provider: p,
                                             extraTokens: 1_200)
    XCTAssertGreaterThanOrEqual(with.dropped, without.dropped)
    XCTAssertLessThanOrEqual(with.history.count, without.history.count)
  }

  func testFitHistoryKeepsSmallConversation() {
    let c = conversation(turns: 4, chars: 10)
    let fitted = ConversationMemory.fitHistory(c, prompt: "질문",
                                               provider: provider(.openAICompatible))
    XCTAssertEqual(fitted.dropped, 0)
    XCTAssertEqual(fitted.history.count, 3)
  }

  // MARK: - 전사·청크·프롬프트

  func testTranscriptIncludesRolesAttachmentsAndSources() {
    let turns = [
      Turn(role: .user, text: "질문", attachments: [Attachment(name: "a.md", kind: .text)]),
      Turn(role: .assistant, text: "답변",
           sources: [TurnSource(title: "뉴스", url: "https://example.com/1", domain: "example.com"),
                     TurnSource(title: "둘", url: "https://example.com/2", domain: "example.com"),
                     TurnSource(title: "셋", url: "https://example.com/3", domain: "example.com")])
    ]
    let text = ConversationMemory.transcript(turns)
    XCTAssertTrue(text.contains("사용자: 질문"))
    XCTAssertTrue(text.contains("[첨부: a.md]"))
    XCTAssertTrue(text.contains("어시스턴트: 답변"))
    XCTAssertTrue(text.contains("https://example.com/1"))
    XCTAssertTrue(text.contains("https://example.com/2"))
    XCTAssertFalse(text.contains("https://example.com/3")) // 출처는 최대 2개
  }

  func testChunksRespectLimitAndKeepContent() {
    let text = (1...20).map { "줄 \($0)" }.joined(separator: "\n")
    let chunks = ConversationMemory.chunks(text, maxCharacters: 18)
    XCTAssertGreaterThan(chunks.count, 1)
    XCTAssertTrue(chunks.allSatisfy { $0.count <= 18 })
    let joined = chunks.joined(separator: "\n")
    XCTAssertTrue(joined.contains("줄 1"))
    XCTAssertTrue(joined.contains("줄 20"))
  }

  func testLongSingleLineIsHardSplit() {
    let text = String(repeating: "가", count: 50)
    let chunks = ConversationMemory.chunks(text, maxCharacters: 10)
    XCTAssertEqual(chunks.count, 5)
    XCTAssertEqual(chunks.joined(), text)
  }

  func testSummaryPromptPreservesFactsAndPreviousSummary() {
    let prompt = ConversationMemory.summaryPrompt(previous: "이전 결정: A안",
                                                   transcript: "사용자: B로 가자",
                                                   maxCharacters: 800)
    XCTAssertTrue(prompt.contains("이전 결정: A안"))
    XCTAssertTrue(prompt.contains("사용자: B로 가자"))
    XCTAssertTrue(prompt.contains("800자"))
    XCTAssertTrue(prompt.contains("수치"))
    XCTAssertTrue(prompt.contains("URL"))
  }

  func testClipSummaryEnforcesLimitAndRejectsEmpty() {
    XCTAssertNil(ConversationMemory.clipSummary("   \n ", maxCharacters: 10))
    let clipped = ConversationMemory.clipSummary(String(repeating: "가", count: 20),
                                                 maxCharacters: 10)
    XCTAssertEqual(clipped?.count, 11) // 10자 + …
    XCTAssertTrue(clipped?.hasSuffix("…") ?? false)
  }

  // MARK: - 저장 호환

  func testSummarySurvivesCodableRoundTrip() throws {
    let c = conversation(turns: 4, chars: 10, summary: "요약", summaryThrough: 1)
    let data = try JSONEncoder().encode(c)
    let decoded = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertEqual(decoded.summary, "요약")
    XCTAssertEqual(decoded.summaryThroughTurnID, c.turns[1].id)
    XCTAssertEqual(decoded.compactPaused, nil)
    XCTAssertEqual(decoded.activeSummary, "요약")
  }

  func testLegacyConversationWithoutSummaryDecodes() throws {
    let c = conversation(turns: 2, chars: 5)
    let data = try JSONEncoder().encode(c)
    var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    obj.removeValue(forKey: "summary")
    obj.removeValue(forKey: "summaryThroughTurnID")
    obj.removeValue(forKey: "compactPaused")
    let legacy = try JSONSerialization.data(withJSONObject: obj)
    let decoded = try JSONDecoder().decode(Conversation.self, from: legacy)
    XCTAssertNil(decoded.summary)
    XCTAssertNil(decoded.summaryThroughTurnID)
    XCTAssertFalse(decoded.autoCompactPaused)
  }

  func testReplaceSummaryKeepsBoundaryAndPause() {
    var c = conversation(turns: 4, chars: 10, summary: "요약", summaryThrough: 1)
    c.compactPaused = true
    let store = ConversationStore(conversation: c)
    store.replaceSummary("사용자가 고친 요약")
    XCTAssertEqual(store.conversation.summary, "사용자가 고친 요약")
    XCTAssertEqual(store.conversation.summaryThroughTurnID, c.turns[1].id)
    XCTAssertTrue(store.conversation.autoCompactPaused)
  }

  func testClearAndResumePauseFlag() {
    let store = ConversationStore(conversation: conversation(turns: 4, chars: 10,
                                                             summary: "요약", summaryThrough: 1))
    store.clearSummary()
    XCTAssertNil(store.conversation.summary)
    XCTAssertTrue(store.conversation.autoCompactPaused)
    store.resumeAutoCompact()
    XCTAssertFalse(store.conversation.autoCompactPaused)
  }

  // MARK: - 로컬 모델 문맥 절약 (2026-10-21, Ollama 60초 시간 초과 대응)

  /// 32B Q4 실측(프롬프트 72~140 tok/s · 생성 3.8~4.5 tok/s)에서 6,765토큰 프롬프트는
  /// 첫 토큰까지 90초가 넘어 앱의 60초 제한에 걸렸다 → Ollama 기본 문맥을 줄인다.
  func testOllamaPromptBudgetIsReducedByDefault() {
    let p = provider(.ollama)
    XCTAssertEqual(ConversationMemory.inputBudget(for: p), 5_888)
    XCTAssertEqual(ConversationMemory.localOllamaPromptBudget, 3_072)
    XCTAssertEqual(ConversationMemory.promptBudget(for: p), 3_072)
    XCTAssertLessThan(ConversationMemory.promptBudget(for: p),
                      ConversationMemory.inputBudget(for: p))
  }

  /// 사용자가 컨텍스트 토큰을 직접 넣었으면 그 의도를 존중한다(임의 상한을 덮어쓰지 않는다).
  func testExplicitContextTokensOverrideLocalCap() {
    let p = provider(.ollama, context: 32_768)
    XCTAssertEqual(ConversationMemory.promptBudget(for: p),
                   ConversationMemory.inputBudget(for: p))
    XCTAssertGreaterThan(ConversationMemory.promptBudget(for: p), 3_072)
  }

  /// 원격·Apple FM은 기존 예산 그대로 — 이번 변경은 로컬 Ollama에만 적용된다.
  func testRemoteAndAppleFMBudgetsAreUnchanged() {
    for type in [LLMProviderType.openAICompatible, .appleFM] {
      let p = provider(type)
      XCTAssertEqual(ConversationMemory.promptBudget(for: p),
                     ConversationMemory.inputBudget(for: p), "\(type)")
    }
  }

  /// 같은 대화라도 Ollama가 원격보다 더 많이 잘라낸다 = 프롬프트가 작아진다.
  func testFitHistoryDropsMoreForOllamaThanRemote() {
    let c = conversation(turns: 20, chars: 200)
    let ollama = ConversationMemory.fitHistory(c, prompt: "질문", provider: provider(.ollama))
    let remote = ConversationMemory.fitHistory(c, prompt: "질문", provider: provider(.openAICompatible))
    XCTAssertGreaterThan(ollama.dropped, remote.dropped)
    XCTAssertEqual(remote.dropped, 0)
  }

  /// 자동 정리도 같은 예산을 쓴다 — Ollama는 70% 지점이 더 빨리 온다.
  func testShouldCompactUsesReducedLocalBudget() {
    let c = conversation(turns: 20, chars: 300)
    let ollama = provider(.ollama)
    let remote = provider(.openAICompatible)
    let tokens = ConversationMemory.contextTokens(c)
    XCTAssertGreaterThan(tokens,
                         Int(Double(ConversationMemory.promptBudget(for: ollama)) * ConversationMemory.triggerRatio))
    XCTAssertLessThan(tokens,
                      Int(Double(ConversationMemory.promptBudget(for: remote)) * ConversationMemory.triggerRatio))
    XCTAssertTrue(ConversationMemory.shouldCompact(c, provider: ollama, keepTurns: 6))
    XCTAssertFalse(ConversationMemory.shouldCompact(c, provider: remote, keepTurns: 6))
  }
}
