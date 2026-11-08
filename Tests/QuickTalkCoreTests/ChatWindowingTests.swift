import XCTest
@testable import QuickTalkCore

/// 대화 윈도잉(v0.35.3) — 최근 턴부터 글자 예산만큼 그리는 **순수 규칙**.
final class ChatWindowingTests: XCTestCase {
  func testEmptyOrSingleTurnRendersEverything() {
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [], budget: 6_000), 0)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [12_000], budget: 6_000), 0)
  }

  func testTwoTurnsAreAlwaysShownEvenOverBudget() {
    // 마지막 두 턴이 예산을 크게 넘어도 질문+답변은 보여 준다.
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [100, 8_000, 9_000], budget: 6_000), 1)
  }

  func testBudgetLargeEnoughRendersFromStart() {
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [1_000, 1_000, 1_000], budget: 6_000), 0)
  }

  func testStopsWhenNextTurnWouldExceedBudget() {
    // 최근 2턴 = 1,000. 예산 6,000 이면 그 앞의 500+500 은 들어가고(2,000) 5,000 은 넘는다.
    let counts = [5_000, 500, 500, 500, 500]
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 6_000), 1)
    // 예산을 7,000 으로 올리면 그 5,000 턴까지 들어간다.
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 7_000), 0)
  }

  func testExactBudgetIncludesThatTurn() {
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [4_000, 3_000, 3_000], budget: 6_000), 1)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [2_000, 2_000, 2_000], budget: 6_000), 0)
  }

  func testHugeFinalTurnStillShowsQuestionAndAnswer() {
    let counts = [10, 10, 40_000]
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 6_000), 1)
  }

  func testUnlimitedBudgetRendersEverything() {
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: [9_999, 9_999, 9_999], budget: .max), 0)
  }

  func testCustomMinimumTurns() {
    let counts = [100, 100, 100, 100, 100]
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 0, minimumTurns: 0), 0)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 250, minimumTurns: 2), 3)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 250, minimumTurns: 3), 2)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 250, minimumTurns: 4), 1)
  }

  func testStepExpandsWindow() {
    // 10턴 × 1,000자. 기본 6,000 → 마지막 6턴. 한 단계(12,000) → 전부.
    let counts = Array(repeating: 1_000, count: 10)
    var start = ChatWindowing.startIndex(charCounts: counts, budget: ChatWindowing.baseCharBudget)
    XCTAssertEqual(start, 4)
    start = ChatWindowing.startIndex(charCounts: counts,
                                     budget: ChatWindowing.baseCharBudget + ChatWindowing.step)
    XCTAssertEqual(start, 0)
  }

  func testBudgetShrinksWindow() {
    let counts = Array(repeating: 1_000, count: 10)
    XCTAssertEqual(ChatWindowing.startIndex(charCounts: counts, budget: 2_000), 8)
  }
}
