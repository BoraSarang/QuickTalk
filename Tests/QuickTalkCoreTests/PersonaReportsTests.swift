import XCTest
@testable import QuickTalkCore

final class PersonaReportsTests: XCTestCase {
  func testSanitizesName() {
    XCTAssertEqual(PersonaReports.sanitize("  개발/e:팀  "), "개발 e 팀")
    XCTAssertEqual(PersonaReports.sanitize("a   b"), "a b")
    XCTAssertEqual(PersonaReports.sanitize(". . ."), "")
    XCTAssertEqual(PersonaReports.sanitize(String(repeating: "가", count: 40)).count,
                   PersonaReports.folderNameLimit)
  }

  func testFolderUsesPersonaSubfolderByDefault() {
    var s = QuickTalkSettings()
    s.defaultReportFolder = "/tmp/qt-reports"
    let persona = Persona(name: "개발e")
    XCTAssertEqual(PersonaReports.folder(settings: s, persona: persona),
                   "/tmp/qt-reports/개발e")
  }

  func testExplicitFolderIsRespectedAsIs() {
    var s = QuickTalkSettings()
    s.defaultReportFolder = "/tmp/qt-reports"
    let persona = Persona(name: "개발e", reportFolder: "~/CustomReports/dev")
    let path = PersonaReports.folder(settings: s, persona: persona)
    XCTAssertEqual(path, (("~/CustomReports/dev") as NSString).expandingTildeInPath)
    XCTAssertFalse(path.hasSuffix("/개발e"))
  }

  func testNoPersonaUsesRoot() {
    var s = QuickTalkSettings()
    s.defaultReportFolder = "/tmp/qt-reports"
    XCTAssertEqual(PersonaReports.folder(settings: s, persona: nil), "/tmp/qt-reports")
  }

  func testDuplicateNamesGetStableIDSuffix() {
    let a = Persona(name: "개발")
    let b = Persona(name: "개발")
    let nameA = PersonaReports.folderName(for: a, all: [a, b])
    let nameB = PersonaReports.folderName(for: b, all: [a, b])
    XCTAssertNotEqual(nameA, nameB)
    XCTAssertTrue(nameA.hasPrefix("개발-"))
    XCTAssertTrue(nameB.hasPrefix("개발-"))
    // 순서가 바뀌어도 같은 결과
    XCTAssertEqual(nameA, PersonaReports.folderName(for: a, all: [b, a]))
  }

  func testEnsureFolderCreatesDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-reports-\(UUID().uuidString)").path
    defer { try? FileManager.default.removeItem(atPath: root) }
    var s = QuickTalkSettings()
    s.defaultReportFolder = root
    let persona = Persona(name: "테크충")
    let url = try XCTUnwrap(PersonaReports.ensureFolder(settings: s, persona: persona))
    XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    XCTAssertEqual(url.lastPathComponent, "테크충")
  }

  func testSharedExplicitPeersDetected() {
    let a = Persona(name: "A", reportFolder: "/tmp/shared")
    let b = Persona(name: "B", reportFolder: "/tmp/shared")
    let c = Persona(name: "C")
    XCTAssertEqual(PersonaReports.sharedExplicitPeers(persona: a, all: [a, b, c]).map(\.id),
                   [b.id])
    XCTAssertTrue(PersonaReports.sharedExplicitPeers(persona: c, all: [a, b, c]).isEmpty)
  }
}
