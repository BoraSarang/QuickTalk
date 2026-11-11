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
  /// - `persona`: 지금 대화의 비서(없으면 nil). 있으면 **그 비서의 리포트 폴더·쓰기 권한**을 알려 준다.
  public static func text(settings: QuickTalkSettings, persona: Persona? = nil) -> String {
    let home = NSHomeDirectory()
    var lines: [String] = []
    lines.append("이것은 QuickTalk 이라는 macOS 메뉴바 앱이다. 사용자가 지금 이 앱으로 묻고 있다.")
    lines.append("- 저장 위치: \(home)/Library/Application Support/QuickTalk")
    lines.append("  · 대화 기록: history.json · 공통 메모리: memory.json · 설정: settings.json")
    lines.append("  · 실행 감사 기록: agent-audit.jsonl · 되돌리기 스냅샷: undo/ · 휴지통: trash/")

    // 리포트 폴더 — 앱이 실제로 쓰기를 허용하는 **한 곳**을 경로로 알려 준다.
    // (예전에는 이 줄이 없어 모델이 읽기 전용 폴더를 추측하고 "쓰기가 막혔다"고 답했다)
    lines.append(reportFolderText(settings: settings, persona: persona))

    // 지금 대화의 비서
    if let persona, persona.isValid {
      lines.append("- 지금 대화의 비서: \(persona.normalized().name)")
    }

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
      lines.append("  · 컴퓨터 제어: 켜짐 — 다른 앱의 화면 요소를 읽고(ui_snapshot) 승인된 앱을 클릭·입력(ui_action)할 수 있다(손쉬운 사용 권한 필요)")
    } else {
      lines.append("  · 컴퓨터 제어: 꺼짐 — 화면 요소 읽기·조작 도구(ui_snapshot, ui_action)를 쓸 수 없다")
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

  /// 모델이 **실제로 쓸 수 있는** 작업 폴더를 알려 주는 블록.
  /// v0.35부터 비서 폴더를 지정하지 않아도 **비서별 하위 폴더**를 쓴다(`PersonaReports`).
  public static func reportFolderText(settings: QuickTalkSettings,
                                      persona: Persona?) -> String {
    let p = persona?.normalized()
    // 비서 폴더에도 `~` 를 쓸 수 있다 — 모델에게는 **실제 경로**를 준다.
    let folder = PersonaReports.folder(settings: settings, persona: p)
    var lines = ["[작업 폴더]", "- 쓰기 가능한 경로: \(folder)"]
    if let p, !p.tools.write {
      lines.append("- 이 비서는 파일 쓰기가 꺼져 있다. 파일을 만들지 말고 답변으로만 전달한다.")
    } else {
      lines.append("- 파일은 이 폴더 안에만 만든다. 다른 경로를 추측하지 않는다.")
      if p != nil {
        lines.append("- 이 폴더가 이 비서의 폴더다. 다른 비서의 폴더를 추측하지 않는다.")
      }
      // v0.36.4 — 파일을 폴더 맨 위에 흩어 놓지 않는다. 만드는 파일과 같은 뜻의 폴더를 먼저 만든다.
      lines.append("- 파일을 만들 때는 **먼저 목적이 드러나는 하위 폴더를 만들고 그 안에 쓴다.**")
      lines.append("  · 폴더 이름은 만들 파일과 같은 뜻으로 짓는다. 예: `memtop/memtop.py`, `photo-organizer/sort-photos.py`")
      lines.append("  · 이름은 소문자·숫자·하이픈만 쓴다. `tmp`·`test`·`output`·`files`·`untitled` 처럼 뜻이 없는 이름은 쓰지 않는다.")
      lines.append("  · 한 작업에서 만든 파일은 같은 폴더에 모은다. 같은 목적의 폴더가 이미 있으면 새로 만들지 않고 그 폴더를 쓴다.")
      lines.append("  · 한 번 쓰고 마는 짧은 메모(`.md`)만 폴더 없이 맨 위에 둘 수 있다.")
      lines.append("- 사용자가 다른 위치를 요구하면 승인 카드를 거쳐 그 경로에 쓴다.")
      // v0.32.2 — 예약 실행용 폴더를 **일반 대화**에 그대로 노출하면 모델이
      // "표로 정리해 파일로 남길까요?"를 먼저 제안한다(2026-11-06 사용자 지적).
      lines.append("- 사용자가 파일·리포트 저장을 요청하기 전에는 먼저 저장을 제안하지 않는다.")
    }
    return lines.joined(separator: "\n")
  }

  /// 일반 대화 프롬프트 앞에 붙일 블록 — **비서가 있을 때만** 넣는다.
  /// 비서 없는 대화에 리포트 폴더를 알려 주면 모델이 스스로 리포트를 제안했다(v0.32.2).
  /// 도구 경로는 시스템 프롬프트(`SystemKnowledge.text`)가 같은 내용을 들고 있다.
  public static func reportFolderPrompt(settings: QuickTalkSettings,
                                        persona: Persona?) -> String {
    guard persona != nil else { return "" }
    return reportFolderText(settings: settings, persona: persona) + "\n\n"
  }
}
