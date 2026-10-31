import Foundation

// [FEATURE] 화면 조작 명세 — 모델이 부른 `ui_action` 인자를 **실행 전에** 검증한다
// (PLAN_v0.25 Phase 2 — 컴퓨터 제어).
//
// 원칙
//   · 좌표(x·y)는 받지 않는다 — 검증할 수단이 없다(Phase 3 비목표).
//   · 요소는 `ui_snapshot` 이 준 참조(`r12`)로만 가리킨다.
//   · `purpose` 는 필수다 — 승인 카드에서 사람이 판단할 재료다.
//   · 검증 실패는 **모델에게 이유를 돌려준다**(조용히 실행하지 않는다).

/// 화면 조작의 종류.
public enum UiActionKind: String, CaseIterable, Codable, Sendable {
  case click
  case type
  case key
  case scroll
  case openApp = "open_app"
  case focusWindow = "focus_window"

  public var displayName: String {
    switch self {
    case .click: return L("클릭")
    case .type: return L("텍스트 입력")
    case .key: return L("키 입력")
    case .scroll: return L("스크롤")
    case .openApp: return L("앱 열기")
    case .focusWindow: return L("창 앞으로")
    }
  }
}

public enum UiScrollDirection: String, CaseIterable, Sendable {
  case up
  case down

  public var displayName: String {
    switch self {
    case .up: return L("위로")
    case .down: return L("아래로")
    }
  }
}

/// 인자 검증 오류 — 문구는 모델과 사용자 모두에게 그대로 보여 준다.
public enum UiActionError: Error, Equatable {
  case malformedArguments
  case missingPurpose
  case unknownAction(String)
  case coordinatesNotSupported
  case missingRef
  case invalidRef(String)
  case emptyText
  case textTooLong
  case emptyKeys
  case invalidKey(String)
  case invalidDirection(String)
  case invalidAmount
  case missingApp
  case missingTitle

  public var message: String {
    switch self {
    case .malformedArguments:
      return L("도구 인자를 읽지 못했습니다. JSON 형식으로 다시 호출하세요.")
    case .missingPurpose:
      return L("purpose(한 줄 이유)가 필요합니다 — 승인 카드에 표시됩니다.")
    case .unknownAction(let raw):
      return Lf("지원하지 않는 화면 조작입니다: %@ — click·type·key·scroll·open_app·focus_window 중 하나를 쓰세요.", raw)
    case .coordinatesNotSupported:
      return L("좌표 클릭은 지원하지 않습니다 — ui_snapshot 으로 요소를 고르고 그 참조(r…)를 쓰세요.")
    case .missingRef:
      return L("이 조작에는 요소 참조(ref)가 필요합니다 — ui_snapshot 을 먼저 호출하세요.")
    case .invalidRef(let ref):
      return Lf("요소 참조가 올바르지 않습니다: %@ — ui_snapshot 이 준 r1, r2 … 형식을 쓰세요.", ref)
    case .emptyText:
      return L("입력할 텍스트가 비어 있습니다.")
    case .textTooLong:
      return Lf("한 번에 입력할 수 있는 글자는 %d자까지입니다.", UiGuard.maxTextLength)
    case .emptyKeys:
      return L("입력할 키 조합이 비어 있습니다. 예: cmd+s")
    case .invalidKey(let key):
      return Lf("허용되지 않는 키입니다: %@", key)
    case .invalidDirection(let raw):
      return Lf("스크롤 방향은 up 또는 down 이어야 합니다: %@", raw)
    case .invalidAmount:
      return L("스크롤 양은 1~20 사이의 정수여야 합니다.")
    case .missingApp:
      return L("대상 앱이 필요합니다 — app 에 앱 이름이나 번들 ID를 넣으세요.")
    case .missingTitle:
      return L("앞으로 가져올 창 제목(title)이 필요합니다.")
    }
  }
}

/// 검증을 통과한 화면 조작 1건.
public struct UiActionSpec: Equatable, Sendable {
  public let kind: UiActionKind
  /// `ui_snapshot` 참조(`r12`) — 요소가 필요한 조작에만 있다.
  public let ref: String?
  public let text: String?
  public let keys: String?
  public let direction: UiScrollDirection?
  /// 스크롤 양(1~20) 또는 클릭 횟수(1~2) — 종류에 따라 뜻이 다르다.
  public let amount: Int
  public let app: String?
  public let title: String?
  /// 한 줄 이유 — 필수.
  public let purpose: String

  private init(kind: UiActionKind, ref: String?, text: String?, keys: String?,
               direction: UiScrollDirection?, amount: Int, app: String?, title: String?,
               purpose: String) {
    self.kind = kind
    self.ref = ref
    self.text = text
    self.keys = keys
    self.direction = direction
    self.amount = amount
    self.app = app
    self.title = title
    self.purpose = purpose
  }

  /// 이 조작이 요소 참조를 요구하는가.
  public var requiresRef: Bool {
    switch kind {
    case .click: return true
    case .type, .scroll: return ref != nil
    case .key, .openApp, .focusWindow: return false
    }
  }

  /// 요소 참조가 있어야만 대상(역할·이름)을 확인할 수 있다.
  public var hasElementTarget: Bool { ref != nil }

  // MARK: - 파싱

  /// 모델이 부른 도구 호출 → 검증된 명세. 실패하면 이유를 돌려준다.
  public static func parse(_ call: AgentToolCall) -> Result<UiActionSpec, UiActionError> {
    parse(arguments: call.arguments)
  }

  public static func parse(arguments: String) -> Result<UiActionSpec, UiActionError> {
    guard let data = arguments.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return .failure(.malformedArguments) }

    // 좌표는 Phase 3 전까지 어떤 형태로도 받지 않는다.
    if object["x"] != nil || object["y"] != nil {
      return .failure(.coordinatesNotSupported)
    }

    let purpose = string(object["purpose"]) ?? ""
    guard !purpose.isEmpty else { return .failure(.missingPurpose) }

    let rawAction = (string(object["action"]) ?? "").lowercased()
    guard let kind = UiActionKind(rawValue: rawAction) else {
      return .failure(.unknownAction(rawAction))
    }

    let ref = normalizedRef(string(object["ref"]))
    let text = object["text"] as? String
    let keys = string(object["keys"])
    let app = string(object["app"])
    let title = string(object["title"])

    switch kind {
    case .click:
      guard let ref else {
        return .failure(string(object["ref"]) == nil ? .missingRef : .invalidRef(string(object["ref"]) ?? ""))
      }
      let count = int(object["click_count"]) ?? 1
      guard (1...2).contains(count) else { return .failure(.invalidAmount) }
      return .success(UiActionSpec(kind: kind, ref: ref, text: nil, keys: nil,
                                   direction: nil, amount: count,
                                   app: app, title: nil, purpose: purpose))

    case .type:
      guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
        return .failure(.emptyText)
      }
      guard text.count <= UiGuard.maxTextLength else { return .failure(.textTooLong) }
      if let rawRef = string(object["ref"]), ref == nil {
        return .failure(.invalidRef(rawRef))
      }
      return .success(UiActionSpec(kind: kind, ref: ref, text: text, keys: nil,
                                   direction: nil, amount: 0,
                                   app: app, title: nil, purpose: purpose))

    case .key:
      guard let keys, !keys.isEmpty else { return .failure(.emptyKeys) }
      return .success(UiActionSpec(kind: kind, ref: nil, text: nil, keys: keys,
                                   direction: nil, amount: 0,
                                   app: app, title: nil, purpose: purpose))

    case .scroll:
      let rawDirection = (string(object["direction"]) ?? "down").lowercased()
      guard let direction = UiScrollDirection(rawValue: rawDirection) else {
        return .failure(.invalidDirection(rawDirection))
      }
      let amount = int(object["amount"]) ?? 3
      guard (1...20).contains(amount) else { return .failure(.invalidAmount) }
      if let rawRef = string(object["ref"]), ref == nil {
        return .failure(.invalidRef(rawRef))
      }
      return .success(UiActionSpec(kind: kind, ref: ref, text: nil, keys: nil,
                                   direction: direction, amount: amount,
                                   app: app, title: nil, purpose: purpose))

    case .openApp:
      guard let app, !app.isEmpty else { return .failure(.missingApp) }
      return .success(UiActionSpec(kind: kind, ref: nil, text: nil, keys: nil,
                                   direction: nil, amount: 0,
                                   app: app, title: nil, purpose: purpose))

    case .focusWindow:
      guard let title, !title.isEmpty else { return .failure(.missingTitle) }
      return .success(UiActionSpec(kind: kind, ref: nil, text: nil, keys: nil,
                                   direction: nil, amount: 0,
                                   app: app, title: title, purpose: purpose))
    }
  }

  private static func string(_ any: Any?) -> String? {
    guard let value = any as? String else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func int(_ any: Any?) -> Int? {
    if let n = any as? Int { return n }
    if let d = any as? Double { return Int(d) }
    if let s = any as? String { return Int(s) }
    return nil
  }

  /// `r12` 형식만 인정한다. 형식이 다르면 nil(호출부가 `invalidRef` 로 구분).
  private static func normalizedRef(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let lower = raw.lowercased()
    guard lower.hasPrefix("r") else { return nil }
    let digits = lower.dropFirst()
    guard !digits.isEmpty, digits.allSatisfy(\.isNumber), Int(digits) ?? 0 > 0 else { return nil }
    return lower
  }

  // MARK: - 카드·감사 문구

  /// 승인 카드에 보여 줄 한 줄. `target` 이 있으면 역할·이름까지 보여 준다.
  public func describe(appName: String, target: UiActionTarget?) -> String {
    let place = target?.label ?? appName
    switch kind {
    case .click:
      let noun = target?.label ?? L("요소")
      return amount > 1
        ? Lf("%@에서 %@을(를) %d번 클릭", appName, noun, amount)
        : Lf("%@에서 %@을(를) 클릭", appName, noun)
    case .type:
      let preview = Self.preview(text ?? "")
      return target == nil
        ? Lf("%@에 텍스트 입력 — %@", appName, preview)
        : Lf("%@에 텍스트 입력 — %@", place, preview)
    case .key:
      return Lf("%@에 키 입력 — %@", appName, keys ?? "")
    case .scroll:
      let direction = direction?.displayName ?? L("아래로")
      return target == nil
        ? Lf("%@에서 %@ %d칸 스크롤", appName, direction, amount)
        : Lf("%@ 위에서 %@ %d칸 스크롤", place, direction, amount)
    case .openApp:
      return Lf("앱 열기 — %@", appName)
    case .focusWindow:
      return Lf("창 앞으로 — %@", title ?? "")
    }
  }

  /// 감사 로그용 — `ui:click Notes "저장"` 형식(PLAN §4.7). 텍스트는 `AgentAudit.mask` 가 가린다.
  public func auditCommand(appName: String, target: UiActionTarget?) -> String {
    let targetName = target?.name ?? title ?? ""
    let quoted = targetName.isEmpty ? "" : " \"\(targetName)\""
    let detail: String
    switch kind {
    case .click: detail = "click"
    case .type: detail = "type \(text ?? "")"
    case .key: detail = "key \(keys ?? "")"
    case .scroll: detail = "scroll \(direction?.rawValue ?? "down") \(amount)"
    case .openApp: detail = "open_app"
    case .focusWindow: detail = "focus_window"
    }
    return "ui:\(detail) \(appName)\(quoted)"
  }

  /// 카드에 남길 입력 미리보기 — 줄바꿈은 `↵` 로 접는다(최대 80자).
  public static func preview(_ text: String) -> String {
    let flat = text.replacingOccurrences(of: "\n", with: "↵")
    guard flat.count > 80 else { return flat }
    return String(flat.prefix(79)) + "…"
  }

  /// 이 조작이 "전송"일 수 있는가 — 줄바꿈이 포함된 텍스트 입력(메일·메신저).
  public var maySend: Bool {
    kind == .type && (text ?? "").contains("\n")
  }
}

/// 조작 대상 요소의 요약 — 카드·판정 공용(Core, AX 의존 없음).
public struct UiActionTarget: Equatable, Sendable {
  public var role: String
  public var name: String
  public var isSecure: Bool

  public init(role: String, name: String, isSecure: Bool) {
    self.role = role
    self.name = name
    self.isSecure = isSecure
  }

  public var label: String {
    name.isEmpty ? role : "\(role) \"\(name)\""
  }
}
