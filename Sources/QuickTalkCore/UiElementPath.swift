import Foundation

// [FEATURE] 화면 요소 경로 — 좌표 대신 "역할 + 이름 + 형제 순번"으로 요소를 가리킨다 (PLAN_v0.25 Phase 1)
//
// 왜 좌표가 아닌가
//   · 좌표는 창을 옮기거나 크기를 바꾸면 곧바로 틀린 곳을 누른다. 검증할 방법도 없다.
//   · 역할·이름은 사람이 읽을 수 있어 승인 카드에 그대로 쓸 수 있고, 실행 직전에
//     "그 자리에 정말 그 버튼이 있는가"를 다시 확인할 수 있다.
//
// 경로는 **스냅샷에 실제로 노출된(emitted) 노드**만 센다. 이름 없는 그룹은 목록에서 빠지고
// 자식이 부모 자리로 올라오므로, 같은 화면이면 같은 경로가 나온다.

public struct UiElementPath: Equatable, Sendable {
  /// 한 단계 — 같은 부모 아래 같은 (역할, 이름) 형제 중 몇 번째인지.
  public struct Step: Equatable, Sendable {
    public var role: String
    public var name: String
    public var index: Int

    public init(role: String, name: String, index: Int) {
      self.role = role
      self.name = name
      self.index = index
    }
  }

  public var steps: [Step]

  public init(steps: [Step] = []) {
    self.steps = steps
  }

  public var isEmpty: Bool { steps.isEmpty }
  public var depth: Int { steps.count }

  /// 실행 직전에 "역할·이름이 그대로인가"를 확인할 때 쓰는 마지막 단계.
  public var target: Step? { steps.last }

  public func appending(_ step: Step) -> UiElementPath {
    UiElementPath(steps: steps + [step])
  }

  /// 같은 요소를 가리키는가 — Phase 2에서 재해석 결과와 비교한다.
  public func matches(_ other: UiElementPath) -> Bool {
    steps == other.steps
  }

  /// 카드·로그용 짧은 설명. 길면 **뒤쪽(대상에 가까운 쪽)** 을 남긴다.
  public var summary: String {
    let parts = steps.map { step -> String in
      let name = step.name.isEmpty ? "" : " \"\(step.name)\""
      return "\(step.role)\(name)[\(step.index)]"
    }
    let text = parts.joined(separator: " > ")
    guard text.count > 160 else { return text }
    return "… " + String(text.suffix(158))
  }
}
