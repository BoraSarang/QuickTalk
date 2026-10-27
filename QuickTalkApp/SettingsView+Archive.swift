import SwiftUI

// [REFACTOR] SettingsView — 보관함·정보 섹션 (2026-10-20 파일 분리)
extension SettingsView {
  // MARK: - 보관함

  @ViewBuilder
  var archiveSection: some View {
    groupBox(L("보관 정책")) {
      HStack {
        Text(L("보관일수")).font(.body)
        Spacer()
        Text(Lf("%d일", store.settings.keepDays)).font(.callout).foregroundColor(.secondary)
        Stepper("", value: $store.settings.keepDays, in: 7...365).labelsHidden()
      }
      .padding(.vertical, 2)
      caption(L("모든 대화가 보낼 때마다 자동 저장됩니다. 🔖 보관한 대화는 남고, 그 외는 보관일수를 지난 뒤 정리됩니다."))
      valueRow(L("저장된 대화"), Lf("%d개", store.archive.count))
      caption(L("기록 파일 위치는 '정보' 탭에서 확인할 수 있습니다. 아래 버튼은 보관한 대화까지 모두 지웁니다."))
      HStack {
        Spacer()
        Button(L("기록 모두 지우기")) { showClearArchiveConfirm = true }
          .foregroundColor(.red)
      }
    }
    .onAppear { store.loadArchive() }
  }

  // MARK: - 정보

  @ViewBuilder
  var aboutSection: some View {
    groupBox(L("앱 정보")) {
      valueRow(L("이름"), "QuickTalk")
      valueRow(L("버전"), Bundle.main.appVersion)
      valueRow(L("번들 ID"), Bundle.main.bundleIdentifier ?? "-")
      valueRow(L("플랫폼"), "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)")
    }
    groupBox(L("저장 위치")) {
      valueRow(L("설정"), "UserDefaults · QuickTalk.settings")
      valueRow(L("대화 기록"), PersistenceService.storeURL.path)
      valueRow(L("실행 기록"), AgentAudit.logURL.path)
      valueRow(L("퀵셸프"), UIStore.shelfDir?.path ?? "~/Library/Application Support/QuickTalk/shelf")
      valueRow(L("API 키"), SecretStore.fileURL.path)
      caption(L("키는 이 Mac의 로컬 파일(권한 600)에만 저장되며 화면·로그에 출력하지 않습니다. 키체인을 쓰지 않아 실행 때마다 허용 창이 뜨지 않습니다."))
    }
    groupBox(L("진단")) {
      valueRow(L("프로바이더"), Lf("프로바이더 %d개 등록 · 활성 %@", store.settings.providers.count,
                                       store.settings.activeProvider?.displayName ?? L("없음")))
      valueRow("Apple FM", appleFMAvailability())
      valueRow("Whisper", WhisperService.status(settings: store.settings))
    }
  }
}
