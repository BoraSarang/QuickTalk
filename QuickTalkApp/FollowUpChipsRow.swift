import SwiftUI

// 후속 질문 칩(v0.32) — 응답이 끝난 답변 아래에 붙는다.
//
// 답변보다 눈에 띄지 않게(작은 글자·연한 보라 테두리) 두고, 누르면 바로 이어서 묻는다.
// 생성·폴백 규칙은 Core(`FollowUpSuggest`)와 `UIStore+FollowUp` 이 맡는다.

struct FollowUpChipsRow: View {
  let chips: [String]
  let onTap: (String) -> Void

  var body: some View {
    VStack(alignment: .trailing, spacing: 5) {
      HStack(spacing: 4) {
        Image(systemName: "sparkles").font(.system(size: 9.5))
        Text(L("이어서 물어보기")).font(.system(size: 10))
      }
      .foregroundColor(.secondary)

      ForEach(chips, id: \.self) { chip in
        Button { onTap(chip) } label: {
          Text(chip)
            .font(.system(size: 11.5))
            .lineLimit(1)
            .foregroundColor(.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(Color.purple.opacity(0.10)))
            .overlay(Capsule().stroke(Color.purple.opacity(0.28), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L("이 질문을 이어서 보냅니다"))
        .accessibilityLabel(chip)
      }
    }
    .frame(maxWidth: .infinity, alignment: .trailing)
    .padding(.top, 2)
  }
}
