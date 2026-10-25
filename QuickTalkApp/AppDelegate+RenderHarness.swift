import SwiftUI
import AppKit

// [REFACTOR] QA 오프스크린 렌더 하네스 — AppDelegate에서 분리 (2026-10-20)
// `--render=<폴더>` 전용. 실제 설정·기록은 건드리지 않는다.
extension AppDelegate {
  func runQARenderIfRequested() {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--render=") }) else { return }
    let dir = String(arg.dropFirst("--render=".count))
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

    let tabArg = CommandLine.arguments.first(where: { $0.hasPrefix("--settings-tab=") })
    let tab = tabArg.flatMap { QuickTalkSettingsTab(rawValue: String($0.dropFirst("--settings-tab=".count))) } ?? .general

    DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in
      guard let self else { return }
      let suffix = "\(L10n.effective.rawValue)"
      // 렌더에서도 QuickShelf 탭을 고를 수 있게(`--shelf-tab=`)
      if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--shelf-tab=") }) {
        let map: [String: ShelfTab] = ["clipboard": .clipboard, "files": .files, "capture": .capture]
        if let tab = map[String(arg.dropFirst("--shelf-tab=".count))] { self.store.shelfTab = tab }
      }
      // 렌더에서 읽어주기 엔진도 고를 수 있게(`--tts-engine=apple|edge`) — 저장하지 않는다
      if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--tts-engine=") }),
         let engine = TTSEngine(rawValue: String(arg.dropFirst("--tts-engine=".count))) {
        self.store.applyRenderOverride(ttsEngine: engine)
      }
      // 렌더에서 웹 검색 카드를 켠 상태로 볼 수 있게(`--demo-websearch`) — 저장하지 않는다
      if CommandLine.arguments.contains("--demo-websearch") {
        self.store.applyRenderOverride(webSearch: true)
      }
      let settingsHeight = CommandLine.arguments
        .first { $0.hasPrefix("--render-height=") }
        .flatMap { Double($0.dropFirst("--render-height=".count)) }
        .map { CGFloat($0) }
        ?? (CommandLine.arguments.contains("--render-tall") ? 1000 : 600)
      // QA: 503 업스트림 오류를 상태 카드에 그대로 표시해 본다(저장하지 않음)
      if CommandLine.arguments.contains("--demo-upstream-error") {
        let url = URL(string: "http://192.168.86.30:8791/v1")!
        let e = QuickTalkError.serverFailure(.upstream(status: 503, code: "server_error"))
        self.store.lastAICall = .failed(e.code)
        self.store.lastAIErrorDetail = AIErrorText.shortDetail(for: e)
        self.store.providerTestResult = Lf("실패 (%@): %@", e.code,
                                           AIErrorText.detail(for: e, url: url))
      }
      // QA: 공통 메모리 카드가 채워진 상태 — 저장하지 않는다.
      if CommandLine.arguments.contains("--demo-global-memory") {
        self.store.applyRenderOverride(memory: [
          GlobalMemoryEntry(title: L("내 맥 사양"),
                            content: L("MacBook Pro M4 Pro 24GB · macOS 26 · 개발은 Xcode와 SwiftUI를 쓴다."),
                            tags: ["개발", "하드웨어"], alwaysInclude: true),
          GlobalMemoryEntry(title: L("답변 선호"),
                            content: L("항상 한국어로, 결론부터 짧게, 코드는 전체 파일로 준다."),
                            tags: ["말투"], alwaysInclude: true),
          GlobalMemoryEntry(title: L("집 네트워크"),
                            content: L("공유기 192.168.86.1 · 개발 서버 192.168.86.30:8791"),
                            tags: ["네트워크"])
        ])
        self.store.settings.globalMemoryMode = .relevant
      }
      // QA: 요약이 있는 상태의 설정 화면을 그리기 위해 먼저 데모 대화를 심는다.
      if CommandLine.arguments.contains("--demo-memory") {
        self.seedDemoConversation()
      }
      self.renderPNG(AnyView(SettingsView(initialTab: tab).environmentObject(self.store)),
                     size: NSSize(width: 780, height: settingsHeight),
                     to: "\(dir)/settings-\(tab.rawValue)-\(suffix).png")
      if CommandLine.arguments.contains("--demo-hub") {
        self.renderPNG(AnyView(QuickTalkHubView(initialTab: .settings).environmentObject(self.store)),
                       size: HubMetrics.popoverSize,
                       to: "\(dir)/hub-\(suffix).png")
      }
      self.renderPNG(AnyView(ShelfView(store: self.store, chrome: .docked, onClose: {}, onSettings: {})),
                     size: NSSize(width: 300, height: 560),
                     to: "\(dir)/shelf-\(suffix).png")
      self.renderPNG(AnyView(MarkdownText(text: Self.markdownSample).padding(14)),
                     size: NSSize(width: 420, height: 520),
                     to: "\(dir)/markdown-\(suffix).png")
      if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-archive-search=") }) {
        let query = String(arg.dropFirst("--demo-archive-search=".count))
        self.store.archive = [
          Conversation(title: "부산 2박 3일 여행 일정", turns: [
            Turn(role: .user, text: "부산 2박 3일 여행 일정을 짜줘"),
            Turn(role: .assistant, text: "해운대와 감천문화마을을 중심으로 정리했습니다.")
          ]),
          Conversation(title: "부산 맛집 추천", turns: [
            Turn(role: .user, text: "부산에서 조용한 해산물 식당 알려줘")
          ]),
          Conversation(title: "서울 전시회 주말 계획", turns: [
            Turn(role: .user, text: "이번 주말 서울 전시회 일정")
          ]),
          Conversation(title: "부산 숙소 비교", turns: [
            Turn(role: .user, text: "광안리와 해운대 숙소를 비교해줘")
          ])
        ]
        self.renderPNG(AnyView(ContentView(initialTab: 1,
                                          initialArchiveQuery: query,
                                          suppressArchiveLoad: true)
                                .environmentObject(self.store)),
                       size: NSSize(width: 460, height: 620),
                       to: "\(dir)/archive-search-\(suffix).png")
      }
      if CommandLine.arguments.contains(where: {
        $0 == "--demo-chat" || $0.hasPrefix("--demo-chat=") || $0.hasPrefix("--demo-search")
          || $0.hasPrefix("--demo-fallback")
          || $0.hasPrefix("--demo-draft-lines=")
          || $0 == "--demo-agent-write"
          || $0 == "--demo-agent"
      }) {
        self.seedDemoConversation()
        if CommandLine.arguments.contains("--demo-agent") {
          // 도구 실행 카드 — 실제 명령·출력이 그대로 보이는지 확인
          var agentDemo = Conversation(title: L("지금 메모리 얼마나 차지 하고 있냐?"))
          agentDemo.turns = [
            Turn(role: .user, text: L("지금 메모리 얼마나 차지 하고 있냐?"),
                 createdAt: Date().addingTimeInterval(-60)),
            Turn(role: .assistant,
                 text: L("**32 GiB 중 약 15.7 GiB 사용 중**입니다. 사용 여유는 90% — 아주 여유로운 상태입니다."),
                 elapsedMs: 4700,
                 createdAt: Date().addingTimeInterval(-50),
                 agentEvents: Self.agentDemoEvents())
          ]
          self.store.conversation = agentDemo
        }
        if CommandLine.arguments.contains("--demo-agent-write") {
          // v0.19 — 쓰기·되돌리기 카드: [되돌리기] 줄 + [이 폴더 허용] 승인 블록
          let scope = NSHomeDirectory() + "/Documents"
          let entry = UndoEntry(
            id: "undo-demo",
            command: "rm ~/Documents/quicktalk-test.txt",
            scope: scope,
            createdAt: Date().addingTimeInterval(-40),
            items: [UndoItem(path: scope + "/quicktalk-test.txt", existed: true,
                             isDirectory: false, backup: "/tmp/backup")],
            note: L("파일을 QuickTalk 휴지통으로 옮겼습니다. [되돌리기] 로 되살릴 수 있습니다."))
          self.store.agentUndoEntries["e-write"] = entry
          let writeEvent = AgentEvent(
            id: "e-write", toolName: "shell", title: L("테스트 파일 삭제"),
            command: "rm ~/Documents/quicktalk-test.txt",
            level: .write, risk: .normal, state: .done,
            output: "mkdir -p … && mv -f -- …\n"
              + L("파일을 QuickTalk 휴지통으로 옮겼습니다. [되돌리기] 로 되살릴 수 있습니다."),
            elapsedMs: 130, undoID: "undo-demo")
          let turnID = UUID()
          var demo = Conversation(title: L("~/Documents 의 테스트 파일 지워줘"))
          demo.turns = [
            Turn(role: .user, text: L("~/Documents 의 테스트 파일 지워줘"),
                 createdAt: Date().addingTimeInterval(-60)),
            Turn(id: turnID, role: .assistant,
                 text: L("`quicktalk-test.txt` 를 **휴지통으로 옮겼습니다.** 되돌리려면 카드의 [되돌리기] 를 누르세요."),
                 elapsedMs: 1200, createdAt: Date().addingTimeInterval(-50),
                 agentEvents: Self.agentDemoEvents() + [writeEvent])
          ]
          self.store.conversation = demo
          self.store.agentTurnID = turnID
          self.store.agentApproval = AgentApprovalRequest(
            command: "echo \"hello\" > ~/Documents/quicktalk-test.txt",
            level: .write, risk: .normal,
            capability: .write(path: scope + "/quicktalk-test.txt"),
            writablePaths: [scope + "/quicktalk-test.txt"],
            reason: L("파일을 만들려면 쓰기 권한이 필요합니다."))
          self.renderPNG(AnyView(ContentView().environmentObject(self.store)),
                         size: NSSize(width: 460, height: 820),
                         to: "\(dir)/chat-agent-write-\(suffix).png")
        }
        let draftLines = CommandLine.arguments
          .first { $0.hasPrefix("--demo-draft-lines=") }
          .flatMap { Int($0.dropFirst("--demo-draft-lines=".count)) } ?? 0
        let initialHeight = draftLines > 0 ? CGFloat((draftLines + 1) * 16 + 12) : 28
        let chatName = CommandLine.arguments.contains("--demo-agent") ? "chat-agent" : "chat"
        self.renderPNG(AnyView(ContentView(initialInputHeight: initialHeight).environmentObject(self.store)),
                       size: NSSize(width: 460, height: 620),
                       to: "\(dir)/\(chatName)-\(suffix).png")
      }
      if CommandLine.arguments.contains("--demo-settings-wide") {
        if CommandLine.arguments.contains("--demo-ping") {
          self.store.providerTestResult = Lf("응답: %@", "pong")
          self.store.lastAICall = .ok
        }
    if CommandLine.arguments.contains("--demo-error") {
          let url = URL(string: "http://192.168.86.30:8791/v1")!
          let e = URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLErrorKey: url])
          self.store.lastAICall = .failed(AIErrorText.code(for: e))
          self.store.lastAIErrorDetail = AIErrorText.shortDetail(for: e)
          self.store.providerTestResult = Lf("실패 (%@): %@", AIErrorText.code(for: e),
                                             AIErrorText.detail(for: e, url: url))
        }
        // 대화 창의 설정 탭 — 넓힌 창에서 카드가 가로로 늘어나는지 확인
        self.renderPNG(AnyView(ContentView(initialTab: 2).environmentObject(self.store)),
                       size: NSSize(width: 960, height: 560),
                       to: "\(dir)/settings-tab-wide-\(suffix).png")
      }
      if CommandLine.arguments.contains("--demo-rename") {
        self.renderPNG(AnyView(
          ZStack {
            Color(nsColor: .windowBackgroundColor)
            RenameSheet(original: L("구구단 만들어줘"), onSave: { _ in })
          }),
          size: NSSize(width: 420, height: 210),
          to: "\(dir)/rename-\(suffix).png")
      }
      if CommandLine.arguments.contains(where: {
        $0 == "--demo-delete-confirm" || $0.hasPrefix("--demo-delete-confirm=")
      }) {
        let all = CommandLine.arguments.contains("--demo-delete-confirm=all")
        self.renderPNG(AnyView(
          ZStack {
            Color(nsColor: .windowBackgroundColor)
            DeleteConfirmSheet(
              heading: all ? L("기록을 모두 지울까요?") : L("대화 기록을 삭제할까요?"),
              target: all ? Lf("대화 %d개", 12) : L("구구단 만들어줘"),
              message: all
                ? L("보관함의 모든 대화가 삭제됩니다. 보관한 대화도 포함되며 되돌릴 수 없습니다.")
                : Lf("이 대화의 %d개 턴이 기록에서 삭제됩니다. 되돌릴 수 없습니다.", 4),
              confirmLabel: all ? L("모두 지우기") : L("삭제"),
              onConfirm: {}
            )
          }),
          size: NSSize(width: 420, height: 230),
          to: "\(dir)/delete-confirm-\(all ? "all" : "one")-\(suffix).png")
      }
      if CommandLine.arguments.contains("--demo-pill") {
        let recent = [
          Conversation(title: "포인터 pill 설계 회의",
                       turns: [Turn(role: .user, text: "pill은 언제 뜨나?")],
                       updatedAt: Date().addingTimeInterval(-120)),
          Conversation(title: "QuickShelf 캡처 정리",
                       turns: [Turn(role: .user, text: "캡처 정리해줘")],
                       updatedAt: Date().addingTimeInterval(-3_600)),
          Conversation(title: "모델 비교 — Ollama vs 원격",
                       turns: [Turn(role: .user, text: "모델 비교")],
                       pinned: true,
                       updatedAt: Date().addingTimeInterval(-86_400))
        ]
        let empty = PillModel()
        let listed = PillModel()
        listed.showList = true
        listed.recent = recent
        let typed = PillModel()
        typed.text = "내일 서울 날씨 알려줘"
        let multiline = PillModel()
        multiline.text = "내일 서울 날씨 알려줘\n그리고 이번 주 일정도 같이 보여줘"
        // 렌더는 값을 프로그램적으로 넣어(textDidChange 없음) 측정이 일어나지 않는다 → 높이를 명시한다
        multiline.inputHeight = 2 * 18 + 12   // 2줄 × 줄높이 18 + 위아래 여백 12
        self.renderPNG(AnyView(Self.pillStage(empty)),
                       size: NSSize(width: 460, height: 140),
                       to: "\(dir)/pill-\(suffix).png")
        self.renderPNG(AnyView(Self.pillStage(typed)),
                       size: NSSize(width: 460, height: 140),
                       to: "\(dir)/pill-typed-\(suffix).png")
        self.renderPNG(AnyView(Self.pillStage(multiline)),
                       size: NSSize(width: 460, height: 200),
                       to: "\(dir)/pill-multiline-\(suffix).png")
        self.renderPNG(AnyView(Self.pillStage(listed)),
                       size: NSSize(width: 460, height: 320),
                       to: "\(dir)/pill-list-\(suffix).png")
      }
      if CommandLine.arguments.contains("--demo-pill-height") {
        // 회귀(2026-10-23): 빈 입력인데 이전 여러 줄 높이가 남아 pill 내용이 위로 몰려 보이던 문제.
        // 2줄로 자란 뒤 글자를 지워도 **측정값이 늦게 와도** 본체는 1줄(56)이어야 한다.
        let m = PillModel()
        m.text = "가나\n다라"
        m.inputHeight = 49
        let grown = PillMetrics.capsuleHeight(text: m.text, inputHeight: m.inputHeight)
        self.renderPNG(AnyView(Self.pillPanelStage(m)),
                       size: NSSize(width: PillMetrics.width,
                                    height: grown + max(0, grown - PillMetrics.height)),
                       to: "\(dir)/pill-height-2line.png")
        NSLog("[PILL-HEIGHT] 2줄 → inputHeight=49 capsule=%.1f", grown)
        m.text = ""
        let cleared = PillMetrics.capsuleHeight(text: m.text, inputHeight: m.inputHeight)
        self.renderPNG(AnyView(Self.pillPanelStage(m)),
                       size: NSSize(width: PillMetrics.width, height: PillMetrics.height),
                       to: "\(dir)/pill-height-cleared.png")
        NSLog("[PILL-HEIGHT] 지운 뒤(낡은 측정값 49 유지) → capsule=%.1f (기대 56)", cleared)
        // 실제로 새로 열 때의 상태(inputHeight 0)도 같은 모양이어야 한다
        m.inputHeight = 0
        self.renderPNG(AnyView(Self.pillPanelStage(m)),
                       size: NSSize(width: PillMetrics.width, height: PillMetrics.height),
                       to: "\(dir)/pill-height-fresh.png")
        NSLog("[PILL-HEIGHT] 새로 열기(inputHeight 0) → capsule=%.1f",
              PillMetrics.capsuleHeight(text: m.text, inputHeight: m.inputHeight))
      }
      NSLog("[QuickTalk] QA 렌더 완료: %@ (lang=%@)", dir, L10n.effective.rawValue)
      NSApp.terminate(nil)
    }
  }

  /// QA: `--search-test=<질문>` — 저장된 Exa 키로 실제 검색 1회.
  /// 창을 띄우지 않고 **건수·지연·도메인만** 로그에 남긴다(검색어·본문·키 금지).
  func runWebSearchSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--search-test=") }) else {
      return false
    }
    let query = String(arg.dropFirst("--search-test=".count))
    store.applyRenderOverride(webSearch: true)
    Task { @MainActor in
      let started = Date()
      let outcome = await self.store.searchWeb(query: query, useCache: false)
      let ms = Int(Date().timeIntervalSince(started) * 1000)
      switch outcome {
      case .success(let results):
        let domains = Set(results.map(\.domain)).sorted().joined(separator: ",")
        NSLog("[SEARCH-TEST] OK results=%d ms=%d domains=%@", results.count, ms, domains)
      case .failure(let error):
        NSLog("[SEARCH-TEST] FAIL code=%@ ms=%d", error.code, ms)
      }
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--answer-test=<질문>` — Exa `/answer` 1회. 답변·인용 길이만 로그에 남긴다.
  func runAnswerSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--answer-test=") })
    else { return false }
    let query = String(arg.dropFirst("--answer-test=".count))
    store.applyRenderOverride(webSearch: true)
    Task { @MainActor in
      let started = Date()
      let outcome = await self.store.answerWeb(query: query)
      let ms = Int(Date().timeIntervalSince(started) * 1000)
      switch outcome {
      case .success(let result):
        NSLog("[ANSWER-TEST] OK chars=%d citations=%d ms=%d",
              result.answer.count, result.sources.count, ms)
      case .failure(let error):
        NSLog("[ANSWER-TEST] FAIL code=%@ ms=%d", error.code, ms)
      }
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--tool-test=<질문>` — 활성 OpenAI 호환 모델에 tools를 붙여 1왕복.
  func runToolCallingSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--tool-test=") })
    else { return false }
    let query = String(arg.dropFirst("--tool-test=".count))
    applyProviderOverrideForSelfTest()
    Task { @MainActor in
      let started = Date()
      let result = await self.store.toolCallingSelfTest(query: query)
      NSLog("[TOOL-TEST] %@ ms=%d", result, Int(Date().timeIntervalSince(started) * 1000))
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--agent-test=<질문>` — 도우미 도구 1회(헤드리스). 도구 실행·권한 판정·최종 답 로그.
  func runAgentSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--agent-test=") })
    else { return false }
    let query = String(arg.dropFirst("--agent-test=".count))
    applyProviderOverrideForSelfTest()
    Task { @MainActor in
      let started = Date()
      let result = await self.store.agentSelfTest(query: query)
      NSLog("[AGENT-TEST] %@ ms=%d", result, Int(Date().timeIntervalSince(started) * 1000))
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--provider=applefm|ollama|remote` — 실검증에서 활성 프로바이더만 메모리에서 바꾼다.
  func applyProviderOverrideForSelfTest() {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--provider=") }) else { return }
    let map: [String: LLMProviderType] = ["applefm": .appleFM, "apple": .appleFM,
                                          "ollama": .ollama, "remote": .openAICompatible]
    if let type = map[String(arg.dropFirst("--provider=".count)).lowercased()] {
      store.applyRenderOverride(providerType: type)
    }
  }

  /// QA: `--fallback-test` — 예비 모델 폴백 경로 1회.
  /// 주 모델은 **연결 불가 주소**(127.0.0.1:9)로 즉시 실패시키고, 예비 모델(Apple FM)이 답하는지 본다.
  /// 설정은 프로세스 한정(저장하지 않음). 로그에는 코드·지연·글자수만 남긴다.
  func runFallbackSelfTestIfRequested() -> Bool {
    guard CommandLine.arguments.contains("--fallback-test") else { return false }
    Task { @MainActor in
      var primary = LLMProviderConfig.newProvider(type: .ollama, existing: [])
      primary.baseURL = "http://127.0.0.1:9"
      primary.model = "fallback-probe"
      primary.enabled = true
      let fallback = LLMProviderConfig.newProvider(type: .appleFM, existing: [])
      var settings = QuickTalkSettings()
      settings.providers = [primary, fallback]
      settings.activeProviderID = primary.id
      settings.fallbackProviderID = fallback.id
      let started = Date()
      var deltas = 0
      do {
        let text = try await UIStore.streamReplyWithFallback(
          settings: settings, provider: primary, prompt: "핑", history: [], attachments: [],
          onDelta: { _ in deltas += 1 })
        NSLog("[FALLBACK-TEST] OK chars=%d deltas=%d ms=%d note=%d",
              text.count, deltas, Int(Date().timeIntervalSince(started) * 1000),
              text.contains("예비 모델") ? 1 : 0)
      } catch {
        NSLog("[FALLBACK-TEST] FAIL code=%@", AIErrorText.code(for: error))
      }
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--search-decide-test=<질문>` — "필요할 때만" 자동 판정만 확인한다(검색·답변 없음).
  /// 로그에는 YES/NO와 지연만 남긴다(질문 내용 금지).
  func runSearchDecideSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--search-decide-test=") })
    else { return false }
    let query = String(arg.dropFirst("--search-decide-test=".count))
    store.applyRenderOverride(webSearch: true)
    applyProviderOverrideForSelfTest()
    Task { @MainActor in
      let started = Date()
      let needed = await self.store.decidesToSearch(query)
      NSLog("[SEARCH-DECIDE] %@ ms=%d", needed ? "YES" : "NO",
            Int(Date().timeIntervalSince(started) * 1000))
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--search-answer-test=<질문>` — 검색 → 프롬프트 주입 → 모델 스트리밍까지 헤드리스 1회.
  /// 로그에는 건수·지연·글자수·인용 여부만 남긴다(검색어·본문·답변 내용·키 금지).
  func runSearchAnswerSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--search-answer-test=") })
    else { return false }
    let query = String(arg.dropFirst("--search-answer-test=".count))
    store.applyRenderOverride(webSearch: true)
    applyProviderOverrideForSelfTest()
    Task { @MainActor in
      let started = Date()
      let outcome = await self.store.searchWeb(query: query, useCache: false)
      guard case .success(let results) = outcome, !results.isEmpty else {
        if case .failure(let e) = outcome {
          NSLog("[SEARCH-ANSWER] FAIL search code=%@", e.code)
        } else {
          NSLog("[SEARCH-ANSWER] FAIL search results=0")
        }
        NSApp.terminate(nil)
        return
      }
      let s = self.store.settings
      guard let provider = s.activeProvider else {
        NSLog("[SEARCH-ANSWER] FAIL no active provider")
        NSApp.terminate(nil)
        return
      }
      // 앱 본선과 같은 한도를 쓴다 — 하네스가 더 큰 프롬프트를 보내면 측정이 앱보다 느려진다.
      let limits = WebSearchPromptLimits.limits(resultCount: s.webSearchResultCount,
                                                maxCharacters: s.webSearchMaxCharacters,
                                                provider: provider)
      let cap = WebSearchPromptLimits.contextCap(for: provider)
      var context = WebSearchContext.build(results: results,
                                           maxCharacters: limits.maxCharacters,
                                           limit: limits.resultCount)
      if ConversationMemory.estimateTokens(context) > cap {
        context = GlobalMemory.clip(context, toTokens: cap)
      }
      let contextTokens = ConversationMemory.estimateTokens(context)
      let prompt = context + "\n\n질문: " + query
      NSLog("[SEARCH-ANSWER] prompt results=%d chars=%d cap=%d contextTokens=%d provider=%@",
            limits.resultCount, limits.maxCharacters, cap, contextTokens, provider.name)
      var chars = 0
      var deltas = 0
      var firstDeltaMs = -1
      do {
        let answer = try await UIStore.streamReply(provider: provider, prompt: prompt,
                                                   history: [], attachments: [],
                                                   onDelta: { delta in
          if firstDeltaMs < 0 {
            firstDeltaMs = Int(Date().timeIntervalSince(started) * 1000)
          }
          deltas += 1
          chars += delta.count
        })
        let cites = (1...5).filter { answer.contains("[\($0)]") }.count
        NSLog("[SEARCH-ANSWER] OK sources=%d answerChars=%d cites=%d deltas=%d firstDeltaMs=%d totalMs=%d provider=%@",
              min(results.count, limits.resultCount), answer.count, cites, deltas, firstDeltaMs,
              Int(Date().timeIntervalSince(started) * 1000), provider.type.displayName)
      } catch {
        NSLog("[SEARCH-ANSWER] FAIL model code=%@", AIErrorText.code(for: error))
      }
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--compact-test[=<턴수>]` — 긴 대화를 만들어 자동 정리 1회를 실제 모델로 실행한다.
  /// 로그에는 턴 수·요약 글자 수·전후 토큰 추정만 남긴다(대화 내용 금지).
  func runCompactSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--compact-test") })
    else { return false }
    let count = Int(arg.split(separator: "=").last ?? "") ?? 20
    store.applyRenderOverride(webSearch: false)
    applyProviderOverrideForSelfTest()
    var turns: [Turn] = []
    for i in 0..<max(8, count) {
      let role: TurnRole = i % 2 == 0 ? .user : .assistant
      turns.append(Turn(role: role,
                        text: "테스트 \(i)번째 메시지. " + String(repeating: "맥락 ", count: 30)))
    }
    store.applyConversationForSelfTest(Conversation(title: "Compact QA", turns: turns))
    Task { @MainActor in
      let started = Date()
      let before = ConversationMemory.contextTokens(self.store.conversation)
      self.store.compactNow()
      while self.store.isCompacting {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      let conv = self.store.conversation
      let after = ConversationMemory.contextTokens(conv)
      let summary = conv.activeSummary
      let recent = UIStore.requestHistory(conv).count
      let provider = self.store.settings.activeProvider?.type.rawValue ?? "none"
      NSLog("[COMPACT-TEST] turns=%d summary=%@ summaryChars=%d before=%d after=%d recent=%d ms=%d provider=%@",
            conv.turns.count, summary == nil ? "NO" : "YES", summary?.count ?? 0,
            before, after, recent,
            Int(Date().timeIntervalSince(started) * 1000), provider)
      if let message = self.store.compactMessage {
        NSLog("[COMPACT-TEST] message=%@", message)
      }
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA: `--compact-auto-test[=<턴수>]` — 자동 트리거(70%)가 실제로 정리를 시작하는지 확인한다.
  /// 20턴은 예산을 넘고, 10턴은 넘지 않아야 한다. 로그에는 수치만 남긴다.
  func runCompactAutoSelfTestIfRequested() -> Bool {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--compact-auto-test") })
    else { return false }
    let count = Int(arg.split(separator: "=").last ?? "") ?? 20
    store.applyRenderOverride(webSearch: false)
    applyProviderOverrideForSelfTest()
    var turns: [Turn] = []
    for i in 0..<max(4, count) {
      let role: TurnRole = i % 2 == 0 ? .user : .assistant
      turns.append(Turn(role: role,
                        text: "자동 테스트 \(i)번째 메시지. " + String(repeating: "맥락 ", count: 30)))
    }
    store.applyConversationForSelfTest(Conversation(title: "Compact Auto QA", turns: turns))
    Task { @MainActor in
      let started = Date()
      let before = ConversationMemory.contextTokens(self.store.conversation)
      let provider = self.store.settings.activeProvider
      let keep = provider?.type == .appleFM ? 4 : self.store.settings.compactKeepTurns
      let expected = provider.map {
        ConversationMemory.shouldCompact(self.store.conversation, provider: $0, keepTurns: keep)
      } ?? false
      self.store.startAutoCompact(convID: self.store.conversation.id)
      // 자동 트리거는 Task로 시작하므로 잠깐 기다린 뒤 상태를 본다.
      try? await Task.sleep(nanoseconds: 300_000_000)
      while self.store.isCompacting {
        try? await Task.sleep(nanoseconds: 100_000_000)
      }
      let conv = self.store.conversation
      let after = ConversationMemory.contextTokens(conv)
      NSLog("[COMPACT-AUTO] turns=%d expected=%@ summary=%@ before=%d after=%d ms=%d provider=%@",
            conv.turns.count, expected ? "YES" : "NO", conv.activeSummary == nil ? "NO" : "YES",
            before, after, Int(Date().timeIntervalSince(started) * 1000),
            provider?.type.rawValue ?? "none")
      NSApp.terminate(nil)
    }
    return true
  }

  /// QA 견본 대화 — **메모리에만** 넣는다(저장 호출 없음, 앱 종료 시 사라진다).
  private func seedDemoConversation() {
    var demo = Conversation(title: "Markdown QA")
    if CommandLine.arguments.contains("--demo-chat=empty") {
      store.conversation = Conversation()   // 빈 새 대화 — 기본 제목(로컬라이즈)·워터마크 확인용
      return
    }
    if CommandLine.arguments.contains("--demo-search-sources") {
      // 검색 출처 카드 — 답변 아래 [1][2][3] 칩
      let now = Date()
      let sources = [
        TurnSource(title: L("네이버, 새 AI 검색 공개"),
                   url: "https://www.yna.co.kr/view/AKR202610200001",
                   domain: "yna.co.kr", publishedAt: now.addingTimeInterval(-7_200)),
        TurnSource(title: L("국내 IT 업계, 생성형 AI 경쟁 본격화"),
                   url: "https://www.hani.co.kr/arti/economy/it/1",
                   domain: "hani.co.kr", publishedAt: now.addingTimeInterval(-9_600)),
        TurnSource(title: L("네이버 AI 검색, 베타 사용자 모집"),
                   url: "https://www.etnews.com/202610200001",
                   domain: "etnews.com", publishedAt: now.addingTimeInterval(-3_600))
      ]
      demo.turns = [
        Turn(role: .user, text: L("오늘 네이버 뉴스 IT 기사 알려줘")),
        Turn(role: .assistant,
             text: L("## 오늘의 IT 뉴스\n\n- 네이버가 새 AI 검색을 공개했습니다. [1]\n- 국내 IT 업계의 생성형 AI 경쟁이 본격화되고 있습니다. [2]\n- 베타 사용자 모집도 시작했습니다. [3]"),
             elapsedMs: 2_140, sources: sources)
      ]
      demo.pinned = false
      store.conversation = demo
      return
    }
    if CommandLine.arguments.contains("--demo-search") {
      // 검색 중 — 점 대신 🌐와 "웹에서 찾는 중…"
      store.conversation = demo
      store.isReplying = true
      store.isSearching = true
      return
    }
    if CommandLine.arguments.contains("--demo-fallback") {
      // 예비 모델 폴백 안내가 실제로 어떻게 보이는지 — 실사용(429 → Apple FM)과 같은 문구를 쓴다.
      let note = UIStore.fallbackNote(
        primaryName: L("Remote OpenAI 호환"), fallbackName: L("Local Apple FM"),
        error: QuickTalkError.serverFailure(.rateLimited(status: 429, code: "server_error")))
      demo.turns = [
        Turn(role: .user, text: L("내 하드 용량 얼마나 남았나?")),
        Turn(role: .assistant,
             text: note + L("제가 지금은 기기 정보를 직접 확인할 수 없습니다. 설정 > 일반 > 저장 공간에서 확인하실 수 있어요."),
             elapsedMs: 2800)
      ]
      demo.pinned = false
      store.conversation = demo
      return
    }
    if CommandLine.arguments.contains(where: { $0.hasPrefix("--demo-search-refusal") }) {
      // 모델이 "검색할 수 없다"고 답한 화면 — [웹에서 찾기] 재시도 버튼 확인용
      // `--demo-search-refusal=tool`: 도구 부재 표현(2026-10-21 실사용 문구) 변형
      let toolStyle = CommandLine.arguments.contains("--demo-search-refusal=tool")
      demo.turns = [
        Turn(role: .user, text: toolStyle ? L("오늘 서울 날씨를 보내 주세요")
                                          : L("오늘 네이버 뉴스 IT 기사 알려줘")),
        Turn(role: .assistant,
             text: toolStyle
               ? L("죄송하지만 제가 지금 사용할 수 있는 도구에는 실시간 날씨 정보를 조회하는 기능이 없습니다. 대신 기상청 날씨누리(weather.go.kr)를 확인해 주세요.")
               : L("죄송하지만 저는 실시간 웹을 검색할 수 없습니다. 최신 뉴스는 직접 확인해 주세요."),
             elapsedMs: toolStyle ? 2700 : 640)
      ]
      demo.pinned = false
      store.conversation = demo
      return
    }
    if CommandLine.arguments.contains("--demo-search-error") {
      demo.turns = [
        Turn(role: .user, text: L("오늘 네이버 뉴스 IT 기사 알려줘")),
        Turn(role: .assistant,
             text: WebSearchError.unauthorized.userText + "\n\n" + L("확인된 자료가 없습니다."),
             elapsedMs: 820)
      ]
      demo.pinned = false
      store.conversation = demo
      return
    }
    if CommandLine.arguments.contains("--demo-stream") {
      // 스트리밍 중 화면 — 부분 출력이 보이고 점 표시는 사라진 상태
      let partial = Turn(role: .assistant,
                         text: "## " + L("스트리밍 확인") + "\n\n"
                           + L("글자가 **도착하는 대로** 그립니다. 아직 문장이 끝나지 않았"))
      demo.turns = [Turn(role: .user, text: L("스트리밍으로 보여줘")), partial]
      demo.pinned = false
      store.conversation = demo
      store.streamingTurnID = partial.id
      store.isReplying = true
      return
    }
    if CommandLine.arguments.contains("--demo-error") {
      // 연결 거부 오류 말풍선 — 정확한 원인 문구 확인용(메모리 한정)
      let url = URL(string: "http://192.168.86.30:8791/v1")!
      let e = URLError(.cannotConnectToHost, userInfo: [NSURLErrorFailingURLErrorKey: url])
      demo.turns = [
        Turn(role: .user, text: L("핑 대신 실제 오류를 보여줘")),
        Turn(role: .assistant, text: AIErrorText.userText(for: e, url: url), elapsedMs: 1000)
      ]
      demo.pinned = false
      store.conversation = demo
      return
    }
    if CommandLine.arguments.contains("--demo-memory") {
      // 자동 정리 배너 — 오래된 4개 메시지를 요약한 상태
      demo.turns = [
        Turn(role: .user, text: L("이번 주 여행 계획을 짜줘")),
        Turn(role: .assistant, text: L("부산 2박 3일 일정으로 정리했습니다. 첫날은 해운대, 둘째 날은 감천문화마을입니다.")),
        Turn(role: .user, text: L("숙소는 조용한 곳으로")),
        Turn(role: .assistant, text: L("광안리 외곽의 조용한 호텔을 추천합니다. 예산은 1박 12만원입니다.")),
        Turn(role: .user, text: L("둘째 날 저녁은 뭐가 좋아?")),
        Turn(role: .assistant, text: L("감천문화마을 근처의 해산물 식당을 추천합니다."))
      ]
      demo.summary = "사용자는 부산 2박 3일 여행을 계획 중이다. 1일차 해운대, 2일차 감천문화마을. 숙소는 광안리 외곽의 조용한 호텔(1박 12만원)."
      demo.summaryThroughTurnID = demo.turns[3].id
      demo.pinned = false
      store.conversation = demo
      return
    }
    // 상대 시간("5분 전")·헤더 아이콘 정렬을 렌더로 확인할 수 있게 시각도 넣는다.
    demo.turns = [
      Turn(role: .user, text: L("테마랑 한/영 전환 마무리해줘"),
           createdAt: Date().addingTimeInterval(-12 * 60)),
      Turn(role: .assistant, text: Self.markdownSample, elapsedMs: 1240,
           createdAt: Date().addingTimeInterval(-9 * 60))
    ]
    demo.pinned = true
    store.conversation = demo

    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--demo-draft-lines=") }),
       let n = Int(arg.dropFirst("--demo-draft-lines=".count)), n > 0 {
      let body = (1...n).map { "Line \($0) — composer growth check" }.joined(separator: "\n")
      // 끝의 빈 줄까지 포함해 Shift+Enter 직후 커서가 보이는지 확인한다.
      store.draft = body + "\n"
    }
  }

  /// QA 견본 — 도구 실행 기록(실제 명령 + 실제 출력)
  private static func agentDemoEvents() -> [AgentEvent] {
    [
      AgentEvent(id: "e1", toolName: "shell",
                 title: L("메모리 사용량 확인"),
                 command: "vm_stat | head -6; echo \"---\"; sysctl -n hw.memsize",
                 level: .read, risk: .normal, state: .done,
                 output: "Mach Virtual Memory Statistics: (page size of 16384 bytes)\n"
                        + "Pages free:                              264599.\n"
                        + "Pages active:                            723342.\n"
                        + "Pages inactive:                          713622.\n"
                        + "Pages speculative:                        44702.\n"
                        + "---\n34359738368",
                 elapsedMs: 815),
      AgentEvent(id: "e2", toolName: "shell",
                 title: L("스왑 사용량"),
                 command: "sysctl vm.swapusage",
                 level: .read, risk: .normal, state: .done,
                 output: "vm.swapusage: total = 1024.00M  used = 215.00M  free = 809.00M  (encrypted)",
                 elapsedMs: 120)
    ]
  }

  /// QA 견본 — 목록·체크박스·표·코드·인용·인라인 서식이 한 번에 보이게
  private static let markdownSample = """
  ## Markdown check
  **Bold** and *italic*, `inline code`, [link](https://example.com).

  - [x] Done item
  - [ ] Open item
  - Plain bullet
    - Nested bullet

  1. First
  2. Second

  | Item | Value |
  |---|---|
  | Alpha | 1 |
  | Beta | 2 |

  > Quoted line

  ```swift
  let answer = 42
  ```
  """

  /// pill QA 렌더 — 실제 창 없이 pill(빈 입력·입력 중·목록)만 PNG로 본다.
  private static func pillStage(_ model: PillModel) -> some View {
    ZStack(alignment: .top) {
      LinearGradient(colors: [Color(red: 0.10, green: 0.09, blue: 0.16),
                              Color(red: 0.05, green: 0.05, blue: 0.07)],
                     startPoint: .top, endPoint: .bottom)
      RadialGradient(colors: [Color.purple.opacity(0.22), .clear],
                     center: .topLeading, startRadius: 0, endRadius: 380)
      PillRootView(model: model,
                   onSubmit: { _ in }, onCancel: {}, onCommandReturn: {}, onToggleList: {},
                   onResume: { _ in }, onOpenArchive: {})
        .padding(.top, 24)
    }
  }

  /// pill 실제 창 크기 그대로 — 창 여백(투명)이 보이도록 초록 바탕을 깐다
  private static func pillPanelStage(_ model: PillModel) -> some View {
    ZStack(alignment: .bottom) {
      Color.green.opacity(0.35)
      PillRootView(model: model,
                   onSubmit: { _ in }, onCancel: {}, onCommandReturn: {}, onToggleList: {},
                   onResume: { _ in }, onOpenArchive: {})
    }
  }

  /// SwiftUI 뷰를 창 없이 PNG로 — `--render` 전용
  private func renderPNG(_ view: AnyView, size: NSSize, to path: String) {    // 창이 없으므로 배경을 직접 깔고, 외형(라이트/다크)도 호스팅 뷰에 지정한다
    let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
    host.appearance = NSApp.appearance
    host.frame = NSRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    // 비동기 레이아웃(폰트·머티리얼)이 한 번 더 도는 시간을 준다
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    host.layoutSubtreeIfNeeded()
    guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
    host.cacheDisplay(in: host.bounds, to: rep)
    if let data = rep.representation(using: .png, properties: [:]) {
      try? data.write(to: URL(fileURLWithPath: path))
      NSLog("[QuickTalk] rendered %@", path)
    }
  }
}
