import SwiftUI
import AppKit
import Combine
import Carbon

// QuickTalk v0.10: 메뉴바 좌클릭 Hub(실행/설정) + 우클릭 컨텍스트 메뉴 (ApexKey 형식)
// + AI 프로바이더 목록(기본 3종, 추가 가능) + 기본 프로바이더 Apple FM
@main
struct QuickTalkApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
  var body: some Scene {
    Settings { SettingsView().environmentObject(delegate.store) }
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  let store = UIStore()
  private var statusItem: NSStatusItem?
  private var panel: NSPanel!
  private var hubPopover: NSPopover?
  private var settingsWindow: NSWindow?
  private var cancellables = Set<AnyCancellable>()
  /// 설정에서 바꾼 전역 단축키의 Carbon 등록 id — 동작별로 하나씩
  private var shortcutIDs: [ShortcutAction: UInt32] = [:]
  /// 이미 등록한 조합 — 설정이 바뀌어도 조합이 같으면 다시 등록하지 않는다
  private var appliedShortcutCombos: [ShortcutAction: String] = [:]
  private var pointerCache: NSPoint?
  private var pointerTimer: Timer?
  private var editHotKeyIDs: [UInt32] = []
  /// QA 실행 인자 오버라이드(저장하지 않음) — 설정 변경 알림보다 우선한다
  private var languageOverride: AppLanguage?
  private var appearanceOverride: AppAppearance?

  func applicationDidFinishLaunching(_ notification: Notification) {
    applyLaunchOverrides()
    applyLanguage(store.settings)
    applyAppearance(store.settings)
    buildPanel()
    setupStatusItem()
    setupSystemMenu()
    installEditShortcuts()
    installEditShortcutMonitor()
    observeSettings()
    installWindowLevelObservers()
    ShelfController.shared.start(store: store, chatWindowProvider: { [weak self] in self?.panel })
    PointerPillController.shared.start(store: store, onOutcome: { [weak self] in self?.handlePill($0) })
    applyShortcuts(store.settings, force: true)
    NSLog("[QuickTalk] launched, LSUIElement=%@, shortcut=%@",
          Bundle.main.object(forInfoDictionaryKey: "LSUIElement") as? String ?? "?",
          store.settings.globalShortcut)
    // 대화 패널의 "설정 열기" 버튼 → 설정 창
    NotificationCenter.default.addObserver(forName: .quickTalkOpenSettings, object: nil, queue: .main) { [weak self] _ in
      self?.openSettings()
    }
    // 시스템 권한 안내(화면 기록·마이크·받아쓰기)가 대화 창에 가리지 않게 잠시 창을 내린다
    NotificationCenter.default.addObserver(forName: .quickTalkSystemPromptBegin, object: nil, queue: .main) { [weak self] _ in
      self?.beginSystemPrompt()
    }
    NotificationCenter.default.addObserver(forName: .quickTalkSystemPromptEnd, object: nil, queue: .main) { [weak self] _ in
      self?.endSystemPrompt()
    }
    // 단축키 변경(녹화) 중에는 기존 전역 핫키를 잠시 풀어, 새 조합이 앱에 먼저 먹히지 않게 한다
    NotificationCenter.default.addObserver(forName: .quickTalkSuspendShortcuts, object: nil, queue: .main) { [weak self] _ in
      self?.suspendShortcuts()
    }
    NotificationCenter.default.addObserver(forName: .quickTalkResumeShortcuts, object: nil, queue: .main) { [weak self] _ in
      guard let self else { return }
      self.applyShortcuts(self.store.settings, force: true)
    }
    // QuickShelf에서 텍스트 삽입·첨부가 일어나면 대화 창을 보여준다(결과가 어디로 갔는지 확인 가능)
    NotificationCenter.default.addObserver(forName: .quickTalkShowChat, object: nil, queue: .main) { [weak self] _ in
      self?.showChatFromShelf()
    }
    // QA 편의: `--open-settings` 로 실행하면 설정 창을 바로 연다 (메뉴바 클릭 없이 확인용)
    runQARenderIfRequested()
    // QA: `--search-test=<질문>` — 저장된 Exa 키로 실제 검색 1회(결과 건수·지연만 로그)
    if runWebSearchSelfTestIfRequested() { return }
    // QA: `--answer-test=<질문>` — Exa `/answer` 1회(답변·인용 길이만 로그)
    if runAnswerSelfTestIfRequested() { return }
    // QA: `--tool-test=<질문>` — 모델이 web_search 도구를 호출하는지 1왕복 확인
    if runToolCallingSelfTestIfRequested() { return }
    // QA: `--search-decide-test=<질문>` — 필요할 때만 자동 판정(YES/NO)
    if runSearchDecideSelfTestIfRequested() { return }
    // QA: `--search-answer-test=<질문>` — 검색 → 프롬프트 주입 → 모델 스트리밍(헤드리스)
    if runSearchAnswerSelfTestIfRequested() { return }
    // QA: `--compact-test[=<턴수>]` — 자동 대화 정리 1회(헤드리스)
    if runCompactSelfTestIfRequested() { return }
    // QA: `--compact-auto-test[=<턴수>]` — 자동 트리거(70%) 확인(헤드리스)
    if runCompactAutoSelfTestIfRequested() { return }
    // QA: `--fallback-test` — 주 모델 실패 → 예비 모델 1회 폴백 경로(헤드리스·온디바이스)
    if runFallbackSelfTestIfRequested() { return }
    if CommandLine.arguments.contains("--open-settings") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.openSettings() }
    }
    // QA 편의: `--open-hub` 로 실행하면 메뉴바 Hub 팝오버를 바로 연다 (클릭 없이 확인용)
    if CommandLine.arguments.contains("--open-hub") {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.toggleHub() }
    }
    // QA 편의: `--open-panel` 로 실행하면 대화 창을 바로 연다 (배치·탭 확인용)
    //   탭 지정: `--panel-tab=<chat|archive|settings>`
    if CommandLine.arguments.contains("--open-panel") {
      let tab = Self.qaPanelTab()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.openPanel(tab: tab) }
    }
    // QA: `--selftest=<프로바이더ID>` 로 저장된 설정·비밀·클라이언트 경로를 실제 호출로 검증
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--selftest=") }) {
      let id = String(arg.dropFirst("--selftest=".count))
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.runSelfTest(providerID: id) }
    }
    // QA: `--ask=<질문>` — 창을 띄우고 실제로 한 번 전송한다(응답 중 표시·전송 E2E 확인용)
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--ask=") }) {
      let question = String(arg.dropFirst("--ask=".count))
      // QA: `--attach=<경로>`(여러 번 지정 가능) — 첨부 전송 E2E 확인용
      for a in CommandLine.arguments.filter({ $0.hasPrefix("--attach=") }) {
        let path = String(a.dropFirst("--attach=".count))
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let ext = url.pathExtension.lowercased()
        let kind: Attachment.Kind = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"].contains(ext)
          ? .image : .file
        store.attached.append(PendingAttachment(name: url.lastPathComponent, url: url, kind: kind))
        NSLog("[QuickTalk] QA --attach 첨부 추가 (kind=%@)", kind.rawValue)
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
        guard let self else { return }
        self.store.draft = question
        NSLog("[QuickTalk] QA --ask 전송 (길이=%d)", question.count)
        self.store.send()
      }
    }
    // QA 편의: `--open-shelf` 로 실행하면 QuickShelf 패널을 바로 연다
    //   탭 지정: `--shelf-tab=<clipboard|files|capture>`
    if CommandLine.arguments.contains("--open-shelf") {
      if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--shelf-tab=") }) {
        let name = String(arg.dropFirst("--shelf-tab=".count))
        let map: [String: ShelfTab] = ["clipboard": .clipboard, "files": .files, "capture": .capture]
        if let tab = map[name] { store.shelfTab = tab }
      }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
        ShelfController.shared.show()
      }
    }
    // QA: `--capture=<full|region|window>` — 캡처 흐름을 바로 시작(권한·오버레이 확인용)
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--capture=") }) {
      let mode = String(arg.dropFirst("--capture=".count))
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
        guard let self else { return }
        switch mode {
        case "full": CaptureService.shared.captureFullScreen(into: self.store)
        case "region": CaptureService.shared.captureRegion(into: self.store)
        case "window": CaptureService.shared.captureWindow(into: self.store)
        default: NSLog("[WARN] E-MAC-CAP-0003 알 수 없는 캡처 모드: %@", mode)
        }
      }
    }
    // QA: `--prefill=<문구>` — 전송하지 않고 입력창만 채운다(입력창 높이·스크롤·플레이스홀더 확인용)
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--prefill=") }) {
      let text = String(arg.dropFirst("--prefill=".count)).replacingOccurrences(of: "\\n", with: "\n")
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
        guard let self else { return }
        self.store.draft = text
        NSLog("[QuickTalk] QA --prefill 입력창 채움 (길이=%d)", text.count)
      }
    }
  }

  /// 실제 프로바이더 1건에 질문 1건을 보내 앱 내부 경로(설정→비밀→클라이언트)를 검증한다.
  /// 응답 본문은 로그에 남기지 않고 길이만 기록한다(키·내용 노출 방지).
  private func runSelfTest(providerID: String) {
    guard let p = store.settings.provider(providerID) else {
      NSLog("[SELFTEST] FAIL — 프로바이더 없음: %@", providerID)
      return
    }
    Task {
      do {
        let reply = try await UIStore.reply(provider: p, prompt: L("연결 확인. 한 단어로 답해줘."), history: [])
        NSLog("[SELFTEST] %@ OK — 응답 %d자", providerID, reply.count)
      } catch {
        NSLog("[SELFTEST] %@ FAIL — %@", providerID, String(describing: error))
      }
    }
  }

  // MARK: - 시스템 메인 메뉴 (ApexKey 형식)

  /// 앱 메뉴(정보·설정…·종료) + 편집 메뉴.
  /// 편집 메뉴가 없으면 텍스트 필드에서 Cmd+C/V/Z가 동작하지 않는다(AppKit은 메인 메뉴의 표준 edit action으로 전달).
  private func setupSystemMenu() {
    let mainMenu = NSMenu()

    let appMenu = NSMenu()
    let about = NSMenuItem(title: L("QuickTalk 정보"), action: #selector(showAboutAction), keyEquivalent: "")
    about.target = self
    appMenu.addItem(about)
    appMenu.addItem(.separator())
    let settingsItem = NSMenuItem(title: L("설정…"), action: #selector(openSettingsMenu), keyEquivalent: ",")
    settingsItem.target = self
    appMenu.addItem(settingsItem)
    appMenu.addItem(.separator())
    let quit = NSMenuItem(title: L("QuickTalk 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    appMenu.addItem(quit)
    let appMenuItem = NSMenuItem()
    appMenuItem.submenu = appMenu
    mainMenu.addItem(appMenuItem)

    // undo:/redo: 는 target을 nil로 두고 responder chain(UndoManager)이 처리하게 한다.
    // (Selector("undo:") 리터럴은 "메서드 없음" 경고를 내므로 NSSelectorFromString 사용)
    let editMenu = NSMenu(title: L("편집"))
    let editItems: [(String, Selector, String)] = [
      (L("실행 취소"), NSSelectorFromString("undo:"), "z"),
      (L("다시 실행"), NSSelectorFromString("redo:"), "Z"),
      (L("오려두기"), #selector(NSText.cut(_:)), "x"),
      (L("복사"), #selector(NSText.copy(_:)), "c"),
      (L("붙여넣기"), #selector(NSText.paste(_:)), "v"),
      (L("전체 선택"), #selector(NSText.selectAll(_:)), "a"),
    ]
    for (title, action, key) in editItems {
      let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
      item.target = nil
      editMenu.addItem(item)
    }
    let editMenuItem = NSMenuItem()
    editMenuItem.submenu = editMenu
    mainMenu.addItem(editMenuItem)

    NSApp.mainMenu = mainMenu
  }

  // MARK: - 메뉴바 상태 아이템

  private func setupStatusItem() {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let b = item.button {
      // 메뉴바 아이콘: 앱 아이콘 세트와 같은 브랜드 마크(템플릿 — 라이트/다크 자동 반전)
      if let mark = NSImage(named: "MenuBarIcon") {
        mark.isTemplate = true
        mark.size = NSSize(width: 18, height: 18)
        b.image = mark
      } else {
        NSLog("[WARN] E-MAC-RENDER-0002 MenuBarIcon 에셋 없음 — SF Symbol로 대체")
        b.image = NSImage(systemSymbolName: "bubble.left.and.text.bubble.right", accessibilityDescription: "QuickTalk")
        b.image?.isTemplate = true
      }
      b.target = self
      b.action = #selector(click(_:))
      b.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }
    statusItem = item
  }

  /// 설정 변경 → 메뉴바 아이콘/Dock 정책, 포인터 추적, 전역 단축키 재등록.
  private func observeSettings() {
    store.$settings
      .receive(on: RunLoop.main)
      .sink { [weak self] s in
        self?.applyLanguage(s)
        self?.applyAppearance(s)
        self?.applyVisibility(s)
        self?.applyPointerTracking(s)
        self?.applyShortcuts(s)
        self?.applyPanelLevel()
      }
      .store(in: &cancellables)
  }

  // MARK: - QA (오프스크린 렌더 · 실행 인자 오버라이드)

  /// QA 전용: `--lang=<system|korean|english>` · `--theme=<system|light|dark>` — **저장하지 않고** 이 실행에만 적용
  private func applyLaunchOverrides() {
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--lang=") }),
       let v = AppLanguage(rawValue: String(arg.dropFirst("--lang=".count))) {
      languageOverride = v
    }
    if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--theme=") }),
       let v = AppAppearance(rawValue: String(arg.dropFirst("--theme=".count))) {
      appearanceOverride = v
    }
  }

  private func applyAppearanceValue(_ v: AppAppearance) {
    switch v {
    case .system: NSApp.appearance = nil
    case .light: NSApp.appearance = NSAppearance(named: .aqua)
    case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
    }
  }

  /// QA 전용: `--render=<폴더>` — 창을 띄우지 않고 설정·Shelf를 PNG로 그린다(오프스크린).
  // MARK: - 테마 · 언어

  /// 설정 언어를 번역표에 반영한다(뷰는 `store.settings` 발행으로 다시 그려진다).
  /// 메뉴·창 제목처럼 SwiftUI 밖에서 만든 문자열은 여기서 다시 만든다.
  private func applyLanguage(_ s: QuickTalkSettings) {
    let want = languageOverride ?? s.language
    let changed = L10n.language != want
    L10n.language = want
    guard changed else { return }
    // L10n은 관찰 대상이 아니므로, 번역표를 바꾼 뒤 뷰를 한 번 더 그리게 한다
    store.languageDidChange()
    setupSystemMenu()
    settingsWindow?.title = L("QuickTalk 설정")
  }

  /// 시스템/라이트/다크 — 앱 전체(패널·설정·Shelf 포함)에 적용된다.
  private func applyAppearance(_ s: QuickTalkSettings) {
    applyAppearanceValue(appearanceOverride ?? s.appearance)
  }

  // MARK: - QuickShelf (PLAN_v0.13)

  // 창 안 엣지 패널은 창 폭을 바꾸지 않는다(목업 v0.6 §3) —
  // 이전 구현의 창 확장(resizeForShelfDock)·폭 복원(normalizeChatWidthForShelf)은 제거했다.

  /// 녹화 중 잠시 해제 — 등록된 조합을 눌러도 동작이 실행되지 않고 설정 창이 키를 받는다
  private func suspendShortcuts() {
    for (_, id) in shortcutIDs { GlobalHotKey.shared.unregister(id: id) }
    shortcutIDs.removeAll()
    appliedShortcutCombos.removeAll()
    NSLog("[QuickTalk] 단축키 일시 해제(녹화)")
  }

  /// 전역 단축키 등록 — 설정에서 조합이 바뀐 것만 다시 등록한다.
  /// Carbon 핫키는 앱이 비활성일 때도 동작하고 입력 모니터링 권한이 필요 없다.
  private func applyShortcuts(_ s: QuickTalkSettings, force: Bool = false) {
    let handlers: [ShortcutAction: () -> Void] = [
      .invoke: { [weak self] in self?.togglePanel(fromShortcut: true) },
      .shelf: { ShelfController.shared.toggle() },
      .captureFull: { [weak self] in
        guard let self else { return }
        Task { @MainActor in CaptureService.shared.captureFullScreen(into: self.store) }
      },
      .captureRegion: { [weak self] in
        guard let self else { return }
        Task { @MainActor in CaptureService.shared.captureRegion(into: self.store) }
      },
      .captureWindow: { [weak self] in
        guard let self else { return }
        Task { @MainActor in CaptureService.shared.captureWindow(into: self.store) }
      },
    ]

    for action in ShortcutAction.allCases {
      let combo = s.shortcut(for: action)
      if !force, appliedShortcutCombos[action] == combo, shortcutIDs[action] != nil { continue }
      if let old = shortcutIDs.removeValue(forKey: action) {
        GlobalHotKey.shared.unregister(id: old)
      }
      appliedShortcutCombos[action] = combo
      guard let parsed = GlobalHotKey.parse(combo), let handler = handlers[action],
            let id = GlobalHotKey.shared.registerTemporary(keyCode: parsed.keyCode,
                                                           modifiers: parsed.modifiers,
                                                           action: handler) else {
        store.shortcutStatus[action] = false
        NSLog("[WARN] E-MAC-KEY-0001 단축키 등록 실패 %@ = %@ — 다른 앱이 선점했거나 형식이 잘못되었습니다",
              action.rawValue, combo)
        continue
      }
      shortcutIDs[action] = id
      store.shortcutStatus[action] = true
      NSLog("[QuickTalk] 단축키 등록 %@ = %@ (id=%u)", action.rawValue, combo, id)
    }
  }

  // MARK: - 마우스 포인터 위치 기억 (포인터 모드 전용)

  /// 포인터 모드일 때만 커서 위치를 주기적으로 기억한다.
  /// 메뉴바 클릭으로 Hub를 열면 커서가 메뉴바 위에 있으므로, "직전 작업 위치"를 써야 자연스럽다.
  private func applyPointerTracking(_ s: QuickTalkSettings) {
    let wanted = s.newWindowPosition == .mousePointer
    if wanted, pointerTimer == nil {
      samplePointer()
      let t = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: true) { [weak self] _ in
        self?.samplePointer()
      }
      t.tolerance = 0.3
      pointerTimer = t
      NSLog("[QuickTalk] 포인터 위치 추적 시작 (포인터 모드)")
    } else if !wanted, pointerTimer != nil {
      pointerTimer?.invalidate()
      pointerTimer = nil
      pointerCache = nil
      NSLog("[QuickTalk] 포인터 위치 추적 중지 (중앙 모드)")
    }
  }

  /// 작업 영역(메뉴바·Dock 제외) 안에 있는 커서 위치만 기억한다.
  private func samplePointer() {
    let p = NSEvent.mouseLocation
    if Self.screenContaining(p) != nil { pointerCache = p }
  }

  /// 해당 좌표가 들어 있는 화면 — 작업 영역(visibleFrame) 기준. 메뉴바/Dock 위면 nil.
  private static func screenContaining(_ p: NSPoint) -> NSScreen? {
    NSScreen.screens.first { $0.visibleFrame.contains(p) }
  }

  private func applyVisibility(_ s: QuickTalkSettings) {
    if !s.showMenuBarIcon && !s.showDockIcon {
      NSLog("[WARN] E-MAC-RENDER-0001 메뉴바·Dock 동시 숨김 요청 — 메뉴바 유지")
      if statusItem == nil { setupStatusItem() }
    } else if s.showMenuBarIcon {
      if statusItem == nil { setupStatusItem() }
    } else {
      dismissHub()
      if let item = statusItem {
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
        NSLog("[QuickTalk] 메뉴바 아이콘 숨김 (단축키 전용)")
      }
    }
    NSApp.setActivationPolicy(s.showDockIcon ? .regular : .accessory)
  }

  // MARK: - 좌/우 클릭 분기 (ApexKey 형식)

  @objc private func click(_ sender: NSStatusBarButton) {
    guard let event = NSApp.currentEvent else { toggleHub(); return }
    if event.type == .rightMouseUp {
      if let pop = hubPopover, pop.isShown { pop.performClose(nil) }
      NSMenu.popUpContextMenu(buildMenu(), with: event, for: sender)
      return
    }
    toggleHub()
  }

  // MARK: - Hub 팝오버 (좌클릭)

  private func makeHubPopover() -> NSPopover {
    let pop = NSPopover()
    let initial = Self.qaHubTab()
    pop.contentViewController = NSHostingController(rootView:
      QuickTalkHubView(initialTab: initial) { [weak self] action in self?.hubAction(action) }
        .environmentObject(store)
    )
    pop.contentSize = HubMetrics.popoverSize
    pop.behavior = .transient
    pop.animates = true
    hubPopover = pop
    return pop
  }

  /// QA용: `--hub-tab=<run|settings>`
  private static func qaHubTab() -> QuickTalkHubView.HubTab {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--hub-tab=") }) else { return .run }
    return QuickTalkHubView.HubTab(rawValue: String(arg.dropFirst("--hub-tab=".count))) ?? .run
  }

  private func toggleHub() {
    if let pop = hubPopover, pop.isShown { pop.performClose(nil); return }
    guard let button = statusItem?.button else { return }
    let pop = hubPopover ?? makeHubPopover()
    NSApp.activate(ignoringOtherApps: true)
    pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
  }

  private func dismissHub() { hubPopover?.performClose(nil) }

  /// Hub 행 액션 — 팝오버를 먼저 닫고 수행
  private func hubAction(_ action: HubMenuAction) {
    dismissHub()
    switch action {
    case .newConversation: openPanel(tab: 0, resetConversation: true)
    case .openArchive: openPanel(tab: 1)
    case .continueConversation:
      if let recent = store.archive.first { store.openConversation(recent) }
      openPanel(tab: 0)
    case .openSettings: openSettings()
    case .toggleVoice: store.toggleVoice()
    case .stopSpeaking: store.stopSpeaking()
    case .about: showAbout()
    case .terminate: NSApp.terminate(nil)
    }
  }

  // MARK: - 우클릭 컨텍스트 메뉴

  private func buildMenu() -> NSMenu {
    let menu = NSMenu()
    let sc = ShortcutCombo.display(store.settings.globalShortcut)
    let items: [(String, Selector, String, AnyObject?)] = [
      (Lf("대화 열기 (%@)", sc), #selector(openPanelAction), "", self),
      (L("보관함"), #selector(openArchiveAction), "1", self),
      (L("음성 입력 토글"), #selector(toggleVoiceAction), "", self),
    ]
    for title in items {
      let it = NSMenuItem(title: title.0, action: title.1, keyEquivalent: title.2)
      it.target = title.3
      menu.addItem(it)
    }
    menu.addItem(.separator())
    let settings = NSMenuItem(title: L("설정…"), action: #selector(openSettingsMenu), keyEquivalent: ",")
    settings.target = self
    menu.addItem(settings)
    let about = NSMenuItem(title: L("정보"), action: #selector(showAboutAction), keyEquivalent: "")
    about.target = self
    menu.addItem(about)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: L("QuickTalk 종료"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.target = NSApp
    menu.addItem(quit)
    return menu
  }

  @objc private func openPanelAction() { openPanel(tab: 0) }
  @objc private func openArchiveAction() { openPanel(tab: 1) }
  @objc private func toggleVoiceAction() { store.toggleVoice() }
  @objc private func openSettingsMenu() { openSettings() }
  @objc private func showAboutAction() { showAbout() }

  private func showAbout() {
    activateApp()
    NSApp.orderFrontStandardAboutPanel(nil)
    // 정보 패널도 대화 창(항상 위) 뒤로 숨지 않게 추적한다
    if let w = NSApp.keyWindow, w !== panel { trackAuxWindow(w) }
  }

  /// 설정 창 — 전용 NSWindow로 직접 관리한다.
  /// (SwiftUI `Settings` 씬은 메인 메뉴를 교체하면 열리지 않으므로 셀렉터에 의존하지 않는다.)
  private func openSettings() {
    activateApp()
    let initial = Self.qaInitialTab()
    if settingsWindow == nil {
      let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 540),
                       styleMask: [.titled, .closable, .miniaturizable, .resizable],
                       backing: .buffered, defer: false)
      w.title = L("QuickTalk 설정")
      w.contentView = NSHostingView(rootView: SettingsView(initialTab: initial).environmentObject(store))
      w.isReleasedWhenClosed = false
      w.setFrameAutosaveName("QuickTalkSettingsWindow")
      w.center()
      settingsWindow = w
      NSLog("[QuickTalk] 설정 창 생성 (tab=%@)", initial.rawValue)
    }
    settingsWindow?.makeKeyAndOrderFront(nil)
    if let w = settingsWindow { trackAuxWindow(w) }
  }

  /// QA용: `--settings-tab=<general|shortcut|ai|voice|archive|about>`
  private static func qaInitialTab() -> QuickTalkSettingsTab {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--settings-tab=") }) else { return .general }
    return QuickTalkSettingsTab(rawValue: String(arg.dropFirst("--settings-tab=".count))) ?? .general
  }

  /// QA용: `--panel-tab=<chat|archive|settings>` — `--open-panel` 과 함께 쓰면 해당 탭으로 연다
  private static func qaPanelTab() -> Int {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--panel-tab=") }) else { return 0 }
    switch arg.dropFirst("--panel-tab=".count) {
    case "archive": return 1
    case "settings": return 2
    default: return 0
    }
  }

  // MARK: - 창 레벨 (항상 위 · 설정/권한 창 가림 방지)

  /// 우리 앱의 보조 창(설정·정보). 떠 있는 동안 대화 창은 일반 레벨로 내린다.
  private var auxWindows: [NSWindow] = []
  /// 진행 중인 시스템 권한 안내 수(안내가 끝나면 0)
  private var systemPromptDepth = 0
  private var systemPromptTimer: Timer?

  /// 대화 창 레벨 계산 — **기본은 일반 창**.
  /// 헤더 📌(`settings.alwaysOnTop`)이 켜져 있고, 설정·정보 창이나 시스템 권한 안내가 없을 때만 `.floating`.
  private func applyPanelLevel() {
    guard let panel else { return }
    let blocked = systemPromptDepth > 0 || auxWindows.contains { $0.isVisible }
    let wantTop = store.settings.alwaysOnTop
    let level: NSWindow.Level = (wantTop && !blocked) ? .floating : .normal
    if panel.level != level {
      panel.level = level
      NSLog("[QuickTalk] 대화 창 레벨 %@ (항상위=%@ 가림방지=%@)",
            level == .floating ? "floating" : "normal", wantTop ? "Y" : "N", blocked ? "Y" : "N")
    }
  }

  /// 설정·정보 창을 추적해 그 창이 떠 있는 동안 대화 창을 내린다.
  private func trackAuxWindow(_ window: NSWindow) {
    if !auxWindows.contains(where: { $0 === window }) { auxWindows.append(window) }
    applyPanelLevel()
  }

  /// 시스템 권한 안내(화면 기록·마이크·받아쓰기)가 대화 창 뒤로 숨지 않게 잠시 내린다.
  /// 완료 콜백이 오지 않아도 30초 뒤 자동 복구한다.
  private func beginSystemPrompt() {
    systemPromptDepth += 1
    applyPanelLevel()
    systemPromptTimer?.invalidate()
    systemPromptTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: false) { [weak self] _ in
      DispatchQueue.main.async {
        self?.systemPromptDepth = 0
        self?.applyPanelLevel()
      }
    }
  }

  private func endSystemPrompt(force: Bool = false) {
    systemPromptDepth = force ? 0 : max(0, systemPromptDepth - 1)
    if systemPromptDepth == 0 {
      systemPromptTimer?.invalidate()
      systemPromptTimer = nil
    }
    applyPanelLevel()
  }

  /// 창이 닫히면 가림 방지 상태를 다시 계산하고, 앱이 다시 활성화되면 시스템 안내 상태를 푼다.
  private func installWindowLevelObservers() {
    NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] _ in
      DispatchQueue.main.async { self?.applyPanelLevel() }
    }
    NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      self?.endSystemPrompt(force: true)
    }
  }

  // MARK: - 대화 패널

  private func buildPanel() {
    let root = ContentView(initialTab: 0).environmentObject(store)
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
      styleMask: [.titled, .fullSizeContentView, .closable, .miniaturizable, .resizable],
      backing: .buffered, defer: false)
    panel.contentView = NSHostingView(rootView: root)
    // 기본은 **일반 창 레벨**. 설정 창·시스템 권한 안내가 대화 창 뒤로 숨지 않게 한다.
    // 헤더 📌(settings.alwaysOnTop)을 켜면 applyPanelLevel()이 `.floating`으로 올린다.
    panel.level = .normal
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = false
    panel.isMovableByWindowBackground = true
    panel.title = "QuickTalk"
    // 가변 크기(PLAN_v0.12): 최소 420×420. 크기·위치는 NSWindow가 기억한다.
    panel.contentMinSize = NSSize(width: 420, height: 420)
    panel.setFrameAutosaveName("QuickTalkMainPanel")
    if !panel.setFrameUsingName("QuickTalkMainPanel") { panel.center() }
  }

  private func togglePanel(fromShortcut: Bool) {
    // pill이 떠 있으면 단축키를 다시 눌렀을 때 닫는다(Spotlight 토글).
    if PointerPillController.shared.isVisible {
      PointerPillController.shared.dismiss()
      return
    }
    if panel.isVisible {
      // 기본 레벨(일반 창)에서는 다른 앱 뒤에 있을 수 있다 — 그때는 닫지 말고 앞으로 가져온다.
      let frontmost = NSApp.isActive && panel.isKeyWindow
      guard frontmost else { showPanel(tab: 0); return }
      panel.orderOut(nil)
      return
    }
    // 단축키: 유지 시간(기본 10분) 안이면 마지막 대화를 이어서, 지났으면 새 대화.
    // 새 대화일 때는 빈 대화 창 대신 포인터 pill을 띄운다(T-21) — 창은 하나이고 표현만 다르다.
    if fromShortcut {
      let entry = ShortcutEntryPresentation.decide(
        settings: store.settings,
        lastActivity: store.conversation.updatedAt,
        hasTurns: !store.conversation.turns.isEmpty)
      if entry == .pill {
        PointerPillController.shared.present()
        return
      }
      store.startShortcutSession()
    }
    showPanel(tab: 0)
  }

  /// pill에서 고른 다음 동작 — 같은 대화 창으로 이어받는다.
  private func handlePill(_ outcome: PillOutcome) {
    switch outcome {
    case .send(let text):
      store.startShortcutSession()
      store.draft = text
      showPanel(tab: 0)
      store.send()
    case .openChat(let draft):
      store.startShortcutSession()
      store.draft = draft
      showPanel(tab: 0)
    case .resume(let conversation):
      store.openConversation(conversation)
      showPanel(tab: 0)
    case .archive:
      showPanel(tab: 1)
    }
  }

  /// QuickShelf 사용 결과를 확인할 수 있게 대화 창을 앞으로 (이미 보이면 위치·탭만 맞춘다)
  private func showChatFromShelf() {
    guard let panel else { return }
    if panel.isVisible {
      // 뒤에 있을 수 있으니 앞으로 올린 뒤 탭만 맞춘다
      activateApp()
      applyPanelLevel()
      panel.makeKeyAndOrderFront(nil)
      NotificationCenter.default.post(name: .openQuickTalk, object: 0)
      NotificationCenter.default.post(name: .quickTalkScrollToBottom, object: nil)
      return
    }
    openPanel(tab: 0)
  }

  private func openPanel(tab: Int, resetConversation: Bool = false) {
    if resetConversation { store.newConversation() }
    showPanel(tab: tab)
  }

  /// 대화 창 표시 — 배치 후 앱을 앞으로 가져온다.
  /// NSPanel은 키 창이 되면서도 앱은 활성화되지 않을 수 있어(그러면 ⌘C/⌘V/⌘Z가 메뉴로 전달되지 않는다),
  /// 활성화를 명시적으로 한 번 더 밀어 준다.
  private func showPanel(tab: Int) {
    activateApp()
    positionPanel()
    applyPanelLevel()
    panel.makeKeyAndOrderFront(nil)
    NotificationCenter.default.post(name: .openQuickTalk, object: tab)
    // 창을 열면 대화는 항상 맨 아래(마지막 턴)부터 — 이어서 열 때도
    NotificationCenter.default.post(name: .quickTalkScrollToBottom, object: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
      guard let self else { return }
      if !NSApp.isActive { self.activateApp() }
      NSLog("[QuickTalk] 창 표시: isActive=%@ isKey=%@", NSApp.isActive ? "Y" : "N",
            self.panel.isKeyWindow ? "Y" : "N")
    }
  }

  /// 앱을 앞으로 가져온다. macOS 14+ 협조적 활성화에서 무시되면 NSRunningApplication으로 보강한다.
  private func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
    if !NSApp.isActive {
      NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
  }

  /// ⌘ 편집 단축키 보조 경로. Carbon 등록이 우선이고, 등록이 없을 때만 직접 응답자 체인으로 넘긴다.
  /// (진단: `--debug-keys` 로 실행하면 수신한 ⌘ 키 이벤트를 로그에 남긴다.)
  private func installEditShortcutMonitor() {
    let debugKeys = CommandLine.arguments.contains("--debug-keys")
    NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
      guard let self else { return e }
      let flags = e.modifierFlags.intersection([.command, .shift, .control, .option])
      guard flags == .command || flags == [.command, .shift] else { return e }
      if debugKeys {
        NSLog("[QuickTalk] ⌘키 수신 keyCode=%d chars=%@ keyWindow=%@ isActive=%@",
              e.keyCode, e.charactersIgnoringModifiers ?? "?",
              NSApp.keyWindow?.title ?? L("없음"), NSApp.isActive ? "Y" : "N")
      }
      guard self.editHotKeyIDs.isEmpty, let window = NSApp.keyWindow, self.isOwnWindow(window) else { return e }
      let action: Selector?
      switch e.keyCode {
      case 0x09: action = #selector(NSText.paste(_:))       // V
      case 0x08: action = #selector(NSText.copy(_:))        // C
      case 0x07: action = #selector(NSText.cut(_:))         // X
      case 0x00: action = #selector(NSText.selectAll(_:))   // A
      case 0x06: action = NSSelectorFromString(flags.contains(.shift) ? "redo:" : "undo:") // Z
      default: action = nil
      }
      guard let action else { return e }
      return NSApp.sendAction(action, to: nil, from: window) ? nil : e
    }
  }

  /// ⌘C/⌘V/⌘X/⌘A/⌘Z — 메뉴바 없는(LSUIElement) 앱에서는 키 등가가 macOS 정책상 불안정하게만 전달된다.
  /// 창이 키일 때만 Carbon으로 등록하고, 창이 키를 잃으면 즉시 해제한다(다른 앱 단축키를 가로채지 않는다).
  private func installEditShortcuts() {
    let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                      NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
    for name in names {
      NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.syncEditShortcuts()
      }
    }
    syncEditShortcuts()
  }

  /// 우리 앱의 창이 키이고 앱이 활성일 때만 편집 단축키를 등록한다.
  private func syncEditShortcuts() {
    // QA: `--no-edit-hotkeys` 는 Carbon 등록을 끄고 로컬 모니터 경로만 쓴다(진단용)
    if CommandLine.arguments.contains("--no-edit-hotkeys") { return }
    let debugKeys = CommandLine.arguments.contains("--debug-keys")
    let keyWindow = NSApp.keyWindow
    let shouldRegister = NSApp.isActive && (keyWindow.map(isOwnWindow) ?? false)
    if shouldRegister, editHotKeyIDs.isEmpty {
      let combos: [(String, Selector)] = [
        ("Cmd+C", #selector(NSText.copy(_:))),
        ("Cmd+V", #selector(NSText.paste(_:))),
        ("Cmd+X", #selector(NSText.cut(_:))),
        ("Cmd+A", #selector(NSText.selectAll(_:))),
        ("Cmd+Z", NSSelectorFromString("undo:")),
        ("Cmd+Shift+Z", NSSelectorFromString("redo:")),
      ]
      for (shortcut, selector) in combos {
        guard let parsed = GlobalHotKey.parse(shortcut),
              let id = GlobalHotKey.shared.registerTemporary(keyCode: parsed.keyCode,
                                                             modifiers: parsed.modifiers,
                                                             action: { [weak self] in
          let target = NSApp.keyWindow.flatMap { self?.isOwnWindow($0) == true ? $0 : nil }
          let handled = target.map { NSApp.sendAction(selector, to: nil, from: $0) } ?? false
          if debugKeys {
            NSLog("[QuickTalk] 편집 단축키 %@ 이벤트 → %@", shortcut, handled ? "처리" : "대상 없음")
          }
        }) else { continue }
        editHotKeyIDs.append(id)
      }
      NSLog("[QuickTalk] 편집 단축키 등록: %d개", editHotKeyIDs.count)
    } else if !shouldRegister, !editHotKeyIDs.isEmpty {
      editHotKeyIDs.forEach { GlobalHotKey.shared.unregister(id: $0) }
      editHotKeyIDs.removeAll()
    }
  }

  /// 대화 창·설정 창(과 그 시트)인지.
  private func isOwnWindow(_ window: NSWindow) -> Bool {
    if window === panel || window === settingsWindow { return true }
    if let parent = window.sheetParent ?? window.parent { return isOwnWindow(parent) }
    return false
  }

  /// 새 대화 창 배치 — 독립 창이므로 설정에 따라 화면 중앙 또는 마우스 포인터에 띄운다.
  /// (메뉴바 아이콘 하단 고정은 쓰지 않는다. 팝오버는 Hub 뿐이다.)
  /// 포인터 모드에서 현재 커서가 메뉴바·Dock 위(작업 영역 밖)면 "직전 작업 위치"를 쓴다.
  private func positionPanel() {
    let size = panel.frame.size
    let mode = Self.qaPanelPosition() ?? store.settings.newWindowPosition
    let pointerNow = NSEvent.mouseLocation
    // 창 중심이 놓일 좌표. nil이면 화면 중앙.
    let target: NSPoint?
    switch mode {
    case .center:
      target = nil
    case .mousePointer:
      target = Self.screenContaining(pointerNow) != nil ? pointerNow : pointerCache
    }
    // 기준 화면: 목표 지점이 속한 화면 → 없으면 메인
    let screen = target.flatMap { Self.screenContaining($0) } ?? NSScreen.main
    guard let vis = screen?.visibleFrame else { panel.center(); return }

    var origin: NSPoint
    if let t = target {
      origin = NSPoint(x: t.x - size.width / 2, y: t.y - size.height / 2)
      NSLog("[QuickTalk] 창 배치: 포인터 모드 origin=(%.0f, %.0f)", origin.x, origin.y)
    } else {
      origin = NSPoint(x: vis.midX - size.width / 2, y: vis.midY - size.height / 2)
      NSLog("[QuickTalk] 창 배치: 중앙 모드 origin=(%.0f, %.0f)", origin.x, origin.y)
    }
    // 화면 밖으로 나가지 않게 클램프
    origin.x = min(max(origin.x, vis.minX), max(vis.minX, vis.maxX - size.width))
    origin.y = min(max(origin.y, vis.minY), max(vis.minY, vis.maxY - size.height))
    panel.setFrameOrigin(origin)
  }

  /// QA용: `--panel-position=<center|mousePointer>` (설정값 대신 이번 실행만 override)
  private static func qaPanelPosition() -> NewWindowPosition? {
    guard let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--panel-position=") }) else { return nil }
    return NewWindowPosition(rawValue: String(arg.dropFirst("--panel-position=".count)))
  }

  // 단축키: 기본 Cmd+Space, 설정에서 변경. Carbon RegisterEventHotKey로 등록하므로
  // 앱에 포커스가 없어도(바탕화면·다른 앱 사용 중) 전역으로 동작한다. 권한 요구 없음.
}

extension Notification.Name {
  static let openQuickTalk = Notification.Name("openQuickTalk")
  static let quickTalkOpenSettings = Notification.Name("quickTalkOpenSettings")
  /// QuickShelf에서 무언가를 대화에 넣었을 때 대화 창을 보여달라는 요청
  static let quickTalkShowChat = Notification.Name("quickTalkShowChat")
  /// 대화 창을 열 때(또는 이어서 열 때) 대화 스크롤을 맨 아래로 맞추라는 요청
  static let quickTalkScrollToBottom = Notification.Name("quickTalkScrollToBottom")
  /// 시스템 권한 안내(대화상자·시스템 설정)가 대화 창 뒤로 숨지 않게 잠시 내리라는 요청
  static let quickTalkSystemPromptBegin = Notification.Name("quickTalkSystemPromptBegin")
  static let quickTalkSystemPromptEnd = Notification.Name("quickTalkSystemPromptEnd")
  /// 단축키 녹화 시작/끝 — 그동안 전역 핫키를 풀어 새 조합을 받을 수 있게 한다
  static let quickTalkSuspendShortcuts = Notification.Name("quickTalkSuspendShortcuts")
  static let quickTalkResumeShortcuts = Notification.Name("quickTalkResumeShortcuts")
}
