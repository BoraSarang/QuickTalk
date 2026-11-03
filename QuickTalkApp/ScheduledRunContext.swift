import Foundation

// [FEATURE] 예약 실행 컨텍스트 (v0.26 3단계)
//
// 예약 실행은 **사용자가 보고 있는 대화가 아니라** 비서 전용 대화에서 돈다.
// `AgentExecutor` 는 도구 실행 상태(카드·승인·쓰기 범위·중지 손잡이)를 `UIStore` 를 통해
// 읽고 쓰므로, 실행 중에는 UIStore 의 접근자가 이 컨텍스트로 갈라진다.
//
// 이렇게 하면
//   · 사용자가 채팅 중이어도 예약 실행이 그 대화에 카드를 끼워 넣지 않고,
//   · 승인은 **그 예약 대화를 열었을 때만** 카드로 보이며,
//   · 실행이 끝나면 대화 한 개가 통째로 보관함에 남는다.

/// 예약 실행 1회의 상태.
final class ScheduledRunContext {
  let taskID: UUID
  /// 비서 전용 대화 저장소 — 현재 대화(`UIStore.core`)와 **완전히 분리**한다.
  let session: ConversationStore
  /// 실행 카드(도구 기록)가 붙는 턴.
  var turnID: UUID?
  /// 이번 실행에서 쌓인 카드 — 승인 카드 렌더에 쓴다.
  var events: [AgentEvent] = []
  /// `web_search` 로 확인한 출처 — 리포트 출처 절에 쓴다.
  var sources: [TurnSource] = []
  /// 전역 권한 정책 — 예약 실행은 **대화 오버라이드를 쓰지 않는다**(PLAN §6).
  let policy: AgentPolicy
  /// 이 대화에서 승인된 쓰기 폴더(7일). 실행이 끝나면 대화 기록에 남는다.
  var writeScopes: [String] = []
  /// 이 대화에서 승인된 화면 조작 앱(7일).
  var uiGrants: [UiAppGrant] = []
  /// 진행 중인 셸 실행의 중지 손잡이.
  var runHandle: SandboxCancellation?
  /// QA 헤드리스 — 승인 요청을 거부로 처리한다.
  var selfTestMode = false
  /// 사용자가 카드에서 [중단]을 눌렀다 — 다음 도구 호출부터 거부하고 리포트를 만들지 않는다.
  var cancelled = false
  /// 승인 대기 요청(있으면 카드가 뜬다).
  var approval: AgentApprovalRequest?
  var approvalContinuation: CheckedContinuation<AgentApprovalChoice, Never>?
  /// 10분이 지나 자동 거부됐는가 — 실패 사유 문구를 가른다.
  var approvalTimedOut = false

  init(taskID: UUID, session: ConversationStore, policy: AgentPolicy) {
    self.taskID = taskID
    self.session = session
    self.policy = policy
  }

  var conversation: Conversation { session.conversation }
}

/// 예약 실행이 승인을 기다리는 상태 — UI·알림이 함께 읽는다.
struct ScheduledApproval: Equatable {
  let taskID: UUID
  let conversationID: UUID
  let turnID: UUID?
  /// 비서 이름(없으면 기본) — 알림 문구에 쓴다.
  let personaName: String?
  let request: AgentApprovalRequest
}

/// 예약 실행 1회가 끝났을 때 알림 계층에 넘기는 요약.
struct ScheduledRunNotice: Equatable {
  let taskID: UUID
  let conversationID: UUID?
  let personaName: String?
  let title: String
  let status: RunStatus
  let fileName: String?
  let reason: String?
}

extension AgentApprovalRequest {
  /// 승인 카드에 보여 줄 한 줄 요약 — 알림 본문에도 쓴다.
  var shortReason: String {
    reason.isEmpty ? command : reason
  }
}
