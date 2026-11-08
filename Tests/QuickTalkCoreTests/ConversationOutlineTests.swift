import XCTest
@testable import QuickTalkCore

/// 대화 목차(v0.32) — 질문 추출·미리보기·현재 위치 계산·검색.
/// 화면은 뷰 몫이고, 여기서는 **순수 규칙**만 검증한다.
final class ConversationOutlineTests: XCTestCase {
  private func turn(_ text: String, role: TurnRole = .user,
                    attachments: [Attachment] = []) -> Turn {
    Turn(role: role, text: text, attachments: attachments)
  }

  // MARK: - entries

  func testEntriesUseOnlyUserTurnsInOrder() {
    let turns = [turn("첫 질문"), turn("답변", role: .assistant),
                 turn("둘째 질문"), turn("답변2", role: .assistant), turn("셋째 질문")]
    let entries = ConversationOutline.entries(from: turns)
    XCTAssertEqual(entries.map(\.preview), ["첫 질문", "둘째 질문", "셋째 질문"])
    XCTAssertEqual(entries.map(\.index), [0, 1, 2])
    // ID 는 그 질문 턴의 것 — 점프 대상
    XCTAssertEqual(entries[1].id, turns[2].id)
  }

  func testPreviewTakesFirstNonEmptyLineAndTrims() {
    let entries = ConversationOutline.entries(from: [
      turn("\n\n   첫 줄만  \n둘째 줄은 버린다")
    ])
    XCTAssertEqual(entries.first?.preview, "첫 줄만")
  }

  func testPreviewTruncatesAtFortyCharacters() {
    let long = String(repeating: "가", count: 60)
    let entries = ConversationOutline.entries(from: [turn(long)])
    XCTAssertEqual(entries.first?.preview.count, ConversationOutline.previewLength)
    // 40자 이하는 그대로
    let exact = String(repeating: "나", count: 40)
    XCTAssertEqual(ConversationOutline.entries(from: [turn(exact)]).first?.preview, exact)
  }

  func testEmptyBodyFallsBackToImageThenAttachment() {
    let image = turn("", attachments: [Attachment(name: "shot.png", kind: .image)])
    let file = turn("   ", attachments: [Attachment(name: "notes.txt", kind: .text)])
    let none = turn("")
    XCTAssertEqual(ConversationOutline.preview(for: image), L("이미지"))
    XCTAssertEqual(ConversationOutline.preview(for: file), L("첨부"))
    XCTAssertEqual(ConversationOutline.preview(for: none), L("첨부"))
  }

  func testShouldShowNeedsThreeQuestions() {
    XCTAssertFalse(ConversationOutline.shouldShow([]))
    XCTAssertFalse(ConversationOutline.shouldShow(
      ConversationOutline.entries(from: [turn("a"), turn("b")])))
    XCTAssertTrue(ConversationOutline.shouldShow(
      ConversationOutline.entries(from: [turn("a"), turn("b"), turn("c")])))
  }

  // MARK: - currentIndex

  func testCurrentIndexPicksLastQuestionAboveAnchor() {
    let turns = [turn("q1"), turn("a1", role: .assistant), turn("q2"),
                 turn("a2", role: .assistant), turn("q3")]
    let entries = ConversationOutline.entries(from: turns)
    let offsets: [UUID: CGFloat] = [
      turns[0].id: 0, turns[2].id: 400, turns[4].id: 900
    ]
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: -10, entries: entries), 0)
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: 0, entries: entries), 0)
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: 399, entries: entries), 0)
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: 400, entries: entries), 1)
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: 950, entries: entries), 2)
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: [:], anchorY: 500, entries: entries), 0)
    XCTAssertNil(ConversationOutline.currentIndex(offsets: offsets, anchorY: 0, entries: []))
  }

  func testCurrentIndexSkipsQuestionsWithoutOffset() {
    let turns = [turn("q1"), turn("a1", role: .assistant), turn("q2")]
    let entries = ConversationOutline.entries(from: turns)
    // 첫 질문의 위치를 아직 못 쟀으면 0(안전한 기본값)으로 둔다.
    let offsets: [UUID: CGFloat] = [turns[2].id: 300]
    XCTAssertEqual(ConversationOutline.currentIndex(offsets: offsets, anchorY: 500, entries: entries), 1)
  }

  // MARK: - visibleIndex (LazyVStack — 일부 좌표만 측정된 경우)

  func testVisibleIndexMatchesCurrentIndexWhenAllOffsetsKnown() {
    let turns = [turn("q1"), turn("a1", role: .assistant), turn("q2"),
                 turn("a2", role: .assistant), turn("q3")]
    let entries = ConversationOutline.entries(from: turns)
    let offsets: [UUID: CGFloat] = [turns[0].id: 0, turns[2].id: 400, turns[4].id: 900]
    for anchor in [-10, 0, 399, 400, 950] as [CGFloat] {
      XCTAssertEqual(ConversationOutline.visibleIndex(
        offsets: offsets, anchorY: anchor, entries: entries),
        ConversationOutline.currentIndex(offsets: offsets, anchorY: anchor, entries: entries))
    }
    XCTAssertNil(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 0, entries: []))
  }

  func testVisibleIndexInterpolatesBetweenMeasuredQuestions() {
    let turns = (0..<6).map { turn("q\($0)") }
    let entries = ConversationOutline.entries(from: turns)
    // 0번(q0, y=0)과 4번(q4, y=800)만 측정 — q2 는 화면 밖이라 모른다.
    let offsets: [UUID: CGFloat] = [turns[0].id: 0, turns[4].id: 800]
    // 질문 간격은 200 — anchor 400 은 q2, 500 은 q2(내림), 790 은 q3.
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 400, entries: entries), 2)
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 500, entries: entries), 2)
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 790, entries: entries), 3)
  }

  func testVisibleIndexEstimatesUpwardWhenOnlyLowerQuestionsMeasured() {
    let turns = (0..<8).map { turn("q\($0)") }
    let entries = ConversationOutline.entries(from: turns)
    // 맨 아래로 이동한 직후 — 아래 3개만 측정됐고 기준선은 그 위에 있다.
    let offsets: [UUID: CGFloat] = [turns[5].id: 5000, turns[6].id: 5200, turns[7].id: 5400]
    // 200 간격 → anchor 4800 은 4번, 4600 은 3번.
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 4800, entries: entries), 4)
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 4600, entries: entries), 3)
    // 한참 위로 올라가도 0 아래로 내려가지 않는다.
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: offsets, anchorY: 0, entries: entries), 0)
  }

  func testVisibleIndexUsesSafeDefaults() {
    let turns = [turn("q1"), turn("q2")]
    let entries = ConversationOutline.entries(from: turns)
    XCTAssertEqual(ConversationOutline.visibleIndex(offsets: [:], anchorY: 500, entries: entries), 0)
    XCTAssertEqual(ConversationOutline.visibleIndex(
      offsets: [turns[1].id: 300], anchorY: 0, entries: entries), 0)
  }

  // MARK: - filter

  func testFilterIsCaseInsensitiveAndIgnoresWhitespace() {
    let entries = ConversationOutline.entries(from: [
      turn("Report 상태 알려줘"), turn("다음 실행 일정은?"), turn("권한을 다시 승인할까?")
    ])
    XCTAssertEqual(ConversationOutline.filter(entries, query: "  REPORT ").count, 1)
    XCTAssertEqual(ConversationOutline.filter(entries, query: "일정").first?.preview, "다음 실행 일정은?")
    XCTAssertEqual(ConversationOutline.filter(entries, query: "").count, 3)
    XCTAssertTrue(ConversationOutline.filter(entries, query: "없는질문").isEmpty)
  }
}
