import Foundation

// [FEATURE] 창 레벨 정책 (2026-10-22)
//
// 왜 Core 로 뺐나: "📌 항상 위"는 AppKit 창 레벨이라 눈으로만 확인할 수 있고,
// 예전 규칙(`설정 창이 뜨면 대화 창을 내린다`)은 **핀을 켜도 설정 창을 열면 꺼진 것처럼 보이는**
// 문제를 만들었다(2026-10-22 사용자 보고: "최상위 클릭 해 놨는데 동작 안하는데?").
//
// 규칙
// - 핀 ON + 시스템 권한 안내 없음 → 대화 창은 **다른 앱 위**(floating). 설정 창이 떠 있어도 유지한다.
// - 설정·정보 창은 **지금 쓰고 있을 때만** 그 위(floatingAbove)에 둔다 — 핀 켜진 대화 창을 가리지 않게.
// - 앱이 비활성일 때 설정 창은 일반 레벨(설정 창이 다른 앱 위에 남지 않게).
// - 시스템 권한 안내(TCC·시스템 설정 딥링크) 중에는 대화 창도 내린다 — 안내가 뒤로 숨으면 안 된다.

public enum WindowLevelPolicy {
  /// 창에 적용할 레벨 종류. AppKit 변환은 앱이 한다.
  public enum Kind: Equatable {
    case normal
    /// 다른 앱 위 — 대화 창(📌 켜짐)
    case floating
    /// floating 바로 위 — 설정·정보 창이 핀 켜진 대화 창에 가리지 않게
    case floatingAbove
  }

  /// 대화 창 레벨.
  /// - Parameters:
  ///   - wantTop: 헤더 📌 / 설정 "대화 창을 항상 위에"
  ///   - systemPrompt: 시스템 권한 안내(또는 시스템 설정 딥링크) 진행 중
  public static func panel(wantTop: Bool, systemPrompt: Bool) -> Kind {
    (wantTop && !systemPrompt) ? .floating : .normal
  }

  /// 설정·정보 창 레벨 — **대화 창이 floating 일 때만** 그 위에 둔다.
  /// - Parameters:
  ///   - inUse: 그 창(또는 그 시트)이 지금 키 창인지 — 쓰고 있는 창만 위로 올린다.
  ///   - appActive: 비활성이면 일반 레벨(다른 앱을 가리지 않게).
  public static func aux(wantTop: Bool, systemPrompt: Bool, appActive: Bool, inUse: Bool) -> Kind {
    (wantTop && !systemPrompt && appActive && inUse) ? .floatingAbove : .normal
  }
}
