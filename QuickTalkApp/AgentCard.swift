import SwiftUI

// [FEATURE] 도구 실행 카드 (PLAN_v0.18 §6)
//
// 대화 안에 붙는 실행 기록 + 승인 UI.
// design_profile = custom — 네이티브 alert 를 쓰지 않고 카드형으로 처리한다.
// (DeleteConfirmSheet 와 같은 원칙: 취소가 기본, Enter 로 실행되지 않는다)

struct AgentCard: View {
  let events: [AgentEvent]
  let approval: AgentApprovalRequest?
  let onAllowOnce: () -> Void
  let onAlwaysAllow: () -> Void
  let onDeny: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !events.isEmpty {
        VStack(alignment: .leading, spacing: 5) {
          ForEach(events) { event in
            eventRow(event)
          }
        }
      }
      if let approval {
        approvalBlock(approval)
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.primary.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.primary.opacity(0.10), lineWidth: 1))
  }

  // MARK: - 실행 1건

  private func eventRow(_ event: AgentEvent) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Image(systemName: Self.icon(for: event.state))
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(Self.tint(for: event.state))
          .frame(width: 12)
        Text(event.title)
          .font(.system(size: 11, design: .monospaced))
          .foregroundColor(.primary)
          .lineLimit(2)
          .truncationMode(.middle)
        Spacer(minLength: 4)
        badge(event.level.displayName,
              color: event.level == .read ? .secondary : .orange)
        if event.risk != .normal {
          badge(event.risk.displayName, color: event.risk == .critical ? .red : .orange)
        }
      }
      if !event.output.isEmpty, event.state != .pending {
        Text(event.output)
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(6)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.leading, 18)
      }
    }
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9, weight: .semibold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Capsule().fill(color.opacity(0.16)))
      .foregroundColor(color)
  }

  // MARK: - 승인 요청

  private func approvalBlock(_ request: AgentApprovalRequest) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      approvalHeader(request)
      // 무엇을 실행하는지 — 명령 전문을 그대로 보여 준다
      Text(request.command)
        .font(.system(size: 11, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.primary.opacity(0.06)))
      Text(request.reason)
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      approvalButtons
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color.orange.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
      .stroke(Color.orange.opacity(0.30), lineWidth: 1))
  }

  private func approvalHeader(_ request: AgentApprovalRequest) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.shield")
        .font(.system(size: 11))
        .foregroundColor(.orange)
      Text(L("실행 권한이 필요합니다"))
        .font(.system(size: 12, weight: .bold))
      Spacer()
      badge(request.level.displayName, color: .orange)
      if request.risk != .normal {
        badge(request.risk.displayName, color: request.risk == .critical ? .red : .orange)
      }
    }
  }

  private var approvalButtons: some View {
    HStack(spacing: 6) {
      Spacer()
      Button(L("거부")) { onDeny() }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
      Button(L("항상 허용")) { onAlwaysAllow() }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(Color.accentColor)
      Button(L("한 번 허용")) { onAllowOnce() }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(.orange))
    }
  }

  // MARK: - 상태 표시

  static func icon(for state: AgentEvent.State) -> String {
    switch state {
    case .pending: return "clock"
    case .running: return "arrow.triangle.2.circlepath"
    case .allowed: return "checkmark.circle"
    case .denied: return "hand.raised.fill"
    case .done: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    }
  }

  static func tint(for state: AgentEvent.State) -> Color {
    switch state {
    case .pending: return .orange
    case .running: return .blue
    case .allowed, .done: return .green
    case .denied: return .secondary
    case .failed: return .red
    }
  }
}
