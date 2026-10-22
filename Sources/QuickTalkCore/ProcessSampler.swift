import Foundation

#if canImport(Darwin)
import Darwin
#endif

// [FEATURE] 프로세스 사용량 (2026-10-22)
//
// 왜 앱이 직접 읽는가:
//   `ps`·`top` 은 **setuid root** 바이너리라 샌드박스가 exec 자체를 거부한다
//   (`/bin/sh: /usr/bin/top: Operation not permitted` — 실측). 권한을 열어도 해결되지 않는다.
//   libproc(`proc_listallpids` + `proc_pidinfo(PROC_PIDTASKINFO)`)은 샌드박스·TCC 권한 없이
//   같은 정보를 읽을 수 있고, 셸을 거치지 않으므로 주입 위험도 없다.
//
// CPU 사용률 계산: 두 번 표본해 **CPU 시간 증가분 / 경과 시간** 으로 구한다
// (코어 1개를 100으로 본다 — 여러 코어를 쓰면 100을 넘는다. top 과 같은 방식).

/// 프로세스 1개의 사용량.
public struct ProcessUsage: Codable, Equatable, Sendable {
  public var pid: Int32
  public var name: String
  /// CPU 사용률(%) — 코어 1개 = 100.
  public var cpuPercent: Double
  /// 상주 메모리(바이트)
  public var memoryBytes: UInt64

  public init(pid: Int32, name: String, cpuPercent: Double, memoryBytes: UInt64) {
    self.pid = pid
    self.name = name
    self.cpuPercent = cpuPercent
    self.memoryBytes = memoryBytes
  }
}

/// 정렬 기준.
public enum ProcessSort: String, Sendable {
  case cpu
  case memory
}

public enum ProcessSampler {
  /// 사용량 상위 프로세스 — `sampleMillis` 간격으로 두 번 읽어 CPU 사용률을 계산한다.
  public static func top(_ sort: ProcessSort = .cpu, limit: Int = 5,
                         sampleMillis: Int = 400) -> [ProcessUsage] {
    #if canImport(Darwin)
    let interval = max(60, min(sampleMillis, 2_000))
    let before = snapshot()
    let started = Date()
    usleep(useconds_t(interval) * 1_000)
    let after = snapshot()
    let elapsed = max(Date().timeIntervalSince(started), 0.001)

    var rows: [ProcessUsage] = []
    rows.reserveCapacity(after.count)
    for (pid, now) in after {
      guard let first = before[pid] else { continue }
      // 프로세스가 재사용되어 CPU 시간이 줄었다면 0으로 본다(음수 방지).
      let cpuSeconds: Double
      if now.cpuNS >= first.cpuNS {
        cpuSeconds = Double(now.cpuNS - first.cpuNS) / 1_000_000_000
      } else {
        cpuSeconds = 0
      }
      rows.append(ProcessUsage(pid: pid, name: now.name,
                               cpuPercent: cpuSeconds / elapsed * 100,
                               memoryBytes: now.memoryBytes))
    }

    switch sort {
    case .cpu:
      rows.sort { $0.cpuPercent == $1.cpuPercent ? $0.memoryBytes > $1.memoryBytes
                                                : $0.cpuPercent > $1.cpuPercent }
    case .memory:
      rows.sort { $0.memoryBytes == $1.memoryBytes ? $0.cpuPercent > $1.cpuPercent
                                                  : $0.memoryBytes > $1.memoryBytes }
    }

    let count = max(1, min(limit, 30))
    return Array(rows.prefix(count))
    #else
    return []
    #endif
  }

  /// CPU 기준 상위 — 흔한 호출부를 위한 편의 함수.
  public static func topCPU(limit: Int = 5, sampleMillis: Int = 400) -> [ProcessUsage] {
    top(.cpu, limit: limit, sampleMillis: sampleMillis)
  }

  /// 모델·카드에 그대로 보여줄 표.
  public static func report(_ rows: [ProcessUsage]) -> String {
    guard !rows.isEmpty else {
      return L("프로세스 정보를 읽지 못했습니다. (권한이 없거나 샘플링에 실패했습니다)")
    }
    var text = pad("PID", 8) + pad("CPU", 8) + pad(L("메모리"), 11) + L("프로세스") + "\n"
    for row in rows {
      let cpu = String(format: "%.1f%%", row.cpuPercent)
      let memory = String(format: "%.1f MB", Double(row.memoryBytes) / 1_048_576)
      text += pad(String(row.pid), 8) + pad(cpu, 8) + pad(memory, 11) + row.name + "\n"
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - 내부

  private struct Entry {
    var cpuNS: UInt64
    var memoryBytes: UInt64
    var name: String
  }

  private static func pad(_ value: String, _ width: Int) -> String {
    let count = value.count
    return count >= width ? value : value + String(repeating: " ", count: width - count)
  }

  #if canImport(Darwin)
  /// 지금 이 순간의 프로세스별 누적 CPU 시간·메모리.
  /// 다른 사용자(루트)의 프로세스는 권한이 없어 건너뛴다 — 사용자 프로세스만으로 충분하다.
  private static func snapshot() -> [Int32: Entry] {
    var pids = [pid_t](repeating: 0, count: 8_192)
    let bytes = Int32(pids.count * MemoryLayout<pid_t>.size)
    let count = proc_listallpids(&pids, bytes)
    guard count > 0 else { return [:] }

    var result: [Int32: Entry] = [:]
    result.reserveCapacity(Int(count))
    let size = Int32(MemoryLayout<proc_taskinfo>.size)

    for index in 0..<Int(count) {
      let pid = pids[index]
      guard pid > 0 else { continue }
      var info = proc_taskinfo()
      guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { continue }

      var buffer = [CChar](repeating: 0, count: 256)
      proc_name(pid, &buffer, UInt32(buffer.count))
      let name = String(cString: buffer)

      result[pid] = Entry(cpuNS: info.pti_total_user &+ info.pti_total_system,
                          memoryBytes: info.pti_resident_size,
                          name: name.isEmpty ? "#\(pid)" : name)
    }
    return result
  }
  #endif
}
