import XCTest
import CoreGraphics
@testable import QuickTalkCore

/// 캡처 좌표 회귀 방지(2026-10-20 실측 버그: "윈도우 캡처가 엉뚱한 창을 잡는다").
///
/// 원인은 좌표계 혼용이었다 — `CGWindowList`는 좌상단 원점(y아래), AppKit·오버레이 뷰는 좌하단 원점(y위),
/// 캡처 이미지 픽셀은 다시 좌상단 원점. 변환을 `CaptureGeometry` 한 곳에서만 하도록 모았다.
final class CaptureGeometryTests: XCTestCase {

  private let primaryHeight: CGFloat = 1120

  // MARK: - Quartz → AppKit

  func testQuartzRectIsFlippedVertically() {
    // 화면 위쪽(y 40..640)에 있는 창
    let quartz = CGRect(x: 100, y: 40, width: 800, height: 600)
    let appKit = CaptureGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: primaryHeight)

    XCTAssertEqual(appKit.minX, 100, "x는 그대로")
    XCTAssertEqual(appKit.width, 800)
    XCTAssertEqual(appKit.height, 600)
    XCTAssertEqual(appKit.minY, 480, "1120 - 640 = 480 (좌하단 원점에서의 아래쪽 y)")
    XCTAssertEqual(appKit.maxY, 1080)
  }

  func testQuartzRectAtTopBecomesAppKitRectAtBottom() {
    // 화면 맨 위 40pt(메뉴바 자리) 띠 → AppKit에서는 맨 아래 40pt
    let bar = CGRect(x: 0, y: 0, width: 1440, height: 40)
    let flipped = CaptureGeometry.appKitRect(fromQuartz: bar, primaryScreenHeight: primaryHeight)
    XCTAssertEqual(flipped.minY, 1080)
    XCTAssertEqual(flipped.maxY, 1120)
  }

  /// 회귀의 핵심: 변환한 사각형에 대해 **보이는 위치의 점**이 들어 있고,
  /// 변환을 빼먹었을 때 들어가던 **뒤집힌 점**은 들어가지 않아야 한다.
  func testHitTestUsesVisiblePositionNotMirroredOne() {
    let quartz = CGRect(x: 200, y: 40, width: 700, height: 300)    // 화면 위쪽 띠
    let appKit = CaptureGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: primaryHeight)

    let visibleCenter = CGPoint(x: quartz.midX, y: primaryHeight - quartz.midY)
    XCTAssertTrue(appKit.contains(visibleCenter), "사용자가 보는 그 자리의 점이 그 창에 잡혀야 한다")

    let mirrored = CGPoint(x: quartz.midX, y: quartz.midY)          // 변환을 빼먹은 예전 좌표
    XCTAssertFalse(appKit.contains(mirrored), "좌표를 섞으면 이 점이 잡혀 엉뚱한 창이 선택된다")
  }

  // MARK: - 오버레이 로컬 → 이미지 픽셀

  func testPixelCropFlipsAndScales() {
    // 오버레이 로컬(좌하단 원점)에서 화면 위쪽(y 1000..1060)을 골랐다
    let local = CGRect(x: 10, y: 1000, width: 100, height: 60)
    let px = CaptureGeometry.pixelCrop(local: local, screenHeight: 1120, scale: 2)

    XCTAssertEqual(px.minX, 20, "x는 배율만 적용")
    XCTAssertEqual(px.minY, 120, "(1120 - 1060) * 2 = 120 — 이미지 좌상단 원점")
    XCTAssertEqual(px.width, 200)
    XCTAssertEqual(px.height, 120)
  }

  func testPixelCropIsIntegral() {
    let local = CGRect(x: 10.4, y: 900.2, width: 99.6, height: 59.4)
    let px = CaptureGeometry.pixelCrop(local: local, screenHeight: 1120, scale: 2)
    XCTAssertEqual(px, px.integral, "픽셀 사각형은 정수여야 한다(`CGImage.cropping`이 잘라낼 수 있게)")
    // 잘라낸 영역이 요청 영역을 포함한다(잘림 없음)
    let scaled = CGRect(x: local.minX * 2, y: (1120 - local.maxY) * 2,
                        width: local.width * 2, height: local.height * 2)
    XCTAssertTrue(px.contains(scaled))
  }
}
