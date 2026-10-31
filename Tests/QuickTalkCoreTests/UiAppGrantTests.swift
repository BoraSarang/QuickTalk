import XCTest
@testable import QuickTalkCore

// [FEATURE] 승인된 조작 앱 — 대화별 유지 · 7일 만료 (PLAN_v0.25 Phase 2)
//
// 승인 폴더(`WriteScopeGrant`)와 **같은 모델**이다.
//   · 대화 기록과 함께 저장한다.
//   · 7일이 지나면 판정·설정 화면에서 빠진다(만료 시각과 같은 순간도 만료).
//   · 다시 승인하면 같은 앱의 기간이 새로 시작되고, 만료된 승인은 정리된다.
//   · 구버전 기록(키 없음)은 "승인 없음"으로 읽힌다.

final class UiAppGrantTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_700_000_000)

  func testDefaultLifetimeIsSevenDays() {
    let grant = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    XCTAssertEqual(UiAppGrant.defaultLifetime, 7 * 24 * 60 * 60)
    XCTAssertEqual(grant.expiresAt, base.addingTimeInterval(7 * 24 * 60 * 60))
    XCTAssertTrue(grant.isActive(at: base))
  }

  func testExpiryBoundaryCountsAsExpired() {
    let grant = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    XCTAssertTrue(grant.isActive(at: grant.expiresAt.addingTimeInterval(-1)))
    XCTAssertFalse(grant.isActive(at: grant.expiresAt))
    XCTAssertFalse(grant.isActive(at: grant.expiresAt.addingTimeInterval(1)))
  }

  func testApproveRefreshesSameAppAndDropsExpired() throws {
    let old = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    let expired = UiAppGrant(bundleID: "com.apple.mail", name: "Mail",
                             approvedAt: base.addingTimeInterval(-8 * 24 * 60 * 60))
    let later = base.addingTimeInterval(3 * 24 * 60 * 60)
    let merged = UiAppGrant.approve(bundleID: "com.apple.Notes", name: "Notes",
                                    into: [old, expired], at: later)
    XCTAssertEqual(merged.map(\.bundleID), ["com.apple.Notes"])
    let refreshed = try XCTUnwrap(merged.first)
    XCTAssertEqual(refreshed.approvedAt, later)
    XCTAssertEqual(refreshed.name, "Notes")
  }

  func testApproveIgnoresEmptyBundleID() {
    let existing = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    let merged = UiAppGrant.approve(bundleID: "   ", name: "?", into: [existing], at: base)
    XCTAssertEqual(merged.map(\.bundleID), ["com.apple.Notes"])
  }

  func testConversationReportsOnlyActiveGrants() {
    let active = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    let expired = UiAppGrant(bundleID: "com.apple.mail", name: "Mail",
                             approvedAt: base.addingTimeInterval(-8 * 24 * 60 * 60))
    let conversation = Conversation(title: "테스트", approvedUiApps: [active, expired])
    XCTAssertEqual(conversation.activeUiAppGrants(at: base).map(\.bundleID),
                   ["com.apple.Notes"])
    XCTAssertTrue(conversation.hasActiveUiAppGrant(bundleID: "com.apple.Notes", at: base))
    XCTAssertFalse(conversation.hasActiveUiAppGrant(bundleID: "com.apple.mail", at: base))
  }

  func testConversationDecodesWithoutApprovedUiApps() throws {
    let original = Conversation(title: "테스트")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object.removeValue(forKey: "approvedUiApps")
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertNil(decoded.approvedUiApps)
    XCTAssertFalse(decoded.hasActiveUiAppGrant(bundleID: "com.apple.Notes", at: base))
  }

  func testConversationRoundTripsGrants() throws {
    let grant = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    let original = Conversation(title: "테스트", approvedUiApps: [grant])
    let decoded = try JSONDecoder().decode(Conversation.self,
                                           from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded.approvedUiApps, [grant])
  }

  func testStoreSavesOnlyActiveGrantsSorted() {
    let store = ConversationStore()
    let notes = UiAppGrant(bundleID: "com.apple.Notes", name: "Notes", approvedAt: base)
    let mail = UiAppGrant(bundleID: "com.apple.mail", name: "Mail", approvedAt: base)
    let expired = UiAppGrant(bundleID: "com.apple.Safari", name: "Safari",
                             approvedAt: base.addingTimeInterval(-8 * 24 * 60 * 60))
    store.setUiAppGrants([notes, mail, expired], at: base)
    XCTAssertEqual(store.conversation.approvedUiApps?.map(\.bundleID),
                   ["com.apple.Notes", "com.apple.mail"].sorted())
  }

  func testStoreClearsGrantsWhenNoneActive() {
    let store = ConversationStore()
    store.setUiAppGrants([UiAppGrant(bundleID: "com.apple.Notes", name: "Notes",
                                     approvedAt: base)], at: base)
    XCTAssertNotNil(store.conversation.approvedUiApps)
    store.setUiAppGrants([], at: base)
    XCTAssertNil(store.conversation.approvedUiApps)
  }
}
