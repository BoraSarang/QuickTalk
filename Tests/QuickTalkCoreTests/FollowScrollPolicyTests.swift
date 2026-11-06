import XCTest
@testable import QuickTalkCore

/// v0.32.1 회귀 — 목차 바로가기 뒤 스크롤이 맨 아래로 튀던 문제.
final class FollowScrollPolicyTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_000)

  /// 점프 직후 중간에서 스크롤을 내려도 바닥으로 붙이지 않는다.
  func testNoPinAfterJumpWhileScrollingDown() {
    let jump = FollowScrollPolicy.jumpStarted(now: t0)
    XCTAssertFalse(jump.followsBottom)
    XCTAssertFalse(jump.atBottom)

    let u = FollowScrollPolicy.update(followsBottom: jump.followsBottom,
                                      distance: 900,
                                      didScrollUp: false,
                                      now: t0.addingTimeInterval(0.4),
                                      suppressUntil: jump.suppressUntil)
    XCTAssertFalse(u.shouldPin)
    XCTAssertFalse(u.followsBottom)
    XCTAssertFalse(u.atBottom)
  }

  /// 점프 중 레이아웃이 확정되기 전 `distance == 0` 이 와도 따라가기를 되살리지 않는다.
  func testTransientAtBottomDuringJumpDoesNotResumeFollowing() {
    let jump = FollowScrollPolicy.jumpStarted(now: t0)

    let transient = FollowScrollPolicy.update(followsBottom: jump.followsBottom,
                                              distance: 0,
                                              didScrollUp: false,
                                              now: t0.addingTimeInterval(0.1),
                                              suppressUntil: jump.suppressUntil)
    XCTAssertFalse(transient.followsBottom)
    XCTAssertFalse(transient.shouldPin)

    // 그 뒤 실제 위치가 중간으로 보고돼도 여전히 따라가지 않는다.
    let middle = FollowScrollPolicy.update(followsBottom: transient.followsBottom,
                                           distance: 900,
                                           didScrollUp: false,
                                           now: t0.addingTimeInterval(0.5),
                                           suppressUntil: jump.suppressUntil)
    XCTAssertFalse(middle.shouldPin)
    XCTAssertFalse(middle.followsBottom)
  }

  /// 억제 시간이 지난 뒤 사용자가 직접 바닥에 닿으면 다시 따라간다.
  func testFollowingResumesWhenUserReachesBottomAfterJump() {
    let jump = FollowScrollPolicy.jumpStarted(now: t0)

    let atEnd = FollowScrollPolicy.update(followsBottom: false,
                                          distance: 0,
                                          didScrollUp: false,
                                          now: t0.addingTimeInterval(2.0),
                                          suppressUntil: jump.suppressUntil)
    XCTAssertTrue(atEnd.followsBottom)
    XCTAssertTrue(atEnd.atBottom)
    XCTAssertFalse(atEnd.shouldPin)

    // 이후 내용이 늘면 다시 바닥을 붙인다.
    let grew = FollowScrollPolicy.update(followsBottom: atEnd.followsBottom,
                                        distance: 120,
                                        didScrollUp: false,
                                        now: t0.addingTimeInterval(2.3),
                                        suppressUntil: jump.suppressUntil,
                                        lastPinAt: t0)
    XCTAssertTrue(grew.shouldPin)
  }

  /// 평소 스트리밍 — 바닥을 따라가던 중 내용이 늘면 다시 붙인다.
  func testPinWhileFollowingStreamingContent() {
    let u = FollowScrollPolicy.update(followsBottom: true,
                                      distance: 120,
                                      didScrollUp: false,
                                      now: t0,
                                      lastPinAt: t0.addingTimeInterval(-1))
    XCTAssertTrue(u.shouldPin)
    XCTAssertTrue(u.followsBottom)
    XCTAssertFalse(u.atBottom)
  }

  /// 사용자가 위로 올리면 따라가기를 끄고 붙이지 않는다.
  func testScrollUpStopsFollowingAndDoesNotPin() {
    let u = FollowScrollPolicy.update(followsBottom: true,
                                      distance: 120,
                                      didScrollUp: true,
                                      now: t0,
                                      lastPinAt: t0.addingTimeInterval(-1))
    XCTAssertFalse(u.followsBottom)
    XCTAssertFalse(u.shouldPin)
  }

  /// 재고정 간격(0.25초) 안에서는 다시 붙이지 않는다.
  func testPinCooldown() {
    let u = FollowScrollPolicy.update(followsBottom: true,
                                      distance: 120,
                                      didScrollUp: false,
                                      now: t0,
                                      lastPinAt: t0.addingTimeInterval(-0.1))
    XCTAssertFalse(u.shouldPin)
    XCTAssertTrue(u.followsBottom)
  }

  /// 위로 올린 직후 점프 억제 중이어도 따라가기는 꺼진 상태를 유지한다.
  func testScrollUpDuringSuppressionKeepsFollowingOff() {
    let jump = FollowScrollPolicy.jumpStarted(now: t0)
    let u = FollowScrollPolicy.update(followsBottom: true,
                                      distance: 300,
                                      didScrollUp: true,
                                      now: t0.addingTimeInterval(0.2),
                                      suppressUntil: jump.suppressUntil)
    XCTAssertFalse(u.followsBottom)
    XCTAssertFalse(u.shouldPin)
  }

  /// 점프 시작 상태 — 따라가기·바닥 표시를 끄고 억제 시각을 1초 뒤로 둔다.
  func testJumpStartedState() {
    let jump = FollowScrollPolicy.jumpStarted(now: t0)
    XCTAssertFalse(jump.followsBottom)
    XCTAssertFalse(jump.atBottom)
    XCTAssertEqual(jump.suppressUntil, t0.addingTimeInterval(FollowScrollPolicy.suppression))
    XCTAssertEqual(FollowScrollPolicy.suppression, 1.0)
  }
}
