import Foundation

// [FEATURE] 대화 창 배치 계산 (2026-10-22)
//
// 왜 Core 로 뺐나: 배치 규칙(“중앙 / 포인터 / 마지막 위치 + 화면 밖 클램프 + pill 자리 우선”)이
// AppDelegate 안에만 있으면 **값으로 고정할 수 없어서** 회귀가 조용히 생긴다.
// 여기서는 순수 계산만 한다 — 창을 실제로 옮기는 일은 앱이 한다.

public enum WindowPlacement {
  /// 창의 좌하단(NSWindow origin)을 계산한다.
  /// - Parameters:
  ///   - mode: 사용자가 고른 위치 설정
  ///   - size: 창 크기
  ///   - anchor: **입력이 시작된 자리**(마우스 포인터 · pill 캐럿). 있으면 설정보다 우선한다.
  ///   - visibleFrame: 메뉴바·Dock 을 뺀 화면 영역
  /// - Returns: nil = "지금 위치를 그대로 둔다"(마지막 위치 모드이면서 anchor 도 없을 때).
  public static func origin(mode: NewWindowPosition, size: NSSize,
                            anchor: NSPoint?, visibleFrame: NSRect) -> NSPoint? {
    // ★ pill 에서 넘어온 대화는 **입력한 자리**에서 이어진다 — 중앙 모드여도 점프하지 않는다.
    if let anchor {
      return clamped(centered(anchor, size: size), size: size, in: visibleFrame)
    }
    switch mode {
    case .center, .mousePointer:
      // 포인터 위치를 모를 때(화면 밖 등)의 안전한 기본값도 중앙이다.
      return clamped(centered(NSPoint(x: visibleFrame.midX, y: visibleFrame.midY), size: size),
                     size: size, in: visibleFrame)
    case .lastPosition:
      return nil
    }
  }

  /// 점을 중심으로 하는 창의 좌하단.
  public static func centered(_ point: NSPoint, size: NSSize) -> NSPoint {
    NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
  }

  /// 창이 보이는 영역 밖으로 나가지 않게 안쪽으로 민다(화면보다 창이 크면 최소값 쪽에 붙인다).
  public static func clamped(_ origin: NSPoint, size: NSSize, in visibleFrame: NSRect) -> NSPoint {
    let maxX = max(visibleFrame.minX, visibleFrame.maxX - size.width)
    let maxY = max(visibleFrame.minY, visibleFrame.maxY - size.height)
    return NSPoint(x: min(max(origin.x, visibleFrame.minX), maxX),
                   y: min(max(origin.y, visibleFrame.minY), maxY))
  }
}
