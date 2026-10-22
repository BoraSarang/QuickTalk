import Foundation

// MARK: - 프로바이더 종류

public enum LLMProviderType: String, Codable, CaseIterable, Identifiable {
  case appleFM
  case ollama
  case openAICompatible

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .appleFM: return L("Apple FM (온디바이스)")
    case .ollama: return L("Ollama (로컬)")
    case .openAICompatible: return L("OpenAI 호환 (원격)")
    }
  }

  public var iconName: String {
    switch self {
    case .appleFM: return "apple.logo"
    case .ollama: return "desktopcomputer"
    case .openAICompatible: return "network"
    }
  }

  public var needsBaseURL: Bool { self != .appleFM }
  public var needsAPIKey: Bool { self == .openAICompatible }
  public var needsModel: Bool { self != .appleFM }
}

// MARK: - 프로바이더 설정 1건 (사용자가 계속 추가/삭제 가능)

public struct LLMProviderConfig: Codable, Identifiable, Equatable {
  public var id: String
  public var name: String
  public var type: LLMProviderType
  public var baseURL: String
  public var model: String
  /// SecretStore(로컬 파일) 항목 이름 — 키 자체는 설정에 넣지 않는다
  public var secretID: String
  public var enabled: Bool
  /// 모델의 컨텍스트 토큰 수(선택). 비우면 종류별 보수적 기본값을 쓴다.
  /// 구버전 설정에는 없으므로 nil이면 기본값 — 자동 대화 정리의 예산 계산에만 쓴다.
  public var contextTokens: Int?

  public init(id: String = UUID().uuidString,
              name: String,
              type: LLMProviderType,
              baseURL: String = "",
              model: String = "",
              secretID: String = "",
              enabled: Bool = true,
              contextTokens: Int? = nil) {
    self.id = id
    self.name = name
    self.type = type
    self.baseURL = baseURL
    self.model = model
    self.secretID = secretID
    self.enabled = enabled
    self.contextTokens = contextTokens
  }

  // 기본 3종 ID — 마이그레이션·기본 활성 지정에 사용
  public static let appleFMID = "local-apple-fm"
  public static let ollamaID = "local-ollama"
  public static let remoteOpenAIID = "remote-openai"

  /// 기본 프로바이더 3종: Local Apple FM(기본 활성) / Local Ollama / Remote OpenAI 호환
  public static func defaultProviders() -> [LLMProviderConfig] {
    [
      LLMProviderConfig(id: appleFMID, name: "Local Apple FM", type: .appleFM),
      LLMProviderConfig(id: ollamaID, name: "Local Ollama", type: .ollama,
                        baseURL: "http://localhost:11434", model: "Local-Qwen2.5-32B:latest"),
      LLMProviderConfig(id: remoteOpenAIID, name: "Remote OpenAI 호환", type: .openAICompatible,
                        baseURL: "http://192.168.86.30:8791/v1", model: "deepseek-v4.1-flash-free",
                        secretID: remoteOpenAIID)
    ]
  }

  /// 화면 표시 이름 — 기본 시드 이름만 현재 언어로 바꿔 보여준다(사용자가 붙인 이름은 그대로).
  public var displayName: String {
    name == "Remote OpenAI 호환" ? L("Remote OpenAI 호환") : name
  }

  /// 신규 프로바이더 템플릿 — 이름 중복 시 "2" 접미사
  public static func newProvider(type: LLMProviderType, existing: [LLMProviderConfig]) -> LLMProviderConfig {
    let base = type == .ollama ? "Local Ollama" : type == .openAICompatible ? "OpenAI 호환" : "Apple FM"
    var name = base
    var n = 2
    while existing.contains(where: { $0.name == name }) {
      name = "\(base) \(n)"
      n += 1
    }
    let id = UUID().uuidString
    return LLMProviderConfig(id: id, name: name, type: type,
                             baseURL: type == .ollama ? "http://localhost:11434"
                                    : type == .openAICompatible ? "http://localhost:11434/v1" : "",
                             model: "",
                             secretID: type == .openAICompatible ? id : "")
  }
}

// MARK: - 클라이언트

public protocol LLMClient {
  /// `attachments`는 **실제 전송 내용**(텍스트 본문·이미지 data URL)이다.
  /// 대화 기록의 `Attachment`(이름·종류)와 다르다 — 본문은 전송 순간에 읽는다.
  func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String

  /// 스트리밍 응답. 델타는 **도착하는 순서대로** `onDelta`에 전달하고 전체 텍스트를 반환한다.
  /// 기본 구현은 한 번에 받아 마지막에 한 번 전달한다(구현체가 있으면 토큰 단위).
  func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
              onDelta: @escaping @MainActor (String) -> Void) async throws -> String
}

public extension LLMClient {
  /// 첨부 없는 호출 편의용
  func send(prompt: String, history: [Turn]) async throws -> String {
    try await send(prompt: prompt, history: history, attachments: [])
  }

  func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
              onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    let full = try await send(prompt: prompt, history: history, attachments: attachments)
    await onDelta(full)
    return full
  }
}

public struct MockLLMClient: LLMClient {
  public init() {}
  public func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    try await Task.sleep(nanoseconds: 300_000_000)
    guard attachments.isEmpty else {
      return "(목업) 첨부 \(attachments.count)건 수신 — \(AttachmentLoader.summary(attachments))"
    }
    return "(목업) 같은 대화방에 턴 누적됨."
  }
}

// MARK: - 스트리밍 응답 헬퍼

/// `URLSession.AsyncBytes` → Data (SSE가 아닌 응답·오류 본문용, 상한으로 폭주 방지)
enum HTTPStream {
  static func collect(_ bytes: URLSession.AsyncBytes, limit: Int = 1_000_000) async throws -> Data {
    var data = Data(); data.reserveCapacity(8192)
    for try await b in bytes {
      data.append(b)
      if data.count >= limit { break }
    }
    return data
  }
}

// OpenAI 호환: POST {baseURL}/chat/completions {model, messages, stream:false|true}
public struct OpenAIClient: LLMClient {
  public var baseURL: URL
  public var apiKey: String
  public var model: String
  public init(baseURL: URL, apiKey: String, model: String) {
    self.baseURL = baseURL; self.apiKey = apiKey; self.model = model
  }
  /// 요청 본문의 messages 배열 — 텍스트 첨부는 본문에 인라인, 이미지는 `image_url` 파트로 싣는다.
  /// (이전 구현은 이름·종류만 기록하고 **내용을 보내지 않아** 첨부가 모델에 전달되지 않았다)
  public static func buildMessages(prompt: String,
                                   history: [Turn],
                                   attachments: [OutgoingAttachment]) -> [[String: Any]] {
    let text = AttachmentLoader.composeText(prompt: prompt, attachments: attachments)
    let images = attachments.compactMap { $0.hasImage ? $0.imageDataURL : nil }
    var messages: [[String: Any]] = history.map {
      ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
    }
    if images.isEmpty {
      messages.append(["role": "user", "content": text])
    } else {
      var parts: [[String: Any]] = [["type": "text",
                                     "text": text.isEmpty ? "첨부한 이미지를 확인해 주세요." : text]]
      for url in images {
        parts.append(["type": "image_url", "image_url": ["url": url]])
      }
      messages.append(["role": "user", "content": parts])
    }
    return messages
  }

  private func makeRequest(prompt: String, history: [Turn],
                           attachments: [OutgoingAttachment], stream: Bool) throws -> URLRequest {
    var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let msgs = Self.buildMessages(prompt: prompt, history: history, attachments: attachments)
    req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "stream": stream])
    return req
  }

  public func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    let req = try makeRequest(prompt: prompt, history: history, attachments: attachments, stream: false)
    let (data, resp) = try await URLSession.shared.data(for: req)
    return try Self.decode(data: data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                           hasImage: attachments.contains { $0.hasImage })
  }

  /// 스트리밍 — `stream: true`로 보내고 SSE(`data: {…}`) 델타를 도착하는 대로 전달한다.
  /// 프록시가 스트리밍을 무시하고 일반 JSON을 주면(Content-Type이 event-stream이 아님) 한 번에 전달한다.
  public func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    let hasImage = attachments.contains { $0.hasImage }
    let req = try makeRequest(prompt: prompt, history: history, attachments: attachments, stream: true)
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let http = resp as? HTTPURLResponse
    let status = http?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: try await HTTPStream.collect(bytes), status: status, hasImage: hasImage)
    }
    let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
    guard type.contains("text/event-stream") else {
      // 프록시가 스트리밍을 무시하고 일반 JSON으로 답한 경우 — 그래도 본문이 SSE면 델타로 푼다
      let data = try await HTTPStream.collect(bytes)
      if let body = String(data: data, encoding: .utf8), body.contains("data:") {
        var streamed = ""
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
          if case .delta(let d) = Self.sseEvent(String(line)) {
            streamed += d
            await onDelta(d)
          }
        }
        if !streamed.isEmpty { return streamed }
      }
      let text = try Self.decode(data: data, status: status, hasImage: hasImage)
      await onDelta(text)
      return text
    }
    var full = ""
    loop: for try await raw in bytes.lines {
      switch Self.sseEvent(raw) {
      case .done:
        break loop
      case .delta(let d):
        full += d
        await onDelta(d)
      case .toolCallDelta, .reasoning:
        continue        // 도구 호출·사고 내용은 도구 없는 경로에서는 무시한다
      case .ignore:
        continue
      }
    }
    if full.isEmpty {
      // SSE를 흉내만 내고 내용이 없는 프록시 — 일반 요청으로 한 번 더 시도한다
      let text = try await send(prompt: prompt, history: history, attachments: attachments)
      await onDelta(text)
      return text
    }
    return full
  }

  /// SSE 한 줄 → 델타/도구호출/생각/종료/무시. (단위 테스트로 고정)
  public enum SSEEvent: Equatable {
    case delta(String)
    case done
    case ignore
    /// 도구 호출 조각 — arguments 는 조각으로 와서 누적한다.
    case toolCallDelta(index: Int, id: String?, name: String?, args: String?)
    /// thinking 모드 모델의 사고 내용 — 다음 요청에 그대로 되돌려야 한다
    case reasoning(String)
  }

  public static func sseEvent(_ line: String) -> SSEEvent {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("data:") else { return .ignore }
    let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
    if payload == "[DONE]" { return .done }
    guard !payload.isEmpty, let data = payload.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .ignore }
    guard let choices = obj["choices"] as? [[String: Any]], let first = choices.first else { return .ignore }
    guard let delta = first["delta"] as? [String: Any] else { return .ignore }
    // 도구 호출 조각이 먼저 온다 — content 보다 우선한다
    if let calls = delta["tool_calls"] as? [[String: Any]] {
      for (i, raw) in calls.enumerated() {
        let index = (raw["index"] as? Int) ?? i
        let fn = raw["function"] as? [String: Any] ?? [:]
        let id = raw["id"] as? String
        let name = fn["name"] as? String
        let args = fn["arguments"] as? String ?? ""
        if id == nil && name == nil && args.isEmpty { continue }
        return .toolCallDelta(index: index, id: id, name: name, args: args)
      }
    }
    if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
      return .reasoning(reasoning)
    }
    let content = delta["content"] as? String
    guard let content, !content.isEmpty else { return .ignore }
    return .delta(content)
  }

  static func failure(data: Data, status: Int, hasImage: Bool) -> QuickTalkError {
    let body = String(data: data, encoding: .utf8) ?? ""
    if let failure = ServerFailure.classify(status: status, body: body, hasImage: hasImage) {
      return .serverFailure(failure)
    }
    return .networkUnavailable()
  }

  static func decode(data: Data, status: Int, hasImage: Bool) throws -> String {
    guard status == 200 else { throw failure(data: data, status: status, hasImage: hasImage) }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let choice = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any],
          let text = choice["content"] as? String, !text.isEmpty else {
      throw QuickTalkError.serverFailure(.emptyResponse(status: status))
    }
    return text
  }

  // MARK: - 툴 콜링 (PLAN_v0.14 P3)

  /// 완성된 messages 배열로 1회 호출 — tool_calls를 그대로 돌려준다.
  /// 프록시가 `tools`를 모르면 400이 오고, 호출부는 기존 주입 방식으로 폴백한다.
  public func completion(messages: [[String: Any]],
                         tools: [[String: Any]]? = nil) async throws -> WebSearchTool.Response {
    var req = try makeMessageRequest(messages: messages, tools: tools, stream: false)
    req.timeoutInterval = 60
    let (data, resp) = try await URLSession.shared.data(for: req)
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: data, status: status, hasImage: false)
    }
    return try WebSearchTool.parse(data)
  }

  /// 툴 결과를 `tool` 메시지로 넣은 뒤 **최종 답변만** 스트리밍한다.
  /// 현재 앱의 1왕복 툴 콜링은 결과를 프롬프트에 주입하므로 이 API는 후속 다중 왕복용이다.
  public func stream(messages: [[String: Any]],
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    let req = try makeMessageRequest(messages: messages, tools: nil, stream: true)
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let http = resp as? HTTPURLResponse
    let status = http?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: try await HTTPStream.collect(bytes), status: status, hasImage: false)
    }
    let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
    guard type.contains("text/event-stream") else {
      let data = try await HTTPStream.collect(bytes)
      if let body = String(data: data, encoding: .utf8), body.contains("data:") {
        var streamed = ""
        for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
          if case .delta(let d) = Self.sseEvent(String(line)) {
            streamed += d
            await onDelta(d)
          }
        }
        if !streamed.isEmpty { return streamed }
      }
      let text = try Self.decode(data: data, status: status, hasImage: false)
      await onDelta(text)
      return text
    }
    var full = ""
    loop: for try await raw in bytes.lines {
      switch Self.sseEvent(raw) {
      case .done:
        break loop
      case .delta(let d):
        full += d
        await onDelta(d)
      case .toolCallDelta, .reasoning:
        continue        // 도구 호출·사고 내용은 도구 없는 경로에서는 무시한다
      case .ignore:
        continue
      }
    }
    guard !full.isEmpty else { throw QuickTalkError.serverFailure(.emptyResponse(status: status)) }
    return full
  }

  /// 스트리밍 + **도구 호출 수집** — 본 모델이 직접 도구를 고르게 한다.
  /// - 본문은 그대로 흘려보내고(스트리밍 유지), 도구 호출 조각은 모아서 돌려준다.
  /// - 도구가 없으면 `toolCalls` 는 비어 있고, 호출이 있으면 본문이 비어 있을 수 있다.
  public func streamWithTools(messages: [[String: Any]],
                              tools: [[String: Any]],
                              onDelta: @escaping @MainActor (String) -> Void) async throws
    -> (text: String, toolCalls: [AgentToolCall], reasoning: String?) {
    var req = try makeMessageRequest(messages: messages, tools: tools, stream: true)
    req.timeoutInterval = 60
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let http = resp as? HTTPURLResponse
    let status = http?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: try await HTTPStream.collect(bytes), status: status, hasImage: false)
    }
    var full = ""
    var reasoning = ""
    var calls: [Int: (id: String, name: String, args: String)] = [:]
    loop: for try await raw in bytes.lines {
      switch Self.sseEvent(raw) {
      case .done:
        break loop
      case .delta(let d):
        full += d
        await onDelta(d)
      case .reasoning(let r):
        reasoning += r
      case .toolCallDelta(let index, let id, let name, let args):
        var entry = calls[index] ?? (id: "", name: "", args: "")
        if let id, !id.isEmpty { entry.id = id }
        if let name, !name.isEmpty { entry.name = name }
        entry.args += args ?? ""
        calls[index] = entry
      case .ignore:
        continue
      }
    }
    let list = calls.keys.sorted().compactMap { key -> AgentToolCall? in
      guard let entry = calls[key], !entry.name.isEmpty else { return nil }
      return AgentToolCall(id: entry.id.isEmpty ? "call_\(key)" : entry.id,
                           name: entry.name, arguments: entry.args.isEmpty ? "{}" : entry.args)
    }
    return (full, list, reasoning.isEmpty ? nil : reasoning)
  }

  private func makeMessageRequest(messages: [[String: Any]],
                                  tools: [[String: Any]]?,
                                  stream: Bool) throws -> URLRequest {
    var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
    req.httpMethod = "POST"
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    var body: [String: Any] = ["model": model, "messages": messages, "stream": stream]
    if let tools, !tools.isEmpty {
      body["tools"] = tools
      body["tool_choice"] = "auto"
    }
    req.httpBody = try JSONSerialization.data(withJSONObject: body)
    return req
  }

  /// GET {baseURL}/models → 모델 id 목록 (설정 UI "모델 불러오기")
  public static func listModels(baseURL: URL, apiKey: String) async throws -> [String] {
    var req = URLRequest(url: baseURL.appendingPathComponent("models"))
    req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuickTalkError.networkUnavailable() }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let list = json?["data"] as? [[String: Any]] ?? []
    return list.compactMap { $0["id"] as? String }
  }
}

// Ollama: POST http://localhost:11434/api/chat {model, messages, stream:false|true}
public struct OllamaClient: LLMClient {
  /// 로컬 모델은 프롬프트가 길면 첫 토큰까지 분 단위로 걸린다(32B Q4 실측 72~140 tok/s).
  /// 60초(URLSession 기본)로는 3~6k토큰 프롬프트가 **첫 토큰 전에** 끊겨 `-1001`.
  /// 원격 OpenAI 호환은 그대로 60초를 쓴다.
  public static let requestTimeout: TimeInterval = 300
  public var host: URL
  public var model: String
  public init(host: URL = URL(string: "http://localhost:11434")!, model: String) {
    self.host = host; self.model = model
  }
  /// Ollama는 `images: [base64]` 필드로 이미지를 받는다(접두어 없는 base64).
  public static func buildMessages(prompt: String,
                                   history: [Turn],
                                   attachments: [OutgoingAttachment]) -> [[String: Any]] {
    let text = AttachmentLoader.composeText(prompt: prompt, attachments: attachments)
    var messages: [[String: Any]] = history.map {
      ["role": $0.role == .user ? "user" : "assistant", "content": $0.text]
    }
    var last: [String: Any] = ["role": "user", "content": text]
    let images = attachments.compactMap { $0.imageBase64 }
    if !images.isEmpty { last["images"] = images }
    messages.append(last)
    return messages
  }

  private func makeRequest(prompt: String, history: [Turn],
                           attachments: [OutgoingAttachment], stream: Bool) throws -> URLRequest {
    var req = URLRequest(url: host.appendingPathComponent("api/chat"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let msgs = Self.buildMessages(prompt: prompt, history: history, attachments: attachments)
    req.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "messages": msgs, "stream": stream])
    // 스트리밍은 첫 데이터가 올 때까지의 유휴 시간이 이 값이다 — 프롬프트 처리를 기다린다.
    req.timeoutInterval = Self.requestTimeout
    return req
  }

  public func send(prompt: String, history: [Turn], attachments: [OutgoingAttachment]) async throws -> String {
    let req = try makeRequest(prompt: prompt, history: history, attachments: attachments, stream: false)
    let (data, resp) = try await URLSession.shared.data(for: req)
    return try Self.decode(data: data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0,
                           hasImage: attachments.contains { $0.hasImage })
  }

  /// 스트리밍 — Ollama는 줄 단위 JSON(NDJSON)으로 `message.content` 델타를 보낸다.
  public func stream(prompt: String, history: [Turn], attachments: [OutgoingAttachment],
                     onDelta: @escaping @MainActor (String) -> Void) async throws -> String {
    let hasImage = attachments.contains { $0.hasImage }
    let req = try makeRequest(prompt: prompt, history: history, attachments: attachments, stream: true)
    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let http = resp as? HTTPURLResponse
    let status = http?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: try await HTTPStream.collect(bytes), status: status,
                         hasImage: hasImage, bodyText: nil)
    }
    let type = http?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
    guard type.contains("ndjson") else {
      let text = try Self.decode(data: try await HTTPStream.collect(bytes), status: status, hasImage: hasImage)
      await onDelta(text)
      return text
    }
    var full = ""
    for try await raw in bytes.lines {
      let line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      if let msg = obj["message"] as? [String: Any],
         let d = msg["content"] as? String, !d.isEmpty {
        full += d
        await onDelta(d)
      }
      if (obj["done"] as? Bool) == true { break }
    }
    if full.isEmpty {
      // NDJSON을 흉내만 내고 내용이 없는 경우 — 일반 요청으로 한 번 더 시도한다
      let text = try await send(prompt: prompt, history: history, attachments: attachments)
      await onDelta(text)
      return text
    }
    return full
  }

  /// 스트리밍 + **도구 호출 수집** (Ollama `/api/chat`).
  /// Ollama 는 NDJSON 한 줄에 `message.content` 과 `message.tool_calls` 가 함께 온다.
  public func streamWithTools(messages: [[String: Any]],
                              tools: [[String: Any]],
                              onDelta: @escaping @MainActor (String) -> Void) async throws
    -> (text: String, toolCalls: [AgentToolCall], reasoning: String?) {
    var body: [String: Any] = ["model": model, "messages": messages, "stream": true]
    if !tools.isEmpty {
      body["tools"] = tools
      body["tool_choice"] = "auto"
    }
    var req = URLRequest(url: host.appendingPathComponent("api/chat"))
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
    req.timeoutInterval = Self.requestTimeout
    req.httpBody = try JSONSerialization.data(withJSONObject: body)

    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
    let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
    guard status == 200 else {
      throw Self.failure(data: try await HTTPStream.collect(bytes), status: status,
                         hasImage: false, bodyText: nil)
    }
    var full = ""
    var calls: [AgentToolCall] = []
    for try await raw in bytes.lines {
      let line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty, let data = line.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
      if let msg = obj["message"] as? [String: Any] {
        if let d = msg["content"] as? String, !d.isEmpty {
          full += d
          await onDelta(d)
        }
        if let rawCalls = msg["tool_calls"] as? [[String: Any]], !rawCalls.isEmpty {
          for (i, raw) in rawCalls.enumerated() {
            let fn = raw["function"] as? [String: Any] ?? [:]
            let name = fn["name"] as? String ?? "shell"
            let args: String
            if let text = fn["arguments"] as? String {
              args = text
            } else if let object = fn["arguments"],
                      let encoded = try? JSONSerialization.data(withJSONObject: object) {
              args = String(data: encoded, encoding: .utf8) ?? "{}"
            } else {
              args = "{}"
            }
            calls.append(AgentToolCall(id: raw["id"] as? String ?? "call_\(i)",
                                       name: name, arguments: args))
          }
        }
      }
      if (obj["done"] as? Bool) == true { break }
    }
    return (full, calls, nil)
  }

  static func failure(data: Data, status: Int, hasImage: Bool, bodyText: String?) -> QuickTalkError {
    let body = bodyText ?? String(data: data, encoding: .utf8) ?? ""
    let mentionsImage = hasImage &&
      (body.lowercased().contains("image") || body.lowercased().contains("vision")
       || body.lowercased().contains("multimodal"))
    if let failure = ServerFailure.classify(status: status, body: body, hasImage: hasImage) {
      if mentionsImage, !failure.canRetryWithoutImage {
        return .serverFailure(.attachmentUnsupported(status: status, code: failure.serverCode))
      }
      return .serverFailure(failure)
    }
    return .networkUnavailable()
  }

  static func decode(data: Data, status: Int, hasImage: Bool) throws -> String {
    guard status == 200 else { throw failure(data: data, status: status, hasImage: hasImage, bodyText: nil) }
    guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let text = (json["message"] as? [String: Any])?["content"] as? String,
          !text.isEmpty else {
      throw QuickTalkError.serverFailure(.emptyResponse(status: status))
    }
    return text
  }

  /// GET {host}/api/tags → 설치된 모델명 목록 (설정 UI "설치된 모델 불러오기")
  public static func listModels(host: URL) async throws -> [String] {
    var req = URLRequest(url: host.appendingPathComponent("api/tags"))
    req.httpMethod = "GET"
    let (data, resp) = try await URLSession.shared.data(for: req)
    guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw QuickTalkError.networkUnavailable() }
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let list = json?["models"] as? [[String: Any]] ?? []
    return list.compactMap { $0["name"] as? String }
  }
}

// Apple FM: macOS 26+ FoundationModels. 실호출은 App 타깃 AppleFMClient.
public enum AppleFM {
  public static var isSupported: Bool {
    if #available(macOS 26.0, *) { return true } else { return false }
  }
}

// MARK: - 구버전 설정 디코딩 호환 (신규 코드에서 사용 금지)

/// v0.9 이전 단일 프로바이더 설정의 rawValue. 마이그레이션 전용.
enum LegacyLLMProviderKind: String, Codable {
  case openAI = "OpenAI 호환"
  case ollama = "Ollama 로컬"
  case appleFM = "Apple FM 온디바이스"

  var providerID: String {
    switch self {
    case .openAI: return LLMProviderConfig.remoteOpenAIID
    case .ollama: return LLMProviderConfig.ollamaID
    case .appleFM: return LLMProviderConfig.appleFMID
    }
  }
}
