import Foundation

// [FEATURE] 승인된 조작 앱 — 대화별로 유지 (PLAN_v0.25 Phase 2)
//
// 승인 폴더(`WriteScopeGrant`, 2026-10-29)와 **같은 모델**이다.
//   · 대화 기록과 함께 저장한다(앱을 다시 켜도 유지).
//   · 7일 뒤 자동 만료한다 — 잊고 있던 앱 조작이 계속 열려 있지 않게.
//   · 다시 승인하면 같은 앱의 기간이 **새로 시작**한다.
//   · 만료 시각과 같은 순간은 만료로 본다.

public struct UiAppGrant: Codable, Equatable, Identifiable {
  /// 승인한 앱의 번들 ID — 승인 단위.
  public let bundleID: String
  /// 화면에 보여 줄 앱 이름(승인 시점 이름).
  public let name: String
  public let approvedAt: Date
  public let expiresAt: Date

  public var id: String { bundleID }

  /// 기본 유효 기간 — 7일.
  public static let defaultLifetime: TimeInterval = 7 * 24 * 60 * 60

  public init(bundleID: String, name: String, approvedAt: Date = Date(),
              lifetime: TimeInterval = UiAppGrant.defaultLifetime) {
    self.bundleID = bundleID
    self.name = name
    self.approvedAt = approvedAt
    self.expiresAt = approvedAt.addingTimeInterval(lifetime)
  }

  /// 아직 유효한가. 만료 시각과 같은 순간은 만료로 본다.
  public func isActive(at now: Date = Date()) -> Bool {
    now < expiresAt
  }

  /// 승인 목록 갱신 — 만료된 승인은 버리고, 같은 앱은 **기간을 새로 시작**한다.
  public static func approve(bundleID: String, name: String,
                             into grants: [UiAppGrant],
                             at now: Date = Date()) -> [UiAppGrant] {
    let id = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return grants.filter { $0.isActive(at: now) } }
    var active = grants.filter { $0.isActive(at: now) }
    active.removeAll { $0.bundleID == id }
    active.append(UiAppGrant(bundleID: id, name: name, approvedAt: now))
    return active
  }
}

extension Conversation {
  /// 지금 유효한 앱 승인 — 만료된 승인은 내보내지 않는다.
  public func activeUiAppGrants(at now: Date = Date()) -> [UiAppGrant] {
    (approvedUiApps ?? []).filter { $0.isActive(at: now) }
  }

  /// 이 대화에서 이 앱을 승인했는가.
  public func hasActiveUiAppGrant(bundleID: String, at now: Date = Date()) -> Bool {
    activeUiAppGrants(at: now).contains { $0.bundleID == bundleID }
  }
}
