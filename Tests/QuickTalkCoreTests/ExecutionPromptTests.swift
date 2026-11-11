import XCTest
@testable import QuickTalkCore

/// v0.36 — 답변 → 실행의 **문구·기록** 계약.
///
/// 실행 자체(도구 루프·승인)는 기존 `AgentExecutor` 가 맡으므로 여기서는
/// ① 말풍선과 모델 계약이 분리돼 있는지 ② 실행 출처가 턴에 남는지 ③ 구버전 기록이
/// 그대로 읽히는지를 확인한다.
final class ExecutionPromptTests: XCTestCase {

  func testVisibleTextIsShortAndNonEmpty() {
    let text = ExecutionPrompt.visibleText
    XCTAssertFalse(text.isEmpty)
    XCTAssertLessThan(text.count, 80, "말풍선은 짧아야 한다")
  }

  func testContractKeepsExecutionRules() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .korean
    let c = ExecutionPrompt.contract()
    XCTAssertTrue(c.contains("실행"))
    XCTAssertTrue(c.contains("아직 실행하지 않은"), "이미 한 일을 반복하지 않는 규칙이 필요하다")
    XCTAssertTrue(c.contains("반복하지 말고"))
    XCTAssertTrue(c.contains("새로 만들거나 고치지 말고"))
    XCTAssertTrue(c.contains("하나면 단계 목록 없이"), "단일 명령에는 계획을 강요하지 않는다")
    XCTAssertTrue(c.contains("실행할 수 없으면"), "불가능한 답변에서 멈추는 규칙이 필요하다")
    XCTAssertLessThan(c.count, 900)
  }

  /// 영어 UI에서는 영어 계약 — 한국어 지시문이 섞이지 않는다.
  func testContractFollowsDisplayLanguage() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .english
    let c = ExecutionPrompt.contract()
    XCTAssertTrue(c.contains("Run only"))
    XCTAssertFalse(c.contains("실행"))
    XCTAssertLessThan(c.count, 1000)
    L10n.language = .korean
    XCTAssertTrue(ExecutionPrompt.contract().contains("실행"))
  }

  // MARK: - v0.36.2 이미 실행한 것 주입

  private func event(_ command: String, _ state: AgentEvent.State = .done) -> AgentEvent {
    AgentEvent(id: UUID().uuidString, toolName: "shell", title: command,
               command: command, level: .read, risk: .normal,
               state: state, output: "ok")
  }

  func testAlreadyRunBlockListsCommandsAndStates() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .korean
    let block = ExecutionPrompt.alreadyRunBlock([
      event("ls -l ~/Documents/QuickTalkWorkspace"),
      event("python3 memtop.py -n 10"),
      event("rm memtop.py", .denied)
    ])
    let text = try! XCTUnwrap(block)
    XCTAssertTrue(text.contains("이미 실행한 것"))
    XCTAssertTrue(text.contains("python3 memtop.py -n 10"))
    XCTAssertTrue(text.contains("완료"))
    XCTAssertTrue(text.contains("거부"))
    XCTAssertFalse(text.contains("rm memtop.py → 완료"))
  }

  func testAlreadyRunBlockIsAbsentWhenNoEvents() {
    XCTAssertNil(ExecutionPrompt.alreadyRunBlock(nil))
    XCTAssertNil(ExecutionPrompt.alreadyRunBlock([]))
    XCTAssertEqual(ExecutionPrompt.contract(alreadyRun: []), ExecutionPrompt.contract())
  }

  /// 기록이 길어도 프롬프트를 잡아먹지 않는다 — 최근 8개, 명령 100자.
  func testAlreadyRunBlockIsCapped() throws {
    let events = (1...30).map { event("command-\($0)-" + String(repeating: "x", count: 150)) }
    let block = try XCTUnwrap(ExecutionPrompt.alreadyRunBlock(events))
    let lines = block.split(separator: "\n").dropFirst()   // 헤더 제외
    XCTAssertEqual(lines.count, 8)
    XCTAssertTrue(block.contains("command-30-"), "최근 것을 남긴다")
    XCTAssertFalse(block.contains("command-1-"), "오래된 것은 자른다")
    for line in lines {
      XCTAssertLessThanOrEqual(line.count, 130, "명령은 100자에서 자른다")
    }
  }

  func testAlreadyRunBlockFollowsLanguage() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .english
    let block = ExecutionPrompt.alreadyRunBlock([event("pwd")])
    XCTAssertEqual(block?.contains("Already run"), true)
    XCTAssertFalse(block?.contains("이미 실행한") == true)
  }

  func testSubmitRecordsExecutionSource() throws {
    let store = ConversationStore()
    let source = UUID()
    let turn = try store.submit(text: ExecutionPrompt.visibleText,
                                executesTurnID: source)
    XCTAssertEqual(turn.executesTurnID, source)
    XCTAssertTrue(turn.isExecutionRequest)
    XCTAssertFalse(turn.isExecutionResult)
  }

  func testAssistantTurnCarriesExecutionSource() {
    let store = ConversationStore()
    let source = UUID()
    let id = store.beginAssistantTurn(executesTurnID: source)
    let turn = store.conversation.turns.first { $0.id == id }
    XCTAssertEqual(turn?.executesTurnID, source)
    XCTAssertEqual(turn?.isExecutionResult, true)
    XCTAssertEqual(turn?.isExecutionRequest, false)
  }

  func testOrdinaryTurnHasNoExecutionSource() throws {
    let store = ConversationStore()
    let turn = try store.submit(text: "보통 질문")
    XCTAssertNil(turn.executesTurnID)
    XCTAssertFalse(turn.isExecutionRequest)
  }

  /// 구버전 기록(키 없음)도 그대로 읽혀야 한다 — 옵셔널 필드라 nil.
  func testOldTurnWithoutExecutionFieldDecodes() throws {
    let id = UUID().uuidString
    let json = """
    {"id":"\(id)","role":"assistant","text":"답","attachments":[],"status":"done"}
    """
    let turn = try JSONDecoder().decode(Turn.self, from: Data(json.utf8))
    XCTAssertEqual(turn.id.uuidString, id)
    XCTAssertNil(turn.executesTurnID)
  }

  func testExecutionSourceRoundTrips() throws {
    let source = UUID()
    let turn = Turn(role: .user, text: "실행", executesTurnID: source)
    let data = try JSONEncoder().encode(turn)
    let decoded = try JSONDecoder().decode(Turn.self, from: data)
    XCTAssertEqual(decoded.executesTurnID, source)
  }
}
