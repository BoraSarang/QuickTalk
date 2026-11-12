import AppKit
import SwiftUI

// [FEATURE] 산출물 카드 — 답변 아래에 붙는 파일 목록 (PLAN_v0.38.2 §5.1)
//
// 파일 내용은 Turn 에 저장하지 않는다. 카드는 경로·크기·변경·줄 수만 보여 주고,
// [미리보기]는 디스크를, diff 는 UndoStack 의 쓰기 전 백업을 읽는다.
// [되돌리기]는 같은 undoID 를 가진 파일을 **한 번에** 되돌린다(셸 한 번의 쓰기 전체).

struct ArtifactCard: View {
  let artifacts: [TurnArtifact]

  @State private var previewRequest: ArtifactPreviewRequest?
  @State private var undoneUndoIDs: Set<String> = []
  @State private var undoMessages: [String: String] = [:]
  @State private var busyUndoID: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 5) {
        Image(systemName: "paperclip")
          .font(.system(size: 10, weight: .semibold))
        Text(Lf("산출물 %d개", artifacts.count))
          .font(.system(size: 10.5, weight: .semibold))
        Spacer(minLength: 4)
      }
      .foregroundColor(.secondary)

      ForEach(artifacts) { artifact in
        row(artifact)
        if let message = undoMessage(for: artifact) {
          Text(message)
            .font(.system(size: 9.5))
            .foregroundColor(.secondary)
            .padding(.leading, 21)
        }
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.purple.opacity(0.045)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.purple.opacity(0.16), lineWidth: 1))
    .sheet(item: $previewRequest) { request in
      ArtifactPreviewSheet(request: request)
    }
  }

  private func row(_ artifact: TurnArtifact) -> some View {
    let exists = FileManager.default.fileExists(atPath: artifact.path)
    let isUndone = artifact.undoID.map { undoneUndoIDs.contains($0) } ?? false
    return HStack(spacing: 7) {
      Image(systemName: icon(for: artifact))
        .font(.system(size: 12))
        .foregroundColor(changeColor(artifact.change).opacity(0.85))
        .frame(width: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(artifact.name)
          .font(.system(size: 11.5, weight: .medium))
          .lineLimit(1)
          .truncationMode(.middle)
        HStack(spacing: 5) {
          changeBadge(artifact)
          if let lines = artifact.lineChangeText {
            Text(lines)
              .font(.system(size: 9.5, design: .monospaced))
              .foregroundColor(.secondary)
          }
          Text(artifact.sizeText)
            .font(.system(size: 9.5))
            .foregroundColor(.secondary)
          if !exists {
            Text(L("파일 없음"))
              .font(.system(size: 9.5))
              .foregroundColor(.orange)
          }
        }
      }
      Spacer(minLength: 4)
      if let busy = busyUndoID, busy == artifact.undoID {
        ProgressView().controlSize(.mini)
      }
      action(L("미리보기")) {
        previewRequest = ArtifactPreviewRequest(path: artifact.path, artifact: artifact)
      }
      action(L("폴더")) { openFolder(artifact.path) }
      if let undoID = artifact.undoID, !isUndone, !undoing(undoID) {
        action(L("되돌리기"), color: .blue) { undo(undoID) }
          .help(L("이 실행의 쓰기 전체를 쓰기 전 상태로 되돌립니다"))
      }
    }
    .help(artifact.path)
  }

  private func undoing(_ undoID: String) -> Bool { busyUndoID == undoID }

  private func undoMessage(for artifact: TurnArtifact) -> String? {
    guard let undoID = artifact.undoID else { return nil }
    guard let message = undoMessages[undoID] else { return nil }
    // 같은 undoID 의 첫 행에만 표시한다(카드마다 같은 문구가 반복되지 않게).
    guard artifacts.first(where: { $0.undoID == undoID })?.id == artifact.id else { return nil }
    return message
  }

  private func undo(_ undoID: String) {
    guard busyUndoID == nil else { return }
    busyUndoID = undoID
    Task {
      let result = await UndoStack.shared.undo(id: undoID)
      let text: String
      if result.succeeded {
        undoneUndoIDs.insert(undoID)
        text = Lf("되돌렸습니다 — %d개 복원 · %d개 삭제", result.restored, result.removed)
      } else if result.alreadyUndone {
        undoneUndoIDs.insert(undoID)
        text = L("이미 되돌렸습니다.")
      } else if result.notFound {
        text = L("되돌리기 기록을 찾지 못했습니다.")
      } else {
        text = Lf("일부만 되돌렸습니다(%d개 실패).", result.failed.count)
      }
      await MainActor.run {
        undoMessages[undoID] = text
        busyUndoID = nil
      }
    }
  }

  private func openFolder(_ path: String) {
    let folder = URL(fileURLWithPath: path).deletingLastPathComponent()
    NSWorkspace.shared.open(folder)
  }

  private func changeBadge(_ artifact: TurnArtifact) -> some View {
    Text(changeText(artifact.change))
      .font(.system(size: 9, weight: .semibold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Capsule().fill(changeColor(artifact.change).opacity(0.14)))
      .foregroundColor(changeColor(artifact.change))
  }

  private func changeText(_ change: TurnArtifact.Change) -> String {
    switch change {
    case .created: return L("생성")
    case .modified: return L("수정")
    case .deleted: return L("삭제")
    }
  }

  private func changeColor(_ change: TurnArtifact.Change) -> Color {
    switch change {
    case .created: return .green
    case .modified: return .blue
    case .deleted: return .red
    }
  }

  private func icon(for artifact: TurnArtifact) -> String {
    if artifact.isImage { return "photo" }
    switch artifact.fileExtension {
    case "md", "txt", "rtf", "csv", "tsv", "json", "yml", "yaml", "toml", "xml":
      return "doc.text"
    case "swift", "py", "sh", "zsh", "js", "ts", "html", "css", "c", "cpp", "rs", "go":
      return "chevron.left.forwardslash.chevron.right"
    case "pdf":
      return "doc.richtext"
    case "zip", "tar", "gz", "7z":
      return "archivebox"
    default:
      return "doc"
    }
  }

  private func action(_ title: String, color: Color = .secondary,
                      _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
      Text(title)
        .font(.system(size: 10, weight: .medium))
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.10)))
        .overlay(Capsule().stroke(color.opacity(0.22), lineWidth: 1))
        .foregroundColor(color == .secondary ? .secondary : color)
        .contentShape(Capsule())
    }
    .buttonStyle(.plain)
  }
}

/// 미리보기 시트 요청 — TurnArtifact 가 없는 Job 파일도 같은 시트를 쓴다.
struct ArtifactPreviewRequest: Identifiable {
  let id = UUID()
  let path: String
  let artifact: TurnArtifact?
}
