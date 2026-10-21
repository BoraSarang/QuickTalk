import SwiftUI
import AppKit

// [REFACTOR] ShelfView — 클립보드 탭 (2026-10-20 파일 분리)
extension ShelfView {
  // MARK: 클립보드 탭

  var clipboardTab: some View {
    VStack(spacing: 0) {
      HStack(spacing: 5) {
        filterChip(L("전체"), kind: nil)
        filterChip(L("텍스트"), kind: .text)
        filterChip(L("이미지"), kind: .image)
        filterChip(L("링크"), kind: .link)
        Spacer()
      }
      .padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)

      if clipboardItems.isEmpty {
        emptyState(L("클립보드가 비어 있습니다"),
                   L("복사하면 2분 동안 여기에 표시됩니다."))
      } else {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
          ScrollView {
            LazyVStack(spacing: 7) {
              ForEach(clipboardItems) { item in
                clipboardCard(item, now: ctx.date)
              }
            }
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
          }
          .scrollIndicators(.hidden)
        }
      }
    }
  }

  private func filterChip(_ title: String, kind: ClipboardItem.Kind?) -> some View {
    let on = clipboardFilter == kind
    return Button { clipboardFilter = kind } label: {
      Text(title)
        .font(.system(size: 10.5))
        .padding(.horizontal, 8).padding(.vertical, 3)
        .foregroundColor(on ? accentText : .secondary)
        .background(Capsule().fill(Color.primary.opacity(on ? 0.12 : 0.05)))
        .overlay(Capsule().stroke(Color(red: 0.48, green: 0.36, blue: 1).opacity(on ? 0.5 : 0), lineWidth: 1))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private func clipboardCard(_ item: ClipboardItem, now: Date) -> some View {
    let revealed = store.clipboard.isRevealed(item.id)
    let masked = item.isSensitive && !revealed
    let hovered = store.shelfPreview == .clipboard(item, masked: masked)
    return Button {
      store.tapClipboard(item)
    } label: {
      VStack(alignment: .leading, spacing: 0) {
        if item.kind == .image, let data = item.imageData, let img = NSImage(data: data) {
          ZStack(alignment: .bottomTrailing) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
              .frame(height: 74).frame(maxWidth: .infinity).clipped()
            Text(item.text).font(.system(size: 8.5, design: .monospaced))
              .foregroundColor(.white.opacity(0.9))
              .padding(.horizontal, 5).padding(.vertical, 2)
              .background(Capsule().fill(Color.black.opacity(0.6)))
              .padding(5)
          }
          .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if item.kind == .file || item.kind == .link {
          HStack(spacing: 7) {
            Image(systemName: item.kind == .link ? "link" : "doc")
              .font(.system(size: 12))
              .frame(width: 24, height: 24)
              .background(RoundedRectangle(cornerRadius: 6).fill(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.18)))
            Text(masked ? ClipboardPolicy.displayText(item, revealed: false) : item.text)
              .font(.system(size: 11.5)).lineLimit(1)
            Spacer(minLength: 0)
          }
          .padding(.horizontal, 2).padding(.top, 1)
        } else {
          Text(masked ? ClipboardPolicy.displayText(item, revealed: false)
                      : ClipboardPolicy.previewText(item.text, limit: 140))
            .font(.system(size: 11.5))
            .lineLimit(3)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        HStack(spacing: 5) {
          Image(systemName: icon(for: item, masked: masked)).font(.system(size: 9))
          Text(kindLabel(item.kind)).font(.system(size: 9))
          if item.isSensitive && !revealed {
            Text(L("민감")).font(.system(size: 8, weight: .bold))
              .padding(.horizontal, 4).padding(.vertical, 1)
              .background(Capsule().fill(Color.orange.opacity(0.22)))
              .foregroundColor(.orange)
          }
          Spacer(minLength: 2)
          Text(timeLabel(store.clipboard.secondsLeft(item, now: now)))
            .font(.system(size: 9, design: .monospaced))
        }
        .foregroundColor(.secondary)
        .padding(.top, 7)
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10)
        .fill(Color.primary.opacity(hovered ? 0.12 : 0.06)))
      .overlay(RoundedRectangle(cornerRadius: 10)
        .stroke(Color(red: 0.48, green: 0.36, blue: 1).opacity(hovered ? 0.8 : 0.14), lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(helpText(masked: masked))
    .onHover { h in setPreview(h, .clipboard(item, masked: masked)) }
  }

}
