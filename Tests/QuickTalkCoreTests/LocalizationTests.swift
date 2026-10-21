import XCTest
@testable import QuickTalkCore

final class LocalizationTests: XCTestCase {
  override func tearDown() {
    L10n.language = .system
    super.tearDown()
  }

  func testEnglishLookup() {
    L10n.language = .english
    XCTAssertEqual(L10n.effective, .en)
    XCTAssertEqual(L("설정"), "Settings")
    XCTAssertEqual(L("새 대화"), "New conversation")
    XCTAssertEqual(Lf("%d턴", 3), "3 turns")
    XCTAssertEqual(Lf("%d분 %d초", 1, 5), "1m 5s")
    // 보간 문구의 인자 순서가 유지된다
    XCTAssertEqual(Lf("%d턴 · %@ · %@", 2, "10:00", "Kept"), "2 turns · 10:00 · Kept")
  }

  func testKoreanLookup() {
    L10n.language = .korean
    XCTAssertEqual(L("설정"), "설정")
    XCTAssertEqual(Lf("%d턴", 3), "3턴")
  }

  func testUnknownKeyFallsBackToKorean() {
    L10n.language = .english
    XCTAssertEqual(L("번역이 없는 문구"), "번역이 없는 문구")
  }

  func testTableHasNoEmptyTranslations() {
    for (key, value) in L10n.table {
      XCTAssertFalse(value.isEmpty, "빈 번역: \(key)")
    }
  }

  func testDeleteConfirmationStringsAreTranslated() {
    L10n.language = .english
    XCTAssertEqual(L("대화 기록을 삭제할까요?"), "Delete this conversation?")
    XCTAssertEqual(L("기록을 모두 지울까요?"), "Clear all history?")
    XCTAssertEqual(Lf("대화 %d개", 12), "12 conversations")
    XCTAssertEqual(Lf("이 대화의 %d개 턴이 기록에서 삭제됩니다. 되돌릴 수 없습니다.", 4),
                   "All 4 turns in this conversation will be removed from history. This cannot be undone.")
    XCTAssertEqual(L("이 대화가 기록에서 삭제됩니다. 되돌릴 수 없습니다."),
                   "This conversation will be removed from history. This cannot be undone.")
  }

  func testSettingsRoundTripKeepsAppearanceAndLanguage() throws {
    var s = QuickTalkSettings()
    s.appearance = .dark
    s.language = .english
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.appearance, .dark)
    XCTAssertEqual(back.language, .english)
  }

  func testLegacySettingsDefaultToSystem() throws {
    // 기존 사용자의 설정 파일에는 appearance/language 키가 없다 → 시스템 기본
    let json = #"{"showMenuBarIcon":true,"showDockIcon":false}"#.data(using: .utf8)!
    let s = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertEqual(s.appearance, .system)
    XCTAssertEqual(s.language, .system)
  }

  func testDurationFormatting() {
    L10n.language = .korean
    XCTAssertEqual(L10n.duration(ms: 900), "0.9초")
    XCTAssertEqual(L10n.duration(ms: 72_000), "1분 12초")
    L10n.language = .english
    XCTAssertEqual(L10n.duration(ms: 900), "0.9s")
    XCTAssertEqual(L10n.duration(ms: 72_000), "1m 12s")
  }
}
