import XCTest
@testable import QuickTalkCore

final class ConversationRewindTests: XCTestCase {
  private func turn(_ role: TurnRole, _ text: String) -> Turn {
    Turn(role: role, text: text)
  }

  func testRewindRemovesTargetAndEverythingAfter() {
    let u1 = turn(.user, "첫 질문")
    let a1 = turn(.assistant, "첫 답")
    let u2 = turn(.user, "두 번째 질문")
    let a2 = turn(.assistant, "두 번째 답")
    let u3 = turn(.user, "세 번째 질문")
    let store = ConversationStore(conversation: Conversation(
      title: "첫 질문",
      turns: [u1, a1, u2, a2, u3]
    ))

    let restored = store.rewind(toUserTurnID: u2.id)

    XCTAssertEqual(restored?.id, u2.id)
    XCTAssertEqual(restored?.text, "두 번째 질문")
    XCTAssertEqual(store.conversation.turns.map(\.id), [u1.id, a1.id])
  }

  func testRewindReturnsAttachmentsForComposerRestore() {
    let first = turn(.user, "첫 질문")
    let attached = Attachment(name: "화면.png", kind: .image, path: "/tmp/화면.png")
    let target = Turn(role: .user, text: "이미지 질문", attachments: [attached])
    let store = ConversationStore(conversation: Conversation(turns: [first, target]))

    let restored = store.rewind(toUserTurnID: target.id)

    XCTAssertEqual(restored?.attachments, [attached])
    XCTAssertEqual(store.conversation.turns.map(\.id), [first.id])
  }

  func testRewindKeepsSummaryBeforeTargetButDropsInvalidSummary() {
    let u1 = turn(.user, "q1")
    let a1 = turn(.assistant, "a1")
    let u2 = turn(.user, "q2")
    let a2 = turn(.assistant, "a2")
    let u3 = turn(.user, "q3")

    let before = ConversationStore(conversation: Conversation(
      turns: [u1, a1, u2, a2, u3],
      summary: "q1 요약",
      summaryThroughTurnID: a1.id
    ))
    before.rewind(toUserTurnID: u2.id)
    XCTAssertEqual(before.conversation.summary, "q1 요약")
    XCTAssertEqual(before.conversation.summaryThroughTurnID, a1.id)

    let after = ConversationStore(conversation: Conversation(
      turns: [u1, a1, u2, a2, u3],
      summary: "a2까지 요약",
      summaryThroughTurnID: a2.id
    ))
    after.rewind(toUserTurnID: u2.id)
    XCTAssertNil(after.conversation.summary)
    XCTAssertNil(after.conversation.summaryThroughTurnID)
    XCTAssertNil(after.conversation.activeSummary)
  }

  func testRewindFirstQuestionResetsOnlyAutoTitle() {
    let first = turn(.user, "원래 첫 질문")
    let answer = turn(.assistant, "답")
    let auto = ConversationStore(conversation: Conversation(
      title: "원래 첫 질문", titleEdited: false, turns: [first, answer]
    ))
    auto.rewind(toUserTurnID: first.id)
    XCTAssertEqual(auto.conversation.title, Conversation.defaultTitle)

    let edited = ConversationStore(conversation: Conversation(
      title: "내가 정한 제목", titleEdited: true, turns: [first, answer]
    ))
    edited.rewind(toUserTurnID: first.id)
    XCTAssertEqual(edited.conversation.title, "내가 정한 제목")
  }

  func testRewindIgnoresAssistantTurnID() {
    let user = turn(.user, "질문")
    let assistant = turn(.assistant, "답")
    let store = ConversationStore(conversation: Conversation(turns: [user, assistant]))

    XCTAssertNil(store.rewind(toUserTurnID: assistant.id))
    XCTAssertEqual(store.conversation.turns.count, 2)
  }
}
