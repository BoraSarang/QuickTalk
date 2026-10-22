import XCTest
@testable import QuickTalkCore

// [FEATURE] 대화 창 배치 테스트 (2026-10-22)
//
// 배경: 사용자가 "pill 은 항상 포인터인데 설정은 무슨 의미냐"고 지적했다.
// 정리한 규칙을 값으로 고정한다:
//   1) pill 에서 넘어온 대화는 **입력한 자리**에서 창이 이어진다(설정보다 우선).
//   2) 설정(중앙·포인터)은 입력 없이 여는 경우에만 쓰인다.
//   3) 마지막 위치는 **지금 자리를 유지**(nil) — 화면 밖일 때만 앱이 안으로 민다.
//   4) 어떤 경우든 창은 보이는 영역을 벗어나지 않는다.

final class WindowPlacementTests: XCTestCase {

  private let screen = NSRect(x: 0, y: 0, width: 1200, height: 800)
  private let size = NSSize(width: 600, height: 400)

  func testCenterModeIsCenteredInVisibleFrame() {
    let origin = WindowPlacement.origin(mode: .center, size: size,
                                       anchor: nil, visibleFrame: screen)
    XCTAssertEqual(origin, NSPoint(x: 300, y: 200))
  }

  func testAnchorMakesWindowCenteredOnPillCaretEvenInCenterMode() {
    // 중앙 모드여도 pill 자리(anchor)가 있으면 그 자리에서 이어진다 — 점프 없음.
    let anchor = NSPoint(x: 900, y: 600)
    let origin = WindowPlacement.origin(mode: .center, size: size,
                                       anchor: anchor, visibleFrame: screen)
    XCTAssertEqual(origin, WindowPlacement.centered(anchor, size: size))
    XCTAssertEqual(origin, NSPoint(x: 600, y: 400))
  }

  func testPointerModeUsesAnchor() {
    let anchor = NSPoint(x: 500, y: 500)
    let origin = WindowPlacement.origin(mode: .mousePointer, size: size,
                                       anchor: anchor, visibleFrame: screen)
    XCTAssertEqual(origin, NSPoint(x: 200, y: 300))
  }

  func testPointerModeWithoutAnchorFallsBackToCenter() {
    // 포인터를 모를 때(화면 밖 등) 창이 엉뚱한 곳에 뜨지 않게 중앙으로.
    let origin = WindowPlacement.origin(mode: .mousePointer, size: size,
                                       anchor: nil, visibleFrame: screen)
    XCTAssertEqual(origin, NSPoint(x: 300, y: 200))
  }

  func testLastPositionWithoutAnchorKeepsCurrentFrame() {
    // nil = "옮긴 자리를 그대로 둔다" — 앱이 프레임을 건드리지 않는다.
    XCTAssertNil(WindowPlacement.origin(mode: .lastPosition, size: size,
                                       anchor: nil, visibleFrame: screen))
  }

  func testLastPositionStillFollowsPillAnchor() {
    let anchor = NSPoint(x: 400, y: 400)
    let origin = WindowPlacement.origin(mode: .lastPosition, size: size,
                                       anchor: anchor, visibleFrame: screen)
    XCTAssertEqual(origin, NSPoint(x: 100, y: 200))
  }

  func testOriginIsClampedIntoVisibleFrame() {
    // 화면 오른쪽 위 모서리에서 연 경우 — 창이 화면 밖으로 나가지 않는다.
    let anchor = NSPoint(x: 1190, y: 790)
    let origin = WindowPlacement.origin(mode: .mousePointer, size: size,
                                       anchor: anchor, visibleFrame: screen)
    XCTAssertEqual(origin, NSPoint(x: 600, y: 400)) // maxX - width, maxY - height
  }

  func testClampKeepsOriginWhenAlreadyInside() {
    let inside = NSPoint(x: 100, y: 100)
    XCTAssertEqual(WindowPlacement.clamped(inside, size: size, in: screen), inside)
  }

  func testClampHandlesWindowLargerThanScreen() {
    // 화면보다 큰 창은 최소값(좌하단)에 붙인다 — 음수 좌표로 밀려나지 않게.
    let big = NSSize(width: 2000, height: 1600)
    let origin = WindowPlacement.clamped(NSPoint(x: -500, y: -500), size: big, in: screen)
    XCTAssertEqual(origin, NSPoint(x: 0, y: 0))
  }

  func testClampedSurvivesNegativeScreenOrigin() {
    // 보조 모니터가 주 화면 왼쪽/아래에 있을 때(음수 원점)도 같은 규칙.
    let left = NSRect(x: -1600, y: -200, width: 1600, height: 900)
    let anchor = NSPoint(x: -800, y: 400)
    let origin = WindowPlacement.origin(mode: .mousePointer, size: size,
                                       anchor: anchor, visibleFrame: left)
    XCTAssertEqual(origin, WindowPlacement.centered(anchor, size: size))
    XCTAssertEqual(origin, NSPoint(x: -1100, y: 200))
  }
}
