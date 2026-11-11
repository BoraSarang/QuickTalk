import XCTest
@testable import QuickTalkCore

// [FEATURE] v0.29 연결 끊김 대기·이어쓰기 + 예고로 끝나는 답 방지
//
// 사용자 요구
//   · 응답 도중 인터넷이 끊기면 **바로 실패로 끝내지 않고** 기다렸다 이어서 쓴다(기본 5초 × 10회).
//   · 대기 중에도 [중지]로 빠져나올 수 있다.
//   · "확인하겠습니다" 같은 예고만 남기고 끝나지 않는다.

final class NetworkRetryTests: XCTestCase {
  override func setUp() {
    super.setUp()
    L10n.language = .korean
  }

  override func tearDown() {
    L10n.language = .system
    super.tearDown()
  }

  // MARK: - 정책

  func testStandardPolicyMatchesRequestedDefaults() {
    let policy = NetworkRetryPolicy.standard
    XCTAssertTrue(policy.enabled)
    XCTAssertEqual(policy.intervalSeconds, 5)
    XCTAssertEqual(policy.maxAttempts, 10)
    XCTAssertEqual(policy.interval, 5)
  }

  func testPolicyClampsUnsafeValues() {
    let low = NetworkRetryPolicy(enabled: true, intervalSeconds: 0, maxAttempts: -3)
    XCTAssertEqual(low.intervalSeconds, 1)
    XCTAssertEqual(low.maxAttempts, 0)
    let high = NetworkRetryPolicy(enabled: true, intervalSeconds: 999, maxAttempts: 999)
    XCTAssertEqual(high.intervalSeconds, 60)
    XCTAssertEqual(high.maxAttempts, 50)
  }

  func testCanRetryStopsAtMaxAttempts() {
    let policy = NetworkRetryPolicy(enabled: true, intervalSeconds: 1, maxAttempts: 2)
    XCTAssertTrue(policy.canRetry(afterFailures: 0))
    XCTAssertTrue(policy.canRetry(afterFailures: 1))
    XCTAssertFalse(policy.canRetry(afterFailures: 2))
    XCTAssertFalse(NetworkRetryPolicy.disabled.canRetry(afterFailures: 0))
  }

  // MARK: - 재시도 판정

  func testTransientNetworkErrorsAreRetryable() {
    XCTAssertTrue(NetworkRetry.isRetryable(URLError(.notConnectedToInternet)))
    XCTAssertTrue(NetworkRetry.isRetryable(URLError(.timedOut)))
    XCTAssertTrue(NetworkRetry.isRetryable(URLError(.networkConnectionLost)))
    XCTAssertTrue(NetworkRetry.isRetryable(URLError(.cannotConnectToHost)))
    XCTAssertTrue(NetworkRetry.isRetryable(URLError(.dnsLookupFailed)))
    XCTAssertTrue(NetworkRetry.isRetryable(QuickTalkError.networkUnavailable()))
  }

  func testCancellationAndPermanentErrorsAreNotRetryable() {
    XCTAssertFalse(NetworkRetry.isRetryable(CancellationError()))
    XCTAssertFalse(NetworkRetry.isRetryable(URLError(.cancelled)))
    XCTAssertFalse(NetworkRetry.isRetryable(URLError(.userAuthenticationRequired)))
    XCTAssertFalse(NetworkRetry.isRetryable(
      QuickTalkError.serverFailure(.keyRejected(status: 401, code: nil))))
    XCTAssertFalse(NetworkRetry.isRetryable(
      QuickTalkError.serverFailure(.attachmentUnsupported(status: 400, code: nil))))
  }

  func testServerFailuresFollowTheirOwnRetryRule() {
    XCTAssertTrue(NetworkRetry.isRetryable(
      QuickTalkError.serverFailure(.rateLimited(status: 429, code: nil))))
    XCTAssertTrue(NetworkRetry.isRetryable(
      QuickTalkError.serverFailure(.upstream(status: 503, code: nil))))
  }

  func testWrappedNSErrorIsJudgedByDomain() {
    let wrapped = NSError(domain: NSURLErrorDomain,
                          code: URLError.notConnectedToInternet.rawValue)
    XCTAssertTrue(NetworkRetry.isRetryable(wrapped))
  }

  // MARK: - 이어쓰기 병합

  func testMergeRemovesOverlappingTail() {
    let partial = "리포트는 Documents 폴더에 저장합니다."
    let continuation = "폴더에 저장합니다. 그리고 목록도 남깁니다."
    let merged = NetworkRetry.mergeContinuation(partial, continuation)
    XCTAssertEqual(merged, "리포트는 Documents 폴더에 저장합니다. 그리고 목록도 남깁니다.")
    XCTAssertEqual(merged.components(separatedBy: "폴더에 저장합니다.").count - 1, 1,
                   "겹치는 문장은 한 번만 남아야 한다")
  }

  func testMergeWithoutOverlapSeparatesParagraphs() {
    let merged = NetworkRetry.mergeContinuation("첫 문단입니다.", "완전히 다른 둘째 문단입니다.")
    XCTAssertEqual(merged, "첫 문단입니다.\n\n완전히 다른 둘째 문단입니다.")
  }

  func testMergeDropsFullyRepeatedTail() {
    let partial = "디스크는 521GiB 남았습니다."
    XCTAssertEqual(NetworkRetry.mergeContinuation(partial, partial), partial)
  }

  func testMergeHandlesEmptySides() {
    XCTAssertEqual(NetworkRetry.mergeContinuation("", "둘째"), "둘째")
    XCTAssertEqual(NetworkRetry.mergeContinuation("첫째", ""), "첫째")
  }

  func testContinuationPromptKeepsOriginalRequestAndPartial() {
    let prompt = NetworkRetry.continuationPrompt(original: "디스크 용량 알려줘",
                                                 partial: "지금 확인한 결과")
    XCTAssertTrue(prompt.contains("디스크 용량 알려줘"))
    XCTAssertTrue(prompt.contains("지금 확인한 결과"))
    XCTAssertTrue(prompt.contains("이어쓰기"))
  }

  // MARK: - 예고 판정

  func testNarrationOnlyAnswersAreDetected() {
    XCTAssertTrue(AgentRunner.looksLikeNarration("확인하겠습니다."))
    XCTAssertTrue(AgentRunner.looksLikeNarration("지금 바로 조회해 보겠습니다"))
    XCTAssertTrue(AgentRunner.looksLikeNarration("I'll check that now."))
    XCTAssertFalse(AgentRunner.looksLikeNarration("디스크는 521GiB 남았습니다."))
    XCTAssertFalse(AgentRunner.looksLikeNarration("확인하겠습니다\n\n- / 는 521GiB 남음"))
    XCTAssertFalse(AgentRunner.looksLikeNarration(""))
  }

  // MARK: - 설정 저장·마이그레이션

  func testSettingsReadRetryDefaultsWhenKeysAreMissing() throws {
    let settings = try JSONDecoder().decode(QuickTalkSettings.self,
                                            from: Data("{}".utf8))
    XCTAssertTrue(settings.networkRetryEnabled)
    XCTAssertEqual(settings.networkRetryIntervalSeconds, 5)
    XCTAssertEqual(settings.networkRetryMaxAttempts, 10)
    XCTAssertEqual(settings.networkRetryPolicy, .standard)
  }

  func testSettingsClampStoredRetryValues() throws {
    let json = #"{"networkRetryEnabled":true,"networkRetryIntervalSeconds":999,"networkRetryMaxAttempts":-4}"#
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: Data(json.utf8))
    XCTAssertEqual(settings.networkRetryIntervalSeconds, 60)
    XCTAssertEqual(settings.networkRetryMaxAttempts, 0)
  }

  func testSettingsRoundTripKeepsRetryValues() throws {
    var original = QuickTalkSettings()
    original.networkRetryEnabled = false
    original.networkRetryIntervalSeconds = 12
    original.networkRetryMaxAttempts = 3
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertFalse(decoded.networkRetryEnabled)
    XCTAssertEqual(decoded.networkRetryIntervalSeconds, 12)
    XCTAssertEqual(decoded.networkRetryMaxAttempts, 3)
  }

  // MARK: - 러너: 연결 끊김 재시도

  @MainActor
  func testRunnerRetriesSameStepAfterConnectionLoss() async throws {
    let client = ScriptedAgentClient(outcomes: [
      .failure(URLError(.networkConnectionLost)),
      .success(.finalAnswer("디스크는 521GiB 남았습니다.", reasoning: nil))
    ])
    var stepsStarted = 0
    var discards = 0
    var retryStates: [NetworkRetryProgress?] = []
    let runner = AgentRunner(client: client, executor: ScriptedAgentExecutor(), maxSteps: 3)
    let result = try await runner.run(
      prompt: "용량 알려줘", history: [], tools: [],
      retry: NetworkRetryPolicy(enabled: true, intervalSeconds: 1, maxAttempts: 2),
      onStepStart: { stepsStarted += 1 },
      onStepDiscard: { discards += 1 },
      onRetry: { retryStates.append($0) })

    XCTAssertEqual(result.answer, "디스크는 521GiB 남았습니다.")
    XCTAssertEqual(result.steps, 1, "재시도는 스텝 수를 늘리지 않는다")
    XCTAssertEqual(client.calls, 2)
    XCTAssertEqual(stepsStarted, 2, "실패한 스텝도 시작으로 센다")
    XCTAssertEqual(discards, 1, "실패한 시도의 부분 글자를 지운다")
    XCTAssertEqual(client.receivedMessages.count, 2)
    XCTAssertEqual(client.receivedMessages[0].count, client.receivedMessages[1].count,
                   "같은 메시지로 다시 요청해야 한다")
    XCTAssertEqual(retryStates.compactMap { $0 }.first?.attempt, 1)
    XCTAssertNil(retryStates.last ?? nil, "대기가 끝나면 상태를 지운다")
  }

  @MainActor
  func testRunnerDoesNotRetryAuthenticationFailure() async {
    let client = ScriptedAgentClient(outcomes: [
      .failure(QuickTalkError.serverFailure(.keyRejected(status: 401, code: nil)))
    ])
    let runner = AgentRunner(client: client, executor: ScriptedAgentExecutor(), maxSteps: 3)
    do {
      _ = try await runner.run(
        prompt: "용량", history: [], tools: [],
        retry: NetworkRetryPolicy(enabled: true, intervalSeconds: 1, maxAttempts: 3))
      XCTFail("키 거부는 재시도하지 않고 그대로 실패해야 한다")
    } catch {
      XCTAssertEqual(client.calls, 1)
    }
  }

  // MARK: - 러너: 예고 문장 처리

  @MainActor
  func testToolCallNarrationIsDiscardedBeforeFinalAnswer() async throws {
    let client = ScriptedAgentClient(
      outcomes: [
        .success(.toolCalls([AgentToolCall(id: "c1", name: "shell",
                                           arguments: #"{"command":"df -h /"}"#)],
                            reasoning: nil)),
        .success(.finalAnswer("디스크는 521GiB 남았습니다.", reasoning: nil))
      ],
      deltas: ["확인하겠습니다.", "디스크는 521GiB 남았습니다."])
    var discards = 0
    let runner = AgentRunner(client: client, executor: ScriptedAgentExecutor())
    let result = try await runner.run(prompt: "용량", history: [],
                                      tools: AgentToolCatalog.all,
                                      onStepDiscard: { discards += 1 })

    XCTAssertEqual(result.answer, "디스크는 521GiB 남았습니다.")
    XCTAssertFalse(result.answer.contains("확인하겠습니다"),
                   "도구 호출 예고가 최종 답변에 섞이면 안 된다")
    XCTAssertGreaterThanOrEqual(discards, 1)
  }

  @MainActor
  func testNarrationOnlyFinalAnswerIsReplacedByRealAnswer() async throws {
    let client = ScriptedAgentClient(outcomes: [
      .success(.finalAnswer("확인하겠습니다.", reasoning: nil)),
      .success(.finalAnswer("디스크는 521GiB 남았습니다.", reasoning: nil))
    ])
    let runner = AgentRunner(client: client, executor: ScriptedAgentExecutor())
    let result = try await runner.run(prompt: "용량", history: [],
                                      tools: AgentToolCatalog.all)
    XCTAssertEqual(result.answer, "디스크는 521GiB 남았습니다.")
    XCTAssertEqual(client.calls, 2)
    XCTAssertTrue(client.receivedTools.last?.isEmpty ?? false,
                  "최종 답변 재촉은 도구를 빼고 요청한다")
  }

  @MainActor
  func testPersistentNarrationFallsBackToCollectedResults() async throws {
    let client = ScriptedAgentClient(outcomes: [
      .success(.finalAnswer("확인하겠습니다.", reasoning: nil)),
      .success(.finalAnswer("다시 확인하겠습니다.", reasoning: nil))
    ])
    let runner = AgentRunner(client: client, executor: ScriptedAgentExecutor())
    let result = try await runner.run(prompt: "용량", history: [],
                                      tools: AgentToolCatalog.all)
    XCTAssertTrue(result.answer.contains("최종 답변을 작성하지 못했습니다"))
    XCTAssertFalse(result.answer.contains("다시 확인하겠습니다"))
  }

  // MARK: - 앱 지식: 리포트 폴더

  func testSystemKnowledgeIncludesDefaultReportFolder() {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkWorkspace"
    let text = SystemKnowledge.reportFolderText(settings: settings, persona: nil)
    XCTAssertTrue(text.contains(expanded("~/Documents/QuickTalkWorkspace")))
    XCTAssertTrue(text.contains("쓰기 가능한 경로"))
  }

  func testPersonaReportFolderOverridesDefault() {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/Reports"
    let persona = Persona(name: "다미", reportFolder: "~/Documents/QuickTalkWorkspace")
    let text = SystemKnowledge.reportFolderText(settings: settings, persona: persona)
    XCTAssertTrue(text.contains(expanded("~/Documents/QuickTalkWorkspace")))
    XCTAssertFalse(text.contains(expanded("~/Documents/Reports")))
  }

  func testReadOnlyPersonaIsToldNotToWrite() {
    let persona = Persona(name: "조사원", tools: .readOnly)
    let text = SystemKnowledge.reportFolderText(settings: QuickTalkSettings(), persona: persona)
    XCTAssertTrue(text.contains("파일 쓰기가 꺼져"))
  }

  /// 비서 없는 일반 대화에는 리포트 폴더 블록을 넣지 않는다 —
  /// 모델이 "파일로 남길까요?"를 먼저 제안하던 원인(v0.32.2, 2026-11-06 사용자 지적).
  func testReportFolderPromptSkippedWithoutPersona() {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkWorkspace"
    XCTAssertEqual(SystemKnowledge.reportFolderPrompt(settings: settings, persona: nil), "")
  }

  func testReportFolderPromptIncludedForPersona() {
    let persona = Persona(name: "다미", reportFolder: "~/Documents/QuickTalkWorkspace")
    let text = SystemKnowledge.reportFolderPrompt(settings: QuickTalkSettings(), persona: persona)
    XCTAssertTrue(text.contains("[작업 폴더]"))
    XCTAssertTrue(text.contains(expanded("~/Documents/QuickTalkWorkspace")))
    // 먼저 저장을 권하지 않는다 — 사용자가 요청할 때만 쓴다.
    XCTAssertTrue(text.contains("먼저 저장을 제안하지 않는다"))
  }

  // MARK: - 작업 폴더 하위 폴더 규칙 (v0.36.4)

  /// 사용자 지시: “workspace 에 파일을 작성하게 된다면 의미 있는 폴더를 만들어 그 안에 쓰도록 유도”.
  func testWorkspaceFilesGoInPurposeFolder() {
    let text = SystemKnowledge.reportFolderText(settings: QuickTalkSettings(), persona: nil)
    XCTAssertTrue(text.contains("목적이 드러나는 하위 폴더를 만들고 그 안에 쓴다"))
    // 파일 이름과 같은 뜻의 폴더 예시
    XCTAssertTrue(text.contains("`memtop/memtop.py`"))
    XCTAssertTrue(text.contains("`photo-organizer/sort-photos.py`"))
    // 뜻 없는 폴더 이름 금지
    XCTAssertTrue(text.contains("`tmp`"))
    XCTAssertTrue(text.contains("뜻이 없는 이름은 쓰지 않는다"))
    // 한 작업은 한 폴더, 기존 폴더 재사용
    XCTAssertTrue(text.contains("같은 폴더에 모은다"))
    XCTAssertTrue(text.contains("이미 있으면 새로 만들지 않고"))
    // 예전의 느슨한 규칙은 사라진다
    XCTAssertFalse(text.contains("하위 폴더로 정리해도 된다"))
  }

  /// 도구 지시문에도 같은 규칙이 있어야 shell 로 파일을 만들 때 지켜진다.
  func testAgentInstructionsRequirePurposeFolder() {
    let text = AgentInstructions.text
    XCTAssertTrue(text.contains("파일을 만들 때"))
    XCTAssertTrue(text.contains("파일과 같은 뜻의 하위 폴더"))
    XCTAssertTrue(text.contains("`disk-report/disk-report.sh`"))
    XCTAssertTrue(text.contains("`tmp`·`test`·`output`·`files`"))
  }

  // MARK: - 비서 아이콘

  func testDisplayEmojiUsesSavedIcon() {
    XCTAssertEqual(Persona(name: "다미", emoji: "🤖").displayEmoji, "🤖")
  }

  func testDisplayEmojiIsStableAndFromPaletteWhenUnset() {
    let persona = Persona(name: "다미")
    let first = persona.displayEmoji
    XCTAssertFalse(first.isEmpty)
    XCTAssertTrue(Persona.iconChoices.contains(first))
    XCTAssertEqual(persona.displayEmoji, first, "같은 비서는 항상 같은 기본 아이콘")
  }
}

// MARK: - 테스트용 스크립트 클라이언트

/// 정해진 결과(성공·실패)를 차례로 돌려주고, 각 호출마다 델타를 흘려보낸다.
private final class ScriptedAgentClient: AgentClient {
  var onReasoning: (@MainActor (String) -> Void)?
  private let outcomes: [Result<AgentStep, Error>]
  private let deltas: [String]
  private var index = 0

  private(set) var calls = 0
  private(set) var receivedMessages: [[AgentMessage]] = []
  private(set) var receivedTools: [[String]] = []

  init(outcomes: [Result<AgentStep, Error>], deltas: [String] = []) {
    // 마지막 결과 뒤에는 "끝" 답변을 돌려주므로, 무한 재촉을 막기 위해 빈 결과를 허용한다.
    self.outcomes = outcomes
    self.deltas = deltas
  }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    receivedMessages.append(messages)
    receivedTools.append(tools.map(\.name))
    let i = index
    index += 1
    calls += 1
    if i < deltas.count, !deltas[i].isEmpty {
      await onDelta(deltas[i])
    }
    guard i < outcomes.count else { return .finalAnswer("끝", reasoning: nil) }
    return try outcomes[i].get()
  }
}

/// 도구 호출을 기록만 하는 실행기.
@MainActor
private final class ScriptedAgentExecutor: AgentToolExecutor {
  private(set) var executed: [AgentToolCall] = []

  func execute(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome {
    executed.append(call)
    return AgentToolOutcome(output: "df 출력", level: .read, risk: .normal)
  }
}

private func expanded(_ path: String) -> String {
  (path as NSString).expandingTildeInPath
}
