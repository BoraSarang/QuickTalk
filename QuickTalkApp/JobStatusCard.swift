import AppKit
import SwiftUI

// [FEATURE] 맡긴 작업 상태 카드 (v0.38, PLAN_v0.38 §8.2)
//
// Job 전용 대화의 첫 assistant 턴에 붙는다. `Turn.jobID` 로 연결되므로
// 앱을 다시 켜도 상태 카드가 그대로 남고, `store.jobs` 가 바뀌면 실시간으로 다시 그린다.

struct JobStatusCard: View {
  let jobID: UUID
  @EnvironmentObject private var store: UIStore

  private var job: Job? { store.job(id: jobID) }

  var body: some View {
    if let job {
      card(job)
    } else {
      HStack(spacing: 6) {
        Image(systemName: "shippingbox")
        Text(L("맡긴 작업을 찾지 못했습니다."))
      }
      .font(.system(size: 11.5))
      .foregroundColor(.secondary)
      .padding(10)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.secondary.opacity(0.06)))
    }
  }

  private func card(_ job: Job) -> some View {
    VStack(alignment: .leading, spacing: 9) {
      header(job)
      Text(job.title)
        .font(.system(size: 13.5, weight: .semibold))
        .fixedSize(horizontal: false, vertical: true)

      if job.status == .waitingApproval {
        Text(L("아래 승인 카드에서 허용하면 이어서 실행합니다."))
          .font(.system(size: 11.5))
          .foregroundColor(.orange)
      } else if let progress = job.progress, !progress.isEmpty,
                job.status != .completed {
        Text(progress)
          .font(.system(size: 11))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }

      HStack(spacing: 10) {
        Text(job.progressLine)
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
        if job.activeSeconds >= 60 {
          Text(elapsedText(job.activeSeconds))
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
        }
        if job.status == .completed {
          Text(Lf("파일 %d개", job.artifactPaths.count))
            .font(.system(size: 10.5, weight: .medium))
            .foregroundColor(tint(.completed))
        }
        Spacer(minLength: 0)
      }

      if job.status == .completed, !job.artifactPaths.isEmpty {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(Array(job.artifactPaths.prefix(4)), id: \.self) { path in
            Text("• \(path)")
              .font(.system(size: 10.5, design: .monospaced))
              .foregroundColor(.secondary)
              .lineLimit(1)
              .truncationMode(.middle)
          }
          if job.artifactPaths.count > 4 {
            Text(Lf("외 %d개", job.artifactPaths.count - 4))
              .font(.system(size: 10))
              .foregroundColor(.secondary)
          }
        }
      }

      footer(job)
    }
    .padding(12)
    .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
      .fill(tint(job.status).opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
      .stroke(tint(job.status).opacity(0.20), lineWidth: 1))
  }

  private func header(_ job: Job) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "shippingbox.fill")
        .font(.system(size: 11, weight: .semibold))
      Text(L("맡긴 작업"))
        .font(.system(size: 11, weight: .semibold))
      Spacer(minLength: 6)
      if job.status == .running || job.status == .queued {
        ProgressView()
          .controlSize(.mini)
      }
      HStack(spacing: 3) {
        Image(systemName: job.status.symbol)
          .font(.system(size: 9, weight: .semibold))
        Text(job.status.displayName)
          .font(.system(size: 9.5, weight: .semibold))
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(tint(job.status).opacity(0.12)))
      .foregroundColor(tint(job.status))
    }
    .foregroundColor(tint(job.status))
  }

  private func footer(_ job: Job) -> some View {
    HStack(spacing: 8) {
      switch job.status {
      case .running, .waitingApproval:
        action(L("중단"), color: .red) { store.jobService?.cancel(job.id) }
      case .queued:
        action(L("취소"), color: .red) { store.jobService?.cancel(job.id) }
      case .paused, .interrupted:
        action(L("계속"), color: .purple) { store.jobService?.resume(job.id) }
      case .failed:
        action(L("다시 시도"), color: .purple) { store.jobService?.resume(job.id) }
      case .completed, .cancelled:
        EmptyView()
      }
      Spacer(minLength: 4)
      action(L("폴더 열기"), color: .secondary) {
        let url = URL(fileURLWithPath: job.workspacePath, isDirectory: true)
        NSWorkspace.shared.open(url)
      }
    }
  }

  private func action(_ title: String, color: Color,
                      _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
      Text(title)
        .font(.system(size: 10.5, weight: .medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().stroke(color.opacity(0.24), lineWidth: 1))
        .foregroundColor(color)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }

  private func tint(_ status: Job.Status) -> Color {
    switch status {
    case .running: return .purple
    case .queued: return .blue
    case .waitingApproval: return .orange
    case .paused, .interrupted: return .yellow
    case .completed: return .green
    case .failed: return .red
    case .cancelled: return .secondary
    }
  }

  private func elapsedText(_ seconds: Double) -> String {
    let minutes = Int(seconds / 60)
    if minutes < 60 { return Lf("%d분", max(1, minutes)) }
    return Lf("%d시간 %d분", minutes / 60, minutes % 60)
  }
}
