import SwiftUI

// [FEATURE] `/할일` — 예약 작업 목록·편집 시트 (v0.26 4단계)
//
// · 이 시트가 일정의 **유일한 관리 창구**다. 모델에게 삭제 도구를 주지 않는 대신
//   사람이 여기서 지우고 고친다(PLAN §7).
// · 카드에는 다음 실행·마지막 결과·리포트 경로가 보인다.
// · 새 일정은 모델의 `schedule_task` 제안과 **같은 검증**(`ScheduleProposal`)을 거치지 않는다 —
//   사람이 직접 입력하므로 형식 오류가 없다.

struct TaskListSheet: View {
  @EnvironmentObject var store: UIStore
  @Environment(\.dismiss) private var dismiss

  @State private var editing: ScheduledTask?
  @State private var isNew = false
  @State private var deleting: ScheduledTask?
  @State private var nowTick = Date()

  private var tasks: [ScheduledTask] { store.schedulerService?.tasks ?? [] }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Image(systemName: "calendar.badge.clock")
          .foregroundColor(.purple)
        Text(L("할일")).font(.headline)
        if !tasks.isEmpty {
          Text(Lf("%d개", tasks.count))
            .font(.caption).foregroundColor(.secondary)
        }
        Spacer()
        Button {
          isNew = true
          editing = ScheduledTask(title: "", instruction: "",
                                  rule: .daily(hour: 9, minute: 0))
        } label: {
          Label(L("새 일정"), systemImage: "plus")
        }
        Button(L("닫기")) { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      .padding(16)

      Divider()

      if tasks.isEmpty {
        emptyState
      } else {
        ScrollView {
          VStack(alignment: .leading, spacing: 8) {
            ForEach(tasks) { task in
              taskCard(task)
            }
          }
          .padding(16)
        }
      }

      Divider()
      Text(L("예약 작업은 앱이 실행 중일 때만 동작합니다. 삭제해도 지난 리포트 파일은 남습니다."))
        .font(.caption).foregroundColor(.secondary)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }
    .frame(width: 640, height: 580)
    .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { nowTick = $0 }
    .onAppear { store.schedulerService?.reload() }
    .sheet(item: $editing) { task in
      TaskEditorSheet(task: task, isNew: isNew,
                      personas: store.settings.personas) { saved in
        store.schedulerService?.upsert(saved)
        editing = nil
      } onCancel: {
        editing = nil
      }
    }
    .sheet(item: $deleting) { task in
      DeleteConfirmSheet(
        heading: L("이 일정을 삭제할까요?"),
        target: task.title,
        message: L("더 이상 실행되지 않습니다. 지난 리포트 파일은 그대로 남습니다."),
        confirmLabel: L("삭제")
      ) {
        store.schedulerService?.delete(task.id)
      }
    }
  }

  // MARK: - 빈 상태

  private var emptyState: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(L("아직 예약 작업이 없습니다."))
        .font(.body).foregroundColor(.secondary)
      Text(L("매일 아침 뉴스 정리처럼 반복할 일을 등록해 두면, 정해진 시각에 비서가 실행하고 Markdown 리포트를 남깁니다."))
        .font(.caption).foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        isNew = true
        editing = ScheduledTask(title: "", instruction: "", rule: .daily(hour: 9, minute: 0))
      } label: {
        Label(L("첫 일정 만들기"), systemImage: "plus")
      }
    }
    .padding(16)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }

  // MARK: - 카드

  private func taskCard(_ task: ScheduledTask) -> some View {
    let persona = store.settings.persona(task.personaID)
    return VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .top, spacing: 10) {
        Text(persona?.normalized().emoji ?? "🗓")
          .font(.system(size: 18))
          .frame(width: 30, height: 30)
          .background(Color.purple.opacity(0.12))
          .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 6) {
            Text(task.title).font(.body).fontWeight(.semibold)
            statusChip(task)
            if !task.enabled && !task.isExpired {
              Text(L("일시 중지"))
                .font(.caption2)
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.secondary.opacity(0.15))
                .clipShape(Capsule())
            }
          }
          Text("\(persona?.name ?? L("기본(비서 없음)")) · \(task.rule.humanDescription())")
            .font(.caption).foregroundColor(.secondary)
          nextFireLine(task)
          if let run = task.lastRun, run.status == .failed || run.status == .interrupted,
             let reason = run.failureReason, !reason.isEmpty {
            Text(reason).font(.caption2).foregroundColor(.red)
              .lineLimit(2)
          }
          if let run = task.lastRun, let path = run.filePath, !path.isEmpty {
            Text(path).font(.caption2).foregroundColor(.secondary)
              .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
          }
        }

        Spacer(minLength: 4)

        VStack(alignment: .trailing, spacing: 4) {
          Button(L("지금 실행")) { store.schedulerService?.runNow(task.id) }
            .disabled(store.schedulerService?.isRunning == true)
          HStack(spacing: 6) {
            Button(task.enabled ? L("일시 중지") : L("다시 시작")) {
              store.schedulerService?.setEnabled(task.id, !task.enabled)
            }
            .disabled(task.isExpired)
            Button(L("편집")) {
              isNew = false
              editing = task
            }
            Button {
              deleting = task
            } label: {
              Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundColor(.secondary)
            .help(L("삭제"))
          }
          .controlSize(.small)
        }
      }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(nsColor: .controlBackgroundColor).opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func statusChip(_ task: ScheduledTask) -> some View {
    let (text, color) = status(task)
    return Text(text)
      .font(.caption2)
      .padding(.horizontal, 5).padding(.vertical, 1)
      .background(color.opacity(0.16))
      .foregroundColor(color)
      .clipShape(Capsule())
  }

  private func status(_ task: ScheduledTask) -> (String, Color) {
    guard let run = task.lastRun else { return (L("아직 실행 없음"), .secondary) }
    switch run.status {
    case .succeeded: return (L("완료"), .green)
    case .failed: return (L("실패"), .red)
    case .cancelled: return (L("취소됨"), .secondary)
    case .missed: return (L("건너뜀"), .orange)
    case .interrupted: return (L("중단됨"), .orange)
    case .running: return (L("실행 중"), .purple)
    case .awaitingApproval: return (L("승인 대기"), .orange)
    }
  }

  @ViewBuilder private func nextFireLine(_ task: ScheduledTask) -> some View {
    if task.isExpired {
      Text(L("한 번 실행이 끝나 더 이상 실행되지 않습니다."))
        .font(.caption2).foregroundColor(.secondary)
    } else if let next = task.nextFireAt {
      Text(Lf("다음 실행: %@", RelativeTime.absolute(next)))
        .font(.caption2).foregroundColor(.secondary)
    } else if task.enabled {
      Text(L("다음 실행 시각을 계산하는 중입니다."))
        .font(.caption2).foregroundColor(.secondary)
    }
  }
}

// MARK: - 편집 시트

struct TaskEditorSheet: View {
  let isNew: Bool
  let personas: [Persona]
  let onSave: (ScheduledTask) -> Void
  let onCancel: () -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var draft: ScheduledTask
  @State private var kind: Kind
  @State private var time: Date
  @State private var weekday: Int
  @State private var onceDate: Date

  private enum Kind: Int, CaseIterable, Identifiable {
    case daily, weekly, once
    var id: Int { rawValue }
    var label: String {
      switch self {
      case .daily: return L("매일")
      case .weekly: return L("매주")
      case .once: return L("한 번")
      }
    }
  }

  init(task: ScheduledTask, isNew: Bool, personas: [Persona],
       onSave: @escaping (ScheduledTask) -> Void,
       onCancel: @escaping () -> Void) {
    self.isNew = isNew
    self.personas = personas
    self.onSave = onSave
    self.onCancel = onCancel
    _draft = State(initialValue: task)

    let cal = Calendar.current
    var kind = Kind.daily
    var time = cal.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    var weekday = 2
    var once = Date().addingTimeInterval(60 * 60)
    switch task.rule {
    case let .daily(hour, minute):
      kind = .daily
      time = cal.date(from: DateComponents(hour: hour, minute: minute)) ?? time
    case let .weekly(w, hour, minute):
      kind = .weekly
      weekday = w
      time = cal.date(from: DateComponents(hour: hour, minute: minute)) ?? time
    case let .once(date):
      kind = .once
      once = date
    }
    _kind = State(initialValue: kind)
    _time = State(initialValue: time)
    _weekday = State(initialValue: weekday)
    _onceDate = State(initialValue: once)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(isNew ? L("새 일정") : L("일정 편집"))
        .font(.headline)
        .padding([.horizontal, .top], 16)

      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            Text(L("제목")).font(.body)
            TextField(L("예: 아침 테크 뉴스"), text: $draft.title)
              .textFieldStyle(.roundedBorder)
          }

          VStack(alignment: .leading, spacing: 4) {
            Text(L("지시문")).font(.body)
            TextEditor(text: $draft.instruction)
              .font(.system(size: 12))
              .frame(minHeight: 110)
              .overlay(RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.3), lineWidth: 1))
            Text(L("매번 그대로 실행됩니다. 무엇을 확인하고 리포트에 무엇을 담을지 구체적으로 적으세요."))
              .font(.caption).foregroundColor(.secondary)
          }

          HStack {
            Text(L("비서")).font(.body)
            Spacer()
            Picker("", selection: $draft.personaID) {
              Text(L("기본(비서 없음)")).tag(UUID?.none)
              ForEach(personas) { p in
                Text("\(p.normalized().emoji ?? "") \(p.name)").tag(Optional(p.id))
              }
            }
            .labelsHidden().pickerStyle(.menu)
            .frame(minWidth: 180, alignment: .trailing)
          }

          Divider()

          HStack {
            Text(L("반복")).font(.body)
            Spacer()
            Picker("", selection: $kind) {
              ForEach(Kind.allCases) { k in Text(k.label).tag(k) }
            }
            .labelsHidden().pickerStyle(.segmented)
            .frame(width: 220)
          }

          if kind != .once {
            HStack {
              Text(L("시각")).font(.body)
              Spacer()
              DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden().datePickerStyle(.stepperField)
            }
          }
          if kind == .weekly {
            HStack {
              Text(L("요일")).font(.body)
              Spacer()
              Picker("", selection: $weekday) {
                ForEach(1...7, id: \.self) { w in
                  Text(ScheduleRule.weekdayName(w)).tag(w)
                }
              }
              .labelsHidden().pickerStyle(.menu)
              .frame(width: 140, alignment: .trailing)
            }
          }
          if kind == .once {
            HStack {
              Text(L("실행 시각")).font(.body)
              Spacer()
              DatePicker("", selection: $onceDate,
                         in: Date().addingTimeInterval(60)...,
                         displayedComponents: [.date, .hourAndMinute])
                .labelsHidden()
            }
          }

          Toggle(L("사용"), isOn: $draft.enabled)
            .toggleStyle(.switch)
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
          save()
          dismiss()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                  draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      .padding(16)
    }
    .frame(width: 560, height: 560)
  }

  private func save() {
    let cal = Calendar.current
    let c = cal.dateComponents([.hour, .minute], from: time)
    var task = draft
    switch kind {
    case .daily:
      task.rule = .daily(hour: c.hour ?? 9, minute: c.minute ?? 0)
    case .weekly:
      task.rule = .weekly(weekday: weekday, hour: c.hour ?? 9, minute: c.minute ?? 0)
    case .once:
      task.rule = .once(onceDate)
    }
    // 규칙이 바뀌면 다음 시각을 다시 계산한다(수정 시 옛 시각이 남지 않게).
    task.nextFireAt = nil
    onSave(task.normalized())
  }
}
