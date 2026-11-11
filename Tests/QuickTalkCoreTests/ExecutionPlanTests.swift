import XCTest
@testable import QuickTalkCore

/// v0.36.3 — `propose_plan` 실행 계획 카드의 **모델 계약**.
///
/// 러너·UI 는 이 모델을 그대로 믿으므로, 여기서는 ① 잘못된 인자를 걸러 내는지
/// ② 상한·중복을 지키는지 ③ 기록에 남았다가 그대로 다시 읽히는지 ④ 실행 계약이
/// 계획 단계를 빠짐없이 넘기는지를 확인한다.
final class ExecutionPlanTests: XCTestCase {

  private func call(_ json: String) -> AgentToolCall {
    AgentToolCall(id: "call_1", name: PlanTool.name, arguments: json)
  }

  // MARK: - 파싱

  func testFromCallReadsGoalStepsPermissions() {
    let plan = ExecutionPlan.from(call("""
      {"goal":"사진 정리","steps":["폴더 확인","날짜 폴더 생성","사진 이동"],
       "permissions":["read","write"]}
      """))
    XCTAssertEqual(plan?.goal, "사진 정리")
    XCTAssertEqual(plan?.steps, ["폴더 확인", "날짜 폴더 생성", "사진 이동"])
    XCTAssertEqual(plan?.permissions, [.read, .write])
  }

  func testFromCallRejectsBrokenJSON() {
    XCTAssertNil(ExecutionPlan.from(call("{not json")))
  }

  func testFromCallRejectsEmptyGoalOrSteps() {
    XCTAssertNil(ExecutionPlan.from(call(#"{"goal":"","steps":["a","b"]}"#)))
    XCTAssertNil(ExecutionPlan.from(call(#"{"goal":"목표","steps":[]}"#)))
    XCTAssertNil(ExecutionPlan.from(call(#"{"goal":"목표","steps":["  ",""]}"#)),
                 "공백 단계는 빈 계획으로 취급한다")
  }

  func testFromCallDropsUnknownPermissions() {
    let plan = ExecutionPlan.from(call("""
      {"goal":"정리","steps":["a","b"],"permissions":["read","admin","network"]}
      """))
    XCTAssertEqual(plan?.permissions, [.read, .network])
  }

  // MARK: - 상한·정규화

  func testStepsAreTrimmedAndCappedAtEight() {
    let steps = (1...12).map { "  \($0)단계  " }
    let plan = ExecutionPlan(goal: "  목표  ", steps: steps)
    XCTAssertEqual(plan.goal, "목표")
    XCTAssertEqual(plan.steps.count, ExecutionPlan.maxSteps)
    XCTAssertEqual(plan.steps.first, "1단계")
    XCTAssertEqual(plan.steps.last, "8단계")
  }

  func testPermissionsAreDeduplicatedInOrder() {
    let plan = ExecutionPlan(goal: "목표", steps: ["a"],
                             permissions: [.write, .read, .write, .network])
    XCTAssertEqual(plan.permissions, [.write, .read, .network])
  }

  func testEmptyWhenGoalOrStepsMissing() {
    XCTAssertTrue(ExecutionPlan(goal: "", steps: ["a"]).isEmpty)
    XCTAssertTrue(ExecutionPlan(goal: "목표", steps: []).isEmpty)
    XCTAssertFalse(ExecutionPlan(goal: "목표", steps: ["a"]).isEmpty)
  }

  // MARK: - 기록 왕복

  func testPlanSurvivesCodableRoundTrip() throws {
    let turn = Turn(role: .assistant, text: "계획입니다.",
                    plan: ExecutionPlan(goal: "정리", steps: ["a", "b"], permissions: [.read]))
    let data = try JSONEncoder().encode(turn)
    let decoded = try JSONDecoder().decode(Turn.self, from: data)
    XCTAssertEqual(decoded.plan, turn.plan)
  }

  func testOldRecordWithoutPlanDecodes() throws {
    // 구버전 기록 = 지금 형식에서 `plan` 키만 없는 것.
    let turn = Turn(role: .assistant, text: "예전 답변")
    let data = try JSONEncoder().encode(turn)
    var obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    obj.removeValue(forKey: "plan")
    let legacy = try JSONSerialization.data(withJSONObject: obj)
    let decoded = try JSONDecoder().decode(Turn.self, from: legacy)
    XCTAssertNil(decoded.plan, "구버전 기록에는 계획이 없다")
  }

  // MARK: - 수정·실행 계약

  func testEditableTextListsEveryStep() {
    let plan = ExecutionPlan(goal: "사진 정리", steps: ["확인", "이동"])
    let text = plan.editableText
    XCTAssertTrue(text.hasPrefix("사진 정리"))
    XCTAssertTrue(text.contains("1. 확인"))
    XCTAssertTrue(text.contains("2. 이동"))
  }

  func testPlanContractCarriesEveryStep() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .korean
    let plan = ExecutionPlan(goal: "사진 정리", steps: ["확인", "이동", "검증"])
    let c = ExecutionPrompt.planContract(plan)
    XCTAssertTrue(c.contains("사진 정리"))
    for (index, step) in plan.steps.enumerated() {
      XCTAssertTrue(c.contains("\(index + 1). \(step)"))
    }
    XCTAssertTrue(c.contains("계획에 있는 단계만"))
    XCTAssertTrue(c.contains("이미 끝난 단계는 반복하지 말고"))
    XCTAssertLessThan(c.count, 1000)
  }

  func testPlanContractAppendsAlreadyRunBlock() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .korean
    let plan = ExecutionPlan(goal: "정리", steps: ["a", "b", "c"])
    let events = [AgentEvent(id: "e1", toolName: "shell", title: "폴더 확인",
                             command: "ls ~/Desktop", level: .read, risk: .normal,
                             state: .done)]
    let with = ExecutionPrompt.planContract(plan, alreadyRun: events)
    XCTAssertTrue(with.contains("ls ~/Desktop"), "이미 실행한 명령을 다시 확인하지 않게 넘긴다")
    XCTAssertGreaterThan(with.count, ExecutionPrompt.planContract(plan).count)
  }

  func testPlanContractFollowsDisplayLanguage() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .english
    let plan = ExecutionPlan(goal: "Tidy photos", steps: ["Check", "Move", "Verify"])
    let c = ExecutionPrompt.planContract(plan)
    XCTAssertTrue(c.contains("Run the plan below"))
    XCTAssertTrue(c.contains("1. Check"))
    XCTAssertFalse(c.contains("계획"))
  }

  func testPlanVisibleTextIsShort() {
    XCTAssertFalse(ExecutionPrompt.planVisibleText.isEmpty)
    XCTAssertLessThan(ExecutionPrompt.planVisibleText.count, 40)
  }

  // MARK: - 러너: 계획을 말하고 **멈춘다**

  @MainActor
  func testRunnerStopsAfterProposePlanAndRunsNoTool() async throws {
    let client = PlanMockClient(steps: [
      .toolCalls([AgentToolCall(id: "p1", name: PlanTool.name, arguments: """
        {"goal":"사진 정리","steps":["확인","이동","검증"],"permissions":["read","write"]}
        """)], reasoning: nil),
      .finalAnswer("이 답변은 나오면 안 된다", reasoning: nil),
    ])
    let executor = PlanMockExecutor()
    let result = try await AgentRunner(client: client, executor: executor)
      .run(prompt: "사진 정리해줘", history: [], tools: AgentToolCatalog.all)

    XCTAssertEqual(result.plan?.goal, "사진 정리")
    XCTAssertEqual(result.plan?.steps.count, 3)
    XCTAssertTrue(executor.executed.isEmpty, "계획 단계에서는 아무 도구도 실행하지 않는다")
    XCTAssertEqual(client.calls, 1, "계획을 받으면 다음 스텝을 요청하지 않는다")
    XCTAssertEqual(result.steps, 1)
  }

  /// 형식이 깨진 계획은 **실행하지 않고** 다시 요청한다 — 사용자에게 빈 카드를 보이지 않는다.
  @MainActor
  func testRunnerRetriesWhenPlanIsMalformed() async throws {
    let client = PlanMockClient(steps: [
      .toolCalls([AgentToolCall(id: "p1", name: PlanTool.name,
                                arguments: #"{"goal":"","steps":[]}"#)], reasoning: nil),
      .finalAnswer("계획을 다시 만들었습니다.", reasoning: nil),
    ])
    let executor = PlanMockExecutor()
    let result = try await AgentRunner(client: client, executor: executor)
      .run(prompt: "정리해줘", history: [], tools: AgentToolCatalog.all)

    XCTAssertNil(result.plan)
    XCTAssertEqual(result.answer, "계획을 다시 만들었습니다.")
    XCTAssertEqual(client.calls, 2, "형식 오류는 tool 메시지로 되돌리고 다시 묻는다")
    XCTAssertTrue(executor.executed.isEmpty)
  }
}

// MARK: - 테스트용 더미 (계획 카드)

private final class PlanMockClient: AgentClient {
  var onReasoning: (@MainActor (String) -> Void)?
  let steps: [AgentStep]
  private(set) var calls = 0
  private var index = 0

  init(steps: [AgentStep]) { self.steps = steps }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    calls += 1
    guard index < steps.count else { return .finalAnswer("끝", reasoning: nil) }
    let step = steps[index]
    index += 1
    return step
  }
}

@MainActor
private final class PlanMockExecutor: AgentToolExecutor {
  private(set) var executed: [AgentToolCall] = []

  func execute(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome {
    executed.append(call)
    return AgentToolOutcome(output: "ok", level: .read, risk: .normal)
  }
}
