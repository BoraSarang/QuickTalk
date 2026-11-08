import Foundation

/// 모델 한 개의 **참고 정보** — models.dev 레지스트리에서 가져온다.
///
/// 원칙: 이 정보는 **표시용**이다. 값이 없으면 추측해서 채우지 않고 `nil`/빈 배열로 둔다.
/// 실제 전송 파라미터(추론 강도 등)는 이번 버전에서 바꾸지 않는다.
public struct ModelInfo: Codable, Hashable, Sendable {
  /// 서버가 알려 준 모델 ID(목록 순서 유지의 기준)
  public var id: String
  /// 사람이 읽는 이름 — 레지스트리에 없으면 ID와 같다.
  public var name: String
  /// 컨텍스트 토큰 수
  public var context: Int?
  /// 최대 출력 토큰 수
  public var output: Int?
  /// 입력 형식 — text, image, video, pdf …
  public var input: [String]
  /// 도구 호출 지원
  public var toolCall: Bool
  /// 추론(thinking) 지원
  public var reasoning: Bool
  /// 첨부(이미지 등) 지원
  public var attachment: Bool
  /// 추론 강도 값 — low, high, max …
  public var effort: [String]
  /// 100만 토큰당 입력 비용(USD) — 레지스트리에 있을 때만
  public var inputCost: Double?
  /// 100만 토큰당 출력 비용(USD)
  public var outputCost: Double?
  /// 정보 출처(models.dev 프로바이더 ID). 없으면 레지스트리 미매칭.
  public var source: String?

  public init(id: String, name: String? = nil, context: Int? = nil, output: Int? = nil,
              input: [String] = [], toolCall: Bool = false, reasoning: Bool = false,
              attachment: Bool = false, effort: [String] = [],
              inputCost: Double? = nil, outputCost: Double? = nil, source: String? = nil) {
    self.id = id
    self.name = (name?.isEmpty == false ? name! : id)
    self.context = context
    self.output = output
    self.input = input
    self.toolCall = toolCall
    self.reasoning = reasoning
    self.attachment = attachment
    self.effort = effort
    self.inputCost = inputCost
    self.outputCost = outputCost
    self.source = source
  }

  /// 레지스트리에서 온 정보가 하나라도 있는가 — 없으면 화면은 "정보 없음"이다.
  public var hasDetails: Bool {
    context != nil || output != nil || !input.isEmpty || toolCall || reasoning
      || !effort.isEmpty || inputCost != nil || outputCost != nil
  }

  /// 무료로 보이는가 — **과장하지 않는다**: ID가 `-free`이거나 비용이 명시적으로 0일 때만.
  public var looksFree: Bool {
    if id.lowercased().hasSuffix("-free") { return true }
    if let inputCost, let outputCost, inputCost == 0, outputCost == 0 { return true }
    return false
  }

  /// 레지스트리 점수 — 같은 ID가 여러 프로바이더에 있을 때 **정보가 많은 쪽**을 고른다.
  var detailScore: Int {
    var score = 0
    if context != nil { score += 4 }
    if output != nil { score += 2 }
    score += min(input.count, 3)
    if toolCall { score += 1 }
    if reasoning { score += 1 }
    if !effort.isEmpty { score += 1 }
    if inputCost != nil { score += 1 }
    return score
  }
}

/// 프로바이더 한 곳의 모델 카탈로그 캐시 한 건.
public struct ModelCatalogEntry: Codable, Equatable, Sendable {
  public var providerID: String
  public var baseURL: String
  public var fetchedAt: Date
  public var models: [ModelInfo]

  public init(providerID: String, baseURL: String, fetchedAt: Date = Date(),
              models: [ModelInfo]) {
    self.providerID = providerID
    self.baseURL = baseURL
    self.fetchedAt = fetchedAt
    self.models = models
  }

  public func isFresh(now: Date = Date()) -> Bool {
    now.timeIntervalSince(fetchedAt) < ModelCatalog.ttl
  }

  public func info(_ id: String) -> ModelInfo? {
    models.first { $0.id == id }
  }
}

/// models.dev 레지스트리 — 235개 프로바이더의 모델 메타데이터.
///
/// 전체 5.9MB를 저장하지 않는다. 여기서는 **ID별 최선 항목**만 뽑아 두고,
/// 캐시 파일에는 현재 프로바이더의 모델에 매칭된 것만 저장한다(수십 KB).
public struct ModelsDevRegistry: Sendable {
  /// 소문자 모델 ID → 가장 정보가 많은 항목
  public let index: [String: ModelInfo]
  /// 레지스트리에 등장한 프로바이더 수(로그·진단용)
  public let providerCount: Int

  public init(index: [String: ModelInfo], providerCount: Int) {
    self.index = index
    self.providerCount = providerCount
  }

  /// JSON 파싱 — 순수 함수라 테스트가 직접 검증한다.
  public init(data: Data) throws {
    guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw ModelCatalogError.invalidRegistry
    }
    var index: [String: ModelInfo] = [:]
    let providers = root.keys.sorted()
    // `opencode`를 마지막에 처리해, 같은 점수면 opencode 정보를 우선한다.
    let ordered = providers.filter { $0 != "opencode" } + (providers.contains("opencode") ? ["opencode"] : [])
    for provider in ordered {
      guard let body = root[provider] as? [String: Any],
            let models = body["models"] as? [String: Any] else { continue }
      for (modelID, raw) in models {
        guard let dict = raw as? [String: Any] else { continue }
        let info = Self.info(id: modelID, dict: dict, provider: provider)
        let key = modelID.lowercased()
        if let existing = index[key] {
          if info.detailScore > existing.detailScore { index[key] = info }
        } else {
          index[key] = info
        }
      }
    }
    self.index = index
    self.providerCount = root.count
  }

  private static func info(id: String, dict: [String: Any], provider: String) -> ModelInfo {
    let limit = dict["limit"] as? [String: Any]
    let modalities = dict["modalities"] as? [String: Any]
    let inputs = (modalities?["input"] as? [String]) ?? []
    let cost = dict["cost"] as? [String: Any]
    var effort: [String] = []
    if let options = dict["reasoning_options"] as? [[String: Any]] {
      for option in options where (option["type"] as? String) == "effort" {
        effort += (option["values"] as? [String]) ?? []
      }
    }
    let attachment = (dict["attachment"] as? Bool) ?? false
    return ModelInfo(
      id: id,
      name: dict["name"] as? String,
      context: intValue(limit?["context"]),
      output: intValue(limit?["output"]),
      input: inputs,
      toolCall: (dict["tool_call"] as? Bool) ?? false,
      reasoning: (dict["reasoning"] as? Bool) ?? false,
      attachment: attachment || inputs.contains { ["image", "video", "pdf"].contains($0) },
      effort: effort,
      inputCost: doubleValue(cost?["input"]),
      outputCost: doubleValue(cost?["output"]),
      source: provider)
  }

  private static func intValue(_ raw: Any?) -> Int? {
    if let n = raw as? Int { return n }
    if let n = raw as? NSNumber { return n.intValue }
    if let s = raw as? String { return Int(s) }
    return nil
  }

  private static func doubleValue(_ raw: Any?) -> Double? {
    if let n = raw as? Double { return n }
    if let n = raw as? NSNumber { return n.doubleValue }
    if let s = raw as? String { return Double(s) }
    return nil
  }
}

public enum ModelCatalogError: Error, Equatable {
  case invalidRegistry
}

/// 모델 카탈로그 캐시 — 순수 I/O·병합 규칙만 둔다.
///
/// 새로고침 시점은 UI(`UIStore`)가 정한다. 여기서는 **TTL 판정·저장·병합**만 책임진다.
public enum ModelCatalog {
  /// 캐시 수명 — 24시간. 수동 ⟳는 언제나 가능하다.
  public static let ttl: TimeInterval = 24 * 60 * 60
  /// models.dev 레지스트리 주소(OpenCode와 같은 출처)
  public static let registryURL = URL(string: "https://models.dev/api.json")!
  /// 전체 레지스트리를 읽을 때의 상한 — 손상·비정상 응답 방어
  public static let maxRegistryBytes = 20 * 1024 * 1024

  public static var cacheURL: URL {
    PersistenceService.directory.appendingPathComponent("model-catalog.json")
  }

  /// 캐시 파일 형식 — 버전을 두어 나중에 바꿔도 조용히 버린다.
  private struct CacheFile: Codable {
    var version: Int = 1
    var entries: [String: ModelCatalogEntry]
  }

  public static func load(from url: URL? = nil) -> [String: ModelCatalogEntry] {
    guard let data = try? Data(contentsOf: url ?? cacheURL),
          let file = try? JSONDecoder().decode(CacheFile.self, from: data),
          file.version == 1 else { return [:] }
    return file.entries
  }

  public static func save(_ entries: [String: ModelCatalogEntry],
                          to url: URL? = nil) throws {
    let target = url ?? cacheURL
    let data = try JSONEncoder().encode(CacheFile(entries: entries))
    try FileManager.default.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    try data.write(to: target, options: .atomic)
  }

  /// 서버가 준 ID 순서를 유지하면서 레지스트리 정보를 붙인다.
  public static func merge(ids: [String], registry: ModelsDevRegistry) -> [ModelInfo] {
    ids.map { id in
      guard var info = registry.index[id.lowercased()] else {
        return ModelInfo(id: id)
      }
      // 서버가 준 ID 표기를 그대로 쓴다(레지스트리 표기와 대소문자가 다를 수 있다).
      info.id = id
      return info
    }
  }

  /// 캐시 항목을 새 목록과 합친다 — 레지스트리 조회가 실패해도 **아는 정보는 유지**한다.
  public static func merge(ids: [String], previous: ModelCatalogEntry?) -> [ModelInfo] {
    guard let previous else { return ids.map { ModelInfo(id: $0) } }
    let old = Dictionary(uniqueKeysWithValues: previous.models.map { ($0.id, $0) })
    return ids.map { old[$0] ?? ModelInfo(id: $0) }
  }
}
