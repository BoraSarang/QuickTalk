import SwiftUI

// [MOCK] v0.31 대화 창 재설계 목업 — **렌더 하네스 전용**(실제 화면 미연결).
// `--demo-redesign` 으로만 그린다. 승인 뒤 실제 ContentView 로 옮긴다.
//
// 목업에서 확인하는 것
//   ① 타이틀바 = traffic light + 제목 + 비서, 나머지 버튼은 호버 시에만
//   ② 응답 = 카드 없이 전체 폭(15pt), 도구 카드는 그대로 위에
//   ③ 질문 = 꼬리 있는 말풍선, ⋯ 메뉴는 호버 시에만
//   ④ 하단 메타: 시간은 항상, 복사/읽어주기만 호버
//   ⑤ 입력독 = ＋ 도구 메뉴 하나(창 연결 · 웹 검색 · 음성 입력)
//   ⑥ QuickShelf = 대화 탭 + 새 대화

struct DesignMockView: View {
  enum Mode { case idle, hover, tools }

  let mode: Mode
  var lang: String = "ko"

  private var s: MockStrings { MockStrings(lang: lang) }
  private var isHover: Bool { mode == .hover }
  private var showsTools: Bool { mode == .tools }

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      MockTheme.background
      VStack(spacing: 0) {
        titleBar
        conversation
        composer
          .overlay(alignment: .bottomTrailing) { if showsTools { toolsMenu } }
      }
      .frame(width: 400, height: 560)
      .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
        .stroke(Color.white.opacity(0.07), lineWidth: 1))
    }
    .frame(width: 400, height: 560)
  }

  // MARK: - 타이틀바

  private var titleBar: some View {
    HStack(spacing: 7) {
      trafficLights
        .frame(width: 54, alignment: .leading)
      Text(s.title)
        .font(.system(size: 13.5, weight: .semibold))
        .foregroundColor(.white.opacity(0.92))
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(0)
      personaBadge(compact: isHover)
        .fixedSize()
        .layoutPriority(1)
      if isHover {
        toolbar
          .fixedSize()
          .layoutPriority(2)
          .transition(.opacity)
      }
    }
    .padding(.horizontal, 12)
    .frame(height: 40)
    .background {
      if isHover {
        LinearGradient(colors: [Color.white.opacity(0.07), Color.white.opacity(0.02)],
                       startPoint: .top, endPoint: .bottom)
      }
    }
    .overlay(alignment: .bottom) {
      Rectangle().fill(Color.white.opacity(isHover ? 0.06 : 0.035)).frame(height: 1)
    }
  }

  private var trafficLights: some View {
    HStack(spacing: 8) {
      Circle().fill(Color(red: 1.00, green: 0.37, blue: 0.34)).frame(width: 12, height: 12)
      Circle().fill(Color(red: 1.00, green: 0.74, blue: 0.18)).frame(width: 12, height: 12)
      Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 12, height: 12)
    }
  }

  private func personaBadge(compact: Bool) -> some View {
    HStack(spacing: 3) {
      Text(s.personaEmoji).font(.system(size: 12))
      if !compact {
        Text(s.personaName).font(.system(size: 11, weight: .medium))
          .foregroundColor(.white.opacity(0.75))
      }
    }
    .padding(.horizontal, compact ? 4 : 7).padding(.vertical, 3)
    .background(Capsule().fill(MockTheme.accent.opacity(0.16)))
    .overlay(Capsule().stroke(MockTheme.accent.opacity(0.30), lineWidth: 1))
    .fixedSize()
    .help(s.personaName)
  }

  private var toolbar: some View {
    HStack(spacing: 0) {
      mockIcon("pin")
      mockIcon("brain")
      mockIcon("bookmark")
      mockIcon("square.and.pencil")
      mockIcon("sidebar.right")
      mockIcon("ellipsis")
    }
    .padding(.horizontal, 4)
    .background(Capsule().fill(Color.white.opacity(0.06)))
  }

  private func mockIcon(_ name: String) -> some View {
    Image(systemName: name)
      .font(.system(size: 10.5, weight: .medium))
      .foregroundColor(.white.opacity(0.72))
      .frame(width: 21, height: 21)
  }

  // MARK: - 대화

  private var conversation: some View {
    VStack(alignment: .leading, spacing: 13) {
      questionRow
      toolCard
      answerBlock
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 16)
    .padding(.top, 14)
    .padding(.bottom, 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  private var questionRow: some View {
    HStack(alignment: .center, spacing: 6) {
      Spacer(minLength: 40)
      Text(s.question)
        .font(.system(size: 13.5))
        .foregroundColor(.white.opacity(0.94))
        .padding(.horizontal, 13).padding(.vertical, 9)
        .background {
          ZStack(alignment: .bottomTrailing) {
            MockBubbleTail()
              .fill(MockTheme.bubble)
              .frame(width: 13, height: 10)
              .offset(x: 4, y: 3)
            RoundedRectangle(cornerRadius: 18, style: .continuous)
              .fill(MockTheme.bubble)
          }
        }
        .fixedSize(horizontal: false, vertical: true)
      if isHover {
        Image(systemName: "ellipsis")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.white.opacity(0.40))
          .frame(width: 18, height: 18)
      }
    }
  }

  private var toolCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 5) {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 10)).foregroundColor(Color(red: 0.30, green: 0.85, blue: 0.52))
        Text("shell")
          .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
          .foregroundColor(.white.opacity(0.80))
        Text(s.toolRead)
          .font(.system(size: 9.5)).foregroundColor(.white.opacity(0.40))
        Spacer()
        Text("0.0s")
          .font(.system(size: 9.5, design: .monospaced)).foregroundColor(.white.opacity(0.35))
      }
      Text("$ psql -c \"select jobname, schedule from cron.job\"")
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundColor(.white.opacity(0.55))
        .lineLimit(1)
      Text(s.toolResult)
        .font(.system(size: 9.8, design: .monospaced))
        .foregroundColor(.white.opacity(0.38))
        .lineLimit(1)
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.white.opacity(0.045)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.white.opacity(0.07), lineWidth: 1))
  }

  private var answerBlock: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 4) {
        Text(s.personaEmoji).font(.system(size: 10))
        Text(s.personaName)
          .font(.system(size: 10.5, weight: .medium))
          .foregroundColor(.white.opacity(0.45))
      }
      MarkdownText(text: s.answer, baseSize: 15)
        .foregroundColor(.white.opacity(0.93))
        .fixedSize(horizontal: false, vertical: true)
      footer
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Text(s.meta)
        .font(.system(size: 10.5))
        .foregroundColor(.white.opacity(0.35))
      Spacer()
      if isHover {
        HStack(spacing: 4) {
          Image(systemName: "doc.on.doc")
          Image(systemName: "speaker.wave.2")
        }
        .font(.system(size: 11))
        .foregroundColor(.white.opacity(0.55))
        .padding(.horizontal, 6).padding(.vertical, 2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
      }
    }
    .frame(height: 17)
  }

  // MARK: - 입력독

  private var composer: some View {
    HStack(spacing: 8) {
      ZStack(alignment: .bottomTrailing) {
        Circle()
          .fill(MockTheme.accent.opacity(0.30))
          .overlay(Circle().stroke(MockTheme.accent.opacity(0.55), lineWidth: 1))
          .frame(width: 30, height: 30)
          .overlay(Text(s.personaEmoji).font(.system(size: 14)))
        Circle().fill(MockTheme.accent)
          .frame(width: 9, height: 9)
          .overlay(Image(systemName: "checkmark")
            .font(.system(size: 5, weight: .bold)).foregroundColor(.white))
          .offset(x: 1, y: 1)
      }
      Text(s.placeholder)
        .font(.system(size: 13))
        .foregroundColor(.white.opacity(0.32))
      Spacer(minLength: 4)
      // ＋ 도구 — 활성 상태(웹 검색)면 그 아이콘으로 바뀐다
      ZStack(alignment: .topTrailing) {
        Circle().fill(Color.white.opacity(0.08))
          .frame(width: 27, height: 27)
          .overlay(
            Image(systemName: showsTools ? "globe" : "plus")
              .font(.system(size: 11, weight: .semibold))
              .foregroundColor(showsTools ? MockTheme.accent : .white.opacity(0.70))
          )
        if showsTools {
          Circle().fill(MockTheme.accent).frame(width: 6, height: 6).offset(x: -2, y: 2)
        }
      }
      Circle().fill(MockTheme.accent)
        .frame(width: 27, height: 27)
        .overlay(Image(systemName: "arrow.up")
          .font(.system(size: 11, weight: .bold)).foregroundColor(.white))
        .opacity(0.90)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 21, style: .continuous)
      .fill(Color.white.opacity(0.065)))
    .overlay(RoundedRectangle(cornerRadius: 21, style: .continuous)
      .stroke(Color.white.opacity(0.10), lineWidth: 1))
    .padding(.horizontal, 12)
    .padding(.bottom, 12)
  }

  private var toolsMenu: some View {
    VStack(alignment: .leading, spacing: 1) {
      toolRow("macwindow.on.rectangle", s.toolWindow, s.toolWindowNote, checked: false)
      toolRow("globe", s.toolWeb, s.toolWebNote, checked: true)
      Divider().overlay(Color.white.opacity(0.08)).padding(.vertical, 2)
      toolRow("mic", s.toolVoice, s.toolVoiceNote, checked: false)
    }
    .padding(5)
    .frame(width: 232)
    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
      .fill(Color(red: 0.16, green: 0.16, blue: 0.19)))
    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
      .stroke(Color.white.opacity(0.10), lineWidth: 1))
    .shadow(color: .black.opacity(0.45), radius: 12, y: 4)
    .padding(.trailing, 46)
    .padding(.bottom, 54)
  }

  private func toolRow(_ icon: String, _ title: String, _ note: String, checked: Bool) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(checked ? MockTheme.accent : .white.opacity(0.75))
        .frame(width: 17)
      VStack(alignment: .leading, spacing: 1) {
        Text(title).font(.system(size: 11.5, weight: .medium)).foregroundColor(.white.opacity(0.90))
        Text(note).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.38))
      }
      Spacer()
      if checked {
        Image(systemName: "checkmark")
          .font(.system(size: 9, weight: .bold)).foregroundColor(MockTheme.accent)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 6)
    .contentShape(Rectangle())
  }
}

// MARK: - QuickShelf 목업

struct ShelfMockView: View {
  var lang: String = "ko"
  private var s: MockStrings { MockStrings(lang: lang) }

  var body: some View {
    VStack(spacing: 0) {
      header
      tabs
      searchRow
      newChatRow
      VStack(spacing: 4) {
        shelfRow(s.conv1, emoji: "🤖", when: s.t1, running: false, selected: true)
        shelfRow(s.conv2, emoji: "🔎", when: s.t2, running: true, selected: false)
        shelfRow(s.conv3, emoji: "🧠", when: s.t3, running: false, selected: false)
      }
      .padding(.horizontal, 10).padding(.top, 6)
      Spacer()
      footer
    }
    .frame(width: 300, height: 520)
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

  private var searchRow: some View {
    HStack(spacing: 6) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 10)).foregroundColor(.white.opacity(0.40))
      Text(s.shelfSearch).font(.system(size: 11)).foregroundColor(.white.opacity(0.30))
      Spacer()
    }
    .padding(.horizontal, 9).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.white.opacity(0.07), lineWidth: 1))
    .padding(.horizontal, 10).padding(.top, 8)
  }

  private var newChatRow: some View {
    HStack(spacing: 7) {
      Image(systemName: "plus.circle.fill")
        .font(.system(size: 13)).foregroundColor(MockTheme.accent)
      VStack(alignment: .leading, spacing: 1) {
        Text(s.newChat).font(.system(size: 11.5, weight: .semibold)).foregroundColor(.white.opacity(0.92))
        Text(s.newChatNote).font(.system(size: 9.5)).foregroundColor(.white.opacity(0.40))
      }
      Spacer()
      Text("⌘N").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.25))
    }
    .padding(.horizontal, 10).padding(.vertical, 8)
    .background(RoundedRectangle(cornerRadius: 9).fill(MockTheme.accent.opacity(0.10)))
    .overlay(RoundedRectangle(cornerRadius: 9).stroke(MockTheme.accent.opacity(0.25), lineWidth: 1))
    .padding(.horizontal, 10).padding(.top, 8)
  }

  private func shelfRow(_ title: String, emoji: String, when: String,
                        running: Bool, selected: Bool) -> some View {
    HStack(spacing: 8) {
      ZStack(alignment: .bottomTrailing) {
        Circle().fill(Color.white.opacity(0.08)).frame(width: 26, height: 26)
          .overlay(Text(emoji).font(.system(size: 12)))
        if running {
          Circle().fill(Color.green).frame(width: 8, height: 8)
            .overlay(Circle().stroke(Color(red: 0.10, green: 0.10, blue: 0.12), lineWidth: 1.5))
            .offset(x: 1, y: 1)
        }
      }
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 11.5, weight: .medium))
          .foregroundColor(.white.opacity(0.90)).lineLimit(1)
        HStack(spacing: 5) {
          if running {
            Text(s.replying).font(.system(size: 9, weight: .semibold))
              .foregroundColor(Color(red: 0.45, green: 0.90, blue: 0.60))
          }
          Text(when).font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
        }
      }
      Spacer(minLength: 0)
      if selected {
        Image(systemName: "checkmark.circle.fill")
          .font(.system(size: 10)).foregroundColor(MockTheme.accent)
      }
    }
    .padding(.horizontal, 8).padding(.vertical, 7)
    .background(RoundedRectangle(cornerRadius: 9)
      .fill(Color.white.opacity(selected ? 0.07 : 0.03)))
    .overlay(RoundedRectangle(cornerRadius: 9)
      .stroke(MockTheme.accent.opacity(selected ? 0.25 : 0), lineWidth: 1))
  }

  private var footer: some View {
    HStack {
      Text(s.shelfFooter).font(.system(size: 9)).foregroundColor(.white.opacity(0.35))
      Spacer()
    }
    .padding(.horizontal, 12).padding(.vertical, 9)
    .overlay(alignment: .top) {
      Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
    }
  }
}

// MARK: - 목업 토큰/문구

private enum MockTheme {
  static let accent = Color(red: 0.63, green: 0.52, blue: 1.0)
  static let bubble = Color(red: 0.29, green: 0.26, blue: 0.44)
  static let background = LinearGradient(
    colors: [Color(red: 0.13, green: 0.12, blue: 0.16),
             Color(red: 0.075, green: 0.075, blue: 0.095)],
    startPoint: .top, endPoint: .bottom)
}

private struct MockBubbleTail: Shape {
  func path(in rect: CGRect) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: rect.minX, y: rect.minY))
    p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                   control: CGPoint(x: rect.maxX - 1, y: rect.minY + 1))
    p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY * 0.55),
                   control: CGPoint(x: rect.minX + 1, y: rect.maxY))
    p.closeSubpath()
    return p
  }
}

private struct MockStrings {
  let lang: String
  private var ko: Bool { lang != "en" }

  var title: String { ko ? "예약 작업 리포트 정리" : "Scheduled job report" }
  var personaEmoji: String { "🤖" }
  var personaName: String { ko ? "다미" : "Dami" }
  var question: String { ko ? "전에 대화 하던거 불러와서 확인해봐" : "Pull up our last conversation" }
  var toolRead: String { ko ? "읽기" : "read" }
  var toolResult: String { ko ? "1 row · 0.031s" : "1 row · 0.031s" }
  var answer: String {
    ko
      ? "정리하면, **pgpsql 정리는 완료**되었고 리포트는 예약만 걸려 있어 아직 산출물이 없습니다. 다음 실행(11/9 월요일 21시)까지 기다리지 않고 지금 리포트를 만들거나, 예약 내용을 손보시려면 말씀해 주세요."
      : "In short, **the pgpsql cleanup is done**, but the report is only scheduled — no output yet. I can generate it now instead of waiting for the next run (Mon, Nov 9 at 21:00), or adjust the schedule if you'd like."
  }
  var meta: String { ko ? "1분 전 · 59.4초" : "1 min ago · 59.4s" }
  var placeholder: String { ko ? "무엇이든 물어보세요" : "Ask anything" }
  var toolWindow: String { ko ? "창 연결" : "Attach a window" }
  var toolWindowNote: String { ko ? "이번 질문에 창 내용을 참고" : "Use a window as context" }
  var toolWeb: String { ko ? "웹 검색" : "Web search" }
  var toolWebNote: String { ko ? "이번 질문만 검색" : "This question only" }
  var toolVoice: String { ko ? "음성 입력" : "Voice input" }
  var toolVoiceNote: String { ko ? "녹음 중지할 때까지 유지" : "Stays on until stopped" }

  // QuickShelf
  var shelf: String { ko ? "퀵셸프" : "QuickShelf" }
  var shelfChats: String { ko ? "대화" : "Chats" }
  var shelfClipboard: String { ko ? "클립보드" : "Clipboard" }
  var shelfFiles: String { ko ? "파일" : "Files" }
  var shelfCapture: String { ko ? "캡처" : "Capture" }
  var shelfSearch: String { ko ? "대화 검색" : "Search chats" }
  var newChat: String { ko ? "새 대화" : "New chat" }
  var newChatNote: String { ko ? "지금 대화는 보관함에 저장됩니다" : "Current chat is saved" }
  var shelfFooter: String { ko ? "대화는 보낼 때마다 자동 저장됩니다" : "Chats are saved automatically" }
  var conv1: String { ko ? "예약 작업 리포트 정리" : "Scheduled job report" }
  var conv2: String { ko ? "QuickShelf 캡처 정리" : "QuickShelf capture cleanup" }
  var conv3: String { ko ? "오픈소스 2천 구조 조사" : "Open-source 2k survey" }
  var t1: String { ko ? "1분 전" : "1 min ago" }
  var t2: String { ko ? "방금" : "just now" }
  var t3: String { ko ? "2시간 전" : "2 hr ago" }
  var replying: String { ko ? "응답 중" : "Replying" }
}
