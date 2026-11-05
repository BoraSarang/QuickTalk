import Foundation

/// 비서가 쓸 수 있는 도구 묶음 (v0.26).
///
/// 이 값은 **모델에게 보여 줄 도구 목록**만 정한다. 실제 실행 권한은 기존
/// `PolicyEngine`·승인 카드가 따로 판정한다 — 도구를 켰다고 승인 없이 실행되지 않고,
/// 껐다고 권한 판정이 느슨해지지도 않는다(이중 게이트).
public struct PersonaTools: Codable, Equatable, Hashable {
  /// 파일·폴더·프로세스·화면 읽기 (`read_file`, `list_dir`, `processes`, `screenshot`)
  public var read: Bool
  /// 웹 검색 (`web_search`)
  public var web: Bool
  /// 셸 명령 (`shell`) — 실행할 때마다 승인 카드가 뜬다
  public var shell: Bool
  /// 파일 쓰기 — 도구 이름은 없고, 리포트 저장 여부를 정한다
  public var write: Bool
  /// 다른 앱 조작 (`ui_snapshot`, `ui_action`)
  public var ui: Bool

  public init(read: Bool = true, web: Bool = true, shell: Bool = false,
              write: Bool = true, ui: Bool = false) {
    self.read = read
    self.web = web
    self.shell = shell
    self.write = write
    self.ui = ui
  }

  /// 읽기 전용 비서 — 조사·요약만 하고 파일은 만들지 않는다.
  public static let readOnly = PersonaTools(read: true, web: true, shell: false, write: false, ui: false)

  /// 모든 도구 — 사용자가 명시적으로 고를 때만 쓴다.
  public static let all = PersonaTools(read: true, web: true, shell: true, write: true, ui: true)

  /// 실제 도구 카탈로그 이름. `PersonaTools` 를 도구 이름으로 옮기는 **유일한 지점**.
  public var toolNames: [String] {
    var names: [String] = []
    if read { names += ["read_file", "list_dir", "processes", "screenshot"] }
    if web { names += ["web_search", "web_fetch"] }
    if shell { names.append("shell") }
    if ui { names += ["ui_snapshot", "ui_action"] }
    return names
  }

  /// 이 비서가 해당 도구를 쓸 수 있는가.
  public func allows(toolNamed name: String) -> Bool {
    toolNames.contains(name)
  }

  /// 켜진 묶음의 사람용 요약 — "웹 검색 · 파일 읽기" / "Web · Read files".
  public var summary: String {
    var parts: [String] = []
    if read { parts.append(L("파일 읽기")) }
    if web { parts.append(L("웹 검색")) }
    if shell { parts.append(L("셸")) }
    if write { parts.append(L("파일 쓰기")) }
    if ui { parts.append(L("앱 조작")) }
    return parts.isEmpty ? L("도구 없음") : parts.joined(separator: " · ")
  }
}

/// 성격·말투를 가진 비서 (v0.26).
///
/// **선택 사항**이다 — 비서가 없으면(`nil`) 앱은 지금과 완전히 동일하게 동작한다.
/// 사용자가 만든 값은 그대로 프롬프트에 들어가므로 길이 상한과 개행 제거를 거친다
/// (`normalized()`). 이 정규화는 "말투" 칸에 지시문을 끼워 넣는 경로를 막는다.
public struct Persona: Codable, Identifiable, Equatable, Hashable {
  public enum Limits {
    public static let name = 20
    public static let role = 200
    public static let tone = 200
  }

  /// 편집 시트에 나열하는 아이콘 프리셋 (v0.28).
  ///
  /// 빈 텍스트필드에 "심볼을 입력하라"는 인상을 주지 않도록 **고르는 목록**으로 보여 준다.
  /// 저장 형식은 그대로 `emoji` 한 글자다 — 기존 비서·기록과 호환된다.
  public static let iconChoices: [String] = [
    "🤖", "🦾", "🧠", "🦉", "🦊",
    "🐻", "🐼", "🐱", "🐶", "🐧",
    "🦁", "🐨", "🦄", "🐝", "🐬",
    "👩‍💻", "🧑‍🔬", "🕵️", "🔎", "📚"
  ]

  public var id: UUID
  public var name: String
  /// 담당 — "매일 아침 테크 소식을 정리하는 비서"
  public var role: String
  /// 말투 — "짧고 딱딱하게, 존댓말 없이"
  public var tone: String
  /// 카드·알림 아이콘(선택). 첫 글자만 쓴다.
  public var emoji: String?
  /// nil = 설정의 활성 프로바이더
  public var providerID: String?
  /// nil = 프로바이더의 모델. **예약 실행에만** 적용되는 모델 덮어쓰기(v0.27).
  public var model: String?
  public var tools: PersonaTools
  /// nil = 설정의 기본 리포트 폴더
  public var reportFolder: String?
  public var createdAt: Date

  public init(id: UUID = UUID(), name: String, role: String = "", tone: String = "",
              emoji: String? = nil, providerID: String? = nil, model: String? = nil,
              tools: PersonaTools = PersonaTools(), reportFolder: String? = nil,
              createdAt: Date = Date()) {
    self.id = id
    self.name = name
    self.role = role
    self.tone = tone
    self.emoji = emoji
    self.providerID = providerID
    self.model = model
    self.tools = tools
    self.reportFolder = reportFolder
    self.createdAt = createdAt
  }

  /// 비서 이름이 비었을 때 쓰는 표시 이름.
  public static var fallbackName: String { L("비서") }

  /// 저장·프롬프트 주입 직전에 부르는 정규화.
  ///
  /// - 이름·역할·말투의 **개행을 공백으로** 바꾼다(프롬프트에 별도 지시 줄을 끼워 넣지 못하게).
  /// - 길이 상한을 **글자 수**로 자른다(이모지·한글 합자 안전).
  /// - 빈 이름은 `fallbackName`, 빈 폴더·프로바이더는 `nil`.
  public func normalized() -> Persona {
    var p = self
    p.name = Self.clean(name, limit: Limits.name, fallback: Self.fallbackName)
    p.role = Self.clean(role, limit: Limits.role)
    p.tone = Self.clean(tone, limit: Limits.tone)
    p.emoji = Self.firstSymbol(emoji)
    p.providerID = Self.optional(providerID)
    p.model = Self.optional(model)
    p.reportFolder = Self.optional(reportFolder)
    return p
  }

  /// 정규화된 값이 유효한가 — 이름만 있으면 된다.
  public var isValid: Bool { !normalized().name.isEmpty }

  /// 카드·알림에 쓰는 짧은 설명 — "리포트 · 차분한 존댓말" (역할이 비면 말투만).
  public var subtitle: String {
    let p = normalized()
    let parts = [p.role, p.tone].filter { !$0.isEmpty }
    return parts.isEmpty ? L("비서") : parts.joined(separator: " · ")
  }

  /// 화면에 보여 줄 아이콘 — 사용자가 비워 두었으면 **ID 기반으로 서로 다른 기본 아이콘**을 준다.
  /// (예전에는 모두 🗣로 보여 어떤 비서를 골랐는지 구분되지 않았다)
  public var displayEmoji: String {
    if let emoji = normalized().emoji, !emoji.isEmpty { return emoji }
    let palette = Self.iconChoices
    guard !palette.isEmpty else { return "🤖" }
    let bytes = id.uuid
    let sum = [bytes.0, bytes.1, bytes.2, bytes.3, bytes.4, bytes.5,
               bytes.6, bytes.7, bytes.8, bytes.9, bytes.10, bytes.11,
               bytes.12, bytes.13, bytes.14, bytes.15].reduce(0) { $0 + Int($1) }
    return palette[sum % palette.count]
  }

  // MARK: - 문자열 정리

  private static func clean(_ raw: String, limit: Int, fallback: String = "") -> String {
    let collapsed = raw
      .components(separatedBy: .whitespacesAndNewlines)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    guard !collapsed.isEmpty else { return fallback }
    return String(collapsed.prefix(limit))
  }

  private static func optional(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func firstSymbol(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let first = trimmed.first else { return nil }
    // 이모지 하나가 여러 유니코드 스칼라로 이뤄질 수 있으므로 Character 단위로 자른다.
    return String(first)
  }
}

/// 비서 정체성을 기존 지시문 **앞**에 붙인다.
///
/// 원칙: 전역 안전 규칙(`AgentInstructions.text`)은 **한 글자도 지우지 않는다**.
/// 비서 값은 스타일만 정하며, 권한·도구 규칙은 아래 전역 규칙이 우선한다는 문장을 함께 넣는다.
public enum PersonaPrompt {
  /// `persona` 가 nil 이면 `base` 를 **그대로** 돌려준다(기존 프롬프트와 완전 동일).
  public static func compose(_ persona: Persona?, base: String) -> String {
    guard let persona else { return base }
    let p = persona.normalized()
    guard p.isValid else { return base }
    return header(p) + "\n\n" + base
  }

  /// 정체성 헤더만 — 테스트·디버그에서 확인한다.
  public static func header(_ persona: Persona) -> String {
    let p = persona.normalized()
    var lines = [
      "[비서]",
      Lf("이름: %@", p.name)
    ]
    if !p.role.isEmpty { lines.append(Lf("역할: %@", p.role)) }
    if !p.tone.isEmpty { lines.append(Lf("말투: %@", p.tone)) }
    lines.append(L("위 이름·역할·말투는 답변의 스타일만 정한다. 권한·도구·안전 규칙은 아래 지시문을 그대로 따른다."))
    return lines.joined(separator: "\n")
  }
}
