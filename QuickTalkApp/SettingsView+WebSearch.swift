import SwiftUI

// [FEATURE] 웹 검색 설정 (PLAN_v0.14) — 설정 › 검색 탭 (2026-10-27 AI 탭에서 분리).
// 키는 `SecretStore`(600)에만 저장하고 설정 JSON·로그에는 남기지 않는다.
extension SettingsView {
  @ViewBuilder
  var webSearchSection: some View {
    groupBox(L("웹 검색")) {
      pickerRow(L("공급자"), selection: $store.settings.webSearchProvider,
                options: WebSearchProvider.allCases.map { ($0, $0.displayName) })

      if store.settings.webSearchProvider == .exa {
        ExaKeyEditor()

        pickerRow(L("답변 방식"), selection: $store.settings.webSearchMode,
                  options: WebSearchMode.allCases.map { ($0, $0.displayName) })
        caption(store.settings.webSearchMode.explanation)
        if store.settings.agentToolsEnabled {
          caption(L("도우미 도구가 켜져 있으면 위 방식과 무관하게 모델이 web_search 도구로 직접 검색합니다. 이때는 검색 여부를 미리 판정하지 않습니다."))
        }

        valueRow(L("검색 시점"), L("필요할 때만"))
        caption(L("질문에 최신 정보가 필요할 때만 자동으로 검색합니다. 입력독의 🌐를 켜면 그 질문은 반드시 검색합니다. 툴 콜링은 모델이 스스로 판단합니다."))

        pickerRow(L("결과 수"), selection: $store.settings.webSearchResultCount,
                  options: QuickTalkSettings.webSearchCountOptions.map { ($0, Lf("%d건", $0)) })
        pickerRow(L("신선도"), selection: $store.settings.webSearchFreshness,
                  options: WebSearchFreshness.allCases.map { ($0, $0.displayName) })
        pickerRow(L("결과 1건 길이"), selection: $store.settings.webSearchMaxCharacters,
                  options: [(1_000, Lf("%d자", 1_000)),
                            (2_000, Lf("%d자", 2_000)),
                            (4_000, Lf("%d자", 4_000))])
        if let provider = store.settings.activeProvider, provider.type == .ollama {
          let limits = WebSearchPromptLimits.limits(resultCount: store.settings.webSearchResultCount,
                                                    maxCharacters: store.settings.webSearchMaxCharacters,
                                                    provider: provider)
          caption(Lf("로컬 모델은 첫 응답이 느려 검색 결과를 %d건·%d자로 줄여 보냅니다.",
                     limits.resultCount, limits.maxCharacters))
        }
        pickerRow(L("하루 검색 한도"), selection: $store.settings.webSearchDailyLimit,
                  options: QuickTalkSettings.webSearchDailyLimitOptions.map {
                    ($0, $0 == 0 ? L("무제한") : Lf("%d회", $0))
                  })
        let used = store.webSearchUsageToday
        caption(Lf("오늘 %d회 · 예상 %@ (Exa $7/1k 기준, 캐시 적중 제외)",
                   used, WebSearchQuota.costText(used)))

        HStack(spacing: 8) {
          Button(store.webSearchTesting ? L("검색 중…") : L("검색 테스트")) { store.testWebSearch() }
            .disabled(store.webSearchTesting || !store.webSearchKeyReady)
          Button(store.answerTesting ? L("답변 중…") : L("/answer 테스트")) { store.testExaAnswer() }
            .disabled(store.answerTesting || !store.webSearchKeyReady)
          Button(L("캐시 비우기")) { store.clearWebSearchCache() }
        }
        if !store.webSearchTestResult.isEmpty {
          Text(store.webSearchTestResult)
            .font(.caption)
            .foregroundColor(store.webSearchTestResult.hasPrefix("⚠️") ? .orange : .secondary)
            .lineLimit(2)
        }
        if !store.answerTestResult.isEmpty {
          Text(store.answerTestResult)
            .font(.caption)
            .foregroundColor(store.answerTestResult.hasPrefix("⚠️") ? .orange : .secondary)
            .lineLimit(2)
        }

        caption(L("검색어는 Exa(미국)로 전송됩니다. 검색을 끄면 외부 요청은 0회이고, 검색어·페이지 본문은 로그에 남기지 않습니다. 답변에는 제목·URL·날짜만 출처로 저장합니다. 툴 콜링은 모델이 검색어를 만들고, /answer는 Exa가 답변 초안과 인용을 만듭니다."))
      } else {
        caption(L("검색을 켜면 질문에 최신 정보가 필요할 때만 검색 결과를 답변 앞에 넣습니다. 모델을 바꾸지 않아도 되고, 검색이 실패해도 답변은 계속됩니다."))
      }
    }
  }
}

/// Exa 키 입력·저장 — 화면을 떠나면 입력값은 사라진다(키는 SecretStore에만).
private struct ExaKeyEditor: View {
  @EnvironmentObject private var store: UIStore
  @State private var input = ""
  @State private var status = ""

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 8) {
        SecureField(L("Exa API 키 (로컬 파일 저장)"), text: $input)
          .textFieldStyle(.roundedBorder)
        Button(L("키 저장")) { save() }
        Button(L("키 삭제")) { delete() }
          .disabled(!store.webSearchKeyReady)
      }
      HStack(spacing: 6) {
        Text(store.webSearchKeyReady ? L("키 저장됨 (로컬 파일)") : L("키 미저장"))
          .font(.caption)
          .foregroundColor(store.webSearchKeyReady ? .secondary : .orange)
        if !status.isEmpty {
          Text(status).font(.caption).foregroundColor(.secondary)
        }
      }
    }
    .padding(.vertical, 2)
  }

  private func save() {
    let secret = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !secret.isEmpty else { status = L("키를 입력하세요"); return }
    if SecretStore.save(account: store.settings.exaSecretID, secret: secret) {
      input = ""
      status = L("저장됨")
      store.webSearchTestResult = ""
    } else {
      status = L("저장 실패 (E-MAC-KEY-0001)")
    }
  }

  private func delete() {
    status = SecretStore.delete(account: store.settings.exaSecretID) ? L("삭제됨") : L("삭제 실패")
    store.webSearchTestResult = ""
  }
}
