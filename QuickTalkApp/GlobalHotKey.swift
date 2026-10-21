import AppKit
import Carbon

/// Carbon `RegisterEventHotKey` 기반 전역 단축키 등록기.
///
/// `NSEvent.addGlobalMonitorForEvents`는 macOS 10.15+에서 **입력 모니터링 권한**이 없으면
/// 조용히 아무 이벤트도 받지 못한다(앱이 활성일 때만 로컬 모니터가 동작 → "포커스 있을 때만 단축키 동작" 증상).
/// Carbon 핫키는 그 권한이 필요 없고, Spotlight 등 시스템 단축키와 같은 조합도 앱 등록이 우선한다.
///
/// 등록은 모두 `registerTemporary` 하나로 한다 — 앱이 시작할 때 전역 단축키(설정값)를,
/// 창이 키일 때만 ⌘C/⌘V 같은 편집 단축키를 등록하고, 필요할 때 토큰(id)으로 해제한다.
final class GlobalHotKey {
  static let shared = GlobalHotKey()

  private struct Entry {
    let ref: EventHotKeyRef
    let action: () -> Void
  }

  private var entries: [UInt32: Entry] = [:]
  private var eventHandler: EventHandlerRef?
  private var nextID: UInt32 = 1

  private init() {}

  // MARK: - 등록/해제

  /// 반환된 id로 `unregister(id:)` 한다.
  func registerTemporary(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) -> UInt32? {
    addHotKey(keyCode: keyCode, modifiers: modifiers, action: action)
  }

  func unregister(id: UInt32) {
    if let entry = entries.removeValue(forKey: id) { UnregisterEventHotKey(entry.ref) }
  }

  // MARK: - 내부

  private func addHotKey(keyCode: Int, modifiers: UInt32, action: @escaping () -> Void) -> UInt32? {
    installHandlerIfNeeded()
    let id = nextID
    var ref: EventHotKeyRef?
    let hotKeyID = EventHotKeyID(signature: OSType(0x51544B31), id: id) // 'QTK1'
    let status = RegisterEventHotKey(UInt32(keyCode), modifiers, hotKeyID,
                                     GetApplicationEventTarget(), 0, &ref)
    guard status == noErr, let ref else { return nil }
    nextID += 1
    entries[id] = Entry(ref: ref, action: action)
    return id
  }

  private func installHandlerIfNeeded() {
    guard eventHandler == nil else { return }
    var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                             eventKind: UInt32(kEventHotKeyPressed))
    let status = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, userData in
        guard let userData, let event else { return noErr }
        let box = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
        var hotKeyID = EventHotKeyID()
        let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), nil,
                                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard err == noErr else { return noErr }
        box.entries[hotKeyID.id]?.action()
        return noErr
      },
      1, &spec,
      Unmanaged.passUnretained(self).toOpaque(),
      &eventHandler
    )
    if status != noErr { NSLog("[WARN] 단축키 핸들러 설치 실패 status=%d", status) }
  }

  /// "Cmd+Shift+Space" / "Option+Shift+3" → (keyCode, Carbon 수정자 마스크)
  static func parse(_ shortcut: String) -> (keyCode: Int, modifiers: UInt32)? {
    guard let combo = ShortcutCombo.parse(shortcut),
          let keyCode = keyCodes[combo.key] else { return nil }
    var modifiers: UInt32 = 0
    if combo.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
    if combo.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
    if combo.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
    if combo.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
    guard modifiers != 0 else { return nil }
    return (keyCode, modifiers)
  }

  /// 설정의 '변경' 버튼 — 실제 키 입력(NSEvent)을 저장 문자열로 바꾼다.
  static func comboString(keyCode: Int, flags: NSEvent.ModifierFlags) -> String? {
    guard let key = keyNames[keyCode] else { return nil }
    var mods: Set<ShortcutCombo.Modifier> = []
    if flags.contains(.command) { mods.insert(.command) }
    if flags.contains(.control) { mods.insert(.control) }
    if flags.contains(.option) { mods.insert(.option) }
    if flags.contains(.shift) { mods.insert(.shift) }
    guard !mods.isEmpty else { return nil }
    return ShortcutCombo(key: key, modifiers: mods).canonical
  }

  /// 표시용("⌥⇧3")
  static func display(_ shortcut: String) -> String { ShortcutCombo.display(shortcut) }

  /// 키 이름 → Carbon 키코드 (Core `ShortcutCombo.keyTokens`와 짝)
  static let keyCodes: [String: Int] = [
    "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E,
    "F": kVK_ANSI_F, "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J,
    "K": kVK_ANSI_K, "L": kVK_ANSI_L, "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O,
    "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R, "S": kVK_ANSI_S, "T": kVK_ANSI_T,
    "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X, "Y": kVK_ANSI_Y,
    "Z": kVK_ANSI_Z,
    "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
    "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
    "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal,
    "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket,
    ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
    ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
    "\\": kVK_ANSI_Backslash, "`": kVK_ANSI_Grave,
    "Space": kVK_Space, "Return": kVK_Return, "Tab": kVK_Tab, "Escape": kVK_Escape,
    "Left": kVK_LeftArrow, "Right": kVK_RightArrow, "Up": kVK_UpArrow, "Down": kVK_DownArrow,
    "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
    "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
  ]

  static let keyNames: [Int: String] = Dictionary(uniqueKeysWithValues: keyCodes.map { ($1, $0) })
}
