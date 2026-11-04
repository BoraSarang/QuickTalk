import SwiftUI

/// 모델이 제안한 예약 작업 확인 카드 (v0.26 등록, v0.27 변경·삭제).
///
/// 알림·승인 카드와 달리 **일정 자체를 바꾸는 결정**이므로 별도 카드로 보여 준다.
/// 버튼을 누르기 전에는 어떤 파일도 바뀌지 않는다.
struct ScheduleProposalCard: View {
  @EnvironmentObject var store: UIStore
  let pending: ScheduleConfirmation

  private var accent: Color {
    switch pending.action {
    case .create: return .purple
    case .update: return .orange
    case .delete: return .red
    }
  }

  private var icon: String {
    switch pending.action {
    case .create: return "calendar.badge.plus"
    case .update: return "calendar.badge.clock"
    case .delete: return "calendar.badge.minus"
    }
  }

  private var heading: String {
    switch pending.action {
    case .create: return L("예약 작업 제안")
    case .update: return L("일정 변경 제안")
    case .delete: return L("일정 삭제 제안")
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 11))
          .foregroundColor(accent)
        Text(heading)
          .font(.system(size: 11.5, weight: .semibold))
        Spacer()
        if pending.isDuplicate, case .create = pending.action {
          Text(L("같은 일정이 있어 덮어씁니다"))
            .font(.caption2)
            .foregroundColor(.orange)
        }
      }
      switch pending.action {
      case .create(let proposal):
        createBody(proposal)
      case .update(let change):
        updateBody(change)
      case .delete(let deletion):
        deleteBody(deletion)
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(accent.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(accent.opacity(0.3), lineWidth: 1))
  }

  // MARK: - 등록

  @ViewBuilder
  private func createBody(_ proposal: ScheduleProposal) -> some View {
    let persona = store.settings.persona(proposal.personaID)?.name ?? L("기본(비서 없음)")
    let skip = proposal.skip.normalized().humanDescription()
    Text(proposal.title)
      .font(.system(size: 12.5, weight: .semibold))
    Text([persona, proposal.rule.humanDescription(), skip].compactMap { $0 }
      .joined(separator: " · "))
      .font(.caption).foregroundColor(.secondary)
    if let next = proposal.rule.next(after: Date(), skip: proposal.skip) {
      Text(Lf("다음 실행: %@", RelativeTime.absolute(next)))
        .font(.caption).foregroundColor(.secondary)
    }
    Text(proposal.instruction)
      .font(.caption).foregroundColor(.secondary)
      .lineLimit(4)
      .fixedSize(horizontal: false, vertical: true)
    actions(confirm: L("등록"), note: L("등록해야 실제로 실행됩니다"))
  }

  // MARK: - 변경

  @ViewBuilder
  private func updateBody(_ change: ScheduleChangeProposal) -> some View {
    Text(change.after.title)
      .font(.system(size: 12.5, weight: .semibold))
    Text(change.summaryLine())
      .font(.caption).foregroundColor(.secondary)
    VStack(alignment: .leading, spacing: 3) {
      ForEach(change.changes) { item in
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(item.label)
            .font(.caption2).foregroundColor(.secondary)
            .frame(width: 46, alignment: .leading)
          Text(item.before)
            .font(.caption)
            .foregroundColor(.secondary)
            .strikethrough()
            .lineLimit(2)
          Image(systemName: "arrow.right")
            .font(.system(size: 8)).foregroundColor(.secondary)
          Text(item.after)
            .font(.caption)
            .lineLimit(2)
        }
      }
    }
    actions(confirm: L("변경"), note: L("변경해야 실제로 반영됩니다"))
  }

  // MARK: - 삭제

  @ViewBuilder
  private func deleteBody(_ deletion: ScheduleDeletionProposal) -> some View {
    Text(deletion.title)
      .font(.system(size: 12.5, weight: .semibold))
    Text([deletion.rule.humanDescription(),
          deletion.skip.normalized().humanDescription()].compactMap { $0 }
      .joined(separator: " · "))
      .font(.caption).foregroundColor(.secondary)
    Text(L("삭제하면 더 이상 실행되지 않습니다. 지난 리포트 파일은 그대로 남습니다."))
      .font(.caption).foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    actions(confirm: L("삭제"), note: L("삭제해야 반영됩니다"), destructive: true)
  }

  // MARK: - 버튼

  @ViewBuilder
  private func actions(confirm: String, note: String,
                       destructive: Bool = false) -> some View {
    HStack(spacing: 6) {
      if destructive {
        Button(confirm) { store.resolveScheduleProposal(accept: true) }
          .buttonStyle(.borderedProminent)
          .tint(.red)
          .controlSize(.small)
      } else {
        Button(confirm) { store.resolveScheduleProposal(accept: true) }
          .buttonStyle(.borderedProminent)
          .controlSize(.small)
      }
      Button(L("취소")) { store.resolveScheduleProposal(accept: false) }
        .controlSize(.small)
      Spacer()
      Text(note)
        .font(.caption2).foregroundColor(.secondary)
    }
    .padding(.top, 2)
  }
}
