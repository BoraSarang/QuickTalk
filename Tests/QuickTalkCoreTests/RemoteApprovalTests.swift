import XCTest
@testable import QuickTalkCore

/// v0.39 원격 승인 — callback nonce·마스킹·본문·설정·Telegram 파싱·티켓 만료.
final class RemoteApprovalTests: XCTestCase {

  // MARK: - callback data

  func testCallbackDataRoundTrip() {
    let nonce = String(repeating: "a", count: 32)
    let allow = RemoteApprovalCallback(nonce: nonce, action: .allow).data
    XCTAssertEqual(allow, "qt:\(nonce):allow")
    XCTAssertEqual(RemoteApprovalCallback.parse(allow)?.nonce, nonce)
    XCTAssertEqual(RemoteApprovalCallback.parse(allow)?.action, .allow)

    let deny = RemoteApprovalCallback(nonce: nonce, action: .deny).data
    XCTAssertEqual(RemoteApprovalCallback.parse(deny)?.action, .deny)
  }

  func testCallbackDataHasNoCommandAndFitsTelegramLimit() {
    let data = RemoteApprovalCallback(nonce: RemoteApprovalCallback.makeNonce(),
                                      action: .allow).data
    XCTAssertLessThanOrEqual(data.utf8.count, TelegramButton.maxCallbackBytes)
    XCTAssertFalse(data.contains("rm "))
    XCTAssertEqual(data.split(separator: ":").count, 3)
  }

  func testMalformedCallbackDataIsRejected() {
    let nonce = String(repeating: "0", count: 32)
    let bad = [
      "", "qt", "qt:", "qt:\(nonce)", "qt:\(nonce):maybe",
      "xx:\(nonce):allow", "qt:\(nonce):allow:extra",
      "qt:short:allow",
      "qt:\(String(repeating: "A", count: 32)):allow", // 대문자 hex 거부
      "qt:\(String(repeating: "g", count: 32)):allow"
    ]
    for raw in bad {
      XCTAssertNil(RemoteApprovalCallback.parse(raw), "거부되어야 함: \(raw)")
    }
  }

  func testNonceIs128BitHexAndUnique() {
    let a = RemoteApprovalCallback.makeNonce()
    let b = RemoteApprovalCallback.makeNonce()
    XCTAssertEqual(a.count, 32)
    XCTAssertTrue(RemoteApprovalCallback.isValidNonce(a))
    XCTAssertNotEqual(a, b)
    XCTAssertFalse(a.contains("-"))
  }

  // MARK: - 마스킹

  func testMasksTokenAssignments() {
    XCTAssertEqual(RemoteApprovalText.maskedCommand("curl -H token=sk-1234567890 https://x"),
                   "curl -H token=*** https://x")
    XCTAssertEqual(RemoteApprovalText.maskedCommand("api_key: abcd1234"),
                   "api_key: ***")
  }

  func testMasksAuthorizationHeader() {
    XCTAssertEqual(RemoteApprovalText.maskedCommand("curl -H 'Authorization: Bearer abcdef123456'"),
                   "curl -H 'Authorization: Bearer ***'")
  }

  func testMasksPasswordAndBotToken() {
    XCTAssertEqual(RemoteApprovalText.maskedCommand("mysql -p supersecret"),
                   "mysql -p ***")
    let bot = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg"
    XCTAssertEqual(RemoteApprovalText.maskedCommand("curl \(bot)"), "curl ***")
  }

  func testCommandBecomesOneLineAndLimited() {
    let multiline = "mkdir -p ~/Documents/x\n\necho\t\"hello\""
    XCTAssertEqual(RemoteApprovalText.maskedCommand(multiline),
                   "mkdir -p ~/Documents/x echo \"hello\"")
    let long = String(repeating: "a", count: 500)
    let masked = RemoteApprovalText.maskedCommand(long)
    XCTAssertEqual(masked.count, RemoteApprovalText.commandLimit)
    XCTAssertTrue(masked.hasSuffix("…"))
  }

  func testScrubRemovesKnownSecret() {
    let secret = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg"
    let text = RemoteApprovalText.scrub("cmd \(secret) end", secrets: [secret])
    XCTAssertEqual(text, "cmd *** end")
  }

  // MARK: - 본문

  func testContentContainsOnlyWhatIsNeeded() {
    let content = RemoteApprovalContent.make(
      requestTitle: "이사 업체 비교",
      fallbackTitle: "맡긴 작업",
      command: "mkdir -p ~/Documents/이사",
      levelName: "쓰기",
      riskName: "보통",
      irreversible: false,
      reason: "작업 폴더 밖에 폴더를 만듭니다.",
      writeScopes: ["~/Documents/이사"],
      personaName: "비서")
    let text = content.messageText
    XCTAssertTrue(text.contains("이사 업체 비교"))
    XCTAssertTrue(text.contains("mkdir -p ~/Documents/이사"))
    XCTAssertTrue(text.contains("보통 · 쓰기"))
    XCTAssertTrue(text.contains("작업 폴더 밖에 폴더를 만듭니다."))
    XCTAssertTrue(text.contains("~/Documents/이사"))
    XCTAssertTrue(text.contains("비서"))
    XCTAssertTrue(text.contains(L("10분 안에 응답하지 않으면 자동 거부됩니다.")))
    // 파일 내용·입력값은 애초에 인자로 받지 않는다.
    XCTAssertFalse(text.contains("<!doctype"))
    XCTAssertFalse(text.contains("password="))
  }

  func testContentTitleFallsBackWhenMissing() {
    let content = RemoteApprovalContent.make(
      requestTitle: "   ", fallbackTitle: "예약 작업",
      command: "pwd", levelName: "읽기", riskName: "보통",
      irreversible: false, reason: "", writeScopes: [], personaName: nil)
    XCTAssertTrue(content.title.contains("예약 작업"))
    XCTAssertFalse(content.title.contains("   "))
    XCTAssertFalse(content.body.contains("이유:"))
  }

  func testContentMarksIrreversible() {
    let content = RemoteApprovalContent.make(
      requestTitle: nil, fallbackTitle: "맡긴 작업",
      command: "rm -rf ~/Desktop/x", levelName: "쓰기", riskName: "중요",
      irreversible: true, reason: "되돌릴 수 없습니다.", writeScopes: [],
      personaName: nil)
    XCTAssertTrue(content.messageText.contains(L("되돌릴 수 없음")))
  }

  func testContentScrubsBotToken() {
    let token = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg"
    let content = RemoteApprovalContent.make(
      requestTitle: "테스트", fallbackTitle: "예약 작업",
      command: "echo \(token)", levelName: "실행", riskName: "보통",
      irreversible: false, reason: "", writeScopes: [], personaName: nil,
      secrets: [token])
    XCTAssertFalse(content.messageText.contains(token))
    XCTAssertTrue(content.messageText.contains("***"))
  }

  func testContentMessageFitsTelegramLimit() {
    let content = RemoteApprovalContent.make(
      requestTitle: String(repeating: "가", count: 100),
      fallbackTitle: "예약 작업",
      command: String(repeating: "x", count: 1000),
      levelName: "쓰기", riskName: "보통", irreversible: false,
      reason: String(repeating: "이", count: 500),
      writeScopes: (0..<10).map { "~/Documents/\($0)" }, personaName: nil)
    XCTAssertLessThanOrEqual(content.messageText.count, RemoteApprovalText.messageLimit)
    XCTAssertLessThanOrEqual(content.messageText.count, 4_096)
  }

  // MARK: - 설정 검증

  func testConfigRejectsMissingOrMalformedValues() {
    let token = "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg"
    XCTAssertFalse(RemoteApprovalConfig(enabled: true, chatID: "", token: token).isReady)
    XCTAssertFalse(RemoteApprovalConfig(enabled: true, chatID: "abc", token: token).isReady)
    XCTAssertFalse(RemoteApprovalConfig(enabled: true, chatID: "12 34", token: token).isReady)
    XCTAssertFalse(RemoteApprovalConfig(enabled: true, chatID: "123456789",
                                        token: nil).isReady)
    XCTAssertFalse(RemoteApprovalConfig(enabled: true, chatID: "123456789",
                                        token: "not-a-token").isReady)
    XCTAssertFalse(RemoteApprovalConfig(enabled: false, chatID: "123456789",
                                        token: token).isReady)
  }

  func testConfigAcceptsUserAndGroupChatIDs() {
    for chat in ["123456789", "-1001234567890", " 42 "] {
      XCTAssertTrue(RemoteApprovalConfig.isValidChatID(chat), chat)
    }
    XCTAssertFalse(RemoteApprovalConfig.isValidChatID("-"))
    XCTAssertFalse(RemoteApprovalConfig.isValidChatID("+123"))
    XCTAssertFalse(RemoteApprovalConfig.isValidChatID("@channel"))
    XCTAssertFalse(RemoteApprovalConfig.isValidChatID("1".padding(toLength: 33,
                                                                  withPad: "0", startingAt: 0)))
  }

  func testConfigCanConnectWithoutBeingEnabled() {
    let config = RemoteApprovalConfig(
      enabled: false, chatID: "123456789",
      token: "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg")
    XCTAssertTrue(config.canConnect)
    XCTAssertFalse(config.isReady)
    XCTAssertEqual(config.inactivityReason, L("원격 승인이 꺼져 있습니다."))
  }

  func testConfigTokenFormat() {
    XCTAssertTrue(RemoteApprovalConfig.isValidToken(
      "123456789:ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefg"))
    XCTAssertFalse(RemoteApprovalConfig.isValidToken(""))
    XCTAssertFalse(RemoteApprovalConfig.isValidToken("123456789"))
    XCTAssertFalse(RemoteApprovalConfig.isValidToken("abc:ABCDEFGHIJKLMNOPQRST"))
    XCTAssertFalse(RemoteApprovalConfig.isValidToken("123:short"))
  }

  // MARK: - 티켓

  func testTicketExpiresAtTenMinutes() {
    let start = Date(timeIntervalSince1970: 1_000)
    let ticket = RemoteApprovalTicket(nonce: String(repeating: "a", count: 32),
                                      chatID: "42", messageID: 7, createdAt: start)
    XCTAssertEqual(ticket.expiresAt.timeIntervalSince(start), 600)
    XCTAssertFalse(ticket.isExpired(now: start.addingTimeInterval(599)))
    XCTAssertTrue(ticket.isExpired(now: start.addingTimeInterval(600)))
    XCTAssertTrue(ticket.isExpired(now: start.addingTimeInterval(601)))
  }

  func testTicketLifetimeCanBeInjectedForQA() {
    let start = Date(timeIntervalSince1970: 2_000)
    let ticket = RemoteApprovalTicket(nonce: String(repeating: "b", count: 32),
                                      chatID: "-1001", messageID: 8,
                                      createdAt: start, lifetime: 5)
    XCTAssertTrue(ticket.isExpired(now: start.addingTimeInterval(5)))
    XCTAssertFalse(ticket.isExpired(now: start.addingTimeInterval(4)))
    XCTAssertFalse(ticket.logLabel.contains("-1001"))
    XCTAssertTrue(ticket.logLabel.contains("001"))
  }

  // MARK: - Telegram JSON

  func testParsesCallbackQueryUpdate() throws {
    let json = """
    {"update_id": 100,
     "callback_query": {"id": "cb-1",
       "from": {"id": 42, "is_bot": false, "first_name": "Lee"},
       "message": {"message_id": 77,
         "chat": {"id": -1001234567890, "type": "supergroup"},
         "text": "🔐 승인 필요"},
       "data": "qt:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:allow"}}
    """
    let update = try JSONDecoder().decode(TelegramUpdate.self, from: Data(json.utf8))
    XCTAssertEqual(update.updateID, 100)
    XCTAssertEqual(update.callbackQuery?.id, "cb-1")
    XCTAssertEqual(update.callbackQuery?.message?.messageID, 77)
    XCTAssertEqual(update.callbackQuery?.message?.chat?.id, -1_001_234_567_890)
    XCTAssertEqual(update.callbackQuery?.data,
                   "qt:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa:allow")
    XCTAssertEqual(RemoteApprovalCallback.parse(update.callbackQuery?.data ?? "")?.action,
                   .allow)
  }

  func testParsesUpdateWithoutCallbackQuery() throws {
    let json = #"{"update_id": 5, "message": {"message_id": 1, "text": "hi"}}"#
    let update = try JSONDecoder().decode(TelegramUpdate.self, from: Data(json.utf8))
    XCTAssertEqual(update.updateID, 5)
    XCTAssertNil(update.callbackQuery)
  }

  func testParsesBotInfoWithoutToken() throws {
    let json = #"{"id": 123456789, "is_bot": true, "first_name": "QuickTalk", "username": "qt_bot"}"#
    let bot = try JSONDecoder().decode(TelegramBotInfo.self, from: Data(json.utf8))
    XCTAssertEqual(bot.displayName, "@qt_bot")
    XCTAssertEqual(bot.id, 123_456_789)
  }

  // MARK: - 설정 왕복

  func testRemoteApprovalSettingsDefaultOff() {
    let settings = QuickTalkSettings()
    XCTAssertFalse(settings.remoteApprovalEnabled)
    XCTAssertEqual(settings.remoteApprovalChatID, "")
  }

  func testRemoteApprovalSettingsRoundTrip() throws {
    var settings = QuickTalkSettings()
    settings.remoteApprovalEnabled = true
    settings.remoteApprovalChatID = "-1001234567890"
    let back = try JSONDecoder().decode(QuickTalkSettings.self,
                                        from: try JSONEncoder().encode(settings))
    XCTAssertTrue(back.remoteApprovalEnabled)
    XCTAssertEqual(back.remoteApprovalChatID, "-1001234567890")
  }

  func testLegacyJSONWithoutRemoteApprovalKeysUsesDefaults() throws {
    let data = try JSONEncoder().encode(QuickTalkSettings())
    var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    json.removeValue(forKey: "remoteApprovalEnabled")
    json.removeValue(forKey: "remoteApprovalChatID")
    let legacy = try JSONSerialization.data(withJSONObject: json)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: legacy)
    XCTAssertFalse(decoded.remoteApprovalEnabled)
    XCTAssertEqual(decoded.remoteApprovalChatID, "")
  }

  // MARK: - 오류 문구

  func testTransportErrorNeverLeaksURLOrToken() {
    let error = TelegramError.transport
    XCTAssertEqual(error.safeDescription, L("Telegram에 연결하지 못했습니다."))
    XCTAssertFalse(error.safeDescription.contains("api.telegram.org"))
    XCTAssertFalse(error.safeDescription.contains("bot"))
  }
}
