import Foundation

// [FEATURE] 예약 작업 스케줄러 (v0.26 3단계)
//
// 앱이 실행 중일 때만 동작한다(로그인 자동 시작이 전제 — PLAN §11).
// 20초마다 `SchedulePlanner.tick` 으로 **순수 판정**만 하고, 실행은 한 번에 1개.
//
// ★ 중복 방지: 실행을 시작하기 **전에** `nextFireAt` 을 다음 시각으로 저장한다.
//   앱이 실행 도중 죽어도 같은 시각을 두 번 실행하지 않는다.
// ★ 앱 종료: `running`/`awaitingApproval` 로 남은 기록은 다음 기동 때 `interrupted` 로 정리한다.

@MainActor
final class SchedulerService {
  /// 폴링 주기 — 분 단위 예약에는 충분하고, 배터리 부담이 작다.
  static let pollInterval: TimeInterval = 20
  /// 밀린 일정이 이 수를 넘으면 1개만 실행하고 나머지는 `missed` 로 남긴다(비용 보호).
  static let maxCatchUpBatch = 3

  private unowned let store: UIStore
  private var timer: Timer?
  private(set) var tasks: [ScheduledTask] = []
  private var runningTaskID: UUID?
  /// 실행 1회가 끝났을 때 (알림 계층이 연결한다).
  var onRunFinished: ((ScheduledTask, RunRecord) -> Void)?

  init(store: UIStore) {
    self.store = store
    tasks = ScheduleStore.load().tasks
  }

  // MARK: - 수명

  func start() {
    stop()
    guard store.settings.schedulerEnabled else {
      NSLog("[QuickTalk] 예약 실행 꺼짐 — 스케줄러를 시작하지 않습니다")
      return
    }
    recoverInterrupted()
    reconcile()
    let t = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
      Task { @MainActor in self?.tick() }
    }
    t.tolerance = 5
    timer = t
    NSLog("[QuickTalk] 스케줄러 시작 — 일정 %d개", tasks.count)
    tick()
  }

  /// 앱 종료 — 실행 중인 타이머를 멈추고 마지막 상태를 저장한다.
  func stop() {
    timer?.invalidate()
    timer = nil
  }

  /// 설정에서 예약 실행을 켜고 끌 때 — 타이머만 다시 건다.
  func applySettings() {
    if store.settings.schedulerEnabled {
      if timer == nil { start() }
    } else {
      stop()
    }
  }

  /// 디스크에서 다시 읽는다(다른 창에서 수정했을 때).
  func reload() {
    tasks = ScheduleStore.load().tasks
    reconcile()
    save()
  }

  func save() {
    do {
      try ScheduleStore.save(ScheduleSnapshot(tasks: tasks))
    } catch {
      NSLog("[WARN] E-MAC-AGENT-0003 schedules.json 저장 실패: %@",
            String(describing: error))
    }
  }

  // MARK: - 조회·편집 (4단계 `/할일` 이 쓴다)

  func task(_ id: UUID) -> ScheduledTask? { tasks.first { $0.id == id } }
  var isRunning: Bool { runningTaskID != nil }
  func isRunning(_ id: UUID) -> Bool { runningTaskID == id }

  /// 추가/수정 — 다음 실행 시각을 채우고 저장한다.
  @discardableResult
  func upsert(_ task: ScheduledTask, now: Date = Date()) -> ScheduledTask {
    var t = task.normalized()
    t.fillNextFireIfNeeded(now: now)
    if let index = tasks.firstIndex(where: { $0.id == t.id }) {
      tasks[index] = t
    } else {
      tasks.append(t)
    }
    save()
    NSLog("[QuickTalk] 예약 작업 저장 — %@ (%@)", t.title, t.rule.humanDescription())
    return t
  }

  /// 삭제 — 리포트 파일은 그대로 둔다(PLAN §8.2).
  func delete(_ id: UUID) {
    tasks.removeAll { $0.id == id }
    save()
    NSLog("[QuickTalk] 예약 작업 삭제")
  }

  /// 일시 중지/다시 시작.
  func setEnabled(_ id: UUID, _ enabled: Bool, now: Date = Date()) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    tasks[index].enabled = enabled
    if enabled {
      tasks[index].nextFireAt = nil
      tasks[index].fillNextFireIfNeeded(now: now)
    }
    save()
  }

  /// "지금 실행" — 예약 시각은 앞당기지 않는다(PLAN §8.2).
  func runNow(_ id: UUID) {
    guard runningTaskID == nil, let task = task(id) else { return }
    // ★ 예약 폴링과 겹치지 않게 **동기적으로** 실행 중 표시를 먼저 잡는다.
    runningTaskID = task.id
    Task { @MainActor in
      await execute(.init(task: task, fireAt: Date()), trigger: .manual, advance: false)
    }
  }

  // MARK: - 폴링

  func tick(now: Date = Date()) {
    guard store.settings.schedulerEnabled, runningTaskID == nil else { return }
    let snapshot = SchedulePlanner.tick(tasks, now: now)

    if !snapshot.missed.isEmpty {
      for firing in snapshot.missed { recordMissed(firing, now: now) }
      save()
    }
    guard !snapshot.due.isEmpty else { return }

    // 밀린 일정이 너무 많으면 1개만 실행하고 나머지는 건너뛴다(토큰·부작용 보호).
    if snapshot.due.count > Self.maxCatchUpBatch {
      for extra in snapshot.due.dropFirst() { recordMissed(extra, now: now) }
      save()
    }
    let firing = snapshot.due[0]
    // ★ Task 가 시작되기 전에 다음 틱이 돌면 같은 일정이 두 번 실행된다 — 먼저 잡아 둔다.
    runningTaskID = firing.task.id
    Task { @MainActor in
      await execute(firing, trigger: .scheduled, advance: true)
    }
  }

  // MARK: - 실행

  private func execute(_ firing: ScheduleTick.Firing, trigger: RunTrigger,
                       advance: Bool) async {
    guard let index = tasks.firstIndex(where: { $0.id == firing.task.id }) else {
      runningTaskID = nil
      return
    }
    defer { runningTaskID = nil }

    let started = Date()
    var task = tasks[index]
    if advance {
      // ★ 실행 **전에** 다음 시각을 저장 — 크래시 후 중복 실행 방지.
      task.advanceNextFire(after: firing.fireAt, now: started)
    }
    let placeholder = RunRecord(startedAt: started, status: .running, trigger: trigger)
    task.record(placeholder)
    tasks[index] = task
    save()

    let runner = ScheduledRunRunner(store: store)
    let outcome = await runner.run(task: task, fireAt: firing.fireAt, trigger: trigger)

    guard let current = tasks.firstIndex(where: { $0.id == task.id }) else { return }
    var updated = tasks[current]
    // 러너는 자기 기록을 새로 만든다 — 미리 넣어 둔 "실행 중" 자리표시자는 지운다.
    updated.history.removeAll { $0.id == placeholder.id }
    updated.history.append(outcome.run)
    updated.lastRun = outcome.run
    updated.conversationID = outcome.conversationID
    if updated.history.count > ScheduledTask.historyLimit {
      updated.history.removeFirst(updated.history.count - ScheduledTask.historyLimit)
    }
    tasks[current] = updated
    save()
    onRunFinished?(updated, outcome.run)
    store.onScheduledRunFinished?(ScheduledRunNotice(
      taskID: updated.id,
      conversationID: updated.conversationID,
      personaName: store.settings.persona(updated.personaID)?.name,
      title: updated.title,
      status: outcome.run.status,
      fileName: outcome.run.filePath.map { ($0 as NSString).lastPathComponent },
      reason: outcome.run.failureReason))
  }

  // MARK: - 정리

  /// 앱이 꺼진 동안 끝나지 못한 실행 — 다음 정시에 다시 실행한다(즉시 재실행 금지).
  private func recoverInterrupted() {
    let now = Date()
    var changed = false
    for i in tasks.indices {
      guard let last = tasks[i].lastRun, !last.status.isTerminal else { continue }
      var run = last
      run.status = .interrupted
      run.finishedAt = now
      run.failureReason = L("앱이 종료되어 실행이 중단되었습니다.")
      if let j = tasks[i].history.lastIndex(where: { $0.id == run.id }) {
        tasks[i].history[j] = run
      }
      tasks[i].lastRun = run
      tasks[i].fillNextFireIfNeeded(now: now)
      changed = true
      NSLog("[QuickTalk] 예약 실행 중단 정리 — 다음 정시에 다시 실행")
    }
    if changed { save() }
  }

  /// 비어 있는 `nextFireAt` 을 채운다(중복 실행 없음 — 이미 있으면 유지).
  private func reconcile() {
    let reconciled = SchedulePlanner.reconciled(tasks, now: Date())
    if reconciled != tasks {
      tasks = reconciled
      save()
    }
  }

  /// 24시간을 넘겨 건너뛴 일정 — 기록만 남기고 다음 시각으로 넘긴다.
  private func recordMissed(_ firing: ScheduleTick.Firing, now: Date) {
    guard let index = tasks.firstIndex(where: { $0.id == firing.task.id }) else { return }
    var task = tasks[index]
    task.record(RunRecord(startedAt: firing.fireAt, finishedAt: now, status: .missed,
                          failureReason: L("24시간이 지나 건너뛰었습니다."),
                          trigger: .scheduled))
    task.advanceNextFire(after: firing.fireAt, now: now)
    tasks[index] = task
  }
}
