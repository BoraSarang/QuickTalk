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
  /// 1줄일 때 pill 높이
  static let height: CGFloat = 56
  /// pill 왼쪽 끝 → 캐럿(입력 시작점)까지. 포인터가 캐럿 자리에 오도록 창을 이만큼 왼쪽으로 둔다.
  static let caretOffset: CGFloat = 55
  static let corner: CGFloat = 28
  static let gap: CGFloat = 8
  static let listWidth: CGFloat = 300
  static let rowHeight: CGFloat = 34
  static let footerHeight: CGFloat = 32
  static let maxRows = 4
  /// 텍스트 상자 위/아래 여백 — 아이콘·텍스트가 pill 안에 정렬되는 기준선
  static let textPad: CGFloat = 13
  /// 입력창 최소 높이(1줄)
  static let minTextHeight: CGFloat = 24
  /// pill 입력 폰트
  static let font = NSFont.systemFont(ofSize: 15.5)
  /// 입력창 최대 줄 수 — ChatInputField 와 같아야 한다(넘치는 값이 와도 pill 은 여기서 자르지 않는다)
  static let maxLines = 4

  static func listHeight(rows: Int) -> CGFloat {
    CGFloat(min(max(rows, 1), maxRows)) * rowHeight + 1 + footerHeight
  }

  /// pill 본체 높이 — 입력창이 여러 줄로 자라면 **위로** 커진다.
  /// 측정값이 어긋나(빈 입력인데 예전 높이가 남는 등) 상자가 끝없이 커지지 않도록 최대 줄 수로 자른다.
  static func capsuleHeight(inputHeight: CGFloat) -> CGFloat {
    let maxInput = ChatInputField.lineHeight(for: font) * CGFloat(maxLines)
      + ChatInputField.verticalPadding * 2
    let text = min(max(minTextHeight, inputHeight), maxInput)
    return max(height, text + textPad * 2)
  }

  /// 글자·측정값 기준 본체 높이 — **빈 입력은 언제나 1줄**이다.
  /// (입력창 측정은 한 프레임 늦게 오므로, 지운 직후에도 예전 여러 줄 높이가 남지 않게 여기서 막는다)
  static func capsuleHeight(text: String, inputHeight: CGFloat) -> CGFloat {
    text.isEmpty ? height : capsuleHeight(inputHeight: inputHeight)
  }
}

final class PillModel: ObservableObject {
  @Published var text = ""
  @Published var showList = false
  @Published var recent: [Conversation] = []
  /// 값이 바뀌면 입력창에 포커스를 준다(pill을 열 때·목록을 닫을 때).
  @Published var focusToken = UUID()
  /// 입력창이 측정한 높이 — 여러 줄이 되면 pill 이 위로 자란다.
  @Published var inputHeight: CGFloat = 0
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
  /// pill 본체(capsule)의 아래쪽 기준선 — 입력창이 위로 자라도 이 선은 그대로
  private var anchorBottom: CGFloat = 0
  /// pill 의 가로 위치(열 때 정해지고 이후 유지)
  private var anchorX: CGFloat = 0
  /// pill 이 마지막으로 놓인 **캐럿 지점** — 대화 창이 같은 자리에서 이어진다.
  /// (finish() 는 dismiss() 뒤에 콜백을 부르므로, 닫히기 전에 기록해 둬야 한다)
  private(set) var lastAnchor: NSPoint?

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
    // 초안이 남아 있으면( Esc 로만 닫은 경우) 높이도 그대로 둔다 —
    // 0으로 지우면 입력창이 같은 높이를 다시 보고하지 않아 글이 잘린 채로 열린다.
    if model.text.isEmpty { model.inputHeight = 0 }
    model.focusToken = UUID()

    // 기준선: 1줄 pill 의 아래쪽(포인터 중심 배치에서 파생)
    let base = frame(totalHeight: PillMetrics.height)
    anchorX = base.origin.x
    anchorBottom = base.origin.y
    // 입력을 시작한 자리 — 대화 창이 여기서 이어진다(설정보다 우선).
    lastAnchor = NSPoint(x: anchorX + PillMetrics.caretOffset,
                         y: anchorBottom + PillMetrics.height / 2)
    panel.setFrame(currentFrame(), display: false)
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

  /// QA 전용 — pill 을 미리 채운다(입력창 높이·위로 성장 확인용)
  func setDraftForQA(_ text: String) {
    model.text = text
    model.focusToken = UUID()
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
  /// (이 위치는 열 때 한 번 정하고, 이후엔 그대로 둔다 — 입력창이 자라도 pill 이 흔들리지 않는다)
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

  /// 현재 크기 — 입력창이 자라면 **위로**, 목록이 열리면 **아래로** 커진다.
  /// 기준선은 pill 본체(capsule)의 아래쪽 — 입력창이 위로 자라도 이 선은 움직이지 않는다.
  private func currentFrame() -> NSRect {
    let capsuleH = PillMetrics.capsuleHeight(text: model.text, inputHeight: model.inputHeight)
    let extra = capsuleH - PillMetrics.height
    let listPart = model.showList
      ? PillMetrics.gap + PillMetrics.listHeight(rows: model.recent.count)
      : 0
    let total = extra + capsuleH + listPart
    var f = NSRect(x: anchorX,
                   y: anchorBottom - extra - capsuleH,
                   width: PillMetrics.width,
                   height: total)
    // 화면을 벗어나면 안쪽으로 민다
    if let vf = screenForPointer()?.visibleFrame {
      if f.minY < vf.minY + 8 { f.origin.y = vf.minY + 8 }
      if f.maxY > vf.maxY - 8 { f.origin.y = vf.maxY - 8 - f.height }
    }
    return f
  }

  private func resize() {
    guard let panel, isVisible else { return }
    let f = currentFrame()
    // 이미 같은 자리·크기면 애니메이션하지 않는다(입력할 때마다 흔들리지 않게)
    guard abs(f.height - panel.frame.height) > 0.5
      || abs(f.origin.y - panel.frame.origin.y) > 0.5
      || abs(f.origin.x - panel.frame.origin.x) > 0.5 else { return }
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
      onCommandReturn: { [weak self] in self?.openChatWindow() },
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

    // 목록이 열리면 창을 아래로 늘리고(위 가장자리 고정), 닫히면 pill 높이로 되돌린다.
    model.$showList
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resize() }
      .store(in: &bag)
    // 입력창이 여러 줄이 되면 pill 이 **위로** 자란다(기준선은 그대로).
    model.$inputHeight
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resize() }
      .store(in: &bag)
    // 빈 입력 ↔ 입력 — 본체 높이 규칙이 달라지므로(빈 입력은 1줄) 창도 다시 맞춘다.
    model.$text
      .map(\.isEmpty)
      .removeDuplicates()
      .receive(on: RunLoop.main)
      .sink { [weak self] _ in self?.resize() }
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
  let onCommandReturn: () -> Void
  let onToggleList: () -> Void
  let onResume: (Conversation) -> Void
  let onOpenArchive: () -> Void

  var body: some View {
    // 창 높이는 컨트롤러가 `capsuleHeight` 로 계산한다 — 여기서 **간격을 더하지 않는다**.
    // (VStack spacing 을 두면 내용이 창보다 커져 아래가 잘리고, 남는 높이는 위쪽 여백으로 보인다)
    VStack(spacing: 0) {
      // 입력창이 자란 만큼 위를 비운다 → pill 이 위로 자란다(기준선은 그대로).
      Color.clear.frame(height: inputExtra)
      capsule
      if model.showList {
        list.padding(.top, PillMetrics.gap)
      }
    }
    .frame(width: PillMetrics.width, alignment: .bottom)
    // 어떤 이유로 창이 내용보다 커도 pill 은 **아래 기준선**에 붙인다(위가 비어 보이지 않게).
    .frame(maxHeight: .infinity, alignment: .bottom)
  }

  /// pill 본체가 1줄보다 커진 만큼 — 위쪽 여백으로 쓴다
  private var inputExtra: CGFloat {
    max(0, capsuleHeight - PillMetrics.height)
  }

  private var capsuleHeight: CGFloat {
    PillMetrics.capsuleHeight(text: model.text, inputHeight: model.inputHeight)
  }

  // MARK: pill

  private var capsule: some View {
    // 하단 정렬 — 아이콘과 텍스트가 pill 의 아래쪽 기준선에 붙는다(위로 자라도 안 움직인다)
    HStack(alignment: .bottom, spacing: 12) {
      PillOrb()
        .padding(.bottom, PillMetrics.textPad)

      ZStack(alignment: .topLeading) {
        if model.text.isEmpty {
          Text(L("무엇이든 물어보세요"))
            .font(.system(size: 15.5))
            .foregroundColor(Color.secondary.opacity(0.8))
            .allowsHitTesting(false)
            .padding(.top, 3)
        }
        // 대화 입력창과 **같은 컴포넌트** — Enter 전송 · Shift+Enter 줄바꿈 · 위로 성장
        ChatInputField(text: $model.text,
                       height: $model.inputHeight,
                       isBusy: false,
                       maxLines: PillMetrics.maxLines,
                       focusToken: model.focusToken,
                       font: PillMetrics.font,
                       onCommandReturn: onCommandReturn,
                       onCancel: onCancel,
                       onSubmit: onSubmit)
          .frame(height: max(PillMetrics.minTextHeight, model.inputHeight))
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.bottom, PillMetrics.textPad)

      PillIconButton(system: "archivebox", active: model.showList,
                     help: L("보관함 — 최근 대화 이어가기")) {
        onToggleList()
      }
      .padding(.bottom, 12)
    }
    .padding(.leading, 13)
    .padding(.trailing, 12)
    .frame(width: PillMetrics.width, height: capsuleHeight)
    .background {
      // Capsule 대신 같은 반지름의 RoundedRectangle — Capsule의 strokeBorder는 좌우 끝에
      // 1pt 세로 이음새를 남긴다(macOS 26, 오프스크린 렌더에서 확인).
      PillGlass().clipShape(RoundedRectangle(cornerRadius: PillMetrics.corner, style: .circular))
    }
    .overlay(
      RoundedRectangle(cornerRadius: PillMetrics.corner, style: .circular)
        .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
    )
    .help(L("Enter 전송 · Shift+Enter 줄바꿈 · ⌘Return 대화 창 · Esc 닫기"))
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
