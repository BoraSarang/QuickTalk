import XCTest
@testable import QuickTalkCore

/// v0.41 규칙 엔진 — **정답 문장 오탐 0**과 경계·안전 필터를 고정한다.
final class ProofreadTests: XCTestCase {
  private func issues(_ text: String, ignoring: Set<String> = []) -> [ProofreadIssue] {
    ProofreadEngine.check(text, ignoring: ignoring).issues
  }

  private func corrected(_ text: String) -> String {
    ProofreadEngine.check(text).corrected
  }

  // MARK: - 사전

  func testSpellingDictionary() {
    let cases: [(String, String)] = [
      ("몇일", "며칠"),
      ("웬지 모르게", "왠지 모르게"),
      ("오랫만이야", "오랜만이야"),
      ("역활이 중요해", "역할이 중요해"),
      ("댓가를 치렀다", "대가를 치렀다"),
      ("설겆이 좀 해", "설거지 좀 해"),
      ("띄워쓰기 확인", "띄어쓰기 확인"),
      ("안되요", "안 돼요"),
      ("어떻해", "어떡해"),
      ("뵈요", "봬요"),
      ("있슴", "있음"),
      ("했읍니다", "했습니다")
    ]
    for (wrong, right) in cases {
      let result = ProofreadEngine.check(wrong)
      XCTAssertEqual(result.issues.count, 1, "\(wrong) — 기대 1건, 실제 \(result.issues)")
      XCTAssertEqual(result.corrected, right, wrong)
    }
  }

  func testSpellingEndings() {
    XCTAssertEqual(corrected("할께요"), "할게요")
    XCTAssertEqual(corrected("내일 갈께"), "내일 갈게")
    XCTAssertEqual(corrected("제가 드릴께요"), "제가 드릴게요")
    XCTAssertEqual(corrected("할려고 했어"), "하려고 했어")
    XCTAssertEqual(corrected("볼려면 가"), "보려면 가")
  }

  /// 겹치는 규칙은 **가장 긴 하나**만 남는다(`안되요` + `되요` → 1건).
  func testOverlapKeepsLongestRule() {
    let list = issues("안되요")
    XCTAssertEqual(list.count, 1)
    XCTAssertEqual(list.first?.original, "안되요")
    XCTAssertEqual(list.first?.replacement, "안 돼요")
  }

  // MARK: - 띄어쓰기

  func testSpacingPatterns() {
    let cases: [(String, String)] = [
      ("이번주에 만나", "이번 주에 만나"),
      ("다음주말", "다음 주말"),
      ("몇개 필요해", "몇 개 필요해"),
      ("몇시에 갈까", "몇 시에 갈까"),
      ("한달 뒤", "한 달 뒤"),
      ("잘부탁드립니다", "잘 부탁드립니다"),
      ("부탁 드릴게요", "부탁드릴게요"),
      ("연락 드리겠습니다", "연락드리겠습니다"),
      ("할때 알려줘", "할 때 알려줘"),
      ("할줄알아", "할 줄알아"),
      ("할거야", "할 거야"),
      ("할수있어", "할 수있어")
    ]
    for (input, expected) in cases {
      XCTAssertEqual(corrected(input), expected, input)
    }
  }

  /// `수록`·`줄기`·`거리`·`한때`·`그때` 는 건드리지 않는다.
  func testSpacingBoundaries() {
    let untouched = [
      "할수록 힘들다",
      "볼수록 예쁘다",
      "줄기세포 연구",
      "볼거리가 많다",
      "한때 유행했다",
      "그때는 몰랐어",
      "이때가 좋아",
      "저때보다 낫다"
    ]
    for text in untouched {
      XCTAssertTrue(issues(text).isEmpty, "오탐: \(text) → \(issues(text))")
    }
  }

  // MARK: - 안전 필터

  func testProtectedRangesAreIgnored() {
    // 보호 구간은 **그대로** 남는다.
    let cases: [(String, String)] = [
      ("https://example.com/몇일?q=할께", "https://example.com/몇일?q=할께"),
      ("www.example.com/몇일", "www.example.com/몇일"),
      ("메일은 foo.bar@example.com 이야", "foo.bar@example.com"),
      ("`몇일` 이라고 쓰면 안 돼", "`몇일`"),
      ("파일은 ~/Documents/몇일.txt 야", "~/Documents/몇일.txt"),
      ("/Users/lee/몇일.md 열어줘", "/Users/lee/몇일.md")
    ]
    for (text, protected) in cases {
      let result = ProofreadEngine.check(text)
      XCTAssertTrue(result.corrected.contains(protected),
                    "보호 구간이 바뀌었습니다: \(text) → \(result.corrected)")
    }
    XCTAssertTrue(issues("https://example.com/몇일").isEmpty)
    XCTAssertTrue(issues("`몇일`").isEmpty)
  }

  func testShortOrNonKoreanTextIsSkipped() {
    XCTAssertTrue(issues("").isEmpty)
    XCTAssertTrue(issues("hello world").isEmpty)
    XCTAssertTrue(issues("할").isEmpty)          // 한글 음절 1자
    XCTAssertTrue(issues("몇일").count == 1)     // 2자
    let long = String(repeating: "몇일 ", count: 4_000)   // 10,000자 초과
    XCTAssertGreaterThan(long.utf16.count, ProofreadEngine.maximumLength)
    XCTAssertTrue(issues(long).isEmpty)
  }

  /// 정답 문장은 그대로 — 카드가 뜨지 않아야 한다.
  func testCorrectSentencesAreClean() {
    let corpus = [
      "이번 주말에 시간 괜찮아?",
      "할 수 있을 것 같아.",
      "몇 시에 만날까?",
      "몇 명이 오는지 알려 줘.",
      "잘 부탁드립니다.",
      "부탁드릴게요.",
      "연락드리겠습니다.",
      "말씀드리기 어렵네요.",
      "그때는 몰랐어.",
      "한때 유행했던 노래야.",
      "금세 끝났다.",
      "줄기세포 연구를 해.",
      "어떻게 해야 할지 모르겠어.",
      "1,000원입니다.",
      "좋아요!",
      "정말요?",
      "내일 볼게요.",
      "회의는 오후 3시에 시작합니다.",
      "줄을 서 주세요.",
      "알겠습니다."
    ]
    for text in corpus {
      let result = ProofreadEngine.check(text)
      XCTAssertTrue(result.isClean, "오탐: \(text) → \(result.issues.map { "\($0.original)→\($0.replacement)" })")
    }
  }

  // MARK: - 문장부호

  func testPunctuationSpacing() {
    XCTAssertEqual(corrected("안녕 , 반가워 !"), "안녕, 반가워!")
    XCTAssertEqual(corrected("정말 ?"), "정말?")
    XCTAssertEqual(corrected("1,000원"), "1,000원")
    XCTAssertEqual(corrected("기다릴게요 ..."), "기다릴게요 ...")
  }

  // MARK: - 적용 순서·멱등성

  func testReverseApplicationKeepsOffsets() {
    let input = "몇일 이번주에 할께요"
    let result = ProofreadEngine.check(input)
    XCTAssertEqual(result.corrected, "며칠 이번 주에 할게요")
    XCTAssertEqual(result.issues.count, 3)
    // 위치는 **원문** 기준 오름차순
    XCTAssertEqual(result.issues.map(\.location), result.issues.map(\.location).sorted())
    XCTAssertEqual(result.issues.map(\.original), ["몇일", "이번주", "할께"])
  }

  func testIdempotent() {
    let inputs = ["몇일 이번주에 할께요", "안되요 몇개 필요해", "잘부탁드립니다. 몇시에 갈까요"]
    for input in inputs {
      let once = corrected(input)
      XCTAssertTrue(ProofreadEngine.check(once).isClean, "두 번째 검사에서 또 걸림: \(once)")
    }
  }

  func testIgnoredExpressionsAreSkipped() {
    XCTAssertEqual(issues("몇일", ignoring: ["몇일"]).count, 0)
    XCTAssertEqual(issues("몇일 이번주", ignoring: ["몇일"]).count, 1)
    // 문장부호 규칙의 원문에는 앞 공백이 붙는다(" ,") — 오타 노트는 다듬은 키를 저장한다.
    XCTAssertEqual(issues("안녕 , 반가워", ignoring: [","]).count, 0)
  }

  func testEmptyReplacementNeverHappens() {
    for text in ["부탁드립니다", "연락드릴게요", "말씀드리겠습니다"] {
      XCTAssertTrue(issues(text).isEmpty, text)
    }
  }

  // MARK: - 성능

  /// 10,000자 상한에서도 전송을 붙잡지 않는다(디버그 빌드 여유 포함 60ms).
  func testPerformanceOnLongText() {
    let sentence = "이번주에 몇일까지 할수있어? 할께요. "
    let text = String(repeating: sentence, count: 10_000 / sentence.count)
    XCTAssertLessThanOrEqual(text.utf16.count, ProofreadEngine.maximumLength)
    let start = Date()
    let result = ProofreadEngine.check(text)
    let elapsed = Date().timeIntervalSince(start) * 1000
    XCTAssertFalse(result.issues.isEmpty)
    XCTAssertLessThan(elapsed, 60, "10,000자 검사 \(String(format: "%.1f", elapsed))ms")
    print("[proofread] \(text.count)자 — \(String(format: "%.2f", result.elapsedMilliseconds))ms, \(result.issues.count)건")
  }

  func testIssueLimit() {
    let text = String(repeating: "이번주 ", count: 100)
    XCTAssertLessThanOrEqual(issues(text).count, ProofreadEngine.maximumIssues)
  }
}
