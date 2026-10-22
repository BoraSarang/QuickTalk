import XCTest
@testable import QuickTalkCore

// [FEATURE] 단일 실행 잠금 테스트 (2026-10-22)
//
// 앱이 두 번 실행되지 않도록 하는 근간 — 파일 잠금(flock)의 동작을 고정한다.
// 실제 앱에서는 설치본과 디버그 빌드가 **같은 잠금 파일**을 쓰므로 하나만 뜬다.

final class InstanceLockTests: XCTestCase {
  private var dir: URL!

  override func setUpWithError() throws {
    dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("qt-lock-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  }

  override func tearDownWithError() throws {
    try? FileManager.default.removeItem(at: dir)
  }

  private func makeLock() -> InstanceLock {
    InstanceLock(path: dir.appendingPathComponent("instance.lock").path)
  }

  func testSecondLockFailsWhileFirstIsHeld() {
    let first = makeLock()
    let second = makeLock()
    XCTAssertTrue(first.acquire())
    XCTAssertTrue(first.isHeld)
    // 설치본 + 디버그 빌드 = 같은 파일 → 두 번째는 실패해야 한다
    XCTAssertFalse(second.acquire())
    XCTAssertFalse(second.isHeld)
  }

  func testReleaseAllowsNextLaunch() {
    let first = makeLock()
    XCTAssertTrue(first.acquire())
    first.release()
    XCTAssertFalse(first.isHeld)
    let second = makeLock()
    XCTAssertTrue(second.acquire())
    second.release()
  }

  func testProcessExitReleasesLock() throws {
    // 자식 프로세스가 잠금을 잡은 뒤 종료하면, OS 가 풀어 다음 실행이 가능해야 한다.
    // (PID 파일 방식이면 찌꺼기가 남아 앱이 영영 안 뜨는 문제가 생긴다)
    let path = dir.appendingPathComponent("instance.lock").path
    let script = "import Foundation; import Darwin; "
      + "let fd = open(\"\(path)\", O_CREAT | O_RDWR, 0o644); "
      + "exit(flock(fd, LOCK_EX | LOCK_NB) == 0 ? 0 : 1)"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
    p.arguments = ["-e", script]
    try p.run()
    p.waitUntilExit()
    XCTAssertEqual(p.terminationStatus, 0, "자식이 잠금을 잡지 못했습니다")

    // 자식은 이미 종료 — 잠금은 OS 가 풀었다
    let lock = makeLock()
    XCTAssertTrue(lock.acquire())
    lock.release()
  }

  func testAcquireIsIdempotent() {
    let lock = makeLock()
    XCTAssertTrue(lock.acquire())
    XCTAssertTrue(lock.acquire())
    lock.release()
    XCTAssertFalse(lock.isHeld)
  }
}
