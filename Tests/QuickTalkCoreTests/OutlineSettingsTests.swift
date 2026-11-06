import XCTest
@testable import QuickTalkCore

/// 대화 목차 · 후속 질문 설정(v0.32) — 기본값·왕복·구버전 폴백.
final class OutlineSettingsTests: XCTestCase {
  func testDefaultsMatchRecommendation() {
    let settings = QuickTalkSettings()
    XCTAssertEqual(settings.outlineDisplay, .both, "레일 + 셸프 보조가 기본")
    XCTAssertTrue(settings.outlineShowPosition)
    XCTAssertTrue(settings.followUpsEnabled)
    XCTAssertEqual(settings.followUpSource, .model)
    XCTAssertTrue(settings.followUpAutoSend)
  }

  func testOutlineDisplayRoundTrips() throws {
    for mode in OutlineDisplay.allCases {
      var settings = QuickTalkSettings()
      settings.outlineDisplay = mode
      let back = try JSONDecoder().decode(QuickTalkSettings.self,
                                          from: try JSONEncoder().encode(settings))
      XCTAssertEqual(back.outlineDisplay, mode)
    }
  }

  func testFollowUpsRoundTrip() throws {
    var settings = QuickTalkSettings()
    settings.followUpsEnabled = false
    settings.followUpSource = .template
    settings.followUpAutoSend = false
    settings.outlineShowPosition = false
    let back = try JSONDecoder().decode(QuickTalkSettings.self,
                                        from: try JSONEncoder().encode(settings))
    XCTAssertFalse(back.followUpsEnabled)
    XCTAssertEqual(back.followUpSource, .template)
    XCTAssertFalse(back.followUpAutoSend)
    XCTAssertFalse(back.outlineShowPosition)
  }

  func testUnknownValuesFallBackWithoutLosingOtherSettings() throws {
    // 다운그레이드·손상: 모르는 enum 이라도 그 항목만 기본값, 나머지는 살린다.
    let json = #"{"outlineDisplay":"floating","followUpSource":"llm","keepDays":7}"#
      .data(using: .utf8)!
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertEqual(settings.outlineDisplay, .both)
    XCTAssertEqual(settings.followUpSource, .model)
    XCTAssertEqual(settings.keepDays, 7)
  }

  func testLegacySettingsWithoutOutlineKeysFallBack() throws {
    let json = #"{"previewLines":3}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertEqual(settings.outlineDisplay, .both)
    XCTAssertTrue(settings.followUpsEnabled)
    XCTAssertEqual(settings.previewLines, 3)
  }

  func testDisplayFlags() {
    XCTAssertFalse(OutlineDisplay.off.showsRail)
    XCTAssertFalse(OutlineDisplay.off.showsShelf)
    XCTAssertTrue(OutlineDisplay.rail.showsRail)
    XCTAssertFalse(OutlineDisplay.rail.showsShelf)
    XCTAssertFalse(OutlineDisplay.shelf.showsRail)
    XCTAssertTrue(OutlineDisplay.shelf.showsShelf)
    XCTAssertTrue(OutlineDisplay.both.showsRail)
    XCTAssertTrue(OutlineDisplay.both.showsShelf)
  }
}
