import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// 새 대화 화면의 중앙 워터마크 — 앱 아이콘 + 안내(Siri 새 대화의 오브 자리).
/// 대화가 시작되면 사라진다(답변 글 뒤로 비치지 않게).
struct ChatBackground: View {
  @EnvironmentObject private var store: UIStore

  var body: some View {
    VStack(spacing: 16) {
      if let icon = NSApp.applicationIconImage {
        Image(nsImage: icon)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: 104)
          .shadow(color: .black.opacity(0.15), radius: 12, y: 5)
      }
      Text(Lf("새 대화 — 헤더의 퀵셸프 버튼(또는 %@)을 눌러 클립보드·파일·캡처를 붙이고 질문하세요. 지난 대화는 보관함 탭에서 열 수 있습니다.",
              ShortcutCombo.display(store.settings.shelfShortcut)))
        .font(.callout)
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: 330)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 28)
    .padding(.horizontal, 12)
  }
}

/// 응답 대기 점 3개 — 네이티브 인디케이터 대신 자체 애니메이션(custom 프로필)
struct TypingDots: View {
  @State private var phase = 0
  private let timer = Timer.publish(every: 0.35, on: .main, in: .common).autoconnect()
  var body: some View {
    HStack(spacing: 4) {
      ForEach(0..<3, id: \.self) { i in
        Circle()
          .fill(Color.secondary.opacity(phase == i ? 0.95 : 0.3))
          .frame(width: 6, height: 6)
      }
    }
    .onReceive(timer) { _ in phase = (phase + 1) % 3 }
  }
}

/// 제목 변경 시트 요청 — 대화방 헤더와 보관함 행이 함께 쓴다.
private struct RenameTarget: Identifiable {
  let id: UUID
  let title: String
}

/// 기록 삭제 확인 시트 요청 — 보관함 행에서만 쓴다.
private struct DeleteTarget: Identifiable {
  let conversation: Conversation
  var id: UUID { conversation.id }
}

// [INFO] [FEATURE] 헤더 접힘 대화창 (PLAN_v0.13: 첨부 진입점은 QuickShelf 하나 — 오른쪽 레일·＋ 제거)
struct ContentView: View {
  @EnvironmentObject var store: UIStore
  @State private var tab: Int
  /// 첨부 호버 미리보기 — **입력 전 칩과 전송 후 말풍선이 같은 카드**를 쓴다.
  @State private var hoverPreview: AttachmentPreview?
  /// 미리보기를 띄운 칩의 안정적인 키 — NSImage 비교로는 사라지지 않던 문제를 막는다.
  @State private var hoverPreviewKey: String?
  /// 입력창 높이(1~2줄) — AppKit이 측정해 돌려준 값을 그대로 쓴다
  @State private var inputHeight: CGFloat
  @State private var archiveQuery: String
  /// 방금 복사한 응답(체크 표시를 잠깐 보여준다)
  @State private var copiedTurn: UUID?
  /// 보관함 검색에서 연 턴 — 그 위치로 스크롤하고 테두리를 깜빡인다
  @State private var focusedTurn: UUID?
  @State private var focusPulse = false
  /// 제목 변경 시트(대화방 헤더·보관함 행 공용)
  @State private var renameTarget: RenameTarget?
  /// 기록 삭제 확인 시트(보관함 행)
  @State private var deleteTarget: DeleteTarget?
  /// 요약 보기 시트
  @State private var showMemory = false
  /// 창 연결 시트 (P0-1) — 창 하나의 텍스트·스크린샷을 참고 자료로
  @State private var showWindowPicker = false
  /// 헤더 제목에 마우스를 올리면 밑줄(편집 가능 표시)
  @State private var titleHover = false
  /// 상대 시간("5분 전")을 1분마다 다시 계산하기 위한 현재 시각 — 창을 오래 열어 두어도 표기가 낡지 않는다.
  @State private var nowTick = Date()
  /// 대화창이 맨 아래에 있는가 — 아니면 우하단에 "맨 아래로" 버튼을 띄운다.
  /// (NSScrollView 값을 직접 읽는다 — SwiftUI 선호도는 스크롤 중에 갱신되지 않는다)
  @State private var atBottom = true
  /// 자동으로 바닥을 따라갈지 — 사용자가 위로 올려 읽는 중에는 **끌어내리지 않는다**.
  /// (스트리밍·도구 출력이 매번 스크롤을 납치하면 위로 올려도 볼 수가 없다 — 2026-11-05 사용자 지적)
  @State private var followsBottom = true
  /// "지금 맨 아래로 붙여라" 신호 — `NSScrollView`를 직접 움직인다.
  /// SwiftUI `scrollTo(anchor:.bottom)`은 내용 높이가 늦게 확정되면 끝까지 가지 못했다.
  @State private var bottomPinToken = 0
  /// 거리 기반 재고정을 너무 자주 하지 않게(스크롤 알림은 초당 수십 번 온다)
  @State private var lastPinAt = Date.distantPast
  var initialTab: Int = 0
  var suppressArchiveLoad = false

  init(initialTab: Int = 0, initialInputHeight: CGFloat = 28,
       initialArchiveQuery: String = "", suppressArchiveLoad: Bool = false) {
    self.initialTab = initialTab
    self.suppressArchiveLoad = suppressArchiveLoad
    _tab = State(initialValue: initialTab)
    _inputHeight = State(initialValue: initialInputHeight)
    _archiveQuery = State(initialValue: initialArchiveQuery)
  }
  private var filteredArchive: [Conversation] {
    // 진행 중 대화는 위 "진행 중" 칸에 따로 보여주므로 목록에서는 뺀다
    let list = store.archive.filter { $0.id != store.conversation.id }
    guard !archiveQuery.isEmpty else { return list }
    let q = archiveQuery.lowercased()
    return list.filter {
      $0.displayTitle.lowercased().contains(q) ||
      $0.turns.contains { $0.text.lowercased().contains(q) }
    }
  }
  /// 이 답변을 만든 비서 — 턴에 기록된 비서가 우선, 구버전 기록은 대화의 현재 비서.
  private func persona(for turn: Turn) -> Persona? {
    store.settings.persona(turn.personaID ?? store.conversation.personaID)
  }
  /// 보관함을 비서별로 묶은 그룹 — 기본(비서 없음)이 먼저, 그 다음 설정 순서.
  private struct PersonaGroup: Identifiable {
    let id: String
    let title: String
    let conversations: [Conversation]
  }

  /// 이 대화의 비서 — 대화에 기록된 값이 우선, 구버전은 마지막 답변의 비서.
  private func personaID(for c: Conversation) -> UUID? {
    c.personaID ?? c.turns.last(where: { $0.role == .assistant })?.personaID
  }

  private var personaGroups: [PersonaGroup] {
    var buckets: [String: [Conversation]] = [:]
    for c in filteredArchive {
      let key = personaID(for: c)?.uuidString ?? "none"
      buckets[key, default: []].append(c)
    }
    var groups: [PersonaGroup] = []
    if let basic = buckets.removeValue(forKey: "none"), !basic.isEmpty {
      // 비서를 쓰지 않는 사용자에게는 예전처럼 "대화 기록" 한 칸으로 보인다.
      let title = store.settings.personas.isEmpty ? L("대화 기록") : L("기본(비서 없음)")
      groups.append(PersonaGroup(id: "none", title: title, conversations: basic))
    }
    for p in store.settings.personas {
      if let list = buckets.removeValue(forKey: p.id.uuidString), !list.isEmpty {
        groups.append(PersonaGroup(id: p.id.uuidString,
                                   title: "\(p.displayEmoji) \(p.name)",
                                   conversations: list))
      }
    }
    // 비서가 삭제된 대화도 사라지지 않게 마지막 그룹으로 남긴다.
    for (key, list) in buckets.sorted(by: { $0.key < $1.key }) {
      groups.append(PersonaGroup(id: key, title: L("삭제된 비서"), conversations: list))
    }
    return groups
  }

  private func personaTag(_ p: Persona) -> some View {
    Text("\(p.displayEmoji) \(p.name)")
      .font(.caption2)
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(Capsule().fill(Color.purple.opacity(0.16)))
      .foregroundColor(.primary)
      .lineLimit(1)
  }

  /// 보관함 한 행 — 제목·비서·턴 수·보관 상태. 행 전체가 열기 버튼이다.
  private func archiveRow(_ c: Conversation) -> some View {
    ZStack(alignment: .trailing) {
      Button { store.openConversation(c, searching: archiveQuery); tab = 0 } label: {
        VStack(alignment: .leading) {
          HStack(spacing: 4) {
            if c.pinned {
              Image(systemName: "bookmark.fill").font(.system(size: 9)).foregroundColor(.purple)
            }
            Text(c.displayTitle).bold().lineLimit(1)
          }
          // 마지막으로 이야기한 때 — "5분 전 / 3일 전 / 10월 14일"
          HStack(spacing: 6) {
            if let p = store.settings.persona(personaID(for: c)) {
              personaTag(p)
            }
            Text(Lf("%d턴 · %@ · %@", c.turns.count,
                    RelativeTime.text(for: c.updatedAt, now: nowTick),
                    c.pinned ? L("보관") : Lf("%d일 보관", store.settings.keepDays)))
              .font(.caption).foregroundColor(.gray)
              .help(Lf("마지막 대화: %@", RelativeTime.absolute(c.updatedAt)))
          }
        }
        .padding(.trailing, 72)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)

      HStack(spacing: 6) {
        Button {
          renameTarget = RenameTarget(id: c.id, title: c.displayTitle)
        } label: {
          Text(L("변경")).font(.caption2).foregroundColor(.secondary)
        }.help(L("제목 변경")).buttonStyle(.borderless)
        Button { deleteTarget = DeleteTarget(conversation: c) } label: {
          Image(systemName: "trash").foregroundColor(.red)
        }.help(L("기록에서 삭제")).buttonStyle(.borderless)
      }
    }
  }
  /// 표시 언어에 맞는 날짜 형식(언어를 바꾸면 다음 렌더부터 반영된다)
  private static var historyDate: DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: L10n.effective == .ko ? "ko_KR" : (Locale.preferredLanguages.first ?? "en_US"))
    f.dateFormat = L("M월 d일 HH:mm")
    return f
  }
  private var shortcutLabel: String { ShortcutCombo.display(store.settings.globalShortcut) }

  /// QuickShelf 도킹 토글 — 창 안쪽에 뜨는 엣지 패널(창 폭은 바뀌지 않는다, 목업 v0.6)
  private func toggleShelfDock() {
    withAnimation(.easeInOut(duration: 0.18)) { store.shelfDocked.toggle() }
  }

  private func closeShelfDock() {
    withAnimation(.easeInOut(duration: 0.18)) { store.shelfDocked = false }
  }

  /// 전면 설정 창 열기 (Hub 설정 탭의 "모든 설정 열기"와 같은 동작)
  private func openSettingsWindow() {
    NotificationCenter.default.post(name: .quickTalkOpenSettings, object: nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  var body: some View {
    ZStack(alignment: .topTrailing) {
      VStack(spacing: 0) {
        headerRow
        if tab == 0 {
          chatTab
        } else if tab == 1 {
          archiveTab
        } else {
          settingsTab
        }
      }
      // QuickShelf — **창 안쪽**에 뜨는 엣지 패널(목업 v0.6 §3). 창 폭은 그대로 두고 오른쪽 위에 겹쳐 띄운다.
      if store.shelfDocked {
        // 뒤 대화를 살짝 눌러 주고, 바깥을 누르면 닫는다(scrim)
        Color.black.opacity(0.28)
          .contentShape(Rectangle())
          .onTapGesture { closeShelfDock() }
          .help(L("바깥을 누르면 퀵셸프가 닫힙니다"))
          .transition(.opacity)
        shelfDockOverlay
          .padding(.top, 8).padding(.bottom, 8).padding(.trailing, 8)
          .transition(.move(edge: .trailing).combined(with: .opacity))
      }
      // 호버 미리보기가 떠 있을 때 Esc로 확실히 닫는다(입력창이 포커스여도 동작).
      if hoverPreview != nil {
        Button("") { dismissHoverPreview() }
          .keyboardShortcut(.escape, modifiers: [])
          .buttonStyle(.plain)
          .frame(width: 0, height: 0)
          .opacity(0)
          .accessibilityHidden(true)
      }
    }
    // 가변 크기(PLAN_v0.12): 최소 420×420. 크기는 NSWindow가 기억한다.
    .frame(minWidth: 420, idealWidth: 460, maxWidth: .infinity,
           minHeight: 420, idealHeight: 560, maxHeight: .infinity, alignment: .top)
    .sheet(item: $renameTarget) { target in
      RenameSheet(original: target.title) { newTitle in
        store.renameConversation(id: target.id, to: newTitle)
      }
    }
    .sheet(item: $deleteTarget) { target in
      DeleteConfirmSheet(
        heading: L("대화 기록을 삭제할까요?"),
        target: target.conversation.displayTitle,
        message: target.conversation.turns.isEmpty
          ? L("이 대화가 기록에서 삭제됩니다. 되돌릴 수 없습니다.")
          : Lf("이 대화의 %d개 턴이 기록에서 삭제됩니다. 되돌릴 수 없습니다.",
               target.conversation.turns.count),
        confirmLabel: L("삭제")
      ) {
        store.deleteConversation(target.conversation)
      }
    }
    .sheet(isPresented: $showMemory) {
      MemorySheet(summary: store.conversation.activeSummary ?? "",
                  onSave: { text in
                    store.updateConversationSummary(text)
                    showMemory = false
                  },
                  onClear: {
                    store.clearConversationMemory()
                    showMemory = false
                  })
    }
    .sheet(isPresented: $showWindowPicker) {
      WindowPickerSheet(store: store)
    }
    .sheet(isPresented: $store.showTaskList) {
      TaskListSheet().environmentObject(store)
    }
    .onAppear { tab = initialTab }
    // 상대 시간("5분 전")은 시간이 흐르면 낡는다 — 1분마다 다시 계산해 표기를 최신으로 유지한다.
    .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { nowTick = $0 }
    .onReceive(NotificationCenter.default.publisher(for: .openQuickTalk)) { n in
      if let t = n.object as? Int { tab = t }
    }
    // 미리보기가 마우스 추적 실패로 남아도 확실히 닫을 수 있게 한다.
    .onExitCommand(perform: dismissHoverPreview)
    .onChange(of: tab) { _, _ in dismissHoverPreview() }
    .onChange(of: store.conversation.id) { _, _ in dismissHoverPreview() }
    .onChange(of: store.attached.count) { _, _ in dismissHoverPreview() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in
      dismissHoverPreview()
    }
    .onDisappear(perform: dismissHoverPreview)
  }

  private func dismissHoverPreview() {
    hoverPreview = nil
    hoverPreviewKey = nil
  }

  /// 창 안에 겹쳐 뜨는 QuickShelf(오른쪽 300pt) — 화면 가장자리 패널과 **같은 뷰**(단일 출처)
  private var shelfDockOverlay: some View {
    ShelfView(store: store,
              chrome: .docked,
              onClose: { closeShelfDock() },
              onSettings: { openSettingsWindow() })
      .frame(width: 300)
      .frame(maxHeight: .infinity)
      .shadow(color: .black.opacity(0.45), radius: 22, x: -10, y: 0)
  }

  /// 헤더에 보여 줄 현재 토큰/자동 정리 기준 — 설정을 열지 않아도 진행도를 확인한다.
  private var memoryStatus: (current: Int, trigger: Int, ratio: Double)? {
    guard let provider = store.settings.activeProvider else { return nil }
    let current = ConversationMemory.contextTokens(store.conversation)
    let trigger = Int(Double(ConversationMemory.promptBudget(for: provider))
                      * ConversationMemory.triggerRatio)
    guard trigger > 0 else { return nil }
    return (current, trigger, Double(current) / Double(trigger))
  }

  /// 토큰 칩을 띄울지 — 대화가 있고 활성 모델이 있을 때만.
  private var showsMemoryChip: Bool {
    !store.conversation.turns.isEmpty && memoryStatus != nil
  }

  /// 기억 사용량 칩 — **헤더가 아니라 대화 영역 위에 띄운다**(2026-10-22).
  /// 헤더에 두 번째 줄로 넣으면 탭마다 헤더 높이가 달라져 보관함·설정으로 옮길 때 화면이 울렁인다.
  @ViewBuilder private var memoryChip: some View {
    if let status = memoryStatus, !store.conversation.turns.isEmpty {
      let percent = Int((status.ratio * 100).rounded())
      HStack(spacing: 3) {
        Image(systemName: "brain.head.profile").font(.system(size: 9))
        // 좁은 창(기본 460pt)에서 줄바꿈되지 않게 축약 표기 — 정확한 값은 툴팁에 있다.
        Text("\(Self.compactTokens(status.current)) / \(Self.compactTokens(status.trigger)) · \(percent)%")
          .font(.system(size: 10, weight: .medium, design: .monospaced))
          .lineLimit(1)
      }
      .foregroundColor(status.current >= status.trigger ? .orange : .secondary)
      .padding(.horizontal, 7).padding(.vertical, 3)
      .background(Capsule().fill(.ultraThinMaterial))
      .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1))
      .help(Lf("현재 약 %d토큰 · 자동 정리 기준 %d토큰", status.current, status.trigger)
            + " " + L("기준을 넘으면 다음 답변을 마친 뒤 백그라운드에서 정리합니다."))
      .padding(.top, 6).padding(.trailing, 10)
    }
  }

  // MARK: - 헤더

  private var headerRow: some View {
    HStack(spacing: 4) {
      Circle().fill(Color.purple).frame(width: 10, height: 10)
      if tab == 0 {
        // 제목 = 첫 질문에서 자동 생성 · 클릭하면 바로 바꿀 수 있다.
        // ★ 기억 사용량(토큰)은 여기 두지 않는다 — 두 줄이 되면 탭(보관함·설정)마다 헤더 높이가
        //   달라져 탭을 옮길 때 화면이 울렁인다(2026-10-22 사용자 지적). 대화 영역 위에 띄운다.
        Button {
          renameTarget = RenameTarget(id: store.conversation.id,
                                      title: store.conversation.displayTitle)
        } label: {
          Text(store.conversation.displayTitle)
            .bold()
            .lineLimit(1)
            .truncationMode(.middle)
            .layoutPriority(1)
            // 호버하면 밑줄 — 클릭해서 이름을 바꿀 수 있다는 표시
            .underline(titleHover, color: .secondary)
        }
        .buttonStyle(.plain)
        .onHover { titleHover = $0 }
        .help(L("제목 변경 — 클릭하여 이 대화의 이름을 바꿉니다"))
      } else {
        Text(tab == 1 ? L("보관함") : L("설정"))
          .bold()
          .lineLimit(1)
          .truncationMode(.middle)
      }
      if tab == 0 && store.conversation.pinned {
        Image(systemName: "bookmark.fill").font(.system(size: 10)).foregroundColor(.purple)
          .help(L("만료 없이 보관 중인 대화입니다"))
      }
      // 비서 칩 — 비서를 1명 이상 만들었을 때만(없으면 지금과 완전히 동일한 화면).
      if tab == 0 && !store.settings.personas.isEmpty {
        PersonaChip()
      }
      Spacer()
      // 읽어주기 중이면 **어느 탭에서든** 멈출 수 있게 헤더에 중지 버튼
      if store.isSpeaking {
        headerIcon("stop.fill", tint: .red, help: L("읽어주기 중지")) { store.stopSpeaking() }
      }
      // ★ 폭이 모자라면 **숨긴다** — Text 는 압축되면 한 글자씩 세로로 쌓여
      //   헤더가 6줄로 커진다(2026-10-25 실측: 기본 460pt + 긴 제목에서 ⌘Space 세로 붕괴).
      //   넓은 창이나 짧은 제목에서는 지금처럼 한 줄로 보인다.
      ViewThatFits(in: .horizontal) {
        Text(shortcutLabel)
          .font(.caption)
          .foregroundColor(.gray)
          .lineLimit(1)
          .fixedSize()
        EmptyView()
      }
      // 📌 = 창을 항상 위에(모든 탭 공통 — 탭이 아니라 창 속성이다).
      // 기본은 꺼짐: 설정 창·시스템 권한 안내가 대화 창 뒤로 숨지 않게 한다.
      headerIcon(store.settings.alwaysOnTop ? "pin.fill" : "pin",
                 active: store.settings.alwaysOnTop,
                 help: store.settings.alwaysOnTop
                   ? L("항상 위 켜짐 — 다른 앱 위에 고정됩니다. 끄면 일반 창처럼 뒤로 갑니다")
                   : L("항상 위 — 이 창을 다른 앱 위에 고정합니다")) {
        store.settings.alwaysOnTop.toggle()
      }

      // 핀·새 대화는 하단 여백을 만들지 않도록 헤더 오른쪽으로 옮겼다(PLAN_v0.12 개정)
      if tab == 0 {
        // 🧠 = 공통 메모리 — **항상 보인다**(꺼져 있어도).
        // 예전엔 전역에서 꺼져 있으면 아예 숨겼다 → 끈 뒤 켤 방법이 헤더에 없어서
        // "껐는데 왜 안 보이지?"가 됐다(2026-10-22 사용자 지적). 꺼져 있으면 흐리게 두고
        // 누르면 다시 켜게 한다.
        let memoryOff = !store.commonMemoryActive
        // ★ "brain.slash" 는 **존재하지 않는 SF Symbol** 이다(macOS 27.2 실측) —
        //   Image(systemName:) 이 빈 뷰가 되어 아이콘이 아예 사라진다("회색으로도 안 보임").
        //   이름은 "brain" 하나로 두고 **색**으로 상태를 구분한다(켜짐 보라 / 꺼짐 회색).
        headerIcon("brain",
                   tint: memoryOff ? .secondary : .purple,
                   help: memoryOff
                     ? (store.settings.globalMemoryEnabled
                        ? L("이 대화에서는 공통 메모리를 쓰지 않습니다 — 눌러서 켜기")
                        : L("공통 메모리가 꺼져 있습니다 — 눌러서 켜기"))
                     : L("공통 메모리 사용 중 — 눌러서 이 대화에서만 끄기")) {
          store.toggleCommonMemory()
        }

        // 🔖 = 이 대화를 만료 없이 보관(모든 대화는 자동 저장되고 보관일수 뒤 정리된다)
        headerIcon(store.conversation.pinned ? "bookmark.fill" : "bookmark",
                   active: store.conversation.pinned,
                   help: store.conversation.pinned
                     ? L("보관 해제 — 보관일수가 지나면 정리됩니다")
                     : L("보관 — 이 대화를 만료 없이 보관함에 남깁니다")) { store.togglePin() }

        headerIcon("square.and.pencil",
                   help: L("새 대화 — 지금 대화는 보관함에 남고 새로 시작합니다")) { store.newConversation() }
        Divider().frame(height: 14)
      }
      headerIcon("sidebar.right", active: store.shelfDocked,
                 help: store.shelfDocked
                   ? L("퀵셸프 접기 — 창 안 허브를 내립니다 (Esc)")
                   : Lf("퀵셸프 — 클립보드·파일·캡처 허브를 창 안쪽에 띄웁니다 (%@)",
                        ShortcutCombo.display(store.settings.shelfShortcut))) { toggleShelfDock() }
      Divider().frame(height: 14)
      headerIcon(tab == 0 ? "bubble.left.fill" : "bubble.left", active: tab == 0,
                 help: L("대화")) { tab = 0 }
      headerIcon(tab == 1 ? "archivebox.fill" : "archivebox", active: tab == 1,
                 help: L("보관함")) { tab = 1 }
      headerIcon(tab == 2 ? "gearshape.fill" : "gearshape", active: tab == 2,
                 help: L("설정")) { tab = 2 }
    }.padding(.horizontal, 12).padding(.vertical, 8)
  }

  /// 헤더 아이콘 공통 모양 — 크기·여백·호버 툴팁을 한 곳에서 맞춘다.
  /// (핀·뇌·북마크·새 대화·퀵셸프·탭이 제각각 크기라 정리되지 않아 보이던 문제)
  /// 활성 상태는 보라색, 비활성은 기본색 — 탭 아이콘도 같은 규칙을 쓴다.
  private func headerIcon(_ name: String, active: Bool = false, tint: Color? = nil,
                          help: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: name)
        .font(.system(size: 12, weight: .medium))
        .foregroundColor(tint ?? (active ? .purple : .primary))
        .frame(width: 22, height: 22)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .help(help)
  }

  // MARK: - 대화 탭 (본문 + 하단 입력독 고정, 첨부는 QuickShelf에서)

  private var chatTab: some View {
    VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            if store.conversation.turns.isEmpty && !store.isReplying {
              ChatBackground().id(store.settings.language)   // L10n은 전역 — 언어 변경 시 다시 그린다
            }
            ForEach(store.conversation.turns, id: \.id) { t in
              HStack(alignment: .bottom) {
                if t.role == .user {
                  Spacer(minLength: 30)
                }
                // 보낸 메시지에 붙인 첨부를 그대로 보여준다(썸네일 + 호버 미리보기)
                VStack(alignment: t.role == .user ? .trailing : .leading, spacing: 4) {
                  // 이 답변을 만든 비서 — 대화 중 비서를 바꿔도 턴마다 귀속이 보인다.
                  if t.role == .assistant, let p = persona(for: t) {
                    HStack(spacing: 4) {
                      Text(p.displayEmoji)
                      Text(p.name)
                    }
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.leading, 3)
                  }
                  if !t.attachments.isEmpty { sentAttachmentStrip(t.attachments) }
                  // ★ 도구 실행 카드는 **답변보다 위**에 둔다 — 명령이 먼저 돌고 그 결과로 답하기 때문.
                  //   답변 아래에 두면 "명령 → 응답" 순서와 화면 순서가 반대가 된다(2026-10-22 사용자 지적).
                  //   (웹 검색 출처는 참고 자료라 아래에 두는 것이 자연스럽다 — 그대로 둔다)
                  // 모델의 일정 제안 — 등록/취소를 이 자리에서 결정한다.
                  if t.role == .assistant,
                     let pending = store.pendingSchedule,
                     pending.turnID == t.id,
                     pending.conversationID == store.conversation.id {
                    ScheduleProposalCard(pending: pending)
                      .padding(.bottom, 2)
                  }
                  if t.role == .assistant,
                     let events = t.agentEvents, !events.isEmpty {
                    AgentCard(events: events,
                              approval: approvalRequest(for: t),
                              showExecution: store.settings.agentShowExecution,
                              undoEntry: store.agentUndoEntry(for: events),
                              undoMessage: store.agentUndoMessage(for: events),
                              onAllowOnce: { store.resolveAgentApproval(.allowOnce) },
                              onAllowScope: { store.resolveAgentApproval(.allowScope) },
                              onAllowApp: { store.resolveAgentApproval(.allowApp) },
                              onAlwaysAllow: { store.resolveAgentApproval(.alwaysAllow) },
                              onDeny: { store.resolveAgentApproval(.deny) },
                              onUndo: {
                                if let id = store.agentUndoEventID(for: events) {
                                  Task { await store.undoAgentWrite(eventID: id) }
                                }
                              },
                              onCancel: { store.cancelAgentRun() },
                              handoffNotice: t.id == store.agentTurnID ? store.agentHandoffNotice : nil,
                              onTerminalHandoff: { store.handoffToTerminal($0) })
                      .padding(.bottom, 2)
                  }
                  if !t.text.isEmpty {
                    if t.role == .assistant {
                      // AI 답변은 마크다운으로 그린다 — 제목·목록·코드·표·링크
                      MarkdownText(text: t.text, sources: t.sources ?? [])
                        .padding(9)
                        .background(Color.primary.opacity(0.055))
                        .cornerRadius(12)
                    } else {
                      Text(t.text).padding(8)
                        .background(RoundedRectangle(cornerRadius: 12)
                          .fill(Color.accentColor.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 12)
                          .stroke(Color.accentColor.opacity(0.22), lineWidth: 1))
                        .cornerRadius(12).textSelection(.enabled)
                    }
                  }
                  // 응답까지 걸린 시간(모델 호출 구간) — 새 기록에만 표시된다
                  // 응답 시각 + 걸린 시간 — "5분 전 · 3.2초".
                  // 왼쪽 상대 시간은 이 대화가 언제 오갔는지, 오른쪽은 모델 호출에 걸린 시간이다.
                  if t.role == .assistant, let ms = t.elapsedMs {
                    let when = t.createdAt.map { RelativeTime.text(for: $0, now: nowTick) }
                    HStack(spacing: 0) {
                      Text(([when, Self.elapsedLabel(ms)].compactMap { $0 })
                        .joined(separator: " · "))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    }
                    .padding(.leading, 3)
                    .help(t.createdAt.map {
                      Lf("응답 도착: %@ · 걸린 시간 %@", RelativeTime.absolute($0), Self.elapsedLabel(ms))
                    } ?? L("응답까지 걸린 시간"))
                  }
                  // 웹 검색 출처 — 답변 아래 카드(클릭하면 기본 브라우저)
                  if t.role == .assistant, let sources = t.sources, !sources.isEmpty {
                    sourceCards(sources)
                  }
                  // 모델이 "검색할 수 없다"고 답했을 때 — 같은 질문을 검색 강제로 재시도
                  if t.role == .assistant, store.shouldOfferWebRetry(t) {
                    webRetryButton(t)
                  }
                }
                // 내용 열은 **남는 폭을 정확히 차지**한다 — 긴 표·명령이 이상 폭(ideal width)을
                // 주장하면 HStack 이 그 폭으로 높이를 재고, 실제로는 좁게 그려져 아래 턴과 겹쳤다.
                .frame(maxWidth: t.role == .assistant ? .infinity : nil,
                       alignment: .leading)
                // 질문 메뉴는 말풍선 **오른쪽**에 두고 위·아래 중앙에 맞춘다.
                // 26pt를 비워 두어 말풍선과 겹치지 않게 한다.
                .padding(.trailing, t.role == .user ? 26 : 0)
                .overlay {
                  // 검색에서 찾은 턴 — 테두리가 몇 번 깜빡여 "여기"라고 알려 준다
                  if focusedTurn == t.id {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                      .stroke(Color.purple, lineWidth: focusPulse ? 2.5 : 1)
                      .opacity(focusPulse ? 1 : 0.25)
                      .padding(-2)
                      .allowsHitTesting(false)
                  }
                }
                .contextMenu {
                  if t.role == .user { questionActions(t) }
                }
                .id(t.id)
                .overlay(alignment: .trailing) {
                  if t.role == .user { questionMenu(t) }
                }
                if t.role == .assistant {
                  HStack(spacing: 1) {
                    // 복사는 **원문(마크다운 소스)** — 붙여넣으면 서식이 그대로 살아난다
                    Button { copyReply(t.text, id: t.id) } label: {
                      Image(systemName: copiedTurn == t.id ? "checkmark" : "doc.on.doc")
                        .frame(width: 24, height: 24)
                        .foregroundColor(copiedTurn == t.id ? .purple : .primary)
                    }
                    .help(copiedTurn == t.id ? L("복사됨") : L("응답 복사 (마크다운 원문)"))
                    .buttonStyle(.borderless)
                    // 읽어주기는 마크다운 기호를 걷어낸 평문으로(별표·백틱을 소리 내지 않게)
                    // 재생 중에는 **중지 버튼**으로 바뀐다(한 번 더 누르면 멈춘다)
                    Button { store.speak(MarkdownPlain.text(t.text), turnID: t.id) } label: {
                      Image(systemName: store.speakingTurnID == t.id ? "stop.fill" : "speaker.wave.2")
                        .frame(width: 24, height: 24)
                        .foregroundColor(store.speakingTurnID == t.id ? .red : .primary)
                    }
                    .help(store.speakingTurnID == t.id ? L("읽어주기 중지") : L("읽어주기"))
                    .buttonStyle(.borderless)
                  }
                  // 스트리밍 중인 답변에는 아직 복사·읽어주기를 노출하지 않는다.
                  // (빈 자리는 유지해 답변이 끝날 때 아이콘이 생기며 말풍선이 밀리지 않게)
                  .opacity(t.id == store.streamingTurnID || t.text.isEmpty ? 0 : 1)
                  .allowsHitTesting(t.id != store.streamingTurnID && !t.text.isEmpty)
                }
              }
            }
            // 스트리밍 첫 글자가 오면 점 표시를 숨긴다(글자가 대신 보인다)
            if store.isReplying,
               store.streamingTurnID == nil || (store.conversation.turns.last?.text.isEmpty ?? true) {
              replyingBubble
            }
            Color.clear.frame(height: 1).id(Self.bottomID)
          }
          .padding(12)
          // 토큰 칩이 위에 떠 있어도 첫 메시지를 가리지 않게 그만큼 비워 둔다(헤더 높이는 그대로).
          .padding(.top, showsMemoryChip ? 14 : 0)
          .frame(maxWidth: .infinity, alignment: .leading)
          // 내용 끝(마커)의 위치를 스크롤 좌표계에서 잰다 — 뷰포트 높이와 비교해 맨 아래 여부를 안다.
          // ★ GeometryReader+PreferenceKey 는 macOS 에서 스크롤 중 갱신되지 않아 버튼이 뜨지 않았다.
          //   NSScrollView 를 직접 관찰한다(2026-10-27).
          .background(ScrollOffsetObserver(
            bottomToken: bottomPinToken,
            onChange: handleScrollDistance))
        }
        .coordinateSpace(name: Self.chatSpace)
        // `.defaultScrollAnchor(.bottom)` 은 **크기가 바뀔 때도** 바닥에 다시 붙는다
        // (macOS 15). 그래서 위로 올려 읽는 중에도 새 글자가 오면 바닥으로 납치됐다
        // — 스크롤이 아예 안 되는 것처럼 느껴진 원인(2026-11-05). 초기 위치는
        // onAppear 의 AppKit 고정(pin)이 잡는다.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 기억 사용량 — 헤더가 아니라 대화 영역 위에 띄운다(탭 전환 시 헤더 높이 고정).
        .overlay(alignment: .topTrailing) { memoryChip }
        .overlay(alignment: .bottomTrailing) { hoverPreviewCard }
        // 맨 아래가 아닐 때만 — 우하단에 "맨 아래로" 플로팅 버튼
        .overlay(alignment: .bottomTrailing) {
          if !atBottom && !store.conversation.turns.isEmpty {
            Button { jumpToBottom() } label: {
              Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.purple.opacity(0.9)))
                .overlay(Circle().stroke(Color.white.opacity(0.28), lineWidth: 1))
                .shadow(color: .black.opacity(0.28), radius: 6, y: 2)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(L("맨 아래(최신)로 이동"))
            .padding(.trailing, 12).padding(.bottom, 8)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .accessibilityLabel(L("맨 아래로"))
          }
        }
        // 새 턴(내가 보낸 메시지)·대화 전환은 사용자가 읽던 위치와 무관하게 바닥으로
        .onChange(of: store.conversation.turns.count) { _, _ in jumpToBottom() }
        // 스트리밍 — 글자가 늘 때마다 바닥을 따라간다(애니메이션 없이, 초당 12회 수준)
        .onChange(of: store.conversation.turns.last?.text.count) { _, _ in
          if store.streamingTurnID != nil { followBottom() }
        }
        // 도구 실행 — 이벤트가 추가되거나 출력이 늘 때도 **맨 아래**를 따라간다.
        // (도구가 무엇을 하는지 화면 밖에서 진행되면 볼 수 없다 — 2026-11-05 사용자 지적)
        .onChange(of: agentFollowToken) { _, _ in followBottom() }
        // 보관함에서 다른 대화를 열 때 — 검색 결과로 열었으면 그 턴, 아니면 맨 아래부터
        .onChange(of: store.conversation.id) { _, _ in
          if let req = store.searchFocus {
            focusTurn(req, proxy: proxy)
          } else {
            jumpToBottom()
          }
        }
        // 이미 열려 있는 대화에서 검색 결과를 다시 눌러도 그 턴으로
        .onChange(of: store.searchFocus) { _, req in
          if let req { focusTurn(req, proxy: proxy) }
        }
        .onChange(of: store.isReplying) { _, _ in followBottom() }
        // 승인 카드가 뜨면 카드 **끝(버튼)** 까지 보이게 맨 아래로 따라간다.
        // (2026-10-26: 카드가 화면 밖에 걸려 [한 번 허용]이 잘려 보이던 문제)
        .onChange(of: store.agentApproval) { _, request in
          guard request != nil else { return }
          jumpToBottom()
          // 긴 명령이 여러 줄로 감기면 카드 높이가 한 프레임 늦게 확정된다 — 한 번 더 맞춘다.
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { jumpToBottom() }
        }
        // 일정 제안 카드가 뜨면 그 턴까지 스크롤한다.
        .onChange(of: store.pendingSchedule) { _, pending in
          guard pending != nil, pending?.conversationID == store.conversation.id else { return }
          jumpToBottom()
        }
        // 예약 실행이 승인을 기다리면 그 대화의 카드 끝까지 따라간다.
        .onChange(of: store.scheduledApproval) { _, pending in
          guard pending != nil, pending?.conversationID == store.conversation.id else { return }
          jumpToBottom()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { jumpToBottom() }
        }
        // 창을 열 때(숨겼다 다시 열 때 포함) — SwiftUI onAppear는 다시 오지 않는다
        .onReceive(NotificationCenter.default.publisher(for: .quickTalkScrollToBottom)) { _ in
          jumpToBottom()
        }
        .onAppear {
          if let req = store.searchFocus {
            focusTurn(req, proxy: proxy)
          } else {
            jumpToBottom()
          }
        }
        }

      networkRetryRow
      memoryRow
      attachmentRow
      attachNoticeRow
      slashPalette
      dockRow
    }
  }

  // MARK: - 호버 미리보기 (스트립·첨부 칩에서 마우스를 올리면 크게 보여준다)

  @ViewBuilder private var hoverPreviewCard: some View {
    if let a = hoverPreview {
      VStack(alignment: .leading, spacing: 7) {
        attachmentPreviewBody(a)
        HStack(spacing: 4) {
          Spacer(minLength: 0)
          Text("esc").font(.system(size: 9, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(Capsule().fill(Color.primary.opacity(0.08)))
          Text(L("Esc로 닫기")).font(.system(size: 9)).foregroundColor(.secondary)
        }
      }
      .padding(10)
      .frame(maxWidth: 380, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .windowBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.16), lineWidth: 1))
      .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
      .padding(.horizontal, 12).padding(.bottom, 6)
      .allowsHitTesting(false)   // 미리보기가 클릭·호버를 가로채지 않게
      .transition(.opacity)
    }
  }

  @ViewBuilder private func attachmentPreviewBody(_ p: AttachmentPreview) -> some View {
    HStack(spacing: 6) {
      Image(systemName: p.kind == .image ? "photo" : "doc")
      Text(p.name).font(.system(size: 11, weight: .semibold)).lineLimit(2)
      if let detail = p.detail {
        Spacer(minLength: 8)
        Text(detail).font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
      }
    }
    if let img = p.image {
      Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
        .frame(maxWidth: 360, maxHeight: 240)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    if let path = p.pathText {
      Text(path)
        .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(3)
    }
    if let note = p.note {
      Text(note).font(.system(size: 11)).foregroundColor(.orange)
    }
    if let footer = p.footer {
      Text(footer).font(.system(size: 10.5)).foregroundColor(.secondary)
    }
  }

  private static let bottomID = "chat-bottom"
  /// 스크롤 위치 측정용 좌표계 이름
  private static let chatSpace = "chat-scroll-space"

  // MARK: - 보낸 메시지의 첨부(썸네일 + 호버 미리보기)

  /// 전송 후 말풍선에 붙는 첨부 카드 — 무엇을 보냈는지 한눈에 보인다.
  /// 호버하면 입력 전 칩과 **같은 미리보기 카드**(`attachmentPreviewBody`)가 뜬다.
  @ViewBuilder private func sentAttachmentStrip(_ atts: [Attachment]) -> some View {
    let shown = atts.count > 3 ? Array(atts.prefix(3)) : atts
    HStack(spacing: 6) {
      ForEach(Array(shown.enumerated()), id: \.offset) { _, a in
        sentAttachmentCard(a)
      }
      if atts.count > shown.count {
        Text("+\(atts.count - shown.count)")
          .font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
          .padding(.horizontal, 9).padding(.vertical, 7)
          .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.18)))
          .help(Lf("나머지 %d건은 표시하지 않았습니다", atts.count - shown.count))
      }
    }
    .frame(maxWidth: 420, alignment: .trailing)
  }

  @ViewBuilder private func sentAttachmentCard(_ a: Attachment) -> some View {
    let p = AttachmentPreview.sent(a)
    Group {
      if let img = p.image {
        ZStack(alignment: .bottomTrailing) {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 150, height: 100).clipped()
          if let detail = p.detail {
            Text(detail)
              .font(.system(size: 9, weight: .semibold))
              .foregroundColor(.white)
              .padding(.horizontal, 5).padding(.vertical, 2)
              .background(Capsule().fill(Color.black.opacity(0.55)))
              .padding(5)
          }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
          .stroke(Color.white.opacity(0.14), lineWidth: 1))
      } else {
        HStack(spacing: 7) {
          Image(systemName: a.kind == .image ? "photo" : "doc.text")
            .font(.system(size: 13)).foregroundColor(.secondary)
          VStack(alignment: .leading, spacing: 1) {
            Text(a.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
            Text(p.note ?? p.detail ?? (a.kind == .image ? L("이미지") : L("파일")))
              .font(.system(size: 9.5))
              .foregroundColor(p.note == nil ? .secondary : .orange)
              .lineLimit(1)
          }
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .frame(maxWidth: 220, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.18)))
        .overlay(RoundedRectangle(cornerRadius: 10)
          .stroke(Color.orange.opacity(p.note == nil ? 0 : 0.5), lineWidth: 1))
      }
    }
    .onHover { hovering in
      let key = "sent|\(a.name)|\(a.path ?? "")"
      if hovering {
        hoverPreview = p
        hoverPreviewKey = key
      } else if hoverPreviewKey == key {
        // NSImage는 다시 만들 때마다 비교가 실패할 수 있다 — 값 비교 대신 안정적인 키로 닫는다.
        hoverPreview = nil
        hoverPreviewKey = nil
      }
    }
    .contextMenu {
      if let path = a.path, FileManager.default.fileExists(atPath: path) {
        Button(L("미리보기 열기")) { NSWorkspace.shared.open(URL(fileURLWithPath: path)) }
        Button(L("Finder에서 보기")) {
          NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
        }
      } else {
        Text(L("원본 파일 없음"))
      }
    }
    .help(p.note ?? Lf("%@ — 마우스를 올리면 크게 봅니다", a.name))
  }

  /// 입력독 위 배너 — 연결이 끊겨 **다시 연결을 기다리는 중**임을 알린다(v0.29).
  /// 대기 중에도 [중지]로 바로 빠져나올 수 있다.
  @ViewBuilder private var networkRetryRow: some View {
    if let status = store.networkRetryStatus {
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(status).font(.system(size: 11)).lineLimit(2)
        Spacer(minLength: 4)
        Button(L("응답 중지")) { store.cancelReply() }
          .buttonStyle(.plain)
          .font(.system(size: 11, weight: .medium))
          .foregroundColor(.red)
          .help(L("다시 연결을 멈추고 지금까지 받은 답변을 남깁니다"))
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.blue.opacity(0.12)))
      .overlay(Capsule().stroke(Color.blue.opacity(0.35), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    }
  }

  /// 입력독 위 배너 — 자동 정리 상태(정리 중 / 요약됨 / 일시 중지 / 실패).
  /// 요약이 적용돼도 원문 턴은 화면·보관함에 그대로 남는다.
  @ViewBuilder private var memoryRow: some View {
    if store.isCompacting, store.compactingConversationID == store.conversation.id {
      HStack(spacing: 6) {
        ProgressView().controlSize(.small)
        Text(L("이전 대화를 정리하는 중…")).font(.system(size: 11))
        Spacer(minLength: 4)
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.purple.opacity(0.12)))
      .overlay(Capsule().stroke(Color.purple.opacity(0.35), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    } else if let message = store.compactMessage {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 10)).foregroundColor(.orange)
        Text(message).font(.system(size: 11)).lineLimit(2)
        Spacer(minLength: 4)
        Button { store.compactMessage = nil } label: {
          Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
        }.buttonStyle(.plain).help(L("안내 닫기"))
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.orange.opacity(0.16)))
      .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    } else if store.conversation.activeSummary != nil {
      HStack(spacing: 6) {
        Image(systemName: "brain.head.profile")
          .font(.system(size: 11)).foregroundColor(.purple)
        Text(Lf("이전 %d개 메시지를 요약해 기억 중", store.conversation.summarizedTurnCount))
          .font(.system(size: 11))
        Spacer(minLength: 4)
        Button(L("보기")) { showMemory = true }
          .buttonStyle(.plain).foregroundColor(.purple)
          .help(L("모델이 기억하는 요약을 확인합니다"))
        Button(L("해제")) { store.clearConversationMemory() }
          .buttonStyle(.plain).foregroundColor(.secondary)
          .help(L("요약을 지우고 자동 정리를 멈춥니다. 원문은 그대로 남습니다"))
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.purple.opacity(0.12)))
      .overlay(Capsule().stroke(Color.purple.opacity(0.35), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    } else if store.conversation.autoCompactPaused {
      HStack(spacing: 6) {
        Image(systemName: "pause.circle")
          .font(.system(size: 11)).foregroundColor(.secondary)
        Text(L("자동 정리가 일시 중지되어 있습니다")).font(.system(size: 11))
        Spacer(minLength: 4)
        Button(L("다시 켜기")) { store.resumeAutoCompact() }
          .buttonStyle(.plain).foregroundColor(.purple)
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.secondary.opacity(0.12)))
      .overlay(Capsule().stroke(Color.secondary.opacity(0.30), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    }
  }

  /// 입력독 위 배너 — 지원하지 않는 형식 등으로 **걸러낸 첨부**를 알린다(무음 실패 금지)
  @ViewBuilder private var attachNoticeRow: some View {
    if let notice = store.attachNotice {
      HStack(spacing: 6) {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 10)).foregroundColor(.orange)
        Text(notice).font(.system(size: 11)).lineLimit(2)
        Spacer(minLength: 4)
        Button { store.attachNotice = nil } label: {
          Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
        }.buttonStyle(.plain).help(L("안내 닫기"))
      }
      .padding(.horizontal, 10).padding(.vertical, 5)
      .background(Capsule().fill(Color.orange.opacity(0.16)))
      .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
      .padding(.horizontal, 12).padding(.bottom, 6)
    }
  }

  /// 질문 말풍선 옆 메뉴 — 다시 응답 / 질문 수정(이후 대화 삭제 후 입력창 복원).
  private func questionMenu(_ t: Turn) -> some View {
    Menu {
      questionActions(t)
    } label: {
      Image(systemName: "ellipsis.circle")
        .font(.system(size: 13))
        .foregroundColor(.secondary)
        .frame(width: 22, height: 22)
        .contentShape(Circle())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .disabled(store.isReplying)
    .help(L("질문 메뉴 — 다시 응답하거나 수정"))
  }

  @ViewBuilder private func questionActions(_ t: Turn) -> some View {
    Button { store.regenerateAnswer(t) } label: {
      Label(L("다시 응답 받기"), systemImage: "arrow.clockwise")
    }
    Button { store.editQuestion(t) } label: {
      Label(L("질문 수정하기"), systemImage: "pencil")
    }
  }

  /// 응답 복사 — 내용은 로그에 남기지 않는다([HARD] 마스킹). 체크 표시는 1.2초만.
  private func copyReply(_ text: String, id: UUID) {
    guard !text.isEmpty else { return }
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(text, forType: .string)
    copiedTurn = id
    NSLog("[QuickTalk] 응답 복사 — %d자", text.count)
    Task { @MainActor in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      if copiedTurn == id { copiedTurn = nil }
    }
  }

  /// 응답 시간 표시 — 60초 미만은 소수 한 자리, 그 이상은 분·초
  /// 토큰 수 축약 — 21,324 → "21.3k" (헤더 폭 절약, 정확한 값은 툴팁)
  static func compactTokens(_ n: Int) -> String {
    guard n >= 1_000 else { return "\(n)" }
    let k = Double(n) / 1_000
    return String(format: k < 10 ? "%.1fk" : "%.0fk", k)
  }

  static func elapsedLabel(_ ms: Int) -> String {
    let seconds = Double(ms) / 1000
    if seconds < 60 { return Lf("%.1f초", seconds) }
    let total = Int(seconds.rounded())
    return Lf("%d분 %d초", total / 60, total % 60)
  }

  /// 자동으로 바닥을 따라간다 — 사용자가 위로 올려 읽는 중(`followsBottom == false`)이면 가만히 둔다.
  /// 스트리밍 글자·도구 출력이 매번 스크롤을 납치하면 과거 내용을 볼 수 없다(2026-11-05).
  private func followBottom() {
    guard focusedTurn == nil, followsBottom else { return }
    pinBottom()
  }

  /// 사용자가 직접 "맨 아래로"를 눌렀거나 새 메시지를 보낸 경우 — 무조건 끝으로.
  private func jumpToBottom() {
    guard focusedTurn == nil else { return }
    followsBottom = true
    atBottom = true
    pinBottom()
  }

  /// `NSScrollView`에 "맨 끝으로" 신호를 보낸다. 실제 이동은 관찰 뷰가 한다.
  /// SwiftUI `scrollTo(anchor:.bottom)` 은 내용 높이가 한 프레임 늦게 확정되면 끝까지 못 갔다.
  private func pinBottom() {
    lastPinAt = Date()
    bottomPinToken &+= 1
  }

  /// 도구 실행 카드가 추가·갱신될 때마다 바뀌는 값 — 자동 스크롤 트리거.
  private var agentFollowToken: String {
    let events = store.conversation.turns.last?.agentEvents ?? []
    let last = events.last
    return "\(events.count)|\(last?.state.rawValue ?? "")|\(last?.output.count ?? 0)"
  }

  /// 사용자가 스크롤을 **위로** 올리면 자동 따라가기를 멈춘다(내용이 스크롤을 납치하지 않게).
  /// 바닥에 닿으면 다시 따라간다.
  private func handleScrollDistance(_ distance: CGFloat, didScrollUp: Bool) {
    if didScrollUp { followsBottom = false }
    let atEnd = ScrollMetrics.isAtBottom(distance: distance)
    if atEnd != atBottom {
      withAnimation(.easeInOut(duration: 0.12)) { atBottom = atEnd }
    }
    if atEnd {
      followsBottom = true
      return
    }
    // 내용이 늘어 바닥에서 멀어진 경우 — 붙어 있던 사용자라면 다시 끝으로 붙인다.
    // (위로 올려 읽는 중이면 followsBottom 이 false 라 건드리지 않는다)
    guard followsBottom, Date().timeIntervalSince(lastPinAt) > 0.25 else { return }
    pinBottom()
  }

  /// 보관함 검색 결과로 연 대화 — 찾은 턴을 가운데로 스크롤하고 테두리를 3회 깜빡인다.
  /// 탭 전환·레이아웃 확정 전에는 scrollTo가 잘리므로 몇 프레임 뒤에 다시 맞춘다.
  private func focusTurn(_ req: SearchFocusRequest, proxy: ScrollViewProxy) {
    guard req.conversationID == store.conversation.id else { return }
    store.searchFocus = nil
    focusedTurn = req.turnID
    focusPulse = false
    let jump = { proxy.scrollTo(req.turnID, anchor: .center) }
    jump()
    DispatchQueue.main.async { jump() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { jump() }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { jump() }
    withAnimation(.easeInOut(duration: 0.24).repeatCount(3, autoreverses: true)) {
      focusPulse = true
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.55) {
      withAnimation(.easeOut(duration: 0.35)) { focusPulse = false }
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        if focusedTurn == req.turnID { focusedTurn = nil }
      }
    }
  }

  /// 승인 카드에 넘길 요청 — 현재 턴의 실행이거나 **예약 실행의 승인 대기**.
  /// 예약 실행은 그 대화를 열었을 때만 카드가 뜬다(다른 대화에 끼어들지 않는다).
  private func approvalRequest(for turn: Turn) -> AgentApprovalRequest? {
    if turn.id == store.agentTurnID { return store.agentApproval }
    if let pending = store.scheduledApproval, pending.turnID == turn.id { return pending.request }
    return nil
  }

  /// 응답 대기 표시 — 자체 점 애니메이션(네이티브 인디케이터 대신) + 경과·모델 라벨
  /// 검색 중에는 점 대신 🌐와 "웹에서 찾는 중…"을 보여 준다.
  private var replyingBubble: some View {
    HStack {
      HStack(spacing: 9) {
        if store.isSearching {
          Image(systemName: "globe")
            .font(.system(size: 12, weight: .medium))
            .foregroundColor(.purple)
        } else {
          TypingDots()
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(store.isSearching ? L("웹에서 찾는 중…") : L("응답 중…")).font(.callout)
          if store.isSearching {
            Text(L("검색 결과를 답변에 넣습니다")).font(.caption2).foregroundColor(.secondary)
          } else {
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
              Text(Lf("%@ · %d초", store.replySourceLabel, store.replySeconds))
                .font(.caption2).foregroundColor(.secondary)
            }
          }
        }
      }
      .padding(.horizontal, 11).padding(.vertical, 9)
      // 불투명한 카드 — 도구 카드가 뒤에 길게 이어져도 글자가 비쳐 겹쳐 보이지 않게 한다.
      .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1))
      Spacer()
    }
  }

  /// 답변 아래 [웹에서 찾기] — 모델이 웹 접근 불가를 밝힌 답변을 같은 질문으로 재시도한다.
  private func webRetryButton(_ turn: Turn) -> some View {
    Button { store.retryWithWebSearch(turn) } label: {
      HStack(spacing: 5) {
        Image(systemName: "globe").font(.system(size: 10, weight: .semibold))
        Text(L("웹에서 찾기")).font(.system(size: 10.5, weight: .semibold))
      }
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(Capsule().fill(Color.purple.opacity(0.12)))
      .overlay(Capsule().stroke(Color.purple.opacity(0.35), lineWidth: 1))
      .foregroundColor(.purple)
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .help(L("이 질문을 웹 검색과 함께 다시 보냅니다"))
  }

  /// 답변 아래 출처 카드 — `[1] 도메인 · 날짜`, 클릭하면 기본 브라우저로 연다.
  /// 복사·읽어주기는 답변 원문만 쓴다(출처는 여기서 따로).
  private func sourceCards(_ sources: [TurnSource]) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Array(sources.prefix(5).enumerated()), id: \.element.id) { index, source in
        Button {
          guard let url = URL(string: source.url) else { return }
          NSWorkspace.shared.open(url)
        } label: {
          HStack(spacing: 5) {
            Text("[\(index + 1)]")
              .font(.system(size: 10, weight: .semibold))
              .foregroundColor(.purple)
            Text(source.domain.isEmpty ? source.title : source.domain)
              .font(.system(size: 10, weight: .medium))
            if !source.domain.isEmpty {
              Text(source.title)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
            }
            if let date = source.publishedAt {
              Text(Self.sourceDate.string(from: date))
                .font(.system(size: 9))
                .foregroundColor(.secondary)
            }
          }
          .padding(.horizontal, 7).padding(.vertical, 3)
          .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
        .help(source.title)
      }
    }
    .padding(.leading, 2)
  }

  private static let sourceDate: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "ko_KR")
    f.dateFormat = "M.d HH:mm"
    return f
  }()

  /// 첨부 칩 — 이미지면 썸네일, 호버하면 크게 보기, ✕로 하나씩 제거
  @ViewBuilder private var attachmentRow: some View {
    if !store.attached.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 6) {
          Image(systemName: "paperclip").font(.system(size: 10)).foregroundColor(.purple)
          ForEach(store.attached) { a in
            let preview = AttachmentPreview.pending(a)
            let previewKey = a.id.uuidString
            HStack(spacing: 5) {
              if let img = a.image {
                Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                  .frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5))
              } else {
                Image(systemName: "doc").font(.system(size: 10))
              }
              Text(a.name).font(.caption).lineLimit(1).frame(maxWidth: 140, alignment: .leading)
              Button { store.removeAttachment(a.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundColor(.secondary)
              }.buttonStyle(.plain).help(L("첨부 제거"))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color.purple.opacity(0.15)))
            .overlay(Capsule().stroke(Color.purple.opacity(hoverPreviewKey == previewKey ? 0.85 : 0.25),
                                     lineWidth: 1))
            .onHover { h in
              if h {
                hoverPreview = preview
                hoverPreviewKey = previewKey
              } else if hoverPreviewKey == previewKey {
                hoverPreview = nil
                hoverPreviewKey = nil
              }
            }
          }
        }
        .padding(.horizontal, 12).padding(.bottom, 6)
      }
      .scrollIndicators(.hidden)
    }
  }

  /// 슬래시 팔레트(v0.21) — `/`로 시작하면 명령을 보여 주고 **클릭**으로 고른다.
  /// Enter 처리(전송)는 바꾸지 않는다 — 한글 IME 안전을 위해 클릭 선택만 추가한다.
  @ViewBuilder private var slashPalette: some View {
    let matches = SlashCommands.matches(store.draft,
                                       toolsEnabled: store.settings.agentToolsEnabled)
    if !matches.isEmpty {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(matches) { command in
          Button {
            if command.id == "tasks" {
              // `/할일` 은 문장을 채우지 않고 **목록 시트**를 연다(PLAN §8.2 예외).
              store.draft = ""
              store.showTaskList = true
            } else {
              store.draft = command.template
              store.composerFocusToken = UUID()
            }
          } label: {
            HStack(spacing: 7) {
              Image(systemName: command.systemImage)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 16)
              Text(command.token)
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
              Text(command.summary)
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(1)
              Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .help(command.template)
        }
      }
      .padding(.vertical, 3)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1))
      .padding(.horizontal, 12)
      .padding(.bottom, 4)
    }
  }

  /// 입력독 — Siri 입력창처럼 **한 상자 안**에 ＋(왼쪽 아래) · 입력 · 🎤/↑(오른쪽 아래)
  /// 입력은 1~5줄까지 늘어나고 그 이상은 상자 안에서 스크롤된다. Enter = 전송 / Shift+Enter = 줄바꿈.
  private var canSend: Bool {
    (!store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.attached.isEmpty)
      && !store.isReplying
  }

  /// 입력 영역 오른쪽 여백 — 아래 버튼(창 연결·🌐·🎤·↑)이 글자를 가리지 않게, 켜진 버튼만큼 비운다.
  private var composerTrailingPadding: CGFloat {
    var p: CGFloat = 84
    if store.settings.windowAttachmentEnabled { p += 32 }
    if store.settings.webSearchEnabled { p += 32 }
    return p
  }

  private var dockRow: some View {
    ZStack(alignment: .bottomTrailing) {
      // 입력 영역 — 좌우로 버튼 자리를 비워 둔다
      ZStack(alignment: .topLeading) {
        ChatInputField(text: $store.draft, height: $inputHeight,
                       isBusy: store.isReplying,
                       focusToken: store.composerFocusToken,
                       onPasteAttachments: { store.pasteAttachmentFromPasteboard() }) { value in
          store.draft = value
          store.send()
        }
        .frame(height: inputHeight)
        if store.draft.isEmpty {
          Text(L("무엇이든 물어보세요"))
            .font(.system(size: 13)).foregroundColor(Color.secondary.opacity(0.75))
            // 여백은 **컨테이너가 이미 준 안쪽 여백**이므로 다시 더하지 않는다(캐럿과 같은 x에서 시작)
            .padding(.leading, ChatInputField.horizontalPadding + 2)
            .padding(.top, ChatInputField.verticalPadding)
            .allowsHitTesting(false)
        }
      }
      // 비서가 있으면 왼쪽 아래 버튼(26pt)만큼 글자 시작점을 비운다 — 없으면 기존과 동일.
      .padding(.leading, store.settings.personas.isEmpty ? 14 : 48)
      .padding(.trailing, composerTrailingPadding)     // 오른쪽 아래 창 연결·🌐·🎤·↑ 자리
      .padding(.vertical, 8)

      // 비서 버튼 — 새 대화에서도 입력 전에 고를 수 있다(v0.28, 헤더 칩과 같은 메뉴).
      if !store.settings.personas.isEmpty {
        HStack {
          PersonaDockButton()
          Spacer()
        }
        .padding(.leading, 12)
        .padding(.bottom, 9)
      }

      HStack(spacing: 6) {
        Spacer()

        // 🪟 창 연결 — 이 창의 텍스트·스크린샷을 이번 질문의 참고 자료로 붙인다(읽기 전용).
        if store.settings.windowAttachmentEnabled {
          Button { showWindowPicker = true } label: {
            Image(systemName: "macwindow.on.rectangle")
              .font(.system(size: 12, weight: .medium))
              .frame(width: 26, height: 26)
              .foregroundColor(.primary)
              .background(Circle().fill(Color.primary.opacity(0.08)))
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .disabled(store.isReplying)
          .help(L("창 연결 — 이 창의 글자와 스크린샷을 참고 자료로 (읽기 전용)"))
        }

        // 🌐 — 이번 질문만 웹 검색(자동 모드에서도 강제). 검색이 꺼져 있으면 숨긴다.
        if store.settings.webSearchEnabled {
          Button { store.forceWebSearch.toggle() } label: {
            Image(systemName: "globe")
              .font(.system(size: 12, weight: .medium))
              .frame(width: 26, height: 26)
              .foregroundColor(store.forceWebSearch ? .white : .primary)
              .background(Circle().fill(store.forceWebSearch ? Color.purple : Color.primary.opacity(0.08)))
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .disabled(store.isReplying)
          .help(store.forceWebSearch
                ? L("이번 질문은 웹 검색합니다 — 누르면 해제")
                : L("이번 질문만 웹 검색 (🌐)"))
        }

        Button { store.toggleVoice() } label: {
          Image(systemName: store.voiceRecording ? "mic.fill" : "mic")
            .font(.system(size: 12, weight: .medium))
            .frame(width: 26, height: 26)
            .foregroundColor(store.voiceRecording ? .red : .primary)
            .background(Circle().fill(Color.primary.opacity(store.voiceRecording ? 0.16 : 0.08)))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(store.voiceRecording ? L("녹음 중지") : Lf("음성 입력 (%@)", store.settings.voiceEngine.displayName))

        Button { store.isReplying ? store.cancelReply() : store.send() } label: {
          // 응답 대기 중에는 전송 대신 **중지**(⏹) — 로컬 모델은 첫 토큰까지 수 분 걸릴 수 있다
          Image(systemName: store.isReplying ? "stop.fill" : "arrow.up")
            .font(.system(size: 12, weight: .bold))
            .frame(width: 26, height: 26)
            .foregroundColor(store.isReplying ? .red : (canSend ? .white : .secondary))
            .background(Circle().fill(store.isReplying
                                      ? Color.red.opacity(0.14)
                                      : (canSend ? Color.accentColor : Color.primary.opacity(0.10))))
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!store.isReplying && !canSend)
        .help(store.isReplying ? L("응답 중지") : L("전송 (Enter)"))
      }
      .padding(.trailing, 8)
      .padding(.bottom, 9)
    }
    .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.14)))
    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    .padding(.horizontal, 10)
    .padding(.bottom, 10)
    .help(L("Enter = 전송 · Shift+Enter = 줄바꿈 (5줄까지 늘어나고 그 이상은 스크롤)"))
  }

  // MARK: - 보관함 탭

  private var archiveTab: some View {
    VStack(spacing: 0) {
      HStack(spacing: 6) {
        TextField(L("기록 검색"), text: $archiveQuery)
          .textFieldStyle(.roundedBorder)
        if !archiveQuery.isEmpty {
          Button { archiveQuery = "" } label: {
            Image(systemName: "xmark.circle.fill")
              .font(.system(size: 14))
              .foregroundColor(.secondary)
              .frame(width: 22, height: 22)
              .contentShape(Circle())
          }
          .buttonStyle(.plain)
          .help(L("검색어 지우기"))
        }
      }
      .padding(.horizontal, 12).padding(.top, 8)
      List {
        Section(L("진행 중")) {
          if store.conversation.turns.isEmpty {
            Text(L("진행 중 대화 없음 — 새 대화에서 시작")).font(.callout).foregroundColor(.gray)
          } else {
            Button { tab = 0 } label: {
              VStack(alignment: .leading) {
                Text(store.conversation.displayTitle).bold()
                HStack(spacing: 6) {
                  if let p = store.settings.persona(personaID(for: store.conversation)) {
                    personaTag(p)
                  }
                  Text(Lf("%d턴 · %@ · %@", store.conversation.turns.count,
                          RelativeTime.text(for: store.conversation.updatedAt, now: nowTick),
                          store.conversation.pinned ? L("보관") : L("자동 저장")))
                    .font(.caption).foregroundColor(.gray)
                    .help(Lf("마지막 대화: %@", RelativeTime.absolute(store.conversation.updatedAt)))
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }.buttonStyle(.plain)
          }
        }
        if filteredArchive.isEmpty {
          Section(L("대화 기록")) {
            Text(archiveQuery.isEmpty ? L("기록 없음 — 대화를 보내면 자동으로 저장됩니다") : L("검색 결과 없음"))
              .font(.callout).foregroundColor(.gray)
          }
        } else if archiveQuery.isEmpty {
          // 비서별로 묶어서 보여 준다 — 기본(비서 없음)이 먼저, 그 다음 설정 순서.
          ForEach(personaGroups) { group in
            Section(group.title) {
              ForEach(group.conversations, id: \.id) { c in
                archiveRow(c)
              }
            }
          }
        } else {
          Section(L("검색 결과")) {
            ForEach(filteredArchive, id: \.id) { c in
              archiveRow(c)
            }
          }
        }
        Section {
          Text(Lf("대화는 보낼 때마다 자동 저장됩니다. 자동 저장분은 %d일 뒤 정리되고, 🔖 보관한 대화는 남습니다.", store.settings.keepDays))
            .font(.caption).foregroundColor(.secondary)
        }
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { if !suppressArchiveLoad { store.loadArchive() } }
  }

  // MARK: - 설정 탭 (메뉴바 Hub 설정 탭과 동일한 뷰 — 단일 출처)

  private var settingsTab: some View {
    ScrollView {
      // 창 폭에 맞춰 카드가 가로로 늘어난다(보관함 탭과 같은 가변 폭)
      QuickSettingsCardsView(onOpenSettings: openSettingsWindow)
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .onAppear { store.loadArchive() }
  }
}

/// 모델이 기억 중인 요약을 보여 주고 직접 고칠 수 있는 시트.
/// 원문은 삭제되지 않았다는 점을 함께 안내한다.
struct MemorySheet: View {
  @Environment(\.dismiss) private var dismiss
  let summary: String
  let onSave: (String) -> Void
  let onClear: () -> Void

  @State private var draft: String

  init(summary: String, onSave: @escaping (String) -> Void, onClear: @escaping () -> Void) {
    self.summary = summary
    self.onSave = onSave
    self.onClear = onClear
    _draft = State(initialValue: summary)
  }

  private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
  private var canSave: Bool { !trimmed.isEmpty && trimmed != summary.trimmingCharacters(in: .whitespacesAndNewlines) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L("대화 기억 요약")).font(.headline)
      Text(L("모델은 아래 요약과 최근 대화만 봅니다. 원문은 화면·보관함에 그대로 남아 있습니다. 요약을 직접 고쳐도 경계와 원문은 바뀌지 않습니다."))
        .font(.caption).foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      TextEditor(text: $draft)
        .font(.system(size: 12.5))
        .scrollContentBackground(.hidden)
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10)
          .stroke(Color.primary.opacity(0.10), lineWidth: 1))
      HStack {
        Button(L("요약 해제")) { onClear(); dismiss() }
          .help(L("요약을 지우고 자동 정리를 멈춥니다"))
        Spacer()
        Text(Lf("%d자", trimmed.count))
          .font(.caption).foregroundColor(.secondary)
        Button(L("저장")) { onSave(trimmed); dismiss() }
          .disabled(!canSave)
          .keyboardShortcut(.defaultAction)
        Button(L("닫기")) { dismiss() }
      }
    }
    .padding(16)
    .frame(width: 540, height: 420)
  }
}




/// 대화 스크롤 — 실제 `NSScrollView` 값을 관찰해 "맨 아래까지 남은 거리"를 알린다.
///
/// `GeometryReader`+`PreferenceKey` 는 macOS 에서 **레이아웃 때만** 값이 갱신됐다.
/// 스크롤은 `NSScrollView` 의 transform 이라 선호도가 다시 오지 않았고,
/// 그래서 "맨 아래로" 버튼이 스크롤 중에 뜨지 않았다(2026-10-27 사용자 보고).
/// 문서 크기 변화(스트리밍·첨부)도 함께 본다.
private struct ScrollOffsetObserver: NSViewRepresentable {
  /// 값이 바뀌면 문서 끝으로 이동한다 — SwiftUI 스크롤 프록시 대신 AppKit 으로 직접.
  let bottomToken: Int
  /// (남은 거리, 사용자가 위로 스크롤했는가)
  let onChange: (CGFloat, Bool) -> Void

  func makeNSView(context: Context) -> ObserverView {
    ObserverView(bottomToken: bottomToken, onChange: onChange)
  }

  func updateNSView(_ nsView: ObserverView, context: Context) {
    nsView.onChange = onChange
    nsView.pinIfNeeded(token: bottomToken)
  }

  final class ObserverView: NSView {
    var onChange: (CGFloat, Bool) -> Void
    private var tokens: [NSObjectProtocol] = []
    private var lastPinToken: Int
    /// 직전 리포트의 스크롤 위치 — **위로 움직였는지** 판정한다.
    /// 트랙패드·마우스 휠·스크롤바·키보드 모두 여기로 잡힌다.
    private var lastOffsetY: CGFloat?
    /// 사용자가 위로 스크롤하는 순간 예약된 재고정(0.02s/0.14s)을 취소한다.
    private var pinCancelled = false
    /// "처음 열 때 바닥" — 내용 높이가 나중에 확정돼도(framedDidChange) 끝까지 붙인다.
    /// 문서 높이가 0인 채로 핀하면 맨 위에 남기 때문(2026-11-05 오프스크린 실측).
    private var awaitingInitialPin = true
    /// 초기 핀이 늦게 확정되는 레이아웃을 따라가기 위한 짧은 타이머(최대 4초).
    private var settleTimer: Timer?

    init(bottomToken: Int, onChange: @escaping (CGFloat, Bool) -> Void) {
      // -1 로 시작해 첫 update 에서 한 번 붙인다 — onAppear 핀을 놓치지 않게.
      self.lastPinToken = -1
      self.onChange = onChange
      super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
      settleTimer?.invalidate()
      tokens.forEach(NotificationCenter.default.removeObserver)
    }

    override func viewDidMoveToWindow() {
      super.viewDidMoveToWindow()
      attach(attempt: 0)
    }

    /// 배경 뷰가 클릭·스크롤을 가로채지 않게
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// 내용 높이가 늦게 확정되는 경우(대화 복원·큰 도구 카드)를 위해 잠깐만 반복해서 맞춘다.
    private func startSettle() {
      guard awaitingInitialPin, settleTimer == nil else { return }
      var ticks = 0
      let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] t in
        guard let self else { t.invalidate(); return }
        ticks += 1
        if !self.awaitingInitialPin || self.pinCancelled || ticks > 26 {
          self.stopSettle()
          return
        }
        self.pin(attempt: 0)
      }
      RunLoop.main.add(timer, forMode: .common)
      settleTimer = timer
    }

    private func stopSettle() {
      settleTimer?.invalidate()
      settleTimer = nil
    }

    /// 문서 끝으로 이동한다. 내용 높이는 한 프레임 늦게 확정되므로 몇 번 더 맞춘다.
    func pinIfNeeded(token: Int) {
      guard token != lastPinToken else { return }
      lastPinToken = token
      pinCancelled = false
      awaitingInitialPin = true
      pin(attempt: 0)
      startSettle()
    }

    private func pin(attempt: Int) {
      guard !pinCancelled else { return }
      // 아직 스크롤 뷰 계층에 붙기 전이면 곧바로 포기하지 말고 다시 시도한다.
      // (오프스크린 렌더·창 생성 직후에는 `enclosingScrollView` 가 nil 이다)
      guard let scroll = enclosingScrollView, let document = scroll.documentView else {
        guard attempt < 6 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
          self?.pin(attempt: attempt + 1)
        }
        return
      }
      scroll.layoutSubtreeIfNeeded()
      // `scrollToEndOfDocument:` 는 SwiftUI 의 스크롤 뷰가 응답하지 않는다(예외로 죽는다).
      // 문서 높이에서 뷰포트 높이를 뺀 위치로 **직접** 옮긴다.
      let clip = scroll.contentView
      let maxY = max(0, document.frame.height - clip.bounds.height)
      let targetY = document.isFlipped ? maxY : 0
      let proposed = NSRect(x: clip.bounds.origin.x, y: targetY,
                            width: clip.bounds.width, height: clip.bounds.height)
      clip.scroll(to: clip.constrainBoundsRect(proposed).origin)
      scroll.reflectScrolledClipView(clip)
      // 높이가 확정된 뒤의 핀이라면 초기 핀은 끝난 것.
      if maxY > 0 {
        awaitingInitialPin = false
        stopSettle()
      }
      // 0.02s · 0.14s — 도구 카드·마크다운이 높이를 확정한 뒤 한 번 더.
      guard attempt < 2 else { return }
      DispatchQueue.main.asyncAfter(deadline: .now() + (attempt == 0 ? 0.02 : 0.14)) { [weak self] in
        self?.pin(attempt: attempt + 1)
      }
    }

    private func attach(attempt: Int) {
      tokens.forEach(NotificationCenter.default.removeObserver)
      tokens.removeAll()
      guard let scroll = enclosingScrollView else {
        // 창에 붙는 첫 순간에는 아직 상위 스크롤 뷰가 없을 수 있다 — 잠시 뒤 다시.
        guard attempt < 10 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
          self?.attach(attempt: attempt + 1)
        }
        return
      }
      scroll.contentView.postsBoundsChangedNotifications = true
      scroll.documentView?.postsFrameChangedNotifications = true
      let center = NotificationCenter.default
      tokens.append(center.addObserver(forName: NSView.boundsDidChangeNotification,
                                       object: scroll.contentView, queue: .main) { [weak self] _ in
        self?.report()
      })
      tokens.append(center.addObserver(forName: NSView.frameDidChangeNotification,
                                       object: scroll.documentView, queue: .main) { [weak self] _ in
        self?.report()
      })
      // 레이아웃이 확정된 뒤 첫 값 — 창을 열 때 버튼이 잠깐 잘못 뜨는 것을 막는다.
      DispatchQueue.main.async { [weak self] in self?.report() }
      startSettle()
    }

    private func report() {
      guard let scroll = enclosingScrollView, let document = scroll.documentView else { return }
      let offsetY = scroll.contentView.bounds.origin.y
      // flipped 좌표계에서 위로 스크롤 = offsetY 감소.
      let scrolledUp = lastOffsetY.map { offsetY < $0 - 0.5 } ?? false
      lastOffsetY = offsetY
      if scrolledUp {
        // 사용자가 직접 올렸다 — 초기 핀도 포기한다(열자마자 읽으려는 걸 방해하지 않게).
        pinCancelled = true
        awaitingInitialPin = false
        stopSettle()
      }
      let distance = ScrollMetrics.distanceFromBottom(
        documentHeight: document.frame.height,
        offsetY: offsetY,
        viewportHeight: scroll.contentView.bounds.height)
      // 처음 열 때는 내용 높이가 나중에 확정된다 — 그때까지 바닥으로 붙인다.
      if awaitingInitialPin, !pinCancelled, distance > 1, document.frame.height > 0 {
        pin(attempt: 0)
      }
      onChange(distance, scrolledUp)
    }
  }
}
