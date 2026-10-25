import XCTest
@testable import QuickTalkCore

// [FEATURE] 시스템 지식 · 터미널 인계 (v0.22 · v0.20)
//
//   · `SystemKnowledge` 는 **설정에서 읽은 사실만** 주입한다(비밀·키는 절대 넣지 않는다).
//   · `TerminalHandoff` 는 앱이 실행하지 않을 명령을 실행 가능한 스크립트로 만든다.
//     앱은 그 파일을 **열기만** 한다 — 실행 여부는 사용자가 정한다.

final class SystemKnowledgeTests: XCTestCase {
  func testReportsActualSettings() {
    var settings = QuickTalkSettings()
    settings.agentToolsEnabled = true
    settings.agentPolicy.autoAcceptAll = true
    settings.agentPolicy.allowCritical = false
    settings.agentTimeoutSeconds = 120
    settings.windowAttachmentEnabled = false
    let text = SystemKnowledge.text(settings: settings)
    XCTAssertTrue(text.contains("도우미 도구: 켜짐"))
    XCTAssertTrue(text.contains("전역 자동 수락: 켜짐"))
    XCTAssertTrue(text.contains("치명적 명령: 차단"))
    XCTAssertTrue(text.contains("실행 제한 시간: 120초"))
    XCTAssertTrue(text.contains("창 연결(읽기 전용): 꺼짐"))
    XCTAssertTrue(text.contains("터미널로 넘긴다"))
  }

  func testReflectsDisabledTools() {
    var settings = QuickTalkSettings()
    settings.agentToolsEnabled = false
    let text = SystemKnowledge.text(settings: settings)
    XCTAssertTrue(text.contains("도우미 도구: 꺼짐"))
    // 도구가 꺼져 있으면 권한 세부는 쓰지 않는다
    XCTAssertFalse(text.contains("권한 정책"))
  }

  func testNeverIncludesSecrets() {
    var settings = QuickTalkSettings()
    // 비밀은 SecretStore 에 있고 설정에는 항목 이름만 둔다 — 그 이름조차 지식 블록에 쓰지 않는다.
    if !settings.providers.isEmpty {
      settings.providers[0].secretID = "sk-test-SECRET-1234567890"
    }
    let text = SystemKnowledge.text(settings: settings)
    XCTAssertFalse(text.contains("SECRET"))
    XCTAssertFalse(text.contains("sk-test"))
  }

  func testStableAcrossLanguages() {
    // 지식 블록은 모델에게 주는 문장이라 언어와 무관하게 항상 채워져야 한다.
    let text = SystemKnowledge.text(settings: QuickTalkSettings())
    XCTAssertFalse(text.isEmpty)
    XCTAssertTrue(text.contains("QuickTalk"))
    XCTAssertTrue(text.contains("Application Support/QuickTalk"))
  }
}

final class TerminalHandoffTests: XCTestCase {
  func testHandoffOnlyForSystemWritesAndElevation() {
    XCTAssertTrue(TerminalHandoff.shouldHandoff(capability: .elevated))
    // 파일이면 **상위 폴더**가 범위 — /etc 는 시스템 루트라 넘긴다.
    XCTAssertTrue(TerminalHandoff.shouldHandoff(capability: .write(path: "/etc/hosts")))
    XCTAssertTrue(TerminalHandoff.shouldHandoff(capability: .write(path: "/usr/bin/tool")))
    XCTAssertTrue(TerminalHandoff.shouldHandoff(capability: .write(path: "/Library/LaunchDaemons/x.plist")))
    // 도구 설치 경로(홈브루·로컬 bin)는 승인하면 앱이 연다 — 터미널로 밀지 않는다.
    XCTAssertFalse(TerminalHandoff.shouldHandoff(
      capability: .write(path: "/opt/homebrew/Cellar/wget/1.0/bin/wget")))
    XCTAssertFalse(TerminalHandoff.shouldHandoff(capability: .write(path: "/usr/local/bin/tool")))
    // 사용자 홈·임시 폴더는 정상 쓰기
    XCTAssertFalse(TerminalHandoff.shouldHandoff(
      capability: .write(path: NSHomeDirectory() + "/Documents/a.txt")))
    XCTAssertFalse(TerminalHandoff.shouldHandoff(
      capability: .write(path: FileManager.default.temporaryDirectory.appendingPathComponent("a.txt").path)))
    // 다른 사용자 홈은 시스템 영역으로 본다
    XCTAssertTrue(TerminalHandoff.shouldHandoff(capability: .write(path: "/Users/someone/a.txt")))
    XCTAssertFalse(TerminalHandoff.shouldHandoff(capability: .read))
    XCTAssertFalse(TerminalHandoff.shouldHandoff(capability: .network))
  }

  func testScriptCarriesCommandAndWarning() {
    let script = TerminalHandoff.script(command: "sudo -v")
    XCTAssertTrue(script.hasPrefix("#!/bin/zsh"))
    XCTAssertTrue(script.contains("sudo -v"))
    XCTAssertTrue(script.contains("앱이 실행하지 않았습니다"))
    XCTAssertTrue(script.contains("exit $status"))
  }

  func testFileNameSanitizesAndKeepsSuffix() {
    let name = TerminalHandoff.fileName(command: "echo a/b > /etc/hosts\nrm -rf ~")
    XCTAssertTrue(name.hasSuffix(".command"))
    XCTAssertFalse(name.contains("/"))
    XCTAssertFalse(name.contains("\n"))
    XCTAssertFalse(name.contains(" "))
    XCTAssertTrue(name.hasPrefix("QuickTalk-"))
    XCTAssertLessThanOrEqual(name.count, 80)
  }

  func testFileNameHandlesEmptyCommand() {
    XCTAssertTrue(TerminalHandoff.fileName(command: "   ").hasSuffix("-command.command"))
  }

  func testNotesExplainWhy() {
    XCTAssertTrue(TerminalHandoff.note(capability: .elevated).contains("상승 권한"))
    XCTAssertTrue(TerminalHandoff.note(capability: .write(path: "/etc/hosts"))
      .contains("시스템 전역 경로"))
    XCTAssertTrue(TerminalHandoff.note(capability: .read).contains("터미널"))
  }
}
