import Foundation

// [FEATURE] 원격 승인 서비스 (v0.39)
//
// 예약 작업·맡긴 작업(Job)이 승인을 기다리면 Telegram 으로 카드 한 장을 보내고,
// **설정한 chat 하나**의 버튼 callback 만 받아 `.allowOnce` / `.deny` 로 되돌린다.
//
// 이 서비스는 **결정 경로를 새로 만들지 않는다.** 실제 결정은 기존
// `UIStore.resolveScheduledApproval` 이 하며, 여기서는 입력을 전달할 뿐이다.
//
// 수명:
//   · 설정이 준비되면 long polling 시작, 아니면 중지.
//   · pending 은 앱 전체에 하나. 새 요청·Mac 처리·만료·실행 종료에서 정리한다.
//   · 앱이 꺼지면 버튼은 응답할 수 없다 — 메시지에 그 사실을 적는다.

@MainActor
final class RemoteApprovalService {
  typealias SettingsProvider = () -> QuickTalkSettings
  typealias TokenProvider = () -> String?

  /// 원격 결정 → 앱의 승인 결정으로 넘기는 훅(AppDelegate 가 `UIStore` 에 연결).
  var onDecision: (@MainActor (RemoteApprovalAction) -> Void)?

  private let settingsProvider: SettingsProvider
  private let tokenProvider: TokenProvider
  private let transport: TelegramTransport
  private let now: () -> Date
  private let lifetime: TimeInterval
  /// QA 는 polling 없이 callback 경로만 확인한다.
  private let autoPolling: Bool

  /// 지금 응답을 기다리는 메시지 — 없으면 nil.
  private(set) var pending: RemoteApprovalTicket?
  /// pending 과 짝을 이루는 승인 요청(문구·QA 확인용).
  private(set) var pendingApproval: ScheduledApproval?
  private(set) var isPolling = false
  /// QA·설정 화면에서 확인할 전송 횟수.
  private(set) var sentCount = 0
  /// 마지막 네트워크 오류 — 토큰·URL 을 담지 않은 안전한 문구.
  private(set) var lastError: String?

  private var pollingTask: Task<Void, Never>?
  private var pollingGeneration = 0
  private var updateOffset: Int64?
  /// 전송 중에 Mac 에서 먼저 결정됐는지 판별한다 — 늦게 도착한 메시지를 pending 으로 만들지 않는다.
  private var offerGeneration = 0

  init(settingsProvider: @escaping SettingsProvider,
       tokenProvider: @escaping TokenProvider,
       transport: TelegramTransport,
       now: @escaping () -> Date = Date.init,
       lifetime: TimeInterval = RemoteApprovalTicket.lifetime,
       autoPolling: Bool = true) {
    self.settingsProvider = settingsProvider
    self.tokenProvider = tokenProvider
    self.transport = transport
    self.now = now
    self.lifetime = lifetime
    self.autoPolling = autoPolling
  }

  // MARK: - 설정

  var config: RemoteApprovalConfig {
    let settings = settingsProvider()
    return RemoteApprovalConfig(enabled: settings.remoteApprovalEnabled,
                                chatID: settings.remoteApprovalChatID,
                                token: tokenProvider())
  }

  /// 설정이 바뀔 때마다 — 켜짐/꺼짐·토큰·chat ID 를 반영한다.
  func applySettings() {
    if config.isReady {
      startPollingIfNeeded()
    } else {
      stopPolling()
      if pending != nil {
        closePending(with: L("원격 승인이 꺼져 취소되었습니다."))
      }
    }
  }

  // MARK: - 요청 보내기

  /// 승인 대기 1건을 Telegram 으로 보낸다. 실패해도 **승인 대기 자체는 막지 않는다.**
  func offer(_ approval: ScheduledApproval) async {
    let config = config
    guard config.isReady, let token = tokenProvider() else { return }
    startPollingIfNeeded()

    // pending 은 하나 — 새 요청이 오면 이전 메시지는 대체됨으로 닫는다.
    if pending != nil { closePending(with: L("새 승인 요청으로 대체되었습니다.")) }
    offerGeneration += 1
    let generation = offerGeneration

    let request = approval.request
    let fallback = approval.kind == .job ? L("맡긴 작업") : L("예약 작업")
    let content = RemoteApprovalContent.make(
      requestTitle: approval.displayTitle,
      fallbackTitle: fallback,
      command: request.command,
      levelName: request.level.displayName,
      riskName: request.risk.displayName,
      irreversible: request.irreversible,
      reason: request.reason,
      writeScopes: request.writeScopes,
      personaName: approval.personaName,
      secrets: [token])

    let nonce = RemoteApprovalCallback.makeNonce()
    let buttons = [
      TelegramButton(text: content.allowTitle,
                     callbackData: RemoteApprovalCallback(nonce: nonce, action: .allow).data),
      TelegramButton(text: content.denyTitle,
                     callbackData: RemoteApprovalCallback(nonce: nonce, action: .deny).data)
    ]

    do {
      let message = try await transport.sendMessage(
        token: token,
        chatID: config.normalizedChatID,
        text: content.messageText,
        buttons: buttons)

      // 전송을 기다리는 사이 Mac 에서 먼저 처리됐다 — 버튼만 지우고 pending 에 넣지 않는다.
      guard generation == offerGeneration else {
        try? await transport.editMessageText(token: token,
                                             chatID: config.normalizedChatID,
                                             messageID: message.messageID,
                                             text: L("🖥 이미 처리된 승인 요청입니다."))
        return
      }

      let ticket = RemoteApprovalTicket(nonce: nonce,
                                        chatID: config.normalizedChatID,
                                        messageID: message.messageID,
                                        createdAt: now(),
                                        lifetime: lifetime)
      pending = ticket
      pendingApproval = approval
      sentCount += 1
      lastError = nil
      NSLog("[QuickTalk] 원격 승인 전송 — %@", ticket.logLabel)
    } catch let error as TelegramError {
      lastError = error.safeDescription
      NSLog("[QuickTalk] 원격 승인 전송 실패 — %@", error.safeDescription)
    } catch {
      lastError = L("Telegram에 연결하지 못했습니다.")
      NSLog("[QuickTalk] 원격 승인 전송 실패 — 알 수 없는 오류")
    }
  }

  // MARK: - 결정 반영

  /// Mac 카드에서 먼저 처리됨 — 원격 메시지의 버튼을 지우고 결과만 남긴다.
  func localResolution(_ choice: AgentApprovalChoice) {
    offerGeneration += 1
    let accepted = choice != .deny
    closePending(with: accepted ? L("🖥 Mac에서 허용됨") : L("🖥 Mac에서 거부됨"))
  }

  /// 10분 만료 — UIStore 타이머가 `resolve(.deny)` 직전에 부른다.
  func expire() {
    offerGeneration += 1
    closePending(with: L("⌛ 시간 초과 — 자동 거부"))
  }

  /// 실행 종료·새 요청·설정 끔 — 남은 메시지를 취소로 닫는다.
  func cancelPending() {
    offerGeneration += 1
    closePending(with: L("취소됨 — 실행이 끝났습니다."))
  }

  private func closePending(with text: String) {
    guard let ticket = pending else { return }
    pending = nil
    pendingApproval = nil
    let token = tokenProvider()
    let transport = self.transport
    Task {
      guard let token, RemoteApprovalConfig.isValidToken(token) else { return }
      try? await transport.editMessageText(token: token,
                                           chatID: ticket.chatID,
                                           messageID: ticket.messageID,
                                           text: text)
    }
  }

  // MARK: - polling

  private func startPollingIfNeeded() {
    guard autoPolling, config.isReady, pollingTask == nil else { return }
    pollingGeneration += 1
    let generation = pollingGeneration
    isPolling = true
    pollingTask = Task { [weak self] in
      guard let self else { return }
      await self.pollLoop(generation: generation)
      if self.pollingGeneration == generation {
        self.pollingTask = nil
        self.isPolling = false
      }
    }
  }

  private func stopPolling() {
    pollingGeneration += 1
    pollingTask?.cancel()
    pollingTask = nil
    isPolling = false
  }

  /// 앱 종료 — 네트워크 편집 없이 조용히 멈춘다.
  func stop() {
    stopPolling()
    pending = nil
    pendingApproval = nil
    offerGeneration += 1
  }

  private func pollLoop(generation: Int) async {
    var backoff: UInt64 = 3
    while !Task.isCancelled, generation == pollingGeneration {
      let config = self.config
      guard config.isReady, let token = tokenProvider() else { return }
      do {
        let updates = try await transport.getUpdates(token: token,
                                                     offset: updateOffset,
                                                     timeout: 25)
        if Task.isCancelled || generation != pollingGeneration { return }
        backoff = 3
        lastError = nil
        for update in updates {
          updateOffset = max(updateOffset ?? 0, update.updateID + 1)
          if let query = update.callbackQuery {
            await handle(query)
          }
        }
      } catch let error as TelegramError {
        if Task.isCancelled || generation != pollingGeneration { return }
        lastError = error.safeDescription
        try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
        backoff = min(backoff * 2, 30)
      } catch {
        if Task.isCancelled || generation != pollingGeneration { return }
        lastError = L("Telegram에 연결하지 못했습니다.")
        try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
        backoff = min(backoff * 2, 30)
      }
    }
  }

  /// callback 1건 처리. **설정한 chat + 현재 nonce + 10분 안**일 때만 결정한다.
  private func handle(_ query: TelegramCallbackQuery) async {
    guard let token = tokenProvider() else { return }
    guard let raw = query.data, let callback = RemoteApprovalCallback.parse(raw) else {
      await answer(query, token: token, text: L("알 수 없는 요청입니다."))
      return
    }
    let config = self.config
    guard config.isReady, let ticket = pending else {
      await answer(query, token: token, text: L("이미 처리되었거나 만료된 요청입니다."))
      return
    }
    // chat ID 는 설정값과 **메시지의 chat** 둘 다 맞아야 한다.
    guard let chatID = query.message?.chat.map({ String($0.id) }),
          chatID == ticket.chatID,
          chatID == config.normalizedChatID else {
      await answer(query, token: token, text: L("허용되지 않은 요청입니다."))
      return
    }
    guard callback.nonce == ticket.nonce else {
      await answer(query, token: token, text: L("이미 처리되었거나 만료된 요청입니다."))
      return
    }
    if ticket.isExpired(now: now()) {
      offerGeneration += 1
      pending = nil
      pendingApproval = nil
      try? await transport.editMessageText(token: token,
                                           chatID: ticket.chatID,
                                           messageID: ticket.messageID,
                                           text: L("⌛ 시간 초과 — 자동 거부"))
      await answer(query, token: token, text: L("시간이 지나 자동 거부되었습니다."))
      return
    }

    // 여기서부터 유효한 결정 — 재사용을 막기 위해 pending 을 먼저 비운다.
    offerGeneration += 1
    pending = nil
    pendingApproval = nil
    let accepted = callback.action == .allow
    let resultText = accepted ? L("✅ 허용됨 (원격)") : L("❌ 거부됨 (원격)")
    try? await transport.editMessageText(token: token,
                                         chatID: ticket.chatID,
                                         messageID: ticket.messageID,
                                         text: resultText)
    await answer(query, token: token,
                 text: accepted ? L("허용했습니다.") : L("거부했습니다."))
    NSLog("[QuickTalk] 원격 승인 결정 — %@ %@",
          accepted ? "allow" : "deny", ticket.logLabel)
    onDecision?(callback.action)
  }

  private func answer(_ query: TelegramCallbackQuery, token: String, text: String) async {
    try? await transport.answerCallbackQuery(token: token, callbackID: query.id, text: text)
  }

  /// QA 전용 — polling 없이 callback 1건을 같은 경로로 처리한다.
  func handleCallbackForQA(_ query: TelegramCallbackQuery) async {
    await handle(query)
  }

  // MARK: - 연결 테스트

  /// `getMe` + 테스트 메시지 1회. 성공하면 봇 이름을 돌려준다.
  func testConnection() async -> Result<String, TelegramError> {
    let config = self.config
    guard config.canConnect, let token = tokenProvider() else {
      return .failure(.notConfigured(
        config.inactivityReason ?? L("봇 토큰과 chat ID를 먼저 설정하세요.")))
    }
    do {
      let bot = try await transport.getMe(token: token)
      _ = try await transport.sendMessage(
        token: token,
        chatID: config.normalizedChatID,
        text: L("✅ QuickTalk 연결 테스트입니다. 이 메시지가 보이면 원격 승인을 받을 준비가 되었습니다."),
        buttons: [])
      startPollingIfNeeded()
      lastError = nil
      return .success(bot.displayName)
    } catch let error as TelegramError {
      lastError = error.safeDescription
      return .failure(error)
    } catch {
      lastError = L("Telegram에 연결하지 못했습니다.")
      return .failure(.transport)
    }
  }
}
