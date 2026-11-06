import SwiftUI

// [MOCK] v0.32 대화 목차 · 후속 질문 제안 — 렌더 하네스 전용(실제 화면 미연결).
// `--demo-outline` 으로만 그린다. 승인 뒤 실제 ContentView 에 옮긴다.
//
// 목업에서 확인하는 것
//   ① 긴 대화에서도 방해되지 않는 **오른쪽 중앙 레일** — 평상시엔 질문 개수만큼의 눈금 + 현재 위치
//   ② 호버하면 질문 목록이 펼쳐지고, 지금 보고 있는 질문이 강조된다
//   ③ 좁은 창(380×420)에서도 레일이 대화를 과하게 가리지 않는다(폭·높이를 창에 맞춰 줄인다)
//   ④ 응답이 끝나면 그 답변 아래에 **후속 질문 칩 3개**
//   ⑤ QuickShelf 대화 탭의 **이 대화 목차** 보조 진입
//   ⑥ 설정 › 대화 에서 두 기능을 각각 켜고 끈다

struct OutlineMockView: View {
  enum Mode { case collapsed, expanded, followUps, both }

  let mode: Mode
  var lang: String = "ko"
  var width: CGFloat = 400
  var height: CGFloat = 560

  private var s: OutlineMockStrings { OutlineMockStrings(lang: lang) }
  /// `both` 는 두 기능을 함께 켠 모습 — 목차는 접힌 레일로 둔다(펼치면 칩을 가린다).
  private var showsExpanded: Bool { mode == .expanded }
  private var showsFollowUps: Bool { mode == .followUps || mode == .both }

  /// 펼친 패널 폭 — 창 폭의 55% 를 넘지 않는다(400 → 216, 380 → 208).
  private var panelWidth: CGFloat { min(216, max(190, width * 0.55)) }
  /// 펼친 패널 높이 — 창 높이에서 제목·입력독 자리를 뺀 만큼만.
  private var panelHeight: CGFloat { min(300, max(170, height - 200)) }
  /// 머리말·검색·안내가 차지하는 높이(행 제외).
  private let panelChrome: CGFloat = 98
  /// 패널 높이에 들어가는 질문 행 수(행 높이 21pt) — 넘치는 질문은 스크롤한다.
  private var visibleQuestions: Int { max(4, Int((panelHeight - panelChrome) / 22)) }
  /// 실제 구현은 펼칠 때 **현재 질문이 보이도록** 스크롤한다 — 목업도 그 창을 보여 준다.
  private var visibleRange: Range<Int> {
    let n = s.questions.count
    let count = min(visibleQuestions, n)
    let start = min(max(0, s.currentIndex - count + 3), n - count)
    return start..<(start + count)
  }
  /// 레일이 차지하는 오른쪽 여백 — **손잡이 폭만** 비운다.
  /// 펼친 패널은 잠깐 덮는 오버레이라, 그때 본문 폭을 줄이면 글자가 5자마다 끊겨 더 나쁘다.
  private var railInset: CGFloat { 34 }

  var body: some View {
    ZStack {
      MockTheme.background
      VStack(spacing: 0) {
        titleBar
        chat
      }
      rail
        .padding(.trailing, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
    .frame(width: width, height: height)
    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
      .stroke(Color.white.opacity(0.07), lineWidth: 1))
    .frame(width: width, height: height)
  }

  // MARK: - 상단

  private var titleBar: some View {
    HStack(spacing: 7) {
      HStack(spacing: 8) {
        Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
        Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
        Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.42)).frame(width: 12, height: 12)
      }
      Text(s.title)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundColor(.white.opacity(0.92))
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text("🤖 \(s.persona)")
        .font(.system(size: 10.5, weight: .medium))
        .foregroundColor(MockTheme.accent)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Capsule().fill(MockTheme.accent.opacity(0.16)))
        .overlay(Capsule().stroke(MockTheme.accent.opacity(0.30), lineWidth: 1))
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.white.opacity(0.04)).frame(height: 1)
    }
  }

  // MARK: - 대화 본문 (긴 대화의 아래쪽)

  private var chat: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(s.earlier.enumerated()), id: \.offset) { item in
          VStack(alignment: .leading, spacing: 8) {
            questionBubble(item.element.0, faded: true)
            markdownText(item.element.1, faded: true)
          }
        }
        toolCard
        questionBubble(s.qCurrent)
        markdownText(s.aCurrent)
        if showsFollowUps { followUps }
        Color.clear.frame(height: 2)
      }
      .padding(.leading, 16)
      .padding(.trailing, railInset)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .scrollIndicators(.hidden)
  }

  private var toolCard: some View {
    HStack(spacing: 7) {
      Image(systemName: "checkmark.circle.fill")
        .font(.system(size: 11))
        .foregroundColor(Color(red: 0.32, green: 0.84, blue: 0.55))
      Text("schedule_list")
        .font(.system(size: 11, weight: .medium, design: .monospaced))
        .foregroundColor(.white.opacity(0.82))
      Spacer(minLength: 6)
      Text("1 row · 0.031s")
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white.opacity(0.38))
    }
    .padding(.horizontal, 10).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.045)))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.07), lineWidth: 1))
  }

  private func questionBubble(_ text: String, faded: Bool = false) -> some View {
    HStack {
      Spacer(minLength: 40)
      Text(text)
        .font(.system(size: 13.5))
        .lineSpacing(2)
        .lineLimit(2)
        .foregroundColor(.white.opacity(faded ? 0.62 : 0.94))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
          .fill(MockTheme.accent.opacity(faded ? 0.10 : 0.18)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
          .stroke(MockTheme.accent.opacity(faded ? 0.12 : 0.20), lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }
  }

  /// 실제 앱은 마크다운을 그린다 — 목업도 `**굵게**` 를 그대로 보이지 않게 파싱한다.
  private func markdownText(_ text: String, faded: Bool = false) -> some View {
    let attributed = (try? AttributedString(
      markdown: text,
      options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
      ?? AttributedString(text)
    return Text(attributed)
      .font(.system(size: 14.5))
      .lineSpacing(3)
      .lineLimit(faded ? 2 : nil)
      .foregroundColor(.white.opacity(faded ? 0.55 : 0.88))
      .fixedSize(horizontal: false, vertical: true)
      .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var followUps: some View {
    VStack(alignment: .trailing, spacing: 6) {
      HStack(spacing: 4) {
        Image(systemName: "sparkles")
          .font(.system(size: 9.5))
        Text(s.followLabel)
          .font(.system(size: 10))
      }
      .foregroundColor(.white.opacity(0.38))
      ForEach(s.followUps, id: \.self) { chip in
        Text(chip)
          .font(.system(size: 11.5))
          .lineLimit(1)
          .foregroundColor(.white.opacity(0.86))
          .padding(.horizontal, 11).padding(.vertical, 6)
          .background(Capsule().fill(MockTheme.accent.opacity(0.10)))
          .overlay(Capsule().stroke(MockTheme.accent.opacity(0.28), lineWidth: 1))
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.top, 2)
  }

  // MARK: - 오른쪽 목차 레일

  private var rail: some View {
    HStack(alignment: .center, spacing: 0) {
      if showsExpanded { outlinePanel }
      if !showsExpanded { railHandle }
    }
  }

  /// 평상시 — 질문 개수만큼의 눈금 + 지금 보고 있는 위치(보라색 막대).
  /// 3줄 손잡이보다 정보가 많고, 폭은 22pt 뿐이라 대화를 가리지 않는다.
  private var railHandle: some View {
    VStack(spacing: 3) {
      ForEach(0..<12, id: \.self) { index in
        Capsule()
          .fill(index == s.currentIndex ? MockTheme.accent : Color.white.opacity(0.30))
          .frame(width: index == s.currentIndex ? 4 : 2,
                 height: index == s.currentIndex ? 12 : 2)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 9)
    .background(Capsule().fill(.ultraThinMaterial))
    .overlay(Capsule().fill(Color(red: 0.12, green: 0.11, blue: 0.15).opacity(0.55)))
    .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
  }

  /// 펼친 목차 — 현재 질문 강조 + 질문이 많으면 검색.
  private var outlinePanel: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Text(s.outlineTitle)
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white.opacity(0.86))
        Spacer(minLength: 4)
        Text(s.count)
          .font(.system(size: 9.5, design: .monospaced))
          .foregroundColor(.white.opacity(0.45))
          .padding(.horizontal, 5).padding(.vertical, 1)
          .background(Capsule().fill(Color.white.opacity(0.08)))
      }
      searchField
      VStack(alignment: .leading, spacing: 1) {
        ForEach(Array(s.questions[visibleRange].enumerated()), id: \.offset) { item in
          outlineRow(visibleRange.lowerBound + item.offset, item.element)
        }
      }
      .frame(height: CGFloat(visibleRange.count) * 22, alignment: .top)
      .clipped()
      HStack(spacing: 4) {
        Text(s.outlineHint)
        Spacer(minLength: 0)
        if s.questions.count > visibleRange.upperBound {
          Text(s.moreCount(s.questions.count - visibleRange.upperBound))
        }
      }
      .font(.system(size: 9))
      .foregroundColor(.white.opacity(0.32))
    }
    .padding(10)
    .frame(width: panelWidth, height: CGFloat(visibleRange.count) * 22 + panelChrome,
           alignment: .topLeading)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.ultraThinMaterial))
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(Color(red: 0.11, green: 0.10, blue: 0.14).opacity(0.82)))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .stroke(Color.white.opacity(0.10), lineWidth: 1))
    .shadow(color: .black.opacity(0.32), radius: 12, y: 6)
  }

  private var searchField: some View {
    HStack(spacing: 5) {
      Image(systemName: "magnifyingglass").font(.system(size: 9))
      Text(s.search).font(.system(size: 10))
      Spacer(minLength: 0)
    }
    .foregroundColor(.white.opacity(0.32))
    .padding(.horizontal, 7).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.white.opacity(0.06), lineWidth: 1))
  }

  private func outlineRow(_ index: Int, _ text: String) -> some View {
    let current = index == s.currentIndex
    return HStack(spacing: 5) {
      Circle()
        .fill(current ? MockTheme.accent : Color.white.opacity(0.16))
        .frame(width: 4, height: 4)
      Text(text)
        .font(.system(size: 10.5, weight: current ? .semibold : .regular))
        .lineLimit(1)
        .truncationMode(.tail)
        .foregroundColor(current ? .white.opacity(0.95) : .white.opacity(0.62))
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 6).padding(.vertical, 4)
    .background(RoundedRectangle(cornerRadius: 6)
      .fill(current ? MockTheme.accent.opacity(0.20) : Color.clear))
  }
}

// MARK: - QuickShelf 목차 목업

struct OutlineShelfMockView: View {
  var lang: String = "ko"
  private var s: OutlineMockStrings { OutlineMockStrings(lang: lang) }

  var body: some View {
    VStack(spacing: 0) {
      header
      tabs
      VStack(alignment: .leading, spacing: 6) {
        HStack(spacing: 6) {
          Text(s.outlineTitle)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.white.opacity(0.88))
          Text(s.count)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(.white.opacity(0.45))
            .padding(.horizontal, 5).padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.08)))
          Spacer()
          Image(systemName: "chevron.up")
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.white.opacity(0.40))
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)

        searchField

        VStack(spacing: 2) {
          ForEach(Array(s.questions.prefix(6).enumerated()), id: \.offset) { item in
            row(item.offset, item.element)
          }
        }
        .padding(.horizontal, 8)
        Text(s.more)
          .font(.system(size: 9.5))
          .foregroundColor(.white.opacity(0.34))
          .padding(.horizontal, 12)
        Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 4)
        Text(s.recent)
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundColor(.white.opacity(0.40))
          .padding(.horizontal, 12)
        VStack(spacing: 3) {
          shelfRow(s.conv1, emoji: "🤖", when: s.t1, running: false, selected: true)
          shelfRow(s.conv2, emoji: "🔎", when: s.t2, running: true, selected: false)
        }
        .padding(.horizontal, 8)
      }
      Spacer(minLength: 0)
      footer
    }
    .frame(width: 320, height: 600)
    .background(
      ZStack {
        Rectangle().fill(.ultraThinMaterial)
        Color(red: 0.10, green: 0.10, blue: 0.12).opacity(0.86)
      }
    )
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
      .stroke(Color.white.opacity(0.10), lineWidth: 1))
  }

  private var header: some View {
    HStack(spacing: 7) {
      Text(s.shelf)
        .font(.system(size: 11.5, weight: .heavy))
        .foregroundColor(MockTheme.accent)
      Circle().fill(Color.green).frame(width: 6, height: 6)
      Text("0")
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.white.opacity(0.45))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(Capsule().fill(Color.white.opacity(0.07)))
      Spacer()
      Image(systemName: "gearshape").font(.system(size: 12)).foregroundColor(.white.opacity(0.55))
      Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundColor(.white.opacity(0.55))
    }
    .padding(.horizontal, 12).padding(.vertical, 10)
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
  }

  private var tabs: some View {
    HStack(spacing: 4) {
      shelfTab(s.shelfChats, count: "3", on: true)
      shelfTab(s.shelfClipboard, count: "0", on: false)
      shelfTab(s.shelfFiles, count: "0", on: false)
      shelfTab(s.shelfCapture, count: "0", on: false)
    }
    .padding(.horizontal, 10).padding(.top, 8)
  }

  private func shelfTab(_ title: String, count: String, on: Bool) -> some View {
    HStack(spacing: 3) {
      Text(title).font(.system(size: 9.5, weight: on ? .semibold : .regular))
      Text(count)
        .font(.system(size: 8.5, design: .monospaced))
        .padding(.horizontal, 3.5).padding(.vertical, 1)
        .background(Capsule().fill(Color.white.opacity(on ? 0.16 : 0.07)))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
    .foregroundColor(on ? MockTheme.accent : .white.opacity(0.45))
    .background(RoundedRectangle(cornerRadius: 8)
      .fill(Color.white.opacity(on ? 0.10 : 0.035)))
    .overlay(RoundedRectangle(cornerRadius: 8)
      .stroke(MockTheme.accent.opacity(on ? 0.55 : 0), lineWidth: 1))
  }

  private var searchField: some View {
    HStack(spacing: 5) {
      Image(systemName: "magnifyingglass").font(.system(size: 9))
      Text(s.search).font(.system(size: 10))
      Spacer()
    }
    .foregroundColor(.white.opacity(0.30))
    .padding(.horizontal, 8).padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.06), lineWidth: 1))
    .padding(.horizontal, 10)
  }

  private func row(_ index: Int, _ text: String) -> some View {
    let current = index == s.currentIndex
    return HStack(spacing: 6) {
      Text("\(index + 1)")
        .font(.system(size: 8.5, design: .monospaced))
        .foregroundColor(.white.opacity(0.30))
        .frame(width: 14, alignment: .trailing)
      Text(text)
        .font(.system(size: 10.5, weight: current ? .semibold : .regular))
        .lineLimit(1)
        .foregroundColor(current ? .white.opacity(0.95) : .white.opacity(0.64))
      Spacer(minLength: 0)
      if current {
        Text(s.now)
          .font(.system(size: 8.5))
          .foregroundColor(MockTheme.accent)
      }
    }
    .padding(.horizontal, 6).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 7)
      .fill(current ? MockTheme.accent.opacity(0.16) : Color.clear))
  }

  private func shelfRow(_ title: String, emoji: String, when: String,
                        running: Bool, selected: Bool) -> some View {
    HStack(spacing: 7) {
      ZStack(alignment: .bottomTrailing) {
        Circle().fill(Color.white.opacity(0.08)).frame(width: 24, height: 24)
          .overlay(Text(emoji).font(.system(size: 11)))
        if running {
          Circle().fill(Color.green).frame(width: 7, height: 7)
            .overlay(Circle().stroke(Color(red: 0.10, green: 0.10, blue: 0.12), lineWidth: 1.5))
            .offset(x: 1, y: 1)
        }
      }
      Text(title)
        .font(.system(size: 11, weight: selected ? .semibold : .regular))
        .foregroundColor(.white.opacity(selected ? 0.92 : 0.70))
        .lineLimit(1)
      Spacer(minLength: 4)
      Text(when).font(.system(size: 9)).foregroundColor(.white.opacity(0.32))
    }
    .padding(.horizontal, 7).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 8)
      .fill(Color.white.opacity(selected ? 0.05 : 0.02)))
  }

  private var footer: some View {
    Text(s.shelfFooter)
      .font(.system(size: 9))
      .foregroundColor(.white.opacity(0.30))
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
      .overlay(alignment: .top) {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
      }
  }
}

// MARK: - 설정 목업

struct OutlineSettingsMockView: View {
  var lang: String = "ko"
  private var s: OutlineMockStrings { OutlineMockStrings(lang: lang) }

  private var tabs: [String] {
    lang == "en"
      ? ["General", "Conversation", "Shortcuts", "AI", "Search", "Tools", "Assistant",
         "Voice", "QuickShelf", "About"]
      : ["일반", "대화", "단축키", "AI", "검색", "도구·권한", "비서", "음성", "퀵셸프", "정보"]
  }
  private let icons = ["gearshape", "bubble.left.and.bubble.right", "keyboard", "brain",
                       "globe", "hammer", "person.2", "mic", "sidebar.right", "info.circle"]

  var body: some View {
    HStack(spacing: 0) {
      sidebar
      detail
    }
    .frame(width: 560, height: 600)
    .background(Color(red: 0.115, green: 0.115, blue: 0.135))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .stroke(Color.white.opacity(0.08), lineWidth: 1))
  }

  private var sidebar: some View {
    VStack(alignment: .leading, spacing: 2) {
      ForEach(Array(tabs.enumerated()), id: \.offset) { item in
        HStack(spacing: 7) {
          Image(systemName: icons[item.offset]).font(.system(size: 12)).frame(width: 18)
          Text(item.element).font(.system(size: 11.5))
          Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6)
          .fill(item.offset == 1 ? MockTheme.accent.opacity(0.16) : Color.clear))
        .foregroundColor(item.offset == 1 ? MockTheme.accent : .white.opacity(0.66))
      }
      Spacer()
    }
    .padding(10)
    .frame(width: 148)
    .background(Color.white.opacity(0.03))
  }

  private var detail: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 14) {
        HStack(spacing: 6) {
          Image(systemName: "bubble.left.and.bubble.right")
            .font(.system(size: 12))
            .foregroundColor(MockTheme.accent)
          Text(lang == "en" ? "Conversation" : "대화")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white.opacity(0.92))
        }
        Text(s.settingsHelp)
          .font(.system(size: 10.5))
          .foregroundColor(.white.opacity(0.50))
          .fixedSize(horizontal: false, vertical: true)
          .padding(9)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 8).fill(MockTheme.accent.opacity(0.08)))
          .overlay(RoundedRectangle(cornerRadius: 8).stroke(MockTheme.accent.opacity(0.18), lineWidth: 1))

        group(s.outlineGroup) {
          VStack(spacing: 8) {
            pickerRow(s.outlineMode, value: s.outlineModeValue)
            toggleRow(s.outlinePosition, on: true)
            caption(s.outlineCaption)
          }
        }
        group(s.followGroup) {
          VStack(spacing: 8) {
            toggleRow(s.followToggle, on: true)
            pickerRow(s.followSource, value: s.followSourceValue)
            toggleRow(s.followSend, on: true)
            caption(s.followCaption)
          }
        }
        Spacer(minLength: 0)
      }
      .padding(16)
    }
  }

  private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.system(size: 11, weight: .semibold))
        .foregroundColor(.white.opacity(0.82))
        .padding(.leading, 10)
      VStack(alignment: .leading, spacing: 8) { content() }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.06), lineWidth: 1))
    }
  }

  private func toggleRow(_ label: String, on: Bool) -> some View {
    HStack {
      Text(label).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.82))
      Spacer()
      Capsule()
        .fill(on ? MockTheme.accent : Color.white.opacity(0.16))
        .frame(width: 30, height: 17)
        .overlay(alignment: on ? .trailing : .leading) {
          Circle().fill(.white).frame(width: 13, height: 13).padding(2)
        }
    }
  }

  private func pickerRow(_ label: String, value: String) -> some View {
    HStack {
      Text(label).font(.system(size: 11.5)).foregroundColor(.white.opacity(0.82))
      Spacer()
      HStack(spacing: 4) {
        Text(value).font(.system(size: 10.5)).foregroundColor(.white.opacity(0.78))
        Image(systemName: "chevron.up.chevron.down").font(.system(size: 7))
          .foregroundColor(.white.opacity(0.35))
      }
      .padding(.horizontal, 8).padding(.vertical, 4)
      .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.07)))
      .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.08), lineWidth: 1))
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.system(size: 9.5))
      .foregroundColor(.white.opacity(0.40))
      .fixedSize(horizontal: false, vertical: true)
  }
}

// MARK: - 문구

struct OutlineMockStrings {
  let lang: String
  private var ko: Bool { lang != "en" }

  var title: String { ko ? "예약 작업 리포트 정리" : "Scheduled job report" }
  var persona: String { ko ? "다미" : "Dami" }

  /// 긴 대화의 앞부분 — 위로 스크롤된 상태를 보여 준다.
  var earlier: [(String, String)] {
    ko
      ? [("이번 주 예약 작업 상태 알려줘",
          "이번 주 예약 작업은 **4건** 모두 실행됐습니다. 성공 3건, 실패 1건입니다. 리포트는 아직 만들지 않았습니다."),
         ("리포트가 아직 없는 이유는?",
          "리포트 생성은 마지막 작업이 끝난 뒤에 돌도록 예약되어 있습니다. 실패한 작업이 재시도 대기 중이라 아직 시작하지 않았습니다.")]
      : [("Weekly scheduled job status",
          "All **four** scheduled jobs ran this week: three succeeded and one failed. The report has not been generated yet."),
         ("Why is there no report yet?",
          "Report generation runs after the last job finishes. It has not started because the failed job is waiting to retry.")]
  }

  var qCurrent: String { ko ? "실패한 작업만 모아서 이유도 알려줘" : "Show only the failed jobs and why" }
  var aCurrent: String {
    ko
      ? "이번 주 실패는 **1건**입니다. `pgpsql` 정리 작업이 11/5 21:00에 권한 오류로 멈췄고, 이후 재시도는 없었습니다. 나머지 3건은 정상 완료됐습니다."
      : "There was **one** failure this week. The `pgpsql` cleanup stopped at 21:00 on Nov 5 with a permission error and was not retried. The other three jobs completed."
  }

  var questions: [String] {
    ko
      ? ["이번 주 예약 작업 상태 알려줘",
         "pgpsql 정리 결과는?",
         "리포트가 아직 없는 이유는?",
         "다음 실행 일정은?",
         "지금 리포트를 바로 만들어줘",
         "예약 시간을 21시로 바꿔줘",
         "지난주 리포트와 비교해줘",
         "실패한 작업만 모아서 이유도 알려줘",
         "오류 로그도 같이 보여줘",
         "리포트 파일은 어디에 저장돼?",
         "폴더 권한을 다시 승인할까?",
         "요약해서 세 줄로 정리해줘"]
      : ["Weekly scheduled job status",
         "What did the pgpsql cleanup return?",
         "Why is there no report yet?",
         "When is the next run?",
         "Generate the report now",
         "Change the schedule to 21:00",
         "Compare with last week's report",
         "Show only failed jobs and why",
         "Show the error log too",
         "Where is the report saved?",
         "Should I re-approve the folder?",
         "Summarize in three lines"]
  }
  var currentIndex: Int { 7 }
  var count: String { ko ? "12개" : "12" }
  var outlineTitle: String { ko ? "대화 목차" : "Outline" }
  var outlineHint: String { ko ? "클릭하면 그 질문으로 이동" : "Click to jump" }
  func moreCount(_ n: Int) -> String { ko ? "아래 \(n)개 더" : "\(n) more below" }
  var search: String { ko ? "질문 검색" : "Search questions" }
  var now: String { ko ? "지금" : "Now" }
  var more: String { ko ? "6개 더 보기" : "Show 6 more" }
  var recent: String { ko ? "최근 대화" : "Recent chats" }
  var shelf: String { ko ? "퀵셸프" : "QuickShelf" }
  var shelfChats: String { ko ? "대화" : "Chats" }
  var shelfClipboard: String { ko ? "클립보드" : "Clipboard" }
  var shelfFiles: String { ko ? "파일" : "Files" }
  var shelfCapture: String { ko ? "캡처" : "Capture" }
  var shelfFooter: String { ko ? "목차는 이 대화에만 적용됩니다" : "Outline applies to this chat" }
  var conv1: String { ko ? "예약 작업 리포트 정리" : "Scheduled job report" }
  var conv2: String { ko ? "QuickShelf 캡처 정리" : "QuickShelf capture cleanup" }
  var t1: String { ko ? "1분 전" : "1 min ago" }
  var t2: String { ko ? "방금" : "just now" }

  var followLabel: String { ko ? "이어서 물어보기" : "Ask next" }
  var followUps: [String] {
    ko
      ? ["권한 오류는 어떻게 고쳐?", "실패한 작업을 다시 예약해줘", "이번 주 리포트를 바로 만들어줘"]
      : ["How do I fix the permission error?", "Reschedule the failed job", "Generate this week's report now"]
  }

  var settingsHelp: String {
    ko
      ? "긴 대화에서 질문을 빠르게 찾고, 응답 뒤에 이어질 질문을 제안합니다."
      : "Jump between questions in long chats, and get suggested follow-ups after each answer."
  }
  var outlineGroup: String { ko ? "대화 목차" : "Conversation outline" }
  var outlineMode: String { ko ? "표시 방식" : "Show as" }
  var outlineModeValue: String { ko ? "플로팅 레일" : "Floating rail" }
  var outlinePosition: String { ko ? "현재 위치 표시" : "Show current position" }
  var outlineCaption: String {
    ko
      ? "질문만 모아 보여 줍니다. 레일을 누르거나 마우스를 올리면 목록이 펼쳐지고, 클릭하면 그 질문으로 이동합니다. 퀵셸프를 고르면 대화 탭 위에 목차가 붙습니다."
      : "Lists your questions only. Hover or click the rail to expand and jump. Choose QuickShelf to show it above the chat list."
  }
  var followGroup: String { ko ? "후속 질문 제안" : "Follow-up suggestions" }
  var followToggle: String { ko ? "응답이 끝나면 3개 제안" : "Suggest 3 follow-ups" }
  var followSource: String { ko ? "생성 방식" : "Source" }
  var followSourceValue: String { ko ? "모델로 생성 (권장)" : "Model (recommended)" }
  var followSend: String { ko ? "클릭하면 바로 전송" : "Send on click" }
  var followCaption: String {
    ko
      ? "응답이 끝난 뒤 2.5초 동안 새 질문이 없을 때만 만듭니다. 실패하면 무료 문구로 대체하고, 짧은 답변·오류 응답에는 표시하지 않습니다."
      : "Generated only after 2.5s of idle time. Falls back to free templates, and hides for short or failed answers."
  }
}
