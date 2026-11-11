import Foundation

// [FEATURE] 실행 계획 카드 (v0.36.3, PLAN_v0.36 §4)
//
// 모델이 여러 단계가 필요한 작업을 하기 전에 `propose_plan` 을 호출해 **계획만 말하고 멈춘다**.
// 사용자가 카드의 [실행]을 누르면 그때 실제 실행 턴이 시작된다.
//
// 설계 원칙:
//   · 계획은 **손이 아니라 입**이다 — propose_plan 은 읽기 전용이고 아무것도 바꾸지 않는다.
//   · 단계는 3~8개로 제한한다(짧게 유지, 카드가 화면을 덮지 않게).
//   · 권한은 읽기/쓰기/네트워크 세 가지로만 표시한다 — 세부 권한은 실행 승인 카드가 다시 판단한다.

public struct ExecutionPlan: Codable, Equatable {
  /// 계획이 요구하는 접근 — 카드에 칩으로 보여 준다.
  public enum Permission: String, Codable, CaseIterable, Identifiable, Equatable {
    case read
    case write
    case network

    public var id: String { rawValue }

    public var displayName: String {
      switch self {
      case .read: return L("읽기")
      case .write: return L("쓰기")
      case .network: return L("네트워크")
      }
    }

    public var symbol: String {
      switch self {
      case .read: return "eye"
      case .write: return "square.and.pencil"
      case .network: return "network"
      }
    }
  }

  /// 카드에 한 줄로 보이는 목표.
  public var goal: String
  /// 순서대로 실행할 단계 — 1~8개.
  public var steps: [String]
  /// 예상 권한. 비어 있으면 칩을 그리지 않는다.
  public var permissions: [Permission]

  /// 단계 상한 — 모델이 더 많이 주면 앞에서 자른다.
  public static let maxSteps = 8

  public init(goal: String, steps: [String], permissions: [Permission] = []) {
    self.goal = goal.trimmingCharacters(in: .whitespacesAndNewlines)
    self.steps = steps
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .prefix(Self.maxSteps)
      .map { $0 }
    // 중복 권한은 한 번만, 선언 순서를 유지한다.
    var seen = Set<Permission>()
    self.permissions = permissions.filter { seen.insert($0).inserted }
  }

  public var isEmpty: Bool { goal.isEmpty || steps.isEmpty }

  /// 도구 호출 인자에서 계획을 만든다. 형식이 어긋나면 nil.
  public static func from(_ call: AgentToolCall) -> ExecutionPlan? {
    guard let data = call.arguments.data(using: .utf8),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }
    let goal = (obj["goal"] as? String) ?? ""
    let rawSteps = (obj["steps"] as? [Any]) ?? []
    let steps = rawSteps.compactMap { $0 as? String }
    let rawPermissions = (obj["permissions"] as? [Any]) ?? []
    let permissions = rawPermissions.compactMap { value -> Permission? in
      guard let raw = value as? String else { return nil }
      return Permission(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
    let plan = ExecutionPlan(goal: goal, steps: steps, permissions: permissions)
    return plan.isEmpty ? nil : plan
  }

  /// [수정]을 눌렀을 때 입력창에 넣을 텍스트 — 그대로 보내면 일반 질문이 된다.
  public var editableText: String {
    var lines = [goal, ""]
    for (index, step) in steps.enumerated() {
      lines.append("\(index + 1). \(step)")
    }
    return lines.joined(separator: "\n")
  }
}

/// `propose_plan` 도구의 이름 — 스키마·실행기·러너가 같은 값을 쓴다.
public enum PlanTool {
  public static let name = "propose_plan"
}

// MARK: - 계획 실행 계약 (v0.36.3)

extension ExecutionPrompt {
  /// 계획 카드의 [실행]을 눌렀을 때 남는 사용자 말풍선.
  public static var planVisibleText: String { L("이 계획대로 실행해 주세요.") }

  /// 계획 실행 계약 — 단계 목록을 그대로 지시문으로 넘긴다.
  ///
  /// v0.36.2 의 `[이미 실행한 것]` 블록도 함께 붙인다 — 계획을 세우면서 확인한 값이
  /// 있으면 실행 턴에서 다시 확인하지 않게 한다.
  public static func planContract(_ plan: ExecutionPlan, alreadyRun: [AgentEvent]? = nil) -> String {
    let english = L10n.effective == .en
    let steps = plan.steps.enumerated()
      .map { "\($0.offset + 1). \($0.element)" }
      .joined(separator: "\n")
    let base: String
    if english {
      base = """
        Run the plan below in order.
        Goal: \(plan.goal)

        \(steps)

        - Run only the steps in this plan. Do not add new research or create files that are not listed.
        - Do not repeat steps that are already done; cite their results instead.
        - Before any irreversible action (delete, overwrite, send, pay), say in one line what will change.
        - If you need a tool, run it now and check the result before reporting.
        - Report each step's result and the final outcome. If a step cannot be done, say why and continue with the rest.
        """
    } else {
      base = """
        아래 계획을 순서대로 실행해 주세요.
        목표: \(plan.goal)

        \(steps)

        - 계획에 있는 단계만 실행하고, 없는 새 조사·파일 생성은 하지 마세요.
        - 이미 끝난 단계는 반복하지 말고, 결과만 인용하세요.
        - 되돌릴 수 없는 동작(삭제·덮어쓰기·전송·결제)은 실행 전에 무엇이 바뀌는지 한 줄로 알려 주세요.
        - 도구가 필요하면 지금 실행하고, 결과까지 확인한 뒤 단계별 결과와 최종 결과를 보고하세요.
        - 실행할 수 없는 단계가 있으면 이유를 한 줄로 말하고, 나머지는 계속하세요.
        """
    }
    guard let block = alreadyRunBlock(alreadyRun) else { return base }
    return base + "\n\n" + block
  }
}
