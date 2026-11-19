import Foundation
import SwiftUI

// [FEATURE] v0.41 전송 게이트 — 대화창·pill이 **같은 규칙**으로 보내기 전에 한 번 검사한다.
//
// · 검사는 전송 직전, 동기. 규칙 엔진은 10,000자에서도 수 ms(실측 3.9ms).
// · 문제가 없으면 그대로 보낸다(fail-open). 전송을 막지 않는다.
// · 자동 경로(`send(executionOf:)`·예약·재응답)와 슬래시 명령은 검사하지 않는다.
// · 문장 전체를 저장하지 않는다 — 구간만 `ProofreadHistory` 에 남긴다.

enum ProofreadSource: String {
  case composer
  case pill
}

enum ProofreadDecision {
  case accepted
  case asIs
  case dismissed
}

/// 카드 한 장의 상태 — 원문·검사 결과·통계 영수증.
struct ProofreadHintState: Identifiable, Equatable {
  let id = UUID()
  let source: ProofreadSource
  let original: String
  let result: ProofreadResult
  /// 기록이 꺼져 있으면 nil.
  let token: ProofreadRecordToken?

  var shown: [ProofreadIssue] {
    Array(result.issues.prefix(ProofreadEngine.maximumIssuesShown))
  }

  var extraCount: Int {
    max(0, result.issues.count - ProofreadEngine.maximumIssuesShown)
  }

  /// pill 1행 — "3곳 · 띄어쓰기 2 · 맞춤법 1"
  var categorySummary: String {
    ProofreadCategory.allCases.compactMap { category in
      let n = result.count(of: category)
      return n > 0 ? "\(category.displayName) \(n)" : nil
    }
    .joined(separator: " · ")
  }
}

enum ProofreadGate {
  /// 검사 대상인가 — 슬래시 명령·짧은 글·너무 긴 글은 건너뛴다.
  static func shouldCheck(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty, !trimmed.hasPrefix("/") else { return false }
    guard trimmed.utf16.count <= ProofreadEngine.maximumLength else { return false }
    return trimmed.unicodeScalars.contains { (0xAC00...0xD7A3).contains($0.value) }
  }

  /// 전송 직전 한 번 검사한다. 문제가 없으면 nil(바로 보내라는 뜻).
  static func evaluate(_ text: String, source: ProofreadSource,
                       settings: QuickTalkSettings,
                       history: ProofreadHistory,
                       disabledForConversation: Bool) -> ProofreadHintState? {
    guard settings.proofreadHintsEnabled, !disabledForConversation,
          shouldCheck(text) else { return nil }
    if source == .pill, settings.proofreadScope == .composerOnly { return nil }

    let result = ProofreadEngine.check(text, ignoring: history.ignored)
    guard !result.isClean else {
      if settings.proofreadRecordEnabled {
        history.recordCheck(hinted: false, issues: [], source: source.rawValue)
      }
      return nil
    }
    let token = settings.proofreadRecordEnabled
      ? history.recordCheck(hinted: true, issues: result.issues, source: source.rawValue)
      : nil
    return ProofreadHintState(source: source, original: text,
                              result: result, token: token)
  }

  static func record(_ decision: ProofreadDecision,
                     for hint: ProofreadHintState,
                     history: ProofreadHistory) {
    guard let token = hint.token else { return }
    switch decision {
    case .accepted: history.recordAccepted(token)
    case .asIs: history.recordAsIs(token)
    case .dismissed: history.recordDismissed(token)
    }
  }
}
