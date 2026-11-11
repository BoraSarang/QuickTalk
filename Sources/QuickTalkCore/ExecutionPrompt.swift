import Foundation

// [FEATURE] 답변 → 실행 (v0.36, PLAN_v0.36 §3)
//
// 답변 아래 [이대로 실행]을 누르면 **사용자 말풍선은 짧게**, 모델에는 **실행 계약**을 준다.
// 말풍선에 계약 전문을 넣으면 대화가 지저분해지고, 모델 프롬프트에만 넣으면
// 사용자가 무엇을 요청했는지 화면에서 알 수 없다 — 둘을 나눈다.
//
// v0.36.2 — "처음부터 다시 하는" 문제 수정:
//   ① 계약이 "답변의 절차를 다시 수행"이라, 이미 끝난 일까지 반복했다.
//      → **아직 실행하지 않은 것만**, 새로 만들지 말고, 이미 확인한 값은 재확인 금지.
//   ② 모델은 자기 과거 도구 실행 기록을 받지 못한다(`AgentRunner` 는 `turn.text` 만 넘긴다).
//      → 그 답변을 만들 때 실행한 명령·결과를 `[이미 실행한 것]` 블록으로 함께 준다.

public enum ExecutionPrompt {
  /// 화면에 남는 사용자 말풍선 — 짧고 명확하게.
  public static var visibleText: String { L("이 답변대로 실행해 주세요.") }

  /// 모델에만 주는 실행 계약.
  ///
  /// 화면 문구가 아니라 **모델 지시문**이므로 번역표(`L`)를 거치지 않는다. 대신 앱 표시
  /// 언어가 영어면 영어 계약을 준다 — 한국어만 주면 영어로 대화하던 모델이 말투를 바꾼다.
  ///
  /// - Parameter alreadyRun: 실행 대상 답변을 만들 때 실제로 실행한 도구 기록.
  ///   있으면 "이미 한 일"을 알려 주어 같은 확인·생성을 반복하지 않게 한다.
  public static func contract(alreadyRun: [AgentEvent]? = nil) -> String {
    let base = L10n.effective == .en ? englishContract : koreanContract
    guard let block = alreadyRunBlock(alreadyRun) else { return base }
    return base + "\n\n" + block
  }

  private static let koreanContract = """
    방금 네가 답한 것 중 **아직 실행하지 않은 부분만** 실행해 주세요.
    - 이미 실행·확인한 단계는 반복하지 말고, 결과만 인용하세요.
    - 답변에 나온 실행 대상만 다루세요. 파일을 새로 만들거나 고치지 말고, 이미 있으면 그대로 쓰세요.
    - 실행할 것이 하나면 단계 목록 없이 바로 실행하세요. 여러 개일 때만 2~4줄로 보여 주세요.
    - 되돌릴 수 없는 동작(삭제·덮어쓰기·전송·결제)은 실행 전에 무엇이 바뀌는지 한 줄로 알려 주세요.
    - 새로 조사·검증하지 마세요. 이미 확인한 값은 다시 확인하지 않습니다.
    - 도구가 필요하면 지금 실행하고, 결과까지 확인한 뒤 최종 보고를 쓰세요.
    - 실행할 수 없으면 이유를 한 줄로 말하고 멈추세요.
    """

  private static let englishContract = """
    Run only the part of your last answer that has **not been run yet**.
    - Do not repeat steps you already ran or checked; cite their results instead.
    - Touch only what the answer names. Do not create or rewrite files; use existing ones as they are.
    - If there is a single action, just run it without a step list. List 2–4 steps only when there are several.
    - Before any irreversible action (delete, overwrite, send, pay), say in one line what will change.
    - Do not investigate or verify again. Values you already checked are settled.
    - If you need a tool, run it now and check the result before writing the final report.
    - If it cannot be done, say why in one line and stop.
    """

  /// 이미 실행한 도구 기록을 모델용 짧은 블록으로 만든다.
  ///
  /// 명령 전문을 그대로 넣으면 프롬프트가 커지고, 출력까지 넣으면 대화가 오염된다.
  /// **최근 8개 · 명령 100자**로 자르고 성공/실패/거부만 남긴다.
  static func alreadyRunBlock(_ events: [AgentEvent]?) -> String? {
    guard let events, !events.isEmpty else { return nil }
    let english = L10n.effective == .en
    let rows = events
      .filter { $0.state == .done || $0.state == .failed || $0.state == .denied }
      .suffix(8)
      .map { event -> String in
        let raw = event.command.isEmpty ? event.title : event.command
        let oneLine = raw
          .replacingOccurrences(of: "\n", with: " ")
          .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
          .trimmingCharacters(in: .whitespaces)
        let command = oneLine.count > 100 ? String(oneLine.prefix(100)) + "…" : oneLine
        let state: String
        switch event.state {
        case .done: state = english ? "done" : "완료"
        case .failed: state = english ? "failed" : "실패"
        case .denied: state = english ? "denied" : "거부"
        default: state = english ? "unknown" : "알 수 없음"
        }
        return "- \(command) → \(state)"
      }
    guard !rows.isEmpty else { return nil }
    let header = english
      ? "[Already run while writing that answer — do not repeat these]"
      : "[그 답변을 만들 때 이미 실행한 것 — 반복하지 말 것]"
    return header + "\n" + rows.joined(separator: "\n")
  }
}
