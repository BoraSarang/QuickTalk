import Foundation

// [FEATURE] 맡긴 작업(Job) — v0.38
//
// 계획 카드의 [맡기기]는 계획을 **백그라운드 작업**으로 넘긴다.
// Job은 대화와 분리된 수명을 갖고, 구간(segment)을 이어서 끝까지 실행한다.
// 저장은 `~/Library/Application Support/QuickTalk/Jobs/jobs.json` — 앱을 다시 켜도 남는다.

public struct Job: Codable, Equatable, Identifiable {
  /// 한 번의 실행 예산 — 30분. [계속]을 누를 때마다 30분씩 늘어난다.
  public static let defaultActiveSeconds: Double = 30 * 60
  public enum Status: String, Codable, Equatable, CaseIterable {
    /// 실행 중
    case running
    /// 앞선 작업이 끝나기를 기다리는 중
    case queued
    /// 승인을 기다리는 중
    case waitingApproval
    /// 한도·오류로 잠시 멈춤 — 사용자가 [계속]을 누르면 재개
    case paused
    case completed
    case failed
    case cancelled
    /// 앱이 작업 도중 종료됨 — 다음 실행에서 [계속]으로 복구
    case interrupted

    public var displayName: String {
      switch self {
      case .running: return L("실행 중")
      case .queued: return L("대기 중")
      case .waitingApproval: return L("승인 대기")
      case .paused: return L("일시 중지")
      case .completed: return L("완료")
      case .failed: return L("실패")
      case .cancelled: return L("중단됨")
      case .interrupted: return L("중단됨")
      }
    }

    public var symbol: String {
      switch self {
      case .running: return "gearshape.2"
      case .queued: return "hourglass"
      case .waitingApproval: return "hand.raised"
      case .paused: return "pause.circle"
      case .completed: return "checkmark.circle"
      case .failed: return "exclamationmark.triangle"
      case .cancelled: return "stop.circle"
      case .interrupted: return "bolt.slash"
      }
    }

    /// 더 이상 스스로 움직이지 않는 상태 — 메뉴바 진행 표시에서 뺀다.
    public var isTerminal: Bool {
      switch self {
      case .completed, .failed, .cancelled: return true
      case .running, .queued, .waitingApproval, .paused, .interrupted: return false
      }
    }

    /// 사용자가 [계속]/[다시 시도]로 이어서 달릴 수 있는 상태.
    public var canResume: Bool {
      self == .paused || self == .interrupted || self == .failed
    }
  }

  public var id: UUID
  /// 목표 1줄 — 대화 제목·알림 제목에 쓴다.
  public var title: String
  /// 계획의 전체 목표 — 연속 구간 프롬프트에 쓴다(제목은 48자로 줄인다).
  public var goal: String
  /// 계획 단계 — 실행 계약과 상태 카드에 쓴다.
  public var steps: [String]
  public var permissions: [ExecutionPlan.Permission]
  /// Job이 쌓이는 전용 대화.
  public var conversationID: UUID
  public var personaID: UUID?
  /// 산출물이 쌓이는 폴더 — 이 안의 쓰기만 자동 승인한다.
  public var workspacePath: String
  public var status: Status
  public var createdAt: Date
  public var updatedAt: Date
  public var finishedAt: Date?
  /// 지금까지 시작한 구간(1부터).
  public var segment: Int
  /// 한 번에 이어서 달릴 수 있는 구간 수.
  public var maxSegments: Int
  /// 지금까지 실행한 도구 횟수 — 비용·진행 감각.
  public var eventCount: Int
  /// 실제로 모델·도구를 돌린 시간(초). 멈춰 있던 시간은 세지 않는다.
  public var activeSeconds: Double
  /// 이번 실행 예산 — 실제 실행 시간 상한(초). [계속]을 누르면 30분씩 늘어난다.
  public var maxActiveSeconds: Double
  public var resultSummary: String?
  /// 작업 폴더 기준 상대 경로.
  public var artifactPaths: [String]
  public var failureReason: String?
  /// 마지막으로 확인한 한 줄(도구 이름·URL 등).
  public var progress: String?

  public init(id: UUID = UUID(), title: String, goal: String = "", steps: [String],
              permissions: [ExecutionPlan.Permission] = [],
              conversationID: UUID, personaID: UUID? = nil,
              workspacePath: String, status: Status = .running,
              createdAt: Date = Date(), updatedAt: Date = Date(),
              finishedAt: Date? = nil, segment: Int = 0, maxSegments: Int = 6,
              eventCount: Int = 0, activeSeconds: Double = 0,
              maxActiveSeconds: Double = Job.defaultActiveSeconds,
              resultSummary: String? = nil,
              artifactPaths: [String] = [], failureReason: String? = nil,
              progress: String? = nil) {
    self.id = id
    self.title = title
    self.goal = goal.isEmpty ? title : goal
    self.steps = steps
    self.permissions = permissions
    self.conversationID = conversationID
    self.personaID = personaID
    self.workspacePath = workspacePath
    self.status = status
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.finishedAt = finishedAt
    self.segment = segment
    self.maxSegments = maxSegments
    self.eventCount = eventCount
    self.activeSeconds = activeSeconds
    self.maxActiveSeconds = maxActiveSeconds
    self.resultSummary = resultSummary
    self.artifactPaths = artifactPaths
    self.failureReason = failureReason
    self.progress = progress
  }

  /// 계획에서 새 Job을 만든다 — 제목·단계·권한을 그대로 가져온다.
  public static func make(plan: ExecutionPlan, id: UUID = UUID(),
                          conversationID: UUID,
                          personaID: UUID?, workspacePath: String,
                          maxSegments: Int = 6) -> Job {
    Job(id: id, title: JobPrompt.title(plan.goal), goal: plan.goal,
        steps: plan.steps,
        permissions: plan.permissions,
        conversationID: conversationID,
        personaID: personaID,
        workspacePath: workspacePath,
        maxSegments: maxSegments)
  }

  /// 짧은 진행 문구 — `2/6 구간 · 도구 14회`.
  public var progressLine: String {
    Lf("%d/%d 구간 · 도구 %d회", segment, maxSegments, eventCount)
  }

  // MARK: - Codable (구버전·누락 키 허용)

  private enum CodingKeys: String, CodingKey {
    case id, title, goal, steps, permissions, conversationID, personaID, workspacePath
    case status, createdAt, updatedAt, finishedAt, segment, maxSegments
    case eventCount, activeSeconds, maxActiveSeconds, resultSummary, artifactPaths, failureReason, progress
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? L("맡긴 작업")
    goal = try c.decodeIfPresent(String.self, forKey: .goal) ?? title
    steps = try c.decodeIfPresent([String].self, forKey: .steps) ?? []
    permissions = try c.decodeIfPresent([ExecutionPlan.Permission].self,
                                        forKey: .permissions) ?? []
    conversationID = try c.decodeIfPresent(UUID.self, forKey: .conversationID) ?? UUID()
    personaID = try c.decodeIfPresent(UUID.self, forKey: .personaID)
    workspacePath = try c.decodeIfPresent(String.self, forKey: .workspacePath) ?? ""
    status = try c.decodeIfPresent(Status.self, forKey: .status) ?? .interrupted
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
    finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
    segment = try c.decodeIfPresent(Int.self, forKey: .segment) ?? 0
    maxSegments = try c.decodeIfPresent(Int.self, forKey: .maxSegments) ?? 6
    eventCount = try c.decodeIfPresent(Int.self, forKey: .eventCount) ?? 0
    activeSeconds = try c.decodeIfPresent(Double.self, forKey: .activeSeconds) ?? 0
    maxActiveSeconds = try c.decodeIfPresent(Double.self, forKey: .maxActiveSeconds)
      ?? Job.defaultActiveSeconds
    resultSummary = try c.decodeIfPresent(String.self, forKey: .resultSummary)
    artifactPaths = try c.decodeIfPresent([String].self, forKey: .artifactPaths) ?? []
    failureReason = try c.decodeIfPresent(String.self, forKey: .failureReason)
    progress = try c.decodeIfPresent(String.self, forKey: .progress)
  }
}

// MARK: - 저장

/// `Jobs/jobs.json` — 파일 하나에 최근 50개.
public struct JobStore {
  public static let fileName = "jobs.json"
  public static let limit = 50

  public let directory: URL

  public init(directory: URL = JobStore.defaultDirectory) {
    self.directory = directory
  }

  public var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

  /// `~/Library/Application Support/QuickTalk/Jobs`
  public static var defaultDirectory: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory())
        .appendingPathComponent("Library/Application Support")
    return base.appendingPathComponent("QuickTalk/Jobs", isDirectory: true)
  }

  /// 저장된 Job — 손상됐으면 빈 목록(앱이 멈추지 않게).
  public func load() -> [Job] {
    guard let data = try? Data(contentsOf: fileURL) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let jobs = try? decoder.decode([Job].self, from: data) else {
      NSLog("[WARN] E-MAC-JOB-0001 jobs.json 을 읽지 못했습니다 — 빈 목록으로 시작")
      return []
    }
    return Self.ordered(jobs)
  }

  public func save(_ jobs: [Job]) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let encoder = JSONEncoder()
      encoder.dateEncodingStrategy = .iso8601
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(Self.ordered(Array(jobs.prefix(Self.limit))))
      // 원자적 쓰기 — 중간에 앱이 죽어도 반쪽 JSON 이 남지 않는다.
      try data.write(to: fileURL, options: .atomic)
    } catch {
      NSLog("[WARN] E-MAC-JOB-0002 jobs.json 저장 실패: %@", String(describing: error))
    }
  }

  /// 같은 id 는 **뒤엣것으로 교체**하고, 최신 createdAt 순으로 정렬한다.
  public static func ordered(_ jobs: [Job]) -> [Job] {
    var seen = Set<UUID>()
    var unique: [Job] = []
    for job in jobs.reversed() where !seen.contains(job.id) {
      seen.insert(job.id)
      unique.append(job)
    }
    return unique.sorted { $0.createdAt > $1.createdAt }
  }

  /// 앱 시작 시 — 실행 중이던 Job은 `interrupted` 로 바꾼다.
  /// 자동 재개하지 않는다: 쓰기 중복·승인 맥락을 사용자가 확인해야 한다.
  public static func markingInterrupted(_ jobs: [Job], at now: Date = Date()) -> [Job] {
    jobs.map { job in
      guard job.status == .running || job.status == .queued
        || job.status == .waitingApproval else { return job }
      var copy = job
      copy.status = .interrupted
      copy.updatedAt = now
      copy.failureReason = nil
      copy.progress = L("앱이 종료되어 작업이 멈췄습니다. [계속]으로 이어서 실행하세요.")
      return copy
    }
  }
}

// MARK: - 작업 폴더·산출물

public struct JobArtifact: Equatable, Identifiable {
  /// 작업 폴더 기준 상대 경로.
  public let path: String
  public let bytes: Int64
  public let modifiedAt: Date?

  public var id: String { path }
  public var name: String { (path as NSString).lastPathComponent }

  public var sizeText: String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    return f.string(fromByteCount: bytes)
  }

  public init(path: String, bytes: Int64, modifiedAt: Date?) {
    self.path = path
    self.bytes = bytes
    self.modifiedAt = modifiedAt
  }
}

public enum JobWorkspace {
  /// `<작업 폴더>/Jobs/<yyyy-MM-dd-HHmmss>-<id4>`
  public static func path(root: String, jobID: UUID, date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd-HHmmss"
    let suffix = jobID.uuidString.replacingOccurrences(of: "-", with: "").prefix(4)
    let rootURL = URL(fileURLWithPath: (root as NSString).expandingTildeInPath, isDirectory: true)
    return rootURL.appendingPathComponent("Jobs", isDirectory: true)
      .appendingPathComponent("\(f.string(from: date))-\(suffix)", isDirectory: true)
      .path
  }

  @discardableResult
  public static func create(at path: String) -> URL? {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    } catch {
      NSLog("[WARN] E-MAC-JOB-0003 작업 폴더 생성 실패: %@", String(describing: error))
      return nil
    }
  }

  /// 작업 폴더 안의 파일 — 숨김·심볼릭 링크 제외, 최대 `limit`개, 경로순.
  public static func artifacts(at path: String, limit: Int = 30) -> [JobArtifact] {
    let root = URL(fileURLWithPath: path, isDirectory: true).resolvingSymlinksInPath()
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey,
                                    .fileSizeKey, .contentModificationDateKey],
      options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
    var found: [JobArtifact] = []
    for case let url as URL in enumerator {
      guard found.count < limit else { break }
      let resolved = url.resolvingSymlinksInPath()
      let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey,
                                                          .fileSizeKey, .contentModificationDateKey])
      if values?.isDirectory == true { continue }
      if values?.isSymbolicLink == true { continue }
      let full = resolved.path
      guard full.hasPrefix(root.path + "/") else { continue }
      let relative = String(full.dropFirst(root.path.count + 1))
      found.append(JobArtifact(path: relative,
                               bytes: Int64(values?.fileSize ?? 0),
                               modifiedAt: values?.contentModificationDate))
      if found.count >= limit { break }
    }
    return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
  }
}
