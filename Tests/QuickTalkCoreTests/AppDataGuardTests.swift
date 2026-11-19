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

  // MARK: - 같은 턴의 읽기 승인 재사용 (v0.41.2)

  func testReadApprovalIsReusedOnlyForReadOnlyProtectedCommands() {
    let command = "cat \(home)/Library/Application Support/QuickTalk/history.json"

    XCTAssertTrue(AppDataGuard.canReuseReadApproval(
      .allow(.read), command: command, readApproved: true, home: home),
      "이번 턴에 저장 데이터 읽기를 승인했으면 같은 읽기는 다시 묻지 않는다")

    XCTAssertFalse(AppDataGuard.canReuseReadApproval(
      .allow(.read), command: command, readApproved: false, home: home),
      "처음 읽기는 승인 카드를 띄운다")

    XCTAssertFalse(AppDataGuard.canReuseReadApproval(
      .allow(.write(path: "/tmp")), command: command, readApproved: true, home: home),
      "쓰기는 승인을 재사용하지 않는다")

    XCTAssertFalse(AppDataGuard.canReuseReadApproval(
      .allow(.read), command: "ls -la", readApproved: true, home: home),
      "보호 데이터가 아닌 명령은 이 경로와 무관하다")

    let ask = AgentApprovalRequest(command: command, level: .read, risk: .normal,
                                   capability: .read, writablePaths: [],
                                   reason: "정책이 매번 확인")
    XCTAssertFalse(AppDataGuard.canReuseReadApproval(
      .ask(ask), command: command, readApproved: true, home: home),
      "사용자의 '읽기: 매번 확인' 설정을 덮지 않는다")
  }

  func testReadApprovalDoesNotExtendToSecretsOrSettings() {
    // 한 번의 승인이 앱 데이터 폴더 전체로 번지면 안 된다 — 비밀 키·설정은 매번 묻는다.
    for name in ["secrets.json", "settings.json", "jobs.json", "memory.json"] {
      let command = "cat \(home)/Library/Application Support/QuickTalk/\(name)"
      XCTAssertFalse(AppDataGuard.canReuseReadApproval(
        .allow(.read), command: command, readApproved: true, home: home),
        "\(name) 은 승인 1회를 재사용하지 않는다")
      XCTAssertFalse(AppDataGuard.allowsBatchedRead(command))
    }
    XCTAssertTrue(AppDataGuard.allowsBatchedRead(
      "cat \(home)/Library/Application Support/QuickTalk/history.json"))
  }

  func testListingTheAppDataFolderArmsBatchedReads() {
    // 2026-11-19 실제 흐름: 첫 명령이 `date; ls -lh …/QuickTalk/` 였고,
    // 그 뒤 history.json 읽기 7건이 각각 카드를 띄웠다. 목록 승인 1회로 묶는다.
    let listing = "date \"+%Y-%m-%d %H:%M\"; ls -lh \"\(home)/Library/Application Support/QuickTalk/\" 2>/dev/null | head -30"
    XCTAssertTrue(AppDataGuard.armsBatchedRead(listing, home: home))

    let cdThenRead = "cd \"\(home)/Library/Application Support/QuickTalk\"; python3 -c \"import json; json.load(open('history.json'))\""
    XCTAssertTrue(AppDataGuard.armsBatchedRead(cdThenRead, home: home))
  }

  func testContentReadsOtherThanHistoryDoNotArmBatchedReads() {
    // `grep -r … *` 는 secrets.json 까지 읽을 수 있다 — 무장하지 않는다.
    let grep = "grep -r token \"\(home)/Library/Application Support/QuickTalk/\""
    XCTAssertFalse(AppDataGuard.armsBatchedRead(grep, home: home))

    let secrets = "cat \"\(home)/Library/Application Support/QuickTalk/secrets.json\""
    XCTAssertFalse(AppDataGuard.armsBatchedRead(secrets, home: home))

    let clipboard = "ls \"\(home)/Library/Application Support/QuickTalk/clip/\""
    XCTAssertFalse(AppDataGuard.armsBatchedRead(clipboard, home: home))
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
