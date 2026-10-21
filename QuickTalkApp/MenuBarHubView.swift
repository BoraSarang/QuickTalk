import SwiftUI

// MARK: - Hub 치수 (단일 출처) — View frame + 패딩 = popover contentSize
enum HubMetrics {
  static let contentWidth: CGFloat = 340
  static let contentHeight: CGFloat = 492
  static let padding: CGFloat = 10
  static var popoverSize: NSSize {
    NSSize(width: contentWidth + padding * 2, height: contentHeight + padding * 2)
  }
}

// MARK: - Hub 액션 (AppDelegate가 팝오버를 닫은 뒤 수행)

enum HubMenuAction {
  case newConversation
  case openArchive
  case continueConversation
  case openSettings
  case toggleVoice
  case stopSpeaking
  case about
  case terminate
}

/// 메뉴바 좌클릭 Hub — ApexKey MenuHubView 준용 (실행/설정 2탭 팝오버).
/// 실행 탭 = 주 액션 + 기능 행 + 최근 대화, 설정 탭 = 기본 설정 + "모든 설정 열기".
struct QuickTalkHubView: View {
  @EnvironmentObject var store: UIStore
  @State private var tab: HubTab = .run
  /// QA용: 처음 열 때 선택할 탭
  var initialTab: HubTab = .run

  /// AppDelegate가 주입하는 단일 디스패치 (닫기 + 실행 보장)
  var onAction: (HubMenuAction) -> Void = { _ in }

  enum HubTab: String, CaseIterable {
    case run, settings
    var label: String { self == .run ? L("실행") : L("설정") }
  }

  private var shortcutLabel: String { ShortcutCombo.display(store.settings.globalShortcut) }

  private var hasConversation: Bool { !store.conversation.turns.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        Group {
          switch tab {
          case .run: runTab
          case .settings: settingsTab
          }
        }
        .frame(maxWidth: .infinity, alignment: .top)
      }
      Divider()
      footer
    }
    .frame(width: HubMetrics.contentWidth, height: HubMetrics.contentHeight)
    .background(Color(nsColor: .windowBackgroundColor))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, HubMetrics.padding)
    .padding(.vertical, HubMetrics.padding)
    .onAppear { tab = initialTab }
  }

  // MARK: - 헤더 + 탭

  private var header: some View {
    HStack(spacing: 8) {
      // 앱 아이콘(에셋 카탈로그 AppIcon) — 없으면 SF Symbol 배지로 대체
      if let icon = NSImage(named: "AppIcon") {
        Image(nsImage: icon)
          .resizable()
          .frame(width: 22, height: 22)
      } else {
        Image(systemName: "bubble.left.and.text.bubble.right")
          .font(.system(size: 12, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 22, height: 22)
          .background(Color.accentColor.gradient)
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      Text("QuickTalk").font(.system(size: 14, weight: .bold))
      Spacer()
      HStack(spacing: 2) {
        ForEach(HubTab.allCases, id: \.rawValue) { t in
          let isOn = tab == t
          Text(t.label)
            .font(.system(size: 12, weight: isOn ? .semibold : .medium))
            .foregroundStyle(isOn ? Color.white : Color.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isOn ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.15)) { tab = t } }
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  // MARK: - 실행 탭

  private var runTab: some View {
    VStack(spacing: 6) {
      heroButton
      hubRow(icon: "archivebox", title: L("보관함"), sub: Lf("대화 기록 %d개 · 검색·삭제", store.archive.count), combo: nil) {
        onAction(.openArchive)
      }
      hubRow(icon: "mic", title: store.voiceRecording ? L("음성 입력 중지") : L("음성 입력"),
             sub: Lf("엔진: %@", store.settings.voiceEngine.rawValue), combo: nil) {
        onAction(.toggleVoice)
      }
      if store.isSpeaking {
        hubRow(icon: "stop.fill", title: L("읽어주기 중지"), sub: L("지금 읽고 있는 답변을 멈춥니다"), combo: nil) {
          onAction(.stopSpeaking)
        }
      }
      hubRow(icon: "brain", title: Lf("AI: %@", store.settings.activeProvider?.displayName ?? L("없음")),
             sub: Lf("프로바이더 %d개 등록", store.settings.providers.count), combo: nil) {
        onAction(.openSettings)
      }
      hubRow(icon: "gearshape", title: L("모든 설정"), sub: L("일반·단축키·AI·음성·보관함"), combo: nil) {
        onAction(.openSettings)
      }
      latestRow
    }
    .padding(.top, 10)
    .padding(.bottom, 6)
  }

  /// 주 액션 — 새 대화 (단축키 표시)
  private var heroButton: some View {
    Button { onAction(.newConversation) } label: {
      HStack(spacing: 10) {
        Image(systemName: "square.and.pencil")
          .font(.system(size: 14, weight: .bold))
          .foregroundStyle(.white)
          .frame(width: 26, height: 26)
          .background(Color.white.opacity(0.22))
          .clipShape(RoundedRectangle(cornerRadius: 7))
        VStack(alignment: .leading, spacing: 1) {
          Text(L("새 대화"))
            .font(.system(size: 13.5, weight: .bold))
            .foregroundStyle(.white)
          Text(L("가운데 창으로 열고 바로 질문"))
            .font(.system(size: 11))
            .foregroundStyle(.white.opacity(0.85))
            .lineLimit(2)
        }
        Spacer(minLength: 4)
        Text(shortcutLabel)
          .font(.system(size: 11, weight: .semibold, design: .monospaced))
          .foregroundStyle(.white)
          .padding(.horizontal, 7).padding(.vertical, 4)
          .background(Color.white.opacity(0.2))
          .clipShape(RoundedRectangle(cornerRadius: 6))
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 9)
      .background(
        RoundedRectangle(cornerRadius: 12)
          .fill(Color.accentColor.gradient)
          .overlay(
            RoundedRectangle(cornerRadius: 12)
              .stroke(Color.white.opacity(0.18), lineWidth: 1)
          )
      )
      .contentShape(RoundedRectangle(cornerRadius: 12))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, 12)
  }

  private func hubRow(icon: String, title: String, sub: String, combo: String?, _ action: @escaping () -> Void) -> some View {
    HubRowButton(icon: icon, title: title, sub: sub, combo: combo, action: action)
      .padding(.horizontal, 12)
  }

  // MARK: - 최근 대화 한 줄

  private var latestRow: some View {
    let latest = store.archive.first
    return HStack(spacing: 8) {
      Circle()
        .fill(latest == nil && !hasConversation ? Color.secondary.opacity(0.4) : Color.green)
        .frame(width: 6, height: 6)
      if let c = latest {
        (Text(L("최근 — ")).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.secondary)
         + Text(c.displayTitle).font(.system(size: 12.5, weight: .semibold)))
          .lineLimit(1).truncationMode(.tail)
        Spacer()
        Button { onAction(.continueConversation) } label: {
          Image(systemName: "arrow.uturn.forward")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 24, height: 24)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(L("최근 대화 이어서 열기"))
      } else if hasConversation {
        Text(Lf("진행 중 대화 %d턴", store.conversation.turns.count)).font(.system(size: 12.5)).foregroundStyle(.secondary)
        Spacer()
        Button { onAction(.continueConversation) } label: {
          Image(systemName: "arrow.uturn.forward")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .frame(width: 24, height: 24)
            .background(Color.accentColor.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
      } else {
        Text(L("아직 대화가 없습니다")).font(.system(size: 12)).foregroundStyle(.secondary)
        Spacer()
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(Color.primary.opacity(0.05))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, 12)
  }

  // MARK: - 설정 탭 (기본 설정) — 대화 창 설정 탭과 완전히 동일한 공유 뷰

  private var settingsTab: some View {
    QuickSettingsCardsView(onOpenSettings: { onAction(.openSettings) })
      .padding(.top, 10)
      .padding(.bottom, 4)
  }

  // MARK: - 푸터

  private var footer: some View {
    HStack(spacing: 8) {
      Text("QuickTalk v\(Bundle.main.appVersion)")
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary.opacity(0.8))
      Spacer()
      footerTap(L("모든 설정")) { onAction(.openSettings) }
      footerTap(L("정보")) { onAction(.about) }
      footerTap(L("종료")) { onAction(.terminate) }
    }
    .padding(.horizontal, 14)
    .padding(.vertical, 7)
  }

  private func footerTap(_ title: String, _ action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
    }
    .buttonStyle(.plain)
  }
}

// MARK: - 빠른 설정 카드 (메뉴바 Hub 설정 탭 == 대화 창 설정 탭)

/// 두 화면이 어긋나지 않도록 한 곳에서만 정의한다.
/// 폭이 다른 두 곳(Hub 340 / 대화 창 460)에서 쓰이므로 가로 패딩만 주입받는다.
struct QuickSettingsCardsView: View {
  @EnvironmentObject var store: UIStore
  /// "모든 설정 열기" 동작 — Hub는 팝오버를 닫고, 대화 창은 전면 설정 창을 띄운다.
  var onOpenSettings: () -> Void
  var horizontalPadding: CGFloat = 12
  /// 모델 목록 펼침 상태 (custom 드롭다운 — 네이티브 팝업을 쓰지 않는다)
  @State private var modelExpanded = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      openAllCard

      activeAICard
      modelCard
      statusCard

      hintRow
    }
  }

  // MARK: 카드

  private var openAllCard: some View {
    Button(action: onOpenSettings) {
      HStack(spacing: 11) {
        Image(systemName: "gearshape")
          .font(.system(size: 13, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 24, height: 24)
          .background(Color.accentColor.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 7))
        VStack(alignment: .leading, spacing: 2) {
          Text(L("모든 설정 열기")).font(.system(size: 13, weight: .semibold))
          Text(L("일반·단축키·AI·음성·보관함·정보")).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
        Spacer()
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(.secondary)
      }
      .padding(11)
      .background(Color(nsColor: .controlBackgroundColor))
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .overlay(
        RoundedRectangle(cornerRadius: 11).stroke(Color.primary.opacity(0.12), lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
    .padding(.horizontal, horizontalPadding)
  }

  private var activeAICard: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(L("활성 AI")).font(.system(size: 12.5, weight: .medium))
        Spacer()
        Text(Lf("%d개 등록됨", store.settings.providers.filter { $0.enabled }.count))
          .font(.system(size: 11)).foregroundStyle(.secondary)
      }
      if store.settings.providers.contains(where: { $0.enabled }) {
        ForEach(store.settings.providers.filter { $0.enabled }) { p in
          providerRow(p)
        }
      } else {
        Text(L("사용 가능한 프로바이더가 없습니다 — 설정 > AI에서 추가하세요"))
          .font(.system(size: 11.5)).foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, horizontalPadding)
  }

  /// 프로바이더 선택 행 — 추가/삭제 없이 **선택만** 한다(편집은 전면 설정 창).
  private func providerRow(_ p: LLMProviderConfig) -> some View {
    let isOn = store.settings.activeProviderID == p.id
    return Button { store.setActiveProvider(p.id) } label: {
      HStack(spacing: 8) {
        Image(systemName: p.type.iconName)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
          .frame(width: 20, height: 20)
          .background((isOn ? Color.accentColor : Color.primary).opacity(isOn ? 0.15 : 0.07))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        Text(p.displayName).font(.system(size: 12.5, weight: isOn ? .semibold : .regular))
          .lineLimit(1).truncationMode(.tail)
        Text(providerSub(p)).font(.system(size: 11)).foregroundStyle(.secondary)
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 4)
        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 12))
          .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
      }
      .padding(.horizontal, 7).padding(.vertical, 4)
      .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .contentShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
    .help(isOn ? L("사용 중") : L("이 프로바이더로 전환"))
  }

  /// 한 줄 요약 — 주소·모델·키 상태 (키 본문은 표시하지 않는다)
  private func providerSub(_ p: LLMProviderConfig) -> String {
    switch p.type {
    case .appleFM: return L("· 온디바이스")
    case .ollama: return "· \(shortHost(p.baseURL))"
    case .openAICompatible:
      let key = p.secretID.isEmpty ? L("키 미저장")
        : (SecretStore.has(account: p.secretID) ? L("키 저장됨") : L("키 미저장"))
      return "· \(shortHost(p.baseURL)) · \(key)"
    }
  }

  private func shortHost(_ url: String) -> String {
    url.replacingOccurrences(of: "http://", with: "")
       .replacingOccurrences(of: "https://", with: "")
       .replacingOccurrences(of: "/v1", with: "")
  }

  // MARK: 모델 (선택만 · 목록 조회는 ⟳ 를 눌렀을 때만)

  private var modelCard: some View {
    let p = store.settings.activeProvider
    let locked = p?.type == .appleFM
    return VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Text(L("모델")).font(.system(size: 12.5, weight: .medium))
        Spacer()
        if let note = store.modelNote {
          Text(note).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      HStack(spacing: 8) {
        if locked {
          Text(L("온디바이스 모델 (자동)")).font(.system(size: 12.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
          Text(L("변경 불가")).font(.system(size: 11)).foregroundStyle(.secondary)
        } else if let p {
          // custom 프로필: 네이티브 팝업 대신 자체 카드 스타일로 그린 드롭다운(가로 꽉 채움).
          modelPicker(current: p.model, options: store.activeModelChoices)
          Button { store.refreshModels() } label: {
            if store.loadingModels {
              ProgressView().controlSize(.small).frame(width: 20, height: 20)
            } else {
              Image(systemName: "arrow.clockwise")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 20, height: 20)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
          }
          .buttonStyle(.plain)
          .help(L("설치된/서버 모델 목록 다시 읽기"))
        } else {
          Text(L("활성 AI 없음")).font(.system(size: 12.5)).foregroundStyle(.secondary)
        }
      }
      // 선택한 AI·모델이 실제로 응답하는지 ping 1건으로 확인한다(전면 설정의 '연결 테스트'와 동일)
      HStack(spacing: 8) {
        Button { store.testActiveProvider() } label: {
          HStack(spacing: 5) {
            if store.testingProvider {
              ProgressView().controlSize(.small).scaleEffect(0.7)
            } else {
              Image(systemName: "bolt.horizontal").font(.system(size: 10, weight: .semibold))
            }
            Text(store.testingProvider ? L("테스트 중…") : L("연결 테스트"))
              .font(.system(size: 11, weight: .medium))
          }
          .padding(.horizontal, 9).padding(.vertical, 4)
          .background(Color.accentColor.opacity(0.12))
          .foregroundStyle(Color.accentColor)
          .clipShape(Capsule())
          .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(store.testingProvider || store.settings.activeProvider == nil)
        .help(L("선택한 AI·모델로 ping을 보내 응답을 확인합니다"))
        if let note = store.providerTestResult {
          Text(note)
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(2).textSelection(.enabled)
            .help(note)
        }
        Spacer(minLength: 0)
      }
      Text(modelCaption(p, locked: locked))
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, horizontalPadding)
  }

  private func modelCaption(_ p: LLMProviderConfig?, locked: Bool) -> String {
    if locked { return L("Apple FM은 시스템 모델을 쓰므로 고를 모델이 없습니다.") }
    guard let p else { return L("설정 > AI에서 프로바이더를 등록하세요.") }
    return Lf("%@ 목록은 새로고침 버튼을 누를 때만 읽습니다. 바꾸면 다음 질문부터 적용됩니다.",
              p.type == .ollama ? L("설치된 모델") : L("서버 모델"))
  }

  /// custom 드롭다운 — 현재 모델 행을 누르면 아래로 목록이 펼쳐진다(자체 카드 스타일, 가로 꽉 채움).
  @ViewBuilder
  private func modelPicker(current: String, options: [String]) -> some View {
    let selected = current.isEmpty ? L("모델 미지정") : current
    VStack(alignment: .leading, spacing: 4) {
      Button {
        withAnimation(.easeInOut(duration: 0.12)) { modelExpanded.toggle() }
      } label: {
        HStack(spacing: 8) {
          Text(selected)
            .font(.system(size: 12.5))
            .foregroundStyle(current.isEmpty ? Color.secondary : Color.primary)
            .lineLimit(1).truncationMode(.middle)
          Spacer(minLength: 4)
          Image(systemName: "chevron.down")
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(.secondary)
            .rotationEffect(.degrees(modelExpanded ? 180 : 0))
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay(
          RoundedRectangle(cornerRadius: 7).stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 7))
      }
      .buttonStyle(.plain)
      .help(options.isEmpty ? L("새로고침 버튼으로 모델 목록을 먼저 읽어 오세요") : L("모델 선택"))

      if modelExpanded {
        if options.isEmpty {
          Text(L("선택할 모델이 없습니다 — 새로고침 버튼으로 목록을 읽어 오세요"))
            .font(.system(size: 11)).foregroundStyle(.secondary)
            .padding(.horizontal, 2)
        } else {
          ScrollView {
            VStack(alignment: .leading, spacing: 1) {
              ForEach(options, id: \.self) { m in
                modelRow(m, isOn: m == current)
              }
            }
          }
          .frame(maxHeight: 112)
        }
      }
    }
  }

  /// 모델 행 — 프로바이더 행과 같은 라디오 스타일(선택만)
  private func modelRow(_ model: String, isOn: Bool) -> some View {
    Button { store.setActiveModel(model); withAnimation(.easeInOut(duration: 0.12)) { modelExpanded = false } } label: {
      HStack(spacing: 8) {
        Image(systemName: isOn ? "largecircle.fill.circle" : "circle")
          .font(.system(size: 11))
          .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.5))
        Text(model).font(.system(size: 12, weight: isOn ? .semibold : .regular))
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 4)
      }
      .padding(.horizontal, 7).padding(.vertical, 3)
      .background(isOn ? Color.accentColor.opacity(0.12) : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 7))
      .contentShape(RoundedRectangle(cornerRadius: 7))
    }
    .buttonStyle(.plain)
  }

  // MARK: 상태 (읽기 전용)

  private var statusCard: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text(L("상태")).font(.system(size: 12.5, weight: .medium))
        Spacer()
        Text(L("읽기 전용")).font(.system(size: 11)).foregroundStyle(.secondary)
      }
      statusRow(L("AI 연결"), store.aiStatusText, ok: store.aiStatusOK,
                neutral: store.lastAICall == .none)
      // 실패했을 때만 정확한 원인을 한 줄 덧붙인다 — 예: `연결 거부 (-1004)` / `HTTP 401 · E-AND-AUTH-0004`
      if case .failed = store.lastAICall,
         let detail = store.lastAIErrorDetail, !detail.isEmpty {
        Text(detail)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
          .textSelection(.enabled)
      }
      statusRow(L("호출 단축키"), store.shortcutStatusOK ? L("동작 중") : L("실패"),
                ok: store.shortcutStatusOK, neutral: false,
                detail: ShortcutCombo.display(store.settings.globalShortcut))
      statusRow(L("음성"), store.voiceStatusText, ok: store.voiceStatusOK,
                neutral: !store.voiceStatusOK)
      Text(L("값 변경은 '모든 설정 열기'에서 합니다. 여기서 바꾸는 건 활성 AI·모델뿐입니다."))
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 12).padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.7))
    .clipShape(RoundedRectangle(cornerRadius: 10))
    .overlay(
      RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.12), lineWidth: 1)
    )
    .padding(.horizontal, horizontalPadding)
  }

  private func statusRow(_ label: String, _ value: String, ok: Bool,
                         neutral: Bool, detail: String? = nil) -> some View {
    HStack(spacing: 6) {
      Text(label).font(.system(size: 12)).foregroundStyle(.secondary)
      Spacer(minLength: 6)
      if let detail, !detail.isEmpty {
        Text(detail).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
      }
      Text(value)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundStyle(neutral ? Color.secondary : (ok ? Color.green : Color.red))
    }
  }

  private var hintRow: some View {
    HStack(alignment: .top, spacing: 8) {
      Image(systemName: "info.circle")
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(store.visibilityHint)
        .font(.system(size: 12)).foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, horizontalPadding + 2)
    // 마지막 카드 아래 여백을 줄인다 — 짧은 설정 화면에서 창 바닥과 붙어 보이게.
    .padding(.top, 2)
  }
}

// MARK: - Hub 행 (hover 강조 + 키캡)

private struct HubRowButton: View {
  let icon: String
  let title: String
  let sub: String
  let combo: String?
  let action: () -> Void
  @State private var hovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 10) {
        Image(systemName: icon)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(Color.accentColor)
          .frame(width: 22, height: 22)
          .background(Color.accentColor.opacity(0.15))
          .clipShape(RoundedRectangle(cornerRadius: 6))
        VStack(alignment: .leading, spacing: 1) {
          Text(title).font(.system(size: 12.5, weight: .semibold))
          Text(sub).font(.system(size: 11)).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.tail)
        }
        Spacer(minLength: 2)
        if let combo, !combo.isEmpty {
          Text(combo)
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color.primary.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
      }
      .padding(.horizontal, 9)
      .padding(.vertical, 7)
      .background(Color(nsColor: .controlBackgroundColor).opacity(hovering ? 1 : 0.55))
      .clipShape(RoundedRectangle(cornerRadius: 11))
      .overlay(
        RoundedRectangle(cornerRadius: 11)
          .stroke(hovering ? Color.accentColor.opacity(0.6) : Color.primary.opacity(0.12), lineWidth: 1)
      )
      .contentShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
    .onHover { hovering = $0 }
  }
}
