import Foundation

// [FEATURE] 연결 끊김 대기·이어쓰기 (2026-11-05)
//
// 사용자 요구: 응답 도중 인터넷이 끊기면 **바로 실패로 끝내지 않고**,
// 설정한 간격(기본 5초)으로 정해진 횟수(기본 10회)만큼 다시 연결을 시도한다.
// 그 사이 사용자는 [중지]로 언제든 빠져나올 수 있어야 한다.
//
// 원칙
//   · 사용자가 [중지]한 요청은 절대 다시 살리지 않는다(`URLError.cancelled`·`CancellationError`).
//   · 키 거부(401)·권한(403)·요청 형식(400) 오류는 기다려도 결과가 같다 → 재시도하지 않는다.
//   · 서버 과부하(5xx)·사용 제한(429)은 **일시 오류**로 보고 같은 대기 규칙을 적용한다.
//   · 재시도 횟수·간격은 사용자가 설정에서 바꾼다(0회 = 자동 재시도 안 함).

/// 연결 끊김 재시도 정책 — 설정 화면에서 바꾸는 값.
public struct NetworkRetryPolicy: Codable, Equatable {
  /// 자동으로 다시 연결할지
  public var enabled: Bool
  /// 한 번 기다리는 시간(초) — 1~60
  public var intervalSeconds: Int
  /// 최대 재시도 횟수 — 0~50
  public var maxAttempts: Int

  public init(enabled: Bool = true, intervalSeconds: Int = 5, maxAttempts: Int = 10) {
    self.enabled = enabled
    self.intervalSeconds = min(60, max(1, intervalSeconds))
    self.maxAttempts = min(50, max(0, maxAttempts))
  }

  /// 사용자 요구 기본값 — 5초 간격 · 10회.
  public static let standard = NetworkRetryPolicy()

  /// 자동 재시도 끔.
  public static let disabled = NetworkRetryPolicy(enabled: false)

  public var interval: TimeInterval { TimeInterval(intervalSeconds) }

  /// `attempt` 는 **이미 실패한 횟수**다. 0부터 시작한다.
  public func canRetry(afterFailures attempt: Int) -> Bool {
    enabled && attempt < maxAttempts
  }
}

/// 재시도 중 화면에 보여 줄 상태.
public struct NetworkRetryProgress: Equatable {
  /// 몇 번째 재시도인가(1부터)
  public let attempt: Int
  public let maxAttempts: Int
  public let waitSeconds: Int

  public init(attempt: Int, maxAttempts: Int, waitSeconds: Int) {
    self.attempt = attempt
    self.maxAttempts = maxAttempts
    self.waitSeconds = waitSeconds
  }
}

public enum NetworkRetry {
  /// 이 오류가 **기다렸다 다시 시도할 가치가 있는가**.
  ///
  /// 네트워크 단절·시간 초과·DNS·프록시의 일시 오류만 참이다.
  /// 인증·권한·형식 오류는 거짓이다(같은 오류가 반복될 뿐이다).
  public static func isRetryable(_ error: Error) -> Bool {
    if error is CancellationError { return false }

    if let url = error as? URLError {
      return isRetryable(urlCode: url.code)
    }

    if let q = error as? QuickTalkError {
      switch q {
      case .networkUnavailable:
        return true
      case .serverFailure(let failure):
        return failure.canRetrySameRequest
      case .detailed(_, let code):
        return code.hasPrefix("E-MAC-NET-0001") || code.hasPrefix("E-MAC-NET-0003")
          || code.hasPrefix("E-MAC-NET-0004")
      default:
        return false
      }
    }

    // 다른 프레임워크가 감싼 `NSError` 도 코드로 판정한다.
    let ns = error as NSError
    if ns.domain == NSURLErrorDomain {
      return isRetryable(urlCode: URLError.Code(rawValue: ns.code))
    }
    return false
  }

  static func isRetryable(urlCode: URLError.Code) -> Bool {
    switch urlCode {
    case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
         .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
         .resourceUnavailable, .dataNotAllowed, .internationalRoamingOff,
         .callIsActive, .backgroundSessionWasDisconnected, .badServerResponse,
         .cannotLoadFromNetwork:
      return true
    default:
      // 사용자가 취소(.cancelled)·인증서 거부(.serverCertificateUntrusted) 등은 재시도하지 않는다.
      return false
    }
  }

  /// 결정적으로 잘린 두 답변을 잇는다 — **겹치는 꼬리/머리**를 한 번만 남긴다.
  ///
  /// 예: partial "…폴더는 /Users/lee/Documents 입니다." + continuation "입니다. 그리고 …"
  ///     → "…폴더는 /Users/lee/Documents 입니다. 그리고 …"
  /// 겹침이 없으면 빈 줄 하나로 구분한다(문단이 붙어 보이지 않게).
  public static func mergeContinuation(_ partial: String, _ continuation: String) -> String {
    let head = partial
    let tail = continuation
    guard !head.isEmpty else { return tail }
    guard !tail.isEmpty else { return head }

    // 너무 짧은 우연 일치("다.", "요.")는 자르지 않는다 — 문장이 사라질 수 있다.
    let minimumOverlap = 8
    let maxOverlap = min(head.count, tail.count)
    guard maxOverlap >= minimumOverlap else { return head + "\n\n" + tail }

    let headChars = Array(head)
    let tailChars = Array(tail)
    var overlap = 0
    for length in stride(from: maxOverlap, through: minimumOverlap, by: -1) {
      if headChars.suffix(length).elementsEqual(tailChars.prefix(length)) {
        overlap = length
        break
      }
    }
    if overlap > 0 {
      let rest = String(tailChars.dropFirst(overlap))
      return head + rest
    }
    // 이어쓰기에서 모델이 이미 쓴 문단을 통째로 반복한 경우 — 완전 중복이면 버린다.
    if head.contains(tail.trimmingCharacters(in: .whitespacesAndNewlines)) {
      return head
    }
    // 문단 경계(빈 줄)가 이미 있으면 그대로 붙이고, 아니면 빈 줄을 넣는다.
    if head.hasSuffix("\n") || tail.hasPrefix("\n") { return head + tail }
    return head + "\n\n" + tail
  }

  /// 이어쓰기 요청 프롬프트 — 원래 요청 + 이미 쓴 답변.
  /// 모델이 이미 쓴 부분을 반복하지 않도록 **한 번만** 분명히 지시한다.
  public static func continuationPrompt(original: String, partial: String) -> String {
    """
    \(original)

    [이어쓰기 요청]
    위 요청에 대한 답변을 아래처럼 쓰다가 네트워크 연결이 끊겼습니다.
    **이미 쓴 내용을 반복하지 말고**, 마지막 문장에 자연스럽게 이어서 나머지를 완성하세요.
    이미 끝난 답변이면 "이미 완료되었습니다" 대신 남은 결론만 짧게 덧붙이세요.

    --- 이미 쓴 답변 ---
    \(partial)
    --- 여기서부터 이어서 ---
    """
  }
}
