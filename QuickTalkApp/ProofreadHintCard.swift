import SwiftUI

// [FEATURE] v0.41 입력 교정 카드 — 대화창(전체)과 포인터 pill(축약)이 같은 뷰를 쓴다.
//
// · 대화 본문에 끼워 넣지 않는다 — 입력독 위에 별도 카드로 띄운다.
// · 경고색(노랑/빨강)을 쓰지 않는다 — 혼내는 느낌 대신 브랜드 바이올렛만 낮은 채도로.
// · Enter = 교정해서 보내기, ⌥Enter = 그대로 보내기, Esc = 카드만 닫기.
struct ProofreadHintCard: View {
  enum Style {
    case composer
    case compact
  }

  let hint: ProofreadHintState
  var style: Style = .composer
  let onAccept: () -> Void
  let onSendAsIs: () -> Void
  let onDismiss: () -> Void
  var onDisableForConversation: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: style == .compact ? 6 : 9) {
      header
      if style == .composer {
        issueList
        buttons
        footer
      } else {
        compactList
        compactButtons
      }
    }
    .padding(.horizontal, style == .compact ? 10 : 14)
    .padding(.vertical, style == .compact ? 9 : 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(background)
    .overlay(
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .strokeBorder(ProofreadPalette.accent.opacity(0.30), lineWidth: 1)
    )
    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    .accessibilityElement(children: .contain)
  }

  private var corner: CGFloat { style == .compact ? 14 : 14 }

  // MARK: 머리

  private var header: some View {
    HStack(alignment: .center, spacing: 8) {
      Image(systemName: "wand.and.sparkles")
        .font(.system(size: style == .compact ? 10.5 : 11.5, weight: .semibold))
        .foregroundColor(ProofreadPalette.accent)
        .frame(width: style == .compact ? 18 : 24, height: style == .compact ? 18 : 24)
        .background(
          RoundedRectangle(cornerRadius: style == .compact ? 5 : 7, style: .continuous)
            .fill(ProofreadPalette.accent.opacity(0.14))
        )
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 1) {
        Text(style == .compact
             ? Lf("%d곳 · %@", hint.result.issues.count, hint.categorySummary)
             : L("보내기 전에 다듬을까요?"))
          .font(.system(size: style == .compact ? 11 : 12.5,
                        weight: .semibold))
          .foregroundColor(style == .compact ? ProofreadPalette.accentText : .primary)
          .lineLimit(1)
        if style == .composer {
          Text(Lf("%d곳을 찾았어요", hint.result.issues.count))
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        }
      }

      Spacer(minLength: 4)

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .font(.system(size: 9.5, weight: .semibold))
          .foregroundColor(.secondary)
          .frame(width: 18, height: 18)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(L("카드만 닫기 (Esc)"))
    }
  }

  // MARK: 목록

  private var issueList: some View {
    VStack(alignment: .leading, spacing: 3) {
      ForEach(hint.shown) { issue in
        HStack(spacing: 7) {
          categoryTag(issue.category)
          Text(issue.original.trimmingCharacters(in: .whitespaces))
            .foregroundColor(.secondary)
            .strikethrough(false)
          Image(systemName: "arrow.right")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundColor(.secondary.opacity(0.7))
          Text(issue.replacement)
            .foregroundColor(.primary)
            .fontWeight(.medium)
        }
        .font(.system(size: 12.5))
        .lineLimit(1)
      }
      if hint.extraCount > 0 {
        Text(Lf("+%d곳 더 있어요", hint.extraCount))
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
          .padding(.leading, 2)
      }
    }
  }

  /// pill — 2줄까지만. 나머지는 `+N`.
  private var compactList: some View {
    Text(compactSummary)
      .font(.system(size: 11.5))
      .foregroundColor(.secondary)
      .lineLimit(1)
      .truncationMode(.tail)
  }

  private var compactSummary: String {
    let parts = hint.shown.prefix(2).map { "\($0.original) → \($0.replacement)" }
    var text = parts.joined(separator: " · ")
    // 카드가 보여 주는 것은 2개뿐이다 — 나머지는 **전체 이슈 수** 기준으로 센다.
    let hidden = max(0, hint.result.issues.count - min(2, hint.shown.count))
    if hidden > 0 { text += "  +\(hidden)" }
    return text
  }

  // MARK: 버튼

  private var buttons: some View {
    HStack(spacing: 8) {
      primaryButton(L("교정해서 보내기 ↩"), action: onAccept)
      secondaryButton(L("그대로 보내기 ⌥↩"), action: onSendAsIs)
      Spacer(minLength: 4)
      if let onDisableForConversation {
        Button(action: onDisableForConversation) {
          Text(L("이 대화에서 끄기"))
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(L("이 대화에서는 다시 묻지 않습니다. 설정은 그대로입니다."))
      }
    }
  }

  private var compactButtons: some View {
    HStack(spacing: 6) {
      primaryButton(L("교정 ↩"), action: onAccept, compact: true)
      secondaryButton(L("그대로 ⌥↩"), action: onSendAsIs, compact: true)
      Spacer(minLength: 0)
    }
  }

  private func primaryButton(_ title: String, action: @escaping () -> Void,
                             compact: Bool = false) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: compact ? 10.5 : 11.5, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, compact ? 8 : 11)
        .frame(height: compact ? 22 : 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(ProofreadPalette.accent)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func secondaryButton(_ title: String, action: @escaping () -> Void,
                               compact: Bool = false) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: compact ? 10.5 : 11.5, weight: .medium))
        .foregroundColor(.primary.opacity(0.86))
        .padding(.horizontal, compact ? 8 : 11)
        .frame(height: compact ? 22 : 26)
        .background(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 7, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.16), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var footer: some View {
    Text(Lf("온디바이스 규칙 검사 · %dms · 문장은 저장하지 않음",
            max(1, Int(hint.result.elapsedMilliseconds.rounded()))))
      .font(.system(size: 9.5))
      .foregroundColor(.secondary.opacity(0.8))
  }

  // MARK: 부품

  private func categoryTag(_ category: ProofreadCategory) -> some View {
    Text(category.displayName)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundColor(ProofreadPalette.tint(category))
      .padding(.horizontal, 4.5)
      .padding(.vertical, 1.5)
      .background(
        RoundedRectangle(cornerRadius: 4, style: .continuous)
          .fill(ProofreadPalette.tint(category).opacity(0.15))
      )
  }

  private var background: some View {
    ZStack {
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(Color(nsColor: .windowBackgroundColor))
      RoundedRectangle(cornerRadius: corner, style: .continuous)
        .fill(ProofreadPalette.accent.opacity(0.045))
    }
  }
}

enum ProofreadPalette {
  /// DESIGN.md 액센트 바이올렛 #7A5CFF
  static let accent = Color(red: 0.478, green: 0.361, blue: 1.0)

  static func tint(_ category: ProofreadCategory) -> Color {
    switch category {
    case .spacing: return Color(red: 0.96, green: 0.58, blue: 0.26)
    case .spelling: return accent
    case .punctuation: return Color(red: 0.29, green: 0.68, blue: 0.82)
    }
  }

  /// 어두운 배경에서도 읽히는 바이올렛 텍스트
  static var accentText: Color { accent }

  /// 주별 차트 막대 — 오타 노트(따뜻한 호박색). 카테고리 색과 섞이지 않게 따로 둔다.
  static let chart = Color(red: 0.74, green: 0.50, blue: 0.15)
}
