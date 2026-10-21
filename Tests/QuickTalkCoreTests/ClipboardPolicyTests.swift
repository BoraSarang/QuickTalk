import XCTest
@testable import QuickTalkCore

/// 클립보드 스트립 정책 (PLAN_v0.12) — 만료 2분 · 최대 5개 · 민감 마스킹
final class ClipboardPolicyTests: XCTestCase {

  private func text(_ s: String, at date: Date = Date()) -> ClipboardItem {
    ClipboardItem(kind: .text, text: s, capturedAt: date)
  }

  // MARK: 만료 · 최대 개수

  func testExpiresAfterTTL() {
    let now = Date()
    var ring = ClipboardRing()
    ring.insert(text("방금 복사", at: now.addingTimeInterval(-10)), now: now)
    ring.insert(text("오래된 복사", at: now.addingTimeInterval(-200)), now: now)

    XCTAssertEqual(ring.items.count, 1)
    XCTAssertEqual(ring.items.first?.text, "방금 복사")
  }

  func testExpireReturnsRemovedCount() {
    let now = Date()
    var ring = ClipboardRing(items: [
      text("a", at: now.addingTimeInterval(-121)),
      text("b", at: now.addingTimeInterval(-5))
    ])
    XCTAssertEqual(ring.expire(now: now), 1)
    XCTAssertEqual(ring.items.map(\.text), ["b"])
  }

  func testKeepsOnlyFiveMostRecent() {
    let now = Date()
    var ring = ClipboardRing()
    for i in 1...7 {
      ring.insert(text("항목\(i)", at: now.addingTimeInterval(Double(i))), now: now.addingTimeInterval(Double(i)))
    }
    XCTAssertEqual(ring.items.count, ClipboardPolicy.maxItems)
    // 최신이 맨 앞
    XCTAssertEqual(ring.items.first?.text, "항목7")
    XCTAssertFalse(ring.items.contains { $0.text == "항목1" })
  }

  func testSameContentMovesToFrontWithoutDuplicating() {
    let now = Date()
    var ring = ClipboardRing()
    ring.insert(text("같은 내용", at: now.addingTimeInterval(-30)), now: now)
    ring.insert(text("다른 내용", at: now.addingTimeInterval(-20)), now: now)
    ring.insert(text("같은 내용", at: now.addingTimeInterval(-1)), now: now)

    XCTAssertEqual(ring.items.count, 2)
    XCTAssertEqual(ring.items.first?.text, "같은 내용")
  }

  // MARK: 남은 시간

  func testSecondsLeftCountsDown() {
    let now = Date()
    let item = text("x", at: now.addingTimeInterval(-30))
    XCTAssertEqual(ClipboardPolicy.secondsLeft(item, now: now), 90)
    XCTAssertFalse(ClipboardPolicy.isExpired(item, now: now))
    XCTAssertTrue(ClipboardPolicy.isExpired(item, now: now.addingTimeInterval(91)))
  }

  // MARK: 민감 판정 · 마스킹

  func testSensitivePatterns() {
    XCTAssertTrue(ClipboardPolicy.looksSensitive("password: hunter2"))
    XCTAssertTrue(ClipboardPolicy.looksSensitive("API_KEY=abcd"))
    XCTAssertTrue(ClipboardPolicy.looksSensitive("인증번호 123456"))
    XCTAssertTrue(ClipboardPolicy.looksSensitive("4111-1111-1111-1111"))
    XCTAssertTrue(ClipboardPolicy.looksSensitive(String(repeating: "a", count: 48)))
    XCTAssertFalse(ClipboardPolicy.looksSensitive("아아아아 안녕하세요"))
    XCTAssertFalse(ClipboardPolicy.looksSensitive("https://example.com/a-b-c"))
  }

  func testSensitiveItemIsMaskedUntilRevealed() {
    let item = ClipboardItem(kind: .text, text: "password: hunter2", isSensitive: true)
    XCTAssertEqual(ClipboardPolicy.displayText(item, revealed: false), "••••••••")
    XCTAssertEqual(ClipboardPolicy.displayText(item, revealed: true), "password: hunter2")
    // 민감하지 않은 항목은 그대로
    XCTAssertEqual(ClipboardPolicy.displayText(text("그냥 텍스트"), revealed: false), "그냥 텍스트")
  }

  // MARK: 링크 · 미리보기

  func testURLDetection() {
    XCTAssertTrue(ClipboardPolicy.looksLikeURL("https://example.com/x"))
    XCTAssertTrue(ClipboardPolicy.looksLikeURL("  http://a.b  "))
    XCTAssertFalse(ClipboardPolicy.looksLikeURL("example.com"))
    XCTAssertFalse(ClipboardPolicy.looksLikeURL("아아아"))
  }

  func testPreviewFlattensAndTruncates() {
    XCTAssertEqual(ClipboardPolicy.previewText("여러\n줄\t텍스트"), "여러 줄 텍스트")
    let long = ClipboardPolicy.previewText(String(repeating: "가", count: 80), limit: 10)
    XCTAssertEqual(long, String(repeating: "가", count: 10) + "…")
  }

  func testRemoveAndClear() {
    let now = Date()
    var ring = ClipboardRing()
    ring.insert(text("a", at: now), now: now)
    ring.insert(text("b", at: now), now: now)
    let id = ring.items.first!.id
    ring.remove(id)
    XCTAssertEqual(ring.items.map(\.text), ["a"])
    ring.removeAll()
    XCTAssertTrue(ring.items.isEmpty)
  }
}
