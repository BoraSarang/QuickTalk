import AppKit
import Foundation
import UserNotifications

// [FEATURE] 예약 작업 알림 (v0.26 5단계)
//
// 알림은 **앱이 실행 중일 때만** 온다(PLAN §11 — 앱이 꺼져 있으면 실행 자체가 없다).
//   · 완료/실패 — 리포트 파일명 또는 실패 사유
//   · 승인 대기 — 알림을 눌러 그 대화를 열고 카드에서 승인한다(알림에서 직접 승인 불가)
// 소리는 macOS 기본음이고, 야간 무음 시간에는 배너만 띄운다(설정에서 변경).

/// 알림 권한 상태 — 설정 화면이 안내를 띄운다.
enum NotificationPermission: String, Equatable {
  /// 아직 물어보지 않음
  case unknown
  case allowed
  case denied
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
  /// 알림 클릭 → 이 대화를 연다(AppDelegate 가 패널 열기와 연결한다).
  var onOpenConversation: ((UUID) -> Void)?

  private unowned let store: UIStore
  private let center = UNUserNotificationCenter.current()

  private enum Category {
    static let approval = "QT_APPROVAL"
    static let run = "QT_RUN"
    static let open = "QT_OPEN"
  }

  private enum InfoKey {
    static let conversationID = "conversationID"
  }

  init(store: UIStore) {
    self.store = store
    super.init()
    center.delegate = self
    registerCategories()
    refreshPermission()
  }

  // MARK: - 권한

  /// 시스템 설정을 다시 읽어 `store.notificationPermission` 을 갱신한다.
  func refreshPermission() {
    center.getNotificationSettings { [weak self] settings in
      let permission: NotificationPermission
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral:
        permission = .allowed
      case .denied:
        permission = .denied
      case .notDetermined:
        permission = .unknown
      @unknown default:
        permission = .unknown
      }
      Task { @MainActor in self?.store.notificationPermission = permission }
    }
  }

  /// 첫 사용 시 권한 요청 — 이미 정했으면 아무 일도 하지 않는다.
  @discardableResult
  func requestAuthorizationIfNeeded() async -> Bool {
    let settings = await center.notificationSettings()
    switch settings.authorizationStatus {
    case .authorized, .provisional, .ephemeral:
      store.notificationPermission = .allowed
      return true
    case .denied:
      store.notificationPermission = .denied
      return false
    case .notDetermined:
      let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
      refreshPermission()
      return granted
    @unknown default:
      return false
    }
  }

  /// 시스템 설정 › 알림 — 앱 항목을 바로 연다(안 되면 알림 설정 루트).
  func openSystemSettings() {
    let bundleID = Bundle.main.bundleIdentifier ?? "com.borasarang.QuickTalk"
    let candidates = [
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(bundleID)",
      "x-apple.systempreferences:com.apple.preference.notifications"
    ]
    for raw in candidates {
      if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
    }
  }

  // MARK: - 알림 보내기

  /// 승인 대기 — 대화를 열어 승인/거부하게 한다(알림에서 직접 승인 불가).
  func notifyApproval(_ approval: ScheduledApproval) {
    guard store.settings.notificationsEnabled, store.settings.notifyOnApproval else { return }
    Task { await deliverApproval(approval) }
  }

  /// 실행 1회 종료 — 성공/실패만 알린다(사용자가 취소한 실행은 알리지 않는다).
  func notifyRunFinished(_ notice: ScheduledRunNotice) {
    guard store.settings.notificationsEnabled,
          ScheduleNotificationText.shouldNotify(notice.status) else { return }
    Task { await deliverRun(notice) }
  }

  /// 맡긴 작업(Job) 완료·실패·일시 중지 — v0.38.
  func notifyJobFinished(_ job: Job) {
    guard store.settings.notificationsEnabled else { return }
    switch job.status {
    case .completed, .failed, .paused, .interrupted:
      break
    case .running, .queued, .waitingApproval, .cancelled:
      return
    }
    Task { await deliverJob(job) }
  }

  private func deliverApproval(_ approval: ScheduledApproval) async {
    guard await requestAuthorizationIfNeeded() else { return }
    let content = UNMutableNotificationContent()
    if approval.kind == .job {
      let text = JobNotificationText.approval(title: approval.displayTitle ?? L("맡긴 작업"),
                                              reason: approval.request.shortReason)
      content.title = text.title
      content.subtitle = text.subtitle
      content.body = text.body
    } else {
      let task = store.schedulerService?.task(approval.taskID)
      let text = ScheduleNotificationText.approval(personaName: approval.personaName,
                                                   taskTitle: task?.title,
                                                   reason: approval.request.shortReason)
      content.title = text.title
      content.subtitle = text.subtitle ?? L("예약 작업")
      content.body = text.body
    }
    content.sound = sound()
    content.categoryIdentifier = Category.approval
    content.userInfo = [InfoKey.conversationID: approval.conversationID.uuidString]

    let request = UNNotificationRequest(
      identifier: "qt-approval-\(approval.taskID.uuidString)",
      content: content, trigger: nil)
    do {
      try await center.add(request)
      NSLog("[QuickTalk] 승인 대기 알림 표시")
    } catch {
      NSLog("[WARN] 승인 대기 알림 실패: %@", String(describing: error))
    }
  }

  private func deliverRun(_ notice: ScheduledRunNotice) async {
    guard await requestAuthorizationIfNeeded() else { return }
    let text = ScheduleNotificationText.run(personaName: notice.personaName,
                                            taskTitle: notice.title,
                                            status: notice.status,
                                            fileName: notice.fileName,
                                            reason: notice.reason)
    let content = UNMutableNotificationContent()
    content.title = text.title
    content.subtitle = text.subtitle ?? ""
    content.body = text.body
    content.sound = sound()
    content.categoryIdentifier = Category.run
    if let id = notice.conversationID {
      content.userInfo = [InfoKey.conversationID: id.uuidString]
    }

    let request = UNNotificationRequest(
      identifier: "qt-run-\(notice.taskID.uuidString)-\(UUID().uuidString)",
      content: content, trigger: nil)
    do {
      try await center.add(request)
      NSLog("[QuickTalk] 예약 실행 알림 표시 — %@", notice.status.rawValue)
    } catch {
      NSLog("[WARN] 예약 실행 알림 실패: %@", String(describing: error))
    }
  }

  /// 맡긴 작업 완료·실패·일시 중지 알림 — 클릭하면 그 Job 대화를 연다.
  private func deliverJob(_ job: Job) async {
    guard await requestAuthorizationIfNeeded() else { return }
    let text: JobNotificationText.Text
    switch job.status {
    case .completed: text = JobNotificationText.completed(job)
    case .failed: text = JobNotificationText.failed(job)
    case .paused, .interrupted: text = JobNotificationText.paused(job)
    default: return
    }
    let content = UNMutableNotificationContent()
    content.title = text.title
    content.subtitle = text.subtitle
    content.body = text.body
    content.sound = sound()
    content.categoryIdentifier = Category.run
    content.userInfo = [InfoKey.conversationID: job.conversationID.uuidString]

    let request = UNNotificationRequest(
      identifier: "qt-job-\(job.id.uuidString)-\(job.status.rawValue)-\(UUID().uuidString)",
      content: content, trigger: nil)
    do {
      try await center.add(request)
      NSLog("[QuickTalk] 맡긴 작업 알림 표시 — %@", job.status.rawValue)
    } catch {
      NSLog("[WARN] 맡긴 작업 알림 실패: %@", String(describing: error))
    }
  }

  // MARK: - 문구

  /// 야간 무음이면 소리 없이 배너만.
  private func sound() -> UNNotificationSound? {
    store.settings.isQuietHours() ? nil : .default
  }

  // MARK: - UNUserNotificationCenterDelegate

  private func registerCategories() {
    let open = UNNotificationAction(identifier: Category.open, title: L("열기"),
                                    options: [.foreground])
    let approval = UNNotificationCategory(identifier: Category.approval, actions: [open],
                                          intentIdentifiers: [], options: [])
    let run = UNNotificationCategory(identifier: Category.run, actions: [open],
                                     intentIdentifiers: [], options: [])
    center.setNotificationCategories([approval, run])
  }

  /// 앱이 앞에 있어도 배너를 보여 준다(놓치지 않게).
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  /// 배너·[열기] 클릭 — 그 대화를 연다. 알림에서 승인하지는 않는다.
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let raw = response.notification.request.content.userInfo[InfoKey.conversationID] as? String
    if let raw, let id = UUID(uuidString: raw) {
      Task { @MainActor in self.onOpenConversation?(id) }
    }
    completionHandler()
  }
}
