import SwiftUI
import AppKit

// [FEATURE] v0.26 비서 — 설정 › 비서 탭과 페르소나 편집 시트.
//
// **비서는 선택 사항**이다. 목록이 비어 있으면 "새 비서" 안내만 보이고,
// 대화 화면·프롬프트는 지금과 완전히 동일하게 동작한다.
//
// 일정 목록은 `/할일` 시트와 같은 뷰를 쓴다(중복 구현 금지) — 여기서는 페르소나와
// 기본값(리포트 폴더·알림·야간 무음)만 관리한다.

extension UIStore {
  /// 저장된 비서를 찾는다. nil·없는 ID 면 nil(= 기본).
  func persona(_ id: UUID?) -> Persona? { settings.persona(id) }

  /// 추가/수정 — 이름이 비면 저장하지 않는다.
  func upsertPersona(_ persona: Persona) {
    let p = persona.normalized()
    guard p.isValid else { return }
    var list = settings.personas
    if let index = list.firstIndex(where: { $0.id == p.id }) {
      list[index] = p
    } else {
      list.append(p)
    }
    settings.personas = list
  }

  /// 삭제. 이 비서를 가리키던 일정은 **기본(비서 없음)** 으로 남는다 —
  /// 여기서 일정을 지우지 않는다(리포트·이력 보존). 일정의 비서 재지정은 `/할일`에서.
  func deletePersona(_ id: UUID) {
    settings.personas.removeAll { $0.id == id }
    if settings.defaultPersonaID == id { settings.defaultPersonaID = nil }
  }
}

// MARK: - 설정 › 비서

struct AssistantSettingsSection: View {
  @EnvironmentObject var store: UIStore
  @State private var editingPersona: Persona?
  @State private var isNewPersona = false
  @State private var deletingPersona: Persona?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      personaCard
      reportCard
      scheduleCard

      Text(L("비서를 만들지 않으면 지금과 똑같이 동작합니다. 대화마다 비서를 고를 수 있고, 고르지 않으면 기본(비서 없음)입니다."))
        .font(.caption).foregroundColor(.secondary)
        .padding(.leading, 2)
        .fixedSize(horizontal: false, vertical: true)
    }
    .sheet(item: $editingPersona) { persona in
      PersonaEditorSheet(persona: persona, isNew: isNewPersona) { saved in
        store.upsertPersona(saved)
        editingPersona = nil
      } onCancel: {
        editingPersona = nil
      }
      .environmentObject(store)
    }
    .sheet(item: $deletingPersona) { persona in
      DeleteConfirmSheet(
        heading: L("비서를 삭제할까요?"),
        target: persona.name,
        message: L("예약 작업은 지워지지 않고 기본(비서 없음)으로 실행됩니다. 지난 리포트 파일도 그대로 남습니다."),
        confirmLabel: L("삭제")
      ) {
        store.deletePersona(persona.id)
      }
    }
  }

  // MARK: 비서 목록

  private var personaCard: some View {
    groupBox(L("비서")) {
      if store.settings.personas.isEmpty {
        emptyState
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(store.settings.personas) { persona in
            personaRow(persona)
            if persona.id != store.settings.personas.last?.id { Divider() }
          }
        }

        HStack {
          Button {
            isNewPersona = true
            editingPersona = Persona(name: "", role: "", tone: "",
                                     tools: .readOnly,
                                     reportFolder: nil)
          } label: {
            Label(L("새 비서"), systemImage: "plus")
          }
          Spacer()
        }
        .padding(.top, 2)

        if store.settings.personas.count > 1 {
          defaultPersonaRow
        }
      }
    }
  }

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("아직 비서가 없습니다."))
        .font(.body)
        .foregroundColor(.secondary)
      Button {
        isNewPersona = true
        editingPersona = Persona(name: "", role: "", tone: "",
                                 tools: .readOnly,
                                 reportFolder: nil)
      } label: {
        Label(L("첫 비서 만들기"), systemImage: "plus")
      }
      caption(L("예: 돌쇠 — 매일 아침 테크 소식을 정리하고, 짧고 차분한 존댓말로 보고합니다."))
    }
    .padding(.vertical, 2)
  }

  /// 비서가 예약 실행에 쓸 AI — `프로바이더 · 모델`.
  func personaAI(_ persona: Persona) -> String {
    let provider = persona.providerID.flatMap { store.settings.provider($0) }
      ?? store.settings.activeProvider
    let name = provider?.displayName ?? L("설정의 활성 AI")
    let model = persona.normalized().model ?? provider?.model ?? ""
    return model.isEmpty ? name : "\(name) · \(model)"
  }

  private func personaRow(_ persona: Persona) -> some View {
    HStack(alignment: .center, spacing: 10) {
      Text(persona.displayEmoji)
        .font(.system(size: 18))
        .frame(width: 30, height: 30)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(persona.name).font(.body).fontWeight(.semibold)
          if store.settings.defaultPersonaID == persona.id {
            Text(L("새 대화 기본"))
              .font(.caption2)
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(Color.accentColor.opacity(0.14))
              .foregroundColor(.accentColor)
              .clipShape(Capsule())
          }
        }
        Text(persona.subtitle).font(.caption).foregroundColor(.secondary)
          .lineLimit(1)
        Text(personaAI(persona)).font(.caption2).foregroundColor(.secondary)
          .lineLimit(1).truncationMode(.middle)
        Text(persona.tools.summary).font(.caption2).foregroundColor(.secondary)
          .lineLimit(1)
      }

      Spacer()

      Button(L("편집")) {
        isNewPersona = false
        editingPersona = persona
      }
      Button {
        deletingPersona = persona
      } label: {
        Image(systemName: "trash")
      }
      .buttonStyle(.borderless)
      .foregroundColor(.secondary)
      .help(L("삭제"))
    }
    .padding(.vertical, 4)
  }

  private var defaultPersonaRow: some View {
    pickerRow(L("새 대화 기본 비서"), selection: Binding(
      get: { store.settings.defaultPersonaID },
      set: { store.settings.defaultPersonaID = $0 }
    ), options: [(UUID?.none, L("기본(비서 없음)"))] +
      store.settings.personas.map { (Optional($0.id), $0.name) })
  }

  // MARK: 작업 폴더

  private var reportCard: some View {
    groupBox(L("작업 폴더")) {
      HStack(alignment: .center, spacing: 10) {
        Image(systemName: "folder")
          .foregroundColor(.secondary)
        VStack(alignment: .leading, spacing: 2) {
          Text(displayPath(store.settings.reportFolderPath))
            .font(.callout)
            .lineLimit(1)
            .truncationMode(.middle)
            .textSelection(.enabled)
          Text(L("도우미가 만든 파일과 예약 리포트가 저장되는 곳입니다."))
            .font(.caption).foregroundColor(.secondary)
        }
        Spacer()
        Button(L("변경…")) { chooseReportFolder() }
        Button(L("기본값")) {
          store.settings.defaultReportFolder = WorkspaceFolder.defaultPath
        }
        .disabled(store.settings.defaultReportFolder == WorkspaceFolder.defaultPath)
      }
      caption(L("폴더가 없으면 실행할 때 만듭니다. 사용자 홈 폴더 밖은 허용하지 않습니다."))
    }
  }

  private func chooseReportFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = URL(fileURLWithPath: store.settings.reportFolderPath, isDirectory: true)
    panel.prompt = L("선택")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    store.settings.defaultReportFolder = url.path
  }

  // MARK: 예약·알림

  private var scheduleCard: some View {
    groupBox(L("예약·알림")) {
      toggleRow(L("예약 작업 실행"), isOn: $store.settings.schedulerEnabled,
                description: L("앱이 실행 중일 때만 동작합니다. 앱을 다시 열면 최근 24시간 안에 놓친 작업 1회를 따라잡습니다."))
      toggleRow(L("완료 알림"), isOn: $store.settings.notificationsEnabled,
                description: L("예약 작업이 끝나면 배너와 소리로 알립니다."))
      toggleRow(L("승인 대기 알림"), isOn: $store.settings.notifyOnApproval,
                description: L("권한이 필요해 멈춘 순간에만 따로 알립니다. 알림에서 바로 승인할 수는 없습니다."))
        .disabled(!store.settings.notificationsEnabled)
      toggleRow(L("야간 무음"), isOn: $store.settings.quietHoursEnabled,
                description: L("이 시간에는 소리 없이 배너만 보여 줍니다."))
        .disabled(!store.settings.notificationsEnabled)
      if store.settings.notificationsEnabled && store.settings.quietHoursEnabled {
        HStack(spacing: 10) {
          Text(L("무음 시간")).font(.body)
          Spacer()
          timePicker($store.settings.quietHoursFromMinute)
          Text("–").foregroundColor(.secondary)
          timePicker($store.settings.quietHoursToMinute)
        }
        .padding(.vertical, 2)
      }
      if store.settings.notificationsEnabled {
        notificationPermissionRow
      }
    }
    .onChange(of: store.settings.notificationsEnabled) { _, on in
      guard on else { return }
      Task { await store.notifications?.requestAuthorizationIfNeeded() }
    }
  }

  /// 알림 권한 안내 — 거부돼도 예약 실행은 계속되고, 알림만 오지 않는다(PLAN S8).
  @ViewBuilder private var notificationPermissionRow: some View {
    switch store.notificationPermission {
    case .denied:
      permissionHint(
        icon: "exclamationmark.triangle.fill", tint: .orange,
        text: L("알림이 시스템 설정에서 꺼져 있습니다. 예약 작업은 계속 실행되지만 알림은 오지 않습니다."))
    case .unknown:
      permissionHint(
        icon: "bell.badge", tint: .accentColor,
        text: L("예약 작업이 끝나거나 승인이 필요할 때 알림을 받으려면 권한이 필요합니다."),
        action: L("알림 허용")) {
          Task { await store.notifications?.requestAuthorizationIfNeeded() }
        }
    case .allowed:
      HStack(spacing: 6) {
        Image(systemName: "checkmark.circle.fill")
          .font(.caption).foregroundColor(.green)
        Text(L("알림 권한이 허용되어 있습니다."))
          .font(.caption).foregroundColor(.secondary)
        Spacer()
        Button(L("시스템 설정 열기")) { store.notifications?.openSystemSettings() }
          .controlSize(.small)
      }
      .padding(.top, 2)
    }
  }

  private func permissionHint(icon: String, tint: Color, text: String,
                              action: String? = nil,
                              run: @escaping () -> Void = {}) -> some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: icon).font(.caption).foregroundColor(tint)
      Text(text)
        .font(.caption).foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      Button(action ?? L("시스템 설정 열기")) {
        if action == nil { store.notifications?.openSystemSettings() } else { run() }
      }
      .controlSize(.small)
    }
    .padding(.top, 2)
  }

  /// 자정 기준 분(minute)을 시각 선택기로 — 22:00~08:00 처럼 자정을 넘겨도 된다.
  private func timePicker(_ minutes: Binding<Int>) -> some View {
    DatePicker("", selection: Binding(
      get: {
        var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        c.hour = minutes.wrappedValue / 60
        c.minute = minutes.wrappedValue % 60
        return Calendar.current.date(from: c) ?? Date()
      },
      set: { date in
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        minutes.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
      }
    ), displayedComponents: .hourAndMinute)
    .labelsHidden()
    .datePickerStyle(.stepperField)
  }

  private func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }

  // MARK: - 설정 창과 같은 행 스타일 (이 섹션은 독립 뷰라 헬퍼를 함께 둔다)

  private func groupBox<Content: View>(_ title: String,
                                       @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title).font(.headline).padding(.leading, 12)
      VStack(alignment: .leading, spacing: 6) { content() }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
      .padding(.leading, 2)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func toggleRow(_ label: String, isOn: Binding<Bool>,
                         description: String? = nil) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack {
        Text(label).font(.body)
        Spacer()
        Toggle("", isOn: isOn).labelsHidden().toggleStyle(.switch)
      }
      if let description { caption(description) }
    }
    .padding(.vertical, 2)
  }

  private func pickerRow<T: Hashable>(_ label: String, selection: Binding<T>,
                                      options: [(T, String)]) -> some View {
    HStack {
      Text(label).font(.body)
      Spacer(minLength: 12)
      Picker("", selection: selection) {
        ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
      }
      .labelsHidden()
      .pickerStyle(.menu)
      .frame(minWidth: 180, maxWidth: 280, alignment: .trailing)
    }
    .padding(.vertical, 2)
  }
}

// MARK: - 비서 편집 시트

struct PersonaEditorSheet: View {
  @EnvironmentObject var store: UIStore
  @Environment(\.dismiss) private var dismiss

  let isNew: Bool
  let onSave: (Persona) -> Void
  let onCancel: () -> Void

  @State private var draft: Persona
  /// 비서별 작업 폴더 덮어쓰기 사용 여부.
  @State private var useCustomFolder: Bool

  init(persona: Persona, isNew: Bool,
       onSave: @escaping (Persona) -> Void,
       onCancel: @escaping () -> Void) {
    self.isNew = isNew
    self.onSave = onSave
    self.onCancel = onCancel
    _draft = State(initialValue: persona)
    _useCustomFolder = State(initialValue: persona.reportFolder != nil)
  }

  /// 비서가 실제로 쓸 AI — 꺼진 프로바이더는 활성 AI로 폴백한다(`ProviderResolver`).
  private var resolution: ProviderResolution {
    ProviderResolver.resolve(settings: store.settings, persona: draft)
  }

  private var resolvedProvider: LLMProviderConfig? { resolution.provider }

  /// "프로바이더 · 모델" — 비서가 모델을 덮어쓰면 그 값을 보여 준다.
  private var aiLabel: String {
    guard let provider = resolvedProvider else { return L("설정의 활성 AI") }
    return provider.model.isEmpty ? provider.displayName
      : "\(provider.displayName) · \(provider.model)"
  }

  /// 이 비서의 실제 저장 경로(아직 저장하지 않은 초안도 포함해 계산).
  private var effectiveReportFolder: String {
    var all = store.settings.personas
    all.removeAll { $0.id == draft.id }
    all.append(draft)
    return PersonaReports.folder(settings: store.settings, persona: draft, all: all)
  }

  private var sharedFolderPeers: [Persona] {
    PersonaReports.sharedExplicitPeers(persona: draft, all: store.settings.personas)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(isNew ? L("새 비서") : L("비서 편집"))
        .font(.headline)
        .padding([.horizontal, .top], 16)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
              Text(L("아이콘")).font(.caption).foregroundColor(.secondary)
              Text(draft.displayEmoji).font(.system(size: 13))
              Spacer()
            }
            PersonaIconGrid(selection: Binding(
              get: { draft.emoji },
              set: { draft.emoji = $0 }
            ))
            caption(L("아이콘은 목록·답변·알림에 같은 표시로 쓰입니다."))
          }

          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(L("이름")).font(.caption).foregroundColor(.secondary)
              Spacer()
              Text(Lf("%d자", draft.name.count))
                .font(.caption2)
                .foregroundColor(draft.name.count > Persona.Limits.name ? .red : .secondary)
            }
            TextField(L("예: 돌쇠"), text: $draft.name)
              .textFieldStyle(.roundedBorder)
          }

          field(L("담당 (역할)"), limit: Persona.Limits.role,
                placeholder: L("예: 매일 아침 테크 소식을 정리하는 비서"),
                text: $draft.role)
          field(L("말투"), limit: Persona.Limits.tone,
                placeholder: L("예: 짧고 차분한 존댓말, 이모지는 쓰지 않음"),
                text: $draft.tone)

          caption(L("역할·말투는 답변 스타일만 정합니다. 권한·도구 규칙은 설정 › 도구·권한을 그대로 따릅니다."))

          Divider()

          VStack(alignment: .leading, spacing: 4) {
            Text(L("이 비서의 AI")).font(.body)
            Picker("", selection: Binding(
              get: { draft.providerID ?? "" },
              set: { draft.providerID = $0.isEmpty ? nil : $0 }
            )) {
              Text(L("설정의 활성 AI")).tag("")
              ForEach(store.settings.providers.filter(\.enabled)) { p in
                Text(p.name).tag(p.id)
              }
            }
            .labelsHidden().pickerStyle(.menu)
            Text(aiLabel)
              .font(.caption).foregroundColor(.secondary)
              .textSelection(.enabled)
            if let warning = resolution.warning {
              Text(warning)
                .font(.caption).foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)
            }
            TextField(L("모델 (비우면 프로바이더 모델)"), text: Binding(
              get: { draft.model ?? "" },
              set: { draft.model = $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            let choices = store.modelChoices(for: resolvedProvider)
            if !choices.isEmpty {
              Picker(L("불러온 모델"), selection: Binding(
                get: { draft.model ?? "" },
                set: { draft.model = $0.isEmpty ? nil : $0 }
              )) {
                Text(L("프로바이더 모델")).tag("")
                ForEach(choices, id: \.self) { Text($0).tag($0) }
              }
              .labelsHidden().pickerStyle(.menu)
            }
            caption(L("대화와 예약 실행 모두에 적용됩니다. 비우면 설정 › AI의 활성 AI를 따릅니다."))
          }

          Divider()

          VStack(alignment: .leading, spacing: 6) {
            Text(L("도구")).font(.body)
            toolToggle(L("파일 읽기"), L("파일·폴더·프로세스·화면을 읽습니다."), $draft.tools.read)
            toolToggle(L("웹 검색"), L("최신 소식을 확인합니다."), $draft.tools.web)
            toolToggle(L("셸"), L("명령을 실행합니다. 실행할 때마다 승인을 받습니다."), $draft.tools.shell)
            toolToggle(L("파일 쓰기"), L("작업 폴더에 파일을 만듭니다."), $draft.tools.write)
            toolToggle(L("앱 조작"), L("다른 앱의 화면 요소를 클릭·입력합니다."), $draft.tools.ui)
            caption(L("도구를 꺼도 실행 권한이 느슨해지지 않습니다. 승인 없는 실행은 없습니다."))
          }

          Divider()

          Toggle(L("이 비서만 다른 작업 폴더 사용"), isOn: $useCustomFolder)
            .toggleStyle(.switch)
            .onChange(of: useCustomFolder) { _, on in
              if !on { draft.reportFolder = nil }
            }
          if useCustomFolder {
            HStack(spacing: 8) {
              Text(displayPath(draft.reportFolder ?? store.settings.reportFolderPath))
                .font(.callout)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
              Spacer()
              Button(L("변경…")) { chooseFolder() }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            if !sharedFolderPeers.isEmpty {
              Text(L("여러 비서가 같은 폴더를 씁니다."))
                .font(.caption).foregroundColor(.orange)
            }
          } else {
            caption(Lf("저장 위치: %@ (이 비서의 폴더)", displayPath(effectiveReportFolder)))
          }
        }
        .padding(16)
      }

      Divider()
      HStack {
        Button(L("취소")) {
          onCancel()
          dismiss()
        }
        Spacer()
        Button(isNew ? L("추가") : L("저장")) {
          onSave(draft.normalized())
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(16)
    }
    .frame(width: 540, height: 600)
  }

  private func field(_ label: String, limit: Int, placeholder: String,
                     text: Binding<String>) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(label).font(.body)
        Spacer()
        Text(Lf("%d자", text.wrappedValue.count))
          .font(.caption2)
          .foregroundColor(text.wrappedValue.count > limit ? .red : .secondary)
      }
      TextField(placeholder, text: text, axis: .vertical)
        .lineLimit(1...3)
        .textFieldStyle(.roundedBorder)
    }
  }

  private func toolToggle(_ label: String, _ description: String,
                          _ binding: Binding<Bool>) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Toggle("", isOn: binding)
        .labelsHidden().toggleStyle(.switch).controlSize(.small)
        .padding(.top, 2)
      VStack(alignment: .leading, spacing: 1) {
        Text(label).font(.callout)
        Text(description).font(.caption).foregroundColor(.secondary)
      }
      Spacer()
    }
  }

  private func caption(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundColor(.secondary)
      .fixedSize(horizontal: false, vertical: true)
  }

  private func displayPath(_ path: String) -> String {
    let home = NSHomeDirectory()
    return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
  }

  private func chooseFolder() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.directoryURL = URL(fileURLWithPath: store.settings.reportFolderPath, isDirectory: true)
    panel.prompt = L("선택")
    guard panel.runModal() == .OK, let url = panel.url else { return }
    draft.reportFolder = url.path
  }
}

// MARK: - 비서 아이콘 선택 (v0.28)

/// 아이콘 텍스트필드 대신 **20개 프리셋을 나열**한다.
/// 목록에 없는 이모지를 쓰던 기존 비서는 그 값을 첫 칸에 함께 보여 준다(저장 값 유지).
struct PersonaIconGrid: View {
  @Binding var selection: String?

  private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 10)

  private var icons: [String] {
    guard let custom = selection, !Persona.iconChoices.contains(custom) else {
      return Persona.iconChoices
    }
    return [custom] + Persona.iconChoices
  }

  var body: some View {
    LazyVGrid(columns: columns, spacing: 6) {
      ForEach(icons, id: \.self) { icon in
        let selected = selection == icon
        Button { selection = icon } label: {
          Text(icon)
            .font(.system(size: 15))
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
              .fill(selected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
              .stroke(selected ? Color.accentColor : Color.clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(icon))
      }
    }
  }
}
