import SwiftUI
import AppKit

// [REFACTOR] ShelfView — 캡처 탭 (2026-10-20 파일 분리)
extension ShelfView {
  // MARK: 캡처 탭

  var captureTab: some View {
    VStack(spacing: 0) {
      VStack(spacing: 6) {
        captureButton(L("전체 화면"), symbol: "display",
                      shortcut: ShortcutCombo.display(store.settings.captureFullShortcut)) {
          CaptureService.shared.captureFullScreen(into: store)
        }
        captureButton(L("윈도우"), symbol: "macwindow",
                      shortcut: ShortcutCombo.display(store.settings.captureWindowShortcut)) {
          CaptureService.shared.captureWindow(into: store)
        }
        captureButton(L("드래그 선택"), symbol: "selection.pin.in.out",
                      shortcut: ShortcutCombo.display(store.settings.captureRegionShortcut)) {
          CaptureService.shared.captureRegion(into: store)
        }
      }
      .padding(.horizontal, 10).padding(.top, 8)

      if captureItems.isEmpty {
        emptyState(L("캡처가 없습니다"), L("위 버튼으로 전체 화면·윈도우·드래그 캡처를 합니다."))
      } else {
        ScrollView {
          LazyVStack(spacing: 7) {
            ForEach(captureItems) { capture in
              captureCard(capture)
            }
          }
          .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 10)
        }
        .scrollIndicators(.hidden)
      }
    }
  }

  private func captureButton(_ title: String, symbol: String, shortcut: String,
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

  private func captureCard(_ capture: ShelfCapture) -> some View {
    let hovered = store.shelfPreview == .capture(capture)
    return ZStack(alignment: .topTrailing) {
      Button {
        store.attachCapture(capture)
      } label: {
        VStack(alignment: .leading, spacing: 0) {
          ZStack(alignment: .topLeading) {
            if let data = capture.thumbnail, let img = NSImage(data: data) {
              Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(height: 74).frame(maxWidth: .infinity).clipped()
            } else {
              Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 74)
            }
            Text(capture.source.label)
              .font(.system(size: 8.5, weight: .bold))
              .padding(.horizontal, 5).padding(.vertical, 2)
              .background(Capsule().fill(Color.black.opacity(0.6)))
              .foregroundColor(.white.opacity(0.9))
              .padding(5)
          }
          .clipShape(RoundedRectangle(cornerRadius: 8))

          HStack(spacing: 5) {
            Text(capture.sizeText).font(.system(size: 9, design: .monospaced))
            Spacer(minLength: 2)
            if store.attached.contains(where: { $0.name == capture.url.lastPathComponent }) {
              Image(systemName: "checkmark.circle.fill").font(.system(size: 9)).foregroundColor(.green)
              Text(L("첨부됨")).font(.system(size: 9)).foregroundColor(.green)
            } else {
              Text(L("클릭 → 첨부")).font(.system(size: 9))
            }
          }
          .foregroundColor(.secondary)
          .padding(.top, 6)
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

      // 선택(호버) 후 툴바 — 첨부와 별개로 복사·저장·Finder 열기
      if hovered {
        HStack(spacing: 2) {
          captureAction("doc.on.doc", L("클립보드에 복사")) { store.copyCapture(capture) }
          captureAction("square.and.arrow.down", L("다른 이름으로 저장")) {
            store.saveCaptureAs(capture)
          }
          captureAction("folder", L("Finder에서 보기")) {
            NSWorkspace.shared.activateFileViewerSelecting([capture.url])
          }
        }
        .padding(3)
        .background(Capsule().fill(Color.black.opacity(0.62)))
        .padding(5)
        .transition(.opacity)
      }
    }
    .onHover { h in setPreview(h, .capture(capture)) }
    .contextMenu {
      Button(L("대화에 첨부")) { store.attachCapture(capture) }
      Button(L("클립보드에 복사")) { store.copyCapture(capture) }
      Button(L("다른 이름으로 저장")) { store.saveCaptureAs(capture) }
      Button(L("Finder에서 보기")) { NSWorkspace.shared.activateFileViewerSelecting([capture.url]) }
      Button(L("삭제"), role: .destructive) { store.removeCapture(capture.id) }
    }
  }

  private func captureAction(_ symbol: String, _ help: String,
                             action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 9, weight: .semibold))
        .foregroundColor(.white.opacity(0.92))
        .frame(width: 20, height: 20)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
  }

}
