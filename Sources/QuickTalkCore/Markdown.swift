import Foundation

/// 목록 항목 — 들여쓰기 깊이를 보존해 하위 목록을 그린다.
public struct MarkdownItem: Equatable {
  public var text: String
  /// 0 = 최상위, 1~3 = 하위(공백 2칸당 1단계)
  public var depth: Int
  /// 체크박스 항목(`- [ ]` / `- [x]`)이면 true/false, 일반 항목이면 nil
  public var task: Bool?

  public init(text: String, depth: Int = 0, task: Bool? = nil) {
    self.text = text
    self.depth = depth
    self.task = task
  }
}

/// 마크다운 표시용 미니 파서 — 원문은 그대로 두고 **표시만** 바꾼다(복사·검색은 소스 기준).
/// CapsuleStash `MarkdownBody`(T-26)의 파서를 QuickTalk용으로 옮기고, AI 답변에 자주 나오는
/// 번호 목록 · 중첩 들여쓰기 · 구분선을 더했다. 순수 함수라 테스트가 직접 검증한다.
public enum MarkdownSegment: Equatable {
  case heading(level: Int, text: String)
  case quote(lines: [String])
  case bullet(items: [MarkdownItem])
  case numbered(items: [MarkdownItem])
  case code(language: String, lines: [String])
  case table(header: [String], rows: [[String]])
  case paragraph(lines: [String])
  case rule
  case blank

  public static func parse(_ text: String) -> [MarkdownSegment] {
    guard !text.isEmpty else { return [] }
    var segments: [MarkdownSegment] = []
    var inFence = false
    var fenceLanguage = ""
    var fenceLines: [String] = []
    var quoteLines: [String] = []
    var bullets: [MarkdownItem] = []
    var numbers: [MarkdownItem] = []
    var paragraphLines: [String] = []

    func flush() {
      if !quoteLines.isEmpty {
        segments.append(.quote(lines: quoteLines))
        quoteLines = []
      }
      if !bullets.isEmpty {
        segments.append(.bullet(items: bullets))
        bullets = []
      }
      if !numbers.isEmpty {
        segments.append(.numbered(items: numbers))
        numbers = []
      }
      if !paragraphLines.isEmpty {
        segments.append(.paragraph(lines: paragraphLines))
        paragraphLines = []
      }
    }

    let lines = text.components(separatedBy: "\n")
    var index = 0
    while index < lines.count {
      let raw = lines[index]
      let trimmed = raw.trimmingCharacters(in: .whitespaces)

      // 표: 헤더행 + 구분행(`|---|---|`)이 오면 본문 행까지 묶는다
      if trimmed.hasPrefix("|"), index + 1 < lines.count,
         isDelimiter(lines[index + 1].trimmingCharacters(in: .whitespaces)) {
        flush()
        let header = splitRow(trimmed)
        var rows: [[String]] = []
        index += 2
        while index < lines.count {
          let row = lines[index].trimmingCharacters(in: .whitespaces)
          guard row.hasPrefix("|") else { break }
          rows.append(splitRow(row))
          index += 1
        }
        segments.append(.table(header: header, rows: rows))
        continue
      }

      // 펜스 코드
      if trimmed.hasPrefix("```") {
        if inFence {
          segments.append(.code(language: fenceLanguage, lines: fenceLines))
          fenceLines = []
          inFence = false
        } else {
          flush()
          fenceLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
          inFence = true
        }
        index += 1
        continue
      }
      if inFence {
        fenceLines.append(raw)
        index += 1
        continue
      }

      // 구분선
      if isRule(trimmed) {
        flush()
        segments.append(.rule)
        index += 1
        continue
      }

      // 인용
      if trimmed.hasPrefix(">") {
        if !bullets.isEmpty || !numbers.isEmpty || !paragraphLines.isEmpty { flush() }
        quoteLines.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
        index += 1
        continue
      }

      // 목록 (불릿 · 번호) — 종류가 바뀌면 목록을 끊는다
      if let item = listItem(raw) {
        if !quoteLines.isEmpty || !paragraphLines.isEmpty { flush() }
        if item.ordered {
          if !bullets.isEmpty { flush() }
          numbers.append(item.value)
        } else {
          if !numbers.isEmpty { flush() }
          bullets.append(item.value)
        }
        index += 1
        continue
      }

      // 제목 (`#`~`######` 뒤에 공백)
      let level = headingLevel(trimmed)
      if level > 0 {
        flush()
        segments.append(.heading(level: level,
                                 text: String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)))
        index += 1
        continue
      }

      if trimmed.isEmpty {
        flush()
        segments.append(.blank)
        index += 1
        continue
      }

      if !quoteLines.isEmpty { flush() }
      paragraphLines.append(raw)
      index += 1
    }
    if inFence {
      // 닫히지 않은 펜스는 코드로 간주
      segments.append(.code(language: fenceLanguage, lines: fenceLines))
    }
    flush()
    return segments
  }

  // MARK: - 행 판별 (내부)

  /// `|---|---|` 구분행
  static func isDelimiter(_ line: String) -> Bool {
    let cells = line.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
      .filter { !$0.isEmpty }
    guard !cells.isEmpty else { return false }
    return cells.allSatisfy { cell in cell.allSatisfy { $0 == "-" || $0 == ":" } }
  }

  /// `| a | b |` → ["a", "b"]
  static func splitRow(_ line: String) -> [String] {
    var body = line
    if body.hasPrefix("|") { body.removeFirst() }
    if body.hasSuffix("|") { body.removeLast() }
    return body.split(separator: "|", omittingEmptySubsequences: false)
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  /// `---` · `***` · `___` (공백 허용, 3자 이상)
  static func isRule(_ line: String) -> Bool {
    let compact = line.filter { !$0.isWhitespace }
    guard compact.count >= 3 else { return false }
    return compact.allSatisfy { $0 == "-" }
      || compact.allSatisfy { $0 == "*" }
      || compact.allSatisfy { $0 == "_" }
  }

  /// 목록 항목 — 들여쓰기 2칸 = 1단계(최대 3단계)
  static func listItem(_ raw: String) -> (ordered: Bool, value: MarkdownItem)? {
    let indent = raw.prefix { $0 == " " || $0 == "\t" }.count
    let depth = min(3, indent / 2)
    let trimmed = raw.trimmingCharacters(in: .whitespaces)

    for marker in ["- ", "* ", "• ", "· "] where trimmed.hasPrefix(marker) {
      var text = String(trimmed.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
      // 체크박스: `[ ]` · `[x]` · `[X]` — 뒤에 공백이 오거나 그것만 있는 경우
      var task: Bool?
      for (box, checked) in [("[ ]", false), ("[x]", true), ("[X]", true)] where text.hasPrefix(box) {
        let rest = text.dropFirst(box.count)
        guard rest.isEmpty || rest.first?.isWhitespace == true else { continue }
        task = checked
        text = String(rest).trimmingCharacters(in: .whitespaces)
        break
      }
      guard !text.isEmpty else { return nil }
      return (false, MarkdownItem(text: text, depth: depth, task: task))
    }

    // 1. / 1) / 1: — 숫자는 3자리까지(날짜 "2026. 10."을 목록으로 오인하지 않게)
    var digits = ""
    var rest = Substring(trimmed)
    while let c = rest.first, c.isNumber, digits.count < 4 {
      digits.append(c)
      rest = rest.dropFirst()
    }
    guard digits.count <= 3, !digits.isEmpty, let sep = rest.first,
          sep == "." || sep == ")" || sep == ":" else { return nil }
    let after = rest.dropFirst()
    guard after.first == " " else { return nil }
    let text = String(after).trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return nil }
    return (true, MarkdownItem(text: text, depth: depth))
  }

  static func headingLevel(_ line: String) -> Int {
    guard line.hasPrefix("#") else { return 0 }
    var level = 0
    for c in line {
      guard c == "#" else { break }
      level += 1
    }
    guard level >= 1, level <= 6 else { return 0 }
    let rest = line.dropFirst(level)
    guard rest.first?.isWhitespace == true else { return 0 }
    return level
  }
}

/// 인라인 서식 토큰 — `**굵게**` · `*기울임*` · `` `코드` `` · `[라벨](주소)`.
/// 닫히지 않거나 비어 있는 마커는 그대로 둔다(원문 보존).
public enum MarkdownInline: Equatable {
  case plain(String)
  case bold(String)
  case italic(String)
  case code(String)
  case link(label: String, url: String)

  public static func tokenize(_ raw: String) -> [MarkdownInline] {
    guard !raw.isEmpty else { return [] }
    var tokens: [MarkdownInline] = []
    var plain = ""
    var index = raw.startIndex

    func flush() {
      if !plain.isEmpty {
        tokens.append(.plain(plain))
        plain = ""
      }
    }

    while index < raw.endIndex {
      let char = raw[index]
      let next = raw.index(after: index)

      // [[번호]](주소) — 웹 검색 인용. 화면에는 `[1]`로 보이고 링크로 동작한다.
      if char == "[", next < raw.endIndex, raw[next] == "[" {
        let innerStart = raw.index(after: next)
        if let close = raw[innerStart...].range(of: "]]") {
          let after = close.upperBound
          if after < raw.endIndex, raw[after] == "(",
             let end = raw[raw.index(after: after)...].firstIndex(of: ")") {
            let label = String(raw[innerStart..<close.lowerBound])
            let url = String(raw[raw.index(after: after)..<end]).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, !url.isEmpty {
              flush()
              tokens.append(.link(label: "[\(label)]", url: url))
              index = raw.index(after: end)
              continue
            }
          }
        }
      }

      // [라벨](주소)
      if char == "[" {
        if let close = raw[next...].firstIndex(of: "]") {
          let after = raw.index(after: close)
          if after < raw.endIndex, raw[after] == "(",
             let end = raw[raw.index(after: after)...].firstIndex(of: ")") {
            let label = String(raw[next..<close])
            let url = String(raw[raw.index(after: after)..<end]).trimmingCharacters(in: .whitespaces)
            if !label.isEmpty, !url.isEmpty {
              flush()
              tokens.append(.link(label: label, url: url))
              index = raw.index(after: end)
              continue
            }
          }
        }
      }

      // `` `코드` ``
      if char == "`", next < raw.endIndex, let close = raw[next...].firstIndex(of: "`") {
        let code = String(raw[next..<close])
        if !code.isEmpty {
          flush()
          tokens.append(.code(code))
          index = raw.index(after: close)
          continue
        }
      }

      if char == "*" {
        // **굵게** 먼저, 다음 ** 가 없으면 리터럴
        if next < raw.endIndex, raw[next] == "*" {
          let from = raw.index(index, offsetBy: 2, limitedBy: raw.endIndex) ?? raw.endIndex
          if from < raw.endIndex, let range = raw[from...].range(of: "**"),
             !raw[from..<range.lowerBound].isEmpty {
            flush()
            tokens.append(.bold(String(raw[from..<range.lowerBound])))
            index = range.upperBound
            continue
          }
          plain += "**"
          index = from
          continue
        }
        // *기울임*
        if next < raw.endIndex, let close = raw[next...].firstIndex(of: "*") {
          let text = String(raw[next..<close])
          if !text.isEmpty {
            flush()
            tokens.append(.italic(text))
            index = raw.index(after: close)
            continue
          }
        }
      }
      plain.append(char)
      index = next
    }
    flush()
    return tokens
  }
}

/// 음성 낭독용 평문 — 마크다운 기호를 걷어낸다(읽어주기가 `**`·``` 를 소리 내지 않게).
public enum MarkdownPlain {
  public static func text(_ markdown: String) -> String {
    var out: [String] = []
    for segment in MarkdownSegment.parse(markdown) {
      switch segment {
      case .heading(_, let text):
        out.append(inline(text))
      case .quote(let lines):
        out.append(inline(lines.joined(separator: " ")))
      case .bullet(let items), .numbered(let items):
        out.append(contentsOf: items.map { inline($0.text) })
      case .code(_, let lines):
        out.append(lines.joined(separator: "\n"))
      case .table(let header, let rows):
        out.append(header.map(inline).joined(separator: ", "))
        for row in rows { out.append(row.map(inline).joined(separator: ", ")) }
      case .paragraph(let lines):
        out.append(inline(lines.joined(separator: " ")))
      case .rule, .blank:
        continue
      }
    }
    return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// 인라인 기호만 제거(링크는 라벨만 읽는다)
  public static func inline(_ raw: String) -> String {
    MarkdownInline.tokenize(raw).map { token in
      switch token {
      case .plain(let s), .bold(let s), .italic(let s), .code(let s):
        return s
      case .link(let label, _):
        return label
      }
    }.joined()
  }
}

/// 웹 검색 답변의 `[n]` 인용을 출처 URL 링크로 바꾼다.
///
/// 원문은 그대로 두고 **표시용 문자열만** 만든다. 코드 블록 안의 `[n]`은 건드리지 않는다.
/// 결과는 `[[n]](url)` 형태이며 `MarkdownInline`이 `[n]` 라벨의 링크로 읽는다.
public enum CitationLinks {
  private static let pattern = try! NSRegularExpression(pattern: "\\[([0-9]{1,2})\\](?!\\()")

  public static func link(_ text: String, urls: [String]) -> String {
    guard !text.isEmpty, !urls.isEmpty else { return text }
    var out: [String] = []
    var inFence = false
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let raw = String(line)
      if raw.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        inFence.toggle()
        out.append(raw)
        continue
      }
      out.append(inFence ? raw : linkLine(raw, urls: urls))
    }
    return out.joined(separator: "\n")
  }

  private static func linkLine(_ line: String, urls: [String]) -> String {
    guard !line.isEmpty else { return line }
    let ns = line as NSString
    let matches = pattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
    guard !matches.isEmpty else { return line }
    let codeRanges = inlineCodeRanges(ns)
    var result = line
    for match in matches.reversed() {
      guard match.numberOfRanges == 2 else { continue }
      let numberRange = match.range(at: 1)
      guard let n = Int(ns.substring(with: numberRange)), n >= 1, n <= urls.count else { continue }
      // 이미 링크로 감싼 `[[1]](...)`를 다시 감싸지 않는다.
      let start = match.range.location
      let end = match.range.location + match.range.length
      if start > 0, ns.character(at: start - 1) == 91 { continue } // '['
      if end < ns.length, ns.character(at: end) == 93 { continue } // ']'
      if codeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) { continue }
      let url = escape(urls[n - 1])
      guard let range = Range(match.range, in: result) else { continue }
      result.replaceSubrange(range, with: "[[\(n)]](\(url))")
    }
    return result
  }

  /// 한 줄 안의 `` `코드` `` 구간 — 인용 치환에서 제외한다.
  private static func inlineCodeRanges(_ ns: NSString) -> [NSRange] {
    var ranges: [NSRange] = []
    var i = 0
    while i < ns.length {
      guard ns.character(at: i) == 96 else { i += 1; continue }
      var j = i + 1
      while j < ns.length, ns.character(at: j) != 96 { j += 1 }
      guard j < ns.length else { break }
      ranges.append(NSRange(location: i, length: j - i + 1))
      i = j + 1
    }
    return ranges
  }

  private static func escape(_ url: String) -> String {
    url.replacingOccurrences(of: "(", with: "%28")
       .replacingOccurrences(of: ")", with: "%29")
       .replacingOccurrences(of: " ", with: "%20")
  }
}
