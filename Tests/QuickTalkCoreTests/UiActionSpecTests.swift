import XCTest
@testable import QuickTalkCore

// [FEATURE] 화면 조작 인자 검증 (PLAN_v0.25 Phase 2)
//
// 고정하는 것
//   · 좌표(x·y)는 어떤 형태로도 받지 않는다.
//   · `purpose` 는 필수다 — 카드에서 사람이 판단할 재료.
//   · 참조는 `r<n>` 형식만, click 은 참조가 필수다.
//   · 텍스트·키·스크롤·앱·창 인자의 빈 값·범위를 실행 전에 막는다.

final class UiActionSpecTests: XCTestCase {
  private func parse(_ json: String) -> Result<UiActionSpec, UiActionError> {
    UiActionSpec.parse(arguments: json)
  }

  private func failure(_ json: String) -> UiActionError? {
    if case .failure(let error) = parse(json) { return error }
    return nil
  }

  // MARK: - 공통

  func testMissingPurposeIsRejected() {
    XCTAssertEqual(failure(#"{"action":"click","ref":"r1"}"#), .missingPurpose)
  }

  func testCoordinatesAreRejected() {
    XCTAssertEqual(failure(#"{"action":"click","ref":"r1","purpose":"저장","x":100,"y":200}"#),
                   .coordinatesNotSupported)
  }

  func testUnknownActionIsRejected() {
    XCTAssertEqual(failure(#"{"action":"drag","purpose":"이동"}"#), .unknownAction("drag"))
  }

  func testMalformedArgumentsAreRejected() {
    XCTAssertEqual(failure("not json"), .malformedArguments)
  }

  // MARK: - 클릭

  func testClickParsesRefAndCount() throws {
    let spec = try parse(#"{"action":"click","ref":"R12","click_count":2,"purpose":"열기"}"#).get()
    XCTAssertEqual(spec.kind, .click)
    XCTAssertEqual(spec.ref, "r12", "참조는 소문자로 정규화한다")
    XCTAssertEqual(spec.amount, 2)
    XCTAssertTrue(spec.requiresRef)
  }

  func testClickWithoutRefIsRejected() {
    XCTAssertEqual(failure(#"{"action":"click","purpose":"열기"}"#), .missingRef)
  }

  func testClickWithBadRefIsRejected() {
    XCTAssertEqual(failure(#"{"action":"click","ref":"button-1","purpose":"열기"}"#),
                   .invalidRef("button-1"))
  }

  func testClickCountOutOfRangeIsRejected() {
    XCTAssertEqual(failure(#"{"action":"click","ref":"r1","click_count":3,"purpose":"열기"}"#),
                   .invalidAmount)
  }

  // MARK: - 텍스트

  func testTypeRequiresText() {
    XCTAssertEqual(failure(#"{"action":"type","ref":"r1","purpose":"입력"}"#), .emptyText)
    XCTAssertEqual(failure(#"{"action":"type","text":"   ","purpose":"입력"}"#), .emptyText)
  }

  func testTypeRejectsTextOverLimit() {
    let long = String(repeating: "a", count: UiGuard.maxTextLength + 1)
    XCTAssertEqual(failure(#"{"action":"type","text":"\#(long)","purpose":"입력"}"#), .textTooLong)
  }

  func testTypeWithoutRefUsesFocusedField() throws {
    let spec = try parse(#"{"action":"type","text":"안녕","purpose":"입력"}"#).get()
    XCTAssertNil(spec.ref)
    XCTAssertFalse(spec.requiresRef)
    XCTAssertEqual(spec.text, "안녕")
  }

  // MARK: - 키

  func testKeyRequiresKeys() {
    XCTAssertEqual(failure(#"{"action":"key","purpose":"저장"}"#), .emptyKeys)
  }

  func testKeyParsesCombination() throws {
    let spec = try parse(#"{"action":"key","keys":"cmd+s","purpose":"저장"}"#).get()
    XCTAssertEqual(spec.keys, "cmd+s")
  }

  // MARK: - 스크롤

  func testScrollDefaultsToDownThree() throws {
    let spec = try parse(#"{"action":"scroll","purpose":"아래로"}"#).get()
    XCTAssertEqual(spec.direction, .down)
    XCTAssertEqual(spec.amount, 3)
  }

  func testScrollRejectsBadDirectionAndAmount() {
    XCTAssertEqual(failure(#"{"action":"scroll","direction":"left","purpose":"이동"}"#),
                   .invalidDirection("left"))
    XCTAssertEqual(failure(#"{"action":"scroll","amount":21,"purpose":"이동"}"#), .invalidAmount)
    XCTAssertEqual(failure(#"{"action":"scroll","amount":0,"purpose":"이동"}"#), .invalidAmount)
  }

  // MARK: - 앱 · 창

  func testOpenAppRequiresApp() {
    XCTAssertEqual(failure(#"{"action":"open_app","purpose":"열기"}"#), .missingApp)
  }

  func testFocusWindowRequiresTitle() {
    XCTAssertEqual(failure(#"{"action":"focus_window","app":"Notes","purpose":"앞으로"}"#),
                   .missingTitle)
  }

  // MARK: - 카드 · 감사 문구

  func testDescribeAndAuditUseTarget() throws {
    let spec = try parse(#"{"action":"click","ref":"r1","app":"Notes","purpose":"저장"}"#).get()
    let target = UiActionTarget(role: "button", name: "저장", isSecure: false)
    XCTAssertEqual(spec.describe(appName: "Notes", target: target), "Notes에서 button \"저장\"을(를) 클릭")
    XCTAssertEqual(spec.auditCommand(appName: "Notes", target: target), "ui:click Notes \"저장\"")
  }

  func testLineBreakTextMaySend() throws {
    let spec = try parse(#"{"action":"type","text":"안녕\n잘 가","purpose":"보내기"}"#).get()
    XCTAssertTrue(spec.maySend, "줄바꿈은 메일·메신저에서 전송일 수 있다")
  }
}
