import AppKit
import SwiftUI

// [FEATURE] 산출물 미리보기 시트 (PLAN_v0.38.2 §5.2)
//
// 텍스트는 [변경 내용 | 현재 파일]을 전환해 본다. diff 는 UndoStack 의 쓰기 전 백업과
// 현재 파일을 비교해 **시트를 열 때** 계산한다(대화 기록에는 저장하지 않는다).
// 이미지·바이너리·사라진 파일은 각각 다른 안내를 보여 주고, [열기]는 기존 LocalFileOpen 을 쓴다.

struct ArtifactPreviewSheet: View {
  let request: ArtifactPreviewRequest
  @Environment(\.dismiss) private var dismiss

  @State private var preview: ArtifactPreview?
  @State private var loading = true
  @State private var showDiff = true
  @State private var undoMessage: String?
  @State private var undone = false
  @State private var undoing = false

  private var path: String { request.path }
  private var artifact: TurnArtifact? { request.artifact }
  private var name: String { (path as NSString).lastPathComponent }

  var body: some View {
    VStack(spacing: 0) {
      header
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
      Divider()
      Group {
        if loading {
          VStack(spacing: 8) {
            ProgressView()
            Text(L("파일을 읽는 중…"))
              .font(.system(size: 11))
              .foregroundColor(.secondary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let preview {
          content(preview)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      Divider()
      footer
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
    .frame(minWidth: 580, idealWidth: 760, maxWidth: 940,
           minHeight: 400, idealHeight: 560, maxHeight: 800)
    .task(id: path) { await load() }
  }

  // MARK: - 헤더

  private var header: some View {
    HStack(spacing: 9) {
      Image(systemName: iconName)
        .font(.system(size: 20))
        .foregroundColor(.purple.opacity(0.85))
        .frame(width: 26)
      VStack(alignment: .leading, spacing: 2) {
        Text(name)
          .font(.system(size: 13.5, weight: .semibold))
          .lineLimit(1)
          .truncationMode(.middle)
        Text(path)
          .font(.system(size: 9.5, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
      }
      Spacer(minLength: 8)
      if let artifact {
        badge(text: changeText(artifact.change), color: changeColor(artifact.change))
        Text(artifact.sizeText)
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
        if let lines = artifact.lineChangeText {
          Text(lines)
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundColor(.secondary)
        }
      } else if let preview {
        Text(preview.sizeText)
          .font(.system(size: 9.5))
          .foregroundColor(.secondary)
      }
      Button { dismiss() } label: {
        Image(systemName: "xmark")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(.secondary)
          .padding(5)
          .background(Circle().fill(Color.primary.opacity(0.06)))
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.cancelAction)
      .help(L("닫기"))
    }
  }

  // MARK: - 본문

  @ViewBuilder
  private func content(_ preview: ArtifactPreview) -> some View {
    switch preview.kind {
    case .text:
      textBody(preview)
    case .image:
      imageBody
    case .binary:
      placeholder(icon: "doc", title: L("미리보기를 지원하지 않는 형식입니다."),
                  detail: L("파일 크기와 경로만 확인할 수 있습니다. [열기]로 기본 앱에서 여세요."))
    case .missing:
      missingBody(preview)
    }
  }

  @ViewBuilder
  private func textBody(_ preview: ArtifactPreview) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 10) {
        if preview.diff != nil, preview.content != nil {
          Picker("", selection: $showDiff) {
            Text(L("변경 내용")).tag(true)
            Text(L("현재 파일")).tag(false)
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 190)
        }
        if let count = preview.lineCount {
          Text(Lf("%d줄", count))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
        }
        Spacer()
        if preview.truncated {
          Text(L("일부만 표시합니다"))
            .font(.system(size: 9.5))
            .foregroundColor(.orange)
        }
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 7)
      Divider()
      if showDiff, let diff = preview.diff, !diff.isEmpty {
        diffView(diff)
      } else if let text = preview.content {
        ScrollView {
          Text(text)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
      } else {
        placeholder(icon: "doc", title: L("표시할 내용이 없습니다."), detail: nil)
      }
    }
  }

  private func diffView(_ diff: String) -> some View {
    let lines = diff.components(separatedBy: "\n")
    return ScrollView {
      LazyVStack(alignment: .leading, spacing: 1) {
        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
          Text(line.isEmpty ? " " : line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(diffColor(line))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(10)
    }
    .background(Color(nsColor: .textBackgroundColor).opacity(0.35))
  }

  private func diffColor(_ line: String) -> Color {
    if line.hasPrefix("+") { return Color(nsColor: .systemGreen) }
    if line.hasPrefix("-") { return Color(nsColor: .systemRed) }
    if line.hasPrefix("@@") { return .purple }
    return .secondary
  }

  private var imageBody: some View {
    Group {
      if let image = NSImage(contentsOfFile: path) {
        ScrollView([.vertical, .horizontal]) {
          Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: 880, maxHeight: 660)
            .padding(14)
        }
      } else {
        placeholder(icon: "photo", title: L("이미지를 열지 못했습니다."),
                    detail: L("[열기]로 기본 앱에서 여세요."))
      }
    }
    .background(Color(nsColor: .textBackgroundColor).opacity(0.25))
  }

  private func missingBody(_ preview: ArtifactPreview) -> some View {
    VStack(spacing: 0) {
      HStack(spacing: 7) {
        Image(systemName: "questionmark.folder")
          .font(.system(size: 11, weight: .semibold))
          .foregroundColor(.orange)
        Text(L("파일이 없습니다 — 이동·삭제·되돌리기되었을 수 있습니다."))
          .font(.system(size: 11.5))
          .foregroundColor(.secondary)
        Spacer()
      }
      .padding(.horizontal, 14)
      .padding(.vertical, 9)
      if let diff = preview.diff, !diff.isEmpty {
        Divider()
        diffView(diff)
      } else {
        Spacer()
      }
    }
  }

  private func placeholder(icon: String, title: String, detail: String?) -> some View {
    VStack(spacing: 9) {
      Image(systemName: icon)
        .font(.system(size: 28))
        .foregroundColor(.secondary.opacity(0.6))
      Text(title)
        .font(.system(size: 12, weight: .medium))
      if let detail {
        Text(detail)
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
          .multilineTextAlignment(.center)
          .frame(maxWidth: 320)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .padding(20)
  }

  // MARK: - 푸터

  private var footer: some View {
    HStack(spacing: 8) {
      if let undoMessage {
        Text(undoMessage)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .lineLimit(2)
      }
      Spacer(minLength: 6)
      footerAction(L("열기"), color: .secondary, disabled: preview?.kind == .missing) {
        LocalFileOpen.open(URL(fileURLWithPath: path))
      }
      footerAction(L("폴더 열기"), color: .secondary) {
        NSWorkspace.shared.open(URL(fileURLWithPath: path).deletingLastPathComponent())
      }
      if let undoID = artifact?.undoID, !undone {
        footerAction(undoing ? L("되돌리는 중…") : L("되돌리기"), color: .blue,
                     disabled: undoing) {
          undo(undoID)
        }
      }
      Button(L("닫기")) { dismiss() }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
        .keyboardShortcut(.cancelAction)
    }
  }

  private func footerAction(_ title: String, color: Color, disabled: Bool = false,
                            _ run: @escaping () -> Void) -> some View {
    Button(action: run) {
      Text(title)
        .font(.system(size: 11.5, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(color.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .stroke(color.opacity(0.22), lineWidth: 1))
        .foregroundColor(color == .secondary ? .secondary : color)
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
    .buttonStyle(.plain)
    .disabled(disabled)
    .opacity(disabled ? 0.45 : 1)
  }

  // MARK: - 동작

  private func load() async {
    loading = true
    var entry: UndoEntry?
    if let undoID = artifact?.undoID {
      entry = await UndoStack.shared.entry(id: undoID)
    }
    let path = self.path
    let loaded = await Task.detached(priority: .userInitiated) {
      FileArtifacts.preview(path: path, undoEntry: entry)
    }.value
    await MainActor.run {
      preview = loaded
      loading = false
      showDiff = loaded.diff != nil
    }
  }

  private func undo(_ undoID: String) {
    guard !undoing else { return }
    undoing = true
    Task {
      let result = await UndoStack.shared.undo(id: undoID)
      let text: String
      if result.succeeded {
        undone = true
        text = Lf("되돌렸습니다 — %d개 복원 · %d개 삭제", result.restored, result.removed)
      } else if result.alreadyUndone {
        undone = true
        text = L("이미 되돌렸습니다.")
      } else if result.notFound {
        text = L("되돌리기 기록을 찾지 못했습니다.")
      } else {
        text = Lf("일부만 되돌렸습니다(%d개 실패).", result.failed.count)
      }
      let entry = await UndoStack.shared.entry(id: undoID)
      let path = self.path
      let loaded = await Task.detached(priority: .userInitiated) {
        FileArtifacts.preview(path: path, undoEntry: entry)
      }.value
      await MainActor.run {
        undoMessage = text
        preview = loaded
        showDiff = false
        undoing = false
      }
    }
  }

  // MARK: - 표시 도우미

  private func badge(text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9, weight: .semibold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Capsule().fill(color.opacity(0.14)))
      .foregroundColor(color)
  }

  private var iconName: String {
    if artifact?.isImage == true { return "photo" }
    switch (path as NSString).pathExtension.lowercased() {
    case "png", "jpg", "jpeg", "gif", "webp", "bmp", "heic", "heif", "tif", "tiff":
      return "photo"
    case "md", "txt", "csv", "json", "yml", "yaml", "toml", "xml":
      return "doc.text"
    case "swift", "py", "sh", "zsh", "js", "ts", "html", "css":
      return "chevron.left.forwardslash.chevron.right"
    default:
      return "doc"
    }
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
}
