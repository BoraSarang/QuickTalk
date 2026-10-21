import Foundation

/// AI 호출 실패를 **정확한 원인**으로 바꾼다.
///
/// 이전에는 `URLError`(연결 거부·시간 초과·오프라인·TLS·DNS)가 모두
/// `E-MAC-NET-0001 / "응답을 가져오지 못했습니다"`로 뭉개져 원인을 알 수 없었다.
/// 여기서는 ① 앱 표준 코드 ② 사용자 문구(정확한 원인 + 호스트) ③ 상태 카드용 짧은 문구를 만든다.
///
/// - 서버 응답 **본문은 절대 넣지 않는다** — 상태코드와 서버가 준 **코드**(`[E-AND-…]`)만 쓴다.
/// - 호스트는 `baseURL`의 host·port만 쓴다(경로·쿼리에 키가 섞여도 노출되지 않는다).
public enum AIErrorText {

  // MARK: - 코드

  /// 오류 → 앱 표준 에러코드. 모르는 오류는 네트워크 오류로 본다(기존 동작과 같다).
  public static func code(for error: Error) -> String {
    if let q = error as? QuickTalkError { return q.code }
    return "E-MAC-NET-0001"
  }

  // MARK: - 사용자 문구(말풍선·테스트 결과)

  /// `"(오류 CODE) 정확한 원인"` — 말풍선에 그대로 들어가는 한 덩어리.
  public static func userText(for error: Error, url: URL? = nil) -> String {
    if let q = error as? QuickTalkError {
      if case .serverFailure(let f) = q {
        return Lf("(오류 %@) %@", f.code, f.userMessage + serverHostSuffix(url))
      }
      if let text = q.userText { return text }
    }
    return Lf("(오류 %@) %@", code(for: error), detail(for: error, url: url))
  }

  /// 코드 없이 원인만 — 테스트 결과·설정 화면에서 코드와 따로 보여 줄 때.
  public static func detail(for error: Error, url: URL? = nil) -> String {
    if let q = error as? QuickTalkError {
      switch q {
      case .serverFailure(let f):
        return f.userMessage + serverHostSuffix(url)
      case .detailed(let message, _):
        return message
      case .networkUnavailable:
        return Lf("서버가 예상 밖의 응답을 보냈습니다%@", hostLabel(url))
      case .providerNotConfigured:
        return L("활성 AI 프로바이더가 없습니다 — 설정 > AI에서 추가하세요")
      case .missingAPIKey:
        return L("API 키가 없습니다 — 설정 > AI에서 키를 저장하세요")
      case .emptySubmission:
        return L("보낼 내용이 없습니다")
      case .unsupportedAttachment(let name, _):
        return Lf("지원하지 않는 첨부입니다: %@", name)
      case .speechDenied:
        return L("마이크·음성 권한이 없습니다")
      }
    }
    if let u = error as? URLError {
      return urlErrorDetail(u, url: url)
    }
    return error.localizedDescription
  }

  /// 상태 카드 한 줄 — 서버 오류는 **원인·HTTP 상태·서버 코드**를 모두 남긴다.
  /// (연결 오류는 상태 카드에서 짧게, 상세 문구는 `detail`이 담당한다)
  public static func shortDetail(for error: Error) -> String {
    if let q = error as? QuickTalkError {
      switch q {
      case .serverFailure(let f):
        return f.statusMessage
      case .detailed(let message, _):
        return message
      case .missingAPIKey:
        return L("API 키 없음")
      case .providerNotConfigured:
        return L("활성 AI 없음")
      case .networkUnavailable:
        return L("예상 밖의 응답")
      default:
        return detail(for: error)
      }
    }
    if let u = error as? URLError {
      switch u.code {
      case .cannotConnectToHost: return Lf("연결 거부 (%d)", u.code.rawValue)
      case .cannotFindHost: return Lf("호스트 없음 (%d)", u.code.rawValue)
      case .dnsLookupFailed: return Lf("DNS 실패 (%d)", u.code.rawValue)
      case .timedOut: return Lf("시간 초과 (%d)", u.code.rawValue)
      case .notConnectedToInternet: return Lf("오프라인 (%d)", u.code.rawValue)
      case .networkConnectionLost: return Lf("연결 끊김 (%d)", u.code.rawValue)
      case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
           .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
        return Lf("TLS 실패 (%d)", u.code.rawValue)
      case .badURL, .unsupportedURL: return Lf("잘못된 주소 (%d)", u.code.rawValue)
      case .userAuthenticationRequired: return Lf("인증 필요 (%d)", u.code.rawValue)
      case .cancelled: return L("취소됨")
      default: return u.localizedDescription
      }
    }
    return error.localizedDescription
  }

  /// 로그용 — 사용자 문구·본문 없이 원인 종류만(연결 거부 = `URLError -1004`).
  public static func logLabel(for error: Error) -> String {
    if let q = error as? QuickTalkError {
      if case .serverFailure(let f) = q {
        return "serverFailure \(f.httpStatus) \(f.label)"
      }
      return q.code
    }
    if let u = error as? URLError { return "URLError \(u.code.rawValue)" }
    return "error"
  }

  /// 연결 자체가 안 된 오류인가(서버 실행 안내를 덧붙일 대상).
  public static func isConnectionFailure(_ error: Error) -> Bool {
    guard let u = error as? URLError else { return false }
    switch u.code {
    case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
         .notConnectedToInternet, .networkConnectionLost, .timedOut:
      return true
    default:
      return false
    }
  }

  // MARK: - URLError 상세

  /// `URLError` → 정확한 원인 문구. 시스템 언어가 아니라 **앱 표시 언어**로 쓴다.
  public static func urlErrorDetail(_ e: URLError, url: URL? = nil) -> String {
    let target = hostLabel(url ?? e.failingURL)
    switch e.code {
    case .cannotConnectToHost:
      return Lf("서버에 연결할 수 없습니다%@ — 주소·포트와 서버 실행 상태를 확인하세요 (연결 거부, NSURLError %d)",
                target, e.code.rawValue)
    case .cannotFindHost:
      return Lf("호스트를 찾을 수 없습니다%@ (NSURLError %d)", target, e.code.rawValue)
    case .dnsLookupFailed:
      return Lf("호스트 이름을 찾지 못했습니다(DNS)%@ (NSURLError %d)", target, e.code.rawValue)
    case .timedOut:
      return Lf("서버 응답이 제한 시간 안에 오지 않았습니다%@ — 서버가 켜져 있는지 확인하세요 (시간 초과, NSURLError %d)",
                target, e.code.rawValue)
    case .notConnectedToInternet:
      return Lf("인터넷에 연결되어 있지 않습니다 (NSURLError %d)", e.code.rawValue)
    case .networkConnectionLost:
      return Lf("서버와의 연결이 끊겼습니다%@ (NSURLError %d)", target, e.code.rawValue)
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
      return Lf("보안 연결(TLS/인증서)에 실패했습니다%@ (NSURLError %d)", target, e.code.rawValue)
    case .badURL, .unsupportedURL:
      return Lf("주소가 올바르지 않습니다%@ (NSURLError %d)", target, e.code.rawValue)
    case .userAuthenticationRequired:
      return Lf("서버가 인증을 요구합니다%@ (NSURLError %d)", target, e.code.rawValue)
    case .cancelled:
      return L("요청이 취소되었습니다")
    case .resourceUnavailable:
      return Lf("서버가 지금은 응답할 수 없습니다%@ (NSURLError %d)", target, e.code.rawValue)
    default:
      return Lf("%@%@ (NSURLError %d)", e.localizedDescription, target, e.code.rawValue)
    }
  }

  /// ` (host:port)` — host가 없으면 빈 문자열(경로·쿼리는 절대 쓰지 않는다).
  private static func hostLabel(_ url: URL?) -> String {
    guard let host = url?.host, !host.isEmpty else { return "" }
    if let port = url?.port { return " (\(host):\(port))" }
    return " (\(host))"
  }

  /// ` — 서버: host:port` — 서버 오류가 **어느 서버**에서 났는지 붙인다.
  private static func serverHostSuffix(_ url: URL?) -> String {
    guard let host = url?.host, !host.isEmpty else { return "" }
    let target = url?.port.map { "\(host):\($0)" } ?? host
    return " — " + Lf("서버: %@", target)
  }
}
