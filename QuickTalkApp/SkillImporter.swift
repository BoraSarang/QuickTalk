import AppKit

// [FEATURE] 스킬 가져오기 (PLAN_v0.37 §6.2)
//
// 폴더를 고르면 **임시 폴더에 먼저 복사하고 검증한 뒤** 사용자 스킬 폴더로 옮긴다.
// 중간에 실패해도 반쪽짜리 스킬이 남지 않게 하기 위해서다.
// 자동 실행·자동 업데이트는 없다 — 사용자가 명시적으로 가져오고 삭제한다.

enum SkillImportError: LocalizedError {
  case noSkillFile
  case invalidID
  case invalidSkill(String)
  case symlinkOutside
  case tooLarge
  case unreadable

  var errorDescription: String? {
    switch self {
    case .noSkillFile:
      return L("SKILL.md 가 있는 폴더만 가져올 수 있습니다.")
    case .invalidID:
      return L("폴더 이름은 소문자·숫자·하이픈 1~40자여야 합니다.")
    case .invalidSkill(let reason):
      return reason
    case .symlinkOutside:
      return L("스킬 폴더 밖을 가리키는 심볼릭 링크가 있습니다.")
    case .tooLarge:
      return L("스킬 폴더가 5MB 를 넘습니다.")
    case .unreadable:
      return L("SKILL.md 를 읽지 못했습니다.")
    }
  }
}

enum SkillImporter {
  static let maxTotalBytes = 5 * 1024 * 1024

  /// 검증을 마치고 임시 폴더에 복사된 상태.
  struct Prepared: Identifiable {
    let id: String
    let name: String
    /// 임시 루트 — 그 아래 `<id>/` 가 실제 스킬 폴더다.
    let stagingRoot: URL

    var itemURL: URL { stagingRoot.appendingPathComponent(id, isDirectory: true) }

    /// 교체를 취소했을 때 임시 파일을 지운다.
    func discard() {
      try? FileManager.default.removeItem(at: stagingRoot)
    }
  }

  static var userRoot: URL { SkillLocations.userRoot() }

  static func userSkillExists(id: String) -> Bool {
    FileManager.default.fileExists(
      atPath: userRoot.appendingPathComponent(id, isDirectory: true).path)
  }

  /// 폴더 선택 → 검증 → 임시 복사. 취소하면 nil.
  static func chooseAndPrepare() throws -> Prepared? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.prompt = L("가져오기")
    guard panel.runModal() == .OK, let source = panel.url else { return nil }

    let id = source.lastPathComponent
    guard SkillMarkdown.isValidID(id) else { throw SkillImportError.invalidID }
    let skillFile = source.appendingPathComponent("SKILL.md")
    guard FileManager.default.fileExists(atPath: skillFile.path) else {
      throw SkillImportError.noSkillFile
    }
    try validate(source)

    guard let data = try? Data(contentsOf: skillFile) else {
      throw SkillImportError.unreadable
    }
    guard data.count <= SkillMarkdown.maxFileBytes else {
      throw SkillImportError.invalidSkill(
        Lf("SKILL.md 가 %dKB 를 넘습니다.", SkillMarkdown.maxFileBytes / 1000))
    }
    guard let text = String(data: data, encoding: .utf8) else {
      throw SkillImportError.invalidSkill(L("SKILL.md 가 UTF-8 이 아닙니다."))
    }
    let skill: Skill
    switch SkillMarkdown.parse(markdown: text, directory: source, source: .user) {
    case .success(let parsed): skill = parsed
    case .failure(let warning): throw SkillImportError.invalidSkill(warning.reason)
    }

    let staging = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuickTalk/skill-import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
    do {
      try FileManager.default.copyItem(at: source, to: staging.appendingPathComponent(id,
                                                                                     isDirectory: true))
    } catch {
      try? FileManager.default.removeItem(at: staging)
      throw SkillImportError.unreadable
    }
    return Prepared(id: id, name: skill.name, stagingRoot: staging)
  }

  /// 검증된 임시 폴더를 사용자 스킬 폴더로 옮긴다. 같은 id 가 있으면 교체한다.
  static func install(_ prepared: Prepared) throws {
    let root = userRoot
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let destination = root.appendingPathComponent(prepared.id, isDirectory: true)
    // 같은 볼륨의 숨김 폴더로 먼저 옮긴다 — 교체 도중 실패해도 반쪽 폴더가 남지 않는다.
    let staged = root.appendingPathComponent(".import-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.moveItem(at: prepared.itemURL, to: staged)
    defer {
      prepared.discard()
      try? FileManager.default.removeItem(at: staged)
    }
    guard FileManager.default.fileExists(atPath: destination.path) else {
      try FileManager.default.moveItem(at: staged, to: destination)
      return
    }
    // 기존 폴더를 백업으로 옮긴 뒤 새 폴더를 넣는다. 실패하면 **원래 폴더를 되돌린다**
    // (예전 `replaceItemAt` 폴백은 실패 시 기존 스킬을 잃을 수 있었다).
    let backup = root.appendingPathComponent(".replaced-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.moveItem(at: destination, to: backup)
    do {
      try FileManager.default.moveItem(at: staged, to: destination)
      try? FileManager.default.removeItem(at: backup)
    } catch {
      try? FileManager.default.moveItem(at: backup, to: destination)
      throw error
    }
  }

  /// 사용자 스킬만 삭제한다. 번들 스킬은 앱 리소스라 지우지 않는다.
  static func remove(id: String) throws {
    guard SkillMarkdown.isValidID(id) else { throw SkillImportError.invalidID }
    let target = userRoot.appendingPathComponent(id, isDirectory: true)
    guard FileManager.default.fileExists(atPath: target.path) else { return }
    try FileManager.default.removeItem(at: target)
  }

  static func reveal(id: String) {
    let target = userRoot.appendingPathComponent(id, isDirectory: true)
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  // MARK: - 내부

  /// 폴더 밖을 가리키는 심볼릭 링크와 5MB 초과를 막는다.
  private static func validate(_ source: URL) throws {
    guard let rootReal = SkillMarkdown.realPath(source) else {
      throw SkillImportError.unreadable
    }
    let keys: [URLResourceKey] = [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
    guard let enumerator = FileManager.default.enumerator(
      at: source, includingPropertiesForKeys: keys) else {
      throw SkillImportError.unreadable
    }
    var total = 0
    for case let url as URL in enumerator {
      let values = try url.resourceValues(forKeys: Set(keys))
      if values.isSymbolicLink == true {
        guard let target = SkillMarkdown.realPath(url),
              SkillMarkdown.isContained(target, inRoot: rootReal) else {
          throw SkillImportError.symlinkOutside
        }
      } else if values.isRegularFile == true {
        total += values.fileSize ?? 0
        if total > maxTotalBytes { throw SkillImportError.tooLarge }
      }
    }
  }
}
