import Foundation

/// 비서별 리포트 저장 폴더 — 경로 해석을 **한 곳에서** 정한다.
///
/// 규칙
/// - 비서가 폴더를 직접 지정 → **그대로** 쓴다(사용자 의도 존중).
/// - 지정하지 않음 → `설정의 기본 폴더/<비서 폴더명>`.
/// - 비서 없음 → 설정의 기본 폴더 루트(기존 동작).
///
/// 기존 루트 파일은 **자동으로 옮기지 않는다**(파괴적 변경 금지). 새 파일부터 하위 폴더로 간다.
public enum PersonaReports {
  /// 폴더명 글자 수 상한 — Finder에서 읽기 좋은 길이.
  public static let folderNameLimit = 24

  /// 비서 이름을 폴더명으로 정리한다.
  ///
  /// - `/`·`:`·`\`·개행은 경로 구분자·Finder 예약 문자라 제거한다.
  /// - 앞뒤 공백·점을 지우고, 연속 공백은 하나로 접는다.
  /// - 비면 `persona-<ID 앞 4자>`.
  /// - 이름이 겹치면 **모든 충돌 항목**에 `-<ID 앞 4자>`를 붙여 순서와 무관하게 안정적이다.
  public static func folderName(for persona: Persona, all: [Persona]) -> String {
    let base = sanitize(persona.normalized().name)
    let idPrefix = idSuffix(persona)
    guard !base.isEmpty else { return "persona-\(idPrefix)" }

    let sameBase = all.filter { sanitize($0.normalized().name) == base }
    if sameBase.count > 1 { return "\(base)-\(idPrefix)" }
    return base
  }

  /// 최종 저장 경로(절대 경로, `~` 확장 완료).
  public static func folder(settings: QuickTalkSettings, persona: Persona?) -> String {
    folder(settings: settings, persona: persona, all: settings.personas)
  }

  public static func folder(settings: QuickTalkSettings, persona: Persona?,
                            all: [Persona]) -> String {
    guard let persona = persona?.normalized() else { return settings.reportFolderPath }
    if let explicit = persona.reportFolder, !explicit.isEmpty {
      return (explicit as NSString).expandingTildeInPath
    }
    let root = settings.reportFolderPath
    let name = folderName(for: persona, all: all.isEmpty ? [persona] : all)
    return (root as NSString).appendingPathComponent(name)
  }

  /// 폴더를 실제로 만든다 — 저장·전송 시점에 앱이 직접 만든다(에이전트 승인 불필요).
  @discardableResult
  public static func ensureFolder(settings: QuickTalkSettings,
                                  persona: Persona?) -> URL? {
    let path = folder(settings: settings, persona: persona)
    let url = URL(fileURLWithPath: path, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return url
    } catch {
      NSLog("[WARN] E-MAC-REPORT-0001 작업 폴더 생성 실패: %@",
            String(describing: error))
      return nil
    }
  }

  /// 같은 폴더를 **명시적으로** 고른 다른 비서들 — 설정 화면 경고용.
  /// 자동 폴더는 이름 충돌 시 접미사가 붙으므로 여기서 세지 않는다.
  public static func sharedExplicitPeers(persona: Persona, all: [Persona]) -> [Persona] {
    guard let explicit = persona.normalized().reportFolder, !explicit.isEmpty else { return [] }
    let path = (explicit as NSString).expandingTildeInPath
    return all.filter {
      $0.id != persona.id
        && ($0.normalized().reportFolder.map { ($0 as NSString).expandingTildeInPath } == path)
    }
  }

  // MARK: - 이름 정리

  static func sanitize(_ raw: String) -> String {
    let mapped = raw.map { ch -> Character in
      if ch == "/" || ch == ":" || ch == "\\" || ch.isNewline || ch == "\t" { return " " }
      return ch
    }
    let collapsed = String(mapped)
      .components(separatedBy: .whitespaces)
      .filter { !$0.isEmpty }
      .joined(separator: " ")
      .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
    return String(collapsed.prefix(folderNameLimit))
  }

  private static func idSuffix(_ persona: Persona) -> String {
    String(persona.id.uuidString.replacingOccurrences(of: "-", with: "").prefix(4)).uppercased()
  }
}
