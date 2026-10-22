import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

// [FEATURE] 프로바이더 3종의 에이전트 클라이언트 (PLAN_v0.18 §5)
//
// 세 프로바이더가 **같은 기능**을 같은 도구로 돌린다.
//   · 원격 OpenAI 호환 — `tools` 배열 + `tool_calls`
//   · Local Ollama      — `/api/chat` 의 `tools` + `message.tool_calls`
//   · Apple FM          — FoundationModels `Tool` 프로토콜 (`call(arguments:)` 자동 실행)
//
// 스파이크 근거: docs/qa/t18-spike/ (Apple FM 실제 호출 성공 4.0초)

// MARK: - OpenAI 호환 (원격 · Ollama 의 /v1 경로도 동일 형식)

final class OpenAICompatibleAgentClient: AgentClient {
  private let client: OpenAIClient
  private let systemPrompt: String

  init(client: OpenAIClient, systemPrompt: String) {
    self.client = client
    self.systemPrompt = systemPrompt
  }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    var payload: [[String: Any]] = [["role": "system", "content": systemPrompt]]
    // 마지막 사용자 메시지에 첨부(이미지·문서 본문)를 붙인다 — 일반 대화와 같은 규칙
    for (i, m) in messages.enumerated() {
      var dict = m.openAIMessage
      if i == messages.count - 1, m.role == .user, !attachments.isEmpty {
        dict = Self.userMessage(text: m.content, attachments: attachments)
      }
      payload.append(dict)
    }
    let result = try await client.streamWithTools(messages: payload,
                                                  tools: AgentTool.schemaArray(tools),
                                                  onDelta: onDelta)
    if !result.toolCalls.isEmpty {
      return .toolCalls(result.toolCalls, reasoning: result.reasoning)
    }
    return .finalAnswer(result.text, reasoning: result.reasoning)
  }

  /// 텍스트 + 이미지 파트 — 일반 대화 경로와 동일한 형식
  static func userMessage(text: String, attachments: [OutgoingAttachment]) -> [String: Any] {
    let body = AttachmentLoader.composeText(prompt: text, attachments: attachments)
    let images = attachments.compactMap { $0.hasImage ? $0.imageDataURL : nil }
    if images.isEmpty { return ["role": "user", "content": body] }
    var parts: [[String: Any]] = [["type": "text", "text": body.isEmpty ? "첨부한 이미지를 확인해 주세요." : body]]
    for url in images { parts.append(["type": "image_url", "image_url": ["url": url]]) }
    return ["role": "user", "content": parts]
  }
}

// MARK: - Ollama (/api/chat)

/// Ollama는 `/api/chat` 를 쓴다(프록시가 아니라 로컬 서버).
/// `tools` 를 받고 `message.tool_calls` 로 되돌린다(인자는 **객체**로 온다 — 문자열이 아니라).
final class OllamaAgentClient: AgentClient {
  private let host: URL
  private let model: String
  private let systemPrompt: String
  private let timeout: TimeInterval

  init(host: URL, model: String, systemPrompt: String, timeout: TimeInterval = 300) {
    self.host = host; self.model = model
    self.systemPrompt = systemPrompt; self.timeout = timeout
  }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    var payload: [[String: Any]] = [["role": "system", "content": systemPrompt]]
    // 마지막 사용자 메시지에 첨부를 붙인다(이미지는 base64)
    for (i, m) in messages.enumerated() {
      var dict = m.openAIMessage
      if i == messages.count - 1, m.role == .user, !attachments.isEmpty {
        dict = Self.userMessage(text: m.content, attachments: attachments)
      }
      payload.append(dict)
    }
    let result = try await OllamaClient(host: host, model: model)
      .streamWithTools(messages: payload, tools: AgentTool.schemaArray(tools), onDelta: onDelta)
    if !result.toolCalls.isEmpty {
      return .toolCalls(result.toolCalls, reasoning: result.reasoning)
    }
    return .finalAnswer(result.text, reasoning: result.reasoning)
  }

  /// Ollama 용 사용자 메시지 — 이미지 필드는 `images: [base64]`
  static func userMessage(text: String, attachments: [OutgoingAttachment]) -> [String: Any] {
    let body = AttachmentLoader.composeText(prompt: text, attachments: attachments)
    let images = attachments.compactMap { $0.hasImage ? $0.imageBase64 : nil }
    var m: [String: Any] = ["role": "user", "content": body]
    if !images.isEmpty { m["images"] = images }
    return m
  }
}

// MARK: - Apple FM (FoundationModels)

#if canImport(FoundationModels)
/// FoundationModels 의 `@Generable` 인자 구조체 — `Tool` 프로토콜은 String/Int 인자를 받지 않는다.
@available(macOS 26.0, *)
@Generable
struct FMShellArgs {
  @Guide(description: "실행할 셸 명령")
  var command: String
}

@available(macOS 26.0, *)
@Generable
struct FMPathArgs {
  @Guide(description: "경로")
  var path: String
}

/// 셸 도구 — FoundationModels 가 `call(arguments:)` 를 **자동으로** 호출한다.
/// 여기서 정책 판단(샌드박스 실측·사용자 확인)을 거치므로, 도구 실행이 곧 권한 게이트다.
@available(macOS 26.0, *)
struct FMShellTool: Tool {
  let tool: AgentTool
  let executor: any AgentToolExecutor

  var name: String { tool.name }
  var description: String { tool.description }

  func call(arguments: FMShellArgs) async throws -> String {
    let json = "{\"command\":\(Self.quote(arguments.command))}"
    let call = AgentToolCall(id: UUID().uuidString, name: tool.name, arguments: json)
    let outcome = await executor.execute(call, tools: [tool])
    return outcome.output
  }

  static func quote(_ s: String) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: [s])) ?? Data("[]".utf8)
    let array = String(data: data, encoding: .utf8) ?? "[]"
    return String(array.dropFirst().dropLast())
  }
}

/// 경로 도구(read_file · list_dir 공통)
@available(macOS 26.0, *)
struct FMPathTool: Tool {
  let tool: AgentTool
  let executor: any AgentToolExecutor

  var name: String { tool.name }
  var description: String { tool.description }

  func call(arguments: FMPathArgs) async throws -> String {
    let json = "{\"path\":\(FMShellTool.quote(arguments.path))}"
    let call = AgentToolCall(id: UUID().uuidString, name: tool.name, arguments: json)
    let outcome = await executor.execute(call, tools: [tool])
    return outcome.output
  }
}
#endif

#if canImport(FoundationModels)
/// `GeneratedContent` → JSON 직렬화 가능한 값으로 바꾼다.
/// (FoundationModels 의 값은 그대로 JSONEncoder 에 넣으면 예외가 난다)
@available(macOS 26.0, *)
extension FoundationModels.GeneratedContent {
  var jsonValue: Any {
    switch kind {
    case .null: return NSNull()
    case .bool(let b): return b
    case .number(let n): return n
    case .string(let s): return s
    case .array(let items): return items.map { $0.jsonValue }
    case .structure(let props, _): return props.mapValues { $0.jsonValue }
    }
  }
}
#endif

/// Apple FM 에이전트 클라이언트 — 도구 세 개(shell·read_file·list_dir)를 FoundationModels 에 넘긴다.
@available(macOS 26.0, *)
final class AppleFMAgentClient: AgentClient {  private let executor: any AgentToolExecutor
  private let systemPrompt: String
  private let tools: [AgentTool]

  init(executor: any AgentToolExecutor, systemPrompt: String, tools: [AgentTool]) {
    self.executor = executor; self.systemPrompt = systemPrompt; self.tools = tools
  }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    #if canImport(FoundationModels)
    let model = SystemLanguageModel.default
    switch model.availability {
    case .available: break
    case .unavailable(let reason):
      throw QuickTalkError.detailed(Lf("Apple FM 사용 불가: %@", String(describing: reason)),
                                    code: "E-MAC-AGENT-0003")
    }
    // 사용 가능한 도구만 FoundationModels 용으로 만든다.
    var fmTools: [any FoundationModels.Tool] = []
    for tool in tools {
      switch tool.name {
      case "shell":
        fmTools.append(FMShellTool(tool: tool, executor: executor))
      case "read_file", "list_dir":
        fmTools.append(FMPathTool(tool: tool, executor: executor))
      default:
        continue
      }
    }
    let history = messages.map { m in
      m.role == .user ? "사용자: \(m.content)" : "어시스턴트: \(m.content)"
    }.joined(separator: "\n")
    let last = messages.last(where: { $0.role == .user })?.content ?? ""
    let prompt = history.isEmpty ? last : "\(history)\n\n새 질문: \(last)"
    let session = LanguageModelSession(model: model, tools: fmTools,
                                       instructions: systemPrompt)
    let response = try await session.respond(to: prompt)
    // 호출 내역은 transcript 에 남는다(실행 카드·감사 로그용).
    var calls: [AgentToolCall] = []
    for entry in response.transcriptEntries {
      guard case .toolCalls(let toolCalls) = entry else { continue }
      for call in toolCalls {
        var arguments = "{}"
        // GeneratedContent 는 JSON 직렬화 대상이 아니다 → JSON 값으로 바꿔야 한다.
        if case .structure(let props, _) = call.arguments.kind {
          let plain = props.mapValues { $0.jsonValue }
          if let data = try? JSONSerialization.data(withJSONObject: plain),
             let text = String(data: data, encoding: .utf8) {
            arguments = text
          }
        }
        calls.append(AgentToolCall(id: call.id, name: call.toolName, arguments: arguments))
      }
    }
    if !calls.isEmpty { return .toolCalls(calls, reasoning: nil) }
    return .finalAnswer(response.content, reasoning: nil)
    #else
    throw QuickTalkError.detailed(L("이 시스템은 Apple FM 도구를 쓸 수 없습니다."), code: "E-MAC-AGENT-0003")
    #endif
  }
}
