import AppKit
import SwiftUI
import Combine
import Carbon
import QuartzCore
import UniformTypeIdentifiers

// [INFO] [FEATURE] QuickShelf 창 관리 — 플로팅 패널 (PLAN_v0.13)
// 화면 가장자리 핸들 표시는 제거했다(사용자 결정, 2026-10-21).
// 이제 QuickShelf는 단축키(기본 ⌥⇧V) 또는 헤더 버튼으로 연다.

/// 패널 창 — Esc로 닫히도록 key를 받을 수 있게 한다(앱을 활성화하지는 않음)
final class ShelfPanelWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    ShelfController.shared.close()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 {           // Esc
      ShelfController.shared.close()
      return
    }
    super.keyDown(with: event)
  }

  /// 패널이 key일 때의 키 조합 — 메뉴(NSMenu)를 거치지 않고 여기서 직접 처리한다
  /// (앱이 비활성 상태여도 패널은 key가 될 수 있고, SwiftUI keyboardShortcut은 메뉴 기반이라 확실하지 않다)
  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    let key = event.charactersIgnoringModifiers?.lowercased()
    if key == "o" {
      if flags == .command {
        ShelfController.shared.pickFiles(imagesOnly: false)
        return true
      }
      if flags == [.command, .shift] {
        ShelfController.shared.pickFiles(imagesOnly: true)
        return true
      }
    }
    return super.performKeyEquivalent(with: event)
  }
}

final class ShelfController {
  static let shared = ShelfController()

  private var panel: ShelfPanelWindow?
  private var previewPanel: NSPanel?
  private var previewWork: DispatchWorkItem?
  private weak var store: UIStore?
  private var bag = Set<AnyCancellable>()
  /// 캡처 순간 대화창을 내렸는지(되돌리기 판단용)
  private var chatHiddenForCapture = false
  /// 대화창 참조 — 창이 떠 있으면 창 안 도킹, 닫혀 있으면 플로팅 패널로 연다
  private var chatWindowProvider: (() -> NSWindow?)?

  private let panelWidth: CGFloat = ShelfMetrics.width
  private var isOpen = false
  /// 창 안 엣지 패널일 때의 키 처리(Esc·⌘O) — 로컬 모니터
  private var dockKeyMonitor: Any?

  // MARK: - 시작

  func start(store: UIStore, chatWindowProvider: (() -> NSWindow?)? = nil) {
    guard self.store == nil else { return }
    self.chatWindowProvider = chatWindowProvider
    self.store = store
    buildPanel(store: store)
    observeDock(store: store)
    observePreview(store: store)
    startDockKeyMonitor()
    NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                           object: nil, queue: .main) { [weak self] _ in
      if self?.isOpen == true { self?.repositionPanel() }
    }
    NSLog("[QuickShelf] 시작 — 패널 준비 (폭=%.0f)", panelWidth)
  }

  // MARK: - 화면

  private func screen() -> NSScreen {
    // 마우스가 있는 화면을 우선(다중 모니터)
    let p = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  // MARK: - 패널

  private func panelFrame(on s: NSScreen) -> NSRect {
    let f = s.visibleFrame
    let h = max(420, f.height - 80)
    return NSRect(x: f.maxX - panelWidth, y: f.minY + (f.height - h) / 2,
                  width: panelWidth, height: h)
  }

  private func buildPanel(store: UIStore) {
    let win = ShelfPanelWindow(contentRect: panelFrame(on: screen()),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
    win.isFloatingPanel = true
    win.level = .floating
    win.hidesOnDeactivate = false
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = true
    win.isMovableByWindowBackground = false

    let root = ShelfView(store: store,
                         onClose: { [weak self] in self?.close() },
                         onSettings: { [weak self] in self?.close(); NotificationCenter.default.post(name: .quickTalkOpenSettings, object: nil) })
    win.contentView = NSHostingView(rootView: root)
    panel = win

    // 바깥(다른 앱 창)을 클릭해 key를 뺏기면 닫는다 — NSOpenPanel 같은 모달 진행 중에는 유지한다.
    NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                           object: win, queue: .main) { [weak self] _ in
      guard let self, self.isOpen else { return }
      if NSApp.modalWindow != nil { return }        // 파일·이미지 선택 창이 떠 있는 동안
      self.close()
    }
  }

  private func repositionPanel() {
    guard let panel else { return }
    panel.setFrame(panelFrame(on: screen()), display: true)
  }

  // MARK: - 열기/닫기

  /// 대화창이 화면에 떠 있으면 **창 안 도킹**을, 닫혀 있으면 **화면 가장자리 패널**을 토글한다.
  func toggle() {
    guard let chat = chatWindowProvider?(), chat.isVisible else {
      isOpen ? close() : show()
      return
    }
    guard let store else { return }
    if store.shelfDocked {
      store.shelfDocked = false
    } else {
      store.shelfDocked = true
      NSApp.activate(ignoringOtherApps: true)
      chat.makeKeyAndOrderFront(nil)
    }
    NSLog("[QuickShelf] 도킹 토글 (대화창 표시 중)")
  }

  /// 캡처 결과 확인 등 — 사용자가 보고 있는 자리에 허브를 연다.
  func openWhereUserIs() {
    if let chat = chatWindowProvider?(), chat.isVisible {
      if store?.shelfDocked != true { store?.shelfDocked = true }
    } else if !isOpen {
      show()
    }
  }

  func show() {
    // 대화창이 떠 있는 동안에는 창 밖 패널을 띄우지 않는다(같은 허브가 두 곳에 보이지 않게) → 창 안 도킹
    if let chat = chatWindowProvider?(), chat.isVisible {
      if isOpen { close() }
      if store?.shelfDocked != true { store?.shelfDocked = true }
      return
    }
    guard let panel else { return }
    repositionPanel()
    isOpen = true
    let end = panel.frame
    if !panel.isVisible {
      var start = panel.frame
      start.origin.x = start.maxX - 14
      panel.setFrame(start, display: false)
      panel.alphaValue = 0
    }
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.22
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(end, display: true)
      panel.animator().alphaValue = 1
    }
    NSLog("[QuickShelf] 패널 열림")
  }

  func close(animated: Bool = true) {
    guard let panel, isOpen else { return }
    isOpen = false
    hidePreview()
    store?.shelfPreview = nil
    if !animated {
      panel.alphaValue = 1
      panel.orderOut(nil)
      panel.setFrame(panelFrame(on: screen()), display: false)
      NSLog("[QuickShelf] 패널 닫힘(즉시)")
      return
    }
    var end = panel.frame
    end.origin.x = end.maxX - 4
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.18
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      guard let self, !self.isOpen else { return }
      panel.orderOut(nil)
      panel.alphaValue = 1
      panel.setFrame(self.panelFrame(on: self.screen()), display: false)
    }
    NSLog("[QuickShelf] 패널 닫힘")
  }

  var isPanelVisible: Bool { isOpen }

  // MARK: - 캡처 순간 숨김 (우리 UI가 캡처에 찍히지 않게)

  /// 패널·미리보기를 잠깐 내린다. 반환값은 "패널이 열려 있었는지"(복원 판단용).
  @discardableResult
  func hideForCapture() -> Bool {
    let wasOpen = isOpen
    hidePreview()
    if isOpen { close(animated: false) }
    // 대화창(창 안 도킹 포함)도 캡처에 찍히지 않게 내린다
    if let chat = chatWindowProvider?(), chat.isVisible {
      chat.orderOut(nil)
      chatHiddenForCapture = true
    }
    return wasOpen
  }

  /// 캡처가 끝난 뒤 원래대로 되돌린다.
  func restoreAfterCapture(wasOpen: Bool) {
    if chatHiddenForCapture {
      chatHiddenForCapture = false
      chatWindowProvider?()?.orderFrontRegardless()
    }
    if wasOpen { show() }
  }

  // MARK: - 미리보기 창

  /// 창 안 엣지 패널(대화 창 위 오버레이)은 별도 창이 아니라 Esc·⌘O를 창이 직접 받지 않는다.
  /// 활성 앱의 키 이벤트를 로컬 모니터로 가로채 **도킹 상태일 때만** 처리한다.
  private func startDockKeyMonitor() {
    guard dockKeyMonitor == nil else { return }
    dockKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self, let store = self.store, store.shelfDocked else { return event }
      let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
      if event.keyCode == 53 {                       // Esc → 허브 닫기
        store.shelfDocked = false
        return nil
      }
      if let key = event.charactersIgnoringModifiers?.lowercased(), key == "o" {
        if flags == .command { self.pickFiles(imagesOnly: false); return nil }
        if flags == [.command, .shift] { self.pickFiles(imagesOnly: true); return nil }
      }
      return event
    }
  }

  /// 도킹이 켜지면 화면 가장자리 패널은 접는다(같은 허브가 두 곳에 보이지 않게)
  private func observeDock(store: UIStore) {
    store.$shelfDocked
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] docked in
        guard let self, docked else { return }
        self.hidePreview()
        if self.isOpen { self.close() }
      }
      .store(in: &bag)
  }

  private func observePreview(store: UIStore) {
    store.$shelfPreview
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] target in
        guard let self else { return }
        self.previewWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
          guard let self else { return }
          if let target { self.showPreview(target) } else { self.hidePreview() }
        }
        self.previewWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (target == nil ? 0.0 : 0.10), execute: work)
      }
      .store(in: &bag)
  }

  private func showPreview(_ target: ShelfPreviewTarget) {
    // 뜨는 자리 계산: 화면 가장자리 패널이면 패널 왼쪽, 창 안 도킹이면 허브(오른쪽 301) 왼쪽
    let docked = (store?.shelfDocked ?? false) && (chatWindowProvider?()?.isVisible ?? false)
    let anchor: NSRect
    if isOpen, let panel { anchor = panel.frame }
    else if docked, let chat = chatWindowProvider?() { anchor = chat.frame }
    else { return }

    let host = NSHostingView(rootView: ShelfPreviewView(target: target))
    host.layoutSubtreeIfNeeded()
    var size = host.fittingSize
    size.width = 300
    size.height = min(max(size.height, 90), 380)

    let win: NSPanel
    if let existing = previewPanel {
      win = existing
    } else {
      win = NSPanel(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                    styleMask: [.borderless, .nonactivatingPanel],
                    backing: .buffered, defer: false)
      win.isFloatingPanel = true
      win.level = .floating
      win.isOpaque = false
      win.backgroundColor = .clear
      win.hasShadow = true
      win.ignoresMouseEvents = true            // 미리보기가 호버·클릭을 가로채지 않게
      win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
      previewPanel = win
    }
    win.contentView = host
    let shelfEdgeX = docked
      ? anchor.maxX - ShelfMetrics.inset - ShelfMetrics.width
      : anchor.minX
    let x = shelfEdgeX - size.width - ShelfMetrics.previewGap
    let y = anchor.midY - size.height / 2
    let frame = NSRect(x: x, y: min(max(y, screen().visibleFrame.minY + 12),
                                    screen().visibleFrame.maxY - size.height - 12),
                       width: size.width, height: size.height)
    win.setFrame(frame, display: true)
    win.orderFrontRegardless()
  }

  private func hidePreview() {
    previewPanel?.orderOut(nil)
  }

  // MARK: - 파일·이미지 선택 (⌘O / ⌘⇧O — 패널이 key일 때)

  func pickFiles(imagesOnly: Bool) {
    guard let store else { return }
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.prompt = L("퀵셸프에 추가")
    panel.message = imagesOnly ? L("대화에 첨부할 이미지를 고르세요") : L("대화에 첨부할 파일을 고르세요")
    // 지원 형식은 Core의 단일 목록에서 만든다(텍스트·코드·PDF·이미지 — P3)
    panel.allowedContentTypes = imagesOnly
      ? [.image]
      : Array(Set([.plainText] + Attachment.supportedExtensions.compactMap { UTType(filenameExtension: $0) }))
    NSApp.activate(ignoringOtherApps: true)
    let result = panel.runModal()
    guard result == .OK else { return }
    store.addShelfFiles(panel.urls)      // 지원하지 않는 형식은 배너로 안내한다
  }


}
