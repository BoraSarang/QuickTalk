import Foundation

// [FEATURE] 작업 폴더 (v0.36.1, 2026-11-11)
//
// 예전 이름은 "리포트 폴더"였다. 그런데 실제 쓰임은 예약 리포트만이 아니라
// **도우미가 만든 스크립트·산출물·시험 파일이 쌓이는 작업 공간**이었다
// (사용자 관찰: 비서 없는 대화에서도 `memtop.py`·`__pycache__` 가 생긴다).
//
// 그래서 새 기본 이름을 `~/Documents/QuickTalkWorkspace` 로 두고, 앱이 만든
// 옛 이름(`QuickTalkReport`)만 **한 번** 옮긴다. 사용자가 직접 고른 다른 폴더는
// 이름이 무엇이든 건드리지 않는다.

public enum WorkspaceFolder {
  /// 새 기본 작업 폴더 — `~` 표기를 그대로 저장한다(사용자 홈이 바뀌어도 따라간다).
  public static let defaultPath = "~/Documents/QuickTalkWorkspace"

  /// 앱이 쓰던 옛 폴더 이름. 이 이름일 때만 자동 이전한다.
  public static let legacyName = "QuickTalkReport"

  /// 저장된 경로의 마지막 조각이 앱이 만든 옛 이름인가.
  public static func isLegacyPath(_ path: String, home: String = NSHomeDirectory()) -> Bool {
    let expanded = expand(path, home: home)
    return (expanded as NSString).lastPathComponent == legacyName
  }

  /// `~/…` 만 직접 푼다 — 테스트에서 가짜 홈을 쓸 수 있게(NSString 확장은 실제 홈을 쓴다).
  static func expand(_ path: String, home: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed == "~" { return home }
    if trimmed.hasPrefix("~/") { return home + String(trimmed.dropFirst(1)) }
    return trimmed
  }

  /// 설정이 옛 이름 폴더를 가리키면 새 작업 폴더로 옮기고 설정을 바꾼다.
  ///
  /// - 옛 폴더가 있고 새 폴더가 없으면 **이름만 바꾼다**(내용 보존).
  /// - 새 폴더가 이미 있으면 **합치지 않는다** — 둘 다 있으면 설정을 그대로 두고 로그만 남긴다.
  /// - 옛 폴더가 없으면 설정만 새 기본값으로 바꾼다(폴더는 필요할 때 만든다).
  ///
  /// - Returns: 설정을 바꿨으면 true.
  @discardableResult
  public static func migrate(settings: inout QuickTalkSettings,
                             fileManager: FileManager = .default,
                             home: String = NSHomeDirectory()) -> Bool {
    let configured = settings.defaultReportFolder
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let raw = configured.isEmpty ? defaultPath : configured
    guard isLegacyPath(raw, home: home) else { return false }

    let oldPath = expand(raw, home: home)
    let newPath = expand(defaultPath, home: home)
    guard oldPath != newPath else { return false }

    var isDir: ObjCBool = false
    let oldExists = fileManager.fileExists(atPath: oldPath, isDirectory: &isDir)
      && isDir.boolValue
    let newExists = fileManager.fileExists(atPath: newPath, isDirectory: &isDir)
      && isDir.boolValue

    if newExists, oldExists {
      // 두 폴더를 합치면 사용자가 어느 쪽을 보던 중인지 알 수 없다 — 손대지 않는다.
      NSLog("[WARN] 작업 폴더 이전 건너뜀 — 새 폴더가 이미 있음: %@", newPath)
      return false
    }
    if oldExists {
      do {
        try fileManager.moveItem(atPath: oldPath, toPath: newPath)
        NSLog("[QuickTalk] 작업 폴더 이전 — %@ → %@", oldPath, newPath)
      } catch {
        // 실패하면 설정도 바꾸지 않는다 — 다음 실행에서 다시 시도한다.
        NSLog("[WARN] E-MAC-REPORT-0002 작업 폴더 이전 실패: %@", error.localizedDescription)
        return false
      }
    }
    settings.defaultReportFolder = defaultPath
    return true
  }
}
