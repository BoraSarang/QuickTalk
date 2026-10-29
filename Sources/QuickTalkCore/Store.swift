import Foundation

public enum QuickTalkError: Error, Equatable {
  case emptySubmission(code: String = "E-MAC-MODEL-0001")
  case unsupportedAttachment(String, code: String = "E-MAC-RENDER-0001")
  case speechDenied(code: String = "E-MAC-AUDIO-0001")
  case networkUnavailable(code: String = "E-MAC-NET-0001")
  case providerNotConfigured(code: String = "E-MAC-NET-0002")
  case missingAPIKey(code: String = "E-MAC-KEY-0001")
  /// 서버가 요청·첨부를 거부 — 상태코드별 분류(`ServerFailure`)로 재시도 전략을 가른다(P2).
  /// 이전에는 모든 4xx가 "이미지 거부"(E-MAC-ATT-0001)로 뭉개졌다.
  case serverFailure(ServerFailure)
  /// 이미 완성된 사용자 문구를 가진 오류 — 스트리밍 경로의 설정 오류 등.
  case detailed(String, code: String = "E-MAC-NET-0001")
  public var code: String {
    switch self {
    case .emptySubmission(let c): return c
    case .unsupportedAttachment(_, let c): return c
    case .speechDenied(let c): return c
    case .networkUnavailable(let c): return c
    case .providerNotConfigured(let c): return c
    case .missingAPIKey(let c): return c
    case .serverFailure(let f): return f.code
    case .detailed(_, let c): return c
    }
  }

  /// 사용자에게 그대로 보여줄 문구(있으면)
  public var userText: String? {
    switch self {
    case .serverFailure(let f): return "(오류 \(f.code)) \(f.userMessage)"
    case .detailed(let message, let code): return "(오류 \(code)) \(message)"
    default: return nil
    }
  }
}

public final class ConversationStore {
  public private(set) var conversation: Conversation
  public init(conversation: Conversation = Conversation()) { self.conversation = conversation }
  @discardableResult
  public func submit(text: String, attachments: [Attachment] = []) throws -> Turn {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty && attachments.isEmpty { throw QuickTalkError.emptySubmission() }
    for a in attachments {
      if a.kind == .file && !Attachment.isSupported(filename: a.name) { throw QuickTalkError.unsupportedAttachment(a.name) }
    }
    let now = Date()
    let turn = Turn(role: .user, text: t, attachments: attachments, status: .submitting,
                    createdAt: now)
    conversation.turns.append(turn)
    conversation.updatedAt = now
    conversation.applyAutoTitle()
    return turn
  }
  public func appendAssistant(text: String, elapsedMs: Int? = nil) -> Turn {
    let now = Date()
    let turn = Turn(role: .assistant, text: text, elapsedMs: elapsedMs, createdAt: now)
    conversation.turns.append(turn); conversation.updatedAt = now; return turn
  }

  /// 스트리밍 응답용 빈 어시스턴트 턴 — 델타가 도착할 때마다 `appendStreaming`으로 채운다.
  @discardableResult
  public func beginAssistantTurn() -> UUID {
    let turn = Turn(role: .assistant, text: "", createdAt: Date())
    conversation.turns.append(turn)
    return turn.id
  }

  /// 스트리밍 델타 추가 — 부분 출력은 메모리에만 쌓고 완료 시 한 번 저장한다.
  public func appendStreaming(_ delta: String, to id: UUID) {
    guard let i = conversation.turns.firstIndex(where: { $0.id == id }) else { return }
    conversation.turns[i].text += delta
  }

  /// 부분 출력이 있는 채로 실패했을 때 — 지금까지의 글자는 남기고 오류 문구를 덧붙인다.
  public func setAssistantText(_ text: String, id: UUID) {
    guard let i = conversation.turns.firstIndex(where: { $0.id == id }) else { return }
    conversation.turns[i].text = text
  }

  /// 도우미 도구 실행 기록을 턴에 붙인다(대화 기록에 함께 남는다).
  public func appendAgentEvent(_ event: AgentEvent, to id: UUID) {
    guard let i = conversation.turns.firstIndex(where: { $0.id == id }) else { return }
    if conversation.turns[i].agentEvents == nil { conversation.turns[i].agentEvents = [] }
    conversation.turns[i].agentEvents?.append(event)
  }

  /// 실행 기록 한 건을 고친다(상태·출력·경과시간).
  public func updateAgentEvent(id eventID: String, in turnID: UUID, _ mutate: (inout AgentEvent) -> Void) {
    guard let i = conversation.turns.firstIndex(where: { $0.id == turnID }),
          var events = conversation.turns[i].agentEvents,
          let j = events.firstIndex(where: { $0.id == eventID }) else { return }
    mutate(&events[j])
    conversation.turns[i].agentEvents = events
  }

  /// 스트리밍 완료 — 응답 시간을 기록하고 대화 수정 시각을 갱신한다.
  public func finishAssistantTurn(_ id: UUID, elapsedMs: Int? = nil, sources: [TurnSource]? = nil) {
    guard let i = conversation.turns.firstIndex(where: { $0.id == id }) else { return }
    if let elapsedMs { conversation.turns[i].elapsedMs = elapsedMs }
    if let sources { conversation.turns[i].sources = sources }
    conversation.updatedAt = Date()
  }
  public func togglePin() { conversation.pinned.toggle() }
  public func clearEphemeral() {
    if !conversation.pinned {
      conversation.turns.removeAll()
      conversation.summary = nil
      conversation.summaryThroughTurnID = nil
      conversation.compactPaused = nil
    }
  }
  public func reset() { conversation = Conversation() }

  /// 사용자가 고른 질문으로 되돌린다 — 그 질문과 **이후 턴을 모두** 지우고 원래 턴을 돌려준다.
  /// 화면은 돌려받은 텍스트·첨부를 입력창에 채워 수정하거나 그대로 다시 보낸다.
  /// - 첫 질문을 되돌리고 제목을 직접 바꾼 적이 없으면 자동 제목도 새 질문에서 다시 만든다.
  /// - 요약 경계가 지워진 턴을 가리키면 더 이상 유효하지 않으므로 요약을 비운다.
  @discardableResult
  public func rewind(toUserTurnID id: UUID) -> Turn? {
    guard let index = conversation.turns.firstIndex(where: { $0.id == id && $0.role == .user })
    else { return nil }
    let original = conversation.turns[index]

    let isFirstUserTurn = !conversation.turns[..<index].contains { $0.role == .user }
    if isFirstUserTurn && !conversation.titleEdited {
      conversation.title = Conversation.defaultTitle
    }

    conversation.turns.removeSubrange(index...)
    conversation.updatedAt = Date()

    if let boundary = conversation.summaryThroughTurnID,
       !conversation.turns.contains(where: { $0.id == boundary }) {
      conversation.summary = nil
      conversation.summaryThroughTurnID = nil
    }
    return original
  }

  /// 자동 정리 결과 — `through`까지의 턴을 요약으로 대체한다(원문 턴은 화면에 그대로 남는다).
  public func applySummary(_ summary: String, through turnID: UUID) {
    conversation.summary = summary
    conversation.summaryThroughTurnID = turnID
    conversation.compactPaused = nil
    conversation.updatedAt = Date()
  }

  /// 사용자가 요약 본문만 직접 고친다 — 경계·자동 정리 일시 중지 상태는 그대로 둔다.
  public func replaceSummary(_ summary: String) {
    guard conversation.summary != nil else { return }
    conversation.summary = summary
    conversation.updatedAt = Date()
  }

  /// 요약 해제 — 이후 자동 정리를 멈춘다(사용자가 명시적으로 해제했으므로 바로 다시 덮지 않는다).
  public func clearSummary(pauseAuto: Bool = true) {
    conversation.summary = nil
    conversation.summaryThroughTurnID = nil
    conversation.compactPaused = pauseAuto ? true : nil
    conversation.updatedAt = Date()
  }

  /// 이 대화에서만 공통 메모리 주입을 끄거나 켠다.
  public func setCommonMemoryDisabled(_ disabled: Bool) {
    conversation.commonMemoryDisabled = disabled ? true : nil
    conversation.updatedAt = Date()
  }

  /// 이 대화에서만 권한 정책을 덮어쓴다(v0.22) — nil/빈 값이면 "설정 따름"으로 되돌린다.
  public func setAgentOverride(_ override: AgentOverride?) {
    let value = (override?.isEmpty ?? true) ? nil : override
    conversation.agentOverride = value
    conversation.updatedAt = Date()
  }

  /// 이 대화의 승인 쓰기 폴더를 통째로 바꾼다(2026-10-29) — 만료된 승인은 저장하지 않는다.
  /// 비면 nil로 되돌려 "승인 없음" 상태를 기록에 남긴다.
  public func setWriteScopeGrants(_ grants: [WriteScopeGrant], at now: Date = Date()) {
    let active = grants.filter { $0.isActive(at: now) }.sorted { $0.path < $1.path }
    conversation.approvedWriteScopes = active.isEmpty ? nil : active
    conversation.updatedAt = Date()
  }

  /// 자동 정리 다시 켜기.
  public func resumeAutoCompact() {
    conversation.compactPaused = nil
    conversation.updatedAt = Date()
  }
  /// 대화를 연다 — 구버전 기록처럼 제목이 "새 대화"로 남아 있어도 첫 질문으로 자동 제목을 채운다.
  public func open(_ c: Conversation) {
    conversation = c
    conversation.applyAutoTitle()
  }
  /// 대화방 제목 변경(사용자 지정 — 이후 자동 제목이 덮지 않는다).
  @discardableResult
  public func rename(to newTitle: String) -> Bool {
    conversation.rename(to: newTitle)
  }
}
