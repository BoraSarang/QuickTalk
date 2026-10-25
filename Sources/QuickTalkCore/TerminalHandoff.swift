import Foundation

// [FEATURE] 터미널 인계 — 앱이 **실행하지 않고** 사용자가 직접 실행하도록 넘긴다 (v0.20)
//
// 시스템 전역 경로(`/usr`, `/etc`, `/System` …)에 쓰는 명령과 `sudo` 가 필요한 명령은
// 앱이 권한을 열어 실행하지 않는다(2026-10-22 `rm -rf /` 사고 이후의 규칙).
// 그렇다고 "안 됩니다"로 끝내면 사용자는 방법이 없다. 그래서 **실행 가능한 `.command` 파일**을
// 만들어 터미널로 열어 준다. 앱은 그 명령을 실행하지 않는다 — 실행 여부는 사용자가 정한다.
//
// AppleScript(`do script`)를 쓰지 않는 이유: 자동화 권한(TCC)이 필요하고,
// 그 권한은 "앱이 터미널을 조종한다"는 뜻이라 최소 권한 원칙에 어긋난다.
// `.command` 파일은 Finder/터미널이 직접 여는 것이라 추가 권한이 없다.

public enum TerminalHandoff {
  /// 앱이 실행하지 않고 터미널로 넘겨야 하는가.
  ///
  /// 쓰기는 `isSystemWrite` 로 판정한다(파일이면 상위 폴더 기준).
  /// `/opt/homebrew`·`/usr/local/bin` 같은 도구 설치 경로는 사용자가 승인하면 열어 준다 —
  /// 여기서 넓게 잡으면 `brew install` 이 전부 터미널로 밀려나 에이전트가 쓸모없어진다.
  public static func shouldHandoff(capability: AgentCapability) -> Bool {
    switch capability {
    case .elevated:
      return true
    case .write(let path):
      return isSystemWrite(path)
    case .read, .network, .blocked, .unprobed:
      return false
    }
  }

  /// 쓰기 범위가 시스템 영역인가 — 파일이면 상위 폴더로 판정한다.
  ///
  /// `RiskClassifier.isSystemScopePath` 는 **정확히 루트일 때만** 참이라
  /// (`/etc/hosts` → 거짓) 여기서는 "루트 아래"까지 본다.
  /// 예외: 사용자 홈 · 임시 폴더 · 도구 설치 경로(홈브루·`/usr/local`) · 외장 볼륨(`/Volumes`).
  /// 이 예외가 없으면 `brew install` 이나 정상적인 파일 복사까지 터미널로 밀려난다.
  public static func isSystemWrite(_ path: String) -> Bool {
    let scope = WriteScope.scope(for: path)
    let target = WriteScope.normalize(scope.isEmpty ? path : scope)
    guard !target.isEmpty else { return false }
    if target == "/" { return true }
    let home = NSHomeDirectory()
    if target == home || target.hasPrefix(home + "/") { return false }
    if isUnder(target, exceptions) { return false }
    return isUnder(target, guardedRoots)
  }

  /// 앱이 쓰기를 열지 않는 시스템 루트.
  private static let guardedRoots = ["/System", "/usr", "/bin", "/sbin", "/etc", "/var",
                                     "/private", "/Library", "/cores", "/opt", "/home", "/Users"]
  /// 사용자가 직접 쓰는 정상 경로 — 시스템 루트 아래여도 막지 않는다.
  private static let exceptions = ["/opt/homebrew", "/usr/local",
                                   "/private/tmp", "/private/var/tmp", "/private/var/folders",
                                   "/var/tmp", "/var/folders"]

  private static func isUnder(_ path: String, _ roots: [String]) -> Bool {
    roots.contains { path == $0 || path.hasPrefix($0 + "/") }
  }

  /// 넘길 스크립트 본문 — 사용자가 열어 보고 실행할 수 있게 **명령 그대로** 담는다.
  public static func script(command: String, date: Date = Date()) -> String {
    let stamp = stampFormatter.string(from: date)
    return """
    #!/bin/zsh
    # QuickTalk 터미널 인계 — \(stamp)
    # 앱이 실행하지 않았습니다. 내용을 확인한 뒤 직접 실행하세요.
    # 이 파일은 실행 권한이 있습니다(터미널에서 열리면 바로 실행됩니다).
    set +e
    \(command)
    status=$?
    echo ""
    echo "[QuickTalk] 종료 코드: $status"
    # 창을 닫지 않고 결과를 볼 수 있게 잠시 기다린다(엔터를 누르면 닫힘).
    read -r "?계속하려면 Enter를 누르세요…"
    exit $status
    """ + "\n"
  }

  /// 파일 이름 — 명령을 알아볼 수 있게 줄이고, 경로 구분자·제어문자는 지운다.
  public static func fileName(command: String, date: Date = Date()) -> String {
    let stamp = fileStampFormatter.string(from: date)
    let head = command
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let safe = head.unicodeScalars.map { scalar -> Character in
      let c = Character(scalar)
      if c.isLetter || c.isNumber || c == "-" || c == "_" || c == "." { return c }
      return "-"
    }
    let collapsed = String(safe)
      .split(separator: "-", omittingEmptySubsequences: true)
      .joined(separator: "-")
    let short = collapsed.count > 40 ? String(collapsed.prefix(40)) : collapsed
    let name = short.isEmpty ? "command" : short
    return "QuickTalk-\(stamp)-\(name).command"
  }

  /// 사용자에게 보여줄 안내 — 카드 아래 한 줄.
  public static func note(capability: AgentCapability) -> String {
    switch capability {
    case .elevated:
      return L("상승 권한이 필요해 앱이 실행하지 않았습니다. [터미널에서 열기]로 직접 실행할 수 있습니다.")
    case .write(let path) where isSystemWrite(path):
      return L("시스템 전역 경로라 앱이 쓰기를 열지 않았습니다. [터미널에서 열기]로 직접 실행할 수 있습니다.")
    default:
      return L("앱이 실행하지 않았습니다. [터미널에서 열기]로 직접 실행할 수 있습니다.")
    }
  }

  private static var stampFormatter: DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    return f
  }

  private static var fileStampFormatter: DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    return f
  }
}
