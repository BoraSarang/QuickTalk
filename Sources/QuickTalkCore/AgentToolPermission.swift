import Foundation

/// 도구별 권한 단계 — **설정의 단계별 정책**(읽기·쓰기·실행)이 도구에도 똑같이 적용되게 한다.
///
/// 배경(2026-10-27): `screenshot` 은 실행 단계에서 권한을 **직접** 판정하지 않아,
/// "읽기: 매번 확인" 으로 설정해도 화면 캡처가 무조건 실행됐다. 정책과 도구가 따로 놀면
/// 사용자가 켜 둔 안전장치가 조용히 무시된다.
public enum AgentToolPermission {
  /// 도구가 요구하는 권한 단계.
  ///
  /// - `screenshot` 은 **읽기**다 — 화면 내용을 읽어 올 뿐 클릭·입력은 하지 않는다.
  ///   다만 "읽기: 매번 확인" 이면 다른 읽기 도구와 똑같이 확인을 받는다(화면은 민감하다).
  /// - `ui_snapshot` 은 **읽기**다 — 화면의 요소를 읽어 올 뿐 클릭·입력은 하지 않는다(PLAN_v0.25).
  /// - `shell` 은 **실행** 단계다. 실제로 필요한 권한은 샌드박스 실측이 좁힌다.
  public static func level(for tool: String) -> AgentPermissionLevel {
    switch tool {
    case "read_file", "list_dir", "processes", "screenshot", "ui_snapshot": return .read
    case "shell": return .execute
    // 정의되지 않은 도구는 **가장 좁은(가장 묻는)** 단계로 본다 — 모르면 묻는다.
    default: return .execute
    }
  }

  /// 이 도구를 실행하기 전에 사용자 확인이 필요한가 — 설정의 단계별 정책을 그대로 따른다.
  public static func needsApproval(tool: String, policy: AgentPolicy) -> Bool {
    policy.autoApprove(for: level(for: tool)) == .alwaysAsk
  }
}
