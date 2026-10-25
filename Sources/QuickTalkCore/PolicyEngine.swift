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
  /// 전역 자동 수락(v0.20) — 일반 명령은 확인 없이 실행한다.
  /// **중요·치명적 위험과 상승 권한은 그대로 확인/차단**한다(안전장치는 자동 수락으로 꺼지지 않는다).
  public var autoAcceptAll: Bool = false
  /// 사용자가 직접 쓴 허용 규칙(`brew install *` 같은 패턴). 앱 기본값 없음.
  public var rules: [String] = []

  public init() {}

  private enum CodingKeys: String, CodingKey {
    case readPolicy, writePolicy, executePolicy, allowElevated, allowCritical
    case autoAcceptAll, rules
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
    autoAcceptAll = try c.decodeIfPresent(Bool.self, forKey: .autoAcceptAll) ?? false
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

  /// 승인하면 열어 줄 **폴더 범위** — "이 폴더 허용" 버튼이 쓴다.
  /// 파일 하나를 승인해도 그 상위 폴더가 범위가 된다(파일을 새로 만들어야 할 수 있다).
  public var writeScopes: [String] {
    var out: [String] = []
    for path in writablePaths {
      let scope = WriteScope.scope(for: path)
      if !scope.isEmpty && !out.contains(scope) { out.append(scope) }
    }
    return out
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

/// ★ 실행 계획 — **실행은 마지막**에 온다.
public enum AgentPlan: Equatable {
  /// 실행 금지(사유 있음)
  case deny(String)
  /// 사용자 확인 필요 — `request.capability` 에 실측 결과(또는 미실측)가 들어 있다.
  case ask(AgentApprovalRequest)
  /// 그대로 실행 (이 범위만)
  case allow(AgentCapability)
}

public enum PolicyEngine {
  /// ★ 결정 — 단계(사용자 설정) × 위험도(시스템 판정).
  ///
  /// `approvedScopes` 는 이번 대화에서 이미 승인한 **폴더 범위**다(v0.19).
  /// 범위 안의 쓰기는 다시 묻지 않는다 — 승인은 폴더 밖으로 새지 않는다.
  public static func decide(command: String,
                            capability: AgentCapability,
                            risk: AgentRiskLevel,
                            policy: AgentPolicy,
                            approvedScopes: [String] = []) -> AgentDecision {
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
    // ④ 전역 자동 수락 — 일반 명령은 확인 없이 실행한다(v0.20).
    //    위 ①~③(치명적 차단·상승 권한 차단·중요 확인)은 **건너뛰지 않는다**.
    if policy.autoAcceptAll { return .allow }
    // ⑤ 이미 승인한 폴더 범위 안의 쓰기 — 다시 묻지 않는다
    if case .write(let path) = capability,
       WriteScope.isApproved(path, scopes: approvedScopes) {
      return .allow
    }
    // ⑥ 사용자가 직접 쓴 허용 규칙
    if matchesRule(command: command, rules: policy.rules) {
      return .allow
    }
    // ⑦ 단계별 정책
    let level = capability.level
    switch policy.autoApprove(for: level) {
    case .alwaysAllow: return .allow
    case .alwaysAsk:
      return .ask(request(command: command, capability: capability, risk: risk,
                          reason: reason(for: capability)))
    }
  }

  /// ★ 실행 **이전**의 순서를 지킨다 — 위험 판정 → 정책 → (일반 명령만) 실측.
  ///
  /// 2026-10-22 사고: 이전 흐름은 [실측(실행) → 정책] 이라 `rm -rf /` 같은 치명적 명령이
  /// **정책 판단 전에 실제로 실행**됐다(읽기 전용 샌드박스라 지워지진 않았지만 명령이 끝나지
  /// 않아 앱이 멈췄다). 이제는 위험·중요 명령은 실행 없이 확인/차단만 하고,
  /// 일반 명령만 실측(=실행)한다.
  public static func plan(command: String, policy: AgentPolicy,
                          approvedScopes: [String] = []) -> AgentPlan {
    let risk = RiskClassifier.classify(command)
    if risk == .critical && !policy.allowCritical {
      return .deny(L("치명적인 명령이라 실행하지 않았습니다. 설정 › 도구에서 허용할 수 있습니다."))
    }
    if risk != .normal {
      // 중요한 명령은 **실측(=실행)하지 않는다** — 승인을 먼저 받고 나서 실측한다.
      let capability: AgentCapability = RiskClassifier.requiresElevation(command) ? .elevated : .unprobed
      return asPlan(decide(command: command, capability: capability, risk: risk,
                           policy: policy, approvedScopes: approvedScopes),
                    capability)
    }
    let capability = SandboxRunner.probe(command).capability
    return asPlan(decide(command: command, capability: capability, risk: risk,
                         policy: policy, approvedScopes: approvedScopes),
                  capability)
  }

  private static func asPlan(_ decision: AgentDecision, _ capability: AgentCapability) -> AgentPlan {
    switch decision {
    case .allow: return .allow(capability)
    case .ask(let request): return .ask(request)
    case .deny(let reason): return .deny(reason)
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
    case .unprobed: return L("실행 권한이 필요합니다.")
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
