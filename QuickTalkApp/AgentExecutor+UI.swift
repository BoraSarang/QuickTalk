import AppKit
import ApplicationServices
import Foundation

// [FEATURE] `ui_action` 실행 — 승인 · 재해석 · 주입 · 감사 (PLAN_v0.25 Phase 2)
//
// 판정 순서(PLAN §6)
//   ① 마스터 토글 → ② 금지 앱 · 보안 필드 · 금지 키 → ③ 실행 한도
//   → ④ 사용자 입력 유휴 → ⑤ 앱 승인 → ⑥ 단계 정책 → ⑦ 경로 재해석 → ⑧ 주입 → ⑨ 감사
//
// 이 파일은 판정을 직접 만들지 않는다 — `UiGuard`(순수)가 정하고, 여기서는 그 결과를 따른다.

extension AgentExecutor {
  // MARK: - 스냅샷 캐시

  /// `ui_snapshot` 결과를 앱별로 기억한다 — 참조를 경로로 되돌리는 데 쓴다.
  func cacheUiTree(_ tree: UiTree) {
    let key = Self.uiTreeKey(tree.target)
    uiTrees[key] = tree
    lastUiTreeKey = key
  }

  private static func uiTreeKey(_ target: UiAppTarget) -> String {
    target.bundleID.isEmpty ? target.name.lowercased() : target.bundleID.lowercased()
  }

  private func currentUiTree() -> UiTree? {
    guard let key = lastUiTreeKey else { return nil }
    return uiTrees[key]
  }

  private func cachedUiTree(for app: String) -> UiTree? {
    let lower = app.lowercased()
    if let exact = uiTrees[lower] { return exact }
    return uiTrees.first { _, tree in
      tree.target.bundleID.lowercased() == lower
        || tree.target.name.lowercased() == lower
    }?.value
  }

  // MARK: - 진입점

  func runUiAction(_ call: AgentToolCall) async -> AgentToolOutcome {
    let level = AgentPermissionLevel.execute
    let risk = AgentRiskLevel.normal
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.all)

    func deny(_ text: String, audit: String? = nil) -> AgentToolOutcome {
      recordUiEvent(call: call, title: title, command: audit ?? "", state: .denied,
                    output: text, level: level, risk: risk)
      if let audit {
        AgentAudit.record(command: audit, level: level, risk: risk,
                          decision: "deny", exitCode: nil, elapsedMs: 0)
      }
      return AgentToolOutcome(output: text, denied: true, level: level, risk: risk)
    }

    // ① 마스터 토글 — 목록에 없어야 하지만, 방금 끈 경우를 대비해 한 번 더 막는다.
    guard store.settings.uiControlEnabled else {
      return deny(L("컴퓨터 제어가 꺼져 있어 화면을 조작할 수 없습니다 — 설정 › 도구·권한에서 켜세요."))
    }
    guard AccessibilityService.hasPermission else {
      return deny(UiAccessError.noPermission.message)
    }

    // 인자 검증 — 실패 사유를 모델에게 그대로 돌려준다.
    let spec: UiActionSpec
    switch UiActionSpec.parse(call) {
    case .success(let parsed): spec = parsed
    case .failure(let error): return deny(error.message)
    }

    // ② 대상 앱·요소 해석
    var app: UiAppTarget?
    var sourceTree: UiTree?
    var sourceEntry: UiSnapshot.Entry?
    var target: UiActionTarget?
    var window: UiWindowRef?
    var existingValue: String?

    switch spec.kind {
    case .openApp:
      guard let resolved = AccessibilityService.appTarget(spec.app ?? "") else {
        return deny(UiAccessError.appNotFound(spec.app ?? "").message)
      }
      app = resolved

    case .focusWindow:
      let query = spec.app ?? currentUiTree()?.target.query ?? ""
      guard let resolved = AccessibilityService.appTarget(query) else {
        return deny(UiAccessError.appNotFound(query).message)
      }
      app = resolved
      switch await AccessibilityService.findWindow(app: resolved.query,
                                                   title: spec.title ?? "") {
      case .success(let found): window = found
      case .failure(let error): return deny(error.message)
      }

    case .click, .type, .scroll:
      if let ref = spec.ref {
        // 참조는 **마지막 스냅샷 안에서만** 유효하다.
        let tree: UiTree
        if let explicit = spec.app, !explicit.isEmpty {
          guard let cached = cachedUiTree(for: explicit) else {
            return deny(L("이 앱의 화면 스냅샷이 없습니다 — ui_snapshot 을 먼저 호출하세요."))
          }
          tree = cached
        } else {
          guard let cached = currentUiTree() else {
            return deny(L("요소 참조를 쓰려면 ui_snapshot 을 먼저 호출해야 합니다."))
          }
          tree = cached
        }
        guard let entry = tree.snapshot.entry(ref: ref) else {
          return deny(Lf("마지막 스냅샷에 없는 참조입니다: %@ — ui_snapshot 을 다시 호출하세요.", ref))
        }
        sourceTree = tree
        sourceEntry = entry
        app = tree.target
        target = UiActionTarget(role: entry.role, name: entry.name, isSecure: entry.isSecure)
        // 카드에 남길 현재 값 — 보안 필드는 절대 읽지 않는다(PLAN §4.6).
        if spec.kind == .type, !entry.isSecure, let token = entry.token,
           let element = tree.elements[token] {
          existingValue = AXAccess.string(element, kAXValueAttribute)
        }
      } else {
        let query = spec.app ?? currentUiTree()?.target.query ?? ""
        guard let resolved = AccessibilityService.appTarget(query) else {
          return deny(UiAccessError.appNotFound(query).message)
        }
        app = resolved
        if spec.kind == .type {
          switch await AccessibilityService.focusedTarget(app: resolved.query) {
          case .success(let focused):
            target = focused
            // 보안 필드의 값은 카드에도, 메모리에도 남기지 않는다.
            if !focused.isSecure {
              existingValue = await existingValueOfFocused(app: resolved)
            }
          case .failure(let error):
            return deny(error.message)
          }
        }
      }

    case .key:
      let query = spec.app ?? currentUiTree()?.target.query ?? ""
      guard let resolved = AccessibilityService.appTarget(query) else {
        return deny(UiAccessError.appNotFound(query).message)
      }
      app = resolved
    }

    guard let app else {
      return deny(L("대상 앱을 찾지 못했습니다 — app 에 앱 이름이나 번들 ID를 넣으세요."))
    }
    guard !app.bundleID.isEmpty else {
      return deny(L("대상 앱의 번들 ID를 확인하지 못했습니다 — 앱 이름을 정확히 지정하세요."))
    }

    let audit = spec.auditCommand(appName: app.name, target: target)
    let display = Self.displayCommand(audit)

    // ③~⑥ 판정 — 금지 앱·키·보안 필드·한도·앱 승인·단계 정책.
    let hasGrant = store.conversation.hasActiveUiAppGrant(bundleID: app.bundleID)
    let policy: AgentAutoApprove = store.effectiveAgentPolicy.autoAcceptAll
      ? .alwaysAllow
      : store.effectiveAgentPolicy.autoApprove(for: .execute)
    let decision = UiGuard.evaluate(spec: spec, target: target,
                                    appBundleID: app.bundleID, appName: app.name,
                                    actionsThisTurn: uiActionsThisTurn,
                                    hasAppGrant: hasGrant, policy: policy)

    switch decision {
    case .deny(let reason):
      return deny(reason, audit: audit)

    case .ask(let reason):
      let detail = cardDetail(spec: spec, appName: app.name, target: target,
                              existingValue: existingValue)
      let request = AgentApprovalRequest(
        command: display, level: level, risk: risk, capability: .unprobed,
        writablePaths: [], reason: reason,
        uiAppName: app.name, uiAppBundleID: app.bundleID,
        irreversible: true, detail: detail)
      recordUiEvent(call: call, title: title, command: display, state: .pending,
                    output: detail, level: level, risk: risk)
      let choice = await requestApproval(request)
      if choice == .deny {
        return deny(L("사용자가 화면 조작을 거부했습니다. 다른 방법을 제안하세요."), audit: audit)
      }
      if choice == .allowApp {
        store.approveUiApp(bundleID: app.bundleID, name: app.name)
      }
      recordUiEvent(call: call, title: title, command: display, state: .running,
                    output: "", level: level, risk: risk)

    case .allow:
      recordUiEvent(call: call, title: title, command: display, state: .running,
                    output: "", level: level, risk: risk)
    }

    // ⑦ 실행 — 취소 손잡이를 만들고, 사용자 입력·경로 재해석을 다시 확인한다.
    let handle = SandboxCancellation()
    uiCancellation = handle
    defer { uiCancellation = nil }

    switch await UiControlService.waitForUserIdle(cancellation: handle) {
    case .ready:
      break
    case .busy:
      return deny(L("사용자가 입력 중이라 실행하지 않았습니다 — 잠시 후 다시 시도하세요."), audit: audit)
    case .cancelled:
      return deny(L("사용자가 중단했습니다."), audit: audit)
    }

    let started = Date()

    // 앱을 앞으로 — 클릭·입력은 그 앱이 앞에 있어야 들어간다.
    if spec.kind != .openApp {
      UiControlService.activate(app)
      try? await Task.sleep(nanoseconds: 120_000_000)
    }
    if handle.isCancelled { return deny(L("사용자가 중단했습니다."), audit: audit) }
    switch await UiControlService.waitForUserIdle(threshold: 0.4, timeout: 0.5,
                                                  cancellation: handle) {
    case .ready:
      break
    case .busy:
      return deny(L("사용자가 입력 중이라 실행하지 않았습니다 — 잠시 후 다시 시도하세요."), audit: audit)
    case .cancelled:
      return deny(L("사용자가 중단했습니다."), audit: audit)
    }

    // 요소가 있으면 **경로로 다시 찾는다** — 스냅샷 이후 UI 가 바뀌었을 수 있다.
    var freshTree = sourceTree
    var freshEntry = sourceEntry
    if let sourceTree, let sourceEntry {
      switch await AccessibilityService.tree(app: sourceTree.target.query) {
      case .success(let tree):
        guard let entry = tree.snapshot.entry(matching: sourceEntry.path),
              entry.role == sourceEntry.role,
              entry.name == sourceEntry.name else {
          return deny(UiAccessError.elementChanged.message, audit: audit)
        }
        if spec.kind == .type, entry.isSecure {
          return deny(L("비밀번호 필드에는 입력할 수 없습니다."), audit: audit)
        }
        if spec.kind == .type, !UiGuard.textRoles.contains(entry.role) {
          return deny(L("입력란 요소가 아닙니다 — ui_snapshot 을 다시 호출해 입력란을 고르세요."),
                      audit: audit)
        }
        freshTree = tree
        freshEntry = entry
        target = UiActionTarget(role: entry.role, name: entry.name, isSecure: entry.isSecure)
      case .failure(let error):
        return deny(error.message, audit: audit)
      }
    } else if spec.kind == .type {
      // ref 없는 입력 — 포커스가 보안 필드로 옮겨 갔는지 다시 본다.
      switch await AccessibilityService.focusedTarget(app: app.query) {
      case .success(let focused):
        guard !focused.isSecure else {
          return deny(L("비밀번호 필드에는 입력할 수 없습니다."), audit: audit)
        }
        guard UiGuard.textRoles.contains(focused.role) else {
          return deny(L("입력란에 포커스가 없습니다 — 먼저 입력란을 클릭하거나 ref 를 지정하세요."),
                      audit: audit)
        }
        target = focused
      case .failure(let error):
        return deny(error.message, audit: audit)
      }
    }

    await waitForActionSpacing()
    if handle.isCancelled { return deny(L("사용자가 중단했습니다."), audit: audit) }

    let doneText: String
    switch spec.kind {
    case .click:
      guard let entry = freshEntry, let center = entry.center else {
        return deny(UiAccessError.invalidElement.message, audit: audit)
      }
      UiControlService.click(at: center, count: spec.amount)
      doneText = Lf("%@을(를) 클릭했습니다.", target?.label ?? app.name)

    case .type:
      if let tree = freshTree, let entry = freshEntry, let token = entry.token,
         let element = tree.elements[token] {
        let focused = AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString,
                                                   kCFBooleanTrue)
        // 포커스를 못 옮기면 요소 중심을 한 번 눌러 포커스를 준다(입력란만 허용된 상태).
        if focused != .success, let center = entry.center {
          UiControlService.click(at: center, count: 1)
        }
        try? await Task.sleep(nanoseconds: 60_000_000)
      }
      if handle.isCancelled { return deny(L("사용자가 중단했습니다."), audit: audit) }
      UiControlService.typeText(spec.text ?? "")
      doneText = L("텍스트를 입력했습니다.")

    case .key:
      guard UiControlService.press(spec.keys ?? "") else {
        return deny(L("키를 보내지 못했습니다 — 키 이름을 확인하세요."), audit: audit)
      }
      doneText = Lf("키를 보냈습니다: %@", spec.keys ?? "")

    case .scroll:
      let point = freshEntry?.center ?? freshTree?.windowFrame?.center
      UiControlService.scroll(spec.direction ?? .down, amount: spec.amount, at: point)
      doneText = Lf("%@ %d칸 스크롤했습니다.", (spec.direction ?? .down).displayName, spec.amount)

    case .openApp:
      switch await UiControlService.open(app) {
      case .success(let opened):
        doneText = Lf("%@ 앱을 열었습니다.", opened.name)
      case .failure(let error):
        return deny(error.message, audit: audit)
      }

    case .focusWindow:
      if let window {
        _ = AccessibilityService.raise(window)
      } else {
        return deny(UiAccessError.invalidElement.message, audit: audit)
      }
      doneText = Lf("'%@' 창을 앞으로 가져왔습니다.", spec.title ?? app.name)
    }

    uiActionsThisTurn += 1
    lastUiActionAt = Date()
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    recordUiEvent(call: call, title: title, command: display, state: .done,
                  output: doneText, elapsed: elapsed, level: level, risk: risk)
    AgentAudit.record(command: audit, level: level, risk: risk,
                      decision: "allow", exitCode: 0, elapsedMs: elapsed)
    NSLog("[QuickTalk] 화면 조작 실행 — %@ · %d/%d",
          spec.kind.rawValue, uiActionsThisTurn, UiGuard.maxActionsPerTurn)

    let hint = (spec.kind == .openApp || spec.kind == .focusWindow)
      ? ""
      : "\n" + L("UI가 바뀌었다면 ui_snapshot 을 다시 호출해 새 참조를 쓰세요.")
    return AgentToolOutcome(output: doneText + hint, level: level, risk: risk)
  }

  // MARK: - 카드 문구

  private func cardDetail(spec: UiActionSpec, appName: String,
                          target: UiActionTarget?, existingValue: String?) -> String {
    var lines = [spec.describe(appName: appName, target: target),
                 Lf("이유: %@", spec.purpose)]
    if spec.maySend {
      lines.append(L("줄바꿈이 포함되어 있어 메일·메신저에서는 전송이 될 수 있습니다."))
    }
    if let existing = existingValue?.trimmingCharacters(in: .whitespacesAndNewlines),
       !existing.isEmpty {
      lines.append(Lf("현재 값: %@", Self.limited(
        existing.replacingOccurrences(of: "\n", with: "↵"), 120)))
    }
    lines.append(L("이 동작은 되돌릴 수 없습니다."))
    return lines.joined(separator: "\n")
  }

  private func existingValueOfFocused(app: UiAppTarget) async -> String? {
    // 포커스 요소의 값은 카드 참고용 — 보안 필드는 `focusedTarget` 의 isSecure 로 이미 걸러진다.
    guard let pid = app.pid else { return nil }
    return await Task.detached(priority: .userInitiated) {
      let element = AXUIElementCreateApplication(pid)
      AXUIElementSetMessagingTimeout(element, UiSnapshotLimits.messagingTimeout)
      guard let focused = AXAccess.element(element, kAXFocusedUIElementAttribute) else { return nil }
      // 보안 필드는 한 번 더 확인하고 읽지 않는다(카드에도 남기지 않는다).
      if AXAccess.string(focused, kAXSubroleAttribute) == "AXSecureTextField" { return nil }
      return AXAccess.string(focused, kAXValueAttribute)
    }.value
  }

  private static func displayCommand(_ command: String) -> String {
    limited(command, 400)
  }

  private static func limited(_ text: String, _ limit: Int) -> String {
    guard text.count > limit else { return text }
    return String(text.prefix(limit - 1)) + "…"
  }

  // MARK: - 카드 · 간격

  /// 같은 도구 호출 id 는 **카드 1장** — 상태·출력만 바꾼다.
  private func recordUiEvent(call: AgentToolCall, title: String, command: String,
                             state: AgentEvent.State, output: String,
                             elapsed: Int = 0,
                             level: AgentPermissionLevel, risk: AgentRiskLevel) {
    if store.agentEvents.contains(where: { $0.id == call.id }) {
      store.updateAgentEvent(id: call.id) {
        $0.state = state
        $0.output = output
        $0.elapsedMs = elapsed
      }
    } else {
      store.appendAgentEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                                        command: command, level: level, risk: risk,
                                        state: state, output: output, elapsedMs: elapsed))
    }
  }

  /// 동작 사이 150ms — UI 가 따라오지 못해 엉뚱한 곳을 누르는 것을 막는다.
  private func waitForActionSpacing() async {
    guard let last = lastUiActionAt else { return }
    let remaining = UiGuard.minimumInterval - Date().timeIntervalSince(last)
    guard remaining > 0 else { return }
    try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
  }
}
