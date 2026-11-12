import SwiftUI
import AppKit
import WebKit

// [FEATURE] 격리 브라우저 보이는 창 (v0.38.3, PLAN_v0.38.3 §4·§5·§8)
//
// v0.38.1 의 `BrowserService` 가 만든 **같은 WKWebView** 를 보이는 창에 옮겨 붙인다.
// 새 브라우저 엔진도, 두 번째 웹뷰도 만들지 않는다 — 모델이 읽는 페이지와 사용자가 보는
// 페이지가 같은 문서여야 하기 때문이다.
//
// 창을 닫으면 `orderOut` 만 하고 웹뷰는 오프스크린 창으로 되돌린다. 그래야 창이 숨겨진
// 동안에도 모델의 읽기·클릭·스냅샷이 안정적으로 동작한다.
//
// 보안: 주소창도 `BrowserURLPolicy` 를 그대로 탄다. 로컬·사설 주소는 열지 않는다.
// 승인 규칙(클릭·입력·제출)은 이 창과 무관하게 `AgentExecutor+Browser` 가 지킨다.

// MARK: - 크롬 상태

struct BrowserChromeState: Equatable {
  var address: String = ""
  var pageTitle: String = ""
  var host: String = ""
  var canGoBack = false
  var canGoForward = false
  var isLoading = false
  var isBlank = true
  var notice: String?
  var activityLabel: String?
  var isModelActive = false
  var progress: Double = 0
}

// MARK: - 창 모델

@MainActor
final class BrowserWindowModel: ObservableObject {
  weak var service: BrowserService?
  let webView: WKWebView

  @Published private(set) var state: BrowserChromeState
  @Published var addressText: String {
    didSet {
      // 사용자가 고치기 시작하면 이전 주소 오류를 지운다.
      if addressError != nil { addressError = nil }
    }
  }
  @Published private(set) var addressError: String?
  /// 창을 다시 열 때 SwiftUI 가 `WKWebView` 를 새 컨테이너에 붙이도록 만드는 토큰.
  @Published private(set) var hostGeneration = 0

  /// 창 제목을 갱신하는 콜백 — 컨트롤러가 채운다.
  var onTitleChange: ((String) -> Void)?

  private var isEditingAddress = false

  init(service: BrowserService) {
    self.service = service
    self.webView = service.webView
    let initial = service.chromeState
    self.state = initial
    self.addressText = initial.address
  }

  /// 서비스의 최신 상태를 가져온다.
  func refresh() {
    guard let service else { return }
    apply(service.chromeState)
  }

  /// 서비스가 밀어 준 상태를 반영한다. 주소를 편집 중이면 입력을 덮어쓰지 않는다.
  func apply(_ new: BrowserChromeState) {
    state = new
    if !isEditingAddress {
      addressText = new.address
    }
    onTitleChange?(Self.title(for: new))
  }

  func setAddressEditing(_ editing: Bool) {
    isEditingAddress = editing
  }

  func submitAddress() {
    guard let service else { return }
    if let error = service.navigateUser(to: addressText) {
      addressError = error
    } else {
      addressError = nil
      isEditingAddress = false
    }
  }

  func goBack() { service?.userGoBack() }
  func goForward() { service?.userGoForward() }
  func reloadOrStop() { service?.userReloadOrStop() }

  func dismissAddressError() { addressError = nil }

  func dismissNotice() {
    service?.clearNotice()
    state.notice = nil
  }

  func bumpHostGeneration() { hostGeneration += 1 }

  private static func title(for state: BrowserChromeState) -> String {
    if !state.pageTitle.isEmpty {
      return Lf("%@ — 격리 브라우저", state.pageTitle)
    }
    if !state.host.isEmpty {
      return Lf("%@ — 격리 브라우저", state.host)
    }
    return L("격리 브라우저")
  }
}

// MARK: - 창 뷰

struct BrowserWindowView: View {
  @ObservedObject var model: BrowserWindowModel
  @FocusState private var addressFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      if let error = model.addressError {
        noticeBar(error, icon: "exclamationmark.triangle.fill", tint: .orange) {
          model.dismissAddressError()
        }
      } else if let notice = model.state.notice {
        noticeBar(notice, icon: "info.circle.fill", tint: .secondary) {
          model.dismissNotice()
        }
      }
      if model.state.isLoading && !model.state.isBlank {
        ProgressView(value: min(max(model.state.progress, 0), 1))
          .progressViewStyle(.linear)
          .frame(height: 2)
      }
      Divider()
      ZStack {
        BrowserWebViewHost(webView: model.webView, generation: model.hostGeneration)
        if model.state.isBlank {
          emptyState
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 640, minHeight: 420)
    .background(Color(nsColor: .windowBackgroundColor))
    .onAppear { model.refresh() }
  }

  // MARK: 툴바

  private var toolbar: some View {
    HStack(spacing: 6) {
      Button(action: model.goBack) {
        Image(systemName: "chevron.left")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .disabled(!model.state.canGoBack)
      .keyboardShortcut("[", modifiers: .command)
      .help(L("뒤로"))

      Button(action: model.goForward) {
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .disabled(!model.state.canGoForward)
      .keyboardShortcut("]", modifiers: .command)
      .help(L("앞으로"))

      Button(action: model.reloadOrStop) {
        Image(systemName: model.state.isLoading ? "xmark" : "arrow.clockwise")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 24, height: 24)
      }
      .buttonStyle(.borderless)
      .disabled(model.state.isBlank && !model.state.isLoading)
      .keyboardShortcut("r", modifiers: .command)
      .help(model.state.isLoading ? L("불러오기 중지") : L("새로고침"))

      TextField(L("주소"), text: $model.addressText,
                onEditingChanged: { model.setAddressEditing($0) },
                onCommit: { model.submitAddress() })
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12))
        .focused($addressFocused)
        .frame(minWidth: 220, maxWidth: .infinity)
        .help(L("주소를 입력하고 Enter를 누르세요."))
        .accessibilityLabel(L("주소"))

      isolationBadge

      if model.state.isModelActive, let label = model.state.activityLabel {
        activityBadge(label)
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 7)
  }

  private var isolationBadge: some View {
    HStack(spacing: 4) {
      Image(systemName: "lock.shield.fill")
        .font(.system(size: 10, weight: .semibold))
      Text(L("격리 프로필"))
        .font(.system(size: 10.5, weight: .semibold))
    }
    .foregroundStyle(Color.accentColor)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.accentColor.opacity(0.10))
    .clipShape(Capsule())
    .fixedSize()
    .help(L("Safari와 쿠키·캐시를 공유하지 않는 전용 프로필입니다."))
    .accessibilityLabel(L("격리 프로필"))
  }

  private func activityBadge(_ label: String) -> some View {
    HStack(spacing: 5) {
      ProgressView()
        .controlSize(.mini)
      Text(label)
        .font(.system(size: 10.5, weight: .medium))
        .lineLimit(1)
    }
    .foregroundStyle(Color.accentColor)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(Color.accentColor.opacity(0.10))
    .clipShape(Capsule())
    .fixedSize()
    .help(L("모델이 이 페이지를 사용하고 있습니다."))
  }

  private func noticeBar(_ text: String, icon: String, tint: Color,
                         dismiss: @escaping () -> Void) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: icon)
        .font(.system(size: 11))
        .foregroundStyle(tint)
        .padding(.top, 1)
      Text(text)
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 4)
      Button(action: dismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 9, weight: .bold))
          .foregroundStyle(.secondary)
          .frame(width: 16, height: 16)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L("알림 닫기"))
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(tint.opacity(0.08))
  }

  private var emptyState: some View {
    VStack(spacing: 10) {
      Image(systemName: "globe")
        .font(.system(size: 36, weight: .light))
        .foregroundStyle(.tertiary)
      Text(L("아직 페이지가 없습니다"))
        .font(.system(size: 15, weight: .semibold))
      Text(L("모델이 페이지를 열면 여기에 표시됩니다. 주소를 직접 입력해도 됩니다."))
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      Text(L("이 창은 Safari와 쿠키·캐시를 공유하지 않는 격리 프로필입니다."))
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .multilineTextAlignment(.center)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color(nsColor: .windowBackgroundColor))
  }
}

// MARK: - WKWebView 호스트

private struct BrowserWebViewHost: NSViewRepresentable {
  let webView: WKWebView
  /// 값이 바뀌면 `updateNSView` 가 다시 붙인다(창을 닫았다 열 때).
  let generation: Int

  func makeNSView(context: Context) -> NSView {
    let container = NSView()
    container.wantsLayer = true
    attach(to: container)
    return container
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    _ = generation
    attach(to: nsView)
  }

  private func attach(to container: NSView) {
    guard webView.superview !== container else { return }
    webView.removeFromSuperview()
    webView.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(webView)
    NSLayoutConstraint.activate([
      webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
      webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
      webView.topAnchor.constraint(equalTo: container.topAnchor),
      webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
    ])
  }
}

// MARK: - 창 컨트롤러

@MainActor
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
  let model: BrowserWindowModel
  private weak var service: BrowserService?
  private static let frameName = "QuickTalkBrowserWindow"

  init(service: BrowserService) {
    self.service = service
    self.model = BrowserWindowModel(service: service)

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 900, height: 640),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    super.init(window: window)

    window.title = L("격리 브라우저")
    window.minSize = NSSize(width: 640, height: 420)
    window.isReleasedWhenClosed = false
    window.tabbingMode = .disallowed
    window.collectionBehavior = [.fullScreenPrimary]
    if !window.setFrameUsingName(Self.frameName) { window.center() }
    _ = window.setFrameAutosaveName(Self.frameName)
    window.delegate = self

    let host = NSHostingView(rootView: BrowserWindowView(model: model))
    host.autoresizingMask = [.width, .height]
    window.contentView = host

    model.onTitleChange = { [weak self] title in self?.window?.title = title }
    model.refresh()
  }

  required init?(coder: NSCoder) {
    fatalError("BrowserWindowController does not support NSCoder")
  }

  /// `activate=true` 는 사용자가 직접 열 때만 — 모델 자동 표시는 포커스를 빼앗지 않는다.
  func present(activate: Bool) {
    guard let window else { return }
    if activate {
      NSApp.activate(ignoringOtherApps: true)
      window.makeKeyAndOrderFront(nil)
    } else {
      window.orderFrontRegardless()
    }
  }

  func hide() {
    window?.orderOut(nil)
  }

  // 빨간 닫기 = 숨김. 페이지와 웹뷰는 살려 두고, 서비스가 오프스크린으로 되돌린다.
  func windowShouldClose(_ sender: NSWindow) -> Bool {
    service?.browserWindowWillHide()
    sender.orderOut(nil)
    return false
  }
}
