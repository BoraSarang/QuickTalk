import Foundation

/// 로컬 비밀 저장소 — API 키 등은 이 Mac의 사용자 전용 파일에만 저장한다.
/// 키체인을 쓰지 않으므로 앱 실행 때마다 접근 허용 프롬프트가 뜨지 않는다.
/// 위치: `~/Library/Application Support/QuickTalk/secrets.json` (파일 권한 600)
///
/// 저장 구조는 `{ "<secretID>": "<secret>" }` 이며, 설정 파일(providers)에는 ID만 둔다.
/// 토큰·키는 로그·화면 어디에도 출력하지 않는다.
public enum SecretStore {
  public static var fileURL: URL {
    if let override = fileURLOverride { return override }
    return FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Application Support/QuickTalk/secrets.json")
  }

  /// 테스트 전용 — 실제 사용자 파일을 건드리지 않도록 경로를 바꾼다.
  static var fileURLOverride: URL?

  public static func load(account: String) -> String? {
    guard !account.isEmpty else { return nil }
    let value = all()[account]
    return (value?.isEmpty ?? true) ? nil : value
  }

  public static func has(account: String) -> Bool { load(account: account) != nil }

  @discardableResult
  public static func save(account: String, secret: String) -> Bool {
    guard !account.isEmpty, !secret.isEmpty else { return false }
    var dict = all()
    dict[account] = secret
    return write(dict)
  }

  @discardableResult
  public static func delete(account: String) -> Bool {
    guard !account.isEmpty else { return false }
    var dict = all()
    guard dict.removeValue(forKey: account) != nil else { return true }
    return write(dict)
  }

  // MARK: - 파일 입출력

  private static func all() -> [String: String] {
    guard let data = try? Data(contentsOf: fileURL),
          let dict = try? JSONDecoder().decode([String: String].self, from: data) else { return [:] }
    return dict
  }

  private static func write(_ dict: [String: String]) -> Bool {
    let fm = FileManager.default
    let dir = fileURL.deletingLastPathComponent()
    do {
      try fm.createDirectory(at: dir, withIntermediateDirectories: true,
                             attributes: [.posixPermissions: 0o700])
      if dict.isEmpty {
        try? fm.removeItem(at: fileURL)
        return true
      }
      let data = try JSONEncoder().encode(dict)
      try data.write(to: fileURL, options: [.atomic])
      // 소유자 전용 권한 (0600)
      try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
      return true
    } catch {
      NSLog("[ERROR] E-MAC-KEY-0001 비밀 저장 실패: \(error.localizedDescription)")
      return false
    }
  }
}
