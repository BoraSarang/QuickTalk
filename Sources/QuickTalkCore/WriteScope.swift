import Foundation

// [FEATURE] 쓰기 경로 스코프 — 승인 범위 계산 (PLAN_v0.18 v0.19)
//
// v0.18은 쓰기가 필요할 때마다 **명령 한 건** 단위로 물었다.
// v0.19는 **경로(폴더) 단위**로 묻는다 — "이 폴더는 이번 대화 동안 허용"을 고르면
// 같은 폴더 안의 다음 쓰기는 다시 묻지 않는다. 승인은 **폴더 밖으로 새지 않는다**.
//
// 여기서는 순수 계산만 한다(파일 시스템을 바꾸지 않는다) — 테스트 대상.

public enum WriteScope {
  /// 경로 정규화 — `~` 확장 · `..` 정리 · 후행 슬래시 제거.
  ///
  /// 심볼릭 링크는 **해석하지 않는다** — 스코프와 대상 경로를 같은 규칙으로 만들어
  /// 서로 일치시키는 것이 목적이다(`SandboxRunner` 가 실행 직전에 realpath 로 바꾼다).
  public static func normalize(_ path: String) -> String {
    var p = path.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !p.isEmpty else { return p }
    if p == "~" { p = NSHomeDirectory() }
    else if p.hasPrefix("~/") { p = NSHomeDirectory() + String(p.dropFirst()) }
    p = (p as NSString).standardizingPath
    while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
    return p
  }

  /// `path` 가 `scope` 안에 있는가(같은 경로 포함).
  public static func contains(_ path: String, in scope: String) -> Bool {
    let p = normalize(path), s = normalize(scope)
    guard !p.isEmpty, !s.isEmpty else { return false }
    if p == s { return true }
    let prefix = s.hasSuffix("/") ? s : s + "/"
    return p.hasPrefix(prefix)
  }

  /// 승인된 스코프 중 하나에 속하는가.
  public static func isApproved(_ path: String, scopes: [String]) -> Bool {
    scopes.contains { contains(path, in: $0) }
  }

  /// 시스템 전역 경로(하위 포함) — 백업·휴지통 대상에서 뺀다.
  ///
  /// `RiskClassifier.isSystemScopePath` 는 **정확히 그 루트**만 본다(`/Users` 자체는 막고
  /// 그 아래 홈 폴더는 허용). 여기서는 하위까지 막아야 하는 진짜 시스템 영역만 따로 본다.
  public static func isSystemPath(_ path: String) -> Bool {
    let p = normalize(path)
    if RiskClassifier.isSystemScopePath(p) { return true }
    let roots = ["/System", "/usr", "/bin", "/sbin", "/etc", "/private/etc", "/Library", "/dev"]
    return roots.contains { p == $0 || p.hasPrefix($0 + "/") }
  }

  /// 승인 범위 계산 — 파일이면 **상위 폴더**(새로 만들어야 할 수 있다), 폴더면 그 폴더.
  public static func scope(for path: String) -> String {
    let p = normalize(path)
    guard !p.isEmpty else { return p }
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: p, isDirectory: &isDir), isDir.boolValue {
      return p
    }
    let parent = (p as NSString).deletingLastPathComponent
    return parent.isEmpty || parent == "/" ? p : normalize(parent)
  }

  /// 명령에서 **경로 후보**를 뽑는다 — 되돌리기(백업) 대상.
  ///
  /// 완벽한 셸 파서가 아니다. 백업은 "놓치면 되돌릴 수 없음"이므로
  /// 경로처럼 보이는 단어를 **넉넉히** 잡는다(과하게 잡아도 안전한 쪽).
  public static func candidatePaths(in command: String,
                                    cwd: String = NSHomeDirectory()) -> [String] {
    var out: [String] = []
    for raw in shellWords(command) {
      var t = raw
      if t.isEmpty || t == ">" || t == ">>" || t == "<" { continue }
      if t.hasPrefix("--") { continue }
      if t.hasPrefix("-") { continue }
      if t.contains("://") { continue }          // URL 은 경로가 아니다
      if t.contains("*") || t.contains("?") { continue }  // 글롭은 실행 시점에 펼쳐진다
      let looksPath = t.hasPrefix("/") || t.hasPrefix("~") || t.hasPrefix("./")
        || t.hasPrefix("../") || t.contains("/")
      guard looksPath else { continue }
      if t.hasPrefix("~") { t = NSHomeDirectory() + String(t.dropFirst()) }
      else if !t.hasPrefix("/") { t = (cwd as NSString).appendingPathComponent(t) }
      let p = normalize(t)
      guard !p.isEmpty, p != NSHomeDirectory() else { continue }
      guard !isSystemPath(p) else { continue }
      if !out.contains(p) { out.append(p) }
    }
    return out
  }

  /// 셸 단어 분리 — 따옴표 안의 공백은 나누지 않고, 따옴표는 벗긴다.
  static func shellWords(_ command: String) -> [String] {
    var words: [String] = []
    var current = ""
    var quote: Character?
    var started = false
    for ch in command {
      if let q = quote {
        if ch == q { quote = nil } else { current.append(ch) }
        continue
      }
      if ch == "\"" || ch == "'" {
        quote = ch
        started = true
        continue
      }
      if ch == " " || ch == "\t" || ch == "\n" || ch == ";" {
        if started || !current.isEmpty {
          words.append(current); current = ""; started = false
        }
        continue
      }
      current.append(ch)
      started = true
    }
    if started || !current.isEmpty { words.append(current) }
    return words
  }
}
