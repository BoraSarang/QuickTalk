import XCTest
@testable import QuickTalkCore

/// 대화방 제목 — 첫 질문 자동 생성 · 사용자 변경 (2026-10-20)
/// 화면(시트)은 뷰 몫이고, 제목 규칙·보존·마이그레이션만 순수 로직으로 검증한다.
final class ConversationTitleTests: XCTestCase {
  func testDerivedTitleCollapsesWhitespaceAndNewlines() {
    XCTAssertEqual(Conversation.derivedTitle(from: "  오늘\n네이버   뉴스\t알려줘  "),
                   "오늘 네이버 뉴스 알려줘")
    XCTAssertEqual(Conversation.derivedTitle(from: "\n\n"), "")
  }

  func testDerivedTitleTruncatesAtLimitWithEllipsis() {
    let long = String(repeating: "가", count: 40)
    let title = Conversation.derivedTitle(from: long, limit: 30)
    XCTAssertEqual(title, String(repeating: "가", count: 30) + "…")
    // 30자 이하는 그대로
    XCTAssertEqual(Conversation.derivedTitle(from: "짧은 질문"), "짧은 질문")
  }

  func testSubmitAutoTitlesFromFirstQuestionOnly() throws {
    let store = ConversationStore()
    try store.submit(text: "  구구단\n만들어줘 ")
    XCTAssertEqual(store.conversation.title, "구구단 만들어줘")
    XCTAssertFalse(store.conversation.titleEdited)

    // 두 번째 질문은 제목을 바꾸지 않는다
    try store.submit(text: "2단도 보여줘")
    XCTAssertEqual(store.conversation.title, "구구단 만들어줘")
  }

  func testAttachmentOnlyFirstQuestionUsesFilename() throws {
    let store = ConversationStore()
    try store.submit(text: "", attachments: [Attachment(name: "회의록.txt", kind: .text)])
    XCTAssertEqual(store.conversation.title, "회의록.txt")
  }

  func testUserRenameIsNeverOverwrittenByAutoTitle() throws {
    let store = ConversationStore()
    try store.submit(text: "구구단 만들어줘")
    XCTAssertTrue(store.rename(to: "  구구단 연습  "))
    XCTAssertEqual(store.conversation.title, "구구단 연습")
    XCTAssertTrue(store.conversation.titleEdited)

    try store.submit(text: "3단도")
    XCTAssertEqual(store.conversation.title, "구구단 연습")
    XCTAssertEqual(store.conversation.displayTitle, "구구단 연습")
  }

  func testRenameRejectsBlankTitle() throws {
    let store = ConversationStore()
    try store.submit(text: "질문")
    XCTAssertFalse(store.rename(to: "   \n "))
    XCTAssertEqual(store.conversation.title, "질문")
  }

  /// 구버전 기록: `titleEdited` 키가 없고 제목이 "새 대화"로 저장돼 있어도 첫 질문을 보여 준다.
  func testLegacyRecordWithoutTitleEditedFallsBackToFirstQuestion() throws {
    let json = """
    {"id":"6E2B0F1A-0000-4000-8000-000000000001","title":"새 대화",
     "turns":[{"id":"6E2B0F1A-0000-4000-8000-000000000002","role":"user","text":"오래된 질문",
               "attachments":[],"status":"done"}],
     "pinned":false,"updatedAt":0}
    """
    let c = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
    XCTAssertFalse(c.titleEdited)
    XCTAssertEqual(c.displayTitle, "오래된 질문")

    // 저장 → 다시 읽기 왕복에서도 사용자 지정 플래그가 보존된다
    let data = try JSONEncoder().encode(c)
    let back = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertFalse(back.titleEdited)
    XCTAssertEqual(back.displayTitle, "오래된 질문")
  }

  func testNormalizedFillsMissingTitlesAndKeepsUserTitles() {
    var legacy = Conversation(title: "새 대화",
                              turns: [Turn(role: .user, text: "제목 없는 옛 대화")])
    legacy.updatedAt = Date(timeIntervalSince1970: 0)
    var renamed = Conversation(title: "내가 정한 제목", titleEdited: true,
                               turns: [Turn(role: .user, text: "다른 질문")])
    renamed.updatedAt = Date(timeIntervalSince1970: 1)

    let list = ConversationHistory.normalized([legacy, renamed])
    XCTAssertEqual(list.first { $0.id == legacy.id }?.title, "제목 없는 옛 대화")
    XCTAssertEqual(list.first { $0.id == renamed.id }?.title, "내가 정한 제목")
  }

  func testOpeningLegacyConversationAppliesAutoTitle() {
    let legacy = Conversation(title: "새 대화",
                              turns: [Turn(role: .user, text: "열 때 제목 채우기")])
    let store = ConversationStore(conversation: Conversation())
    store.open(legacy)
    XCTAssertEqual(store.conversation.title, "열 때 제목 채우기")
  }
}
