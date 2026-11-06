import SwiftUI
import AVFoundation
import Combine
import UniformTypeIdentifiers

// [INFO] [FEATURE] 대화 입력독 (Xcode 단일 타깃: Core 파일 동시 컴파일)

/// 아직 전송하지 않은 첨부 1건 — 미리보기(썸네일)와 전송을 위해 실제 파일 위치를 함께 들고 있다.
/// 보관함 검색 결과를 열 때 어느 턴으로 갈지 — ContentView가 스크롤·깜빡임에 쓴다.
/// `token` 덕분에 같은 턴을 다시 눌러도 새 요청으로 인식된다.
struct SearchFocusRequest: Equatable {
  let conversationID: UUID
  let turnID: UUID
  let query: String
  let token = UUID()
}

struct PendingAttachment: Identifiable, Equatable {
  let id = UUID()
  var name: String
  var url: URL?
  var kind: Attachment.Kind

  /// 첨부 칩·미리보기에 쓸 이미지(있으면)
  var image: NSImage? {
    guard kind == .image, let url else { return nil }
    return NSImage(contentsOf: url)
  }

  /// 파일 크기 문구(있으면)
  var sizeText: String? {
    guard let url,
          let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
    else { return nil }
    return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
  }
}

final class UIStore: ObservableObject {
  // MARK: - 대화방별 세션 (v0.31 6a)
  /// 지금 화면에 보이는 대화방. 실행·입력 상태는 모두 그 방의 `ChatSession` 에 있다.
  /// (예약 실행과 같은 방식으로 대화별 상태를 분리해, 다음 단계에서 동시 응답을 켠다)
  @Published private var activeSessionID = UUID()
  private var sessions: [UUID: ChatSession] = [:]
  private var sessionObservers: [UUID: AnyCancellable] = [:]

  /// 활성 대화방 — 없으면 만든다(앱 시작·QA 렌더에서도 안전).
  var activeSession: ChatSession {
    if let s = sessions[activeSessionID] { return s }
    let s = ChatSession(conversation: Conversation())
    sessions[s.id] = s
    observe(s)
    activeSessionID = s.id
    return s
  }

  /// 화면이 보는 대화 — 활성 세션의 대화.
  var conversation: Conversation {
    get { activeSession.conversation }
    set { activeSession.conversation = newValue }
  }
  /// 활성 세션의 대화 저장소. 예약 실행은 별도 저장소를 그대로 쓴다.
  var core: ConversationStore { activeSession.core }

  /// 그 대화방이 지금 응답 중인가 — 목록에서 **다른 방의 응답 중 점**을 그릴 때 쓴다.
  func isSessionReplying(conversationID: UUID) -> Bool {
    sessions[conversationID]?.isReplying ?? false
  }

  var draft: String {
    get { activeSession.draft }
    set { activeSession.draft = newValue }
  }
  var attached: [PendingAttachment] {
    get { activeSession.attached }
    set { activeSession.attached = newValue }
  }
  /// 입력독 🌐 — **이번 질문만** 검색을 강제한다(전송 후 자동 해제)
  var forceWebSearch: Bool {
    get { activeSession.forceWebSearch }
    set { activeSession.forceWebSearch = newValue }
  }
  /// 응답 대기 상태 — 입력독에 "응답 중" 표시를 띄우고 중복 전송을 막는다
  var isReplying: Bool {
    get { activeSession.isReplying }
    set { activeSession.isReplying = newValue }
  }
  // MARK: - 웹 검색 (PLAN_v0.14)
  /// 검색 결과를 기다리는 중 — 응답 말풍선 대신 "웹에서 찾는 중…"을 보여 준다
  var isSearching: Bool {
    get { activeSession.isSearching }
    set { activeSession.isSearching = newValue }
  }
  // MARK: - 도우미 도구 (PLAN_v0.18)
  /// 실행 카드 — 지금 답변에 붙는 도구 실행 기록
  var agentEvents: [AgentEvent] {
    get { activeSession.agentEvents }
    set { activeSession.agentEvents = newValue }
  }
  /// 에이전트가 `web_search` 로 확인한 출처 — 답변 아래 출처 카드에 쓴다(v0.23).
  var agentSearchSources: [TurnSource] {
    get { activeSession.agentSearchSources }
    set { activeSession.agentSearchSources = newValue }
  }
  /// 승인을 기다리는 요청 — 카드에 [허용] 버튼이 뜬다
  var agentApproval: AgentApprovalRequest? {
    get { activeSession.agentApproval }
    set { activeSession.agentApproval = newValue }
  }
  /// 실행 카드가 붙은 턴 — 그 턴 아래에 카드를 그린다
  var agentTurnID: UUID? {
    get { activeSession.agentTurnID }
    set { activeSession.agentTurnID = newValue }
  }

  @Published var settings = QuickTalkSettings() {
    didSet { saveSettings() }
  }
  @Published var voiceRecording = false
  /// 설정 › AI의 [검색 테스트] 결과(건수·지연 또는 오류 코드)
  @Published var webSearchTestResult = ""
  @Published var webSearchTesting = false
  /// 설정 › AI의 [답변 API 테스트] 결과
  @Published var answerTestResult = ""
  @Published var answerTesting = false
  /// 승인된 쓰기 폴더 — **대화별**로 유지되고 7일 뒤 만료된다("이 폴더 허용", v0.19 → 2026-10-29).
  /// 대화 기록과 함께 저장하므로 앱을 다시 켜도 남는다.
  var activeWriteScopeGrants: [WriteScopeGrant] {
    (conversation.approvedWriteScopes ?? [])
      .filter { $0.isActive() }
      .sorted { $0.expiresAt < $1.expiresAt }
  }
  /// 이번 대화에서 지금 유효한 승인 쓰기 폴더.
  /// ★ 예약 실행 중에는 그 실행의 범위를 쓴다(현재 대화를 건드리지 않는다).
  var approvedWriteScopes: [String] { approvedWriteScopes(for: activeSession) }

  func approvedWriteScopes(for session: ChatSession) -> [String] {
    if let scheduledRun { return scheduledRun.writeScopes }
    return (session.conversation.approvedWriteScopes ?? [])
      .filter { $0.isActive() }
      .sorted { $0.expiresAt < $1.expiresAt }
      .map(\.path)
  }
  /// 승인된 화면 조작 앱 — 대화별 7일(PLAN_v0.25 Phase 2).
  var activeUiAppGrants: [UiAppGrant] {
    (conversation.approvedUiApps ?? [])
      .filter { $0.isActive() }
      .sorted { $0.expiresAt < $1.expiresAt }
  }
  /// 지금 유효한 화면 조작 승인 — 예약 실행이면 그 실행의 승인.
  var activeUiGrants: [UiAppGrant] {
    scheduledRun?.uiGrants.filter { $0.isActive() } ?? activeUiAppGrants
  }
  /// 실제 적용 정책 — 전역 설정 위에 **이 대화의 오버라이드**를 얹는다(v0.22).
  /// 치명적 차단·상승 권한 제한은 전역 값 그대로다.
  /// 예약 실행은 대화 오버라이드를 쓰지 않는다(사용자가 그 자리에 없으므로 전역 정책만).
  var effectiveAgentPolicy: AgentPolicy { effectiveAgentPolicy(for: activeSession) }

  /// 그 대화방의 실제 정책 — 백그라운드 응답이 다른 방의 오버라이드를 쓰지 않게 한다.
  func effectiveAgentPolicy(for session: ChatSession) -> AgentPolicy {
    if let scheduledRun { return scheduledRun.policy }
    return (session.conversation.agentOverride ?? AgentOverride()).merged(into: settings.agentPolicy)
  }
  /// 실행 카드(eventID)별 되돌리기 스냅샷 — 이번 실행에서 만든 것만 카드에 보인다
  var agentUndoEntries: [String: UndoEntry] {
    get { activeSession.agentUndoEntries }
    set { activeSession.agentUndoEntries = newValue }
  }
  /// 되돌리기 결과 안내(카드 아래 한 줄)
  var agentUndoMessages: [String: String] {
    get { activeSession.agentUndoMessages }
    set { activeSession.agentUndoMessages = newValue }
  }
  /// 진행 중인 셸 실행의 중지 손잡이(v0.20) — 카드 [중단] 버튼이 쓴다.
  /// 예약 실행 중이면 그 실행의 손잡이로 갈라진다.
  var agentRunHandle: SandboxCancellation? {
    get { scheduledRun?.runHandle ?? activeSession.currentRunHandle }
    set {
      if let scheduledRun { scheduledRun.runHandle = newValue }
      else { activeSession.currentRunHandle = newValue }
    }
  }
  /// 터미널 인계 결과 안내(실패 사유 등) — 카드 아래 한 줄.
  var agentHandoffNotice: String? {
    get { activeSession.agentHandoffNotice }
    set { activeSession.agentHandoffNotice = newValue }
  }
  /// 도구 실행기 — 정책 판단·사용자 확인·감사 기록
  var agentExecutor: AgentExecutor? {
    get { activeSession.agentExecutor }
    set { activeSession.agentExecutor = newValue }
  }
  /// 도구 필요 판정 캐시 — 같은 질문이면 10분간 모델을 다시 부르지 않는다.
  var agentDecisionCache: [String: (needed: Bool, at: Date)] = [:]
  let agentDecisionTTL: TimeInterval = 600
  /// QA 헤드리스 모드 — 승인이 필요한 명령을 자동으로 거부한다(대면 창이 없으므로).
  var agentSelfTestMode: Bool {
    get { scheduledRun?.selfTestMode ?? uiAgentSelfTestMode }
    set {
      if let scheduledRun { scheduledRun.selfTestMode = newValue } else { uiAgentSelfTestMode = newValue }
    }
  }
  private var uiAgentSelfTestMode = false

  // MARK: - 예약 실행 (v0.26)

  /// 예약 작업 스케줄러 — `AppDelegate` 가 만들고 넣어 준다(설정·`/할일` 시트·알림이 함께 쓴다).
  var schedulerService: SchedulerService?
  /// 일정 목록이 바뀔 때마다 오르는 값 — `SchedulerService` 는 ObservableObject 가 아니라
  /// `@Published` 로 목록을 알릴 수 없다. 저장·삭제·중지 때 이 값을 올려 `/할일` 시트가
  /// **30초 폴링을 기다리지 않고 즉시** 다시 그리게 한다(2026-11-03).
  @Published var scheduleRevision = 0
  /// 지금 돌고 있는 예약 실행 — 도구 카드·승인·쓰기 범위를 **현재 대화와 분리**한다.
  var scheduledRun: ScheduledRunContext?
  /// 예약 실행의 승인 대기 — 그 대화를 열었을 때만 카드에 버튼이 뜬다.
  @Published var scheduledApproval: ScheduledApproval?
  /// 승인 대기 만료 타이머(10분).
  private var scheduledApprovalTimer: Timer?
  /// 승인 대기·실행 종료를 알림 계층에 넘기는 훅(5단계 NotificationService 가 연결).
  var onScheduledApproval: ((ScheduledApproval) -> Void)?
  var onScheduledRunFinished: ((ScheduledRunNotice) -> Void)?

  /// 알림 서비스·권한 상태 (5단계) — AppDelegate 가 만든다.
  var notifications: NotificationService?
  @Published var notificationPermission: NotificationPermission = .unknown

  /// 예약 실행의 승인을 기다린다 — 10분이 지나면 거부로 끝난다.
  /// 알림에서는 승인할 수 없다(오탭 방지) — 사용자가 대화를 열어 카드에서 눌러야 한다.
  @MainActor
  func requestScheduledApproval(_ request: AgentApprovalRequest) async -> AgentApprovalChoice {
    guard let ctx = scheduledRun else { return .deny }
    // QA 헤드리스 — 무한 대기 방지.
    if ctx.selfTestMode { return .deny }
    return await withCheckedContinuation { cont in
      ctx.approval = request
      ctx.approvalContinuation = cont
      ctx.approvalTimedOut = false
      scheduledApproval = ScheduledApproval(taskID: ctx.taskID,
                                            conversationID: ctx.conversation.id,
                                            turnID: ctx.turnID,
                                            personaName: settings.persona(scheduledRunPersonaID)?.name,
                                            request: request)
      onScheduledApproval?(scheduledApproval!)
      scheduledApprovalTimer?.invalidate()
      let box = WeakMainActorBox(self)
      scheduledApprovalTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: false) { _ in
        Task { @MainActor in
          guard let self = box.value,
                let ctx = self.scheduledRun, ctx.approvalContinuation != nil else { return }
          ctx.approvalTimedOut = true
          self.resolveScheduledApproval(.deny)
        }
      }
    }
  }

  /// 사용자가 카드에서 승인/거부를 눌렀다.
  @MainActor
  func resolveScheduledApproval(_ choice: AgentApprovalChoice) {
    scheduledApprovalTimer?.invalidate()
    scheduledApprovalTimer = nil
    scheduledApproval = nil
    guard let ctx = scheduledRun, let cont = ctx.approvalContinuation else { return }
    ctx.approvalContinuation = nil
    ctx.approval = nil
    cont.resume(returning: choice)
  }

  /// 승인 대기 중인 예약 실행의 비서 ID — 러너가 실행 전에 넣어 둔다(알림 문구용).
  var scheduledRunPersonaID: UUID?

  /// 이 앱(화면 조작)이 지금 유효하게 승인됐는가 — 예약 실행이면 그 대화의 승인.
  func hasUiAppGrant(bundleID: String) -> Bool {
    hasUiAppGrant(bundleID: bundleID, session: activeSession)
  }

  func hasUiAppGrant(bundleID: String, session: ChatSession) -> Bool {
    if let scheduledRun {
      return scheduledRun.uiGrants.contains { $0.bundleID == bundleID && $0.isActive() }
    }
    return session.conversation.hasActiveUiAppGrant(bundleID: bundleID)
  }

  /// 이 실행 카드가 이미 있는가 — 예약 실행이면 그 컨텍스트를 본다.
  func hasAgentEvent(id: String) -> Bool { hasAgentEvent(id: id, session: activeSession) }

  func hasAgentEvent(id: String, session: ChatSession) -> Bool {
    if let scheduledRun { return scheduledRun.events.contains { $0.id == id } }
    return session.agentEvents.contains { $0.id == id }
  }

  // MARK: - 일정 제안 확인 카드 (v0.26 4단계)

  /// `/할일` 시트 표시 — 슬래시 명령과 헤더가 함께 쓴다.
  @Published var showTaskList = false
  /// 모델이 제안한 예약 작업 — 사용자가 [등록]을 눌러야 실제로 저장된다.
  var pendingSchedule: ScheduleConfirmation? {
    get { activeSession.pendingSchedule }
    set { activeSession.pendingSchedule = newValue }
  }
  private var scheduleContinuation: CheckedContinuation<Bool, Never>?
  private var scheduleTimer: Timer?

  /// 확인 카드를 띄우고 사용자의 결정을 기다린다(10분 뒤 자동 취소).
  /// 예약 실행 중에는 절대 등록하지 않는다(사람이 없는 자리에서 일정이 늘어나면 위험).
  @MainActor
  func requestScheduleConfirmation(_ proposal: ScheduleProposal) async -> Bool {
    guard scheduledRun == nil, !agentSelfTestMode else { return false }
    let duplicate = schedulerService?.tasks.contains {
      $0.title == proposal.title && $0.rule == proposal.rule
    } ?? false
    return await requestScheduleAction(.create(proposal), isDuplicate: duplicate)
  }

  /// `schedule_update` 확인 카드 — 변경 전 → 변경 후를 보여 준다.
  @MainActor
  func requestScheduleChangeConfirmation(_ change: ScheduleChangeProposal) async -> Bool {
    guard scheduledRun == nil, !agentSelfTestMode else { return false }
    return await requestScheduleAction(.update(change))
  }

  /// `schedule_delete` 확인 카드 — "취소"는 삭제다.
  @MainActor
  func requestScheduleDeletionConfirmation(_ deletion: ScheduleDeletionProposal) async -> Bool {
    guard scheduledRun == nil, !agentSelfTestMode else { return false }
    return await requestScheduleAction(.delete(deletion))
  }

  @MainActor
  private func requestScheduleAction(_ action: SchedulePendingAction,
                                     isDuplicate: Bool = false) async -> Bool {
    await withCheckedContinuation { cont in
      scheduleContinuation = cont
      pendingSchedule = ScheduleConfirmation(conversationID: conversation.id,
                                             turnID: agentTurnID,
                                             action: action,
                                             isDuplicate: isDuplicate)
      scheduleTimer?.invalidate()
      let box = WeakMainActorBox(self)
      scheduleTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: false) { _ in
        Task { @MainActor in box.value?.resolveScheduleProposal(accept: false) }
      }
    }
  }

  /// 카드의 [등록]/[변경]/[삭제]/[취소]. 승인하면 `SchedulerService` 가 저장한다.
  @MainActor
  func resolveScheduleProposal(accept: Bool) {
    scheduleTimer?.invalidate()
    scheduleTimer = nil
    let pending = pendingSchedule
    pendingSchedule = nil
    var applied = false
    if accept, let pending {
      switch pending.action {
      case .create(let proposal):
        applied = register(proposal)
      case .update(let change):
        applied = applyScheduleChange(change)
      case .delete(let deletion):
        applied = deleteSchedule(deletion)
      }
    }
    guard let cont = scheduleContinuation else { return }
    scheduleContinuation = nil
    cont.resume(returning: applied)
  }

  /// 같은 제목·규칙이 있으면 **덮어쓴다**(중복 일정 방지). 없으면 새로 만든다.
  @MainActor
  private func register(_ p: ScheduleProposal) -> Bool {
    guard let service = schedulerService else { return false }
    if let existing = service.tasks.first(where: { $0.title == p.title && $0.rule == p.rule }) {
      var task = existing
      task.instruction = p.instruction
      task.personaID = p.personaID
      task.skip = p.skip
      task.enabled = true
      task.nextFireAt = nil
      service.upsert(task)
      NSLog("[QuickTalk] 예약 작업 수정 — %@", task.title)
    } else {
      let task = service.upsert(ScheduledTask(personaID: p.personaID, title: p.title,
                                              instruction: p.instruction, rule: p.rule,
                                              skip: p.skip))
      NSLog("[QuickTalk] 예약 작업 등록 — %@ (%@)", task.title, task.rule.humanDescription())
    }
    return true
  }

  /// 변경 승인 — 실행 중인 일정은 건드리지 않는다(사람이 없는 자리에서 규칙이 바뀌면 위험).
  @MainActor
  private func applyScheduleChange(_ change: ScheduleChangeProposal) -> Bool {
    guard let service = schedulerService,
          service.task(change.taskID) != nil,
          !service.isRunning(change.taskID) else { return false }
    var task = change.after
    task.nextFireAt = nil
    service.upsert(task)
    NSLog("[QuickTalk] 예약 작업 변경 — %@ (%@)", task.title, task.rule.humanDescription())
    return true
  }

  /// 삭제 승인 — 리포트 파일은 그대로 둔다(PLAN §8.2).
  @MainActor
  private func deleteSchedule(_ deletion: ScheduleDeletionProposal) -> Bool {
    guard let service = schedulerService,
          service.task(deletion.taskID) != nil,
          !service.isRunning(deletion.taskID) else { return false }
    service.delete(deletion.taskID)
    NSLog("[QuickTalk] 예약 작업 삭제 — %@", deletion.title)
    return true
  }
  /// 공통 메모리 — 모든 대화에 적용되는 사용자 작성 사실(PLAN_v0.16).
  @Published var memoryEntries: [GlobalMemoryEntry] = [] {
    didSet { saveMemory() }
  }
  /// 메모리 저장·가져오기 안내(실패 포함).
  @Published var memoryNotice: String?
  private var suppressMemorySave = false
  private let searchCache = SearchCache()
  private let answerCache = ExaAnswerCache()
  /// 검색 필요 판정 캐시 — 같은 질문·직전 맥락이면 10분간 모델을 다시 부르지 않는다.
  private var searchDecisionCache: [String: (needed: Bool, at: Date)] = [:]
  private let searchDecisionTTL: TimeInterval = 600
  // MARK: - 대화 기억 정리 (T-71)
  /// 요약을 만들고 있는 중 — 입력독 위 배너에 표시한다(응답 대기와 별개).
  @Published var isCompacting = false
  /// 정리 중인 대화방 — 다른 방으로 전환했을 때 배너가 섞이지 않게 한다.
  @Published var compactingConversationID: UUID?
  /// 정리 실패·안내 문구(자동 정리 중에는 조용히, 수동은 사유 표시).
  @Published var compactMessage: String?
  /// 지금 토큰을 받고 있는 어시스턴트 턴 — 첫 글자가 오면 점 표시를 숨기고 자동 스크롤한다
  var streamingTurnID: UUID? {
    get { activeSession.streamingTurnID }
    set { activeSession.streamingTurnID = newValue }
  }
  /// 지금 도착 중인 **사고 과정**(thinking 모델) — 답변이 시작되기 전에도 "지금 고민 중"을 보여 준다.
  /// 완료되면 턴(`Turn.reasoning`)에 저장하고 비운다.
  var liveReasoning: String {
    get { activeSession.liveReasoning }
    set { activeSession.liveReasoning = newValue }
  }
  /// 연결이 끊겨 다시 연결을 기다리는 중이면 상태 문구 — 입력독 위 배너에 표시한다(v0.29).
  /// nil 이면 대기 중이 아니다. [중지]는 기존 응답 중지 버튼이 그대로 담당한다.
  var networkRetryStatus: String? {
    get { activeSession.networkRetryStatus }
    set { activeSession.networkRetryStatus = newValue }
  }
  /// QA 렌더에서 설정을 바꿀 때 저장을 막는다
  private var suppressSettingsSave = false
  /// QA 오프스크린 렌더 중인가 — 실제 기록(history.json)을 화면에 끌어오지 않게 한다.
  private(set) var isRenderHarness = false
  var replyStartedAt: Date? {
    get { activeSession.replyStartedAt }
    set { activeSession.replyStartedAt = newValue }
  }
  /// 진행 중인 응답 Task — 로컬 모델은 첫 토큰까지 수 분 걸릴 수 있어 **사용자가 중지**할 수 있다.
  var replyTask: Task<Void, Never>? {
    get { activeSession.replyTask }
    set { activeSession.replyTask = newValue }
  }
  /// 질문 수정/다시 응답으로 입력창을 채웠을 때 포커스를 되돌리기 위한 토큰
  @Published var composerFocusToken: UUID?

  /// 응답 대기 경과(초)
  var replySeconds: Int { Int(Date().timeIntervalSince(replyStartedAt ?? Date())) }

  /// 응답 중 표시에 쓸 프로바이더·모델 라벨
  var replySourceLabel: String {
    guard let p = settings.activeProvider else { return L("AI 미설정") }
    let model = p.model.isEmpty ? p.type.displayName : p.model
    return "\(p.displayName) · \(model)"
  }
  let speech = AppleSpeechService()
  /// Edge TTS(온라인) — `edge-tts` CLI로 합성한 mp3를 재생한다
  let edgeSpeech = EdgeSpeechService()
  /// Piper TTS(로컬) — `piper` CLI로 합성한 wav를 재생한다
  let piperSpeech = PiperSpeechService()
  /// 최근 클립보드 스트립 (PLAN_v0.12) — 만료 2분 · 최대 5개
  let clipboard = ClipboardService()
  // MARK: - QuickShelf 상태 (PLAN_v0.13)
  @Published var shelfTab: ShelfTab = .chats
  @Published var shelfFiles: [ShelfFile] = []
  @Published var shelfCaptures: [ShelfCapture] = []
  /// 호버 미리보기 대상(패널 왼쪽 별도 창)
  @Published var shelfPreview: ShelfPreviewTarget?
  /// 권한·실패 안내 문구(패널 상단에 표시)
  @Published var shelfNotice: String?
  /// 읽어주기(TTS) 재생 중 — 헤더·메시지 버튼이 **중지**로 바뀐다
  @Published var isSpeaking = false
  /// 음성 설정 묶음 — 바뀐 항목이 있을 때만 서비스에 다시 넘긴다(튜플 8개는 Equatable이 없다)
  private struct SpeechSettingsKey: Equatable {
    let locale: String
    let voice: String
    let ttsLanguage: String
    let rate: Double
    let edgeVoice: String
    let edgeBinary: String
    let piperModel: String
    let piperBinary: String
  }

  /// 지금 읽고 있는 응답(턴) — 그 말풍선만 중지 버튼이 된다
  @Published var speakingTurnID: UUID?
  /// 전역 단축키 등록 결과(동작별) — 설정 창의 ⚠️ 표시
  @Published var shortcutStatus: [ShortcutAction: Bool] = [:]
  /// 안내를 눌렀을 때 할 일(권한 요청 등) — 없으면 그냥 안내
  @Published var shelfNoticeAction: ShelfNoticeAction?
  /// 안내 배너의 동작 — 배너 본문을 누르면 실행한다
  enum ShelfNoticeAction: Equatable {
    case screenRecording
  }

  /// 안내를 띄우고(선택) 눌렀을 때 할 일을 함께 지정한다.
  /// `nil`로 지우면 동작도 같이 지운다(이전 안내의 동작이 남지 않게).
  func showShelfNotice(_ text: String?, action: ShelfNoticeAction? = nil) {
    shelfNotice = text
    shelfNoticeAction = text == nil ? nil : action
  }

  /// 첨부 안내(지원하지 않는 형식 등) — 입력독 위 배너로 표시한다(무음 실패 금지)
  @Published var attachNotice: String?
  /// 보관함 검색 결과에서 이동·강조할 턴(ContentView가 소비한 뒤 nil로 지운다)
  @Published var searchFocus: SearchFocusRequest?
  private var attachNoticeToken = UUID()
  /// 대화창 안에 도킹된 상태(창 오른쪽에 3탭 허브가 붙는다) — 창이 열려 있을 때의 기본 위치
  @Published var shelfDocked = false
  private var whisperRecorder: AVAudioRecorder?
  private var bag = Set<AnyCancellable>()
  private let settingsKey = "QuickTalk.settings"

  /// 세션(대화방)의 변경을 UIStore 변경으로 전달한다 — 뷰는 UIStore만 관찰한다.
  private func observe(_ session: ChatSession) {
    sessionObservers[session.id] = session.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
  }

  init() {
    let first = ChatSession(conversation: Conversation())
    sessions[first.id] = first
    activeSessionID = first.id
    observe(first)
    if let data = UserDefaults.standard.data(forKey: settingsKey),
       let loaded = try? JSONDecoder().decode(QuickTalkSettings.self, from: data) {
      // 구버전 기본값(Ctrl+Space) 마이그레이션: 미변경 유저는 Cmd+Space로 승격
      var s = loaded
      var changed = false
      if s.globalShortcut == "Ctrl+Space" { s.globalShortcut = "Cmd+Space"; changed = true }
      // QuickShelf 기본 단축키 ⌥⌘V가 다른 앱의 '경로 복사'와 겹쳐 ⇧⌥V로 옮긴다.
      // 저장값이 옛 기본값이면 매번 승격한다(실행 중이던 앱이 옛 값을 다시 저장해도 다음 실행에서 바로잡힘).
      if s.shelfShortcut == "Option+Cmd+V" {
        s.shelfShortcut = "Option+Shift+V"
        changed = true
      }
      // 활성 프로바이더가 원격인데 키체인에 키가 없으면 Apple FM으로 폴백 (키 없는 실패 방지)
      if let active = s.activeProvider {
        let needsKey = active.type == .openAICompatible
        let keyMissing = active.secretID.isEmpty || !SecretStore.has(account: active.secretID)
        if needsKey && keyMissing, let fallback = Self.keylessFallbackID(in: s), fallback != active.id {
          s.activeProviderID = fallback
          changed = true
        }
      } else {
        s.activeProviderID = LLMProviderConfig.appleFMID
        changed = true
      }
      // 표시 정책: 메뉴바·Dock 둘 다 숨김 상태는 진입점이 없으므로 Dock을 켠다
      if s.normalizeVisibility() { changed = true }
      settings = s
      if changed { saveSettings() }
    }
    speech.$isRecording.assign(to: &$voiceRecording)
    // 동기 구독 — 중지 직후 새로 읽기 시작할 때 "false" 이벤트가 뒤늦게 도착해
    // 새로 지정한 speakingTurnID를 지워 버리지 않게 한다.
    // 세 엔진(Apple·Edge·Piper) 중 하나라도 재생 중이면 '읽는 중'이다
    speech.$isSpeaking
      .combineLatest(edgeSpeech.$isSpeaking, piperSpeech.$isSpeaking)
      .map { $0 || $1 || $2 }
      .removeDuplicates()
      .sink { [weak self] speaking in
        guard let self else { return }
        self.isSpeaking = speaking
        guard !speaking else { return }
        // 중지 직후 다른 엔진으로 새로 읽기 시작할 수 있다 — 잠깐 뒤에도 조용할 때만 턴 표시를 지운다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
          guard let self, !self.isSpeaking else { return }
          self.speakingTurnID = nil
        }
      }
      .store(in: &bag)
    speech.onPartial = { [weak self] t in self?.draft = t }
    speech.onFinal = { [weak self] t in self?.draft = t }
    // 음성 설정(받아쓰기 언어·읽어주기 목소리/속도)을 서비스에 반영하고, 바뀔 때마다 다시 넘긴다
    applySpeechSettings()
    $settings
      .dropFirst()
      .map { s in
        SpeechSettingsKey(locale: s.appleSpeechLocale,
                          voice: s.ttsVoiceID,
                          ttsLanguage: s.ttsLanguage,
                          rate: s.ttsRate,
                          edgeVoice: s.edgeVoice,
                          edgeBinary: s.edgeBinaryPath,
                          piperModel: s.piperModelPath,
                          piperBinary: s.piperBinaryPath)
      }
      .removeDuplicates()
      .sink { [weak self] v in
        self?.speech.configure(locale: v.locale, voice: v.voice, ttsLanguage: v.ttsLanguage, rate: v.rate)
        self?.edgeSpeech.configure(voice: v.edgeVoice, rate: v.rate, binary: v.edgeBinary)
        self?.piperSpeech.configure(rate: v.rate, model: v.piperModel, binary: v.piperBinary)
      }
      .store(in: &bag)
    // 중첩 ObservableObject(ClipboardService)의 변경을 UIStore 변경으로 전달한다.
    // (뷰가 UIStore만 관찰하면 항목 소멸이 스트립 표시 조건에 반영되지 않는다)
    clipboard.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    // Edge·Piper TTS의 '최근 오류' 표시도 설정 창에서 바로 갱신되게
    edgeSpeech.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    piperSpeech.objectWillChange
      .sink { [weak self] _ in self?.objectWillChange.send() }
      .store(in: &bag)
    clipboard.start()
    memoryEntries = GlobalMemoryFile.load()
    loadArchive()
    restoreLastConversation()
  }

  // MARK: - 클립보드 스트립 → 입력/첨부 (PLAN_v0.12)

  /// 텍스트/링크: 입력창에 이어 붙인다(커서 위치 개념은 입력창 끝으로 단순화)
  func insertClipboardText(_ item: ClipboardItem) {
    let text = clipboard.displayText(item)
    guard !text.isEmpty else { return }
    if draft.isEmpty { draft = text }
    else if draft.hasSuffix(" ") || draft.hasSuffix("\n") { draft += text }
    else { draft += " " + text }
    NSLog("[QuickTalk] 클립보드 텍스트 입력창 삽입 kind=%@ 길이=%d", item.kind.rawValue, text.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// ⌘V — 클립보드의 **이미지·파일**을 대화 첨부로 붙인다(v0.28).
  /// 텍스트는 AppKit 기본 붙여넣기에 맡기려고 `false` 를 돌려준다.
  /// (QuickShelf를 열고 카드를 고르지 않아도 바로 첨부된다)
  func pasteAttachmentFromPasteboard() -> Bool {
    let pb = NSPasteboard.general

    // 1) 파일 — Finder에서 복사한 파일들. 지원 형식만 받고, 거부는 조용히 버리지 않는다.
    if let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
      var added = 0
      var rejected: [String] = []
      for url in urls {
        let name = url.lastPathComponent
        guard Attachment.isSupported(filename: name) else {
          rejected.append(name)
          continue
        }
        guard !attached.contains(where: { $0.name == name }) else { continue }
        let kind: Attachment.Kind = Self.isImageName(name) ? .image : .file
        attached.append(PendingAttachment(name: name, url: url, kind: kind))
        added += 1
      }
      if !rejected.isEmpty { setAttachNotice(Self.unsupportedMessage(rejected)) }
      if added > 0 {
        NSLog("[QuickTalk] ⌘V 파일 첨부 %d건 (총 %d)", added, attached.count)
        closeShelfAfterPick()
        NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
      }
      return true
    }

    // 2) 이미지 — 스크린샷 붙여넣기. **원본 해상도**로 저장한다(스트립 썸네일이 아니라).
    if let image = NSImage(pasteboard: pb),
       let data = Self.pngData(image),
       let url = Self.writeTempImage(data) {
      attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: .image))
      NSLog("[QuickTalk] ⌘V 이미지 첨부 (총 %d)", attached.count)
      closeShelfAfterPick()
      NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
      return true
    }

    return false
  }

  private static func pngData(_ image: NSImage) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
  }

  /// 창 안 허브에서 항목을 고른 뒤에는 허브를 접는다 — 오버레이가 입력독·전송 버튼을 가리지 않게
  /// (목업 v0.6의 드로어 동작. 여러 개를 붙이려면 ⌥⌘V로 다시 열면 된다 — 카드·탭 상태는 그대로 남는다)
  private func closeShelfAfterPick() {
    guard shelfDocked else { return }
    withAnimation(.easeInOut(duration: 0.18)) { shelfDocked = false }
  }

  /// 스트립 항목 누름 — 민감 항목은 **먼저 공개**하고, 다시 누르면 삽입/첨부 후 스트립에서 사라진다.
  func tapClipboard(_ item: ClipboardItem) {
    if item.isSensitive && !clipboard.isRevealed(item.id) {
      clipboard.reveal(item.id)
      NSLog("[QuickTalk] 클립보드 민감 항목 공개 (kind=%@)", item.kind.rawValue)
      return
    }
    attachClipboard(item)
    // 사용한 항목은 스트립에서 제거한다(같은 것을 계속 붙는 문제 방지)
    clipboard.remove(item.id)
  }

  /// 이미지: 입력창에 넣을 수 없으므로 임시 파일로 저장 후 첨부로 추가
  func attachClipboard(_ item: ClipboardItem) {
    switch item.kind {
    case .image:
      guard let data = item.imageData, let url = Self.writeTempImage(data) else {
        NSLog("[ERROR] E-MAC-RENDER-0001 클립보드 이미지 저장 실패")
        return
      }
      attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: .image))
      NSLog("[QuickTalk] 클립보드 이미지 첨부 추가 (개수=%d)", attached.count)
      closeShelfAfterPick()
      NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
    case .file:
      let name = item.text
      guard Attachment.isSupported(filename: name) else {
        setAttachNotice(Self.unsupportedMessage([name]))
        return
      }
      if !attached.contains(where: { $0.name == name }) {
        // 클립보드가 준 파일 경로를 그대로 넘긴다 — 없으면 전송 시 이름만 알린다(P1)
        attached.append(PendingAttachment(name: name, url: item.fileURL, kind: .file))
        if item.fileURL == nil {
          setAttachNotice(Lf("「%@」의 파일 위치를 얻지 못해 이름만 전달됩니다", name))
        } else if let url = item.fileURL, !FileManager.default.fileExists(atPath: url.path) {
          setAttachNotice(Lf("「%@」 파일이 이미 사라졌습니다 — 본문 없이 이름만 전달됩니다", name))
        }
      }
      NSLog("[QuickTalk] 클립보드 파일 첨부 추가 (개수=%d)", attached.count)
      closeShelfAfterPick()
    case .text, .link:
      insertClipboardText(item)
    }
  }

  static func isImageName(_ name: String) -> Bool { Attachment.isImageName(name) }

  // MARK: - 첨부 안내(무음 실패 금지)

  /// 지원하지 않는 형식 등을 입력독 위 배너로 알린다([HARD] 무음 실패 금지). 9초 뒤 스스로 사라진다.
  func setAttachNotice(_ text: String) {
    attachNotice = text
    let token = UUID()
    attachNoticeToken = token
    DispatchQueue.main.asyncAfter(deadline: .now() + 9) { [weak self] in
      guard let self, self.attachNoticeToken == token else { return }
      self.attachNotice = nil
    }
  }

  /// 걸러낸 파일 안내 문구 — 이름은 앞 3개만 보여준다(로그에는 개수만)
  static func unsupportedMessage(_ names: [String]) -> String {
    guard !names.isEmpty else { return "" }
    let list = names.prefix(3).joined(separator: ", ")
    let extra = names.count > 3 ? Lf(" 외 %d건", names.count - 3) : ""
    NSLog("[WARN] E-MAC-MODEL-0001 지원하지 않는 첨부 %d건 제외", names.count)
    return Lf("첨부할 수 없는 형식입니다: %@%@ — 텍스트·코드 파일·PDF·이미지만 첨부됩니다", list, extra)
  }

  // MARK: - QuickShelf: 파일 · 캡처 (PLAN_v0.13)

  /// QuickShelf 파일·캡처 보관 폴더
  static var shelfDir: URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    else { return nil }
    let dir = base.appendingPathComponent("QuickTalk/shelf", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  /// 파일 선택 결과를 파일 탭에 추가한다(중복 경로는 무시).
  @discardableResult
  func addShelfFiles(_ urls: [URL]) -> Int {
    var added = 0
    var rejected: [String] = []
    for url in urls {
      guard Attachment.isSupported(filename: url.lastPathComponent) else {
        rejected.append(url.lastPathComponent)     // 조용히 버리지 않는다(P3)
        continue
      }
      if shelfFiles.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) { continue }
      let kind: Attachment.Kind = Self.isImageName(url.lastPathComponent) ? .image : .file
      shelfFiles.insert(ShelfFile(name: url.lastPathComponent, url: url, kind: kind), at: 0)
      added += 1
    }
    if !rejected.isEmpty { showShelfNotice(Self.unsupportedMessage(rejected)) }
    if added > 0 {
      NSLog("[QuickShelf] 파일 %d건 추가 (총 %d)", added, shelfFiles.count)
      shelfTab = .files
    }
    return added
  }

  func removeShelfFile(_ id: UUID) {
    shelfFiles.removeAll { $0.id == id }
  }

  /// 파일 카드 클릭 → 대화 첨부. 사용한 카드는 목록에서 사라진다(원본 파일은 그대로).
  func attachShelfFile(_ file: ShelfFile) {
    if attached.contains(where: { $0.name == file.name }) {
      showShelfNotice(Lf("이미 첨부된 파일입니다: %@", file.name))
      return
    }
    attached.append(PendingAttachment(name: file.name, url: file.url, kind: file.kind))
    removeShelfFile(file.id)
    NSLog("[QuickShelf] 파일 첨부 (이름=%@, 첨부=%d)", file.name, attached.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// 캡처 결과를 저장하고 캡처 탭 맨 위에 넣는다.
  @discardableResult
  func addCapture(png: Data, pixelWidth: Int, pixelHeight: Int, source: ShelfCapture.Source) -> ShelfCapture? {
    guard let dir = Self.shelfDir else { return nil }
    let df = DateFormatter()
    df.dateFormat = "yyyyMMdd-HHmmss"
    let base = "캡처-\(source.label.replacingOccurrences(of: " ", with: ""))-\(df.string(from: Date()))"
    var url = dir.appendingPathComponent(base + ".png")
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base)-\(n).png")
      n += 1
    }
    do { try png.write(to: url) } catch {
      NSLog("[ERROR] E-MAC-RENDER-0001 캡처 저장 실패")
      return nil
    }
    let capture = ShelfCapture(url: url,
                               thumbnail: Self.thumbnailPNG(png, maxSide: 480),
                               width: pixelWidth, height: pixelHeight, source: source)
    shelfCaptures.insert(capture, at: 0)
    shelfTab = .capture
    NSLog("[QuickShelf] 캡처 추가 source=%@ %dx%d (총 %d)",
          source.rawValue, pixelWidth, pixelHeight, shelfCaptures.count)
    return capture
  }

  func removeCapture(_ id: UUID) {
    if let c = shelfCaptures.first(where: { $0.id == id }) {
      try? FileManager.default.removeItem(at: c.url)
    }
    shelfCaptures.removeAll { $0.id == id }
  }

  func clearCaptures() {
    for c in shelfCaptures { try? FileManager.default.removeItem(at: c.url) }
    shelfCaptures.removeAll()
  }

  /// 캡처 카드 툴바 — 클립보드 복사(다른 앱에 바로 붙여넣기)
  func copyCapture(_ capture: ShelfCapture) {
    guard let image = NSImage(contentsOf: capture.url) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.writeObjects([image])
    showShelfNotice(L("캡처를 클립보드에 복사했습니다."))
    NSLog("[QuickShelf] 캡처 클립보드 복사")
  }

  /// 캡처 카드 툴바 — 다른 이름/위치로 저장
  func saveCaptureAs(_ capture: ShelfCapture) {
    let panel = NSSavePanel()
    panel.allowedContentTypes = [.png]
    panel.nameFieldStringValue = capture.url.lastPathComponent
    panel.canCreateDirectories = true
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      try FileManager.default.copyItem(at: capture.url, to: url)
      showShelfNotice(L("캡처를 저장했습니다."))
      NSLog("[QuickShelf] 캡처 저장")
    } catch {
      showShelfNotice(L("캡처 저장에 실패했습니다."))
      NSLog("[ERROR] E-MAC-RENDER-0001 캡처 저장 실패")
    }
  }

  /// 캡처 카드 클릭 → 대화 첨부. 첨부용 임시 복사본을 만든 뒤 카드와 원본을 지운다.
  /// (첨부가 원본 경로를 가리킨 채 파일이 사라지는 문제를 막는다)
  func attachCapture(_ capture: ShelfCapture) {
    guard let data = try? Data(contentsOf: capture.url) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    let base = capture.url.deletingPathExtension().lastPathComponent
    guard let url = Self.writeTempImage(data, name: base) else {
      showShelfNotice(L("캡처 파일을 읽을 수 없습니다."))
      return
    }
    attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: .image))
    removeCapture(capture.id)
    NSLog("[QuickShelf] 캡처 첨부 (첨부=%d)", attached.count)
    closeShelfAfterPick()
    NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
  }

  /// PNG → 축소 PNG(카드 썸네일)
  static func thumbnailPNG(_ data: Data, maxSide: CGFloat) -> Data? {
    guard let image = NSImage(data: data) else { return data }
    let size = image.size
    guard size.width > 0, size.height > 0 else { return data }
    let scale = min(1, maxSide / max(size.width, size.height))
    let target = NSSize(width: max(1, (size.width * scale).rounded()),
                        height: max(1, (size.height * scale).rounded()))
    let thumb = NSImage(size: target)
    thumb.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: target),
               from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1)
    thumb.unlockFocus()
    guard let tiff = thumb.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return data }
    return rep.representation(using: .png, properties: [:])
  }

  func removeAttachment(_ id: UUID) { attached.removeAll { $0.id == id } }

  /// 앱 지원 폴더에 임시 이미지 파일을 만든다 — 첨부 칩에 사람이 알아볼 이름이 보이도록
  /// 크기·시각을 파일명에 넣는다(예: 붙여넣은 이미지 600x300-215412.png)
  private static func writeTempImage(_ data: Data, name: String? = nil) -> URL? {
    let fm = FileManager.default
    guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("QuickTalk/clip", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    let size = NSBitmapImageRep(data: data).map { "\($0.pixelsWide)x\($0.pixelsHigh)" } ?? "image"
    let df = DateFormatter()
    df.dateFormat = "HHmmss"
    let stem: String
    if let name, !name.isEmpty {
      stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
    } else {
      stem = "붙여넣은 이미지 \(size)-\(df.string(from: Date()))"
    }
    var url = dir.appendingPathComponent("\(stem).png")
    var n = 2
    while fm.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(stem)-\(n).png")
      n += 1
    }
    do { try data.write(to: url); return url } catch { return nil }
  }

  private func saveSettings() {
    guard !suppressSettingsSave else { return }   // QA 렌더용 임시 변경은 저장하지 않는다
    if let data = try? JSONEncoder().encode(settings) {
      UserDefaults.standard.set(data, forKey: settingsKey)
    }
  }

  /// QA 렌더 하네스 전용 — 저장 없이 설정 한 항목만 바꾼다(사용자 설정 오염 금지).
  func applyRenderOverride(ttsEngine: TTSEngine) {
    suppressSettingsSave = true
    settings.ttsEngine = ttsEngine
    suppressSettingsSave = false
  }

  /// QA 렌더 전용 — **실제 언어 전환 경로**를 태운다(설정 발행 → AppDelegate sink → applyLanguage).
  /// `--lang=`(실행 인자)은 시작 시점만 재현하므로, 사용자가 설정에서 언어를 바꾸는 경우는 이쪽으로 확인한다.
  func applyRenderOverride(language: AppLanguage) {
    suppressSettingsSave = true
    settings.language = language
    suppressSettingsSave = false
  }

  /// QA 렌더 시작 표시 — 렌더 중에는 실제 기록을 디스크에서 다시 읽지 않는다(개인 대화가 문서에 남지 않게).
  func markRenderHarness() { isRenderHarness = true }

  /// QA 렌더·실검증용 — 웹 검색을 켠 상태로 **메모리에서만** 바꾼다(설정 저장 없음).
  func applyRenderOverride(webSearch enabled: Bool) {
    suppressSettingsSave = true
    settings.webSearchProvider = enabled ? .exa : .none
    suppressSettingsSave = false
  }

  /// QA 렌더 전용 — 전역 자동 수락을 켠 상태를 **메모리에서만** 재현한다(설정 저장 없음).
  func applyRenderOverride(autoAcceptAll: Bool) {
    suppressSettingsSave = true
    settings.agentPolicy.autoAcceptAll = autoAcceptAll
    suppressSettingsSave = false
  }

  /// QA 렌더 전용 — 상단 도구를 항상 보이는 상태로 **메모리에서만** 재현한다(설정 저장 없음).
  func applyRenderOverride(chatToolbarAlwaysVisible: Bool) {    suppressSettingsSave = true
    settings.chatToolbarAlwaysVisible = chatToolbarAlwaysVisible
    suppressSettingsSave = false
  }

  /// QA 렌더 전용 — 컴퓨터 제어(화면 요소 읽기)를 켠 상태를 **메모리에서만** 재현한다(설정 저장 없음).
  func applyRenderOverride(uiControl: Bool) {
    suppressSettingsSave = true
    settings.uiControlEnabled = uiControl
    suppressSettingsSave = false
  }

  /// QA 렌더 전용 — 웹 검색 답변 방식을 **메모리에서만** 바꾼다(설정 저장 없음).
  /// `simulateRemoteProvider` 면 OpenAI 호환 모델을 하나 심어 "도구 루프가 검색을 가져가는" 상태를 재현한다.
  func applyRenderOverride(webSearchMode: WebSearchMode, agentTools: Bool? = nil,
                           simulateRemoteProvider: Bool = false) {
    suppressSettingsSave = true
    settings.webSearchProvider = .exa
    settings.webSearchMode = webSearchMode
    if let agentTools { settings.agentToolsEnabled = agentTools }
    if simulateRemoteProvider {
      // 실제 키가 있는 secretID 를 빌려 쓴다 — `canUseAgentTools` 는 키 존재까지 확인한다.
      let keyID = settings.providers.map(\.secretID)
        .first { SecretStore.has(account: $0) } ?? settings.exaSecretID
      let qa = LLMProviderConfig(id: "qa-remote", name: "QA Remote", type: .openAICompatible,
                                 baseURL: "http://127.0.0.1:1/v1", model: "qa-model",
                                 secretID: keyID, enabled: true)
      settings.providers = [qa]
      settings.activeProviderID = qa.id
    }
    suppressSettingsSave = false
  }

  /// QA 렌더·실검증용 — 대화를 **메모리에만** 바꾼다(저장 없음).
  func applyConversationForSelfTest(_ c: Conversation) {
    // 자가검증이 실제 history.json을 덮어쓰지 않게 이 실행 동안 저장을 막는다.
    suppressArchiveSaveForSelfTest = true
    core.open(c)
    conversation = core.conversation
  }

  /// QA 자가검증 전용 — true면 `syncArchive()`가 파일을 쓰지 않는다(사용자 기록 보호).
  var suppressArchiveSaveForSelfTest = false

  /// QA 렌더 전용 — 비서 목록을 **메모리에서만** 바꾼다(설정 저장 없음).
  func applyRenderOverride(personas: [Persona]) {
    suppressSettingsSave = true
    settings.personas = personas
    suppressSettingsSave = false
  }

  /// QA 실검증용 — 활성 프로바이더를 **메모리에서만** 바꾼다(설정 저장 없음).
  func applyRenderOverride(activeProviderID id: String) {
    suppressSettingsSave = true
    settings.activeProviderID = id
    suppressSettingsSave = false
  }

  /// QA 실검증용 — 프로바이더 **종류**로 활성 프로바이더를 고른다(예: Apple FM).
  func applyRenderOverride(providerType: LLMProviderType) {
    guard let p = settings.providers.first(where: { $0.type == providerType && $0.enabled })
      ?? settings.providers.first(where: { $0.type == providerType }) else { return }
    applyRenderOverride(activeProviderID: p.id)
  }

  // MARK: - 표시 정책 (메뉴바·Dock 중 최소 1개 유지)

  func setMenuBarIcon(_ visible: Bool) {
    var s = settings
    s.setMenuBarIcon(visible)
    settings = s
  }

  func setDockIcon(_ visible: Bool) {
    var s = settings
    s.setDockIcon(visible)
    settings = s
  }

  /// 현재 진입점 상태 안내 문구 (설정·Hub 공용)
  var visibilityHint: String {
    if !settings.showMenuBarIcon {
      return L("메뉴바 아이콘을 숨겼습니다. Dock 아이콘과 단축키로 열 수 있습니다.")
    }
    if settings.showDockIcon {
      return L("메뉴바와 Dock 양쪽에서 열 수 있습니다.")
    }
    return L("메뉴바 아이콘으로 열 수 있습니다. 단축키로도 호출됩니다.")
  }

  // MARK: - AI 빠른 설정 (대화 창 설정 탭 · 메뉴바 Hub 설정 탭 공용 상태)

  /// 마지막 AI 호출 결과 — 상태 카드에 표시(상주 요청 없이 결과만 보관)
  enum AICallState: Equatable {
    case none
    case ok
    case failed(String)
  }

  @Published var lastAICall: AICallState = .none
  /// 마지막 AI 오류의 **정확한 원인** 한 줄(상태 카드) — 성공하면 지운다.
  /// 예: `연결 거부 (-1004)`, `HTTP 401 · E-AND-AUTH-0004`
  @Published var lastAIErrorDetail: String?
  /// 활성 AI·모델 연결 테스트 진행 중
  @Published var testingProvider = false
  /// 연결 테스트 결과(응답 앞부분 또는 에러코드) — 비어 있으면 표시하지 않는다
  @Published var providerTestResult: String?
  @Published var modelOptions: [String] = []
  @Published var loadingModels = false
  @Published var modelNote: String?

  /// 모델 픽커 후보 — 저장된 모델명 + 조회해 온 목록
  var activeModelChoices: [String] {
    var list: [String] = []
    if let m = settings.activeProvider?.model, !m.isEmpty { list.append(m) }
    for m in modelOptions where !list.contains(m) { list.append(m) }
    return list
  }

  func setActiveProvider(_ id: String) {
    settings.activeProviderID = id
    modelOptions = []
    modelNote = nil
    providerTestResult = nil
    lastAIErrorDetail = nil
    lastAICall = .none
  }

  func setActiveModel(_ model: String) {
    guard let id = settings.activeProvider?.id,
          let i = settings.providers.firstIndex(where: { $0.id == id }) else { return }
    var list = settings.providers
    list[i].model = model
    settings.providers = list
    providerTestResult = nil
    lastAIErrorDetail = nil
    lastAICall = .none
  }

  /// 모델 목록 조회 — 사용자가 ⟳를 눌렀을 때만 요청한다(상주 요청 금지).
  func refreshModels() {
    guard let p = settings.activeProvider else {
      modelOptions = []; modelNote = L("활성 AI가 없습니다 (E-MAC-NET-0002)"); return
    }
    guard p.type != .appleFM else {
      modelOptions = []; modelNote = L("온디바이스 모델은 자동 선택됩니다"); return
    }
    guard let host = URL(string: p.baseURL) else {
      modelOptions = []; modelNote = L("주소가 올바르지 않습니다 (E-MAC-NET-0002)"); return
    }
    loadingModels = true
    modelNote = nil
    Task { @MainActor in
      defer { self.loadingModels = false }
      do {
        switch p.type {
        case .ollama:
          self.modelOptions = try await OllamaClient.listModels(host: host)
        case .openAICompatible:
          let key = p.secretID.isEmpty ? "" : (SecretStore.load(account: p.secretID) ?? "")
          self.modelOptions = try await OpenAIClient.listModels(baseURL: host, apiKey: key)
        case .appleFM:
          self.modelOptions = []
        }
        self.modelNote = self.modelOptions.isEmpty
          ? L("모델 목록이 비어 있습니다 (E-MAC-NET-0002)")
          : Lf("모델 %d개", self.modelOptions.count)
      } catch {
        self.modelOptions = []
        self.modelNote = L("모델 목록 조회 실패 (E-MAC-NET-0002)")
        NSLog("[ERROR] E-MAC-NET-0002 모델 목록 조회 실패: \(error)")
      }
    }
  }

  /// 선택한 AI·모델로 실제 질문(ping) 1건을 보내 연결을 확인한다.
  /// 설정 창의 '연결 테스트'(ProviderEditorSheet)와 같은 응답 경로를 쓴다.
  /// 응답 본문은 짧게만 화면에 남기고 로그에는 남기지 않는다.
  func testActiveProvider() {
    guard !testingProvider else { return }
    guard let p = settings.activeProvider else {
      providerTestResult = L("활성 AI가 없습니다 (E-MAC-NET-0002)")
      lastAIErrorDetail = L("활성 AI 없음")
      lastAICall = .failed("E-MAC-NET-0002")
      return
    }
    testingProvider = true
    providerTestResult = nil
    Task { @MainActor in
      defer { self.testingProvider = false }
      let started = Date()
      do {
        let reply = try await Self.reply(provider: p, prompt: "ping", history: [])
        let isError = reply.hasPrefix("(오류") || reply.hasPrefix("(Error")
        let elapsed = Date().timeIntervalSince(started)
        if isError {
          let code = Self.errorCode(in: reply)
          self.lastAICall = .failed(code)
          self.lastAIErrorDetail = Self.errorSummary(in: reply)
          self.providerTestResult = reply.count > 90 ? String(reply.prefix(90)) + "…" : reply
          NSLog("[QuickTalk] 연결 테스트 실패 (%@) %.1fs", code, elapsed)
        } else {
          self.lastAICall = .ok
          self.lastAIErrorDetail = nil
          let flat = reply
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
          self.providerTestResult = Lf("응답: %@", flat.count > 60 ? String(flat.prefix(60)) + "…" : flat)
          NSLog("[QuickTalk] 연결 테스트 성공 %.1fs", elapsed)
        }
      } catch {
        let code = AIErrorText.code(for: error)
        let url = URL(string: p.baseURL)
        self.lastAICall = .failed(code)
        self.lastAIErrorDetail = AIErrorText.shortDetail(for: error)
        self.providerTestResult = Lf("실패 (%@): %@", code, AIErrorText.detail(for: error, url: url))
        NSLog("[QuickTalk] 연결 테스트 실패 (%@) — %@ %.1fs", code, AIErrorText.logLabel(for: error),
              Date().timeIntervalSince(started))
      }
    }
  }

  // MARK: - 상태 카드 (읽기 전용)

  var aiStatusText: String {
    switch lastAICall {
    case .none: return L("아직 호출 없음")
    case .ok: return L("정상")
    case .failed(let code): return Lf("실패 · %@", code)
    }
  }

  var aiStatusOK: Bool {
    if case .ok = lastAICall { return true }
    return false
  }

  var shortcutStatusOK: Bool { shortcutStatus[.invoke] ?? false }

  var voiceStatusText: String {
    settings.voiceEngine == .whisper
      ? (WhisperService.isReady(settings: settings) ? L("Whisper 준비됨") : L("Whisper 미지정"))
      : settings.voiceEngine.rawValue
  }

  var voiceStatusOK: Bool {
    settings.voiceEngine == .whisper ? WhisperService.isReady(settings: settings) : true
  }

  /// 오류 문구에서 에러코드만 추출 (없으면 네트워크 기본값)
  private static func errorCode(in text: String) -> String {
    guard let r = text.range(of: "E-MAC-[A-Z]+-[0-9]{4}", options: .regularExpression) else {
      return "E-MAC-NET-0001"
    }
    return String(text[r])
  }

  /// 오류 문구에서 `(오류 CODE) ` 접두어를 떼고 상태 카드용 문구로 만든다.
  /// 서버가 준 본문은 들어 있지 않고, 앱이 만든 원인 설명만 남는다.
  private static func errorSummary(in text: String) -> String {
    var body = text
    if let r = body.range(of: "^(?:\\(오류 |\\(Error )[^)]+\\)\\s*", options: .regularExpression) {
      body.removeSubrange(r)
    }
    body = body
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    // 상태 카드는 여러 줄로 늘어날 수 있으므로 원인 설명을 자르지 않는다.
    // (서버 본문이 아니라 앱이 만든 고정 문구라 길이가 제한적이다)
    return body
  }

  /// 단축키로 새로 열 때의 세션 규칙 — 마지막 대화가 유지 시간(`shortcutSessionMinutes`)을
  /// 넘겼으면 지난 대화를 기록에 남기고 새로 시작한다. `0`(사용 안 함)이면 언제나 새 대화.
  func startShortcutSession() {
    guard !conversation.turns.isEmpty else { return }
    guard settings.continuesSession(lastActivity: conversation.updatedAt) else {
      NSLog("[QuickTalk] 단축키 세션 만료(%@) — 새 대화 시작", settings.sessionMinutesLabel)
      newConversation()
      return
    }
    NSLog("[QuickTalk] 단축키 세션 유지(%@) — 마지막 대화 이어서", settings.sessionMinutesLabel)
  }

  /// 새 대화 — 지금 대화는 **먼저 기록에 저장**하고 비운다(휘발 금지).
  /// 표시 언어가 바뀌었을 때 뷰를 다시 그리게 한다(번역표는 관찰 대상이 아니다).
  func languageDidChange() {
    objectWillChange.send()
  }

  func newConversation() {
    stopSpeaking()
    syncArchive()
    // 새 대화의 기본 비서 — 설정 › 비서의 `defaultPersonaID`(없으면 기본).
    var fresh = Conversation()
    if let id = settings.defaultPersonaID, settings.persona(id) != nil {
      fresh.personaID = id
    }
    activateSession(fresh)
    compactMessage = nil
  }

  /// 대화방으로 전환한다 — 방마다 입력·실행 상태가 따로 남는다(v0.31 6a).
  /// 같은 방을 다시 열면 **진행 중인 상태를 덮어쓰지 않는다**(응답 중인 방 보호).
  private func activateSession(_ c: Conversation) {
    if let existing = sessions[c.id] {
      if !existing.isReplying {
        existing.core.open(c)
        existing.conversation = existing.core.conversation
      }
      activeSessionID = existing.id
      observe(existing)
    } else {
      let session = ChatSession(conversation: c)
      sessions[session.id] = session
      observe(session)
      activeSessionID = session.id
    }
    // 빈 임시 방(앱 시작 기본)은 남겨 두지 않는다.
    let empties = sessions.filter { $0.key != activeSessionID
      && $0.value.conversation.turns.isEmpty
      && !$0.value.conversation.pinned
      && !$0.value.isReplying
      && $0.value.draft.isEmpty }
    for key in empties.keys {
      sessions.removeValue(forKey: key)
      sessionObservers.removeValue(forKey: key)
    }
  }

  /// 이 대화의 비서를 바꾼다 — 목록 맨 위는 `기본(비서 없음)`.
  func selectPersona(_ id: UUID?) {
    guard conversation.personaID != id else { return }
    core.setPersonaID(id)
    conversation = core.conversation
    syncArchive()
    NSLog("[QuickTalk] 대화 비서 선택 — %@",
          settings.persona(id)?.name ?? "기본")
  }
  // MARK: - 질문 되돌리기·다시 응답 (T-72)

  /// 질문을 입력창으로 되돌린다 — 그 질문과 이후 응답을 모두 지우고, 텍스트·첨부를 복원한다.
  func editQuestion(_ turn: Turn) {
    guard !isReplying, turn.role == .user else { return }
    restoreQuestion(turn, resend: false)
  }

  /// 같은 질문으로 다시 응답을 받는다 — 이후 대화를 지우고 방금 질문을 그대로 다시 보낸다.
  func regenerateAnswer(_ turn: Turn) {
    guard !isReplying, turn.role == .user else { return }
    restoreQuestion(turn, resend: true)
  }

  /// 어시스턴트 답변 바로 앞의 사용자 질문 — 웹 검색 재시도에 쓴다.
  func userTurn(before turnID: UUID) -> Turn? {
    guard let index = conversation.turns.firstIndex(where: { $0.id == turnID }) else { return nil }
    return conversation.turns[..<index].last(where: { $0.role == .user })
  }

  /// 답변이 "검색할 수 없다"고 밝혔고, 웹 검색이 준비되어 있으면 재시도 버튼을 보여 준다.
  func shouldOfferWebRetry(_ turn: Turn) -> Bool {
    guard settings.webSearchProvider != .none, webSearchKeyReady, !isReplying else { return false }
    guard turn.role == .assistant, !turn.text.isEmpty else { return false }
    guard (turn.sources ?? []).isEmpty else { return false }
    guard WebSearchQuery.looksLikeSearchRefusal(turn.text) else { return false }
    return userTurn(before: turn.id) != nil
  }

  /// 같은 질문을 웹 검색 강제로 다시 보낸다 — 이후 턴은 지우고 새 답변을 만든다.
  func retryWithWebSearch(_ turn: Turn) {
    guard shouldOfferWebRetry(turn), let question = userTurn(before: turn.id) else { return }
    forceWebSearch = true
    NSLog("[QuickTalk] 웹 검색 재시도 — 이전 답변을 되돌리고 같은 질문을 검색 강제로 전송")
    regenerateAnswer(question)
  }

  private func restoreQuestion(_ turn: Turn, resend: Bool) {
    guard let restored = core.rewind(toUserTurnID: turn.id) else { return }
    conversation = core.conversation
    draft = restored.text
    attached = restored.attachments.map { a in
      PendingAttachment(name: a.name,
                        url: a.path.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) },
                        kind: a.kind)
    }
    searchFocus = nil
    compactMessage = nil
    lastAICall = .none
    lastAIErrorDetail = nil
    composerFocusToken = UUID()
    syncArchive()
    if resend { send(allowCommands: false) }
  }

  /// 보관(만료 없이 유지) 토글
  func togglePin() {
    core.togglePin()
    conversation = core.conversation
    syncArchive()
  }
  /// 모든 대화 기록(자동 저장분 + 보관분). 화면에는 `syncArchive`/`loadArchive`로 반영된다.
  @Published var archive: [Conversation] = []

  func loadArchive() {
    var list = PersistenceService.load(keepDays: settings.keepDays)
    if !conversation.turns.isEmpty || conversation.pinned {
      list.removeAll { $0.id == conversation.id }
      list.insert(conversation, at: 0)
    }
    archive = ConversationHistory.ordered(list)
  }

  /// 앱 시작 시 마지막 대화를 이어서 연다(2026-10-20 "언제나 새 대화" 수정).
  func restoreLastConversation() {
    guard conversation.turns.isEmpty,
          let latest = ConversationHistory.mostRecent(archive) else { return }
    activateSession(latest)
    NSLog("[QuickTalk] 마지막 대화 복원 — %d턴 pinned=%@",
          conversation.turns.count, conversation.pinned ? "Y" : "N")
    markInterruptedQuestion()
    // 앱을 다시 켰을 때 이미 예산을 넘었으면 백그라운드로 정리한다(첫 답변 지연 방지).
    startAutoCompact(convID: conversation.id)
  }

  /// ★ 앱이 꺼진 사이에 응답이 끝나지 못한 질문이 남아 있으면 — "사라짐" 대신
  ///   왜 끊겼는지 알리고 다시 물어볼 수 있게 한다(2026-10-22 사고: 앱이 멈춰서
  ///   강제 종료되면 마지막 질문의 답이 기록에 남지 않았다).
  private func markInterruptedQuestion() {
    guard let last = conversation.turns.last, last.role == .user else { return }
    let note = L("앱이 종료되어 응답이 끊겼습니다. 같은 질문을 다시 보내 주세요.")
    _ = core.appendAssistant(text: note)
    conversation = core.conversation
    syncArchive()
    NSLog("[QuickTalk] E-MAC-AGENT-0002 응답이 끊긴 질문을 표시했습니다")
  }

  /// 현재 대화를 기록에 반영하고 파일에 쓴다 — 핀 여부와 무관(모든 대화 자동 저장).
  func syncArchive(_ session: ChatSession? = nil) {
    guard !suppressArchiveSaveForSelfTest else { return }
    let conversation = (session ?? activeSession).conversation
    archive.removeAll { $0.id == conversation.id }
    if !conversation.turns.isEmpty || conversation.pinned {
      archive.insert(conversation, at: 0)
    }
    archive = ConversationHistory.ordered(archive)
    do {
      try PersistenceService.save(archive)
    } catch {
      NSLog("[WARN] E-MAC-RENDER-0001 대화 기록 저장 실패: %@", String(describing: error))
    }
  }

  /// 예약 실행 대화를 보관함에 반영한다(v0.26).
  ///
  /// 사용자가 그 대화를 **열어 놓았으면** 화면도 함께 갱신한다(승인 카드가 실시간으로 보이게).
  /// 열려 있지 않으면 보관함 목록만 갱신한다 — 현재 대화는 건드리지 않는다.
  func applyScheduledConversation(_ c: Conversation) {
    archive.removeAll { $0.id == c.id }
    if !c.turns.isEmpty || c.pinned { archive.insert(c, at: 0) }
    archive = ConversationHistory.ordered(archive)
    try? PersistenceService.save(archive)
    if conversation.id == c.id {
      core.open(c)
      conversation = core.conversation
    }
  }

  /// 대화별 권한 오버라이드 변경(v0.22) — 코어에 반영하고 즉시 저장한다.
  func setAgentOverride(_ update: (inout AgentOverride) -> Void) {
    var override = conversation.agentOverride ?? AgentOverride()
    update(&override)
    core.setAgentOverride(override)
    conversation = core.conversation
    syncArchive()
  }

  /// 승인 쓰기 폴더를 코어에 반영하고 즉시 저장한다.
  func setWriteScopeGrants(_ grants: [WriteScopeGrant]) {
    core.setWriteScopeGrants(grants)
    conversation = core.conversation
    syncArchive()
  }

  /// 이번 대화에서 승인한 쓰기 폴더를 해제한다.
  func removeWriteScope(_ scope: String) {
    let remaining = (conversation.approvedWriteScopes ?? []).filter { $0.path != scope }
    setWriteScopeGrants(remaining)
  }

  /// 승인된 조작 앱을 코어에 반영하고 즉시 저장한다 — 만료된 승인은 저장하지 않는다.
  func setUiAppGrants(_ grants: [UiAppGrant]) {
    core.setUiAppGrants(grants)
    conversation = core.conversation
    syncArchive()
  }

  /// [이 앱 허용] — 이 대화에서 그 앱을 7일 동안 다시 묻지 않는다.
  func approveUiApp(bundleID: String, name: String) {
    if let ctx = scheduledRun {
      let grants = UiAppGrant.approve(bundleID: bundleID, name: name,
                                      into: ctx.conversation.approvedUiApps ?? [])
      ctx.session.setUiAppGrants(grants)
      ctx.uiGrants = ctx.conversation.approvedUiApps ?? []
      applyScheduledConversation(ctx.conversation)
      NSLog("[QuickTalk] 예약 실행 화면 조작 앱 승인 — %d개 앱", ctx.uiGrants.count)
      return
    }
    let grants = UiAppGrant.approve(bundleID: bundleID, name: name,
                                    into: conversation.approvedUiApps ?? [])
    setUiAppGrants(grants)
    NSLog("[QuickTalk] 화면 조작 앱 승인 — %d개 앱", activeUiAppGrants.count)
  }

  /// 승인한 조작 앱을 해제한다 — 다음 조작은 다시 묻는다.
  func removeUiAppGrant(bundleID: String) {
    let remaining = (conversation.approvedUiApps ?? []).filter { $0.bundleID != bundleID }
    setUiAppGrants(remaining)
  }

  /// 대화방 제목 변경 — 대화 헤더·보관함 공용.
  /// 현재 대화면 코어에 반영하고, 보관함 목록·파일에도 즉시 저장한다. 빈 제목은 무시.
  func renameConversation(id: UUID, to newTitle: String) {
    let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return }
    if conversation.id == id {
      core.rename(to: t)
      conversation = core.conversation
    }
    if let i = archive.firstIndex(where: { $0.id == id }) {
      archive[i].rename(to: t)
    }
    syncArchive()
  }

  func deleteConversation(_ c: Conversation) {
    let deletingCurrent = conversation.id == c.id
    // 진행 중 응답이 있으면 먼저 멈춘다 — 취소하지 않으면 지운 대화의 답변이
    // 새 대화에 이어 붙는다(2026-11-06, 진행 중 대화 삭제 추가).
    if deletingCurrent { cancelReply() }
    archive.removeAll { $0.id == c.id }
    try? PersistenceService.save(archive)
    // 현재 대화를 지웠다면 그 자리에서 **새 대화**로 비운다(syncArchive로 되살아나지 않게).
    if deletingCurrent {
      stopSpeaking()
      core.reset()
      if let id = settings.defaultPersonaID, settings.persona(id) != nil {
        core.setPersonaID(id)
      }
      conversation = core.conversation
      draft = ""; attached.removeAll()
      compactMessage = nil
      searchFocus = nil
      pendingSchedule = nil
    }
  }

  func clearArchive() {
    archive.removeAll()
    try? PersistenceService.save(archive)
  }

  /// 보관함에서 대화를 연다. `searching`이 있으면 그 검색어와 일치하는 첫 턴으로 포커스를 요청한다.
  func openConversation(_ c: Conversation, searching query: String = "") {
    activateSession(c)
    compactMessage = nil
    if let turn = c.firstTurn(matching: query) {
      searchFocus = SearchFocusRequest(conversationID: c.id, turnID: turn.id, query: query)
    } else {
      searchFocus = nil
    }
    startAutoCompact(convID: c.id)
  }

  /// 알림 클릭 — 대화 ID로 연다(5단계 딥링크). 보관함에 없으면 디스크에서 다시 읽는다.
  @discardableResult
  func openConversation(id: UUID) -> Bool {
    if let c = archive.first(where: { $0.id == id }) {
      openConversation(c)
      return true
    }
    let list = PersistenceService.load(keepDays: settings.keepDays)
    guard let c = list.first(where: { $0.id == id }) else { return false }
    archive = list
    openConversation(c)
    return true
  }

  // MARK: - 음성 (엔진별 분기)
  func toggleVoice() {
    // 받아쓰기 시작 전에 낭독을 멈춘다(스피커 소리가 마이크로 들어가지 않게)
    if !voiceRecording { stopSpeaking() }
    switch settings.voiceEngine {
    case .apple:
      speech.toggle()
    case .whisper:
      toggleWhisperRecord()
    }
  }

  /// 읽어주기 — 같은 응답을 읽는 중이면 **중지**, 다른 응답이면 그 응답으로 바꿔 읽는다.
  func speak(_ text: String, turnID: UUID? = nil) {
    guard !text.isEmpty else { return }
    if isSpeaking, turnID == nil || speakingTurnID == turnID {
      stopSpeaking()
      return
    }
    // 엔진을 바꿔 읽거나 다른 답변으로 넘어갈 때 — 이전 소리를 반드시 끊는다
    stopSpeaking()
    speakingTurnID = turnID
    switch settings.ttsEngine {
    case .edge: edgeSpeech.speak(text)
    case .piper: piperSpeech.speak(text)
    case .apple: speech.speak(text)
    }
  }

  /// 읽어주기 중지(헤더·Hub·메시지 버튼 공용)
  func stopSpeaking() {
    speech.stopSpeaking()
    edgeSpeech.stop()
    piperSpeech.stop()
    speakingTurnID = nil
  }

  /// 설정 창 '미리 듣기' — 지금 고른 엔진·목소리·속도로 샘플을 읽는다
  func previewVoice() {
    stopSpeaking()
    switch settings.ttsEngine {
    case .edge: edgeSpeech.previewVoice()
    case .piper: piperSpeech.previewVoice()
    case .apple: speech.previewVoice()
    }
  }

  /// 음성 설정을 서비스에 넘긴다(받아쓰기 언어·읽어주기 목소리/속도)
  private func applySpeechSettings() {
    speech.configure(locale: settings.appleSpeechLocale,
                     voice: settings.ttsVoiceID,
                     ttsLanguage: settings.ttsLanguage,
                     rate: settings.ttsRate)
    edgeSpeech.configure(voice: settings.edgeVoice,
                         rate: settings.ttsRate,
                         binary: settings.edgeBinaryPath)
    piperSpeech.configure(rate: settings.ttsRate,
                          model: settings.piperModelPath,
                          binary: settings.piperBinaryPath)
  }

  private var whisperURL: URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("quicktalk-voice.wav")
  }

  private func toggleWhisperRecord() {
    if let rec = whisperRecorder, rec.isRecording {
      rec.stop()
      whisperRecorder = nil
      voiceRecording = false
      transcribeWhisper()
      return
    }
    guard WhisperService.isReady(settings: settings) else {
      NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 미준비: \(WhisperService.status(settings: settings))")
      draft = L("(Whisper 미준비) ") + WhisperService.status(settings: settings)
      return
    }
    let fmt = [AVFormatIDKey: Int(kAudioFormatLinearPCM),
               AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1,
               AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false] as [String: Any]
    do {
      whisperRecorder = try AVAudioRecorder(url: whisperURL, settings: fmt)
      whisperRecorder?.record()
      voiceRecording = true
    } catch {
      NSLog("[ERROR] E-MAC-AUDIO-0001 녹음 시작 실패: \(error)")
    }
  }

  private func transcribeWhisper() {
    Task { @MainActor in
      do {
        draft = try await WhisperService.transcribe(wavURL: whisperURL, settings: settings)
      } catch {
        NSLog("[ERROR] E-MAC-AUDIO-0001 Whisper 전사 실패: \(error)")
        draft = L("(전사 실패 E-MAC-AUDIO-0001)")
      }
    }
  }
  func send(allowCommands: Bool = true) {
    stopSpeaking()
    // 응답 대기 중 중복 전송 금지 — 답이 섞이지 않게 한다(입력독의 ↑도 비활성)
    guard !isReplying else {
      NSLog("[QuickTalk] 응답 대기 중 — 중복 전송 무시")
      return
    }
    // 새 질문을 시작하면 이전 답변의 후속 질문 제안은 지운다(v0.32).
    clearFollowUps(for: activeSession)
    // 보조 명령 — 일반 사용자는 자동 정리만 쓰면 된다. `/compact`는 즉시 정리.
    let command = draft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if allowCommands, command == "/compact" {
      draft = ""
      compactNow()
      return
    }
    do {
      let pending = attached                       // 전송 직후 목록을 비우므로 미리 잡아 둔다
      // 경로까지 남긴다 — 보낸 뒤 말풍선에 썸네일·미리보기를 다시 그리기 위해
      let atts = pending.map { Attachment(name: $0.name, kind: $0.kind, path: $0.url?.path) }
      let prompt = draft
      try core.submit(text: prompt, attachments: atts)
      conversation = core.conversation
      draft = ""; attached.removeAll()
      syncArchive()                      // 사용자 메시지도 바로 기록(앱이 꺼져도 남는다)
      // 한글 IME: 전송 직후 조합 커밋이 입력창으로 되돌아오는 경우가 있어 잠시 방어한다
      suppressEcho(of: prompt)
      // 이 응답이 **어느 대화방의 것인지** 잡아 둔다 — 도중에 다른 방을 열어도
      // 상태·글자는 그 방에만 쌓인다(v0.31 6a/6b).
      let session = activeSession
      session.isReplying = true
      session.replyStartedAt = Date()
      let convID = session.conversation.id
      session.replyTask = Task { @MainActor in
        // 응답까지 걸린 시간 — 모델 호출 구간만 잰다(첨부 읽기 제외)
        var callStarted = Date()
        defer {
          session.isReplying = false
          session.replyStartedAt = nil
          session.streamingTurnID = nil
          session.isSearching = false
          session.networkRetryStatus = nil
          session.replyTask = nil
        }
        // 첨부 "내용"은 여기서 읽는다 — 텍스트 파일은 본문 인라인, 이미지는 data URL로 실린다
        let outgoing = await Self.loadAttachments(pending)
        if !outgoing.isEmpty {
          NSLog("[QuickTalk] 첨부 전송 준비 — %@", AttachmentLoader.summary(outgoing))
        }
        guard session.conversation.id == convID else { return }
        // 사용자가 [중지]를 눌렀으면 여기서 멈춘다(모델 호출 없이 종료).
        if Task.isCancelled { return }
        guard let provider = self.settings.activeProvider else {
          self.compactMessage = L("활성 AI가 없습니다. 설정 > AI에서 프로바이더를 켜 주세요.")
          self.lastAICall = .failed("E-MAC-MODEL-0002")
          self.lastAIErrorDetail = L("활성 AI가 없습니다.")
          return
        }
        // 이번 질문은 `prompt`로 따로 싣는다 — 기록에서 사용자 턴까지 빼야 같은 질문이 두 번 들어가지 않는다
        // 요약이 있으면 경계 이후만 원문으로 싣고, 요약은 프롬프트 앞에 고정한다.
        // 예산을 넘는 장문 대화는 오래된 기록부터 요청에서 제외한다(원문은 저장소에 유지).
        let attachmentTokens = outgoing.reduce(0) { sum, a in
          sum + ConversationMemory.estimateTokens(a.name) + (a.kind == .image ? 256 : 0)
        }
        let ws = self.settings
        // 로컬 Ollama는 프롬프트가 길수록 첫 토큰이 늦다 — 검색 결과 수·본문 길이를 먼저 줄인다.
        // (Apple FM·원격은 설정값 그대로 — 이 절약은 Ollama 전용이다)
        let searchLimits = WebSearchPromptLimits.limits(resultCount: ws.webSearchResultCount,
                                                        maxCharacters: ws.webSearchMaxCharacters,
                                                        provider: provider)
        if searchLimits.resultCount != ws.webSearchResultCount
            || searchLimits.maxCharacters != ws.webSearchMaxCharacters {
          NSLog("[QuickTalk] Ollama 문맥 절약 — 검색 %d건·%d자로 축소(설정 %d건·%d자)",
                searchLimits.resultCount, searchLimits.maxCharacters,
                ws.webSearchResultCount, ws.webSearchMaxCharacters)
        }
        // 공통 메모리 — 이 대화에서 끄지 않았고 전역 설정이 켜져 있을 때만.
        // 대화 요약보다 **앞**에 둔다(변하지 않는 사용자 사실이 먼저 보이게).
        let globalMemory: GlobalMemoryPrompt = self.commonMemoryActive
          ? GlobalMemory.prompt(self.memoryEntries, query: prompt,
                                mode: ws.globalMemoryMode,
                                budget: ws.globalMemoryBudgetTokens)
          : .empty
        let conversationPrefix = Self.memoryPromptPrefix(session.conversation)
        // 비서 — 대화마다 고른 성격·말투를 **프롬프트 앞**에 붙인다.
        // 도구가 꺼진 일반 클라이언트에도 적용되도록 시스템 프롬프트가 아니라 여기에 둔다.
        let conversationPersona = self.settings.persona(session.conversation.personaID)
        let personaHeader = conversationPersona
          .map { PersonaPrompt.header($0) + "\n\n" } ?? ""
        // 비서가 자기 **쓰기 가능한 리포트 폴더**를 알아야 엉뚱한 곳을 뒤지지 않는다(v0.29).
        // 도구 경로든 일반 경로든 같은 블록이 프롬프트 앞에 들어간다.
        let reportFolderBlock = SystemKnowledge.reportFolderText(
          settings: ws, persona: conversationPersona) + "\n\n"
        let memoryPrefix = reportFolderBlock + personaHeader + globalMemory.text + conversationPrefix
        if !globalMemory.isEmpty {
          NSLog("[QuickTalk] 공통 메모리 %d개 주입 (약 %d토큰)",
                globalMemory.included.count, globalMemory.tokens)
        }
        let fitted = ConversationMemory.fitHistory(session.conversation,
                                                   prompt: prompt,
                                                   provider: provider,
                                                   attachmentTokens: attachmentTokens,
                                                   extraTokens: globalMemory.tokens
                                                     + (ws.webSearchEnabled ? 400 : 0))
        let history = fitted.history
        if fitted.dropped > 0 {
          self.compactMessage = Lf("모델 예산을 넘어 이전 메시지 %d개를 이번 요청에서 제외했습니다. 원문은 그대로 남아 있습니다.",
                                   fitted.dropped)
          NSLog("[QuickTalk] 예산 초과 — 이번 요청에서 이전 턴 %d개 제외", fitted.dropped)
        }
        // 검색 컨텍스트는 크기 제한이 없다(설정 2,000자 × 결과 수). 작은 컨텍스트 모델
        // (Apple FM 등)에서 기록을 모두 비워도 넘치지 않도록 입력 예산의 1/3로 자른다.
        func cappedSearchContext(_ text: String) -> String {
          guard !text.isEmpty else { return "" }
          let cap = WebSearchPromptLimits.contextCap(for: provider)
          guard ConversationMemory.estimateTokens(text) > cap else { return text }
          NSLog("[QuickTalk] 검색 컨텍스트가 커서 %d토큰으로 줄임", cap)
          return GlobalMemory.clip(text, toTokens: cap)
        }
        // ── 웹 검색 (PLAN_v0.14) — 답변 생성 **전에** 1회, 실패해도 답변은 계속한다 ──
        var modelPrompt = memoryPrefix + prompt
        var sources: [TurnSource] = []
        var searchNote: String?
        /// 실제로 프롬프트에 들어간 검색 컨텍스트 토큰 — 기록 예산을 정확히 다시 맞춘다.
        var searchContextTokens = 0
        // 검색 결과를 프롬프트에 넣는다 — `/answer` 폴백과 일반 검색이 **같은 규칙**을 쓰게 한 곳에 둔다.
        func applySearchResults(_ results: [SearchResult]) {
          guard !results.isEmpty else { return }
          let context = cappedSearchContext(WebSearchContext.build(
            results: results,
            maxCharacters: searchLimits.maxCharacters,
            limit: searchLimits.resultCount))
          searchContextTokens = ConversationMemory.estimateTokens(context)
          modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
          sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
        }
        /// 툴 콜링이 검색 없이 바로 답한 경우 — 두 번째 모델 호출을 건너뛴다.
        var precomputedAnswer: String?
        let forced = session.forceWebSearch
        session.forceWebSearch = false
        // 도구가 켜져 있으면 **웹 검색도 같은 루프**에서 모델이 직접 고른다(v0.23).
        // 사전 검색·Y/N 판정을 따로 돌리면 호출이 두 번 되고, 모델이 검색 없이 답하면
        // 그 답이 확정되어 셸·프로세스 도구를 쓸 기회가 사라진다.
        let usesAgentTools = self.canUseAgentTools(provider)
        let searchToolReady = self.webSearchToolAvailable
        // 사전 검색을 건너뛰어도 되는 경우 = **루프 안에서 검색할 수 있을 때**만.
        // Apple FM 은 web_search 를 등록하지 않으므로 사전 검색을 남긴다(안 그러면 검색을 잃는다).
        let skipPreSearch = WebSearchRouting.skipsPreSearch(
          agentTools: usesAgentTools, searchToolReady: searchToolReady,
          providerType: provider.type)

        // P3-a) 툴 콜링 — 모델이 `web_search`를 직접 호출한다. OpenAI 호환에서만 시도하고,
        // 프록시가 tools를 모르면(400) 아래 기존 주입 경로로 조용히 폴백한다.
        var handledByTool = false
        var toolFellBack = false
        if ws.webSearchEnabled, ws.webSearchMode == .toolCalling,
           provider.type == .openAICompatible, !forced, !skipPreSearch {
          session.isSearching = true
          let plan = await self.planWebToolCall(provider: provider,
                                                prompt: memoryPrefix + prompt,
                                                history: history,
                                                attachments: outgoing)
          session.isSearching = false
          switch plan {
          case .search(let results):
            handledByTool = true
            if results.isEmpty {
              searchNote = L("⚠️ 모델이 검색을 요청했지만 결과가 없습니다 — 모델 지식으로 답합니다.")
            } else {
              let context = cappedSearchContext(WebSearchContext.build(
                results: results,
                maxCharacters: searchLimits.maxCharacters,
                limit: searchLimits.resultCount))
              searchContextTokens = ConversationMemory.estimateTokens(context)
              modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
              sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
              NSLog("[QuickTalk] 툴 콜링 검색 %d건 → 프롬프트 주입", sources.count)
            }
          case .answer(let text):
            handledByTool = true
            precomputedAnswer = text
            NSLog("[QuickTalk] 툴 콜링 — 검색 없이 모델이 직접 답변 (%d자)", text.count)
          case .unsupported(let detail):
            toolFellBack = true
            searchNote = detail
            NSLog("[WARN] E-MAC-TOOL-0001 툴 콜링 미지원 → 주입 폴백")
          case .failed(let detail):
            handledByTool = true
            searchNote = detail
            NSLog("[WARN] %@ 툴 콜링 요청 실패 → 검색 없이 답변",
                  WebToolError.requestFailed.code)
          }
        }

        // P3-b) `/answer` 또는 기존 주입 — "필요할 때만"은 모델 Y/N 판정으로 정한다.
        // 🌐를 켠 질문은 판정을 건너뛰고 반드시 검색한다.
        var needsSearch = false
        // 🌐(이번 질문만)은 도구가 켜져 있어도 사용자의 명시적 의도라 그대로 존중한다.
        if !handledByTool, !skipPreSearch || forced {
          needsSearch = WebSearchQuery.shouldSearch(provider: ws.webSearchProvider, forced: forced)
          // 툴 콜링은 OpenAI 호환에서만 시도한다 — 다른 프로바이더에서는 주입 판정으로 폴백.
          let toolModeUnavailable = ws.webSearchMode == .toolCalling
            && provider.type != .openAICompatible
          if !needsSearch, ws.webSearchEnabled,
             (ws.webSearchMode != .toolCalling || toolFellBack || toolModeUnavailable) {
            needsSearch = await self.decidesToSearch(prompt, history: history)
          }
        }
        if !handledByTool, needsSearch {
          session.isSearching = true
          if ws.webSearchMode == .answer {
            // Exa `/answer` — 실패하면 같은 질문으로 일반 검색을 한 번 더 시도한다.
            let answered = await self.answerWeb(query: prompt)
            session.isSearching = false
            switch answered {
            case .success(let result):
              if result.isEmpty {
                searchNote = L("⚠️ 웹 답변 결과가 비어 있습니다 — 모델 지식으로 답합니다.")
              } else {
                let context = cappedSearchContext(ExaAnswer.context(result,
                                                                    limit: searchLimits.resultCount))
                searchContextTokens = ConversationMemory.estimateTokens(context)
                modelPrompt = memoryPrefix + context + "\n\n질문: " + prompt
                sources = result.sources
                NSLog("[QuickTalk] /answer 인용 %d건 → 프롬프트 주입", sources.count)
              }
            case .failure(let error):
              searchNote = error.userText
              NSLog("[ERROR] %@ /answer 실패 → 일반 검색 폴백", error.code)
              let fallback = await self.searchWeb(query: prompt)
              if case .success(let results) = fallback {
                applySearchResults(results)
              }
            }
          } else {
            let outcome = await self.searchWeb(query: prompt)
            session.isSearching = false
            switch outcome {
            case .success(let results):
              if results.isEmpty {
                searchNote = L("⚠️ 웹 검색 결과가 없습니다 — 모델 지식으로 답합니다.")
              } else {
                applySearchResults(results)
                NSLog("[QuickTalk] 웹 검색 %d건 → 프롬프트 주입", sources.count)
              }
            case .failure(let error):
              // 검색어·본문은 로그에 남기지 않는다(코드만)
              searchNote = error.userText
              NSLog("[ERROR] %@ 웹 검색 실패", error.code)
            }
          }
        }
        // 검색 중 사용자가 다른 대화방으로 옮겼으면 이 답변은 버린다(다른 방에 섞이지 않게).
        guard session.conversation.id == convID else { return }
        // 초기 400토큰 예약보다 검색 컨텍스트가 크면 기록을 다시 맞춘다.
        // (검색은 기록 fitting 뒤에 일어나므로 실제 컨텍스트 크기를 그때 알 수 있다.)
        var finalHistory = history
        if searchContextTokens > 400 {
          let refit = ConversationMemory.fitHistory(
            session.conversation, prompt: prompt, provider: provider,
            attachmentTokens: attachmentTokens,
            extraTokens: globalMemory.tokens + searchContextTokens)
          finalHistory = refit.history
          if refit.dropped > fitted.dropped {
            self.compactMessage = Lf("모델 예산을 넘어 이전 메시지 %d개를 이번 요청에서 제외했습니다. 원문은 그대로 남아 있습니다.",
                                     refit.dropped)
            NSLog("[QuickTalk] 검색 컨텍스트로 기록 %d개 추가 제외", refit.dropped - fitted.dropped)
          }
        }
        callStarted = Date()
        // 스트리밍 버블 — 첫 델타 전까지는 아래 점 애니메이션이 보인다
        if Task.isCancelled { return }     // 검색·판정 중에 [중지]를 누른 경우
        let aid = session.core.beginAssistantTurn()
        session.conversation = session.core.conversation
        session.streamingTurnID = aid
        // 사고 과정(thinking 모델) — 답변이 시작되기 전에도 화면이 "지금 고민 중"을 보여 준다.
        // 스텝(모델 호출)마다 새 구간으로 쌓는다 — 도구 카드 앞에 그 구간을 붙이고 비운다.
        // 완료되면 **마지막 구간**(최종 답변 직전의 사고)을 턴에 저장한다.
        session.liveReasoning = ""
        let appendReasoning: @MainActor (String) -> Void = { piece in
          guard session.conversation.id == convID else { return }
          var text = session.liveReasoning + piece
          if text.count > 24_000 { text = String(text.suffix(24_000)) }
          session.liveReasoning = text
        }
        /// 말풍선에서 **모델 답변 앞**에 붙는 안내(검색 경고·첨부 경고) — 재시도로 지우지 않는다.
        var answerPrefix = ""
        // 첨부 경고(줄임·미전송)는 델타보다 먼저 붙인다 — 기존 `reply`와 같은 순서
        if let searchNote {
          session.core.appendStreaming(searchNote + "\n\n", to: aid)
          session.conversation = session.core.conversation
          answerPrefix += searchNote + "\n\n"
        }
        let warnings = AttachmentLoader.warnings(outgoing)
        if !warnings.isEmpty {
          session.core.appendStreaming(warnings, to: aid)
          session.conversation = session.core.conversation
          answerPrefix += warnings
        }
        var buffer = ""
        /// 모델이 실제로 내보낸 답변만 따로 센다 — 재시도·이어쓰기의 기준점.
        var modelText = ""
        /// 에이전트 스텝 시작 시점의 답변 — 도구 호출 예고를 지울 때 되돌린다.
        var stepStartText = ""
        let retryPolicy = ws.networkRetryPolicy
        var lastFlush = Date.distantPast
        let flush: (Bool) -> Void = { force in
          guard force || Date().timeIntervalSince(lastFlush) >= 0.08 else { return }
          guard !buffer.isEmpty else { return }
          guard session.conversation.id == convID else { buffer = ""; return }
          session.core.appendStreaming(buffer, to: aid)
          buffer = ""
          lastFlush = Date()
          session.conversation = session.core.conversation
        }
        /// 재시도·이어쓰기 후 말풍선을 **중복 없는 답변**으로 다시 맞춘다.
        let replaceAnswer: (String) -> Void = { text in
          modelText = text
          buffer = ""
          guard session.conversation.id == convID else { return }
          session.core.setAssistantText(answerPrefix + text, id: aid)
          session.conversation = session.core.conversation
        }
        let showRetry: (NetworkRetryProgress?) -> Void = { progress in
          session.networkRetryStatus = progress.map { Self.retryStatusText($0) }
        }
        do {
          guard let p = self.settings.activeProvider else {
            throw QuickTalkError.providerNotConfigured()
          }
          let reply: String
          if let precomputedAnswer {
            // 툴 콜링이 검색 없이 답한 경우 — 그대로 표시한다(스트리밍 없음).
            reply = precomputedAnswer
            modelText = precomputedAnswer
            session.core.appendStreaming(precomputedAnswer, to: aid)
            session.conversation = session.core.conversation
          } else if let agentClient = self.makeAgentClientIfEnabled(provider: p,
                                                                    persona: conversationPersona,
                                                                    session: session) {
            // 도우미 도구 — **판정 없이** 도구를 넘기고, 본 모델이 직접 골라 실행한다.
            // 웹 검색도 **같은 루프**에 넣는다(v0.23) — 모델이 답을 모르면 `web_search` 를 고른다.
            // Apple FM 은 등록 도구가 shell/read_file/list_dir 뿐이라 넘겨도 쓰이지 않는다.
            // 컴퓨터 제어(ui_snapshot)는 마스터 토글이 켜져 있을 때만 목록에 넣는다.
            let agentTools = AgentToolCatalog.available(
              for: settings.persona(conversation.personaID),
              includingWebSearch: searchToolReady && p.type != .appleFM,
              includingUI: settings.uiControlEnabled && p.type != .appleFM,
              includingSchedule: true)
            do {
              reply = try await self.runAgentTurn(
                session: session,
                client: agentClient, prompt: modelPrompt,
                history: finalHistory, turnID: aid,
                tools: agentTools,
                attachments: outgoing,
                retry: retryPolicy,
                onDelta: { delta in
                  modelText += delta
                  buffer += delta
                  flush(false)
                },
                // 스텝 시작 시점을 기억했다가, 도구 호출 예고·재시도 실패분을 지운다.
                // 사고 과정도 스텝마다 새 구간 — 재시도한 실패 시도의 사고는 버린다.
                onReasoning: appendReasoning,
                onStepStart: { stepStartText = modelText; session.liveReasoning = "" },
                onStepDiscard: { replaceAnswer(stepStartText) },
                onRetry: { showRetry($0) })
              // 모델이 검색으로 확인한 출처가 있으면 답변에 남긴다.
              if !session.agentSearchSources.isEmpty { sources = session.agentSearchSources }
            } catch {
              // 도구를 모르는 서버(400 등)면 도구 없는 일반 경로로 되돌린다.
              // **아직 글자가 없을 때만** — 부분 답변이 있으면 그 답을 지키고 오류를 알린다.
              if modelText.isEmpty, WebToolError.isToolUnsupported(error) {
                NSLog("[QuickTalk] E-MAC-TOOL-0001 도구 미지원 → 일반 경로로 폴백")
                // 이 턴은 사전 검색을 건너뛰었으므로, 폴백에서 **검색을 잃지 않도록** 한 번 주입한다.
                var fallbackPrompt = modelPrompt
                if searchToolReady,
                   await self.decidesToSearch(prompt, history: finalHistory),
                   case .success(let results) = await self.searchWeb(query: prompt),
                   !results.isEmpty {
                  let context = cappedSearchContext(WebSearchContext.build(
                    results: results,
                    maxCharacters: searchLimits.maxCharacters,
                    limit: searchLimits.resultCount))
                  fallbackPrompt = memoryPrefix + context + "\n\n질문: " + prompt
                  sources = WebSearchContext.sources(from: results, limit: searchLimits.resultCount)
                }
                reply = try await Self.streamReplyResuming(
                  settings: self.settings, provider: p, prompt: fallbackPrompt,
                  history: finalHistory, attachments: outgoing, policy: retryPolicy,
                  onDelta: { delta in
                    modelText += delta
                    buffer += delta
                    flush(false)
                  },
                  onReplace: { replaceAnswer($0) },
                  onRetry: { showRetry($0) },
                  onReasoning: appendReasoning)
              } else {
                throw error
              }
            }
          } else {
            reply = try await Self.streamReplyResuming(
              settings: self.settings, provider: p, prompt: modelPrompt,
              history: finalHistory,
              attachments: outgoing,
              policy: retryPolicy,
              onDelta: { delta in
                modelText += delta
                buffer += delta
                flush(false)
              },
              onReplace: { replaceAnswer($0) },
              onRetry: { showRetry($0) },
              onReasoning: appendReasoning)
          }
          session.networkRetryStatus = nil
          flush(true)
          guard session.conversation.id == convID else { return }
          let current = session.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
          // 오류 문구는 표시 언어에 따라 "(오류 …)" 또는 "(Error …)"로 시작한다
          let isError = reply.hasPrefix("(오류") || reply.hasPrefix("(Error")
          if isError {
            // 재시도 사다리가 델타 대신 오류 문자열을 돌려준 경우
            session.core.setAssistantText(current.isEmpty ? reply : current + "\n\n" + reply, id: aid)
          } else if reply != modelText, !reply.isEmpty {
            // 에이전트가 스트리밍 없이 만든 최종 답(최대 스텝 안전망·재촉 답변)을 반영한다.
            // 예전에는 이미 글자가 있으면 이 값을 버려 "확인하겠습니다"가 답으로 남았다.
            session.core.setAssistantText(answerPrefix + reply, id: aid)
          } else if current.isEmpty {
            // 스트리밍을 지원하지 않는 경로(기본 구현) — 한 번에 채운다
            session.core.setAssistantText(answerPrefix + reply, id: aid)
          }
          session.core.finishAssistantTurn(aid, elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000),
                                        sources: sources.isEmpty ? nil : sources,
                                        reasoning: session.liveReasoning.isEmpty ? nil : session.liveReasoning)
          session.conversation = session.core.conversation
          session.liveReasoning = ""
          self.syncArchive(session)
          // 답변을 마친 뒤 **백그라운드로** 정리한다 — 현재 답변 지연을 만들지 않는다.
          if !isError {
            self.startAutoCompact(convID: convID, session: session)
            // v0.32 — 정상 종료된 답변에만 후속 질문 칩을 예약한다.
            let finalAnswer = session.conversation.turns
              .first(where: { $0.id == aid })?.text ?? ""
            self.scheduleFollowUps(session: session, assistantTurnID: aid,
                                   question: prompt, answer: finalAnswer)
          }
          self.lastAICall = isError ? .failed(Self.errorCode(in: reply)) : .ok
          self.lastAIErrorDetail = isError ? Self.errorSummary(in: reply) : nil
        } catch {
          session.networkRetryStatus = nil
          // 사용자가 [중지]를 누른 경우 — 오류가 아니다. 부분 출력은 남기고 안내만 덧붙인다.
          if Task.isCancelled || error is CancellationError
              || (error as? URLError)?.code == .cancelled {
            flush(true)
            let current = session.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
            if current.isEmpty {
              session.core.setAssistantText(L("응답을 중지했습니다."), id: aid)
            } else {
              session.core.appendStreaming(L("\n\n⏹ 중지됨"), to: aid)
            }
            session.core.finishAssistantTurn(aid,
                                          elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000),
                                          sources: sources.isEmpty ? nil : sources)
            session.conversation = session.core.conversation
            self.syncArchive(session)
            NSLog("[QuickTalk] 사용자 중지 — 응답 취소(부분 %d자)", current.count)
            return
          }
          // 실패는 코드 + **정확한 원인**으로 남긴다 — 연결 거부·시간 초과·오프라인·TLS가
          // 모두 NET-0001로 뭉개지지 않게(URLError 상세는 AIErrorText가 만든다).
          flush(true)
          let code = AIErrorText.code(for: error)
          let url = self.settings.activeProvider.flatMap { URL(string: $0.baseURL) }
          let text = AIErrorText.userText(for: error, url: url)
          NSLog("[ERROR] %@ LLM 호출 실패 — %@", code, AIErrorText.logLabel(for: error))
          let current = session.conversation.turns.first(where: { $0.id == aid })?.text ?? ""
          session.core.setAssistantText(current.isEmpty ? text : current + "\n\n" + text, id: aid)
          session.core.finishAssistantTurn(aid, elapsedMs: Int(Date().timeIntervalSince(callStarted) * 1000))
          session.conversation = session.core.conversation
          self.syncArchive(session)
          self.lastAICall = .failed(code)
          self.lastAIErrorDetail = AIErrorText.shortDetail(for: error)
          session.liveReasoning = ""
        }
      }
    } catch {
      // 사용자 [중지]로 취소된 경우는 오류가 아니다 — 조용히 끝낸다.
      if Task.isCancelled || error is CancellationError {
        print("[QuickTalk] 사용자 중지 — 전송 준비 취소")
        return
      }
      // [ERROR] E-MAC-MODEL-0001 + 메시지 매핑. 무음 실패 금지
      print("[ERROR] E-MAC-MODEL-0001 빈 제출 또는 첨부 오류: \(error)")
    }
  }

  /// 진행 중인 응답을 사용자가 중지한다.
  ///
  /// 로컬 Ollama는 첫 토큰까지 수 분 걸릴 수 있어(문맥 처리 30~90초 + 모델 로드) 300초 동안
  /// 입력독이 잠긴다. 그 사이 모델이 멈춘 것처럼 보여도 빠져나갈 수단이 없었다 — 이 버튼이 그 출구다.
  /// 부분 출력이 있으면 남기고, 없으면 "응답을 중지했습니다."만 남긴다(예비 모델로 넘어가지 않는다).
  func cancelReply() {
    guard isReplying else { return }
    NSLog("[QuickTalk] 사용자 중지 요청 — 진행 중인 응답 취소")
    clearFollowUps(for: activeSession)
    // 승인 대기 중이면 거부로 깨우고, 셸이 돌고 있으면 프로세스를 멈춘다(v0.20).
    let executor = agentExecutor
    Task { @MainActor in executor?.cancelPending() }
    replyTask?.cancel()
    replyTask = nil
    isReplying = false
    replyStartedAt = nil
    streamingTurnID = nil
    isSearching = false
    networkRetryStatus = nil
    liveReasoning = ""
  }

  // MARK: - 대화 기억 정리 (T-71)

  /// 요청에 실을 기록 — 요약 경계 이후의 원문만 남기고, 방금 추가된 사용자 턴은 뺀다.
  static func requestHistory(_ conversation: Conversation) -> [Turn] {
    ConversationMemory.requestHistory(conversation)
  }

  /// 요약을 프롬프트 앞에 고정한다 — Apple FM의 6턴 제한에 잘리지 않게.
  static func memoryPromptPrefix(_ conversation: Conversation) -> String {
    ConversationMemory.memoryPromptPrefix(conversation)
  }

  // MARK: - 공통 메모리 (PLAN_v0.16)

  /// 이 대화에서 공통 메모리를 쓰는가 — 전역 설정 + 대화별 토글.
  var commonMemoryActive: Bool {
    settings.globalMemoryEnabled && conversation.commonMemoryDisabled != true
  }

  /// 이 대화만 공통 메모리 주입을 끄거나 켠다.
  func setCommonMemory(enabledForConversation on: Bool) {
    core.setCommonMemoryDisabled(!on)
    conversation = core.conversation
    syncArchive()
  }

  /// 헤더의 공통 메모리 아이콘 — 상태에 따라 켜기/끄기.
  ///  · **전역 OFF** → 전역을 켠다(꺼진 뒤 헤더에서 되돌릴 수 있어야 한다)
  ///  · 전역 ON + 이 대화 OFF → 이 대화에서만 켠다
  ///  · 켜짐 → 이 대화에서만 끈다
  ///
  /// 예전엔 전역에서 꺼져 있으면 아이콘을 아예 숨겼다 → 끈 뒤 켤 방법이 헤더에
  /// 없어서 혼란스러웠다(2026-10-22 사용자 지적).
  func toggleCommonMemory() {
    if !settings.globalMemoryEnabled {
      settings.globalMemoryEnabled = true
      core.setCommonMemoryDisabled(false)
      conversation = core.conversation
      syncArchive()
      return
    }
    setCommonMemory(enabledForConversation: !commonMemoryActive)
  }

  /// 항목 추가·수정 — 같은 ID가 있으면 덮어쓰고 `updatedAt`을 갱신한다.
  func upsertMemory(_ entry: GlobalMemoryEntry) {
    var copy = entry
    copy.title = copy.title.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.content = copy.content.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.tags = GlobalMemoryEntry.normalizeTags(copy.tags.joined(separator: ","))
    copy.updatedAt = Date()
    if let i = memoryEntries.firstIndex(where: { $0.id == copy.id }) {
      memoryEntries[i] = copy
    } else {
      memoryEntries.append(copy)
    }
  }

  func deleteMemory(_ id: UUID) {
    memoryEntries.removeAll { $0.id == id }
  }

  func setMemoryEnabled(_ id: UUID, _ on: Bool) {
    guard let i = memoryEntries.firstIndex(where: { $0.id == id }) else { return }
    // 사용 여부는 내용이 아니므로 updatedAt을 바꾸지 않는다(임베딩 캐시 유지·정렬 안정).
    memoryEntries[i].enabled = on
  }

  /// 목록 순서 변경(위/아래) — 프롬프트에 들어가는 순서이기도 하다.
  func moveMemory(_ id: UUID, by offset: Int) {
    guard let i = memoryEntries.firstIndex(where: { $0.id == id }) else { return }
    let j = i + offset
    guard memoryEntries.indices.contains(j) else { return }
    memoryEntries.swapAt(i, j)
  }

  /// JSON 내보내기 — 사용자가 고른 경로에 원자적으로 쓴다.
  func exportMemory(to url: URL) {
    do {
      try GlobalMemoryFile.save(memoryEntries, to: url)
      memoryNotice = Lf("메모리 %d개를 내보냈습니다.", memoryEntries.count)
    } catch {
      memoryNotice = Lf("메모리 내보내기에 실패했습니다: %@", error.localizedDescription)
      NSLog("[ERROR] E-MAC-MEM-0002 공통 메모리 내보내기 실패")
    }
  }

  /// JSON 가져오기 — 같은 ID는 건너뛰고 새 항목만 추가한다.
  func importMemory(from url: URL) {
    do {
      let data = try Data(contentsOf: url)
      let imported = try GlobalMemoryFile.decode(data)
      let merged = GlobalMemoryFile.merge(memoryEntries, with: imported)
      memoryNotice = nil
      memoryEntries = merged.entries
      // didSet 저장이 실패하면 그 안내를 덮지 않는다.
      if memoryNotice == nil {
        memoryNotice = Lf("메모리 %d개를 가져왔습니다.", merged.added)
      }
    } catch {
      memoryNotice = Lf("메모리 가져오기에 실패했습니다: %@", error.localizedDescription)
      NSLog("[ERROR] E-MAC-MEM-0003 공통 메모리 가져오기 실패")
    }
  }

  @discardableResult
  private func saveMemory() -> Bool {
    guard !suppressMemorySave else { return true }
    do {
      try GlobalMemoryFile.save(memoryEntries)
      return true
    } catch {
      NSLog("[ERROR] E-MAC-MEM-0004 공통 메모리 저장 실패")
      memoryNotice = L("메모리를 저장하지 못했습니다.")
      return false
    }
  }

  /// QA 렌더 전용 — 저장 없이 메모리를 메모리에만 넣는다.
  func applyRenderOverride(memory entries: [GlobalMemoryEntry]) {
    suppressMemorySave = true
    memoryEntries = entries
    suppressMemorySave = false
  }

  /// Apple FM은 4K 예산이라 최근 원문을 4개까지만 남긴다(사용자 설정이 더 커도).
  private func effectiveKeepTurns(for provider: LLMProviderConfig) -> Int {
    let requested = max(2, settings.compactKeepTurns)
    return provider.type == .appleFM ? min(requested, 4) : requested
  }

  /// `/compact` — 임계치와 무관하게 지금 정리한다(전문가용 보조 명령).
  func compactNow() {
    // 답변 중에는 정리하지 않는다 — 스트리밍 중인 반쪽 답변을 요약에 넣지 않기 위해서다.
    guard !isCompacting, !isReplying else { return }
    if conversation.autoCompactPaused {
      core.resumeAutoCompact()
      conversation = core.conversation
    }
    runCompaction(conversation: conversation, manual: true)
  }

  /// 답변을 마친 뒤 호출 — 예산의 70%를 넘었을 때만 백그라운드로 정리한다.
  func startAutoCompact(convID: UUID, session: ChatSession? = nil) {
    guard settings.autoCompact, !isCompacting else { return }
    let s = session ?? activeSession
    guard s.id == convID, !s.conversation.autoCompactPaused else { return }
    guard let provider = settings.activeProvider else { return }
    let keep = effectiveKeepTurns(for: provider)
    guard ConversationMemory.shouldCompact(s.conversation, provider: provider, keepTurns: keep) else {
      return
    }
    runCompaction(conversation: s.conversation, manual: false, session: s)
  }

  /// 정리 실행 — 원문은 그대로 두고 `summary`만 갱신한다(실패하면 아무것도 바꾸지 않는다).
  private func runCompaction(conversation target: Conversation, manual: Bool,
                             session: ChatSession? = nil) {
    guard let provider = settings.activeProvider else {
      if manual { compactMessage = L("활성 AI가 없습니다. 설정 > AI에서 프로바이더를 켜 주세요.") }
      return
    }
    let keep = effectiveKeepTurns(for: provider)
    let boundary = ConversationMemory.boundaryIndex(turnCount: target.turns.count, keepTurns: keep)
    guard boundary >= 2 else {
      if manual { compactMessage = L("정리할 이전 대화가 없습니다.") }
      return
    }
    let previousBoundary = target.summaryBoundaryIndex
    let start = previousBoundary.map { $0 + 1 } ?? 0
    guard start < boundary else {
      if manual { compactMessage = L("이미 최근 대화까지 정리되어 있습니다.") }
      return
    }
    let oldTurns = Array(target.turns[start..<boundary])
    let through = target.turns[boundary - 1].id
    let previous = target.activeSummary
    let convID = target.id
    let s = session ?? activeSession
    isCompacting = true
    compactingConversationID = convID
    compactMessage = nil
    Task { @MainActor in
      defer {
        self.isCompacting = false
        self.compactingConversationID = nil
      }
      do {
        let summary = try await Self.makeSummary(provider: provider, previous: previous, turns: oldTurns)
        // 그 사이 사용자가 요약을 해제했으면 적용하지 않는다(다른 방에 섞이지 않게).
        guard s.id == convID,
              !s.conversation.autoCompactPaused,
              s.conversation.turns.contains(where: { $0.id == through }) else { return }
        s.core.applySummary(summary, through: through)
        s.conversation = s.core.conversation
        self.syncArchive(s)
        NSLog("[QuickTalk] 대화 정리 — %d턴 → 요약 %d자 (%@)",
              oldTurns.count, summary.count, provider.type.rawValue)
      } catch {
        let code = AIErrorText.code(for: error)
        NSLog("[ERROR] %@ 대화 정리 실패", code)
        if manual { self.compactMessage = Lf("대화 정리에 실패했습니다 (%@)", code) }
      }
    }
  }

  /// 요약 생성 — 긴 기록은 청크로 나눠 **기존 요약 + 다음 부분**을 반복 갱신한다(롤링 요약).
  /// Apple FM은 4K 컨텍스트라 작은 청크, 원격·Ollama는 큰 청크를 쓴다.
  nonisolated static func makeSummary(provider: LLMProviderConfig,
                                      previous: String?,
                                      turns: [Turn]) async throws -> String {
    guard !turns.isEmpty else {
      throw QuickTalkError.detailed(L("정리할 대화가 없습니다."), code: "E-MAC-MEM-0001")
    }
    let limit = ConversationMemory.summaryLimit(for: provider)
    let chunkLimit = ConversationMemory.chunkLimit(for: provider)
    let full = ConversationMemory.transcript(turns)
    let pieces = ConversationMemory.chunks(full, maxCharacters: chunkLimit)
    guard !pieces.isEmpty else {
      throw QuickTalkError.detailed(L("대화 요약을 만들지 못했습니다."), code: "E-MAC-MEM-0001")
    }
    var summary = previous
    for piece in pieces {
      let prompt = ConversationMemory.summaryPrompt(previous: summary, transcript: piece,
                                                    maxCharacters: limit)
      let raw = try await UIStore.reply(provider: provider, prompt: prompt, history: [])
      guard let clipped = ConversationMemory.clipSummary(raw, maxCharacters: limit) else {
        throw QuickTalkError.detailed(L("대화 요약이 비어 있습니다."), code: "E-MAC-MEM-0001")
      }
      summary = clipped
    }
    guard let summary, !summary.isEmpty else {
      throw QuickTalkError.detailed(L("대화 요약을 만들지 못했습니다."), code: "E-MAC-MEM-0001")
    }
    return summary
  }

  /// 요약 본문을 직접 편집한다 — 경계와 자동 정리 상태는 유지한다.
  func updateConversationSummary(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      compactMessage = L("요약을 비워 둘 수 없습니다. 지우려면 [요약 해제]를 누르세요.")
      return
    }
    guard conversation.summary != nil else { return }
    core.replaceSummary(trimmed)
    conversation = core.conversation
    syncArchive()
    compactMessage = nil
    NSLog("[QuickTalk] 대화 요약 직접 편집 — %d자", trimmed.count)
  }

  /// 요약 해제 — 사용자가 명시적으로 해제했으므로 자동 정리를 멈춘다.
  func clearConversationMemory() {
    core.clearSummary(pauseAuto: true)
    conversation = core.conversation
    syncArchive()
    compactMessage = nil
    NSLog("[QuickTalk] 대화 요약 해제 — 자동 정리 일시 중지")
  }

  /// 자동 정리 다시 켜기 — 바로 예산을 넘었으면 백그라운드로 정리한다.
  func resumeAutoCompact() {
    core.resumeAutoCompact()
    conversation = core.conversation
    syncArchive()
    // 답변 중이면 끝난 뒤 다음 턴에서 자동으로 판단한다(반쪽 답변을 요약하지 않음).
    if !isReplying { startAutoCompact(convID: conversation.id) }
  }

  // MARK: - 웹 검색 실행 (PLAN_v0.14)

  /// Exa 키가 저장되어 있는가(키 값 자체는 읽지 않고 존재만 확인)
  var webSearchKeyReady: Bool { SecretStore.has(account: settings.exaSecretID) }

  /// 오늘 보낸 네트워크 검색 횟수(캐시 적중 제외).
  var webSearchUsageToday: Int {
    WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                             count: settings.webSearchUsageCount)
  }

  /// 검색 1회 — 캐시(10분) 우선. 실패는 `WebSearchError`로만 돌려준다(답변은 계속).
  /// Exa 검색 1회 — **메인 액터에서만** 돈다.
  ///
  /// `settings`(사용량 카운터)를 갱신하는데, 이 함수가 비격리 async로 돌면 `await` 뒤
  /// 협력 스레드에서 재개되어 **Published 값을 메인 밖에서 바꾼다**. 그러면 SwiftUI가 그 스레드에서
  /// 뷰를 갱신하고, AppKit 입력창이 창 드래그 영역을 건드리며
  /// `NSWindow drag regions should only be invalidated on the Main Thread!` 예외로 **앱이 죽는다**
  /// (2026-10-21 실사용 크래시: 첨부 있는 질문 수정 → 전송 → SIGABRT).
  @MainActor
  func searchWeb(query: String, useCache: Bool = true) async -> Result<[SearchResult], WebSearchError> {
    let s = settings
    guard s.webSearchProvider == .exa else { return .failure(.missingKey) }
    guard let key = SecretStore.load(account: s.exaSecretID), !key.isEmpty else {
      return .failure(.missingKey)
    }
    // 날짜가 바뀌었으면 카운터를 리셋한다(로컬 시간 기준).
    let today = WebSearchQuota.dayKey()
    if s.webSearchUsageDay != today {
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = 0
    }
    let keyStr = SearchCache.key(provider: s.webSearchProvider, query: query,
                                 freshness: s.webSearchFreshness,
                                 count: s.webSearchResultCount,
                                 maxCharacters: s.webSearchMaxCharacters)
    // 캐시 적중은 네트워크 호출이 아니므로 한도보다 **먼저** 확인한다.
    // (한도 도달 후에도 이미 받은 결과는 쓸 수 있어야 한다.)
    if useCache, let hit = searchCache.get(keyStr) { return .success(hit) }
    let used = WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                                        count: settings.webSearchUsageCount)
    if WebSearchQuota.limitReached(limit: s.webSearchDailyLimit, used: used) {
      NSLog("[QuickTalk] 웹 검색 일일 한도 도달 — %d/%d", used, s.webSearchDailyLimit)
      return .failure(.dailyLimit)
    }
    do {
      let results = try await ExaSearchClient(apiKey: key)
        .search(query: query,
                count: s.webSearchResultCount,
                freshness: s.webSearchFreshness,
                maxCharacters: s.webSearchMaxCharacters)
      if !results.isEmpty { searchCache.put(results, key: keyStr) }
      // HTTP 응답을 받은 검색은 결과 0건이어도 비용이 발생할 수 있으므로 센다.
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = used + 1
      return .success(results)
    } catch let error as WebSearchError {
      return .failure(error)
    } catch {
      return .failure(.network(AIErrorText.shortDetail(for: error)))
    }
  }

  /// Exa `/answer` 1회 — 검색+요약+인용을 한 번에. 실패는 `WebSearchError`로 돌려준다.
  /// 일반 검색과 같은 일일 한도를 공유한다(네트워크 호출 1회 = 카운트 1).
  /// 같은 질문은 10분 캐시를 먼저 확인한다(한도·지연 절약).
  /// `searchWeb`과 같은 이유로 **메인 액터 고정**(설정 카운터를 안전하게 갱신).
  @MainActor
  func answerWeb(query: String, useCache: Bool = true) async -> Result<ExaAnswerResult, WebSearchError> {
    let s = settings
    guard s.webSearchProvider == .exa else { return .failure(.missingKey) }
    guard let key = SecretStore.load(account: s.exaSecretID), !key.isEmpty else {
      return .failure(.missingKey)
    }
    let today = WebSearchQuota.dayKey()
    if s.webSearchUsageDay != today {
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = 0
    }
    let keyStr = ExaAnswerCache.key(query: query)
    if useCache, let hit = answerCache.get(keyStr) { return .success(hit) }
    let used = WebSearchQuota.usedToday(day: settings.webSearchUsageDay,
                                        count: settings.webSearchUsageCount)
    if WebSearchQuota.limitReached(limit: s.webSearchDailyLimit, used: used) {
      return .failure(.dailyLimit)
    }
    do {
      let result = try await ExaAnswerClient(apiKey: key).answer(query: query)
      answerCache.put(result, for: keyStr)
      settings.webSearchUsageDay = today
      settings.webSearchUsageCount = used + 1
      return .success(result)
    } catch let error as WebSearchError {
      return .failure(error)
    } catch {
      return .failure(.network(AIErrorText.shortDetail(for: error)))
    }
  }

  /// 툴 콜링 1왕복 — 모델이 `web_search`를 호출하면 검색을 실행해 결과를 돌려준다.
  /// 호출이 없으면 모델이 바로 답한 것으로 보고 그 본문을 쓴다.
  enum WebToolPlan {
    case search([SearchResult])
    case answer(String)
    /// tools 미지원(4xx) — 기존 주입 경로로 폴백한다.
    case unsupported(String)
    /// 네트워크·인증·5xx — 두 번째 모델 호출을 하지 않고 검색 없이 답한다.
    case failed(String)
  }

  func planWebToolCall(provider: LLMProviderConfig,
                               prompt: String,
                               history: [Turn],
                               attachments: [OutgoingAttachment]) async -> WebToolPlan {
    guard provider.type == .openAICompatible, !provider.model.isEmpty else {
      return .unsupported(L("⚠️ 툴 콜링은 OpenAI 호환 프로바이더에서만 동작합니다."))
    }
    // 검색 키가 없으면 모델을 한 번 더 부르지 않는다(호출 후 빈 결과가 되는 것 방지).
    guard settings.webSearchEnabled, webSearchKeyReady else {
      return .failed(L("⚠️ Exa 키가 없어 웹 검색을 건너뜁니다."))
    }
    guard !provider.secretID.isEmpty,
          let key = SecretStore.load(account: provider.secretID), !key.isEmpty else {
      return .failed(L("⚠️ API 키가 없어 툴 콜링을 건너뜁니다."))
    }
    guard let base = URL(string: provider.baseURL) else {
      return .failed(L("⚠️ 주소가 올바르지 않아 툴 콜링을 건너뜁니다."))
    }
    let client = OpenAIClient(baseURL: base, apiKey: key, model: provider.model)
    let messages = OpenAIClient.buildMessages(prompt: prompt, history: history,
                                              attachments: attachments)
    do {
      let response = try await client.completion(messages: messages,
                                                 tools: WebSearchTool.schema)
      let calls = response.calls
        .filter { $0.name == WebSearchTool.name && $0.query != nil }
        .prefix(WebSearchTool.maxCallsPerTurn)
      if calls.isEmpty {
        let text = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? .search([]) : .answer(text)
      }
      var results: [SearchResult] = []
      var seenURLs = Set<String>()
      var seenQueries = Set<String>()
      for call in calls {
        guard let query = call.query else { continue }
        // 같은 검색어를 여러 번 호출한 모델도 네트워크/쿼터를 중복 사용하지 않는다.
        let queryKey = query.lowercased()
          .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        guard seenQueries.insert(queryKey).inserted else { continue }
        let outcome = await searchWeb(query: query)
        guard case .success(let found) = outcome else { continue }
        for r in found where seenURLs.insert(r.url.lowercased()).inserted {
          results.append(r)
        }
      }
      return .search(Array(results.prefix(max(1, settings.webSearchResultCount))))
    } catch {
      if error is WebToolError || WebToolError.isToolUnsupported(error) {
        // tools 미지원(400/404/422) 또는 해석 불가 응답 — 기존 주입 방식으로 폴백한다.
        return .unsupported(L("⚠️ 툴 콜링을 사용할 수 없어 검색 결과 주입으로 전환했습니다."))
      }
      // 인증·한도·5xx·네트워크 — 폴백해도 같은 실패가 반복되므로 검색 없이 답한다.
      return .failed(Lf("⚠️ 툴 콜링 요청이 실패해 검색 없이 답합니다 (%@)",
                        AIErrorText.code(for: error)))
    }
  }

  /// QA 헤드리스 — 툴 콜링 1왕복. 결과 건수/답변 여부만 돌려준다(질문·본문 로그 금지).
  func toolCallingSelfTest(query: String) async -> String {
    guard let provider = settings.activeProvider else { return "FAIL no-provider" }
    let plan = await planWebToolCall(provider: provider, prompt: query,
                                     history: [], attachments: [])
    switch plan {
    case .search(let results): return "OK search results=\(results.count)"
    case .answer(let text): return "OK answer chars=\(text.count)"
    case .unsupported: return "FALLBACK unsupported"
    case .failed(let detail): return "FAIL \(detail)"
    }
  }

  /// 설정 › AI의 [답변 API 테스트] — 본문·키·검색어는 로그에 남기지 않는다.
  func testExaAnswer() {
    guard !answerTesting else { return }
    answerTesting = true
    answerTestResult = ""
    Task { @MainActor in
      let started = Date()
      let outcome = await self.answerWeb(query: "오늘 뉴스", useCache: false)
      self.answerTesting = false
      switch outcome {
      case .success(let result):
        let secs = Date().timeIntervalSince(started)
        self.answerTestResult = Lf("답변 %d자 · 인용 %d건 · %.1f초",
                                   result.answer.count, result.sources.count, secs)
      case .failure(let error):
        self.answerTestResult = error.userText
      }
    }
  }

  /// "필요할 때만" 자동 판정 — 활성 모델에게 **검색 필요 여부만** 짧게 묻는다.
  /// 질문 문구의 키워드 목록으로 추측하지 않는다(사용자가 든 예시가 규칙이 되지 않게).
  /// 실패·시간 초과면 검색하지 않는다 — 답변 지연·비용을 늘리지 않는 쪽을 택한다.
  func decidesToSearch(_ prompt: String, history: [Turn] = []) async -> Bool {
    guard let provider = settings.activeProvider else { return false }
    let previous = history.last(where: { $0.role == .user })?.text
    let key = Self.searchDecisionKey(providerID: provider.id,
                                     previous: previous,
                                     prompt: prompt)
    if let hit = searchDecisionCache[key],
       Date().timeIntervalSince(hit.at) < searchDecisionTTL {
      NSLog("[QuickTalk] 검색 필요 판정 캐시 %@", hit.needed ? "YES" : "NO")
      return hit.needed
    }
    let question = WebSearchQuery.classifierPrompt(question: prompt,
                                                   previousQuestion: previous)
    let started = Date()
    // 타임아웃은 프로바이더별 — 온디바이스 5초, 원격 8초, Ollama 20초(콜드 로드까지, Core 주석 참조)
    let timeout = WebSearchQuery.classifierTimeout(for: provider.type)
    // 일시 오류(429·5xx·네트워크)는 **1회 재시도**한다. 빨리 실패하므로 추가 지연이 작고,
    // 실패를 곧 "검색 안 함"으로 굳히면 최신 정보가 필요한 질문이 조용히 검색 없이 답해진다.
    // 시간 초과는 이미 오래 기다린 것이라 재시도하지 않는다.
    var attempt = 1
    while true {
      do {
        let answer = try await Self.classifierAnswer(provider: provider, prompt: question,
                                                     timeout: timeout)
        let needed = WebSearchQuery.parseNeed(answer)
        rememberSearchDecision(needed, key: key)
        NSLog("[QuickTalk] 검색 필요 판정 %@ (%dms, 시도 %d)", needed ? "YES" : "NO",
              Int(Date().timeIntervalSince(started) * 1000), attempt)
        return needed
      } catch {
        // 원인을 구분해 남긴다 — 시간 초과(E-MAC-SEARCH-0004)와 프로바이더 오류(네트워크·인증·5xx)는 대응이 다르다
        let code = AIErrorText.code(for: error)
        if attempt < 2, WebSearchQuery.classifierRetryAllowed(after: code) {
          NSLog("[QuickTalk] 검색 필요 판정 일시 오류(%@) → 1회 재시도 (%dms)",
                code, Int(Date().timeIntervalSince(started) * 1000))
          // 429 직후 즉시 재시도하면 같은 제한에 걸리기 쉬워 아주 짧게 쉰다.
          try? await Task.sleep(nanoseconds: 400_000_000)
          attempt += 1
          continue
        }
        NSLog("[QuickTalk] 검색 필요 판정 실패 → 검색 안 함 (제한 %.0f초, %dms, code=%@, 시도 %d)",
              timeout, Int(Date().timeIntervalSince(started) * 1000), code, attempt)
        return false
      }
    }
  }

  /// 판정 캐시 키 — 모델·직전 질문·현재 질문. 대소문자/공백만 정규화한다.
  static func searchDecisionKey(providerID: String, previous: String?, prompt: String) -> String {
    let norm: (String) -> String = { s in
      s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    return "\(providerID)|\(norm(previous ?? ""))|\(norm(prompt))"
  }

  private func rememberSearchDecision(_ needed: Bool, key: String) {
    if searchDecisionCache.count >= 50 { searchDecisionCache.removeAll() }
    searchDecisionCache[key] = (needed, Date())
  }

  /// 분류용 짧은 호출 — `timeout`초를 넘기면 취소하고 nil(검색 안 함)로 처리한다.
  static func classifierAnswer(provider: LLMProviderConfig,
                                       prompt: String,
                                       timeout: TimeInterval) async throws -> String {
    try await withThrowingTaskGroup(of: String?.self) { group in
      group.addTask {
        try await UIStore.reply(provider: provider, prompt: prompt, history: [])
      }
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        return nil
      }
      let first = try await group.next() ?? nil
      group.cancelAll()
      guard let answer = first else {
        throw QuickTalkError.detailed(L("검색 필요 여부 판정 시간 초과"),
                                      code: "E-MAC-SEARCH-0004")
      }
      return answer
    }
  }

  /// 설정 › AI의 [검색 테스트] — 건수·지연만 표시한다(본문·키·검색어 로그 금지).
  func testWebSearch() {
    guard !webSearchTesting else { return }
    webSearchTesting = true
    webSearchTestResult = ""
    Task { @MainActor in
      let started = Date()
      let outcome = await self.searchWeb(query: "오늘 뉴스", useCache: false)
      self.webSearchTesting = false
      switch outcome {
      case .success(let results):
        let secs = Date().timeIntervalSince(started)
        self.webSearchTestResult = results.isEmpty
          ? L("응답은 왔지만 결과가 0건입니다.")
          : Lf("검색 %d건 · %.1f초", results.count, secs)
      case .failure(let error):
        self.webSearchTestResult = error.userText
      }
    }
  }

  /// 검색 캐시 비우기 — 같은 질문을 다시 검색하고 싶을 때
  func clearWebSearchCache() {
    searchCache.clear()
    answerCache.clear()
    webSearchTestResult = L("검색·답변 캐시를 비웠습니다.")
  }

  /// 전송 직후 같은 텍스트가 다시 들어오면(IME 조합 커밋 에코) 무시하고 입력창을 비운다.
  /// 사용자가 곧바로 다른 내용을 입력하기 시작하면 즉시 중단한다.
  private func suppressEcho(of text: String) {
    guard !text.isEmpty else { return }
    Task { @MainActor in
      for _ in 0..<25 {                       // 약 0.5초
        try? await Task.sleep(nanoseconds: 20_000_000)
        if draft == text { draft = "" }
        else if !draft.isEmpty { return }      // 새 입력이 들어오면 중단
      }
    }
  }

  /// 폴백 안내 한 줄 — 화면·데모 렌더가 **같은 문구**를 쓰도록 한 곳에 둔다.
  static func fallbackNote(primaryName: String, fallbackName: String, error: Error) -> String {
    Lf("⚠️ 주 모델(%@)이 응답하지 않아 예비 모델(%@)로 답했습니다 — %@\n\n",
       primaryName, fallbackName, ProviderFallback.reason(for: error))
  }

  /// 재시도 배너 문구 — 설정 연동(초·횟수)을 사용자에게 그대로 보여 준다.
  static func retryStatusText(_ progress: NetworkRetryProgress) -> String {
    Lf("연결 끊김 — %d초 후 다시 연결합니다 (%d/%d)",
       progress.waitSeconds, progress.attempt, progress.maxAttempts)
  }

  /// 스트리밍 + **연결 끊김 대기·이어쓰기** (v0.29).
  ///
  /// - 첫 글자 전에 끊기면 같은 요청을 다시 보낸다.
  /// - 글자가 나온 뒤 끊기면 **이미 쓴 부분을 보존**하고 "이어서 쓰기" 요청을 보낸다.
  ///   돌아온 글은 겹치는 경계를 지워 합친다(`NetworkRetry.mergeContinuation`).
  /// - `policy` 횟수를 모두 쓰면 마지막 오류를 그대로 던진다(부분 답변은 호출부가 남긴다).
  ///
  /// `onReplace` 는 말풍선을 **중복 없는 현재 답변**으로 다시 맞출 때 부른다.
  @MainActor
  static func streamReplyResuming(settings: QuickTalkSettings,
                                  provider: LLMProviderConfig,
                                  prompt: String,
                                  history: [Turn],
                                  attachments: [OutgoingAttachment],
                                  policy: NetworkRetryPolicy,
                                  onDelta: @escaping @MainActor (String) -> Void,
                                  onReplace: @escaping @MainActor (String) -> Void,
                                  onRetry: @escaping @MainActor (NetworkRetryProgress?) -> Void,
                                  onReasoning: @escaping @MainActor (String) -> Void = { _ in })
    async throws -> String {
    var answer = ""
    var failures = 0
    while true {
      var attempt = ""
      do {
        let request = answer.isEmpty
          ? prompt
          : NetworkRetry.continuationPrompt(original: prompt, partial: answer)
        let text = try await streamReplyWithFallback(
          settings: settings, provider: provider, prompt: request,
          history: history, attachments: attachments,
          allowFallback: answer.isEmpty,
          onDelta: { delta in
            attempt += delta
            onDelta(delta)
          },
          onReasoning: onReasoning)
        answer = NetworkRetry.mergeContinuation(answer, text.isEmpty ? attempt : text)
        onRetry(nil)
        onReplace(answer)
        return answer
      } catch {
        if Task.isCancelled || error is CancellationError { throw error }
        // 실패한 시도에서 이미 받은 글자는 버리지 않는다.
        if !attempt.isEmpty {
          answer = NetworkRetry.mergeContinuation(answer, attempt)
          onReplace(answer)
        }
        guard policy.canRetry(afterFailures: failures),
              NetworkRetry.isRetryable(error) else {
          onRetry(nil)
          throw error
        }
        failures += 1
        let progress = NetworkRetryProgress(attempt: failures,
                                            maxAttempts: policy.maxAttempts,
                                            waitSeconds: policy.intervalSeconds)
        onRetry(progress)
        NSLog("[QuickTalk] 연결 끊김 — %d/%d회, %d초 후 %@",
              failures, policy.maxAttempts, policy.intervalSeconds,
              answer.isEmpty ? "같은 요청 재전송" : "이어쓰기")
        do {
          try await Task.sleep(nanoseconds: UInt64(policy.interval * 1_000_000_000))
        } catch {
          onRetry(nil)
          throw error
        }
        onRetry(nil)
      }
    }
  }

  /// 주 모델 → (일시 오류면) **예비 모델 1회**. 이미 글자가 화면에 나간 뒤에는 전환하지 않는다.
  /// 예비 모델의 첫 글자가 올 때 안내를 붙인다 — 예비도 실패하면 안내만 남지 않게.
  ///
  /// - `allowFallback`: false 면 예비 모델로 넘어가지 않는다. **부분 답변이 이미 있는**
  ///   재시도 경로에서 다른 모델의 답이 겹치는 것을 막는다.
  @MainActor
  static func streamReplyWithFallback(settings: QuickTalkSettings,
                                      provider primary: LLMProviderConfig,
                                      prompt: String,
                                      history: [Turn],
                                      attachments: [OutgoingAttachment],
                                      allowFallback: Bool = true,
                                      onDelta: @escaping @MainActor (String) -> Void,
                                      onReasoning: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
    do {
      return try await streamReply(provider: primary, prompt: prompt, history: history,
                                   attachments: attachments, onDelta: onDelta,
                                   onReasoning: onReasoning)
    } catch {
      let primaryError = error
      let primaryCode = AIErrorText.code(for: primaryError)
      guard allowFallback, let fb = settings.fallbackProvider,
            ProviderFallback.isUsable(fb, keyExists: { SecretStore.has(account: $0) }),
            ProviderFallback.allowed(after: primaryError) else { throw primaryError }
      NSLog("[WARN] E-MAC-FALLBACK-0001 주 모델 실패(%@) → 예비 모델 1회 시도", primaryCode)
      let note = fallbackNote(primaryName: primary.displayName,
                              fallbackName: fb.displayName,
                              error: primaryError)
      // 예비 모델은 예산이 더 작을 수 있다(원격 → Apple FM). 그 예산에 맞춰 오래된 턴을 덜어낸다.
      let fitted = Conversation(turns: history)
      let fallbackHistory = ConversationMemory.fitHistory(fitted, prompt: prompt,
                                                          provider: fb).history
      // 첫 델타에서 안내를 내보내기 위한 플래그(동시성 경고 없이 값 전달).
      final class Announced { var value = false }
      let announced = Announced()
      do {
        let text = try await streamReply(
          provider: fb, prompt: prompt, history: fallbackHistory, attachments: attachments,
          onDelta: { delta in
            if !announced.value {
              announced.value = true
              onDelta(note)
            }
            onDelta(delta)
          },
          onReasoning: onReasoning)
        // 델타를 한 번도 내보내지 않는 클라이언트도 안내를 잃지 않게 반환값에도 붙인다
        // (스트리밍 경로에서는 화면 텍스트와 같은 값이 된다).
        return note + text
      } catch let fallbackError {
        NSLog("[ERROR] E-MAC-FALLBACK-0002 예비 모델도 실패 — %@",
              AIErrorText.logLabel(for: fallbackError))
        throw QuickTalkError.detailed(
          Lf("주 모델(%@) 실패(%@) 후 예비 모델(%@)도 실패했습니다 — %@",
             primary.displayName, primaryCode, fb.displayName,
             ProviderFallback.reason(for: fallbackError)),
          code: AIErrorText.code(for: fallbackError))
      }
    }
  }

  /// 스트리밍 응답 — 활성 AI·모델 1건. 델타는 메인 액터에서 **도착 순서대로** 온다.
  /// OpenAI 호환=SSE, Ollama=NDJSON, Apple FM=한 번에(FoundationModels 스트리밍 미사용).
  @MainActor
  static func streamReply(provider p: LLMProviderConfig, prompt: String, history: [Turn],
                          attachments: [OutgoingAttachment],
                          onDelta: @escaping @MainActor (String) -> Void,
                          onReasoning: @escaping @MainActor (String) -> Void = { _ in }) async throws -> String {
    switch p.type {
    case .appleFM:
      let skipped = attachments.filter { $0.hasImage }
      let answer = try await appleFMReply(prompt: prompt, history: history, attachments: attachments)
      if !skipped.isEmpty {
        onDelta(Lf("⚠️ Apple FM은 이미지를 받지 못해 %d건을 빼고 보냈습니다.\n\n", skipped.count))
      }
      onDelta(answer)
      return answer
    case .ollama:
      guard !p.model.isEmpty else {
        throw QuickTalkError.detailed(L("모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요."),
                                      code: "E-MAC-NET-0002")
      }
      guard let host = URL(string: p.baseURL) else {
        throw QuickTalkError.detailed(Lf("호스트 주소가 올바르지 않습니다: %@", p.baseURL),
                                      code: "E-MAC-NET-0002")
      }
      return try await AttachmentRetry.stream(client: OllamaClient(host: host, model: p.model),
                                              prompt: prompt, history: history,
                                              attachments: attachments, model: p.model,
                                              onDelta: onDelta, onReasoning: onReasoning)
    case .openAICompatible:
      guard !p.model.isEmpty else {
        throw QuickTalkError.detailed(L("모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요."),
                                      code: "E-MAC-NET-0002")
      }
      guard !p.secretID.isEmpty,
            let key = SecretStore.load(account: p.secretID), !key.isEmpty else {
        throw QuickTalkError.detailed(L("API 키가 없습니다. 설정 > AI에서 키를 저장해 주세요."),
                                      code: "E-MAC-KEY-0001")
      }
      guard let base = URL(string: p.baseURL) else {
        throw QuickTalkError.detailed(Lf("주소가 올바르지 않습니다: %@", p.baseURL),
                                      code: "E-MAC-NET-0002")
      }
      return try await AttachmentRetry.stream(client: OpenAIClient(baseURL: base, apiKey: key, model: p.model),
                                              prompt: prompt, history: history,
                                              attachments: attachments, model: p.model,
                                              onDelta: onDelta, onReasoning: onReasoning)
    }
  }

  /// 첨부 파일 본문 읽기 — 무거운 작업(파일 IO·이미지 base64)은 메인 밖에서 한다.
  nonisolated static func loadAttachments(_ pending: [PendingAttachment]) async -> [OutgoingAttachment] {
    guard !pending.isEmpty else { return [] }
    let items = pending.map { (name: $0.name, kind: $0.kind, url: $0.url) }
    return await Task.detached(priority: .userInitiated) {
      items.map { AttachmentLoader.load(name: $0.name, kind: $0.kind, url: $0.url) }
    }.value
  }

  /// 키가 필요 없는 프로바이더 ID — 원격 키 미저장 시 폴백 대상
  private static func keylessFallbackID(in s: QuickTalkSettings) -> String? {
    if let fm = s.providers.first(where: { $0.id == LLMProviderConfig.appleFMID && $0.enabled }) {
      return fm.id
    }
    return s.providers.first { $0.enabled && $0.type != .openAICompatible }?.id
      ?? s.providers.first { $0.enabled }?.id
  }

  /// 프로바이더 1건으로 응답 수신 (설정 UI의 "테스트" 버튼에서도 재사용).
  /// 실패는 목업으로 숨기지 않고 에러코드 문구로 반환한다.
  static func reply(provider p: LLMProviderConfig,
                    prompt: String,
                    history: [Turn],
                    attachments: [OutgoingAttachment] = []) async throws -> String {
    let answer = try await replyRaw(provider: p, prompt: prompt, history: history, attachments: attachments)
    // 줄여 보냄·잘라냄·미전송 사유는 숨기지 않고 답변 앞에 붙인다(무음 실패 금지)
    return AttachmentLoader.warnings(attachments) + answer
  }

  /// 첨부 전송 — 실패 분류별 재시도 사다리는 Core(`AttachmentRetry`)에 있다(P2).
  private static func sendWithAttachmentFallback(client: any LLMClient,
                                                 prompt: String,
                                                 history: [Turn],
                                                 attachments: [OutgoingAttachment],
                                                 model: String) async throws -> String {
    try await AttachmentRetry.send(client: client, prompt: prompt, history: history,
                                   attachments: attachments, model: model)
  }

  private static func replyRaw(provider p: LLMProviderConfig,
                               prompt: String,
                               history: [Turn],
                               attachments: [OutgoingAttachment]) async throws -> String {
    switch p.type {
    case .appleFM:
      let skipped = attachments.filter { $0.hasImage }
      let answer = try await appleFMReply(prompt: prompt, history: history, attachments: attachments)
      return skipped.isEmpty ? answer
        : Lf("⚠️ Apple FM은 이미지를 받지 못해 %d건을 빼고 보냈습니다.\n\n", skipped.count) + answer
    case .ollama:
      guard !p.model.isEmpty else {
        return L("(오류 E-MAC-NET-0002) 모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요.")
      }
      guard let host = URL(string: p.baseURL) else {
        return Lf("(오류 E-MAC-NET-0002) 호스트 주소가 올바르지 않습니다: %@", p.baseURL)
      }
      // 연결 거부·시간 초과·서버 오류를 그대로 전달한다 — UI가 `AIErrorText`로 정확한 원인을 만든다
      return try await sendWithAttachmentFallback(client: OllamaClient(host: host, model: p.model),
                                                 prompt: prompt, history: history,
                                                 attachments: attachments, model: p.model)
    case .openAICompatible:
      guard !p.model.isEmpty else {
        return L("(오류 E-MAC-NET-0002) 모델이 비어 있습니다. 설정 > AI에서 모델을 지정해 주세요.")
      }
      guard !p.secretID.isEmpty,
            let key = SecretStore.load(account: p.secretID), !key.isEmpty else {
        return L("(오류 E-MAC-KEY-0001) API 키가 없습니다. 설정 > AI에서 키를 저장해 주세요.")
      }
      guard let base = URL(string: p.baseURL) else {
        return Lf("(오류 E-MAC-NET-0002) 주소가 올바르지 않습니다: %@", p.baseURL)
      }
      return try await sendWithAttachmentFallback(client: OpenAIClient(baseURL: base, apiKey: key, model: p.model),
                                                 prompt: prompt, history: history,
                                                 attachments: attachments, model: p.model)
    }
  }
}

/// `Timer` 블록(`@Sendable`)이 비-Sendable 객체를 직접 잡지 않도록 감싸는 약한 상자.
/// 실제 작업은 `Task { @MainActor }` 안에서 하고, 타이머가 살아 있는 동안만 대상을 붙든다.
final class WeakMainActorBox<T: AnyObject>: @unchecked Sendable {
  weak var value: T?
  init(_ value: T) { self.value = value }
}

// MARK: - 대화방 하나의 상태 (v0.31 6a)

/// 대화방 하나가 들고 있는 입력·실행 상태.
///
/// 예전에는 `UIStore` 가 전부 **하나만** 들고 있어서, 다른 대화를 열면
/// 진행 중이던 응답의 상태(스트리밍 턴·도구 카드·승인)가 화면에서 사라졌다.
/// 이제 대화방마다 이 객체를 두고, 화면은 활성 방의 것만 본다.
/// (동시 응답을 켜는 6b 는 이 경계 위에서 `replyTask` 를 방별로 돌린다)
final class ChatSession: ObservableObject, Identifiable {
  let id: UUID
  /// 이 방의 대화 저장소 — 예약 실행과 같은 방식으로 방마다 독립이다.
  let core: ConversationStore
  @Published var conversation: Conversation

  // 입력독
  @Published var draft = ""
  @Published var attached: [PendingAttachment] = []
  /// 이번 질문만 웹 검색을 강제한다(전송 후 자동 해제)
  @Published var forceWebSearch = false

  // 응답 진행
  @Published var isReplying = false
  @Published var isSearching = false
  @Published var streamingTurnID: UUID?
  /// 지금 도착 중인 사고 과정 — 완료 시 턴에 저장하고 비운다.
  @Published var liveReasoning = ""
  @Published var networkRetryStatus: String?
  var replyStartedAt: Date?
  var replyTask: Task<Void, Never>?

  /// 후속 질문 제안(v0.32) — 답변 턴 ID → 칩 목록. 대화방마다 따로 둔다.
  @Published var followUpStates: [UUID: FollowUpState] = [:]
  /// 후속 질문 생성 작업 — 새 전송·중지 시 취소한다.
  var followUpTask: Task<Void, Never>?

  // 도우미 도구
  @Published var agentEvents: [AgentEvent] = []
  var agentSearchSources: [TurnSource] = []
  @Published var agentApproval: AgentApprovalRequest?
  @Published var agentTurnID: UUID?
  @Published var agentHandoffNotice: String?
  @Published var agentUndoEntries: [String: UndoEntry] = [:]
  @Published var agentUndoMessages: [String: String] = [:]
  var agentExecutor: AgentExecutor?
  var currentRunHandle: SandboxCancellation?

  // 일정 제안 카드
  @Published var pendingSchedule: ScheduleConfirmation?

  init(conversation: Conversation) {
    self.id = conversation.id
    self.core = ConversationStore(conversation: conversation)
    self.conversation = conversation
  }
}
