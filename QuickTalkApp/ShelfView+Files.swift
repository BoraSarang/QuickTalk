import SwiftUI
import AppKit
import UniformTypeIdentifiers

// [REFACTOR] ShelfView — 파일·이미지 탭 (2026-10-20 파일 분리)
extension ShelfView {
  // MARK: 파일 탭

  var filesTab: some View {
    VStack(spacing: 0) {
      VStack(spacing: 6) {
        pickButton(L("파일 선택…"), symbol: "doc", shortcut: "⌘O") { pick(imagesOnly: false) }
          .keyboardShortcut("o", modifiers: .command)
        pickButton(L("이미지 선택…"), symbol: "photo", shortcut: "⌘⇧O") { pick(imagesOnly: true) }
          .keyboardShortcut("o", modifiers: [.command, .shift])
      }
      .padding(.horizontal, 10).padding(.top, 8)

      dropZone

      if fileItems.isEmpty {
        emptyState(L("첨부할 파일이 없습니다"), L("파일을 고르거나 아래로 끌어다 놓으세요."))
      } else {
        ScrollView {
          LazyVStack(spacing: 7) {
            ForEach(fileItems) { file in
              fileCard(file)
            }
          }
          .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  private func pickButton(_ title: String, symbol: String, shortcut: String,
                          action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 8) {
        Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
        Text(title).font(.system(size: 11.5))
        Spacer()
        Text(shortcut).font(.system(size: 9, design: .monospaced))
          .foregroundColor(accentText)
          .padding(.horizontal, 5).padding(.vertical, 2)
          .background(RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.16)))
      }
      .padding(.horizontal, 9).padding(.vertical, 8)
      .frame(maxWidth: .infinity)
      .background(RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.05)))
      .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.07), lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  private var dropZone: some View {
    RoundedRectangle(cornerRadius: 10)
      .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      .foregroundColor(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.5))
      .frame(height: 56)
      .overlay(
        VStack(spacing: 2) {
          Text(L("여기로 파일을 끌어다 놓으세요")).font(.system(size: 10.5))
            .foregroundColor(accentText)
          Text(L("⌘O = 파일 선택 · ⌘⇧O = 이미지 선택")).font(.system(size: 9)).foregroundColor(.secondary)
        }
      )
      .background(RoundedRectangle(cornerRadius: 10).fill(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.06)))
      .padding(.horizontal, 10).padding(.top, 8)
      .onDrop(of: [.fileURL], isTargeted: nil) { providers in
        handleDrop(providers)
        return true
      }
  }

  private func fileCard(_ file: ShelfFile) -> some View {
    let hovered = store.shelfPreview == .file(file)
    return Button {
      store.attachShelfFile(file)
    } label: {
      HStack(spacing: 8) {
        if let img = file.thumbnail {
          Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 7))
        } else {
          RoundedRectangle(cornerRadius: 7)
            .fill(Color(red: 0.48, green: 0.36, blue: 1).opacity(0.18))
            .frame(width: 34, height: 34)
            .overlay(Image(systemName: "doc").font(.system(size: 13)).foregroundColor(.white.opacity(0.85)))
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(file.name).font(.system(size: 11.5)).lineLimit(1)
          Text([file.kind == .image ? L("이미지") : L("파일"), file.sizeText]
                .compactMap { $0 }.joined(separator: " · "))
            .font(.system(size: 9.5)).foregroundColor(.secondary)
        }
        Spacer(minLength: 0)
        if store.attached.contains(where: { $0.name == file.name }) {
          Image(systemName: "checkmark.circle.fill").font(.system(size: 11)).foregroundColor(.green)
        }
      }
      .padding(8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(hovered ? 0.12 : 0.06)))
      .overlay(RoundedRectangle(cornerRadius: 10)
        .stroke(Color(red: 0.48, green: 0.36, blue: 1).opacity(hovered ? 0.8 : 0.14), lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L("눌러서 대화에 첨부"))
    .onHover { h in setPreview(h, .file(file)) }
    .contextMenu {
      Button(L("대화에 첨부")) { store.attachShelfFile(file) }
      Button(L("목록에서 제거"), role: .destructive) { store.removeShelfFile(file.id) }
    }
  }

}
