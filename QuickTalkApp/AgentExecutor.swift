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
    let probe = SandboxRunner.probe(command)
    let policy = store.settings.agentPolicy
    let decision = PolicyEngine.decide(command: command, capability: probe.capability,
                                        risk: risk, policy: policy)

    switch decision {
    case .deny(let reason):
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: command,
                                        command: command, level: probe.capability.level,
                                        risk: risk, state: .denied, output: reason))
      AgentAudit.record(command: command, level: probe.capability.level, risk: risk,
                        decision: "deny", exitCode: nil, elapsedMs: 0)
      return AgentToolOutcome(output: reason, denied: true, level: probe.capability.level, risk: risk)

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
      return await executeShell(call, command: command, capability: probe.capability,
                                risk: risk, allowed: true)

    case .allow:
      return await executeShell(call, command: command, capability: probe.capability,
                                risk: risk, allowed: true)
    }
  }

  /// 승인된 범위만 열고 실행한다.
  private func executeShell(_ call: AgentToolCall, command: String,
                            capability: AgentCapability, risk: AgentRiskLevel,
                            allowed: Bool) async -> AgentToolOutcome {
    store.updateAgentEvent(id: call.id) { $0.state = .running }
    let profile: String
    switch capability {
    case .read:
      profile = SandboxRunner.readOnlyProfile()
    case .write(let path):
      profile = SandboxRunner.scopedProfile(writablePaths: [Self.writableScope(for: path)])
    case .network:
      profile = SandboxRunner.scopedProfile(writablePaths: [], allowNetwork: true)
    case .elevated:
      profile = SandboxRunner.elevatedProfile(writablePaths: [])
    case .blocked:
      profile = SandboxRunner.readOnlyProfile()
    }
    let started = Date()
    let result = SandboxRunner.run(command, profile: profile, timeout: 60)
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let output = Self.outputText(result)
    store.updateAgentEvent(id: call.id) {
      $0.state = result.succeeded ? .done : .failed
      $0.output = output
      $0.elapsedMs = elapsed
    }
    AgentAudit.record(command: command, level: capability.level, risk: risk,
                      decision: allowed ? "allow" : "deny",
                      exitCode: result.exitCode, elapsedMs: elapsed)
    return AgentToolOutcome(output: output, denied: false,
                             level: capability.level, risk: risk)
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
