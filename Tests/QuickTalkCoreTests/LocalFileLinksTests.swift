import XCTest
@testable import QuickTalkCore

/// 답변 속 로컬 파일·폴더 링크 (2026-11-08) — 존재하는 경로만, 코드 블록은 그대로.
final class LocalFileLinksTests: XCTestCase {
  private var root: URL!
  private var folder: URL!
  private var report: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuickTalkLocalFileLinks-\(UUID().uuidString)", isDirectory: true)
    folder = root.appendingPathComponent("QuickTalkReport", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    report = folder.appendingPathComponent("OpenCode-Zen-Free-Models.md")
    FileManager.default.createFile(atPath: report.path, contents: Data("hello".utf8))
  }

  override func tearDownWithError() throws {
    if let root { try? FileManager.default.removeItem(at: root) }
  }

  // MARK: - 기본

  func testExistingAbsoluteFileBecomesLink() {
    let text = "리포트: \(report.path)"
    let linked = LocalFileLinks.link(text)
    XCTAssertTrue(linked.contains("[\(report.path)](file://"), linked)
    XCTAssertTrue(linked.contains(".md)"), linked)
  }

  func testExistingFolderBecomesLink() {
    let linked = LocalFileLinks.link("폴더: \(folder.path)")
    XCTAssertTrue(linked.contains("[\(folder.path)](file://"), linked)
  }

  func testMissingPathIsNotLinked() {
    let missing = folder.appendingPathComponent("없는파일.md").path
    XCTAssertEqual(LocalFileLinks.link("보고서: \(missing)"), "보고서: \(missing)")
  }

  func testBareFileNameResolvesAgainstMentionedFolder() {
    let text = "리포트 폴더: \(folder.path)\n- report.md\n- OpenCode-Zen-Free-Models.md"
    // report.md 는 없고 두 번째만 존재한다.
    let linked = LocalFileLinks.link(text)
    XCTAssertFalse(linked.contains("[report.md]"), linked)
    XCTAssertTrue(linked.contains("[OpenCode-Zen-Free-Models.md](file://"), linked)
  }

  func testBareFileNameResolvesAgainstExtraDirectory() {
    let text = "- OpenCode-Zen-Free-Models.md"
    let linked = LocalFileLinks.link(text, extraDirectories: [folder.path])
    XCTAssertTrue(linked.contains("[OpenCode-Zen-Free-Models.md](file://"), linked)
  }

  // MARK: - 건드리면 안 되는 곳

  func testCodeFenceIsUntouched() {
    let text = """
    ```sh
    cat \(report.path)
    ```
    \(report.path)
    """
    let linked = LocalFileLinks.link(text)
    XCTAssertTrue(linked.contains("cat \(report.path)"), linked)
    XCTAssertEqual(linked.components(separatedBy: "cat \(report.path)").count, 2,
                   "코드 펜스 안은 링크로 바뀌지 않는다")
    XCTAssertTrue(linked.contains("[\(report.path)](file://"), "펜스 밖은 링크가 된다")
  }

  func testInlineCodeIsLeftForTheRenderer() {
    let text = "`\(report.path)` 그리고 `OpenCode-Zen-Free-Models.md`"
    XCTAssertEqual(LocalFileLinks.link(text, extraDirectories: [folder.path]), text,
                   "인라인 코드는 모노 글꼴을 유지하려고 렌더 단계에서 링크로 만든다")
  }

  func testExistingMarkdownLinkIsNotDoubleWrapped() {
    let text = "[보고서](\(report.path))"
    XCTAssertEqual(LocalFileLinks.link(text), text)
  }

  func testWebURLIsNotMistakenForAPath() {
    let text = "참고: https://example.com/docs/OpenCode-Zen-Free-Models.md"
    XCTAssertEqual(LocalFileLinks.link(text, extraDirectories: [folder.path]), text)
  }

  func testBoldPathIsNotCorruptedByLinkSyntax() {
    // `**…**` 안에 링크 문법을 넣으면 토크나이저가 글자 그대로 보여 준다 → 건드리지 않는다.
    let text = "**\(report.path)**"
    XCTAssertEqual(LocalFileLinks.link(text), text)
  }

  // MARK: - 인라인 코드용 해석

  func testURLForInlineCodeAbsoluteAndBareName() {
    XCTAssertEqual(LocalFileLinks.url(for: report.path, directories: []),
                   URL(fileURLWithPath: report.path))
    XCTAssertEqual(LocalFileLinks.url(for: "OpenCode-Zen-Free-Models.md", directories: [folder.path]),
                   URL(fileURLWithPath: report.path))
    XCTAssertNil(LocalFileLinks.url(for: "없는파일.md", directories: [folder.path]))
    XCTAssertNil(LocalFileLinks.url(for: "그냥코드", directories: [folder.path]))
  }

  // MARK: - 문장부호

  func testTrailingSentencePunctuationIsTrimmed() {
    let linked = LocalFileLinks.link("보고서: \(report.path).")
    XCTAssertTrue(linked.contains("[\(report.path)](file://"),
                  "문장 끝 점은 링크 라벨에 들어가지 않는다: \(linked)")
  }
}
