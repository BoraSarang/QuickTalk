import XCTest
@testable import QuickTalkCore

/// v0.39.1 — 초당 토큰(추정) 계산·표기. 실제 토크나이저 대신 앱 예산과 같은 추정을 쓴다.
final class TokenSpeedTests: XCTestCase {

  func testShortAnswersAndMissingTimeAreHidden() {
    // 12토큰 미만 — 속도를 보여 주지 않는다.
    XCTAssertNil(TokenSpeed.tokensPerSecond(text: "가나다라마", elapsedMs: 5_000))
    // 1초 미만 — 표본이 너무 짧다.
    XCTAssertNil(TokenSpeed.tokensPerSecond(text: String(repeating: "가", count: 100), elapsedMs: 900))
    XCTAssertNil(TokenSpeed.tokensPerSecond(text: String(repeating: "가", count: 100), elapsedMs: nil))
    XCTAssertNil(TokenSpeed.tokensPerSecond(text: "", elapsedMs: 5_000))
  }

  func testRateIsEstimatedTokensOverElapsed() {
    // ASCII 100자 = 25토큰. 5초 → 5 tok/s.
    let ascii = String(repeating: "a", count: 100)
    XCTAssertEqual(try XCTUnwrap(TokenSpeed.tokensPerSecond(text: ascii, elapsedMs: 5_000)),
                   5, accuracy: 0.0001)
    // 한국어 100자 = 100토큰. 2초 → 50 tok/s.
    let korean = String(repeating: "가", count: 100)
    XCTAssertEqual(try XCTUnwrap(TokenSpeed.tokensPerSecond(text: korean, elapsedMs: 2_000)),
                   50, accuracy: 0.0001)
  }

  func testLiveRateNeedsFirstDeltaAndHalfSecond() {
    let start = Date(timeIntervalSince1970: 1_000)
    // 첫 글자 시각이 없으면 계산하지 않는다.
    XCTAssertNil(TokenSpeed.liveTokensPerSecond(tokens: 20, since: nil,
                                                now: start.addingTimeInterval(2)))
    // 0.5초 미만 표본도 숨긴다.
    XCTAssertNil(TokenSpeed.liveTokensPerSecond(tokens: 20, since: start,
                                                now: start.addingTimeInterval(0.4)))
    // 20토큰 / 2초 = 10 tok/s.
    XCTAssertEqual(try XCTUnwrap(TokenSpeed.liveTokensPerSecond(
      tokens: 20, since: start, now: start.addingTimeInterval(2))),
      10, accuracy: 0.0001)
  }

  func testLabelFormatting() {
    XCTAssertEqual(TokenSpeed.label(4.24), "4.2 tok/s")
    XCTAssertEqual(TokenSpeed.label(9.99), "10.0 tok/s")   // 반올림 결과가 10이어도 소수 한 자리 유지
    XCTAssertEqual(TokenSpeed.label(10.4), "10 tok/s")
    XCTAssertEqual(TokenSpeed.label(128.6), "129 tok/s")
    XCTAssertEqual(TokenSpeed.label(0), "")
    XCTAssertEqual(TokenSpeed.label(.infinity), "")
  }
}
