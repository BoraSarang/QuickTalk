import XCTest
@testable import QuickTalkCore

// [FEATURE] 쓰기 경로 스코프 테스트 (PLAN_v0.18 v0.19)
//
// "이 폴더 허용" 은 그 폴더 **안에서만** 유효해야 한다 — 옆 폴더나 상위 폴더로 새면
// 승인 한 번으로 홈 전체를 쓸 수 있게 된다.

final class WriteScopeTests: XCTestCase {
  private let home = NSHomeDirectory()

  func testNormalizeExpandsHomeAndDots() {
    XCTAssertEqual(WriteScope.normalize("~/Documents"), home + "/Documents")
    XCTAssertEqual(WriteScope.normalize("~/Documents/../Downloads"), home + "/Downloads")
    XCTAssertEqual(WriteScope.normalize(home + "/Documents/"), home + "/Documents")
    XCTAssertEqual(WriteScope.normalize(""), "")
  }

  func testContainsRespectsFolderBoundary() {
    let scope = home + "/Documents"
    XCTAssertTrue(WriteScope.contains(scope, in: scope))
    XCTAssertTrue(WriteScope.contains(scope + "/a.txt", in: scope))
    XCTAssertTrue(WriteScope.contains(scope + "/sub/b.txt", in: scope))
    XCTAssertFalse(WriteScope.contains(scope + "2/a.txt", in: scope), "접두어만 같은 옆 폴더로 새면 안 된다")
    XCTAssertFalse(WriteScope.contains(home + "/Downloads/a.txt", in: scope))
    XCTAssertFalse(WriteScope.contains(home, in: scope), "상위 폴더는 범위 밖")
  }

  func testApprovedScopes() {
    let scopes = [home + "/Documents", home + "/Downloads"]
    XCTAssertTrue(WriteScope.isApproved(home + "/Documents/a.txt", scopes: scopes))
    XCTAssertTrue(WriteScope.isApproved("~/Downloads/x", scopes: scopes))
    XCTAssertFalse(WriteScope.isApproved(home + "/Desktop/x", scopes: scopes))
    XCTAssertFalse(WriteScope.isApproved(home + "/Documents/a.txt", scopes: []))
  }

  func testScopeForFileIsParentFolder() throws {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-scope-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    XCTAssertEqual(WriteScope.scope(for: dir.path), dir.path, "폴더는 그 폴더가 범위")
    XCTAssertEqual(WriteScope.scope(for: dir.appendingPathComponent("new.txt").path), dir.path,
                   "파일은 상위 폴더가 범위(새로 만들어야 한다)")
  }

  // MARK: - 명령에서 경로 뽑기

  func testCandidatePathsFromRedirect() {
    let paths = WriteScope.candidatePaths(in: "echo hi > ~/Documents/a.txt")
    XCTAssertEqual(paths, [home + "/Documents/a.txt"])
  }

  func testCandidatePathsSkipsFlagsAndURLs() {
    let paths = WriteScope.candidatePaths(in: "curl -o ~/Downloads/x.zip https://example.com/x.zip")
    XCTAssertEqual(paths, [home + "/Downloads/x.zip"])
  }

  func testCandidatePathsHandlesQuotedSpaces() {
    let paths = WriteScope.candidatePaths(in: "rm -rf \"~/Documents/my notes\"")
    XCTAssertEqual(paths, [home + "/Documents/my notes"])
  }

  func testCandidatePathsSkipsSystemPathsAndHome() {
    let paths = WriteScope.candidatePaths(in: "rm -rf /usr/local/x ~")
    XCTAssertEqual(paths, [])
  }

  func testCandidatePathsResolvesRelativeToCwd() {
    let paths = WriteScope.candidatePaths(in: "mkdir out/file.txt", cwd: "/tmp/work")
    XCTAssertEqual(paths, ["/tmp/work/out/file.txt"])
  }
}
