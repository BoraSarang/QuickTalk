import Foundation
import Darwin

// [FEATURE] 격리 브라우저 URL 정책 (v0.38.1)
//
// 브라우저는 임의의 웹 페이지를 여는 도구다. 그 자체로는 읽기지만, 모델이
// `http://127.0.0.1:8080/admin` 같은 **이 Mac의 내부 주소**를 열게 두면
// 웹 페이지 하나로 로컬 서비스를 들여다보는 통로가 된다. 그래서 여기서
// http/https·공인 호스트만 허용하고, 로컬·사설 대역은 **열기 전에** 거부한다.
//
// 한계: DNS가 사설 IP로 풀리는 호스트(리바인딩)는 이 검사로 막지 못한다.
//       문서(PLAN_v0.38.1 §5.2·§12)에 한계로 적는다.

public enum BrowserURLPolicy {
  public enum ValidationError: Error, Equatable {
    case empty
    case tooLong
    case badScheme
    case credentials
    case missingHost
    case invalid
    case localNetwork

    /// 모델과 사용자에게 그대로 보여 줄 한 줄.
    public var userText: String {
      switch self {
      case .empty:
        return L("주소가 비어 있습니다.")
      case .tooLong:
        return L("주소가 너무 깁니다. 2,048자 이내로 주세요.")
      case .badScheme:
        return L("http:// 또는 https:// 주소만 열 수 있습니다.")
      case .credentials:
        return L("주소에 사용자 이름·비밀번호를 넣을 수 없습니다.")
      case .missingHost:
        return L("주소에 호스트 이름이 없습니다.")
      case .invalid:
        return L("주소 형식이 올바르지 않습니다.")
      case .localNetwork:
        return L("로컬·사설 네트워크 주소는 열지 않습니다. 공개된 웹 주소를 주세요.")
      }
    }
  }

  /// 사용자가 준 문자열을 안전한 http/https URL로 정규화한다.
  ///
  /// - `example.com`처럼 스킴이 없으면 `https://`를 붙인다.
  /// - `javascript:`·`file:`·`data:` 처럼 스킴이 있지만 http/https가 아니면 거부한다.
  public static func validate(_ raw: String) throws -> URL {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw ValidationError.empty }
    guard trimmed.count <= 2_048 else { throw ValidationError.tooLong }

    var candidate = trimmed
    let lower = trimmed.lowercased()
    if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
      // `foo:bar` 모양은 스킴으로 본다 — `example.com:8080`은 스킴이 아니다.
      if trimmed.contains("://") { throw ValidationError.badScheme }
      if trimmed.range(of: #"^[A-Za-z][A-Za-z0-9+.-]*:"#,
                       options: .regularExpression) != nil {
        throw ValidationError.badScheme
      }
      candidate = "https://" + trimmed
    }

    guard let components = URLComponents(string: candidate),
          let scheme = components.scheme?.lowercased(),
          scheme == "http" || scheme == "https" else {
      throw ValidationError.badScheme
    }
    guard components.user == nil, components.password == nil else {
      throw ValidationError.credentials
    }
    guard let host = components.host, !host.isEmpty else {
      throw ValidationError.missingHost
    }
    guard !isBlockedHost(host) else { throw ValidationError.localNetwork }
    guard let url = components.url else { throw ValidationError.invalid }
    return url
  }

  /// 편의 — 실패하면 nil.
  public static func url(from raw: String) -> URL? {
    try? validate(raw)
  }

  /// 이 URL을 열어도 되는가 — 리다이렉트·링크 이동에도 같은 기준을 쓴다.
  public static func navigationBlockReason(_ url: URL) -> String? {
    guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
      return ValidationError.badScheme.userText
    }
    guard let host = url.host, !host.isEmpty else {
      return ValidationError.missingHost.userText
    }
    guard url.user == nil, url.password == nil else {
      return ValidationError.credentials.userText
    }
    guard !isBlockedHost(host) else { return ValidationError.localNetwork.userText }
    return nil
  }

  /// http(암호화되지 않음)인가 — 카드·안내 문구에 쓴다.
  public static func isInsecure(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "http"
  }

  /// 화면에 보여 줄 짧은 호스트 — `www.`는 떼고, 포트가 있으면 붙인다.
  public static func displayHost(_ url: URL) -> String {
    var host = (url.host ?? "").lowercased()
    if host.hasPrefix("www.") { host = String(host.dropFirst(4)) }
    if let port = url.port, port != 80, port != 443 {
      return "\(host):\(port)"
    }
    return host.isEmpty ? url.absoluteString : host
  }

  /// 링크 이동이 **상태를 바꿀 가능성이 큰** 주소인가.
  ///
  /// 완벽한 판정이 아니다. 흔한 위험 신호(로그아웃·삭제·해지·결제)만 승인 카드로 올린다.
  /// `?q=delete` 같은 **검색어**는 걸리지 않게 경로 조각과 쿼리 키를 중심으로 본다.
  public static func linkNeedsApproval(_ url: URL) -> Bool {
    let dangerous: Set<String> = [
      "logout", "signout", "sign-out", "delete", "remove", "unsubscribe",
      "cancel", "checkout", "purchase", "buy", "pay", "payment", "transfer",
      "withdraw", "deactivate", "revoke", "disable", "close-account",
      "delete-account",
    ]
    let segments = url.path.lowercased()
      .split(separator: "/")
      .map(String.init)
    if segments.contains(where: { dangerous.contains($0) }) { return true }

    guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
      return false
    }
    let actionKeys: Set<String> = ["action", "do", "op", "operation", "cmd", "command"]
    for item in items {
      let key = item.name.lowercased()
      let value = (item.value ?? "").lowercased()
      if dangerous.contains(key) { return true }
      if actionKeys.contains(key), dangerous.contains(value) { return true }
      // `?confirm=1` — 확인 링크는 대개 서버 상태를 바꾼다.
      if key == "confirm" { return true }
    }
    return false
  }

  // MARK: - 호스트 판정

  /// 로컬·사설 대역·숫자 호스트인가.
  public static func isBlockedHost(_ rawHost: String) -> Bool {
    var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if host.hasPrefix("[") && host.hasSuffix("]") {
      host = String(host.dropFirst().dropLast())
    }
    if host.hasSuffix(".") { host = String(host.dropLast()) }
    guard !host.isEmpty else { return true }

    if host == "localhost" || host.hasSuffix(".localhost") { return true }
    // mDNS·사내망·홈 네트워크에서 흔히 쓰는 예약/로컬 이름.
    for suffix in [".local", ".internal", ".lan", ".home.arpa"] {
      if host.hasSuffix(suffix) { return true }
    }
    if host.contains("%") { return true }   // IPv6 zone id

    // `2130706433`·`0x7f000001` 같은 숫자 표기 — 공인 도메인처럼 보이지 않게 거부.
    if host.hasPrefix("0x") {
      return ipv4Value(host).map(isBlockedIPv4) ?? true
    }
    if host.range(of: #"^[0-9.]+$"#, options: .regularExpression) != nil {
      // `0177.0.0.1` 처럼 앞자리 0은 8진수로 해석될 수 있다 — 모호하면 거부.
      let parts = host.split(separator: ".", omittingEmptySubsequences: false)
      if parts.contains(where: { $0.count > 1 && $0.hasPrefix("0") }) { return true }
      // 순수 숫자/점 표기는 IPv4의 다른 표기일 수 있다 → 파싱해서 판정하고, 파싱이 안 되면 거부.
      if let value = ipv4Value(host) { return isBlockedIPv4(value) }
      return true
    }

    var addr = in_addr()
    if inet_pton(AF_INET, host, &addr) == 1 {
      return isBlockedIPv4(UInt32(bigEndian: addr.s_addr))
    }
    var addr6 = in6_addr()
    if inet_pton(AF_INET6, host, &addr6) == 1 {
      return isBlockedIPv6(addr6)
    }
    return false
  }

  /// IPv4 점 표기(또는 정수 표기)를 32비트 값으로. 실패하면 nil.
  private static func ipv4Value(_ host: String) -> UInt32? {
    if host.hasPrefix("0x") {
      return UInt32(host.dropFirst(2), radix: 16)
    }
    let parts = host.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 4 else {
      // `2130706433` 한 덩어리
      if parts.count == 1, let n = UInt32(host) { return n }
      return nil
    }
    var value: UInt32 = 0
    for part in parts {
      guard !part.isEmpty, let n = UInt32(part), n <= 255 else { return nil }
      value = (value << 8) | n
    }
    return value
  }

  private static func isBlockedIPv4(_ value: UInt32) -> Bool {
    let a = UInt8((value >> 24) & 0xFF)
    let b = UInt8((value >> 16) & 0xFF)
    let c = UInt8((value >> 8) & 0xFF)
    switch a {
    case 0, 10, 127: return true
    case 100: return b >= 64 && b <= 127          // 100.64/10 CGNAT
    case 169: return b == 254                     // link-local
    case 172: return b >= 16 && b <= 31           // 172.16/12
    case 192:
      if b == 168 { return true }                 // 192.168/16
      if b == 0 { return true }                   // 192.0.0/24
      if b == 2 { return true }                   // 192.0.2/24 TEST-NET-1
      return false
    case 198:
      if b == 18 || b == 19 { return true }       // 198.18/15
      if b == 51 && c == 100 { return true }      // 198.51.100/24 TEST-NET-2
      return false
    case 203:
      return b == 0 && c == 113                   // 203.0.113/24 TEST-NET-3
    default:
      return a >= 224                             // multicast·reserved
    }
  }

  private static func isBlockedIPv6(_ addr: in6_addr) -> Bool {
    let bytes = withUnsafeBytes(of: addr) { Array($0) }
    guard bytes.count == 16 else { return true }
    // :: 와 ::1
    if bytes.prefix(15).allSatisfy({ $0 == 0 }) {
      return bytes[15] == 0 || bytes[15] == 1
    }
    // fc00::/7 (ULA)
    if (bytes[0] & 0xFE) == 0xFC { return true }
    // fe80::/10 (link-local)
    if bytes[0] == 0xFE && (bytes[1] & 0xC0) == 0x80 { return true }
    // ff00::/8 (multicast)
    if bytes[0] == 0xFF { return true }
    // 2001:db8::/32 (문서용)
    if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0D && bytes[3] == 0xB8 {
      return true
    }
    // ::ffff:0:0/96 (IPv4-mapped) — 안쪽 IPv4를 검사한다.
    if bytes.prefix(10).allSatisfy({ $0 == 0 }),
       bytes[10] == 0xFF, bytes[11] == 0xFF {
      let v4 = (UInt32(bytes[12]) << 24) | (UInt32(bytes[13]) << 16)
        | (UInt32(bytes[14]) << 8) | UInt32(bytes[15])
      return isBlockedIPv4(v4)
    }
    return false
  }
}
