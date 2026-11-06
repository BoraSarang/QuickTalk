import Foundation

// 대화 목차(v0.32) — **화면에 그리지 않는 순수 계산**만 둔다.
//
// 목차는 사용자 질문만 모은다. 답변까지 넣으면 항목이 두 배가 되어
// 목록이 길어지고 "질문으로 점프"라는 목적이 흐려진다.
// 미리보기는 질문의 **첫 줄 40자** — 목록 폭 200pt 안에서 한 줄로 읽히는 최대치.

/// 목차 한 줄.
public struct OutlineEntry: Identifiable, Hashable, Sendable {
  /// 그 질문 턴의 ID — 점프는 이 ID로 스크롤한다.
  public let id: UUID
  /// 질문 순번(0부터) — 목록 번호·현재 위치 계산에 쓴다.
  public let index: Int
  /// 질문 첫 줄 40자(빈 본문은 "이미지"/"첨부").
  public let preview: String

  public init(id: UUID, index: Int, preview: String) {
    self.id = id
    self.index = index
    self.preview = preview
  }
}

public enum ConversationOutline {
  /// 미리보기 최대 글자 수 — 목록 한 줄에 들어가는 만큼.
  public static let previewLength = 40
  /// 이보다 적으면 목차를 띄우지 않는다(질문 2개는 스크롤 두 번이면 닿는다).
  public static let minimumQuestions = 3

  /// 대화의 사용자 질문만 목차로 만든다.
  public static func entries(from turns: [Turn]) -> [OutlineEntry] {
    var index = 0
    var result: [OutlineEntry] = []
    for turn in turns where turn.role == .user {
      result.append(OutlineEntry(id: turn.id, index: index, preview: preview(for: turn)))
      index += 1
    }
    return result
  }

  /// 질문 하나의 미리보기 — 첫 줄만, 공백 정리, 40자.
  public static func preview(for turn: Turn) -> String {
    let firstLine = turn.text
      .components(separatedBy: .newlines)
      .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }?
      .trimmingCharacters(in: .whitespaces) ?? ""
    if firstLine.isEmpty {
      let hasImage = turn.attachments.contains { $0.kind == .image }
      return hasImage ? L("이미지") : L("첨부")
    }
    return String(firstLine.prefix(previewLength))
  }

  /// 목차를 보여 줄 만한 대화인가(질문 3개 이상).
  public static func shouldShow(_ entries: [OutlineEntry]) -> Bool {
    entries.count >= minimumQuestions
  }

  /// 지금 화면 위쪽에 걸린 질문의 순번.
  ///
  /// - Parameters:
  ///   - offsets: 질문 턴 ID → 스크롤 **내용** 좌표에서의 y(스크롤과 무관하게 고정).
  ///   - anchorY: 화면 위쪽 기준선의 내용 좌표(= 스크롤 오프셋 + 여유).
  ///   - entries: 목차(턴 순서).
  /// - Returns: 기준선 위에 있는 **마지막** 질문. 하나도 없으면 0, 목차가 비면 nil.
  public static func currentIndex(offsets: [UUID: CGFloat],
                                 anchorY: CGFloat,
                                 entries: [OutlineEntry]) -> Int? {
    guard !entries.isEmpty else { return nil }
    var current = 0
    for (position, entry) in entries.enumerated() {
      guard let y = offsets[entry.id] else { continue }
      if y <= anchorY { current = position } else { break }
    }
    return current
  }

  /// 질문 검색 — 빈 문자열이면 전체, 아니면 미리보기 부분 일치(대소문자 무시).
  public static func filter(_ entries: [OutlineEntry], query: String) -> [OutlineEntry] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return entries }
    return entries.filter { $0.preview.range(of: needle,
                                             options: [.caseInsensitive, .diacriticInsensitive]) != nil }
  }
}
