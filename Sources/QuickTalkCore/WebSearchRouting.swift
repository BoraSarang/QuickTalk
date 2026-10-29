import Foundation

// [REFACTOR] 웹 검색 경로 판정 — 앱과 설정 화면이 같은 규칙을 쓰게 모은다 (2026-10-29)
//
// v0.23 부터 도우미 도구가 켜져 있으면 웹 검색도 **에이전트 루프 안에서** 모델이 고른다.
// 그래서 앱이 먼저 검색하는 경로(사전 검색·Exa `/answer` 초안)는 다음 조건에서만 돈다.
// 이 판정이 UIStore 안에 흩어져 있으면 설정 화면이 "지금 이 방식이 쓰이는지"를
// 설명할 수 없고, 조건을 바꿀 때 두 곳이 어긋난다. 순수 함수로 고정한다.

public enum WebSearchRouting {
  /// 사전 검색을 건너뛰어도 되는가 — **루프 안에서 검색할 수 있을 때만**.
  /// Apple FM 은 `web_search` 도구를 등록하지 않으므로(모델이 작아 도구 호출이 불안정)
  /// 사전 검색을 남긴다. 그러지 않으면 검색 기회 자체가 사라진다.
  public static func skipsPreSearch(agentTools: Bool, searchToolReady: Bool,
                                    providerType: LLMProviderType) -> Bool {
    agentTools && searchToolReady && providerType != .appleFM
  }

  /// 선택한 답변 방식이 이번 실행에서 **실제로 사전 검색 경로**를 타는가.
  /// `.answer` 는 사전 검색이 건너뛰어지면 초안이 만들어지지 않는다(설정 화면 안내용).
  public static func usesPreSearch(agentTools: Bool, searchToolReady: Bool,
                                   providerType: LLMProviderType) -> Bool {
    !skipsPreSearch(agentTools: agentTools, searchToolReady: searchToolReady,
                    providerType: providerType)
  }

  /// `.answer` 초안이 지금 실행에서 쓰이는가.
  public static func usesAnswerDraft(mode: WebSearchMode, agentTools: Bool,
                                     searchToolReady: Bool,
                                     providerType: LLMProviderType) -> Bool {
    mode == .answer && usesPreSearch(agentTools: agentTools,
                                     searchToolReady: searchToolReady,
                                     providerType: providerType)
  }
}
