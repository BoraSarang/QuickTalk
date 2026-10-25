import XCTest
@testable import QuickTalkCore

// [FEATURE] 스트리밍 실행 · 중단 (v0.20)
//
// 계약
//   · 출력이 오는 대로 `onOutput` 으로 흘러간다(카드가 실시간으로 보여 준다).
//   · `SandboxCancellation` 으로 밖에서 멈출 수 있다 — 프로세스가 실제로 죽는다.
//   · 중단·시간 초과는 **성공으로 위장하지 않는다**(exit != 0 + 사유).

/// IO 스레드에서 호출되는 콜백을 모으는 작은 상자.
private final class Chunks: @unchecked Sendable {
  private let lock = NSLock()
  private var values: [String] = []

  func append(_ text: String) {
    lock.lock()
    values.append(text)
    lock.unlock()
  }

  var all: String {
    lock.lock()
    defer { lock.unlock() }
    return values.joined()
  }

  var count: Int {
    lock.lock()
    defer { lock.unlock() }
    return values.count
  }
}

final class StreamingExecutionTests: XCTestCase {
  func testStreamsOutputWhileRunning() {
    let chunks = Chunks()
    let result = SandboxRunner.runStreaming(
      "printf 'a\\nb\\nc\\n'",
      profile: SandboxRunner.readOnlyProfile(),
      timeout: 10,
      onOutput: { chunks.append($0) })
    XCTAssertTrue(result.succeeded, result.combined)
    XCTAssertEqual(result.stdout, "a\nb\nc\n")
    XCTAssertGreaterThan(chunks.count, 0, "출력 조각이 콜백으로 와야 한다")
    XCTAssertEqual(chunks.all, "a\nb\nc\n")
  }

  func testStreamingKeepsWorkingWhenCallbackIsNil() {
    let result = SandboxRunner.run("echo hello", profile: SandboxRunner.readOnlyProfile())
    XCTAssertTrue(result.succeeded, result.combined)
    XCTAssertEqual(result.stdout, "hello\n")
  }

  func testCancellationStopsProcess() {
    let cancel = SandboxCancellation()
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { cancel.cancel() }
    let t0 = Date()
    let stopped = SandboxRunner.runStreaming(
      "sleep 5",
      profile: SandboxRunner.readOnlyProfile(),
      timeout: 30,
      cancellation: cancel,
      onOutput: nil)
    let elapsed = Date().timeIntervalSince(t0)
    XCTAssertFalse(stopped.succeeded, "중단은 성공이 아니다")
    XCTAssertTrue(stopped.stderr.contains("중지"), "중단 사유를 보여 줘야 한다: \(stopped.stderr)")
    XCTAssertLessThan(elapsed, 3, "취소는 기다리지 않고 즉시 끝나야 한다")
  }

  func testTimeoutIsReported() {
    let result = SandboxRunner.run("sleep 3", profile: SandboxRunner.readOnlyProfile(),
                                   timeout: 0.5)
    XCTAssertFalse(result.succeeded)
    XCTAssertTrue(result.stderr.contains("시간 초과"), result.stderr)
  }

  func testOutputLimitClips() {
    let result = SandboxRunner.run("yes x | head -c 5000", profile: SandboxRunner.readOnlyProfile(),
                                   timeout: 10, outputLimit: 100)
    XCTAssertTrue(result.stdout.contains("출력 잘림"), "잘렸다는 사실을 알려야 한다")
    XCTAssertLessThan(result.stdout.count, 200, "원문 5000자가 그대로 오면 안 된다")
  }
}
