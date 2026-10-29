import XCTest
@testable import QuickTalkCore

// [FEATURE] 승인된 쓰기 폴더 — 대화별 유지 · 7일 만료 (2026-10-29)
//
// 핵심 계약
//   · 승인은 대화 기록과 함께 저장되어 앱을 다시 켜도 남는다.
//   · 7일이 지나면 판정·설정 화면에서 빠진다(만료 시각과 같은 순간도 만료).
//   · 다시 승인하면 같은 경로의 기간이 **새로 시작**되고, 만료된 승인은 정리된다.
//   · 구버전 기록(키 없음)은 "승인 없음"으로 읽힌다.

final class WriteScopeGrantTests: XCTestCase {
  private let base = Date(timeIntervalSince1970: 1_700_000_000)

  // MARK: - 만료

  func testDefaultLifetimeIsSevenDays() {
    let grant = WriteScopeGrant(path: "/tmp/work", approvedAt: base)
    XCTAssertEqual(WriteScopeGrant.defaultLifetime, 7 * 24 * 60 * 60)
    XCTAssertEqual(grant.expiresAt, base.addingTimeInterval(7 * 24 * 60 * 60))
    XCTAssertTrue(grant.isActive(at: base))
  }

  func testExpiryBoundaryCountsAsExpired() {
    let grant = WriteScopeGrant(path: "/tmp/work", approvedAt: base)
    XCTAssertTrue(grant.isActive(at: grant.expiresAt.addingTimeInterval(-1)))
    // 만료 시각과 같은 순간은 만료로 본다 — 경계가 애매하면 "하루 더" 열릴 수 있다.
    XCTAssertFalse(grant.isActive(at: grant.expiresAt))
    XCTAssertFalse(grant.isActive(at: grant.expiresAt.addingTimeInterval(1)))
  }

  // MARK: - 승인 병합

  func testApproveRefreshesSamePathAndKeepsOthers() throws {
    let old = WriteScopeGrant(path: "/tmp/a", approvedAt: base)
    let later = base.addingTimeInterval(3 * 24 * 60 * 60)
    let merged = WriteScopeGrant.approve(["/tmp/a", "/tmp/b"], into: [old], at: later)
    XCTAssertEqual(merged.map(\.path), ["/tmp/a", "/tmp/b"])
    let refreshed = try XCTUnwrap(merged.first { $0.path == "/tmp/a" })
    XCTAssertEqual(refreshed.approvedAt, later)
    XCTAssertEqual(refreshed.expiresAt, later.addingTimeInterval(WriteScopeGrant.defaultLifetime))
  }

  func testApproveDropsExpiredGrantsAndDuplicates() {
    let expired = WriteScopeGrant(path: "/tmp/old", approvedAt: base)
    let now = base.addingTimeInterval(8 * 24 * 60 * 60)
    let merged = WriteScopeGrant.approve(["/tmp/new", "/tmp/new"], into: [expired], at: now)
    XCTAssertEqual(merged.map(\.path), ["/tmp/new"])
  }

  func testApproveNormalizesAndIgnoresEmpty() {
    let merged = WriteScopeGrant.approve(["  ", "~/Documents/../Documents/tmp/"], into: [], at: base)
    XCTAssertEqual(merged.count, 1)
    XCTAssertEqual(merged.first?.path,
                   WriteScope.normalize(NSHomeDirectory() + "/Documents/tmp"))
  }

  // MARK: - 대화 기록

  func testConversationActivePathsExcludeExpired() {
    let active = WriteScopeGrant(path: "/tmp/active", approvedAt: base)
    let expired = WriteScopeGrant(path: "/tmp/expired", approvedAt: base.addingTimeInterval(-8 * 24 * 60 * 60))
    let conversation = Conversation(title: "테스트", approvedWriteScopes: [active, expired])
    XCTAssertEqual(conversation.activeWriteScopePaths(at: base), ["/tmp/active"])
  }

  func testConversationDecodesWithoutApprovedWriteScopes() throws {
    let original = Conversation(title: "테스트")
    var object = try XCTUnwrap(
      JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
    object.removeValue(forKey: "approvedWriteScopes")
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertNil(decoded.approvedWriteScopes)
  }

  func testConversationRoundTripsGrants() throws {
    let grant = WriteScopeGrant(path: "/tmp/work", approvedAt: base)
    let original = Conversation(title: "테스트", approvedWriteScopes: [grant])
    let decoded = try JSONDecoder().decode(Conversation.self,
                                           from: JSONEncoder().encode(original))
    XCTAssertEqual(decoded.approvedWriteScopes, [grant])
  }

  // MARK: - 저장

  func testStoreSavesOnlyActiveGrants() {
    let store = ConversationStore()
    let active = WriteScopeGrant(path: "/tmp/active", approvedAt: base)
    let expired = WriteScopeGrant(path: "/tmp/expired", approvedAt: base.addingTimeInterval(-8 * 24 * 60 * 60))
    store.setWriteScopeGrants([active, expired], at: base)
    XCTAssertEqual(store.conversation.approvedWriteScopes?.map(\.path), ["/tmp/active"])
  }

  func testStoreClearsGrantsWhenNoneActive() {
    let store = ConversationStore()
    store.setWriteScopeGrants([WriteScopeGrant(path: "/tmp/a", approvedAt: base)], at: base)
    XCTAssertNotNil(store.conversation.approvedWriteScopes)
    store.setWriteScopeGrants([], at: base)
    XCTAssertNil(store.conversation.approvedWriteScopes)
  }
}
