import XCTest
@testable import QuickTalkCore

/// 예비 모델 폴백 (2026-10-21) — 어떤 실패에서 넘어가고, 어떤 실패는 넘어가지 않는지 고정한다.
final class ProviderFallbackTests: XCTestCase {

  func testFallbackAllowedForTransientFailures() {
    XCTAssertTrue(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.rateLimited(status: 429, code: "server_error"))))
    XCTAssertTrue(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.upstream(status: 503, code: "server_error"))))
    XCTAssertTrue(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.emptyResponse(status: 200))))
    XCTAssertTrue(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.keyRejected(status: 401, code: "E-AND-AUTH-0004"))))
    XCTAssertTrue(ProviderFallback.allowed(
      after: QuickTalkError.networkUnavailable()))
    XCTAssertTrue(ProviderFallback.allowed(after: URLError(.timedOut)))
    XCTAssertTrue(ProviderFallback.allowed(after: URLError(.cannotConnectToHost)))
    XCTAssertTrue(ProviderFallback.allowed(after: URLError(.networkConnectionLost)))
    XCTAssertTrue(ProviderFallback.allowed(after: URLError(.cannotFindHost)))
  }

  func testFallbackRejectedForPolicyConfigAndAttachments() {
    // 403 정책 거부 — 다른 모델로 우회하지 않는다.
    XCTAssertFalse(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.forbidden(status: 403, code: nil))))
    // 첨부 거부는 `AttachmentRetry` 사다리가 먼저 처리한다.
    XCTAssertFalse(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.attachmentTooLarge(status: 413, code: nil))))
    XCTAssertFalse(ProviderFallback.allowed(
      after: QuickTalkError.serverFailure(.attachmentUnsupported(status: 422, code: nil))))
    // 설정 오류(모델 미지정 등)는 예비 모델로 넘어가지 않는다.
    XCTAssertFalse(ProviderFallback.allowed(
      after: QuickTalkError.detailed("모델이 비어 있습니다.", code: "E-MAC-MODEL-0002")))
    XCTAssertFalse(ProviderFallback.allowed(after: QuickTalkError.emptySubmission()))
    // 취소는 폴백 대상이 아니다.
    XCTAssertFalse(ProviderFallback.allowed(after: URLError(.cancelled)))
  }

  func testFallbackReasonIsShortAndHidesProviderCode() {
    // 429 — 한 줄에 상태·앱 코드만. 업스트림이 준 코드 문자열([server_error])은 화면에 쓰지 않는다.
    let reason = ProviderFallback.reason(
      for: QuickTalkError.serverFailure(.rateLimited(status: 429, code: "server_error")))
    XCTAssertTrue(reason.contains("429"))
    XCTAssertTrue(reason.contains("E-MAC-NET-0004"))
    XCTAssertFalse(reason.contains("server_error"))
    XCTAssertLessThan(reason.count, 40)

    XCTAssertTrue(ProviderFallback.reason(
      for: QuickTalkError.serverFailure(.upstream(status: 502, code: nil))).contains("502"))
    XCTAssertTrue(ProviderFallback.reason(for: URLError(.timedOut)).contains("시간 초과"))
    XCTAssertTrue(ProviderFallback.reason(for: URLError(.cannotConnectToHost)).contains("연결 실패"))
    // 설명 문장이 길게 붙지 않는다(말풍선 안내 한 줄).
    XCTAssertLessThan(ProviderFallback.reason(
      for: QuickTalkError.serverFailure(.upstream(status: 503, code: nil))).count, 40)
  }

  func testFallbackUsableRequiresModelKeyAndURL() {
    var remote = LLMProviderConfig.newProvider(type: .openAICompatible, existing: [])
    remote.model = "m"
    remote.baseURL = "http://127.0.0.1:1/v1"
    remote.secretID = "provider-key-test"
    // 키가 저장되어 있지 않으면 사용 불가
    XCTAssertFalse(ProviderFallback.isUsable(remote, keyExists: { _ in false }))
    XCTAssertTrue(ProviderFallback.isUsable(remote, keyExists: { _ in true }))
    // 모델이 비면 사용 불가
    remote.model = ""
    XCTAssertFalse(ProviderFallback.isUsable(remote, keyExists: { _ in true }))
    // 비활성 프로바이더는 사용 불가
    remote.model = "m"
    remote.enabled = false
    XCTAssertFalse(ProviderFallback.isUsable(remote, keyExists: { _ in true }))
    // Apple FM은 키·모델·주소가 필요 없다
    let apple = LLMProviderConfig.newProvider(type: .appleFM, existing: [])
    XCTAssertTrue(ProviderFallback.isUsable(apple, keyExists: { _ in false }))
  }

  func testFallbackSettingRoundTripAndBackwardCompatibility() throws {
    // 기본값은 "사용 안 함"
    XCTAssertEqual(QuickTalkSettings().fallbackProviderID, "")
    XCTAssertNil(QuickTalkSettings().fallbackProvider)

    var s = QuickTalkSettings()
    s.fallbackProviderID = LLMProviderConfig.appleFMID
    let data = try JSONEncoder().encode(s)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertEqual(back.fallbackProviderID, LLMProviderConfig.appleFMID)

    // 구버전 JSON(키 없음)은 빈 문자열로 디코드되고 나머지 설정은 유지된다.
    var json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    json.removeValue(forKey: "fallbackProviderID")
    json["theme"] = nil
    let legacy = try JSONSerialization.data(withJSONObject: json)
    let old = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertEqual(old.fallbackProviderID, "")
    XCTAssertEqual(old.activeProviderID, s.activeProviderID)
  }

  func testFallbackProviderIsNilWhenSameAsActive() {
    var s = QuickTalkSettings()
    s.providers = [
      LLMProviderConfig.newProvider(type: .appleFM, existing: []),
      LLMProviderConfig.newProvider(type: .ollama, existing: [])
    ]
    s.activeProviderID = s.providers[0].id
    // 주 모델과 같은 ID는 폴백이 아니다(무한 왕복 방지)
    s.fallbackProviderID = s.providers[0].id
    XCTAssertNil(s.fallbackProvider)
    s.fallbackProviderID = s.providers[1].id
    XCTAssertEqual(s.fallbackProvider?.id, s.providers[1].id)
    // 비활성 예비 모델은 쓰지 않는다
    s.providers[1].enabled = false
    XCTAssertNil(s.fallbackProvider)
  }

  // MARK: - 사용자 중지 (2026-10-21)

  /// 사용자가 [중지]를 눌러 취소한 요청은 **실패가 아니다** — 예비 모델로 넘어가면
  /// 멈춘 줄 알았는데 다른 모델이 답을 이어서 만들어 화면이 되살아난다.
  func testCancellationNeverFallsBack() {
    XCTAssertFalse(ProviderFallback.allowed(after: CancellationError()))
    XCTAssertFalse(ProviderFallback.allowed(after: URLError(.cancelled)))
    // 대조: 같은 네트워크 계열이라도 시간 초과는 넘어간다
    XCTAssertTrue(ProviderFallback.allowed(after: URLError(.timedOut)))
  }
}
