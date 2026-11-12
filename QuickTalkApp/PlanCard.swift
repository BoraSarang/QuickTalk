import SwiftUI

// [FEATURE] 실행 계획 카드 (v0.36.3, PLAN_v0.36 §4)
//
// 모델이 propose_plan 으로 계획만 말하고 멈추면 이 카드가 답변 아래에 붙는다.
// 사용자가 [실행]을 누르기 전에는 **아무것도 실행되지 않는다** — 계획은 손이 아니라 입이다.

struct PlanCard: View {
  let plan: ExecutionPlan
  let state: UIStore.PlanRunState
  let canRun: Bool
  let onRun: () -> Void
  let onEdit: () -> Void
  /// [맡기기] — 백그라운드 Job으로 넘긴다(v0.38). nil 이면 버튼을 숨긴다.
  var onDelegate: (() -> Void)? = nil

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      header
      Text(plan.goal)
        .font(.system(size: 13.5, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)
      steps
      footer
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(Color.purple.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
      .stroke(Color.purple.opacity(0.18), lineWidth: 1))
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "list.bullet.clipboard")
        .font(.system(size: 11.5, weight: .semibold))
      Text(L("실행 계획"))
        .font(.system(size: 11, weight: .semibold))
      Spacer(minLength: 6)
      ForEach(plan.permissions) { permission in
        HStack(spacing: 3) {
          Image(systemName: permission.symbol)
            .font(.system(size: 8.5, weight: .semibold))
          Text(permission.displayName)
            .font(.system(size: 9.5, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.purple.opacity(0.09)))
        .foregroundColor(.purple)
      }
    }
    .foregroundColor(.purple)
  }

  private var steps: some View {
    VStack(alignment: .leading, spacing: 5) {
      ForEach(Array(plan.steps.enumerated()), id: \.offset) { index, step in
        let done = state.completed.contains(index)
        HStack(alignment: .firstTextBaseline, spacing: 7) {
          Image(systemName: done ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(done ? .purple : .secondary)
          Text(step)
            .font(.system(size: 12.5))
            .foregroundColor(done ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
          Spacer(minLength: 0)
        }
      }
    }
  }

  private var footer: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        if state.isRunning {
          ProgressView()
            .controlSize(.small)
          Text(L("실행 중"))
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        } else if state.finished {
          HStack(spacing: 3) {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 10, weight: .semibold))
            Text(L("실행 완료"))
              .font(.system(size: 10.5, weight: .medium))
          }
          .foregroundColor(.purple)
        }
        Spacer(minLength: 4)
        if canRun {
          Button(action: onEdit) {
            Text(L("수정"))
              .font(.system(size: 10.5, weight: .medium))
              .padding(.horizontal, 8)
              .padding(.vertical, 4)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .foregroundColor(.secondary)
          .help(L("계획을 입력창으로 가져와 고칩니다"))

          Button(action: onRun) {
            HStack(spacing: 3) {
              Image(systemName: "play.fill")
                .font(.system(size: 8.5, weight: .bold))
              Text(L("실행"))
                .font(.system(size: 10.5, weight: .semibold))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.purple.opacity(0.14)))
            .overlay(Capsule().stroke(Color.purple.opacity(0.32), lineWidth: 1))
            .foregroundColor(.purple)
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .help(L("이 계획을 순서대로 실행합니다"))

          if let onDelegate {
            Button(action: onDelegate) {
              HStack(spacing: 3) {
                Image(systemName: "shippingbox")
                  .font(.system(size: 8.5, weight: .bold))
                Text(L("맡기기"))
                  .font(.system(size: 10.5, weight: .semibold))
              }
              .padding(.horizontal, 9)
              .padding(.vertical, 4)
              .background(Capsule().fill(Color.accentColor.opacity(0.10)))
              .overlay(Capsule().stroke(Color.accentColor.opacity(0.28), lineWidth: 1))
              .foregroundColor(.accentColor)
              .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(L("앱이 백그라운드에서 끝까지 진행하고, 완료되면 알려 줍니다"))
          }
        }
      }
      if canRun, onDelegate != nil {
        Text(L("작업 폴더에 파일을 만들고, 중요·치명적 명령은 항상 확인합니다."))
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
      }
    }
  }
}
