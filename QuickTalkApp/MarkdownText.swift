import SwiftUI

/// AI 답변용 마크다운 렌더러 — CapsuleStash `MarkdownBody`(T-26)를 QuickTalk 토큰으로 옮긴 것.
///
/// 원문(`message.text`)은 그대로 두고 **표시만** 바꾼다. 복사는 원문, 읽어주기는 평문
/// (`MarkdownPlain.text`)을 쓴다. 파싱 결과는 `@State`에 메모해 스트리밍 중 재평가 비용을 줄인다.
struct MarkdownText: View {
  let text: String
  /// 웹 검색 출처 — 답변의 `[n]`을 클릭 가능한 링크로 표시한다.
  var sources: [TurnSource] = []
  var baseSize: CGFloat = 13

  @State private var segments: [MarkdownSegment]

  init(text: String, sources: [TurnSource] = [], baseSize: CGFloat = 13) {
    self.text = text
    self.sources = sources
    self.baseSize = baseSize
    _segments = State(initialValue: MarkdownSegment.parse(
      CitationLinks.link(text, urls: sources.map(\.url))))
  }

  private func rendered(_ raw: String, urls: [String]) -> [MarkdownSegment] {
    MarkdownSegment.parse(CitationLinks.link(raw, urls: urls))
  }

  private var base: Font { .system(size: baseSize) }
  private var mono: Font { .system(size: baseSize - 1, design: .monospaced) }
  private let accent = Color(red: 0.48, green: 0.36, blue: 1)
  private var muted: Color { .secondary }
  /// 코드 글자 — 라이트/다크 모두에서 읽히게 의미 색(모노 글꼴로 이미 구분된다)
  private var codeInk: Color { .primary }
  /// 블록 배경·테두리도 의미 색 기반(고정 RGBA는 라이트 모드에서 안 읽힌다)
  private var blockFill: Color { Color.primary.opacity(0.06) }
  private var lineColor: Color { Color.primary.opacity(0.14) }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
        segmentView(segment)
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .textSelection(.enabled)
    .onChange(of: text) { _, new in
      segments = rendered(new, urls: sources.map(\.url))
    }
    .onChange(of: sources) { _, new in
      segments = rendered(text, urls: new.map(\.url))
    }
  }

  // MARK: - 블록

  @ViewBuilder
  private func segmentView(_ segment: MarkdownSegment) -> some View {
    switch segment {
    case .heading(let level, let text):
      Self.styled(text, base: headingFont(level), accent: accent, mono: mono)
        .foregroundColor(.primary)
        .padding(.top, level == 1 ? 4 : 2)

    case .quote(let lines):
      HStack(alignment: .top, spacing: 8) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(accent.opacity(0.55))
          .frame(width: 3)
        Self.styled(lines.joined(separator: "\n"), base: base, accent: accent, mono: mono)
          .italic()
          .foregroundColor(muted)
      }

    case .bullet(let items):
      itemList(items, numbered: false)

    case .numbered(let items):
      itemList(items, numbered: true)

    case .code(let language, let lines):
      VStack(alignment: .leading, spacing: 5) {
        if !language.isEmpty {
          Text(language.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(muted)
        }
        // 중첩 ScrollView는 채팅 스크롤과 충돌하고 렌더도 비어 나왔다 → 줄바꿈으로 보여준다
        Text(lines.joined(separator: "\n"))
          .font(mono)
          .foregroundColor(codeInk)
          .lineSpacing(2)
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(10)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8).fill(blockFill))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(lineColor, lineWidth: 1))

    case .table(let header, let rows):
      tableView(header: header, rows: rows)

    case .paragraph(let lines):
      Self.styled(lines.joined(separator: "\n"), base: base, accent: accent, mono: mono)
        .foregroundColor(.primary)
        .lineSpacing(3)

    case .rule:
      Rectangle().fill(lineColor).frame(height: 1)

    case .blank:
      Spacer(minLength: 2).frame(height: 2)
    }
  }

  private func headingFont(_ level: Int) -> Font {
    switch level {
    case 1: return .system(size: baseSize + 4, weight: .bold)
    case 2: return .system(size: baseSize + 2, weight: .bold)
    default: return .system(size: baseSize + 0.5, weight: .semibold)
    }
  }

  /// 목록 — 들여쓰기 깊이만큼 밀고, 단계별로 다른 불릿을 쓴다.
  private func itemList(_ items: [MarkdownItem], numbered: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(Array(items.enumerated()), id: \.offset) { index, item in
        HStack(alignment: .firstTextBaseline, spacing: 6) {
          if let task = item.task {
            Text(task ? "☑" : "☐")
              .font(base)
              .foregroundColor(task ? accent : muted)
              .frame(minWidth: 8, alignment: .trailing)
          } else {
            Text(numbered ? "\(index + 1)." : bullet(for: item.depth))
              .font(numbered ? base.monospacedDigit() : base)
              .foregroundColor(muted)
              .frame(minWidth: numbered ? 16 : 8, alignment: .trailing)
          }
          Self.styled(item.text, base: base, accent: accent, mono: mono)
            .foregroundColor(.primary)
        }
        .padding(.leading, CGFloat(item.depth) * 14)
      }
    }
  }

  private func bullet(for depth: Int) -> String {
    switch depth {
    case 0: return "•"
    case 1: return "◦"
    default: return "▪"
    }
  }

  // MARK: - 표 (행 60개까지만 — 거대 표에서 레이아웃이 멈추지 않게)

  private func tableView(header: [String], rows: [[String]]) -> some View {
    let columnCount = max(header.count, rows.map(\.count).max() ?? 0)
    let shown = Array(rows.prefix(60))
    return VStack(spacing: 0) {
      Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
        GridRow {
          ForEach(0..<max(columnCount, 1), id: \.self) { index in
            Self.styled(index < header.count ? header[index] : "",
                        base: .system(size: baseSize - 1, weight: .semibold),
                        accent: accent, mono: mono)
              .foregroundColor(.primary)
              .padding(.horizontal, 9)
              .padding(.vertical, 5)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .background(blockFill)
        Rectangle().fill(lineColor).frame(height: 1)
        ForEach(shown.indices, id: \.self) { rowIndex in
          GridRow {
            ForEach(0..<max(columnCount, 1), id: \.self) { colIndex in
              Self.styled(colIndex < shown[rowIndex].count ? shown[rowIndex][colIndex] : "",
                          base: .system(size: baseSize - 1), accent: accent, mono: mono)
                .foregroundColor(.primary)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
          if rowIndex < shown.count - 1 {
            Rectangle().fill(lineColor.opacity(0.6)).frame(height: 1)
          }
        }
      }
      if rows.count > shown.count {
        Text(Lf("외 %d줄", rows.count - shown.count))
          .font(.system(size: 11))
          .foregroundColor(muted)
          .padding(.vertical, 5)
      }
    }
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(lineColor, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 7))
    .textSelection(.enabled)
  }

  // MARK: - 인라인

  /// `**굵게**` · `*기울임*` · `` `코드` `` · `[라벨](주소)` 을 `Text`로 잇는다.
  static func styled(_ raw: String, base: Font, accent: Color, mono: Font) -> Text {
    var result = Text("")
    for token in MarkdownInline.tokenize(raw) {
      switch token {
      case .plain(let string):
        result = result + Text(string).font(base)
      case .bold(let string):
        result = result + Text(string).font(base).fontWeight(.bold)
      case .italic(let string):
        result = result + Text(string).font(base).italic()
      case .code(let string):
        // Text 연결이라 배경 필은 못 넣는다 — 모노 + 색으로 구분
        result = result + Text(string).font(mono).foregroundColor(accent)
      case .link(let label, let url):
        var attributed = AttributedString(label)
        if let parsed = URL(string: url) {
          attributed.link = parsed
        }
        attributed.underlineStyle = .single
        attributed.foregroundColor = accent
        result = result + Text(attributed).font(base)
      }
    }
    return result
  }
}
