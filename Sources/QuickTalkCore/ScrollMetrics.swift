import CoreGraphics

/// 스크롤 위치 계산 — AppKit 값을 순수 함수로 분리해 테스트한다.
///
/// 배경(2026-10-27): "맨 아래로" 버튼이 스크롤 중에 뜨지 않았다. 원인은
/// `GeometryReader`+`PreferenceKey` 선호도가 **레이아웃 때만** 갱신되고
/// 사용자가 스크롤해도 값이 그대로였던 것 — macOS 의 `ScrollView` 는 `NSScrollView` 라
/// 스크롤이 순수 transform 이다. 이제 `NSScrollView` 값을 직접 읽어 판정한다.
public enum ScrollMetrics {
  /// 문서 끝에서 뷰포트 바닥까지의 거리(pt). 위로 스크롤할수록 커진다.
  /// 오버스크롤(음수)은 0으로 눌러 "맨 아래"로 취급한다.
  public static func distanceFromBottom(documentHeight: CGFloat,
                                         offsetY: CGFloat,
                                         viewportHeight: CGFloat) -> CGFloat {
    max(0, documentHeight - (offsetY + viewportHeight))
  }

  /// 맨 아래로 볼지 — 기본 24pt 여유(관성·여백 오차 흡수).
  public static func isAtBottom(distance: CGFloat, threshold: CGFloat = 24) -> Bool {
    distance <= threshold
  }
}
