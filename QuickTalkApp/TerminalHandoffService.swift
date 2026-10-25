import AppKit
import Foundation

// [FEATURE] 터미널 인계 — `.command` 파일을 만들어 Finder/터미널로 연다 (v0.20)
//
// 앱은 명령을 **실행하지 않는다**. 파일을 만들고 여는 것뿐이다.
// AppleScript(`do script`)는 자동화 권한이 필요하므로 쓰지 않는다 — 최소 권한 원칙.
enum TerminalHandoffService {
  /// 인계 파일을 만들고 연다. 실패하면 사유를 돌려준다(무음 실패 금지).
  @MainActor
  static func open(command: String) -> String? {
    let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return L("넘길 명령이 비어 있습니다.") }
    guard let dir = handoffDir() else {
      return L("터미널 인계 파일을 만들 폴더를 찾지 못했습니다.")
    }
    let url = dir.appendingPathComponent(TerminalHandoff.fileName(command: trimmed))
    let body = TerminalHandoff.script(command: trimmed)
    do {
      try body.write(to: url, atomically: true, encoding: .utf8)
      // 실행 권한 — 터미널이 열면 바로 실행된다(내용은 사용자가 확인할 수 있다).
      try FileManager.default.setAttributes([.posixPermissions: 0o700],
                                            ofItemAtPath: url.path)
    } catch {
      NSLog("[ERROR] E-MAC-HANDOFF-0001 인계 파일 생성 실패: %@", String(describing: error))
      return L("터미널 인계 파일을 만들지 못했습니다.")
    }
    let opened = NSWorkspace.shared.open(url)
    NSLog("[QuickTalk] 터미널 인계 — 파일 %@ · 열림 %@", url.lastPathComponent, opened ? "Y" : "N")
    if !opened {
      return L("인계 파일은 만들었지만 터미널로 열지 못했습니다. Finder에서 열어 보세요.")
    }
    return nil
  }

  /// 인계 파일 폴더 — 임시 폴더에 두고 오래된 파일은 정리한다.
  private static func handoffDir() -> URL? {
    let dir = FileManager.default.temporaryDirectory
      .appendingPathComponent("QuickTalk/handoff", isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    } catch {
      return nil
    }
    prune(dir)
    return dir
  }

  /// 7일 지난 인계 파일 정리.
  private static func prune(_ dir: URL, keepDays: Int = 7) {
    let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86_400)
    guard let items = try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    for url in items {
      let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if date < cutoff { try? FileManager.default.removeItem(at: url) }
    }
  }
}
