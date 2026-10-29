import AppKit
import ApplicationServices
import CoreGraphics

// [FEATURE] 화면 요소 읽기 — 접근성(AX) 트리 (PLAN_v0.25 Phase 1)
//
// **읽기 전용**이다. 클릭·입력·스크롤·포커스 이동을 하지 않는다(Phase 2에서 별도 서비스로 넣는다).
// 순수 계산(평탄화·경로·상한)은 `Sources/QuickTalkCore/UiSnapshot.swift` 가 맡고,
// 이 파일은 **AX 호출**만 한다. 그래야 권한 없이도 계약을 단위 테스트로 고정할 수 있다.
//
// 안전 규칙
//   · 메인 스레드에서 부르지 않는다(호출부가 Task.detached) — 앱이 멈춰도 QuickTalk는 멈추지 않는다.
//   · 창 하나만, 노드·깊이·시간 상한 안에서만 읽는다.
//   · `AXManualAccessibility` 힌트만 켠다(Chromium 계열이 웹 콘텐츠 트리를 노출하게 하는 **읽기 힌트**).
//   · 값을 바꾸는 속성은 절대 쓰지 않는다.

enum UiAccessError: Error, Equatable {
  case noPermission
  case appNotFound(String)
  case noWindow(String)

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
    }
  }
}

enum AccessibilityService {
  static var hasPermission: Bool { AXIsProcessTrusted() }

  /// 앱 하나의 창 1개를 읽어 평평한 요소 목록으로 돌려준다.
  /// - Parameter app: 앱 이름 또는 번들 ID. 비우면 **QuickTalk를 제외한** 맨 앞 앱.
  static func snapshot(app: String?) async -> Result<UiSnapshot, UiAccessError> {
    guard hasPermission else { return .failure(.noPermission) }

    let query = (app ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    guard let target = resolveApp(query) else { return .failure(.appNotFound(query)) }
    let pid = target.processIdentifier
    let name = target.localizedName
      ?? target.bundleIdentifier
      ?? L("알 수 없는 앱")
    let deadline = Date().addingTimeInterval(UiSnapshotLimits.deadlineSeconds)

    let built: UiSnapshot? = await Task.detached(priority: .userInitiated) {
      read(pid: pid, appName: name, deadline: deadline)
    }.value

    guard let built else { return .failure(.noWindow(name)) }
    return .success(built)
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

  // MARK: - AX 트리 → UiNode (워커 스레드)

  private static func read(pid: pid_t, appName: String, deadline: Date) -> UiSnapshot? {
    let app = AXUIElementCreateApplication(pid)
    // 앱이 멈춰 있어도 1.5초 안에 포기한다(AX 기본 타임아웃은 수 초).
    AXUIElementSetMessagingTimeout(app, UiSnapshotLimits.messagingTimeout)
    // Chromium 계열은 이 힌트가 있어야 웹 콘텐츠 트리를 만든다(값을 바꾸지 않는 힌트).
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    guard let window = AXAccess.element(app, kAXFocusedWindowAttribute)
      ?? AXAccess.elements(app, kAXWindowsAttribute).first
    else { return nil }

    let title = AXAccess.string(window, kAXTitleAttribute) ?? AXAccess.appName(of: app) ?? ""
    var budget = UiSnapshotLimits.maxNodes
    let root = convert(window, depth: 0, budget: &budget, deadline: deadline)
      ?? UiNode(role: "AXWindow", name: title)
    return UiSnapshot.build(appName: appName, windowTitle: title, root: root)
  }

  /// AX 요소 1개 → `UiNode`. 예산·깊이·시간을 넘으면 nil(자식만 버리고 부모는 남는다).
  private static func convert(_ el: AXUIElement, depth: Int,
                              budget: inout Int, deadline: Date) -> UiNode? {
    guard budget > 0, depth <= UiSnapshotLimits.maxDepth, Date() < deadline else { return nil }
    budget -= 1

    let role = AXAccess.string(el, kAXRoleAttribute) ?? ""
    // 메뉴바는 앱 전체 메뉴라 창 내용과 무관하다 — 통째로 건너뛴다(창 텍스트 읽기와 같은 규칙).
    if role == "AXMenuBar" || role == "AXMenu" { return nil }

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
      convert($0, depth: depth + 1, budget: &budget, deadline: deadline)
    }

    return UiNode(role: role,
                  name: name,
                  hasValue: !(value ?? "").isEmpty && !textRoles.contains(role),
                  isSecure: secure,
                  isEnabled: AXAccess.bool(el, kAXEnabledAttribute as String) ?? true,
                  frame: frame,
                  children: children)
  }
}
