import Foundation

/// 대화 기록 정리 규칙 — 순수 함수라 테스트가 직접 검증한다.
///
/// 2026-10-20 개정: 이전에는 **핀한 대화만** 저장하고 미핀은 앱을 끄면 사라졌다.
/// 이제 모든 대화를 기록에 남기고, 미핀은 `keepDays` 뒤에 정리한다(핀은 나이 무관).
public enum ConversationHistory {
  /// 보관(핀) 우선, 그 안에서는 최근 갱신 순. 같은 ID가 여러 번 있으면 가장 최근 것만 남긴다.
  public static func ordered(_ list: [Conversation]) -> [Conversation] {
    var seen = Set<UUID>()
    var unique: [Conversation] = []
    for c in list.sorted(by: { $0.updatedAt > $1.updatedAt }) where seen.insert(c.id).inserted {
      unique.append(c)
    }
    return unique.filter(\.pinned) + unique.filter { !$0.pinned }
  }

  /// 만료 정리 — 핀은 유지, 미핀은 `keepDays`(0 이하 = 무제한)를 지난 것만 폐기.
  public static func pruned(_ list: [Conversation], keepDays: Int, now: Date = Date()) -> [Conversation] {
    guard keepDays > 0 else { return ordered(list) }
    let cutoff = now.addingTimeInterval(TimeInterval(-keepDays * 86_400))
    return ordered(list.filter { $0.pinned || $0.updatedAt >= cutoff })
  }

  /// 제목 없는 옛 기록에 첫 질문으로 자동 제목을 채운다(저장 전 메모리에서만).
  /// 사용자가 바꾼 제목(`titleEdited`)과 이미 있는 제목은 건드리지 않는다.
  public static func normalized(_ list: [Conversation]) -> [Conversation] {
    list.map { c in
      var c = c
      c.applyAutoTitle()
      return c
    }
  }

  /// 시작할 때 이어서 열 대화 — 가장 최근에 갱신된 대화(핀 여부 무관).
  public static func mostRecent(_ list: [Conversation]) -> Conversation? {
    list.max(by: { $0.updatedAt < $1.updatedAt })
  }
}

/// 대화 기록 저장소 — 모든 대화를 JSON 한 파일에 원자적으로 쓴다.
public enum PersistenceService {
  public static var directory: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/QuickTalk")
  }
  /// 대화 기록 파일(핀 + 미핀 모두)
  public static var storeURL: URL { directory.appendingPathComponent("history.json") }
  /// 구버전 파일(핀만 저장) — 첫 로드에서 승계한다.
  public static var legacyPinnedURL: URL { directory.appendingPathComponent("pinned.json") }

  public static func save(_ conversations: [Conversation], to url: URL? = nil) throws {
    let target = url ?? storeURL
    let data = try JSONEncoder().encode(ConversationHistory.ordered(conversations))
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
  }

  /// 기록을 읽는다. `history.json`이 없으면(구버전) `pinned.json`을 승계한다.
  /// `from:`은 테스트용 — 실제 저장 위치를 건드리지 않고 왕복을 검증한다.
  public static func load(keepDays: Int = 30, from url: URL? = nil) -> [Conversation] {
    if let data = try? Data(contentsOf: url ?? storeURL),
       let list = try? JSONDecoder().decode([Conversation].self, from: data) {
      return ConversationHistory.pruned(ConversationHistory.normalized(list), keepDays: keepDays)
    }
    if url == nil, let data = try? Data(contentsOf: legacyPinnedURL),
       let list = try? JSONDecoder().decode([Conversation].self, from: data) {
      NSLog("[QuickTalk] 구버전 pinned.json 승계 — %d개", list.count)
      return ConversationHistory.pruned(ConversationHistory.normalized(list), keepDays: keepDays)
    }
    return []
  }
}
