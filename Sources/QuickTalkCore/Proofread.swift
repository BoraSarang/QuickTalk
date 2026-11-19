import Foundation

// [FEATURE] v0.41 입력 교정 힌트 — 보내기 직전에 한글 맞춤법·띄어쓰기를 살핀다.
//
// 설계 원칙(PLAN_v0.41 §1·§8):
//   · 확실한 것만 알린다. **놓치는 것이 틀린 교정보다 낫다**(정밀도 우선).
//   · 의미·말투·문장 구조는 바꾸지 않는다. 규칙 사전 + 고정밀 띄어쓰기 패턴만.
//   · 온디바이스·동기. 네트워크 0회, 500자 5ms 이하 목표.
//   · Apple FM은 실측(중앙값 2.04초·오교정 13/18)으로 전송 경로에서 제외했다.
//
// 위치는 **UTF-16(NSRange)** 기준이다 — 전송 직전 문자열 교체에 그대로 쓴다.

/// 교정 항목의 분류 — 카드 태그·오타 노트 칩·통계에 쓴다.
public enum ProofreadCategory: String, Codable, CaseIterable, Identifiable, Sendable {
  case spacing
  case spelling
  case punctuation

  public var id: String { rawValue }

  public var displayName: String {
    switch self {
    case .spacing: return L("띄어쓰기")
    case .spelling: return L("맞춤법")
    case .punctuation: return L("문장부호")
    }
  }
}

/// 한 곳의 교정 — `location`/`length` 는 UTF-16 기준.
public struct ProofreadIssue: Identifiable, Equatable, Sendable {
  public let ruleID: String
  public let category: ProofreadCategory
  public let location: Int
  public let length: Int
  public let original: String
  public let replacement: String

  public init(ruleID: String, category: ProofreadCategory,
              location: Int, length: Int,
              original: String, replacement: String) {
    self.ruleID = ruleID
    self.category = category
    self.location = location
    self.length = length
    self.original = original
    self.replacement = replacement
  }

  public var id: String { "\(ruleID)@\(location):\(length)" }
  public var range: NSRange { NSRange(location: location, length: length) }
}

/// 한 번의 검사 결과. 문제가 없으면 `issues` 가 비고 `corrected == original` 이다.
public struct ProofreadResult: Equatable, Sendable {
  public let original: String
  public let corrected: String
  public let issues: [ProofreadIssue]
  public let elapsedMilliseconds: Double

  public init(original: String, corrected: String,
              issues: [ProofreadIssue], elapsedMilliseconds: Double) {
    self.original = original
    self.corrected = corrected
    self.issues = issues
    self.elapsedMilliseconds = elapsedMilliseconds
  }

  public var isClean: Bool { issues.isEmpty }
  public var count: Int { issues.count }

  public func count(of category: ProofreadCategory) -> Int {
    issues.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
  }
}

// MARK: - 엔진

/// 닫힌 규칙 사전으로 한 번에 훑는 교정 엔진.
///
/// - 스레드 안전: 규칙은 첫 호출 때 만들어지고 이후 읽기만 한다.
/// - 실패하지 않는다: 검사 대상이 아니면(짧은 글·한글 없음·너무 김) 빈 결과를 돌려준다.
public enum ProofreadEngine {
  /// 이보다 긴 글은 검사하지 않는다 — 전송 리듬을 지키기 위한 상한.
  public static let maximumLength = 10_000
  /// 카드에 보여 줄 최대 개수(나머지는 `+N곳`).
  public static let maximumIssuesShown = 4
  /// 한 번에 돌려줄 최대 교정 수 — 통계가 폭주하지 않게.
  static let maximumIssues = 40
  /// 후보 상한 — 10,000자 반복문에서도 겹침 해소가 선형에 가깝게 끝나게.
  static let maximumCandidates = 400

  public static func check(_ text: String,
                           ignoring: Set<String> = []) -> ProofreadResult {
    let started = DispatchTime.now().uptimeNanoseconds
    func result(_ issues: [ProofreadIssue]) -> ProofreadResult {
      let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
      let accepted = issues.prefix(maximumIssues)
      return ProofreadResult(original: text,
                             corrected: Self.apply(text, Array(accepted)),
                             issues: Array(accepted),
                             elapsedMilliseconds: elapsed)
    }

    let ns = text as NSString
    guard ns.length > 0, ns.length <= maximumLength, hangulSyllables(ns) >= 2 else {
      return result([])
    }
    let protectedRanges = self.protectedRanges(ns)
    func isProtected(_ range: NSRange) -> Bool {
      protectedRanges.contains { NSIntersectionRange($0, range).length > 0 }
    }

    var candidates: [Candidate] = []
    var order = 0

    // 1) 닫힌 사전 — 한 번의 정규식 패스로 모두 찾는다(긴 표현 우선).
    let wordMatches = WordRules.regex.matches(in: text,
                                              range: NSRange(location: 0, length: ns.length))
    for m in wordMatches {
      if candidates.count >= maximumCandidates { break }
      order += 1
      let range = m.range
      guard range.length > 0, !isProtected(range) else { continue }
      let original = ns.substring(with: range)
      guard let fix = WordRules.fix(for: original) else { continue }
      guard !isIgnoring(original, ignoring) else { continue }
      if !passes(fix.boundary, ns, range) { continue }
      candidates.append(Candidate(ruleID: fix.id, category: fix.category,
                                  range: range, original: original,
                                  replacement: fix.right, order: order))
    }

    // 2) 고정밀 띄어쓰기 패턴
    for rule in PatternRules.all {
      if candidates.count >= maximumCandidates { break }
      let matches = rule.regex.matches(in: text,
                                       range: NSRange(location: 0, length: ns.length))
      for m in matches {
        if candidates.count >= maximumCandidates { break }
        order += 1
        let range = m.range
        guard range.length > 0, !isProtected(range) else { continue }
        let original = ns.substring(with: range)
        guard !isIgnoring(original, ignoring) else { continue }
        let replacement = rule.regex.replacementString(for: m, in: text,
                                                       offset: 0,
                                                       template: rule.template)
        guard replacement != original else { continue }   // 이미 올바른 표기
        candidates.append(Candidate(ruleID: rule.id, category: rule.category,
                                    range: range, original: original,
                                    replacement: replacement, order: order))
      }
    }

    // 3) 문장부호 — 앞 공백만 지운다(줄임표·숫자 쉼표는 건드리지 않는다).
    for rule in PunctuationRules.all {
      if candidates.count >= maximumCandidates { break }
      let matches = rule.regex.matches(in: text,
                                       range: NSRange(location: 0, length: ns.length))
      for m in matches {
        if candidates.count >= maximumCandidates { break }
        order += 1
        let range = m.range
        guard range.length > 0, !isProtected(range) else { continue }
        let original = ns.substring(with: range)
        guard !isIgnoring(original, ignoring) else { continue }
        let replacement = rule.regex.replacementString(for: m, in: text,
                                                       offset: 0,
                                                       template: rule.template)
        guard replacement != original else { continue }
        candidates.append(Candidate(ruleID: rule.id, category: rule.category,
                                    range: range, original: original,
                                    replacement: replacement, order: order))
      }
    }

    return result(resolve(candidates))
  }

  /// [무시] 목록과 비교한다 — 문장부호 규칙은 앞 공백까지 원문에 포함하므로
  /// (예: `" ,"`) 공백을 다듬은 키도 함께 본다. 오타 노트는 다듬은 키를 저장한다.
  private static func isIgnoring(_ original: String, _ ignoring: Set<String>) -> Bool {
    guard !ignoring.isEmpty else { return false }
    if ignoring.contains(original) { return true }
    let trimmed = original.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed != original && ignoring.contains(trimmed)
  }

  // MARK: 겹침 해소

  private struct Candidate {
    let ruleID: String
    let category: ProofreadCategory
    let range: NSRange
    let original: String
    let replacement: String
    let order: Int
  }

  /// 같은 구간에 여러 규칙이 걸리면 **가장 긴 것 하나**만 남기고, 앞에서부터 겹치지 않게 고른다.
  private static func resolve(_ candidates: [Candidate]) -> [ProofreadIssue] {
    let sorted = candidates.sorted { a, b in
      if a.range.length != b.range.length { return a.range.length > b.range.length }
      if a.range.location != b.range.location { return a.range.location < b.range.location }
      return a.order < b.order
    }
    var accepted: [Candidate] = []
    var occupied = IndexSet()
    for c in sorted {
      let lower = c.range.location
      let upper = c.range.location + c.range.length
      guard lower >= 0, upper > lower else { continue }
      if occupied.intersects(integersIn: lower..<upper) { continue }
      occupied.insert(integersIn: lower..<upper)
      accepted.append(c)
      if accepted.count >= maximumIssues { break }
    }
    return accepted
      .sorted { $0.range.location < $1.range.location }
      .map {
        ProofreadIssue(ruleID: $0.ruleID, category: $0.category,
                       location: $0.range.location, length: $0.range.length,
                       original: $0.original, replacement: $0.replacement)
      }
  }

  /// 뒤에서부터 교체한다 — 앞 구간의 위치가 흔들리지 않는다.
  private static func apply(_ text: String, _ issues: [ProofreadIssue]) -> String {
    guard !issues.isEmpty else { return text }
    let result = NSMutableString(string: text)
    for issue in issues.sorted(by: { $0.location > $1.location }) {
      guard issue.location >= 0,
            issue.location + issue.length <= result.length else { continue }
      result.replaceCharacters(in: issue.range, with: issue.replacement)
    }
    return result as String
  }

  // MARK: 안전 필터

  /// URL·이메일·파일 경로·백틱 코드 — 이 안의 글자는 고치지 않는다.
  private static func protectedRanges(_ ns: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    let full = NSRange(location: 0, length: ns.length)
    for re in ProtectionPatterns.all {
      re.enumerateMatches(in: ns as String, range: full) { match, _, _ in
        if let match { ranges.append(match.range) }
      }
    }
    return ranges
  }

  private static func passes(_ boundary: WordRules.Boundary,
                             _ ns: NSString, _ range: NSRange) -> Bool {
    switch boundary {
    case .none:
      return true
    case .left:
      return range.location == 0 || !isHangul(ns.character(at: range.location - 1))
    case .both:
      if range.location > 0, isHangul(ns.character(at: range.location - 1)) {
        return false
      }
      let end = range.location + range.length
      return end >= ns.length || !isHangul(ns.character(at: end))
    }
  }

  private static func hangulSyllables(_ ns: NSString) -> Int {
    var count = 0
    for i in 0..<ns.length where isHangul(ns.character(at: i)) {
      count += 1
      if count >= 2 { return count }
    }
    return count
  }

  private static func isHangul(_ ch: unichar) -> Bool {
    (0xAC00...0xD7A3).contains(Int(ch))
  }
}

// MARK: - 규칙

/// 닫힌 사전 — **항상 틀린** 표기만 넣는다. 문맥에 따라 맞기도 한 것은 넣지 않는다.
/// (예: `안되` 전체 치환, `한번`, `이야기 하고`, `완료 해야` 는 제외)
private enum WordRules {
  /// 앞뒤 경계 — 더 긴 단어 안에서 우연히 걸리는 것을 막는다.
  enum Boundary {
    /// 경계를 보지 않는다(항상 틀리는 표기).
    case none
    /// 앞만 본다 — `할려고`·`할려면` 처럼 뒤에 어미가 붙는 표현.
    case left
    /// 앞뒤 모두 한글이 아니어야 한다(`금새` 같은 독립 단어).
    case both
  }

  struct Fix {
    let wrong: String
    let right: String
    let id: String
    let category: ProofreadCategory
    let boundary: Boundary
  }

  static let fixes: [Fix] = [
    // 맞춤법 — 사전
    .init(wrong: "몇일", right: "며칠", id: "spelling.myeochil", category: .spelling, boundary: .none),
    .init(wrong: "웬지", right: "왠지", id: "spelling.waenji", category: .spelling, boundary: .none),
    .init(wrong: "왠만", right: "웬만", id: "spelling.waenman", category: .spelling, boundary: .both),
    .init(wrong: "왠일", right: "웬일", id: "spelling.waenil", category: .spelling, boundary: .none),
    .init(wrong: "오랬동안", right: "오랫동안", id: "spelling.oraet-dongan", category: .spelling, boundary: .none),
    .init(wrong: "오랫만", right: "오랜만", id: "spelling.oraenman", category: .spelling, boundary: .none),
    .init(wrong: "어의없", right: "어이없", id: "spelling.eouieop", category: .spelling, boundary: .none),
    .init(wrong: "금새", right: "금세", id: "spelling.geumse", category: .spelling, boundary: .both),
    .init(wrong: "역활", right: "역할", id: "spelling.yeokhal", category: .spelling, boundary: .none),
    .init(wrong: "댓가", right: "대가", id: "spelling.daega", category: .spelling, boundary: .none),
    .init(wrong: "설겆이", right: "설거지", id: "spelling.seolgeoji", category: .spelling, boundary: .none),
    .init(wrong: "띄워쓰기", right: "띄어쓰기", id: "spelling.ttieosseugi", category: .spelling, boundary: .none),
    .init(wrong: "안되요", right: "안 돼요", id: "spelling.andwaeyo", category: .spelling, boundary: .none),
    .init(wrong: "안됬", right: "안 됐", id: "spelling.andwaet", category: .spelling, boundary: .none),
    .init(wrong: "됬", right: "됐", id: "spelling.dwaet", category: .spelling, boundary: .none),
    .init(wrong: "됀", right: "된", id: "spelling.doen", category: .spelling, boundary: .none),
    .init(wrong: "되요", right: "돼요", id: "spelling.dwaeyo", category: .spelling, boundary: .none),
    .init(wrong: "어떻해", right: "어떡해", id: "spelling.eotteokhae", category: .spelling, boundary: .none),
    .init(wrong: "뵈요", right: "봬요", id: "spelling.bwaeyo", category: .spelling, boundary: .none),
    .init(wrong: "있슴", right: "있음", id: "spelling.isseum", category: .spelling, boundary: .none),
    .init(wrong: "없슴", right: "없음", id: "spelling.eopseum", category: .spelling, boundary: .none),
    .init(wrong: "하겟", right: "하겠", id: "spelling.haget", category: .spelling, boundary: .none),
    .init(wrong: "되겟", right: "되겠", id: "spelling.doegget", category: .spelling, boundary: .none),
    .init(wrong: "했슴", right: "했음", id: "spelling.haetseum", category: .spelling, boundary: .none),
    .init(wrong: "했읍니다", right: "했습니다", id: "spelling.haeteupnida", category: .spelling, boundary: .none),
    .init(wrong: "갔읍니다", right: "갔습니다", id: "spelling.gateupnida", category: .spelling, boundary: .none),
    .init(wrong: "할려", right: "하려", id: "spelling.hallyeo", category: .spelling, boundary: .left),
    .init(wrong: "갈려", right: "가려", id: "spelling.gallyeo", category: .spelling, boundary: .left),
    .init(wrong: "볼려", right: "보려", id: "spelling.bollyeo", category: .spelling, boundary: .left),
    .init(wrong: "줄려", right: "주려", id: "spelling.jullyeo", category: .spelling, boundary: .left),
    .init(wrong: "먹을려", right: "먹으려", id: "spelling.meogeullyeo", category: .spelling, boundary: .left),
    .init(wrong: "보낼려", right: "보내려", id: "spelling.bonaellyeo", category: .spelling, boundary: .left),
    .init(wrong: "만날려", right: "만나려", id: "spelling.mannallyeo", category: .spelling, boundary: .left),
    .init(wrong: "마실려", right: "마시려", id: "spelling.masillyeo", category: .spelling, boundary: .left),
    .init(wrong: "모를려", right: "모르려", id: "spelling.moreullyeo", category: .spelling, boundary: .left),
    // -ㄹ께 → -ㄹ게 (항상 틀린다)
    .init(wrong: "할께", right: "할게", id: "spelling.halkke", category: .spelling, boundary: .none),
    .init(wrong: "갈께", right: "갈게", id: "spelling.galkke", category: .spelling, boundary: .none),
    .init(wrong: "볼께", right: "볼게", id: "spelling.bolkke", category: .spelling, boundary: .none),
    .init(wrong: "줄께", right: "줄게", id: "spelling.julkke", category: .spelling, boundary: .none),
    .init(wrong: "올께", right: "올게", id: "spelling.olkke", category: .spelling, boundary: .none),
    .init(wrong: "드릴께", right: "드릴게", id: "spelling.deurilkke", category: .spelling, boundary: .none),
    .init(wrong: "먹을께", right: "먹을게", id: "spelling.meogeulkke", category: .spelling, boundary: .none),
    .init(wrong: "마실께", right: "마실게", id: "spelling.masilkke", category: .spelling, boundary: .none),
    .init(wrong: "보낼께", right: "보낼게", id: "spelling.bonaelkke", category: .spelling, boundary: .none),
    .init(wrong: "만날께", right: "만날게", id: "spelling.mannalkke", category: .spelling, boundary: .none),
    .init(wrong: "쓸께", right: "쓸게", id: "spelling.sseulkke", category: .spelling, boundary: .none),
    .init(wrong: "알께", right: "알게", id: "spelling.alkke", category: .spelling, boundary: .none),
    .init(wrong: "모를께", right: "모를게", id: "spelling.moreulkke", category: .spelling, boundary: .none),
    .init(wrong: "될께", right: "될게", id: "spelling.doelkke", category: .spelling, boundary: .none)
  ]

  private static let lookup: [String: Fix] = {
    var map: [String: Fix] = [:]
    for fix in fixes { map[fix.wrong] = fix }
    return map
  }()

  /// 긴 표현을 먼저 두어 정규식이 최장 일치를 고르게 한다.
  static let regex: NSRegularExpression = {
    let pattern = fixes
      .sorted { $0.wrong.count > $1.wrong.count }
      .map { NSRegularExpression.escapedPattern(for: $0.wrong) }
      .joined(separator: "|")
    return try! NSRegularExpression(pattern: pattern)
  }()

  static func fix(for wrong: String) -> Fix? { lookup[wrong] }
}

private struct PatternRule {
  let id: String
  let category: ProofreadCategory
  let regex: NSRegularExpression
  let template: String

  init(_ id: String, _ category: ProofreadCategory,
       _ pattern: String, _ template: String) {
    self.id = id
    self.category = category
    self.regex = try! NSRegularExpression(pattern: pattern)
    self.template = template
  }
}

/// 띄어쓰기 — 형태 경계가 명확한 것만. `$1` 은 어미, `$2` 는 뒤 말이다.
private enum PatternRules {
  /// "할 수 / 할 것 / 할 줄 / 할 때 / 할 거" 처럼 **관형형 + 의존 명사**는 항상 띄어 쓴다.
  /// `한때`(단어)와 `그때`·`이때` 는 어간 목록에 없어 건드리지 않는다.
  private static let stems = "할|줄|볼|될|갈|올|먹을|마실|보낼|만날|쓸|알|모를|드릴|없을|있을"

  static let all: [PatternRule] = [
    PatternRule("spacing.su", .spacing, "(\(stems))수(?!록)", "$1 수"),           // 할수록 제외
    PatternRule("spacing.geot", .spacing, "(\(stems))것", "$1 것"),
    PatternRule("spacing.jul", .spacing, "(\(stems))줄(?!기)", "$1 줄"),          // 줄기(명사) 제외
    PatternRule("spacing.tae", .spacing, "(\(stems))때", "$1 때"),
    PatternRule("spacing.geo", .spacing, "(\(stems))거(?!리|기|울|래|치)", "$1 거"),
    PatternRule("spacing.this-week", .spacing, "(이번|다음|지난|저번|요번)주", "$1 주"),
    PatternRule("spacing.this-month", .spacing, "(이번|다음|지난|저번|요번)달", "$1 달"),
    PatternRule("spacing.month-count", .spacing, "(한|두|세|네|몇|여러|두세|서너)달", "$1 달"),
    PatternRule("spacing.myeot", .spacing, "몇(시|분|개|명|번|월|년|군데|가지)", "몇 $1"),
    PatternRule("spacing.jal-butak", .spacing, "잘부탁", "잘 부탁"),
    // `부탁 드리` → `부탁드리` 는 표준 표기다. 이미 붙어 있으면 치환이 같아 자동으로 버려진다.
    // `드릴게요`·`드릴까요` 는 어간이 `드릴` 로 바뀌므로 함께 받는다.
    PatternRule("spacing.deari", .spacing, "(부탁|연락|말씀) ?(드리|드릴|드려|드립)", "$1$2"),
    PatternRule("spacing.eotteoke-hae", .spacing, "어떻게해", "어떻게 해")
  ]
}

private enum PunctuationRules {
  /// 문장부호 **앞** 공백만 지운다. `1,000`·`...`·이모지는 건드리지 않는다.
  static let all: [PatternRule] = [
    PatternRule("punctuation.space-before", .punctuation,
                "(?<=\\S) +([,.?!])(?!\\.)", "$1")
  ]
}

private enum ProtectionPatterns {
  static let all: [NSRegularExpression] = [
    try! NSRegularExpression(pattern: #"https?://[^\s]+"#),
    try! NSRegularExpression(pattern: #"www\.[^\s]+"#),
    try! NSRegularExpression(pattern: #"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#),
    try! NSRegularExpression(pattern: #"~/[^\s]+"#),
    try! NSRegularExpression(pattern: #"(?<!\w)/Users/[^\s]+"#),
    try! NSRegularExpression(pattern: #"`[^`\n]*`"#)
  ]
}
