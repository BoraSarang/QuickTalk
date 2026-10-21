import Foundation

// [FEATURE] 공통 메모리 (PLAN_v0.16)
//
// 대화 기억 정리(`ConversationMemory`)가 **대화별 요약**이라면, 공통 메모리는
// **모든 대화에 적용되는 사용자가 직접 쓴 사실**이다. 모델을 학습시키는 것이 아니라
// 매 요청의 프롬프트 앞에 선택된 항목을 넣는다.
//
// P1 — 여러 항목 CRUD·켜기/끄기·항상 주입·토큰 예산
// P2 — 태그·검색·정렬·가져오기/내보내기·관련 항목만 주입
// P3 — 로컬 임베딩(해시 n-gram)으로 질문과 관련된 항목만 검색
//
// 원칙:
// - 메모리는 **사용자 데이터**다. 원격 프로바이더를 쓰면 켜 둔 항목이 전송된다(설정에 경고).
// - 비밀번호·토큰 같은 민감정보를 넣지 않도록 안내한다(자동 검열은 하지 않는다).
// - 저장 파일은 Application Support/QuickTalk/memory.json — 대화 기록과 분리한다.

// MARK: - 항목

public struct GlobalMemoryEntry: Codable, Identifiable, Equatable {
  public var id: UUID
  /// 목록에 보이는 짧은 이름(비우면 본문 첫 줄을 쓴다).
  public var title: String
  public var content: String
  /// 검색·관련성 판단에 쓰는 태그("#" 없이 저장).
  public var tags: [String]
  public var enabled: Bool
  /// 관련성 모드에서도 질문과 무관하게 항상 포함한다.
  public var alwaysInclude: Bool
  public var createdAt: Date
  public var updatedAt: Date

  public init(id: UUID = UUID(),
              title: String = "",
              content: String = "",
              tags: [String] = [],
              enabled: Bool = true,
              alwaysInclude: Bool = false,
              createdAt: Date = Date(),
              updatedAt: Date = Date()) {
    self.id = id
    self.title = title
    self.content = content
    self.tags = tags
    self.enabled = enabled
    self.alwaysInclude = alwaysInclude
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, content, tags, enabled, alwaysInclude, createdAt, updatedAt
  }

  /// 구버전·외부 JSON에 일부 키가 없어도 열린다.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
    title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
    content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
    tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
    enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    alwaysInclude = try c.decodeIfPresent(Bool.self, forKey: .alwaysInclude) ?? false
    createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
  }

  /// 비어 있는 항목인가 — 저장·주입에서 제외한다.
  public var isBlank: Bool {
    content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  /// 목록·프롬프트에 쓰는 이름. 제목이 비면 본문 첫 줄, 그것도 비면 "메모".
  public var displayTitle: String {
    let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !t.isEmpty { return t }
    let first = content
      .split(whereSeparator: { $0.isNewline })
      .first
      .map(String.init)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if !first.isEmpty { return String(first.prefix(40)) }
    return L("메모")
  }

  /// 태그를 "#a #b" 형태로 — 빈 태그는 버린다.
  public var tagText: String {
    tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .map { "#\($0)" }
      .joined(separator: " ")
  }

  /// 프롬프트 1건 비용(제목·본문·태그 + 구분자 오버헤드).
  public var estimatedTokens: Int {
    ConversationMemory.estimateTokens(displayTitle)
      + ConversationMemory.estimateTokens(content)
      + ConversationMemory.estimateTokens(tags.joined(separator: " "))
      + 12
  }

  /// 사용자가 입력한 태그 문자열("a, b #c")을 정규화한다.
  public static func normalizeTags(_ raw: String) -> [String] {
    var seen = Set<String>()
    return raw
      .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
      .filter { !$0.isEmpty }
      .filter { seen.insert($0.lowercased()).inserted }
  }
}

// MARK: - 주입 방식

public enum MemoryInjectionMode: String, Codable, CaseIterable, Identifiable {
  /// 켜 둔 모든 항목을 예산까지 넣는다(P1 기본).
  case always
  /// `항상 포함` + 질문과 관련 있는 항목만 넣는다(P3 검색).
  case relevant

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .always: return L("항상 모두 포함")
    case .relevant: return L("관련 항목만")
    }
  }

  public var explanation: String {
    switch self {
    case .always:
      return L("켜 둔 메모리를 매 질문에 넣습니다. 토큰 예산을 넘으면 뒤쪽 항목부터 빠집니다.")
    case .relevant:
      return L("질문과 관련 있는 항목만 골라 넣습니다. [항상 포함]을 켠 항목은 언제나 들어갑니다.")
    }
  }
}

// MARK: - 선택 결과

public struct GlobalMemoryPrompt: Equatable {
  public let text: String
  public let included: [GlobalMemoryEntry]
  public let tokens: Int
  /// 예산 때문에 본문을 줄인 항목.
  public let clippedIDs: [UUID]

  public static let empty = GlobalMemoryPrompt(text: "", included: [], tokens: 0, clippedIDs: [])

  public var isEmpty: Bool { text.isEmpty }
}

// MARK: - 선택·프롬프트 조립

public enum GlobalMemory {
  /// 관련성 모드의 최소 점수 — 낮으면 잡음, 높으면 누락. 로컬 임베딩 기준 보수적으로 잡는다.
  public static let relevantThreshold: Double = 0.22
  /// 프롬프트 머리말·규칙의 **보수적 기본값**. 실제 문구 길이는 `headerText()`로 계산한다.
  public static let headerTokens: Int = 70

  /// 공통 메모리 머리말·규칙 — 예산 계산과 프롬프트 본문이 같은 문자열을 쓴다.
  public static func headerText() -> String {
    """
    \(L("[사용자 공통 메모리]"))
    \(L("아래는 사용자가 모든 대화에 적용하려고 저장한 사실이다. 이미 알고 있는 정보로 취급하고 같은 내용을 다시 묻지 않는다. 메모리와 이번 질문이 충돌하면 질문의 최신 내용을 우선한다. 메모리에 없는 내용을 지어내지 않는다."))

    """
  }

  /// 실제 머리말 비용(언어에 따라 달라진다).
  public static var actualHeaderTokens: Int {
    ConversationMemory.estimateTokens(headerText())
  }

  /// 켜진 항목만, 사용자가 정한 순서를 유지한다.
  public static func enabled(_ entries: [GlobalMemoryEntry]) -> [GlobalMemoryEntry] {
    entries.filter { $0.enabled && !$0.isBlank }
  }

  /// 질문과 항목의 관련성 — 로컬 임베딩 코사인 + 태그/제목 일치 보정.
  /// 단건 호출용. 여러 항목을 비교할 때는 `select`가 질문 벡터를 한 번만 만든다.
  public static func relevance(_ entry: GlobalMemoryEntry, query: String) -> Double {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return 0 }
    return relevance(entry,
                     queryVector: MemoryEmbedding.vector(for: q),
                     normalizedQuery: MemoryEmbedding.normalize(q))
  }

  /// 이미 만든 질문 벡터·정규화 문자열로 점수를 계산한다(항목 벡터는 캐시).
  static func relevance(_ entry: GlobalMemoryEntry,
                        queryVector: [Double],
                        normalizedQuery: String) -> Double {
    var score = MemoryEmbedding.cosine(queryVector,
                                       MemoryEmbedding.vector(for: entry)) * 0.8
    let normalizedTitle = MemoryEmbedding.normalize(entry.displayTitle)
    if !normalizedQuery.isEmpty, normalizedTitle.contains(normalizedQuery) { score += 0.12 }
    for tag in entry.tags {
      let t = MemoryEmbedding.normalize(tag)
      if !t.isEmpty, normalizedQuery.contains(t) { score += 0.08 }
    }
    return score
  }

  /// 주입 후보를 고른다(예산 적용 전).
  /// - `.always`: 전부
  /// - `.relevant`: 항상 포함 + 관련 점수 이상. 관련 항목이 하나도 없으면 **아무것도 넣지 않는다**.
  public static func select(_ entries: [GlobalMemoryEntry],
                            query: String,
                            mode: MemoryInjectionMode) -> [GlobalMemoryEntry] {
    let candidates = enabled(entries)
    guard !candidates.isEmpty else { return [] }
    let picked: [GlobalMemoryEntry]
    switch mode {
    case .always:
      picked = candidates
    case .relevant:
      // 질문 임베딩은 한 번만, 항목 임베딩은 updatedAt 캐시에서 꺼낸다.
      let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
      let queryVector = MemoryEmbedding.vector(for: q)
      let normalizedQuery = MemoryEmbedding.normalize(q)
      let scored = candidates.map { entry in
        (entry, relevance(entry, queryVector: queryVector, normalizedQuery: normalizedQuery))
      }
      picked = scored
        .filter { $0.0.alwaysInclude || $0.1 >= relevantThreshold }
        .sorted { a, b in
          if a.0.alwaysInclude != b.0.alwaysInclude { return a.0.alwaysInclude }
          if a.1 != b.1 { return a.1 > b.1 }
          return a.0.updatedAt > b.0.updatedAt
        }
        .map(\.0)
    }
    return picked
  }

  /// 예산에 맞춰 앞에서부터 넣고, 마지막 항목이 넘치면 본문을 줄인다.
  public static func fit(_ entries: [GlobalMemoryEntry],
                         budget: Int,
                         reserved: Int = headerTokens) -> (entries: [GlobalMemoryEntry], clipped: [UUID]) {
    let reserved = max(0, reserved)
    guard budget > reserved else { return ([], []) }
    var remaining = budget - reserved
    var out: [GlobalMemoryEntry] = []
    var clipped: [UUID] = []
    for entry in entries {
      let cost = entry.estimatedTokens
      if cost <= remaining {
        out.append(entry)
        remaining -= cost
        continue
      }
      // 최소 40토큰 이상 남았을 때만 부분 포함 — 잘린 메모리는 오해를 부를 수 있다.
      guard remaining >= 40 else { break }
      var copy = entry
      let titleCost = ConversationMemory.estimateTokens(entry.displayTitle)
        + ConversationMemory.estimateTokens(entry.tags.joined(separator: " ")) + 12
      let contentBudget = max(12, remaining - titleCost)
      copy.content = clip(entry.content, toTokens: contentBudget)
      guard !copy.content.isEmpty else { break }
      out.append(copy)
      clipped.append(entry.id)
      remaining = 0
      break
    }
    return (out, clipped)
  }

  /// 본문을 대략 `tokens` 이하로 줄인다(보수적 토큰 추정 사용).
  public static func clip(_ text: String, toTokens tokens: Int) -> String {
    guard tokens > 0 else { return "" }
    guard ConversationMemory.estimateTokens(text) > tokens else { return text }
    // 토큰 추정은 접두어 길이에 단조 증가하므로 이진 탐색으로 자른다.
    // (이전 10%씩 줄이기는 긴 메모리에서 접두어를 수십 번 복사했다.)
    var low = 0
    var high = text.count
    while low < high {
      let mid = (low + high + 1) / 2
      if ConversationMemory.estimateTokens(String(text.prefix(mid))) <= tokens {
        low = mid
      } else {
        high = mid - 1
      }
    }
    guard low > 0 else { return "" }
    return String(text.prefix(low)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
  }

  /// 모델 프롬프트 앞에 넣는 블록. 항목이 없으면 빈 결과.
  public static func prompt(_ entries: [GlobalMemoryEntry],
                            query: String,
                            mode: MemoryInjectionMode,
                            budget: Int) -> GlobalMemoryPrompt {
    let selected = select(entries, query: query, mode: mode)
    guard !selected.isEmpty else { return .empty }
    let header = headerText()
    let fitted = fit(selected, budget: budget,
                     reserved: ConversationMemory.estimateTokens(header))
    guard !fitted.entries.isEmpty else { return .empty }
    let body = fitted.entries.map { entry -> String in
      // 여러 줄 메모리는 이어지는 줄을 들여써 목록 구조가 깨지지 않게 한다.
      let content = entry.content
        .split(separator: "\n", omittingEmptySubsequences: false)
        .joined(separator: "\n  ")
      var line = content.isEmpty
        ? "- [\(entry.displayTitle)]"
        : "- [\(entry.displayTitle)] \(content)"
      let tags = entry.tagText
      if !tags.isEmpty { line += " (\(tags))" }
      return line
    }.joined(separator: "\n")
    let text = header + body + "\n"
    let tokens = ConversationMemory.estimateTokens(text)
    return GlobalMemoryPrompt(text: text, included: fitted.entries,
                              tokens: tokens, clippedIDs: fitted.clipped)
  }

  /// 화면 요약 — "3개 · 약 120토큰 · 2개 제외".
  public static func summary(_ entries: [GlobalMemoryEntry], budget: Int) -> String {
    let on = enabled(entries)
    let shown = fit(select(entries, query: "", mode: .always), budget: budget,
                    reserved: actualHeaderTokens).entries
    let used = prompt(entries, query: "", mode: .always, budget: budget).tokens
    var text = Lf("켜짐 %d개 · 예산 내 %d개 · 약 %d토큰", on.count, shown.count, used)
    if on.count > shown.count { text += Lf(" · %d개 제외", on.count - shown.count) }
    return text
  }
}

// MARK: - 로컬 임베딩 (P3)

/// 외부 API 없이 도는 결정론적 해시 임베딩.
/// 정확한 신경망 임베딩은 아니지만 **질문과 메모리의 어휘 겹침**을 cosine으로 비교하기에 충분하고,
/// 오프라인·무료·빠르며 테스트가 고정된다. (모델 임베딩은 후속 과제)
public enum MemoryEmbedding {
  public static let dimensions = 2_048

  /// 소문자화 + 구두점→공백. 한국어는 그대로 둔다.
  public static func normalize(_ text: String) -> String {
    let lowered = text.lowercased()
    let mapped = lowered.unicodeScalars.map { scalar -> Character in
      if CharacterSet.alphanumerics.contains(scalar) || scalar == " " { return Character(scalar) }
      return " "
    }
    return String(mapped)
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }

  /// 특징 벡터 — ASCII 단어 + CJK uni/bi-gram. 같은 텍스트는 항상 같은 결과.
  public static func vector(for text: String) -> [Double] {
    var v = [Double](repeating: 0, count: dimensions)
    let normalized = normalize(text)
    guard !normalized.isEmpty else { return v }
    var asciiRun = ""
    var cjkRun: [Character] = []

    func flushASCII() {
      guard asciiRun.count >= 2 else { asciiRun = ""; return }
      add(asciiRun, weight: 1, to: &v)
      asciiRun = ""
    }
    func flushCJK() {
      guard !cjkRun.isEmpty else { return }
      // 단일 글자는 잡음이 커서 쓰지 않는다 — 한국어는 2-gram이 사실상 단어 역할을 한다.
      if cjkRun.count >= 2 {
        for i in 0..<(cjkRun.count - 1) {
          add(String(cjkRun[i...(i + 1)]), weight: 1, to: &v)
        }
      }
      cjkRun.removeAll(keepingCapacity: true)
    }

    for ch in normalized {
      if ch.isASCII {
        flushCJK()
        if ch.isLetter || ch.isNumber { asciiRun.append(ch) } else { flushASCII() }
      } else {
        flushASCII()
        if ch == " " { flushCJK() } else { cjkRun.append(ch) }
      }
    }
    flushASCII(); flushCJK()

    let norm = sqrt(v.reduce(0) { $0 + $1 * $1 })
    if norm > 0 { v = v.map { $0 / norm } }
    return v
  }

  /// 항목 벡터 — `updatedAt`·길이로 캐시해 질문마다 다시 만들지 않는다.
  public static func vector(for entry: GlobalMemoryEntry) -> [Double] {
    MemoryEmbeddingCache.shared.vector(for: entry)
  }

  public static func cosine(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count, !a.isEmpty else { return 0 }
    var dot = 0.0
    for i in 0..<a.count { dot += a[i] * b[i] }
    return max(0, min(1, dot))
  }

  static func add(_ feature: String, weight: Double, to v: inout [Double]) {
    let h = fnv1a(feature)
    let index = Int(h % UInt64(dimensions))
    let sign: Double = (h & 0x8000_0000_0000_0000) == 0 ? 1 : -1
    v[index] += sign * weight
  }

  /// FNV-1a 64 — Swift `Hasher`와 달리 실행마다 값이 바뀌지 않는다.
  static func fnv1a(_ s: String) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for b in s.utf8 {
      hash ^= UInt64(b)
      hash = hash &* 0x0000_0100_0000_01b3
    }
    return hash
  }
}

/// 항목 임베딩 캐시 — 메모리 수가 많아도 질문마다 전체 본문을 다시 벡터화하지 않는다.
/// 키에 UUID·updatedAt·길이를 넣어 편집 후에는 새로 계산한다.
final class MemoryEmbeddingCache {
  static let shared = MemoryEmbeddingCache()

  private struct Key: Hashable {
    let id: UUID
    let updatedAt: TimeInterval
    let contentCount: Int
    let titleCount: Int
    let tagCount: Int
  }

  private var entries: [Key: [Double]] = [:]
  private var order: [Key] = []
  private let lock = NSLock()
  private let capacity = 128

  func vector(for entry: GlobalMemoryEntry) -> [Double] {
    let key = Key(id: entry.id,
                  updatedAt: entry.updatedAt.timeIntervalSince1970,
                  contentCount: entry.content.count,
                  titleCount: entry.title.count,
                  tagCount: entry.tags.count)
    lock.lock()
    if let cached = entries[key] {
      lock.unlock()
      return cached
    }
    lock.unlock()

    let text = entry.displayTitle + "\n" + entry.content + "\n"
      + entry.tags.joined(separator: " ")
    let vector = MemoryEmbedding.vector(for: text)

    lock.lock()
    if entries[key] == nil {
      entries[key] = vector
      order.append(key)
      while order.count > capacity {
        let oldest = order.removeFirst()
        entries.removeValue(forKey: oldest)
      }
    }
    lock.unlock()
    return vector
  }

  /// 테스트·가져오기 후 강제 무효화용.
  func clear() {
    lock.lock()
    entries.removeAll(keepingCapacity: true)
    order.removeAll(keepingCapacity: true)
    lock.unlock()
  }
}

// MARK: - 저장·가져오기/내보내기 (P2)

public enum GlobalMemoryFile {
  public static var directory: URL { PersistenceService.directory }
  public static var url: URL { directory.appendingPathComponent("memory.json") }

  /// 저장 형식 — 나중에 필드를 늘려도 읽을 수 있게 봉투를 쓴다.
  public struct Archive: Codable, Equatable {
    public var version: Int
    public var entries: [GlobalMemoryEntry]
    public init(version: Int = 1, entries: [GlobalMemoryEntry]) {
      self.version = version; self.entries = entries
    }
  }

  public static func encode(_ entries: [GlobalMemoryEntry]) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return try encoder.encode(Archive(entries: entries))
  }

  /// 배열과 봉투(`{"entries":[...]}`) 모두 읽는다 — 직접 만든 JSON도 가져올 수 있게.
  public static func decode(_ data: Data) throws -> [GlobalMemoryEntry] {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let archive = try? decoder.decode(Archive.self, from: data) {
      return archive.entries.filter { !$0.isBlank }
    }
    if let list = try? decoder.decode([GlobalMemoryEntry].self, from: data) {
      return list.filter { !$0.isBlank }
    }
    // 날짜가 숫자(구버전 기본 인코더)인 파일도 받아 준다.
    let fallback = JSONDecoder()
    if let archive = try? fallback.decode(Archive.self, from: data) {
      return archive.entries.filter { !$0.isBlank }
    }
    return try fallback.decode([GlobalMemoryEntry].self, from: data)
      .filter { !$0.isBlank }
  }

  public static func load(from target: URL? = nil) -> [GlobalMemoryEntry] {
    let source = target ?? url
    guard let data = try? Data(contentsOf: source) else { return [] }
    do {
      return try decode(data)
    } catch {
      // 깨진 파일을 []로 취급한 뒤 다음 저장에서 덮어쓰면 사용자 데이터가 사라진다.
      // 원본을 `.corrupt`로 보존하고 빈 목록을 돌려준다(다음 저장은 새 파일).
      let backup = source.appendingPathExtension("corrupt")
      try? data.write(to: backup, options: .atomic)
      try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                             ofItemAtPath: backup.path)
      NSLog("[ERROR] E-MAC-MEM-0005 %@ decode failed — backup: %@",
            source.lastPathComponent, backup.lastPathComponent)
      return []
    }
  }

  public static func save(_ entries: [GlobalMemoryEntry], to target: URL? = nil) throws {
    let destination = target ?? url
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try encode(entries).write(to: destination, options: .atomic)
    // 메모리는 개인정보가 될 수 있다 — 소유자만 읽고 쓰게 한다.
    try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                           ofItemAtPath: destination.path)
  }

  /// 가져오기 — 같은 ID는 건너뛰고, 새 ID면 추가한다. 반환: (추가, 중복).
  public static func merge(_ existing: [GlobalMemoryEntry],
                           with imported: [GlobalMemoryEntry]) -> (entries: [GlobalMemoryEntry], added: Int) {
    var ids = Set(existing.map(\.id))
    var out = existing
    var added = 0
    for entry in imported where !entry.isBlank {
      guard !ids.contains(entry.id) else { continue }
      ids.insert(entry.id)
      out.append(entry)
      added += 1
    }
    return (out, added)
  }
}
