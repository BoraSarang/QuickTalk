import SwiftUI

// [REFACTOR] SettingsView — AI 프로바이더 섹션 (2026-10-20 파일 분리)
extension SettingsView {
  // MARK: - AI

  @ViewBuilder
  var aiSection: some View {
    groupBox(L("활성 프로바이더")) {
      if store.settings.providers.filter({ $0.enabled }).isEmpty {
        Text(L("사용 가능한 프로바이더가 없습니다. 아래에서 추가하세요."))
          .font(.callout).foregroundColor(.orange)
      } else {
        pickerRow(L("답변 생성에 사용"), selection: $store.settings.activeProviderID,
                  options: store.settings.providers.filter { $0.enabled }.map { ($0.id, $0.displayName) })
        let candidates = store.settings.providers.filter { $0.enabled && $0.id != store.settings.activeProviderID }
        if candidates.isEmpty {
          valueRow(L("예비 AI"), L("사용 안 함"))
        } else {
          pickerRow(L("예비 AI (실패 시 1회)"), selection: $store.settings.fallbackProviderID,
                    options: [("", L("사용 안 함"))] + candidates.map { ($0.id, $0.displayName) })
        }
        caption(L("주 모델이 사용 제한(429)·서버 오류·시간 초과로 실패하면 예비 AI로 한 번만 다시 시도합니다. 키·권한 오류와 첨부 거부는 전환하지 않으며, 다른 모델로 답하면 답변 위에 안내가 붙습니다."))
      }
      if let active = store.settings.activeProvider {
        valueRow(L("종류"), active.type.displayName)
        if active.type == .appleFM {
          valueRow(L("상태"), appleFMAvailability())
        } else {
          valueRow(L("주소"), active.baseURL)
          valueRow(L("모델"), active.model.isEmpty ? L("미지정") : active.model)
        }
        if active.type.needsAPIKey {
          valueRow(L("API 키"), SecretStore.has(account: active.secretID) ? L("로컬 파일에 저장됨") : L("미저장"))
        }
      }
    }
    .onChange(of: store.settings.activeProviderID) { _, new in
      // 주 모델이 예비 AI와 같아지면 폴백이 무의미하다 — 선택을 비운다.
      if store.settings.fallbackProviderID == new {
        store.settings.fallbackProviderID = ""
      }
    }
    groupBox(Lf("프로바이더 목록 (%d개)", store.settings.providers.count)) {
      ForEach(store.settings.providers) { p in
        providerRow(p)
      }
      Divider().padding(.vertical, 2)
      Menu {
        ForEach(LLMProviderType.allCases) { type in
          Button(type.displayName) { addProvider(type) }
        }
      } label: {
        Label(L("프로바이더 추가"), systemImage: "plus")
      }
      .menuStyle(.borderlessButton)
      .frame(maxWidth: 180, alignment: .leading)
      caption(L("종류를 고르면 설정 시트가 열립니다. 원격은 주소와 API 키를 저장해야 동작합니다."))
      caption(L("웹 검색은 '검색' 탭, 기억과 보관은 '대화' 탭에서 설정합니다."))
    }
  }

  /// 대화 기억 정리 — 길어지면 오래된 턴을 요약해 첫 토큰 지연·비용을 줄인다.
  @ViewBuilder
  var memorySection: some View {
    groupBox(L("대화 기억 정리")) {
      HStack {
        Text(L("자동으로 정리"))
        Spacer()
        Toggle("", isOn: $store.settings.autoCompact)
          .labelsHidden().toggleStyle(.switch).controlSize(.small)
      }
      pickerRow(L("최근 원문 유지"), selection: $store.settings.compactKeepTurns,
                options: QuickTalkSettings.compactKeepOptions.map { ($0, Lf("%d개 메시지", $0)) })
        .disabled(!store.settings.autoCompact)
      HStack(spacing: 8) {
        Button(store.isCompacting ? L("정리 중…") : L("지금 정리")) { store.compactNow() }
          .disabled(store.isCompacting || store.isReplying)
        if store.conversation.activeSummary != nil {
          Button(L("보기")) { showMemory = true }
            .help(L("모델이 기억하는 요약을 확인·편집합니다"))
          Button(L("요약 해제")) { store.clearConversationMemory() }
            .disabled(store.isCompacting)
        }
        if let message = store.compactMessage {
          Text(message).font(.caption).foregroundColor(.orange).lineLimit(2)
        }
      }
      if let provider = store.settings.activeProvider {
        let current = ConversationMemory.contextTokens(store.conversation)
        let trigger = Int(Double(ConversationMemory.promptBudget(for: provider))
                          * ConversationMemory.triggerRatio)
        caption(Lf("현재 약 %d토큰 · 자동 정리 기준 %d토큰", current, trigger))
        caption(L("기준을 넘으면 다음 답변을 마친 뒤 백그라운드에서 정리합니다."))
      }
      caption(L("대화가 길어지면 최근 메시지만 원문으로 보내고, 그 이전은 요약해 기억합니다. 원문은 삭제되지 않으며, 요약이 생기면 이 화면의 [보기] 또는 입력독 위 배너의 [보기]에서 확인·편집할 수 있습니다. Apple FM은 4,096토큰 예산에 맞춰 최근 4개까지 유지합니다."))
      if let provider = store.settings.activeProvider, provider.type == .ollama {
        caption(L("Local Ollama는 응답 속도 때문에 이번 요청의 문맥을 기본 3,072토큰으로 줄입니다. 프로바이더에 컨텍스트 토큰을 직접 넣으면 그 값을 씁니다."))
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
  }

  /// 프로바이더 1행 — 아이콘 · 이름 · 요약 + 편집/삭제
  private func providerRow(_ p: LLMProviderConfig) -> some View {    HStack(spacing: 10) {
      Image(systemName: p.type.iconName)
        .font(.system(size: 12))
        .foregroundColor(.accentColor)
        .frame(width: 24, height: 24)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 7))
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(p.displayName).font(.body)
          if store.settings.activeProviderID == p.id {
            Text(L("사용 중")).font(.caption2)
              .padding(.horizontal, 6).padding(.vertical, 1)
              .background(Color.accentColor.opacity(0.15))
              .foregroundColor(.accentColor)
              .clipShape(Capsule())
          }
          if !p.enabled {
            Text(L("사용 안 함")).font(.caption2).foregroundColor(.secondary)
          }
        }
        Text(providerSummary(p)).font(.caption).foregroundColor(.secondary)
          .lineLimit(1).truncationMode(.middle)
      }
      Spacer()
      Toggle("", isOn: Binding(
        get: { p.enabled },
        set: { on in updateProvider(p) { $0.enabled = on } }
      ))
      .labelsHidden().toggleStyle(.switch).controlSize(.small)
      Button(L("편집")) { editingIsNew = false; editingProvider = p }
        .buttonStyle(.borderless)
      Button {
        removeProvider(p)
      } label: {
        Image(systemName: "trash").foregroundColor(.red)
      }
      .buttonStyle(.borderless)
      .disabled(store.settings.providers.count <= 1)
      .help(L("프로바이더 삭제"))
    }
    .padding(.vertical, 4)
  }

  private func providerSummary(_ p: LLMProviderConfig) -> String {
    switch p.type {
    case .appleFM: return Lf("온디바이스 · %@", appleFMAvailability())
    case .ollama: return "\(p.baseURL) · \(p.model.isEmpty ? L("모델 미지정") : p.model)"
    case .openAICompatible:
      let key = p.secretID.isEmpty ? L("키 미저장")
        : (SecretStore.has(account: p.secretID) ? L("키 저장됨") : L("키 미저장"))
      return "\(p.baseURL) · \(p.model.isEmpty ? L("모델 미지정") : p.model) · \(key)"
    }
  }

  private func updateProvider(_ p: LLMProviderConfig, _ apply: (inout LLMProviderConfig) -> Void) {
    guard let i = store.settings.providers.firstIndex(where: { $0.id == p.id }) else { return }
    var copy = store.settings.providers
    apply(&copy[i])
    store.settings.providers = copy
  }

  private func addProvider(_ type: LLMProviderType) {
    let created = LLMProviderConfig.newProvider(type: type, existing: store.settings.providers)
    store.settings.providers.append(created)
    editingIsNew = true
    editingProvider = created
  }

  private func removeProvider(_ p: LLMProviderConfig) {
    store.settings.providers.removeAll { $0.id == p.id }
    if store.settings.fallbackProviderID == p.id {
      store.settings.fallbackProviderID = ""
    }
    if store.settings.activeProviderID == p.id {
      store.settings.activeProviderID = store.settings.providers.first { $0.enabled }?.id
        ?? store.settings.providers.first?.id ?? LLMProviderConfig.appleFMID
      // 주 모델이 바뀌었는데 예비 AI가 그 모델과 같아지면 폴백이 무의미하다.
      if store.settings.fallbackProviderID == store.settings.activeProviderID {
        store.settings.fallbackProviderID = ""
      }
    }
  }

}
