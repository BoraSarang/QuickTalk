import AppKit

// [FEATURE] 답변 속 로컬 파일·폴더 열기 (2026-11-08)
//
// 사용자 지적: 리포트 파일이 이름만 나오면 파인더를 직접 열어 찾아야 한다.
// 답변의 경로를 누르면 **폴더는 파인더**, **파일은 기본 앱**으로 연다.
// 다만 `.app`·스크립트·설치 파일처럼 **누르는 것만으로 코드가 실행되는** 대상은
// 한 번 확인을 받는다(실수 클릭으로 실행되지 않게).
enum LocalFileOpen {
  /// 실행·설치로 이어질 수 있는 확장자 — 열기 전에 확인한다.
  private static let riskyExtensions: Set<String> = [
    "app", "command", "sh", "zsh", "bash", "fish", "tool", "terminal",
    "scpt", "applescript", "workflow", "action", "jar", "pkg", "dmg", "iso",
  ]

  /// 확인 창이 떠 있는 동안 중복 클릭을 막는다.
  private static var isConfirming = false

  /// URL을 연다. 존재하지 않으면 조용히 실패한다(링크는 존재할 때만 만들어지지만,
  /// 답변을 읽는 사이 파일이 지워졌을 수 있다).
  static func open(_ url: URL) {
    guard url.isFileURL else { return }
    let path = url.path
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
      NSSound.beep()
      NSLog("[QuickTalk] 파일 링크 — 경로가 사라졌습니다: %@", path)
      return
    }

    // 폴더는 파인더로 연다 — 단 `.app` 번들은 폴더지만 실행되므로 확인 대상.
    if isDirectory.boolValue {
      if riskyExtensions.contains(url.pathExtension.lowercased()) {
        confirmAndOpen(url)
      } else {
        NSWorkspace.shared.open(url)
      }
      return
    }

    // 스크립트·설치 파일·실행 권한이 붙은 파일은 확인 후 연다.
    if riskyExtensions.contains(url.pathExtension.lowercased())
      || FileManager.default.isExecutableFile(atPath: path) {
      confirmAndOpen(url)
    } else {
      NSWorkspace.shared.open(url)
    }
  }

  private static func confirmAndOpen(_ url: URL) {
    guard !isConfirming else { return }
    isConfirming = true
    defer { isConfirming = false }
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = L("파일 열기 확인")
    alert.informativeText = Lf("이 파일은 앱·스크립트·설치 파일이라 실행될 수 있습니다.\n그래도 열까요?\n\n%@",
                               url.path)
    alert.alertStyle = .warning
    alert.addButton(withTitle: L("열기"))
    alert.addButton(withTitle: L("취소"))
    if alert.runModal() == .alertFirstButtonReturn {
      NSWorkspace.shared.open(url)
    }
  }
}
