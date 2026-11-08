import AppKit
import SwiftUI

/// 앱 공통 강조색 토큰 — 마크다운과 QuickShelf가 **같은 적응형 색**을 쓴다.
///
/// 고정 바이올렛 `#7A5CFF`(0.48, 0.36, 1)는 다크 배경에서 ≈3.9:1 · 라이트 배경에서 ≈4.4:1 로,
/// 12~13pt 모노 글자에 필요한 4.5:1 에 못 미쳤다(2026-11-05 사용자 지적 — "다크·라이트 둘 다 안 보인다").
/// 굵게(`**…**`)는 **색이 아니라 굵기**다 — 본문과 같은 `.primary` 를 그대로 쓴다.
enum AccentPalette {
  /// 인라인 코드 · 링크 · 인용 막대 · 완료 체크 · QuickShelf 강조 문구
  static func text(_ scheme: ColorScheme) -> Color {
    scheme == .dark
      ? Color(red: 0.80, green: 0.75, blue: 1.00)   // 라벤더 — 다크 배경에서 ≈10:1
      : Color(red: 0.40, green: 0.28, blue: 0.82)   // 진한 브랜드 퍼플 — 라이트 배경에서 ≈6.1:1
  }
}

/// AI 답변용 마크다운 렌더러 — CapsuleStash `MarkdownBody`(T-26)를 QuickTalk 토큰으로 옮긴 것.
///
/// 원문(`message.text`)은 그대로 두고 **표시만** 바꾼다. 복사는 원문, 읽어주기는 평문
/// (`MarkdownPlain.text`)을 쓴다. 파싱 결과는 `@State`에 메모해 스트리밍 중 재평가 비용을 줄인다.
struct MarkdownText: View {
  let text: String
  /// 웹 검색 출처 — 답변의 `[n]`을 클릭 가능한 링크로 표시한다.
  var sources: [TurnSource] = []
  var baseSize: CGFloat = 13
  /// 파일명만 나열된 답변에서 찾아볼 폴더(예: 지금 대화의 리포트 폴더).
  var fileDirectories: [String] = []

  @Environment(\.colorScheme) private var colorScheme
  @State private var segments: [MarkdownSegment]
  /// 인라인 코드 안의 경로를 링크로 만들 때 기준이 되는 폴더 목록.
  @State private var searchDirectories: [String] = []

  init(text: String, sources: [TurnSource] = [], baseSize: CGFloat = 13,
       fileDirectories: [String] = []) {
    self.text = text
    self.sources = sources
    self.baseSize = baseSize
    self.fileDirectories = fileDirectories
    let linked = Self.linked(text, urls: sources.map(\.url), directories: fileDirectories)
    _segments = State(initialValue: MarkdownSegment.parse(linked))
    _searchDirectories = State(initialValue: LocalFileLinks.directories(
      in: text, extraDirectories: fileDirectories))
  }

  private static func linked(_ raw: String, urls: [String], directories: [String]) -> String {
    let cited = CitationLinks.link(raw, urls: urls)
    return LocalFileLinks.link(cited, extraDirectories: directories)
  }

  private func rendered(_ raw: String, urls: [String]) -> [MarkdownSegment] {
    searchDirectories = LocalFileLinks.directories(in: raw, extraDirectories: fileDirectories)
    return MarkdownSegment.parse(Self.linked(raw, urls: urls, directories: fileDirectories))
  }

  private var base: Font { .system(size: baseSize) }
  private var mono: Font { .system(size: baseSize - 1, design: .monospaced) }
  /// 인라인 코드·링크·체크 색 — 테마(라이트/다크)에 따라 바뀐다.
  private var accent: Color { AccentPalette.text(colorScheme) }
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
    // 파일 링크는 기본 브라우저 대신 로컬에서 연다 — 위험한 형식은 확인 후.
    .environment(\.openURL, OpenURLAction { url in
      if url.isFileURL {
        LocalFileOpen.open(url)
        return .handled
      }
      return .systemAction
    })
    .onChange(of: text) { _, new in
      segments = rendered(new, urls: sources.map(\.url))
    }
    .onChange(of: sources) { _, new in
      segments = rendered(text, urls: new.map(\.url))
    }
    .onChange(of: fileDirectories) { _, _ in
      segments = rendered(text, urls: sources.map(\.url))
    }
  }

  // MARK: - 블록

  @ViewBuilder
  private func segmentView(_ segment: MarkdownSegment) -> some View {
    switch segment {
    case .heading(let level, let text):
      Self.styled(text, base: headingFont(level), accent: accent, mono: mono,
                  directories: searchDirectories)
        .foregroundColor(.primary)
        .padding(.top, level == 1 ? 4 : 2)

    case .quote(let lines):
      HStack(alignment: .top, spacing: 8) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(accent.opacity(0.55))
          .frame(width: 3)
        Self.styled(lines.joined(separator: "\n"), base: base, accent: accent, mono: mono,
                    directories: searchDirectories)
          .italic()
          .foregroundColor(muted)
      }

    case .bullet(let items):
      itemList(items, numbered: false)

    case .numbered(let items):
      itemList(items, numbered: true)

    case .code(let language, let lines):
      CodeBlockView(language: language,
                    code: lines.joined(separator: "\n"),
                    mono: mono,
                    ink: codeInk,
                    muted: muted,
                    fill: blockFill,
                    line: lineColor,
                    accent: accent)

    case .table(let header, let rows):
      tableView(header: header, rows: rows)

    case .paragraph(let lines):
      Self.styled(lines.joined(separator: "\n"), base: base, accent: accent, mono: mono,
                  directories: searchDirectories)
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
          Self.styled(item.text, base: base, accent: accent, mono: mono,
                      directories: searchDirectories)
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
                        accent: accent, mono: mono, directories: searchDirectories)
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
                          base: .system(size: baseSize - 1), accent: accent, mono: mono,
                          directories: searchDirectories)
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
  /// `directories` 가 주어지면 인라인 코드 안의 경로도 **모노 글꼴 그대로** 클릭 링크가 된다.
  static func styled(_ raw: String, base: Font, accent: Color, mono: Font,
                     directories: [String] = []) -> Text {
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
        // 인라인 코드가 실제 파일·폴더면 — 모노 글꼴을 유지한 채 링크로 만든다.
        if let url = LocalFileLinks.url(for: string, directories: directories) {
          var attributed = AttributedString(string)
          attributed.link = url
          attributed.underlineStyle = .single
          attributed.foregroundColor = accent
          result = result + Text(attributed).font(mono)
        } else {
          // Text 연결이라 배경 필은 못 넣는다 — 모노 + 색으로 구분
          result = result + Text(string).font(mono).foregroundColor(accent)
        }
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

// MARK: - 코드 블록 (복사 버튼)

/// 셸·코드 블록 — 오른쪽 위 복사 버튼으로 **블록 내용만** 클립보드에 넣는다.
private struct CodeBlockView: View {
  let language: String
  let code: String
  let mono: Font
  let ink: Color
  let muted: Color
  let fill: Color
  let line: Color
  let accent: Color

  @State private var copied = false
  @State private var hover = false

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        if !language.isEmpty {
          Text(language.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(muted)
        }
        Spacer(minLength: 0)
        Button(action: copy) {
          HStack(spacing: 4) {
            Image(systemName: copied ? "checkmark" : "doc.on.doc")
              .font(.system(size: 10, weight: .semibold))
            Text(copied ? L("복사됨") : L("복사"))
              .font(.system(size: 10, weight: .medium))
          }
          .foregroundColor(copied ? accent : muted)
          .padding(.horizontal, 7)
          .padding(.vertical, 3)
          .background(
            RoundedRectangle(cornerRadius: 5)
              .fill(Color.primary.opacity(hover ? 0.10 : 0.04))
          )
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help(L("이 코드 블록을 클립보드에 복사"))
        .accessibilityLabel(L("이 코드 블록을 클립보드에 복사"))
      }
      // 중첩 ScrollView는 채팅 스크롤과 충돌하고 렌더도 비어 나왔다 → 줄바꿈으로 보여준다
      Text(code)
        .font(mono)
        .foregroundColor(ink)
        .lineSpacing(2)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 8).fill(fill))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(line, lineWidth: 1))
  }

  private func copy() {
    let pb = NSPasteboard.general
    pb.clearContents()
    pb.setString(code, forType: .string)
    copied = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
      copied = false
    }
  }
}
