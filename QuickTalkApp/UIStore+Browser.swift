import Foundation

// [FEATURE] 격리 브라우저 캐시 (v0.38.1, PLAN_v0.38.1 §5.1·§6)
//
// 브라우저는 **대화 단위**로 산다. Job 이 도는 동안 사용자가 다른 대화를 열어도
// Job 의 페이지와 사용자의 페이지가 섞이지 않는다.
//
// 정리 규칙
//   · 대화별 최대 2개(LRU) — 메모리·웹 프로세스가 무한히 늘지 않게.
//   · 15분 유휴 — 마지막 사용 뒤 방치된 페이지는 창을 닫는다.
//   · 앱 종료·데이터 지우기 — 전부 정리한다.
//
// 전용 프로필 ID는 설정에 저장한다(비밀 아님). Safari 와 쿠키·캐시를 공유하지 않는
// WebKit 데이터 저장소 식별자다.

extension UIStore {
  /// 도구가 움직이는 대화 — 예약/Job 이면 그 대화, 아니면 활성 대화.
  var browserConversation: Conversation {
    scheduledRun?.conversation ?? activeSession.conversation
  }

  /// 이 대화의 브라우저. 꺼져 있으면 nil(도구 자체가 목록에 없어야 하지만 이중 확인).
  @MainActor
  func browserService(for session: ChatSession? = nil) -> BrowserService? {
    guard settings.browserEnabled, settings.agentToolsEnabled else { return nil }
    // 예약/Job 실행 중에는 **그 실행의 대화**를 쓴다 — 사용자가 보는 대화의 페이지를 덮지 않는다.
    let conversationID = scheduledRun?.conversation.id
      ?? session?.conversation.id
      ?? activeSession.conversation.id
    sweepBrowserServices()
    if let existing = browserServices[conversationID] {
      browserLastUsed[conversationID] = Date()
      return existing
    }
    let service = BrowserService(profileID: browserProfileUUID())
    browserServices[conversationID] = service
    browserLastUsed[conversationID] = Date()
    evictIfNeeded()
    return service
  }

  /// 저장된 프로필 ID — 없으면 만들어 **즉시 설정에 저장**한다.
  /// 저장하지 않으면 앱을 껐다 켤 때마다 새 프로필이 생겨 쿠키가 사라진다.
  func browserProfileUUID() -> UUID {
    if let id = UUID(uuidString: settings.browserProfileID) { return id }
    let id = UUID()
    settings.browserProfileID = id.uuidString
    return id
  }

  /// 15분 넘게 쓰지 않은 브라우저를 정리한다.
  @MainActor
  func sweepBrowserServices() {
    let cutoff = Date().addingTimeInterval(-15 * 60)
    for (id, used) in browserLastUsed where used < cutoff {
      browserServices[id]?.teardown()
      browserServices[id] = nil
      browserLastUsed[id] = nil
    }
  }

  /// 최대 2개 — 가장 오래된 것부터 닫는다. 방금 만든 것은 남긴다.
  @MainActor
  private func evictIfNeeded() {
    while browserServices.count > 2 {
      let oldest = browserLastUsed.min { $0.value < $1.value }?.key
      guard let oldest else { return }
      browserServices[oldest]?.teardown()
      browserServices[oldest] = nil
      browserLastUsed[oldest] = nil
    }
  }

  /// 설정 › 격리 브라우저 › 데이터 지우기 — 쿠키·캐시·로컬 저장소를 모두 지운다.
  @MainActor
  func clearBrowserData() async {
    let profile = browserProfileUUID()
    for (_, service) in browserServices { service.teardown() }
    browserServices.removeAll()
    browserLastUsed.removeAll()
    await BrowserService.clearData(profileID: profile)
    NSLog("[QuickTalk] 격리 브라우저 데이터 삭제 — profile=%@", profile.uuidString)
  }

  /// 앱 종료 — 열린 페이지를 모두 닫는다.
  @MainActor
  func teardownBrowsers() {
    for (_, service) in browserServices { service.teardown() }
    browserServices.removeAll()
    browserLastUsed.removeAll()
  }
}
