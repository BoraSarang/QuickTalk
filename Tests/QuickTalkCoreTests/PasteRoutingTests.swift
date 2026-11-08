import XCTest
@testable import QuickTalkCore

/// v0.35.2 — 브라우저 주소창의 URL 을 붙여넣을 수 없던 회귀.
/// 클립보드가 `public.url` 로 웹 주소를 주면 `readObjects(forClasses: [NSURL.self])` 가
/// 그 주소를 돌려주는데, 예전 코드는 이를 파일로 오인해 붙여넣기를 삼켰다.
final class PasteRoutingTests: XCTestCase {
  func testWebURLsAreNotTreatedAsFiles() {
    let urls = [URL(string: "https://www.youtube.com/watch?v=9zOwUT1PdKY")!]
    XCTAssertTrue(PasteRouting.fileURLs(from: urls).isEmpty)
  }

  func testFileURLsAreKept() {
    let file = URL(fileURLWithPath: "/Users/lee/Documents/보고서.pdf")
    XCTAssertEqual(PasteRouting.fileURLs(from: [file]), [file])
  }

  func testMixedURLsKeepOnlyFiles() {
    let file = URL(fileURLWithPath: "/tmp/note.md")
    let web = URL(string: "https://example.com/a/b.html")!
    XCTAssertEqual(PasteRouting.fileURLs(from: [web, file]), [file])
  }

  func testEmptyURLList() {
    XCTAssertTrue(PasteRouting.fileURLs(from: []).isEmpty)
  }

  /// `file://` 로 시작하는 URL 문자열도 파일로 남는다(공백·한글 경로 포함).
  func testFileURLWithSpacesAndKorean() {
    let file = URL(string: "file:///Users/lee/Documents/%EB%B3%B4%EA%B3%A0%EC%84%9C%20v2.pdf")!
    XCTAssertTrue(file.isFileURL)
    XCTAssertEqual(PasteRouting.fileURLs(from: [file]), [file])
  }
}
