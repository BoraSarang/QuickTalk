import Foundation

// [FEATURE] 되돌리기 스택 — 쓰기 직전 스냅샷 (PLAN_v0.18 v0.19)
//
// 왜 스냅샷인가?
//   도구는 `shell` 하나뿐이라 "무엇을 지웠는지"를 앱이 명령어별로 해석할 수 없다
//   (`rm`·`mv`·`tee`·`sed -i`·`python -c` …). 대신 **명령이 건드릴 경로를 실행 전에 복사**해 두고,
//   [되돌리기] 를 누르면 그 시점으로 파일을 되돌린다. 어떤 명령이든 같은 방식으로 되돌릴 수 있다.
//
// 안전 경계
//   · 백업 크기 상한(기본 64MB)·개수 상한(기본 200) — 넘으면 "되돌릴 수 없음"으로 기록한다.
//   · 보관 개수 상한(기본 30) — 오래된 스냅샷부터 지운다(디스크를 먹지 않게).
//   · 앱을 다시 켜면 **카드의 [되돌리기] 는 사라지지만** 백업·기록은 남는다(디스크 보관).

public struct UndoItem: Codable, Equatable, Identifiable {
  public var id: String { path }
  /// 원래 경로(정규화)
  public let path: String
  /// 실행 전에 존재했는가 — false 면 되돌리기 때 **지운다**(이번에 새로 생긴 것)
  public let existed: Bool
  public let isDirectory: Bool
  /// 백업 위치(존재했고 백업에 성공했을 때만)
  public var backup: String?
  /// 백업하지 못한 이유
  public var note: String?

  public init(path: String, existed: Bool, isDirectory: Bool,
              backup: String? = nil, note: String? = nil) {
    self.path = path; self.existed = existed; self.isDirectory = isDirectory
    self.backup = backup; self.note = note
  }
}

public struct UndoEntry: Codable, Equatable, Identifiable {
  public let id: String
  /// 실행한 명령(원문)
  public let command: String
  /// 승인된 쓰기 범위(폴더)
  public let scope: String
  public let createdAt: Date
  public var items: [UndoItem]
  /// 되돌리기 전체에 대한 안내(예: 휴지통 이동, 너무 큼)
  public var note: String?
  public var undoneAt: Date?

  public init(id: String, command: String, scope: String, createdAt: Date,
              items: [UndoItem], note: String? = nil, undoneAt: Date? = nil) {
    self.id = id; self.command = command; self.scope = scope
    self.createdAt = createdAt; self.items = items; self.note = note; self.undoneAt = undoneAt
  }

  public var isUndone: Bool { undoneAt != nil }
  /// 되돌릴 수 있는가 — 백업이 있거나, 새로 만든 경로가 있으면 가능.
  public var isUndoable: Bool {
    items.contains { ($0.existed && $0.backup != nil) || !$0.existed }
  }
}

public struct UndoResult: Equatable {
  public var restored: Int
  public var removed: Int
  public var failed: [String]
  /// 이미 되돌린 항목이면 true(변경 없음)
  public var alreadyUndone: Bool
  public var notFound: Bool

  public init(restored: Int = 0, removed: Int = 0, failed: [String] = [],
              alreadyUndone: Bool = false, notFound: Bool = false) {
    self.restored = restored; self.removed = removed; self.failed = failed
    self.alreadyUndone = alreadyUndone; self.notFound = notFound
  }

  public var succeeded: Bool { failed.isEmpty && !notFound && !alreadyUndone }
}

/// 쓰기 직전 스냅샷 · 되돌리기.
public actor UndoStack {
  public static let shared = UndoStack()

  public nonisolated let root: URL
  public nonisolated let trashRoot: URL
  private let indexURL: URL
  private let maxBytes: Int
  private let maxItems: Int
  private let maxEntries: Int

  public private(set) var entries: [UndoEntry]

  public init(root: URL = UndoStack.defaultRoot(),
              trashRoot: URL? = nil,
              maxBytes: Int = 64 * 1024 * 1024,
              maxItems: Int = 200,
              maxEntries: Int = 30) {
    self.root = root
    self.trashRoot = trashRoot ?? root.deletingLastPathComponent()
      .appendingPathComponent("trash", isDirectory: true)
    self.indexURL = root.appendingPathComponent("index.json")
    self.maxBytes = maxBytes
    self.maxItems = maxItems
    self.maxEntries = maxEntries
    self.entries = Self.loadIndex(indexURL)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
  }

  public static func defaultRoot() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                        in: .userDomainMask).first
      ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
    return base.appendingPathComponent("QuickTalk/undo", isDirectory: true)
  }

  // MARK: - 스냅샷

  /// 실행 **전에** 부른다. 존재하는 경로는 백업하고, 없는 경로는 "새로 생길 것"으로 기록한다.
  public func snapshot(command: String, scope: String, paths: [String]) -> UndoEntry {
    let id = UUID().uuidString.lowercased()
    let dir = root.appendingPathComponent(id, isDirectory: true)
    let fm = FileManager.default
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

    var items: [UndoItem] = []
    var note: String?

    for (index, path) in paths.prefix(maxItems).enumerated() {
      var isDir: ObjCBool = false
      let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
      guard exists else {
        items.append(UndoItem(path: path, existed: false, isDirectory: false))
        continue
      }
      let size = Self.byteSize(of: path, limit: maxBytes)
      if size > maxBytes {
        items.append(UndoItem(path: path, existed: true, isDirectory: isDir.boolValue,
                              note: L("너무 커서 백업하지 못했습니다.")))
        note = L("일부 항목이 너무 커서 되돌릴 수 없습니다.")
        continue
      }
      let name = (path as NSString).lastPathComponent
      let dest = dir.appendingPathComponent("item-\(index)-\(name)", isDirectory: isDir.boolValue)
      do {
        try fm.copyItem(atPath: path, toPath: dest.path)
        items.append(UndoItem(path: path, existed: true, isDirectory: isDir.boolValue,
                              backup: dest.path))
      } catch {
        items.append(UndoItem(path: path, existed: true, isDirectory: isDir.boolValue,
                              note: L("백업에 실패했습니다.")))
        note = L("일부 항목을 백업하지 못했습니다.")
      }
    }

    if paths.count > maxItems {
      note = Lf("항목이 너무 많아(%d개) 일부만 백업했습니다.", paths.count)
    }

    let entry = UndoEntry(id: id, command: command, scope: scope, createdAt: Date(),
                          items: items, note: note)
    if items.isEmpty { try? fm.removeItem(at: dir) }
    return entry
  }

  /// 실행이 끝난 뒤 기록에 남긴다.
  public func commit(_ entry: UndoEntry) {
    entries.insert(entry, at: 0)
    trim()
    save()
  }

  /// 실행이 실패했거나 승인되지 않았으면 백업을 버린다.
  public func discard(id: String) {
    entries.removeAll { $0.id == id }
    try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    save()
  }

  // MARK: - 되돌리기

  public func entry(id: String) -> UndoEntry? {
    entries.first { $0.id == id }
  }

  /// 스냅샷 시점으로 되돌린다.
  public func undo(id: String) -> UndoResult {
    guard let idx = entries.firstIndex(where: { $0.id == id }) else {
      return UndoResult(notFound: true)
    }
    if entries[idx].undoneAt != nil { return UndoResult(alreadyUndone: true) }

    let fm = FileManager.default
    var restored = 0, removed = 0
    var failed: [String] = []

    for item in entries[idx].items {
      if item.existed {
        guard let backup = item.backup, fm.fileExists(atPath: backup) else {
          failed.append(item.path)   // 백업이 없다(너무 컸거나 실패) — 되돌릴 수 없음
          continue
        }
        // 현재 상태를 지우고 백업을 되돌린다.
        if fm.fileExists(atPath: item.path) {
          try? fm.removeItem(atPath: item.path)
        }
        let parent = (item.path as NSString).deletingLastPathComponent
        try? fm.createDirectory(atPath: parent, withIntermediateDirectories: true)
        do {
          try fm.copyItem(atPath: backup, toPath: item.path)
          restored += 1
        } catch {
          failed.append(item.path)
        }
      } else {
        // 실행 전에 없던 경로 — 이번에 새로 생긴 것만 지운다.
        if fm.fileExists(atPath: item.path) {
          do {
            try fm.removeItem(atPath: item.path)
            removed += 1
          } catch {
            failed.append(item.path)
          }
        }
      }
    }

    entries[idx].undoneAt = Date()
    if failed.isEmpty {
      try? fm.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
    }
    save()
    return UndoResult(restored: restored, removed: removed, failed: failed)
  }

  // MARK: - 보관

  private func trim() {
    let fm = FileManager.default
    while entries.count > maxEntries {
      let old = entries.removeLast()
      try? fm.removeItem(at: root.appendingPathComponent(old.id, isDirectory: true))
    }
  }

  private func save() {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(entries) else { return }
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try? data.write(to: indexURL, options: .atomic)
  }

  private static func loadIndex(_ url: URL) -> [UndoEntry] {
    guard let data = try? Data(contentsOf: url) else { return [] }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return (try? decoder.decode([UndoEntry].self, from: data)) ?? []
  }

  /// 경로의 총 바이트 — 상한을 넘으면 조기 종료(큰 폴더를 끝까지 세지 않는다).
  static func byteSize(of path: String, limit: Int) -> Int {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return 0 }
    if !isDir.boolValue {
      return (try? fm.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
    }
    var total = 0
    guard let enumerator = fm.enumerator(atPath: path) else { return 0 }
    for case let sub as String in enumerator {
      let full = (path as NSString).appendingPathComponent(sub)
      let size = (try? fm.attributesOfItem(atPath: full)[.size] as? Int) ?? 0
      total += size
      if total > limit { return total }
    }
    return total
  }
}
