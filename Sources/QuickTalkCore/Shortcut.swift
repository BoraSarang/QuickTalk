import Foundation

// [INFO] [FEATURE] 전역 단축키 모델 (2026-10-20, T-59)
// 앱이 쓰는 단축키를 **한 곳**에서 정의하고, 설정에서 조합을 바꿀 수 있게 한다.

/// 사용자가 바꿀 수 있는 전역 단축키
public enum ShortcutAction: String, CaseIterable, Codable, Hashable, Sendable {
  case invoke
  case shelf
  case captureFull
  case captureRegion
  case captureWindow

  public var title: String {
    switch self {
    case .invoke: return L("대화 열기")
    case .shelf: return L("퀵셸프 열기/닫기")
    case .captureFull: return L("캡처 — 전체 화면")
    case .captureRegion: return L("캡처 — 드래그 선택")
    case .captureWindow: return L("캡처 — 윈도우")
    }
  }

  public var detail: String {
    switch self {
    case .invoke: return L("어디서든 대화 창을 열고 닫습니다")
    case .shelf: return L("클립보드·파일·캡처 허브를 부릅니다")
    case .captureFull: return L("모든 화면을 바로 캡처해 퀵셸프에 넣습니다")
    case .captureRegion: return L("드래그한 영역만 캡처합니다")
    case .captureWindow: return L("클릭한 창만 캡처합니다")
    }
  }

  /// 기본 조합. 캡처 3종은 macOS의 ⌘⇧3/4와 겹치지 않게 ⌥를 쓴다.
  public var defaultCombo: String {
    switch self {
    case .invoke: return "Cmd+Space"
    case .shelf: return "Option+Shift+V"
    case .captureFull: return "Option+Shift+3"
    case .captureRegion: return "Option+Shift+4"
    case .captureWindow: return "Option+Shift+Cmd+4"
    }
  }
}

/// 단축키 조합 — 문자열("Option+Shift+3")을 정규화·표시한다.
public struct ShortcutCombo: Equatable, Hashable, Codable, Sendable {
  public enum Modifier: String, CaseIterable, Codable, Sendable {
    case control, option, shift, command

    /// 저장 문자열에 쓰는 토큰
    public var token: String {
      switch self {
      case .control: return "Control"
      case .option: return "Option"
      case .shift: return "Shift"
      case .command: return "Cmd"
      }
    }

    /// 표시 기호(⌃⌥⇧⌘)
    public var symbol: String {
      switch self {
      case .control: return "⌃"
      case .option: return "⌥"
      case .shift: return "⇧"
      case .command: return "⌘"
      }
    }
  }

  public var key: String
  public var modifiers: Set<Modifier>

  public init(key: String, modifiers: Set<Modifier>) {
    self.key = key
    self.modifiers = modifiers
  }

  /// 키 이름 목록 — 앱(GlobalHotKey)의 키코드 표와 짝을 이룬다.
  public static let keyTokens: [String] = {
    let letters = (65...90).compactMap { UnicodeScalar($0).map { String(Character($0)) } }
    let digits = (0...9).map(String.init)
    let controls = ["Space", "Return", "Tab", "Escape", "Left", "Right", "Up", "Down"]
    let functions = (1...12).map { "F\($0)" }
    let punctuation = ["-", "=", "[", "]", ";", "'", ",", ".", "/", "\\", "`"]
    return letters + digits + controls + functions + punctuation
  }()

  /// 대소문자·표기 흔들림을 정규화한다("space" → "Space", "v" → "V").
  public static func canonicalKey(_ raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }
    if trimmed.count == 1, let upper = trimmed.uppercased().first,
       keyTokens.contains(String(upper)) {
      return String(upper)
    }
    return keyTokens.first { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
  }

  private static func modifier(forSymbol symbol: Character) -> Modifier? {
    switch symbol {
    case "⌘": return .command
    case "⌃": return .control
    case "⌥": return .option
    case "⇧": return .shift
    default: return nil
    }
  }

  /// "Option+Shift+3" · "⌥⇧3" · "opt+shift+3" 모두 받는다.
  public static func parse(_ string: String) -> ShortcutCombo? {
    var mods: Set<Modifier> = []
    var key: String?
    for raw in string.split(separator: "+") {
      let part = raw.trimmingCharacters(in: .whitespaces)
      if part.isEmpty { return nil }
      switch part.lowercased() {
      case "cmd", "command", "⌘": mods.insert(.command)
      case "ctrl", "control", "⌃": mods.insert(.control)
      case "opt", "option", "alt", "⌥": mods.insert(.option)
      case "shift", "⇧": mods.insert(.shift)
      default:
        // "⌥⇧3" · "⌘Space"처럼 기호가 붙은 표기도 받는다
        var rest = part
        while let first = rest.first, let mod = modifier(forSymbol: first) {
          mods.insert(mod)
          rest.removeFirst()
        }
        guard !rest.isEmpty else { continue }
        guard key == nil, let k = canonicalKey(rest) else { return nil }
        key = k
      }
    }
    guard let key, !mods.isEmpty else { return nil }   // 보조 키 없는 단일 키는 전역 단축키로 쓰지 않는다
    return ShortcutCombo(key: key, modifiers: mods)
  }

  /// 저장용 정규 문자열 — 수정자 순서를 고정해 같은 조합이 한 가지로만 표현된다.
  public var canonical: String {
    let order: [Modifier] = [.control, .option, .shift, .command]
    let mods = order.filter { modifiers.contains($0) }.map(\.token)
    return (mods + [key]).joined(separator: "+")
  }

  /// 화면 표시 — "⌥⇧3" · "⌘Space"
  public var display: String {
    let order: [Modifier] = [.control, .option, .shift, .command]
    let mods = order.filter { modifiers.contains($0) }.map(\.symbol).joined()
    return mods + keySymbol
  }

  public var keySymbol: String {
    switch key {
    case "Space": return "Space"
    case "Return": return "↩"
    case "Tab": return "⇥"
    case "Escape": return "⎋"
    case "Left": return "←"
    case "Right": return "→"
    case "Up": return "↑"
    case "Down": return "↓"
    default: return key
    }
  }

  /// 표시 문자열이 필요할 때 파싱 실패하면 원문을 그대로 보여 준다(설정이 깨져도 화면은 뜨게).
  public static func display(_ string: String) -> String {
    parse(string)?.display ?? string
  }
}

// MARK: - 설정 접근

public extension QuickTalkSettings {
  func shortcut(for action: ShortcutAction) -> String {
    switch action {
    case .invoke: return globalShortcut
    case .shelf: return shelfShortcut
    case .captureFull: return captureFullShortcut
    case .captureRegion: return captureRegionShortcut
    case .captureWindow: return captureWindowShortcut
    }
  }

  mutating func setShortcut(_ combo: String, for action: ShortcutAction) {
    switch action {
    case .invoke: globalShortcut = combo
    case .shelf: shelfShortcut = combo
    case .captureFull: captureFullShortcut = combo
    case .captureRegion: captureRegionShortcut = combo
    case .captureWindow: captureWindowShortcut = combo
    }
  }

  /// 같은 조합을 쓰는 다른 동작(중복 검사용) — 없으면 nil
  func shortcutConflict(_ combo: String, for action: ShortcutAction) -> ShortcutAction? {
    guard let target = ShortcutCombo.parse(combo) else { return nil }
    return ShortcutAction.allCases.first {
      $0 != action && ShortcutCombo.parse(shortcut(for: $0)) == target
    }
  }
}
