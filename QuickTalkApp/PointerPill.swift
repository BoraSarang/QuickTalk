import AppKit
import SwiftUI
import Combine

// [FEATURE] T-21 포인터 pill — ⌘Space "새 대화"의 입구 (2026-10-21)
//
// 대화 창과 **별개 창이 아니라 같은 대화의 컴팩트 표현**이다.
// 설정 › 일반의 "단축키로 열 때 유지" 규칙(ShortcutEntryPresentation)이 "새 대화"라고 하면
// 빈 대화 창을 띄우는 대신 포인터 자리에 이 pill만 띄운다.
//   Enter      → 대화 창이 열리며 그 질문을 전송
//   ⌘Return    → 전송하지 않고 대화 창만 연다(빈 입력이면 새 대화 창, 첨부·설정용)
//   Esc        → pill만 닫는다(대화 상태·기록은 그대로)
//   보관함 아이콘 → 최근 대화 4개 + "보관함 전체 열기"

// MARK: - 결과

/// pill에서 사용자가 고른 다음 동작 — AppDelegate가 대화 창으로 이어받는다.
enum PillOutcome {
  case send(String)
  case openChat(draft: String)
  case resume(Conversation)
  case archive
}

// MARK: - 값

enum PillMetrics {
  static let width: CGFloat = 380
  static let height: CGFloat = 56
  /// pill 왼쪽 끝 → 캐럿(입력 시작점)까지. 포인터가 캐럿 자리에 오도록 창을 이만큼 왼쪽으로 둔다.
  static let caretOffset: CGFloat = 55
  static let corner: CGFloat = 28
  static let gap: CGFloat = 8
  static let listWidth: CGFloat = 300
  static let rowHeight: CGFloat = 34
  static let footerHeight: CGFloat = 32
  static let maxRows = 4

  static func listHeight(rows: Int) -> CGFloat {
    CGFloat(min(max(rows, 1), maxRows)) * rowHeight + 1 + footerHeight
  }

  static func totalHeight(showList: Bool, rows: Int) -> CGFloat {
    showList ? height + gap + listHeight(rows: rows) : height
  }
}

final class PillModel: ObservableObject {
  @Published var text = ""
  @Published var showList = false
  @Published var recent: [Conversation] = []
  /// 값이 바뀌면 입력창에 포커스를 준다(pill을 열 때·목록을 닫을 때).
  @Published var focusToken = UUID()
}

// MARK: - 창

/// Esc를 창 수준에서도 받는 borderless 패널 — 입력창이 포커스를 잃어도 닫힌다.
final class PointerPillPanel: NSPanel {
  var onCancel: (() -> Void)?
  var onCommandReturn: (() -> Void)?
  var onOpenArchive: (() -> Void)?

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func cancelOperation(_ sender: Any?) {
    onCancel?()
  }

  override func keyDown(with event: NSEvent) {
    if event.keyCode == 53 { onCancel?(); return }        // Esc
    super.keyDown(with: event)
  }

  override func performKeyEquivalent(with event: NSEvent) -> Bool {
    let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
    // ⌘Return(36) · ⌘Enter(76) — 전송하지 않고 대화 창만 연다
    if flags == .command, event.keyCode == 36 || event.keyCode == 76 {
      onCommandReturn?()
      return true
    }
    // ⌘L — 보관함 전체 열기(목록 푸터에 표시한 키)
    if flags == .command, event.charactersIgnoringModifiers?.lowercased() == "l" {
      onOpenArchive?()
      return true
    }
    return super.performKeyEquivalent(with: event)
  }
}

// MARK: - 컨트롤러

final class PointerPillController {
  static let shared = PointerPillController()

  private(set) var isVisible = false
  private var panel: PointerPillPanel?
  private weak var store: UIStore?
  private var onOutcome: ((PillOutcome) -> Void)?
  private let model = PillModel()
  private var bag = Set<AnyCancellable>()
  /// Esc·단축키로 닫을 때 되돌려 줄 앱(다른 앱에서 ⌘Space를 눌렀던 경우).
  private var previousApp: NSRunningApplication?
  private var openedAt = Date.distantPast

  func start(store: UIStore, onOutcome: @escaping (PillOutcome) -> Void) {
    guard panel == nil else { return }
    self.store = store
    self.onOutcome = onOutcome
    buildPanel(store: store)
    NSLog("[QuickTalk] 포인터 pill 준비 (%.0f×%.0f)", PillMetrics.width, PillMetrics.height)
  }

  // MARK: 열기/닫기

  func present() {
    guard let panel else { return }
    if isVisible {
      model.focusToken = UUID()
      panel.makeKeyAndOrderFront(nil)
      return
    }
    previousApp = NSWorkspace.shared.frontmostApplication
    if previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
      previousApp = nil
    }
    model.recent = recentConversations()
    model.showList = false
    model.focusToken = UUID()

    panel.setFrame(frame(totalHeight: PillMetrics.height), display: false)
    panel.alphaValue = 0
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
    panel.orderFrontRegardless()
    isVisible = true
    openedAt = Date()

    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.12
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 1
    }
    // 창이 실제로 붙은 뒤 한 번 더 포커스를 요청한다(첫 updateNSView에서 window가 아직 nil일 수 있다).
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
      guard let self, self.isVisible else { return }
      self.model.focusToken = UUID()
    }
    NSLog("[QuickTalk] pill 열림 — 최근 대화 %d개", model.recent.count)
  }

  /// `restoringFocus`는 Esc·단축키로 **스스로** 닫을 때만 true.
  /// 다른 앱을 클릭해 포커스를 잃은 경우에는 그 앱을 건드리지 않는다.
  func dismiss(restoringFocus: Bool = true, animated: Bool = true) {
    guard let panel, isVisible else { return }
    isVisible = false
    model.showList = false
    let app = restoringFocus ? previousApp : nil
    previousApp = nil
    guard animated else {
      // 대화 창으로 넘어가는 순간 — pill이 잠깐 겹쳐 보이지 않게 즉시 내린다.
      panel.alphaValue = 1
      panel.orderOut(nil)
      app?.activate(options: [])
      return
    }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.10
      ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
      panel.animator().alphaValue = 0
    } completionHandler: { [weak self] in
      DispatchQueue.main.async {
        guard let self, !self.isVisible else { return }
        panel.orderOut(nil)
        panel.alphaValue = 1
        app?.activate(options: [])
      }
    }
  }

  // MARK: 결과

  func submit(_ raw: String) {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    finish(.send(text))
  }

  func openChatWindow() {
    let draft = model.text.trimmingCharacters(in: .whitespacesAndNewlines)
    finish(.openChat(draft: draft))
  }

  func toggleList() {
    model.showList.toggle()
    model.focusToken = UUID()
    NSLog("[QuickTalk] pill 보관함 목록 %@ — %d개", model.showList ? "열림" : "닫힘", model.recent.count)
  }

  func resume(_ c: Conversation) {
    finish(.resume(c))
  }

  func openArchive() {
    finish(.archive)
  }

  private func finish(_ outcome: PillOutcome) {
    let callback = onOutcome
    model.text = ""
    dismiss(restoringFocus: false, animated: false)
    callback?(outcome)
  }

  // MARK: 화면

  private func recentConversations() -> [Conversation] {
    (store?.archive ?? [])
      .sorted { $0.updatedAt > $1.updatedAt }
      .prefix(PillMetrics.maxRows)
      .map { $0 }
  }

  private func screenForPointer() -> NSScreen? {
    let p = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens.first
  }

  /// 포인터가 **캐럿 자리**에 오도록 — 세로는 포인터 중심, 가로는 입력 시작점.
  private func frame(totalHeight: CGFloat) -> NSRect {
    let p = NSEvent.mouseLocation
    let vf = screenForPointer()?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    let margin: CGFloat = 8
    var x = p.x - PillMetrics.caretOffset
    var y = p.y - PillMetrics.height / 2
    x = min(max(x, vf.minX + margin), max(vf.minX + margin, vf.maxX - PillMetrics.width - margin))
    y = min(max(y, vf.minY + margin), max(vf.minY + margin, vf.maxY - totalHeight - margin))
    return NSRect(x: x.rounded(), y: y.rounded(), width: PillMetrics.width, height: totalHeight)
  }

  private func resizeForList() {
    guard let panel, isVisible else { return }
    let h = PillMetrics.totalHeight(showList: model.showList, rows: model.recent.count)
    var f = panel.frame
    let top = f.maxY
    f.size.height = h
    f.origin.y = top - h
    if let vf = screenForPointer()?.visibleFrame {
      f.origin.y = max(f.origin.y, vf.minY + 8)          // 아래로 넘치면 위로 밀어 넣는다
    }
    NSAnimationContext.runAnimationGroup { ctx in
      ctx.duration = 0.14
      ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(f, display: true)
    }
  }

  // MARK: 만들기

  private func buildPanel(store: UIStore) {
    let root = PillRootView(
      model: model,
      onSubmit: { [weak self] in self?.submit($0) },
      onCancel: { [weak self] in self?.dismiss() },
      onToggleList: { [weak self] in self?.toggleList() },
      onResume: { [weak self] in self?.resume($0) },
      onOpenArchive: { [weak self] in self?.openArchive() }
    )
    let win = PointerPillPanel(contentRect: NSRect(x: 0, y: 0, width: PillMetrics.width, height: PillMetrics.height),
                               styleMask: [.borderless], backing: .buffered, defer: false)
    win.isFloatingPanel = true
    win.level = .floating
    win.hidesOnDeactivate = false
    win.isOpaque = false
    win.backgroundColor = .clear
    win.hasShadow = true
    win.isMovableByWindowBackground = false
    win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    win.contentView = NSHostingView(rootView: root)
    win.onCancel = { [weak self] in self?.dismiss() }
    win.onCommandReturn = { [weak self] in self?.openChatWindow() }
    win.onOpenArchive = { [weak self] in self?.openArchive() }
    panel = win

    // 목록이 열리면 창을 아래로 늘이고(위 가장자리 고정), 닫히면 pill 높이로 되돌린다.
    model.$showList
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resizeForList() }
      .store(in: &bag)

    // 바깥을 클릭해 key를 잃으면 닫는다(Spotlight처럼). 여는 도중의 일시적 resign은 무시한다.
    NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification,
                                           object: win, queue: .main) { [weak self] _ in
      DispatchQueue.main.async { self?.handleResignKey() }
    }
    _ = store  // 컨트롤러는 store를 weak로 들고 archive를 읽는다
  }

  /// 포커스를 잃으면 닫는다 — 여는 도중(활성화 지연)의 일시적 resign은 무시한다.
  private func handleResignKey() {
    guard isVisible, Date().timeIntervalSince(openedAt) > 0.25 else { return }
    if NSApp.modalWindow != nil { return }
    dismiss(restoringFocus: false)
  }
}

// MARK: - 뷰

struct PillRootView: View {
  @ObservedObject var model: PillModel
  let onSubmit: (String) -> Void
  let onCancel: () -> Void
  let onToggleList: () -> Void
  let onResume: (Conversation) -> Void
  let onOpenArchive: () -> Void

  var body: some View {
    VStack(spacing: PillMetrics.gap) {
      capsule
      if model.showList { list }
    }
    .frame(width: PillMetrics.width, alignment: .top)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  // MARK: pill

  private var capsule: some View {
    HStack(spacing: 12) {
      PillOrb()

      ZStack(alignment: .leading) {
        if model.text.isEmpty {
          Text(L("무엇이든 물어보세요"))
            .font(.system(size: 15.5))
            .foregroundColor(Color.secondary.opacity(0.8))
            .allowsHitTesting(false)
        }
        PillTextField(text: $model.text,
                      focusToken: model.focusToken,
                      onSubmit: onSubmit,
                      onCancel: onCancel)
          .frame(height: 24)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      PillIconButton(system: "archivebox", active: model.showList,
                     help: L("보관함 — 최근 대화 이어가기")) {
        onToggleList()
      }
    }
    .padding(.leading, 13)
    .padding(.trailing, 12)
    .frame(width: PillMetrics.width, height: PillMetrics.height)
    .background {
      // Capsule 대신 같은 반지름의 RoundedRectangle — Capsule의 strokeBorder는 좌우 끝에
      // 1pt 세로 이음새를 남긴다(macOS 26, 오프스크린 렌더에서 확인).
      PillGlass().clipShape(RoundedRectangle(cornerRadius: PillMetrics.corner, style: .circular))
    }
    .overlay(
      RoundedRectangle(cornerRadius: PillMetrics.corner, style: .circular)
        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
    )
    .help(L("Enter 전송 · ⌘Return 대화 창 · Esc 닫기"))
  }

  // MARK: 보관함 목록

  private var list: some View {
    VStack(spacing: 0) {
      if model.recent.isEmpty {
        HStack {
          Text(L("아직 대화가 없습니다"))
            .font(.system(size: 12))
            .foregroundColor(.secondary)
          Spacer()
        }
        .padding(.horizontal, 12)
        .frame(height: PillMetrics.rowHeight)
      } else {
        ForEach(Array(model.recent.prefix(PillMetrics.maxRows)), id: \.id) { c in
          PillRecentRow(conversation: c) { onResume(c) }
        }
      }
      Rectangle()
        .fill(Color.primary.opacity(0.09))
        .frame(height: 1)
      Button(action: onOpenArchive) {
        HStack(spacing: 6) {
          Text(L("보관함 전체 열기"))
            .font(.system(size: 12, weight: .medium))
          Spacer()
          Text("⌘L")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(height: PillMetrics.footerHeight)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L("보관함 탭으로 이동 (⌘L)"))
    }
    .frame(width: PillMetrics.listWidth)
    .background {
      PillGlass().clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
  }
}

private enum PillPalette {
  /// DESIGN.md 액센트 바이올렛 #7A5CFF
  static let accent = Color(red: 0.478, green: 0.361, blue: 1.0)
  static let violet = Color(red: 0.69, green: 0.42, blue: 1.0)
  static let amber = Color(red: 1.0, green: 0.54, blue: 0.30)
}

/// pill의 유리 바탕 — 반투명 솔리드. 시스템 머티리얼은 창 가장자리에서 1pt 이음새가 보여 쓰지 않는다.
private struct PillGlass: View {
  var body: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor).opacity(0.90)
      LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.01)],
                     startPoint: .top, endPoint: .bottom)
    }
  }
}

private struct PillOrb: View {
  var body: some View {
    Circle()
      .fill(
        AngularGradient(
          colors: [PillPalette.accent, PillPalette.violet, PillPalette.amber, PillPalette.accent],
          center: .center,
          startAngle: .degrees(210),
          endAngle: .degrees(570))
      )
      .overlay(
        Circle().fill(
          RadialGradient(colors: [Color.white.opacity(0.55), .clear],
                         center: UnitPoint(x: 0.34, y: 0.28),
                         startRadius: 0, endRadius: 15)
        )
      )
      .overlay(Circle().strokeBorder(Color.white.opacity(0.24), lineWidth: 1))
      .frame(width: 30, height: 30)
      .accessibilityHidden(true)
  }
}

private struct PillIconButton: View {
  let system: String
  let active: Bool
  let help: String
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      Image(systemName: system)
        .font(.system(size: 14, weight: .medium))
        .foregroundColor(active ? .white : Color.primary.opacity(0.78))
        .frame(width: 32, height: 32)
        .background(
          Circle().fill(active ? PillPalette.accent
                               : Color.primary.opacity(hover ? 0.14 : 0.07))
        )
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
        .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .help(help)
  }
}

private struct PillRecentRow: View {
  let conversation: Conversation
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 9) {
        Circle()
          .fill(conversation.pinned ? PillPalette.accent : Color.secondary.opacity(0.4))
          .frame(width: 5, height: 5)
        Text(title)
          .font(.system(size: 12))
          .lineLimit(1)
          .truncationMode(.middle)
          .foregroundColor(.primary)
        Spacer(minLength: 6)
        Text(RelativeTime.text(for: conversation.updatedAt))
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
          .fixedSize()
      }
      .padding(.horizontal, 12)
      .frame(height: PillMetrics.rowHeight)
      .frame(maxWidth: .infinity)
      .background(Color.primary.opacity(hover ? 0.07 : 0))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { hover = $0 }
    .help(L("이 대화 이어가기"))
  }

  private var title: String {
    conversation.title.isEmpty ? L("새 대화") : conversation.title
  }
}

// MARK: - 입력창 (단일 행 NSTextField)

/// 한글 IME 조합 Enter를 먼저 확정하고, Esc·Enter를 창에 정확히 전달한다.
struct PillTextField: NSViewRepresentable {
  @Binding var text: String
  var focusToken: UUID
  var onSubmit: (String) -> Void
  var onCancel: () -> Void

  func makeCoordinator() -> Coordinator { Coordinator(self) }

  func makeNSView(context: Context) -> NSTextField {
    let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.font = .systemFont(ofSize: 15.5)
    field.textColor = .labelColor
    field.delegate = context.coordinator
    field.cell?.wraps = false
    field.cell?.isScrollable = true
    field.cell?.usesSingleLineMode = true
    field.cell?.truncatesLastVisibleLine = true
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.stringValue = text
    return field
  }

  func updateNSView(_ field: NSTextField, context: Context) {
    context.coordinator.parent = self
    let editing = field.currentEditor() as? NSTextView
    if field.stringValue != text, !(editing?.hasMarkedText() ?? false) {
      field.stringValue = text
    }
    if context.coordinator.lastFocusToken != focusToken {
      context.coordinator.lastFocusToken = focusToken
      DispatchQueue.main.async { [weak field] in
        guard let field, let window = field.window else { return }
        window.makeFirstResponder(field)
      }
    }
  }

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: PillTextField
    var lastFocusToken: UUID?

    init(_ parent: PillTextField) { self.parent = parent }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      if parent.text != field.stringValue { parent.text = field.stringValue }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        parent.onCancel()
        return true
      }
      guard commandSelector == #selector(NSResponder.insertNewline(_:)) else { return false }
      // 한글 조합 중 Enter — 조합을 먼저 확정해야 글자가 남지 않는다(대화 입력창과 같은 규칙)
      if textView.hasMarkedText() {
        let marked = (textView.string as NSString).substring(with: textView.markedRange())
        textView.insertText(marked, replacementRange: textView.markedRange())
      }
      if NSApp.currentEvent?.modifierFlags.contains(.command) == true { return false } // 창이 ⌘Return 처리
      let value = control.stringValue
      guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
      parent.onSubmit(value)
      return true
    }
  }
}
