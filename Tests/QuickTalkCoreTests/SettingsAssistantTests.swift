import XCTest
@testable import QuickTalkCore

// [FEATURE] v0.26 설정·대화 — 기존 설정을 잃지 않고 새 키만 더한다.
//
// 사용자의 설정 JSON 에는 새 키가 없다. `decodeIfPresent` + 기본값을 지키지 않으면
// 앱을 켜는 순간 설정 전체가 사라진다.

final class SettingsAssistantTests: XCTestCase {
  private var calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    c.locale = Locale(identifier: "en_US_POSIX")
    return c
  }()

  private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: 3,
                                       hour: hour, minute: minute))!
  }

  // MARK: - 설정 하위 호환

  func testLegacySettingsDecodeWithoutAssistantKeys() throws {
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: Data("{}".utf8))
    XCTAssertTrue(settings.personas.isEmpty, "기존 설정에는 비서가 없다 — 비어 있어야 한다")
    XCTAssertNil(settings.defaultPersonaID)
    XCTAssertEqual(settings.defaultReportFolder, "~/Documents/QuickTalkWorkspace")
    XCTAssertTrue(settings.schedulerEnabled)
    XCTAssertTrue(settings.notificationsEnabled)
    XCTAssertTrue(settings.quietHoursEnabled)
    XCTAssertEqual(settings.quietHoursFromMinute, 22 * 60)
    XCTAssertEqual(settings.quietHoursToMinute, 8 * 60)
    XCTAssertNil(settings.defaultPersona, "비서가 없으면 기본도 nil")
  }

  func testAssistantSettingsRoundTrip() throws {
    var settings = QuickTalkSettings()
    let persona = Persona(name: "돌쇠", role: "리포트", tone: "차분하게")
    settings.personas = [persona]
    settings.defaultPersonaID = persona.id
    settings.defaultReportFolder = "~/Documents/My Reports"
    settings.quietHoursFromMinute = 23 * 60 + 30
    settings.quietHoursToMinute = 7 * 60
    settings.notificationsEnabled = false

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(decoded, settings)
    XCTAssertEqual(decoded.defaultPersona?.name, "돌쇠")
  }

  func testPersonaNamesAreNormalizedWhenSettingsDecode() throws {
    let json = """
    {"personas":[{"id":"\(UUID().uuidString)","name":"  돌쇠  ","role":"리포트",
      "tone":"차분","tools":{"read":true,"web":true,"shell":false,"write":true,"ui":false},
      "createdAt":0}]}
    """
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: Data(json.utf8))
    XCTAssertEqual(settings.personas.first?.name, "돌쇠")
  }

  func testReportFolderPathExpandsTilde() {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkWorkspace"
    XCTAssertEqual(settings.reportFolderPath,
                   NSHomeDirectory() + "/Documents/QuickTalkWorkspace")
  }

  func testEmptyReportFolderFallsBackToDefault() {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "   "
    XCTAssertEqual(settings.reportFolderPath,
                   NSHomeDirectory() + "/Documents/QuickTalkWorkspace")
  }

  // MARK: - 야간 무음

  func testQuietHoursWrapPastMidnight() {
    let settings = QuickTalkSettings()
    XCTAssertTrue(settings.isQuietHours(at: at(23, 0), calendar: calendar))
    XCTAssertTrue(settings.isQuietHours(at: at(3, 0), calendar: calendar))
    XCTAssertTrue(settings.isQuietHours(at: at(7, 59), calendar: calendar))
    XCTAssertFalse(settings.isQuietHours(at: at(8, 0), calendar: calendar), "끝 시각은 무음이 아니다")
    XCTAssertFalse(settings.isQuietHours(at: at(21, 59), calendar: calendar))
    XCTAssertTrue(settings.isQuietHours(at: at(22, 0), calendar: calendar), "시작 시각은 무음이다")
  }

  func testQuietHoursCanBeTurnedOff() {
    var settings = QuickTalkSettings()
    settings.quietHoursEnabled = false
    XCTAssertFalse(settings.isQuietHours(at: at(23, 0), calendar: calendar))
  }

  func testSameQuietStartAndEndDisablesWindow() {
    var settings = QuickTalkSettings()
    settings.quietHoursFromMinute = 9 * 60
    settings.quietHoursToMinute = 9 * 60
    XCTAssertFalse(settings.isQuietHours(at: at(9, 0), calendar: calendar))
  }

  // MARK: - 대화의 비서

  func testLegacyConversationDecodesWithoutPersona() throws {
    let json = """
    {"id":"\(UUID().uuidString)","title":"예전 대화","turns":[],
     "updatedAt":0}
    """
    let conversation = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
    XCTAssertNil(conversation.personaID, "기존 대화는 비서 없음(nil) — 마이그레이션 없음")
  }

  func testConversationRoundTripKeepsPersona() throws {
    let personaID = UUID()
    let conversation = Conversation(title: "리포트", personaID: personaID)
    let data = try JSONEncoder().encode(conversation)
    XCTAssertEqual(try JSONDecoder().decode(Conversation.self, from: data).personaID, personaID)
  }
}
