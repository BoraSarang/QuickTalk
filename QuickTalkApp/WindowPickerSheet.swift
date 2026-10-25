import SwiftUI
import AppKit

// [INFO] [FEATURE] 창 연결 시트 (P0-1)
//
// Meta AI의 "창 연결"에서 **목록·권한·미리보기**만 가져왔다. 조작(클릭·입력)은 없다.
// - 창을 고르면 "QuickTalk가 읽을 내용"을 먼저 보여준다 → 무엇이 모델로 가는지 숨기지 않는다.
// - 권한이 하나라도 없으면 카드로 알리고, 그 자리에서 설정을 열 수 있다.
// - 읽기 전용·단일 스냅샷이라는 사실은 첨부 본문(WindowContextPrompt)에도 적힌다.

struct WindowPickerSheet: View {
  @ObservedObject var store: UIStore
  @Environment(\.dismiss) private var dismiss

  @State private var windows: [WindowTarget] = []
  @State private var icons: [pid_t: NSImage] = [:]
  @State private var selectedID: CGWindowID?
  @State private var query = ""
  @State private var loading = true
  @State private var loadError: String?
  @State private var preview = ""
  @State private var previewLoading = false
  @State private var attaching = false
  @State private var attachError: String?
  @State private var hasScreen = WindowAttachmentService.hasScreenPermission
  @State private var hasAX = WindowAttachmentService.hasAccessibilityPermission
  @State private var previewTask: Task<Void, Never>?

  private var selected: WindowTarget? {
    windows.first { $0.id == selectedID }
  }

  private var filtered: [WindowTarget] {
    let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return windows }
    return windows.filter {
      $0.displayTitle.lowercased().contains(q) || $0.appName.lowercased().contains(q)
    }
  }

  private var canAttach: Bool {
    selected != nil && !attaching && !loading
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      if !hasScreen || !hasAX { permissionCard }
      windowList
      previewCard
      footer
    }
    .padding(16)
    .frame(width: 500, height: 580)
    .task { await reload() }
    .onChange(of: selectedID) { _, _ in schedulePreview() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
      // 설정에서 권한을 켜고 돌아온 경우 — 앱 재실행 전이라도 상태를 다시 읽는다.
      let screen = WindowAttachmentService.hasScreenPermission
      let ax = WindowAttachmentService.hasAccessibilityPermission
      let gainedScreen = !hasScreen && screen
      hasScreen = screen
      hasAX = ax
      if gainedScreen, windows.isEmpty { Task { await reload() } }
    }
    .onDisappear { previewTask?.cancel() }
  }

  // MARK: - 머리말

  private var header: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: "macwindow.on.rectangle")
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(.white)
        .frame(width: 28, height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.purple))
      VStack(alignment: .leading, spacing: 2) {
        Text(L("창 연결")).font(.system(size: 14, weight: .bold))
        Text(L("창 하나의 화면 텍스트와 스크린샷을 이번 질문의 참고 자료로 붙입니다. 읽기만 하며 창을 조작하지 않습니다."))
          .font(.system(size: 11)).foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      Button { Task { await reload() } } label: {
        Image(systemName: "arrow.clockwise")
          .font(.system(size: 11, weight: .semibold))
          .frame(width: 24, height: 24)
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .disabled(loading)
      .help(L("창 목록 새로 고침"))
    }
  }

  // MARK: - 권한

  private var permissionCard: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(L("권한이 필요합니다"))
        .font(.system(size: 11, weight: .semibold))
      if !hasScreen {
        permissionRow(icon: "rectangle.dashed.badge.record",
                      title: L("화면 기록"),
                      detail: L("창 목록과 스크린샷에 필요합니다."),
                      actionLabel: L("설정 열기")) {
          CaptureService.openScreenRecordingSettings()
        }
      }
      if !hasAX {
        permissionRow(icon: "hand.raised",
                      title: L("손쉬운 사용"),
                      detail: L("글자를 읽는 데 필요합니다(없으면 스크린샷만)."),
                      actionLabel: L("권한 요청")) {
          WindowAttachmentService.requestAccessibility()
          hasAX = WindowAttachmentService.hasAccessibilityPermission
        }
      }
      Text(L("권한을 허용한 뒤에는 앱을 다시 실행해야 반영됩니다."))
        .font(.system(size: 10)).foregroundColor(.secondary)
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.orange.opacity(0.10)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.orange.opacity(0.35), lineWidth: 1))
  }

  private func permissionRow(icon: String, title: String, detail: String,
                             actionLabel: String, action: @escaping () -> Void) -> some View {
    HStack(spacing: 8) {
      Image(systemName: icon)
        .font(.system(size: 11))
        .foregroundColor(.orange)
        .frame(width: 16)
      Text(title).font(.system(size: 11, weight: .semibold))
      Text(detail).font(.system(size: 10.5)).foregroundColor(.secondary)
      Spacer(minLength: 6)
      Button(action: action) {
        Text(actionLabel)
          .font(.system(size: 10.5, weight: .semibold))
          .padding(.horizontal, 8).padding(.vertical, 3)
          .background(Capsule().fill(Color.orange.opacity(0.18)))
          .overlay(Capsule().stroke(Color.orange.opacity(0.45), lineWidth: 1))
          .contentShape(Capsule())
      }
      .buttonStyle(.plain)
      .help(actionLabel)
    }
  }

  // MARK: - 창 목록

  private var windowList: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        Text(L("창 선택")).font(.system(size: 11, weight: .semibold))
        Text(Lf("%d개", windows.count)).font(.system(size: 10)).foregroundColor(.secondary)
        Spacer()
        TextField(L("앱·창 제목으로 찾기"), text: $query)
          .textFieldStyle(.plain)
          .font(.system(size: 11))
          .padding(.horizontal, 8).padding(.vertical, 4)
          .frame(width: 190)
          .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(0.06)))
          .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .stroke(Color.primary.opacity(0.10), lineWidth: 1))
      }

      ScrollView {
        LazyVStack(spacing: 2) {
          if loading {
            HStack(spacing: 8) {
              ProgressView().controlSize(.small)
              Text(L("창 목록을 읽는 중…")).font(.system(size: 11)).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
          } else if let loadError {
            Text(loadError)
              .font(.system(size: 11)).foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 24)
          } else if filtered.isEmpty {
            Text(windows.isEmpty ? L("연결할 창이 없습니다.") : L("찾는 창이 없습니다."))
              .font(.system(size: 11)).foregroundColor(.secondary)
              .frame(maxWidth: .infinity, alignment: .center)
              .padding(.vertical, 24)
          } else {
            ForEach(filtered) { target in
              row(target)
            }
          }
        }
        .padding(4)
      }
      .frame(minHeight: 140, maxHeight: .infinity)
      .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Color.primary.opacity(0.04)))
      .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
  }

  private func row(_ target: WindowTarget) -> some View {
    let isSelected = target.id == selectedID
    return Button { selectedID = target.id } label: {
      HStack(spacing: 8) {
        if let icon = icons[target.pid] {
          Image(nsImage: icon).resizable().frame(width: 18, height: 18)
        } else {
          Image(systemName: "macwindow")
            .font(.system(size: 12)).foregroundColor(.secondary)
            .frame(width: 18, height: 18)
        }
        VStack(alignment: .leading, spacing: 1) {
          Text(target.displayTitle)
            .font(.system(size: 12, weight: .medium))
            .lineLimit(1).truncationMode(.middle)
          Text(Lf("%@ · %d×%d", target.appName,
                  Int(target.width.rounded()), Int(target.height.rounded())))
            .font(.system(size: 10)).foregroundColor(.secondary)
            .lineLimit(1)
        }
        Spacer(minLength: 6)
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 12)).foregroundColor(.purple)
        }
      }
      .padding(.horizontal, 8).padding(.vertical, 6)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(isSelected ? Color.purple.opacity(0.14) : Color.clear))
      .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
        .stroke(isSelected ? Color.purple.opacity(0.40) : Color.clear, lineWidth: 1))
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(target.displayTitle)
  }

  // MARK: - 미리보기

  private var previewCard: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack(spacing: 6) {
        Text(L("QuickTalk가 읽을 내용")).font(.system(size: 11, weight: .semibold))
        if previewLoading { ProgressView().controlSize(.small).scaleEffect(0.7) }
        Spacer()
        if !preview.isEmpty {
          Text(Lf("%d자", preview.count)).font(.system(size: 10)).foregroundColor(.secondary)
        }
        if !hasScreen {
          Text(L("스크린샷 없음")).font(.system(size: 10)).foregroundColor(.secondary)
        }
      }
      ScrollView {
        Text(previewDisplay)
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundColor(preview.isEmpty ? .secondary : .primary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .textSelection(.enabled)
          .padding(8)
      }
      .frame(height: 110)
      .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
        .fill(Color.primary.opacity(0.05)))
      .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
        .stroke(Color.primary.opacity(0.10), lineWidth: 1))
    }
  }

  private var previewDisplay: String {
    guard let target = selected else { return L("창을 고르면 여기에 읽을 내용이 보입니다.") }
    if !hasAX { return L("손쉬운 사용 권한이 없어 글자를 읽을 수 없습니다 — 스크린샷만 전송됩니다.") }
    if preview.isEmpty {
      return previewLoading ? L("읽는 중…") : L("읽을 수 있는 텍스트가 없습니다 — 스크린샷만 전송됩니다.")
    }
    // 긴 창은 앞부분만 보여준다(전체는 첨부 파일로 그대로 간다).
    return WindowContextPrompt.previewText(WindowSnapshot(target: target, text: preview))
  }

  // MARK: - 바닥

  private var footer: some View {
    HStack(spacing: 8) {
      if let attachError {
        Image(systemName: "exclamationmark.triangle.fill")
          .font(.system(size: 10)).foregroundColor(.orange)
        Text(attachError).font(.system(size: 10.5)).foregroundColor(.orange)
          .lineLimit(2)
      } else {
        Text(!hasScreen
             ? L("화면 기록 권한이 필요합니다.")
             : (hasAX ? L("텍스트와 스크린샷을 함께 붙입니다.")
                      : L("손쉬운 사용 권한이 없어 스크린샷만 붙입니다.")))
          .font(.system(size: 10.5)).foregroundColor(.secondary)
      }
      Spacer(minLength: 8)
      Button(L("취소")) { dismiss() }
        .keyboardShortcut(.cancelAction)
        .disabled(attaching)
      Button {
        Task { await attachSelected() }
      } label: {
        HStack(spacing: 5) {
          if attaching { ProgressView().controlSize(.small).scaleEffect(0.7) }
          Text(attaching ? L("읽는 중…") : L("연결"))
            .font(.system(size: 12, weight: .semibold))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(canAttach ? Color.purple : Color.secondary.opacity(0.35)))
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .keyboardShortcut(.defaultAction)
      .disabled(!canAttach)
      .help(L("이 창을 참고 자료로 붙입니다"))
    }
  }

  // MARK: - 동작

  private func reload() async {
    loading = true
    loadError = nil
    hasScreen = WindowAttachmentService.hasScreenPermission
    hasAX = WindowAttachmentService.hasAccessibilityPermission
    // 창 목록 자체가 화면 기록 권한을 요구한다(SCShareableContent) — 없으면 목록을 시도하지 않는다.
    guard hasScreen else {
      windows = []
      selectedID = nil
      loadError = L("화면 기록 권한이 없어 창 목록을 볼 수 없습니다 — 시스템 설정에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요.")
      loading = false
      return
    }
    do {
      let found = try await WindowAttachmentService.listWindows()
      windows = found
      for w in found where icons[w.pid] == nil {
        if let icon = NSRunningApplication(processIdentifier: w.pid)?.icon {
          icons[w.pid] = icon
        }
      }
      if selectedID == nil || !found.contains(where: { $0.id == selectedID }) {
        selectedID = found.first?.id
      }
    } catch {
      windows = []
      loadError = (error as? WindowAttachError)?.message ?? L("창 목록을 읽지 못했습니다.")
    }
    loading = false
  }

  private func schedulePreview() {
    previewTask?.cancel()
    preview = ""
    previewLoading = false
    guard let target = selected else { return }
    guard hasAX else { return }
    previewLoading = true
    previewTask = Task {
      // 목록을 훑을 때 창을 빠르게 바꿔도 마지막 것만 읽는다.
      try? await Task.sleep(nanoseconds: 220_000_000)
      guard !Task.isCancelled else { return }
      let result = await WindowAttachmentService.shared.preview(target)
      guard !Task.isCancelled, selectedID == target.id else { return }
      preview = result.text
      previewLoading = false
    }
  }

  private func attachSelected() async {
    guard let target = selected else { return }
    attaching = true
    attachError = nil
    do {
      try await WindowAttachmentService.shared.attach(target, into: store)
      dismiss()
    } catch {
      attachError = (error as? WindowAttachError)?.message ?? L("창을 연결하지 못했습니다.")
      attaching = false
    }
  }
}
