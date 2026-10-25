import XCTest
@testable import QuickTalkCore

// [FEATURE] 휴지통 rewrite 테스트 (PLAN_v0.18 v0.19)
//
// 단순 `rm` 만 이동으로 바꾼다. 복합 명령·글롭·상대 경로·시스템 경로는 **바꾸지 않는다**(위험).

final class TrashRewriteTests: XCTestCase {
  private var root: URL!
  private var trash: URL!

  override func setUpWithError() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-trash-\(UUID().uuidString)", isDirectory: true)
    trash = root.appendingPathComponent("trash", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    if let root { try? FileManager.default.removeItem(at: root) }
  }

  private func touch(_ name: String) throws -> URL {
    let url = root.appendingPathComponent(name)
    try "x".write(to: url, atomically: true, encoding: .utf8)
    return url
  }

  func testSimpleRemoveBecomesMove() throws {
    let file = try touch("a.txt")
    let plan = try XCTUnwrap(TrashRewrite.plan("rm \(file.path)", trashRoot: trash.path, id: "abc"))
    XCTAssertEqual(plan.moves.count, 1)
    XCTAssertEqual(plan.moves[0].source, file.path)
    XCTAssertTrue(plan.command.hasPrefix("mkdir -p "))
    XCTAssertTrue(plan.command.contains("mv -f --"))
    XCTAssertFalse(plan.command.contains("rm "))
  }

  func testFlagsAreIgnoredButTargetsKept() throws {
    let file = try touch("b.txt")
    let plan = try XCTUnwrap(TrashRewrite.plan("rm -rf \(file.path)", trashRoot: trash.path))
    XCTAssertEqual(plan.moves.map(\.source), [file.path])
  }

  func testMultipleTargets() throws {
    let a = try touch("c1.txt"), b = try touch("c2.txt")
    let plan = try XCTUnwrap(TrashRewrite.plan("rm \(a.path) \(b.path)", trashRoot: trash.path))
    XCTAssertEqual(plan.moves.count, 2)
    XCTAssertEqual(plan.command.components(separatedBy: "mv -f --").count - 1, 2)
  }

  func testComplexCommandIsNotRewritten() throws {
    let file = try touch("d.txt")
    XCTAssertNil(TrashRewrite.plan("rm \(file.path) && echo done", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("rm \(file.path) | cat", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("rm \(file.path); ls", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("echo rm \(file.path) > log", trashRoot: trash.path))
  }

  func testGlobIsNotRewritten() throws {
    _ = try touch("e.log")
    XCTAssertNil(TrashRewrite.plan("rm \(root.path)/*.log", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("rm \(root.path)/e*.log", trashRoot: trash.path))
  }

  func testRelativePathIsNotRewritten() throws {
    _ = try touch("rel.txt")
    // 상대 경로는 실행 위치(cwd)를 알 수 없다 — 그대로 실행하게 둔다.
    XCTAssertNil(TrashRewrite.plan("rm rel.txt", trashRoot: trash.path))
  }

  func testMissingTargetIsNotRewritten() {
    // `rm -f` 는 없는 파일도 성공한다 — `mv` 로 바꾸면 결과(종료 코드)가 달라진다.
    XCTAssertNil(TrashRewrite.plan("rm \(root.path)/nope.txt", trashRoot: trash.path))
  }

  func testSystemPathIsNotRewritten() {
    XCTAssertNil(TrashRewrite.plan("rm -rf /usr/local/lib/x", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("rm -rf ~", trashRoot: trash.path))
  }

  func testNotRemoveCommand() {
    XCTAssertNil(TrashRewrite.plan("mv a.txt b.txt", trashRoot: trash.path))
    XCTAssertNil(TrashRewrite.plan("ls", trashRoot: trash.path))
  }

  func testQuotedPathWithSpaces() throws {
    let file = root.appendingPathComponent("my notes.txt")
    try "x".write(to: file, atomically: true, encoding: .utf8)
    let plan = try XCTUnwrap(TrashRewrite.plan("rm \"\(file.path)\"", trashRoot: trash.path))
    XCTAssertEqual(plan.moves[0].source, file.path)
    XCTAssertTrue(plan.command.contains("'"), "경로는 셸 인용으로 감싼다")
  }

  /// 실제로 실행해 파일이 사라지고 휴지통에 남는지 — 샌드박스 없이 셸만 확인.
  func testRewrittenCommandMovesFile() throws {
    let file = try touch("f.txt")
    let plan = try XCTUnwrap(TrashRewrite.plan("rm \(file.path)", trashRoot: trash.path, id: "run"))
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", plan.command]
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: plan.moves[0].destination))
  }
}
