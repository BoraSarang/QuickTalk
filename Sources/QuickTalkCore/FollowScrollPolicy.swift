import Foundation

/// 자동 스크롤(바닥 따라가기) 판정 — AppKit 값을 순수 함수로 분리해 테스트한다.
///
/// 배경(v0.32.1, 2026-11-06 사용자 지적): 대화 목차에서 질문으로 **바로가기**한 뒤
/// 스크롤을 내리면 가끔 맨 아래로 튀었다. 원인은 두 가지가 겹친 것 —
/// 1) 점프 직후 `followsBottom` 이 true 로 남아, 중간에서 스크롤을 내리면 "내용이 늘었다"고
///    오판해 `pinBottom()` 을 호출했다.
/// 2) 점프 중 레이아웃이 확정되기 전 `distance` 가 잠깐 0 으로 보고되면 `atBottom` 이 true 가 되어
///    따라가기가 다시 켜졌다.
///
/// 그래서 **프로그램이 이동을 시작한 뒤 짧은 구간(`suppression`)** 동안은
/// 자동 핀도, 따라가기 재개도 하지 않는다. 사용자가 직접 바닥에 닿았을 때만 다시 켠다.
public enum FollowScrollPolicy {
  /// 점프 직후 자동 핀을 멈추는 시간(초). `scrollTo` 재시도(0.28초)와
  /// 레이아웃 확정(수 프레임)을 모두 덮는다.
  public static let suppression: TimeInterval = 1.0

  /// 거리 기반 재고정 최소 간격(초) — 스크롤 알림은 초당 수십 번 온다.
  public static let pinCooldown: TimeInterval = 0.25

  /// 한 번의 스크롤 리포트를 반영한 결과.
  public struct Update: Equatable {
    /// 앞으로 내용이 늘 때 바닥을 따라갈지.
    public let followsBottom: Bool
    /// 맨 아래에 있는지(우하단 "맨 아래로" 버튼 표시용).
    public let atBottom: Bool
    /// 지금 `pinBottom()` 을 보내야 하는지.
    public let shouldPin: Bool

    public init(followsBottom: Bool, atBottom: Bool, shouldPin: Bool) {
      self.followsBottom = followsBottom
      self.atBottom = atBottom
      self.shouldPin = shouldPin
    }
  }

  /// 스크롤 리포트 하나를 반영한다.
  ///
  /// - Parameters:
  ///   - followsBottom: 직전까지 바닥을 따라가고 있었는지.
  ///   - distance: 문서 끝까지 남은 거리(pt).
  ///   - didScrollUp: 이번 리포트에서 사용자가 위로 올렸는지.
  ///   - now: 현재 시각.
  ///   - suppressUntil: 이 시각까지는 프로그램 이동 중이라 자동 핀·재개를 하지 않는다.
  ///   - lastPinAt: 마지막으로 바닥에 붙인 시각.
  public static func update(followsBottom: Bool,
                            distance: CGFloat,
                            didScrollUp: Bool,
                            now: Date,
                            suppressUntil: Date = .distantPast,
                            lastPinAt: Date = .distantPast) -> Update {
    let atEnd = ScrollMetrics.isAtBottom(distance: distance)
    var follows = followsBottom
    // 위로 올렸으면 즉시 따라가기를 멈춘다(읽는 중 콘텐츠가 스크롤을 납치하지 않게).
    if didScrollUp { follows = false }

    // 점프 직후 — 레이아웃이 확정되기 전의 잘못된 `atBottom` 으로 따라가기를 되살리지 않는다.
    if now < suppressUntil {
      return Update(followsBottom: follows, atBottom: atEnd, shouldPin: false)
    }

    if atEnd {
      follows = true
      return Update(followsBottom: follows, atBottom: true, shouldPin: false)
    }

    let cooledDown = now.timeIntervalSince(lastPinAt) > pinCooldown
    return Update(followsBottom: follows,
                  atBottom: false,
                  shouldPin: follows && cooledDown)
  }

  /// 프로그램 이동(목차·검색 결과 점프)을 시작할 때의 상태 —
  /// 따라가기를 끄고 잠시 자동 핀을 막는다.
  public static func jumpStarted(now: Date,
                                 suppressFor duration: TimeInterval = suppression) -> (followsBottom: Bool, atBottom: Bool, suppressUntil: Date) {
    (false, false, now.addingTimeInterval(duration))
  }
}
