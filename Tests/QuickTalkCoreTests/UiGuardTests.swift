import XCTest
@testable import QuickTalkCore

// [FEATURE] 화면 조작 안전 판정 — 순수 계약 (PLAN_v0.25 Phase 2)
//
// 고정하는 것
//   · 금지 앱(터미널·비밀번호 관리자·시스템 설정·QuickTalk)은 승인과 무관하게 거부한다.
//   · 금지 키 조합(cmd+q 등)은 실행하지 않는다.
//   · 보안 필드·텍스트가 아닌 요소에는 입력하지 않는다.
//   · 앱 승인이 없으면 ask, 정책이 매번 확인이면 ask, 둘 다 통과해야 allow.
//   · 한 요청 30번을 넘으면 31번째는 나가지 않는다.

final class UiGuardTests: XCTestCase {
  private func spec(_ kind: UiActionKind, ref: String? = "r1", text: String? = nil,
                    keys: String? = nil, direction: UiScrollDirection? = nil,
                    amount: Int = 1, app: String? = "Notes", title: String? = nil,
                    purpose: String = "테스트") -> UiActionSpec {
    var object: [String: Any] = ["action": kind.rawValue, "purpose": purpose]
    if let ref { object["ref"] = ref }
    if let text { object["text"] = text }
    if let keys { object["keys"] = keys }
    if let direction { object["direction"] = direction.rawValue }
    if kind == .scroll { object["amount"] = amount }
    if kind == .openApp, let app { object["app"] = app }
    if kind == .focusWindow, let title { object["title"] = title }
    let data = try! JSONSerialization.data(withJSONObject: object)
    return try! UiActionSpec.parse(arguments: String(decoding: data, as: UTF8.self)).get()
  }

  private let target = UiActionTarget(role: "button", name: "저장", isSecure: false)

  private func evaluate(_ spec: UiActionSpec, target: UiActionTarget? = nil,
                        bundleID: String = "com.apple.Notes", appName: String = "Notes",
                        actions: Int = 0, grant: Bool = true,
                        policy: AgentAutoApprove = .alwaysAllow) -> UiGuardDecision {
    UiGuard.evaluate(spec: spec, target: target,
                     appBundleID: bundleID, appName: appName,
                     actionsThisTurn: actions, hasAppGrant: grant, policy: policy)
  }

  // MARK: - 금지 앱

  func testDeniedAppsAreMatchedByBundleIDAndPrefix() {
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "com.apple.Terminal"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "com.googlecode.iterm2"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "dev.warp.Warp-Stable"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "com.1password.1password"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "com.agilebits.onepassword7"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "com.borasarang.QuickTalk"))
    XCTAssertNil(UiGuard.deniedReason(bundleID: "com.apple.Notes"))
  }

  func testDeniedAppFallsBackToNameWhenBundleIDIsEmpty() {
    XCTAssertNil(UiGuard.deniedReason(bundleID: "", appName: "Notes"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "", appName: "Terminal"))
    XCTAssertNotNil(UiGuard.deniedReason(bundleID: "", appName: "Keychain Access"))
  }

  func testForbiddenAppIsDeniedEvenWithGrant() {
    let decision = evaluate(spec(.openApp), bundleID: "com.apple.Terminal",
                            appName: "Terminal", grant: true)
    guard case .deny(let reason) = decision else {
      return XCTFail("터미널은 승인과 무관하게 거부해야 한다: \(decision)")
    }
    XCTAssertTrue(reason.contains("터미널"))
  }

  // MARK: - 키

  func testAllowedKeyCombinationPasses() {
    XCTAssertNil(UiGuard.keyViolation("cmd+s"))
    XCTAssertNil(UiGuard.keyViolation("shift+tab"))
    XCTAssertNil(UiGuard.keyViolation("return"))
    XCTAssertNil(UiGuard.keyViolation("⌘+a"))
  }

  func testForbiddenKeyCombinationsAreBlocked() {
    XCTAssertNotNil(UiGuard.keyViolation("cmd+q"))
    XCTAssertNotNil(UiGuard.keyViolation("Q+CMD"), "순서·대소문자와 무관하게 막는다")
    XCTAssertNotNil(UiGuard.keyViolation("cmd+opt+esc"))
    XCTAssertNotNil(UiGuard.keyViolation("ctrl+cmd+q"))
    XCTAssertNotNil(UiGuard.keyViolation("cmd+shift+q"))
  }

  func testUnknownOrMultipleKeysAreBlocked() {
    XCTAssertNotNil(UiGuard.keyViolation("cmd+f13"))
    XCTAssertNotNil(UiGuard.keyViolation("a+b"))
    XCTAssertNotNil(UiGuard.keyViolation("cmd+"))
    XCTAssertNotNil(UiGuard.keyViolation(""))
  }

  func testForbiddenKeyIsDeniedBeforeApproval() {
    let decision = evaluate(spec(.key, ref: nil, keys: "cmd+q"), target: nil, grant: false)
    guard case .deny = decision else { return XCTFail("금지 키는 승인 전에 거부해야 한다") }
  }

  // MARK: - 보안 필드 · 역할

  func testSecureFieldRejectsTyping() {
    let secure = UiActionTarget(role: "textfield", name: "암호", isSecure: true)
    let decision = evaluate(spec(.type, text: "secret"), target: secure)
    guard case .deny(let reason) = decision else { return XCTFail("보안 필드는 거부해야 한다") }
    XCTAssertTrue(reason.contains("비밀번호"))
  }

  func testTypingIntoNonTextFieldIsRejected() {
    let decision = evaluate(spec(.type, text: "hello"), target: target)
    guard case .deny(let reason) = decision else { return XCTFail("버튼에는 입력할 수 없다") }
    XCTAssertTrue(reason.contains("입력란"))
  }

  func testTypingIntoTextFieldIsAllowedWithGrant() {
    let field = UiActionTarget(role: "textfield", name: "메모", isSecure: false)
    XCTAssertEqual(evaluate(spec(.type, text: "hello"), target: field), .allow)
  }

  // MARK: - 승인 · 정책 · 한도

  func testMissingAppGrantAsks() {
    let decision = evaluate(spec(.click), target: target, grant: false)
    guard case .ask(let reason) = decision else { return XCTFail("앱 승인이 없으면 물어야 한다") }
    XCTAssertTrue(reason.contains("처음"))
  }

  func testGrantAndAlwaysAskStillAsks() {
    let decision = evaluate(spec(.click), target: target, grant: true, policy: .alwaysAsk)
    guard case .ask = decision else { return XCTFail("매번 확인 정책은 승인 뒤에도 물어야 한다") }
  }

  func testGrantAndAlwaysAllowAllows() {
    XCTAssertEqual(evaluate(spec(.click), target: target, grant: true, policy: .alwaysAllow), .allow)
  }

  func testActionLimitDeniesTheThirtyFirstAction() {
    XCTAssertEqual(evaluate(spec(.click), target: target, actions: 29), .allow)
    let decision = evaluate(spec(.click), target: target, actions: 30)
    guard case .deny(let reason) = decision else { return XCTFail("30번을 넘으면 거부해야 한다") }
    XCTAssertTrue(reason.contains("30"))
  }

  func testDeniedAppSummaryListsEveryReasonOnce() {
    let summary = UiGuard.deniedAppSummary
    XCTAssertTrue(summary.contains("터미널"))
    XCTAssertTrue(summary.contains("비밀번호 관리자"))
    XCTAssertTrue(summary.contains("시스템 설정"))
  }
}
