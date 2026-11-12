import Foundation

// [FEATURE] 격리 브라우저 도구 실행 (v0.38.1, PLAN_v0.38.1 §4·§5.5·§9)
//
// 브라우저도 **기존 신뢰 모델**을 그대로 탄다.
//   · 읽기(open·read·back)는 설정의 읽기 정책을 따른다.
//   · 링크 이동은 읽기, 그 밖의 클릭·입력·제출은 **항상 승인**이다.
//   · 승인 카드는 `AgentApprovalRequest`(기존 경로) — Job 이면 10분 뒤 일시 중지·알림.
//   · 감사 로그에는 입력값을 남기지 않는다(필드 이름까지만).
//   · 읽은 페이지는 답변 출처 카드에 쌓인다.
//
// 게이트는 셋이다: `settings.browserEnabled` + `settings.agentToolsEnabled` +
// 이번 턴 도구 목록에 `browser_*` 가 실제로 들어 있는지(비서의 웹 토글·Apple FM 제외).

extension AgentExecutor {
  // MARK: - 진입점

  func runBrowser(_ call: AgentToolCall, tools: [AgentTool]) async -> AgentToolOutcome {
    guard store.settings.agentToolsEnabled else {
      return browserFail(call, text: L("도우미 도구가 꺼져 있습니다 — 설정 › 도구·권한에서 켜세요."),
                         denied: true)
    }
    guard store.settings.browserEnabled else {
      return browserFail(call, text: L("격리 브라우저가 꺼져 있습니다 — 설정 › 도구·권한에서 켜세요."),
                         denied: true)
    }
    guard tools.contains(where: { $0.name == call.name }) else {
      return browserFail(call, text: L("이 대화의 비서는 브라우저 도구를 쓸 수 없습니다."),
                         denied: true)
    }
    switch call.name {
    case "browser_open": return await runBrowserOpen(call)
    case "browser_read": return await runBrowserRead(call)
    case "browser_back": return await runBrowserBack(call)
    case "browser_click": return await runBrowserClick(call)
    case "browser_type": return await runBrowserType(call)
    case "browser_submit": return await runBrowserSubmit(call)
    default:
      return browserFail(call, text: Lf("지원하지 않는 브라우저 도구입니다: %@", call.name),
                         denied: true)
    }
  }

  // MARK: - 읽기

  private func runBrowserOpen(_ call: AgentToolCall) async -> AgentToolOutcome {
    let raw = call.stringArgument("url") ?? ""
    let url: URL
    do {
      url = try BrowserURLPolicy.validate(raw)
    } catch {
      let text = (error as? BrowserURLPolicy.ValidationError)?.userText
        ?? L("주소 형식이 올바르지 않습니다.")
      return browserFail(call, text: text, denied: true, command: raw)
    }
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true,
                         command: url.absoluteString)
    }
    let maxCharacters = browserMaxCharacters(call)
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: url.absoluteString, level: .read, risk: .normal,
                           state: .pending))
    let approved = await browserApprove(call: call, level: .read,
                                        command: "browser_open \(url.absoluteString)",
                                        detail: Lf("전용 프로필로 엽니다: %@", url.absoluteString),
                                        reason: L("웹 페이지를 읽기 위해 엽니다."),
                                        irreversible: false, force: false)
    guard approved else { return browserDenied(call, command: "browser_open \(url.absoluteString)") }
    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let page = try await service.open(url, maxCharacters: maxCharacters)
      return browserFinishPage(call, page: page, maxCharacters: maxCharacters,
                               started: started, audit: "browser_open \(page.url)",
                               level: .read)
    } catch {
      return browserFailure(call, error: error, audit: "browser_open \(url.absoluteString)",
                            started: started, level: .read)
    }
  }

  private func runBrowserRead(_ call: AgentToolCall) async -> AgentToolOutcome {
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true)
    }
    let maxCharacters = browserMaxCharacters(call)
    let command = service.currentURL?.absoluteString ?? ""
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: command, level: .read, risk: .normal, state: .pending))
    let approved = await browserApprove(call: call, level: .read,
                                        command: "browser_read \(command)",
                                        detail: L("지금 열려 있는 페이지를 다시 읽습니다."),
                                        reason: L("페이지의 최신 내용과 참조를 확인합니다."),
                                        irreversible: false, force: false)
    guard approved else { return browserDenied(call, command: "browser_read \(command)") }
    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let page = try await service.current(maxCharacters: maxCharacters)
      return browserFinishPage(call, page: page, maxCharacters: maxCharacters,
                               started: started, audit: "browser_read \(page.url)",
                               level: .read)
    } catch {
      return browserFailure(call, error: error, audit: "browser_read \(command)",
                            started: started, level: .read)
    }
  }

  private func runBrowserBack(_ call: AgentToolCall) async -> AgentToolOutcome {
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true)
    }
    let maxCharacters = browserMaxCharacters(call)
    let command = service.currentURL?.absoluteString ?? ""
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: command, level: .read, risk: .normal, state: .pending))
    let approved = await browserApprove(call: call, level: .read,
                                        command: "browser_back \(command)",
                                        detail: L("이전 페이지로 돌아갑니다."),
                                        reason: L("앞 페이지로 돌아가 내용을 확인합니다."),
                                        irreversible: false, force: false)
    guard approved else { return browserDenied(call, command: "browser_back \(command)") }
    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let page = try await service.back(maxCharacters: maxCharacters)
      return browserFinishPage(call, page: page, maxCharacters: maxCharacters,
                               started: started, audit: "browser_back \(page.url)",
                               level: .read)
    } catch {
      return browserFailure(call, error: error, audit: "browser_back \(command)",
                            started: started, level: .read)
    }
  }

  // MARK: - 클릭

  private func runBrowserClick(_ call: AgentToolCall) async -> AgentToolOutcome {
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true)
    }
    let ref = call.stringArgument("ref") ?? ""
    let purpose = (call.stringArgument("purpose") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let maxCharacters = browserMaxCharacters(call)
    let plan: BrowserService.ClickPlan
    do {
      plan = try service.clickPlan(ref: ref)
    } catch {
      return browserFailure(call, error: error, audit: "browser_click ref=\(ref)",
                            started: Date(), level: .read)
    }
    let element = plan.element
    let pageURL = service.currentURL?.absoluteString ?? ""
    let label = element.label.isEmpty ? element.name : element.label
    let target = plan.destination?.absoluteString ?? pageURL
    let pageHost = URL(string: pageURL).map { BrowserURLPolicy.displayHost($0) } ?? ""
    let audit = plan.destination == nil
      ? "browser_click \(pageHost) ref=\(ref)"
      : "browser_click link \(target)"
    let level: AgentPermissionLevel = plan.isReadOnlyLink ? .read : .execute
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: target, level: level, risk: .normal, state: .pending))

    if plan.isReadOnlyLink {
      let approved = await browserApprove(call: call, level: .read,
                                          command: audit,
                                          detail: Lf("링크로 이동합니다: %@", target),
                                          reason: browserReason(purpose, fallback: L("페이지 안의 링크를 따라갑니다.")),
                                          irreversible: false, force: false)
      guard approved else { return browserDenied(call, command: audit, level: .read) }
    } else {
      // 링크가 아닌 클릭은 **항상** 승인 — 버튼·체크박스·탭은 서버 상태를 바꿀 수 있다.
      let detail = [
        Lf("페이지: %@", pageURL),
        Lf("요소: %@ (%@)", label.isEmpty ? ref : label, element.kind),
        L("버튼·체크박스·탭 클릭은 페이지나 서버의 상태를 바꿀 수 있습니다."),
      ].joined(separator: "\n")
      let approved = await browserApprove(call: call, level: .execute,
                                          command: audit,
                                          detail: detail,
                                          reason: browserReason(purpose, fallback: L("페이지의 요소를 클릭합니다.")),
                                          irreversible: true, force: true)
      guard approved else { return browserDenied(call, command: audit, level: .execute) }
    }

    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let page = try await service.performClick(ref: ref, maxCharacters: maxCharacters)
      return browserFinishPage(call, page: page, maxCharacters: maxCharacters,
                               started: started, audit: audit, level: level)
    } catch {
      return browserFailure(call, error: error, audit: audit, started: started, level: level)
    }
  }

  // MARK: - 입력·제출

  private func runBrowserType(_ call: AgentToolCall) async -> AgentToolOutcome {
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true)
    }
    let ref = call.stringArgument("ref") ?? ""
    let rawText = call.stringArgument("text") ?? ""
    guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return browserFail(call, text: L("입력할 내용이 비어 있습니다."), denied: true,
                         command: "browser_type ref=\(ref)")
    }
    guard rawText.count <= 2_000 else {
      return browserFail(call, text: L("입력은 2,000자까지만 지원합니다."), denied: true,
                         command: "browser_type ref=\(ref)")
    }
    let purpose = (call.stringArgument("purpose") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let pageURL = service.currentURL?.absoluteString ?? ""
    let element: BrowserElement
    do {
      element = try service.element(ref: ref)
    } catch {
      return browserFailure(call, error: error, audit: "browser_type ref=\(ref)",
                            started: Date(), level: .execute)
    }
    guard !BrowserService.isSensitiveElement(element) else {
      return browserFail(call, text: BrowserService.ServiceError.sensitiveField.userText,
                         denied: true, command: "browser_type ref=\(ref)")
    }
    if let blocked = Self.browserFieldRejection(element) {
      return browserFail(call, text: blocked, denied: true, command: "browser_type ref=\(ref)")
    }
    let field = element.label.isEmpty ? (element.name.isEmpty ? ref : element.name) : element.label
    let preview = String(rawText.prefix(120))
    let audit = "browser_type \(pageURL) field=\(element.name.isEmpty ? field : element.name)"
    let command = [
      "browser_type \(pageURL)",
      Lf("필드: %@ (%@) · ref=%@", field, element.kind, ref),
      Lf("입력할 내용: \"%@\"%@", preview, rawText.count > 120 ? "…" : ""),
    ].joined(separator: "\n")
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: audit, level: .execute, risk: .normal, state: .pending))
    let approved = await browserApprove(call: call, level: .execute,
                                        command: command,
                                        detail: L("입력은 페이지의 검색창·양식에만 들어갑니다. 비밀번호·결제·인증번호 필드는 거부합니다."),
                                        reason: browserReason(purpose, fallback: L("양식에 내용을 입력합니다.")),
                                        irreversible: true, force: true)
    guard approved else { return browserDenied(call, command: audit, level: .execute) }

    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let typed = try await service.type(ref: ref, text: rawText)
      let elapsed = Int(Date().timeIntervalSince(started) * 1000)
      let name = typed.label.isEmpty ? (typed.name.isEmpty ? ref : typed.name) : typed.label
      updateEvent(call.id) {
        $0.state = .done
        $0.output = Lf("%@에 %d자를 입력했습니다.", name, rawText.count)
        $0.elapsedMs = elapsed
      }
      // 감사 로그에는 **입력값을 남기지 않는다** — 필드 이름까지만.
      recordAudit(command: audit, level: .execute, risk: .normal,
                  decision: "allow", exitCode: nil, elapsedMs: elapsed)
      return AgentToolOutcome(output: Lf("%@에 %d자를 입력했습니다. 아직 제출하지 않았습니다 — 필요하면 browser_submit 을 쓰세요.",
                                         name, rawText.count),
                              level: .execute, risk: .normal)
    } catch {
      return browserFailure(call, error: error, audit: audit, started: started, level: .execute)
    }
  }

  private func runBrowserSubmit(_ call: AgentToolCall) async -> AgentToolOutcome {
    guard let service = store.browserService(for: session) else {
      return browserFail(call, text: L("격리 브라우저를 열 수 없습니다."), denied: true)
    }
    let ref = call.stringArgument("ref") ?? ""
    let purpose = (call.stringArgument("purpose") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let maxCharacters = browserMaxCharacters(call)
    let plan: BrowserService.FormPlan
    do {
      plan = try service.formPlan(ref: ref)
    } catch {
      return browserFailure(call, error: error, audit: "browser_submit ref=\(ref)",
                            started: Date(), level: .execute)
    }
    let action = plan.form.action
    let audit = "browser_submit \(plan.method) \(action)"
    var detailLines = [
      Lf("방식: %@", plan.method),
      Lf("보낼 곳: %@", action),
      Lf("필드: %@", plan.fieldNames.isEmpty ? L("(없음)") : plan.fieldNames.joined(separator: ", ")),
    ]
    if plan.isCrossSite {
      detailLines.append(L("⚠️ 지금 페이지와 다른 사이트로 보냅니다."))
    }
    if plan.form.hasSensitive {
      detailLines.append(Lf("표시하지 않은 비밀번호·숨김 필드 %d개가 함께 전송될 수 있습니다.",
                            plan.form.sensitiveCount))
    }
    let command = "browser_submit \(plan.method) \(action)"
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: audit, level: .execute, risk: .normal, state: .pending))
    let approved = await browserApprove(call: call, level: .execute,
                                        command: command,
                                        detail: detailLines.joined(separator: "\n"),
                                        reason: browserReason(purpose, fallback: L("양식을 제출합니다.")),
                                        irreversible: true, force: true)
    guard approved else { return browserDenied(call, command: audit, level: .execute) }

    service.beginModelActivity(call.name)
    defer { service.endModelActivity() }
    updateEvent(call.id) { $0.state = .running }
    let started = Date()
    do {
      let page = try await service.performSubmit(ref: ref, maxCharacters: maxCharacters)
      return browserFinishPage(call, page: page, maxCharacters: maxCharacters,
                               started: started, audit: audit, level: .execute)
    } catch {
      return browserFailure(call, error: error, audit: audit, started: started, level: .execute)
    }
  }

  // MARK: - 공용

  /// 승인 카드 — `force` 면 정책과 무관하게 **항상** 묻는다(상태 변경 동작).
  /// 읽기 동작은 설정의 읽기 정책을 따른다.
  private func browserApprove(call: AgentToolCall, level: AgentPermissionLevel,
                              command: String, detail: String, reason: String,
                              irreversible: Bool, force: Bool) async -> Bool {
    if !force {
      let policy = store.effectiveAgentPolicy(for: session)
      guard AgentToolPermission.needsApproval(tool: call.name, policy: policy) else { return true }
    }
    let request = AgentApprovalRequest(
      command: command,
      level: level,
      risk: .normal,
      capability: .network,
      writablePaths: [],
      reason: reason,
      irreversible: irreversible,
      detail: detail,
      allowsAlwaysAllow: false)
    let choice = await requestApproval(request)
    switch choice {
    case .allowOnce, .allowScope, .allowApp, .alwaysAllow:
      return true
    case .deny:
      return false
    }
  }

  private func browserReason(_ purpose: String, fallback: String) -> String {
    purpose.isEmpty ? fallback : purpose
  }

  private func browserMaxCharacters(_ call: AgentToolCall) -> Int {
    min(max(call.intArgument("max_characters") ?? 10_000, 500), 20_000)
  }

  /// 페이지 스냅샷을 모델 출력·카드·출처로 바꾼다.
  private func browserFinishPage(_ call: AgentToolCall, page: BrowserPageSnapshot,
                                 maxCharacters: Int, started: Date,
                                 audit: String, level: AgentPermissionLevel) -> AgentToolOutcome {
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let links = page.elements.filter(\.isLink).count
    let summary = Lf("본문 %d자 · 링크 %d개 · 양식 %d개",
                     min(page.text.count, maxCharacters), links, page.forms.count)
    updateEvent(call.id) {
      $0.state = .done
      $0.output = summary
      $0.elapsedMs = elapsed
    }
    addTurnSource(TurnSource(title: page.title.isEmpty ? page.url : page.title,
                             url: page.url,
                             domain: WebText.domain(of: page.url),
                             snippet: String(page.text.prefix(120))))
    recordAudit(command: audit, level: level, risk: .normal,
                decision: "allow", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: BrowserToolText.render(page, maxCharacters: maxCharacters),
                            level: level, risk: .normal)
  }

  private func browserFailure(_ call: AgentToolCall, error: Error, audit: String,
                              started: Date, level: AgentPermissionLevel) -> AgentToolOutcome {
    let elapsed = Int(Date().timeIntervalSince(started) * 1000)
    let text = (error as? BrowserService.ServiceError)?.userText ?? error.localizedDescription
    updateEvent(call.id) {
      $0.state = .failed
      $0.output = text
      $0.elapsedMs = elapsed
    }
    recordAudit(command: audit, level: level, risk: .normal,
                decision: "deny", exitCode: nil, elapsedMs: elapsed)
    return AgentToolOutcome(output: text, denied: true, level: level, risk: .normal)
  }

  /// 검증 단계에서 막힌 호출 — 카드 한 장을 failed 로 남기고 모델에 이유를 돌려준다.
  private func browserFail(_ call: AgentToolCall, text: String, denied: Bool,
                           command: String = "") -> AgentToolOutcome {
    let title = AgentRunner.title(for: call, tools: AgentToolCatalog.browserTools)
    appendEvent(AgentEvent(id: call.id, toolName: call.name, title: title,
                           command: command, level: .read, risk: .normal,
                           state: .failed, output: text))
    if !command.isEmpty {
      recordAudit(command: "\(call.name) \(command)", level: .read, risk: .normal,
                  decision: denied ? "deny" : "allow", exitCode: nil, elapsedMs: 0)
    }
    return AgentToolOutcome(output: text, denied: denied, level: .read, risk: .normal)
  }

  private func browserDenied(_ call: AgentToolCall, command: String,
                             level: AgentPermissionLevel = .read) -> AgentToolOutcome {
    let text = L("사용자가 승인하지 않아 실행하지 않았습니다.")
    updateEvent(call.id) { $0.state = .denied; $0.output = text }
    recordAudit(command: command, level: level, risk: .normal,
                decision: "deny", exitCode: nil, elapsedMs: 0)
    return AgentToolOutcome(output: text, denied: true, level: level, risk: .normal)
  }

  /// `browser_type` 이 거부해야 하는 필드 종류 — 스냅샷에서 빠졌더라도 한 번 더 막는다.
  static func browserFieldRejection(_ element: BrowserElement) -> String? {
    let type = element.type.lowercased()
    if ["password", "file", "hidden", "submit", "button", "reset", "image"].contains(type) {
      return BrowserService.ServiceError.sensitiveField.userText
    }
    switch element.kind {
    case "input", "textarea", "select": return nil
    default:
      return Lf("이 요소(%@)에는 입력할 수 없습니다.", element.kind)
    }
  }
}
