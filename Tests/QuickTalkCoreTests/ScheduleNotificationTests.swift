import XCTest
@testable import QuickTalkCore

/// v0.26 5단계 — 알림 문구·알림 여부.
/// 실제 배너는 `NotificationService`(App)가 띄우고, 여기서는 **순수 문구 규칙**만 검증한다.
final class ScheduleNotificationTests: XCTestCase {

  // MARK: - 승인 대기

  func testApprovalUsesPersonaTitleAndTaskSubtitle() {
    let text = ScheduleNotificationText.approval(personaName: "돌쇠", taskTitle: "아침 뉴스",
                                                 reason: "파일을 씁니다")
    XCTAssertEqual(text.title, Lf("%@ — 승인 대기", "돌쇠"))
    XCTAssertEqual(text.subtitle, "아침 뉴스")
    XCTAssertTrue(text.body.hasPrefix("파일을 씁니다 — "), text.body)
    XCTAssertTrue(text.body.contains(L("대화를 열어 승인하거나 거부하세요.")), text.body)
  }

  func testApprovalWithoutPersonaUsesDefaultLabel() {
    let text = ScheduleNotificationText.approval(personaName: nil, taskTitle: nil, reason: "확인")
    XCTAssertEqual(text.title, Lf("%@ — 승인 대기", L("기본(비서 없음)")))
    XCTAssertNil(text.subtitle)
  }

  func testApprovalBodyIsClipped() {
    let long = String(repeating: "가", count: 400)
    let text = ScheduleNotificationText.approval(personaName: "돌쇠", taskTitle: "t", reason: long)
    XCTAssertEqual(text.body.count, ScheduleNotificationText.bodyLimit + 1, "상한 + …")
    XCTAssertTrue(text.body.hasSuffix("…"))
  }

  // MARK: - 실행 종료

  func testSuccessShowsReportFile() {
    let text = ScheduleNotificationText.run(personaName: "돌쇠", taskTitle: "아침 뉴스",
                                            status: .succeeded,
                                            fileName: "2026-11-04 아침 뉴스.md", reason: nil)
    XCTAssertEqual(text.title, Lf("%@ — 완료", "돌쇠"))
    XCTAssertEqual(text.subtitle, "아침 뉴스")
    XCTAssertEqual(text.body, Lf("리포트: %@", "2026-11-04 아침 뉴스.md"))
  }

  func testFailureShowsReasonFirst() {
    let text = ScheduleNotificationText.run(personaName: nil, taskTitle: "뉴스",
                                            status: .failed, fileName: "x.md",
                                            reason: "AI 프로바이더가 설정되지 않았습니다.")
    XCTAssertEqual(text.title, Lf("%@ — 실패", L("기본(비서 없음)")))
    XCTAssertEqual(text.body, "AI 프로바이더가 설정되지 않았습니다.")
  }

  func testApprovalExpiryHasItsOwnTitle() {
    let text = ScheduleNotificationText.run(
      personaName: "졸쇠", taskTitle: "뉴스", status: .failed, fileName: nil,
      reason: L("승인 대기 시간(10분)이 만료되었습니다."))
    XCTAssertEqual(text.title, Lf("%@ — 승인 대기 만료", "졸쇠"))
    XCTAssertEqual(text.body, L("10분 안에 승인하지 않아 취소되었습니다. 다시 실행하세요."))
  }

  func testFailureWithoutReasonFallsBackToFile() {
    let text = ScheduleNotificationText.run(personaName: nil, taskTitle: "뉴스",
                                            status: .failed, fileName: "x.md", reason: "  ")
    XCTAssertEqual(text.body, Lf("리포트: %@", "x.md"))
  }

  func testEmptyBodiesWhenNothingToSay() {
    let text = ScheduleNotificationText.run(personaName: nil, taskTitle: "뉴스",
                                            status: .succeeded, fileName: nil, reason: nil)
    XCTAssertEqual(text.body, "")
  }

  // MARK: - 알림 여부

  func testNotifiesOnlyForTerminalTroubleOrSuccess() {
    XCTAssertTrue(ScheduleNotificationText.shouldNotify(.succeeded))
    XCTAssertTrue(ScheduleNotificationText.shouldNotify(.failed))
    XCTAssertTrue(ScheduleNotificationText.shouldNotify(.interrupted))
    // 사용자가 직접 취소했거나 아직 끝나지 않은 실행은 조용히 둔다.
    XCTAssertFalse(ScheduleNotificationText.shouldNotify(.cancelled))
    XCTAssertFalse(ScheduleNotificationText.shouldNotify(.missed))
    XCTAssertFalse(ScheduleNotificationText.shouldNotify(.running))
    XCTAssertFalse(ScheduleNotificationText.shouldNotify(.awaitingApproval))
  }
}
