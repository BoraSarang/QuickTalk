import SwiftUI
import AppKit

// [REFACTOR] SettingsView — 일반·단축키·퀵셸프 섹션 (2026-10-20 파일 분리)
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
    groupBox(L("동작")) {
      toggleRow(L("대화 창을 항상 위에"), isOn: $store.settings.alwaysOnTop,
                description: L("다른 앱 위에 고정합니다(대화 창 헤더의 📌와 같습니다). 끄면 일반 창처럼 뒤로 가서 설정·시스템 권한 창을 가리지 않습니다."))
      pickerRow(L("단축키로 열 때 유지"), selection: $store.settings.shortcutSessionMinutes,
                options: QuickTalkSettings.sessionMinuteOptions.map {
                  ($0, $0 == 0 ? L("사용 안 함(언제나 새 대화)") : Lf("%d분 이내면 이어서", $0))
                })
      caption(Lf("%@로 열 때 마지막 대화가 이 시간 안에 있었으면 이어서 열고, 지났으면 새 대화로 시작합니다. 대화는 보낼 때마다 자동 저장됩니다.",
                 ShortcutCombo.display(store.settings.globalShortcut)))
      pickerRow(L("대화 창 위치"), selection: $store.settings.newWindowPosition,
                options: NewWindowPosition.allCases.map { ($0, $0.displayName) })
      caption(L("⌘Space 새 대화는 포인터 자리 pill에서 입력을 시작하고, 대화 창도 그 자리에서 열립니다. 이 설정은 이어서 열기·보관함·Hub·QuickShelf에서 창을 열 때만 적용됩니다."))
      caption(L("마지막 위치 = 옮긴 자리를 기억합니다(처음엔 화면 중앙). 포인터 모드에서 메뉴바로 열면 마지막 작업 위치를 씁니다. 화면 밖으로 나가면 보이는 영역 안으로 밀어 넣습니다."))
      valueRow(L("메뉴바 좌클릭"), L("Hub 팝오버 (실행·설정 탭)"))
      valueRow(L("메뉴바 우클릭"), L("컨텍스트 메뉴"))
    }
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
    }
    groupBox(L("화면 기록 권한")) {
      valueRow(L("현재 상태"), CaptureService.hasPermission() ? L("허용됨") : L("허용되지 않음"))
      HStack(spacing: 8) {
        Button(L("권한 요청")) {
          if CaptureService.ensureScreenPermission() {
            store.showShelfNotice(nil)
          } else {
            store.showShelfNotice(L("화면 기록 권한이 필요합니다 — 시스템 설정에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요."),
                                  action: .screenRecording)
          }
        }
        Button(L("시스템 설정 열기")) { CaptureService.openScreenRecordingSettings() }
        Spacer()
      }
      caption(L("허용은 시스템 설정 › 개인정보 보호 및 보안 › 화면 기록에서 합니다. 허용 후에는 앱을 다시 실행해야 캡처가 동작합니다."))
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

}
