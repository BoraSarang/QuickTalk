import Foundation

// [FEATURE] 도구 실행기 — 권한 실측 · 정책 판단 · 사용자 확인 · 감사 기록 (PLAN_v0.18 §4)
//
// 흐름
//   1) 샌드박스(읽기 전용)로 먼저 실행해 **요구 권한을 실측**한다.
//   2) PolicyEngine 으로 허용/확인/차단을 정한다.
//   3) 확인이 필요하면 대화 카드가 기다리고, 사용자가 고른다.
//   4) 승인된 범위(경로)만 열고 재실행한다.
//
// 앱은 명령어 이름을 모른다. `brew`·`adb`·`ollama` 를 몰라도 동작한다.

/// 사용자의 승인 선택.
enum AgentApprovalChoice {
  /// 이번에만 허용
  case allowOnce
  /// 이 폴더(쓰기 범위)를 이번 대화 동안 허용
  case allowScope
  /// 이 앱(화면 조작)을 이번 대화 동안 허용 — 7일
  case allowApp
  /// 이 명령 패턴을 항상 허용
  case alwaysAllow
  /// 거부
  case deny
}

@MainActor
final class AgentExecutor: AgentToolExecutor {
  unowned let store: UIStore
  private var continuation: CheckedContinuation<AgentApprovalChoice, Never>?
  /// 이번 턴에 `web_search` 로 모은 출처 — 답변 아래 출처 카드에 쓴다.
  private(set) var turnSources: [TurnSource] = []
  /// 이번 턴에 받은 화면 스냅샷 — 참조(`r12`)를 경로로 되돌린다(앱별 1장).
  var uiTrees: [String: UiTree] = [:]
  /// 마지막 스냅샷의 키 — 모델이 앱을 생략하면 이 앱을 쓴다.
  var lastUiTreeKey: String?
  /// 이번 턴에 실제로 나간 화면 조작 수 — 30번을 넘지 않는다.
  var uiActionsThisTurn = 0
  /// 마지막 화면 조작 시각 — 동작 사이 150ms 간격.
  var lastUiActionAt: Date?
  /// 화면 조작 중지 손잡이 — 카드 [중단]이 취소한다.
  var uiCancellation: SandboxCancellation?

  init(store: UIStore) {
    self.store = store
  }

  // MARK: - 진입점

  func execute(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome {
    switch call.name {
    case "shell": return await runShell(call)
    case "read_file": return await readFile(call)
    case "list_dir": return await listDir(call)
    case "processes": return await runProcesses(call)
    case "screenshot": return await captureScreenshot(call)
    case "web_search": return await runWebSearch(call)
    case "ui_snapshot": return await runUiSnapshot(call)
    case "ui_action": return await runUiAction(call)
    default:
      let text = Lf("지원하지 않는 도구입니다: %@", call.name)
      return AgentToolOutcome(output: text, denied: true, level: .execute, risk: .normal)
    }
  }

  // MARK: - 셸

  private func runShell(_ call: AgentToolCall) async -> AgentToolOutcome {
    let command = call.stringArgument("command") ?? ""
    guard !command.isEmpty else {
      return AgentToolOutcome(output: L("명령이 비어 있습니다."), denied: true, level: .read)
    }
    let risk = RiskClassifier.classify(command)
    // 전역 설정 + **이 대화의 오버라이드**(v0.22) — 치명적·상승 권한 제한은 전역 값 그대로.
    let policy = store.effectiveAgentPolicy
    let approvedScopes = store.approvedWriteScopes

    // ★ 실행 **이전**의 순서를 지킨다 (2026-10-22 사고).
    //   이전 흐름은 [실측(실행) → 정책 판단] 이라 `rm -rf /` 가 샌드박스 실측에서
    //   실제로 실행됐고(읽기 전용이라 지워지진 않았지만) 명령이 끝나지 않아 앱이 멈췄다.
    //   이제 위험 판정 → 정책 → (일반 명령만) 실측 순서로 간다. 실측·실행은 메인 스레드 밖.
    let plan = await Task.detached(priority: .userInitiated) {
      PolicyEngine.plan(command: command, policy: policy, approvedScopes: approvedScopes)
    }.value

    switch plan {
    case .deny(let reason):
      // 상승 권한(sudo)은 앱이 실행하지 않는다 — 대신 **터미널로 넘길 수 있게** 한다.
      let handoff = RiskClassifier.requiresElevation(command) ? command : nil
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: command,
                                        command: command, level: .execute,
                                        risk: risk, state: .denied, output: reason,
                                        terminalCommand: handoff))
      AgentAudit.record(command: command, level: .execute, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: reason, denied: true, level: .execute, risk: risk,
                              terminalCommand: handoff)

    case .ask(let request):
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: command,
                                        command: command, level: request.level, risk: risk,
                                        state: .pending, output: request.reason))
      let choice = await requestApproval(request)
      if choice == .deny {
        let text = L("사용자가 실행을 거부했습니다. 다른 방법을 제안하세요.")
        store.updateAgentEvent(id: call.id) { $0.state = .denied; $0.output = text }
        AgentAudit.record(command: command, level: request.level, risk: risk,
                          decision: "deny", exitCode: nil, elapsedMs: 0)
        return AgentToolOutcome(output: text, denied: true, level: request.level, risk: risk)
      }
      if choice == .alwaysAllow {
        store.addAgentRule(pattern: command)
      }
      if choice == .allowScope {
        // 이 폴더를 이번 대화 동안 허용 — 같은 폴더의 다음 쓰기는 다시 묻지 않는다.
        store.approveWriteScopes(request.writeScopes)
      }
      // 승인된 뒤에야 실측한다 — 필요한 권한(경로)을 알아야 그 범위만 열 수 있다.
      let capability: AgentCapability
      if risk == .normal {
        capability = request.capability
      } else {
        capability = await Self.probeApprovedOffMain(command).capability
      }
      return await executeShell(call, command: command, capability: capability, risk: risk)

    case .allow(let capability):
      // 승인만으로 떨어져도 **실측 없이** 실행하지 않는다(중요·치명적 명령).
      let resolved: AgentCapability
      if capability == .unprobed {
        resolved = await Self.probeApprovedOffMain(command).capability
      } else {
        resolved = capability
      }
      // ★ 자동 허용된 실행도 **카드에 남긴다**(v0.20) — 예전에는 승인을 거치지 않은
      //   실행이 화면에 전혀 보이지 않았다(무엇이 돌았는지 알 수 없음).
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: command,
                                        command: command, level: resolved.level, risk: risk,
                                        state: .running))
      return await executeShell(call, command: command, capability: resolved, risk: risk)
    }
  }

  /// 승인을 받은 뒤의 실측 — 위험 판정을 이미 통과한 명령.
  private static func probeApprovedOffMain(_ command: String) async -> SandboxProbe {
    await Task.detached(priority: .userInitiated) { SandboxRunner.probeApproved(command) }.value
  }

  /// 승인된 범위만 열고 실행한다.
  private func executeShell(_ call: AgentToolCall, command: String,
                            capability input: AgentCapability,
                            risk: AgentRiskLevel) async -> AgentToolOutcome {
    var capability = input
    // 실측 전(중요·치명적 명령)이면 여기서 한 번 실측한다 — 승인은 이미 받았다.
    if capability == .unprobed {
      capability = await Self.probeApprovedOffMain(command).capability
    }
    store.updateAgentEvent(id: call.id) { $0.state = .running }
    let profile: String
    var runCommand = command
    var undo: UndoEntry?
    switch capability {
    case .read, .unprobed:
      profile = SandboxRunner.readOnlyProfile()
    case .write(let path):
      // ★ 시스템 영역에는 쓰기를 열지 않는다(디스크 전체가 지워질 수 있다).
      //   파일이면 상위 폴더가 쓰기 범위가 되므로 **범위 기준**으로 막는다.
      //   판정은 `TerminalHandoff.isSystemWrite` 하나로 모은다(카드 안내와 같은 기준).
      let scope = Self.writableScope(for: path)
      if TerminalHandoff.isSystemWrite(path) {
        // v0.20 — "안 됩니다"로 끝내지 않고 **터미널로 넘긴다**(앱은 실행하지 않는다).
        let note = TerminalHandoff.note(capability: capability)
        store.updateAgentEvent(id: call.id) {
          $0.state = .denied
          $0.output = note
          $0.terminalCommand = command
        }
        AgentAudit.record(command: command, level: capability.level, risk: risk,
                          decision: "deny", exitCode: nil, elapsedMs: 0)
        return AgentToolOutcome(output: note, denied: true, level: capability.level,
                                risk: risk, terminalCommand: command)
      }
      // ★ v0.19 — 실행 **전에** 되돌릴 지점을 만든다(스냅샷 + 단순 rm 은 휴지통 이동).
      let prepared = await prepareWrite(command: command, scope: scope)
      runCommand = prepared.command
      undo = prepared.undo
      profile = SandboxRunner.scopedProfile(writablePaths: [scope] + prepared.extraWritePaths)
    case .network:
      profile = SandboxRunner.scopedProfile(writablePaths: [], allowNetwork: true)
    case .elevated:
      profile = SandboxRunner.elevatedProfile(writablePaths: [])
    case .blocked:
      // ★ 샌드박스가 **실행 자체**를 막는 명령(setuid ps·top 등) — 권한을 열어도 해결되지 않는다.
      //   실행하지 않고 이유를 모델에게 돌려준다(재시도 금지 안내 포함).
      return await finishShell(call, command: command, risk: risk, level: capability.level,
                               result: SandboxResult(exitCode: -1, stdout: "",
                                                     stderr: SandboxRunner.blockedNote(for: command)),
                               denied: true)
    }
    let started = Date()
    // ★ 실행도 메인 스레드 밖에서 — 오래 걸리는 명령이 UI 를 얼리지 않게.
    //   v0.20: 출력을 **오는 대로** 카드에 흘리고, [중단] 버튼으로 프로세스를 멈춘다.
    let timeout = TimeInterval(min(max(store.settings.agentTimeoutSeconds, 10), 600))
    let handle = SandboxCancellation()
    store.agentRunHandle = handle
    let liveEnabled = store.settings.agentStreamOutput
    let live = LiveShellOutput()
    let storeRef = store
    let result = await Task.detached(priority: .userInitiated) {
      SandboxRunner.runStreaming(runCommand, profile: profile, timeout: timeout,
                                 cancellation: handle,
                                 onOutput: { chunk in
        guard liveEnabled else { return }
        let text = live.append(chunk)
        guard live.shouldFlush() else { return }
        Task { @MainActor in
          storeRef.updateAgentEvent(id: call.id) { $0.output = text }
        }
      })
    }.value
    store.agentRunHandle = nil
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    // ★ 되돌리기 기록 — 성공한 쓰기만 남기고, 실패·중단이면 백업을 버린다(v0.19).
    //   (2026-10-25 발견: commit 을 부르지 않아 [되돌리기]가 항상 "기록을 찾지 못했습니다"였다)
    if let undo {
      if result.succeeded { await UndoStack.shared.commit(undo) }
      else { await UndoStack.shared.discard(id: undo.id) }
    }
    return await finishShell(call, command: command, risk: risk, level: capability.level,
                             result: result, elapsedMs: elapsed,
                             execCommand: runCommand == command ? nil : runCommand,
                             undo: result.succeeded ? undo : nil, denied: false)
  }

  /// 쓰기 직전 준비 — 되돌릴 지점(스냅샷)을 만들고, 단순 `rm` 이면 휴지통 이동으로 바꾼다.
  ///
  /// 백업은 **승인된 폴더 안의 경로만** 대상으로 한다(그 밖은 쓸 수 없다).
  private func prepareWrite(command: String, scope: String) async
  -> (command: String, undo: UndoEntry?, extraWritePaths: [String]) {
    let trashRoot = UndoStack.shared.trashRoot.path
    let trash = TrashRewrite.plan(command, trashRoot: trashRoot)
    var extra: [String] = []
    let paths: [String]
    var effective = command
    if let trash {
      paths = trash.moves.map(\.source)
      extra = [trash.directory]      // 휴지통 폴더도 샌드박스에 열어 줘야 한다
      effective = trash.command
    } else {
      paths = WriteScope.candidatePaths(in: command)
        .filter { WriteScope.contains($0, in: scope) }
    }
    guard !paths.isEmpty else { return (effective, nil, extra) }
    var entry = await UndoStack.shared.snapshot(command: command, scope: scope, paths: paths)
    if entry.note == nil {
      entry.note = trash != nil
        ? L("파일을 QuickTalk 휴지통으로 옮겼습니다. [되돌리기] 로 되살릴 수 있습니다.")
        : nil
    }
    return (effective, entry, extra)
  }

  /// 실행 결과를 카드·감사 기록에 반영한다.
  private func finishShell(_ call: AgentToolCall, command: String,
                            risk: AgentRiskLevel, level: AgentPermissionLevel,
                            result: SandboxResult, elapsedMs: Int? = nil,
                            execCommand: String? = nil, undo: UndoEntry? = nil,
                            denied: Bool) async -> AgentToolOutcome {
    let elapsed = elapsedMs ?? 0
    var output = Self.outputText(result)
    // 휴지통 rewrite 로 실제 실행 명령이 달라졌으면 **그대로 보여 준다**(정직하게).
    if let execCommand {
      output = Lf("실제 실행: %@", execCommand) + "\n" + output
    }
    if let note = undo?.note, !note.isEmpty {
      output += "\n" + note
    }
    store.updateAgentEvent(id: call.id) {
      $0.state = result.succeeded ? .done : .failed
      $0.output = output
      $0.elapsedMs = elapsed
      if let undo { $0.undoID = undo.id }
    }
    if let undo {
      store.registerAgentUndo(undo, eventID: call.id)
    }
    AgentAudit.record(command: command, level: level, risk: risk,
                      decision: denied ? "deny" : "allow",
                      exitCode: result.exitCode, elapsedMs: elapsed)
    return AgentToolOutcome(output: output, denied: denied,
                             level: level, risk: risk)
  }

  /// 파일이 대상이면 **상위 폴더**를 쓰기 범위로 연다(파일이 없으면 생성해야 해서).
  static func writableScope(for path: String) -> String {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
      return path
    }
    let parent = (path as NSString).deletingLastPathComponent
    return parent.isEmpty ? path : parent
  }

  /// 모델에게 돌려줄 출력 — 표준출력 + (실패하면) 표준에러.
  static func outputText(_ result: SandboxResult) -> String {
    var text = result.stdout
    if !result.stderr.isEmpty {
      text += text.isEmpty ? result.stderr : "\n" + result.stderr
    }
    text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return L("(출력 없음)") }
    if text.count > 4_000 { text = String(text.prefix(4_000)) + "\n… (생략)" }
    return text
  }

  // MARK: - 실행 카드

  /// 도구 호출 **1건 = 카드 1장**.
  ///
  /// 승인 대기(`.pending`) 카드를 먼저 띄운 뒤 실행 단계에서 새 카드를 또 추가하면,
  /// `updateAgentEvent` 는 첫 장만 고치므로 **첫 카드가 "실행 중"으로 굳고** 결과 카드가
  /// 따로 생긴다. 같은 id 가 이미 있으면 그 카드의 상태·출력만 바꾼다(2026-10-27).
  private func upsertAgentEvent(_ event: AgentEvent) {
    guard store.agentEvents.contains(where: { $0.id == event.id }) else {
      store.appendAgentEvent(event)
      return
    }
    store.updateAgentEvent(id: event.id) { existing in
      existing.state = event.state
      existing.output = event.output
    }
  }

  // MARK: - 파일 읽기 · 폴더 목록

  private func readFile(_ call: AgentToolCall) async -> AgentToolOutcome {
    let path = call.stringArgument("path") ?? ""
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    // 읽기는 기본 자동 허용 — 정책이 "매번 확인"이면 확인 카드(판정은 스크린샷과 같은 곳)
    if AgentToolPermission.needsApproval(tool: call.name, policy: store.effectiveAgentPolicy) {
      let request = AgentApprovalRequest(command: path, level: level, risk: risk,
                                         capability: .read, writablePaths: [],
                                         reason: L("파일을 읽으려면 확인이 필요합니다."))
      upsertAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                  command: path, level: level, risk: risk,
                                  state: .pending, output: request.reason))
      if await requestApproval(request) == .deny {
        let text = L("사용자가 파일 읽기를 거부했습니다.")
        store.updateAgentEvent(id: call.id) { $0.state = .denied; $0.output = text }
        return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
      }
    }
    upsertAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                command: path, level: level, risk: risk, state: .running))
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else {
      let text = Lf("파일이 없습니다: %@", path)
      upsertAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                  command: path, level: level, risk: risk,
                                  state: .failed, output: text))
      return AgentToolOutcome(output: text, level: level, risk: risk)
    }
    let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
    let limited = data.count > 20_000 ? data.prefix(20_000) : data
    let text = String(data: limited, encoding: .utf8) ?? L("(텍스트가 아닌 파일입니다)")
    upsertAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                command: path, level: level, risk: risk,
                                state: .done, output: Lf("(파일 %d자)", text.count)))
    return AgentToolOutcome(output: text, level: level, risk: risk)
  }

  /// 프로세스 사용량 — `ps`·`top` 은 setuid 라 샌드박스가 실행을 막는다. 앱이 libproc 으로 직접 읽는다.
  private func runProcesses(_ call: AgentToolCall) async -> AgentToolOutcome {
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    let limit = min(max(call.intArgument("limit") ?? 5, 1), 30)
    let sort = ProcessSort(rawValue: call.stringArgument("sort") ?? "cpu") ?? .cpu
    store.appendAgentEvent(AgentEvent(
      id: call.id, toolName: call.name,
      title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
      command: "", level: level, risk: risk, state: .running))
    let started = Date()
    // 표본 사이에 쉬므로 메인 스레드 밖에서(400ms) — UI 가 끊기지 않게.
    let rows = await Task.detached(priority: .userInitiated) {
      ProcessSampler.top(sort, limit: limit)
    }.value
    let text = ProcessSampler.report(rows)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    store.updateAgentEvent(id: call.id) {
      $0.state = rows.isEmpty ? .failed : .done
      $0.output = text
      $0.elapsedMs = elapsed
    }
    return AgentToolOutcome(output: text, level: level, risk: risk)
  }

  private func listDir(_ call: AgentToolCall) async -> AgentToolOutcome {
    let path = call.stringArgument("path") ?? ""
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    let fm = FileManager.default
    store.updateAgentEvent(id: call.id) { $0.state = .running }
    guard let items = try? fm.contentsOfDirectory(atPath: path) else {
      let text = Lf("폴더를 읽을 수 없습니다: %@", path)
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                        command: path, level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, level: level, risk: risk)
    }
    let fm2 = FileManager.default
    let lines = items.prefix(200).map { name -> String in
      let full = (path as NSString).appendingPathComponent(name)
      var isDir: ObjCBool = false
      _ = fm2.fileExists(atPath: full, isDirectory: &isDir)
      let size = (try? fm2.attributesOfItem(atPath: full)[.size] as? Int) ?? 0
      return "\(isDir.boolValue ? "📁" : "📄") \(name)\(size > 0 ? " (\(size) bytes)" : "")"
    }
    let text = lines.isEmpty ? L("(빈 폴더)") : lines.joined(separator: "\n")
    store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                      command: path, level: level, risk: risk,
                                      state: .done, output: Lf("%d개 항목", items.count)))
    return AgentToolOutcome(output: text, level: level, risk: risk)
  }

  // MARK: - 스크린샷 (v0.21)

  /// `screenshot` 도구 — 창/화면 1장을 찍어 다음 스텝에 이미지로 넘긴다.
  /// 읽기 전용이며, 화면 기록 권한이 없으면 **허용 방법**을 알려 준다.
  private func captureScreenshot(_ call: AgentToolCall) async -> AgentToolOutcome {
    let target = call.stringArgument("target") ?? "window"
    let level = AgentToolPermission.level(for: call.name)
    let risk = AgentRiskLevel.normal
    // ★ 읽기 단계 정책을 그대로 따른다. 예전에는 이 판정이 없어 "읽기: 매번 확인"
    //   으로 설정해도 화면 캡처가 무조건 실행됐다(2026-10-27).
    if AgentToolPermission.needsApproval(tool: call.name, policy: store.effectiveAgentPolicy) {
      let command = "screenshot \(target)"
      let request = AgentApprovalRequest(
        command: command, level: level, risk: risk, capability: .read, writablePaths: [],
        reason: L("화면을 캡처하려면 확인이 필요합니다."))
      upsertAgentEvent(AgentEvent(
        id: call.id, toolName: call.name,
        title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
        command: target, level: level, risk: risk, state: .pending, output: request.reason))
      if await requestApproval(request) == .deny {
        let text = L("사용자가 화면 캡처를 거부했습니다.")
        store.updateAgentEvent(id: call.id) { $0.state = .denied; $0.output = text }
        AgentAudit.record(command: command, level: level, risk: risk,
                          decision: "deny", exitCode: nil, elapsedMs: 0)
        return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
      }
    }
    upsertAgentEvent(AgentEvent(
      id: call.id, toolName: call.name,
      title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
      command: target, level: level, risk: risk, state: .running))
    do {
      let url = try await WindowAttachmentService.captureForTool(target: target)
      let text = Lf("스크린샷을 찍었습니다(%@). 다음 스텝에서 이 이미지를 볼 수 있습니다.",
                    url.lastPathComponent)
      store.updateAgentEvent(id: call.id) { $0.state = .done; $0.output = text }
      AgentAudit.record(command: "screenshot \(target)", level: level, risk: risk,
                        decision: "allow", exitCode: 0, elapsedMs: 0)
      return AgentToolOutcome(output: text, level: level, risk: risk, imageURL: url)
    } catch {
      let message = (error as? WindowAttachError)?.message
        ?? L("스크린샷을 찍지 못했습니다.")
      store.updateAgentEvent(id: call.id) { $0.state = .failed; $0.output = message }
      AgentAudit.record(command: "screenshot \(target)", level: level, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: message, denied: true, level: level, risk: risk)
    }
  }

  // MARK: - 화면 요소 읽기 (PLAN_v0.25 Phase 1)

  /// `ui_snapshot` — 다른 앱 창의 접근성 요소를 **읽기만** 한다.
  ///
  /// 마스터 토글(`uiControlEnabled`)이 꺼져 있으면 도구가 목록에 없지만,
  /// 설정을 방금 끈 경우를 대비해 실행 직전에 한 번 더 막는다.
  /// 권한이 없으면 **허용 방법**을 돌려준다(스크린샷 도구와 같은 방식).
  private func runUiSnapshot(_ call: AgentToolCall) async -> AgentToolOutcome {
    let level = AgentToolPermission.level(for: call.name)
    let risk = AgentRiskLevel.normal
    let app = (call.stringArgument("app") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let command = app.isEmpty ? "ui_snapshot" : "ui_snapshot \(app)"

    guard store.settings.uiControlEnabled else {
      let text = L("컴퓨터 제어가 꺼져 있어 화면 요소를 읽을 수 없습니다 — 설정 › 도구·권한에서 켜세요.")
      upsertAgentEvent(AgentEvent(id: call.id, toolName: call.name,
                                  title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
                                  command: command, level: level, risk: risk,
                                  state: .denied, output: text))
      AgentAudit.record(command: command, level: level, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }

    // 읽기 단계 정책을 그대로 따른다(화면은 민감하다 — "읽기: 매번 확인"이면 묻는다).
    if AgentToolPermission.needsApproval(tool: call.name, policy: store.effectiveAgentPolicy) {
      let request = AgentApprovalRequest(
        command: command, level: level, risk: risk, capability: .read, writablePaths: [],
        reason: L("다른 앱의 화면 요소를 읽으려면 확인이 필요합니다."))
      upsertAgentEvent(AgentEvent(
        id: call.id, toolName: call.name,
        title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
        command: app, level: level, risk: risk, state: .pending, output: request.reason))
      if await requestApproval(request) == .deny {
        let text = L("사용자가 화면 요소 읽기를 거부했습니다.")
        store.updateAgentEvent(id: call.id) { $0.state = .denied; $0.output = text }
        AgentAudit.record(command: command, level: level, risk: risk,
                          decision: "deny", exitCode: nil, elapsedMs: 0)
        return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
      }
    }

    upsertAgentEvent(AgentEvent(
      id: call.id, toolName: call.name,
      title: AgentRunner.title(for: call, tools: AgentToolCatalog.all),
      command: app, level: level, risk: risk, state: .running))

    switch await AccessibilityService.tree(app: app.isEmpty ? nil : app) {
    case .success(let tree):
      cacheUiTree(tree)
      let text = tree.snapshot.render()
      store.updateAgentEvent(id: call.id) { event in
        event.state = .done
        event.output = Lf("요소 %d개를 읽었습니다.", tree.snapshot.count)
      }
      AgentAudit.record(command: command, level: level, risk: risk,
                        decision: "allow", exitCode: 0, elapsedMs: 0)
      NSLog("[QuickTalk] 화면 요소 %d개 읽음 (앱=%@)", tree.snapshot.count, tree.snapshot.appName)
      return AgentToolOutcome(output: text, level: level, risk: risk)

    case .failure(let error):
      let text = error.message
      store.updateAgentEvent(id: call.id) { $0.state = .failed; $0.output = text }
      AgentAudit.record(command: command, level: level, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }
  }

  // MARK: - 웹 검색 (v0.23)

  /// `web_search` — 모델이 "내 지식 밖"이라고 판단할 때 **직접** 호출한다.
  /// 앱이 Exa를 대신 호출하고 제목·URL·날짜·발췌만 돌려준다(읽기 전용, 승인·샌드박스 불필요).
  /// 검색어는 감사 로그에 남기지 않는다(기존 웹 검색 정책과 동일).
  private func runWebSearch(_ call: AgentToolCall) async -> AgentToolOutcome {
    let query = (call.stringArgument("query") ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    guard !query.isEmpty else {
      let text = L("검색어가 비어 있습니다.")
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name,
                                        title: text, command: "",
                                        level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }
    store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name,
                                      title: Lf("웹 검색 — %@", query), command: "",
                                      level: level, risk: risk, state: .running))
    let started = Date()
    let outcome = await store.searchWeb(query: query)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    switch outcome {
    case .success(let results) where !results.isEmpty:
      let limit = max(1, store.settings.webSearchResultCount)
      let context = WebSearchContext.build(results: results,
                                           maxCharacters: store.settings.webSearchMaxCharacters,
                                           limit: limit)
      for source in WebSearchContext.sources(from: results, limit: limit)
      where !turnSources.contains(where: { $0.url == source.url }) {
        turnSources.append(source)
      }
      let added = turnSources.count
      store.updateAgentEvent(id: call.id) {
        $0.state = .done
        $0.output = Lf("검색 결과 %d건 · 출처 %d개", results.count, added)
        $0.elapsedMs = elapsed
      }
      return AgentToolOutcome(output: context, level: level, risk: risk)

    case .success:
      let text = L("검색 결과가 없습니다. 다른 검색어로 시도하거나 아는 범위에서 답하세요.")
      store.updateAgentEvent(id: call.id) {
        $0.state = .failed
        $0.output = text
        $0.elapsedMs = elapsed
      }
      return AgentToolOutcome(output: text, level: level, risk: risk)

    case .failure(let error):
      let text = error.userText
      store.updateAgentEvent(id: call.id) {
        $0.state = .failed
        $0.output = text
        $0.elapsedMs = elapsed
      }
      return AgentToolOutcome(output: text, level: level, risk: risk)
    }
  }

  // MARK: - 승인 대기

  /// 사용자 응답을 기다린다(카드에서 누르면 이어진다).
  func requestApproval(_ request: AgentApprovalRequest) async -> AgentApprovalChoice {
    // QA 헤드리스 — 대면 창이 없으므로 승인은 거부로 처리한다(무한 대기 방지).
    if store.agentSelfTestMode { return .deny }
    return await withCheckedContinuation { cont in
      self.continuation = cont
      self.store.agentApproval = request
    }
  }

  /// 사용자가 카드의 버튼을 눌렀다.
  func resolveApproval(_ choice: AgentApprovalChoice) {
    store.agentApproval = nil
    guard let cont = continuation else { return }
    continuation = nil
    cont.resume(returning: choice)
  }

  /// 응답 중지 — 승인 대기 중이면 거부로 깨우고, 실행 중이면 프로세스를 멈춘다.
  func cancelPending() {
    if let cont = continuation {
      continuation = nil
      store.agentApproval = nil
      cont.resume(returning: .deny)
    }
    store.cancelAgentRun()
    cancelUIActions()
  }

  /// 진행 중인 화면 조작 중지 — 다음 동작을 보내지 않는다(PLAN_v0.25 §4.4).
  func cancelUIActions() {
    uiCancellation?.cancel()
  }
}

/// 실행 중 출력을 모으는 작은 상자 — IO 스레드에서 쓰고 메인에서 읽는다.
private final class LiveShellOutput: @unchecked Sendable {
  private let lock = NSLock()
  private var text = ""
  private var lastFlush = Date.distantPast

  /// 조각을 더하고 지금까지의 출력을 돌려준다(표시 상한 8,000자).
  func append(_ chunk: String) -> String {
    lock.lock()
    defer { lock.unlock() }
    if text.count < 8_000 { text += chunk }
    return String(text.suffix(8_000))
  }

  /// 0.15초에 한 번만 화면을 갱신한다(조각마다 갱신하면 UI 가 끊긴다).
  func shouldFlush() -> Bool {
    lock.lock()
    defer { lock.unlock() }
    let now = Date()
    guard now.timeIntervalSince(lastFlush) >= 0.15 else { return false }
    lastFlush = now
    return true
  }
}
