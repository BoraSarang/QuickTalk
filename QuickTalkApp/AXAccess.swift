import ApplicationServices
import CoreGraphics
import Foundation

// [REFACTOR] 접근성(AX) 호출 공통 헬퍼 (2026-10-29)
//
// 두 곳이 같은 규칙을 쓴다.
//   · `AXWindowReader` — 창 텍스트 읽기(창 연결, v0.21)
//   · `AccessibilityService` — 화면 요소 스냅샷(컴퓨터 제어 Phase 1, PLAN_v0.25)
// 규칙(타입 확인·nil 처리)이 갈라지면 한쪽만 조용히 빈 결과를 돌려주게 되므로 한 곳에 모은다.

enum AXAccess {
  /// AX 속성 하나 — 타입이 다르면 nil.
  static func element(_ el: AXUIElement, _ attr: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (value as! AXUIElement)
  }

  /// AX 요소 배열 속성 — 요소가 아닌 항목은 버린다.
  static func elements(_ el: AXUIElement, _ attr: String) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
          let array = value as? NSArray else { return [] }
    return array.compactMap { any -> AXUIElement? in
      guard CFGetTypeID(any as CFTypeRef) == AXUIElementGetTypeID() else { return nil }
      return (any as! AXUIElement)
    }
  }

  static func children(_ el: AXUIElement) -> [AXUIElement] {
    elements(el, kAXChildrenAttribute)
  }

  /// 문자열 속성 — 숫자도 문자열로 받는다(AX는 값을 NSNumber로 주기도 한다).
  static func string(_ el: AXUIElement, _ attr: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
          let value else { return nil }
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return nil
  }

  /// 참/거짓 속성 — 없으면 nil(호출부가 기본값을 정한다).
  static func bool(_ el: AXUIElement, _ attr: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success,
          let n = value as? NSNumber else { return nil }
    return n.boolValue
  }

  static func size(_ el: AXUIElement) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXSizeAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    guard AXValueGetValue(value as! AXValue, .cgSize, &size) else { return nil }
    return size
  }

  static func origin(_ el: AXUIElement) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(el, kAXPositionAttribute as CFString, &value) == .success,
          let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    guard AXValueGetValue(value as! AXValue, .cgPoint, &point) else { return nil }
    return point
  }

  static func appName(of app: AXUIElement) -> String? {
    string(app, kAXTitleAttribute)
  }
}
