import SwiftUI

// [FEATURE] v0.41 오타 노트 — 자주 틀리는 표현과 교정률을 본다.
//
// 프라이버시: 문장 전체가 아니라 **틀린 구간 → 고친 구간**만 보여 준다.
// 통계 정의(PLAN_v0.41 §7):
//   발생률 = 힌트가 뜬 메시지 ÷ 검사한 메시지
//   교정률 = 교정해서 보낸 메시지 ÷ 힌트가 뜬 메시지
//   다시 고침 = 카드를 닫고 입력으로 돌아간 횟수
// 90일 보존은 ProofreadHistory.prune() 이 지킨다.
struct ProofreadNotesSheet: View {
  @ObservedObject var history: ProofreadHistory
  @Environment(\.dismiss) private var dismiss
  @State private var days = 30
  @State private var category: ProofreadCategory?
  @State private var showClearConfirm = false

  private var summary: ProofreadSummary { history.summary(days: days) }
  private var weeks: [ProofreadWeekPoint] {
    history.weekly(weeks: days <= 7 ? 4 : (days <= 30 ? 8 : 13))
  }

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 14) {
          if summary.checks == 0 {
            emptyState
          } else {
            statCards
            chartCard
            expressionSection
          }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
    }
    .frame(width: 760, height: 630)
    .background(Color(nsColor: .windowBackgroundColor))
    .sheet(isPresented: $showClearConfirm) {
      DeleteConfirmSheet(
        heading: L("오타 노트를 모두 지울까요?"),
        target: Lf("구간 %d개", history.data.entries.count),
        message: L("자주 틀리는 표현과 통계가 모두 사라집니다. 되돌릴 수 없습니다."),
        confirmLabel: L("모두 지우기")
      ) {
        history.clearAll()
      }
    }
  }

  // MARK: - 머리

  private var header: some View {
    HStack(alignment: .top, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(L("오타 노트"))
          .font(.system(size: 17, weight: .semibold))
        Text(L("자주 틀리는 표현과 고친 기록을 봅니다. 문장 전체는 저장하지 않습니다."))
          .font(.system(size: 11.5))
          .foregroundColor(.secondary)
      }
      Spacer(minLength: 12)
      periodControl
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.secondary)
          .frame(width: 22, height: 22)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L("닫기"))
    }
    .padding(.horizontal, 20)
    .padding(.top, 16)
    .padding(.bottom, 14)
  }

  /// 7일 / 30일 / 90일 — 네이티브 세그먼트 대신 같은 모양의 버튼 묶음.
  private var periodControl: some View {
    HStack(spacing: 2) {
      ForEach([7, 30, 90], id: \.self) { value in
        Button { days = value } label: {
          Text(Lf("%d일", value))
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(
              RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(days == value ? Color(nsColor: .controlBackgroundColor) : .clear)
            )
            .foregroundColor(days == value ? .primary : .secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(Color.primary.opacity(0.06))
    )
  }

  // MARK: - 요약 카드

  private var statCards: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
              spacing: 10) {
      statCard("\(summary.checks)",
               title: L("검사한 메시지"),
               sub: summary.isLowSample ? L("표본이 적어요") : L("기능이 켜진 뒤"),
               accent: false)
      statCard("\(summary.hints)",
               title: L("힌트가 뜬 메시지"),
               sub: Lf("발생률 %d%% · 그대로 %d",
                       percent(summary.occurrenceRate), summary.asIs),
               accent: true)
      statCard("\(summary.accepted)",
               title: L("교정해서 보낸"),
               sub: summary.acceptanceRate.map { Lf("교정률 %d%%", percent($0)) } ?? L("—"),
               accent: true)
      statCard("\(summary.dismissed)",
               title: L("다시 고침"),
               sub: L("힌트를 닫고 입력으로"),
               accent: false)
    }
  }

  private func statCard(_ value: String, title: String, sub: String,
                        accent: Bool) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value)
        .font(.system(size: 24, weight: .semibold, design: .rounded))
        .monospacedDigit()
      Text(title)
        .font(.system(size: 11))
        .foregroundColor(.secondary)
      Text(sub)
        .font(.system(size: 9.5))
        .foregroundColor(accent ? ProofreadPalette.accent : .secondary.opacity(0.85))
        .lineLimit(1)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    )
  }

  // MARK: - 차트

  private var chartCard: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .firstTextBaseline) {
        VStack(alignment: .leading, spacing: 2) {
          Text(L("주별 발생률"))
            .font(.system(size: 12, weight: .semibold))
          Text(L("검사한 메시지 대비 힌트가 뜬 비율"))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        Spacer()
        Text(Lf("평균 %d%% · %d주", percent(weeklyAverage), weeks.count))
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
      }
      WeeklyRateChart(points: weeks)
        .frame(height: 132)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    )
  }

  private var weeklyAverage: Double? {
    let checks = weeks.reduce(0) { $0 + $1.checks }
    let hints = weeks.reduce(0) { $0 + $1.hints }
    guard checks > 0 else { return nil }
    return Double(hints) / Double(checks)
  }

  // MARK: - 표현 목록

  private var expressionSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      categoryChips
        .padding(.bottom, 8)
      if !history.ignored.isEmpty {
        HStack(spacing: 8) {
          Text(Lf("무시한 표현 %d", history.ignored.count))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          Button(L("모두 해제")) { history.unignoreAll() }
            .buttonStyle(.plain)
            .font(.system(size: 10))
            .foregroundColor(ProofreadPalette.accent)
          Spacer(minLength: 0)
        }
        .padding(.bottom, 6)
      }
      tableHeader
      Divider()
      if filteredExpressions.isEmpty {
        Text(L("이 기간에 기록된 표현이 없습니다"))
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .frame(maxWidth: .infinity, alignment: .center)
          .padding(.vertical, 24)
      } else {
        ForEach(filteredExpressions) { expression in
          expressionRow(expression)
          Divider()
        }
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    )
  }

  private var categoryChips: some View {
    let counts = Dictionary(uniqueKeysWithValues:
      history.categoryCounts(days: days).map { ($0.category, $0.count) })
    let total = counts.values.reduce(0, +)
    return HStack(spacing: 6) {
      chip(nil, label: Lf("전체 %d", total), count: total)
      ForEach(ProofreadCategory.allCases) { item in
        if let n = counts[item], n > 0 {
          chip(item, label: "\(item.displayName) \(n)", count: n)
        }
      }
      Spacer(minLength: 0)
    }
  }

  private func chip(_ item: ProofreadCategory?, label: String, count: Int) -> some View {
    let selected = category == item
    return Button {
      category = item
    } label: {
      Text(label)
        .font(.system(size: 10.5, weight: selected ? .semibold : .regular))
        .foregroundColor(selected ? .white : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
          Capsule()
            .fill(selected
                  ? (item.map { ProofreadPalette.tint($0) } ?? ProofreadPalette.accent)
                  : Color.primary.opacity(0.06))
        )
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private var tableHeader: some View {
    HStack(spacing: 8) {
      Text(L("표현")).frame(maxWidth: .infinity, alignment: .leading)
      Text(L("횟수")).frame(width: Self.countWidth, alignment: .trailing)
      Text(L("교정")).frame(width: Self.correctionWidth, alignment: .leading)
      Text(L("마지막")).frame(width: Self.lastWidth, alignment: .trailing)
      Color.clear.frame(width: Self.actionWidth)
    }
    .font(.system(size: 10))
    .foregroundColor(.secondary)
    .padding(.vertical, 6)
  }

  private func expressionRow(_ expression: ProofreadExpression) -> some View {
    HStack(spacing: 8) {
      HStack(spacing: 5) {
        Text(expression.original.trimmingCharacters(in: .whitespaces))
          .foregroundColor(.secondary)
        Image(systemName: "arrow.right")
          .font(.system(size: 8.5, weight: .semibold))
          .foregroundColor(.secondary.opacity(0.65))
        Text(expression.replacement)
          .fontWeight(.medium)
        categoryTag(expression.category)
        Spacer(minLength: 0)
      }
      .font(.system(size: 11.5))
      .lineLimit(1)
      .frame(maxWidth: .infinity, alignment: .leading)

      Text("\(expression.count)")
        .font(.system(size: 11))
        .monospacedDigit()
        .frame(width: Self.countWidth, alignment: .trailing)

      VStack(alignment: .leading, spacing: 3) {
        Text("\(expression.accepted)/\(expression.count)")
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
          .monospacedDigit()
        progressBar(expression)
      }
      .frame(width: Self.correctionWidth, alignment: .leading)

      Text(lastSeenLabel(expression.lastSeen))
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .frame(width: Self.lastWidth, alignment: .trailing)

      Button(L("무시")) { history.ignore(expression.original) }
        .buttonStyle(.plain)
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .frame(width: Self.actionWidth, alignment: .trailing)
        .help(L("이 표현은 다시 알리지 않습니다. 설정은 그대로입니다."))
    }
    .padding(.vertical, 6)
  }

  private static let countWidth: CGFloat = 40
  private static let correctionWidth: CGFloat = 140
  private static let lastWidth: CGFloat = 74
  private static let actionWidth: CGFloat = 40

  private func progressBar(_ expression: ProofreadExpression) -> some View {
    GeometryReader { geo in
      let ratio = expression.count > 0
        ? min(1, max(0, CGFloat(expression.accepted) / CGFloat(expression.count)))
        : 0
      ZStack(alignment: .leading) {
        Capsule().fill(Color.primary.opacity(0.09))
        Capsule()
          .fill(ProofreadPalette.accent)
          .frame(width: max(ratio > 0 ? 2 : 0, geo.size.width * ratio))
      }
    }
    .frame(height: 4)
  }

  private func categoryTag(_ item: ProofreadCategory) -> some View {
    Text(item.displayName)
      .font(.system(size: 9, weight: .semibold))
      .foregroundColor(ProofreadPalette.tint(item))
      .padding(.horizontal, 4)
      .padding(.vertical, 1)
      .background(
        RoundedRectangle(cornerRadius: 3.5, style: .continuous)
          .fill(ProofreadPalette.tint(item).opacity(0.14))
      )
  }

  // MARK: - 빈 상태 · 꼬리

  private var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "wand.and.sparkles")
        .font(.system(size: 17, weight: .medium))
        .foregroundColor(ProofreadPalette.accent)
        .frame(width: 38, height: 38)
        .background(
          RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(ProofreadPalette.accent.opacity(0.14))
        )
      Text(L("아직 기록이 없어요"))
        .font(.system(size: 13.5, weight: .semibold))
        .padding(.top, 2)
      Text(L("교정 힌트를 사용하면서 자주 틀리는 표현이 여기에 쌓입니다."))
        .font(.system(size: 11.5))
        .foregroundColor(.secondary)
      Text(L("문장 전체는 아니라 틀린 구간만 저장합니다."))
        .font(.system(size: 10.5))
        .foregroundColor(.secondary.opacity(0.8))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 90)
  }

  private var footer: some View {
    HStack(spacing: 12) {
      Text(L("기록은 이 Mac에만 저장됩니다 · 90일 뒤 자동 삭제"))
        .font(.system(size: 10))
        .foregroundColor(.secondary)
      Spacer()
      if !history.data.entries.isEmpty {
        Button { showClearConfirm = true } label: {
          Text(L("모두 지우기"))
            .font(.system(size: 11))
            .foregroundColor(.red)
        }
        .buttonStyle(.plain)
      }
      Button(L("닫기")) { dismiss() }
        .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 12)
  }

  // MARK: - 계산

  private var filteredExpressions: [ProofreadExpression] {
    history.expressions(days: days, limit: 200).filter { expression in
      // 무시한 표현은 표에서 빼고, 위의 "무시한 표현 N · 모두 해제"로 되돌린다.
      !history.isIgnored(expression.original)
        && (category == nil || expression.category == category)
    }
  }

  private func percent(_ value: Double?) -> Int {
    guard let value else { return 0 }
    return Int((value * 100).rounded())
  }

  private func lastSeenLabel(_ date: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) { return L("오늘") }
    if calendar.isDateInYesterday(date) { return L("어제") }
    return Self.dateFormatter.string(from: date)
  }

  private static var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = L10n.effective == .en
      ? Locale(identifier: "en_US")
      : Locale(identifier: "ko_KR")
    formatter.setLocalizedDateFormatFromTemplate("MMM d")
    return formatter
  }
}

// MARK: - 주별 막대 그래프

/// Charts 프레임워크 없이 `Canvas` 로 그린다(배포 타깃에 Charts 의존을 늘리지 않는다).
private struct WeeklyRateChart: View {
  let points: [ProofreadWeekPoint]

  private var rates: [Double?] {
    points.map { point in
      point.checks > 0 ? Double(point.hints) / Double(point.checks) : nil
    }
  }

  var body: some View {
    Canvas { context, size in
      let labelHeight: CGFloat = 12
      let axisHeight: CGFloat = 12
      let gap: CGFloat = 5
      let top = labelHeight + gap
      let bottom = size.height - axisHeight - gap
      let plotHeight = max(1, bottom - top)
      let slot = size.width / CGFloat(max(1, points.count))
      let barWidth = min(24, slot * 0.5)
      let maxRate = max(0.05, rates.compactMap { $0 }.max() ?? 0)

      func label(_ text: String) -> GraphicsContext.ResolvedText {
        context.resolve(
          Text(text)
            .font(.system(size: 9))
            .foregroundColor(.secondary)
        )
      }

      // 평균선
      let checks = points.reduce(0) { $0 + $1.checks }
      let hints = points.reduce(0) { $0 + $1.hints }
      if checks > 0 {
        let average = Double(hints) / Double(checks)
        let y = bottom - plotHeight * CGFloat(average / maxRate)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y))
        path.addLine(to: CGPoint(x: size.width, y: y))
        context.stroke(path,
                       with: .color(ProofreadPalette.accent.opacity(0.55)),
                       style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
        context.draw(label(Lf("평균 %d%%", Int((average * 100).rounded()))),
                     at: CGPoint(x: size.width - 2, y: y - 7),
                     anchor: .trailing)
      }

      for (index, point) in points.enumerated() {
        let centerX = slot * (CGFloat(index) + 0.5)
        let rate = rates[index]

        // 위쪽 퍼센트
        let percentText = rate.map { "\(Int(($0 * 100).rounded()))%" } ?? "—"
        context.draw(label(percentText),
                     at: CGPoint(x: centerX, y: labelHeight / 2),
                     anchor: .center)

        // 막대
        if let rate, rate > 0 {
          let height = max(3, plotHeight * CGFloat(rate / maxRate))
          let rect = CGRect(x: centerX - barWidth / 2, y: bottom - height,
                            width: barWidth, height: height)
          context.fill(Path(roundedRect: rect, cornerRadius: 2),
                       with: .color(ProofreadPalette.chart))
        } else {
          let rect = CGRect(x: centerX - barWidth / 2, y: bottom - 1,
                            width: barWidth, height: 1)
          context.fill(Path(roundedRect: rect, cornerRadius: 0.5),
                       with: .color(Color.primary.opacity(0.10)))
        }

        // 아래쪽 날짜
        context.draw(label(Self.axisLabel(point.end)),
                     at: CGPoint(x: centerX, y: size.height - axisHeight / 2),
                     anchor: .center)
      }
    }
    .accessibilityLabel(L("주별 발생률"))
  }

  private static var axisFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.locale = L10n.effective == .en
      ? Locale(identifier: "en_US")
      : Locale(identifier: "ko_KR")
    formatter.setLocalizedDateFormatFromTemplate("M d")
    return formatter
  }

  private static func axisLabel(_ date: Date) -> String {
    axisFormatter.string(from: date)
  }
}
