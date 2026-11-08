import Foundation

// 후속 질문 제안(v0.32) — 응답이 끝난 뒤 칩 3개를 준비한다.
//
// 흐름
//   ① `send()` 완료 지점에서 `scheduleFollowUps` 를 부른다(오류·중지 응답은 제외).
//   ② 무료 문구 모드면 바로 칩을 채운다(모델 호출 0).
//   ③ 모델 모드면 2.5초 뒤 **짧게 1회** 호출한다 — 읽기 시작한 사용자를 방해하지 않게.
//     8초 안에 답이 없으면 포기하고 무료 문구로 대체한다(칩이 영영 안 뜨는 일 방지).
//   ④ 새 전송·중지 시 이전 작업과 칩을 지운다.
//
// 상태는 **대화방(ChatSession)별**로 둔다 — 다른 방을 열어도 그 방의 칩이 섞이지 않는다.

/// 답변 턴 하나에 붙는 후속 질문 칩.
struct FollowUpState: Equatable {
  var chips: [String]
}

extension UIStore {
  /// 응답이 끝난 뒤 후속 질문을 예약한다. 조건이 맞지 않으면 아무것도 하지 않는다.
  func scheduleFollowUps(session: ChatSession, assistantTurnID: UUID,
                         question: String, answer: String) {
    clearFollowUps(for: session)
    guard settings.followUpsEnabled else { return }
    guard FollowUpSuggest.isEligible(question: question, answer: answer) else { return }

    // 무료 문구 — 모델을 부르지 않고 즉시 채운다.
    if settings.followUpSource == .template {
      let chips = FollowUpSuggest.fallback(question: question, answer: answer)
      if !chips.isEmpty {
        session.followUpStates[assistantTurnID] = FollowUpState(chips: chips)
      }
      return
    }

    let convID = session.conversation.id
    // 비서별 AI(v0.35) — 답변을 만든 모델과 같은 AI로 후속 질문을 만든다.
    let provider = ProviderResolver.provider(settings: settings,
                                             personaID: session.conversation.personaID)
    let count = FollowUpSuggest.defaultCount
    session.followUpTask = Task { @MainActor [weak self, weak session] in
      // 답변을 읽기 시작한 사용자를 방해하지 않게 잠깐 기다린다.
      try? await Task.sleep(for: .milliseconds(2500))
      guard !Task.isCancelled, let self, let session else { return }
      guard session.conversation.id == convID, !session.isReplying else { return }
      guard self.settings.followUpsEnabled,
            self.settings.followUpSource == .model else { return }

      var chips: [String] = []
      if let provider {
        let prompt = FollowUpSuggest.prompt(question: question, answer: answer, count: count)
        if let raw = await Self.followUpReply(provider: provider, prompt: prompt) {
          chips = FollowUpSuggest.parse(raw, limit: count)
        }
      }
      guard !Task.isCancelled, session.conversation.id == convID else { return }
      if chips.isEmpty {
        chips = FollowUpSuggest.fallback(question: question, answer: answer, count: count)
      }
      if !chips.isEmpty {
        session.followUpStates[assistantTurnID] = FollowUpState(chips: chips)
      }
      session.followUpTask = nil
    }
  }

  /// 사용자가 칩을 눌렀다 — 설정에 따라 바로 보내거나 입력창에 채운다.
  func sendFollowUp(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !isReplying else { return }
    clearFollowUps(for: activeSession)
    draft = trimmed
    if settings.followUpAutoSend {
      send()
    } else {
      composerFocusToken = UUID()
    }
  }

  /// 이 대화방의 후속 질문 작업·칩을 지운다(새 전송·중지).
  func clearFollowUps(for session: ChatSession) {
    session.followUpTask?.cancel()
    session.followUpTask = nil
    if !session.followUpStates.isEmpty { session.followUpStates.removeAll() }
  }

  /// 모델 1회 호출 — 8초를 넘기면 포기한다.
  /// 모델 요청과 타이머를 **경쟁**시켜 먼저 끝난 쪽을 쓴다. 부모 작업이 취소되면
  /// 두 자식도 함께 취소되어 기다리지 않고 nil 로 돌아온다.
  private static func followUpReply(provider: LLMProviderConfig, prompt: String) async -> String? {
    await withTaskGroup(of: String?.self) { group in
      group.addTask {
        try? await Self.reply(provider: provider, prompt: prompt, history: [])
      }
      group.addTask {
        try? await Task.sleep(for: .seconds(8))
        return nil
      }
      let first = await group.next() ?? nil
      group.cancelAll()
      return first
    }
  }
}
