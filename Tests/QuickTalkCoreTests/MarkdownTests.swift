import XCTest
@testable import QuickTalkCore

/// AI 답변 마크다운 렌더러(2026-10-20) — 블록 파서·인라인 토크나이저·낭독용 평문.
/// CapsuleStash `MarkdownBody`(T-26) 파서를 옮기고 번호 목록·중첩·링크·구분선을 더했다.
final class MarkdownTests: XCTestCase {

  // MARK: - 블록

  func testHeadingAndParagraph() {
    let segments = MarkdownSegment.parse("# 제목\n첫 줄\n둘째 줄")
    XCTAssertEqual(segments, [
      .heading(level: 1, text: "제목"),
      .paragraph(lines: ["첫 줄", "둘째 줄"])
    ])
  }

  func testHeadingKeepsDeepLevelsForTheViewToClamp() {
    XCTAssertEqual(MarkdownSegment.parse("#### 넷"), [.heading(level: 4, text: "넷")])
    XCTAssertEqual(MarkdownSegment.parse("#해시없음"), [.paragraph(lines: ["#해시없음"])],
                   "공백이 없으면 제목이 아니다")
  }

  func testBulletsKeepIndentDepth() {
    let segments = MarkdownSegment.parse("- 하나\n  - 둘\n    - 셋\n- 넷")
    XCTAssertEqual(segments, [
      .bullet(items: [
        MarkdownItem(text: "하나", depth: 0),
        MarkdownItem(text: "둘", depth: 1),
        MarkdownItem(text: "셋", depth: 2),
        MarkdownItem(text: "넷", depth: 0)
      ])
    ])
  }

  func testNumberedListAndTypeSwitchStartsNewSegment() {
    let segments = MarkdownSegment.parse("1. 하나\n2) 둘\n- 불릿")
    XCTAssertEqual(segments, [
      .numbered(items: [MarkdownItem(text: "하나"), MarkdownItem(text: "둘")]),
      .bullet(items: [MarkdownItem(text: "불릿")])
    ])
  }

  func testDateIsNotMistakenForANumberedList() {
    XCTAssertEqual(MarkdownSegment.parse("2026. 10. 20 회의"),
                   [.paragraph(lines: ["2026. 10. 20 회의"])])
  }

  func testQuote() {
    XCTAssertEqual(MarkdownSegment.parse("> 인용\n> 둘째"), [.quote(lines: ["인용", "둘째"])])
  }

  func testFencedCodeKeepsLanguageAndLines() {
    let text = "설명\n```swift\nlet a = 1\n\nlet b = 2\n```\n끝"
    XCTAssertEqual(MarkdownSegment.parse(text), [
      .paragraph(lines: ["설명"]),
      .code(language: "swift", lines: ["let a = 1", "", "let b = 2"]),
      .paragraph(lines: ["끝"])
    ])
  }

  func testUnclosedFenceIsStillCode() {
    XCTAssertEqual(MarkdownSegment.parse("```\n줄1\n줄2"),
                   [.code(language: "", lines: ["줄1", "줄2"])])
  }

  func testTable() {
    let text = "| 이름 | 값 |\n|---|---|\n| 가 | 1 |\n| 나 | 2 |"
    XCTAssertEqual(MarkdownSegment.parse(text), [
      .table(header: ["이름", "값"], rows: [["가", "1"], ["나", "2"]])
    ])
  }

  func testRuleVersusBulletAndTableDelimiter() {
    XCTAssertEqual(MarkdownSegment.parse("---"), [.rule])
    XCTAssertEqual(MarkdownSegment.parse("***"), [.rule])
    XCTAssertEqual(MarkdownSegment.parse("- 항목"), [.bullet(items: [MarkdownItem(text: "항목")])],
                   "'- 항목'은 불릿이지 구분선이 아니다")
    XCTAssertEqual(MarkdownSegment.parse("| a |\n|---|\n| b |"),
                   [.table(header: ["a"], rows: [["b"]])],
                   "|---|는 표 구분행이지 구분선이 아니다")
  }

  func testTaskList() {
    XCTAssertEqual(MarkdownSegment.parse("- [ ] 할 일\n- [x] 끝난 일\n- [X] 대문자\n- 보통 항목"), [
      .bullet(items: [MarkdownItem(text: "할 일", task: false),
                      MarkdownItem(text: "끝난 일", task: true),
                      MarkdownItem(text: "대문자", task: true),
                      MarkdownItem(text: "보통 항목")])
    ])
    // `[ ]`가 문장 중간에 있으면 체크박스가 아니다
    XCTAssertEqual(MarkdownSegment.parse("- 배열 [ ] 표기"), [
      .bullet(items: [MarkdownItem(text: "배열 [ ] 표기")])
    ])
  }

  func testTaskListPlainTextKeepsLabel() {
    XCTAssertEqual(MarkdownPlain.text("- [x] 배포 확인"), "배포 확인")
  }

  func testBlankLineSeparatesParagraphs() {
    XCTAssertEqual(MarkdownSegment.parse("첫 문단\n\n둘째 문단"), [
      .paragraph(lines: ["첫 문단"]), .blank, .paragraph(lines: ["둘째 문단"])
    ])
  }

  // MARK: - 인라인

  func testInlineTokens() {
    XCTAssertEqual(MarkdownInline.tokenize("**굵게** 그리고 *기울임* 그리고 `코드`"), [
      .bold("굵게"), .plain(" 그리고 "), .italic("기울임"), .plain(" 그리고 "), .code("코드")
    ])
  }

  func testInlineLink() {
    XCTAssertEqual(MarkdownInline.tokenize("[네이버](https://naver.com) 링크"), [
      .link(label: "네이버", url: "https://naver.com"), .plain(" 링크")
    ])
  }

  func testUnmatchedMarkersStayLiteral() {
    XCTAssertEqual(MarkdownInline.tokenize("**열림"), [.plain("**열림")])
    XCTAssertEqual(MarkdownInline.tokenize("a * b"), [.plain("a * b")])
    XCTAssertEqual(MarkdownInline.tokenize("`열림"), [.plain("`열림")])
  }

  func testCitationLinkSyntax() {
    XCTAssertEqual(MarkdownInline.tokenize("근거 [[1]](https://example.com) 입니다"), [
      .plain("근거 "), .link(label: "[1]", url: "https://example.com"), .plain(" 입니다")
    ])
  }

  func testCitationLinksOnlyKnownNumbers() {
    let text = "근거 [1]와 [2], 범위 밖 [9], 코드 `[1]`"
    let linked = CitationLinks.link(text, urls: ["https://a.example", "https://b.example"])
    XCTAssertTrue(linked.contains("[[1]](https://a.example)"))
    XCTAssertTrue(linked.contains("[[2]](https://b.example)"))
    XCTAssertTrue(linked.contains("[9]"))
    XCTAssertTrue(linked.contains("`[1]`"), "인라인 코드 안도 원문 그대로 둔다")
  }

  func testCitationLinksSkipCodeFencesAndExistingLinks() {
    let text = """
    ```
    [1]
    ```
    이미 링크 [[1]](https://old.example)
    """
    let linked = CitationLinks.link(text, urls: ["https://new.example"])
    XCTAssertTrue(linked.contains("```\n[1]\n```"))
    XCTAssertTrue(linked.contains("[[1]](https://old.example)"))
  }

  // MARK: - 낭독용 평문 (읽어주기)

  func testPlainTextDropsMarkup() {
    let markdown = """
    ## 요약
    **중요한** 내용과 `코드`가 있습니다.
    - 첫째
    - 둘째

    ```sh
    echo hi
    ```
    [링크](https://example.com)
    """
    let plain = MarkdownPlain.text(markdown)
    XCTAssertFalse(plain.contains("**"))
    XCTAssertFalse(plain.contains("`"))
    XCTAssertFalse(plain.contains("#"))
    XCTAssertTrue(plain.contains("중요한 내용과 코드가 있습니다."))
    XCTAssertTrue(plain.contains("첫째"))
    XCTAssertTrue(plain.contains("echo hi"))
    XCTAssertTrue(plain.contains("링크"))
    XCTAssertFalse(plain.contains("https://example.com"), "링크는 라벨만 읽는다")
  }

  func testPlainTextTableReadsCellsWithCommas() {
    let plain = MarkdownPlain.text("| 이름 | 값 |\n|---|---|\n| 가 | 1 |")
    XCTAssertEqual(plain, "이름, 값\n가, 1")
  }
}
