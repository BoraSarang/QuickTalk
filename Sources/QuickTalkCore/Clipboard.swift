import Foundation

/// 최근 클립보드 항목 1건 (PLAN_v0.12).
/// **내용은 로그에 남기지 않는다** — 로그에는 개수·종류만 기록한다([HARD] 로그 마스킹).
public struct ClipboardItem: Identifiable, Equatable {
  public enum Kind: String, Equatable, Codable { case text, image, file, link }

  public let id: UUID
  public let kind: Kind
  /// 텍스트 본문 / 이미지 라벨 / 파일명
  public let text: String
  /// 이미지일 때만: 썸네일용 축소 PNG 데이터
  public let imageData: Data?
  public let capturedAt: Date
  /// 비밀번호 관리자 마커 또는 민감 패턴 → 기본 마스킹
  public let isSensitive: Bool
  /// 클립보드가 담고 있던 **파일 위치**(파일 항목일 때만).
  /// 이전에는 이름만 보관해 첨부해도 본문을 읽지 못했다(핸드오프 P1).
  /// 항목 수명(2분) 동안만 유효할 수 있다 — 전송 시점에 사라졌으면 `AttachmentLoader`의 사유 안내로 처리한다.
  public let fileURL: URL?

  public init(id: UUID = UUID(), kind: Kind, text: String, imageData: Data? = nil,
              capturedAt: Date = Date(), isSensitive: Bool = false, fileURL: URL? = nil) {
    self.id = id
    self.kind = kind
    self.text = text
    self.imageData = imageData
    self.capturedAt = capturedAt
    self.isSensitive = isSensitive
    self.fileURL = fileURL
  }

  /// 입력창에 바로 넣을 수 있는 항목인가 (텍스트·링크)
  public var isInsertableText: Bool { kind == .text || kind == .link }
}

/// 클립보드 스트립 정책 — 만료 2분 · 최대 5개 (2026-10-19 사용자 확정).
public enum ClipboardPolicy {
  public static let ttl: TimeInterval = 120
  public static let maxItems = 5
  /// 텍스트 보관 상한(자)
  public static let maxTextLength = 4000
  /// 썸네일 긴 변(px) — 스트립 칩(22pt)과 호버 미리보기(최대 360pt)에 함께 쓴다
  public static let thumbnailMaxSide: Double = 480

  /// 남은 시간(초). 0이면 만료.
  public static func secondsLeft(_ item: ClipboardItem, now: Date = Date()) -> Int {
    max(0, Int((ttl - now.timeIntervalSince(item.capturedAt)).rounded(.up)))
  }

  public static func isExpired(_ item: ClipboardItem, now: Date = Date()) -> Bool {
    now.timeIntervalSince(item.capturedAt) >= ttl
  }

  /// http/https 문자열 판정
  public static func looksLikeURL(_ text: String) -> Bool {
    guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let scheme = url.scheme?.lowercased() else { return false }
    return (scheme == "http" || scheme == "https") && url.host != nil
  }

  /// 민감 패턴 판정 — 판정 **결과만** 남기고 값은 남기지 않는다.
  public static func looksSensitive(_ text: String) -> Bool {
    let lower = text.lowercased()
    let keys = ["password", "passwd", "secret", "api key", "apikey", "api_key",
                "token", "otp", "인증번호", "주민등록", "card number", "cvc", "비밀번호"]
    if keys.contains(where: { lower.contains($0) }) { return true }
    // 카드번호 형태(4자리 그룹 3개 이상 + 숫자 15~19개)
    let digits = text.filter { $0.isNumber }
    let dashes = text.filter { $0 == "-" }.count
    if dashes >= 3, (15...19).contains(digits.count), text.contains("-") { return true }
    // 공백 없는 긴 무작위 문자열(토큰류)
    if text.count >= 40, !text.contains(" "),
       text.rangeOfCharacter(from: CharacterSet.alphanumerics.inverted) == nil { return true }
    return false
  }

  /// 표시용 텍스트 — 민감 항목은 공개 전까지 마스킹
  public static func displayText(_ item: ClipboardItem, revealed: Bool) -> String {
    if item.isSensitive && !revealed { return "••••••••" }
    return item.text
  }

  /// 한 줄 미리보기(개행·과다 공백 정리, 최대 길이 제한)
  public static func previewText(_ text: String, limit: Int = 60) -> String {
    let flattened = text
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
      .split(separator: " ", omittingEmptySubsequences: true)
      .joined(separator: " ")
    if flattened.count <= limit { return flattened }
    return String(flattened.prefix(limit)) + "…"
  }
}

/// 최근 항목 링버퍼 — 만료 정리 / 최대 개수 / 같은 내용 최신화 규칙을 담는다.
/// (AppKit 없이 순수 로직만 — `swift test`로 검증 가능)
public struct ClipboardRing {
  public private(set) var items: [ClipboardItem]

  public init(items: [ClipboardItem] = []) { self.items = items }

  /// 새 항목을 맨 앞에 넣는다. 같은 종류·같은 내용은 중복 제거 후 맨 앞으로 올린다.
  /// 이미 만료된 항목은 받지 않는다(늦게 도착한 변경분 방어).
  public mutating func insert(_ item: ClipboardItem, now: Date = Date()) {
    expire(now: now)
    guard !ClipboardPolicy.isExpired(item, now: now) else { return }
    items.removeAll { $0.kind == item.kind && $0.text == item.text }
    items.insert(item, at: 0)
    if items.count > ClipboardPolicy.maxItems {
      items.removeLast(items.count - ClipboardPolicy.maxItems)
    }
  }

  /// 만료된 항목 제거. 제거한 개수를 돌려준다.
  @discardableResult
  public mutating func expire(now: Date = Date()) -> Int {
    let before = items.count
    items.removeAll { ClipboardPolicy.isExpired($0, now: now) }
    return before - items.count
  }

  public mutating func remove(_ id: UUID) { items.removeAll { $0.id == id } }
  public mutating func removeAll() { items.removeAll() }
}
