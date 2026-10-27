import XCTest
@testable import QuickTalkCore

final class ScrollMetricsTests: XCTestCase {
  /// 맨 아래에 있으면 남은 거리 0
  func testDistanceAtBottomIsZero() {
    XCTAssertEqual(ScrollMetrics.distanceFromBottom(documentHeight: 3801, offsetY: 3401,
                                                    viewportHeight: 400), 0)
  }

  /// 중간이면 남은 거리 = 문서 - (오프셋 + 뷰포트)
  func testDistanceInMiddle() {
    XCTAssertEqual(ScrollMetrics.distanceFromBottom(documentHeight: 3801, offsetY: 1000,
                                                    viewportHeight: 400), 2401)
  }

  /// 오버스크롤(음수)은 0으로 눌러 "맨 아래"로 취급한다
  func testOverScrollClampsToZero() {
    XCTAssertEqual(ScrollMetrics.distanceFromBottom(documentHeight: 3801, offsetY: 3601,
                                                    viewportHeight: 400), 0)
  }

  /// 문서가 뷰포트보다 짧으면 항상 맨 아래
  func testShortDocumentIsAtBottom() {
    XCTAssertEqual(ScrollMetrics.distanceFromBottom(documentHeight: 120, offsetY: 0,
                                                    viewportHeight: 400), 0)
  }

  /// 판정 여유 24pt — 경계 포함, 그 밖은 아님
  func testAtBottomThreshold() {
    XCTAssertTrue(ScrollMetrics.isAtBottom(distance: 0))
    XCTAssertTrue(ScrollMetrics.isAtBottom(distance: 24))
    XCTAssertFalse(ScrollMetrics.isAtBottom(distance: 24.1))
    XCTAssertFalse(ScrollMetrics.isAtBottom(distance: 2401))
    XCTAssertTrue(ScrollMetrics.isAtBottom(distance: 30, threshold: 40))
  }
}
