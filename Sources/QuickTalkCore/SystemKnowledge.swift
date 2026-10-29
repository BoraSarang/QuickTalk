import Foundation

// [FEATURE] 앱 자신에 대한 지식 — 모델에게 **실제 설정값**을 주입한다 (v0.22)
//
// v0.18의 `selfKnowledge` 는 고정 문구였다. 그래서 모델이 "웹 검색이 켜져 있는지",
// "지금 권한 정책이 무엇인지", "창 연결이 켜져 있는지"를 몰라 엉뚱한 안내를 했다.
// 여기서는 설정에서 읽은 **사실만** 한 줄씩 적는다(비밀·키·토큰은 절대 넣지 않는다).
//
// 원칙
//   · 값이 없으면 그 줄을 쓰지 않는다(빈 값으로 모델을 헷갈리게 하지 않는다).
//   · API 키·시크릿 ID·파일 본문은 넣지 않는다 — 이름과 켜짐/꺼짐만.
//   · 앱이 이미 하는 일은 "다시 만들지 말고 설정 경로를 안내"하라고 분명히 말한다.

public enum SystemKnowledge {
  /// 모델에게 주는 앱 지식 블록.
  public static func text(settings: QuickTalkSettings) -> String {
    let home = NSHomeDirectory()
    var lines: [String] = []
    lines.append("이것은 QuickTalk 이라는 macOS 메뉴바 앱이다. 사용자가 지금 이 앱으로 묻고 있다.")
    lines.append("- 저장 위치: \(home)/Library/Application Support/QuickTalk")
    lines.append("  · 대화 기록: history.json · 공통 메모리: memory.json · 설정: settings.json")
    lines.append("  · 실행 감사 기록: agent-audit.jsonl · 되돌리기 스냅샷: undo/ · 휴지통: trash/")

    // 지금 쓰는 AI
    if let p = settings.activeProvider {
      lines.append("- 지금 쓰는 AI: \(p.displayName) (모델 \(p.model.isEmpty ? "시스템 기본" : p.model))")
    } else {
      lines.append("- 지금 쓰는 AI: 없음 (설정 › AI에서 골라야 한다)")
    }

    // 도우미 도구 · 권한
    lines.append("- 도우미 도구: \(settings.agentToolsEnabled ? "켜짐" : "꺼짐")")
    if settings.agentToolsEnabled {
      let policy = settings.agentPolicy
      lines.append("  · 권한 정책 — 읽기: \(policy.readPolicy.displayName) · 쓰기: \(policy.writePolicy.displayName) · 실행: \(policy.executePolicy.displayName)")
      lines.append("  · 전역 자동 수락: \(policy.autoAcceptAll ? "켜짐(일반 명령은 확인 없이 실행)" : "꺼짐")")
      lines.append("  · 치명적 명령: \(policy.allowCritical ? "허용" : "차단") · 상승 권한(sudo): \(policy.allowElevated ? "허용" : "차단")")
      lines.append("  · 사용자가 직접 쓴 허용 규칙: \(policy.rules.count)개")
      lines.append("  · 실행 제한 시간: \(settings.agentTimeoutSeconds)초")
      lines.append("  · 시스템 전역 경로 쓰기는 앱이 실행하지 않고 터미널로 넘긴다.")
    }

    // 입력·첨부
    lines.append("- 창 연결(읽기 전용): \(settings.windowAttachmentEnabled ? "켜짐" : "꺼짐") — 창 하나의 글자·스크린샷을 이번 질문에 붙인다")
    lines.append("- 화면 캡처 도구(screenshot): 모델이 필요할 때 창/화면을 찍어 다음 판단에 쓴다(화면 기록 권한 필요)")
    if settings.uiControlEnabled {
      lines.append("  · 컴퓨터 제어: 켜짐 — 다른 앱의 화면 요소를 읽을 수 있다(ui_snapshot, 손쉬운 사용 권한 필요). 클릭·입력은 아직 지원하지 않는다")
    } else {
      lines.append("  · 컴퓨터 제어: 꺼짐 — 화면 요소를 읽는 도구(ui_snapshot)를 쓸 수 없다")
    }

    // 웹 검색
    switch settings.webSearchProvider {
    case .none:
      lines.append("- 웹 검색: 꺼짐 (설정 › 웹 검색에서 Exa를 켤 수 있다)")
    default:
      lines.append("- 웹 검색: \(settings.webSearchProvider.displayName) · 결과 \(settings.webSearchResultCount)개 · 신선도 \(settings.webSearchFreshness.displayName)")
    }

    // 기억
    lines.append("- 공통 메모리: \(settings.globalMemoryEnabled ? "켜짐" : "꺼짐") · 대화 요약 자동 정리: \(settings.autoCompact ? "켜짐" : "꺼짐")")

    // 음성
    lines.append("- 음성 입력: \(settings.voiceEngine.displayName) · 읽어주기: \(settings.ttsEngine.displayName)")

    // 단축키 (이름만, 실제 키 조합은 설정 화면과 같다)
    lines.append("- 전역 단축키: 대화 \(settings.globalShortcut) · 퀵셸프 \(settings.shelfShortcut)")

    // QuickShelf
    lines.append("- QuickShelf: 클립보드·파일·캡처 허브(\(settings.shelfShortcut))")

    lines.append("- 앱에 이미 있는 기능은 다시 설치하거나 만들지 말고, 설정 경로만 안내한다.")
    lines.append("- 설정 파일을 직접 고치지 말고 설정 화면을 안내한다.")
    return lines.joined(separator: "\n")
  }
}
