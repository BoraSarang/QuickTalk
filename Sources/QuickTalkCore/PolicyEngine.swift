import Foundation

// [FEATURE] 권한 정책 — 단계 × 위험도로 허용/확인/차단 결정 (PLAN_v0.18 §4.2·§4.5)
//
// 2축 구조
//   · 권한 단계(읽기/쓰기/실행) — 사용자가 설정에서 "항상 허용 / 매번 확인"을 고른다.
//   · 위험도(보통/중요/치명적) — 시스템이 정한다. **중요는 자동 허용이어도 반드시 확인**,
//     치명적은 기본 차단(설정에서 해제 가능).
//
// 앱이 제공하는 화이트리스트는 없다. 허용 규칙은 **사용자가 직접 쓰는 패턴**이다.

/// 사용자 설정 — 단계별 자동 처리 + 제한 + 허용 규칙.
public struct AgentPolicy: Codable, Equatable {
  /// 읽기 자동 허용(기본 켜짐 — 읽기는 시스템에 아무 변화도 없다)
  public var readPolicy: AgentAutoApprove = .alwaysAllow
  /// 쓰기 자동 허용(기본 끔 — 매번 확인)
  public var writePolicy: AgentAutoApprove = .alwaysAsk
  /// 실행 자동 허용(기본 끔 — 매번 확인)
  public var executePolicy: AgentAutoApprove = .alwaysAsk
  /// 상승 권한(sudo 등) 허용 — 기본 꺼짐. 켜도 앱은 비밀번호를 요구하지 않는다.
  public var allowElevated: Bool = false
  /// 치명적 명령 허용 — 기본 꺼짐.
  public var allowCritical: Bool = false
  /// 사용자가 직접 쓴 허용 규칙(`brew install *` 같은 패턴). 앱 기본값 없음.
  public var rules: [String] = []

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case readPolicy, writePolicy, executePolicy, allowElevated, allowCritical, rules
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func enumValue<T: RawRepresentable>(_ t: T.Type, _ k: CodingKeys, _ d: T) -> T
    where T.RawValue == String {
      guard let raw = try? c.decodeIfPresent(String.self, forKey: k), let v = T(rawValue: raw) else { return d }
      return v
    }
    readPolicy = enumValue(AgentAutoApprove.self, .readPolicy, .alwaysAllow)
    writePolicy = enumValue(AgentAutoApprove.self, .writePolicy, .alwaysAsk)
    executePolicy = enumValue(AgentAutoApprove.self, .executePolicy, .alwaysAsk)
    allowElevated = try c.decodeIfPresent(Bool.self, forKey: .allowElevated) ?? false
    allowCritical = try c.decodeIfPresent(Bool.self, forKey: .allowCritical) ?? false
    rules = try c.decodeIfPresent([String].self, forKey: .rules) ?? []
  }

  /// 단계별 정책 조회.
  public func autoApprove(for level: AgentPermissionLevel) -> AgentAutoApprove {
    switch level {
    case .read: return readPolicy
    case .write: return writePolicy
    case .execute: return executePolicy
    }
  }
}

/// 사용자에게 확인할 요청 — 확인 시트에 그대로 보여 준다.
public struct AgentApprovalRequest: Equatable {
  public let command: String
  public let level: AgentPermissionLevel
  public let risk: AgentRiskLevel
  public let capability: AgentCapability
  /// 승인으로 열어 줄 경로(쓰기 요구일 때)
  public let writablePaths: [String]
  /// 왜 확인하는지(한 줄)
  public let reason: String

  public init(command: String, level: AgentPermissionLevel, risk: AgentRiskLevel,
              capability: AgentCapability, writablePaths: [String], reason: String) {
    self.command = command; self.level = level; self.risk = risk
    self.capability = capability; self.writablePaths = writablePaths; self.reason = reason
  }
}

/// 결정 결과.
public enum AgentDecision: Equatable {
  /// 그대로 실행
  case allow
  /// 사용자 확인 필요
  case ask(AgentApprovalRequest)
  /// 실행하지 않음(사유 있음)
  case deny(String)
}

public enum PolicyEngine {
  /// ★ 결정 — 단계(사용자 설정) × 위험도(시스템 판정).
  public static func decide(command: String,
                            capability: AgentCapability,
                            risk: AgentRiskLevel,
                            policy: AgentPolicy) -> AgentDecision {
    // ① 치명적 — 기본 차단(해제는 설정에서)
    if risk == .critical && !policy.allowCritical {
      return .deny(L("치명적인 명령이라 실행하지 않았습니다. 설정 › 도구에서 허용할 수 있습니다."))
    }
    // ② 상승 권한 — 샌드박스로 막을 수 없다. 앱은 비밀번호를 요구하지 않는다.
    if capability == .elevated && !policy.allowElevated {
      return .deny(L("상승 권한이 필요한 명령입니다. 터미널에서 직접 실행해 주세요."))
    }
    // ③ 위험도 "중요"는 자동 허용이어도 반드시 확인한다
    if risk == .important {
      return .ask(request(command: command, capability: capability, risk: risk,
                          reason: L("시스템에 영향을 줄 수 있어 확인합니다.")))
    }
    // ④ 사용자가 직접 쓴 허용 규칙
    if matchesRule(command: command, rules: policy.rules) {
      return .allow
    }
    // ⑤ 단계별 정책
    let level = capability.level
    switch policy.autoApprove(for: level) {
    case .alwaysAllow: return .allow
    case .alwaysAsk:
      return .ask(request(command: command, capability: capability, risk: risk,
                          reason: reason(for: capability)))
    }
  }

  private static func request(command: String, capability: AgentCapability,
                              risk: AgentRiskLevel, reason: String) -> AgentApprovalRequest {
    let paths: [String]
    if case .write(let path) = capability { paths = [path] } else { paths = [] }
    return AgentApprovalRequest(command: command, level: capability.level, risk: risk,
                                capability: capability, writablePaths: paths, reason: reason)
  }

  private static func reason(for capability: AgentCapability) -> String {
    switch capability {
    case .read: return L("읽기만 필요합니다.")
    case .write(let path): return Lf("쓰기가 필요합니다: %@", path)
    case .network: return L("네트워크 접근이 필요합니다.")
    case .elevated: return L("상승 권한이 필요합니다.")
    case .blocked: return L("샌드박스가 막았습니다.")
    }
  }

  /// 허용 규칙 매칭 — `*` 와일드카드, 앞부분 일치도 지원(`brew install` → `brew install *`).
  public static func matchesRule(command: String, rules: [String]) -> Bool {
    let normalized = command.trimmingCharacters(in: .whitespacesAndNewlines)
    for raw in rules {
      let pattern = raw.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !pattern.isEmpty else { continue }
      if pattern == normalized { return true }
      if pattern.contains("*") {
        if matchesWildcard(command: normalized, pattern: pattern) { return true }
      } else if normalized.hasPrefix(pattern + " ") || normalized.hasPrefix(pattern) {
        return true
      }
    }
    return false
  }

  /// `*` → `.*` 정규식 변환(그 외 문자는 이스케이프).
  static func matchesWildcard(command: String, pattern: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: pattern)
      .replacingOccurrences(of: "\\*", with: ".*")
    guard let re = try? NSRegularExpression(pattern: "^\(escaped)$") else { return false }
    let range = NSRange(command.startIndex..., in: command)
    return re.firstMatch(in: command, range: range) != nil
  }
}
