import Foundation

// 후속 질문 제안(v0.32) — **모델 호출과 화면 사이의 순수 규칙**만 둔다.
//
// 흐름
//   ① 응답이 정상 종료되면 `isEligible` 로 거른다(짧은 답변·오류·중단 제외)
//   ② `prompt(...)` 로 짧은 생성 요청을 만든다(질문 600자·답변 500자)
//   ③ 모델 응답을 `parse(...)` 로 정리한다(번호·불릿·JSON 허용, 중복 제거)
//   ④ 실패하면 `fallback(...)` 이 **항상 3개**를 만든다(모델 호출 0)
//
// 문구는 앱 표시 언어를 따른다(영어 UI면 영어 칩). 답변 언어와 다를 수 있으나,
// 폴백은 어차피 고정 문구라 사용자가 읽는 언어를 따르는 편이 자연스럽다.

public enum FollowUpSuggest {
  /// 프롬프트에 싣는 질문 길이 상한.
  public static let maxQuestionChars = 600
  /// 프롬프트에 싣는 답변 길이 상한.
  public static let maxAnswerChars = 500
  /// 기본 칩 개수.
  public static let defaultCount = 3
  /// 이보다 짧은 답변에는 칩을 달지 않는다(칩이 답변보다 커진다).
  public static let minimumAnswerChars = 80
  /// 칩 하나의 최대 길이 — 넘으면 목록에서 버린다.
  public static let maxChipChars = 80

  /// 후속 질문을 만들어도 되는 응답인가.
  public static func isEligible(question: String, answer: String) -> Bool {
    let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !q.isEmpty, a.count >= minimumAnswerChars else { return false }
    // 오류 문구는 표시 언어에 따라 "(오류 …)" / "(Error …)" 로 시작한다.
    if a.hasPrefix("(오류") || a.hasPrefix("(Error") { return false }
    // 사용자가 중지한 응답의 꼬리표
    if a.hasSuffix("⏹ 중지됨") || a.contains("\n\n⏹ 중지됨") { return false }
    return true
  }

  /// 모델에 보낼 생성 프롬프트 — 짧고, 언어·길이·형식을 못 박는다.
  public static func prompt(question: String, answer: String, count: Int = defaultCount) -> String {
    let q = clamped(question, maxQuestionChars)
    let a = clamped(answer, maxAnswerChars)
    let n = max(1, count)
    return """
    아래 대화를 이어갈 만한 **후속 질문** \(n)개를 만드세요.

    규칙:
    - 답변과 같은 언어로 씁니다.
    - 각 12~28자, 한 줄, 물음표로 끝냅니다.
    - 이미 답한 내용을 다시 묻지 않습니다.
    - 번호와 질문만 씁니다. 설명·머리말·따옴표는 쓰지 않습니다.

    [질문]
    \(q)

    [답변]
    \(a)
    """
  }

  /// 모델 응답 → 칩 목록. 번호 목록·불릿·JSON 배열을 모두 받아 준다.
  public static func parse(_ raw: String, limit: Int = defaultCount) -> [String] {
    let cleaned = raw
      .components(separatedBy: .newlines)
      .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("```") }
      .joined(separator: "\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)

    var candidates: [String] = []
    if let json = parseJSONArray(cleaned) {
      candidates = json
    } else {
      candidates = cleaned
        .components(separatedBy: .newlines)
        .map(stripBullet)
    }
    return normalize(candidates, limit: limit, requireQuestionMark: true)
  }

  /// 모델을 못 쓰거나 실패했을 때의 **무료 문구** — 항상 `count`개를 채운다.
  public static func fallback(question: String, answer: String, count: Int = defaultCount) -> [String] {
    let lower = answer.lowercased()
    var candidates: [String] = []
    if lower.contains("오류") || lower.contains("error") || lower.contains("실패")
        || lower.contains("failed") {
      candidates.append(L("이 오류를 고치는 방법은?"))
    }
    if lower.contains("권한") || lower.contains("permission") {
      candidates.append(L("권한은 어떻게 허용해?"))
    }
    if lower.contains("설정") || lower.contains("settings") {
      candidates.append(L("설정에서 어디를 바꾸면 돼?"))
    }
    if answer.contains("`") || lower.contains("func ") || lower.contains("swift") {
      candidates.append(L("코드 예시로 보여줘"))
    }
    candidates.append(contentsOf: [
      L("예시로 보여줘"),
      L("더 자세히 설명해줘"),
      L("다음 단계는 뭐야?"),
      L("표로 정리해줘"),
      L("짧게 요약해줘")
    ])
    return normalize(candidates, limit: count, requireQuestionMark: false)
  }

  // MARK: - 내부

  private static func clamped(_ text: String, _ limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.count > limit else { return trimmed }
    return String(trimmed.prefix(limit)) + "…"
  }

  private static func stripBullet(_ line: String) -> String {
    var s = line.trimmingCharacters(in: .whitespaces)
    // "1." "1)" "-" "•" "*" 같은 머리표 제거
    if let range = s.range(of: #"^\s*(\d+[\.\)]|[-*•‣])\s*"#, options: .regularExpression) {
      s.removeSubrange(range)
    }
    return s.trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
  }

  private static func parseJSONArray(_ text: String) -> [String]? {
    guard let start = text.firstIndex(of: "["),
          let end = text.lastIndex(of: "]"), start < end else { return nil }
    let slice = String(text[start...end])
    guard let data = slice.data(using: .utf8),
          let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return nil }
    let strings = array.compactMap { $0 as? String }
    return strings.isEmpty ? nil : strings
  }

  /// 공백·중복 정리, 길이 제한, 개수 제한.
  private static func normalize(_ candidates: [String], limit: Int,
                                requireQuestionMark: Bool) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for raw in candidates {
      let chip = raw
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'“”‘’ "))
      guard !chip.isEmpty, chip.count <= maxChipChars else { continue }
      // 머리말("규칙:", "후속 질문:") 같은 줄은 질문이 아니다 — 모델 응답만 걸러 낸다.
      if requireQuestionMark,
         !(chip.contains("?") || chip.contains("？") || chip.contains("까")) { continue }
      let key = chip.lowercased()
      guard seen.insert(key).inserted else { continue }
      result.append(chip)
      if result.count >= max(1, limit) { break }
    }
    return result
  }
}
