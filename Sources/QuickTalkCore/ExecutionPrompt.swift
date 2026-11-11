import Foundation

// [FEATURE] 답변 → 실행 (v0.36, PLAN_v0.36 §3)
//
// 답변 아래 [이대로 실행]을 누르면 **사용자 말풍선은 짧게**, 모델에는 **실행 계약**을 준다.
// 말풍선에 계약 전문을 넣으면 대화가 지저분해지고, 모델 프롬프트에만 넣으면
// 사용자가 무엇을 요청했는지 화면에서 알 수 없다 — 둘을 나눈다.

public enum ExecutionPrompt {
  /// 화면에 남는 사용자 말풍선 — 짧고 명확하게.
  public static var visibleText: String { L("이 답변대로 실행해 주세요.") }

  /// 모델에만 주는 실행 계약.
  ///
  /// 화면 문구가 아니라 **모델 지시문**이므로 번역표(`L`)를 거치지 않는다. 대신 앱 표시
  /// 언어가 영어면 영어 계약을 준다 — 한국어만 주면 영어로 대화하던 모델이 말투를 바꾼다.
  public static var contract: String {
    L10n.effective == .en ? englishContract : koreanContract
  }

  private static let koreanContract = """
    방금 네가 답한 절차를 실제로 실행해 주세요.
    - 위 답변의 내용을 다시 묻지 말고, 그 절차를 기준으로 진행하세요.
    - 먼저 실행할 단계를 3~6개로 짧게 보여 주세요.
    - 각 단계는 지금 이 Mac에서 실제로 실행 가능한 것이어야 합니다.
    - 되돌릴 수 없는 동작(삭제·덮어쓰기·전송·결제)은 실행 전에 무엇이 바뀌는지 한 줄로 알려 주세요.
    - 도구가 필요하면 지금 실행하고, 결과까지 확인한 뒤 최종 보고를 쓰세요.
    - 실행할 수 없으면 이유를 한 줄로 말하고 멈추세요.
    """

  private static let englishContract = """
    Now actually carry out the procedure you just described in your last answer.
    - Do not ask again what was in that answer; use it as the plan.
    - First list the steps you will run, 3–6 short lines.
    - Every step must be something you can really do on this Mac right now.
    - Before any irreversible action (delete, overwrite, send, pay), say in one line what will change.
    - If you need a tool, run it now and check the result before writing the final report.
    - If it cannot be done, say why in one line and stop.
    """
}
