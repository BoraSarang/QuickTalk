import XCTest
@testable import QuickTalkCore

final class ArtifactTests: XCTestCase {
  // MARK: - 줄 diff

  func testLineDiffCountsAndUnifiedHunk() throws {
    let before = "one\ntwo\nthree\nfour\nfive\n"
    let after = "one\ntwo changed\nthree\nfour\nfive\nsix\n"
    let diff = try XCTUnwrap(LineDiff.compare(before: before, after: after))
    XCTAssertEqual(diff.added, 2)
    XCTAssertEqual(diff.removed, 1)
    XCTAssertTrue(diff.unified.contains("@@"))
    XCTAssertTrue(diff.unified.contains("-two"))
    XCTAssertTrue(diff.unified.contains("+two changed"))
    XCTAssertTrue(diff.unified.contains("+six"))
    XCTAssertFalse(diff.truncated)
  }

  func testLineDiffTreatsCRLFAsSameLineEnding() throws {
    let diff = try XCTUnwrap(LineDiff.compare(before: "a\r\nb\r\n", after: "a\nb\n"))
    XCTAssertEqual(diff.added, 0)
    XCTAssertEqual(diff.removed, 0)
    XCTAssertEqual(diff.unified, "")
  }

  func testLineDiffSkipsVeryLargeFiles() {
    let before = (0..<(LineDiff.maxLines + 1)).map(String.init).joined(separator: "\n")
    XCTAssertNil(LineDiff.compare(before: before, after: before + "\nx"))
  }

  func testLineDiffTruncatesLongOutput() throws {
    let before = (0..<1_000).map { "old \($0)" }.joined(separator: "\n")
    let after = (0..<1_000).map { "new \($0)" }.joined(separator: "\n")
    let diff = try XCTUnwrap(LineDiff.compare(before: before, after: after))
    XCTAssertEqual(diff.added, 1_000)
    XCTAssertEqual(diff.removed, 1_000)
    XCTAssertTrue(diff.truncated)
    XCTAssertLessThanOrEqual(diff.unified.components(separatedBy: "\n").count,
                             LineDiff.maxOutputLines + 2)
  }

  // MARK: - Codable

  func testTurnWithoutArtifactsStillDecodes() throws {
    let json = """
    {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","role":"user","text":"hi",
     "attachments":[],"status":"done"}
    """
    let turn = try JSONDecoder().decode(Turn.self, from: Data(json.utf8))
    XCTAssertNil(turn.artifacts)
  }

  func testArtifactCodableRoundTrip() throws {
    let artifact = TurnArtifact(path: "/tmp/a.md", change: .modified, byteCount: 42,
                                addedLines: 3, removedLines: 1, undoID: "u1",
                                createdAt: Date(timeIntervalSince1970: 100))
    let data = try JSONEncoder().encode(artifact)
    XCTAssertEqual(try JSONDecoder().decode(TurnArtifact.self, from: data), artifact)
  }

  // MARK: - Store

  func testStoreReplacesSamePathAndCapsCount() {
    let store = ConversationStore()
    let turn = store.appendAssistant(text: "결과")
    store.appendArtifact(TurnArtifact(path: "/tmp/a.md", change: .created, byteCount: 10), to: turn.id)
    store.appendArtifact(TurnArtifact(path: "/tmp/a.md", change: .modified, byteCount: 20), to: turn.id)
    XCTAssertEqual(store.conversation.turns.last?.artifacts?.count, 1)
    XCTAssertEqual(store.conversation.turns.last?.artifacts?.first?.change, .modified)
    XCTAssertEqual(store.conversation.turns.last?.artifacts?.first?.byteCount, 20)

    for i in 0..<(TurnArtifact.maxPerTurn + 3) {
      store.appendArtifact(TurnArtifact(path: "/tmp/f\(i).md", change: .created, byteCount: i),
                           to: turn.id)
    }
    XCTAssertEqual(store.conversation.turns.last?.artifacts?.count, TurnArtifact.maxPerTurn)
  }

  // MARK: - UndoEntry 에서 수집

  func testCollectsCreatedModifiedDeletedAndSkipsUnchanged() async throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("qt-artifact-\(UUID())", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let created = tmp.appendingPathComponent("created.md").path
    let modified = tmp.appendingPathComponent("modified.md").path
    let deleted = tmp.appendingPathComponent("deleted.md").path
    let unchanged = tmp.appendingPathComponent("unchanged.md").path
    try fm.createDirectory(at: tmp.appendingPathComponent("unused"), withIntermediateDirectories: true)

    try "old\n".write(toFile: modified, atomically: true, encoding: .utf8)
    try "gone\n".write(toFile: deleted, atomically: true, encoding: .utf8)
    try "same\n".write(toFile: unchanged, atomically: true, encoding: .utf8)

    let stack = UndoStack(root: tmp.appendingPathComponent("undo", isDirectory: true),
                          trashRoot: tmp.appendingPathComponent("trash", isDirectory: true))
    let entry = await stack.snapshot(command: "test", scope: tmp.path,
                                     paths: [created, modified, deleted, unchanged])

    try "new\nsecond\n".write(toFile: created, atomically: true, encoding: .utf8)
    try "old\nnew line\n".write(toFile: modified, atomically: true, encoding: .utf8)
    try fm.removeItem(atPath: deleted)

    let artifacts = FileArtifacts.collect(undo: entry)
    let byPath = Dictionary(uniqueKeysWithValues: artifacts.map { ($0.path, $0) })
    XCTAssertEqual(byPath[created]?.change, .created)
    XCTAssertEqual(byPath[modified]?.change, .modified)
    XCTAssertEqual(byPath[deleted]?.change, .deleted)
    XCTAssertNil(byPath[unchanged], "내용이 같은 파일은 산출물이 아니다")
    XCTAssertEqual(byPath[created]?.addedLines, 2)
    XCTAssertEqual(byPath[modified]?.addedLines, 1)
    XCTAssertEqual(byPath[deleted]?.removedLines, 1)
    XCTAssertEqual(byPath[created]?.undoID, entry.id)
  }

  func testCollectSkipsDirectories() async throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("qt-artifact-dir-\(UUID())", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    let dir = tmp.appendingPathComponent("folder", isDirectory: true).path
    try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let stack = UndoStack(root: tmp.appendingPathComponent("undo", isDirectory: true),
                          trashRoot: tmp.appendingPathComponent("trash", isDirectory: true))
    let entry = await stack.snapshot(command: "test", scope: tmp.path, paths: [dir])
    XCTAssertTrue(FileArtifacts.collect(undo: entry).isEmpty)
  }

  // MARK: - 미리보기

  func testPreviewTextDiffAndMissing() async throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("qt-preview-\(UUID())", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    let path = tmp.appendingPathComponent("note.md").path
    try "before\n".write(toFile: path, atomically: true, encoding: .utf8)
    let stack = UndoStack(root: tmp.appendingPathComponent("undo", isDirectory: true),
                          trashRoot: tmp.appendingPathComponent("trash", isDirectory: true))
    let entry = await stack.snapshot(command: "test", scope: tmp.path, paths: [path])
    try "before\nafter\n".write(toFile: path, atomically: true, encoding: .utf8)

    let preview = FileArtifacts.preview(path: path, undoEntry: entry)
    XCTAssertEqual(preview.kind, .text)
    XCTAssertEqual(preview.lineCount, 2)
    XCTAssertFalse(preview.truncated)
    XCTAssertTrue(preview.diff?.contains("+after") == true)

    try fm.removeItem(atPath: path)
    let missing = FileArtifacts.preview(path: path, undoEntry: entry)
    XCTAssertEqual(missing.kind, .missing)
    XCTAssertTrue(missing.diff?.contains("-before") == true, "삭제된 파일은 백업과의 diff 를 보여 준다")
  }

  func testPreviewImageAndBinary() throws {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory.appendingPathComponent("qt-preview-kind-\(UUID())", isDirectory: true)
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }

    let image = tmp.appendingPathComponent("pixel.png").path
    try Data([0x89, 0x50, 0x4E, 0x47]).write(to: URL(fileURLWithPath: image))
    XCTAssertEqual(FileArtifacts.preview(path: image).kind, .image)

    let binary = tmp.appendingPathComponent("data.bin").path
    try Data([0, 1, 2, 3]).write(to: URL(fileURLWithPath: binary))
    XCTAssertEqual(FileArtifacts.preview(path: binary).kind, .binary)
  }

  func testWritePreviewShowsOnlyFirstLines() {
    let content = (0..<40).map { "line \($0)" }.joined(separator: "\n")
    let preview = FileWritePreview(path: "/tmp/a.md", isNew: true, content: content)
    XCTAssertTrue(preview.truncated)
    XCTAssertEqual(preview.lineCount, 40)
    XCTAssertEqual(preview.text.components(separatedBy: "\n").count, FileWritePreview.maxLines)
  }

  // MARK: - 도구 카탈로그·권한

  func testWriteFileToolIsInCatalogAndWritable() {
    XCTAssertTrue(AgentToolCatalog.all.contains { $0.name == "write_file" })
    XCTAssertEqual(AgentToolPermission.level(for: "write_file"), .write)
    XCTAssertEqual(AgentToolCatalog.available(includingWebSearch: false).count, 7)
  }

  func testPersonaWriteToggleGatesWriteFile() {
    let off = AgentToolCatalog.available(for: PersonaTools(write: false), includingWebSearch: false)
    XCTAssertFalse(off.contains { $0.name == "write_file" })
    let on = AgentToolCatalog.available(for: PersonaTools(write: true), includingWebSearch: false)
    XCTAssertTrue(on.contains { $0.name == "write_file" })
  }
}
