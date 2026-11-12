import Foundation

// [FEATURE] 맡긴 작업 실행기 (v0.38, PLAN_v0.38 §6)
//
// 사용자가 계획 카드에서 [맡기기]를 누르면 이 실행기가 Job을 만든다.
//   · Job은 **전용 대화**(🧰 목표, 핀 고정)에서 돌고 현재 대화를 오염시키지 않는다.
//   · 작업 폴더 안의 쓰기만 자동 승인한다. 중요·치명·시스템·앱 데이터는 기존 승인 카드.
//   · 12스텝 구간을 최대 6번 이어서 달린다(최대 30분). 한도에 닿으면 `.paused` + 알림.
//   · 승인은 10분 기다리고, 만료되면 `.paused` — 사용자가 열어서 [계속]하면 이어 간다.
//
// ★ 실행 엔진은 새로 만들지 않는다 — `AgentRunner`·`AgentExecutor`·`ScheduledRunContext` 를
//   그대로 쓴다. 그래서 샌드박스·승인·감사 로그·되돌리기가 자동으로 적용된다.

@MainActor
final class JobService {
  /// 한 구간에서 쓸 수 있는 도구 스텝 — `AgentRunner` 기본 상한과 같다.
  static let segmentSteps = 12
  /// 처음 맡길 때 이어서 달릴 수 있는 구간 수.
  static let defaultSegments = 6
  /// 실제 실행 시간 상한(누적). 멈춰 있던 시간은 세지 않는다.
  static let maxActiveSeconds: TimeInterval = Job.defaultActiveSeconds

  private unowned let store: UIStore
  private let jobStore: JobStore
  private var runnerTask: Task<Void, Never>?
  /// 지금 실행 중인 Job. 한 번에 하나만 — `scheduledRun` 컨텍스트가 앱 전체에 하나뿐이다.
  private(set) var activeJobID: UUID?
  /// 앞선 작업이 끝나기를 기다리는 Job들.
  private var queuedIDs: [UUID] = []
  /// 스트리밍 화면 갱신 제한 — 조각마다 다시 그리면 UI 가 끊긴다.
  private var lastLivePublish = Date.distantPast

  /// 메뉴바·툴팁을 다시 그리게 한다(AppDelegate 가 연결).
  var onJobsChanged: (() -> Void)?

  init(store: UIStore, jobStore: JobStore = JobStore()) {
    self.store = store
    self.jobStore = jobStore
  }

  /// SchedulerService 가 예약 실행을 미룰지 판단할 때 쓴다.
  var isExecuting: Bool { activeJobID != nil }

  // MARK: - 승인 상태 (UIStore 가 승인 카드와 함께 부른다)

  /// 승인 카드가 떴다 — 상태 카드에 "승인 대기"를 보여 준다.
  func markWaiting(_ id: UUID) {
    guard var job = store.job(id: id),
          job.status == .running || job.status == .waitingApproval else { return }
    job.status = .waitingApproval
    job.progress = L("승인을 기다리는 중입니다.")
    job.updatedAt = Date()
    upsert(job)
  }

  /// 사용자가 승인했다 — 다시 실행 중으로.
  func markRunning(_ id: UUID) {
    guard var job = store.job(id: id), job.status == .waitingApproval else { return }
    job.status = .running
    job.progress = L("승인되어 이어서 실행합니다.")
    job.updatedAt = Date()
    upsert(job)
  }

  // MARK: - 수명

  /// 앱 시작 — 저장된 Job을 읽고, 실행 중이던 것은 **자동 재개하지 않고** 멈춘 것으로 표시한다.
  func start() {
    guard store.jobs.isEmpty else { return }
    var jobs = jobStore.load()
    jobs = JobStore.markingInterrupted(jobs)
    jobs = Array(JobStore.ordered(jobs).prefix(JobStore.limit))
    store.jobs = jobs
    jobStore.save(jobs)
    onJobsChanged?()
    let waiting = jobs.filter { $0.status == .interrupted }.count
    NSLog("[QuickTalk] 맡긴 작업 %d개 불러옴 — 이어서 할 작업 %d개", jobs.count, waiting)
  }

  // MARK: - 시작

  /// 계획 카드의 [맡기기] — Job을 만들고 전용 대화를 연다.
  func start(plan: ExecutionPlan, from session: ChatSession) {
    let personaID = session.conversation.personaID
    let persona = store.settings.persona(personaID)
    let jobID = UUID()
    let root = PersonaReports.folder(settings: store.settings, persona: persona)
    let workspace = JobWorkspace.path(root: root, jobID: jobID)
    guard JobWorkspace.create(at: workspace) != nil else {
      NSLog("[WARN] E-MAC-JOB-0004 작업 폴더를 만들지 못했습니다 — %@", workspace)
      return
    }

    let title = JobPrompt.title(plan.goal)
    var conversation = Conversation(title: "🧰 \(title)", pinned: true, personaID: personaID)
    conversation.titleEdited = true
    let core = ConversationStore(conversation: conversation)
    _ = try? core.submit(text: JobPrompt.visibleText)
    _ = core.appendJobStatus(jobID: jobID)
    // ★ 작업 폴더만 7일 자동 승인 — 그 밖의 쓰기·중요·치명은 항상 확인한다.
    core.setWriteScopeGrants(WriteScopeGrant.approve([workspace], into: []))

    var job = Job.make(plan: plan, id: jobID, conversationID: core.conversation.id,
                       personaID: personaID, workspacePath: workspace,
                       maxSegments: Self.defaultSegments)
    let canStartNow = activeJobID == nil
    job.status = canStartNow ? .running : .queued
    if !canStartNow { job.progress = L("앞선 작업이 끝나면 시작합니다.") }
    upsert(job)

    store.applyScheduledConversation(core.conversation)
    // 맡긴 직후에는 그 대화를 보여 준다 — "시작했다"는 확인이 없으면 사용자는 앱이 멈춘 줄 안다.
    store.openConversation(core.conversation)
    NSLog("[QuickTalk] 맡긴 작업 시작 — %@ (구간 %d, 폴더 %@)", title, job.maxSegments, workspace)

    if canStartNow {
      launch(jobID)
    } else if !queuedIDs.contains(jobID) {
      queuedIDs.append(jobID)
    }
  }

  // MARK: - 중단·재개

  /// 상태 카드·메뉴의 [중단] — 지금 도구를 멈추고 다음 도구부터 거부한다. 부분 산출물은 남긴다.
  func cancel(_ id: UUID) {
    guard var job = store.job(id: id) else { return }
    switch job.status {
    case .running, .waitingApproval, .queued, .paused, .interrupted:
      break
    case .completed, .failed, .cancelled:
      return
    }
    let wasQueued = job.status == .queued
    if wasQueued { queuedIDs.removeAll { $0 == id } }

    job.status = .cancelled
    job.failureReason = nil
    job.progress = L("사용자가 중단했습니다.")
    job.finishedAt = Date()
    job.updatedAt = Date()
    job.resultSummary = job.resultSummary ?? L("사용자가 중단했습니다.")
    job.artifactPaths = JobWorkspace.artifacts(at: job.workspacePath).map(\.path)
    upsert(job)

    if !wasQueued, store.scheduledRun?.jobID == id {
      // 예약 실행과 같은 경로 — 승인 대기를 거부로 깨우고 셸 프로세스를 멈춘다.
      store.cancelAgentRun()
    }
    NSLog("[QuickTalk] 맡긴 작업 중단 — %@", job.title)
  }

  /// 상태 카드의 [계속]/[다시 시도] — 구간 번호를 유지하고 6구간을 새로 준다.
  func resume(_ id: UUID) {
    guard var job = store.job(id: id), job.status.canResume else { return }
    job.status = activeJobID == nil ? .running : .queued
    job.failureReason = nil
    job.finishedAt = nil
    job.progress = activeJobID == nil
      ? L("이어서 실행합니다.")
      : L("앞선 작업이 끝나면 시작합니다.")
    job.maxSegments = max(job.maxSegments, job.segment + Self.defaultSegments)
    // [계속]은 시간 예산도 새로 준다 — 예산이 그대로면 시간 초과로 멈춘 Job이 즉시 다시 멈춘다.
    job.maxActiveSeconds = max(job.maxActiveSeconds, job.activeSeconds + Self.maxActiveSeconds)
    job.updatedAt = Date()
    upsert(job)

    if activeJobID == nil {
      launch(id)
    } else if !queuedIDs.contains(id) {
      queuedIDs.append(id)
    }
    NSLog("[QuickTalk] 맡긴 작업 재개 — %@ (구간 %d/%d)", job.title, job.segment, job.maxSegments)
  }

  // MARK: - 실행

  private func launch(_ jobID: UUID) {
    guard activeJobID == nil else {
      if !queuedIDs.contains(jobID) { queuedIDs.append(jobID) }
      return
    }
    activeJobID = jobID
    onJobsChanged?()
    runnerTask = Task { @MainActor [weak self] in
      guard let self else { return }
      await self.run(jobID)
      self.finishActive(jobID)
    }
  }

  private func finishActive(_ jobID: UUID) {
    guard activeJobID == jobID else { return }
    activeJobID = nil
    runnerTask = nil
    onJobsChanged?()
    startNextQueued()
  }

  private func startNextQueued() {
    while !queuedIDs.isEmpty {
      let id = queuedIDs.removeFirst()
      guard var job = store.job(id: id), job.status == .queued else { continue }
      job.status = .running
      job.progress = nil
      job.updatedAt = Date()
      upsert(job)
      launch(id)
      return
    }
  }

  /// Job 1회 실행 — 구간 루프. 실패해도 던지지 않고 상태로 남긴다.
  private func run(_ jobID: UUID) async {
    guard let snapshot = store.job(id: jobID), snapshot.status == .running else { return }

    // 예약 실행이 끝날 때까지 기다린다 — 실행 컨텍스트(`scheduledRun`)는 앱 전체에 하나뿐이다.
    while store.scheduledRun != nil {
      guard store.job(id: jobID)?.status == .running else { return }
      do {
        try await Task.sleep(nanoseconds: 2_000_000_000)
      } catch {
        return
      }
    }
    guard var job = store.job(id: jobID), job.status == .running else { return }

    let conversation = currentConversation(for: job)
    let session = ConversationStore(conversation: conversation)
    let ctx = ScheduledRunContext(taskID: job.id, session: session,
                                  policy: store.settings.agentPolicy,
                                  kind: .job, jobID: job.id, displayTitle: job.title)
    ctx.writeScopes = (conversation.approvedWriteScopes ?? [])
      .filter { $0.isActive() }.map(\.path)
    ctx.uiGrants = (conversation.approvedUiApps ?? []).filter { $0.isActive() }
    // 재개해도 같은 일을 반복하지 않게, 지난 구간의 최근 카드 12개를 넘긴다.
    ctx.events = Array(conversation.turns.suffix(8)
      .flatMap { $0.agentEvents ?? [] }
      .suffix(12))
    store.scheduledRun = ctx
    store.scheduledRunPersonaID = job.personaID
    defer {
      store.scheduledRun = nil
      store.scheduledRunPersonaID = nil
      store.scheduledApproval = nil
    }

    let persona = store.settings.persona(job.personaID)
    guard let provider = ProviderResolver.provider(settings: store.settings, persona: persona) else {
      fail(&job, reason: L("AI 프로바이더가 설정되지 않았습니다."), session: session)
      return
    }
    let executor = AgentExecutor(store: store, session: store.activeSession)
    guard let client = store.makeAgentClient(provider: provider, executor: executor,
                                             persona: persona) else {
      fail(&job, reason: L("AI 클라이언트를 만들지 못했습니다 — 설정 › AI의 모델·키를 확인하세요."),
           session: session)
      return
    }
    let tools = AgentToolCatalog.available(
      for: persona,
      includingWebSearch: store.settings.webSearchEnabled && store.webSearchKeyReady
        && provider.type != .appleFM,
      includingUI: store.settings.uiControlEnabled && provider.type != .appleFM,
      includingSchedule: true,
      includingScheduleMutations: false)
    let runner = AgentRunner(client: client, executor: executor,
                             maxSteps: Self.segmentSteps, stopAtStepLimit: true)

    while true {
      guard let live = store.job(id: jobID),
            live.status == .running || live.status == .waitingApproval else {
        return   // 사용자가 [중단]했다 — 상태는 cancel() 이 이미 저장했다.
      }
      job = live
      if job.segment >= job.maxSegments {
        pause(&job, reason: Lf("구간 한도(%d)에 도달했습니다. [계속]으로 이어서 실행하세요.",
                              job.maxSegments), session: session)
        return
      }
      if job.activeSeconds >= job.maxActiveSeconds {
        pause(&job, reason: L("실행 시간 한도(30분)에 도달했습니다. [계속]으로 이어서 실행하세요."),
              session: session)
        return
      }

      let segmentNumber = job.segment + 1
      let prompt = job.segment == 0
        ? JobPrompt.first(plan(from: job), workspace: job.workspacePath)
        : JobPrompt.continuation(plan(from: job), workspace: job.workspacePath,
                                 events: ctx.events, segment: segmentNumber)
      let turnID = session.beginAssistantTurn()
      ctx.turnID = turnID
      job.segment = segmentNumber
      job.updatedAt = Date()
      job.progress = Lf("%d구간 시작", segmentNumber)
      upsert(job)
      store.applyScheduledConversation(session.conversation)
      lastLivePublish = Date.distantPast

      let started = Date()
      var streamed = ""
      do {
        let result = try await runner.run(
          prompt: prompt, history: [], tools: tools,
          onDelta: { [weak self] delta in
            streamed += delta
            session.appendStreaming(delta, to: turnID)
            self?.publishLive(session.conversation)
          })
        let elapsed = Date().timeIntervalSince(started)
        job.activeSeconds += elapsed
        job.eventCount += result.events.count
        job.updatedAt = Date()
        if !result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           result.answer != streamed {
          session.setAssistantText(result.answer, id: turnID)
        }
        let trimmedStream = streamed.trimmingCharacters(in: .whitespacesAndNewlines)
        let answer = result.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          ? trimmedStream
          : result.answer
        if let last = result.events.last { job.progress = last.title }
        job.artifactPaths = JobWorkspace.artifacts(at: job.workspacePath).map(\.path)
        session.finishAssistantTurn(turnID, elapsedMs: Int(elapsed * 1000),
                                    sources: executor.turnSources.isEmpty
                                      ? nil : executor.turnSources)
        upsert(job)
        store.applyScheduledConversation(session.conversation)

        if ctx.cancelled {
          cancelAfterRun(&job, session: session)
          return
        }
        if ctx.approvalTimedOut {
          pause(&job, reason: L("승인 대기 시간(10분)이 만료되었습니다. [계속]으로 이어서 실행하세요."),
                session: session)
          return
        }
        if result.hadDenial {
          pause(&job, reason: L("승인이 거부되어 일부 작업을 마치지 못했습니다. [계속]으로 이어서 실행하세요."),
                session: session)
          return
        }
        if !result.hitStepLimit {
          complete(&job, answer: answer.isEmpty ? L("작업을 마쳤습니다.") : answer,
                   session: session)
          return
        }
      } catch {
        job.activeSeconds += Date().timeIntervalSince(started)
        let message = AIErrorText.userText(for: error)
        session.setAssistantText(message, id: turnID)
        store.applyScheduledConversation(session.conversation)
        fail(&job, reason: message, session: session)
        return
      }
    }
  }

  // MARK: - 상태 저장

  private func upsert(_ job: Job) {
    var jobs = store.jobs.filter { $0.id != job.id }
    jobs.insert(job, at: 0)
    store.jobs = Array(JobStore.ordered(jobs).prefix(JobStore.limit))
    jobStore.save(store.jobs)
    onJobsChanged?()
  }

  /// 스트리밍 중 화면만 따라오게 한다(디스크 저장 없음·0.5초 제한).
  private func publishLive(_ conversation: Conversation) {
    let now = Date()
    guard now.timeIntervalSince(lastLivePublish) >= 0.5 else { return }
    lastLivePublish = now
    store.updateScheduledConversationIfOpen(conversation)
  }

  private func complete(_ job: inout Job, answer: String, session: ConversationStore) {
    job.status = .completed
    job.finishedAt = Date()
    job.updatedAt = Date()
    job.resultSummary = JobPrompt.summary(answer)
    job.failureReason = nil
    job.progress = L("완료")
    let artifacts = JobWorkspace.artifacts(at: job.workspacePath)
    job.artifactPaths = artifacts.map(\.path)
    upsert(job)
    _ = session.appendAssistant(text: JobPrompt.resultMarkdown(job, artifacts: artifacts))
    store.applyScheduledConversation(session.conversation)
    store.notifications?.notifyJobFinished(job)
    NSLog("[QuickTalk] 맡긴 작업 완료 — %@ · 파일 %d개", job.title, artifacts.count)
  }

  private func pause(_ job: inout Job, reason: String, session: ConversationStore?) {
    job.status = .paused
    job.failureReason = reason
    job.progress = reason
    job.updatedAt = Date()
    job.artifactPaths = JobWorkspace.artifacts(at: job.workspacePath).map(\.path)
    upsert(job)
    if let session { store.applyScheduledConversation(session.conversation) }
    store.notifications?.notifyJobFinished(job)
    NSLog("[QuickTalk] 맡긴 작업 일시 중지 — %@ · %@", job.title, reason)
  }

  private func fail(_ job: inout Job, reason: String, session: ConversationStore?) {
    job.status = .failed
    job.failureReason = reason
    job.progress = reason
    job.finishedAt = Date()
    job.updatedAt = Date()
    job.artifactPaths = JobWorkspace.artifacts(at: job.workspacePath).map(\.path)
    upsert(job)
    if let session { store.applyScheduledConversation(session.conversation) }
    store.notifications?.notifyJobFinished(job)
    NSLog("[QuickTalk] 맡긴 작업 실패 — %@ · %@", job.title, reason)
  }

  private func cancelAfterRun(_ job: inout Job, session: ConversationStore?) {
    job.status = .cancelled
    job.failureReason = nil
    job.progress = L("사용자가 중단했습니다.")
    job.finishedAt = Date()
    job.updatedAt = Date()
    job.artifactPaths = JobWorkspace.artifacts(at: job.workspacePath).map(\.path)
    upsert(job)
    if let session { store.applyScheduledConversation(session.conversation) }
  }

  // MARK: - 조회

  /// 이 Job의 대화 — 열려 있으면 지금 화면의 것을 쓴다(사용자가 붙인 말도 보존).
  private func currentConversation(for job: Job) -> Conversation {
    if store.conversation.id == job.conversationID { return store.conversation }
    if let c = store.archive.first(where: { $0.id == job.conversationID }) { return c }
    if let c = PersistenceService.load(keepDays: store.settings.keepDays)
      .first(where: { $0.id == job.conversationID }) { return c }
    // 기록이 사라졌어도 Job은 이어 간다 — 빈 전용 대화를 다시 만든다.
    var c = Conversation(id: job.conversationID, title: "🧰 \(job.title)",
                         pinned: true, personaID: job.personaID)
    c.titleEdited = true
    return c
  }

  private func plan(from job: Job) -> ExecutionPlan {
    ExecutionPlan(goal: job.goal.isEmpty ? job.title : job.goal,
                  steps: job.steps.isEmpty ? [job.title] : job.steps,
                  permissions: job.permissions)
  }
}
