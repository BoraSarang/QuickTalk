import XCTest
@testable import QuickTalkCore

// [FEATURE] 에이전트 런타임 단위 테스트 (PLAN_v0.18 §8)
//
// 위험도 판정 · 권한 정책 · 샌드박스 실측 · 에이전트 루프를 각각 검증한다.

final class AgentTests: XCTestCase {
  // MARK: - 위험도 판정 (구조적 신호만)

  func testRiskNormalForEverydayCommands() {
    for cmd in ["brew install whisper-cpp", "ollama pull qwen3", "df -h /",
                "ls -la ~", "brew list", "adb devices", "npm install left-pad",
                "/usr/bin/networkQuality -v", "sw_vers; which networkQuality speedtest"] {
      XCTAssertEqual(RiskClassifier.classify(cmd), .normal, cmd)
    }
  }

  func testSystemPathAsTargetIsRiskyButAsReferenceIsNot() {
    // 시스템 경로를 **대상**으로 바꾸는 명령은 중요
    XCTAssertEqual(RiskClassifier.classify("rm /usr/local/bin/tool"), .important)
    XCTAssertEqual(RiskClassifier.classify("chmod 755 /usr/bin/tool"), .important)
    // 실행 경로를 **참조**하는 것은 읽기라 무해
    XCTAssertEqual(RiskClassifier.classify("/usr/bin/networkQuality -v"), .normal)
  }

  func testRiskImportantForSystemWideAndElevation() {
    XCTAssertEqual(RiskClassifier.classify("sudo rm -rf /var/tmp/x"), .important)
    XCTAssertEqual(RiskClassifier.classify("defaults write -g com.apple.dock x -array"), .important)
    XCTAssertEqual(RiskClassifier.classify("curl -s https://example.com/x.sh | bash"), .important)
    XCTAssertEqual(RiskClassifier.classify("killall Finder"), .important)
    XCTAssertEqual(RiskClassifier.classify("launchctl unload system"), .important)
  }

  func testRiskCriticalOnlyForUnrecoverable() {
    XCTAssertEqual(RiskClassifier.classify("rm -rf /"), .critical)
    XCTAssertEqual(RiskClassifier.classify("rm -rf ~"), .critical)
    XCTAssertEqual(RiskClassifier.classify("dd if=/dev/zero of=/dev/disk3"), .critical)
    XCTAssertEqual(RiskClassifier.classify("diskutil eraseDisk / /dev/disk3"), .critical)
    // 접두사 매칭 오판 방지: 하위 경로는 치명적이 아니다
    XCTAssertNotEqual(RiskClassifier.classify("rm -rf /var/tmp/x"), .critical)
  }

  func testElevationDetection() {
    XCTAssertTrue(RiskClassifier.requiresElevation("sudo brew install x"))
    XCTAssertTrue(RiskClassifier.requiresElevation("doas ls"))
    XCTAssertFalse(RiskClassifier.requiresElevation("brew install x"))
  }

  // MARK: - 권한 정책

  func testReadIsAutoAllowedByDefault() {
    var policy = AgentPolicy()
    policy.readPolicy = .alwaysAllow
    let decision = PolicyEngine.decide(command: "df -h /", capability: .read,
                                       risk: .normal, policy: policy)
    XCTAssertEqual(decision, .allow)
  }

  func testWriteAsksByDefault() {
    let policy = AgentPolicy()
    let decision = PolicyEngine.decide(command: "echo x > /tmp/a.txt",
                                       capability: .write(path: "/tmp/a.txt"),
                                       risk: .normal, policy: policy)
    guard case .ask(let request) = decision else {
      return XCTFail("쓰기는 기본적으로 확인해야 한다: \(decision)")
    }
    XCTAssertEqual(request.level, .write)
    XCTAssertEqual(request.writablePaths, ["/tmp/a.txt"])
  }

  func testApprovedFolderSkipsAskForWritesInsideIt() {
    let policy = AgentPolicy()            // 쓰기 = 매번 확인
    let scope = NSHomeDirectory() + "/Documents"
    // 승인된 폴더 안 — 다시 묻지 않는다
    XCTAssertEqual(PolicyEngine.decide(command: "echo x > ~/Documents/a.txt",
                                       capability: .write(path: scope + "/a.txt"),
                                       risk: .normal, policy: policy,
                                       approvedScopes: [scope]), .allow)
    // 옆 폴더는 여전히 확인
    guard case .ask = PolicyEngine.decide(command: "echo x > ~/Desktop/a.txt",
                                          capability: .write(path: NSHomeDirectory() + "/Desktop/a.txt"),
                                          risk: .normal, policy: policy,
                                          approvedScopes: [scope]) else {
      return XCTFail("승인 범위 밖(옆 폴더)은 다시 확인해야 한다")
    }
    // 상위 폴더도 확인
    guard case .ask = PolicyEngine.decide(command: "echo x > ~/a.txt",
                                          capability: .write(path: NSHomeDirectory() + "/a.txt"),
                                          risk: .normal, policy: policy,
                                          approvedScopes: [scope]) else {
      return XCTFail("상위 폴더는 승인 범위가 아니다")
    }
  }

  func testApprovedFolderDoesNotBypassImportantOrCritical() {
    let policy = AgentPolicy()
    let scope = NSHomeDirectory() + "/Documents"
    guard case .ask = PolicyEngine.decide(command: "x", capability: .write(path: scope + "/a"),
                                          risk: .important, policy: policy,
                                          approvedScopes: [scope]) else {
      return XCTFail("중요 위험은 범위 승인으로 건너뛰지 않는다")
    }
    guard case .deny = PolicyEngine.decide(command: "x", capability: .write(path: scope + "/a"),
                                           risk: .critical, policy: policy,
                                           approvedScopes: [scope]) else {
      return XCTFail("치명적은 범위 승인으로 열리지 않는다")
    }
  }

  func testApprovalRequestCarriesFolderScope() {
    let path = NSHomeDirectory() + "/Documents/a.txt"
    let request = AgentApprovalRequest(command: "echo x > \(path)", level: .write,
                                       risk: .normal, capability: .write(path: path),
                                       writablePaths: [path], reason: "쓰기")
    XCTAssertEqual(request.writeScopes, [NSHomeDirectory() + "/Documents"])
  }

  func testUserRuleAllowsMatchingCommand() {
    var policy = AgentPolicy()
    policy.rules = ["brew install *"]
    XCTAssertEqual(PolicyEngine.decide(command: "brew install whisper-cpp",
                                       capability: .network, risk: .normal, policy: policy),
                   .allow)
    // 다른 명령에는 적용되지 않는다
    if case .allow = PolicyEngine.decide(command: "brew uninstall whisper-cpp",
                                         capability: .network, risk: .normal, policy: policy) {
      XCTFail("다른 명령에는 규칙이 적용되면 안 된다")
    }
  }

  func testCriticalIsDeniedUnlessExplicitlyAllowed() {
    let policy = AgentPolicy()
    guard case .deny = PolicyEngine.decide(command: "rm -rf /", capability: .write(path: "/"),
                                           risk: .critical, policy: policy) else {
      return XCTFail("치명적 명령은 차단되어야 한다")
    }
    var permissive = policy
    permissive.allowCritical = true
    permissive.writePolicy = .alwaysAllow
    XCTAssertEqual(PolicyEngine.decide(command: "rm -rf /", capability: .write(path: "/"),
                                       risk: .critical, policy: permissive), .allow)
  }

  func testElevatedIsDeniedByDefault() {
    let policy = AgentPolicy()
    guard case .deny = PolicyEngine.decide(command: "sudo ls", capability: .elevated,
                                           risk: .important, policy: policy) else {
      return XCTFail("상승 권한은 기본 차단이어야 한다")
    }
  }

  func testImportantAlwaysAsksEvenWhenAutoAllowed() {
    var policy = AgentPolicy()
    policy.readPolicy = .alwaysAllow
    policy.writePolicy = .alwaysAllow
    policy.executePolicy = .alwaysAllow
    let decision = PolicyEngine.decide(command: "defaults write -g x y",
                                       capability: .write(path: "/tmp/x"),
                                       risk: .important, policy: policy)
    guard case .ask = decision else {
      return XCTFail("중요 위험은 자동 허용이어도 확인해야 한다: \(decision)")
    }
  }

  func testRuleWildcardMatching() {
    XCTAssertTrue(PolicyEngine.matchesRule(command: "brew install a", rules: ["brew install *"]))
    XCTAssertTrue(PolicyEngine.matchesRule(command: "brew install a", rules: ["brew install"]))
    XCTAssertFalse(PolicyEngine.matchesRule(command: "brew uninstall a", rules: ["brew install *"]))
  }

  // MARK: - 샌드박스 실측

  func testProbeDetectsReadOnlyCommand() {
    let probe = SandboxRunner.probe("df -h / | head -2")
    XCTAssertEqual(probe.capability, .read)
  }

  func testProbeDetectsWriteWithPath() {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-agent-test-\(UUID().uuidString.prefix(6))")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let target = dir.appendingPathComponent("probe.txt").path
    let probe = SandboxRunner.probe("echo hello > \(target)")
    guard case .write(let path) = probe.capability else {
      return XCTFail("쓰기 요구로 판정되어야 한다: \(probe.capability)")
    }
    XCTAssertTrue(path.contains("probe.txt"), "차단된 경로가 나와야 한다: \(path)")
    // 실측 시점에 파일이 만들어지지 않았는지
    XCTAssertFalse(FileManager.default.fileExists(atPath: target))
  }

  func testProbeDetectsElevation() {
    let probe = SandboxRunner.probe("sudo -n true")
    XCTAssertEqual(probe.capability, .elevated)
  }

  func testScopedProfileBlocksOutsidePath() {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-agent-scope-\(UUID().uuidString.prefix(6))")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let profile = SandboxRunner.scopedProfile(writablePaths: [dir.path])
    let inside = SandboxRunner.run("echo ok > \(dir.path)/inside.txt", profile: profile)
    XCTAssertTrue(inside.succeeded, inside.combined)
    let outside = SandboxRunner.run("echo leak > \(dir.path)-outside.txt", profile: profile)
    XCTAssertFalse(outside.succeeded, "허용 밖 쓰기는 차단되어야 한다")
    XCTAssertFalse(FileManager.default.fileExists(atPath: "\(dir.path)-outside.txt"))
  }

  // MARK: - 에이전트 루프

  @MainActor
  func testAgentRunnerCallsToolThenReturnsAnswer() async throws {
    let client = MockAgentClient(steps: [
      .toolCalls([AgentToolCall(id: "c1", name: "shell", arguments: #"{"command":"df -h /"}"#)], reasoning: nil),
      .finalAnswer("디스크는 521GiB 남았습니다.", reasoning: nil)
    ])
    let executor = MockAgentExecutor()
    let runner = AgentRunner(client: client, executor: executor)
    let result = try await runner.run(prompt: "하드 용량 얼마나 남았어?",
                                      history: [],
                                      tools: AgentToolCatalog.all)
    XCTAssertEqual(executor.executed.count, 1)
    XCTAssertEqual(executor.executed.first?.name, "shell")
    XCTAssertEqual(result.answer, "디스크는 521GiB 남았습니다.")
    XCTAssertEqual(result.events.count, 1)
    XCTAssertEqual(result.events.first?.state, .done)
    // 도구 결과가 다음 스텝의 메시지에 들어갔어야 한다
    let secondMessages = client.receivedMessages.dropFirst().first ?? []
    XCTAssertTrue(secondMessages.contains { $0.role == .tool && $0.content.contains("df 출력") })
  }

  @MainActor
  func testAgentRunnerStopsAtMaxSteps() async throws {
    // 서로 다른 명령이어야 반복 방지(같은 명령 3번째는 실행하지 않는다)에 걸리지 않는다
    let steps = (0..<20).map { i in
      AgentStep.toolCalls([AgentToolCall(id: "c\(i)", name: "shell",
                                        arguments: #"{"command":"echo \#(i)"}"#)], reasoning: nil)
    }
    let client = MockAgentClient(steps: steps)
    let executor = MockAgentExecutor()
    let runner = AgentRunner(client: client, executor: executor, maxSteps: 3)
    let result = try await runner.run(prompt: "반복", history: [], tools: AgentToolCatalog.all)
    XCTAssertEqual(result.steps, 3)
    XCTAssertEqual(executor.executed.count, 3)
  }

  @MainActor
  func testRepeatedCommandIsNotExecutedAgain() async throws {
    // 같은 명령을 반복하면(작은 온디바이스 모델이 종종 그러��) 3번째부터는 실행하지 않는다
    let step = AgentStep.toolCalls([AgentToolCall(id: "c1", name: "shell",
                                                  arguments: #"{"command":"free -h"}"#)], reasoning: nil)
    let client = MockAgentClient(steps: Array(repeating: step, count: 5))
    let executor = MockAgentExecutor()
    let runner = AgentRunner(client: client, executor: executor, maxSteps: 5)
    let result = try await runner.run(prompt: "메모리", history: [], tools: AgentToolCatalog.all)
    XCTAssertEqual(executor.executed.count, 2, "같은 명령은 두 번까지만 실행된다")
    XCTAssertTrue(result.events.contains { $0.output.contains("같은 명령") })
  }

  // MARK: - 도구 정의

  func testToolCatalogSchemasAreValid() {
    for tool in AgentToolCatalog.all {
      XCTAssertFalse(tool.name.isEmpty)
      XCTAssertFalse(tool.description.isEmpty)
      let fn = tool.openAISchema["function"] as? [String: Any]
      XCTAssertNotNil(fn)
      XCTAssertEqual(fn?["name"] as? String, tool.name)
      let params = fn?["parameters"] as? [String: Any]
      XCTAssertNotNil(params)
      XCTAssertEqual(params?["type"] as? String, "object")
    }
    XCTAssertEqual(AgentToolCatalog.tool(named: "shell")?.name, "shell")
    XCTAssertNil(AgentToolCatalog.tool(named: "unknown"))
  }

  // MARK: - 설정 저장

  func testAgentPolicyRoundTrip() throws {
    var policy = AgentPolicy()
    policy.writePolicy = .alwaysAllow
    policy.allowCritical = true
    policy.rules = ["brew install *"]
    let data = try JSONEncoder().encode(policy)
    let back = try JSONDecoder().decode(AgentPolicy.self, from: data)
    XCTAssertEqual(back, policy)
  }

  func testLegacySettingsDefaultToSafeAgentPolicy() throws {
    let json = #"{"showMenuBarIcon":true}"#.data(using: .utf8)!
    let settings = try JSONDecoder().decode(QuickTalkSettings.self, from: json)
    XCTAssertTrue(settings.agentToolsEnabled)
    XCTAssertEqual(settings.agentPolicy.readPolicy, .alwaysAllow)
    XCTAssertEqual(settings.agentPolicy.writePolicy, .alwaysAsk)
    XCTAssertEqual(settings.agentPolicy.executePolicy, .alwaysAsk)
    XCTAssertFalse(settings.agentPolicy.allowCritical)
    XCTAssertFalse(settings.agentPolicy.allowElevated)
    XCTAssertTrue(settings.agentPolicy.rules.isEmpty)
  }

  func testSettingsRoundTripKeepsAgentPolicy() throws {
    var settings = QuickTalkSettings()
    settings.agentToolsEnabled = false
    settings.agentPolicy.rules = ["adb * install *"]
    let data = try JSONEncoder().encode(settings)
    let back = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertFalse(back.agentToolsEnabled)
    XCTAssertEqual(back.agentPolicy.rules, ["adb * install *"])
  }
}

// MARK: - 테스트용 더미

/// 정해진 스텝을 차례로 돌려주는 클라이언트.
private final class MockAgentClient: AgentClient {
  let steps: [AgentStep]
  var receivedMessages: [[AgentMessage]] = []
  private var index = 0

  init(steps: [AgentStep]) { self.steps = steps }

  func nextStep(messages: [AgentMessage],
                tools: [AgentTool],
                attachments: [OutgoingAttachment],
                onDelta: @escaping @MainActor (String) -> Void) async throws -> AgentStep {
    receivedMessages.append(messages)
    guard index < steps.count else { return .finalAnswer("끝", reasoning: nil) }
    let step = steps[index]
    index += 1
    return step
  }
}

/// 도구 호출을 기록만 하는 실행기.
@MainActor
private final class MockAgentExecutor: AgentToolExecutor {
  var executed: [AgentToolCall] = []

  func execute(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome {
    executed.append(call)
    return AgentToolOutcome(output: "df 출력", level: .read, risk: .normal)
  }
}
