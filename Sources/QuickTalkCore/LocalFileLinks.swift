import Foundation

// [FEATURE] 답변에 나온 로컬 파일·폴더를 클릭 가능한 링크로 (2026-11-08)
//
// 사용자 지적: 리포트 파일을 "이름만" 나열하면 파인더를 직접 열어 찾아야 한다.
// 답변 원문은 그대로 두고 **표시용 문자열에만** `[표시](file:///절대경로)` 링크를 끼워 넣는다.
//
// 규칙
//   · 존재하는 경로만 링크한다(없는 파일명을 링크로 만들면 눌렀을 때 실패한다).
//   · 코드 펜스(```) 안은 건드리지 않는다 — 셸 명령·코드가 링크로 바뀌면 복사·실행이 깨진다.
//   · 이미 있는 마크다운 링크·굵게 표시(`**`)·URL 은 건드리지 않는다.
//   · 파일명만 나열된 경우, 같은 답변에서 먼저 언급된 **폴더 경로**를 기준으로 찾는다.
public enum LocalFileLinks {
  /// 링크로 만들 파일 확장자 — 흔한 문서·이미지·코드·압축 파일만.
  /// (`.com`·`.net` 같은 도메인 조각을 파일명으로 오인하지 않게 허용 목록으로 둔다)
  public static let fileExtensions: Set<String> = [
    "md", "markdown", "txt", "log", "json", "jsonl", "yaml", "yml", "toml", "ini", "conf",
    "csv", "tsv", "sql", "sqlite", "db",
    "pdf", "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg", "bmp",
    "mp3", "m4a", "wav", "aiff", "mp4", "mov", "mkv", "avi",
    "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar",
    "swift", "py", "js", "ts", "tsx", "jsx", "sh", "zsh", "bash", "fish",
    "rb", "go", "rs", "java", "kt", "kts", "c", "h", "cc", "cpp", "hpp", "m", "mm",
    "html", "htm", "css", "scss", "xml", "plist", "entitlements", "pbxproj",
    "doc", "docx", "xls", "xlsx", "ppt", "pptx", "pages", "numbers", "key", "epub",
    "command", "tool", "terminal", "scpt", "applescript",
    "pkg", "dmg", "iso",
  ]

  /// 절대 경로(`/…` · `~/…`) — 공백·따옴표·괄호 밖까지.
  private static let absolutePattern = try! NSRegularExpression(
    pattern: #"(?:~|/)[^\s"'`<>|]*"#)
  /// 확장자가 있는 파일명 — 경로 구분자·굵게/링크 기호에 붙어 있으면 제외.
  private static let barePattern = try! NSRegularExpression(
    pattern: #"(?<![\w./\-*\[\]])([A-Za-z0-9_\-가-힣][A-Za-z0-9_.\-가-힣]{0,120}\.[A-Za-z0-9]{1,10})(?![\w*\[\]])"#)
  /// 이미 링크로 감싼 구간 — 다시 감싸지 않는다.
  private static let markdownLinkPattern = try! NSRegularExpression(
    pattern: #"\[[^\]\n]*\]\([^)\n]*\)"#)
  /// 굵게·기울임 구간 — 안쪽에 링크 문법을 넣으면 토크나이저가 글자 그대로 보여 준다.
  private static let emphasisPattern = try! NSRegularExpression(
    pattern: #"\*\*[^*\n]+\*\*|\*[^*\n]+\*"#)

  // MARK: - 공개 API

  /// 답변 텍스트에 존재하는 파일·폴더 링크를 삽입한 **표시용** 문자열을 돌려준다.
  /// - Parameters:
  ///   - text: 원문(마크다운). 코드 펜스는 그대로 둔다.
  ///   - extraDirectories: 파일명만 나열됐을 때 찾아볼 추가 폴더(예: 리포트 폴더).
  public static func link(_ text: String,
                          extraDirectories: [String] = [],
                          fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                          isDirectory: (String) -> Bool = {
                            var d: ObjCBool = false
                            return FileManager.default.fileExists(atPath: $0, isDirectory: &d)
                              && d.boolValue
                          }) -> String {
    guard text.contains(".") || text.contains("/") || text.contains("~") else { return text }
    let directories = directories(in: text, extraDirectories: extraDirectories,
                                  fileExists: fileExists, isDirectory: isDirectory)
    guard !directories.isEmpty || text.contains("~") || text.contains("/") else { return text }

    var result: [String] = []
    var inFence = false
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") {
        inFence.toggle()
        result.append(line)
        continue
      }
      guard !inFence else {
        result.append(line)
        continue
      }
      result.append(linkLine(line, directories: directories,
                             fileExists: fileExists, isDirectory: isDirectory))
    }
    return result.joined(separator: "\n")
  }

  /// 텍스트에서 **존재하는** 폴더 후보를 모은다(언급 순서 유지·중복 제거).
  /// 절대 파일 경로가 나오면 그 부모 폴더도 후보에 넣는다.
  public static func directories(in text: String,
                                 extraDirectories: [String] = [],
                                 fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
                                 isDirectory: (String) -> Bool = {
                                   var d: ObjCBool = false
                                   return FileManager.default.fileExists(atPath: $0, isDirectory: &d)
                                     && d.boolValue
                                 }) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    func add(_ path: String) {
      let normalized = normalize(path)
      guard !normalized.isEmpty, seen.insert(normalized).inserted else { return }
      out.append(normalized)
    }
    for raw in extraDirectories { add(resolve(raw)) }

    var inFence = false
    for line in text.components(separatedBy: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("```") { inFence.toggle(); continue }
      guard !inFence else { continue }
      let ns = line as NSString
      let matches = absolutePattern.matches(in: line, range: NSRange(location: 0, length: ns.length))
      for match in matches {
        let path = trimTrailing(ns.substring(with: match.range))
        guard !path.isEmpty else { continue }
        let resolved = resolve(path)
        if isDirectory(resolved) {
          add(resolved)
        } else if fileExists(resolved) {
          add((resolved as NSString).deletingLastPathComponent)
        } else if looksLikeDirectory(path) {
          // 아직 만들어지지 않은 폴더라도 후보로 둔다 — 파일명 후보를 찾을 때만 쓰인다.
          add(resolved)
        }
      }
    }
    return out
  }

  /// 경로 또는 파일명을 후보 폴더 기준으로 실제 URL 로 해석한다(없으면 nil).
  /// 인라인 코드(`` `…` ``) 안의 경로를 클릭 가능하게 만들 때 쓴다.
  public static func url(for reference: String,
                         directories: [String],
                         fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> URL? {
    var trimmed = trimTrailing(reference.trimmingCharacters(in: .whitespacesAndNewlines))
    guard !trimmed.isEmpty else { return nil }
    if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
      var resolved = resolve(trimmed)
      if !fileExists(resolved), trimmed.hasSuffix(".") {
        trimmed.removeLast()
        resolved = resolve(trimmed)
      }
      return fileExists(resolved) ? URL(fileURLWithPath: resolved) : nil
    }
    guard looksLikeFileName(trimmed) else { return nil }
    for directory in directories {
      let candidate = (directory as NSString).appendingPathComponent(trimmed)
      if fileExists(candidate) { return URL(fileURLWithPath: candidate) }
    }
    return nil
  }

  // MARK: - 줄 처리

  private static func linkLine(_ line: String,
                               directories: [String],
                               fileExists: (String) -> Bool,
                               isDirectory: (String) -> Bool) -> String {
    guard !line.isEmpty else { return line }
    let ns = line as NSString
    let linkRanges = markdownLinkPattern
      .matches(in: line, range: NSRange(location: 0, length: ns.length))
      .map(\.range)
    // 인라인 코드(`` `…` ``) 안은 건드리지 않는다 — 경로는 렌더 단계에서 모노 글꼴 그대로 링크로 만든다.
    let codeRanges = inlineCodeRanges(ns)
    let emphasisRanges = emphasisPattern
      .matches(in: line, range: NSRange(location: 0, length: ns.length))
      .map(\.range)
    let protectedRanges = linkRanges + codeRanges + emphasisRanges
    var replacements: [(NSRange, String)] = []

    // 1) 절대 경로 — 존재하면 링크(폴더 포함).
    for match in absolutePattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
      guard !intersects(match.range, protectedRanges) else { continue }
      // URL(`https://…` · `file://…`)의 일부를 경로로 오인하지 않는다.
      let start = match.range.location
      if start > 0 {
        let prev = ns.character(at: start - 1)
        if prev == 47 { continue }                       // '/'
        if prev == 58, start >= 2 {                      // ':' — 스킴(`https:`)
          let scheme = ns.character(at: start - 2)
          if (scheme >= 65 && scheme <= 90) || (scheme >= 97 && scheme <= 122) { continue }
        }
      }
      var path = trimTrailing(ns.substring(with: match.range))
      guard !path.isEmpty, isLinkableLabel(path) else { continue }
      // 문장 끝 마침표(`…/report.md.`) — 점을 뗀 경로가 실제로 있으면 그쪽을 쓴다.
      if !fileExists(resolve(path)), path.hasSuffix(".") {
        let dropped = String(path.dropLast())
        if fileExists(resolve(dropped)) { path = dropped }
      }
      let resolved = resolve(path)
      guard fileExists(resolved) else { continue }
      let range = NSRange(location: match.range.location, length: (path as NSString).length)
      let anchor = NSRange(location: range.location, length: range.length)
      if let existing = replacements.first(where: { NSIntersectionRange($0.0, anchor).length > 0 }) {
        // 긴 경로가 이미 잡았으면 짧은 중복은 버린다.
        if existing.0.length >= anchor.length { continue }
        replacements.removeAll { $0.0 == existing.0 }
      }
      _ = isDirectory
      replacements.append((anchor, markdownLink(label: path, url: URL(fileURLWithPath: resolved))))
    }

    // 2) 파일명만 나열된 경우 — 같은 답변에서 언급된 폴더 기준.
    guard !directories.isEmpty else { return apply(replacements, to: line) }
    for match in barePattern.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
      guard !intersects(match.range, protectedRanges) else { continue }
      guard !intersects(match.range, replacements.map(\.0)) else { continue }
      let name = ns.substring(with: match.range(at: 1))
      guard looksLikeFileName(name), isLinkableLabel(name) else { continue }
      guard let url = url(for: name, directories: directories, fileExists: fileExists) else { continue }
      replacements.append((match.range(at: 1), markdownLink(label: name, url: url)))
    }

    return apply(replacements, to: line)
  }

  private static func apply(_ replacements: [(NSRange, String)], to line: String) -> String {
    guard !replacements.isEmpty else { return line }
    var out = line
    for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
      guard let r = Range(range, in: out) else { continue }
      out.replaceSubrange(r, with: replacement)
    }
    return out
  }

  // MARK: - 판별

  private static func looksLikeFileName(_ name: String) -> Bool {
    let ext = (name as NSString).pathExtension.lowercased()
    guard !ext.isEmpty, fileExtensions.contains(ext) else { return false }
    // "e.g." · "U.S." 같은 문장 조각 제외 — 확장자 앞에 최소 한 글자.
    let stem = (name as NSString).deletingPathExtension
    return !stem.isEmpty
  }

  private static func looksLikeDirectory(_ path: String) -> Bool {
    let ext = (path as NSString).pathExtension.lowercased()
    return ext.isEmpty || ext == "app"
  }

  /// 마크다운 라벨에 그대로 넣을 수 있는가 — `[`·`]` 가 있으면 링크 문법이 깨진다.
  private static func isLinkableLabel(_ text: String) -> Bool {
    !text.contains("[") && !text.contains("]") && !text.contains("\n")
  }

  private static func intersects(_ range: NSRange, _ others: [NSRange]) -> Bool {
    others.contains { NSIntersectionRange(range, $0).length > 0 }
  }

  private static func markdownLink(label: String, url: URL) -> String {
    // 마크다운 링크 주소는 첫 `)` 에서 끝난다 — 괄호·공백을 퍼센트 인코딩한다.
    let escaped = url.absoluteString
      .replacingOccurrences(of: "(", with: "%28")
      .replacingOccurrences(of: ")", with: "%29")
      .replacingOccurrences(of: " ", with: "%20")
    return "[\(label)](\(escaped))"
  }

  /// 한 줄 안의 `` `코드` `` 구간 — 링크 삽입에서 제외한다.
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

  // MARK: - 경로

  private static func resolve(_ path: String) -> String {
    (path as NSString).expandingTildeInPath
  }

  private static func normalize(_ path: String) -> String {
    var p = resolve(path)
    while p.count > 1, p.hasSuffix("/") { p.removeLast() }
    return p
  }

  /// 문장부호·괄호가 경로 끝에 붙어 있으면 떼어 낸다(`…/report/.` → `…/report/`).
  private static func trimTrailing(_ raw: String) -> String {
    var text = raw
    let trailing: Set<Character> = [".", ",", ";", ":", "!", "?", ")", "]", "}", "»", "\"", "'", "”", "’"]
    while let last = text.last, trailing.contains(last) {
      // 확장자 점(`.md`)은 남긴다 — 앞 글자가 영숫자/한글이면 점 제거 금지.
      if last == "." {
        let before = text.dropLast().last
        if let before, before.isLetter || before.isNumber { break }
      }
      text.removeLast()
    }
    if let cut = text.firstIndex(where: { $0 == "—" || $0 == "–" || $0 == "\t" }) {
      text = String(text[..<cut])
    }
    return text.trimmingCharacters(in: .whitespaces)
  }
}
