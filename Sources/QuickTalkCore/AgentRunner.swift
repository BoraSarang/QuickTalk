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
  /// 이 도구 호출 **직전** 모델의 사고 과정(thinking 모델, v0.31).
  /// 사고 → 도구 → 사고 → 도구 순서를 화면에 그대로 그리기 위해 카드에 함께 남긴다.
  /// 구버전 기록에는 없으므로 nil.
  public var reasoningBefore: String?
  /// 이 명령이 실행한 **스킬 id**(v0.37) — 명령에 드러난 스킬 경로에서 알아낸 최선 노력 값.
  /// 카드에 `스킬: …` 한 줄을 붙여 어떤 절차가 돌았는지 보이게 한다.
  public var skillName: String?

  public init(id: String, toolName: String, title: String, command: String,
              level: AgentPermissionLevel, risk: AgentRiskLevel,
              state: State = .pending, output: String = "", elapsedMs: Int = 0,
              undoID: String? = nil, terminalCommand: String? = nil,
              reasoningBefore: String? = nil, skillName: String? = nil) {
    self.id = id; self.toolName = toolName; self.title = title; self.command = command
    self.level = level; self.risk = risk; self.state = state
    self.output = output; self.elapsedMs = elapsedMs; self.undoID = undoID
    self.terminalCommand = terminalCommand; self.reasoningBefore = reasoningBefore
    self.skillName = skillName
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
  /// `propose_plan` 이 제안한 계획 — 있으면 UI 가 계획 카드를 그리고 실행은 사용자 결정으로 미룬다.
  public let plan: ExecutionPlan?
  /// 스텝 상한에 걸려 **일이 남은 채** 끝났는가(v0.38 Job 구간 이어가기).
  /// `stopAtStepLimit` 을 켠 러너만 true 를 낸다 — 기존 실행은 영향 없다.
  public let hitStepLimit: Bool

  public init(answer: String, events: [AgentEvent], steps: Int,
              hadDenial: Bool, plan: ExecutionPlan? = nil,
              hitStepLimit: Bool = false) {
    self.answer = answer; self.events = events; self.steps = steps
    self.hadDenial = hadDenial; self.plan = plan
    self.hitStepLimit = hitStepLimit
  }
}

public struct AgentRunner {
  public let client: any AgentClient
  public let executor: any AgentToolExecutor
  /// 최대 스텝 수 — 무한 루프·비용 방지(기본 8)
  public let maxSteps: Int
  /// 상한에 닿으면 **최종 답변을 재촉하지 않고** 바로 멈춘다 — Job이 다음 구간을 이어 간다.
  public let stopAtStepLimit: Bool

  public init(client: any AgentClient, executor: any AgentToolExecutor, maxSteps: Int = 8,
              stopAtStepLimit: Bool = false) {
    self.client = client; self.executor = executor; self.maxSteps = maxSteps
    self.stopAtStepLimit = stopAtStepLimit
  }

  /// 에이전트 루프 실행.
  /// `onDelta` 로 최종 답변이 토큰 단위로 흘러나온다(스트리밍 유지).
  ///
  /// - `retry`: 스텝 도중 연결이 끊기면 **같은 단계를 다시 요청**한다. 이미 실행한 도구는
  ///   되돌리지 않고, 실패한 스텝에서 흘러나온 글자만 `onStepDiscard` 로 지운다.
  /// - `onStepStart`: 한 스텝(=모델 호출)을 시작할 때. 호출부가 말풍선의 현재 글자를 기억한다.
  /// - `onStepDiscard`: 그 스텝의 글자를 버려야 할 때(도구 호출 예고·재시도). 호출부가 기억한
  ///   지점으로 말풍선을 되돌린다. **도구 호출 스텝의 예고 문장이 최종 답변에 섞이던 문제**를 막는다.
  /// - `onRetry`: 재시도 대기 상태(끝나면 nil).
  public func run(prompt: String,
                  history: [Turn],
                  tools: [AgentTool],
                  attachments: [OutgoingAttachment] = [],
                  retry: NetworkRetryPolicy = .standard,
                  onDelta: @escaping @MainActor (String) -> Void = { _ in },
                  onReasoning: @escaping @MainActor (String) -> Void = { _ in },
                  onStepStart: @escaping @MainActor () -> Void = {},
                  onStepDiscard: @escaping @MainActor () -> Void = {},
                  onRetry: @escaping @MainActor (NetworkRetryProgress?) -> Void = { _ in }) async throws -> AgentRunResult {
    // 사고 과정 델타 — 클라이언트가 도착하는 대로 흘려보낸다(화면 표시용).
    client.onReasoning = onReasoning
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
    /// "최종 답변을 쓰라"는 재촉을 이미 했는가 — 무한 재촉 방지
    var nudged = false

    /// 모델 호출 1회 — 연결이 끊기면 **같은 메시지로** 다시 요청한다.
    /// 실패한 시도의 부분 글자는 `onStepDiscard` 로 지우므로 중복되지 않는다.
    func callStep(tools: [AgentTool]) async throws -> AgentStep {
      var failures = 0
      while true {
        await onStepStart()
        do {
          let step = try await client.nextStep(messages: messages, tools: tools,
                                               attachments: attachments + images,
                                               onDelta: onDelta)
          await onRetry(nil)
          return step
        } catch {
          if Task.isCancelled || error is CancellationError { throw error }
          guard retry.canRetry(afterFailures: failures),
                NetworkRetry.isRetryable(error) else {
            await onRetry(nil)
            throw error
          }
          failures += 1
          await onStepDiscard()
          await onRetry(NetworkRetryProgress(attempt: failures,
                                             maxAttempts: retry.maxAttempts,
                                             waitSeconds: retry.intervalSeconds))
          NSLog("[QuickTalk] 연결 끊김 — %d/%d회, %d초 후 같은 단계를 다시 요청",
                failures, retry.maxAttempts, retry.intervalSeconds)
          try await Task.sleep(nanoseconds: UInt64(retry.interval * 1_000_000_000))
        }
      }
    }

    /// 지금까지 확인한 결과만으로 답을 만든다 — 모델이 끝내 답을 못 쓸 때의 **마지막 안전망**.
    func fallbackAnswer() -> String {
      let collectedText = collected.suffix(4).joined(separator: "\n\n")
      let head = L("도구 실행은 끝났지만 모델이 최종 답변을 작성하지 못했습니다. 지금까지 확인한 내용은 아래와 같습니다.")
      return head + (collectedText.isEmpty ? "" : "\n\n" + collectedText)
    }

    /// 도구를 **빼고** 최종 답변만 요구한다. 예고 문장으로 끝나는 답을 결과로 바꾸는 장치.
    func nudgedAnswer() async throws -> String? {
      messages.append(AgentMessage(role: .user, content: AgentInstructions.finalAnswerNudge))
      do {
        let step = try await callStep(tools: [])
        guard case .finalAnswer(let text, _) = step else {
          await onStepDiscard()
          return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !Self.looksLikeNarration(trimmed) else {
          await onStepDiscard()
          return nil
        }
        return text
      } catch {
        if Task.isCancelled || error is CancellationError { throw error }
        NSLog("[WARN] 최종 답변 재촉 실패 — %@", AIErrorText.code(for: error))
        await onStepDiscard()
        return nil
      }
    }

    while steps < maxSteps {
      steps += 1
      try Task.checkCancellation()
      // ★ 사용자 첨부와 스크린샷을 **함께** 싣는다. 예전에는 스크린샷이 한 장이라도
      //   생기면 `images` 만 보내 **사용자가 붙인 첨부가 사라졌다**(2026-10-27).
      let step = try await callStep(tools: tools)
      switch step {
      case .finalAnswer(let text, _):
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // ① 빈 답 ② "확인하겠습니다" 같은 **예고만** 있는 답 → 도구를 빼고 한 번 더 요구한다.
        if trimmed.isEmpty || (!nudged && Self.looksLikeNarration(trimmed)) {
          await onStepDiscard()
          if !nudged {
            nudged = true
            if let answer = try await nudgedAnswer() {
              return AgentRunResult(answer: answer, events: events, steps: steps, hadDenial: hadDenial)
            }
          }
          return AgentRunResult(answer: fallbackAnswer(), events: events, steps: steps, hadDenial: hadDenial)
        }
        return AgentRunResult(answer: text, events: events, steps: steps, hadDenial: hadDenial)

      case .toolCalls(let calls, let reasoning):
        guard !calls.isEmpty else {
          await onStepDiscard()
          if !nudged {
            nudged = true
            if let answer = try await nudgedAnswer() {
              return AgentRunResult(answer: answer, events: events, steps: steps, hadDenial: hadDenial)
            }
          }
          return AgentRunResult(answer: fallbackAnswer(), events: events, steps: steps, hadDenial: hadDenial)
        }
        // 이 스텝에서 흘러나온 글자는 **도구 호출 예고**다 — 최종 답변으로 남기지 않는다.
        // (예전에는 이 문장이 그대로 답변이 되어 "확인하겠습니다"에서 끊긴 것처럼 보였다)
        await onStepDiscard()
        // assistant 메시지에 tool_calls 를 그대로 넣어야 프로토콜이 맞는다.
        // thinking 모드 모델은 사고 내용(reasoning_content)도 되돌려야 한다 — 빠지면 400.
        messages.append(AgentMessage(role: .assistant, content: "", toolCalls: calls,
                                      reasoningContent: reasoning))
        // ★ propose_plan 은 **실행하지 않고 멈춘다** — 계획을 카드로 보여 주고 사용자가 결정한다.
        //   같은 스텝에 다른 도구가 섞여 있어도 계획이 우선이다(손보다 입이 먼저).
        if let planCall = calls.first(where: { $0.name == PlanTool.name }) {
          if let plan = ExecutionPlan.from(planCall) {
            return AgentRunResult(
              answer: L("계획을 제안했습니다. 아래 [실행]을 누르면 이 순서로 진행합니다. 고치려면 [수정]을 누르세요."),
              events: events, steps: steps, hadDenial: hadDenial, plan: plan)
          }
          let note = L("계획 형식이 올바르지 않습니다. 목표와 3~8개의 단계를 다시 주세요.")
          messages.append(AgentMessage(role: .tool, content: note, toolCallID: planCall.id))
          continue
        }
        var addedImage = false
        for call in calls {
          try Task.checkCancellation()
          // 같은 명령을 몇 번이나 반복하면(특히 작은 온디바이스 모델) 무한 반복이 된다.
          // 2번 반복된 명령은 다시 실행하지 않고, 모델에게 다른 방법을 쓰라고 알린다.
          let signature = "\(call.name)|\(Self.signatureDetail(for: call))"
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
    // 스텝 상한에 걸렸다 — Job은 여기서 **최종 답변을 재촉하지 않는다**.
    // (재촉하면 "다 끝난 것처럼" 보이는 답이 나오고, 다음 구간과 중복된다)
    if stopAtStepLimit {
      return AgentRunResult(answer: "", events: events, steps: steps,
                            hadDenial: hadDenial, hitStepLimit: true)
    }
    // 스텝 상한에 걸렸다 — 도구를 빼고 **최종 답변만** 한 번 더 요구한다.
    // (예전에는 여기서 만든 "작업이 길어 중단했습니다 + 결과" 문구가 UI 에서 무시됐다)
    if !nudged, let answer = try await nudgedAnswer() {
      return AgentRunResult(answer: answer, events: events, steps: steps, hadDenial: hadDenial)
    }
    return AgentRunResult(answer: fallbackAnswer(), events: events, steps: steps, hadDenial: hadDenial)
  }

  /// 예고만 하고 끝나는 답인가 — 결과(수치·목록·줄바꿈) 없이 "확인하겠습니다"류로 끝나면 참.
  /// 지나치게 넓히면 정상 답변을 다시 쓰게 하므로 **짧은 한 문단**만 본다.
  public static func looksLikeNarration(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty, t.count <= 400 else { return false }
    // 줄바꿈·목록·수치가 있으면 이미 결과를 보여 준 답으로 본다.
    if t.contains("\n") || t.rangeOfCharacter(from: .decimalDigits) != nil { return false }
    let cues = [
      "확인하겠", "확인해 보겠", "조회하겠", "조회해 보겠", "찾겠", "찾고",
      "살펴보겠", "알아보겠", "진행하겠", "진행합니다", "작성하겠", "작성합니다",
      "저장하겠", "저장합니다", "보겠습니다", "다시 확인", "지금 확인"
    ]
    if cues.contains(where: { t.contains($0) }) { return true }
    let lower = t.lowercased()
    return ["i'll ", "i will ", "let me ", "checking now", "i'm going to"]
      .contains(where: { lower.contains($0) })
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
    case "web_fetch":
      return Lf("웹 페이지 읽기 — %@", call.stringArgument("url") ?? "")
    case "ui_snapshot":
      let app = (call.stringArgument("app") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return Lf("화면 요소 — %@", app.isEmpty ? L("앞에 있는 앱") : app)
    case "ui_action":
      let raw = (call.stringArgument("action") ?? "").lowercased()
      let kind = UiActionKind(rawValue: raw)
      let label = kind?.displayName ?? (raw.isEmpty ? call.name : raw)
      let app = (call.stringArgument("app") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return app.isEmpty ? label : Lf("%@ — %@", label, app)
    default:
      return tools.first { $0.name == call.name }?.name ?? call.name
    }
  }

  /// 반복 호출 판정에 쓰는 인자 요약 — `ui_action` 은 action/ref/text 까지 본다.
  /// (명령·경로만 보면 `ui_action` 이 늘 빈 문자열이라 두 번 뒤에 막힌다)
  static func signatureDetail(for call: AgentToolCall) -> String {
    if call.name == "ui_action" {
      return ["action", "ref", "app", "title"]
        .compactMap { call.stringArgument($0) }
        .joined(separator: "|")
        + "|" + String((call.stringArgument("text") ?? "").prefix(40))
    }
    return call.stringArgument("command")
      ?? call.stringArgument("path")
      ?? call.stringArgument("query")
      ?? ""
  }

  /// 모델에게 돌려줄 요약 — 출력이 크면 자른다.
  static func summarize(_ output: String) -> String {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.count <= 2_000 { return trimmed }
    return String(trimmed.prefix(2_000)) + "\n… (생략)"
  }
}
