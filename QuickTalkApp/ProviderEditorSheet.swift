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
  /// 편집 중인 프로바이더의 모델 상세(v0.35) — 캐시에서 즉시 채운다.
  @State private var catalogEntry: ModelCatalogEntry?
  @State private var modelSearch = ""
  @State private var modelCatalogNote = ""
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
            row(L("모델")) {
              VStack(alignment: .leading, spacing: 6) {
                // 직접 입력도 허용한다 — 서버가 목록에 없는 ID를 받는 경우가 있다.
                TextField(L("모델 이름"), text: $draft.model)
                  .textFieldStyle(.roundedBorder)
                HStack(spacing: 6) {
                  Button {
                    loadModels()
                  } label: {
                    Label(loadingModels ? L("불러오는 중…") : modelButtonTitle,
                          systemImage: "arrow.clockwise")
                  }
                  .disabled(loadingModels || !draft.type.needsBaseURL)
                  if !modelCatalogNote.isEmpty {
                    Text(modelCatalogNote)
                      .font(.caption).foregroundColor(.secondary).lineLimit(1)
                  }
                  Spacer(minLength: 0)
                }
                if !modelList.isEmpty {
                  TextField(L("모델 검색"), text: $modelSearch)
                    .textFieldStyle(.roundedBorder)
                  modelListBox
                }
                if let info = selectedInfo {
                  modelDetailBlock(info)
                } else if !draft.type.needsBaseURL {
                  caption(L("Apple FM은 시스템 모델을 쓰므로 고를 모델이 없습니다."))
                }
              }
            }
            caption(draft.type == .ollama
                    ? L("`ollama serve` 실행 중이어야 목록을 불러올 수 있습니다.")
                    : L("목록은 캐시에서 바로 보여 줍니다. 새로 고치려면 [모델 목록 불러오기]를 누르세요."))
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
    .frame(width: 540, height: 600)
    .onAppear {
      keyStatus = keyStateText()
      if isNew { apiKeyInput = "" }
      loadCachedModels()
    }
  }

  // MARK: - 모델 목록·상세 (v0.35)

  /// 캐시에 있는 목록은 **즉시** 보여 준다(네트워크를 기다리지 않는다).
  private func loadCachedModels() {
    guard draft.type.needsModel else { return }
    catalogEntry = store.cachedCatalog(for: draft)
    modelList = catalogEntry?.models.map(\.id) ?? []
    modelCatalogNote = catalogEntry.map(catalogNote) ?? ""
  }

  private func catalogNote(_ entry: ModelCatalogEntry) -> String {
    let stamp = Self.catalogStamp.string(from: entry.fetchedAt)
    return entry.isFresh()
      ? Lf("모델 %d개 · %@ 기준", entry.models.count, stamp)
      : Lf("모델 %d개 · %@ 기준 · 오래된 목록", entry.models.count, stamp)
  }

  private static let catalogStamp: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "MM-dd HH:mm"
    return f
  }()

  private var filteredModels: [ModelInfo] {
    guard let entry = catalogEntry else { return [] }
    let q = modelSearch.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return entry.models }
    return entry.models.filter {
      $0.id.localizedCaseInsensitiveContains(q) || $0.name.localizedCaseInsensitiveContains(q)
    }
  }

  private var selectedInfo: ModelInfo? {
    guard let entry = catalogEntry, !draft.model.isEmpty else { return nil }
    return entry.models.first { $0.id == draft.model }
      ?? entry.models.first { $0.id.caseInsensitiveCompare(draft.model) == .orderedSame }
  }

  /// 검색·선택 목록 — 모델 이름과 ID를 함께 보여 주고, 고르면 상세가 아래에 붙는다.
  private var modelListBox: some View {
    ScrollView {
      LazyVStack(spacing: 1) {
        ForEach(filteredModels, id: \.id) { info in
          let selected = info.id == draft.model
          Button { draft.model = info.id } label: {
            HStack(spacing: 6) {
              Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 10))
                .foregroundColor(selected ? .purple : .secondary)
              Text(info.name)
                .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                .lineLimit(1)
              if info.name != info.id {
                Text(info.id)
                  .font(.system(size: 9.5, design: .monospaced))
                  .foregroundColor(.secondary)
                  .lineLimit(1).truncationMode(.middle)
              }
              Spacer(minLength: 0)
              if info.looksFree { freeBadge }
            }
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 5)
              .fill(selected ? Color.purple.opacity(0.10) : Color.clear))
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
        }
        if filteredModels.isEmpty {
          Text(L("일치하는 모델이 없습니다"))
            .font(.caption).foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6).padding(.vertical, 5)
        }
      }
      .padding(3)
    }
    .frame(maxHeight: 150)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.04)))
    .overlay(RoundedRectangle(cornerRadius: 7)
      .stroke(Color.primary.opacity(0.10), lineWidth: 1))
  }

  private var freeBadge: some View {
    Text(L("무료"))
      .font(.system(size: 8.5, weight: .semibold))
      .foregroundColor(.green)
      .padding(.horizontal, 4).padding(.vertical, 1)
      .background(Capsule().fill(Color.green.opacity(0.12)))
  }

  /// 선택한 모델의 능력 — 정보가 없으면 **추측하지 않고** "정보 없음"으로 둔다.
  private func modelDetailBlock(_ info: ModelInfo) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        Text(info.name).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
        if info.looksFree { freeBadge }
        Spacer(minLength: 0)
      }
      if info.hasDetails {
        if info.context != nil || info.output != nil {
          Text(Self.sizeLine(info))
            .font(.system(size: 10.5)).foregroundColor(.secondary)
        }
        Text(Self.capabilityLine(info))
          .font(.system(size: 10.5)).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(L("정보 없음")).font(.system(size: 10.5)).foregroundColor(.secondary)
      }
      Text(info.source.map { Lf("참고: models.dev · %@", $0) } ?? L("참고: models.dev"))
        .font(.system(size: 9)).foregroundColor(.secondary.opacity(0.8))
    }
    .padding(8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
  }

  static func sizeLine(_ info: ModelInfo) -> String {
    var parts: [String] = []
    if let c = info.context { parts.append(Lf("%@ 컨텍스트", compact(c))) }
    if let o = info.output { parts.append(Lf("%@ 출력", compact(o))) }
    return parts.joined(separator: " · ")
  }

  static func capabilityLine(_ info: ModelInfo) -> String {
    var parts: [String] = []
    if !info.input.isEmpty { parts.append(Lf("입력 %@", info.input.joined(separator: "·"))) }
    if info.toolCall { parts.append(L("도구")) }
    if info.reasoning {
      parts.append(info.effort.isEmpty ? L("추론") : Lf("추론 %@", info.effort.joined(separator: "/")))
    }
    return parts.isEmpty ? L("추가 정보 없음") : parts.joined(separator: " · ")
  }

  /// 200000 → "200K", 1000000 → "1M" (표시용 축약)
  static func compact(_ n: Int) -> String {
    if n >= 1_000_000 {
      let v = Double(n) / 1_000_000
      return v == v.rounded() ? String(format: "%.0fM", v) : String(format: "%.1fM", v)
    }
    if n >= 1_000 {
      let v = Double(n) / 1_000
      return v == v.rounded() ? String(format: "%.0fK", v) : String(format: "%.1fK", v)
    }
    return "\(n)"
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
    guard draft.type.needsBaseURL else {
      modelList = []; catalogEntry = nil; modelCatalogNote = ""; return
    }
    loadingModels = true
    let probe = draft
    Task { @MainActor in
      defer { loadingModels = false }
      let entry = await store.fetchCatalog(for: probe, force: true)
      guard probe.id == draft.id else { return }
      catalogEntry = entry
      if let entry {
        modelList = entry.models.map(\.id)
        modelCatalogNote = catalogNote(entry)
        if draft.model.isEmpty, let first = entry.models.first { draft.model = first.id }
      } else {
        modelList = []
        modelCatalogNote = ""
        testResult = L("모델 목록 조회 실패 (E-MAC-NET-0002)")
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

