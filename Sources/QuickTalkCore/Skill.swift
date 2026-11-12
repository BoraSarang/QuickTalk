import Foundation

// [FEATURE] 스킬 (PLAN_v0.37 §5·§7)
//
// 스킬은 **절차 문서**다. `SKILL.md`(frontmatter + 본문) + 선택 `scripts/` 폴더.
// OpenCode/Claude 계열과 같은 모양이라 사용자가 가진 폴더를 그대로 가져올 수 있다.
//
// 원칙: 스킬은 **권한을 넓히지 않는다**. `tools:` 는 좁히기만 하고, 실제 실행은
// 기존 `AgentExecutor`·샌드박스·승인 카드가 그대로 판정한다.

/// 스킬이 요구하는 최소 권한 수준 — UI 배지와 정렬에 쓴다.
public enum SkillRisk: String, Codable, Equatable {
  case read
  case write

  public var displayName: String {
    switch self {
    case .read: return L("읽기")
    case .write: return L("쓰기")
    }
  }
}

/// 로드된 스킬 하나.
public struct Skill: Identifiable, Equatable {
  public enum Source: String, Codable, Equatable {
    case bundled
    case user

    public var displayName: String {
      switch self {
      case .bundled: return L("기본")
      case .user: return L("사용자")
      }
    }
  }

  /// 폴더 이름이자 모델이 `read_skill` 에 넘기는 값 — `^[a-z0-9][a-z0-9-]{0,39}$`.
  public let id: String
  /// 표시 이름 (frontmatter `name`).
  public let name: String
  public let description: String
  /// 언제 쓰는지 한 줄 (frontmatter `when`).
  public let when: String
  /// 이 스킬이 쓸 도구 이름. 빈 배열 = 제한 없음(지금 대화의 도구 안에서).
  public let tools: [String]
  public let version: Int
  public let risk: SkillRisk
  public let source: Source
  /// 스킬 폴더의 절대 경로.
  public let directory: URL
  /// `SKILL.md` 본문(frontmatter 제외).
  public let body: String
  /// `scripts/` 안의 상대 경로 — 최대 20개.
  public let scripts: [String]

  public init(id: String, name: String, description: String, when: String = "",
              tools: [String] = [], version: Int = 1, risk: SkillRisk,
              source: Skill.Source, directory: URL, body: String, scripts: [String] = []) {
    self.id = id
    self.name = name
    self.description = description
    self.when = when
    self.tools = tools
    self.version = version
    self.risk = risk
    self.source = source
    self.directory = directory
    self.body = body
    self.scripts = scripts
  }
}

/// 무시된 스킬 한 건 — 설정 화면에 사유를 보여 준다(조용히 넘기지 않는다).
public struct SkillWarning: Equatable, Error {
  /// 무효인 폴더 이름(모를 때는 빈 문자열).
  public let id: String
  public let reason: String

  public init(id: String, reason: String) {
    self.id = id
    self.reason = reason
  }
}

public struct SkillLoadResult: Equatable {
  public let skills: [Skill]
  public let warnings: [SkillWarning]

  public init(skills: [Skill], warnings: [SkillWarning] = []) {
    self.skills = skills
    self.warnings = warnings
  }
}

/// 스킬 폴더 위치.
public enum SkillLocations {
  /// 앱 번들 — `QuickTalk.app/Contents/Resources/Skills` (읽기 전용).
  public static func bundledRoot(bundle: Bundle = .main) -> URL? {
    bundle.resourceURL?.appendingPathComponent("Skills", isDirectory: true)
  }

  /// 사용자 스킬 — `~/Library/Application Support/QuickTalk/Skills`.
  public static func userRoot(home: String = NSHomeDirectory()) -> URL {
    URL(fileURLWithPath: home)
      .appendingPathComponent("Library/Application Support/QuickTalk/Skills", isDirectory: true)
  }

  /// 셸 명령 문자열이 가리키는 스킬 id — 실행 카드에 `스킬: …` 을 붙이기 위한 **최선 노력**.
  ///
  /// 경로가 명령에 **그대로 드러난 경우만** 알아본다. 변수·난독화로 숨긴 경로는 잡지 못한다
  /// (카드 표시용이며 권한 판정과는 무관하다).
  public static func skillID(referencedIn command: String) -> String? {
    let markers = [
      "/Library/Application Support/QuickTalk/Skills/",
      "/Contents/Resources/Skills/",
    ]
    for marker in markers {
      guard let range = command.range(of: marker) else { continue }
      let rest = command[range.upperBound...]
      let id = String(rest.prefix { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-") })
      if SkillMarkdown.isValidID(id) { return id }
    }
    return nil
  }
}

// MARK: - SKILL.md 파서

/// `SKILL.md` 한 파일을 읽는 **유일한 지점**.
///
/// YAML 라이브러리를 쓰지 않는다 — 필요한 문법은 `key: value` 와 `key: [a, b]` 뿐이다.
/// 모르는 키는 무시하고, 앞으로 형식이 늘어나도 기존 스킬이 깨지지 않게 한다.
public enum SkillMarkdown {
  public static let maxFileBytes = 64_000
  public static let maxFrontmatterBytes = 8_000
  public static let maxNameLength = 60
  public static let maxDescriptionLength = 200
  public static let maxWhenLength = 200
  public static let maxScripts = 20
  public static let maxScriptBytes = 1_000_000

  /// 폴더 이름이 스킬 id 로 쓸 수 있는가.
  public static func isValidID(_ id: String) -> Bool {
    guard (1...40).contains(id.count) else { return false }
    guard let first = id.first, first.isASCII, first.isLowercase || first.isNumber else { return false }
    return id.allSatisfy { ch in
      ch == "-" || (ch.isASCII && (ch.isLowercase || ch.isNumber))
    }
  }

  /// `SKILL.md` 문자열을 `Skill` 로 바꾼다.
  public static func parse(markdown: String, directory: URL,
                           source: Skill.Source) -> Result<Skill, SkillWarning> {
    let id = directory.lastPathComponent
    func invalid(_ reason: String) -> Result<Skill, SkillWarning> {
      .failure(SkillWarning(id: id, reason: reason))
    }

    guard markdown.utf8.count <= maxFileBytes else {
      return invalid(Lf("SKILL.md 가 %dKB 를 넘습니다.", maxFileBytes / 1000))
    }
    guard isValidID(id) else {
      return invalid(L("폴더 이름은 소문자·숫자·하이픈 1~40자여야 합니다."))
    }

    // CRLF 를 LF 로 맞춘 뒤 줄 단위로 본다.
    let normalized = markdown
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)

    guard let first = lines.first,
          first.trimmingCharacters(in: .whitespaces) == "---" else {
      return invalid(L("첫 줄이 --- 인 frontmatter 가 없습니다."))
    }
    guard let close = lines.indices.dropFirst().first(where: {
      lines[$0].trimmingCharacters(in: .whitespaces) == "---"
    }) else {
      return invalid(L("frontmatter 의 닫는 --- 가 없습니다."))
    }

    let frontmatter = lines[1..<close].joined(separator: "\n")
    guard frontmatter.utf8.count <= maxFrontmatterBytes else {
      return invalid(Lf("frontmatter 가 %dKB 를 넘습니다.", maxFrontmatterBytes / 1000))
    }

    var values: [String: String] = [:]
    for line in lines[1..<close] {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
      guard let colon = trimmed.firstIndex(of: ":") else { continue }
      let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      var value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
      if value.count >= 2, let f = value.first, let l = value.last, f == l, f == "\"" || f == "'" {
        value = String(value.dropFirst().dropLast())
      }
      values[key] = value
    }

    guard let rawName = values["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawName.isEmpty else {
      return invalid(L("name 이 없습니다."))
    }
    guard let rawDescription = values["description"]?.trimmingCharacters(in: .whitespacesAndNewlines),
          !rawDescription.isEmpty else {
      return invalid(L("description 이 없습니다."))
    }

    let name = String(rawName.prefix(maxNameLength))
    let description = String(rawDescription.prefix(maxDescriptionLength))
    let when = String((values["when"] ?? "").prefix(maxWhenLength))
    let tools = list(values["tools"] ?? "")
    let version = Int(values["version"] ?? "") ?? 1

    let risk: SkillRisk
    switch (values["risk"] ?? "").lowercased() {
    case "read": risk = .read
    case "write": risk = .write
    default:
      // 명시가 없으면 도구에서 추론한다 — 셸은 쓰기 가능성이 있다.
      risk = tools.contains("shell") ? .write : .read
    }

    // 본문 — 앞뒤의 **빈 줄만** 정리하고 내용은 변형하지 않는다.
    var bodyLines = Array(lines[(close + 1)...])
    while let f = bodyLines.first, f.trimmingCharacters(in: .whitespaces).isEmpty {
      bodyLines.removeFirst()
    }
    while let l = bodyLines.last, l.trimmingCharacters(in: .whitespaces).isEmpty {
      bodyLines.removeLast()
    }

    let scripts = scriptFiles(in: directory)

    return .success(Skill(id: id, name: name, description: description, when: when,
                          tools: tools, version: version, risk: risk, source: source,
                          directory: directory, body: bodyLines.joined(separator: "\n"),
                          scripts: scripts))
  }

  /// `[a, b]` 인라인 목록. 대괄호가 없어도 쉼표로 나눈다(관대한 입력).
  static func list(_ raw: String) -> [String] {
    var text = raw.trimmingCharacters(in: .whitespaces)
    if text.hasPrefix("["), text.hasSuffix("]") {
      text = String(text.dropFirst().dropLast())
    }
    var seen = Set<String>()
    return text.split(separator: ",").compactMap { part in
      var value = part.trimmingCharacters(in: .whitespaces).lowercased()
      if value.count >= 2, let f = value.first, let l = value.last, f == l, f == "\"" || f == "'" {
        value = String(value.dropFirst().dropLast())
      }
      guard !value.isEmpty, seen.insert(value).inserted else { return nil }
      return value
    }
  }

  /// `scripts/` 안의 일반 파일 — 이름순, 최대 20개, 1MB 이하만.
  static func scriptFiles(in directory: URL) -> [String] {
    let root = directory.appendingPathComponent("scripts", isDirectory: true)
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: root, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
      options: [.skipsHiddenFiles]) else { return [] }
    let files = entries.compactMap { url -> (String, Int)? in
      guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
            values.isRegularFile == true else { return nil }
      let size = values.fileSize ?? 0
      guard size <= maxScriptBytes else { return nil }
      return ("scripts/" + url.lastPathComponent, size)
    }
    return files.sorted { $0.0 < $1.0 }.prefix(maxScripts).map(\.0)
  }

  /// 심볼릭 링크까지 해석한 실제 경로.
  public static func realPath(_ url: URL) -> String? {
    var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
    guard realpath(url.path, &buffer) != nil else { return nil }
    return String(cString: buffer)
  }

  /// `path` 가 `root` 안에 있는가(경계 검사 — `…/Skills2` 는 다른 폴더).
  public static func isContained(_ path: String, inRoot root: String) -> Bool {
    path == root || path.hasPrefix(root.hasSuffix("/") ? root : root + "/")
  }
}

// MARK: - 레지스트리

/// 번들·사용자 폴더를 스캔해 스킬 목록을 만든다.
///
/// - 같은 id 는 **사용자 것이 이긴다**(번들 파일은 지우지 않는다).
/// - 무효·경로 탈출 스킬은 건너뛰고 `warnings` 에 사유를 남긴다.
public enum SkillRegistry {
  public static let maxSkills = 200

  public static func load(bundledRoot: URL?, userRoot: URL?) -> SkillLoadResult {
    var byID: [String: Skill] = [:]
    var warnings: [SkillWarning] = []

    func scan(_ root: URL?, source: Skill.Source) {
      guard let root else { return }
      guard let rootReal = SkillMarkdown.realPath(root) else { return }
      guard let entries = try? FileManager.default.contentsOfDirectory(
        at: URL(fileURLWithPath: rootReal),
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]) else { return }

      for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let id = entry.lastPathComponent
        let skillFile = entry.appendingPathComponent("SKILL.md")
        // SKILL.md 가 없는 폴더는 스킬이 아니다 — 조용히 건너뛴다(경고 아님).
        guard FileManager.default.fileExists(atPath: skillFile.path) else { continue }
        guard SkillMarkdown.isValidID(id) else {
          warnings.append(SkillWarning(id: id,
            reason: L("폴더 이름은 소문자·숫자·하이픈 1~40자여야 합니다.")))
          continue
        }
        // 폴더와 SKILL.md 모두 **루트 안의 실제 경로**여야 한다(심볼릭 링크 탈출 차단).
        guard let dirReal = SkillMarkdown.realPath(entry),
              SkillMarkdown.isContained(dirReal, inRoot: rootReal),
              let fileReal = SkillMarkdown.realPath(skillFile),
              SkillMarkdown.isContained(fileReal, inRoot: rootReal) else {
          warnings.append(SkillWarning(id: id,
            reason: L("스킬 폴더가 스킬 폴더 밖을 가리킵니다.")))
          continue
        }
        guard let data = FileManager.default.contents(atPath: fileReal) else {
          warnings.append(SkillWarning(id: id, reason: L("SKILL.md 를 읽지 못했습니다.")))
          continue
        }
        guard data.count <= SkillMarkdown.maxFileBytes else {
          warnings.append(SkillWarning(id: id,
            reason: Lf("SKILL.md 가 %dKB 를 넘습니다.", SkillMarkdown.maxFileBytes / 1000)))
          continue
        }
        guard let text = String(data: data, encoding: .utf8) else {
          warnings.append(SkillWarning(id: id, reason: L("SKILL.md 가 UTF-8 이 아닙니다.")))
          continue
        }
        switch SkillMarkdown.parse(markdown: text,
                                   directory: URL(fileURLWithPath: dirReal),
                                   source: source) {
        case .success(let skill):
          byID[id] = skill        // 번들 → 사용자 순서라 사용자가 덮어쓴다
        case .failure(let warning):
          warnings.append(warning)
        }
      }
    }

    scan(bundledRoot, source: .bundled)
    scan(userRoot, source: .user)

    var skills = Array(byID.values)
    skills.sort {
      let byName = $0.name.localizedCaseInsensitiveCompare($1.name)
      return byName == .orderedSame ? $0.id < $1.id : byName == .orderedAscending
    }
    if skills.count > maxSkills {
      skills = Array(skills.prefix(maxSkills))
      warnings.append(SkillWarning(id: "",
        reason: Lf("스킬이 %d개를 넘어 앞의 %d개만 불러왔습니다.", maxSkills, maxSkills)))
    }
    return SkillLoadResult(skills: skills, warnings: warnings)
  }
}
