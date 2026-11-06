import XCTest
@testable import QuickTalkCore

/// 후속 질문 제안(v0.32) — 자격 조건·프롬프트 길이·파싱·무료 폴백.
final class FollowUpSuggestTests: XCTestCase {
  private let answer = String(repeating: "이번 주 예약 작업은 정상입니다. ", count: 8)

  // MARK: - isEligible

  func testShortAnswerIsNotEligible() {
    XCTAssertFalse(FollowUpSuggest.isEligible(question: "질문", answer: "짧은 답"))
    XCTAssertTrue(FollowUpSuggest.isEligible(question: "질문", answer: answer))
  }

  func testErrorAndStoppedAnswersAreNotEligible() {
    let long = String(repeating: "내용 ", count: 40)
    XCTAssertFalse(FollowUpSuggest.isEligible(question: "질문", answer: "(오류 E-MAC-NET-0001) " + long))
    XCTAssertFalse(FollowUpSuggest.isEligible(question: "질문", answer: "(Error E-MAC-NET-0001) " + long))
    XCTAssertFalse(FollowUpSuggest.isEligible(question: "질문", answer: long + "\n\n⏹ 중지됨"))
  }

  func testEmptyQuestionIsNotEligible() {
    XCTAssertFalse(FollowUpSuggest.isEligible(question: "   ", answer: answer))
  }

  // MARK: - prompt

  func testPromptClampsQuestionAndAnswer() {
    let longQ = String(repeating: "가", count: 900)
    let longA = String(repeating: "나", count: 900)
    let prompt = FollowUpSuggest.prompt(question: longQ, answer: longA)
    XCTAssertTrue(prompt.contains("[질문]"))
    XCTAssertTrue(prompt.contains("[답변]"))
    // 원문 900자 + 말줄임표가 아니라 상한 + "…" 로 잘린다
    XCTAssertTrue(prompt.contains(String(repeating: "가", count: FollowUpSuggest.maxQuestionChars) + "…"))
    XCTAssertTrue(prompt.contains(String(repeating: "나", count: FollowUpSuggest.maxAnswerChars) + "…"))
    XCTAssertFalse(prompt.contains(String(repeating: "가", count: FollowUpSuggest.maxQuestionChars + 1)))
  }

  func testPromptUsesRequestedCount() {
    XCTAssertTrue(FollowUpSuggest.prompt(question: "q", answer: "a", count: 4).contains("4개"))
  }

  // MARK: - parse

  func testParseNumberedList() {
    let raw = """
    다음 질문을 추천합니다:
    1. 권한 오류는 어떻게 고쳐?
    2) 실패한 작업을 다시 예약해줘?
    - 이번 주 리포트는 언제 나와?
    """
    XCTAssertEqual(FollowUpSuggest.parse(raw), [
      "권한 오류는 어떻게 고쳐?",
      "실패한 작업을 다시 예약해줘?",
      "이번 주 리포트는 언제 나와?"
    ])
  }

  func testParseJSONArray() {
    let raw = #"["권한 오류는 어떻게 고쳐?", "다음 실행은 언제야?", "리포트는 어디에 저장돼?"]"#
    XCTAssertEqual(FollowUpSuggest.parse(raw).count, 3)
    XCTAssertEqual(FollowUpSuggest.parse(raw).first, "권한 오류는 어떻게 고쳐?")
  }

  func testParseDropsHeadersDuplicatesAndCodeFences() {
    let raw = """
    ```text
    후속 질문:
    1. 같은 질문?
    2. 같은 질문?
    3. 다른 질문은 뭐야?
    ```
    """
    XCTAssertEqual(FollowUpSuggest.parse(raw), ["같은 질문?", "다른 질문은 뭐야?"])
  }

  func testParseLimitsCount() {
    let raw = (1...6).map { "\($0). 질문 \($0)은 뭐야?" }.joined(separator: "\n")
    XCTAssertEqual(FollowUpSuggest.parse(raw).count, FollowUpSuggest.defaultCount)
  }

  func testParseRejectsOverlongChip() {
    let long = String(repeating: "가", count: FollowUpSuggest.maxChipChars + 1)
    XCTAssertTrue(FollowUpSuggest.parse("1. \(long)?").isEmpty)
  }

  // MARK: - fallback

  func testFallbackAlwaysFillsRequestedCount() {
    for count in 1...4 {
      let chips = FollowUpSuggest.fallback(question: "질문", answer: "짧은 답", count: count)
      XCTAssertEqual(chips.count, count)
      XCTAssertEqual(Set(chips).count, chips.count, "중복 없음")
      XCTAssertTrue(chips.allSatisfy { !$0.isEmpty })
    }
  }

  func testFallbackPicksAnswerKeywords() {
    let errorAnswer = String(repeating: "권한 오류가 발생했습니다. ", count: 10)
    let chips = FollowUpSuggest.fallback(question: "상태 알려줘", answer: errorAnswer)
    XCTAssertEqual(chips.count, 3)
    XCTAssertTrue(chips.contains(L("이 오류를 고치는 방법은?")),
                  "오류 답변이면 고치는 방법을 먼저 제안한다")
    XCTAssertTrue(chips.contains(L("권한은 어떻게 허용해?")))
  }

  func testFallbackHasNoDuplicateWhenKeywordsOverlap() {
    let answer = String(repeating: "설정에서 권한 오류를 고치세요. ", count: 10)
    let chips = FollowUpSuggest.fallback(question: "질문", answer: answer, count: 4)
    XCTAssertEqual(chips.count, 4)
    XCTAssertEqual(Set(chips).count, 4)
  }
}
