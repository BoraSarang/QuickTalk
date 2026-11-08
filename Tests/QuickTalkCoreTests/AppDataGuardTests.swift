import XCTest
@testable import QuickTalkCore

/// 앱 자기 데이터 보호 (2026-11-08) — 대화 기록·공통 메모리를 모델이 자동으로 읽지 못하게 한다.
///
/// 배경: `agent-audit.log` 2026-11-05 12:16Z 에 모델이 셸로 `history.json` 을 7회 읽어
/// 다른 대화의 내용을 답변에 끌어온 사례가 있었다. 공통 메모리(🧠)와 무관한 경로다.
final class AppDataGuardTests: XCTestCase {
  private let home = "/Users/tester"

  // MARK: - 경로 보호

  func testAppDataDirectoryIsProtected() {
    XCTAssertTrue(AppDataGuard.isProtected(path: AppDataGuard.appDataDirectory(home: home), home: home))
  }

  func testFilesUnderAppDataAreProtected() {
    let dir = AppDataGuard.appDataDirectory(home: home)
    XCTAssertTrue(AppDataGuard.isProtected(path: dir + "/history.json", home: home))
    XCTAssertTrue(AppDataGuard.isProtected(path: dir + "/memory.json", home: home))
    XCTAssertTrue(AppDataGuard.isProtected(path: dir + "/undo/snapshot.json", home: home))
  }

  func testTildePathIsProtected() {
    XCTAssertTrue(AppDataGuard.isProtected(path: "~/Library/Application Support/QuickTalk/history.json",
                                          home: home))
  }

  func testPreferencesPlistIsProtected() {
    XCTAssertTrue(AppDataGuard.isProtected(
      path: "~/Library/Preferences/com.borasarang.QuickTalk.plist", home: home))
  }

  func testProjectAndReportFoldersAreNotProtected() {
    XCTAssertFalse(AppDataGuard.isProtected(path: "/Users/lee/Documents/Apps/QuickTalk/README.md",
                                            home: home))
    XCTAssertFalse(AppDataGuard.isProtected(path: "~/Documents/QuickTalkReport/report.md", home: home))
  }

  /// 이름이 겹치는 **다른 폴더**(QuickTalkReport)를 보호 대상으로 오인하지 않는다.
  func testSiblingFolderWithSamePrefixIsNotProtected() {
    XCTAssertFalse(AppDataGuard.isProtected(
      path: "~/Library/Application Support/QuickTalkReport/report.md", home: home))
  }

  func testEmptyPathIsNotProtected() {
    XCTAssertFalse(AppDataGuard.isProtected(path: "", home: home))
  }

  // MARK: - 셸 명령

  func testCommandReadingHistoryIsDetected() {
    XCTAssertTrue(AppDataGuard.commandTouchesProtectedData(
      "cat \"\(home)/Library/Application Support/QuickTalk/history.json\"", home: home))
    XCTAssertTrue(AppDataGuard.commandTouchesProtectedData(
      "cat ~/Library/Application Support/QuickTalk/history.json", home: home))
    XCTAssertTrue(AppDataGuard.commandTouchesProtectedData(
      "cat $HOME/Library/Application Support/QuickTalk/memory.json", home: home))
  }

  /// Finder/터미널에서 흔한 **이스케이프된 공백** 표기도 같은 경로다.
  func testEscapedSpacePathIsDetected() {
    XCTAssertTrue(AppDataGuard.commandTouchesProtectedData(
      "cat ~/Library/Application\\ Support/QuickTalk/history.json", home: home))
  }

  func testDefaultsDomainIsDetected() {
    XCTAssertTrue(AppDataGuard.commandTouchesProtectedData(
      "defaults read com.borasarang.QuickTalk", home: home))
  }

  func testUnrelatedCommandsAreNotDetected() {
    XCTAssertFalse(AppDataGuard.commandTouchesProtectedData(
      "cat ~/Documents/QuickTalkReport/report.md", home: home))
    XCTAssertFalse(AppDataGuard.commandTouchesProtectedData(
      "cd /Users/lee/Documents/Apps/QuickTalk && git status", home: home))
    XCTAssertFalse(AppDataGuard.commandTouchesProtectedData("ls -la", home: home))
    XCTAssertFalse(AppDataGuard.commandTouchesProtectedData("", home: home))
  }

  func testSiblingFolderCommandIsNotDetected() {
    XCTAssertFalse(AppDataGuard.commandTouchesProtectedData(
      "ls ~/Library/Application Support/QuickTalkReport", home: home))
  }

  // MARK: - 정책 승격

  func testAutomaticAllowIsEscalatedToApproval() {
    let plan = AppDataGuard.guardedPlan(.allow(.read),
                                        command: "cat ~/Library/Application Support/QuickTalk/history.json",
                                        home: home)
    guard case .ask(let request) = plan else {
      return XCTFail("보호 데이터 접근은 승인 카드로 승격돼야 합니다")
    }
    XCTAssertFalse(request.allowsAlwaysAllow, "앱 데이터 접근은 '항상 허용'을 저장하면 안 됩니다")
    XCTAssertEqual(request.capability, .unprobed)
  }

  func testDenyIsKept() {
    let plan = AppDataGuard.guardedPlan(.deny("blocked"),
                                        command: "cat ~/Library/Application Support/QuickTalk/history.json",
                                        home: home)
    XCTAssertEqual(plan, .deny("blocked"))
  }

  func testExistingAskBecomesProtectedApproval() {
    let request = AgentApprovalRequest(command: "cat history", level: .write, risk: .important,
                                       capability: .write(path: "/tmp/history"), writablePaths: ["/tmp"],
                                       reason: "ask")
    let plan = AppDataGuard.guardedPlan(.ask(request),
                                        command: "cat ~/Library/Application Support/QuickTalk/history.json",
                                        home: home)
    guard case .ask(let guarded) = plan else {
      return XCTFail("기존 확인 요청은 승인 카드로 유지돼야 합니다")
    }
    XCTAssertEqual(guarded.level, .write, "권한 단계는 정책 판정을 그대로 둔다")
    XCTAssertEqual(guarded.writablePaths, ["/tmp"], "승인 범위는 잃지 않는다")
    XCTAssertFalse(guarded.allowsAlwaysAllow)
    XCTAssertNotEqual(guarded.reason, "ask", "앱 데이터 접근 사유로 바뀐다")
  }

  func testUnrelatedCommandPlanIsUnchanged() {
    let plan = AppDataGuard.guardedPlan(.allow(.read), command: "ls -la", home: home)
    XCTAssertEqual(plan, .allow(.read))
  }

  /// 정책이 "항상 허용 + 전역 자동 수락"이어도 앱 데이터는 승인 카드로 승격된다.
  func testAutoAcceptPolicyStillAsksForAppData() {
    var policy = AgentPolicy()
    policy.readPolicy = .alwaysAllow
    policy.executePolicy = .alwaysAllow
    policy.autoAcceptAll = true
    let command = "cat ~/Library/Application Support/QuickTalk/history.json"
    let plan = PolicyEngine.plan(command: command, policy: policy, approvedScopes: [])
    guard case .allow = plan else {
      return XCTFail("정책은 이 명령을 자동 허용해야 합니다: \(plan)")
    }
    guard case .ask(let request) = AppDataGuard.guardedPlan(plan, command: command, home: home) else {
      return XCTFail("앱 데이터 접근은 승인 카드로 승격돼야 합니다")
    }
    XCTAssertFalse(request.allowsAlwaysAllow)
  }
}
