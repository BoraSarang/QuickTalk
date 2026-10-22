import XCTest
@testable import QuickTalkCore

/// 공통 메모리 (PLAN_v0.16) — 저장·선택·토큰 예산·관련성 검색·가져오기/내보내기.
/// 네트워크 없이 순수 로직만 검증한다.
final class GlobalMemoryTests: XCTestCase {

  private func entry(_ title: String, _ content: String,
                     tags: [String] = [], enabled: Bool = true,
                     always: Bool = false) -> GlobalMemoryEntry {
    GlobalMemoryEntry(title: title, content: content, tags: tags,
                      enabled: enabled, alwaysInclude: always)
  }

  // MARK: - 모델·저장

  func testEntryCodableRoundTrip() throws {
    let original = entry("맥 사양", "M4 Pro 24GB", tags: ["개발", "하드웨어"], always: true)
    let data = try GlobalMemoryFile.encode([original])
    let decoded = try GlobalMemoryFile.decode(data)
    XCTAssertEqual(decoded.count, 1)
    XCTAssertEqual(decoded[0].id, original.id)
    XCTAssertEqual(decoded[0].title, "맥 사양")
    XCTAssertEqual(decoded[0].tags, ["개발", "하드웨어"])
    XCTAssertTrue(decoded[0].alwaysInclude)
    XCTAssertTrue(decoded[0].enabled)
  }

  func testLegacyEntryWithoutOptionalKeysDecodes() throws {
    let json = #"[{"title":"옛 메모","content":"본문"}]"#
    let decoded = try GlobalMemoryFile.decode(Data(json.utf8))
    XCTAssertEqual(decoded.count, 1)
    XCTAssertTrue(decoded[0].enabled)
    XCTAssertFalse(decoded[0].alwaysInclude)
    XCTAssertEqual(decoded[0].displayTitle, "옛 메모")
  }

  func testSaveLoadAndMergeSkipsDuplicateIDs() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-memory-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("memory.json")
    defer { try? FileManager.default.removeItem(at: dir) }

    let a = entry("A", "첫째")
    let b = entry("B", "둘째")
    try GlobalMemoryFile.save([a], to: url)
    XCTAssertEqual(GlobalMemoryFile.load(from: url).map(\.title), ["A"])

    let merged = GlobalMemoryFile.merge([a], with: [a, b])
    XCTAssertEqual(merged.added, 1)
    XCTAssertEqual(merged.entries.count, 2)
  }

  func testBlankEntriesAreIgnored() {
    let blank = GlobalMemoryEntry()
    XCTAssertTrue(blank.isBlank)
    XCTAssertEqual(GlobalMemory.enabled([blank]).count, 0)
    XCTAssertEqual(GlobalMemoryFile.merge([], with: [blank]).added, 0)
  }

  func testNormalizeTags() {
    XCTAssertEqual(GlobalMemoryEntry.normalizeTags(" 개발, #맥  ,, 개발 ; 하드웨어 "),
                   ["개발", "맥", "하드웨어"])
  }

  // MARK: - 선택·토큰 예산

  func testDisabledEntriesAreNeverIncluded() {
    let on = entry("켬", "포함")
    let off = entry("끔", "제외", enabled: false)
    let prompt = GlobalMemory.prompt([on, off], query: "질문", mode: .always, budget: 800)
    XCTAssertTrue(prompt.text.contains("포함"))
    XCTAssertFalse(prompt.text.contains("제외"))
  }

  func testBudgetStopsOrClipsEntries() {
    let long = String(repeating: "가", count: 2_000)
    let prompt = GlobalMemory.prompt([entry("긴 메모", long)],
                                     query: "질문", mode: .always, budget: 400)
    XCTAssertFalse(prompt.included.isEmpty)
    XCTAssertLessThanOrEqual(prompt.tokens, 460)                 // 추정 오차 여유
    XCTAssertEqual(prompt.clippedIDs.count, 1)
    XCTAssertTrue(prompt.included[0].content.hasSuffix("…"))
  }

  func testTinyBudgetIncludesNothing() {
    XCTAssertTrue(GlobalMemory.prompt([entry("A", "B")], query: "q",
                                      mode: .always, budget: 20).isEmpty)
  }

  func testAlwaysModeKeepsUserOrder() {
    let entries = [entry("첫째", "1"), entry("둘째", "2"), entry("셋째", "3")]
    let picked = GlobalMemory.select(entries, query: "", mode: .always)
    XCTAssertEqual(picked.map(\.title), ["첫째", "둘째", "셋째"])
  }

  // MARK: - 관련성 검색 (P3)

  func testEmbeddingIsDeterministicAndNormalized() {
    let a = MemoryEmbedding.vector(for: "맥북 M4 Pro 개발")
    let b = MemoryEmbedding.vector(for: "맥북 M4 Pro 개발")
    XCTAssertEqual(a, b)
    let norm = sqrt(a.reduce(0) { $0 + $1 * $1 })
    XCTAssertEqual(norm, 1.0, accuracy: 0.0001)
    XCTAssertEqual(MemoryEmbedding.cosine(a, b), 1.0, accuracy: 0.0001)
  }

  func testRelevantModePicksMatchingEntryOnly() {
    let spec = entry("내 컴퓨터", "컴퓨터 사양은 맥북 M4 Pro 24GB이다", tags: ["개발"])
    let cat = entry("고양이", "고양이 이름은 보리이고 사료는 연어를 먹는다")
    let picked = GlobalMemory.select([spec, cat], query: "내 컴퓨터 사양 알려줘",
                                     mode: .relevant)
    XCTAssertEqual(picked.map(\.title), ["내 컴퓨터"])
  }

  func testRelevantModeKeepsAlwaysInclude() {
    let spec = entry("내 컴퓨터", "맥북 M4 Pro")
    let rule = entry("답변 규칙", "항상 존댓말", always: true)
    let picked = GlobalMemory.select([spec, rule], query: "오늘 날씨",
                                     mode: .relevant)
    XCTAssertEqual(picked.map(\.title), ["답변 규칙"])
  }

  func testRelevantModeWithNoMatchIncludesNothing() {
    let cat = entry("고양이", "보리")
    XCTAssertTrue(GlobalMemory.select([cat], query: "스위프트 동시성",
                                      mode: .relevant).isEmpty)
  }

  // MARK: - 설정·대화 호환

  func testSettingsRoundTripKeepsGlobalMemoryFields() throws {
    var settings = QuickTalkSettings()
    settings.globalMemoryEnabled = false
    settings.globalMemoryMode = .relevant
    settings.globalMemoryBudgetTokens = 1_600
    settings.webSearchMode = .toolCalling
    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: data)
    XCTAssertFalse(decoded.globalMemoryEnabled)
    XCTAssertEqual(decoded.globalMemoryMode, .relevant)
    XCTAssertEqual(decoded.globalMemoryBudgetTokens, 1_600)
    XCTAssertEqual(decoded.webSearchMode, .toolCalling)
  }

  func testLegacySettingsUseGlobalMemoryDefaults() throws {
    let json = #"{"showMenuBarIcon":true,"showDockIcon":false}"#
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: Data(json.utf8))
    // 2026-10-22 사용자 요청 — 공용 메모리 기본값 Off.
    XCTAssertFalse(decoded.globalMemoryEnabled)
    XCTAssertEqual(decoded.globalMemoryMode, .always)
    XCTAssertEqual(decoded.globalMemoryBudgetTokens, 800)
    XCTAssertEqual(decoded.webSearchMode, .inject)
  }

  func testGlobalMemoryDefaultIsOff() {
    // 신규 사용자(설정 파일 없음)는 공용 메모리가 기본 OFF다.
    let settings = QuickTalkSettings()
    XCTAssertFalse(settings.globalMemoryEnabled)
  }

  func testConversationCommonMemoryFlagRoundTrip() throws {
    let original = Conversation(turns: [], commonMemoryDisabled: true)
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Conversation.self, from: data)
    XCTAssertEqual(decoded.commonMemoryDisabled, true)
  }

  func testConversationWithoutFlagDefaultsToUsingMemory() throws {
    let json = #"{"id":"00000000-0000-0000-0000-000000000001","title":"t","turns":[],"updatedAt":0}"#
    let decoded = try JSONDecoder().decode(Conversation.self, from: Data(json.utf8))
    XCTAssertNil(decoded.commonMemoryDisabled)
  }

  // MARK: - 프롬프트

  func testPromptHasHeaderRulesAndTags() {
    let prompt = GlobalMemory.prompt([entry("맥 사양", "M4 Pro 24GB", tags: ["개발"])],
                                     query: "질문", mode: .always, budget: 800)
    XCTAssertTrue(prompt.text.contains("공통 메모리"))
    XCTAssertTrue(prompt.text.contains("다시 묻지 않는다"))
    XCTAssertTrue(prompt.text.contains("M4 Pro 24GB"))
    XCTAssertTrue(prompt.text.contains("#개발"))
    XCTAssertGreaterThan(prompt.tokens, 0)
  }

  func testCachedEntryVectorMatchesDirectVector() {
    let e = entry("맥 사양", "M4 Pro 24GB", tags: ["개발"])
    let direct = MemoryEmbedding.vector(for: e.displayTitle + "\n" + e.content + "\n"
      + e.tags.joined(separator: " "))
    let cached = MemoryEmbedding.vector(for: e)
    XCTAssertEqual(cached, direct)
    XCTAssertEqual(MemoryEmbedding.vector(for: e), cached)
  }

  func testMultilineMemoryIsIndentedUnderItsBullet() {
    let prompt = GlobalMemory.prompt([entry("설정", "첫 줄\n둘째 줄")],
                                     query: "질문", mode: .always, budget: 800)
    XCTAssertTrue(prompt.text.contains("- [설정] 첫 줄\n  둘째 줄"))
  }

  func testCorruptMemoryFileIsPreserved() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-memory-corrupt-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    let url = dir.appendingPathComponent("memory.json")
    let broken = Data("{not json".utf8)
    try broken.write(to: url)

    XCTAssertTrue(GlobalMemoryFile.load(from: url).isEmpty)
    let backup = url.appendingPathExtension("corrupt")
    XCTAssertEqual(try Data(contentsOf: backup), broken)
  }

  func testSavedMemoryFileIsOwnerOnly() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-memory-perm-\(UUID().uuidString)", isDirectory: true)
    let url = dir.appendingPathComponent("memory.json")
    defer { try? FileManager.default.removeItem(at: dir) }
    try GlobalMemoryFile.save([entry("A", "B")], to: url)
    let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
    XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testUnknownEnumValuesDoNotDiscardOtherSettings() throws {
    let json = #"{"showMenuBarIcon":false,"keepDays":7,"globalMemoryMode":"future","webSearchMode":"future","webSearchProvider":"future"}"#
    let decoded = try JSONDecoder().decode(QuickTalkSettings.self, from: Data(json.utf8))
    XCTAssertFalse(decoded.showMenuBarIcon)
    XCTAssertEqual(decoded.keepDays, 7)
    XCTAssertEqual(decoded.globalMemoryMode, .always)
    XCTAssertEqual(decoded.webSearchMode, .inject)
    XCTAssertEqual(decoded.webSearchProvider, .none)
  }
}
