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
  /// 이 명령 패턴을 항상 허용
  case alwaysAllow
  /// 거부
  case deny
}

@MainActor
final class AgentExecutor: AgentToolExecutor {
  private unowned let store: UIStore
  private var continuation: CheckedContinuation<AgentApprovalChoice, Never>?

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
    let policy = store.settings.agentPolicy

    // ★ 실행 **이전**의 순서를 지킨다 (2026-10-22 사고).
    //   이전 흐름은 [실측(실행) → 정책 판단] 이라 `rm -rf /` 가 샌드박스 실측에서
    //   실제로 실행됐고(읽기 전용이라 지워지진 않았지만) 명령이 끝나지 않아 앱이 멈췄다.
    //   이제 위험 판정 → 정책 → (일반 명령만) 실측 순서로 간다. 실측·실행은 메인 스레드 밖.
    let plan = await Task.detached(priority: .userInitiated) {
      PolicyEngine.plan(command: command, policy: policy)
    }.value

    switch plan {
    case .deny(let reason):
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: command,
                                        command: command, level: .execute,
                                        risk: risk, state: .denied, output: reason))
      AgentAudit.record(command: command, level: .execute, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: reason, denied: true, level: .execute, risk: risk)

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
    switch capability {
    case .read, .unprobed:
      profile = SandboxRunner.readOnlyProfile()
    case .write(let path):
      // ★ 시스템 전역 경로에는 쓰기를 열지 않는다(디스크 전체가 지워질 수 있다).
      //   파일이면 상위 폴더가 쓰기 범위가 되므로 **범위 기준**으로 막는다.
      let scope = Self.writableScope(for: path)
      if RiskClassifier.isSystemScopePath(scope) || RiskClassifier.isSystemScopePath(path) {
        return await finishShell(call, command: command, risk: risk, level: capability.level,
                                 result: SandboxResult(exitCode: -1, stdout: "",
                                                       stderr: L("시스템 전역 경로에는 쓰기를 허용하지 않습니다.")),
                                 denied: true)
      }
      profile = SandboxRunner.scopedProfile(writablePaths: [scope])
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
    let result = await Task.detached(priority: .userInitiated) {
      SandboxRunner.run(command, profile: profile, timeout: 60)
    }.value
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    return await finishShell(call, command: command, risk: risk, level: capability.level,
                             result: result, elapsedMs: elapsed, denied: false)
  }

  /// 실행 결과를 카드·감사 기록에 반영한다.
  private func finishShell(_ call: AgentToolCall, command: String,
                            risk: AgentRiskLevel, level: AgentPermissionLevel,
                            result: SandboxResult, elapsedMs: Int? = nil,
                            denied: Bool) async -> AgentToolOutcome {
    let elapsed = elapsedMs ?? 0
    let output = Self.outputText(result)
    store.updateAgentEvent(id: call.id) {
      $0.state = result.succeeded ? .done : .failed
      $0.output = output
      $0.elapsedMs = elapsed
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

  // MARK: - 파일 읽기 · 폴더 목록

  private func readFile(_ call: AgentToolCall) async -> AgentToolOutcome {
    let path = call.stringArgument("path") ?? ""
    let level = AgentPermissionLevel.read
    let risk = AgentRiskLevel.normal
    // 읽기는 기본 자동 허용 — 정책이 "매번 확인"이면 확인 카드
    if store.settings.agentPolicy.autoApprove(for: level) == .alwaysAsk {
      let request = AgentApprovalRequest(command: path, level: level, risk: risk,
                                         capability: .read, writablePaths: [],
                                         reason: L("파일을 읽으려면 확인이 필요합니다."))
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                        command: path, level: level, risk: risk,
                                        state: .pending, output: request.reason))
      if await requestApproval(request) == .deny {
        let text = L("사용자가 파일 읽기를 거부했습니다.")
        store.updateAgentEvent(id: call.id) { $0.state = .denied; $0.output = text }
        return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
      }
    }
    store.updateAgentEvent(id: call.id) { $0.state = .running }
    let fm = FileManager.default
    guard fm.fileExists(atPath: path) else {
      let text = Lf("파일이 없습니다: %@", path)
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
                                        command: path, level: level, risk: risk,
                                        state: .failed, output: text))
      return AgentToolOutcome(output: text, level: level, risk: risk)
    }
    let data = (try? Data(contentsOf: URL(fileURLWithPath: path))) ?? Data()
    let limited = data.count > 20_000 ? data.prefix(20_000) : data
    let text = String(data: limited, encoding: .utf8) ?? L("(텍스트가 아닌 파일입니다)")
    store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: path,
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
}
