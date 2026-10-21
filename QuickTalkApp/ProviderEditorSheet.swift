import SwiftUI

// [REFACTOR] 프로바이더 편집 시트 — SettingsView에서 분리 (2026-10-20)
// MARK: - 프로바이더 편집 시트

struct ProviderEditorSheet: View {
  @EnvironmentObject var store: UIStore
  @Environment(\.dismiss) private var dismiss

  let isNew: Bool
  @State private var draft: LLMProviderConfig
  @State private var apiKeyInput = ""
  @State private var keyStatus = ""
  @State private var modelList: [String] = []
  @State private var loadingModels = false
  @State private var testResult = ""
  @State private var testing = false
  /// 컨텍스트 토큰 입력(선택) — 비우면 종류별 기본값
  @State private var contextTokensText = ""

  init(provider: LLMProviderConfig, isNew: Bool) {
    self.isNew = isNew
    _draft = State(initialValue: provider)
    _contextTokensText = State(initialValue: provider.contextTokens.map(String.init) ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(isNew ? L("프로바이더 추가") : L("프로바이더 편집"))
        .font(.headline)
        .padding([.horizontal, .top], 16)
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          row(L("이름")) { TextField(L("표시 이름"), text: $draft.name).textFieldStyle(.roundedBorder) }
          row(L("종류")) {
            Picker("", selection: $draft.type) {
              ForEach(LLMProviderType.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu)
          }
          if draft.type.needsBaseURL {
            row(draft.type == .ollama ? L("호스트") : L("주소 (BaseURL)")) {
              TextField("http://…", text: $draft.baseURL).textFieldStyle(.roundedBorder)
            }
          }
          if draft.type.needsModel {
            row(L("모델")) { TextField(L("모델 이름"), text: $draft.model).textFieldStyle(.roundedBorder) }
            HStack {
              Button(loadingModels ? L("불러오는 중…") : modelButtonTitle) { loadModels() }
                .disabled(loadingModels || !draft.type.needsBaseURL)
              if !modelList.isEmpty {
                Picker(L("불러온 모델"), selection: $draft.model) {
                  ForEach(modelList, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().pickerStyle(.menu).frame(maxWidth: 260)
              }
            }
            caption(draft.type == .ollama
                    ? L("`ollama serve` 실행 중이어야 목록을 불러올 수 있습니다.")
                    : L("주소와 키가 맞아야 서버의 모델 목록을 불러옵니다."))
          }
          if draft.type.needsModel {
            row(L("컨텍스트 토큰 (선택)")) {
              TextField("예: 32768", text: $contextTokensText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: contextTokensText) { _, value in
                  let t = value.trimmingCharacters(in: .whitespaces)
                  draft.contextTokens = t.isEmpty ? nil : Int(t)
                }
            }
            caption(L("자동 대화 정리 예산 계산에 씁니다. 비우면 종류별 기본값(Ollama 8,192 · 원격 32,768)입니다."))
          }
          if draft.type.needsAPIKey {
            Divider()
            SecureField(L("API 키 (로컬 파일 저장)"), text: $apiKeyInput)
              .textFieldStyle(.roundedBorder)
            HStack {
              Button(L("키 저장")) { saveKey() }
              Button(L("키 삭제")) { deleteKey() }
              Text(keyStatus).font(.caption).foregroundColor(.secondary)
            }
            caption(Lf("키는 이 Mac의 로컬 파일(%@, 권한 600)에만 저장되며, 설정 공유 파일·로그에는 남지 않습니다.", SecretStore.fileURL.path))
          }
          Divider()
          HStack {
            Button(testing ? L("테스트 중…") : L("연결 테스트")) { runTest() }
              .disabled(testing)
            if !testResult.isEmpty {
              Text(testResult).font(.caption).foregroundColor(.secondary)
                .lineLimit(3).textSelection(.enabled)
            }
          }
          caption(L("실제로 질문 1건을 보내 응답을 확인합니다. 실패하면 에러코드가 표시됩니다."))
        }
        .padding(16)
      }
      Divider()
      HStack {
        Button(L("취소")) { dismiss() }
        Spacer()
        Button(isNew ? L("추가") : L("저장")) { commit() }
          .keyboardShortcut(.defaultAction)
          .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
      }
      .padding(16)
    }
    .frame(width: 520, height: 460)
    .onAppear {
      keyStatus = keyStateText()
      if isNew { apiKeyInput = "" }
    }
  }

  private var modelButtonTitle: String {
    draft.type == .ollama ? L("설치된 모델 불러오기") : L("모델 목록 불러오기")
  }

  private func row<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label).font(.body)
      content()
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text).font(.caption).foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func secretID() -> String {
    draft.secretID.isEmpty ? draft.id : draft.secretID
  }

  private func keyStateText() -> String {
    guard draft.type.needsAPIKey else { return L("이 종류는 키가 필요 없습니다.") }
    return SecretStore.has(account: secretID()) ? L("키 저장됨") : L("키 미입력")
  }

  private func saveKey() {
    let secret = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !secret.isEmpty else { keyStatus = L("키를 입력하세요"); return }
    if draft.secretID.isEmpty { draft.secretID = draft.id }
    if SecretStore.save(account: secretID(), secret: secret) {
      apiKeyInput = ""
      keyStatus = L("저장됨 (로컬 파일)")
    } else {
      keyStatus = L("저장 실패 E-MAC-KEY-0001")
    }
  }

  private func deleteKey() {
    guard draft.type.needsAPIKey, !draft.secretID.isEmpty else { keyStatus = L("삭제할 키가 없습니다"); return }
    keyStatus = SecretStore.delete(account: secretID()) ? L("삭제됨") : L("삭제 실패")
  }

  private func loadModels() {
    guard let host = URL(string: draft.baseURL) else { modelList = []; return }
    loadingModels = true
    Task { @MainActor in
      defer { loadingModels = false }
      do {
        switch draft.type {
        case .ollama:
          modelList = try await OllamaClient.listModels(host: host)
        case .openAICompatible:
          let key = SecretStore.load(account: secretID()) ?? ""
          modelList = try await OpenAIClient.listModels(baseURL: host, apiKey: key)
        case .appleFM:
          modelList = []
        }
        if draft.model.isEmpty, let first = modelList.first { draft.model = first }
        if modelList.isEmpty { testResult = L("모델 목록이 비어 있습니다 (E-MAC-NET-0002)") }
      } catch {
        modelList = []
        testResult = Lf("모델 목록 조회 실패 (%@): %@",
                        AIErrorText.code(for: error),
                        AIErrorText.detail(for: error, url: URL(string: draft.baseURL)))
      }
    }
  }

  private func runTest() {
    testing = true
    testResult = ""
    let probe = draft
    Task { @MainActor in
      defer { testing = false }
      do {
        let reply = try await UIStore.reply(provider: probe, prompt: L("연결 확인. 한 단어로 답해줘."), history: [])
        if reply.hasPrefix("(오류") || reply.hasPrefix("(Error") {
          testResult = reply                    // 앱이 만든 정확한 원인 문구를 그대로
        } else {
          let short = reply.count > 60 ? String(reply.prefix(60)) + "…" : reply
          testResult = Lf("응답: %@", short)
        }
      } catch {
        testResult = Lf("실패 (%@): %@", AIErrorText.code(for: error),
                        AIErrorText.detail(for: error, url: URL(string: probe.baseURL)))
      }
    }
  }

  private func commit() {
    var updated = draft
    updated.name = draft.name.trimmingCharacters(in: .whitespaces)
    if updated.type.needsAPIKey && updated.secretID.isEmpty {
      updated.secretID = updated.id
    }
    if let i = store.settings.providers.firstIndex(where: { $0.id == updated.id }) {
      store.settings.providers[i] = updated
    } else {
      store.settings.providers.append(updated)
    }
    dismiss()
  }
}

