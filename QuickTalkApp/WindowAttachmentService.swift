import AppKit
import ApplicationServices
import CoreGraphics
import ScreenCaptureKit

// [INFO] [FEATURE] 창 연결 — 창 하나의 **텍스트(접근성)** 와 **스크린샷**을 이번 질문의 참고 자료로 첨부한다 (P0-1)
//
// Meta AI for macOS의 "창 연결"과 목적은 같지만 **읽기 전용**이다:
//   - 창 조작(클릭·입력·스크롤)은 넣지 않는다. 모델에도 "다시 읽을 수 없는 단일 스냅샷"이라고 알린다.
//   - 첨부는 기존 첨부 파이프라인(텍스트 파일 + PNG)을 그대로 탄다 → 프로바이더 3종 모두 동작한다.
//   - 서버 업로드 없음. 파일은 `~/Library/Application Support/QuickTalk/window/` 에만 잠깐 남는다.
//
// 권한 2종:
//   - 화면 기록(Screen Recording): 스크린샷. 없으면 텍스트만 보낸다.
//   - 손쉬운 사용(Accessibility): 화면 텍스트. 없으면 스크린샷만 보낸다.
//   둘 다 없으면 아무것도 보낼 수 없으므로 시트에서 권한 안내를 먼저 보여준다.

enum WindowAttachError: Error {
  case noPermission
  case windowGone
  case noContent
  case captureFailed
  case saveFailed

  var message: String {
    switch self {
    case .noPermission:
      return L("화면 기록 또는 손쉬운 사용 권한이 필요합니다 — 시스템 설정 › 개인정보 보호 및 보안에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요.")
    case .windowGone:
      return L("그 창을 읽지 못했습니다 — 창이 닫혔거나 최소화되었는지 확인하세요.")
    case .noContent:
      return L("이 창에서 읽을 수 있는 내용을 찾지 못했습니다 — 다른 창을 골라 보세요.")
    case .captureFailed:
      return L("창 스크린샷을 찍지 못했습니다.")
    case .saveFailed:
      return L("창 내용을 임시 파일로 저장하지 못했습니다.")
    }
  }
}

/// 창 1개를 첨부한 결과 — 실제로 첨부 목록에 들어가는 파일 2개.
struct WindowAttachment {
  let snapshot: WindowSnapshot
  let textURL: URL
  let imageURL: URL?
}

@MainActor
final class WindowAttachmentService {
  static let shared = WindowAttachmentService()
  private init() {}

  // MARK: - 권한

  static var hasScreenPermission: Bool { CGPreflightScreenCaptureAccess() }
  static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

  /// 손쉬운 사용 권한 요청 — 시스템 대화상자가 대화 창(항상 위) 뒤로 숨지 않게 잠시 내린다.
  @discardableResult
  static func requestAccessibility() -> Bool {
    NotificationCenter.default.post(name: .quickTalkSystemPromptBegin, object: nil)
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    NotificationCenter.default.post(name: .quickTalkSystemPromptEnd, object: nil)
    NSLog("[WindowAttach] 손쉬운 사용 권한 요청 trusted=%@ (허용 후 앱 재실행 필요)", trusted ? "Y" : "N")
    return trusted
  }

  static func openAccessibilitySettings() {
    NotificationCenter.default.post(name: .quickTalkSystemPromptBegin, object: nil)
    let urls = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
    ]
    for u in urls {
      if let url = URL(string: u), NSWorkspace.shared.open(url) { return }
    }
    NotificationCenter.default.post(name: .quickTalkSystemPromptEnd, object: nil)
    NSLog("[WARN] E-MAC-AX-0001 손쉬운 사용 설정 링크 열기 실패")
  }

  // MARK: - 창 목록

  /// 화면에 보이는 일반 창(앞→뒤). 시스템 UI·우리 앱·너무 작은 창은 뺀다.
  static func listWindows() async throws -> [WindowTarget] {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw WindowAttachError.noPermission
    }
    let order = zOrder()
    let myPID = ProcessInfo.processInfo.processIdentifier
    var targets: [WindowTarget] = []
    for win in content.windows {
      guard win.windowLayer == 0, win.isOnScreen else { continue }
      guard let app = win.owningApplication else { continue }
      guard app.processID != myPID else { continue }
      let bundleID = app.bundleIdentifier
      let appName = app.applicationName
      let title = win.title ?? ""
      guard WindowContextLimits.accepts(bundleID: bundleID, appName: appName,
                                        title: title,
                                        width: win.frame.width, height: win.frame.height)
      else { continue }
      targets.append(WindowTarget(id: win.windowID, pid: app.processID,
                                  bundleID: bundleID, appName: appName, title: title,
                                  width: win.frame.width, height: win.frame.height))
    }
    // CGWindowList 순서(앞→뒤)로 정렬 — 목록이 화면의 겹침 순서와 같아진다.
    targets.sort { (order[$0.id] ?? .max) < (order[$1.id] ?? .max) }
    return targets
  }

  /// `CGWindowList`의 앞→뒤 순서(창 번호 → 순번).
  private static func zOrder() -> [CGWindowID: Int] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return [:] }
    var order: [CGWindowID: Int] = [:]
    for (i, info) in list.enumerated() {
      guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
      order[CGWindowID(truncating: number)] = i
    }
    return order
  }

  // MARK: - 미리보기 (텍스트만)

  /// 시트 미리보기 — 첨부 전에 "무엇을 읽는지" 보여준다. 스크린샷은 찍지 않는다(가볍게).
  func preview(_ target: WindowTarget) async -> (text: String, truncated: Bool) {
    guard Self.hasAccessibilityPermission else { return ("", false) }
    let pid = target.pid
    let title = target.title
    let width = target.width
    let height = target.height
    let raw = await Task.detached(priority: .userInitiated) {
      AXWindowReader.readText(pid: pid, windowTitle: title, width: width, height: height)
    }.value
    let clean = WindowContextPrompt.sanitize(raw)
    let (text, truncated) = WindowContextPrompt.truncate(clean)
    return (text, truncated)
  }

  // MARK: - 첨부

  /// 창 1개를 읽어 첨부 목록에 넣는다. 권한이 하나라도 있으면 **가능한 것만** 보낸다.
  @discardableResult
  func attach(_ target: WindowTarget, into store: UIStore) async throws -> WindowAttachment {
    let canText = Self.hasAccessibilityPermission
    let canShot = Self.hasScreenPermission
    guard canText || canShot else { throw WindowAttachError.noPermission }

    var text = ""
    var selected = ""
    if canText {
      let pid = target.pid
      let title = target.title
      let width = target.width
      let height = target.height
      let read = await Task.detached(priority: .userInitiated) {
        AXWindowReader.read(pid: pid, windowTitle: title, width: width, height: height)
      }.value
      text = WindowContextPrompt.sanitize(read.text)
      selected = WindowContextPrompt.sanitize(read.selected)
    }
    let (clipped, truncated) = WindowContextPrompt.truncate(text)

    var image: CGImage?
    if canShot {
      // 스크린샷 실패는 텍스트를 버릴 이유가 아니다 — 텍스트가 있으면 그대로 보낸다.
      do {
        image = try await capture(target)
      } catch {
        NSLog("[WARN] E-MAC-WIN-0001 창 캡처 실패 — 텍스트만 첨부: %@", String(describing: error))
      }
    }
    if clipped.isEmpty, selected.isEmpty, image == nil { throw WindowAttachError.noContent }

    let snapshot = WindowSnapshot(target: target, text: clipped, selectedText: selected,
                                  truncated: truncated, hasScreenshot: image != nil)
    let saved = try save(snapshot: snapshot, image: image)

    let textAttachment = PendingAttachment(name: saved.textURL.lastPathComponent,
                                           url: saved.textURL, kind: .file)
    store.attached.append(textAttachment)
    if let imageURL = saved.imageURL {
      store.attached.append(PendingAttachment(name: imageURL.lastPathComponent,
                                              url: imageURL, kind: .image))
    }
    NSLog("[WindowAttach] 첨부 완료 app=%@ title=%@ text=%d자 shot=%@",
          target.appName, target.displayTitle, clipped.count, image == nil ? "N" : "Y")
    return saved
  }

  // MARK: - 스크린샷

  private func capture(_ target: WindowTarget) async throws -> CGImage {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw WindowAttachError.noPermission
    }
    guard let win = content.windows.first(where: { $0.windowID == target.id }) else {
      throw WindowAttachError.windowGone
    }
    var image = try await Self.shoot(win)
    // 창이 아직 그려지기 전이면 단색으로 찍힌다 — 한 번만 다시 찍는다.
    if Self.looksBlank(image) {
      try? await Task.sleep(nanoseconds: 150_000_000)
      image = try await Self.shoot(win)
    }
    return image
  }

  // MARK: - screenshot 도구 (v0.21)

  /// 모델의 `screenshot` 도구 — 앞 창 또는 전체 화면 1장을 찍어 **파일 경로**로 돌려준다.
  /// 다음 스텝에서 이 파일이 이미지 첨부로 모델에 전달된다.
  static func captureForTool(target: String) async throws -> URL {
    guard hasScreenPermission else { throw WindowAttachError.noPermission }
    let image: CGImage
    if target == "screen" {
      image = try await captureMainDisplay()
    } else {
      guard let front = try await listWindows().first else { throw WindowAttachError.windowGone }
      image = try await captureWindow(front)
    }
    return try saveForTool(image, target: target)
  }

  /// 창 하나를 캡처(정적 함수 — 도구 경로에서 인스턴스 없이 쓴다).
  private static func captureWindow(_ target: WindowTarget) async throws -> CGImage {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw WindowAttachError.noPermission
    }
    guard let win = content.windows.first(where: { $0.windowID == target.id }) else {
      throw WindowAttachError.windowGone
    }
    var image = try await shoot(win)
    if looksBlank(image) {
      try? await Task.sleep(nanoseconds: 150_000_000)
      image = try await shoot(win)
    }
    return image
  }

  /// 전체 화면(주 디스플레이) 1장.
  private static func captureMainDisplay() async throws -> CGImage {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw WindowAttachError.noPermission
    }
    guard let display = content.displays.first else { throw WindowAttachError.captureFailed }
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    let rawW = CGFloat(display.width) * scale
    let rawH = CGFloat(display.height) * scale
    let maxSide: CGFloat = 2_048
    let shrink = min(1, maxSide / max(rawW, rawH, 1))

    let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
    let config = SCStreamConfiguration()
    config.width = max(1, Int((rawW * shrink).rounded()))
    config.height = max(1, Int((rawH * shrink).rounded()))
    config.showsCursor = false
    if #available(macOS 14.0, *) { config.captureResolution = .best }
    do {
      return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
      throw WindowAttachError.captureFailed
    }
  }

  /// 도구용 스크린샷 저장 — 파일 이름에 종류·시각을 넣어 알아보게 한다.
  private static func saveForTool(_ image: CGImage, target: String) throws -> URL {
    guard let dir = windowDir else { throw WindowAttachError.saveFailed }
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyyMMdd-HHmmss"
    let name = "screenshot-\(target == "screen" ? "screen" : "window")-\(f.string(from: Date())).png"
    let url = uniqueURL(in: dir, fileName: name)
    do {
      try CaptureService.pngData(image).write(to: url)
    } catch {
      throw WindowAttachError.saveFailed
    }
    pruneOldFiles(in: dir)
    return url
  }

  private static func shoot(_ win: SCWindow) async throws -> CGImage {
    // 배율은 메인 화면 기준 — 멀티 모니터에서 배율이 달라도 해상도만 달라질 뿐 내용은 같다.
    let scale = NSScreen.main?.backingScaleFactor ?? 2
    // 모델이 읽기 좋은 선에서 상한을 둔다(원본 그대로면 수 MB PNG가 된다).
    let maxSide: CGFloat = 2_048
    let rawW = win.frame.width * scale
    let rawH = win.frame.height * scale
    let shrink = min(1, maxSide / max(rawW, rawH, 1))

    let filter = SCContentFilter(desktopIndependentWindow: win)
    let config = SCStreamConfiguration()
    config.width = max(1, Int((rawW * shrink).rounded()))
    config.height = max(1, Int((rawH * shrink).rounded()))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true
    if #available(macOS 14.0, *) { config.captureResolution = .best }
    do {
      return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
      throw WindowAttachError.captureFailed
    }
  }

  /// 거의 단색인가 — 창이 아직 안 그려졌을 때의 빈 캡처를 걸러낸다.
  static func looksBlank(_ image: CGImage) -> Bool {
    let side = 8
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
      guard let ctx = CGContext(data: buf.baseAddress, width: side, height: side,
                                bitsPerComponent: 8, bytesPerRow: side * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
      else { return false }
      ctx.interpolationQuality = .none
      ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
      return true
    }
    guard ok else { return false }
    var first: (UInt8, UInt8, UInt8)?
    for i in stride(from: 0, to: pixels.count, by: 4) {
      let rgb = (pixels[i], pixels[i + 1], pixels[i + 2])
      if let f = first {
        if abs(Int(f.0) - Int(rgb.0)) > 6
            || abs(Int(f.1) - Int(rgb.1)) > 6
            || abs(Int(f.2) - Int(rgb.2)) > 6 { return false }
      } else {
        first = rgb
      }
    }
    return true
  }

  // MARK: - 파일

  /// 창 연결 임시 폴더
  static var windowDir: URL? {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                              in: .userDomainMask).first else { return nil }
    let dir = base.appendingPathComponent("QuickTalk/window", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
  }

  private func save(snapshot: WindowSnapshot, image: CGImage?) throws -> WindowAttachment {
    guard let dir = Self.windowDir else { throw WindowAttachError.saveFailed }
    let textURL = Self.uniqueURL(in: dir, fileName: WindowContextPrompt.textFileName(snapshot.target))
    let body = WindowContextPrompt.fileBody(snapshot)
    do {
      try body.write(to: textURL, atomically: true, encoding: .utf8)
    } catch {
      throw WindowAttachError.saveFailed
    }
    var imageURL: URL?
    if let image {
      let url = Self.uniqueURL(in: dir, fileName: WindowContextPrompt.imageFileName(snapshot.target))
      do {
        try CaptureService.pngData(image).write(to: url)
        imageURL = url
      } catch {
        NSLog("[ERROR] E-MAC-WIN-0002 창 스크린샷 저장 실패")
      }
    }
    Self.pruneOldFiles(in: dir)
    return WindowAttachment(snapshot: snapshot, textURL: textURL, imageURL: imageURL)
  }

  /// 같은 이름이 있으면 `이름-2.txt` 처럼 번호를 붙인다(칩에 보이는 이름은 그대로 유지).
  private static func uniqueURL(in dir: URL, fileName: String) -> URL {
    let base = (fileName as NSString).deletingPathExtension
    let ext = (fileName as NSString).pathExtension
    var url = dir.appendingPathComponent(fileName)
    var n = 2
    while FileManager.default.fileExists(atPath: url.path) {
      url = dir.appendingPathComponent("\(base)-\(n).\(ext)")
      n += 1
    }
    return url
  }

  /// 오래된 창 연결 파일 정리 — 첨부는 한 번 쓰고 끝나므로 무한정 쌓이면 안 된다.
  private static func pruneOldFiles(in dir: URL, keepDays: Int = 7) {
    let cutoff = Date().addingTimeInterval(-Double(keepDays) * 86_400)
    guard let items = try? FileManager.default.contentsOfDirectory(
      at: dir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
    for url in items {
      let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
        .contentModificationDate ?? .distantPast
      if date < cutoff { try? FileManager.default.removeItem(at: url) }
    }
  }
}

// MARK: - 접근성 텍스트 읽기

/// AX 트리를 훑어 **화면에 보이는 글자**를 모은다.
///
/// - 읽기 전용: 값을 읽기만 하고, 창 상태를 바꾸는 속성은 쓰지 않는다.
///   단 Chromium 계열 앱이 웹 콘텐츠 트리를 노출하도록 `AXManualAccessibility` 힌트만 켠다.
/// - 앱이 응답하지 않아도 UI가 멈추지 않게 **메인 스레드 밖**에서 돌린다(호출부가 Task.detached).
/// - 노드·깊이 상한으로 거대한 창에서도 오래 붙잡지 않는다.
enum AXWindowReader {

  /// 본문으로 볼 역할 — 컨테이너(그룹·스크롤 영역)는 자식만 따라간다.
  private static let contentRoles: Set<String> = [
    "AXStaticText", "AXTextField", "AXTextArea", "AXButton", "AXCheckBox",
    "AXRadioButton", "AXPopUpButton", "AXComboBox", "AXLink", "AXHeading",
    "AXCell", "AXTab", "AXSlider", "AXProgressIndicator", "AXDisclosureTriangle",
    "AXImage", "AXValueIndicator", "AXDateField", "AXTimeField"
  ]

  /// 메뉴바는 앱 전체 메뉴라 창 내용과 무관하다 — 통째로 건너뛴다.
  private static let skippedRoles: Set<String> = ["AXMenuBar", "AXMenu"]

  /// 본문 텍스트만
  static func readText(pid: pid_t, windowTitle: String,
                       width: CGFloat = 0, height: CGFloat = 0) -> String {
    read(pid: pid, windowTitle: windowTitle, width: width, height: height).text
  }

  /// 본문 + 사용자가 선택해 둔 텍스트
  static func read(pid: pid_t, windowTitle: String,
                   width: CGFloat = 0, height: CGFloat = 0) -> (text: String, selected: String) {
    let app = AXUIElementCreateApplication(pid)
    // 앱이 멈춰 있어도 1.5초 안에 포기한다(AX 기본 타임아웃은 수 초).
    AXUIElementSetMessagingTimeout(app, 1.5)
    // Chromium 계열은 이 힌트가 있어야 웹 콘텐츠 트리를 만든다(값을 바꾸지 않는 힌트).
    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

    guard let window = chooseWindow(in: app, title: windowTitle,
                                    width: width, height: height) else { return ("", "") }
    var lines: [String] = []
    var seen = Set<String>()
    var budget = WindowContextLimits.maxNodes
    let skip: Set<String> = [windowTitle, appName(of: app)].compactMap { $0 }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .reduce(into: Set<String>()) { $0.insert($1) }

    // 앱이 응답하지 않아도 AX 호출이 1.5초씩 쌓일 수 있다 — 전체 6초 예산을 둔다.
    walk(window, depth: 0, budget: &budget, lines: &lines, seen: &seen, skip: skip,
         deadline: Date().addingTimeInterval(6))
    return (lines.joined(separator: "\n"), selectedText(pid: pid, window: window))
  }

  // MARK: - 트리

  private static func walk(_ element: AXUIElement, depth: Int, budget: inout Int,
                           lines: inout [String], seen: inout Set<String>,
                           skip: Set<String>, deadline: Date) {
    guard budget > 0, depth <= WindowContextLimits.maxDepth, Date() < deadline else { return }
    budget -= 1

    let role = string(element, kAXRoleAttribute) ?? ""
    if skippedRoles.contains(role) { return }

    if contentRoles.contains(role) {
      for attr in [kAXValueAttribute, kAXTitleAttribute,
                   kAXDescriptionAttribute, kAXPlaceholderValueAttribute] {
        guard let raw = string(element, attr) else { continue }
        append(raw, into: &lines, seen: &seen, skip: skip)
      }
    }

    for child in children(element) {
      walk(child, depth: depth + 1, budget: &budget,
           lines: &lines, seen: &seen, skip: skip, deadline: deadline)
    }
  }

  private static func append(_ raw: String, into lines: inout [String],
                             seen: inout Set<String>, skip: Set<String>) {
    var s = raw.replacingOccurrences(of: "\r\n", with: "\n")
               .replacingOccurrences(of: "\r", with: "\n")
               .trimmingCharacters(in: .whitespacesAndNewlines)
    // 한 줄짜리 값에 섞인 줄바꿈은 공백으로(표·버튼 제목이 세로로 늘어서지 않게)
    if !s.contains("\n\n") { s = s.replacingOccurrences(of: "\n", with: " ") }
    guard !s.isEmpty, s.count <= 8_000, !skip.contains(s) else { return }
    if seen.insert(s).inserted { lines.append(s) }
  }

  // MARK: - 창 선택

  private static func chooseWindow(in app: AXUIElement, title: String,
                                   width: CGFloat, height: CGFloat) -> AXUIElement? {
    let windows = elements(app, kAXWindowsAttribute)
    guard !windows.isEmpty else { return nil }
    let wanted = title.trimmingCharacters(in: .whitespacesAndNewlines)
    if !wanted.isEmpty {
      if let exact = windows.first(where: { string($0, kAXTitleAttribute) == wanted }) { return exact }
      if let partial = windows.first(where: {
        (string($0, kAXTitleAttribute) ?? "").contains(wanted)
      }) { return partial }
    }
    // 목록을 연 뒤 제목이 바뀌었을 수 있다 — 크기로 찾는다.
    // (엉뚱한 창을 읽어 엉뚱한 답을 만드는 것보다, 텍스트 없이 스크린샷만 보내는 편이 안전하다)
    if width > 0, height > 0,
       let sized = windows.first(where: { window in
         guard let s = size(window) else { return false }
         return abs(s.width - width) <= 8 && abs(s.height - height) <= 8
       }) {
      return sized
    }
    // 창이 하나뿐이면 그 창이 맞다.
    if windows.count == 1 { return windows.first }
    NSLog("[WindowAttach] 제목·크기로 창을 찾지 못했습니다 — 텍스트 없이 스크린샷만: %@", wanted)
    return nil
  }

  private static func size(_ el: AXUIElement) -> CGSize? { AXAccess.size(el) }

  // MARK: - 선택 텍스트

  private static func selectedText(pid: pid_t, window: AXUIElement) -> String {
    // 1) 시스템 전역 포커스 요소가 이 앱 것이면 그 선택 영역을 읽는다(가장 정확).
    let system = AXUIElementCreateSystemWide()
    if let focused = element(system, kAXFocusedUIElementAttribute) {
      var focusedPID: pid_t = 0
      if AXUIElementGetPid(focused, &focusedPID) == .success, focusedPID == pid,
         let text = string(focused, kAXSelectedTextAttribute), !text.isEmpty {
        return text
      }
    }
    // 2) 이 창의 포커스 요소에서 한 번 더.
    if let focused = element(window, kAXFocusedUIElementAttribute),
       let text = string(focused, kAXSelectedTextAttribute), !text.isEmpty {
      return text
    }
    return ""
  }

  // MARK: - AX 유틸

  private static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    AXAccess.element(el, attr)
  }

  private static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    AXAccess.elements(el, attr)
  }

  private static func children(_ el: AXUIElement) -> [AXUIElement] { AXAccess.children(el) }

  private static func string(_ el: AXUIElement, _ attr: String) -> String? {
    AXAccess.string(el, attr)
  }

  private static func appName(of app: AXUIElement) -> String? { AXAccess.appName(of: app) }
}
