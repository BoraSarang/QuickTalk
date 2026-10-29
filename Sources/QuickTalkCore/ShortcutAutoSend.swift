import Foundation

// [FEATURE] Shortcuts/AppIntent 자동 전송 — 옵트인 (2026-10-29)
//
// 지금까지 Shortcuts는 입력창에 질문을 **채우기만** 했다(자동 전송 없음).
// 사용자가 명시적으로 켠 경우에만, '질문하고 보내기' 동작이 확인 없이 전송한다.
// 기본값은 꺼짐 — 사용자가 보지 않은 질문이 도구 권한 게이트를 통과하면 안 되기 때문이다.

public enum ShortcutAutoSend {
  /// '보내기'를 요청한 동작이 실제로 전송할지. 설정이 꺼져 있으면 초안만 채운다.
  public static func shouldSend(requested: Bool, enabled: Bool) -> Bool {
    requested && enabled
  }
}
