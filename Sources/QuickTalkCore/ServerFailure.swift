import Foundation

/// 서버(로컬 프록시·업스트림) 응답 실패의 **분류**.
///
/// 이전 구현은 이미지가 실린 요청의 **모든 4xx를 "모델이 이미지를 거부"로 뭉개고**,
/// 5xx·빈 본문은 네트워크 오류로 표시했다 → 401(토큰 불일치)·429(사용 제한)·413(용량)이
/// "파일 전송 실패"로 오진되고 불필요한 재시도까지 돌았다(핸드오프 2026-10-20 P2).
/// 분류별로 **재시도 전략**이 갈리므로 여기서 한 곳에 모아 판정한다.
public enum ServerFailure: Equatable {
  /// 401 — 서버가 키/토큰 거부
  case keyRejected(status: Int, code: String?)
  /// 403 — 접근 거부(게이트)
  case forbidden(status: Int, code: String?)
  /// 413 — 첨부가 커서 거부
  case attachmentTooLarge(status: Int, code: String?)
  /// 400/422 — 형식·모델 능력(이미지를 못 받는 모델 등)
  case attachmentUnsupported(status: Int, code: String?)
  /// 429 — 사용 제한
  case rateLimited(status: Int, code: String?)
  /// 5xx — 업스트림 일시 오류
  case upstream(status: Int, code: String?)
  /// 그 밖의 4xx(404·405·426 …) — 재시도해도 같은 결과
  case requestRejected(status: Int, code: String?)
  /// 200인데 본문이 비어 있음
  case emptyResponse(status: Int)

  public var httpStatus: Int {
    switch self {
    case .keyRejected(let s, _), .forbidden(let s, _), .attachmentTooLarge(let s, _),
         .attachmentUnsupported(let s, _), .rateLimited(let s, _), .upstream(let s, _),
         .requestRejected(let s, _), .emptyResponse(let s):
      return s
    }
  }

  /// 서버가 알려준 코드(예: 프록시 `E-AND-AUTH-0004`). 로그·진단용.
  public var serverCode: String? {
    switch self {
    case .keyRejected(_, let c), .forbidden(_, let c), .attachmentTooLarge(_, let c),
         .attachmentUnsupported(_, let c), .rateLimited(_, let c), .upstream(_, let c),
         .requestRejected(_, let c):
      return c
    case .emptyResponse:
      return nil
    }
  }

  /// 앱 표준 에러코드
  public var code: String {
    switch self {
    case .keyRejected, .forbidden: return "E-MAC-KEY-0002"
    case .attachmentTooLarge: return "E-MAC-ATT-0002"
    case .attachmentUnsupported: return "E-MAC-ATT-0003"
    case .rateLimited: return "E-MAC-NET-0004"
    case .upstream, .emptyResponse: return "E-MAC-NET-0003"
    case .requestRejected: return "E-MAC-NET-0005"
    }
  }

  /// 사용자에게 보여줄 문구 — **서버 본문을 그대로 노출하지 않는다**([HARD] 로그 마스킹·정보 노출 금지).
  /// 서버 코드만 덧붙여 진단에 쓸 수 있게 한다.
  public var userMessage: String {
    let base: String
    switch self {
    case .keyRejected:
      base = L("서버가 접속 키를 거부했습니다 — 설정 > AI에서 API 키(프록시 접속 토큰)를 확인하세요")
    case .forbidden:
      base = L("서버가 요청을 거부했습니다(접근 권한)")
    case .attachmentTooLarge:
      base = L("첨부가 커서 서버가 거부했습니다")
    case .attachmentUnsupported:
      base = L("이 모델이 첨부(주로 이미지)를 받지 못합니다")
    case .rateLimited:
      base = L("사용 제한에 걸렸습니다 — 잠시 후 다시 시도해 주세요")
    case .upstream:
      base = L("모델 서버(업스트림)가 일시적으로 요청을 처리할 수 없습니다 — 과부하·점검·프록시 장애일 수 있습니다. 잠시 후 다시 시도하거나 다른 모델을 선택하세요")
    case .requestRejected:
      base = L("서버가 요청을 거부했습니다 — 주소·모델 이름·요청 형식을 확인하세요")
    case .emptyResponse:
      base = L("모델 서버가 빈 응답을 보냈습니다 — 프록시가 스트리밍을 지원하지 않거나 응답을 잘못 감쌌을 수 있습니다")
    }
    if let c = serverCode { return Lf("%@ [%@] (HTTP %d)", base, c, httpStatus) }
    return Lf("%@ (HTTP %d)", base, httpStatus)
  }

  /// 상태 카드용 — **한 화면에 들어오는 길이**로 원인·상태·서버 코드·다음 행동을 담는다.
  /// 말풍선·연결 테스트는 더 긴 `userMessage`를 쓴다.
  public var statusMessage: String {
    let code = serverCode.map { " · \($0)" } ?? ""
    switch self {
    case .upstream:
      return Lf("HTTP %d%@ — 모델 서버 과부하·점검·프록시 오류 가능. 잠시 후 재시도하거나 다른 모델을 선택하세요",
                httpStatus, code)
    case .emptyResponse:
      return Lf("HTTP %d 빈 응답 — 프록시의 스트리밍/응답 래핑을 확인하세요",
                httpStatus)
    default:
      return userMessage
    }
  }

  /// 같은 요청을 1회 다시 보낼 가치가 있는가(업스트림 일시 오류·사용 제한)
  public var canRetrySameRequest: Bool {
    switch self {
    case .upstream, .rateLimited: return true
    default: return false
    }
  }

  /// 이미지를 더 작게 만들어 다시 보낸다(용량 초과)
  public var canRetryShrunk: Bool {
    if case .attachmentTooLarge = self { return true }
    return false
  }

  /// 이미지를 빼고 텍스트만 다시 보낸다(모델이 이미지를 못 받는 경우)
  public var canRetryWithoutImage: Bool {
    if case .attachmentUnsupported = self { return true }
    return false
  }

  /// 재시도 전 대기(초) — 사용 제한은 잠깐 쉬었다 보낸다
  public var retryDelay: TimeInterval {
    if case .rateLimited = self { return 1.5 }
    return 0
  }

  /// 로그용 짧은 이름(내용·본문 없음)
  public var label: String {
    switch self {
    case .keyRejected: return "key-rejected"
    case .forbidden: return "forbidden"
    case .attachmentTooLarge: return "attachment-size"
    case .attachmentUnsupported: return "attachment-capability"
    case .rateLimited: return "rate-limited"
    case .upstream: return "upstream"
    case .requestRejected: return "request-rejected"
    case .emptyResponse: return "empty-response"
    }
  }

  // MARK: - 판정

  /// HTTP 상태·본문 → 실패 분류. 성공(2xx)이면 nil.
  public static func classify(status: Int, body: String, hasImage: Bool) -> ServerFailure? {
    guard !(200..<300).contains(status) else { return nil }
    let server = serverCode(inBody: body)
    // 프록시가 인증 코드를 주면 상태코드보다 우선한다(프록시가 400으로 감싸 보내는 경우 대비)
    if let server, server.uppercased().contains("AUTH") {
      return .keyRejected(status: status, code: server)
    }
    switch status {
    case 401: return .keyRejected(status: status, code: server)
    case 403: return .forbidden(status: status, code: server)
    case 413: return .attachmentTooLarge(status: status, code: server)
    case 429: return .rateLimited(status: status, code: server)
    case 400, 422:
      // 이미지가 실려 있으면 "모델이 이미지를 못 받는다"로 보고 텍스트만 재시도한다.
      // 이미지 없이 400/422면 요청 자체의 문제이므로 재시도하지 않는다.
      return hasImage ? .attachmentUnsupported(status: status, code: server)
                      : .requestRejected(status: status, code: server)
    case 500...599: return .upstream(status: status, code: server)
    default:
      if (400..<500).contains(status) { return .requestRejected(status: status, code: server) }
      return .upstream(status: status, code: server)
    }
  }

  /// 응답 본문에서 서버 코드만 뽑는다 — 본문 자체는 보관·노출하지 않는다.
  /// 프록시 예: `{"type":"error","error":{"type":"<코드명>","code":"E-AND-AUTH-0004","message":"…"}}`
  public static func serverCode(inBody body: String) -> String? {
    guard !body.isEmpty, let data = body.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
    var candidates: [String] = []
    if let c = obj["code"] as? String { candidates.append(c) }
    if let err = obj["error"] as? [String: Any] {
      if let c = err["code"] as? String { candidates.append(c) }
      if let t = err["type"] as? String { candidates.append(t) }
    }
    if let t = obj["type"] as? String, t.lowercased() != "error" { candidates.append(t) }
    return candidates.compactMap(sanitizedCode).first
  }

  /// 코드처럼 보이는 문자열만 통과시킨다(본문·메시지가 사용자 문구로 새지 않게)
  static func sanitizedCode(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard (1...40).contains(trimmed.count) else { return nil }
    let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")
    guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
    return trimmed
  }

  /// 상태코드·본문이 주어졌을 때 사용자 문구(코드 포함)
  public static func message(status: Int, body: String, hasImage: Bool) -> String? {
    classify(status: status, body: body, hasImage: hasImage)?.userMessage
  }
}
