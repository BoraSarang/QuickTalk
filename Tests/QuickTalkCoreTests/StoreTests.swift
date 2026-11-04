import XCTest
@testable import QuickTalkCore

final class StoreTests: XCTestCase {
  func testKeyboardFirstSubmission() throws {
    let s = ConversationStore()
    let t = try s.submit(text: "웹 페이지 번역 온디바이스로 돼?", attachments: [Attachment(name: "a.md", kind: .file)])
    XCTAssertEqual(t.status, .submitting)
    XCTAssertEqual(s.conversation.turns.count, 1)
    let a = s.appendAssistant(text: "서버 통신 필요")
    XCTAssertEqual(s.conversation.turns.count, 2)
    XCTAssertEqual(a.role, .assistant)
  }
  func testEmptyThrows() {
    let s = ConversationStore()
    XCTAssertThrowsError(try s.submit(text: "   ")) { e in
      XCTAssertEqual((e as? QuickTalkError)?.code, "E-MAC-MODEL-0001")
    }
  }
  func testUnsupportedFileThrows() {
    let s = ConversationStore()
    XCTAssertThrowsError(try s.submit(text: "x", attachments: [Attachment(name: "a.exe", kind: .file)]))
  }
  func testEphemeralKeepsPinnedOnly() throws {
    let s = ConversationStore()
    try s.submit(text: "hi")
    s.clearEphemeral()
    XCTAssertTrue(s.conversation.turns.isEmpty)
    try s.submit(text: "hi2"); s.togglePin(); s.clearEphemeral()
    XCTAssertFalse(s.conversation.turns.isEmpty)
  }
  func testSupportedExtensions() {
    XCTAssertTrue(Attachment.isSupported(filename: "n.md"))
    XCTAssertTrue(Attachment.isSupported(filename: "n.TXT"))
    XCTAssertTrue(Attachment.isSupported(filename: "s.png"))
    XCTAssertFalse(Attachment.isSupported(filename: "a.exe"))
  }

  /// 대화 중 비서를 바꿔도 **턴마다** 그때의 비서가 남는다(v0.27).
  func testAssistantTurnCapturesPersonaAtCreation() throws {
    let s = ConversationStore()
    let a = UUID(), b = UUID()
    s.setPersonaID(a)
    try s.submit(text: "안녕")
    let first = s.beginAssistantTurn()
    XCTAssertEqual(s.conversation.turns.first(where: { $0.id == first })?.personaID, a)

    s.setPersonaID(b)
    let second = s.appendAssistant(text: "바뀐 비서")
    XCTAssertEqual(second.personaID, b)
    // 첫 답변의 귀속은 바뀌지 않는다.
    XCTAssertEqual(s.conversation.turns.first(where: { $0.id == first })?.personaID, a)

    s.setPersonaID(nil)
    XCTAssertNil(s.appendAssistant(text: "기본").personaID)
  }

  /// 구버전 기록(personaID 키 없음)도 읽힌다.
  func testTurnDecodesWithoutPersonaID() throws {
    let json = #"{"id":"\#(UUID().uuidString)","role":"assistant","text":"hi","attachments":[],"status":"done"}"#
    let turn = try JSONDecoder().decode(Turn.self, from: Data(json.utf8))
    XCTAssertNil(turn.personaID)
  }
}
