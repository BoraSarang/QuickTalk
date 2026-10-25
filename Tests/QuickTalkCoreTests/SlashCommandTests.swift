import XCTest
@testable import QuickTalkCore

// [FEATURE] 슬래시 팔레트 (v0.21)
//
// 팔레트는 **입력을 돕는 지름길**이다. 자유 텍스트를 막지 않고,
// 명령 이름·별칭·설명으로 거르며, `/` 첫 토큰일 때만 나타난다.

final class SlashCommandTests: XCTestCase {
  func testPaletteVisibleOnlyForFirstToken() {
    XCTAssertTrue(SlashCommands.isPaletteVisible(for: "/"))
    XCTAssertTrue(SlashCommands.isPaletteVisible(for: "/화면"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "화면"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "/화면 지금"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "/화면\n둘째 줄"))
    XCTAssertTrue(SlashCommands.matches("일반 질문").isEmpty)
  }

  func testEmptySlashListsEverything() {
    XCTAssertEqual(SlashCommands.matches("/").count, SlashCommands.all.count)
    XCTAssertEqual(SlashCommands.matches("/화면").count, 1)
    XCTAssertEqual(SlashCommands.matches("/화면").first?.name, "화면")
  }

  func testAliasesAndSummaryMatch() {
    XCTAssertEqual(SlashCommands.matches("/screenshot").first?.name, "화면")
    XCTAssertEqual(SlashCommands.matches("/ram").first?.name, "메모리")
    XCTAssertEqual(SlashCommands.matches("/용량").first?.name, "디스크")
    // 설명으로도 찾힌다
    XCTAssertFalse(SlashCommands.matches("/확인").isEmpty)
  }

  func testParseNameAliasAndArgument() {
    let a = SlashCommands.parse("/화면")
    XCTAssertEqual(a?.command.name, "화면")
    XCTAssertEqual(a?.argument, "")
    let b = SlashCommands.parse("/screenshot 지금 바로")
    XCTAssertEqual(b?.command.name, "화면")
    XCTAssertEqual(b?.argument, "지금 바로")
    XCTAssertNil(SlashCommands.parse("화면"))
    XCTAssertNil(SlashCommands.parse("/없는명령"))
  }

  func testCatalogIsConsistent() {
    let names = SlashCommands.all.map(\.name)
    XCTAssertEqual(Set(names).count, names.count, "명령 이름은 고유해야 한다")
    for command in SlashCommands.all {
      XCTAssertFalse(command.summary.isEmpty, "\(command.name): 설명이 필요하다")
      XCTAssertFalse(command.template.isEmpty, "\(command.name): 채울 문장이 필요하다")
      XCTAssertTrue(command.token.hasPrefix("/"))
      // 템플릿이 슬래시로 시작하면 전송 시 팔레트가 다시 뜬다 — 일반 문장이어야 한다.
      XCTAssertFalse(command.template.hasPrefix("/"), "\(command.name): 템플릿은 일반 문장")
    }
  }

  func testCommandsMapToExistingTools() {
    // 팔레트는 **앱에 실제로 있는 기능**만 가리킨다.
    let toolNames = Set(AgentToolCatalog.all.map(\.name))
    XCTAssertTrue(toolNames.contains("shell"))
    XCTAssertTrue(toolNames.contains("screenshot"))
    let templates = SlashCommands.all.map(\.template).joined(separator: "\n")
    XCTAssertTrue(templates.contains("디스크"))
    XCTAssertTrue(templates.contains("프로세스"))
    XCTAssertTrue(templates.contains("캡처"))
  }
}
