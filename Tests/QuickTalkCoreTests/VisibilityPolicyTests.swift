import XCTest
@testable import QuickTalkCore

/// 표시 정책: 메뉴바·Dock을 모두 숨기면 앱 진입점이 사라지므로 최소 1개를 강제한다.
final class VisibilityPolicyTests: XCTestCase {
  func testHidingMenuBarTurnsDockOn() {
    var s = QuickTalkSettings()          // 기본: 메뉴바 O, Dock X
    s.setMenuBarIcon(false)
    XCTAssertFalse(s.showMenuBarIcon)
    XCTAssertTrue(s.showDockIcon, "메뉴바를 숨기면 Dock 진입점이 자동으로 켜져야 한다")
  }

  func testHidingDockTurnsMenuBarOn() {
    var s = QuickTalkSettings()
    s.showMenuBarIcon = false
    s.showDockIcon = true                // 메뉴바 숨김 + Dock 표시
    s.setDockIcon(false)
    XCTAssertFalse(s.showDockIcon)
    XCTAssertTrue(s.showMenuBarIcon, "Dock을 숨기면 메뉴바 진입점이 자동으로 켜져야 한다")
  }

  func testShowingIsIndependent() {
    var s = QuickTalkSettings()
    s.setDockIcon(true)
    XCTAssertTrue(s.showMenuBarIcon)
    XCTAssertTrue(s.showDockIcon)
    s.setMenuBarIcon(true)
    XCTAssertEqual(s.showMenuBarIcon, true)
    XCTAssertEqual(s.showDockIcon, true)
  }

  func testNormalizeRepairsBothHidden() {
    var s = QuickTalkSettings()
    s.showMenuBarIcon = false
    s.showDockIcon = false
    XCTAssertTrue(s.normalizeVisibility())
    XCTAssertFalse(s.showMenuBarIcon)
    XCTAssertTrue(s.showDockIcon)
    XCTAssertFalse(s.normalizeVisibility(), "이미 정상 상태면 변경 없음")
  }
}
