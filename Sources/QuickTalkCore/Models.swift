import Foundation

public enum TurnStatus: String, Codable, Equatable { case composing, submitting, thinking, streaming, done, failed }
public enum TurnRole: String, Codable, Equatable { case user, assistant }

public struct Attachment: Codable, Equatable {
  public var name: String
  public var kind: Kind
  /// 원본 파일 경로 — 대화 말풍선에 **썸네일·호버 미리보기**를 다시 그리기 위해 남긴다.
  /// (캡처 파일을 지우는 등으로 사라질 수 있으므로 화면은 아이콘·안내로 폴백한다)
  public var path: String?
  public enum Kind: String, Codable { case text, image, link, file }
  public init(name: String, kind: Kind, path: String? = nil) {
    self.name = name; self.kind = kind; self.path = path
  }

  /// 본문을 인라인으로 보낼 수 있는 텍스트·코드 계열 확장자 (P3: 지원 형식 확대)
  public static let textExtensions: [String] = [
    "md", "markdown", "txt", "text", "rtf", "log",
    "json", "jsonl", "csv", "tsv", "yml", "yaml", "xml", "plist", "toml", "ini", "cfg", "conf", "env",
    "html", "htm", "css", "scss", "js", "mjs", "cjs", "ts", "tsx", "jsx",
    "swift", "py", "rb", "go", "rs", "java", "kt", "kts", "cs", "php",
    "c", "h", "cc", "cpp", "hpp", "m", "mm", "sh", "zsh", "bash", "sql",
    "srt", "vtt", "tex", "bib", "patch", "diff"
  ]
  /// 이미지 확장자
  public static let imageExtensions: [String] = [
    "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff"
  ]
  /// 텍스트로 **추출**해서 보내는 문서(PDF는 텍스트 층만 뽑는다)
  public static let documentExtensions: [String] = ["pdf"]
  /// 첨부 가능한 전체 확장자(파일 선택 패널 필터·검사 공용)
  public static var supportedExtensions: [String] {
    textExtensions + documentExtensions + imageExtensions
  }

  /// 확장자 추출(소문자, 점 제외)
  public static func fileExtension(_ filename: String) -> String {
    (filename as NSString).pathExtension.lowercased()
  }

  public static func isImageName(_ filename: String) -> Bool {
    imageExtensions.contains(fileExtension(filename))
  }

  public static func isSupported(filename: String) -> Bool {
    supportedExtensions.contains(fileExtension(filename))
  }
}

public struct Turn: Codable, Equatable {
  public var id: UUID
  public var role: TurnRole
  public var text: String
  public var attachments: [Attachment]
  public var status: TurnStatus
  /// 응답까지 걸린 시간(ms) — 어시스턴트 턴에만 기록한다. 구버전 기록에는 없는 값(nil).
  public var elapsedMs: Int?
  /// 웹 검색 출처 — 검색을 쓰지 않은 턴·구버전 기록에는 없다(nil).
  public var sources: [TurnSource]?
  /// 이 턴을 만들거나 받은 시각 — "5분 전" 같은 상대 시간 표기에 쓴다.
  /// 구버전 기록에는 없으므로 옵션(nil)이며, 없으면 상대 시간을 표시하지 않는다.
  public var createdAt: Date?
  /// 도우미 도구 실행 기록 — 실제로 실행한 명령·출력(대화 기록에 함께 남는다).
  /// 구버전 기록에는 없는 값(nil)이며, 없으면 실행 카드를 그리지 않는다.
  public var agentEvents: [AgentEvent]?

  public init(id: UUID = UUID(), role: TurnRole, text: String,
              attachments: [Attachment] = [], status: TurnStatus = .done,
              elapsedMs: Int? = nil, sources: [TurnSource]? = nil,
              createdAt: Date? = nil, agentEvents: [AgentEvent]? = nil) {
    self.id = id; self.role = role; self.text = text
    self.attachments = attachments; self.status = status; self.elapsedMs = elapsedMs
    self.sources = sources; self.createdAt = createdAt; self.agentEvents = agentEvents
  }
}

/// 상대 시간 문구 — "방금", "5분 전", "3시간 전", "2일 전", "1주 전",
/// 그보다 오래되면 날짜("10월 14일", 다른 해면 "2025년 10월 14일").
/// 미래 시각(시계 오차)은 "방금"으로 본다.
public enum RelativeTime {
  public static func text(for date: Date, now: Date = Date()) -> String {
    let seconds = now.timeIntervalSince(date)
    guard seconds >= 60 else { return L("방금") }
    let minutes = Int(seconds) / 60
    if minutes < 60 { return Lf("%d분 전", minutes) }
    let hours = minutes / 60
    if hours < 24 { return Lf("%d시간 전", hours) }
    let days = hours / 24
    if days < 7 { return Lf("%d일 전", days) }
    let weeks = days / 7
    if weeks < 5 { return Lf("%d주 전", weeks) }
    return dayFormatter(for: date, now: now).string(from: date)
  }

  /// 절대 시각 — 툴팁·보관함에서 정확한 시각을 함께 보여 줄 때 쓴다.
  public static func absolute(_ date: Date) -> String {
    let f = formatter("M월 d일 HH:mm")
    return f.string(from: date)
  }

  private static func dayFormatter(for date: Date, now: Date) -> DateFormatter {
    let cal = Calendar.current
    let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
    return formatter(sameYear ? "M월 d일" : "yyyy년 M월 d일")
  }

  private static func formatter(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: L10n.effective == .ko ? "ko_KR"
                      : (Locale.preferredLanguages.first ?? "en_US"))
    f.dateFormat = L(pattern)
    return f
  }
}

public struct Conversation: Codable, Equatable {
  public var id: UUID
  public var title: String
  /// 사용자가 직접 바꾼 제목인가 — true면 자동 제목이 절대 덮어쓰지 않는다.
  /// 구버전 기록에는 키가 없으므로 `decodeIfPresent`로 false 처리한다.
  public var titleEdited: Bool
  public var turns: [Turn]
  public var pinned: Bool
  public var updatedAt: Date
  /// 오래된 대화를 압축한 기억 요약 — `summaryThroughTurnID`까지의 턴을 대신한다.
  /// 구버전 기록에는 없는 값(nil)이며, 없으면 전체 턴을 그대로 보낸다.
  public var summary: String?
  /// 요약이 커버하는 마지막 턴 — 이 턴 **다음**부터는 원문 그대로 전송한다.
  public var summaryThroughTurnID: UUID?
  /// 사용자가 "요약 해제"를 눌러 자동 정리를 잠시 멈춘 상태(구버전 nil = false).
  public var compactPaused: Bool?
  /// 이 대화에서만 공통 메모리 주입을 끈다(구버전 nil = false).
  public var commonMemoryDisabled: Bool?
  public init(id: UUID = UUID(), title: String = Conversation.defaultTitle, titleEdited: Bool = false,
              turns: [Turn] = [], pinned: Bool = false, updatedAt: Date = Date(),
              summary: String? = nil, summaryThroughTurnID: UUID? = nil,
              compactPaused: Bool? = nil, commonMemoryDisabled: Bool? = nil) {
    self.id = id; self.title = title; self.titleEdited = titleEdited
    self.turns = turns; self.pinned = pinned; self.updatedAt = updatedAt
    self.summary = summary; self.summaryThroughTurnID = summaryThroughTurnID
    self.compactPaused = compactPaused
    self.commonMemoryDisabled = commonMemoryDisabled
  }

  private enum CodingKeys: String, CodingKey {
    case id, title, titleEdited, turns, pinned, updatedAt
    case summary, summaryThroughTurnID, compactPaused, commonMemoryDisabled
  }
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    id = try c.decode(UUID.self, forKey: .id)
    title = try c.decode(String.self, forKey: .title)
    titleEdited = try c.decodeIfPresent(Bool.self, forKey: .titleEdited) ?? false
    turns = try c.decode([Turn].self, forKey: .turns)
    pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    summary = try c.decodeIfPresent(String.self, forKey: .summary)
    summaryThroughTurnID = try c.decodeIfPresent(UUID.self, forKey: .summaryThroughTurnID)
    compactPaused = try c.decodeIfPresent(Bool.self, forKey: .compactPaused)
    commonMemoryDisabled = try c.decodeIfPresent(Bool.self, forKey: .commonMemoryDisabled)
  }

  /// 실제로 쓸 수 있는 요약 — 경계 턴이 사라졌으면(기록 편집 등) nil로 본다.
  public var activeSummary: String? {
    guard let summary, !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          summaryBoundaryIndex != nil else { return nil }
    return summary
  }

  /// 요약 경계(마지막으로 요약된 턴)의 인덱스.
  public var summaryBoundaryIndex: Int? {
    guard let summaryThroughTurnID else { return nil }
    return turns.firstIndex { $0.id == summaryThroughTurnID }
  }

  /// 요약에 포함된 턴 수(배너 문구용).
  public var summarizedTurnCount: Int {
    (summaryBoundaryIndex ?? -1) + 1
  }

  /// 사용자가 자동 정리를 멈췄는가.
  public var autoCompactPaused: Bool { compactPaused ?? false }

  /// 제목이 없는 새 대화의 기본 이름
  public static let defaultTitle = "새 대화"

  /// 여러 줄·연속 공백을 한 줄로 접고 `limit`자에서 말줄임한 제목.
  /// 예: "  오늘\n네이버   뉴스 " → "오늘 네이버 뉴스"
  public static func derivedTitle(from text: String, limit: Int = 30) -> String {
    let flat = text
      .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    guard !flat.isEmpty else { return "" }
    guard flat.count > limit else { return flat }
    let cut = String(flat.prefix(limit)).trimmingCharacters(in: .whitespaces)
    return cut + "…"
  }

  /// 첫 질문(텍스트, 없으면 첫 첨부 이름)으로 만든 제목. 만들 수 없으면 빈 문자열.
  public var autoTitle: String {
    guard let first = turns.first(where: {
      $0.role == .user &&
        (!$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.attachments.isEmpty)
    }) else { return "" }
    let text = first.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      ? (first.attachments.first?.name ?? "")
      : first.text
    return Self.derivedTitle(from: text)
  }

  /// 화면에 보여줄 제목 — 사용자가 바꾼 제목 > 저장된 제목 > 첫 질문 > "새 대화".
  /// 구버전 기록처럼 제목이 "새 대화"로 저장된 경우에도 첫 질문을 바로 보여 준다.
  public var displayTitle: String {
    if titleEdited { return title.isEmpty ? L(Self.defaultTitle) : title }
    if !title.isEmpty && title != Self.defaultTitle { return title }
    let auto = autoTitle
    return auto.isEmpty ? L(Self.defaultTitle) : auto
  }

  /// 첫 질문으로 자동 제목을 채운다(사용자가 바꾼 제목은 건드리지 않는다).
  @discardableResult
  public mutating func applyAutoTitle() -> Bool {
    guard !titleEdited, title.isEmpty || title == Self.defaultTitle else { return false }
    let auto = autoTitle
    guard !auto.isEmpty, auto != title else { return false }
    title = auto
    return true
  }

  /// 사용자가 제목을 바꾼다 — 빈 제목은 거부. 이후 자동 제목이 덮지 않도록 표시한다.
  @discardableResult
  public mutating func rename(to newTitle: String) -> Bool {
    let t = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    title = t
    titleEdited = true
    return true
  }

  /// 검색어와 처음 일치하는 턴(질문·응답 어느 쪽이든).
  /// 보관함에서 검색 결과를 열 때 그 위치로 스크롤·강조하는 데 쓴다. 빈 검색어면 nil.
  public func firstTurn(matching query: String) -> Turn? {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty else { return nil }
    return turns.first {
      $0.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
  }
}
