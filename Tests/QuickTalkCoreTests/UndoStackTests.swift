import XCTest
@testable import QuickTalkCore

// [FEATURE] 되돌리기 스택 테스트 (PLAN_v0.18 v0.19)
//
// 쓰기 직전 스냅샷 → 명령 실행 → [되돌리기] 로 그 시점 복원.
// 임시 폴더에서만 검사한다(실제 사용자 파일은 건드리지 않는다).

final class UndoStackTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-undo-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let root { try? FileManager.default.removeItem(at: root) }
  }

  private func makeStack(maxBytes: Int = 64 * 1024 * 1024,
                         maxEntries: Int = 30) -> UndoStack {
    UndoStack(root: root.appendingPathComponent("undo", isDirectory: true),
              trashRoot: root.appendingPathComponent("trash", isDirectory: true),
              maxBytes: maxBytes, maxEntries: maxEntries)
  }

  private func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
  }

  // MARK: - 복원

  func testSnapshotRestoresDeletedFile() async throws {
    let file = root.appendingPathComponent("work/a.txt")
    try write("hello", to: file)
    let stack = makeStack()

    let entry = await stack.snapshot(command: "rm -f a.txt", scope: root.appendingPathComponent("work").path,
                                     paths: [file.path])
    try FileManager.default.removeItem(at: file)     // 명령이 지운 것과 같은 상태
    await stack.commit(entry)

    let result = await stack.undo(id: entry.id)
    XCTAssertTrue(result.succeeded, "\(result)")
    XCTAssertEqual(result.restored, 1)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "hello")
  }

  func testSnapshotRestoresModifiedFile() async throws {
    let file = root.appendingPathComponent("work/b.txt")
    try write("before", to: file)
    let stack = makeStack()
    let entry = await stack.snapshot(command: "echo after > b.txt",
                                     scope: root.appendingPathComponent("work").path,
                                     paths: [file.path])
    try write("after", to: file)                     // 명령이 덮어쓴 것과 같은 상태
    await stack.commit(entry)

    let result = await stack.undo(id: entry.id)
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "before")
  }

  func testUndoRemovesFileCreatedByCommand() async throws {
    let file = root.appendingPathComponent("work/new.txt")
    let stack = makeStack()
    // 실행 전에는 없던 경로 — 되돌리면 지운다.
    let entry = await stack.snapshot(command: "touch new.txt",
                                     scope: root.appendingPathComponent("work").path,
                                     paths: [file.path])
    try write("created", to: file)
    await stack.commit(entry)

    let result = await stack.undo(id: entry.id)
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(result.removed, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testDirectoryTreeIsRestored() async throws {
    let dir = root.appendingPathComponent("work/folder")
    try write("1", to: dir.appendingPathComponent("a.txt"))
    try write("2", to: dir.appendingPathComponent("sub/b.txt"))
    let stack = makeStack()
    let entry = await stack.snapshot(command: "rm -rf folder", scope: root.appendingPathComponent("work").path,
                                     paths: [dir.path])
    try FileManager.default.removeItem(at: dir)
    await stack.commit(entry)

    let result = await stack.undo(id: entry.id)
    XCTAssertTrue(result.succeeded)
    XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("a.txt"), encoding: .utf8), "1")
    XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent("sub/b.txt"), encoding: .utf8), "2")
  }

  // MARK: - 한계

  func testUndoTwiceIsNoOp() async throws {
    let file = root.appendingPathComponent("work/c.txt")
    try write("x", to: file)
    let stack = makeStack()
    let entry = await stack.snapshot(command: "rm c.txt",
                                     scope: root.appendingPathComponent("work").path,
                                     paths: [file.path])
    try FileManager.default.removeItem(at: file)
    await stack.commit(entry)

    _ = await stack.undo(id: entry.id)
    let second = await stack.undo(id: entry.id)
    XCTAssertTrue(second.alreadyUndone)
    XCTAssertFalse(second.succeeded)
  }

  func testTooLargeFileIsNotBackedUp() async throws {
    let file = root.appendingPathComponent("work/big.bin")
    try write(String(repeating: "a", count: 200), to: file)
    let stack = makeStack(maxBytes: 50)
    let entry = await stack.snapshot(command: "rm big.bin",
                                     scope: root.appendingPathComponent("work").path,
                                     paths: [file.path])
    XCTAssertNil(entry.items[0].backup)
    XCTAssertNotNil(entry.note)
    XCTAssertFalse(entry.isUndoable)

    try FileManager.default.removeItem(at: file)
    await stack.commit(entry)
    let result = await stack.undo(id: entry.id)
    XCTAssertFalse(result.succeeded)
    XCTAssertEqual(result.failed, [file.path])
  }

  func testCommitKeepsOnlyMaxEntries() async throws {
    let stack = makeStack(maxEntries: 2)
    for i in 0..<3 {
      let entry = await stack.snapshot(command: "touch f\(i)",
                                       scope: root.path, paths: [root.appendingPathComponent("f\(i)").path])
      await stack.commit(entry)
    }
    let count = await stack.entries.count
    XCTAssertEqual(count, 2)
  }

  func testNotFoundEntry() async {
    let stack = makeStack()
    let result = await stack.undo(id: "nope")
    XCTAssertTrue(result.notFound)
  }
}
