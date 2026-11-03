import SwiftUI

/// 모델이 제안한 예약 작업 확인 카드 (v0.26 4단계).
///
/// 알림·승인 카드와 달리 **일정 자체를 만드는 결정**이므로 별도 카드로 보여 준다.
/// [등록]을 누르기 전에는 어떤 파일도 만들어지지 않는다.
struct ScheduleProposalCard: View {
  @EnvironmentObject var store: UIStore
  let pending: ScheduleConfirmation

  private var proposal: ScheduleProposal { pending.proposal }

  private var meta: String {
    let persona = store.settings.persona(proposal.personaID)?.name ?? L("기본(비서 없음)")
    return "\(persona) · \(proposal.rule.humanDescription())"
  }

  private var nextText: String? {
    guard let next = proposal.rule.next(after: Date()) else { return nil }
    return Lf("다음 실행: %@", RelativeTime.absolute(next))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 6) {
        Image(systemName: "calendar.badge.plus")
          .font(.system(size: 11))
          .foregroundColor(.purple)
        Text(L("예약 작업 제안"))
          .font(.system(size: 11.5, weight: .semibold))
        Spacer()
        if pending.isDuplicate {
          Text(L("같은 일정이 있어 덮어씁니다"))
            .font(.caption2)
            .foregroundColor(.orange)
        }
      }
      Text(proposal.title)
        .font(.system(size: 12.5, weight: .semibold))
      Text([meta, nextText].compactMap { $0 }.joined(separator: " · "))
        .font(.caption).foregroundColor(.secondary)
      Text(proposal.instruction)
        .font(.caption).foregroundColor(.secondary)
        .lineLimit(4)
        .fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 6) {
        Button(L("등록")) {
          store.resolveScheduleProposal(accept: true)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
        Button(L("취소")) {
          store.resolveScheduleProposal(accept: false)
        }
        .controlSize(.small)
        Spacer()
        Text(L("등록해야 실제로 실행됩니다"))
          .font(.caption2).foregroundColor(.secondary)
      }
      .padding(.top, 2)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.purple.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.purple.opacity(0.3), lineWidth: 1))
  }
}
