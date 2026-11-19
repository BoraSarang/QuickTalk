import XCTest
@testable import QuickTalkCore

/// 표시 정책(v0.40): 메뉴바·Dock 아이콘은 **독립**이고, 둘 다 꺼도 된다.
/// 아이콘이 0개일 때의 복구(재실행 → 메뉴바 아이콘 + 설정 창)는 앱 계층(AppDelegate)이 맡는다.
final class VisibilityPolicyTests: XCTestCase {
  func testDefaults() {
    let s = QuickTalkSettings()          // 기본: 메뉴바 O, Dock X
    XCTAssertTrue(s.showMenuBarIcon)
    XCTAssertFalse(s.showDockIcon)
    XCTAssertFalse(s.hasNoEntryPoint)
  }

  func testHidingMenuBarLeavesDockUnchanged() {
    var s = QuickTalkSettings()
    s.setMenuBarIcon(false)
    XCTAssertFalse(s.showMenuBarIcon)
    XCTAssertFalse(s.showDockIcon, "메뉴바를 숨겨도 Dock은 자동으로 켜지지 않는다")
    XCTAssertTrue(s.hasNoEntryPoint, "기본 Dock이 꺼져 있으므로 둘 다 없는 상태가 된다")
  }

  func testHidingDockLeavesMenuBarUnchanged() {
    var s = QuickTalkSettings()
    s.showMenuBarIcon = false
    s.showDockIcon = true                // 메뉴바 숨김 + Dock 표시
    s.setDockIcon(false)
    XCTAssertFalse(s.showDockIcon)
    XCTAssertFalse(s.showMenuBarIcon, "Dock을 숨겨도 메뉴바가 자동으로 켜지지 않는다")
    XCTAssertTrue(s.hasNoEntryPoint)
  }

  func testBothHiddenIsAllowed() {
    var s = QuickTalkSettings()
    s.showDockIcon = true
    s.setMenuBarIcon(false)
    s.setDockIcon(false)
    XCTAssertTrue(s.hasNoEntryPoint)
  }

  func testBothHiddenSurvivesEncoding() throws {
    var s = QuickTalkSettings()
    s.showMenuBarIcon = false
    s.showDockIcon = false
    let data = try JSONEncoder().encode(s)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertTrue(decoded.hasNoEntryPoint, "아이콘 0개 설정은 저장·복원돼도 유지되어야 한다")
  }

  /// 시작 시 복구는 **아이콘 0개 + 사용자 실행**일 때만. 로그인 자동 시작·QA 하네스는 조용히 시작한다.
  func testRecoveryOnLaunchOnlyForUserLaunchWithoutIcons() {
    var s = QuickTalkSettings()
    s.showMenuBarIcon = false
    s.showDockIcon = false
    XCTAssertTrue(s.shouldRecoverEntryPointOnLaunch(launchedAsLoginItem: false, isHeadlessHarness: false))
    XCTAssertFalse(s.shouldRecoverEntryPointOnLaunch(launchedAsLoginItem: true, isHeadlessHarness: false))
    XCTAssertFalse(s.shouldRecoverEntryPointOnLaunch(launchedAsLoginItem: false, isHeadlessHarness: true))

    s.showMenuBarIcon = true
    XCTAssertFalse(s.shouldRecoverEntryPointOnLaunch(launchedAsLoginItem: false, isHeadlessHarness: false),
                   "메뉴바 아이콘이 있으면 시작 시 설정 창을 열지 않는다")
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
}
