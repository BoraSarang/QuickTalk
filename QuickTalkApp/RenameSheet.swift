import SwiftUI

/// 대화방 제목 변경 시트 — 대화 헤더와 보관함 행에서 함께 쓴다.
/// design_profile = custom: 네이티브 alert 대신 카드형 입력창(TextField·취소/저장),
/// Enter = 저장, Esc = 취소. 빈 제목은 저장되지 않는다.
struct RenameSheet: View {
  let original: String
  let onSave: (String) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var text: String
  @FocusState private var focused: Bool

  init(original: String, onSave: @escaping (String) -> Void) {
    self.original = original
    self.onSave = onSave
    _text = State(initialValue: original)
  }

  /// 여러 줄·연속 공백은 한 줄로 접는다(제목은 한 줄).
  private var trimmed: String {
    text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
  private var canSave: Bool { !trimmed.isEmpty && trimmed != original }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(L("대화방 제목"))
        .font(.system(size: 13, weight: .bold))
      TextField(L("제목을 입력하세요"), text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(Color.purple.opacity(focused ? 0.65 : 0.18), lineWidth: 1))
        .focused($focused)
        .onSubmit { save() }
      HStack(spacing: 8) {
        Text(L("비우면 저장되지 않습니다"))
          .font(.caption).foregroundColor(.secondary)
        Spacer()
        Button(L("취소")) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button(L("저장")) { save() }
          .keyboardShortcut(.defaultAction)
          .disabled(!canSave)
      }
    }
    .padding(16)
    .frame(width: 350)
    .onAppear { focused = true }
  }

  private func save() {
    guard canSave else { return }
    onSave(trimmed)
    dismiss()
  }
}
