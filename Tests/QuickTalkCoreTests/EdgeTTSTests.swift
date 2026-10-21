import XCTest
@testable import QuickTalkCore

/// Edge TTS(2026-10-20) — 속도 눈금 변환·CLI 인자·목소리 목록·설정 저장.
final class EdgeTTSTests: XCTestCase {

  func testRatePercentMapping() {
    // Apple 슬라이더 기본값(0.48) = Edge 0%, 양끝은 -50% · +55%
    XCTAssertEqual(EdgeTTS.ratePercent(fromRate: 0.48), 0)
    XCTAssertEqual(EdgeTTS.ratePercent(fromRate: 0.35), -50)
    XCTAssertEqual(EdgeTTS.ratePercent(fromRate: 0.62), 55)
    // 5% 단위로 반올림
    XCTAssertEqual(EdgeTTS.ratePercent(fromRate: 0.50), 10)
  }

  func testRateArgumentAlwaysSigned() {
    XCTAssertEqual(EdgeTTS.rateArgument(percent: 0), "+0%")
    XCTAssertEqual(EdgeTTS.rateArgument(percent: -15), "-15%")
    XCTAssertEqual(EdgeTTS.rateArgument(percent: 25), "+25%")
  }

  func testArgumentsBuild() {
    let args = EdgeTTS.arguments(text: "안녕하세요", voice: "", ratePercent: 10, outputPath: "/tmp/a.mp3")
    XCTAssertEqual(args, ["--voice", EdgeTTS.defaultVoice,
                          "--text", "안녕하세요",
                          "--rate", "+10%",
                          "--write-media", "/tmp/a.mp3"])
  }

  func testVoiceFilteringAndLookup() {
    let korean = EdgeTTS.voices(matching: "ko-KR")
    XCTAssertFalse(korean.isEmpty)
    XCTAssertTrue(korean.allSatisfy { $0.locale == "ko-KR" })
    // 지원하지 않는 언어는 전체 목록으로 폴백
    XCTAssertEqual(EdgeTTS.voices(matching: "xx-XX").count, EdgeTTS.voices.count)
    XCTAssertEqual(EdgeTTS.voice(id: "en-US-AvaMultilingualNeural")?.name, "Ava")
    XCTAssertNil(EdgeTTS.voice(id: "nope"))
  }

  func testVoiceDisplayNameIsLocalizedByLanguage() {
    let v = EdgeTTS.voices.first { $0.id == "ko-KR-SunHiNeural" }
    XCTAssertNotNil(v)
    XCTAssertTrue(v?.displayName.contains("SunHi") ?? false)
  }

  func testSettingsRoundTripKeepsEdgeFields() throws {
    var settings = QuickTalkSettings()
    settings.ttsEngine = .edge
    settings.edgeVoice = "en-US-AvaMultilingualNeural"
    settings.edgeBinaryPath = "/opt/homebrew/bin/edge-tts"
    let data = try JSONEncoder().encode(settings)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.ttsEngine, .edge)
    XCTAssertEqual(back.edgeVoice, "en-US-AvaMultilingualNeural")
    XCTAssertEqual(back.edgeBinaryPath, "/opt/homebrew/bin/edge-tts")
  }

  func testLegacySettingsDefaultToAppleEngine() throws {
    // Edge 키가 없던 예전 설정 파일도 Apple 엔진으로 열려야 한다
    let legacy: [String: Any] = ["ttsLanguage": "ko-KR", "ttsRate": 0.48]
    let data = try JSONSerialization.data(withJSONObject: legacy)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.ttsEngine, .apple)
    XCTAssertEqual(back.edgeVoice, EdgeTTS.defaultVoice)
    XCTAssertEqual(back.edgeBinaryPath, "")
  }
}
