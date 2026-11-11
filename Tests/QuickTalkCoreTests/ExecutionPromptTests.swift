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
    let c = ExecutionPrompt.contract
    XCTAssertTrue(c.contains("실행"))
    XCTAssertTrue(c.contains("3~6"))
    XCTAssertTrue(c.contains("실행할 수 없으면"), "불가능한 답변에서 멈추는 규칙이 필요하다")
    XCTAssertLessThan(c.count, 600)
  }

  /// 영어 UI에서는 영어 계약 — 한국어 지시문이 섞이지 않는다.
  func testContractFollowsDisplayLanguage() {
    let before = L10n.language
    defer { L10n.language = before }
    L10n.language = .english
    let c = ExecutionPrompt.contract
    XCTAssertTrue(c.contains("carry out"))
    XCTAssertFalse(c.contains("실행"))
    XCTAssertLessThan(c.count, 700)
    L10n.language = .korean
    XCTAssertTrue(ExecutionPrompt.contract.contains("실행"))
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
