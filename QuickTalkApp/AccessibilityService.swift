import AppKit
import ApplicationServices
import CoreGraphics

// [FEATURE] 화면 요소 읽기 — 접근성(AX) 트리 (PLAN_v0.25 Phase 1)
//
// Phase 2 에서 **경로로 요소를 다시 찾는** 역할까지 맡는다.
// 순수 계산(평탄화·경로·상한)은 `Sources/QuickTalkCore/UiSnapshot.swift` 가 맡고,
// 이 파일은 **AX 호출**만 한다. 그래야 권한 없이도 계약을 단위 테스트로 고정할 수 있다.
//
// 안전 규칙
//   · 메인 스레드에서 부르지 않는다(호출부가 Task.detached) — 앱이 멈춰도 QuickTalk는 멈추지 않는다.
//   · 창 하나만, 노드·깊이·시간 상한 안에서만 읽는다.
//   · `AXManualAccessibility` 힌트만 켠다(Chromium 계열이 웹 콘텐츠 트리를 노출하게 하는 **읽기 힌트**).
//   · 값을 바꾸는 속성은 쓰지 않는다(포커스 이동은 Phase 2 `UiControlService` 의 몫).

enum UiAccessError: Error, Equatable {
  case noPermission
  case appNotFound(String)
  case noWindow(String)
  case noFocusedElement(String)
  case noWindowTitle(app: String, title: String)
  case elementChanged
  case invalidElement
  case actionFailed

  var message: String {
    switch self {
    case .noPermission:
      return L("손쉬운 사용 권한이 없어 화면 요소를 읽을 수 없습니다 — 시스템 설정 › 개인정보 보호 및 보안 › 손쉬운 사용에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요.")
    case .appNotFound(let name):
      return name.isEmpty
        ? L("읽을 앱을 찾지 못했습니다 — 앱 이름이나 번들 ID를 지정하세요.")
        : Lf("'%@' 앱을 찾지 못했습니다 — 실행 중인지, 이름이 맞는지 확인하세요.", name)
    case .noWindow(let name):
      return Lf("'%@' 앱에서 읽을 창을 찾지 못했습니다 — 창이 최소화되었는지 확인하세요.", name)
    case .noFocusedElement(let name):
      return Lf("'%@' 앱에서 입력 받을 요소를 찾지 못했습니다 — 먼저 입력란을 클릭하거나 ref 를 지정하세요.", name)
    case .noWindowTitle(let app, let title):
      return Lf("'%@' 앱에서 '%@' 창을 찾지 못했습니다.", app, title)
    case .elementChanged:
      return L("UI가 바뀌었습니다 — ui_snapshot 을 다시 호출해 새 참조로 시도하세요.")
    case .invalidElement:
      return L("요소를 다시 찾지 못했습니다 — ui_snapshot 을 다시 호출하세요.")
    case .actionFailed:
      return L("화면 조작을 실행하지 못했습니다.")
    }
  }
}

/// 실행 중이거나 설치된 앱 1건 — 승인·금지 판정은 **번들 ID** 로 한다.
struct UiAppTarget {
  let bundleID: String
  let name: String
  let url: URL?
  let pid: pid_t?

  var query: String { bundleID.isEmpty ? name : bundleID }
}

/// 스냅샷 1장 + 그 안의 AX 요소 — 참조(`r12`)를 실제 요소로 되돌리는 데 쓴다.
/// 토큰은 **스냅샷 안에서만** 유효하다. UI 가 바뀌면 경로 비교에서 걸린다.
struct UiTree {
  let snapshot: UiSnapshot
  let elements: [Int: AXUIElement]
  let target: UiAppTarget
  /// 창 전체 사각형 — 참조 없는 스크롤의 기준점.
  let windowFrame: UiRect?
}

/// `focus_window` 로 앞으로 가져올 창 1개.
struct UiWindowRef {
  let target: UiActionTarget
  let element: AXUIElement
}

enum AccessibilityService {
  static var hasPermission: Bool { AXIsProcessTrusted() }

  /// 앱 하나의 창 1개를 읽어 평평한 요소 목록으로 돌려준다.
  /// - Parameter app: 앱 이름 또는 번들 ID. 비우면 **QuickTalk를 제외한** 맨 앞 앱.
  static func snapshot(app: String?) async -> Result<UiSnapshot, UiAccessError> {
    (await tree(app: app)).map(\.snapshot)
  }

  /// 스냅샷 + 토큰→AX 요소 표.
  static func tree(app: String?) async -> Result<UiTree, UiAccessError> {
    guard hasPermission else { return .failure(.noPermission) }

    let query = (app ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let target = appTarget(query) else { return .failure(.appNotFound(query)) }
    guard let pid = target.pid else { return .failure(.appNotFound(query)) }
    let deadline = Date().addingTimeInterval(UiSnapshotLimits.deadlineSeconds)

    let built: (snapshot: UiSnapshot, elements: [Int: AXUIElement], frame: UiRect?)? =
      await Task.detached(priority: .userInitiated) {
        read(pid: pid, target: target, deadline: deadline)
      }.value

    guard let built else { return .failure(.noWindow(target.name)) }
    return .success(UiTree(snapshot: built.snapshot, elements: built.elements,
                           target: target, windowFrame: built.frame))
  }

  // MARK: - 앱 고르기

  /// 이름·번들 ID로 실행 중인 앱을 찾는다. 비우면 앞에 있는(QuickTalk 제외) 앱.
  static func resolveApp(_ query: String) -> NSRunningApplication? {
    guard !query.isEmpty else { return frontmostOtherApp() }
    let lower = query.lowercased()
    let running = NSWorkspace.shared.runningApplications
      .filter { $0.activationPolicy != .prohibited }
    return running.first { ($0.bundleIdentifier ?? "").lowercased() == lower }
      ?? running.first { ($0.localizedName ?? "").lowercased() == lower }
      ?? running.first { ($0.localizedName ?? "").lowercased().contains(lower) }
      ?? running.first { ($0.bundleIdentifier ?? "").lowercased().contains(lower) }
  }

  /// 실행 중인 앱 → 설치된 앱 순서로 대상 하나를 고른다.
  /// `open_app` 은 실행 중이 아니어도 되고, 요소 조작은 실행 중이어야 한다(호출부가 pid 확인).
  static func appTarget(_ query: String) -> UiAppTarget? {
    if let running = resolveApp(query) { return target(for: running) }
    guard !query.isEmpty, let url = installedAppURL(query) else { return nil }
    let bundle = Bundle(url: url)
    let bundleID = bundle?.bundleIdentifier ?? ""
    let name = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
      ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
      ?? url.deletingPathExtension().lastPathComponent
    return UiAppTarget(bundleID: bundleID, name: name, url: url, pid: nil)
  }

  static func target(for app: NSRunningApplication) -> UiAppTarget {
    let bundleID = app.bundleIdentifier ?? ""
    let name = app.localizedName ?? (bundleID.isEmpty ? L("알 수 없는 앱") : bundleID)
    return UiAppTarget(bundleID: bundleID, name: name,
                       url: app.bundleURL, pid: app.processIdentifier)
  }

  /// 설치된 `.app` 찾기 — 흔한 폴더만 본다(전체 디스크 검색은 느리고 과하다).
  static func installedAppURL(_ query: String) -> URL? {
    let lower = query.lowercased()
    if lower.contains("."), !lower.contains(" ") {
      if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: query) { return url }
    }
    let fm = FileManager.default
    let home = NSHomeDirectory()
    let roots = ["/Applications", "/Applications/Utilities",
                 "/System/Applications", "/System/Applications/Utilities",
                 home + "/Applications"]
    for root in roots {
      guard let names = try? fm.contentsOfDirectory(atPath: root) else { continue }
      for name in names where name.hasSuffix(".app") {
        let bare = String(name.dropLast(4)).lowercased()
        guard bare == lower || bare.contains(lower) else { continue }
        let path = (root as NSString).appendingPathComponent(name)
        if let url = Bundle(path: path)?.bundleURL { return url }
      }
    }
    return nil
  }

  /// "앞에 있는 앱". 사용자가 QuickTalk에서 묻고 있으면 QuickTalk가 앞이므로,
  /// 그때는 **창 순서(z-order)에서 QuickTalk 다음에 오는 앱**을 쓴다.
  /// (모델이 앱을 지정하지 않았을 때 자기 자신을 읽는 헛수고를 막는다)
  static func frontmostOtherApp() -> NSRunningApplication? {
    let mine = ProcessInfo.processInfo.processIdentifier
    if let front = NSWorkspace.shared.frontmostApplication,
       front.processIdentifier != mine {
      return front
    }
    guard let list = CGWindowListCopyWindowInfo(
      [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
    else {
      let front = NSWorkspace.shared.frontmostApplication
      return front?.processIdentifier == mine ? nil : front
    }

    for info in list {
      guard let number = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
      let pid = number.int32Value
      if pid == mine { continue }
      // 레이어 0 = 일반 앱 창. 메뉴바·독·알림 같은 오버레이는 제외한다.
      if let layer = info[kCGWindowLayer as String] as? NSNumber, layer.intValue != 0 { continue }
      if let alpha = info[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue == 0 { continue }
      if let app = NSRunningApplication(processIdentifier: pid) { return app }
    }
    // 다른 앱 창이 하나도 없으면 **자기 자신을 읽지 않는다** — 빈 결과가 낫다.
    return nil
  }

  // MARK: - 포커스 · 창

  /// `type` 에 ref 가 없을 때 — 지금 포커스된 요소가 보안 필드인지 확인한다.
  static func focusedTarget(app query: String) async -> Result<UiActionTarget, UiAccessError> {
    guard hasPermission else { return .failure(.noPermission) }
    guard let target = appTarget(query), let pid = target.pid else {
      return .failure(.appNotFound(query))
    }
    let result: UiActionTarget? = await Task.detached(priority: .userInitiated) {
      focused(pid: pid)
    }.value
    guard let result else { return .failure(.noFocusedElement(target.name)) }
    return .success(result)
  }

  /// 같은 앱에서 제목이 맞는 창을 찾는다(정확 일치 → 포함).
  static func findWindow(app query: String, title: String) async -> Result<UiWindowRef, UiAccessError> {
    guard hasPermission else { return .failure(.noPermission) }
    guard let target = appTarget(query), let pid = target.pid else {
      return .failure(.appNotFound(query))
    }
    let result: UiWindowRef? = await Task.detached(priority: .userInitiated) {
      window(pid: pid, title: title)
    }.value
    guard let result else {
      return .failure(.noWindowTitle(app: target.name, title: title))
    }
    return .success(result)
  }

  /// 창을 앞으로 — 승인을 받은 **뒤에** 부른다(포커스를 뺏는 동작).
  static func raise(_ window: UiWindowRef) -> Bool {
    AXUIElementPerformAction(window.element, kAXRaiseAction as CFString) == .success
  }

  // MARK: - AX 트리 → UiNode (워커 스레드)

  private static func read(pid: pid_t, target: UiAppTarget,
                           deadline: Date) -> (UiSnapshot, [Int: AXUIElement], UiRect?)? {
    let app = AXUIElementCreateApplication(pid)
    // 앱이 멈춰 있어도 1.5초 안에 포기한다(AX 기본 타임아웃은 수 초).
    AXUIElementSetMessagingTimeout(app, UiSnapshotLimits.messagingTimeout)
    // Chromium 계열은 이 힌트가 있어야 웹 콘텐츠 트리를 만든다(값을 바꾸지 않는 힌트).
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    guard let window = AXAccess.element(app, kAXFocusedWindowAttribute)
      ?? AXAccess.elements(app, kAXWindowsAttribute).first
    else { return nil }

    var frame: UiRect?
    if let origin = AXAccess.origin(window), let size = AXAccess.size(window),
       size.width > 0, size.height > 0 {
      frame = UiRect(x: Double(origin.x), y: Double(origin.y),
                     width: Double(size.width), height: Double(size.height))
    }

    let title = AXAccess.string(window, kAXTitleAttribute) ?? AXAccess.appName(of: app) ?? ""
    var budget = UiSnapshotLimits.maxNodes
    var elements: [Int: AXUIElement] = [:]
    var nextToken = 0
    let root = convert(window, depth: 0, budget: &budget, deadline: deadline,
                       elements: &elements, nextToken: &nextToken)
      ?? UiNode(role: "AXWindow", name: title)
    let snapshot = UiSnapshot.build(appName: target.name, windowTitle: title,
                                    root: root, bundleID: target.bundleID)
    return (snapshot, elements, frame)
  }

  /// AX 요소 1개 → `UiNode`. 예산·깊이·시간을 넘으면 nil(자식만 버리고 부모는 남는다).
  private static func convert(_ el: AXUIElement, depth: Int,
                              budget: inout Int, deadline: Date,
                              elements: inout [Int: AXUIElement],
                              nextToken: inout Int) -> UiNode? {
    guard budget > 0, depth <= UiSnapshotLimits.maxDepth, Date() < deadline else { return nil }
    budget -= 1

    let role = AXAccess.string(el, kAXRoleAttribute) ?? ""
    // 메뉴바는 앱 전체 메뉴라 창 내용과 무관하다 — 통째로 건너뛴다(창 텍스트 읽기와 같은 규칙).
    if role == "AXMenuBar" || role == "AXMenu" { return nil }

    let token = nextToken
    nextToken += 1
    elements[token] = el

    let subrole = AXAccess.string(el, kAXSubroleAttribute) ?? ""
    let secure = subrole == "AXSecureTextField"
    let value = secure ? nil : AXAccess.string(el, kAXValueAttribute)
    let title = AXAccess.string(el, kAXTitleAttribute)
    let description = AXAccess.string(el, kAXDescriptionAttribute)
    let placeholder = AXAccess.string(el, kAXPlaceholderValueAttribute)

    // 글자 요소는 값이 곧 이름이다(화면에 보이는 글자). 입력 요소는 라벨(제목·설명·플레이스홀더)을 쓴다.
    let textRoles: Set<String> = ["AXStaticText", "AXHeading", "AXLink", "AXCell"]
    let name: String
    if textRoles.contains(role) {
      name = [value, title, description].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    } else {
      name = [title, description, placeholder].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    var frame: UiRect?
    if let origin = AXAccess.origin(el), let size = AXAccess.size(el),
       size.width > 0, size.height > 0 {
      frame = UiRect(x: Double(origin.x), y: Double(origin.y),
                     width: Double(size.width), height: Double(size.height))
    }

    let children = AXAccess.children(el).compactMap {
      convert($0, depth: depth + 1, budget: &budget, deadline: deadline,
              elements: &elements, nextToken: &nextToken)
    }

    return UiNode(role: role,
                  name: name,
                  hasValue: !(value ?? "").isEmpty && !textRoles.contains(role),
                  isSecure: secure,
                  isEnabled: AXAccess.bool(el, kAXEnabledAttribute as String) ?? true,
                  frame: frame,
                  children: children,
                  token: token)
  }

  private static func focused(pid: pid_t) -> UiActionTarget? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, UiSnapshotLimits.messagingTimeout)
    guard let el = AXAccess.element(app, kAXFocusedUIElementAttribute) else { return nil }
    let role = AXAccess.string(el, kAXRoleAttribute) ?? ""
    let subrole = AXAccess.string(el, kAXSubroleAttribute) ?? ""
    let title = AXAccess.string(el, kAXTitleAttribute)
    let description = AXAccess.string(el, kAXDescriptionAttribute)
    let placeholder = AXAccess.string(el, kAXPlaceholderValueAttribute)
    let name = [title, description, placeholder].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    return UiActionTarget(role: UiSnapshot.displayRole(role), name: name,
                          isSecure: subrole == "AXSecureTextField")
  }

  private static func window(pid: pid_t, title: String) -> UiWindowRef? {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, UiSnapshotLimits.messagingTimeout)
    let windows = AXAccess.elements(app, kAXWindowsAttribute)
    let wanted = title.lowercased()
    let match = windows.first { (AXAccess.string($0, kAXTitleAttribute) ?? "").lowercased() == wanted }
      ?? windows.first { (AXAccess.string($0, kAXTitleAttribute) ?? "").lowercased().contains(wanted) }
    guard let match else { return nil }
    let name = AXAccess.string(match, kAXTitleAttribute) ?? title
    return UiWindowRef(target: UiActionTarget(role: "window", name: name, isSecure: false),
                       element: match)
  }
}
