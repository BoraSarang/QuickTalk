import SwiftUI
import AppKit
import UniformTypeIdentifiers

// [INFO] [FEATURE] QuickShelf 패널 — 클립보드 · 파일 · 캡처 3탭 (PLAN_v0.13, 목업 v0.6)

/// QuickShelf가 놓이는 자리 — 화면 가장자리 플로팅 패널 / 대화창 안에 겹쳐 뜨는 엣지 패널
enum ShelfChrome {
  case floating
  case docked
}

/// QuickShelf 패널 치수 — 창 안 엣지 패널과 호버 미리보기 자리 계산이 같은 값을 쓴다
enum ShelfMetrics {
  /// 패널 폭
  static let width: CGFloat = 300
  /// 창 안에서 띄울 때 창 가장자리와의 여백(목업 v0.6: top/bottom/right 8)
  static let inset: CGFloat = 8
  /// 호버 미리보기가 패널 왼쪽에 뜰 때의 간격
  static let previewGap: CGFloat = 12
}

/// QuickShelf 강조 텍스트 색 — 마크다운과 같은 공통 토큰(`AccentPalette`)을 쓴다.
/// (고정 라벤더를 라이트에 쓰면 대비가 낮아 읽기 어렵다)
enum ShelfTheme {
  static func accentText(_ scheme: ColorScheme) -> Color {
    AccentPalette.text(scheme)
  }
}

struct ShelfView: View {
  @ObservedObject var store: UIStore
  var chrome: ShelfChrome = .floating
  var onClose: () -> Void
  var onSettings: () -> Void
  /// 보관함 전체 보기(검색·이름 변경·삭제·비서별 정리) — 창 안 보관함 탭으로 이동한다.
  var onOpenArchive: () -> Void = {}

  @Environment(\.colorScheme) private var colorScheme
  @State private var query = ""
  @State var clipboardFilter: ClipboardItem.Kind?

  /// 강조 문구 색 — 다크에서는 라벤더, 라이트에서는 진한 브랜드 퍼플(대비 확보)
  var accentText: Color { ShelfTheme.accentText(colorScheme) }

  var clipboardItems: [ClipboardItem] {
    store.clipboard.items.filter { item in
      if let f = clipboardFilter, item.kind != f { return false }
      guard !query.isEmpty else { return true }
      return store.clipboard.displayText(item).localizedCaseInsensitiveContains(query)
        || item.kind.rawValue.localizedCaseInsensitiveContains(query)
    }
  }

  var fileItems: [ShelfFile] {
    store.shelfFiles.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
  }

  var captureItems: [ShelfCapture] {
    store.shelfCaptures.filter {
      query.isEmpty || $0.source.label.localizedCaseInsensitiveContains(query)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      tabs
      searchRow
      if let notice = store.shelfNotice { noticeBanner(notice) }
      content
      footer
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        // 라이트/다크 모두에서 성립하는 유리 바탕 — 테마를 따라간다
        Color(nsColor: .windowBackgroundColor)
          .opacity(chrome == .floating ? 0.72 : 0.58)
      }
    )
    // 창 안 엣지 패널은 창 위에 뜨는 카드라 모서리·테두리를 준다(목업 v0.6 .panel)
    .clipShape(RoundedRectangle(cornerRadius: chrome == .floating ? 16 : 12))
    .overlay(RoundedRectangle(cornerRadius: chrome == .floating ? 16 : 12)
      .stroke(Color.primary.opacity(0.10), lineWidth: 1))
  }

  // MARK: - 헤더 · 탭

  private var header: some View {
    HStack(spacing: 7) {
      Text(L("퀵셸프"))
        .font(.system(size: 11.5, weight: .heavy))
        .foregroundColor(accentText)
      Circle().fill(Color.green).frame(width: 6, height: 6)
      Text("\(badgeCount)")
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
      Spacer()
      Button(action: onSettings) {
        Image(systemName: "gearshape").font(.system(size: 12))
      }
      .buttonStyle(IconButtonStyle())
      .help(L("퀵셸프 설정"))
      Button(action: onClose) {
        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
      }
      .buttonStyle(IconButtonStyle())
      .help(chrome == .floating ? L("닫기 (Esc)") : L("퀵셸프 접기"))
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .overlay(alignment: .bottom) { Divider().overlay(Color.primary.opacity(0.08)) }
  }

  private var badgeCount: Int {
    switch store.shelfTab {
    case .chats: return store.archive.count
    case .clipboard: return store.clipboard.items.count
    case .files: return store.shelfFiles.count
    case .capture: return store.shelfCaptures.count
    }
  }

  private var tabs: some View {
    HStack(spacing: 4) {
      ForEach(ShelfTab.allCases, id: \.self) { tab in
        let on = store.shelfTab == tab
        Button {
          store.shelfTab = tab
          query = ""
        } label: {
          HStack(spacing: 4) {
            Text(tab.title).font(.system(size: 10.5, weight: on ? .semibold : .regular))
            Text("\(count(for: tab))")
              .font(.system(size: 9, design: .monospaced))
              .padding(.horizontal, 4).padding(.vertical, 1)
              .background(Capsule().fill(Color.primary.opacity(on ? 0.18 : 0.08)))
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, 6)
          .foregroundColor(on ? accentText : .secondary)
          .background(RoundedRectangle(cornerRadius: 9)
            .fill(Color.primary.opacity(on ? 0.10 : 0.04)))
          .overlay(RoundedRectangle(cornerRadius: 9)
            .stroke(Color(red: 0.48, green: 0.36, blue: 1).opacity(on ? 0.55 : 0), lineWidth: 1))
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Lf("%@ 탭", tab.title))
      }
    }
    .padding(.horizontal, 10).padding(.top, 8)
  }

  private func count(for tab: ShelfTab) -> Int {
    switch tab {
    case .chats: return store.archive.count
    case .clipboard: return store.clipboard.items.count
    case .files: return store.shelfFiles.count
    case .capture: return store.shelfCaptures.count
    }
  }

  private var searchRow: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundColor(.secondary)
      TextField(searchPlaceholder, text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 11.5))
      if !query.isEmpty {
        Button { query = "" } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
          .buttonStyle(.plain).foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 9).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07), lineWidth: 1))
    .padding(.horizontal, 10).padding(.top, 8)
  }

  // MARK: - 본문

  /// 권한·실패 안내 — 어느 탭에서든 보이게 본문 위에 띄운다(단축키로 캡처했을 때도 확인 가능)
  private func noticeBanner(_ notice: String) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "exclamationmark.triangle.fill")
        .font(.system(size: 10)).foregroundColor(.orange)
      VStack(alignment: .leading, spacing: 3) {
        Text(notice).font(.system(size: 10)).foregroundColor(.orange.opacity(0.95))
          .fixedSize(horizontal: false, vertical: true)
        if store.shelfNoticeAction != nil {
          // 배너 **전체**가 눌러지는 영역이다 — 눈에 보이게 알려 준다
          Text(L("클릭하여 권한 요청")).font(.system(size: 9.5, weight: .semibold))
            .foregroundColor(.orange)
        }
      }
      Spacer(minLength: 0)
      Button { store.showShelfNotice(nil) } label: {
        Image(systemName: "xmark").font(.system(size: 8))
      }
      .buttonStyle(.plain).foregroundColor(.secondary)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.orange.opacity(0.12)))
    .contentShape(Rectangle())
    .onTapGesture { runNoticeAction() }
    .help(store.shelfNoticeAction == nil ? "" : L("화면 기록 권한을 요청합니다"))
    .padding(.horizontal, 10).padding(.top, 8)
  }

  /// 안내 배너를 눌렀을 때 — 권한 안내면 시스템에 요청하고, 이미 거부된 상태면 설정 화면을 연다.
  private func runNoticeAction() {
    guard let action = store.shelfNoticeAction else { return }
    switch action {
    case .screenRecording:
      if CaptureService.ensureScreenPermission() {
        store.showShelfNotice(L("화면 기록 권한이 허용되었습니다 — 앱을 다시 실행하면 캡처가 동작합니다."))
      } else {
        // 이미 거부된 상태에서는 시스템 대화상자가 다시 뜨지 않는다 → 설정 › 화면 기록을 직접 연다
        CaptureService.openScreenRecordingSettings()
        NSLog("[QuickShelf] 화면 기록 권한 안내 클릭 — 시스템 설정 열기")
      }
    }
  }

  @ViewBuilder private var content: some View {
    switch store.shelfTab {
    case .chats: chatsTab
    case .clipboard: clipboardTab
    case .files: filesTab
    case .capture: captureTab
    }
  }

  // MARK: - 대화 탭 (v0.31)
  //
  // 상단 아이콘에서 사라진 "보관함·새 대화"를 여기로 모았다. 행을 고르면
  // 그 대화로 이동하고 **셸프는 자동으로 닫힌다**(사용자 요청 2026-11-05).

  private var searchPlaceholder: String {
    store.shelfTab == .chats ? L("대화 검색") : L("검색")
  }

  /// 검색어에 맞는 **다른** 대화들 — 지금 열려 있는 대화는 위에 따로 보여 준다.
  private var chatItems: [Conversation] {
    let list = store.archive.filter { $0.id != store.conversation.id }
    guard !query.isEmpty else { return list }
    let q = query.lowercased()
    return list.filter {
      $0.displayTitle.lowercased().contains(q) ||
      $0.turns.contains { $0.text.lowercased().contains(q) }
    }
  }

  private func personaID(for c: Conversation) -> UUID? {
    c.personaID ?? c.turns.last(where: { $0.role == .assistant })?.personaID
  }

  @ViewBuilder private var chatsTab: some View {
    VStack(spacing: 6) {
      Button { startNewChat() } label: {
        HStack(spacing: 8) {
          Image(systemName: "plus.circle.fill")
            .font(.system(size: 14))
            .foregroundColor(.purple)
          VStack(alignment: .leading, spacing: 1) {
            Text(L("새 대화")).font(.system(size: 11.5, weight: .semibold))
            Text(L("지금 대화는 보관함에 저장됩니다"))
              .font(.system(size: 9.5)).foregroundColor(.secondary)
          }
          Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9).fill(Color.purple.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 9)
          .stroke(Color.purple.opacity(0.25), lineWidth: 1))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L("새 대화 시작 — 지금 대화는 보관함에 남습니다"))
      .padding(.horizontal, 10)

      ScrollView {
        LazyVStack(spacing: 4) {
          if !store.conversation.turns.isEmpty || store.conversation.pinned {
            chatRow(store.conversation, selected: true)
          }
          ForEach(chatItems, id: \.id) { c in
            chatRow(c, selected: false)
          }
          if store.conversation.turns.isEmpty && !store.conversation.pinned && chatItems.isEmpty {
            emptyState(L("보관된 대화가 없습니다"), L("새 대화를 시작하면 여기에 쌓입니다"))
              .frame(height: 180)
          }
        }
        .padding(.horizontal, 10).padding(.top, 2).padding(.bottom, 6)
      }
    }
    .padding(.top, 8)
    .onAppear { if !store.isRenderHarness { store.loadArchive() } }
  }

  private func chatRow(_ c: Conversation, selected: Bool) -> some View {
    let running = store.isReplying && store.conversation.id == c.id
    let persona = store.settings.persona(personaID(for: c))
    return Button { openChat(c) } label: {
      HStack(spacing: 8) {
        ZStack(alignment: .bottomTrailing) {
          Circle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 26, height: 26)
            .overlay {
              if let persona {
                Text(persona.displayEmoji).font(.system(size: 12))
              } else {
                Image(systemName: "person.crop.circle")
                  .font(.system(size: 12)).foregroundColor(.secondary)
              }
            }
          if running {
            Circle()
              .fill(Color.green)
              .frame(width: 8, height: 8)
              .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
              .offset(x: 1, y: 1)
          }
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(c.displayTitle)
            .font(.system(size: 11.5, weight: .medium))
            .lineLimit(1)
          HStack(spacing: 5) {
            if running {
              Text(L("응답 중"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.green)
            }
            Text(RelativeTime.text(for: c.updatedAt))
              .font(.system(size: 9))
              .foregroundColor(.secondary)
          }
        }
        Spacer(minLength: 0)
        if selected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 10))
            .foregroundColor(.purple)
        }
      }
      .padding(.horizontal, 8).padding(.vertical, 7)
      .background(RoundedRectangle(cornerRadius: 9)
        .fill(Color.primary.opacity(selected ? 0.07 : 0.03)))
      .overlay(RoundedRectangle(cornerRadius: 9)
        .stroke(Color.purple.opacity(selected ? 0.25 : 0), lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(c.displayTitle)
  }

  private func openChat(_ c: Conversation) {
    // 검색어가 있으면 그 단어가 나온 턴으로 이동한다(창 안 보관함과 같은 동작).
    if c.id != store.conversation.id { store.openConversation(c, searching: query) }
    onClose()
  }

  private func startNewChat() {
    store.newConversation()
    store.shelfTab = .chats
    onClose()
  }

  // MARK: - 푸터

  private var footer: some View {
    HStack(spacing: 6) {
      if store.shelfTab == .chats {
        // 목록은 빠른 전환용 — **검색·삭제·이름 변경·비서별 정리**는 창 안 보관함에서 한다.
        Button {
          onOpenArchive()
          onClose()
        } label: {
          HStack(spacing: 4) {
            Image(systemName: "archivebox").font(.system(size: 9))
            Text(L("보관함 전체 열기 — 검색·삭제·이름 변경"))
              .font(.system(size: 9.5, weight: .medium))
              .lineLimit(1)
          }
        }
        .buttonStyle(.plain)
        .foregroundColor(accentText)
        .help(L("보관함 — 검색 · 이름 변경 · 삭제 · 비서별 정리"))
        Spacer(minLength: 0)
      } else {
        Text(footerText).font(.system(size: 9.5)).foregroundColor(.secondary)
        Spacer()
        Button(L("모두 지우기")) { clearCurrent() }
          .buttonStyle(.plain)
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .overlay(alignment: .top) { Divider().overlay(Color.primary.opacity(0.08)) }
  }

  private var footerText: String {
    switch store.shelfTab {
    case .chats: return L("대화는 보낼 때마다 자동 저장됩니다 · 고르면 이 창이 닫힙니다")
    case .clipboard: return Lf("2분 뒤 사라짐 · 최대 %d개", ClipboardPolicy.maxItems)
    case .files: return L("클릭하면 대화에 첨부되고 목록에서 사라짐")
    case .capture: return L("첨부하면 목록에서 사라짐 · 복사·저장은 유지")
    }
  }

  private func clearCurrent() {
    switch store.shelfTab {
    case .chats: break
    case .clipboard: store.clipboard.clear()
    case .files: store.shelfFiles.removeAll()
    case .capture: store.clearCaptures()
    }
  }

  // MARK: - 공통

  func emptyState(_ title: String, _ note: String) -> some View {
    VStack(spacing: 5) {
      Image(systemName: "tray").font(.system(size: 20)).foregroundColor(.white.opacity(0.25))
      Text(title).font(.system(size: 11.5)).foregroundColor(.secondary)
      Text(note).font(.system(size: 10)).foregroundColor(.secondary.opacity(0.7))
        .multilineTextAlignment(.center)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(.horizontal, 18)
  }

  func setPreview(_ hovering: Bool, _ target: ShelfPreviewTarget) {
    if hovering { store.shelfPreview = target }
    else if store.shelfPreview == target { store.shelfPreview = nil }
  }

  func icon(for item: ClipboardItem, masked: Bool) -> String {
    switch item.kind {
    case .image: return "photo"
    case .link: return "link"
    case .file: return "doc"
    case .text: return masked ? "lock" : "text.alignleft"
    }
  }

  func kindLabel(_ kind: ClipboardItem.Kind) -> String {
    switch kind {
    case .image: return L("이미지")
    case .link: return L("링크")
    case .file: return L("파일")
    case .text: return L("텍스트")
    }
  }

  func timeLabel(_ seconds: Int) -> String {
    max(0, seconds) >= 60 ? String(format: "%d:%02d", seconds / 60, seconds % 60) : "0:\(max(0, seconds))"
  }

  func helpText(masked: Bool) -> String {
    if masked { return L("민감 항목 — 눌러서 내용 확인") }
    return L("클릭하면 입력창에 들어가거나 첨부됩니다 · 사용하면 목록에서 사라집니다")
  }

  func pick(imagesOnly: Bool) {
    ShelfController.shared.pickFiles(imagesOnly: imagesOnly)
  }

  func handleDrop(_ providers: [NSItemProvider]) {
    let group = DispatchGroup()
    var urls: [URL] = []
    let lock = NSLock()
    for provider in providers {
      group.enter()
      _ = provider.loadObject(ofClass: URL.self) { url, _ in
        if let url { lock.lock(); urls.append(url); lock.unlock() }
        group.leave()
      }
    }
    group.notify(queue: .main) {
      store.addShelfFiles(urls)
    }
  }
}

// MARK: - 작은 아이콘 버튼

struct IconButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .frame(width: 25, height: 25)
      .foregroundColor(.secondary)
      .background(RoundedRectangle(cornerRadius: 7)
        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : 0)))
      .contentShape(Rectangle())
  }
}

// MARK: - 호버 미리보기 창 내용

struct ShelfPreviewView: View {
  let target: ShelfPreviewTarget
  @Environment(\.colorScheme) private var colorScheme

  var accentText: Color { ShelfTheme.accentText(colorScheme) }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      header
      switch target {
      case .clipboard(let item, let masked):
        if item.kind == .image, let data = item.imageData, let img = NSImage(data: data) {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
          ScrollView {
            Text(masked ? ClipboardPolicy.displayText(item, revealed: false)
                        : ClipboardPolicy.previewText(item.text, limit: 900))
              .font(.system(size: 11.5))
              .lineSpacing(2)
              .frame(maxWidth: .infinity, alignment: .leading)
              .textSelection(.enabled)
          }
          .frame(maxHeight: 190)
        }
      case .file(let file):
        if let img = file.thumbnail {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(file.name).font(.system(size: 11.5))
          Text([file.kind == .image ? L("이미지") : L("파일"), file.sizeText, file.url.deletingLastPathComponent().path]
                .compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 9.5)).foregroundColor(.secondary).lineLimit(2)
        }
      case .capture(let capture):
        if let data = capture.thumbnail, let img = NSImage(data: data) {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: 210)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        Text([capture.source.label, capture.sizeText,
              capture.createdAt.formatted(date: .omitted, time: .shortened)]
              .joined(separator: " · "))
          .font(.system(size: 9.5)).foregroundColor(.secondary)
      }
      footerHint
    }
    .padding(12)
    .frame(width: 300)
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        Color(nsColor: .windowBackgroundColor).opacity(0.88)
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14)
      .stroke(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.55), lineWidth: 1))
  }

  private var header: some View {
    HStack(spacing: 5) {
      Image(systemName: headerSymbol).font(.system(size: 9))
      Text(headerTitle).font(.system(size: 10))
      Spacer()
      Text(headerMeta).font(.system(size: 9, design: .monospaced))
    }
    .foregroundColor(.secondary)
  }

  private var headerSymbol: String {
    switch target {
    case .clipboard(let i, let m):
      switch i.kind {
      case .image: return "photo"
      case .link: return "link"
      case .file: return "doc"
      case .text: return m ? "lock" : "text.alignleft"
      }
    case .file: return "doc"
    case .capture: return "camera.viewfinder"
    }
  }

  private var headerTitle: String {
    switch target {
    case .clipboard(let i, let m):
      if m { return L("민감 항목 (가림)") }
      switch i.kind {
      case .image: return L("이미지")
      case .link: return L("링크")
      case .file: return L("파일")
      case .text: return L("텍스트")
      }
    case .file: return L("파일")
    case .capture: return L("캡처")
    }
  }

  private var headerMeta: String {
    switch target {
    case .clipboard(let i, _):
      return i.kind == .text ? Lf("%d자", i.text.count) : ""
    case .file(let f):
      return f.sizeText ?? ""
    case .capture(let c):
      return c.sizeText
    }
  }

  private var footerHint: some View {
    Text(hint)
      .font(.system(size: 9.5))
      .foregroundColor(accentText)
  }

  private var hint: String {
    switch target {
    case .clipboard(let i, let m):
      if m { return L("클릭하면 내용이 공개됩니다 (다시 클릭 = 사용)") }
      return i.kind == .image || i.kind == .file
        ? L("클릭하면 첨부로 추가됩니다")
        : L("클릭하면 입력창에 들어갑니다")
    case .file: return L("클릭하면 대화에 첨부됩니다")
    case .capture: return L("클릭하면 대화에 첨부됩니다")
    }
  }
}
