import Foundation

// [FEATURE] 원격 승인 — 예약·맡긴 작업이 승인 때문에 멈췄을 때 Telegram 버튼으로
// **한 번만** 허용/거부한다(v0.39).
//
// 원칙: 승인 결정 경로는 기존 것을 그대로 쓴다. 이 파일은 **입력 수단**에 필요한
// 최소 타입만 담는다 — callback data(1회용 nonce), 메시지 본문(마스킹), 설정 검증,
// Telegram Bot API JSON 모델, 티켓 만료.
//
// 안전:
//   · callback data 에 명령을 넣지 않는다(64바이트 제한 + 채팅방에 노출될 수 있음).
//   · 본문에는 명령·위험·이유·쓰기 범위만. 파일 내용·페이지 본문·입력값은 보내지 않는다.
//   · 토큰은 `SecretStore` 에만. 이 파일의 어떤 타입도 토큰을 보관하지 않는다.

// MARK: - 버튼 동작

/// 원격에서 고를 수 있는 결정 — **한 번 허용**과 **거부**뿐이다.
/// `.alwaysAllow`·쓰기 범위 영구 승인은 원격에서 만들 수 없다.
public enum RemoteApprovalAction: String, Codable, CaseIterable, Equatable {
  case allow
  case deny

  public var label: String {
    switch self {
    case .allow: return L("✅ 허용")
    case .deny: return L("❌ 거부")
    }
  }
}

// MARK: - callback data

/// Telegram inline button 의 callback data — `qt:<32 hex nonce>:allow|deny`.
///
/// 64바이트 제한 안에서 명령·경로를 담지 않는다. nonce 는 요청마다 새로 만드는
/// 128비트 난수이며, pending 에서 한 번만 맞춰 본다(재사용 불가).
public struct RemoteApprovalCallback: Equatable {
  public static let prefix = "qt"
  /// 128비트 = 32 hex.
  public static let nonceLength = 32

  public let nonce: String
  public let action: RemoteApprovalAction

  public init(nonce: String, action: RemoteApprovalAction) {
    self.nonce = nonce
    self.action = action
  }

  /// Telegram 이 허용하는 64바이트 이하의 짧은 문자열.
  public var data: String {
    "\(Self.prefix):\(nonce):\(action.rawValue)"
  }

  /// 형식이 맞지 않으면 nil — 잘못된 callback 은 조용히 무시한다.
  public static func parse(_ raw: String) -> RemoteApprovalCallback? {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
    guard parts.count == 3,
          parts[0] == Substring(prefix),
          isValidNonce(String(parts[1])),
          let action = RemoteApprovalAction(rawValue: String(parts[2]))
    else { return nil }
    return RemoteApprovalCallback(nonce: String(parts[1]), action: action)
  }

  /// 32자 소문자 hex 인지 — 다른 형식은 위조·오래된 버튼으로 본다.
  public static func isValidNonce(_ nonce: String) -> Bool {
    guard nonce.count == nonceLength else { return false }
    return nonce.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
  }

  /// 128비트 난수 — UUID(122비트)보다 nonce 충돌 여지를 줄인다.
  public static func makeNonce() -> String {
    var rng = SystemRandomNumberGenerator()
    let high = UInt64.random(in: .min ... .max, using: &rng)
    let low = UInt64.random(in: .min ... .max, using: &rng)
    return String(format: "%016llx%016llx", high, low)
  }
}

// MARK: - 본문 만들기

/// Telegram 에 보낼 승인 카드의 문구. 버튼 라벨은 지역화한다.
public struct RemoteApprovalContent: Equatable {
  public let title: String
  public let body: String
  public let allowTitle: String
  public let denyTitle: String

  public init(title: String, body: String, allowTitle: String, denyTitle: String) {
    self.title = title
    self.body = body
    self.allowTitle = allowTitle
    self.denyTitle = denyTitle
  }

  /// 실제 메시지 본문 — 제목 + 빈 줄 + 상세.
  public var messageText: String {
    RemoteApprovalText.limit("\(title)\n\n\(body)", to: RemoteApprovalText.messageLimit)
  }

  /// 승인 요청 1건의 문구를 만든다. 파일 내용·입력값은 인자로 받지 않는다.
  public static func make(requestTitle: String?,
                          fallbackTitle: String,
                          command: String,
                          levelName: String,
                          riskName: String,
                          irreversible: Bool,
                          reason: String,
                          writeScopes: [String],
                          personaName: String?,
                          secrets: [String] = []) -> RemoteApprovalContent {
    let trimmedTitle = (requestTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
    var risk = "\(riskName) · \(levelName)"
    if irreversible { risk += " · \(L("되돌릴 수 없음"))" }

    var lines: [String] = [
      Lf("명령: %@", RemoteApprovalText.maskedCommand(command)),
      Lf("위험: %@", risk)
    ]
    let cleanReason = RemoteApprovalText.oneLine(reason, limit: 200)
    if !cleanReason.isEmpty { lines.append(Lf("이유: %@", cleanReason)) }
    if !writeScopes.isEmpty {
      let shown = writeScopes.prefix(3).joined(separator: ", ")
      let suffix = writeScopes.count > 3 ? " (+\(writeScopes.count - 3))" : ""
      lines.append(Lf("쓰기 범위: %@", shown + suffix))
    }
    let persona = (personaName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !persona.isEmpty { lines.append(Lf("비서: %@", persona)) }
    lines.append("")
    lines.append(L("10분 안에 응답하지 않으면 자동 거부됩니다."))
    lines.append(L("QuickTalk가 실행 중일 때만 응답할 수 있습니다."))

    let body = RemoteApprovalText.limit(
      RemoteApprovalText.scrub(lines.joined(separator: "\n"), secrets: secrets),
      to: RemoteApprovalText.bodyLimit)
    return RemoteApprovalContent(
      title: Lf("🔐 승인 필요 — %@", title),
      body: body,
      allowTitle: RemoteApprovalAction.allow.label,
      denyTitle: RemoteApprovalAction.deny.label)
  }
}

// MARK: - 문구 유틸

public enum RemoteApprovalText {
  /// 명령은 300자까지만 — 메시지가 길어져 버튼이 밀리지 않게.
  public static let commandLimit = 300
  public static let bodyLimit = 3_500
  /// Telegram 메시지 상한 4096 — 여유를 둔다.
  public static let messageLimit = 4_000

  /// 한 줄로 접고, 비밀 패턴을 가리고, 길이를 제한한다.
  public static func maskedCommand(_ command: String) -> String {
    oneLine(maskSecrets(command), limit: commandLimit)
  }

  /// 줄바꿈·연속 공백을 한 칸으로. 잘리면 말줄임표를 붙인다.
  public static func oneLine(_ text: String, limit: Int) -> String {
    var out = text
      .replacingOccurrences(of: "\r\n", with: " ")
      .replacingOccurrences(of: "\n", with: " ")
      .replacingOccurrences(of: "\r", with: " ")
      .replacingOccurrences(of: "\t", with: " ")
    while out.contains("  ") { out = out.replacingOccurrences(of: "  ", with: " ") }
    out = out.trimmingCharacters(in: .whitespacesAndNewlines)
    return limitText(out, to: limit)
  }

  /// 토큰·API 키·비밀번호·Authorization 헤더를 `***` 로 가린다([HARD] 로그 마스킹).
  public static func maskSecrets(_ text: String) -> String {
    var out = text
    let rules: [(String, String)] = [
      (#"(?i)(token|api[_-]?key|apikey|password|passwd|secret)(\s*[=:]\s*)\S+"#, "$1$2***"),
      (#"(?i)(authorization:\s*bearer\s+)[^\s'"]+"#, "$1***"),
      (#"\b\d{6,}:[A-Za-z0-9_-]{25,}\b"#, "***"),
      // `mysql -p <비밀번호>` 는 가리되 `mkdir -p ~/경로` 는 그대로 둔다.
      (#"(?i)(-p\s+)(?![/~])\S{6,}"#, "$1***")
    ]
    for (pattern, template) in rules {
      guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
      let range = NSRange(out.startIndex..., in: out)
      out = re.stringByReplacingMatches(in: out, range: range, withTemplate: template)
    }
    return out
  }

  /// 알려진 비밀 문자열(예: 봇 토큰)이 본문에 섞여도 지운다. 6자 미만은 오탐이 커서 건너뛴다.
  public static func scrub(_ text: String, secrets: [String]) -> String {
    var out = text
    for secret in secrets where secret.count >= 6 {
      out = out.replacingOccurrences(of: secret, with: "***")
    }
    return out
  }

  /// 길이 제한 — 자르면 `…` 를 붙인다(Telegram 4096자·카드 레이아웃 보호).
  public static func limit(_ text: String, to max: Int) -> String {
    limitText(text, to: max)
  }

  private static func limitText(_ text: String, to max: Int) -> String {
    guard max > 0, text.count > max else { return text }
    return String(text.prefix(max - 1)) + "…"
  }
}

// MARK: - 설정 검증

/// 원격 승인 설정의 유효성 — **토큰 원문은 보관하지 않는다**(존재·형식만).
public struct RemoteApprovalConfig: Equatable {
  /// 봇 토큰을 저장하는 `SecretStore` 계정 이름.
  public static let tokenAccount = "telegramApprovalBotToken"

  public let enabled: Bool
  public let chatID: String
  public let hasToken: Bool

  public init(enabled: Bool, chatID: String, token: String?) {
    self.enabled = enabled
    self.chatID = chatID
    self.hasToken = Self.isValidToken(token ?? "")
  }

  /// 공백을 뺀 chat ID — 요청·비교에 항상 이 값을 쓴다.
  public var normalizedChatID: String {
    chatID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 토큰과 chat ID 가 모두 준비됐는가 — 켜짐 여부와 무관(연결 테스트용).
  public var canConnect: Bool {
    hasToken && Self.isValidChatID(chatID)
  }

  /// 지금 polling·전송을 시작해도 되는가.
  public var isReady: Bool { enabled && canConnect }

  /// 켜져 있는데 준비가 덜 됐을 때 이유 — 설정 화면·QA 로그에 쓴다.
  public var inactivityReason: String? {
    guard enabled else { return L("원격 승인이 꺼져 있습니다.") }
    guard hasToken else { return L("봇 토큰이 없거나 형식이 올바르지 않습니다.") }
    guard Self.isValidChatID(chatID) else { return L("chat ID가 올바르지 않습니다.") }
    return nil
  }

  /// Telegram chat ID — 숫자(단체·채널은 음수)만. `@channel`·초대 링크는 받지 않는다.
  public static func isValidChatID(_ raw: String) -> Bool {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty, text.count <= 32 else { return false }
    var digits = Substring(text)
    if digits.first == "-" { digits = digits.dropFirst() }
    guard !digits.isEmpty, digits.count <= 20 else { return false }
    return digits.allSatisfy { $0.isNumber }
  }

  /// BotFather 토큰 — `<숫자>:<영숫자·_- 10자 이상>`.
  public static func isValidToken(_ raw: String) -> Bool {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 20, text.count <= 128 else { return false }
    let parts = text.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2,
          !parts[0].isEmpty, parts[0].allSatisfy({ $0.isNumber }),
          parts[1].count >= 10
    else { return false }
    return parts[1].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
  }
}

// MARK: - 승인 티켓

/// 보낸 메시지 1건과 그 nonce·만료 시각. pending 은 앱 전체에 하나뿐이다.
public struct RemoteApprovalTicket: Equatable {
  /// 기존 예약 승인과 같은 10분.
  public static let lifetime: TimeInterval = 10 * 60

  public let nonce: String
  public let chatID: String
  public let messageID: Int64
  public let createdAt: Date
  public let expiresAt: Date

  public init(nonce: String, chatID: String, messageID: Int64,
              createdAt: Date, lifetime: TimeInterval = RemoteApprovalTicket.lifetime) {
    self.nonce = nonce
    self.chatID = chatID
    self.messageID = messageID
    self.createdAt = createdAt
    self.expiresAt = createdAt.addingTimeInterval(lifetime)
  }

  /// 만료 경계는 **같은 순간도 만료**로 본다.
  public func isExpired(now: Date) -> Bool {
    now.timeIntervalSince(expiresAt) >= 0
  }

  /// 로그·QA 용 짧은 표기 — nonce 앞 6자만.
  public var logLabel: String {
    "nonce=\(nonce.prefix(6))… chat=…\(chatID.suffix(3))"
  }
}

// MARK: - Telegram Bot API 모델

public struct TelegramChat: Codable, Equatable {
  public let id: Int64
  public let type: String?

  public init(id: Int64, type: String? = nil) {
    self.id = id
    self.type = type
  }
}

public struct TelegramUser: Codable, Equatable {
  public let id: Int64
  public let isBot: Bool?
  public let firstName: String?
  public let username: String?

  public init(id: Int64, isBot: Bool? = nil, firstName: String? = nil, username: String? = nil) {
    self.id = id
    self.isBot = isBot
    self.firstName = firstName
    self.username = username
  }

  enum CodingKeys: String, CodingKey {
    case id
    case isBot = "is_bot"
    case firstName = "first_name"
    case username
  }
}

public struct TelegramMessage: Codable, Equatable {
  public let messageID: Int64
  public let chat: TelegramChat?
  public let text: String?

  public init(messageID: Int64, chat: TelegramChat? = nil, text: String? = nil) {
    self.messageID = messageID
    self.chat = chat
    self.text = text
  }

  enum CodingKeys: String, CodingKey {
    case messageID = "message_id"
    case chat
    case text
  }
}

public struct TelegramCallbackQuery: Codable, Equatable {
  public let id: String
  public let from: TelegramUser?
  public let message: TelegramMessage?
  public let data: String?

  public init(id: String, from: TelegramUser? = nil,
              message: TelegramMessage? = nil, data: String? = nil) {
    self.id = id
    self.from = from
    self.message = message
    self.data = data
  }
}

public struct TelegramUpdate: Codable, Equatable {
  public let updateID: Int64
  public let callbackQuery: TelegramCallbackQuery?

  public init(updateID: Int64, callbackQuery: TelegramCallbackQuery? = nil) {
    self.updateID = updateID
    self.callbackQuery = callbackQuery
  }

  enum CodingKeys: String, CodingKey {
    case updateID = "update_id"
    case callbackQuery = "callback_query"
  }
}

public struct TelegramBotInfo: Codable, Equatable {
  public let id: Int64
  public let isBot: Bool?
  public let firstName: String?
  public let username: String?

  public init(id: Int64, isBot: Bool? = nil,
              firstName: String? = nil, username: String? = nil) {
    self.id = id
    self.isBot = isBot
    self.firstName = firstName
    self.username = username
  }

  enum CodingKeys: String, CodingKey {
    case id
    case isBot = "is_bot"
    case firstName = "first_name"
    case username
  }

  /// 설정 화면에 보여 줄 이름 — 토큰은 절대 포함하지 않는다.
  public var displayName: String {
    if let username, !username.isEmpty { return "@\(username)" }
    if let firstName, !firstName.isEmpty { return firstName }
    return "#\(id)"
  }
}

/// inline keyboard 버튼 1개 — callback data 는 64바이트 이하여야 한다.
public struct TelegramButton: Equatable {
  public static let maxCallbackBytes = 64

  public let text: String
  public let callbackData: String

  public init(text: String, callbackData: String) {
    self.text = text
    self.callbackData = callbackData
  }

  public var isValid: Bool {
    !text.isEmpty && !callbackData.isEmpty
      && callbackData.utf8.count <= Self.maxCallbackBytes
  }
}

// MARK: - 전송 계층

public enum TelegramError: Error, Equatable, LocalizedError {
  /// 설정이 준비되지 않음(이유 포함).
  case notConfigured(String)
  /// Bot API 가 `ok=false` 로 거부함 — 서버가 준 description.
  case api(String)
  /// JSON 을 읽을 수 없음.
  case invalidResponse
  /// 네트워크·HTTP 실패. **URL·토큰을 담지 않는다.**
  case transport

  public var errorDescription: String? {
    switch self {
    case .notConfigured(let reason): return reason
    case .api(let message): return message
    case .invalidResponse: return L("Telegram 응답을 읽을 수 없습니다.")
    case .transport: return L("Telegram에 연결하지 못했습니다.")
    }
  }

  /// 로그·UI 에 쓸 안전한 한 줄 — 원문 오류에 토큰이 섞일 여지를 없앤다.
  public var safeDescription: String {
    switch self {
    case .notConfigured(let reason): return reason
    case .api(let message):
      return RemoteApprovalText.limit(RemoteApprovalText.oneLine(message, limit: 160), to: 160)
    case .invalidResponse, .transport:
      return errorDescription ?? L("Telegram 연결에 실패했습니다.")
    }
  }
}

/// Bot API 호출 — 앱은 `URLSessionTelegramTransport`, QA 는 fake 를 쓴다.
/// 메서드가 MainActor 서비스에서 호출되므로 구현도 가벼워야 한다.
public protocol TelegramTransport: AnyObject {
  func getMe(token: String) async throws -> TelegramBotInfo
  func sendMessage(token: String, chatID: String, text: String,
                   buttons: [TelegramButton]) async throws -> TelegramMessage
  func editMessageText(token: String, chatID: String, messageID: Int64,
                       text: String) async throws
  func answerCallbackQuery(token: String, callbackID: String, text: String) async throws
  func getUpdates(token: String, offset: Int64?, timeout: Int) async throws -> [TelegramUpdate]
}
