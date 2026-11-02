import XCTest
@testable import QuickTalkCore

/// User-Agent — 기본 CFNetwork UA(`QuickTalk/1 CFNetwork/3896.200.61 Darwin/27.2.0`) 대신
/// `QuickTalk/<버전>` 한 줄만 보내는지 고정한다.
final class UserAgentTests: XCTestCase {

  func testFormatIsNameAndVersionOnly() {
    XCTAssertEqual(QuickTalkUserAgent.format(version: "1.0"), "QuickTalk/1.0")
    XCTAssertEqual(QuickTalkUserAgent.format(version: "0.25"), "QuickTalk/0.25")
  }

  func testValueHasNoCFNetworkOrDarwinSuffix() {
    XCTAssertTrue(QuickTalkUserAgent.value.hasPrefix("QuickTalk/"))
    XCTAssertFalse(QuickTalkUserAgent.value.contains("CFNetwork"))
    XCTAssertFalse(QuickTalkUserAgent.value.contains("Darwin"))
    XCTAssertFalse(QuickTalkUserAgent.value.contains(" "), "UA는 공백 없는 한 토큰이어야 한다")
    XCTAssertEqual(QuickTalkUserAgent.value.components(separatedBy: "/").count, 2)
  }

  func testApplyReplacesExistingHeader() {
    var request = URLRequest(url: URL(string: "https://example.com")!)
    request.setValue("QuickTalk/1 CFNetwork/3896.200.61 Darwin/27.2.0",
                     forHTTPHeaderField: "User-Agent")
    QuickTalkUserAgent.apply(to: &request)
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), QuickTalkUserAgent.value)
  }

  // MARK: - 실제 요청 빌더

  func testOpenAIChatRequestCarriesUserAgent() throws {
    let client = OpenAIClient(baseURL: URL(string: "http://localhost:8791/v1")!,
                              apiKey: "test-key", model: "test-model")
    let request = try client.makeRequest(prompt: "안녕", history: [], attachments: [], stream: true)
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), QuickTalkUserAgent.value)
    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
  }

  func testOllamaChatRequestCarriesUserAgent() throws {
    let client = OllamaClient(host: URL(string: "http://localhost:11434")!, model: "test-model")
    let request = try client.makeRequest(prompt: "안녕", history: [], attachments: [], stream: false)
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), QuickTalkUserAgent.value)
  }

  func testExaSearchRequestCarriesUserAgent() {
    let request = ExaSearch.request(query: "테스트", count: 3,
                                    freshness: .any, maxCharacters: 500)
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), QuickTalkUserAgent.value)
  }

  func testExaAnswerRequestCarriesUserAgent() {
    let request = ExaAnswer.request(query: "테스트")
    XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), QuickTalkUserAgent.value)
  }
}
