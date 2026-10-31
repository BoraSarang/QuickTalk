import XCTest
@testable import QuickTalkCore

// [FEATURE] ⌘Space 토글 판정 테스트 (2026-10-31)
//
// 배경: 사용자가 대화 창을 띄운 뒤 다른 앱을 조작하다가 ⌘Space 를 다시 누르면
// 창이 **사라져야** 하는데, 화면 중앙으로 이동하며 앞으로 나왔다.
//   원인: "창이 보이지만 키 창이 아님"을 "앞으로 가져와야 함"으로 해석했다.
// 고정하는 규칙:
//   1) pill 이 떠 있으면 pill 을 닫는다(창보다 우선).
//   2) 창이 보이면 **키 창 여부와 무관하게** 숨긴다 — 위치를 바꾸지 않는다.
//   3) 둘 다 없을 때만 새로 연다.

final class PanelToggleTests: XCTestCase {

  func testPillTakesPriorityOverPanel() {
    XCTAssertEqual(PanelToggle.decide(pillVisible: true, panelVisible: true), .dismissPill)
    XCTAssertEqual(PanelToggle.decide(pillVisible: true, panelVisible: false), .dismissPill)
  }

  func testVisiblePanelIsHiddenEvenWhenNotKey() {
    // 핵심 회귀: 다른 앱이 앞에 있어 창이 키가 아니어도 숨긴다.
    XCTAssertEqual(PanelToggle.decide(pillVisible: false, panelVisible: true), .hidePanel)
  }

  func testNothingVisibleOpens() {
    XCTAssertEqual(PanelToggle.decide(pillVisible: false, panelVisible: false), .show)
  }
}
