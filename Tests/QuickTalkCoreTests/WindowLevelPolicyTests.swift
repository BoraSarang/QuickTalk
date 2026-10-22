import XCTest
@testable import QuickTalkCore

// [FEATURE] 창 레벨 정책 테스트 (2026-10-22)
//
// 배경: 사용자가 "최상위(📌) 클릭 해 놨는데 동작 안하는데? 대화창 + 설정창이 떠 있으면 먹히질 않음"이라고 보고했다.
// 원인은 설정 창이 보이는 동안 대화 창을 **일반 레벨로 내리던** 규칙이었다.
// 이제 규칙은: 핀은 설정 창과 무관하게 유지하고, 설정 창만 **쓰는 동안** 그 위에 올린다.

final class WindowLevelPolicyTests: XCTestCase {

  // MARK: 대화 창

  func testPanelFloatsWhenPinned() {
    XCTAssertEqual(WindowLevelPolicy.panel(wantTop: true, systemPrompt: false), .floating)
  }

  func testPanelIsNormalWithoutPin() {
    XCTAssertEqual(WindowLevelPolicy.panel(wantTop: false, systemPrompt: false), .normal)
  }

  func testPanelIsNormalDuringSystemPrompt() {
    // TCC 안내·시스템 설정 딥링크는 다른 앱 창이라 올릴 수 없다 → 잠시 내린다.
    XCTAssertEqual(WindowLevelPolicy.panel(wantTop: true, systemPrompt: true), .normal)
  }

  // MARK: 설정·정보 창

  func testAuxSitsAbovePinnedPanelWhileInUse() {
    XCTAssertEqual(WindowLevelPolicy.aux(wantTop: true, systemPrompt: false,
                                        appActive: true, inUse: true), .floatingAbove)
  }

  func testAuxStaysNormalWhenNotInUse() {
    // 대화를 읽는 중(설정 창은 키 창이 아님) — 핀 켜진 대화 창을 가리지 않는다.
    XCTAssertEqual(WindowLevelPolicy.aux(wantTop: true, systemPrompt: false,
                                        appActive: true, inUse: false), .normal)
  }

  func testAuxIsNormalWhenAppInactive() {
    // 설정 창이 다른 앱 위에 남지 않게.
    XCTAssertEqual(WindowLevelPolicy.aux(wantTop: true, systemPrompt: false,
                                        appActive: false, inUse: true), .normal)
  }

  func testAuxIsNormalWhenPanelIsNotPinned() {
    XCTAssertEqual(WindowLevelPolicy.aux(wantTop: false, systemPrompt: false,
                                        appActive: true, inUse: true), .normal)
  }

  func testAuxIsNormalDuringSystemPrompt() {
    XCTAssertEqual(WindowLevelPolicy.aux(wantTop: true, systemPrompt: true,
                                        appActive: true, inUse: true), .normal)
  }
}
