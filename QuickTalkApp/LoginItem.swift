import AppKit
import Foundation
import ServiceManagement

/// 로그인 시 자동 실행 — **시스템 로그인 항목이 단일 출처**다.
///
/// 설정 JSON 에 따로 저장하지 않는 이유:
/// 사용자가 시스템 설정 › 일반 › 로그인 항목에서 직접 껐다 켜면 저장값과 화면이 어긋난다.
/// 화면은 항상 `SMAppService.mainApp.status` 를 읽는다(앱이 활성화될 때 다시 읽는다).
enum LoginItem {
  /// 지금 로그인 항목으로 등록되어 있는가
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  /// 등록은 됐지만 사용자가 **시스템 설정에서 허용**해야 실제로 켜지는 상태
  static var requiresApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

  /// 켜기/끄기. 실패하면 사람이 읽을 수 있는 이유를 돌려준다(설정 화면 캡션에 표시).
  @discardableResult
  static func setEnabled(_ enabled: Bool) -> String? {
    let service = SMAppService.mainApp
    do {
      if enabled {
        guard service.status != .enabled else { return nil }
        try service.register()
      } else {
        guard service.status != .notRegistered else { return nil }
        try service.unregister()
      }
      NSLog("[QuickTalk] 로그인 항목 %@ — status=%d",
            enabled ? "등록" : "해제", service.status.rawValue)
      return nil
    } catch {
      NSLog("[QuickTalk] 로그인 항목 %@ 실패 — %@",
            enabled ? "등록" : "해제", error.localizedDescription)
      return error.localizedDescription
    }
  }

  /// 시스템 설정 › 일반 › 로그인 항목 열기(승인이 필요할 때 안내 버튼)
  static func openSettings() {
    let candidates = [
      "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
      "x-apple.systempreferences:com.apple.preferences.users?LoginItems"
    ]
    for value in candidates {
      if let url = URL(string: value), NSWorkspace.shared.open(url) { return }
    }
  }
}
