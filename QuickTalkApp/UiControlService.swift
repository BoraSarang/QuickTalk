import AppKit
import ApplicationServices
import CoreGraphics

// [FEATURE] 화면 조작 — CGEvent·NSWorkspace (PLAN_v0.25 Phase 2)
//
// 이 파일은 **시스템에 실제로 손을 뻗는** 유일한 곳이다.
//   · 판정(금지 앱·키·보안 필드·한도)은 `Sources/QuickTalkCore/UiGuard.swift` 가 먼저 한다.
//   · 여기서는 "판정을 통과한 동작"만 주입한다 — 스스로 허용 여부를 정하지 않는다.
//
// 안전 규칙
//   · 좌표는 모델이 주지 않는다. 요소의 AX 프레임 중심만 쓴다.
//   · 동작 사이 150ms 간격은 실행기(`AgentExecutor+UI`)가 지킨다.
//   · 사용자가 입력 중이면(0.4초 이내) 최대 2초 기다리고, 계속 입력 중이면 **실행하지 않는다**.
//   · 합성 이벤트는 `.hidSystemState` 에 잡히지 않으므로 자기 이벤트로 자기 가드가 막히지 않는다.

enum UiIdleResult {
  case ready
  case busy
  case cancelled
}

enum UiControlService {
  /// 사용자가 방금 입력했는가 — 하드웨어 이벤트만 센다.
  static func secondsSinceUserInput() -> TimeInterval {
    let key = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    let mouse = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
    let right = CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .rightMouseDown)
    return min(key, mouse, right)
  }

  /// 동작 직전 유휴 확인 — 사용자가 타자를 치는 중이면 양보한다.
  static func waitForUserIdle(threshold: TimeInterval = 0.4,
                              timeout: TimeInterval = 2.0,
                              cancellation: SandboxCancellation?) async -> UiIdleResult {
    if secondsSinceUserInput() >= threshold { return .ready }
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if cancellation?.isCancelled == true { return .cancelled }
      try? await Task.sleep(nanoseconds: 100_000_000)
      if secondsSinceUserInput() >= threshold { return .ready }
    }
    return cancellation?.isCancelled == true ? .cancelled : .busy
  }

  /// 앱을 앞으로 가져온다. 이미 앞이면 그대로 둔다.
  @discardableResult
  static func activate(_ target: UiAppTarget) -> Bool {
    guard let pid = target.pid,
          let app = NSRunningApplication(processIdentifier: pid) else { return false }
    if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
    return app.activate(options: [.activateAllWindows])
  }

  /// 앱 실행 — 이미 실행 중이면 앞으로 가져온다.
  static func open(_ target: UiAppTarget) async -> Result<UiAppTarget, UiAccessError> {
    let query = target.query
    if let running = AccessibilityService.resolveApp(query) {
      let resolved = AccessibilityService.target(for: running)
      activate(resolved)
      return .success(resolved)
    }
    guard let url = target.url else { return .failure(.appNotFound(target.name)) }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    do {
      let app = try await NSWorkspace.shared.openApplication(at: url,
                                                             configuration: configuration)
      let resolved = AccessibilityService.target(for: app)
      NSLog("[QuickTalk] 화면 조작 — 앱 열기 (이름은 로그에 남기지 않는다)")
      return .success(resolved)
    } catch {
      return .failure(.actionFailed)
    }
  }

  // MARK: - 클릭

  /// 요소 중심 클릭 — `count` 가 2면 더블클릭.
  static func click(at point: UiPoint, count: Int) {
    let p = CGPoint(x: point.x, y: point.y)
    CGWarpMouseCursorPosition(p)
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                       mouseCursorPosition: p, mouseButton: .left)
    let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                     mouseCursorPosition: p, mouseButton: .left)
    let state = Int64(max(1, count))
    down?.setIntegerValueField(.mouseEventClickState, value: state)
    up?.setIntegerValueField(.mouseEventClickState, value: state)
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
  }

  // MARK: - 텍스트

  /// 텍스트 입력 — 유니코드 이벤트라 키 배열·IME 와 무관하게 들어간다.
  /// 줄바꿈은 `return` 키로 보낸다(메일·메신저에서는 **전송**이 될 수 있다).
  static func typeText(_ text: String) {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, line) in lines.enumerated() {
      if !line.isEmpty { typeUnicode(String(line)) }
      if index < lines.count - 1 { _ = press("return") }
    }
  }

  /// CGEvent 는 한 번에 20 UTF-16 단위까지만 실을 수 있다 — 나눠 보낸다.
  private static func typeUnicode(_ text: String) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    var buffer: [UniChar] = []

    func flush() {
      guard !buffer.isEmpty else { return }
      let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true)
      down?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer)
      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
      down?.post(tap: .cghidEventTap)
      up?.post(tap: .cghidEventTap)
      buffer.removeAll(keepingCapacity: true)
    }

    for character in text {
      let units = Array(String(character).utf16)
      if buffer.count + units.count > 20 { flush() }
      buffer.append(contentsOf: units)
    }
    flush()
  }

  // MARK: - 키

  /// `cmd+s` 같은 조합 — 허용 목록은 `UiGuard.keyViolation` 이 이미 확인했다.
  @discardableResult
  static func press(_ keys: String) -> Bool {
    guard let tokens = UiGuard.keyTokens(keys) else { return false }
    var flags: CGEventFlags = []
    var key: String?
    for token in tokens {
      switch token {
      case "cmd": flags.insert(.maskCommand)
      case "opt": flags.insert(.maskAlternate)
      case "ctrl": flags.insert(.maskControl)
      case "shift": flags.insert(.maskShift)
      default: key = token
      }
    }
    guard let key, let code = keyCodes[key],
          let source = CGEventSource(stateID: .hidSystemState) else { return false }
    let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
    down?.flags = flags
    up?.flags = flags
    down?.post(tap: .cghidEventTap)
    up?.post(tap: .cghidEventTap)
    return true
  }

  /// US 배열 기준 가상 키 코드 — `UiGuard.allowedKeyTokens` 와 같은 이름을 쓴다.
  private static let keyCodes: [String: CGKeyCode] = [
    "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
    "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
    "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26,
    "-": 27, "8": 28, "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35,
    "return": 36, "l": 37, "j": 38, "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43,
    "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48, "space": 49, "`": 50,
    "delete": 51, "esc": 53,
    "left": 123, "right": 124, "down": 125, "up": 126,
    "home": 115, "end": 119, "pageup": 116, "pagedown": 121, "forwarddelete": 117,
    "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
    "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
  ]

  // MARK: - 스크롤

  /// 휠 스크롤 — `point` 가 있으면 그 요소 위에서, 없으면 현재 마우스 위치에서.
  static func scroll(_ direction: UiScrollDirection, amount: Int, at point: UiPoint?) {
    guard let source = CGEventSource(stateID: .hidSystemState) else { return }
    let lines = Int32(max(1, amount))
    let delta = direction == .up ? lines : -lines
    guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line,
                              wheelCount: 1, wheel1: delta, wheel2: 0, wheel3: 0)
    else { return }
    if let point {
      let p = CGPoint(x: point.x, y: point.y)
      CGWarpMouseCursorPosition(p)
      event.location = p
    }
    event.post(tap: .cghidEventTap)
  }
}
