import AppIntents
import AppKit
import Foundation

// [FEATURE] Shortcuts / Siri 연동 (v0.21)
//
// 원칙
//   · Shortcuts는 **입력창에 질문을 채우기만** 한다. 자동 전송하지 않는다.
//     (자동 전송은 사용자가 확인하지 않은 명령이 실행될 수 있어 도구 권한 게이트의 뜻과 어긋난다)
//   · 앱이 아직 떠 있지 않으면 Shortcuts가 앱을 실행한다. 그때 `perform()` 이
//     `applicationDidFinishLaunching` 보다 먼저 끝날 수 있으므로, 라우터가 **대기열**을 들고 있다가
//     준비되면 넘긴다(질문이 조용히 사라지지 않게).
//   · 화면이 없는 메뉴바 앱이라 결과는 dialog 로 알려 준다.

/// AppIntent → AppDelegate 사이의 얇은 다리.
///
/// `perform()` 은 임의 스레드에서 올 수 있고, `applicationDidFinishLaunching` 은 메인 스레드다.
/// 두 쪽이 같은 상자를 보게 락만 쓴다(액터 격리 없이 안전).
final class QuickTalkIntentRouter: @unchecked Sendable {
  static let shared = QuickTalkIntentRouter()

  private let lock = NSLock()
  private var handler: (@MainActor (String) -> Void)?
  private var pending: String?

  private init() {}

  /// AppDelegate가 준비되면 설치한다 — 그 전에 들어온 질문은 여기서 넘긴다.
  func install(_ handler: @escaping @MainActor (String) -> Void) {
    lock.lock()
    self.handler = handler
    let pending = self.pending
    self.pending = nil
    lock.unlock()
    if let pending {
      Task { @MainActor in handler(pending) }
    }
  }

  /// 질문을 입력창에 채운다(자동 전송 없음).
  func fillDraft(_ text: String) {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    lock.lock()
    let handler = self.handler
    if handler == nil { pending = trimmed }   // 앱이 막 실행됐다 — 준비되면 넘긴다
    lock.unlock()
    guard let handler else { return }
    Task { @MainActor in handler(trimmed) }
  }

  /// 대화 창을 연다(질문 없이).
  func openChat() {
    Task { @MainActor in
      NotificationCenter.default.post(name: .quickTalkShowChat, object: nil)
    }
  }
}

// MARK: - Intents

/// 질문을 QuickTalk 입력창에 채운다. **전송은 사용자가** 한다.
@available(macOS 13.0, *)
struct QuickTalkFillDraftIntent: AppIntent {
  static var title: LocalizedStringResource = "QuickTalk에 질문 채우기"
  static var description = IntentDescription(
    "QuickTalk 입력창에 질문을 채웁니다. 자동으로 보내지 않으므로 확인한 뒤 전송하세요.")
  /// 앱을 앞으로 가져와 입력창을 보여 준다.
  static var openAppWhenRun: Bool = true

  @Parameter(title: "질문", description: "QuickTalk 입력창에 넣을 문장")
  var text: String

  init() {}

  init(text: String) {
    self.text = text
  }

  func perform() async throws -> some IntentResult & ProvidesDialog {
    QuickTalkIntentRouter.shared.fillDraft(text)
    return .result(dialog: "QuickTalk 입력창에 넣었습니다. 확인한 뒤 전송하세요.")
  }
}

/// QuickTalk 대화 창을 연다.
@available(macOS 13.0, *)
struct QuickTalkOpenIntent: AppIntent {
  static var title: LocalizedStringResource = "QuickTalk 열기"
  static var description = IntentDescription("QuickTalk 대화 창을 엽니다.")
  static var openAppWhenRun: Bool = true

  init() {}

  func perform() async throws -> some IntentResult {
    QuickTalkIntentRouter.shared.openChat()
    return .result()
  }
}

/// Siri·Shortcuts 앱에 노출할 기본 동작.
@available(macOS 13.0, *)
struct QuickTalkShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(intent: QuickTalkFillDraftIntent(),
                phrases: [
                  "\(.applicationName)에 질문 채우기",
                  "Ask \(.applicationName)"
                ],
                shortTitle: "질문 채우기",
                systemImageName: "text.cursor")
    AppShortcut(intent: QuickTalkOpenIntent(),
                phrases: [
                  "\(.applicationName) 열기",
                  "Open \(.applicationName)"
                ],
                shortTitle: "QuickTalk 열기",
                systemImageName: "macwindow")
  }
}
