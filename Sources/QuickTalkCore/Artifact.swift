import Foundation

// [FEATURE] 산출물 카드 — 턴에 남는 파일 기록·미리보기·diff (PLAN_v0.38.2)
//
// 왜 파일 내용을 Turn 에 저장하지 않는가?
//   대화 기록(history.json)이 파일 크기만큼 커지면 보관함 전체가 느려진다.
//   카드에는 **경로·크기·변경·줄 수**만 남기고, 미리보기는 디스크를 읽는다.
//   diff 는 `UndoStack` 의 **쓰기 직전 백업**과 현재 파일을 비교해 그때 계산한다.
//
// 안전 경계
//   · 미리보기는 로컬 파일만 읽고 최대 256KB 까지만 읽는다.
//   · diff 는 양쪽이 모두 UTF-8 텍스트이고 5,000줄 이하일 때만 계산한다.
//   · 파일 내용은 로그·감사 기록·알림에 남기지 않는다(호출부 책임).

public struct TurnArtifact: Codable, Equatable, Identifiable, Hashable {
  public enum Change: String, Codable, Equatable, Hashable {
    case created
    case modified
    case deleted
  }

  public var id: UUID
  /// 절대 경로(정규화). Job 카드처럼 상대 경로를 쓰는 곳은 별도 모델을 쓴다.
  public var path: String
  public var change: Change
  /// 현재 크기. 삭제된 파일이면 **삭제 전** 크기.
  public var byteCount: Int
  /// UTF-8 텍스트이고 계산 가능할 때만.
  public var addedLines: Int?
  public var removedLines: Int?
  /// `UndoStack` 스냅샷 — 있으면 [되돌리기]를 보여 준다.
  public var undoID: String?
  public var createdAt: Date

  /// 한 턴에 남기는 최대 산출물 수 — 카드가 대화를 덮지 않게 한다.
  public static let maxPerTurn = 12

  public init(id: UUID = UUID(), path: String, change: Change, byteCount: Int,
              addedLines: Int? = nil, removedLines: Int? = nil,
              undoID: String? = nil, createdAt: Date = Date()) {
    self.id = id
    self.path = path
    self.change = change
    self.byteCount = byteCount
    self.addedLines = addedLines
    self.removedLines = removedLines
    self.undoID = undoID
    self.createdAt = createdAt
  }

  public var name: String { (path as NSString).lastPathComponent }
  public var fileExtension: String { (path as NSString).pathExtension.lowercased() }
  public var isImage: Bool { Attachment.isImageName(path) }

  /// `12 KB` 처럼 사람이 읽는 크기. 0바이트도 `0 KB`로 표시한다.
  public var sizeText: String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: Int64(byteCount))
  }

  /// 카드에 붙는 +/- 요약. 계산하지 못했으면 nil.
  public var lineChangeText: String? {
    switch (addedLines, removedLines) {
    case let (added?, removed?):
      return "+\(added) −\(removed)"
    case let (added?, nil):
      return "+\(added)"
    case let (nil, removed?):
      return "−\(removed)"
    default:
      return nil
    }
  }
}

// MARK: - 줄 diff

/// 줄 단위 변경 요약 + unified diff.
public struct TextDiff: Equatable {
  public let added: Int
  public let removed: Int
  /// unified diff(문맥 3줄). 변경이 없으면 빈 문자열.
  public let unified: String
  /// 출력 줄 수 상한에 걸려 뒤가 잘렸는가.
  public let truncated: Bool

  public init(added: Int, removed: Int, unified: String, truncated: Bool = false) {
    self.added = added; self.removed = removed
    self.unified = unified; self.truncated = truncated
  }
}

public enum LineDiff {
  /// 이보다 긴 파일은 diff 를 계산하지 않는다(메모리·시간 보호).
  public static let maxLines = 5_000
  /// unified diff 출력 상한.
  public static let maxOutputLines = 400
  /// 문맥 줄 수.
  public static let context = 3

  /// 두 텍스트의 줄 diff. 너무 길면 nil(호출부는 크기만 보여 준다).
  public static func compare(before: String, after: String) -> TextDiff? {
    let old = lines(before)
    let new = lines(after)
    guard old.count <= maxLines, new.count <= maxLines else { return nil }

    let changes = new.difference(from: old)
    var removed = Set<Int>()
    var inserted = Set<Int>()
    for change in changes {
      switch change {
      case .remove(let offset, _, _): removed.insert(offset)
      case .insert(let offset, _, _): inserted.insert(offset)
      }
    }
    let addedCount = inserted.count
    let removedCount = removed.count
    guard addedCount > 0 || removedCount > 0 else {
      return TextDiff(added: 0, removed: 0, unified: "")
    }

    var ops: [Op] = []
    ops.reserveCapacity(old.count + new.count)
    var i = 0, j = 0
    while i < old.count || j < new.count {
      if i < old.count && removed.contains(i) {
        ops.append(Op(kind: .remove, text: old[i], oldLine: i + 1, newLine: j + 1))
        i += 1
      } else if j < new.count && inserted.contains(j) {
        ops.append(Op(kind: .add, text: new[j], oldLine: i + 1, newLine: j + 1))
        j += 1
      } else if i < old.count && j < new.count {
        ops.append(Op(kind: .context, text: old[i], oldLine: i + 1, newLine: j + 1))
        i += 1; j += 1
      } else if i < old.count {
        ops.append(Op(kind: .remove, text: old[i], oldLine: i + 1, newLine: j + 1))
        i += 1
      } else {
        ops.append(Op(kind: .add, text: new[j], oldLine: i + 1, newLine: j + 1))
        j += 1
      }
    }

    // 변경 지점 주변만 문맥과 함께 묶는다.
    let changeIndices = ops.indices.filter { ops[$0].kind != .context }
    var ranges: [ClosedRange<Int>] = []
    for index in changeIndices {
      let start = max(0, index - context)
      let end = min(ops.count - 1, index + context)
      if let last = ranges.last, start <= last.upperBound + 1 {
        ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, end)
      } else {
        ranges.append(start...end)
      }
    }

    var output: [String] = []
    var truncated = false
    for range in ranges {
      let slice = ops[range]
      let oldCount = slice.filter { $0.kind != .add }.count
      let newCount = slice.filter { $0.kind != .remove }.count
      let first = slice.first!
      output.append("@@ -\(first.oldLine),\(oldCount) +\(first.newLine),\(newCount) @@")
      for op in slice {
        switch op.kind {
        case .context: output.append(" " + op.text)
        case .add: output.append("+" + op.text)
        case .remove: output.append("-" + op.text)
        }
        if output.count >= maxOutputLines {
          truncated = true
          break
        }
      }
      if truncated { break }
    }

    return TextDiff(added: addedCount, removed: removedCount,
                    unified: output.joined(separator: "\n"), truncated: truncated)
  }

  /// CRLF 도 같은 줄로 본다. 마지막 개행은 빈 줄을 만들지 않는다.
  static func lines(_ text: String) -> [String] {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var out = normalized.components(separatedBy: "\n")
    if out.last == "" { out.removeLast() }
    return out
  }

  private struct Op {
    enum Kind { case context, add, remove }
    let kind: Kind
    let text: String
    let oldLine: Int
    let newLine: Int
  }
}

// MARK: - 파일에서 산출물 만들기

public enum FileArtifacts {
  /// diff·미리보기에 읽는 최대 바이트. 이보다 크면 앞부분만 보여 준다.
  public static let previewBytes = 256 * 1024

  /// 쓰기 전/후 데이터로 산출물 1개를 만든다. `diff` 는 호출부가 완전한 텍스트일 때만 넘긴다.
  public static func make(path: String, change: TurnArtifact.Change, byteCount: Int,
                          diff: TextDiff?, undoID: String?,
                          now: Date = Date()) -> TurnArtifact {
    TurnArtifact(path: path, change: change, byteCount: byteCount,
                 addedLines: diff?.added, removedLines: diff?.removed,
                 undoID: undoID, createdAt: now)
  }

  /// `UndoEntry` 의 항목에서 실제로 바뀐 파일만 골라 산출물로 만든다.
  ///
  /// - 디렉터리·백업 실패 항목은 건너뛴다(내용을 비교할 수 없으므로 “바뀌었다”고 단정하지 않는다).
  /// - 수정인데 백업과 현재가 **바이트 단위로 같으면** 건드리지 않은 것이므로 제외한다.
  public static func collect(undo: UndoEntry, limit: Int = TurnArtifact.maxPerTurn) -> [TurnArtifact] {
    let fm = FileManager.default
    var out: [TurnArtifact] = []

    for item in undo.items {
      if item.isDirectory { continue }
      if out.count >= limit { break }

      var isDir: ObjCBool = false
      let exists = fm.fileExists(atPath: item.path, isDirectory: &isDir)
      if isDir.boolValue { continue }

      let change: TurnArtifact.Change
      switch (item.existed, exists) {
      case (false, true): change = .created
      case (true, true): change = .modified
      case (true, false): change = .deleted
      case (false, false): continue
      }

      if change == .modified, let backup = item.backup,
         fm.contentsEqual(atPath: item.path, andPath: backup) {
        continue
      }

      let beforeData = item.backup.flatMap { readPrefix($0, maxBytes: previewBytes) }
      let afterData = exists ? readPrefix(item.path, maxBytes: previewBytes) : nil
      let afterComplete = exists ? fileSize(item.path) <= previewBytes : true
      let beforeComplete = item.backup.map { fileSize($0) <= previewBytes } ?? true

      let byteCount: Int
      if exists {
        byteCount = fileSize(item.path)
      } else if let backup = item.backup {
        byteCount = fileSize(backup)
      } else {
        byteCount = 0
      }

      // 양쪽이 모두 완전한 UTF-8 텍스트일 때만 줄 수를 계산한다.
      var diff: TextDiff?
      if beforeComplete, afterComplete,
         let beforeText = text(from: change == .created ? Data() : beforeData),
         let afterText = text(from: change == .deleted ? Data() : afterData) {
        diff = LineDiff.compare(before: beforeText, after: afterText)
      }

      out.append(make(path: item.path, change: change, byteCount: byteCount,
                      diff: diff, undoID: undo.id))
    }
    return out
  }

  /// 미리보기 — 현재 파일과(있으면) 쓰기 전 백업을 비교한다.
  public static func preview(path: String, undoEntry: UndoEntry? = nil,
                             maxBytes: Int = previewBytes) -> ArtifactPreview {
    let fm = FileManager.default
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue else {
      // 삭제된 파일도 백업이 있으면 “무엇이 사라졌는지” diff 로 보여 준다.
      var removedDiff: String?
      var removedBytes = 0
      if let item = undoEntry?.items.first(where: { $0.path == path }),
         let backup = item.backup, fileSize(backup) <= maxBytes,
         let data = readPrefix(backup, maxBytes: maxBytes),
         let before = text(from: data) {
        removedBytes = fileSize(backup)
        removedDiff = LineDiff.compare(before: before, after: "")?.unified
      }
      return ArtifactPreview(kind: .missing, content: nil, diff: removedDiff,
                             byteCount: removedBytes, lineCount: nil,
                             truncated: false, modifiedAt: nil)
    }

    let size = fileSize(path)
    let modified = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    if Attachment.isImageName(path) {
      return ArtifactPreview(kind: .image, content: nil, diff: nil,
                             byteCount: size, lineCount: nil, truncated: false,
                             modifiedAt: modified)
    }

    guard let data = readPrefix(path, maxBytes: maxBytes),
          let current = text(from: data) else {
      return ArtifactPreview(kind: .binary, content: nil, diff: nil,
                             byteCount: size, lineCount: nil, truncated: false,
                             modifiedAt: modified)
    }

    let truncated = size > maxBytes
    let lineCount = truncated ? nil : LineDiff.lines(current).count

    var diffText: String?
    var diffTruncated = false
    if !truncated, let item = undoEntry?.items.first(where: { $0.path == path }),
       let backup = item.backup, fileSize(backup) <= maxBytes,
       let beforeData = readPrefix(backup, maxBytes: maxBytes),
       let before = text(from: beforeData),
       let diff = LineDiff.compare(before: before, after: current),
       !diff.unified.isEmpty {
      diffText = diff.unified
      diffTruncated = diff.truncated
    }

    return ArtifactPreview(kind: .text, content: current, diff: diffText,
                           byteCount: size, lineCount: lineCount,
                           truncated: truncated || diffTruncated,
                           modifiedAt: modified)
  }

  // MARK: - 내부

  static func fileSize(_ path: String) -> Int {
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let size = attrs[.size] as? NSNumber else { return 0 }
    return size.intValue
  }

  static func readPrefix(_ path: String, maxBytes: Int) -> Data? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? handle.close() }
    return try? handle.read(upToCount: maxBytes)
  }

  /// NUL 이 없고 UTF-8 로 읽히면 텍스트로 본다.
  static func text(from data: Data?) -> String? {
    guard let data else { return nil }
    if data.isEmpty { return "" }
    guard !data.contains(0), let text = String(data: data, encoding: .utf8) else { return nil }
    return text
  }
}

/// 미리보기 시트가 그리는 내용 — Core 는 UI 를 모른다(NSImage 는 앱에서 읽는다).
public struct ArtifactPreview: Equatable {
  public enum Kind: String, Equatable {
    case text
    case image
    case binary
    case missing
  }

  public let kind: Kind
  /// 현재 파일 앞부분(텍스트일 때).
  public let content: String?
  /// 쓰기 전 백업과의 unified diff — 백업이 없으면 nil.
  public let diff: String?
  public let byteCount: Int
  public let lineCount: Int?
  /// 파일 또는 diff 가 잘렸는가.
  public let truncated: Bool
  public let modifiedAt: Date?

  public init(kind: Kind, content: String?, diff: String?, byteCount: Int,
              lineCount: Int?, truncated: Bool, modifiedAt: Date?) {
    self.kind = kind; self.content = content; self.diff = diff
    self.byteCount = byteCount; self.lineCount = lineCount
    self.truncated = truncated; self.modifiedAt = modifiedAt
  }

  public var sizeText: String {
    let f = ByteCountFormatter()
    f.countStyle = .file
    f.allowedUnits = [.useKB, .useMB, .useGB]
    f.allowsNonnumericFormatting = false
    return f.string(fromByteCount: Int64(byteCount))
  }
}

/// `write_file` 승인 카드에 보여 주는 앞부분 — 파일 전체를 노출하지 않는다.
public struct FileWritePreview: Equatable {
  public let path: String
  public let isNew: Bool
  public let byteCount: Int
  public let lineCount: Int
  public let text: String
  public let truncated: Bool

  public static let maxLines = 20

  public init(path: String, isNew: Bool, content: String) {
    self.path = path
    self.isNew = isNew
    let data = Data(content.utf8)
    self.byteCount = data.count
    let lines = LineDiff.lines(content)
    self.lineCount = lines.count
    self.truncated = lines.count > Self.maxLines || content.count > 4_000
    self.text = lines.prefix(Self.maxLines).joined(separator: "\n")
  }
}
