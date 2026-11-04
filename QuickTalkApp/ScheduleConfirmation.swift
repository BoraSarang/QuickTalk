import Foundation

/// 모델이 제안한 예약 작업 변경 3종 — 확인 카드가 보여 주고, 사용자가 눌러야 저장된다 (v0.27).
enum SchedulePendingAction: Equatable {
  case create(ScheduleProposal)
  case update(ScheduleChangeProposal)
  case delete(ScheduleDeletionProposal)

  var isMutation: Bool {
    switch self {
    case .create, .update, .delete: return true
    }
  }
}

/// 확인 카드 하나 — 등록·변경·삭제를 같은 큐로 처리한다(한 턴에 1건).
struct ScheduleConfirmation: Equatable {
  let conversationID: UUID
  /// 카드가 붙는 턴 — 그 턴 아래에 그린다.
  let turnID: UUID?
  let action: SchedulePendingAction
  /// 같은 제목·규칙의 일정이 이미 있는가 — 등록 카드에 "덮어씁니다" 안내를 띄운다.
  let isDuplicate: Bool

  init(conversationID: UUID, turnID: UUID?,
       action: SchedulePendingAction, isDuplicate: Bool = false) {
    self.conversationID = conversationID
    self.turnID = turnID
    self.action = action
    self.isDuplicate = isDuplicate
  }

  var proposal: ScheduleProposal? {
    if case let .create(proposal) = action { return proposal }
    return nil
  }

  var change: ScheduleChangeProposal? {
    if case let .update(change) = action { return change }
    return nil
  }

  var deletion: ScheduleDeletionProposal? {
    if case let .delete(deletion) = action { return deletion }
    return nil
  }
}
