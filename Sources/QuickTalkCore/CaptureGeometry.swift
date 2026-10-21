import Foundation
import CoreGraphics

/// 캡처 좌표 변환 — **좌표계를 섞으면 엉뚱한 창을 잡는다**(2026-10-20 실측 버그).
///
/// - `CGWindowListCopyWindowInfo`의 창 사각형: **전역 좌표, 좌상단 원점, y 아래로 증가**(Quartz)
/// - `NSScreen.frame`·`NSView` 좌표: **전역 좌표, 좌하단 원점, y 위로 증가**(AppKit)
/// - 캡처 이미지(`CGImage`) 픽셀: **좌상단 원점**
///
/// 세 좌표계를 한 곳에서만 변환하도록 모아 둔다(순수 함수 — `swift test` 대상).
public enum CaptureGeometry {
  /// Quartz 전역(좌상단 원점) → AppKit 전역(좌하단 원점).
  /// - Parameter primaryScreenHeight: **주 화면**(`NSScreen.screens[0]`)의 높이. 보조 화면 좌표도 이 기준으로 정의된다.
  public static func appKitRect(fromQuartz rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
    CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY,
           width: rect.width, height: rect.height)
  }

  /// AppKit 로컬(좌하단 원점, 화면 크기 기준) → 캡처 이미지의 **픽셀** 사각형(좌상단 원점).
  /// - Parameters:
  ///   - local: 오버레이 뷰 좌표(좌하단 원점)
  ///   - screenHeight: 오버레이(화면) 높이(pt)
  ///   - scale: 화면 배율(1x/2x)
  public static func pixelCrop(local rect: CGRect, screenHeight: CGFloat, scale: CGFloat) -> CGRect {
    let flipped = CGRect(x: rect.minX, y: screenHeight - rect.maxY,
                         width: rect.width, height: rect.height)
    return CGRect(x: flipped.minX * scale, y: flipped.minY * scale,
                  width: flipped.width * scale, height: flipped.height * scale).integral
  }
}
