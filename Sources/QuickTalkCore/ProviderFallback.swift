import Foundation

// [FEATURE] 예비 모델 폴백 (2026-10-21)
//
// 주 모델이 **일시적으로 쓸 수 없을 때**(429 사용 제한·5xx·시간 초과·연결 실패) 답변 전체가
// 오류로 끝나는 대신, 사용자가 지정한 **예비 프로바이더로 1회** 다시 시도한다.
//
// 원칙
// - **1회만** 넘어간다(사슬·무한 재시도 없음). 예비도 실패하면 그 오류를 그대로 보여 준다.
// - 예비 모델이 없거나 준비되지 않았으면(키·모델·주소) 아무 것도 하지 않는다 — 주 모델 오류를 그대로 알린다.
// - 403(정책 거부)은 넘어가지 않는다. 다른 모델로 우회하면 제공자의 거부를 숨기게 된다.
// - 첨부 거부(413·422)는 `AttachmentRetry` 사다리가 먼저 처리한다 — 여기서 또 넘어가면 지연만 늘어난다.
// - 이미 글자가 화면에 나간 뒤에는 넘어가지 않는다(호출부 판단 — 중복 출력 방지).

public enum ProviderFallback {
  /// 이 오류에서 예비 모델을 시도할 가치가 있는가.
  public static func allowed(after error: Error) -> Bool {
    // 사용자가 [중지]로 취소한 요청 — 예비 모델로 넘어가면 안 된다(멈춘 응답이 되살아난다).
    if error is CancellationError { return false }
    if let url = error as? URLError {
      switch url.code {
      case .cancelled:
        return false
      case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed,
           .networkConnectionLost, .notConnectedToInternet, .secureConnectionFailed,
           .badServerResponse, .resourceUnavailable, .dataNotAllowed, .internationalRoamingOff:
        return true
      default:
        return false
      }
    }
    guard let e = error as? QuickTalkError else {
      // 분류되지 않은 오류 — 한 번 시도할 가치가 있다.
      return true
    }
    switch e {
    case .networkUnavailable:
      return true
    case .serverFailure(let f):
      switch f {
      case .upstream, .rateLimited, .emptyResponse,
           .keyRejected, .requestRejected:
        // 일시 오류 · 사용 제한 · 빈 응답 · 주 모델의 키/요청 거부.
        // 키 거부도 예비 모델로 답하고 **안내에 원인을 함께 적는다**(설정 오류를 숨기지 않는다).
        return true
      case .forbidden, .attachmentTooLarge, .attachmentUnsupported:
        return false
      }
    case .detailed(_, let code):
      // 네트워크·시간 초과 계열만. 모델 미지정 같은 설정 오류는 넘어가지 않는다.
      return code.hasPrefix("E-MAC-NET-")
    default:
      return false
    }
  }

  /// 안내 한 줄에 넣을 **짧은 원인** — 서버 본문·제공자 코드 문자열은 노출하지 않는다.
  /// (`[server_error]` 같은 업스트림 코드는 진단용으로만 쓰고, 화면에는 앱 표준 코드를 남긴다.)
  public static func reason(for error: Error) -> String {
    if let q = error as? QuickTalkError, case .serverFailure(let f) = q {
      let label: String
      switch f {
      case .rateLimited: label = L("사용 제한")
      case .upstream: label = L("모델 서버 오류")
      case .emptyResponse: label = L("빈 응답")
      case .keyRejected: label = L("키 거부")
      case .requestRejected: label = L("요청 거부")
      case .forbidden: label = L("접근 거부")
      case .attachmentTooLarge: label = L("첨부 용량 초과")
      case .attachmentUnsupported: label = L("첨부 미지원")
      }
      return Lf("%@ (HTTP %d · %@)", label, f.httpStatus, f.code)
    }
    if let u = error as? URLError {
      let label: String
      switch u.code {
      case .timedOut: label = L("시간 초과")
      case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed: label = L("연결 실패")
      case .notConnectedToInternet, .networkConnectionLost: label = L("네트워크 끊김")
      default: label = L("네트워크 오류")
      }
      return Lf("%@ (NSURLError %d)", label, u.code.rawValue)
    }
    return AIErrorText.shortDetail(for: error)
  }

  /// 예비 프로바이더가 실제로 호출 가능한 상태인가 — 빈 모델·키 없음이면 넘어가 봐야 바로 실패한다.
  public static func isUsable(_ p: LLMProviderConfig,
                              keyExists: (String) -> Bool) -> Bool {
    guard p.enabled else { return false }
    switch p.type {
    case .appleFM:
      return true
    case .ollama:
      return !p.model.isEmpty && URL(string: p.baseURL) != nil
    case .openAICompatible:
      guard !p.secretID.isEmpty, keyExists(p.secretID) else { return false }
      return !p.model.isEmpty && URL(string: p.baseURL) != nil
    }
  }
}
