import Foundation

// [FEATURE] 화면 요소 스냅샷 (PLAN_v0.25 Phase 1 — 읽기 전용)
//
// 접근성(AX) 트리를 **모델과 사람이 같은 언어로** 읽을 수 있게 평평한 목록으로 만든다.
// 이 파일은 **순수 계산**만 한다 — AX 호출은 `QuickTalkApp/AccessibilityService.swift` 가 맡는다.
// (그래서 권한 없이도 단위 테스트로 계약을 고정할 수 있다)
//
// 원칙
//   · 참조(`r1`, `r2`, …)는 **스냅샷 안에서만** 유효하다. 저장하거나 다음 턴에 쓰지 않는다.
//   · 비밀번호 필드는 **값을 절대 싣지 않는다**(`isSecure` 표시만).
//   · 이름 없는 컨테이너는 목록에서 빼고 자식만 올린다 — 경로가 화면마다 흔들리지 않게.
//   · 노드 수·깊이·이름 길이에 상한을 둔다(거대한 창에서도 모델 컨텍스트를 태우지 않게).

/// 화면 좌표(정수) — 승인 카드에서 사람이 확인할 수 있게 함께 보여 준다.
public struct UiPoint: Equatable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }
}

/// 요소의 화면 사각형 — 중심 좌표는 클릭 지점(Phase 2)이 된다.
public struct UiRect: Equatable, Sendable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public var center: UiPoint {
    UiPoint(x: Int((x + width / 2).rounded()), y: Int((y + height / 2).rounded()))
  }
}

/// AX 트리 한 노드 — 앱 쪽에서 채운다.
public struct UiNode: Equatable, Sendable {
  public var role: String
  public var name: String
  public var hasValue: Bool
  public var isSecure: Bool
  public var isEnabled: Bool
  public var frame: UiRect?
  public var children: [UiNode]

  public init(role: String, name: String = "", hasValue: Bool = false,
              isSecure: Bool = false, isEnabled: Bool = true,
              frame: UiRect? = nil, children: [UiNode] = []) {
    self.role = role
    self.name = name
    self.hasValue = hasValue
    self.isSecure = isSecure
    self.isEnabled = isEnabled
    self.frame = frame
    self.children = children
  }
}

public enum UiSnapshotLimits {
  /// 한 번에 보여 줄 요소 수 — 넘으면 잘라서 알린다.
  public static let maxNodes = 400
  /// 트리 깊이 상한(컨테이너가 깊은 앱에서 무한히 내려가지 않게).
  public static let maxDepth = 12
  /// 요소 이름 길이 상한.
  public static let maxNameLength = 120
  /// AX 호출 전체 예산 — 앱이 멈춰 있어도 이 시간 안에 포기한다.
  public static let deadlineSeconds: TimeInterval = 6
  /// AX 메시징 타임아웃(호출 1회).
  public static let messagingTimeout: Float = 1.5

  /// 이름이 없어도 목록에 남기는 역할 — 이름 없이도 "누를 수 있는 것"이다.
  public static let interactiveRoles: Set<String> = [
    "button", "checkbox", "radio", "popup", "combobox", "textfield", "textarea",
    "slider", "tab", "menuitem", "link", "searchfield", "incrementor", "stepper"
  ]
}

/// 평평한 요소 목록 — 모델에게 그대로 넘긴다.
public struct UiSnapshot: Equatable, Sendable {
  public struct Entry: Equatable, Sendable {
    /// `r1` 형식 — 스냅샷 안에서만 유효.
    public var ref: String
    /// 들여쓰기 깊이(0부터).
    public var depth: Int
    public var role: String
    public var name: String
    public var hasValue: Bool
    public var isSecure: Bool
    public var isEnabled: Bool
    public var center: UiPoint?
    public var path: UiElementPath

    public init(ref: String, depth: Int, role: String, name: String,
                hasValue: Bool, isSecure: Bool, isEnabled: Bool,
                center: UiPoint?, path: UiElementPath) {
      self.ref = ref
      self.depth = depth
      self.role = role
      self.name = name
      self.hasValue = hasValue
      self.isSecure = isSecure
      self.isEnabled = isEnabled
      self.center = center
      self.path = path
    }
  }

  public var appName: String
  public var windowTitle: String
  public var entries: [Entry]
  /// 노드 상한에 걸려 잘렸는가.
  public var truncated: Bool

  public init(appName: String, windowTitle: String, entries: [Entry], truncated: Bool) {
    self.appName = appName
    self.windowTitle = windowTitle
    self.entries = entries
    self.truncated = truncated
  }

  public var isEmpty: Bool { entries.isEmpty }
  public var count: Int { entries.count }

  public func entry(ref: String) -> Entry? {
    entries.first { $0.ref == ref }
  }

  /// AX 역할(`AXButton`) → 목록에 쓰는 이름(`button`).
  public static func displayRole(_ axRole: String) -> String {
    var role = axRole
    if role.hasPrefix("AX") { role = String(role.dropFirst(2)) }
    return role.lowercased()
  }

  /// 트리 → 목록. 화면 상태를 바꾸지 않는다.
  public static func build(appName: String, windowTitle: String,
                           root: UiNode) -> UiSnapshot {
    var entries: [Entry] = []
    var truncated = false

    func shouldEmit(_ node: UiNode, role: String, name: String) -> Bool {
      if !name.isEmpty { return true }
      if node.hasValue || node.isSecure { return true }
      return UiSnapshotLimits.interactiveRoles.contains(role)
    }

    func clipped(_ name: String) -> String {
      let flat = name.replacingOccurrences(of: "\n", with: " ")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard flat.count > UiSnapshotLimits.maxNameLength else { return flat }
      return String(flat.prefix(UiSnapshotLimits.maxNameLength - 1)) + "…"
    }

    func walk(children: [UiNode], depth: Int, parent: UiElementPath,
              occurrences: inout [String: Int]) {
      guard depth <= UiSnapshotLimits.maxDepth else {
        truncated = true
        return
      }
      for child in children {
        let role = displayRole(child.role)
        let name = clipped(child.name)
        if shouldEmit(child, role: role, name: name) {
          guard entries.count < UiSnapshotLimits.maxNodes else {
            truncated = true
            return
          }
          let key = role + "\u{1}" + name
          let index = occurrences[key, default: 0]
          occurrences[key] = index + 1
          let path = parent.appending(.init(role: role, name: name, index: index))
          entries.append(Entry(ref: "r\(entries.count + 1)", depth: depth,
                               role: role, name: name,
                               // 비밀번호 필드는 값이 있어도 **없다고** 한다.
                               hasValue: child.isSecure ? false : child.hasValue,
                               isSecure: child.isSecure,
                               isEnabled: child.isEnabled,
                               center: child.frame?.center,
                               path: path))
          // 이름 있는 요소의 자식은 **새 부모** 아래에서 순번을 다시 센다.
          var childOccurrences: [String: Int] = [:]
          walk(children: child.children, depth: depth + 1, parent: path,
               occurrences: &childOccurrences)
        } else {
          // 이름 없는 컨테이너 — 자식이 부모 자리로 올라오므로 **같은 순번표**를 이어 쓴다.
          // (따로 세면 평탄화된 형제끼리 index 가 겹쳐 경로가 모호해진다)
          walk(children: child.children, depth: depth, parent: parent,
               occurrences: &occurrences)
        }
      }
    }

    // 창 자체는 머리말(앱·창 제목)에 이미 있으므로 목록에서 뺀다.
    var rootOccurrences: [String: Int] = [:]
    walk(children: root.children, depth: 0, parent: UiElementPath(),
         occurrences: &rootOccurrences)
    return UiSnapshot(appName: appName, windowTitle: windowTitle,
                      entries: entries, truncated: truncated)
  }

  /// 모델에게 넘길 본문. 요소가 없으면 이유를 함께 적는다(빈 문자열을 돌려주지 않는다).
  public func render() -> String {
    guard !entries.isEmpty else {
      return L("화면에서 요소를 찾지 못했습니다 — 앱이 접근성 트리를 노출하지 않을 수 있습니다. 스크린샷(screenshot 도구)을 대신 쓰세요.")
    }
    var lines: [String] = []
    let title = windowTitle.isEmpty ? L("(제목 없음)") : windowTitle
    lines.append(Lf("앱: %@ · 창: %@ · 요소 %d개", appName, title, entries.count))
    for entry in entries {
      let indent = String(repeating: "  ", count: min(entry.depth, 8))
      var line = "\(indent)[\(entry.ref)] \(entry.role)"
      if !entry.name.isEmpty { line += " \"\(entry.name)\"" }
      if entry.isSecure { line += " secure" }
      if entry.hasValue { line += " value" }
      if !entry.isEnabled { line += " disabled" }
      if let center = entry.center { line += " center=(\(center.x),\(center.y))" }
      lines.append(line)
    }
    if truncated {
      lines.append(Lf("… 요소가 많아 %d개까지만 표시했습니다.", UiSnapshotLimits.maxNodes))
    }
    return lines.joined(separator: "\n")
  }

  /// 승인 카드·로그용 한 줄.
  public var cardTitle: String {
    let title = windowTitle.isEmpty ? appName : "\(appName) — \(windowTitle)"
    return Lf("화면 요소 — %@", title)
  }
}
