import XCTest
@testable import QuickTalkCore

// [FEATURE] Shortcuts/AppIntent 자동 전송 — 옵트인 (2026-10-29)
//
// 계약
//   · 기본 설정(꺼짐)에서는 '보내기' 요청이 와도 전송하지 않는다(초안만).
//   · 설정을 켠 경우에만 '질문하고 보내기' 동작이 전송한다.
//   · '질문 채우기'는 요청 자체가 `requested = false` 이므로 설정과 무관하게 전송하지 않는다.
//   · 구버전 설정(키 없음)은 꺼짐으로 읽힌다.

final class ShortcutAutoSendTests: XCTestCase {
  func testDefaultSettingIsOff() throws {
    let json = #"{"showMenuBarIcon":true}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertFalse(settings.shortcutAutoSend)
  }

  func testRoundTripsEnabledSetting() throws {
    var settings = QuickTalkSettings()
    settings.shortcutAutoSend = true
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self,
                                           from: JSONEncoder().encode(settings))
    XCTAssertTrue(decoded.shortcutAutoSend)
  }

  func testSendsOnlyWhenRequestedAndEnabled() {
    XCTAssertFalse(ShortcutAutoSend.shouldSend(requested: true, enabled: false))
    XCTAssertTrue(ShortcutAutoSend.shouldSend(requested: true, enabled: true))
    // '질문 채우기'는 설정이 켜져 있어도 전송하지 않는다.
    XCTAssertFalse(ShortcutAutoSend.shouldSend(requested: false, enabled: true))
    XCTAssertFalse(ShortcutAutoSend.shouldSend(requested: false, enabled: false))
  }
}
