import XCTest
@testable import QuickTalkCore

/// 읽어주기 목소리 목록 규칙 — 설치된 목소리 중 **고른 언어만** + **품질 높은 순**(2026-10-20 추가).
final class SpeechCatalogTests: XCTestCase {

  private let voices = [
    SpeechVoice(id: "compact.ko.KYURI", name: "규리", language: "ko-KR", quality: 1),
    SpeechVoice(id: "enhanced.ko.SORA", name: "소라", language: "ko-KR", quality: 2),
    SpeechVoice(id: "premium.ko.SUJIN", name: "수진", language: "ko-KR", quality: 3),
    SpeechVoice(id: "compact.en-US.SAMANTHA", name: "Samantha", language: "en-US", quality: 1),
    SpeechVoice(id: "compact.en-GB.DANIEL", name: "Daniel", language: "en-GB", quality: 1)
  ]

  func testMatchingKeepsOnlyTheLanguage() {
    let ko = SpeechCatalog.voices(matching: "ko-KR", from: voices)
    XCTAssertEqual(ko.count, 3)
    XCTAssertTrue(ko.allSatisfy { $0.language == "ko-KR" })
  }

  func testMatchingUsesPrimaryLanguageWhenRegionHasNoVoices() {
    // "en" → en-US·en-GB 모두(지역 차이는 표시 이름으로 구분)
    XCTAssertEqual(SpeechCatalog.voices(matching: "en", from: voices).count, 2)
    // "en-US" → 그 지역 목소리만
    XCTAssertEqual(SpeechCatalog.voices(matching: "en-US", from: voices).map(\.name), ["Samantha"])
    // "en-AU" → 설치된 목소리가 없으니 주 언어("en")로 넓힌다(무음이 되지 않게)
    XCTAssertEqual(SpeechCatalog.voices(matching: "en-AU", from: voices).count, 2)
    // 한국어는 지역까지 일치
    XCTAssertEqual(SpeechCatalog.voices(matching: "ko-KR", from: voices).count, 3)
  }

  func testSortsByQualityThenName() {
    let ko = SpeechCatalog.voices(matching: "ko-KR", from: voices)
    XCTAssertEqual(ko.map(\.name), ["수진", "소라", "규리"], "프리미엄 → 향상 → 기본 순")
    XCTAssertEqual(ko.map(\.quality), [3, 2, 1])
  }

  func testEmptyLanguageReturnsEverything() {
    XCTAssertEqual(SpeechCatalog.voices(matching: "", from: voices).count, voices.count)
  }

  /// macOS는 같은 목소리를 compact·super-compact 두 벌로 준다 — 목록에 두 번 보이면 고를 수 없다
  func testDuplicatePackagingKeepsBestQuality() {
    let dupes = [
      SpeechVoice(id: "super-compact.ko.YUNA", name: "Yuna", language: "ko-KR", quality: 0),
      SpeechVoice(id: "compact.ko.YUNA", name: "Yuna", language: "ko-KR", quality: 1)
    ]
    let picked = SpeechCatalog.voices(matching: "ko-KR", from: dupes)
    XCTAssertEqual(picked.count, 1)
    XCTAssertEqual(picked.first?.id, "compact.ko.YUNA")
    XCTAssertEqual(picked.first?.qualityLabel, "기본")
  }

  /// Siri 자연스러운 목소리는 시스템 이름이 "음성 2"라 알아볼 수 없다
  func testSiriNaturalVoiceGetsReadableName() {
    let v = SpeechVoice(id: "com.apple.siri.natural.Minji", name: "음성 2",
                        language: "ko-KR", quality: 2)
    XCTAssertEqual(v.friendlyName, "Siri 자연스러운 (Minji)")
    XCTAssertTrue(v.displayName.hasPrefix("Siri 자연스러운 (Minji) · "))
    XCTAssertEqual(v.qualityLabel, "향상")
  }

  func testLowQualityLabel() {
    XCTAssertEqual(SpeechVoice(id: "x", name: "n", language: "ko-KR", quality: 0).qualityLabel, "저품질")
  }

  func testDisplayNameShowsQuality() {
    let v = SpeechVoice(id: "x", name: "수진", language: "ko-KR", quality: 3)
    XCTAssertEqual(v.qualityLabel, "프리미엄")
    XCTAssertEqual(v.displayName, "수진 · \(SpeechCatalog.languageName("ko-KR")) · 프리미엄")
  }

  func testLanguagesAreUniqueAndSorted() {
    let langs = SpeechCatalog.languages(from: voices)
    XCTAssertEqual(Set(langs), ["ko-KR", "en-US", "en-GB"])
    XCTAssertEqual(langs.count, 3, "중복 제거")

    let ko = Locale(identifier: "ko_KR")
    let names = langs.map { SpeechCatalog.languageName($0, locale: ko) }
    XCTAssertEqual(names.last, "한국어(대한민국)", "한국어가 마지막")
    XCTAssertEqual(names.dropLast().allSatisfy { $0.hasPrefix("영어") }, true)
    XCTAssertEqual(SpeechCatalog.languageName("", locale: ko), "시스템 기본")
    XCTAssertEqual(SpeechCatalog.languageName("xx-YY", locale: ko), "xx-YY", "모르는 코드는 그대로 보여준다")
  }
}
