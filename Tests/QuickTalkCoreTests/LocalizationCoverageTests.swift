import XCTest
@testable import QuickTalkCore

/// `L(...)`/`Lf(...)` 에 쓰인 한국어 원문이 **모두** 영어 번역표에 있는지 자동으로 검사한다.
///
/// 배경(2026-10-27): 번역 누락이 74곳 → 12곳을 손으로 보충했지만, 새 화면 문구가
/// `LocalizationTable.swift` 에 들어가지 않아도 **알려 주는 장치가 없었다**(또 94곳 누락).
/// 이제 문구를 `L("...")` 로 감싸고 번역을 넣지 않으면 이 테스트가 실패한다.
///
/// 규칙
/// 1. 소스의 `L("...")`/`Lf("...")` 리터럴은 전부 `L10n.table` 키로 있어야 한다.
/// 2. 보간(`\\(...)`)을 `L`/`Lf` 에 직접 넘기면 안 된다 — 번역표 키가 런타임마다 달라진다.
///    `Lf("%@ 폴더", name)` 처럼 **포맷 문자열**로 쓴다.
final class LocalizationCoverageTests: XCTestCase {
  func testEveryLocalizedLiteralHasEnglishTranslation() throws {
    let files = try SourceScanner.files()
    var missing: [String] = []
    for file in files {
      for hit in file.literals where !hit.interpolated {
        guard L10n.table[hit.key] == nil else { continue }
        missing.append("\(file.path):\(hit.line) — \(hit.key)")
      }
    }
    XCTAssertTrue(missing.isEmpty,
                  "영어 번역이 없는 문구 \(missing.count)건 — Sources/QuickTalkCore/LocalizationTable.swift 에 추가하세요:\n"
                  + missing.joined(separator: "\n"))
  }

  func testNoInterpolatedStringPassedToLocalizer() throws {
    let files = try SourceScanner.files()
    var bad: [String] = []
    for file in files {
      for hit in file.literals where hit.interpolated {
        bad.append("\(file.path):\(hit.line) — \(hit.key)")
      }
    }
    XCTAssertTrue(bad.isEmpty,
                  "`L`/`Lf` 에 문자열 보간을 넘기면 번역표 조회가 실패합니다. 포맷 인자(`Lf(\"%@ …\", 값)`)로 바꾸세요:\n"
                  + bad.joined(separator: "\n"))
  }

  /// 영어 칸에 한국어를 그대로 복사한 경우(번역 누락의 가장 흔한 형태)를 잡는다.
  func testEnglishTableHasNoKoreanText() {
    let offenders = L10n.table
      .filter { _, value in
        value.unicodeScalars.contains { (0xAC00...0xD7A3).contains(Int($0.value)) }
      }
      .keys.sorted()
    XCTAssertTrue(offenders.isEmpty, "영어 번역에 한글이 남아 있습니다: \(offenders)")
  }

  /// 검사 대상이 실제로 잡히는지 — 스캐너가 조용히 0건을 훑고 통과하는 것을 막는다.
  func testScannerFindsLocalizedLiterals() throws {
    let files = try SourceScanner.files()
    let count = files.reduce(0) { $0 + $1.literals.count }
    XCTAssertGreaterThan(count, 500, "스캔된 문구가 너무 적습니다 — 스캐너 경로를 확인하세요(\(files.count)개 파일)")
  }
}

// MARK: - 소스 스캐너

private struct SourceScanner {
  struct Hit {
    let line: Int
    /// 번역표 키(이스케이프 해제 후)
    let key: String
    /// 문자열 보간(`\\(...)`) 포함 여부
    let interpolated: Bool
  }

  struct File {
    let path: String
    let literals: [Hit]
  }

  /// `L(`/`Lf(` 뒤의 문자열 리터럴. 앞이 `.`/영숫자면 다른 심볼(`URL(`, `Tool(` 등)이므로 제외한다.
  private static let callPattern = try! NSRegularExpression(
    pattern: #"(?<![\w.])Lf?\(\s*"((?:[^"\\]|\\.)*)""#)

  static func files() throws -> [File] {
    // Tests/QuickTalkCoreTests/<이 파일> → 저장소 루트
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    let fm = FileManager.default
    var result: [File] = []
    for dir in ["Sources/QuickTalkCore", "QuickTalkApp"] {
      let base = root.appendingPathComponent(dir)
      guard let walker = fm.enumerator(at: base, includingPropertiesForKeys: nil) else { continue }
      for case let url as URL in walker where url.pathExtension == "swift" {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
        let relative = url.path.replacingOccurrences(of: root.path + "/", with: "")
        result.append(File(path: relative, literals: scan(text)))
      }
    }
    guard !result.isEmpty else {
      throw XCTSkip("소스 경로를 찾지 못해 번역 누락을 검사하지 않았습니다: \(root.path)")
    }
    return result.sorted { $0.path < $1.path }
  }

  static func scan(_ text: String) -> [Hit] {
    var hits: [Hit] = []
    for (index, line) in text.components(separatedBy: .newlines).enumerated() {
      // 주석 줄은 건너뛴다(예: `// L("...") 예시`)
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("//") { continue }
      let range = NSRange(line.startIndex..., in: line)
      for match in callPattern.matches(in: line, range: range) {
        guard let raw = Range(match.range(at: 1), in: line).map({ String(line[$0]) }) else { continue }
        hits.append(Hit(line: index + 1,
                        key: unescape(raw),
                        interpolated: raw.contains("\\(")))
      }
    }
    return hits
  }

  /// Swift 문자열 리터럴의 이스케이프를 실제 문자로 되돌린다(번역표 키와 같은 형태로 비교).
  static func unescape(_ raw: String) -> String {
    var out = ""
    var iterator = raw.makeIterator()
    while let ch = iterator.next() {
      guard ch == "\\" else { out.append(ch); continue }
      guard let next = iterator.next() else { out.append(ch); break }
      switch next {
      case "n": out.append("\n")
      case "t": out.append("\t")
      case "r": out.append("\r")
      case "0": out.append("\0")
      case "\"": out.append("\"")
      case "\\": out.append("\\")
      default: out.append("\\"); out.append(next)
      }
    }
    return out
  }
}
