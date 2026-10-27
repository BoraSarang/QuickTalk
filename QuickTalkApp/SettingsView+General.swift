import SwiftUI
import AppKit
import Combine

// [REFACTOR] SettingsView — 일반·대화·단축키·퀵셸프 섹션 (2026-10-20 분리, 2026-10-27 재구성)
extension SettingsView {
  // MARK: - 일반

  @ViewBuilder
  var generalSection: some View {
    groupBox(L("언어 · 테마")) {
      pickerRow(L("언어"), selection: $store.settings.language,
                options: AppLanguage.allCases.map { ($0, $0.displayName) })
      caption(L("'시스템 기본'은 macOS 선호 언어를 따릅니다. 바꾸면 즉시 반영됩니다."))
      pickerRow(L("테마"), selection: $store.settings.appearance,
                options: AppAppearance.allCases.map { ($0, $0.displayName) })
      caption(L("'시스템'은 macOS의 라이트/다크 설정을 따릅니다."))
    }
    groupBox(L("표시")) {
      toggleRow(L("메뉴바에 표시"), isOn: menuBarIconBinding,
                description: L("끄면 Dock 아이콘이 자동으로 켜집니다(진입점 최소 1개 유지)."))
      toggleRow(L("Dock에 표시"), isOn: dockIconBinding,
                description: L("끄면 메뉴바 아이콘이 자동으로 켜집니다. 개발 중 확인용으로만 켜세요."))
      caption(store.visibilityHint)
    }
    groupBox(L("시작 및 동작")) {
      toggleRow(L("로그인 시 자동 시작"), isOn: launchAtLoginBinding,
                description: L("Mac 에 로그인하면 QuickTalk 가 메뉴바에서 자동으로 시작됩니다. 시스템 설정 › 일반 › 로그인 항목과 같은 값을 씁니다."))
      if LoginItem.requiresApproval {
        HStack(spacing: 8) {
          Text(L("시스템 설정 › 일반 › 로그인 항목에서 QuickTalk를 허용해 주세요."))
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
          Button(L("시스템 설정 열기")) { LoginItem.openSettings() }
          Spacer()
        }
      }
      if let loginItemError { caption(loginItemError) }
      toggleRow(L("대화 창을 항상 위에"), isOn: $store.settings.alwaysOnTop,
                description: L("다른 앱 위에 고정합니다(대화 창 헤더의 📌와 같습니다). 설정 창은 그 위에 뜹니다. 끄면 일반 창처럼 뒤로 갑니다."))
      valueRow(L("메뉴바 좌클릭"), L("Hub 팝오버 (실행·설정 탭)"))
      valueRow(L("메뉴바 우클릭"), L("컨텍스트 메뉴"))
    }
    // 로그인 항목은 시스템이 단일 출처 — 화면을 열 때·앱이 다시 활성화될 때 실제 상태를 읽는다
    // (사용자가 시스템 설정에서 직접 껐다 켜도 토글이 어긋나지 않게).
    .onAppear { refreshLoginItem() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      refreshLoginItem()
    }
  }

  /// 시스템 상태를 다시 읽어 토글에 반영한다
  func refreshLoginItem() {
    let enabled = LoginItem.isEnabled || LoginItem.requiresApproval
    if launchAtLogin != enabled { launchAtLogin = enabled }
  }

  var launchAtLoginBinding: Binding<Bool> {
    Binding(get: { launchAtLogin }, set: { on in
      let error = LoginItem.setEnabled(on)
      launchAtLogin = LoginItem.isEnabled || LoginItem.requiresApproval
      loginItemError = error.map { Lf("로그인 항목을 바꾸지 못했습니다: %@", $0) }
    })
  }

  // MARK: - 단축키

  @ViewBuilder
  var shortcutSection: some View {
    groupBox(L("전역 단축키")) {
      ForEach(ShortcutAction.allCases, id: \.self) { action in
        shortcutRow(action)
      }
      if let recordHint {
        Text(recordHint)
          .font(.caption)
          .foregroundColor(.accentColor)
          .fixedSize(horizontal: false, vertical: true)
      }
      caption(L("'변경'을 누르고 원하는 키 조합을 누르세요. Esc 취소 · Delete 키 = 기본값."))
      caption(L("앱에 포커스가 없어도 동작합니다(바탕화면·다른 앱 사용 중 포함). 권한 승인은 필요하지 않습니다."))
      caption(L("같은 조합을 다른 앱이 먼저 쓰고 있으면 등록에 실패합니다(⚠️). 그때는 다른 조합을 골라 주세요."))
    }
    .onDisappear { stopRecording() }
    groupBox(L("창 안에서 쓰는 키")) {
      valueRow(L("보내기"), L("Return — 입력창에서 전송"))
      valueRow(L("줄바꿈"), L("Shift+Return"))
      valueRow(L("닫기·취소"), L("Esc — 오버레이·퀵셸프 닫기"))
      valueRow(L("편집"), L("⌘C · ⌘V · ⌘X · ⌘A · ⌘Z · ⌘⇧Z"))
      caption(L("창 안 키는 macOS 편집 규칙을 따르며 바꿀 수 없습니다."))
    }
  }

  /// 단축키 한 줄 — 표시 칩 + 변경/취소 + 기본값
  private func shortcutRow(_ action: ShortcutAction) -> some View {
    let combo = store.settings.shortcut(for: action)
    let failed = store.shortcutStatus[action] == false
    let isRecording = recordingShortcut == action
    return HStack(spacing: 8) {
      VStack(alignment: .leading, spacing: 1) {
        Text(action.title).font(.body)
        Text(action.detail).font(.caption).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 10)
      if failed {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 11))
          .foregroundColor(.orange)
          .help(L("등록 실패 — 다른 앱이 같은 조합을 쓰고 있을 수 있습니다"))
      }
      Text(isRecording ? L("키 입력…") : ShortcutCombo.display(combo))
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
        .lineLimit(1)
        .padding(.horizontal, 9).padding(.vertical, 4)
        .frame(minWidth: 92)
        .background(RoundedRectangle(cornerRadius: 7)
          .fill(Color.primary.opacity(isRecording ? 0.10 : 0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7)
          .stroke(isRecording ? Color.accentColor : Color.primary.opacity(0.10), lineWidth: 1))
        .foregroundColor(isRecording ? .accentColor : .primary)
      Button(isRecording ? L("취소") : L("변경")) {
        isRecording ? stopRecording() : beginRecording(action)
      }
      .frame(minWidth: 56)
      Button {
        store.settings.setShortcut(action.defaultCombo, for: action)
      } label: {
        Image(systemName: "arrow.counterclockwise").font(.system(size: 10.5))
      }
      .buttonStyle(.borderless)
      .disabled(combo == action.defaultCombo)
      .help(Lf("기본값(%@)으로 되돌리기", ShortcutCombo.display(action.defaultCombo)))
    }
    .padding(.vertical, 3)
  }

  // MARK: - 단축키 녹화

  private func beginRecording(_ action: ShortcutAction) {
    stopRecording()
    // 기존 전역 핫키가 새 조합을 먼저 가로채지 않게 잠시 푼다
    NotificationCenter.default.post(name: .quickTalkSuspendShortcuts, object: nil)
    recordingShortcut = action
    recordHint = L("원하는 키 조합을 누르세요 — Esc 취소")
    recordMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
      handleRecordedKey(event, action: action)
    }
  }

  /// 설정 창에서 키를 받아 저장 문자열로 — Esc 취소 · Delete 기본값
  private func handleRecordedKey(_ event: NSEvent, action: ShortcutAction) -> NSEvent? {
    if event.keyCode == 53 { stopRecording(); return nil }              // Esc
    if event.keyCode == 51 || event.keyCode == 117 {                    // Delete / Forward Delete
      store.settings.setShortcut(action.defaultCombo, for: action)
      stopRecording()
      return nil
    }
    guard let combo = GlobalHotKey.comboString(keyCode: Int(event.keyCode), flags: event.modifierFlags) else {
      recordHint = L("보조 키(⌘⌃⌥⇧)와 함께 눌러 주세요")
      return nil
    }
    if let other = store.settings.shortcutConflict(combo, for: action) {
      recordHint = Lf("%@이(가) 이미 사용 중입니다 — 다른 조합을 눌러 주세요", other.title)
      return nil
    }
    store.settings.setShortcut(combo, for: action)
    recordHint = nil
    stopRecording()
    return nil
  }

  private func stopRecording() {
    let wasRecording = recordingShortcut != nil
    if let m = recordMonitor { NSEvent.removeMonitor(m) }
    recordMonitor = nil
    recordingShortcut = nil
    recordHint = nil
    if wasRecording {
      NotificationCenter.default.post(name: .quickTalkResumeShortcuts, object: nil)
    }
  }

  // MARK: - QuickShelf (PLAN_v0.13)

  @ViewBuilder
  var shelfSection: some View {
    groupBox(L("화면 가장자리 허브")) {
      toggleRow(L("캡처를 클립보드에도 복사"), isOn: $store.settings.shelfCopyCaptureToClipboard,
                description: L("캡처하면 퀵셸프에 쌓이는 동시에 클립보드에도 들어가 다른 앱에서 바로 붙여넣을 수 있습니다."))
      valueRow(L("패널 단축키"), Lf("%@ (퀵셸프 열기/닫기)",
                                  ShortcutCombo.display(store.settings.shelfShortcut)))
      valueRow(L("캡처 단축키"), Lf("%@ 전체 · %@ 드래그 · %@ 창",
                                  ShortcutCombo.display(store.settings.captureFullShortcut),
                                  ShortcutCombo.display(store.settings.captureRegionShortcut),
                                  ShortcutCombo.display(store.settings.captureWindowShortcut)))
      caption(L("시스템 ⌘⇧3·⌘⇧4는 macOS 전용이라 앱이 가로챌 수 없습니다 — 그래서 자체 조합(⌥⇧3/4)을 씁니다."))
      caption(L("패널·캡처 단축키는 '단축키' 탭에서 바꿉니다."))
      caption(L("캡처에는 화면 기록 권한이 필요합니다 — 상태와 요청은 도구·권한 › 시스템 권한에서 합니다."))
    }
    groupBox(L("저장 정책 (내용은 기록하지 않습니다)")) {
      valueRow(L("클립보드"), L("최근 5개 · 2분 뒤 자동 만료 · 사용하면 즉시 제거"))
      valueRow(L("파일 · 캡처"), L("첨부하면 목록에서 사라짐 (복사·저장은 유지)"))
      valueRow(L("보관 위치"), shelfPathHint)
      caption(L("클립보드 내용은 읽기만 하며 로그·캡처에 남기지 않습니다. 민감 항목은 기본 가림 상태로 표시됩니다."))
      HStack(spacing: 8) {
        Button(L("퀵셸프 파일·캡처 폴더 열기")) { openShelfFolder() }
        Button(L("캡처 모두 지우기")) { store.clearCaptures() }
        Spacer()
      }
    }
  }

  private var shelfPathHint: String {
    UIStore.shelfDir?.path ?? "~/Library/Application Support/QuickTalk/shelf"
  }

  private func openShelfFolder() {
    guard let dir = UIStore.shelfDir else { return }
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    NSWorkspace.shared.open(dir)
  }

  // MARK: - 대화 (2026-10-27 설정 재구성)
  //
  // "대화"는 **창 하나를 다루는 데 필요한 것**만 모은다.
  //   ① 창 연결 — 다른 앱 창을 참고 자료로 붙이기(권한은 도구·권한 탭에 모아 둔다)
  //   ② 창 동작 — 새 창 위치·단축키로 열 때 이어서
  //   ③ 기억    — 대화 기억 정리 · 공통 메모리   (+AI.swift)
  //   ④ 보관    — 보관일수 · 지우기               (+Archive.swift)
  // 웹 검색은 '검색', 프로바이더는 'AI'로 옮겼다(한 탭에 서로 다른 일이 섞여 있었다).
  @ViewBuilder
  var conversationSection: some View {
    windowAttachmentSection
    windowBehaviorSection
    memorySection
    globalMemorySection
    archiveSection
  }

  @ViewBuilder
  var windowAttachmentSection: some View {
    groupBox(L("창 연결")) {
      toggleRow(L("입력독에 창 연결 버튼 표시"), isOn: $store.settings.windowAttachmentEnabled,
                description: L("창 하나의 글자와 스크린샷을 이번 질문의 참고 자료로 붙입니다. 읽기만 하며 창을 조작하지 않습니다."))
      caption(L("화면 기록은 창 목록·스크린샷에, 손쉬운 사용은 글자를 읽는 데 씁니다. 손쉬운 사용이 없으면 스크린샷만 붙습니다."))
      caption(L("권한 상태와 요청은 도구·권한 › 시스템 권한에서 합니다. 허용 후에는 앱을 다시 실행해야 반영됩니다."))
    }
  }

  @ViewBuilder
  var windowBehaviorSection: some View {
    groupBox(L("창 동작")) {
      pickerRow(L("단축키로 열 때 유지"), selection: $store.settings.shortcutSessionMinutes,
                options: QuickTalkSettings.sessionMinuteOptions.map {
                  ($0, $0 == 0 ? L("사용 안 함(언제나 새 대화)") : Lf("%d분 이내면 이어서", $0))
                })
      caption(Lf("%@로 열 때 마지막 대화가 이 시간 안에 있었으면 이어서 열고, 지났으면 새 대화로 시작합니다. 대화는 보낼 때마다 자동 저장됩니다.",
                 ShortcutCombo.display(store.settings.globalShortcut)))
      pickerRow(L("대화 창 위치"), selection: $store.settings.newWindowPosition,
                options: NewWindowPosition.allCases.map { ($0, $0.displayName) })
      caption(Lf("%@ 새 대화는 포인터 자리 pill에서 입력을 시작하고, 대화 창도 그 자리에서 열립니다. 이 설정은 이어서 열기·보관함·Hub·QuickShelf에서 창을 열 때만 적용됩니다.",
                 ShortcutCombo.display(store.settings.globalShortcut)))
      caption(L("마지막 위치 = 옮긴 자리를 기억합니다(처음엔 화면 중앙). 포인터 모드에서 메뉴바로 열면 마지막 작업 위치를 씁니다. 화면 밖으로 나가면 보이는 영역 안으로 밀어 넣습니다."))
    }
  }

}
