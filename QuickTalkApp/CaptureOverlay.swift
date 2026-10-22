import AppKit

// [REFACTOR] 캡처 오버레이 — 드래그 선택 · 윈도우 강조 (2026-10-20 CaptureService에서 분리)
// Esc 취소·십자 커서·윈도우 모드 하이라이트는 모두 이 파일에 있다.

// MARK: - 오버레이 (드래그 선택 · 윈도우 강조)

/// borderless 창은 기본적으로 key가 될 수 없어 Esc 키가 전달되지 않는다 — 오버레이 전용 서브클래스
final class CaptureOverlayWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

final class CaptureOverlayController: NSObject {
  enum Mode { case region, window }

  let mode: Mode
  let screen: NSScreen
  let frozen: CGImage
  /// 잡을 수 있는 창 목록 — **모드와 무관하게** 항상 채워 둔다
  /// (드래그 모드 → Space → 윈도우 모드 전환 시에도 필요)
  var windows: [CaptureWindowTarget]
  /// 드래그 선택(로컬 좌표) 완료
  var onFinish: ((CGImage, ShelfCapture.Source) -> Void)?
  /// 윈도우 모드에서 창 선택 — 그 창만 다시 캡처한다(화면 자르기가 아님)
  var onPickWindow: ((CaptureWindowTarget) -> Void)?
  var onCancel: (() -> Void)?
  /// 윈도우 모드로 전환할 때 창 목록을 다시 읽는다
  var onRefreshWindows: (() -> [CaptureWindowTarget])?

  private var window: NSWindow?
  /// Esc 보조 경로 — 창이 key가 아니어도 앱이 이벤트를 받으면 취소한다
  private var escMonitor: Any?

  init(mode: Mode, screen: NSScreen, frozen: CGImage, windows: [CaptureWindowTarget]) {
    self.mode = mode
    self.screen = screen
    self.frozen = frozen
    self.windows = windows
  }

  func begin() {
    let win = CaptureOverlayWindow(contentRect: screen.frame, styleMask: [.borderless],
                                   backing: .buffered, defer: false)
    win.level = .screenSaver
    win.isOpaque = true
    win.backgroundColor = .black
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    win.acceptsMouseMovedEvents = true
    win.ignoresMouseEvents = false

    let view = CaptureOverlayView(frame: NSRect(origin: .zero, size: screen.frame.size),
                                  mode: mode,
                                  frozen: NSImage(cgImage: frozen, size: screen.frame.size),
                                  screenFrame: screen.frame,
                                  windows: windows)
    view.onSelect = { [weak self] rect in
      self?.finish(rect)
    }
    view.onPickWindow = { [weak self] target in
      self?.pick(target)
    }
    view.onCancel = { [weak self] in
      self?.cancel()
    }
    // 윈도우 모드로 전환할 때 목록을 다시 읽는다
    view.onRefreshWindows = { [weak self] in
      guard let self else { return [] }
      let fresh = self.onRefreshWindows?() ?? []
      self.windows = fresh
      return fresh
    }
    win.contentView = view
    NSApp.activate(ignoringOtherApps: true)
    win.makeKeyAndOrderFront(nil)
    win.makeFirstResponder(view)
    win.invalidateCursorRects(for: view)
    NSCursor.crosshair.set()
    // 앱 활성화는 비동기로 끝나고, 그 순간 macOS가 커서를 화살표로 다시 계산한다.
    // 다음 틱에 사각형을 무효화하고 한 번 더 십자로 고정한다(첫 프레임에서 화살표로 바뀌던 문제).
    DispatchQueue.main.async { [weak self] in
      guard let self, self.window === win else { return }
      win.invalidateCursorRects(for: view)
      NSCursor.crosshair.set()
    }
    escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard event.keyCode == 53 else { return event }   // Esc
      self?.cancel()
      return nil
    }
    window = win
    NSLog("[QuickShelf] 캡처 오버레이 mode=%@ screen=%@", mode == .region ? "region" : "window",
          screen.localizedName)
  }

  private func finish(_ rect: NSRect) {
    guard rect.width >= 4, rect.height >= 4 else { cancel(); return }
    let scale = CGFloat(frozen.width) / screen.frame.width
    let px = CaptureGeometry.pixelCrop(local: rect, screenHeight: screen.frame.height, scale: scale)
    close()
    guard px.width >= 1, px.height >= 1, let cropped = frozen.cropping(to: px) else {
      onCancel?()
      return
    }
    onFinish?(cropped, .region)
  }

  /// 윈도우 모드 — 오버레이를 먼저 내리고, 그 창만 다시 캡처하도록 넘긴다
  private func pick(_ target: CaptureWindowTarget) {
    close()
    onPickWindow?(target)
  }

  private func cancel() {
    close()
    onCancel?()
  }

  private func close() {
    if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
    NSCursor.arrow.set()
    window?.orderOut(nil)
    window = nil
  }

  // MARK: - QA

  /// QA 전용 — Space 키를 흉내내 모드 전환을 확인한다(드래그 → 윈도우).
  /// 반환: (모드, 잡을 수 있는 창 수, 강조 여부)
  func simulateSpaceForQA() -> (mode: String, windows: Int, highlight: Bool) {
    guard let window, let view = window.contentView as? CaptureOverlayView else {
      return ("none", 0, false)
    }
    if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   characters: " ", charactersIgnoringModifiers: " ",
                                   isARepeat: false, keyCode: 49) {
      view.keyDown(with: event)
    }
    return (view.modeLabel, view.windowCount, view.hasHighlight)
  }
}

final class CaptureOverlayView: NSView {
  /// Space로 드래그 ↔ 윈도우 모드를 오간다(macOS 기본 캡처와 같은 동작)
  private(set) var mode: CaptureOverlayController.Mode
  private let frozen: NSImage
  private let screenFrame: NSRect
  /// 잡을 수 있는 창 목록 — 모드와 무관하게 채워 둔다
  private var windows: [CaptureWindowTarget]
  var onSelect: ((NSRect) -> Void)?
  var onPickWindow: ((CaptureWindowTarget) -> Void)?
  var onCancel: (() -> Void)?
  /// 윈도우 모드 진입 시 목록을 다시 읽는 훅
  var onRefreshWindows: (() -> [CaptureWindowTarget])?

  private var startPoint: NSPoint?
  private var currentPoint: NSPoint?
  private var mouse: NSPoint = .zero
  /// 마우스 아래 창(가장 앞) — 강조·라벨에 쓴다
  private var highlighted: CaptureWindowTarget?

  init(frame: NSRect, mode: CaptureOverlayController.Mode, frozen: NSImage,
       screenFrame: NSRect, windows: [CaptureWindowTarget]) {
    self.mode = mode
    self.frozen = frozen
    self.screenFrame = screenFrame
    self.windows = windows
    super.init(frame: frame)
  }

  required init?(coder: NSCoder) { fatalError() }

  override var acceptsFirstResponder: Bool { true }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  /// 커서 사각형 — AppKit이 마우스를 움직일 때마다 커서를 되돌리므로 여기서 십자를 다시 지정한다
  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .crosshair)
  }

  /// 십자 커서를 유지한다 — 창이 key가 되거나 앱이 활성화될 때, 마우스가 움직일 때
  /// AppKit이 커서를 화살표로 다시 계산하므로 이벤트마다 한 번 더 지정한다.
  private func keepCrosshair() {
    NSCursor.crosshair.set()
  }

  override func cursorUpdate(with event: NSEvent) {
    keepCrosshair()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    guard let window else { return }
    // 오버레이가 뜨는 순간의 마우스 위치 — Space로 윈도우 모드로 바꿀 때 바로 강조가 보이게
    mouse = convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    if mode == .window { highlighted = windowTarget(at: mouse) }
    window.invalidateCursorRects(for: self)
    // 창이 표시된 직후(첫 draw)에 시스템이 커서를 다시 계산하는 경우가 있어 다음 틱에 재확정
    DispatchQueue.main.async { [weak self] in
      guard let self, let window = self.window else { return }
      window.invalidateCursorRects(for: self)
      self.keepCrosshair()
    }
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    for area in trackingAreas { removeTrackingArea(area) }
    addTrackingArea(NSTrackingArea(rect: .zero,
                                   options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                   owner: self, userInfo: nil))
  }

  override func mouseEntered(with event: NSEvent) {
    keepCrosshair()
  }

  private var selection: NSRect? {
    guard let a = startPoint, let b = currentPoint else { return nil }
    return NSRect(x: min(a.x, b.x), y: min(a.y, b.y),
                  width: abs(a.x - b.x), height: abs(a.y - b.y))
  }

  // MARK: 이벤트

  /// QA 전용 접근자 — 모드·창 수·강조 여부
  var modeLabel: String { mode == .window ? "window" : "region" }
  var windowCount: Int { windows.count }
  var hasHighlight: Bool { highlighted != nil }

  override func mouseDown(with event: NSEvent) {
    keepCrosshair()
    let p = convert(event.locationInWindow, from: nil)
    mouse = p
    if mode == .window {
      if let target = windowTarget(at: p) { onPickWindow?(target) }
      return
    }
    startPoint = p
    currentPoint = p
    needsDisplay = true
  }

  override func mouseDragged(with event: NSEvent) {
    keepCrosshair()
    let p = convert(event.locationInWindow, from: nil)
    mouse = p
    if mode == .region {
      currentPoint = p
      needsDisplay = true
    }
  }

  override func mouseUp(with event: NSEvent) {
    keepCrosshair()
    guard mode == .region else { return }
    let p = convert(event.locationInWindow, from: nil)
    currentPoint = p
    if let sel = selection, sel.width >= 4, sel.height >= 4 {
      onSelect?(sel)
    } else {
      startPoint = nil
      currentPoint = nil
      needsDisplay = true
    }
  }

  override func mouseMoved(with event: NSEvent) {
    keepCrosshair()
    mouse = convert(event.locationInWindow, from: nil)
    if mode == .window {
      highlighted = windowTarget(at: mouse)
      needsDisplay = true
    }
  }

  override func keyDown(with event: NSEvent) {
    switch event.keyCode {
    case 53: onCancel?()        // Esc
    case 49: toggleMode()       // Space = 드래그 ↔ 윈도우 (macOS 기본 캡처와 동일)
    default: break
    }
  }

  /// 드래그 중이 아니면 두 모드를 오간다. 윈도우 모드로 바뀌면 마우스 아래 창을 바로 강조한다.
  private func toggleMode() {
    guard startPoint == nil, currentPoint == nil else { return }
    mode = (mode == .region) ? .window : .region
    if mode == .window {
      // 창 목록을 다시 읽는다 — 오버레이가 뜬 뒤 새로 열린 창도 잡히도록
      if let refreshed = onRefreshWindows?(), !refreshed.isEmpty {
        windows = refreshed
      }
      highlighted = windowTarget(at: mouse)
    } else {
      highlighted = nil
    }
    needsDisplay = true
  }

  /// Esc는 `cancelOperation:`으로 올 수도 있다(키 해석 경로)
  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  /// 윈도우 모드 — 마우스 아래(가장 앞) 창을 찾는다.
  /// `windows`는 AppKit 전역 좌표(좌하단 원점)이고, 여기서도 같은 좌표계로 맞춰 비교한다.
  private func windowTarget(at p: NSPoint) -> CaptureWindowTarget? {
    let screenPoint = NSPoint(x: p.x + screenFrame.minX, y: p.y + screenFrame.minY)
    return windows.first { $0.rect.contains(screenPoint) }
  }

  // MARK: 그리기

  override func draw(_ dirtyRect: NSRect) {
    frozen.draw(in: bounds)

    NSColor.black.withAlphaComponent(0.5).setFill()
    bounds.fill()

    if mode == .window {
      if let target = highlighted {
        let hl = target.localRect(in: screenFrame)
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: hl).addClip()
        frozen.draw(in: hl, from: hl, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        NSColor(red: 0.61, green: 0.53, blue: 1, alpha: 1).setStroke()
        let border = NSBezierPath(roundedRect: hl.insetBy(dx: -1, dy: -1), xRadius: 9, yRadius: 9)
        border.lineWidth = 2
        border.stroke()
        // 어느 창을 잡았는지 이름으로 확인할 수 있게 한다
        let name = target.appName ?? L("윈도우")
        drawLabel(Lf("%@ — 클릭하여 캡처", name), at: NSPoint(x: hl.minX, y: hl.maxY + 8),
                  background: NSColor(red: 0.48, green: 0.36, blue: 1, alpha: 0.95))
      }
      // 잡을 수 있는 창이 하나도 없으면 이유를 알려준다(라벨만 바뀌고 아무것도 안 되는 상태 방지)
      if windows.isEmpty {
        drawHint(L("잡을 수 있는 창이 없습니다 · Space = 드래그 · Esc = 취소"))
      } else {
        drawHint(L("클릭 = 윈도우 캡처 · Space = 드래그 · Esc = 취소"))
      }
      return
    }

    // 드래그 선택
    if let sel = selection, sel.width > 0, sel.height > 0 {
      NSGraphicsContext.saveGraphicsState()
      NSBezierPath(rect: sel).addClip()
      frozen.draw(in: sel, from: sel, operation: .sourceOver, fraction: 1)
      NSGraphicsContext.restoreGraphicsState()

      NSColor(red: 0.61, green: 0.53, blue: 1, alpha: 1).setStroke()
      let border = NSBezierPath(rect: sel)
      border.lineWidth = 1.5
      border.stroke()

      // 모서리 핸들
      NSColor.white.setFill()
      for p in [NSPoint(x: sel.minX, y: sel.minY), NSPoint(x: sel.maxX, y: sel.minY),
                NSPoint(x: sel.minX, y: sel.maxY), NSPoint(x: sel.maxX, y: sel.maxY)] {
        NSBezierPath(ovalIn: NSRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)).fill()
      }

      drawLabel("\(Int(sel.width)) × \(Int(sel.height))",
                at: NSPoint(x: sel.maxX - 72, y: sel.maxY + 8),
                background: NSColor(white: 0.12, alpha: 0.92))
    }

    drawHint(L("드래그하여 선택 · Space = 윈도우 · Esc = 취소"))
  }

  private func drawHint(_ text: String) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.systemFont(ofSize: 11),
      .foregroundColor: NSColor.white.withAlphaComponent(0.85)
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    let rect = NSRect(x: bounds.midX - size.width / 2 - 14, y: 26,
                      width: size.width + 28, height: size.height + 12)
    NSColor(white: 0.08, alpha: 0.9).setFill()
    NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10).fill()
    (text as NSString).draw(at: NSPoint(x: rect.minX + 14, y: rect.minY + 6), withAttributes: attrs)
  }

  private func drawLabel(_ text: String, at p: NSPoint, background: NSColor) {
    let attrs: [NSAttributedString.Key: Any] = [
      .font: NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .medium),
      .foregroundColor: NSColor.white
    ]
    let size = (text as NSString).size(withAttributes: attrs)
    let rect = NSRect(x: p.x, y: p.y, width: size.width + 14, height: size.height + 8)
    background.setFill()
    NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
    (text as NSString).draw(at: NSPoint(x: rect.minX + 7, y: rect.minY + 4), withAttributes: attrs)
  }
}
