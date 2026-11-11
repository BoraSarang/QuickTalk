import XCTest
@testable import QuickTalkCore

/// v0.36.1 — "리포트 폴더"를 **작업 폴더**로 바꾸면서 생긴 이전 규칙.
///
/// 자동 이전은 **앱이 만든 옛 이름(`QuickTalkReport`)에만** 적용한다.
/// 사용자가 직접 고른 폴더는 이름이 같아 보여도 건드리지 않는다.
final class WorkspaceFolderTests: XCTestCase {
  private var root: URL!

  override func setUpWithError() throws {
    root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("WorkspaceFolderTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: root)
  }

  private var home: String { root.path }

  private func makeFolder(_ relative: String) throws -> URL {
    let url = URL(fileURLWithPath: home).appendingPathComponent(relative, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  func testLegacyFolderIsRenamedAndSettingUpdated() throws {
    let old = try makeFolder("Documents/QuickTalkReport")
    try "report".write(to: old.appendingPathComponent("note.md"), atomically: true, encoding: .utf8)

    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkReport"
    let changed = WorkspaceFolder.migrate(settings: &settings, home: home)

    XCTAssertTrue(changed)
    XCTAssertEqual(settings.defaultReportFolder, WorkspaceFolder.defaultPath)
    let new = URL(fileURLWithPath: home).appendingPathComponent("Documents/QuickTalkWorkspace")
    XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    XCTAssertEqual(try String(contentsOf: new.appendingPathComponent("note.md"), encoding: .utf8),
                   "report", "내용이 그대로 옮겨져야 한다")
    XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "옛 폴더는 남지 않는다")
  }

  /// 둘 다 있으면 합치지 않는다 — 사용자가 어느 쪽을 보던 중인지 알 수 없다.
  func testExistingNewFolderIsNotMerged() throws {
    let old = try makeFolder("Documents/QuickTalkReport")
    let new = try makeFolder("Documents/QuickTalkWorkspace")
    try "old".write(to: old.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
    try "new".write(to: new.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)

    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkReport"
    let changed = WorkspaceFolder.migrate(settings: &settings, home: home)

    XCTAssertFalse(changed)
    XCTAssertEqual(settings.defaultReportFolder, "~/Documents/QuickTalkReport")
    XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("a.md").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("b.md").path))
  }

  func testCustomFolderIsUntouched() throws {
    try makeFolder("Documents/MyOwnFolder")
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/MyOwnFolder"

    XCTAssertFalse(WorkspaceFolder.migrate(settings: &settings, home: home))
    XCTAssertEqual(settings.defaultReportFolder, "~/Documents/MyOwnFolder")
  }

  func testMissingLegacyFolderOnlyRepointsSetting() throws {
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkReport"

    XCTAssertTrue(WorkspaceFolder.migrate(settings: &settings, home: home))
    XCTAssertEqual(settings.defaultReportFolder, WorkspaceFolder.defaultPath)
    // 폴더는 필요할 때 만든다 — 이전이 폴더를 미리 만들지 않는다.
    XCTAssertFalse(FileManager.default.fileExists(
      atPath: home + "/Documents/QuickTalkWorkspace"))
  }

  func testSimilarNameIsNotMigrated() throws {
    try makeFolder("Documents/QuickTalkReportOld")
    var settings = QuickTalkSettings()
    settings.defaultReportFolder = "~/Documents/QuickTalkReportOld"

    XCTAssertFalse(WorkspaceFolder.migrate(settings: &settings, home: home))
    XCTAssertEqual(settings.defaultReportFolder, "~/Documents/QuickTalkReportOld")
  }

  func testAbsoluteLegacyPathIsMigrated() throws {
    let old = try makeFolder("Documents/QuickTalkReport")
    XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))

    var settings = QuickTalkSettings()
    settings.defaultReportFolder = old.path   // 사용자가 폴더 선택기로 고른 절대 경로
    XCTAssertTrue(WorkspaceFolder.migrate(settings: &settings, home: home))
    XCTAssertEqual(settings.defaultReportFolder, WorkspaceFolder.defaultPath)
  }

  func testIsLegacyPathMatchesOnlyLastComponent() {
    XCTAssertTrue(WorkspaceFolder.isLegacyPath("~/Documents/QuickTalkReport", home: home))
    XCTAssertTrue(WorkspaceFolder.isLegacyPath("/tmp/QuickTalkReport", home: home))
    XCTAssertFalse(WorkspaceFolder.isLegacyPath("~/Documents/QuickTalkReport/sub", home: home))
    XCTAssertFalse(WorkspaceFolder.isLegacyPath("~/Documents/QuickTalkReportOld", home: home))
  }
}
