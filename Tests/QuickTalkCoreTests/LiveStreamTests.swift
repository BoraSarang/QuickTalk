import XCTest
@testable import QuickTalkCore

/// 실제 HTTP 스트리밍 검증 — `QT_LIVE_STREAM=1`일 때만 실행한다.
///
/// 사전 준비(로컬 전용):
/// ```
/// python3 - <<'PY'
/// from http.server import BaseHTTPRequestHandler, HTTPServer
/// import json, time
/// class H(BaseHTTPRequestHandler):
///     def do_POST(self):
///         n = int(self.headers.get('content-length', '0')); self.rfile.read(n)
///         if self.path.endswith('/api/chat'):
///             self.send_response(200); self.send_header('Content-Type', 'application/x-ndjson'); self.end_headers()
///             for c in ['안', '녕', '!']:
///                 self.wfile.write((json.dumps({'message': {'content': c}, 'done': False}, ensure_ascii=False) + '\n').encode()); self.wfile.flush(); time.sleep(0.01)
///             self.wfile.write((json.dumps({'done': True}) + '\n').encode()); self.wfile.flush()
///         else:
///             self.send_response(200); self.send_header('Content-Type', 'text/event-stream'); self.end_headers()
///             for c in ['안', '녕', '!']:
///                 self.wfile.write(('data: ' + json.dumps({'choices': [{'delta': {'content': c}}]}, ensure_ascii=False) + '\n\n').encode()); self.wfile.flush(); time.sleep(0.01)
///             self.wfile.write(b'data: [DONE]\n\n'); self.wfile.flush()
///     def log_message(self, *a): pass
/// HTTPServer(('127.0.0.1', 8799), H).serve_forever()
/// PY
/// ```
final class LiveStreamTests: XCTestCase {

  @MainActor
  func testLiveOpenAISSE() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["QT_LIVE_STREAM"] == "1",
                      "QT_LIVE_STREAM=1일 때만 (로컬 SSE 서버 필요)")
    let client = OpenAIClient(baseURL: URL(string: "http://127.0.0.1:8799/v1")!,
                              apiKey: "x", model: "m")
    var got: [String] = []
    let full = try await client.stream(prompt: "p", history: [], attachments: []) { got.append($0) }
    XCTAssertEqual(got, ["안", "녕", "!"], "델타는 도착 순서대로 와야 한다")
    XCTAssertEqual(full, "안녕!")
  }

  @MainActor
  func testLiveOllamaNDJSON() async throws {
    try XCTSkipUnless(ProcessInfo.processInfo.environment["QT_LIVE_STREAM"] == "1",
                      "QT_LIVE_STREAM=1일 때만 (로컬 NDJSON 서버 필요)")
    let client = OllamaClient(host: URL(string: "http://127.0.0.1:8799")!, model: "m")
    var got: [String] = []
    let full = try await client.stream(prompt: "p", history: [], attachments: []) { got.append($0) }
    XCTAssertEqual(got, ["안", "녕", "!"])
    XCTAssertEqual(full, "안녕!")
  }
}
