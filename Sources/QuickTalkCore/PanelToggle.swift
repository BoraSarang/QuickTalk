import Foundation

// [FEATURE] 전역 단축키(⌘Space) 토글 판정 (2026-10-31)
//
// 왜 Core 로 뺐나: "이미 보이는 창을 다시 누르면 숨긴다"는 규칙이 AppDelegate 안에만 있으면
// 값으로 고정할 수 없어서 회귀가 조용히 생긴다. 실제로 2026-10-31 사용자 실측에서
// 창이 보이는데 키 창이 아니면(다른 앱이 앞에 있으면) **숨기지 않고 중앙으로 다시 배치**하는
// 버그가 있었다. 여기서는 판정만 하고, 창을 다루는 일은 앱이 한다.
//
// 우선순위: pill 이 떠 있으면 pill 부터 닫는다(Spotlight 토글). 그다음 창이 보이면 숨긴다.
// 둘 다 없을 때만 새로 연다 — 이때 pill/창 선택은 호출부(ShortcutEntryPresentation)가 맡는다.

public enum PanelToggle {
  public enum Action: Equatable {
    /// 포인터 pill 을 닫는다.
    case dismissPill
    /// 대화 창을 숨긴다(위치를 바꾸지 않는다).
    case hidePanel
    /// 아무것도 떠 있지 않다 — 호출부가 pill 또는 창을 새로 연다.
    case show
  }

  /// 단축키를 눌렀을 때 할 일.
  /// - Parameters:
  ///   - pillVisible: 포인터 pill 이 떠 있는가
  ///   - panelVisible: 대화 창이 화면에 보이는가(키 창이 아니어도 보이면 true)
  public static func decide(pillVisible: Bool, panelVisible: Bool) -> Action {
    if pillVisible { return .dismissPill }
    if panelVisible { return .hidePanel }
    return .show
  }
}
