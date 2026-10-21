import XCTest
@testable import QuickTalkCore

/// 보관함 검색 결과 → 그 턴으로 이동 (2026-10-20)
/// 검색어와 처음 일치하는 턴을 찾는 순수 로직만 테스트한다(스크롤·깜빡임은 뷰 몫).
final class ConversationSearchTests: XCTestCase {
  private func sample() -> Conversation {
    Conversation(title: "배포 스크립트", turns: [
      Turn(role: .user, text: "오늘 서버 배포 어떻게 해?"),
      Turn(role: .assistant, text: "**배포**는 `scripts/deploy.sh`를 실행하면 됩니다."),
      Turn(role: .user, text: "롤백은?"),
      Turn(role: .assistant, text: "롤백은 deploy.sh --rollback 으로 되돌립니다.")
    ])
  }

  func testFindsUserTurn() {
    let c = sample()
    XCTAssertEqual(c.firstTurn(matching: "서버 배포")?.role, .user)
    XCTAssertEqual(c.firstTurn(matching: "서버 배포")?.id, c.turns[0].id)
  }

  func testFindsAssistantTurnIgnoringCase() {
    let c = sample()
    // 마크다운 원문(`**배포**`) 안의 단어도 찾는다
    XCTAssertEqual(c.firstTurn(matching: "DEPLOY.SH")?.role, .assistant)
    XCTAssertEqual(c.firstTurn(matching: "deploy.sh")?.id, c.turns[1].id)
  }

  func testEmptyQueryReturnsNil() {
    let c = sample()
    XCTAssertNil(c.firstTurn(matching: ""))
    XCTAssertNil(c.firstTurn(matching: "   \n"))
    XCTAssertNil(c.firstTurn(matching: "없는 단어"))
  }

  func testFirstMatchWinsWhenBothSidesContainQuery() {
    let c = sample()
    // 두 번째 턴(응답)과 네 번째 턴(응답)에 '롤백'이 있지만, '롤백은?' 질문이 먼저다
    XCTAssertEqual(c.firstTurn(matching: "롤백")?.id, c.turns[2].id)
  }
}
