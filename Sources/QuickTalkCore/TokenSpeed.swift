import Foundation

/// 응답 생성 속도 — **초당 토큰(추정)**.
///
/// 앱에는 실제 토크나이저가 없다. 그래서 대화 예산 계산과 같은 보수적 추정
/// (`ConversationMemory.estimateTokens`)을 쓴다. 청구 토큰 수와 같지는 않지만
/// "이 모델이 이 답변을 어느 속도로 냈는가"를 모델·설정끼리 비교하기에 충분하다.
public enum TokenSpeed {
  /// 이보다 짧은 답변은 속도를 표시하지 않는다 — 숫자가 크게 튀어 의미가 없다.
  public static let minimumTokens = 12
  /// 이보다 빠른 응답(1초 미만)도 표시하지 않는다.
  public static let minimumMilliseconds = 1_000
  /// 스트리밍 중 실시간 값의 최소 표본 — 첫 글자만 나온 순간의 수백 tok/s 를 숨긴다.
  public static let minimumLiveSeconds = 0.5
  public static let minimumLiveTokens = 4

  /// 완료된 답변의 평균 속도 — 추정 토큰 ÷ **전체 걸린 시간**(첫 토큰 대기·도구 호출 포함).
  ///
  /// 도구를 여러 번 쓴 에이전트 답변은 낮게 나온다. 그건 실제 체감 속도이므로 보정하지 않는다.
  public static func tokensPerSecond(text: String, elapsedMs: Int?) -> Double? {
    guard let elapsedMs, elapsedMs >= minimumMilliseconds else { return nil }
    let tokens = ConversationMemory.estimateTokens(text)
    guard tokens >= minimumTokens else { return nil }
    return Double(tokens) / (Double(elapsedMs) / 1_000)
  }

  /// 스트리밍 중 **지금까지**의 속도 — 첫 글자가 온 뒤의 경과 시간으로 나눈다.
  /// (첫 토큰 대기 시간은 생성 속도가 아니므로 뺀다.)
  public static func liveTokensPerSecond(tokens: Int, since firstDeltaAt: Date?,
                                         now: Date = Date()) -> Double? {
    guard tokens >= minimumLiveTokens, let firstDeltaAt else { return nil }
    let seconds = now.timeIntervalSince(firstDeltaAt)
    guard seconds >= minimumLiveSeconds else { return nil }
    return Double(tokens) / seconds
  }

  /// 화면 표기 — 10 미만은 소수 한 자리(로컬 모델 4.2 tok/s), 그 이상은 정수.
  public static func label(_ rate: Double) -> String {
    guard rate.isFinite, rate > 0 else { return "" }
    if rate < 10 { return String(format: "%.1f tok/s", rate) }
    return String(format: "%.0f tok/s", rate)
  }
}
