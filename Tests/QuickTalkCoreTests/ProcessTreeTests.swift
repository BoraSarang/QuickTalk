import XCTest
#if canImport(Darwin)
import Darwin
#endif
@testable import QuickTalkCore

// [REGRESSION] 2026-10-25 — [중단]·시간 초과가 자식 프로세스를 남기던 문제.
//
// `Process.terminate()` 는 sandbox-exec 한 개만 죽이고, 그 아래 `/bin/sh` 와 손자 프로세스는
// 살아남았다(실측: 부모 종료 후 자식 sleep 생존). 여기서는 실제 프로세스 트리로 확인한다.
// 사용자 프로세스와 겹치지 않게 고유 인자(`sleep 30.7`)를 쓴다.

final class ProcessTreeTests: XCTestCase {
  func testTerminateProcessTreeKillsDescendants() throws {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", "sleep 30.7 & wait"]
    try p.run()
    defer {
      if p.isRunning { kill(p.processIdentifier, SIGKILL) }
      p.waitUntilExit()
    }

    var kids: [pid_t] = []
    for _ in 0..<40 {
      kids = SandboxRunner.descendantPIDs(of: p.processIdentifier)
      if !kids.isEmpty { break }
      usleep(50_000)
    }
    XCTAssertFalse(kids.isEmpty, "자식 프로세스가 생기지 않아 검증할 수 없음")

    SandboxRunner.terminateProcessTree(p.processIdentifier)
    // 고아가 되었더라도 PID 로 직접 확인한다(부모가 사라지면 트리 조회로는 알 수 없다).
    var alive: [pid_t] = []
    for _ in 0..<20 {
      alive = kids.filter { kill($0, 0) == 0 }
      if alive.isEmpty { break }
      usleep(50_000)
    }
    for pid in kids { kill(pid, SIGKILL) }   // 실패해도 남기지 않는다
    XCTAssertTrue(alive.isEmpty, "종료 후에도 살아 있는 자식: \(alive)")
  }
}
