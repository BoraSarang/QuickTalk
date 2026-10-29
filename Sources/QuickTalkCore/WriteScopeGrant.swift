import Foundation

// [FEATURE] 승인된 쓰기 폴더 — 대화별로 유지 (2026-10-29)
//
// 이전에는 `UIStore.writeScopesByConversation` 메모리에만 있어 앱을 다시 켜면 사라졌다.
// 승인 범위는 그대로 **대화별**로 두되, 대화 기록과 함께 저장하고 **7일 뒤 자동 만료**한다.
// 오래된 승인이 조용히 남아 있으면 사용자가 잊은 폴더에 쓰기가 열릴 수 있기 때문이다.
// 만료된 승인은 판정에 쓰지 않고, 다시 승인하면 기간이 갱신된다.

public struct WriteScopeGrant: Codable, Equatable, Identifiable {
  /// 승인한 폴더(정규화된 경로)
  public let path: String
  public let approvedAt: Date
  public let expiresAt: Date

  public var id: String { path }

  /// 기본 유효 기간 — 7일.
  public static let defaultLifetime: TimeInterval = 7 * 24 * 60 * 60

  public init(path: String, approvedAt: Date = Date(),
              lifetime: TimeInterval = WriteScopeGrant.defaultLifetime) {
    self.path = path
    self.approvedAt = approvedAt
    self.expiresAt = approvedAt.addingTimeInterval(lifetime)
  }

  /// 아직 유효한가. 만료 시각과 같은 순간은 만료로 본다.
  public func isActive(at now: Date = Date()) -> Bool {
    now < expiresAt
  }

  /// 승인 목록 갱신 — 만료된 승인은 버리고, 같은 경로는 **기간을 새로 시작**한다.
  public static func approve(_ paths: [String], into grants: [WriteScopeGrant],
                             at now: Date = Date()) -> [WriteScopeGrant] {
    var active = grants.filter { $0.isActive(at: now) }
    for raw in paths {
      let path = WriteScope.normalize(raw)
      guard !path.isEmpty else { continue }
      active.removeAll { $0.path == path }
      active.append(WriteScopeGrant(path: path, approvedAt: now))
    }
    return active
  }
}

extension Conversation {
  /// 지금 유효한 승인 폴더 경로 — 만료된 승인은 내보내지 않는다.
  public func activeWriteScopePaths(at now: Date = Date()) -> [String] {
    (approvedWriteScopes ?? []).filter { $0.isActive(at: now) }.map(\.path)
  }
}
