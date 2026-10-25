import XCTest
@testable import QuickTalkCore

// [FEATURE] 창 연결 테스트 (P0-1, 2026-10-25)
//
// 고정하는 규칙:
//   1) 접근성 텍스트는 **사람이 읽을 수 있게** 정리한다(제어문자 제거, 빈 줄 2줄까지).
//   2) 길면 **줄 경계**에서 자르고, 잘랐다는 사실을 모델·사용자에게 알린다.
//   3) 창 목록에서 시스템 UI·너무 작은 창은 뺀다.
//   4) 첨부 본문은 "읽기 전용 · 다시 읽을 수 없는 단일 스냅샷"을 먼저 밝힌다.
//   5) 텍스트가 없으면 스크린샷만 보낸다는 사실을 숨기지 않는다.

final class WindowContextTests: XCTestCase {

  override func setUp() {
    super.setUp()
    L10n.language = .korean
  }

  override func tearDown() {
    L10n.language = .system
    super.tearDown()
  }

  // MARK: - 도우미

  private func target(app: String = "Safari",
                      bundleID: String = "com.apple.Safari",
                      title: String = "애플 개발자 문서",
                      width: CGFloat = 1200,
                      height: CGFloat = 800) -> WindowTarget {
    WindowTarget(id: 42, pid: 1234, bundleID: bundleID, appName: app,
                 title: title, width: width, height: height)
  }

  private func snapshot(text: String = "본문",
                        selected: String = "",
                        truncated: Bool = false,
                        screenshot: Bool = false,
                        title: String = "애플 개발자 문서") -> WindowSnapshot {
    WindowSnapshot(target: target(title: title), text: text,
                   selectedText: selected, truncated: truncated,
                   hasScreenshot: screenshot)
  }

  // MARK: - sanitize

  func testSanitizeNormalizesLineEndings() {
    XCTAssertEqual(WindowContextPrompt.sanitize("가\r\n나\r다"), "가\n나\n다")
  }

  func testSanitizeRemovesControlCharactersButKeepsTabs() {
    let raw = "가\u{0007}나\t다\u{0000}"
    XCTAssertEqual(WindowContextPrompt.sanitize(raw), "가나\t다")
  }

  func testSanitizeTrimsTrailingSpacesOnEachLine() {
    XCTAssertEqual(WindowContextPrompt.sanitize("가   \n나\t "), "가\n나")
  }

  func testSanitizeCollapsesLongBlankRunsToTwoLines() {
    let raw = "가\n\n\n\n\n나"
    XCTAssertEqual(WindowContextPrompt.sanitize(raw), "가\n\n\n나")
  }

  func testSanitizeTrimsOuterWhitespace() {
    XCTAssertEqual(WindowContextPrompt.sanitize("\n\n  가  \n\n"), "가")
  }

  func testSanitizeOfWhitespaceOnlyIsEmpty() {
    XCTAssertTrue(WindowContextPrompt.sanitize(" \n\t\n ").isEmpty)
  }

  // MARK: - truncate

  func testTruncateLeavesShortTextUntouched() {
    let (text, truncated) = WindowContextPrompt.truncate("짧은 글", limit: 100)
    XCTAssertEqual(text, "짧은 글")
    XCTAssertFalse(truncated)
  }

  func testTruncateCutsAtLineBoundary() {
    // limit 12 — 9번째 글자 뒤가 줄 경계이고 limit의 절반(6)을 넘으므로 그 줄에서 끊는다.
    let raw = "첫 번째 줄입니다\n두 번째 줄입니다"
    let (text, truncated) = WindowContextPrompt.truncate(raw, limit: 12)
    XCTAssertTrue(truncated)
    XCTAssertEqual(text, "첫 번째 줄입니다")
  }

  func testTruncateFallsBackToHardCutWhenNoGoodLineBoundary() {
    let raw = "가나다라마바사아자차카타파하"
    let (text, truncated) = WindowContextPrompt.truncate(raw, limit: 5)
    XCTAssertTrue(truncated)
    XCTAssertEqual(text, "가나다라마")
  }

  func testTruncateIgnoresEarlyLineBoundary() {
    // 줄 경계가 limit의 절반보다 앞이면 그 줄에서 끊지 않는다(너무 많이 버리지 않게).
    let raw = "가\n" + String(repeating: "나", count: 30)
    let (text, truncated) = WindowContextPrompt.truncate(raw, limit: 10)
    XCTAssertTrue(truncated)
    XCTAssertEqual(text.count, 10)
  }

  func testTruncateWithZeroLimitReturnsOriginal() {
    let (text, truncated) = WindowContextPrompt.truncate("가나다", limit: 0)
    XCTAssertEqual(text, "가나다")
    XCTAssertFalse(truncated)
  }

  // MARK: - 창 목록 규칙

  func testSystemUIBundlesAreExcluded() {
    for bundle in ["com.apple.dock", "com.apple.controlcenter",
                   "com.apple.notificationcenterui", "com.apple.WindowManager"] {
      XCTAssertFalse(WindowContextLimits.accepts(bundleID: bundle, appName: "Dock",
                                                 title: "Dock", width: 800, height: 600),
                     "\(bundle) 은 창 목록에서 빠져야 한다")
    }
  }

  func testExcludedAppNamesCoverMissingBundleIDs() {
    XCTAssertTrue(WindowContextLimits.isExcluded(bundleID: "", appName: "Window Server"))
    XCTAssertTrue(WindowContextLimits.isExcluded(bundleID: "", appName: "Spotlight"))
    XCTAssertFalse(WindowContextLimits.isExcluded(bundleID: "com.apple.Safari", appName: "Safari"))
  }

  func testTinyWindowsAreRejected() {
    XCTAssertFalse(WindowContextLimits.accepts(bundleID: "com.apple.Safari", appName: "Safari",
                                               title: "작은 창",
                                               width: WindowContextLimits.minWidth - 1,
                                               height: 600))
    XCTAssertFalse(WindowContextLimits.accepts(bundleID: "com.apple.Safari", appName: "Safari",
                                               title: "작은 창", width: 800,
                                               height: WindowContextLimits.minHeight - 1))
  }

  func testNormalWindowIsAccepted() {
    XCTAssertTrue(WindowContextLimits.accepts(bundleID: "com.apple.Safari", appName: "Safari",
                                              title: "애플", width: 1200, height: 800))
  }

  func testWindowWithoutAnyNameIsRejected() {
    XCTAssertFalse(WindowContextLimits.accepts(bundleID: "com.example.app", appName: "   ",
                                               title: "  ", width: 800, height: 600))
  }

  // MARK: - 표시 이름

  func testDisplayTitleFallsBackToAppName() {
    XCTAssertEqual(target(app: "메모", title: "  ").displayTitle, "메모")
    XCTAssertEqual(target(app: "메모", title: "할 일").displayTitle, "할 일")
  }

  // MARK: - 첨부 본문

  func testFileBodyStatesReadOnlySingleSnapshot() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "화면 글"))
    XCTAssertTrue(body.contains("Safari"))
    XCTAssertTrue(body.contains("애플 개발자 문서"))
    XCTAssertTrue(body.contains("읽기 전용"))
    XCTAssertTrue(body.contains("다시 읽을 수 없습니다"))
    XCTAssertTrue(body.contains("화면 글"))
  }

  func testFileBodyIncludesTimestamp() {
    let formatter = WindowContextPrompt.timestampFormatter
    let date = formatter.date(from: "2026-10-25 04:12:00")!
    let snap = WindowSnapshot(target: target(), text: "본문", capturedAt: date)
    XCTAssertTrue(WindowContextPrompt.fileBody(snap).contains("2026-10-25 04:12:00"))
  }

  func testFileBodyMarksTruncation() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "앞부분", truncated: true))
    XCTAssertTrue(body.contains("앞부분"))
    XCTAssertTrue(body.contains("길어서"))
  }

  func testFileBodyIncludesSelectedTextSection() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "본문", selected: "고른 문장"))
    XCTAssertTrue(body.contains("선택된 텍스트"))
    XCTAssertTrue(body.contains("고른 문장"))
  }

  func testFileBodyOmitsSelectedSectionWhenEmpty() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "본문", selected: "   "))
    XCTAssertFalse(body.contains("선택된 텍스트"))
  }

  func testFileBodyMentionsScreenshotWhenAttached() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "본문", screenshot: true))
    XCTAssertTrue(body.contains("스크린샷"))
  }

  func testFileBodyWithoutTextPointsToScreenshot() {
    let body = WindowContextPrompt.fileBody(snapshot(text: "  ", screenshot: true))
    XCTAssertTrue(body.contains("텍스트 없음"))
    XCTAssertTrue(body.contains("스크린샷"))
  }

  func testHasNoTextIsTrueOnlyWhenBothEmpty() {
    XCTAssertTrue(snapshot(text: "", selected: "  ").hasNoText)
    XCTAssertFalse(snapshot(text: "본문").hasNoText)
    XCTAssertFalse(snapshot(text: "", selected: "고른 문장").hasNoText)
  }

  // MARK: - 미리보기

  func testPreviewTextShowsBodyWhenShort() {
    XCTAssertEqual(WindowContextPrompt.previewText(snapshot(text: "짧은 화면 글")), "짧은 화면 글")
  }

  func testPreviewTextIsCutWithEllipsis() {
    let long = String(repeating: "가", count: 2_000)
    let preview = WindowContextPrompt.previewText(snapshot(text: long), limit: 100)
    XCTAssertEqual(preview.count, 102)   // 100자 + 줄바꿈 + `…`
    XCTAssertTrue(preview.hasSuffix("…"))
  }

  func testPreviewTextExplainsWhenNothingReadable() {
    let preview = WindowContextPrompt.previewText(snapshot(text: ""))
    XCTAssertTrue(preview.contains("텍스트가 없습니다"))
  }

  // MARK: - 파일 이름

  func testTextFileNameUsesAppNameAndTxtExtension() {
    let name = WindowContextPrompt.textFileName(target())
    XCTAssertTrue(name.contains("Safari"))
    XCTAssertTrue(name.hasSuffix(".txt"))
  }

  func testImageFileNameUsesAppNameAndPngExtension() {
    let name = WindowContextPrompt.imageFileName(target())
    XCTAssertTrue(name.contains("Safari"))
    XCTAssertTrue(name.hasSuffix(".png"))
  }

  func testFileNamesAreValidPathComponents() {
    let odd = target(app: "My/App: v2", title: "a/b")
    for name in [WindowContextPrompt.textFileName(odd),
                 WindowContextPrompt.imageFileName(odd)] {
      XCTAssertFalse(name.contains("/"), "파일 이름에 경로 구분자가 들어가면 안 된다: \(name)")
      XCTAssertFalse(name.contains(":"), "파일 이름에 콜론이 들어가면 안 된다: \(name)")
    }
  }

  // MARK: - 스냅샷 기본값

  func testSnapshotDefaultsAreConservative() {
    let snap = WindowSnapshot(target: target(), text: "본문")
    XCTAssertEqual(snap.selectedText, "")
    XCTAssertFalse(snap.truncated)
    XCTAssertFalse(snap.hasScreenshot)
  }

  // MARK: - 번역

  func testWindowAttachStringsAreTranslated() {
    L10n.language = .english
    XCTAssertEqual(L("창 연결"), "Connect window")
    XCTAssertEqual(L("창 텍스트"), "Window text")
    XCTAssertEqual(L("창 스크린샷"), "window screenshot")
    XCTAssertEqual(L("손쉬운 사용"), "Accessibility")
    XCTAssertEqual(L("화면 기록"), "Screen Recording")
    XCTAssertEqual(Lf("%d자", 12), "12 chars")
  }
}
