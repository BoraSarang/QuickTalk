import Foundation

// [FEATURE] 리포트 파일 쓰기 (v0.26 3단계)
//
// 경로는 **사용자가 만든 제목**에서 나온다. 그래서 여기서 마지막으로 막는다:
//   · 사용자 홈 폴더 밖(예: `/etc`, 다른 볼륨)으로는 쓰지 않는다.
//   · 심볼릭 링크를 따라간 결과가 홈 밖이면 쓰지 않는다(`..` 는 `ReportNaming` 이 이미 제거).
//   · 폴더가 없으면 만들되, 만들 수 없으면 실패로 기록한다(조용히 다른 곳에 쓰지 않는다).
//
// 파일 쓰기는 **앱이** 한다 — 모델이 `shell` 로 쓰는 것이 아니므로 승인 카드가 뜨지 않는다.
// 대신 승인 없이 쓰는 유일한 경로이므로 위 규칙을 코드로 고정한다.

enum ReportWriteError: LocalizedError, Equatable {
  /// 사용자 홈 폴더 밖
  case outsideHome(String)
  /// 심볼릭 링크를 따라가면 홈 밖
  case symlinkEscape(String)
  case createFailed(String)
  case writeFailed(String)

  var errorDescription: String? { message }

  var message: String {
    switch self {
    case .outsideHome(let path):
      return Lf("사용자 홈 폴더 밖에는 저장할 수 없습니다: %@", path)
    case .symlinkEscape(let path):
      return Lf("심볼릭 링크가 홈 폴더 밖을 가리킵니다: %@", path)
    case .createFailed(let path):
      return Lf("리포트 폴더를 만들지 못했습니다: %@", path)
    case .writeFailed(let reason):
      return Lf("리포트 파일을 쓰지 못했습니다: %@", reason)
    }
  }
}

enum ReportWriter {
  /// 사용자 홈 — 이 밖으로는 쓰지 않는다.
  static var home: String { WriteScope.normalize(NSHomeDirectory()) }

  /// 폴더 문자열(`~` 허용)을 검증된 URL로 바꾼다.
  /// 만들지는 않는다 — 검증과 생성 순서를 분리해 테스트한다.
  static func resolveFolder(_ raw: String) throws -> URL {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    let fallback = "~/Documents/Reports"
    let expanded = (trimmed.isEmpty ? fallback : trimmed) as NSString
    let path = WriteScope.normalize(expanded.expandingTildeInPath)

    // ① 표기상 홈 밖이면 즉시 거부(`..` 로 빠져나가는 경우 포함).
    guard WriteScope.contains(path, in: home) else {
      throw ReportWriteError.outsideHome(path)
    }

    // ② 실제로 존재하는 가장 가까운 상위 폴더의 심볼릭 링크를 따라가 본다.
    //    `~/Documents` 가 다른 볼륨을 가리키는 식으로 홈 밖에 쓰이는 것을 막는다.
    let resolvedAncestor = existingAncestor(URL(fileURLWithPath: path))
      .resolvingSymlinksInPath().path
    guard WriteScope.contains(WriteScope.normalize(resolvedAncestor), in: home) else {
      throw ReportWriteError.symlinkEscape(resolvedAncestor)
    }

    return URL(fileURLWithPath: path, isDirectory: true)
  }

  /// 존재하는 가장 가까운 상위 경로(없으면 `/`).
  private static func existingAncestor(_ url: URL) -> URL {
    var probe = url
    while probe.path != "/" && !FileManager.default.fileExists(atPath: probe.path) {
      probe.deleteLastPathComponent()
    }
    return probe
  }

  /// 리포트를 원자적으로 쓴다. 같은 이름이 있으면 `-2`, `-3` … 을 붙인다.
  /// - Returns: 실제로 쓴 파일 URL
  @discardableResult
  static func write(markdown: String, title: String, date: Date,
                    folder: String, calendar: Calendar = .current) throws -> URL {
    let fm = FileManager.default
    let directory = try resolveFolder(folder)

    do {
      try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
      throw ReportWriteError.createFailed(directory.path)
    }

    // 생성 직후 다시 확인한다(그 사이 링크로 바뀌었을 수 있다).
    let resolved = directory.resolvingSymlinksInPath().path
    guard WriteScope.contains(WriteScope.normalize(resolved), in: home) else {
      throw ReportWriteError.symlinkEscape(resolved)
    }

    let existing = Set((try? fm.contentsOfDirectory(atPath: directory.path)) ?? [])
    let name = ReportNaming.unique(
      ReportNaming.fileName(title: title, date: date, calendar: calendar),
      existing: existing)
    let url = directory.appendingPathComponent(name)

    // 기존 항목이 심볼릭 링크면 따라가지 않는다(링크 대상 덮어쓰기 방지).
    if let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]),
       values.isSymbolicLink == true {
      throw ReportWriteError.symlinkEscape(url.path)
    }

    do {
      try Data(markdown.utf8).write(to: url, options: .atomic)
    } catch {
      throw ReportWriteError.writeFailed(error.localizedDescription)
    }
    NSLog("[QuickTalk] 리포트 저장 — %@", url.lastPathComponent)
    return url
  }

  /// 사용자에게 보여 줄 경로 — 홈은 `~` 로 접는다.
  static func displayPath(_ path: String) -> String {
    let normalized = WriteScope.normalize(path)
    guard normalized.hasPrefix(home) else { return path }
    return "~" + normalized.dropFirst(home.count)
  }
}
