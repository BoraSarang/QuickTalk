import XCTest
@testable import QuickTalkCore

/// v0.26 3단계 — Markdown 리포트 본문·요약 규칙.
final class ReportDocumentTests: XCTestCase {

  private func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Seoul")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
  }

  private var seoul: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return c
  }

  private func source(_ title: String, _ url: String, domain: String = "example.com") -> TurnSource {
    TurnSource(title: title, url: url, domain: domain)
  }

  // MARK: - 머리말

  func testHeadingHasTitleAndMeta() {
    let doc = ReportDocument(title: "테크 뉴스", personaName: "돌쇠", instruction: "요약해 줘",
                             body: "본문", sources: [], ranAt: date("2026-11-04 09:00"),
                             ruleText: "매일 09:00")
    let md = doc.markdown(calendar: seoul)
    XCTAssertTrue(md.hasPrefix("# 테크 뉴스\n"), md)
    XCTAssertTrue(md.contains("> 2026-11-04 09:00 · 돌쇠 · 매일 09:00"), md)
  }

  func testEmptyTitleFallsBack() {
    let doc = ReportDocument(title: "   ", instruction: "", body: "본문",
                             ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertTrue(md.hasPrefix("# " + L("리포트 문서")), md)
  }

  func testPersonaAndRuleOmittedWhenMissing() {
    let doc = ReportDocument(title: "리포트", instruction: "", body: "본문",
                             ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertFalse(md.contains(" ·  · "), md)
    XCTAssertTrue(md.contains("> 2026-11-04 09:00\n"), md)
  }

  // MARK: - 절 구성

  func testInstructionSectionWrittenAsCodeBlock() {
    let doc = ReportDocument(title: "리포트", instruction: "  최신 소식 정리  ",
                             body: "본문", ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertTrue(md.contains("## " + L("지시")), md)
    XCTAssertTrue(md.contains("```text\n최신 소식 정리\n```"), md)
  }

  func testEmptyInstructionOmitsSection() {
    let doc = ReportDocument(title: "리포트", instruction: "   ", body: "본문",
                             ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertFalse(md.contains("## " + L("지시")), md)
  }

  /// 출처가 없으면 "출처" 제목만 덩그러니 남지 않아야 한다.
  func testSourcesSectionOmittedWhenEmpty() {
    let doc = ReportDocument(title: "리포트", instruction: "", body: "본문",
                             sources: [], ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertFalse(md.contains("## " + L("출처")), md)
  }

  func testSourcesSectionListsLinkedURLsInOrder() {
    let doc = ReportDocument(
      title: "리포트", instruction: "", body: "본문",
      sources: [source("첫 번째", "https://a.example/1"),
                source("두 번째", "https://b.example/2", domain: "b.example")],
      ranAt: date("2026-11-04 09:00"))
    let md = doc.markdown(calendar: seoul)
    XCTAssertTrue(md.contains("## " + L("출처")), md)
    let first = md.range(of: "1. [첫 번째](https://a.example/1)")
    let second = md.range(of: "2. [두 번째](https://b.example/2) — b.example")
    XCTAssertNotNil(first)
    XCTAssertNotNil(second)
    XCTAssertLessThan(first!.lowerBound, second!.lowerBound)
  }

  func testSourceWithEmptyURLIsDropped() {
    let doc = ReportDocument(title: "리포트", instruction: "", body: "본문",
                             sources: [source("빈 링크", "")],
                             ranAt: date("2026-11-04 09:00"))
    XCTAssertFalse(doc.markdown(calendar: seoul).contains(L("출처")))
  }

  func testSourceWithoutTitleUsesDomain() {
    let doc = ReportDocument(title: "리포트", instruction: "", body: "본문",
                             sources: [source("", "https://c.example/x", domain: "c.example")],
                             ranAt: date("2026-11-04 09:00"))
    XCTAssertTrue(doc.markdown(calendar: seoul).contains("[c.example](https://c.example/x)"))
  }

  func testBodyIsTrimmedAndKeptVerbatim() {
    let doc = ReportDocument(title: "리포트", instruction: "", body: "\n  ## 상세\n값 42\n\n",
                             ranAt: date("2026-11-04 09:00"))
    XCTAssertTrue(doc.markdown(calendar: seoul).contains("## 상세\n값 42"))
  }

  // MARK: - 요약

  func testSummarySkipsHeadingsFencesAndRules() {
    let answer = """
      # 제목
      ```swift
      let x = 1
      ```
      ---
      - 첫째 핵심
      - 둘째 핵심
      3. 셋째 핵심
      나머지는 잘린다
      """
    let points = ReportDocument.summaryPoints(from: answer)
    XCTAssertEqual(points, ["제목", "첫째 핵심", "둘째 핵심"], "\(points)")
  }

  func testSummaryDeduplicatesAndLimits() {
    let answer = "같은 줄\n같은 줄\n둘\n셋\n넷"
    XCTAssertEqual(ReportDocument.summaryPoints(from: answer, limit: 3), ["같은 줄", "둘", "셋"])
  }

  func testSummaryTruncatesLongLines() {
    let long = String(repeating: "가", count: 200)
    let points = ReportDocument.summaryPoints(from: long, limit: 1, maxLength: 20)
    XCTAssertEqual(points.count, 1)
    XCTAssertEqual(points[0].count, 21, "20자 + …")
    XCTAssertTrue(points[0].hasSuffix("…"))
  }

  func testSummaryReturnsNilForEmptyAnswer() {
    XCTAssertNil(ReportDocument.summary(from: "   \n\n```\n\n"))
    XCTAssertEqual(ReportDocument.summary(from: "- 하나\n- 둘"), "하나\n둘")
  }

  func testSummaryKeepsBoldAndInlineMarkdown() {
    // 요약은 평문 카드에 그대로 들어가므로 별표를 벗기지 않는다(원문 유지).
    XCTAssertEqual(ReportDocument.summaryPoints(from: "**중요** 소식", limit: 1), ["**중요** 소식"])
  }
}
