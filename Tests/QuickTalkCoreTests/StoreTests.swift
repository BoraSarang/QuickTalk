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
}
