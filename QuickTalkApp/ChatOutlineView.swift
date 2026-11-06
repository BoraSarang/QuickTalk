import SwiftUI

// 대화 목차(v0.32) — 오른쪽 가운데 **눈금 레일** + 펼친 **목록 패널**.
//
// 설계 원칙
//   ① 평상시에는 폭 22pt 의 눈금만 둔다 — 질문 수만큼 점을 찍고, 지금 읽는 질문은 보라색 막대로.
//   ② 마우스를 0.35초 올리거나 누르면 왼쪽으로 목록이 펼쳐진다(누르면 고정, Esc 로 닫기).
//   ③ 패널은 **오버레이**다 — 펼쳐도 대화 본문 폭이 변하지 않는다(글자가 다시 접히지 않게).
//   ④ 좁은 창에서도 대화를 과하게 가리지 않도록 폭·높이를 창 크기에 맞춰 줄인다.
//
// 질문 추출·현재 위치 계산·검색은 Core(`ConversationOutline`)가 맡고, 여기서는 그리기만 한다.

struct ChatOutlineRail: View {
  let entries: [OutlineEntry]
  let currentIndex: Int
  let showsPosition: Bool
  /// 대화 영역의 크기 — 패널 폭·높이를 여기에 맞춘다.
  let availableWidth: CGFloat
  let availableHeight: CGFloat
  /// 질문을 골랐다 — ContentView 가 그 턴으로 스크롤한다.
  let onSelect: (OutlineEntry) -> Void
  /// QA 렌더 전용 — 처음부터 펼친 상태로 그린다(실사용은 호버·클릭으로 연다).
  var initiallyExpanded = false

  @State private var expanded = false
  /// 클릭으로 고정했는가 — 고정 중에는 마우스가 떠나도 접히지 않는다.
  @State private var pinned = false
  @State private var query = ""
  @State private var hoverTask: Task<Void, Never>?

  init(entries: [OutlineEntry], currentIndex: Int, showsPosition: Bool,
       availableWidth: CGFloat, availableHeight: CGFloat,
       onSelect: @escaping (OutlineEntry) -> Void,
       initiallyExpanded: Bool = false) {
    self.entries = entries
    self.currentIndex = currentIndex
    self.showsPosition = showsPosition
    self.availableWidth = availableWidth
    self.availableHeight = availableHeight
    self.onSelect = onSelect
    self.initiallyExpanded = initiallyExpanded
    _expanded = State(initialValue: initiallyExpanded)
    _pinned = State(initialValue: initiallyExpanded)
  }

  /// 패널 폭 — 창 폭의 55% 를 넘지 않는다(400 → 216, 380 → 209).
  private var panelWidth: CGFloat {
    min(216, max(170, availableWidth * 0.55))
  }
  /// 패널 높이 — 대화 영역에서 머리말·입력독 자리를 뺀 만큼만.
  private var panelHeight: CGFloat {
    min(300, max(150, availableHeight - 120))
  }

  private var filtered: [OutlineEntry] {
    ConversationOutline.filter(entries, query: query)
  }

  /// 레일 눈금이 가리키는 질문 번호 — 질문이 많으면 18개로 균등 샘플링한다.
  private var tickPositions: [Int] {
    let maxTicks = 18
    guard entries.count > maxTicks else { return Array(0..<entries.count) }
    return (0..<maxTicks).map { i in
      Int((Double(i) * Double(entries.count - 1) / Double(maxTicks - 1)).rounded())
    }
  }

  /// 지금 읽는 질문에 가장 가까운 눈금 위치.
  private var currentTickPosition: Int? {
    guard showsPosition, !entries.isEmpty else { return nil }
    let clamped = min(max(0, currentIndex), entries.count - 1)
    guard entries.count > 18 else { return clamped }
    return tickPositions.enumerated()
      .min { abs($0.element - clamped) < abs($1.element - clamped) }?
      .offset
  }

  var body: some View {
    HStack(alignment: .center, spacing: 0) {
      if expanded { panel } else { railHandle }
    }
    .onHover { inside in
      if inside { scheduleExpand() } else { scheduleCollapse() }
    }
    .background {
      // 펼친 동안 Esc 로 닫는다(입력창이 포커스여도 동작하도록 숨은 버튼).
      if expanded {
        Button("") { collapse(force: true) }
          .keyboardShortcut(.escape, modifiers: [])
          .buttonStyle(.plain)
          .frame(width: 0, height: 0)
          .opacity(0)
          .accessibilityHidden(true)
      }
    }
    .animation(.easeInOut(duration: 0.16), value: expanded)
    .onAppear {
      if initiallyExpanded {
        expanded = true
        pinned = true
      }
    }
  }

  // MARK: - 접힌 레일

  /// 평상시 — 질문 수만큼의 눈금 + 지금 읽는 위치(보라색 막대). 폭 22pt.
  private var railHandle: some View {
    VStack(spacing: 3) {
      ForEach(Array(tickPositions.enumerated()), id: \.offset) { item in
        let current = item.offset == currentTickPosition
        Capsule()
          .fill(current ? Color.purple : Color.primary.opacity(0.28))
          .frame(width: current ? 4 : 2, height: current ? 12 : 2)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 9)
    .background(Capsule().fill(.ultraThinMaterial))
    .background(Capsule().fill(Color(nsColor: .windowBackgroundColor).opacity(0.55)))
    .overlay(Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 1))
    .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    .contentShape(Capsule())
    .help(L("대화 목차 — 눌러서 질문 목록 보기"))
    .accessibilityLabel(L("대화 목차"))
    .onTapGesture { togglePinned() }
  }

  // MARK: - 펼친 목차

  private var panel: some View {
    VStack(alignment: .leading, spacing: 7) {
      HStack(spacing: 6) {
        Text(L("대화 목차"))
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.primary.opacity(0.88))
        Text(Lf("질문 %d개", entries.count))
          .font(.system(size: 9.5, design: .monospaced))
          .foregroundColor(.secondary)
          .padding(.horizontal, 5).padding(.vertical, 1)
          .background(Capsule().fill(Color.primary.opacity(0.08)))
        Spacer(minLength: 4)
        Button { collapse(force: true) } label: {
          Image(systemName: "chevron.right")
            .font(.system(size: 9, weight: .semibold))
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(.secondary)
        .help(L("목차 접기"))
      }

      if entries.count >= 8 { searchField }

      ScrollViewReader { proxy in
        ScrollView(.vertical, showsIndicators: false) {
          LazyVStack(alignment: .leading, spacing: 1) {
            ForEach(filtered) { entry in
              outlineRow(entry).id(entry.index)
            }
          }
          .padding(.vertical, 1)
        }
        .frame(maxHeight: max(90, panelHeight - (entries.count >= 8 ? 118 : 78)))
        .onAppear { scrollToCurrent(proxy) }
        .onChange(of: currentIndex) { _, _ in scrollToCurrent(proxy) }
        .onChange(of: query) { _, _ in scrollToCurrent(proxy) }
      }

      HStack(spacing: 4) {
        Text(L("질문을 누르면 그 위치로 이동합니다"))
          .font(.system(size: 9))
          .foregroundColor(.secondary)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
    }
    .padding(10)
    .frame(width: panelWidth)
    .frame(maxHeight: panelHeight, alignment: .top)
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.regularMaterial))
    .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .fill(Color(nsColor: .windowBackgroundColor).opacity(0.72)))
    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
      .stroke(Color.primary.opacity(0.10), lineWidth: 1))
    .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
  }

  private var searchField: some View {
    HStack(spacing: 5) {
      Image(systemName: "magnifyingglass").font(.system(size: 9))
      TextField(L("질문 검색"), text: $query)
        .textFieldStyle(.plain)
        .font(.system(size: 10.5))
      if !query.isEmpty {
        Button { query = "" } label: {
          Image(systemName: "xmark.circle.fill").font(.system(size: 9))
        }
        .buttonStyle(.plain)
      }
    }
    .foregroundColor(.secondary)
    .padding(.horizontal, 7).padding(.vertical, 5)
    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 7)
      .stroke(Color.primary.opacity(0.07), lineWidth: 1))
  }

  private func outlineRow(_ entry: OutlineEntry) -> some View {
    let current = entry.index == currentIndex
    return Button {
      onSelect(entry)
      collapse(force: true)
    } label: {
      HStack(spacing: 5) {
        Circle()
          .fill(current ? Color.purple : Color.primary.opacity(0.18))
          .frame(width: 4, height: 4)
        Text(entry.preview)
          .font(.system(size: 10.5, weight: current ? .semibold : .regular))
          .lineLimit(1)
          .truncationMode(.tail)
          .foregroundColor(current ? .primary : .secondary)
        Spacer(minLength: 0)
      }
      .padding(.horizontal, 6).padding(.vertical, 4)
      .background(RoundedRectangle(cornerRadius: 6)
        .fill(current ? Color.purple.opacity(0.16) : Color.clear))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(entry.preview)
  }

  // MARK: - 펼침 · 접힘

  private func scheduleExpand() {
    guard !expanded else { return }
    hoverTask?.cancel()
    hoverTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      withAnimation(.easeOut(duration: 0.16)) { expanded = true }
    }
  }

  private func scheduleCollapse() {
    guard !pinned else { return }
    hoverTask?.cancel()
    hoverTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled else { return }
      withAnimation(.easeIn(duration: 0.14)) { expanded = false }
      query = ""
    }
  }

  private func togglePinned() {
    pinned.toggle()
    if pinned {
      expanded = true
    } else {
      expanded = false
      query = ""
    }
  }

  private func collapse(force: Bool) {
    if force { pinned = false }
    hoverTask?.cancel()
    withAnimation(.easeIn(duration: 0.14)) { expanded = false }
    query = ""
  }

  /// 펼칠 때 **지금 읽는 질문**이 보이도록 맞춘다(검색 중이면 마지막 결과).
  private func scrollToCurrent(_ proxy: ScrollViewProxy) {
    guard !filtered.isEmpty else { return }
    let target = filtered.first(where: { $0.index == currentIndex }) ?? filtered.last
    guard let target else { return }
    DispatchQueue.main.async {
      proxy.scrollTo(target.index, anchor: .center)
    }
  }
}
