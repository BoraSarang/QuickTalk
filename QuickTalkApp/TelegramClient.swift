import Foundation

// [FEATURE] Telegram Bot API 전송 계층 (v0.39 원격 승인)
//
// **아웃바운드 HTTPS POST 만** 쓴다. 인바운드 포트·웹훅 서버를 열지 않는다.
// long polling(`getUpdates`, timeout 25초)으로 callback_query 를 받는다.
//
// 보안:
//   · 토큰은 URL 경로에만 쓰고 로그·오류 문구에 남기지 않는다.
//   · 네트워크 오류는 `TelegramError.transport` 로 바꿔 URL(토큰 포함)을 숨긴다.
//   · 요청 본문은 JSON — 명령·이유·경로만 담고 파일 내용은 담지 않는다.

final class URLSessionTelegramTransport: TelegramTransport {
  private let session: URLSession
  private let baseURL: URL
  private let decoder = JSONDecoder()

  init(session: URLSession = .shared,
       baseURL: URL = URL(string: "https://api.telegram.org")!) {
    self.session = session
    self.baseURL = baseURL
  }

  // MARK: - Bot API

  func getMe(token: String) async throws -> TelegramBotInfo {
    try await call(token: token, method: "getMe", body: [:], timeout: 20)
  }

  func sendMessage(token: String, chatID: String, text: String,
                   buttons: [TelegramButton]) async throws -> TelegramMessage {
    var body: [String: Any] = [
      "chat_id": chatID,
      "text": text,
      "disable_web_page_preview": true
    ]
    if !buttons.isEmpty {
      let keyboard = buttons.map { ["text": $0.text, "callback_data": $0.callbackData] }
      body["reply_markup"] = ["inline_keyboard": [keyboard]]
    }
    return try await call(token: token, method: "sendMessage", body: body, timeout: 20)
  }

  func editMessageText(token: String, chatID: String, messageID: Int64,
                       text: String) async throws {
    let body: [String: Any] = [
      "chat_id": chatID,
      "message_id": messageID,
      "text": text,
      // 빈 inline keyboard = 버튼 제거.
      "reply_markup": ["inline_keyboard": []]
    ]
    let _: Bool = try await call(token: token, method: "editMessageText", body: body,
                                 timeout: 20)
  }

  func answerCallbackQuery(token: String, callbackID: String, text: String) async throws {
    let body: [String: Any] = [
      "callback_query_id": callbackID,
      "text": text,
      "show_alert": false
    ]
    let _: Bool = try await call(token: token, method: "answerCallbackQuery", body: body,
                                 timeout: 20)
  }

  func getUpdates(token: String, offset: Int64?,
                  timeout: Int) async throws -> [TelegramUpdate] {
    var body: [String: Any] = [
      "timeout": timeout,
      "allowed_updates": ["callback_query"]
    ]
    if let offset { body["offset"] = offset }
    // long polling — 서버가 timeout 동안 응답을 붙잡는다. URLSession 은 여유를 더 둔다.
    return try await call(token: token, method: "getUpdates", body: body,
                          timeout: TimeInterval(timeout + 15))
  }

  // MARK: - 공통

  private struct Envelope<T: Decodable>: Decodable {
    let ok: Bool
    let result: T?
    let description: String?
  }

  private func call<T: Decodable>(token: String, method: String,
                                  body: [String: Any],
                                  timeout: TimeInterval) async throws -> T {
    let data = try await request(token: token, method: method, body: body, timeout: timeout)
    let envelope: Envelope<T>
    do {
      envelope = try decoder.decode(Envelope<T>.self, from: data)
    } catch {
      throw TelegramError.invalidResponse
    }
    guard envelope.ok else {
      throw TelegramError.api(envelope.description ?? L("Telegram이 요청을 거부했습니다."))
    }
    guard let result = envelope.result else {
      throw TelegramError.invalidResponse
    }
    return result
  }

  private func request(token: String, method: String,
                       body: [String: Any],
                       timeout: TimeInterval) async throws -> Data {
    guard RemoteApprovalConfig.isValidToken(token) else {
      throw TelegramError.notConfigured(L("봇 토큰이 없거나 형식이 올바르지 않습니다."))
    }
    guard let url = URL(string: "\(baseURL.absoluteString)/bot\(token)/\(method)") else {
      throw TelegramError.invalidResponse
    }
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.timeoutInterval = timeout
    do {
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    } catch {
      throw TelegramError.invalidResponse
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await session.data(for: request)
    } catch {
      // URLError 에는 토큰이 들어간 URL 이 실릴 수 있다 — 반드시 일반 오류로 바꾼다.
      throw TelegramError.transport
    }
    guard let http = response as? HTTPURLResponse else {
      throw TelegramError.invalidResponse
    }
    // Telegram 은 4xx 에도 JSON `description` 을 준다 — envelope 해석에 맡긴다.
    if !(200..<300).contains(http.statusCode) && data.isEmpty {
      throw TelegramError.api("HTTP \(http.statusCode)")
    }
    return data
  }
}
