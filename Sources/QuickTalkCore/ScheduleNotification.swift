import Foundation

/// 예약 작업 알림 문구 (v0.26 5단계).
///
/// 알림은 `UserNotifications` 가 App 계층에만 있으므로, **문구 규칙**은 여기서 순수하게
/// 만들고 테스트한다. 제목·본문·자막·알림 여부만 정하고, 소리·배너는 서비스가 맡는다.
public struct ScheduleNotificationText: Equatable {
  public let title: String
  public let subtitle: String?
  public let body: String

  /// 알림 본문 길이 상한 — macOS 배너에서 잘리지 않게.
  public static let bodyLimit = 160

  public init(title: String, subtitle: String?, body: String) {
    self.title = title
    self.subtitle = subtitle
    self.body = body
  }

  /// 승인 대기 — **알림에서 승인할 수 없다**는 안내를 본문에 넣는다.
  public static func approval(personaName: String?, taskTitle: String?,
                              reason: String) -> ScheduleNotificationText {
    let hint = L("대화를 열어 승인하거나 거부하세요.")
    return ScheduleNotificationText(
      title: Lf("%@ — 승인 대기", personaLabel(personaName)),
      subtitle: taskTitle,
      body: clipped(reason + " — " + hint))
  }

  /// 실행 1회 종료 — 성공은 파일명, 실패는 사유를 보여 준다.
  /// 승인 대기 만료는 따로 문구를 쓴다(PLAN §6).
  public static func run(personaName: String?, taskTitle: String, status: RunStatus,
                         fileName: String?, reason: String?) -> ScheduleNotificationText {
    let label = personaLabel(personaName)
    if status == .failed, reason == L("승인 대기 시간(10분)이 만료되었습니다.") {
      return ScheduleNotificationText(
        title: Lf("%@ — 승인 대기 만료", label),
        subtitle: taskTitle,
        body: L("10분 안에 승인하지 않아 취소되었습니다. 다시 실행하세요."))
    }

    let title: String
    switch status {
    case .succeeded: title = Lf("%@ — 완료", label)
    case .failed: title = Lf("%@ — 실패", label)
    case .interrupted: title = Lf("%@ — 중단됨", label)
    case .missed: title = Lf("%@ — 건너뜀", label)
    case .cancelled: title = Lf("%@ — 취소됨", label)
    case .running: title = Lf("%@ — 실행 중", label)
    case .awaitingApproval: title = Lf("%@ — 승인 대기", label)
    }

    let file = fileName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let body: String
    if status == .succeeded, !file.isEmpty {
      body = Lf("리포트: %@", file)
    } else if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      body = clipped(reason)
    } else if !file.isEmpty {
      body = Lf("리포트: %@", file)
    } else {
      body = ""
    }
    return ScheduleNotificationText(title: title, subtitle: taskTitle, body: body)
  }

  /// 사용자가 직접 취소한 실행은 알리지 않는다 — 이미 알고 있는 일이다.
  public static func shouldNotify(_ status: RunStatus) -> Bool {
    switch status {
    case .succeeded, .failed, .interrupted: return true
    case .cancelled, .missed, .running, .awaitingApproval: return false
    }
  }

  // MARK: - 도우미

  private static func personaLabel(_ name: String?) -> String {
    let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? L("기본(비서 없음)") : trimmed
  }

  static func clipped(_ text: String, limit: Int = bodyLimit) -> String {
    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.count > limit else { return clean }
    return String(clean.prefix(limit)) + "…"
  }
}
