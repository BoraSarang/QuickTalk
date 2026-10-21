import Foundation

// [FEATURE] 에이전트 런타임 — 권한 단계 · 위험도 · 도구 타입 (PLAN_v0.18)
//
// v0.18의 핵심: **앱은 명령어 이름을 모른다.** `brew`·`adb`·`pip`를 하드코딩하지 않는다.
// 모델이 정한 명령을 앱은 그대로 실행하고, 그 명령이 **무슨 권한을 요구하는지**만 판단한다.
// 판단은 하드코딩이 아니라 **샌드박스로 실측**한다(SandboxRunner).

// MARK: - 권한 단계

/// 앱이 사용할 수 있는 권한 3단계 — "무엇을 하는가".
public enum AgentPermissionLevel: String, Codable, CaseIterable, Identifiable, Equatable {
  /// 상태를 조회만 한다(파일 읽기·목록·프로세스·시스템 정보·네트워크 측정)
  case read
  /// 사용자 데이터를 바꾸되 되돌릴 수 있다(파일 생성·수정·휴지통 이동·설정 변경)
  case write
  /// 외부 프로그램을 실행해 상태를 바꾼다(패키지 설치·기기 배포·네트워크 조회)
  case execute

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .read: return L("읽기")
    case .write: return L("쓰기")
    case .execute: return L("실행")
    }
  }

  /// 단계가 높을수록 위험 — 비교와 "이 단계까지 자동 허용" 설정에 쓴다.
  public var rank: Int {
    switch self {
    case .read: return 0
    case .write: return 1
    case .execute: return 2
    }
  }

  public var explanation: String {
    switch self {
    case .read:
      return L("파일을 읽고 화면 정보를 확인합니다. 시스템에 아무 변화도 없습니다.")
    case .write:
      return L("파일·설정·일정을 만듭니다. 되돌릴 수 있는 변경만 이 단계로 다룹니다.")
    case .execute:
      return L("프로그램을 실행합니다. 설치·배포처럼 되돌리기 어려울 수 있습니다.")
    }
  }
}

/// 단계별 자동 처리 정책 — "항상 허용" 또는 "매번 확인".
public enum AgentAutoApprove: String, Codable, CaseIterable, Identifiable, Equatable {
  case alwaysAllow
  case alwaysAsk

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .alwaysAllow: return L("항상 허용")
    case .alwaysAsk: return L("매번 확인")
    }
  }
}

/// 위험도 — "잘못 되면 얼마나 심각한가". 권한 단계와 **별개 축**이다.
public enum AgentRiskLevel: Int, Codable, CaseIterable, Identifiable, Equatable {
  /// 되돌릴 수 있거나 영향이 국소적
  case normal = 0
  /// 되돌리기 어렵거나 시스템 전역 — **자동 허용이어도 반드시 확인**한다
  case important = 1
  /// 복구 불가(부팅 불능·데이터 파괴) — 기본 차단
  case critical = 2

  public var id: Int { rawValue }

  public var displayName: String {
    switch self {
    case .normal: return L("보통")
    case .important: return L("중요")
    case .critical: return L("치명적")
    }
  }
}

// MARK: - 도구

/// 프로바이더 중립 도구 정의 — OpenAI 형식 스키마를 그대로 담는다.
/// 스키마는 만들어진 뒤 바뀌지 않으므로 `Sendable` 로 취급한다.
public struct AgentTool: @unchecked Sendable {
  public let name: String
  public let description: String
  /// OpenAI `tools` 배열 원소(`type` + `function`)
  public let openAISchema: [String: Any]

  public init(name: String, description: String, parameters: [String: Any]) {
    self.name = name
    self.description = description
    self.openAISchema = [
      "type": "function",
      "function": [
        "name": name,
        "description": description,
        "parameters": parameters
      ]
    ]
  }

  /// OpenAI `tools` 배열 전체
  public static func schemaArray(_ tools: [AgentTool]) -> [[String: Any]] {
    tools.map(\.openAISchema)
  }
}

/// 모델이 부른 도구 한 건.
public struct AgentToolCall: Equatable {
  public let id: String
  public let name: String
  /// 인자(JSON 문자열)
  public let arguments: String

  public init(id: String, name: String, arguments: String) {
    self.id = id; self.name = name; self.arguments = arguments
  }

  /// 인자에서 문자열 값을 꺼낸다(`{"command":"ls"}` → "ls").
  public func stringArgument(_ key: String) -> String? {
    guard let data = arguments.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      let raw = arguments.trimmingCharacters(in: .whitespacesAndNewlines)
      return raw.isEmpty ? nil : raw
    }
    return (obj[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// 모델 ↔ 앱 사이의 한 줄.
public struct AgentMessage {
  public enum Role: String { case user, assistant, tool }
  public let role: Role
  public let content: String
  public let toolCalls: [AgentToolCall]?
  public let toolCallID: String?
  /// thinking 모드 모델의 사고 내용 — **다음 요청에 그대로 되돌려야 한다.**
  /// (프록시가 `reasoning_content` 를 요구한다 — 빠지면 400 으로 거절된다)
  public let reasoningContent: String?

  public init(role: Role, content: String,
              toolCalls: [AgentToolCall]? = nil, toolCallID: String? = nil,
              reasoningContent: String? = nil) {
    self.role = role; self.content = content
    self.toolCalls = toolCalls; self.toolCallID = toolCallID
    self.reasoningContent = reasoningContent
  }

  /// OpenAI `messages` 원소로 변환 — tool_calls 는 규격대로 되돌린다.
  public var openAIMessage: [String: Any] {
    var m: [String: Any] = ["role": role.rawValue]
    switch role {
    case .tool:
      m["content"] = content
      if let toolCallID { m["tool_call_id"] = toolCallID }
    case .assistant:
      m["content"] = content.isEmpty ? NSNull() : content
      if let reasoningContent, !reasoningContent.isEmpty {
        m["reasoning_content"] = reasoningContent
      }
      if let toolCalls, !toolCalls.isEmpty {
        m["tool_calls"] = toolCalls.map { call in
          ["id": call.id, "type": "function",
           "function": ["name": call.name, "arguments": call.arguments]]
        }
      }
    case .user:
      m["content"] = content
    }
    return m
  }
}

/// 모델의 한 스텝 결과 — 도구를 부르거나, 답을 완성했다.
public enum AgentStep: Equatable {
  /// 도구 호출 — `reasoning` 은 thinking 모드의 사고 내용(다음 요청에 되돌려야 한다)
  case toolCalls([AgentToolCall], reasoning: String?)
  /// 최종 답변
  case finalAnswer(String, reasoning: String?)
}

/// 프로바이더 중립 에이전트 클라이언트 — 3종(Apple FM·Ollama·OpenAI 호환)이 각각 구현한다.
public protocol AgentClient: AnyObject {
  /// 도구를 넘겨 한 스텝 진행한다. 도구 호출이 없으면 `.finalAnswer`.
  func nextStep(messages: [AgentMessage], tools: [AgentTool]) async throws -> AgentStep
}
