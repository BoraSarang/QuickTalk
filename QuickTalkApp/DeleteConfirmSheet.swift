import SwiftUI

/// 삭제 확인 시트 — design_profile = custom.
/// 네이티브 alert 대신 카드형 확인창을 쓴다(제목·대상·결과 안내).
/// **취소가 기본(Esc)** 이고, 삭제는 빨간 버튼이다. Enter로는 실행되지 않는다(실수 방지).
struct DeleteConfirmSheet: View {
  let heading: String
  let target: String
  let message: String
  let confirmLabel: String
  let onConfirm: () -> Void

  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "trash.fill")
          .font(.system(size: 13))
          .foregroundColor(.red)
        Text(heading)
          .font(.system(size: 13, weight: .bold))
      }

      // 무엇이 사라지는지 한눈에 보이게 제목을 그대로 보여준다.
      Text(target)
        .font(.system(size: 13, weight: .semibold))
        .lineLimit(2)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
          .fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
          .stroke(Color.red.opacity(0.18), lineWidth: 1))

      Text(message)
        .font(.callout)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      HStack(spacing: 8) {
        Spacer()
        Button(L("취소")) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button {
          onConfirm()
          dismiss()
        } label: {
          Text(confirmLabel)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(Color.red))
        }
        .buttonStyle(.plain)
        .help(confirmLabel)
      }
    }
    .padding(16)
    .frame(width: 350)
  }
}
