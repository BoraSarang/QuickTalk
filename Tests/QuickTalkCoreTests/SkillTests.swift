import XCTest
@testable import QuickTalkCore

/// v0.37 — `SKILL.md` 파서·레지스트리 (PLAN §5·§7·§13).
final class SkillTests: XCTestCase {
  private var root: URL!
  private var bundled: URL!
  private var user: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("SkillTests-\(UUID().uuidString)", isDirectory: true)
    bundled = root.appendingPathComponent("bundled", isDirectory: true)
    user = root.appendingPathComponent("user", isDirectory: true)
    try FileManager.default.createDirectory(at: bundled, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  // MARK: - 도우미

  @discardableResult
  private func writeSkill(_ id: String, markdown: String, in parent: URL? = nil) throws -> URL {
    let dir = (parent ?? user).appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try markdown.write(to: dir.appendingPathComponent("SKILL.md"), atomically: true, encoding: .utf8)
    return dir
  }

  private func markdown(name: String = "테스트 스킬",
                        description: String = "테스트용 절차",
                        extra: [String] = [],
                        body: String = "본문") -> String {
    var lines = ["---", "name: \(name)", "description: \(description)"]
    lines += extra
    lines += ["---", body]
    return lines.joined(separator: "\n")
  }

  private func parse(_ text: String, id: String = "test-skill",
                     source: Skill.Source = .user) -> Result<Skill, SkillWarning> {
    let dir = root.appendingPathComponent(id, isDirectory: true)
    return SkillMarkdown.parse(markdown: text, directory: dir, source: source)
  }

  // MARK: - 파서

  func testParsesAllFrontmatterKeys() throws {
    let text = markdown(name: "웹 조사", description: "여러 사이트를 비교한다",
                        extra: ["when: 최신 정보가 필요할 때",
                                "tools: [web_search, web_fetch]",
                                "version: 3",
                                "risk: read"],
                        body: "# 절차\n1. 검색한다")
    let skill = try parse(text).get()
    XCTAssertEqual(skill.id, "test-skill")
    XCTAssertEqual(skill.name, "웹 조사")
    XCTAssertEqual(skill.description, "여러 사이트를 비교한다")
    XCTAssertEqual(skill.when, "최신 정보가 필요할 때")
    XCTAssertEqual(skill.tools, ["web_search", "web_fetch"])
    XCTAssertEqual(skill.version, 3)
    XCTAssertEqual(skill.risk, .read)
    XCTAssertEqual(skill.body, "# 절차\n1. 검색한다")
    XCTAssertEqual(skill.source, .user)
  }

  func testRejectsMissingClosingDelimiter() {
    let text = "---\nname: x\ndescription: y\n본문"
    XCTAssertThrowsParse(text)
  }

  func testRejectsMissingName() {
    let text = "---\ndescription: y\n---\n본문"
    XCTAssertThrowsParse(text)
  }

  func testRejectsMissingDescription() {
    let text = "---\nname: x\n---\n본문"
    XCTAssertThrowsParse(text)
  }

  func testRejectsMissingFrontmatter() {
    XCTAssertThrowsParse("# 제목\n본문")
  }

  func testKeepsColonAndCommaInsideQuotes() throws {
    let text = markdown(description: "\"A, B: C\"")
    let skill = try parse(text).get()
    XCTAssertEqual(skill.description, "A, B: C")
  }

  func testParsesInlineListDeduplicatesAndLowercases() throws {
    let text = markdown(extra: ["tools: [ Shell, web_search, shell, Web_Fetch ]"])
    let skill = try parse(text).get()
    XCTAssertEqual(skill.tools, ["shell", "web_search", "web_fetch"])
  }

  func testIgnoresUnknownKeys() throws {
    let text = markdown(extra: ["future_key: value", "another: 1"])
    let skill = try parse(text).get()
    XCTAssertEqual(skill.name, "테스트 스킬")
  }

  func testNonNumericVersionFallsBackToOne() throws {
    let text = markdown(extra: ["version: one"])
    XCTAssertEqual(try parse(text).get().version, 1)
  }

  func testRiskIsInferredFromTools() throws {
    let withShell = try parse(markdown(extra: ["tools: [shell]"])).get()
    XCTAssertEqual(withShell.risk, .write)
    let withoutShell = try parse(markdown(extra: ["tools: [web_search]"])).get()
    XCTAssertEqual(withoutShell.risk, .read)
    let explicit = try parse(markdown(extra: ["tools: [shell]", "risk: read"])).get()
    XCTAssertEqual(explicit.risk, .read, "명시한 risk 가 추론보다 우선한다")
  }

  func testBodyTrimsOnlyBlankEdges() throws {
    let text = "---\nname: x\ndescription: y\n---\n\n\n  첫 줄\n\n둘째 줄\n\n\n"
    let skill = try parse(text).get()
    XCTAssertEqual(skill.body, "  첫 줄\n\n둘째 줄", "안쪽 빈 줄과 들여쓰기는 보존한다")
  }

  func testRejectsOversizedFile() {
    let huge = markdown(body: String(repeating: "a", count: SkillMarkdown.maxFileBytes))
    XCTAssertThrowsParse(huge)
  }

  // MARK: - 레지스트리

  func testUserSkillOverridesBundled() throws {
    try writeSkill("shared", markdown: markdown(name: "번들"), in: bundled)
    try writeSkill("shared", markdown: markdown(name: "사용자"), in: user)
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertEqual(result.skills.count, 1)
    XCTAssertEqual(result.skills.first?.name, "사용자")
    XCTAssertEqual(result.skills.first?.source, .user)
  }

  func testSkipsFolderWithoutSkillFile() throws {
    try FileManager.default.createDirectory(at: user.appendingPathComponent("not-a-skill"),
                                            withIntermediateDirectories: true)
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertTrue(result.skills.isEmpty)
    XCTAssertTrue(result.warnings.isEmpty, "SKILL.md 가 없는 폴더는 경고가 아니다")
  }

  func testInvalidIDProducesWarning() throws {
    try writeSkill("Bad_Name", markdown: markdown())
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertTrue(result.skills.isEmpty)
    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertEqual(result.warnings.first?.id, "Bad_Name")
  }

  func testCapsSkillsAtTwoHundred() throws {
    for i in 0..<205 {
      let id = String(format: "skill-%03d", i)
      try writeSkill(id, markdown: markdown(name: id))
    }
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertEqual(result.skills.count, SkillRegistry.maxSkills)
    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertTrue(result.warnings[0].reason.contains("200"))
  }

  func testScriptsAreCappedAtTwenty() throws {
    let dir = try writeSkill("many-scripts", markdown: markdown())
    let scripts = dir.appendingPathComponent("scripts", isDirectory: true)
    try FileManager.default.createDirectory(at: scripts, withIntermediateDirectories: true)
    for i in 0..<25 {
      try "print(\(i))".write(to: scripts.appendingPathComponent(String(format: "s%02d.py", i)),
                              atomically: true, encoding: .utf8)
    }
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertEqual(result.skills.first?.scripts.count, 20)
    XCTAssertEqual(result.skills.first?.scripts.first, "scripts/s00.py")
  }

  func testSymlinkOutsideRootIsRejected() throws {
    let outside = root.appendingPathComponent("outside/evil", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try markdown().write(to: outside.appendingPathComponent("SKILL.md"),
                         atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
      at: user.appendingPathComponent("evil"), withDestinationURL: outside)

    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertTrue(result.skills.isEmpty)
    XCTAssertEqual(result.warnings.count, 1)
    XCTAssertTrue(result.warnings[0].reason.contains("밖"))
  }

  func testSortsByName() throws {
    try writeSkill("zeta", markdown: markdown(name: "나중"))
    try writeSkill("alpha", markdown: markdown(name: "가나"))
    let result = SkillRegistry.load(bundledRoot: bundled, userRoot: user)
    XCTAssertEqual(result.skills.map(\.id), ["alpha", "zeta"])
  }

  // MARK: - 설정·비서 호환

  func testSettingsDefaultSkillsOffForOldJSON() throws {
    let data = try JSONEncoder().encode(QuickTalkSettings())
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "skillsEnabled")
    let old = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: old)
    XCTAssertFalse(decoded.skillsEnabled)
  }

  func testPersonaSkillsDefaultOnForOldJSON() throws {
    let persona = Persona(name: "리서처")
    let data = try JSONEncoder().encode(persona)
    var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "skillsEnabled")
    let old = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(Persona.self, from: old)
    XCTAssertTrue(decoded.skillsEnabled)
    XCTAssertEqual(decoded.name, "리서처")
  }

  // MARK: - 프롬프트 (v0.37 P2)

  private func skill(id: String, description: String = "설명", when: String = "",
                     tools: [String] = []) -> Skill {
    Skill(id: id, name: id, description: description, when: when, tools: tools,
          risk: .read, source: .user,
          directory: root.appendingPathComponent(id, isDirectory: true),
          body: "본문 내용", scripts: [])
  }

  func testEmptySkillsProduceNoBlock() {
    XCTAssertNil(SkillPrompt.block(for: []))
  }

  func testBlockHasOnlyListAndSafetyFooter() throws {
    let block = try XCTUnwrap(SkillPrompt.block(for: [
      skill(id: "web-research", description: "조사한다", when: "최신 정보")
    ]))
    XCTAssertTrue(block.contains("web-research — 조사한다 (언제: 최신 정보)"))
    XCTAssertFalse(block.contains("본문 내용"), "본문은 목록에 넣지 않는다")
    XCTAssertTrue(block.contains("안전 규칙이 항상 우선"))
  }

  func testBlockRespectsBudgetAndSaysHowManyAreHidden() {
    let skills = (0..<40).map {
      skill(id: String(format: "skill-%02d", $0),
            description: String(repeating: "가", count: 100))
    }
    let block = SkillPrompt.block(for: skills) ?? ""
    XCTAssertLessThanOrEqual(block.count, SkillPrompt.budget)
    XCTAssertTrue(block.contains("…외"), block)
  }

  func testAvailableSkillsRequiresToolSubset() {
    let readOnly = skill(id: "reader", tools: ["web_search"])
    let shellSkill = skill(id: "writer", tools: ["shell"])
    let unrestricted = skill(id: "free", tools: [])
    let usable = SkillPrompt.availableSkills([readOnly, shellSkill, unrestricted],
                                             availableTools: ["web_search", "read_file"])
    XCTAssertEqual(usable.map(\.id), ["reader", "free"])
  }

  func testEffectiveEnabledPersonaOverridesGlobal() {
    var settings = QuickTalkSettings()
    settings.skillsEnabled = false
    XCTAssertFalse(SkillPrompt.effectiveEnabled(settings: settings, persona: nil),
                   "일반 대화는 전역 설정을 따른다(기본 Off)")
    XCTAssertTrue(SkillPrompt.effectiveEnabled(settings: settings,
                                               persona: Persona(name: "비서")),
                  "비서는 전역 Off 를 덮어쓴다(기본 On)")

    settings.skillsEnabled = true
    var off = Persona(name: "비서")
    off.skillsEnabled = false
    XCTAssertFalse(SkillPrompt.effectiveEnabled(settings: settings, persona: off),
                   "비서 Off 는 전역 On 도 덮어쓴다")
  }

  func testScheduledRunNeverUsesSkills() {
    var settings = QuickTalkSettings()
    settings.skillsEnabled = true
    XCTAssertFalse(SkillPrompt.effectiveEnabled(settings: settings, persona: nil,
                                                scheduled: true))
    XCTAssertFalse(SkillPrompt.effectiveEnabled(settings: settings,
                                                persona: Persona(name: "비서"),
                                                scheduled: true))
  }

  // MARK: - 실행 카드 표시 (v0.37 §11.4)

  func testFindsUserSkillInCommand() {
    let command = #"python3 "/Users/me/Library/Application Support/QuickTalk/Skills/weekly-report/scripts/x.py""#
    XCTAssertEqual(SkillLocations.skillID(referencedIn: command), "weekly-report")
  }

  func testFindsBundledSkillInCommand() {
    let command = "cat /Applications/QuickTalk.app/Contents/Resources/Skills/web-research/SKILL.md"
    XCTAssertEqual(SkillLocations.skillID(referencedIn: command), "web-research")
  }

  func testIgnoresUnrelatedPathAndInvalidID() {
    XCTAssertNil(SkillLocations.skillID(referencedIn: "ls ~/Documents"))
    XCTAssertNil(SkillLocations.skillID(
      referencedIn: "/Users/me/Library/Application Support/QuickTalk/Skills/Bad_Name/x"))
    XCTAssertNil(SkillLocations.skillID(
      referencedIn: "/Users/me/Library/Application Support/QuickTalk/Skills2/web/x"))
  }

  // MARK: - 도우미

  private func XCTAssertThrowsParse(_ text: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
    switch parse(text) {
    case .success:
      XCTFail("무효인 SKILL.md 가 통과했다", file: file, line: line)
    case .failure(let warning):
      XCTAssertFalse(warning.reason.isEmpty, file: file, line: line)
    }
  }
}
