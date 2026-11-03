import Foundation

/// `schedules.json` 한 파일의 내용. `schemaVersion` 으로 이후 마이그레이션을 구분한다.
public struct ScheduleSnapshot: Codable, Equatable {
  public static let currentVersion = 1

  public var schemaVersion: Int
  public var tasks: [ScheduledTask]

  public init(tasks: [ScheduledTask] = [], schemaVersion: Int = ScheduleSnapshot.currentVersion) {
    self.schemaVersion = schemaVersion
    self.tasks = tasks
  }

  private enum CodingKeys: String, CodingKey { case schemaVersion, tasks }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentVersion
    tasks = try c.decodeIfPresent([ScheduledTask].self, forKey: .tasks) ?? []
  }
}

/// 예약 작업 저장소 — 대화 기록(`history.json`)과 **분리**한다.
///
/// 대화를 지워도 일정·리포트는 남는다. 쓰기는 `Data.write(options: .atomic)` 로
/// 반쯤 쓰인 파일이 남지 않게 한다(`PersistenceService` 와 같은 방식).
public enum ScheduleStore {
  public static var directory: URL { PersistenceService.directory }
  public static var storeURL: URL { directory.appendingPathComponent("schedules.json") }

  public static func save(_ snapshot: ScheduleSnapshot, to url: URL? = nil) throws {
    let target = url ?? storeURL
    let data = try JSONEncoder().encode(snapshot)
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
  }

  /// 읽기. 파일이 없으면 빈 목록, **손상됐으면 백업하고 빈 목록**을 돌려준다.
  /// 손상 파일을 지우지 않는 이유: 사용자가 직접 복구할 수 있어야 한다.
  public static func load(from url: URL? = nil, now: Date = Date()) -> ScheduleSnapshot {
    let target = url ?? storeURL
    guard let data = try? Data(contentsOf: target) else { return ScheduleSnapshot() }

    guard let snapshot = try? JSONDecoder().decode(ScheduleSnapshot.self, from: data) else {
      let backup = backup(target, now: now)
      NSLog("[QuickTalk] schedules.json 손상 — 백업: %@", backup?.path ?? "실패")
      return ScheduleSnapshot()
    }

    // 미래 버전은 우리가 모르는 키를 잃을 수 있다 — 덮어쓰지 않고 백업만 남긴다.
    guard snapshot.schemaVersion <= ScheduleSnapshot.currentVersion else {
      let backup = backup(target, now: now)
      NSLog("[QuickTalk] schedules.json 미래 버전 %d — 백업: %@",
            snapshot.schemaVersion, backup?.path ?? "실패")
      return ScheduleSnapshot()
    }
    return ScheduleSnapshot(tasks: snapshot.tasks, schemaVersion: ScheduleSnapshot.currentVersion)
  }

  /// 손상·미래 버전 파일을 옆에 복사한다(원본 유지). 같은 이름이면 `-2`.
  @discardableResult
  public static func backup(_ url: URL, now: Date = Date()) -> URL? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    let suffix = f.string(from: now)
    let dir = url.deletingLastPathComponent()
    var candidate = dir.appendingPathComponent("schedules.corrupt-\(suffix).json")
    var index = 2
    while FileManager.default.fileExists(atPath: candidate.path) {
      candidate = dir.appendingPathComponent("schedules.corrupt-\(suffix)-\(index).json")
      index += 1
    }
    do {
      try FileManager.default.copyItem(at: url, to: candidate)
      return candidate
    } catch {
      NSLog("[QuickTalk] schedules 백업 실패: %@", error.localizedDescription)
      return nil
    }
  }
}

// MARK: - 다음 실행 판정

/// 한 번의 폴링에서 나온 결과.
public struct ScheduleTick: Equatable {
  public struct Firing: Equatable {
    public var task: ScheduledTask
    public var fireAt: Date
  }

  /// 지금 실행(또는 24시간 안이면 따라잡기 실행).
  public var due: [Firing]
  /// 24시간을 넘겨 건너뛰고 `missed` 로 기록할 것.
  public var missed: [Firing]

  public var isEmpty: Bool { due.isEmpty && missed.isEmpty }
}

/// 순수 판정 로직 — 타이머·파일과 분리해 테스트한다.
public enum SchedulePlanner {
  /// 24시간을 넘긴 일정은 실행하지 않고 건너뛴다.
  public static func tick(_ tasks: [ScheduledTask], now: Date,
                          calendar: Calendar = .current,
                          catchUpWindow: TimeInterval = ScheduleRule.catchUpWindow) -> ScheduleTick {
    var due: [ScheduleTick.Firing] = []
    var missed: [ScheduleTick.Firing] = []

    for task in tasks {
      guard task.enabled, let fireAt = task.nextFireAt, fireAt <= now else { continue }
      let firing = ScheduleTick.Firing(task: task, fireAt: fireAt)
      if ScheduleRule.shouldCatchUp(now: now, scheduled: fireAt, window: catchUpWindow) {
        due.append(firing)
      } else {
        missed.append(firing)
      }
    }

    let order: (ScheduleTick.Firing, ScheduleTick.Firing) -> Bool = { a, b in
      if a.fireAt != b.fireAt { return a.fireAt < b.fireAt }
      return a.task.id.uuidString < b.task.id.uuidString
    }
    return ScheduleTick(due: due.sorted(by: order), missed: missed.sorted(by: order))
  }

  /// 앱을 새로 켰을 때 비어 있는 `nextFireAt` 을 채운다(이미 있으면 유지 — 중복 방지).
  public static func reconciled(_ tasks: [ScheduledTask], now: Date,
                                calendar: Calendar = .current) -> [ScheduledTask] {
    tasks.map { task in
      var copy = task
      copy.fillNextFireIfNeeded(now: now, calendar: calendar)
      return copy
    }
  }

  /// 실행이 끝난(또는 건너뛴) 일정의 다음 시각을 계산한다.
  public static func advanced(_ task: ScheduledTask, fireAt: Date, now: Date,
                              calendar: Calendar = .current) -> ScheduledTask {
    var copy = task
    copy.advanceNextFire(after: fireAt, now: now, calendar: calendar)
    return copy
  }
}
