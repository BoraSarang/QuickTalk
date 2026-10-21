import XCTest
@testable import QuickTalkCore

/// 전역 단축키 모델(2026-10-20, T-59) — 문자열 파싱·표시·기본값·설정 접근·중복 검사.
final class ShortcutTests: XCTestCase {

  func testParsesTokensAndSymbols() {
    XCTAssertEqual(ShortcutCombo.parse("Cmd+Space")?.display, "⌘Space")
    XCTAssertEqual(ShortcutCombo.parse("⌥⇧3")?.canonical, "Option+Shift+3")
    XCTAssertEqual(ShortcutCombo.parse("opt+shift+3")?.canonical, "Option+Shift+3")
    XCTAssertEqual(ShortcutCombo.parse("Option+Shift+Cmd+4")?.display, "⌥⇧⌘4")
    XCTAssertEqual(ShortcutCombo.parse("Ctrl+F5")?.canonical, "Control+F5")
    XCTAssertEqual(ShortcutCombo.parse("Cmd+Return")?.keySymbol, "↩")
  }

  func testCanonicalOrderIsStable() {
    let a = ShortcutCombo.parse("Cmd+Option+Shift+3")
    let b = ShortcutCombo.parse("Shift+Option+Cmd+3")
    XCTAssertEqual(a, b)
    XCTAssertEqual(a?.canonical, "Option+Shift+Cmd+3")
  }

  func testRejectsIncompleteCombos() {
    XCTAssertNil(ShortcutCombo.parse("Space"))            // 보조 키 없음
    XCTAssertNil(ShortcutCombo.parse("Cmd+"))             // 키 없음
    XCTAssertNil(ShortcutCombo.parse("Cmd+Shift"))        // 수정자만
    XCTAssertNil(ShortcutCombo.parse("Cmd+Unicorn"))      // 알 수 없는 키
  }

  func testEveryDefaultIsParsable() {
    for action in ShortcutAction.allCases {
      XCTAssertNotNil(ShortcutCombo.parse(action.defaultCombo), action.rawValue)
    }
  }

  func testSettingsAccessorsAndConflict() {
    var s = QuickTalkSettings()
    XCTAssertEqual(s.shortcut(for: .invoke), "Cmd+Space")
    XCTAssertEqual(s.shortcut(for: .shelf), "Option+Shift+V")
    s.setShortcut("Ctrl+Option+K", for: .shelf)
    XCTAssertEqual(s.shortcut(for: .shelf), "Ctrl+Option+K")
    XCTAssertEqual(s.shortcutConflict("Ctrl+Option+K", for: .invoke), .shelf)
    XCTAssertNil(s.shortcutConflict("Ctrl+Option+K", for: .shelf))
    XCTAssertNil(s.shortcutConflict("Cmd+Space", for: .invoke))
  }

  func testLegacySettingsGetShortcutDefaults() throws {
    let legacy: [String: Any] = ["globalShortcut": "Cmd+Space"]
    let data = try JSONSerialization.data(withJSONObject: legacy)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.shelfShortcut, "Option+Shift+V")
    XCTAssertEqual(back.captureFullShortcut, "Option+Shift+3")
    XCTAssertEqual(back.captureRegionShortcut, "Option+Shift+4")
    XCTAssertEqual(back.captureWindowShortcut, "Option+Shift+Cmd+4")
  }

  func testRoundTripKeepsCustomShortcuts() throws {
    var s = QuickTalkSettings()
    s.setShortcut("Option+Shift+9", for: .captureRegion)
    s.setShortcut("Ctrl+Shift+H", for: .invoke)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: JSONEncoder().encode(s))
    XCTAssertEqual(back.captureRegionShortcut, "Option+Shift+9")
    XCTAssertEqual(back.globalShortcut, "Ctrl+Shift+H")
  }
}
