import AppKit
import Foundation

// [FEATURE] 단일 인스턴스 — QuickTalk 은 한 번에 하나만 실행한다 (2026-10-22)
//
// 중복 실행되면 메뉴바 아이콘·대화 창·포인터 pill 이 **각각** 생긴다.
// (실사용 신고: pill 창이 두 개 겹쳐 뜸)
// 설치본과 디버그 빌드처럼 실행 파일 경로가 달라도 번들 ID 가 같으므로 하나로 본다.
//
// 판정은 Core 의 `InstanceLock`(flock) — 프로세스가 끝나면 OS 가 잠금을 자동으로 푼다.
//
// QA 하네스(`--render=`·`--ask=` …)는 개발 중에만 쓰는 임시 실행이라
// 이미 앱이 떠 있어도 돌아가야 한다 → 단일 인스턴스 검사에서 제외한다.

enum SingleInstance {
  static let bundleID = "com.borasarang.QuickTalk"
  /// 기존 인스턴스에 "창을 앞으로 내라"고 알리는 분산 알림
  static let activateNotification = Notification.Name("com.borasarang.QuickTalk.activate")

  private static let lock: InstanceLock = {
    let fm = FileManager.default
    let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("QuickTalk", isDirectory: true)
    try? fm.createDirectory(at: base, withIntermediateDirectories: true)
    return InstanceLock(path: base.appendingPathComponent("instance.lock").path)
  }()

  /// 화면을 띄우지 않는 QA 하네스인가.
  ///
  /// 오프스크린 렌더·헤드리스 자가진단만 예외로 둔다(창·메뉴바 아이콘을 만들지 않는다).
  /// `--ask=`·`--open-panel` 처럼 **창을 띄우는** 실행은 일반 실행과 똑같이 중복을 막는다
  /// — 정확히 그 경우에 앱이 두 개 떠서 pill·창이 겹쳤다(2026-10-22 신고).
  static var isHeadlessHarness: Bool {
    let headlessPrefixes = [
      "--render=",
      "--search-test=", "--answer-test=", "--tool-test=", "--search-decide-test=",
      "--search-answer-test=", "--agent-test=", "--selftest=",
      "--compact-test", "--compact-auto-test=", "--fallback-test",
    ]
    return CommandLine.arguments.contains { arg in
      headlessPrefixes.contains { arg.hasPrefix($0) }
    }
  }

  /// 잠금을 잡는다. 이미 다른 인스턴스가 잡고 있으면 false.
  static func acquire() -> Bool {
    let ok = lock.acquire()
    if !ok { NSLog("[QuickTalk] 단일 인스턴스 잠금이 이미 잡혀 있습니다") }
    return ok
  }

  /// 중복 실행을 시도한 쪽 — 기존 인스턴스를 앞으로 가져오고 스스로 끝난다.
  static func activateExisting() {
    DistributedNotificationCenter.default().postNotificationName(
      activateNotification, object: nil, userInfo: nil, deliverImmediately: true)
    if let running = NSRunningApplication
      .runningApplications(withBundleIdentifier: bundleID)
      .first(where: { $0.processIdentifier != getpid() }) {
      running.activate(options: [.activateAllWindows])
    }
  }

  static func release() {
    lock.release()
  }
}
