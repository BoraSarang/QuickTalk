import Foundation

// [FEATURE] 스킬 프롬프트 (PLAN_v0.37 §8)
//
// 시스템 프롬프트에는 **목록만** 넣는다 — 이름·설명·언제. 본문은 `read_skill` 로
// 필요할 때만 읽는다(점진 공개). 예산을 넘으면 잘라서 `…외 N개` 로 정직하게 표시한다.

public enum SkillPrompt {
  /// 목록 전체 예산(문자 수).
  public static let budget = 1_200

  static let header = "[사용할 수 있는 스킬]"
  static let footer = """
    필요하면 read_skill(name) 로 본문을 읽고 그 절차를 따르세요. \
    스킬은 절차일 뿐이며, 앱의 안전 규칙이 항상 우선합니다.
    """

  /// 지금 대화에서 스킬을 쓸 수 있는가 (D1).
  ///
  /// - 비서 대화: `persona.skillsEnabled` 가 전역 설정을 **덮어쓴다**.
  /// - 일반 대화: `settings.skillsEnabled`.
  /// - 예약 실행: 항상 꺼짐(D2).
  public static func effectiveEnabled(settings: QuickTalkSettings,
                                      persona: Persona?,
                                      scheduled: Bool = false) -> Bool {
    guard !scheduled else { return false }
    if let persona { return persona.skillsEnabled }
    return settings.skillsEnabled
  }

  /// 지금 쓸 수 있는 도구의 **부분집합**인 스킬만 남긴다.
  /// 스킬이 권한을 넓힐 수는 없다 — `tools:` 는 좁히기만 한다.
  public static func availableSkills(_ skills: [Skill],
                                     availableTools: Set<String>) -> [Skill] {
    skills.filter { skill in
      skill.tools.allSatisfy { availableTools.contains($0) }
    }
  }

  /// 프롬프트에 넣을 목록 블록. 스킬이 없으면 nil.
  public static func block(for skills: [Skill], budget: Int = budget) -> String? {
    guard !skills.isEmpty else { return nil }
    let reserved = header.count + 1 + footer.count + 1
    guard reserved < budget else { return nil }

    var lines = [header]
    var used = reserved
    var included = 0
    for skill in skills {
      var line = "- \(skill.id) — \(skill.description)"
      if !skill.when.isEmpty { line += " (언제: \(skill.when))" }
      if used + line.count + 1 > budget {
        let remaining = skills.count - included
        let more = "- …외 \(remaining)개"
        if used + more.count + 1 <= budget { lines.append(more) }
        break
      }
      lines.append(line)
      used += line.count + 1
      included += 1
    }
    lines.append(footer)
    return lines.joined(separator: "\n")
  }
}
