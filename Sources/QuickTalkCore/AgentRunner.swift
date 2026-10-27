import Foundation

// [FEATURE] 에이전트 루프 — 호출 → 도구 실행 → 관찰 → 반복 (PLAN_v0.18 §5)
//
// 모델이 도구를 부르면 앱이 실행하고, 결과를 되돌려 다음 스텝을 진행한다.
// 실행 카드(AgentEvent)는 앱 화면에 그리기 위한 기록이고, 감사로그와도 같은 데이터를 쓴다.

/// 도구 실행 1건의 기록 — 화면 카드·감사 로그 공용.
public struct AgentEvent: Codable, Equatable, Identifiable {
  public enum State: String, Codable, Equatable {
    /// 승인을 기다리는 중
    case pending
    /// 실행 중
    case running
    /// 승인됨
    case allowed
    /// 사용자가 거부함
    case denied
    /// 끝남(성공)
    case done
    /// 실패
    case failed
  }

  public let id: String
  public let toolName: String
  /// 화면에 보여줄 한 줄(명령 또는 작업)
  public let title: String
  /// 실행한 명령(또는 경로)
  public let command: String
  public let level: AgentPermissionLevel
  public let risk: AgentRiskLevel
  public var state: State
  public var output: String
  public var elapsedMs: Int
  /// 이 실행으로 되돌릴 수 있는 스냅샷 — [되돌리기] 카드가 쓴다(구버전 기록에는 없다)
  public var undoID: String?
  /// 앱이 실행하지 않고 **터미널로 넘길** 명령(v0.20) — 카드에 [터미널에서 열기]가 뜬다.
  public var terminalCommand: String?

  public init(id: String, toolName: String, title: String, command: String,
              level: AgentPermissionLevel, risk: AgentRiskLevel,
              state: State = .pending, output: String = "", elapsedMs: Int = 0,
              undoID: String? = nil, terminalCommand: String? = nil) {
    self.id = id; self.toolName = toolName; self.title = title; self.command = command
    self.level = level; self.risk = risk; self.state = state
    self.output = output; self.elapsedMs = elapsedMs; self.undoID = undoID
    self.terminalCommand = terminalCommand
  }
}

/// 도구 실행 결과.
public struct AgentToolOutcome {
  /// 모델에게 되돌려줄 내용(요약 — 원문 전체를 주지 않는다)
  public let output: String
  /// 사용자가 거부했거나 정책이 막은 경우
  public let denied: Bool
  public let level: AgentPermissionLevel
  public let risk: AgentRiskLevel
  /// 스크린샷 도구가 만든 이미지(v0.21) — 다음 스텝에 첨부로 붙는다.
  public let imageURL: URL?
  /// 앱이 실행하지 않고 터미널로 넘길 명령(v0.20)
  public let terminalCommand: String?

  public init(output: String, denied: Bool = false,
              level: AgentPermissionLevel = .read, risk: AgentRiskLevel = .normal,
              imageURL: URL? = nil, terminalCommand: String? = nil) {
    self.output = output; self.denied = denied; self.level = level; self.risk = risk
    self.imageURL = imageURL; self.terminalCommand = terminalCommand
  }
}

/// 도구 실행 주체 — 앱 쪽에서 구현한다(정책 판단·사용자 확인을 담당).
public protocol AgentToolExecutor: AnyObject, Sendable {
  /// 도구 호출을 실행한다. 승인이 필요하면 구현체가 사용자 응답을 기다린 뒤 진행한다.
  /// 메인 액터에서 돌아간다(UI 갱신·사용자 확인이 메인에서 이뤄야 한다).
  @MainActor
  func execute(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome
}

/// 루프 결과.
public struct AgentRunResult {
  public let answer: String
  public let events: [AgentEvent]
  public let steps: Int
  /// 도구 호출이 한 번이라도 거부됐는가
  public let hadDenial: Bool
}

public struct AgentRunner {
  public let client: any AgentClient
  public let executor: any AgentToolExecutor
  /// 최대 스텝 수 — 무한 루프·비용 방지(기본 8)
  public let maxSteps: Int

  public init(client: any AgentClient, executor: any AgentToolExecutor, maxSteps: Int = 8) {
    self.client = client; self.executor = executor; self.maxSteps = maxSteps
  }

  /// 에이전트 루프 실행.
  /// `onDelta` 로 최종 답변이 토큰 단위로 흘러나온다(스트리밍 유지).
  public func run(prompt: String,
                  history: [Turn],
                  tools: [AgentTool],
                  attachments: [OutgoingAttachment] = [],
                  onDelta: @escaping @MainActor (String) -> Void = { _ in }) async throws -> AgentRunResult {
    var messages: [AgentMessage] = history.map {
      AgentMessage(role: $0.role == .user ? .user : .assistant, content: $0.text)
    }
    messages.append(AgentMessage(role: .user, content: prompt))

    var events: [AgentEvent] = []
    var hadDenial = false
    var steps = 0
    var collected: [String] = []
    /// 스크린샷 도구가 만든 이미지 — 다음 스텝의 **사용자 메시지**에 붙인다(v0.21).
    /// (클라이언트는 마지막 메시지가 user 일 때만 첨부를 싣는다 — tool 메시지 뒤에는 안 붙는다)
    var images: [OutgoingAttachment] = []
    /// 실행한 명령의 반복 횟수 — 같은 명령 무한 반복 방지
    var signatures: [String: Int] = [:]

    while steps < maxSteps {
      steps += 1
      try Task.checkCancellation()
      // ★ 사용자 첨부와 스크린샷을 **함께** 싣는다. 예전에는 스크린샷이 한 장이라도
      //   생기면 `images` 만 보내 **사용자가 붙인 첨부가 사라졌다**(2026-10-27).
      let step = try await client.nextStep(messages: messages, tools: tools,
                                           attachments: attachments + images,
                                           onDelta: onDelta)
      switch step {
      case .finalAnswer(let text, _):
        return AgentRunResult(answer: text, events: events, steps: steps, hadDenial: hadDenial)

      case .toolCalls(let calls, let reasoning):
        guard !calls.isEmpty else {
          return AgentRunResult(answer: "", events: events, steps: steps, hadDenial: hadDenial)
        }
        // assistant 메시지에 tool_calls 를 그대로 넣어야 프로토콜이 맞는다.
        // thinking 모드 모델은 사고 내용(reasoning_content)도 되돌려야 한다 — 빠지면 400.
        messages.append(AgentMessage(role: .assistant, content: "", toolCalls: calls,
                                      reasoningContent: reasoning))
        var addedImage = false
        for call in calls {
          try Task.checkCancellation()
          // 같은 명령을 몇 번이나 반복하면(특히 작은 온디바이스 모델) 무한 반복이 된다.
          // 2번 반복된 명령은 다시 실행하지 않고, 모델에게 다른 방법을 쓰라고 알린다.
          let signature = "\(call.name)|\(call.stringArgument("command") ?? call.stringArgument("path") ?? call.stringArgument("query") ?? "")"
          let repeats = (signatures[signature] ?? 0) + 1
          signatures[signature] = repeats
          if repeats > 2 {
            let note = L("같은 명령이 여러 번 실행되었습니다. 다른 방법을 사용하세요.")
            events.append(AgentEvent(id: call.id, toolName: call.name,
                                     title: Self.title(for: call, tools: tools),
                                     command: call.stringArgument("command") ?? "",
                                     level: .read, risk: .normal, state: .failed, output: note))
            messages.append(AgentMessage(role: .tool, content: note, toolCallID: call.id))
            continue
          }
          let outcome = await executor.execute(call, tools: tools)
          if outcome.denied { hadDenial = true }
          // 스크린샷은 다음 스텝에 첨부로 — 최대 3장(토큰·전송량 상한).
          if let url = outcome.imageURL, images.count < 3 {
            let loaded = AttachmentLoader.load(name: url.lastPathComponent, kind: .image, url: url)
            if loaded.hasImage { images.append(loaded); addedImage = true }
          }
          let summary = Self.summarize(outcome.output)
          events.append(AgentEvent(id: call.id, toolName: call.name,
                                   title: Self.title(for: call, tools: tools),
                                   command: call.stringArgument("command")
                                     ?? call.stringArgument("path")
                                     ?? call.stringArgument("query") ?? "",
                                   level: outcome.level, risk: outcome.risk,
                                   state: outcome.denied ? .denied : .done,
                                   output: summary, elapsedMs: 0,
                                   terminalCommand: outcome.terminalCommand))
          collected.append("\(call.name): \(summary)")
          messages.append(AgentMessage(role: .tool, content: outcome.output, toolCallID: call.id))
        }
        // tool 메시지 뒤에 **사용자 메시지**를 하나 둬야 다음 요청에 이미지가 실린다.
        if addedImage {
          messages.append(AgentMessage(role: .user,
                                       content: L("(방금 찍은 스크린샷을 첨부했습니다. 다음 판단에 참고하세요.)")))
        }
      }
    }
    // 스텝 상한에 걸렸으면 모델이 답하지 못했으므로 **지금까지 모은 결과**로 답한다.
    let collectedText = collected.suffix(3).joined(separator: "\n\n")
    let answer = L("작업이 길어 중단했습니다. 지금까지 확인한 내용은 아래와 같습니다.")
      + (collectedText.isEmpty ? "" : "\n\n" + collectedText)
    return AgentRunResult(answer: answer, events: events, steps: steps, hadDenial: hadDenial)
  }

  /// 실행 카드에 보여줄 한 줄.
  static func title(for call: AgentToolCall, tools: [AgentTool]) -> String {
    switch call.name {
    case "shell":
      let cmd = call.stringArgument("command") ?? ""
      let purpose = call.stringArgument("purpose") ?? ""
      return purpose.isEmpty ? cmd : "\(purpose) — \(cmd)"
    case "read_file":
      return Lf("파일 읽기 — %@", call.stringArgument("path") ?? "")
    case "list_dir":
      return Lf("폴더 목록 — %@", call.stringArgument("path") ?? "")
    case "processes":
      let sort = (call.stringArgument("sort") ?? "cpu") == "memory" ? L("메모리") : L("CPU")
      return Lf("프로세스 사용량 — %@ 순위", sort)
    case "screenshot":
      let target = (call.stringArgument("target") ?? "window") == "screen" ? L("화면") : L("창")
      return Lf("스크린샷 — %@", target)
    case "web_search":
      return Lf("웹 검색 — %@", call.stringArgument("query") ?? "")
    default:
      return tools.first { $0.name == call.name }?.name ?? call.name
    }
  }

  /// 모델에게 돌려줄 요약 — 출력이 크면 자른다.
  static func summarize(_ output: String) -> String {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 2_000 { return trimmed }
    return String(trimmed.prefix(2_000)) + "\n… (생략)"
  }
}
