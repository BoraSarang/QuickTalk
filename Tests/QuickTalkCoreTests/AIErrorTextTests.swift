import XCTest
@testable import QuickTalkCore

/// AI 오류 문구 — 연결 거부·시간 초과·오프라인·TLS·서버 상태가
/// 모두 "응답을 가져오지 못했습니다"로 뭉개지지 않고 **정확한 원인**을 남기는지.
final class AIErrorTextTests: XCTestCase {
  private let base = URL(string: "http://192.168.86.30:8791/v1")!

  private func urlError(_ code: URLError.Code) -> URLError {
    URLError(code, userInfo: [NSURLErrorFailingURLErrorKey: base])
  }

  // MARK: - 정확한 원인

  func testConnectionRefusedNamesHostAndCode() {
    let e = urlError(.cannotConnectToHost)
    XCTAssertEqual(AIErrorText.code(for: e), "E-MAC-NET-0001")
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("E-MAC-NET-0001"), text)
    XCTAssertTrue(text.contains("192.168.86.30:8791"), text)   // 어느 서버인지
    XCTAssertTrue(text.contains("-1004"), text)                 // 연결 거부
    XCTAssertFalse(text.contains("/v1"), text)                  // 경로·키는 노출하지 않는다
  }

  func testTimeout() {
    let e = urlError(.timedOut)
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("-1001"), text)
    XCTAssertTrue(text.contains("192.168.86.30:8791"), text)
    XCTAssertTrue(AIErrorText.shortDetail(for: e).contains("1001"))
  }

  func testOffline() {
    let e = urlError(.notConnectedToInternet)
    XCTAssertTrue(AIErrorText.userText(for: e, url: base).contains("-1009"))
    XCTAssertTrue(AIErrorText.shortDetail(for: e).contains("1009"))
  }

  func testDNSUsesHostOnly() {
    let e = urlError(.dnsLookupFailed)
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("-1006"), text)
    XCTAssertTrue(text.contains("192.168.86.30"), text)
    XCTAssertFalse(text.contains("/v1"), text)
  }

  func testTLS() {
    let e = urlError(.secureConnectionFailed)
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("-1200"), text)
    XCTAssertTrue(AIErrorText.shortDetail(for: e).contains("1200"))
  }

  // MARK: - 서버 오류(HTTP)

  func testServerFailureKeepsStatusAndServerCode() {
    let e = QuickTalkError.serverFailure(.keyRejected(status: 401, code: "E-AND-AUTH-0004"))
    XCTAssertEqual(AIErrorText.code(for: e), "E-MAC-KEY-0002")
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("E-MAC-KEY-0002"), text)
    XCTAssertTrue(text.contains("HTTP 401"), text)
    XCTAssertTrue(text.contains("E-AND-AUTH-0004"), text)
    let short = AIErrorText.shortDetail(for: e)
    XCTAssertTrue(short.contains("401"), short)
    XCTAssertTrue(short.contains("E-AND-AUTH-0004"), short)
  }

  func testUpstreamStatus() {
    let e = QuickTalkError.serverFailure(.upstream(status: 503, code: nil))
    XCTAssertEqual(AIErrorText.code(for: e), "E-MAC-NET-0003")
    let text = AIErrorText.userText(for: e, url: base)
    XCTAssertTrue(text.contains("503"), text)
    XCTAssertTrue(text.contains("모델 서버"), text)
    XCTAssertTrue(text.contains("192.168.86.30:8791"), text)
    let short = AIErrorText.shortDetail(for: e)
    XCTAssertTrue(short.contains("503"), short)
    XCTAssertTrue(short.contains("모델 서버"), short)
  }

  func testServerDetailIncludesServerCodeAndHost() {
    let e = QuickTalkError.serverFailure(.upstream(status: 503, code: "server_error"))
    let detail = AIErrorText.detail(for: e, url: base)
    XCTAssertTrue(detail.contains("503"), detail)
    XCTAssertTrue(detail.contains("server_error"), detail)
    XCTAssertTrue(detail.contains("192.168.86.30:8791"), detail)
    XCTAssertFalse(detail.contains("/v1"), detail)   // 경로는 노출하지 않는다
    let status = AIErrorText.shortDetail(for: e)
    XCTAssertTrue(status.contains("server_error"), status)
    XCTAssertFalse(status.contains("192.168.86.30"), status) // 상태 카드는 짧게
    XCTAssertLessThan(status.count, detail.count)    // 상태 카드는 더 짧게
  }

  // MARK: - 분류

  func testConnectionFailureClassification() {
    XCTAssertTrue(AIErrorText.isConnectionFailure(urlError(.cannotConnectToHost)))
    XCTAssertTrue(AIErrorText.isConnectionFailure(urlError(.timedOut)))
    XCTAssertTrue(AIErrorText.isConnectionFailure(urlError(.notConnectedToInternet)))
    XCTAssertFalse(AIErrorText.isConnectionFailure(urlError(.cancelled)))
    XCTAssertFalse(AIErrorText.isConnectionFailure(QuickTalkError.serverFailure(.keyRejected(status: 401, code: nil))))
  }

  func testLogLabelHasNoBody() {
    XCTAssertEqual(AIErrorText.logLabel(for: urlError(.cannotConnectToHost)), "URLError -1004")
    let server = QuickTalkError.serverFailure(.keyRejected(status: 401, code: "E-AND-AUTH-0004"))
    XCTAssertTrue(AIErrorText.logLabel(for: server).contains("401"))
    XCTAssertFalse(AIErrorText.logLabel(for: server).contains("E-AND-AUTH-0004"))
  }
}
