import Foundation

/// 예약 실행 1회가 남기는 **Markdown 리포트** (v0.26).
///
/// 본문은 모델이 쓴 답변을 그대로 쓰고, 머리말(제목·시각·비서·규칙)과 출처 절만
/// 앱이 붙인다. 출처가 없으면 절을 **통째로 생략**한다(빈 "출처" 제목이 남지 않게).
public struct ReportDocument: Equatable {
  public var title: String
  /// 실행한 비서 이름 — nil 이면 `기본(비서 없음)`.
  public var personaName: String?
  /// 사용자가 등록한 지시문 전문 — 나중에 "무엇을 시켰는지" 확인할 수 있게.
  public var instruction: String
  /// 모델이 쓴 본문(핵심 요약 + 상세).
  public var body: String
  public var sources: [TurnSource]
  public var ranAt: Date
  /// "매일 09:00" 같은 사람용 규칙 설명.
  public var ruleText: String

  public init(title: String, personaName: String? = nil, instruction: String,
              body: String, sources: [TurnSource] = [], ranAt: Date = Date(),
              ruleText: String = "") {
    self.title = title
    self.personaName = personaName
    self.instruction = instruction
    self.body = body
    self.sources = sources
    self.ranAt = ranAt
    self.ruleText = ruleText
  }

  /// 파일에 쓸 Markdown 전문.
  public func markdown(calendar: Calendar = .current) -> String {
    var lines: [String] = []
    lines.append("# " + (title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          ? L("리포트 문서") : title.trimmingCharacters(in: .whitespacesAndNewlines)))
    lines.append("")

    var meta = [ScheduleRule.dateText(ranAt, calendar: calendar)]
    if let personaName, !personaName.isEmpty { meta.append(personaName) }
    if !ruleText.isEmpty { meta.append(ruleText) }
    lines.append("> " + meta.joined(separator: " · "))
    lines.append("")

    let cleanInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
    if !cleanInstruction.isEmpty {
      lines.append("## " + L("지시"))
      lines.append("")
      lines.append("```text")
      lines.append(cleanInstruction)
      lines.append("```")
      lines.append("")
    }

    lines.append("## " + L("결과"))
    lines.append("")
    lines.append(body.trimmingCharacters(in: .whitespacesAndNewlines))
    lines.append("")

    let usableSources = sources.filter { !$0.url.isEmpty }
    if !usableSources.isEmpty {
      lines.append("## " + L("출처"))
      lines.append("")
      for (index, source) in usableSources.enumerated() {
        let label = source.title.isEmpty ? source.domain : source.title
        lines.append("\(index + 1). [\(label)](\(source.url))" +
                     (source.domain.isEmpty ? "" : " — \(source.domain)"))
      }
      lines.append("")
    }
    return lines.joined(separator: "\n")
  }

  // MARK: - 요약

  /// 답변 앞부분에서 **핵심 2~3줄**만 뽑는다(대화 카드·알림에 쓴다).
  ///
  /// 모델에게 별도 형식을 강요하지 않는다 — 작은 모델은 형식을 자주 어긴다.
  /// 대신 첫 줄부터 의미 있는 줄을 고르고, 마크다운 장식(`#`, `-`, `1.`)을 벗긴다.
  public static func summaryPoints(from answer: String,
                                   limit: Int = 3,
                                   maxLength: Int = 120) -> [String] {
    var points: [String] = []
    var inFence = false
    for raw in answer.components(separatedBy: .newlines) {
      var line = raw.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      // 코드 펜스 안쪽은 요약이 아니다 — 펜스를 만나면 닫힐 때까지 건너뛴다.
      if line.hasPrefix("```") { inFence.toggle(); continue }
      if inFence { continue }
      // 표 구분선·구분선은 요약이 아니다.
      if line.hasPrefix("|") { continue }
      if line.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "=" || $0 == "_" }) { continue }
      // 제목 장식
      while line.hasPrefix("#") { line.removeFirst() }
      line = line.trimmingCharacters(in: .whitespaces)
      // 목록 장식
      for marker in ["- ", "* ", "• ", "· "] where line.hasPrefix(marker) {
        line = String(line.dropFirst(marker.count))
      }
      // "1. ", "2) " 같은 번호
      let digits = line.prefix { $0.isNumber }
      if !digits.isEmpty {
        let rest = line.dropFirst(digits.count)
        if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
          line = String(rest.dropFirst(2))
        }
      }
      line = line.trimmingCharacters(in: .whitespaces)
      guard !line.isEmpty else { continue }
      if line.count > maxLength { line = String(line.prefix(maxLength)).trimmingCharacters(in: .whitespaces) + "…" }
      if !points.contains(line) { points.append(line) }
      if points.count >= limit { break }
    }
    return points
  }

  /// 카드·`RunRecord.summary` 에 넣을 한 덩어리 — 점이 없으면 nil.
  public static func summary(from answer: String, limit: Int = 3) -> String? {
    let points = summaryPoints(from: answer, limit: limit)
    return points.isEmpty ? nil : points.joined(separator: "\n")
  }
}
