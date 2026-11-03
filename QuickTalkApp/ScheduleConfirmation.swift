import Foundation

/// 모델이 제안한 예약 작업 — 확인 카드가 보여 주고, 사용자가 [등록]을 눌러야 저장된다 (v0.26 4단계).
struct ScheduleConfirmation: Equatable {
  let conversationID: UUID
  /// 카드가 붙는 턴 — 그 턴 아래에 그린다.
  let turnID: UUID?
  let proposal: ScheduleProposal
  /// 같은 제목·규칙의 일정이 이미 있는가 — 카드에 "덮어씁니다" 안내를 띄운다.
  let isDuplicate: Bool
}
