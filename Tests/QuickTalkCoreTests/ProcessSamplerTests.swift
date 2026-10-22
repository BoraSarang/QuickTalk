import XCTest
@testable import QuickTalkCore

// [FEATURE] 프로세스 샘플러 테스트 (2026-10-22)
//
// 배경: `ps`·`top` 은 setuid root 라 샌드박스가 exec 자체를 거부한다
// ("/bin/sh: /usr/bin/top: Operation not permitted"). 셸로는 프로세스 사용량을 볼 수 없어
// libproc 으로 직접 읽도록 만들었다 — 여기서 그 경로가 실제 값을 내는지 고정한다.

final class ProcessSamplerTests: XCTestCase {

  func testSamplesProcessesByCPU() {
    let rows = ProcessSampler.top(.cpu, limit: 5, sampleMillis: 120)
    XCTAssertFalse(rows.isEmpty, "프로세스를 하나도 읽지 못했습니다")
    XCTAssertLessThanOrEqual(rows.count, 5)
    for row in rows {
      XCTAssertGreaterThan(row.pid, 0)
      XCTAssertFalse(row.name.isEmpty)
      XCTAssertGreaterThanOrEqual(row.cpuPercent, 0)
      XCTAssertLessThan(row.cpuPercent, 10_000)
    }
    // CPU 내림차순
    let values = rows.map(\.cpuPercent)
    XCTAssertEqual(values, values.sorted(by: >))
  }

  func testSamplesByMemory() {
    let rows = ProcessSampler.top(.memory, limit: 5, sampleMillis: 120)
    XCTAssertFalse(rows.isEmpty)
    let memory = rows.map(\.memoryBytes)
    XCTAssertEqual(memory, memory.sorted(by: >))
  }

  func testReportHasHeaderAndRows() {
    let rows = [
      ProcessUsage(pid: 123, name: "QuickTalk", cpuPercent: 12.5, memoryBytes: 64 * 1_048_576),
      ProcessUsage(pid: 456, name: "WindowServer", cpuPercent: 3.0, memoryBytes: 12 * 1_048_576)
    ]
    let text = ProcessSampler.report(rows)
    XCTAssertTrue(text.contains("PID"))
    XCTAssertTrue(text.contains("123"))
    XCTAssertTrue(text.contains("12.5%"))
    XCTAssertTrue(text.contains("QuickTalk"))
    XCTAssertTrue(text.contains("64.0 MB"))
    XCTAssertEqual(text.split(separator: "\n").count, 3)   // 머리글 + 2줄
  }

  func testReportHandlesEmptyRows() {
    XCTAssertFalse(ProcessSampler.report([]).isEmpty)
  }
}
