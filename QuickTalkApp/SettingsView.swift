import SwiftUI

// MARK: - 설정 탭 정의 (ApexKey SettingsTabs 준용)

enum QuickTalkSettingsTab: String, CaseIterable, Identifiable {
  case general, shortcut, shelf, ai, voice, archive, about

  var id: String { rawValue }

  var title: String {
    switch self {
    case .general: return L("일반")
    case .shortcut: return L("단축키")
    case .shelf: return L("퀵셸프")
    case .ai: return "AI"
    case .voice: return L("음성")
    case .archive: return L("보관함")
    case .about: return L("정보")
    }
  }

  var iconName: String {
    switch self {
    case .general: return "gearshape"
    case .shortcut: return "keyboard"
    case .shelf: return "sidebar.right"
    case .ai: return "brain"
    case .voice: return "mic"
    case .archive: return "archivebox"
    case .about: return "info.circle"
    }
  }

  /// 도움말 카드 3줄 — 뭐고 / 언제 / 이렇게
  var help: (what: String, when: String, how: String) {
    switch self {
    case .general:
      return (L("QuickTalk의 표시 방식과 실행 동작을 정합니다."),
              L("메뉴바·Dock 노출이나 새 창 동작이 마음에 안 들 때."),
              L("토글을 끄면 즉시 반영됩니다. 메뉴바를 끄면 Dock 아이콘이 자동으로 켜집니다."))
    case .shortcut:
      return (L("대화 열기·퀵셸프·캡처까지, 앱이 쓰는 전역 단축키입니다."),
              L("다른 앱 작업 중 바로 부르거나 캡처할 때."),
              L("'변경'을 누르고 원하는 조합을 누르면 즉시 등록됩니다. 앱에 포커스가 없어도 동작합니다."))
    case .shelf:
      return (L("단축키나 헤더 버튼으로 여는 퀵셸프(클립보드·파일·캡처) 허브 설정입니다."),
              L("복사한 내용·파일·화면 캡처를 대화에 붙일 때."),
              L("대화 창이 열려 있으면 창 안에, 닫혀 있으면 화면 오른쪽에 뜹니다. 캡처는 화면 기록 권한이 필요합니다(허용 후 앱 재실행)."))
    case .ai:
      return (L("답변을 만들 AI 프로바이더 목록입니다. 기본 3종이 들어 있고 계속 추가할 수 있습니다."),
              L("로컬/원격 모델을 바꾸거나 새 서버를 붙일 때."),
              L("활성 프로바이더를 고르고, 원격이면 주소·키를 저장한 뒤 '연결 테스트'로 확인하세요."))
    case .voice:
      return (L("음성 입력(받아쓰기)과 답변 읽어주기 엔진을 정합니다."),
              L("마이크로 질문하거나 답변을 소리로 들을 때."),
              L("Apple은 즉시 동작하고, Whisper는 로컬 모델, Edge TTS는 온라인, Piper는 로컬 모델로 읽습니다."))
    case .archive:
      return (L("모든 대화를 자동 저장하고 정리하는 정책입니다."),
              L("오래된 대화를 자동 정리하거나 기록을 비우고 싶을 때."),
              L("보관일수를 조정하거나 기록을 한 번에 지울 수 있습니다. 🔖 보관한 대화는 남습니다."))
    case .about:
      return (L("빌드 정보와 저장 위치를 확인합니다."),
              L("버전 확인이나 문제 신고 전 점검이 필요할 때."),
              L("아래 경로를 복사해 로그·설정을 함께 첨부하면 빠르게 확인됩니다."))
    }
  }
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
      ForEach(QuickTalkSettingsTab.allCases) { t in
        Button {
          tab = t
        } label: {
          HStack(spacing: 8) {
            Image(systemName: t.iconName)
              .font(.system(size: 13))
              .frame(width: 20)
            Text(t.title).font(.body)
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
      Spacer()
      Text("QuickTalk v\(Bundle.main.appVersion)")
        .font(.caption)
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
    }
    .padding(10)
    .frame(width: 190)
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
        case .shortcut: shortcutSection
        case .shelf: shelfSection
        case .ai: aiSection
        case .voice: voiceSection
        case .archive: archiveSection
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
