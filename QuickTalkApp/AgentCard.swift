import SwiftUI

// [FEATURE] 도구 실행 카드 — 실제 실행 내역 보기 (PLAN_v0.18 §6)
//
// 대화 안에 붙는 실행 기록.
// - **명령 + 실제 출력(stdout/stderr) + 종료 코드 + 경과시간** 을 그대로 보여준다.
// - 설정 › 도구 › "실행 과정 표시" 를 끄면 한 줄 요약만 남는다(간결 모드).
// - design_profile = custom — 네이티브 alert 를 쓰지 않고 카드형으로 처리한다.

struct AgentCard: View {
  let events: [AgentEvent]
  let approval: AgentApprovalRequest?
  /// 설정 › 도구 › 실행 과정 표시
  var showExecution: Bool = true
  /// 이 카드에서 되돌릴 수 있는 쓰기(v0.19) — 없으면 nil
  var undoEntry: UndoEntry? = nil
  /// 되돌리기 결과 안내
  var undoMessage: String? = nil
  var onAllowOnce: () -> Void = {}
  /// "이 폴더 허용" — 쓰기 범위를 이번 대화 동안 승인한다
  var onAllowScope: () -> Void = {}
  /// "이 앱 허용" — 화면 조작 대상을 이번 대화 동안 승인한다(7일)
  var onAllowApp: () -> Void = {}
  var onAlwaysAllow: () -> Void = {}
  var onDeny: () -> Void = {}
  var onUndo: (() -> Void)? = nil
  /// 진행 중인 실행을 멈춘다(v0.20)
  var onCancel: () -> Void = {}
  /// 터미널로 넘긴 결과 안내
  var handoffNotice: String? = nil
  /// 앱이 실행하지 않은 명령을 터미널로 연다(v0.20)
  var onTerminalHandoff: (String) -> Void = { _ in }

  /// 중요·치명적 명령의 **2차 확인** — 한 번 더 눌러야 실행된다.
  @State private var armed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      if !events.isEmpty {
        VStack(alignment: .leading, spacing: 6) {
          ForEach(events) { event in
            eventView(event)
          }
        }
      }
      // 실행 중인 명령이 있으면 **카드에서 바로** 멈출 수 있게 한다(v0.20).
      if events.contains(where: { $0.state == .running }) {
        HStack {
          Spacer()
          Button(L("중단")) { onCancel() }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(.red)
            .help(L("실행 중인 명령을 멈춥니다"))
        }
      }
      if let handoffNotice {
        Text(handoffNotice)
          .font(.system(size: 10))
          .foregroundColor(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let undoEntry {
        undoRow(undoEntry)
      }
      if let approval {
        approvalBlock(approval)
      }
    }
    .padding(9)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .fill(Color.primary.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
      .stroke(Color.primary.opacity(0.10), lineWidth: 1))
  }

  // MARK: - 실행 1건

  @ViewBuilder
  private func eventView(_ event: AgentEvent) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      header(event)
      if showExecution {
        // 실제 실행한 명령
        if !event.command.isEmpty {
          Text("$ \(event.command)")
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(.primary.opacity(0.85))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 16)
        }
        // 실제 출력
        if !event.output.isEmpty {
          outputBox(event)
        }
      } else {
        // 간결 모드 — 한 줄 요약
        Text(summaryLine(event))
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
          .padding(.leading, 16)
      }
      // 앱이 실행하지 않은 명령 — **터미널로 직접** 열 수 있게 한다(v0.20).
      if let command = event.terminalCommand, !command.isEmpty {
        HStack(spacing: 5) {
          Image(systemName: "terminal")
            .font(.system(size: 10))
            .foregroundColor(.secondary)
          Button(L("터미널에서 열기")) { onTerminalHandoff(command) }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.accentColor)
            .help(L("이 명령을 실행 가능한 파일로 만들어 터미널에서 엽니다 — 앱이 대신 실행하지는 않습니다"))
          Spacer(minLength: 4)
        }
        .padding(.leading, 16)
      }
    }
  }

  private func header(_ event: AgentEvent) -> some View {
    HStack(spacing: 6) {
      Image(systemName: Self.icon(for: event.state))
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(Self.tint(for: event.state))
        .frame(width: 12)
      Text(event.toolName)
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(.secondary)
      Spacer(minLength: 4)
      badge(event.level.displayName, color: event.level == .read ? .secondary : .orange)
      if event.risk != .normal {
        badge(event.risk.displayName, color: event.risk == .critical ? .red : .orange)
      }
      if event.elapsedMs > 0 {
        Text(String(format: "%.1fs", Double(event.elapsedMs) / 1000))
          .font(.system(size: 9.5, design: .monospaced))
          .foregroundColor(.secondary)
      }
    }
  }

  /// 실제 출력 — 스크롤되는 작은 터미널 창
  private func outputBox(_ event: AgentEvent) -> some View {
    ScrollView(.vertical) {
      Text(event.output)
        .font(.system(size: 10, design: .monospaced))
        .foregroundColor(.primary.opacity(0.8))
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }
    .frame(maxHeight: 150)
    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(Color.primary.opacity(0.05)))
    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
      .stroke(Color.primary.opacity(0.08), lineWidth: 1))
    .padding(.leading, 16)
  }

  private func summaryLine(_ event: AgentEvent) -> String {
    let state: String
    switch event.state {
    case .pending: state = L("승인 대기")
    case .running: state = L("실행 중")
    case .allowed: state = L("허용됨")
    case .denied: state = L("거부됨")
    case .done: state = L("완료")
    case .failed: state = L("실패")
    }
    return "\(state) · \(event.level.displayName) · \(event.title)"
  }

  private func badge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9, weight: .semibold))
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Capsule().fill(color.opacity(0.16)))
      .foregroundColor(color)
  }

  // MARK: - 승인 요청

  private func approvalBlock(_ request: AgentApprovalRequest) -> some View {
    VStack(alignment: .leading, spacing: 7) {
      approvalHeader(request)
      // 무엇을 실행하는지 — 명령 전문을 그대로 보여 준다
      Text(request.command)
        .font(.system(size: 11, design: .monospaced))
        .fixedSize(horizontal: false, vertical: true)
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
          .fill(Color.primary.opacity(0.06)))
      // 무엇을 어디에 할지 — 컴퓨터 제어는 대상·이유·되돌릴 수 없음을 함께 보여 준다.
      if let detail = request.detail, !detail.isEmpty {
        Text(detail)
          .font(.system(size: 11))
          .foregroundColor(.primary.opacity(0.85))
          .fixedSize(horizontal: false, vertical: true)
      }
      Text(request.reason)
        .font(.caption)
        .foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      // 위험도 강조 + 2차 확인(v0.20) — 중요·치명적은 한 번 더 확인한다.
      if request.risk != .normal {
        HStack(alignment: .top, spacing: 5) {
          Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundColor(request.risk == .critical ? .red : .orange)
          Text(request.risk == .critical
               ? L("치명적: 복구할 수 없는 변경일 수 있습니다. 정말 실행하려면 [한 번 허용]을 한 번 더 누르세요.")
               : L("중요: 시스템에 영향을 줄 수 있습니다. 정말 실행하려면 [한 번 허용]을 한 번 더 누르세요."))
            .font(.system(size: 10))
            .foregroundColor(request.risk == .critical ? .red : .orange)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill((request.risk == .critical ? Color.red : Color.orange).opacity(0.10)))
        Text(L("중요·치명적 명령은 항상 허용할 수 없습니다 — 실행할 때마다 확인합니다."))
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      // 어떤 폴더를 열게 되는지 — 승인 범위를 숨기지 않는다
      if let scope = request.writeScopes.first {
        Text(Lf("열어 줄 폴더: %@", shortPath(scope)))
          .font(.system(size: 10, design: .monospaced))
          .foregroundColor(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      approvalButtons(request)
    }
    .padding(8)
    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
      .fill(Color.orange.opacity(0.08)))
    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
      .stroke(Color.orange.opacity(0.30), lineWidth: 1))
  }

  private func approvalHeader(_ request: AgentApprovalRequest) -> some View {
    HStack(spacing: 6) {
      Image(systemName: "exclamationmark.shield")
        .font(.system(size: 11))
        .foregroundColor(.orange)
      Text(L("실행 권한이 필요합니다"))
        .font(.system(size: 12, weight: .bold))
      Spacer()
      badge(request.level.displayName, color: .orange)
      if request.risk != .normal {
        badge(request.risk.displayName, color: request.risk == .critical ? .red : .orange)
      }
      // 화면 조작은 파일 백업처럼 되돌릴 수 없다 — 위험도와 별개로 항상 표시한다.
      if request.irreversible {
        badge(L("되돌릴 수 없음"), color: .red)
      }
    }
  }

  private func approvalButtons(_ request: AgentApprovalRequest) -> some View {
    HStack(spacing: 6) {
      Spacer()
      Button(L("거부")) { onDeny() }
        .keyboardShortcut(.cancelAction)
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .foregroundColor(.secondary)
      if let scope = request.writeScopes.first {
        // 이 폴더를 이번 대화 동안 허용 — 같은 폴더의 다음 쓰기는 다시 묻지 않는다(v0.19)
        Button(L("이 폴더 허용")) { onAllowScope() }
          .buttonStyle(.plain)
          .font(.system(size: 12))
          .foregroundColor(Color.accentColor)
          .help(Lf("이번 대화 동안 %@ 폴더의 쓰기를 다시 묻지 않습니다", shortPath(scope)))
      }
      if let app = request.uiAppName, request.uiAppBundleID != nil {
        // 이 앱을 이번 대화 동안 허용 — 7일 뒤 만료(승인 폴더와 같은 모델).
        Button(L("이 앱 허용")) { onAllowApp() }
          .buttonStyle(.plain)
          .font(.system(size: 12))
          .foregroundColor(Color.accentColor)
          .help(Lf("이번 대화에서 %@ 앱 조작을 7일 동안 다시 묻지 않습니다", app))
      }
      // 중요·치명적 명령은 **항상 허용할 수 없다** — 규칙을 저장해도 확인을 건너뛰지 않으므로
      // 버튼을 숨긴다(눌러도 매번 다시 묻던 원인). 화면 조작은 명령 규칙과 무관하므로 숨긴다.
      if request.risk == .normal && request.uiAppBundleID == nil {
        Button(L("항상 허용")) { onAlwaysAllow() }
          .buttonStyle(.plain)
          .font(.system(size: 12))
          .foregroundColor(Color.accentColor)
          .help(L("이 명령을 허용 규칙으로 저장합니다"))
      }
      Button(armed && request.risk != .normal ? L("정말 실행") : L("한 번 허용")) {
        // 중요·치명적은 **2차 확인** — 첫 클릭은 무장만, 두 번째 클릭에서 실행한다(v0.20).
        if request.risk != .normal && !armed {
          armed = true
        } else {
          armed = false
          onAllowOnce()
        }
      }
        .buttonStyle(.plain)
        .font(.system(size: 12, weight: .semibold))
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(armed && request.risk != .normal
                ? (request.risk == .critical ? Color.red : Color.orange)
                : Color.orange))
        .help(request.risk != .normal
              ? L("중요·치명적 명령입니다 — 한 번 더 눌러야 실행됩니다")
              : L("이번에만 허용합니다"))
    }
    .onChange(of: request) { armed = false }
  }

  // MARK: - 되돌리기 (v0.19)

  /// 쓰기 실행 아래 붙는 [되돌리기] 줄 — "이 쓰기는 되돌릴 수 있습니다".
  private func undoRow(_ entry: UndoEntry) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 6) {
        Image(systemName: entry.isUndone ? "arrow.uturn.backward.circle" : "clock.arrow.circlepath")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(entry.isUndone ? .secondary : .blue)
          .frame(width: 12)
        Text(entry.isUndone ? L("되돌렸습니다") : L("이 쓰기는 되돌릴 수 있습니다"))
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
        if !entry.isUndone, let scope = entry.scope.isEmpty ? nil : entry.scope {
          Text(shortPath(scope))
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundColor(.secondary.opacity(0.8))
            .lineLimit(1)
            .truncationMode(.middle)
        }
        Spacer(minLength: 4)
        if !entry.isUndone, onUndo != nil {
          Button(L("되돌리기")) { onUndo?() }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color.accentColor)
            .help(L("이 쓰기 직전 상태로 파일을 되돌립니다"))
        }
      }
      if let undoMessage {
        Text(undoMessage)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .padding(.leading, 18)
      } else if let note = entry.note, !entry.isUndone {
        Text(note)
          .font(.system(size: 10))
          .foregroundColor(.secondary)
          .padding(.leading, 18)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.leading, 2)
  }

  /// `~/Documents` 처럼 홈을 줄여 보여 준다(좁은 카드에서 경로가 길다).
  private func shortPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
  }

  // MARK: - 상태 표시

  static func icon(for state: AgentEvent.State) -> String {
    switch state {
    case .pending: return "clock"
    case .running: return "arrow.triangle.2.circlepath"
    case .allowed: return "checkmark.circle"
    case .denied: return "hand.raised.fill"
    case .done: return "checkmark.circle.fill"
    case .failed: return "xmark.circle.fill"
    }
  }

  static func tint(for state: AgentEvent.State) -> Color {
    switch state {
    case .pending: return .orange
    case .running: return .blue
    case .allowed, .done: return .green
    case .denied: return .secondary
    case .failed: return .red
    }
  }
}
