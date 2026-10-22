import AppKit
import ScreenCaptureKit
import CoreGraphics

// [INFO] [FEATURE] 캡처 — 전체 화면 · 윈도우 · 드래그 선택 (PLAN_v0.13)
// - ⌘⇧3/4는 시스템 전용이라 앱이 가로챌 수 없다 → 자체 단축키(⌥⇧3/4)에서 이 서비스를 호출한다.
// - 화면 이미지를 한 번 떠서(SCScreenshotManager) 오버레이에 깔고, 선택 영역은 그 이미지에서 잘라낸다.
//   (오버레이가 캡처에 찍히는 문제를 피하고, 선택 영역·크기 표시를 즉시 그릴 수 있다)

enum CaptureError: Error {
  case noPermission
  case noDisplay
  case captureFailed
  case windowGone
  case cancelled

  var message: String {
    switch self {
    case .noPermission: return L("화면 기록 권한이 필요합니다 — 시스템 설정 › 개인정보 보호 및 보안 › 화면 기록에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요.")
    case .noDisplay: return L("캡처할 디스플레이를 찾지 못했습니다.")
    case .captureFailed: return L("화면을 캡처하지 못했습니다.")
    case .windowGone: return L("그 창을 캡처하지 못했습니다 — 창이 닫혔거나 최소화되었는지 확인하세요.")
    case .cancelled: return L("캡처를 취소했습니다.")
    }
  }
}

/// 윈도우 캡처 대상 — `CGWindowList`의 창 번호·사각형을 **AppKit 전역 좌표(좌하단 원점)** 로 옮겨 둔다.
/// (Quartz 좌표를 그대로 그리면 엉뚱한 창을 잡는다 — `CaptureGeometry`)
struct CaptureWindowTarget: Equatable {
  let id: CGWindowID
  /// AppKit 전역 좌표(좌하단 원점, y 위)
  let rect: CGRect
  let appName: String?
  let title: String?

  /// 오버레이 뷰 안 좌표(좌하단 원점)로 변환
  func localRect(in screen: CGRect) -> CGRect {
    CGRect(x: rect.minX - screen.minX, y: rect.minY - screen.minY,
           width: rect.width, height: rect.height)
  }
}

@MainActor
final class CaptureService {
  static let shared = CaptureService()

  private var overlay: CaptureOverlayController?
  private var busy = false

  // MARK: - 권한

  static func hasPermission() -> Bool { CGPreflightScreenCaptureAccess() }

  /// 권한이 없으면 시스템 안내를 띄운다(첫 요청은 항상 false — 허용 후 앱 재실행 필요).
  @discardableResult
  static func ensureScreenPermission(silent: Bool = false) -> Bool {
    if CGPreflightScreenCaptureAccess() { return true }
    if silent { return false }
    // 권한 대화상자가 대화 창(항상 위) 뒤로 숨지 않게 잠시 창을 내린다
    NotificationCenter.default.post(name: .quickTalkSystemPromptBegin, object: nil)
    let granted = CGRequestScreenCaptureAccess()
    NotificationCenter.default.post(name: .quickTalkSystemPromptEnd, object: nil)
    NSLog("[QuickShelf] 화면 기록 권한 요청 granted=%@ (허용 후 앱 재실행 필요)",
          granted ? "Y" : "N")
    return granted
  }

  /// 시스템 설정 › 개인정보 보호 및 보안 › 화면 기록을 연다(패널이 가리지 않게 잠시 내린다).
  static func openScreenRecordingSettings() {
    NotificationCenter.default.post(name: .quickTalkSystemPromptBegin, object: nil)
    let urls = [
      "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
      "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
    ]
    for u in urls {
      if let url = URL(string: u), NSWorkspace.shared.open(url) { return }
    }
    NotificationCenter.default.post(name: .quickTalkSystemPromptEnd, object: nil)
    NSLog("[WARN] E-MAC-CAP-0005 화면 기록 설정 링크 열기 실패")
  }

  // MARK: - 공개 API

  func captureFullScreen(into store: UIStore) {
    guard ready(into: store) else { return }
    busy = true
    Task { @MainActor in
      defer { self.busy = false }
      let screen = Self.screenUnderMouse()
      let wasOpen = ShelfController.shared.hideForCapture()
      await Self.settle()                       // 창이 실제로 내려간 뒤에 찍는다
      do {
        let image = try await Self.snapshot(screen: screen)
        ShelfController.shared.restoreAfterCapture(wasOpen: wasOpen)
        self.finish(image, source: .fullScreen, into: store)
      } catch {
        ShelfController.shared.restoreAfterCapture(wasOpen: wasOpen)
        self.fail(error, into: store)
      }
    }
  }

  func captureRegion(into store: UIStore) {
    startOverlay(mode: .region, into: store)
  }

  func captureWindow(into store: UIStore) {
    startOverlay(mode: .window, into: store)
  }

  // MARK: - 내부

  private func ready(into store: UIStore) -> Bool {
    guard !busy, overlay == nil else { return false }
    guard Self.ensureScreenPermission() else {
      store.showShelfNotice(CaptureError.noPermission.message, action: .screenRecording)
      NSLog("[ERROR] E-MAC-CAP-0001 화면 기록 권한 없음")
      return false
    }
    return true
  }

  private func startOverlay(mode: CaptureOverlayController.Mode, into store: UIStore) {
    guard ready(into: store) else { return }
    busy = true
    let screen = Self.screenUnderMouse()
    let wasOpen = ShelfController.shared.hideForCapture()
    Task { @MainActor in
      await Self.settle()
      do {
        let image = try await Self.snapshot(screen: screen)
        self.busy = false
        // 창 목록은 **모드와 무관하게 항상** 모은다.
        // (드래그 모드에서 Space로 윈도우 모드로 바꿀 때도 목록이 필요했다 —
        //  모드에 따라 목록을 비우면 라벨만 "윈도우"로 바뀌고 어떤 창도 잡히지 않았다)
        let controller = CaptureOverlayController(mode: mode, screen: screen, frozen: image,
                                                  windows: Self.windowTargets(on: screen))
        // 윈도우 모드로 전환하는 시점에 창 목록을 다시 읽는다(그사이 새로 열린 창도 잡히도록)
        controller.onRefreshWindows = { Self.windowTargets(on: screen) }
        // CaptureService는 앱 수명 동안 유지되는 싱글턴이라 강한 캡처가 안전하다(순환은 overlay=nil로 끊긴다)
        controller.onFinish = { cropped, source in
          self.overlay = nil
          ShelfController.shared.restoreAfterCapture(wasOpen: wasOpen)
          self.finish(cropped, source: source, into: store)
        }
        // 윈도우 캡처 — 화면을 잘라 쓰지 않고 **그 창의 표면만** 다시 캡처한다(겹친 창 제외)
        controller.onPickWindow = { target in
          self.overlay = nil
          Task { @MainActor in
            let wasOpenInner = wasOpen
            do {
              let image = try await Self.snapshot(window: target, screen: screen)
              ShelfController.shared.restoreAfterCapture(wasOpen: wasOpenInner)
              self.finish(image, source: .window, into: store)
            } catch {
              ShelfController.shared.restoreAfterCapture(wasOpen: wasOpenInner)
              self.fail(error, into: store)
            }
          }
        }
        controller.onCancel = {
          self.overlay = nil
          ShelfController.shared.restoreAfterCapture(wasOpen: wasOpen)
          NSLog("[QuickShelf] 캡처 취소")
        }
        self.overlay = controller
        controller.begin()
      } catch {
        self.busy = false
        ShelfController.shared.restoreAfterCapture(wasOpen: wasOpen)
        self.fail(error, into: store)
      }
    }
  }

  private func finish(_ image: CGImage, source: ShelfCapture.Source, into store: UIStore) {
    let data = Self.pngData(image)
    guard let capture = store.addCapture(png: data, pixelWidth: image.width,
                                         pixelHeight: image.height, source: source) else {
      store.showShelfNotice(L("캡처를 저장하지 못했습니다."))
      return
    }
    // 기본: QuickShelf에 추가. 클립보드에도 복사해 두면 다른 앱에서 바로 붙여넣을 수 있다.
    if store.settings.shelfCopyCaptureToClipboard, let ns = NSImage(data: data) {
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.writeObjects([ns])
    }
    NSLog("[QuickShelf] 캡처 완료 source=%@ %dx%d → %@", source.rawValue,
          capture.width, capture.height, capture.url.lastPathComponent)
    // 결과가 어디에 들어갔는지 바로 보이게 허브를 연다(대화창이 떠 있으면 창 안 도킹, 아니면 화면 가장자리 패널)
    ShelfController.shared.openWhereUserIs()
  }

  private func fail(_ error: Error, into store: UIStore) {
    store.showShelfNotice((error as? CaptureError)?.message ?? Lf("캡처 실패: %@", error.localizedDescription))
    NSLog("[ERROR] E-MAC-CAP-0002 캡처 실패 — %@", String(describing: error))
  }

  // MARK: - 화면

  static func screenUnderMouse() -> NSScreen {
    let p = NSEvent.mouseLocation
    return NSScreen.screens.first { $0.frame.contains(p) } ?? NSScreen.main ?? NSScreen.screens[0]
  }

  static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
    (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }

  /// 화면 1장을 픽셀 그대로 캡처한다(오버레이를 띄우기 전에 호출).
  static func snapshot(screen: NSScreen) async throws -> CGImage {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw CaptureError.noPermission
    }
    guard let displayID = displayID(of: screen),
          let display = content.displays.first(where: { $0.displayID == displayID }) else {
      throw CaptureError.noDisplay
    }
    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.width = display.width
    config.height = display.height
    config.showsCursor = false
    if #available(macOS 14.0, *) { config.captureResolution = .best }
    do {
      return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
      throw CaptureError.captureFailed
    }
  }

  /// 윈도우 1개만 캡처한다 — **그 창의 표면**만 합성하므로 위에 겹친 창·바탕화면이 찍히지 않는다.
  /// (화면을 떠서 사각형만 자르는 방식은 겹친 창까지 포함된다 — 2026-10-20 실측 버그)
  static func snapshot(window target: CaptureWindowTarget, screen: NSScreen) async throws -> CGImage {
    let content: SCShareableContent
    do {
      content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    } catch {
      throw CaptureError.noPermission
    }
    guard let win = content.windows.first(where: { $0.windowID == target.id }) else {
      throw CaptureError.windowGone
    }
    // 창이 놓인 화면의 배율로 픽셀 크기를 맞춘다(보조 모니터 배율이 다를 수 있다)
    let host = NSScreen.screens.first { $0.frame.intersects(target.rect) } ?? screen
    let scale = host.backingScaleFactor
    let filter = SCContentFilter(desktopIndependentWindow: win)
    let config = SCStreamConfiguration()
    config.width = max(1, Int((win.frame.width * scale).rounded()))
    config.height = max(1, Int((win.frame.height * scale).rounded()))
    config.showsCursor = false
    config.ignoreShadowsSingleWindow = true       // 창 그림자는 내용이 아니다
    if #available(macOS 14.0, *) { config.captureResolution = .best }
    do {
      return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    } catch {
      throw CaptureError.captureFailed
    }
  }

  /// 화면에 보이는 일반 윈도우(앞→뒤 순서). 우리 앱·시스템 UI는 제외.
  /// 사각형은 **여기서 한 번만** AppKit 전역 좌표로 변환한다(`CGWindowList`는 좌상단 원점).
  static func windowTargets(on screen: NSScreen) -> [CaptureWindowTarget] {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                kCGNullWindowID) as? [[String: Any]] else { return [] }
    let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.maxY
    var targets: [CaptureWindowTarget] = []
    let myPID = ProcessInfo.processInfo.processIdentifier
    for info in list {
      guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
      if let pid = info[kCGWindowOwnerPID as String] as? Int32, pid == myPID { continue }
      guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
            let quartz = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
      guard quartz.width >= 80, quartz.height >= 60 else { continue }
      let rect = CaptureGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: primaryHeight)
      guard rect.intersects(screen.frame) else { continue }
      guard let number = info[kCGWindowNumber as String] as? NSNumber else { continue }
      targets.append(CaptureWindowTarget(id: CGWindowID(truncating: number),
                                         rect: rect,
                                         appName: info[kCGWindowOwnerName as String] as? String,
                                         title: info[kCGWindowName as String] as? String))
    }
    return targets
  }

  /// 창이 실제로 내려간 뒤에 캡처하도록 잠깐 기다린다(우리 UI가 찍히는 것 방지)
  static func settle() async {
    try? await Task.sleep(nanoseconds: 160_000_000)
  }

  static func pngData(_ image: CGImage) -> Data {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:]) ?? Data()
  }

  // MARK: - QA

  /// QA 전용 — 오버레이 상태 확인(드래그 모드 → Space → 윈도우 모드 전환)
  func overlaySelfTest() -> (mode: String, windows: Int, highlight: Bool) {
    guard let overlay else { return ("none", 0, false) }
    return overlay.simulateSpaceForQA()
  }
}
