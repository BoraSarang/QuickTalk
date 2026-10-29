import XCTest
@testable import QuickTalkCore

// [FEATURE] 화면 요소 스냅샷 — 순수 계산 계약 (PLAN_v0.25 Phase 1)
//
// 고정하는 것
//   · 이름 없는 컨테이너는 목록에서 빠지고 자식이 부모 자리로 올라온다(경로가 흔들리지 않게).
//   · 참조는 r1, r2, … 순서대로 — 같은 스냅샷 안에서만 유효하다.
//   · 같은 이름 형제는 **순번**으로 구분한다(경로의 index).
//   · 비밀번호 필드는 값이 있어도 "없다"고 보고한다.
//   · 노드·깊이·이름 길이 상한에서 **조용히 잘리지 않고** truncated 로 알린다.

final class UiSnapshotTests: XCTestCase {
  private func button(_ name: String, frame: UiRect? = nil) -> UiNode {
    UiNode(role: "AXButton", name: name, frame: frame)
  }

  // MARK: - 평탄화

  func testUnnamedContainersAreFlattened() {
    let root = UiNode(role: "AXWindow", name: "메모", children: [
      UiNode(role: "AXGroup", children: [
        UiNode(role: "AXGroup", children: [button("저장")])
      ])
    ])
    let snapshot = UiSnapshot.build(appName: "Notes", windowTitle: "메모", root: root)
    XCTAssertEqual(snapshot.entries.map(\.name), ["저장"])
    // 창·그룹은 목록에 없고 버튼이 첫 줄이다.
    XCTAssertEqual(snapshot.entries.first?.ref, "r1")
    XCTAssertEqual(snapshot.entries.first?.depth, 0)
    XCTAssertFalse(snapshot.truncated)
  }

  func testNamedContainerKeepsDepthForChildren() {
    let root = UiNode(role: "AXWindow", name: "메모", children: [
      UiNode(role: "AXGroup", name: "도구 막대", children: [button("저장")])
    ])
    let snapshot = UiSnapshot.build(appName: "Notes", windowTitle: "메모", root: root)
    XCTAssertEqual(snapshot.entries.map(\.depth), [0, 1])
    XCTAssertEqual(snapshot.entries.map(\.ref), ["r1", "r2"])
    XCTAssertEqual(snapshot.entries[1].path.depth, 2)
  }

  func testRefsAreSequential() {
    let root = UiNode(role: "AXWindow", children: [
      button("가"), button("나"), button("다")
    ])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.entries.map(\.ref), ["r1", "r2", "r3"])
    XCTAssertEqual(snapshot.entry(ref: "r2")?.name, "나")
    XCTAssertNil(snapshot.entry(ref: "r9"))
  }

  // MARK: - 경로

  func testSameNameSiblingsGetDistinctIndex() {
    let root = UiNode(role: "AXWindow", children: [button("삭제"), button("삭제")])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.entries.map { $0.path.target?.index }, [0, 1])
    XCTAssertTrue(snapshot.entries[0].path.summary.contains("[0]"))
  }

  func testDifferentParentsRestartIndex() {
    let root = UiNode(role: "AXWindow", children: [
      UiNode(role: "AXGroup", name: "A", children: [button("열기")]),
      UiNode(role: "AXGroup", name: "B", children: [button("열기")])
    ])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    let openIndices = snapshot.entries.filter { $0.name == "열기" }.map { $0.path.target?.index }
    XCTAssertEqual(openIndices, [0, 0])
  }

  func testFlattenedContainerKeepsSiblingIndexUnique() {
    // 이름 없는 그룹이 평탄화되면 그 자식과 바깥 형제가 **같은 부모** 아래에 선다.
    // 순번표를 새로 만들면 둘 다 index 0 이 되어 경로가 모호해진다 — Phase 2에서 엉뚱한 요소를 누른다.
    let root = UiNode(role: "AXWindow", children: [
      UiNode(role: "AXGroup", children: [button("열기")]),
      button("열기")
    ])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.entries.map { $0.path.target?.index }, [0, 1])
  }

  func testPathSummaryKeepsTailWhenLong() {
    var path = UiElementPath()
    for i in 0..<30 {
      path = path.appending(.init(role: "group", name: "아주 긴 이름 \(i)", index: 0))
    }
    let summary = path.summary
    XCTAssertTrue(summary.count <= 162, "카드에 들어가야 한다")
    XCTAssertTrue(summary.hasSuffix("group \"아주 긴 이름 29\"[0]"), "대상(마지막 단계)이 남아야 한다")
  }

  // MARK: - 비밀번호 필드

  func testSecureFieldNeverReportsValue() {
    let root = UiNode(role: "AXWindow", children: [
      UiNode(role: "AXTextField", name: "암호", hasValue: true, isSecure: true)
    ])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    let entry = snapshot.entries[0]
    XCTAssertTrue(entry.isSecure)
    XCTAssertFalse(entry.hasValue, "비밀번호 필드는 값이 있어도 없다고 보고한다")
    let rendered = snapshot.render()
    XCTAssertTrue(rendered.contains("secure"))
    XCTAssertFalse(rendered.contains("value"))
  }

  // MARK: - 상한

  func testNameIsClipped() {
    let long = String(repeating: "가", count: 300)
    let root = UiNode(role: "AXWindow", children: [button(long)])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.entries[0].name.count, UiSnapshotLimits.maxNameLength)
    XCTAssertTrue(snapshot.entries[0].name.hasSuffix("…"))
  }

  func testNodeCapMarksTruncated() {
    let children = (0..<500).map { button("버튼 \($0)") }
    let root = UiNode(role: "AXWindow", children: children)
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.count, UiSnapshotLimits.maxNodes)
    XCTAssertTrue(snapshot.truncated)
    XCTAssertTrue(snapshot.render().contains("\(UiSnapshotLimits.maxNodes)개까지만"))
  }

  func testDepthCapMarksTruncated() {
    var node = button("깊은 버튼")
    for i in 0..<20 {
      node = UiNode(role: "AXGroup", name: "그룹 \(i)", children: [node])
    }
    let root = UiNode(role: "AXWindow", children: [node])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertTrue(snapshot.truncated)
    XCTAssertEqual(snapshot.count, UiSnapshotLimits.maxDepth + 1)
  }

  // MARK: - 렌더

  func testRenderMarksDisabledAndCenter() {
    let root = UiNode(role: "AXWindow", children: [
      UiNode(role: "AXButton", name: "저장", isEnabled: false,
             frame: UiRect(x: 780, y: 620, width: 64, height: 40)),
      button("취소")
    ])
    let snapshot = UiSnapshot.build(appName: "Notes", windowTitle: "메모", root: root)
    let rendered = snapshot.render()
    XCTAssertTrue(rendered.contains("[r1] button \"저장\" disabled center=(812,640)"))
    XCTAssertTrue(rendered.contains("[r2] button \"취소\""))
    XCTAssertFalse(rendered.contains("center=(0,0)"))
  }

  func testEmptySnapshotExplainsWhy() {
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "",
                                    root: UiNode(role: "AXWindow"))
    XCTAssertTrue(snapshot.isEmpty)
    // 빈 문자열을 돌려주면 모델이 "화면이 비었다"와 "도구가 실패했다"를 구분하지 못한다.
    XCTAssertFalse(snapshot.render().isEmpty)
    XCTAssertTrue(snapshot.render().contains("screenshot"))
  }

  func testCardTitleMentionsAppAndWindow() {
    let snapshot = UiSnapshot.build(appName: "Notes", windowTitle: "메모",
                                    root: UiNode(role: "AXWindow", children: [button("저장")]))
    XCTAssertTrue(snapshot.cardTitle.contains("Notes"))
    XCTAssertTrue(snapshot.cardTitle.contains("메모"))
  }

  // MARK: - 역할 이름

  func testDisplayRoleStripsAXPrefix() {
    XCTAssertEqual(UiSnapshot.displayRole("AXButton"), "button")
    XCTAssertEqual(UiSnapshot.displayRole("AXTextField"), "textfield")
    XCTAssertEqual(UiSnapshot.displayRole("AXUnknownRole"), "unknownrole")
    XCTAssertEqual(UiSnapshot.displayRole("button"), "button")
  }

  func testInteractiveRoleWithoutNameIsKept() {
    let root = UiNode(role: "AXWindow", children: [
      UiNode(role: "AXButton"),                       // 이름 없는 버튼 — 눌러야 하므로 남긴다
      UiNode(role: "AXGroup")                         // 이름 없는 그룹 — 뺀다
    ])
    let snapshot = UiSnapshot.build(appName: "App", windowTitle: "", root: root)
    XCTAssertEqual(snapshot.entries.map(\.role), ["button"])
  }
}
