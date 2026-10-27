import SwiftUI

// MARK: - 설정 탭 정의 (ApexKey SettingsTabs 준용)

// 2026-10-27 재구성 — "이게 여기가 맞나?" 지적을 반영해 **기능 단위**로 나눴다.
//   · AI      = 답변을 만드는 것(프로바이더)만
//   · 검색    = 웹 검색(공급자·키·비용)
//   · 대화    = 창 연결·창 동작·기억·보관
//   · 도구·권한 = 컴퓨터 접근 권한·규칙·기록
// 탭이 9개라 낱개로 늘어놓으면 찾기 어려워 사이드바를 3묶음으로 나눈다.
enum QuickTalkSettingsTab: String, CaseIterable, Identifiable {
  case general, conversation, shortcut, ai, search, tools, voice, shelf, about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return L("일반")
    case .conversation: return L("대화")
    case .shortcut: return L("단축키")
    case .ai: return "AI"
    case .search: return L("검색")
    case .tools: return L("도구·권한")
    case .voice: return L("음성")
    case .shelf: return L("퀵셸프")
    case .about: return L("정보")
    }
  }

  var iconName: String {
    switch self {
    case .general: return "gearshape"
    case .conversation: return "bubble.left.and.bubble.right"
    case .shortcut: return "keyboard"
    case .ai: return "brain"
    case .search: return "globe"
    case .tools: return "hammer"
    case .voice: return "mic"
    case .shelf: return "sidebar.right"
    case .about: return "info.circle"
    }
  }

  /// 도움말 카드 3줄 — 뭐고 / 언제 / 이렇게
  var help: (what: String, when: String, how: String) {
    switch self {
    case .general:
      return (L("언어·테마와 메뉴바/Dock 노출, 로그인 시 시작을 정합니다."),
              L("앱을 어떻게 띄우고 보일지 바꿀 때."),
              L("토글은 즉시 반영됩니다. 메뉴바와 Dock 아이콘 중 최소 하나는 켜져 있습니다."))
    case .conversation:
      return (L("대화 창의 동작과 기억, 보관 정책을 정합니다."),
              L("창을 붙이거나, 기억을 정리하고 오래된 대화를 보관할 때."),
              L("창 연결에는 화면 기록·손쉬운 사용 권한이 필요합니다(도구·권한 › 시스템 권한)."))
    case .shortcut:
      return (L("대화 열기·퀵셸프·캡처까지, 앱이 쓰는 전역 단축키입니다."),
              L("다른 앱 작업 중 바로 부르거나 캡처할 때."),
              L("'변경'을 누르고 원하는 조합을 누르면 즉시 등록됩니다. 앱에 포커스가 없어도 동작합니다."))
    case .ai:
      return (L("답변을 만들 AI와 실패할 때 쓸 예비 AI를 고릅니다."),
              L("모델·서버를 바꾸거나 새 프로바이더를 붙일 때."),
              L("활성 프로바이더를 고르고, 원격이면 주소·키를 저장한 뒤 연결 테스트로 확인하세요."))
    case .search:
      return (L("웹 검색 공급자와 답변 방식을 정합니다."),
              L("최신 정보가 필요한 답변의 품질이나 비용을 조정할 때."),
              L("Exa 키를 저장하고 검색 테스트로 확인하세요. 도구가 켜져 있으면 모델이 필요할 때 직접 검색합니다."))
    case .tools:
      return (L("도우미가 컴퓨터를 확인·실행할 때의 권한과 기록입니다."),
              L("읽기·쓰기·실행을 어디까지 허용할지 정할 때."),
              L("전역 권한을 먼저 정하고, 예외만 항상 허용 규칙에 추가하세요. 위험한 명령은 규칙 테스터로 미리 확인합니다."))
    case .voice:
      return (L("음성 입력(받아쓰기)과 답변 읽어주기 엔진을 정합니다."),
              L("마이크로 질문하거나 답변을 소리로 들을 때."),
              L("Apple은 즉시 동작하고, Whisper는 로컬 모델, Edge TTS는 온라인, Piper는 로컬 모델로 읽습니다."))
    case .shelf:
      return (L("화면 가장자리 퀵셸프(클립보드·파일·캡처) 설정입니다."),
              L("캡처를 대화에 붙이거나 저장 정책을 볼 때."),
              L("패널·캡처 단축키는 단축키 탭에서 바꿉니다. 캡처에는 화면 기록 권한이 필요합니다."))
    case .about:
      return (L("빌드 정보와 저장 위치, 진단 상태입니다."),
              L("버전 확인이나 문제 신고 전 점검이 필요할 때."),
              L("아래 경로를 복사해 로그와 함께 첨부하면 빠르게 확인됩니다."))
    }
  }
}

/// 사이드바 묶음 — 탭이 9개라 한 줄로 늘어놓으면 찾기 어렵다.
private struct SettingsSidebarGroup: Identifiable {
  let title: String
  let tabs: [QuickTalkSettingsTab]
  var id: String { title }
}

// MARK: - 도움말 카드 (뭐고·언제·이렇게)

struct SettingsHelpCard: View {
  let tab: QuickTalkSettingsTab

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      row(icon: "questionmark.circle", text: tab.help.what, accent: false)
      row(icon: "clock", text: tab.help.when, accent: false)
      row(icon: "hand.point.up", text: tab.help.how, accent: true)
    }
    .padding(12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color.accentColor.opacity(0.07))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .padding(.bottom, 4)
  }

  private func row(icon: String, text: String, accent: Bool) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 12))
        .foregroundColor(accent ? Color.accentColor : Color.secondary)
        .frame(width: 16)
        .padding(.top, 1)
      Text(text)
        .font(.callout)
        .foregroundColor(accent ? Color.primary : Color.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
  }
}

// MARK: - 설정 창

struct SettingsView: View {
  @EnvironmentObject var store: UIStore
  @State private var tab: QuickTalkSettingsTab = .general
  @State var editingProvider: LLMProviderConfig?
  @State var editingIsNew = false
  /// "기록 모두 지우기" 확인 시트
  @State var showClearArchiveConfirm = false
  /// 대화 기억 요약 보기/편집 시트
  @State var showMemory = false
  /// 공통 메모리 편집 시트
  @State var editingMemory: GlobalMemoryEntry?
  @State var memoryIsNew = false
  @State var memorySearch = ""
  @State var showWhisperPicker = false
  @State var showPiperPicker = false
  @State var showWhisperFolderPicker = false
  /// 어느 백엔드의 모델을 고르는 중인가(파일 선택 패널이 파일/폴더로 갈린다)
  @State var whisperPickKind: WhisperModel.Kind = .ggml
  /// QA·딥링크용: 처음 열 때 선택할 탭
  var initialTab: QuickTalkSettingsTab = .general
  /// 단축키 녹화 중인 동작(설정 창)
  @State var recordingShortcut: ShortcutAction?
  /// 녹화 안내(중복·보조 키 필요 등)
  @State var recordHint: String?
  /// 녹화 중 로컬 키 모니터
  @State var recordMonitor: Any?
  /// 도우미 도구 — 허용 규칙 입력용(설정 › 도구)
  @State var newAgentRule: String = ""
  /// 도우미 도구 — 실행 기록 펼치기
  @State var showAgentAudit = false
  /// 규칙 테스터 — 판정을 미리 확인할 명령(v0.22). 실행하지는 않는다.
  @State var agentRuleProbe: String = ""
  /// 로그인 시 자동 시작 — 시스템 로그인 항목 상태(설정 JSON 에는 저장하지 않는다)
  @State var launchAtLogin = LoginItem.isEnabled
  @State var loginItemError: String?

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      Divider()
      detail
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 700, minHeight: 460)
    .onAppear { tab = initialTab }
    .sheet(item: $editingProvider) { p in
      ProviderEditorSheet(provider: p, isNew: editingIsNew)
        .environmentObject(store)
    }
    .sheet(isPresented: $showClearArchiveConfirm) {
      DeleteConfirmSheet(
        heading: L("기록을 모두 지울까요?"),
        target: Lf("대화 %d개", store.archive.count),
        message: L("보관함의 모든 대화가 삭제됩니다. 보관한 대화도 포함되며 되돌릴 수 없습니다."),
        confirmLabel: L("모두 지우기")
      ) {
        store.clearArchive()
      }
    }
  }

  // MARK: - 사이드바

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(sidebarGroups.enumerated()), id: \.offset) { index, group in
        if index > 0 {
          Divider().padding(.horizontal, 8).padding(.vertical, 5)
        }
        Text(group.title)
          .font(.caption2)
          .foregroundColor(.secondary)
          .padding(.horizontal, 10)
          .padding(.bottom, 1)
        ForEach(group.tabs) { t in
          sidebarButton(t)
        }
      }
      Spacer()
      Text("QuickTalk v\(Bundle.main.appVersion)")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
    }
    .padding(10)
    .frame(width: 205)
  }

  /// 사이드바 3묶음 — 앱(기본 동작) / 기능(대화에 쓰는 것) / 기타(정보).
  private var sidebarGroups: [SettingsSidebarGroup] {
    [
      SettingsSidebarGroup(title: L("앱"), tabs: [.general, .conversation, .shortcut]),
      SettingsSidebarGroup(title: L("기능"), tabs: [.ai, .search, .tools, .voice, .shelf]),
      SettingsSidebarGroup(title: L("기타"), tabs: [.about]),
    ]
  }

  private func sidebarButton(_ t: QuickTalkSettingsTab) -> some View {
    Button {
      tab = t
    } label: {
      HStack(spacing: 8) {
        Image(systemName: t.iconName)
          .font(.system(size: 13))
          .frame(width: 20)
        Text(t.title).font(.body)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
        Spacer()
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 7)
      .background(tab == t ? Color.accentColor.opacity(0.14) : Color.clear)
      .foregroundColor(tab == t ? Color.accentColor : Color.primary)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // MARK: - 상세

  @ViewBuilder
  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 10) {
        SettingsHelpCard(tab: tab)
          // L10n은 관찰 대상이 아니다 — 이 카드는 store를 읽지 않아 언어 변경만으로는 다시 그려지지 않는다
          .id(store.settings.language)
        switch tab {
        case .general: generalSection
        case .conversation: conversationSection
        case .shortcut: shortcutSection
        case .ai: aiSection
        case .search: webSearchSection
        case .tools: toolsSection
        case .voice: voiceSection
        case .shelf: shelfSection
        case .about: aboutSection
        }
      }
      .padding(.horizontal, 18)
      .padding(.top, 18)
      // 카드가 짧은 탭에서 창 아래에 남는 빈 공간을 줄인다(기본 창 크기는 유지).
      .padding(.bottom, 10)
    }
  }

  // MARK: - 행 시스템 (라벨 좌 · 컨트롤 우 · 설명 들여쓰기)

  func groupBox<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline).padding(.leading, 12)
      VStack(alignment: .leading, spacing: 6) {
        content()
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }

  func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
      .padding(.leading, 2)
      .fixedSize(horizontal: false, vertical: true)
  }

  func toggleRow(_ label: String, isOn: Binding<Bool>, description: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label).font(.body)
        Spacer()
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
      }
      if let description { caption(description) }
    }
    .padding(.vertical, 2)
  }

  func pickerRow<T: Hashable>(_ label: String, selection: Binding<T>, options: [(T, String)]) -> some View {
    HStack {
      Text(label).font(.body)
      Spacer(minLength: 12)
      Picker("", selection: selection) {
        ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      // 컨트롤을 카드 오른쪽 끝에 붙인다(기본 프레임은 가운데 정렬이라 애매하게 떠 보임)
      .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
    }
    .padding(.vertical, 2)
  }

  /// 표시 토글 바인딩 — 정책(진입점 최소 1개)을 거쳐 저장한다.
  var menuBarIconBinding: Binding<Bool> {
    Binding(get: { store.settings.showMenuBarIcon }, set: { store.setMenuBarIcon($0) })
  }
  var dockIconBinding: Binding<Bool> {
    Binding(get: { store.settings.showDockIcon }, set: { store.setDockIcon($0) })
  }

  func valueRow(_ label: String, _ value: String) -> some View {
    HStack(alignment: .top) {
      Text(label).font(.body)
      Spacer()
      Text(value)
        .font(.callout)
        .foregroundColor(.secondary)
        .textSelection(.enabled)
        .multilineTextAlignment(.trailing)
        .fixedSize(horizontal: false, vertical: true)   // 영어가 길면 잘리지 않고 줄바꿈
        .layoutPriority(1)
    }
    .padding(.vertical, 2)
  }

}

// MARK: - 헬퍼

extension Bundle {
  /// Info.plist 버전 (없으면 "1.0")
  var appVersion: String {
    (object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
  }
}
