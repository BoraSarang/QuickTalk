import Foundation

// [FEATURE] 슬래시 팔레트 (v0.21) — `/`로 시작하면 명령 목록을 보여 주고 **클릭으로** 고른다.
//
// 왜 팔레트인가
//   · 작은 모델은 "도구를 골라라"는 지시를 놓치기 쉽다. 사용자가 의도를 한 번에 지정하면
//     모델이 어떤 도구를 써야 하는지 헷갈리지 않는다.
//   · 자유 텍스트를 **대체**하지 않는다. 팔레트는 입력을 돕는 지름길일 뿐이고,
//     고른 뒤에도 문장을 이어 쓸 수 있다.
//
// 원칙
//   · Enter 처리(전송)는 바꾸지 않는다 — **클릭 선택만** 추가한다(한글 IME 안전).
//   · 명령은 앱의 실제 기능과 1:1로 대응한다. 없는 기능을 있는 척하지 않는다.
//   · 창 연결처럼 **권한·선택이 필요한 기능**은 팔레트에 넣지 않는다(입력독 🪟 버튼이 담당).

public struct SlashCommand: Identifiable, Equatable {
  /// 표시 이름(`/` 제외)
  public let name: String
  /// 검색 별칭(영문 포함)
  public let aliases: [String]
  /// 한 줄 설명
  public let summary: String
  /// 입력창에 채울 문장
  public let template: String
  /// SF Symbol
  public let systemImage: String
  /// 도우미 도구가 켜져 있어야 쓸 수 있는 명령인가 — 도구가 꺼져 있으면 팔레트에서 숨긴다.
  public let requiresTools: Bool

  public var id: String { name }
  public var token: String { "/" + name }

  public init(name: String, aliases: [String] = [], summary: String,
              template: String, systemImage: String, requiresTools: Bool = true) {
    self.name = name
    self.aliases = aliases
    self.summary = summary
    self.template = template
    self.systemImage = systemImage
    self.requiresTools = requiresTools
  }

  /// 검색어가 이 명령과 맞는가 — 이름·별칭·설명의 부분 일치.
  public func matches(_ query: String) -> Bool {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return true }
    if name.lowercased().contains(q) { return true }
    if aliases.contains(where: { $0.lowercased().contains(q) }) { return true }
    return summary.lowercased().contains(q)
  }
}

public enum SlashCommands {
  /// 전체 명령 — **계산 프로퍼티**다.
  ///
  /// 예전에는 `static let` 이라 처음 읽는 순간의 언어로 문구가 고정됐고(설정에서 영어로 바꿔도
  /// 팔레트만 한국어로 남았다), 도구를 꺼도 계속 보였다(2026-10-27).
  public static var all: [SlashCommand] { catalog }

  /// 지금 설정에서 쓸 수 있는 명령 — 도우미 도구가 꺼져 있으면 도구가 필요한 명령은 숨긴다.
  public static func available(agentToolsEnabled: Bool) -> [SlashCommand] {
    agentToolsEnabled ? catalog : catalog.filter { !$0.requiresTools }
  }

  private static var catalog: [SlashCommand] {
    [
    SlashCommand(
      name: "화면",
      aliases: ["screen", "screenshot", "캡처"],
      summary: L("지금 화면을 찍어서 보여 달라고 요청"),
      template: L("지금 화면을 캡처해서 보여 주세요."),
      systemImage: "camera.viewfinder"),
    SlashCommand(
      name: "창",
      aliases: ["window", "front"],
      summary: L("앞에 있는 창을 찍어서 보여 달라고 요청"),
      template: L("지금 앞에 있는 창을 캡처해서 보여 주세요."),
      systemImage: "macwindow"),
    SlashCommand(
      name: "디스크",
      aliases: ["disk", "storage", "용량"],
      summary: L("디스크 여유 공간 확인"),
      template: L("디스크 여유 공간을 확인해 주세요."),
      systemImage: "internaldrive"),
    SlashCommand(
      name: "프로세스",
      aliases: ["process", "cpu", "top"],
      summary: L("CPU를 많이 쓰는 프로세스 확인"),
      template: L("CPU를 많이 쓰는 프로세스를 알려 주세요."),
      systemImage: "chart.bar.xaxis"),
    SlashCommand(
      name: "메모리",
      aliases: ["memory", "ram"],
      summary: L("메모리(RAM) 사용량 확인"),
      template: L("메모리(RAM) 사용량을 알려 주세요."),
      systemImage: "memorychip"),
    SlashCommand(
      name: "설정",
      aliases: ["settings", "config"],
      summary: L("QuickTalk 설정·기능 확인"),
      template: L("지금 QuickTalk 설정과 켜져 있는 기능을 알려 주세요."),
      systemImage: "slider.horizontal.3",
      // 설정·도움말은 도구 없이도 된다(앱 지식은 지시문에 실린다).
      requiresTools: false),
    SlashCommand(
      name: "도움말",
      aliases: ["help", "commands"],
      summary: L("슬래시 명령 목록 보기"),
      template: L("슬래시 명령으로 무엇을 할 수 있는지 알려 주세요."),
      systemImage: "questionmark.circle",
      requiresTools: false)
    ]
  }

  /// 팔레트를 보여 줄 상태인가 — `/`로 시작하고 아직 한 줄이며 공백이 없는 **첫 토큰**일 때.
  public static func isPaletteVisible(for text: String) -> Bool {
    guard text.hasPrefix("/") else { return false }
    guard !text.contains("\n") else { return false }
    // "/화면" 처럼 명령 이름만 치는 동안 보여 준다. 문장이 이어지면 숨긴다.
    let body = text.dropFirst()
    return !body.contains(" ")
  }

  /// 현재 입력으로 거른 목록 — `toolsEnabled` 가 false 면 도구가 필요한 명령은 빠진다.
  public static func matches(_ text: String, toolsEnabled: Bool = true) -> [SlashCommand] {
    guard isPaletteVisible(for: text) else { return [] }
    let query = String(text.dropFirst())
    return available(agentToolsEnabled: toolsEnabled).filter { $0.matches(query) }
  }

  /// 입력 전체가 슬래시 명령인가 — `/화면` 또는 `/화면 지금 바로`.
  /// (전송 시점에 명령을 해석해 문장을 바꾸는 용도가 아니라, 표시·테스트용)
  public static func parse(_ text: String) -> (command: SlashCommand, argument: String)? {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("/") else { return nil }
    let parts = trimmed.dropFirst().split(separator: " ", maxSplits: 1,
                                          omittingEmptySubsequences: true)
    guard let head = parts.first else { return nil }
    let name = String(head)
    guard let command = all.first(where: {
      $0.name.caseInsensitiveCompare(name) == .orderedSame
        || $0.aliases.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame })
    }) else { return nil }
    let argument = parts.count > 1 ? String(parts[1]) : ""
    return (command, argument)
  }
}
