import XCTest
@testable import QuickTalkCore

// [REFACTOR] 웹 검색 경로 판정 — 사전 검색/`/answer` 초안이 언제 도는가 (2026-10-29)
//
// 규칙
//   · 도우미 도구 + 검색 도구 준비 + Apple FM 이 아니면 → 모델이 루프 안에서 검색한다(사전 검색 생략).
//   · Apple FM 은 web_search 도구를 등록하지 않으므로 사전 검색을 남긴다(검색 기회 보존).
//   · 도구가 꺼져 있거나 키가 없으면 기존 사전 검색 경로가 그대로 돈다.
//   · Exa `/answer` 초안은 사전 검색이 살아 있을 때만 만들어진다 — 설정 화면이 이 값으로 안내한다.

final class WebSearchRoutingTests: XCTestCase {
  func testSkipsPreSearchWhenLoopCanSearch() {
    XCTAssertTrue(WebSearchRouting.skipsPreSearch(agentTools: true, searchToolReady: true,
                                                  providerType: .openAICompatible))
    XCTAssertTrue(WebSearchRouting.skipsPreSearch(agentTools: true, searchToolReady: true,
                                                  providerType: .ollama))
  }

  func testAppleFMKeepsPreSearch() {
    // Apple FM 은 도구 루프가 켜져도 web_search 를 등록하지 않는다.
    XCTAssertFalse(WebSearchRouting.skipsPreSearch(agentTools: true, searchToolReady: true,
                                                   providerType: .appleFM))
    XCTAssertTrue(WebSearchRouting.usesPreSearch(agentTools: true, searchToolReady: true,
                                                 providerType: .appleFM))
  }

  func testSkipsOnlyWhenToolsAndSearchAreReady() {
    XCTAssertFalse(WebSearchRouting.skipsPreSearch(agentTools: false, searchToolReady: true,
                                                   providerType: .openAICompatible))
    XCTAssertFalse(WebSearchRouting.skipsPreSearch(agentTools: true, searchToolReady: false,
                                                   providerType: .openAICompatible))
  }

  func testAnswerDraftActiveOnlyWhenPreSearchRuns() {
    XCTAssertTrue(WebSearchRouting.usesAnswerDraft(mode: .answer, agentTools: false,
                                                   searchToolReady: true,
                                                   providerType: .openAICompatible))
    XCTAssertTrue(WebSearchRouting.usesAnswerDraft(mode: .answer, agentTools: true,
                                                   searchToolReady: true,
                                                   providerType: .appleFM))
    // 도구 루프가 검색을 가져가면 초안은 만들어지지 않는다 — 설정 화면이 이 경우를 안내한다.
    XCTAssertFalse(WebSearchRouting.usesAnswerDraft(mode: .answer, agentTools: true,
                                                    searchToolReady: true,
                                                    providerType: .openAICompatible))
  }

  func testAnswerDraftOnlyForAnswerMode() {
    XCTAssertFalse(WebSearchRouting.usesAnswerDraft(mode: .inject, agentTools: false,
                                                    searchToolReady: true,
                                                    providerType: .openAICompatible))
    XCTAssertFalse(WebSearchRouting.usesAnswerDraft(mode: .toolCalling, agentTools: false,
                                                    searchToolReady: true,
                                                    providerType: .openAICompatible))
  }
}
