import XCTest
@testable import QuickTalkCore

/// 스트리밍 응답 — SSE/NDJSON 델타 파싱, 순서 보장, 부분 출력 후 재시도 금지.
final class StreamingTests: XCTestCase {

  // MARK: - OpenAI SSE 파서

  func testSSEDelta() {
    let line = #"data: {"choices":[{"delta":{"content":"안"}}]}"#
    XCTAssertEqual(OpenAIClient.sseEvent(line), .delta("안"))
  }

  func testSSEDone() {
    XCTAssertEqual(OpenAIClient.sseEvent("data: [DONE]"), .done)
  }

  // MARK: - 도구 호출 조각 (스트리밍 중 tools 를 받는 프로바이더)

  func testSSEToolCallDelta() {
    let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"shell","arguments":"{\"comm"}}]}}]}"#
    XCTAssertEqual(OpenAIClient.sseEvent(line),
                   .toolCallDelta(index: 0, id: "call_1", name: "shell", args: "{\"comm"))
  }

  func testSSEToolCallArgumentFragment() {
    // 두 번째 조각 — id·이름 없이 arguments 만 온다
    let line = #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"and\"}"}}]}}]}"#
    XCTAssertEqual(OpenAIClient.sseEvent(line),
                   .toolCallDelta(index: 0, id: nil, name: nil, args: "and\"}"))
  }

  func testSSEReasoningContent() {
    let line = #"data: {"choices":[{"delta":{"reasoning_content":"생각 중"}}]}"#
    XCTAssertEqual(OpenAIClient.sseEvent(line), .reasoning("생각 중"))
  }

  func testSSEIgnoresNonDataAndEmptyDelta() {
    XCTAssertEqual(OpenAIClient.sseEvent(": keep-alive"), .ignore)
    XCTAssertEqual(OpenAIClient.sseEvent("event: message"), .ignore)
    XCTAssertEqual(OpenAIClient.sseEvent(#"data: {"choices":[{"delta":{}}]}"#), .ignore)
    XCTAssertEqual(OpenAIClient.sseEvent("data: "), .ignore)
  }

  func testSSEHandlesSpacesAndCR() {
    let line = "  data:  {\"choices\":[{\"delta\":{\"content\":\"x\"}}]}\r"
    XCTAssertEqual(OpenAIClient.sseEvent(line), .delta("x"))
  }

  // MARK: - 대화 턴(부분 출력)

  func testStreamingTurnLifecycle() {
    let store = ConversationStore()
    let id = store.beginAssistantTurn()
    store.appendStreaming("안", to: id)
    store.appendStreaming("녕", to: id)
    XCTAssertEqual(store.conversation.turns.last?.text, "안녕")
    XCTAssertNil(store.conversation.turns.last?.elapsedMs)

    store.finishAssistantTurn(id, elapsedMs: 1234)
    XCTAssertEqual(store.conversation.turns.last?.elapsedMs, 1234)

    store.setAssistantText("바뀜", id: id)
    XCTAssertEqual(store.conversation.turns.last?.text, "바뀜")
  }

  // MARK: - 재시도 사다리

  @MainActor
  func testDeltasArriveInOrder() async throws {
    let client = ChunkClient(chunks: ["가", "나", "다"])
    var got: [String] = []
    let full = try await AttachmentRetry.stream(client: client, prompt: "p", history: [],
                                                attachments: [], model: "m") { got.append($0) }
    XCTAssertEqual(got, ["가", "나", "다"])
    XCTAssertEqual(full, "가나다")
  }

  @MainActor
  func testPartialOutputIsNotRetried() async {
    let client = PartialFailClient()
    let attachment = OutgoingAttachment(name: "a.txt", kind: .file, text: "본문")
    do {
      _ = try await AttachmentRetry.stream(client: client, prompt: "p", history: [],
                                           attachments: [attachment], model: "m") { _ in }
      XCTFail("부분 출력 후에는 실패를 그대로 던져야 한다")
    } catch {
      XCTAssertEqual((error as? QuickTalkError)?.code, "E-MAC-NET-0003")
    }
    XCTAssertEqual(client.sendCalls, 0, "이미 보여 준 글자가 있으면 재시도하지 않는다")
  }

  @MainActor
  func testRetryBeforeAnyDeltaUsesWholeResponse() async throws {
    let client = RetryClient()
    let attachment = OutgoingAttachment(name: "a.txt", kind: .file, text: "본문")
    var got: [String] = []
    let full = try await AttachmentRetry.stream(client: client, prompt: "p", history: [],
                                                attachments: [attachment], model: "m") { got.append($0) }
    XCTAssertEqual(client.sendCalls, 1)
    XCTAssertEqual(got.count, 1, "재시도 응답은 원인 안내와 함께 한 번에 전달")
    XCTAssertTrue(got[0].contains("재시도 응답"))
    XCTAssertTrue(full.contains("재시도 응답"))
  }
}

// MARK: - 테스트용 클라이언트

private final class ChunkClient: LLMClient {
  let chunks: [String]
  init(chunks: [String]) { self.chunks = chunks }

  func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    chunks.joined()
  }

  func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
              onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    var full = ""
    for c in chunks {
      full += c
      await onDelta(c)
    }
    return full
  }
}

/// 첫 델타를 보낸 뒤 실패 — 재시도하면 안 되는 경로.
private final class PartialFailClient: LLMClient {
  var sendCalls = 0

  func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    sendCalls += 1
    return "재시도하면 안 됨"
  }

  func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
              onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    await onDelta("부분")
    throw QuickTalkError.serverFailure(.upstream(status: 500, code: nil))
  }
}

/// 델타 전에 500 — 같은 요청을 1회 재시도(비스트리밍)하고 안내와 함께 전달.
private final class RetryClient: LLMClient {
  var sendCalls = 0

  func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    sendCalls += 1
    return "재시도 응답"
  }

  func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
              onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    throw QuickTalkError.serverFailure(.upstream(status: 500, code: nil))
  }
}
