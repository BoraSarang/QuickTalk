import XCTest
@testable import QuickTalkCore

/// 지난 작업 요약 (v0.41.2) — "지난주에 뭐 했지?"를 셸 없이 한 번에 답하기 위한 압축 요약.
///
/// 배경: 모델이 `history.json` 을 8번 읽어 승인 카드가 8번 떴다(2026-11-19).
/// 이 요약은 제목·마지막 질문·Job 결과만 담고, 원문 전체와 현재 대화는 뺀다.
final class PastWorkTests: XCTestCase {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func conversation(_ title: String, daysAgo: Double, question: String,
                            answer: String = "완료했습니다.",
                            id: UUID = UUID()) -> Conversation {
    let date = now.addingTimeInterval(-daysAgo * 86_400)
    return Conversation(
      id: id, title: title,
      turns: [Turn(role: .user, text: question, createdAt: date),
              Turn(role: .assistant, text: answer, createdAt: date)],
      updatedAt: date)
  }

  func testDigestExcludesCurrentConversation() {
    let current = conversation("지금", daysAgo: 0, question: "ㄴㄴㄴ")
    let other = conversation("볼륨", daysAgo: 1, question: "볼륨 스크립트 만들어줘")

    let text = PastWork.digest(conversations: [current, other], jobs: [],
                               days: 7, excluding: current.id, now: now)

    XCTAssertFalse(text.contains("ㄴㄴㄴ"), "현재 대화가 요약에 새면 자기 자신을 참고한다")
    XCTAssertTrue(text.contains("볼륨 스크립트"))
  }

  func testDigestKeepsOnlyTheWindow() {
    let old = conversation("한 달 전", daysAgo: 30, question: "예전 작업")
    let recent = conversation("이틀 전", daysAgo: 2, question: "최근 작업")

    let text = PastWork.digest(conversations: [old, recent], jobs: [], days: 7, now: now)

    XCTAssertFalse(text.contains("예전 작업"), "7일 밖 기록은 넣지 않는다")
    XCTAssertTrue(text.contains("최근 작업"))
  }

  func testDigestFiltersByQuery() {
    let volume = conversation("볼륨", daysAgo: 1, question: "볼륨 스크립트")
    let tts = conversation("TTS", daysAgo: 2, question: "목소리 복제")

    let text = PastWork.digest(conversations: [volume, tts], jobs: [],
                               days: 7, query: "볼륨", now: now)

    XCTAssertTrue(text.contains("볼륨 스크립트"))
    XCTAssertFalse(text.contains("목소리 복제"))
  }

  func testDigestIncludesJobsWithStatusAndFiles() {
    let job = Job(title: "볼륨 스크립트", goal: "볼륨 조절 스크립트",
                  steps: ["작성", "실행"], conversationID: UUID(),
                  workspacePath: "/tmp/job", status: .completed,
                  createdAt: now.addingTimeInterval(-6 * 86_400),
                  updatedAt: now.addingTimeInterval(-5 * 86_400),
                  finishedAt: now.addingTimeInterval(-5 * 86_400),
                  resultSummary: "volume-control.sh 완성",
                  artifactPaths: ["volume-control.sh"])

    let text = PastWork.digest(conversations: [], jobs: [job], days: 7, now: now)

    XCTAssertTrue(text.contains("완료"))
    XCTAssertTrue(text.contains("볼륨 스크립트"))
    XCTAssertTrue(text.contains("volume-control.sh 완성"))
    XCTAssertTrue(text.contains("파일 1개"), "산출물 개수는 '어디까지 했는지'의 핵심이다")
  }

  func testPlanProposalIsNotShownAsAJobResult() {
    // 2026-11-15 볼륨 Job 의 resultSummary 는 결과가 아니라 "계획을 제안했습니다"였다.
    let job = Job(title: "볼륨 스크립트", steps: ["작성"], conversationID: UUID(),
                  workspacePath: "/tmp/job", status: .completed,
                  updatedAt: now.addingTimeInterval(-86_400),
                  finishedAt: now.addingTimeInterval(-86_400),
                  resultSummary: "계획을 제안했습니다. 아래 [실행]을 누르면 이 순서로 진행합니다.")

    let text = PastWork.digest(conversations: [], jobs: [job], days: 7, now: now)

    XCTAssertTrue(text.contains("볼륨 스크립트"))
    XCTAssertFalse(text.contains("계획을 제안했습니다"), "계획 제안은 결과가 아니다")
  }

  func testQueuedJobIsNotPastWork() {
    let job = Job(title: "대기 작업", steps: ["실행"], conversationID: UUID(),
                  workspacePath: "/tmp/job", status: .queued,
                  updatedAt: now.addingTimeInterval(-3_600))

    let text = PastWork.digest(conversations: [], jobs: [job], days: 7, now: now)

    XCTAssertFalse(text.contains("대기 작업"))
    XCTAssertTrue(text.contains("없습니다"))
  }

  func testDigestCapsLengthAndSaysHowManyWereSkipped() {
    let conversations = (0..<20).map { index in
      conversation("대화 \(index)", daysAgo: Double(index) / 24,
                   question: String(repeating: "아주 긴 질문 ", count: 8))
    }

    let text = PastWork.digest(conversations: conversations, jobs: [], days: 7, now: now)

    XCTAssertLessThanOrEqual(text.count, PastWork.maximumCharacters + 80,
                             "모델에 넘기는 요약은 1,800자 안쪽이어야 한다")
    XCTAssertTrue(text.contains("외"), "잘린 항목 수를 알려 준다")
  }

  func testEmptyDigest() {
    let text = PastWork.digest(conversations: [], jobs: [], days: 7, now: now)
    XCTAssertTrue(text.contains("없습니다"))
  }
}
