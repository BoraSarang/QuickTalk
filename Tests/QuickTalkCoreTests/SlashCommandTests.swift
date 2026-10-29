import XCTest
@testable import QuickTalkCore

// [FEATURE] 슬래시 팔레트 (v0.21)
//
// 팔레트는 **입력을 돕는 지름길**이다. 자유 텍스트를 막지 않고,
// 명령 이름·별칭·설명으로 거르며, `/` 첫 토큰일 때만 나타난다.
//
// 2026-10-29 — 명령 **이름도** 언어를 따라간다(`/화면` ↔ `/Screen`).
//   이름이 한국어 리터럴로 고정돼 있어 영어 UI 에서도 `/화면` 이 남았고,
//   사용자는 "팔레트가 설정 언어의 반대로 나온다"고 느꼈다.

final class SlashCommandTests: XCTestCase {
  /// 번역표는 전역 상태다 — 테스트가 언어를 바꾸면 반드시 되돌린다(중첩 호출도 안전하게 defer).
  private func withLanguage(_ language: AppLanguage, _ body: () -> Void) {
    let previous = L10n.language
    L10n.language = language
    defer { L10n.language = previous }
    body()
  }

  func testPaletteVisibleOnlyForFirstToken() {
    XCTAssertTrue(SlashCommands.isPaletteVisible(for: "/"))
    XCTAssertTrue(SlashCommands.isPaletteVisible(for: "/화면"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "화면"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "/화면 지금"))
    XCTAssertFalse(SlashCommands.isPaletteVisible(for: "/화면\n둘째 줄"))
    XCTAssertTrue(SlashCommands.matches("일반 질문").isEmpty)
  }

  /// 팔레트 문구는 **지금 언어**를 따라야 한다 — `static let` 이면 처음 읽은 언어로 고정된다.
  func testCatalogFollowsCurrentLanguage() {
    withLanguage(.korean) {
      let command = SlashCommands.all.first { $0.id == "screen" }
      XCTAssertEqual(command?.name, "화면")
      XCTAssertEqual(command?.summary, "지금 화면을 찍어서 보여 달라고 요청")
      XCTAssertEqual(command?.token, "/화면")
    }
    withLanguage(.english) {
      let command = SlashCommands.all.first { $0.id == "screen" }
      XCTAssertEqual(command?.name, "Screen", "영어 UI 에서는 명령 이름도 영어여야 한다")
      XCTAssertEqual(command?.token, "/Screen")
      XCTAssertEqual(command?.summary, "Ask for a screenshot of the screen")
    }
  }

  /// 모든 명령이 한/영 이름을 갖는다 — 한쪽 언어에서만 보이면 팔레트가 반쪽 번역이 된다.
  func testEveryCommandNameIsTranslated() {
    withLanguage(.korean) {
      let korean = SlashCommands.all.map(\.name)
      withLanguage(.english) {
        let english = SlashCommands.all.map(\.name)
        XCTAssertEqual(korean.count, english.count)
        XCTAssertTrue(korean.allSatisfy { !$0.contains(where: { $0.isASCII }) },
                      "한국어 이름에 영문이 섞이면 안 된다: \(korean)")
        XCTAssertTrue(english.allSatisfy { !$0.contains(where: { $0.isHangulSyllable }) },
                      "영어 이름에 한글이 남았다: \(english)")
      }
    }
  }

  /// 언어를 바꿔도 **예전 이름으로** 칠 수 있어야 한다(습관·기억).
  func testOldLanguageNameStillMatches() {
    withLanguage(.english) {
      XCTAssertEqual(SlashCommands.matches("/화면").first?.id, "screen")
      XCTAssertEqual(SlashCommands.matches("/화면").first?.name, "Screen")
      XCTAssertEqual(SlashCommands.parse("/화면")?.command.id, "screen")
    }
    withLanguage(.korean) {
      XCTAssertEqual(SlashCommands.matches("/Screen").first?.id, "screen")
      XCTAssertEqual(SlashCommands.parse("/Screen")?.command.id, "screen")
    }
  }

  /// 도우미 도구를 끄면 도구가 필요한 명령은 팔레트에서 사라진다(2026-10-27).
  func testToolCommandsHiddenWhenToolsDisabled() {
    withLanguage(.korean) {
      let off = Set(SlashCommands.available(agentToolsEnabled: false).map(\.id))
      XCTAssertEqual(off, ["settings", "help"])
      XCTAssertTrue(SlashCommands.matches("/디스크", toolsEnabled: false).isEmpty)
      XCTAssertEqual(SlashCommands.matches("/도움말", toolsEnabled: false).first?.id, "help")
      XCTAssertEqual(SlashCommands.available(agentToolsEnabled: true).count,
                     SlashCommands.all.count)
    }
  }

  func testEmptySlashListsEverything() {
    withLanguage(.korean) {
      XCTAssertEqual(SlashCommands.matches("/").count, SlashCommands.all.count)
      XCTAssertEqual(SlashCommands.matches("/화면").count, 1)
      XCTAssertEqual(SlashCommands.matches("/화면").first?.name, "화면")
    }
    withLanguage(.english) {
      XCTAssertEqual(SlashCommands.matches("/").count, SlashCommands.all.count)
      XCTAssertEqual(SlashCommands.matches("/").first?.name, "Screen")
    }
  }

  func testAliasesAndSummaryMatch() {
    withLanguage(.korean) {
      XCTAssertEqual(SlashCommands.matches("/screenshot").first?.name, "화면")
      XCTAssertEqual(SlashCommands.matches("/ram").first?.name, "메모리")
      XCTAssertEqual(SlashCommands.matches("/용량").first?.name, "디스크")
      // 설명으로도 찾힌다
      XCTAssertFalse(SlashCommands.matches("/확인").isEmpty)
    }
  }

  func testParseNameAliasAndArgument() {
    withLanguage(.korean) {
      let a = SlashCommands.parse("/화면")
      XCTAssertEqual(a?.command.name, "화면")
      XCTAssertEqual(a?.argument, "")
      let b = SlashCommands.parse("/screenshot 지금 바로")
      XCTAssertEqual(b?.command.name, "화면")
      XCTAssertEqual(b?.argument, "지금 바로")
      XCTAssertNil(SlashCommands.parse("화면"))
      XCTAssertNil(SlashCommands.parse("/없는명령"))
    }
  }

  func testCatalogIsConsistent() {
    let ids = SlashCommands.all.map(\.id)
    XCTAssertEqual(Set(ids).count, ids.count, "명령 식별자는 고유해야 한다")
    let names = SlashCommands.all.map(\.name)
    XCTAssertEqual(Set(names).count, names.count, "같은 언어에서 명령 이름은 고유해야 한다")
    for command in SlashCommands.all {
      XCTAssertFalse(command.summary.isEmpty, "\(command.id): 설명이 필요하다")
      XCTAssertFalse(command.template.isEmpty, "\(command.id): 채울 문장이 필요하다")
      XCTAssertTrue(command.token.hasPrefix("/"))
      // 템플릿이 슬래시로 시작하면 전송 시 팔레트가 다시 뜬다 — 일반 문장이어야 한다.
      XCTAssertFalse(command.template.hasPrefix("/"), "\(command.id): 템플릿은 일반 문장")
      // 별칭에 자기 이름이 들어 있어야 언어를 바꾼 뒤에도 같은 이름으로 칠 수 있다.
      XCTAssertTrue(command.aliases.contains { $0.caseInsensitiveCompare(command.name) == .orderedSame },
                    "\(command.id): 현재 이름이 별칭에 없다")
    }
  }

  func testCommandsMapToExistingTools() {
    // 팔레트는 **앱에 실제로 있는 기능**만 가리킨다.
    let toolNames = Set(AgentToolCatalog.all.map(\.name))
    XCTAssertTrue(toolNames.contains("shell"))
    XCTAssertTrue(toolNames.contains("screenshot"))
    withLanguage(.korean) {
      let templates = SlashCommands.all.map(\.template).joined(separator: "\n")
      XCTAssertTrue(templates.contains("디스크"))
      XCTAssertTrue(templates.contains("프로세스"))
      XCTAssertTrue(templates.contains("캡처"))
    }
  }
}

private extension Character {
  var isHangulSyllable: Bool {
    guard let scalar = unicodeScalars.first, unicodeScalars.count == 1 else { return false }
    return (0xAC00...0xD7A3).contains(Int(scalar.value))
  }
}
