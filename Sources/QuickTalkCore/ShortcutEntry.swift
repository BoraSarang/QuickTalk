import Foundation

// [FEATURE] T-21 포인터 pill — ⌘Space를 눌렀을 때 무엇을 띄울지 (2026-10-21)
//
// pill은 대화 창과 **별개 기능이 아니라 같은 대화의 다른 표현**이다.
// 설정 › 일반의 "단축키로 열 때 유지"(`shortcutSessionMinutes`) 규칙을 그대로 따르고,
// 그 결과가 "새 대화"일 때만 빈 대화 창 대신 pill을 띄운다.
//
// | 마지막 대화 | 결과 |
// |---|---|
// | 유지 시간 이내 | `.conversation` — 지금처럼 대화 창 그대로 |
// | 유지 시간 초과 | `.pill` — 빈 창 대신 포인터 자리 pill |
// | 이어갈 대화 없음(첫 실행·빈 대화) | `.pill` |
// | 설정 0(사용 안 함) | 항상 `.pill` (사용자 확정: 2026-10-21) |
public enum ShortcutEntryPresentation: Equatable {
  /// 마지막 대화를 이어서 연다 — 지금 대화 창을 그대로 보여 준다.
  case conversation
  /// 새 대화의 입구 — 빈 대화 창을 만들지 않고 포인터 자리에 pill만 띄운다.
  case pill

  /// - Parameters:
  ///   - settings: 유지 시간 규칙을 가진 설정.
  ///   - lastActivity: 현재 대화의 마지막 갱신 시각.
  ///   - hasTurns: 현재 대화에 이어갈 턴이 있는지.
  public static func decide(settings: QuickTalkSettings,
                            lastActivity: Date?,
                            hasTurns: Bool,
                            now: Date = Date()) -> Self {
    // 이어갈 대화가 없으면 항상 pill — 빈 대화 창을 띄울 이유가 없다.
    guard hasTurns else { return .pill }
    return settings.continuesSession(lastActivity: lastActivity, now: now) ? .conversation : .pill
  }
}
