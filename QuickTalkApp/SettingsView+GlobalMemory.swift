import SwiftUI
import AppKit

// [FEATURE] 공통 메모리 (PLAN_v0.16) — 설정 › AI 카드.
// 대화별 요약(`ConversationMemory`)과 달리 **모든 대화**에 적용되는 사용자 작성 사실이다.
// 저장 위치: ~/Library/Application Support/QuickTalk/memory.json
extension SettingsView {
  @ViewBuilder
  var globalMemorySection: some View {
    groupBox(L("공통 메모리")) {
      HStack {
        Text(L("모든 대화에 적용"))
        Spacer()
        Toggle("", isOn: $store.settings.globalMemoryEnabled)
          .labelsHidden().toggleStyle(.switch).controlSize(.small)
      }
      if store.settings.globalMemoryEnabled {
        pickerRow(L("넣는 방식"), selection: $store.settings.globalMemoryMode,
                  options: MemoryInjectionMode.allCases.map { ($0, $0.displayName) })
        caption(store.settings.globalMemoryMode.explanation)
        pickerRow(L("토큰 예산"), selection: $store.settings.globalMemoryBudgetTokens,
                  options: QuickTalkSettings.globalMemoryBudgetOptions.map {
                    ($0, Lf("약 %d토큰", $0))
                  })
        caption(GlobalMemory.summary(store.memoryEntries,
                                     budget: store.settings.globalMemoryBudgetTokens))

        HStack(spacing: 8) {
          Image(systemName: "magnifyingglass").font(.caption).foregroundColor(.secondary)
          TextField(L("제목·본문·태그 검색"), text: $memorySearch)
            .textFieldStyle(.roundedBorder)
          Button {
            memoryIsNew = true
            editingMemory = GlobalMemoryEntry()
          } label: {
            Label(L("추가"), systemImage: "plus")
          }
        }

        if store.memoryEntries.isEmpty {
          Text(L("아직 저장한 메모리가 없습니다. 예: “내 맥은 M4 Pro 24GB, 개발은 Xcode·SwiftUI”"))
            .font(.callout).foregroundColor(.secondary)
            .padding(.vertical, 4)
        } else if filteredMemoryEntries.isEmpty {
          Text(L("검색과 일치하는 메모리가 없습니다."))
            .font(.callout).foregroundColor(.secondary)
        } else {
          VStack(alignment: .leading, spacing: 0) {
            ForEach(filteredMemoryEntries) { entry in
              memoryRow(entry)
              if entry.id != filteredMemoryEntries.last?.id { Divider() }
            }
          }
        }

        HStack(spacing: 8) {
          Button(L("가져오기")) { importMemoryFile() }
          Button(L("내보내기")) { exportMemoryFile() }
            .disabled(store.memoryEntries.isEmpty)
          if let notice = store.memoryNotice {
            Text(notice).font(.caption).foregroundColor(.secondary).lineLimit(2)
          }
        }

        caption(L("메모리는 모델 학습이 아니라 매 요청의 프롬프트에 들어가는 참고 사실입니다. 원격 프로바이더를 쓰면 켜 둔 항목이 그 서버로 전송됩니다. 비밀번호·API 키 같은 민감정보는 저장하지 마세요. 이 대화에서만 끄려면 대화 창 헤더의 🧠 버튼을 누르세요."))
      } else {
        caption(L("꺼 두면 저장된 항목은 남지만 어떤 요청에도 전송되지 않습니다."))
      }
    }
    .sheet(item: $editingMemory) { entry in
      MemoryEditorSheet(entry: entry, isNew: memoryIsNew) { saved in
        store.upsertMemory(saved)
        editingMemory = nil
      } onCancel: {
        editingMemory = nil
      }
    }
  }

  /// 검색어로 제목·본문·태그를 필터링한다(순서는 사용자가 정한 순서 유지).
  var filteredMemoryEntries: [GlobalMemoryEntry] {
    let q = memorySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !q.isEmpty else { return store.memoryEntries }
    return store.memoryEntries.filter { entry in
      entry.displayTitle.lowercased().contains(q)
        || entry.content.lowercased().contains(q)
        || entry.tags.contains { $0.lowercased().contains(q) }
    }
  }

  @ViewBuilder
  func memoryRow(_ entry: GlobalMemoryEntry) -> some View {
    HStack(alignment: .top, spacing: 8) {
      Toggle("", isOn: Binding(
        get: { entry.enabled },
        set: { store.setMemoryEnabled(entry.id, $0) }
      ))
      .labelsHidden().toggleStyle(.switch).controlSize(.mini)
      .padding(.top, 2)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(entry.displayTitle).font(.body).lineLimit(1)
          if entry.alwaysInclude {
            Text(L("항상")).font(.caption2)
              .padding(.horizontal, 5).padding(.vertical, 1)
              .background(Color.purple.opacity(0.14))
              .foregroundColor(.purple)
              .clipShape(Capsule())
          }
          if !entry.enabled {
            Text(L("꺼짐")).font(.caption2).foregroundColor(.secondary)
          }
        }
        Text(entry.content).font(.caption).foregroundColor(.secondary)
          .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        if !entry.tags.isEmpty {
          Text(entry.tagText).font(.caption2).foregroundColor(.accentColor).lineLimit(1)
        }
      }
      Spacer(minLength: 4)
      Text(Lf("%d토큰", entry.estimatedTokens))
        .font(.caption2).foregroundColor(.secondary)
        .frame(width: 52, alignment: .trailing)
      VStack(spacing: 1) {
        Button { store.moveMemory(entry.id, by: -1) } label: {
          Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
        }
        .buttonStyle(.borderless).help(L("위로"))
        Button { store.moveMemory(entry.id, by: 1) } label: {
          Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .buttonStyle(.borderless).help(L("아래로"))
      }
      Button(L("편집")) { memoryIsNew = false; editingMemory = entry }
        .buttonStyle(.borderless)
      Button {
        store.deleteMemory(entry.id)
      } label: {
        Image(systemName: "trash").foregroundColor(.red)
      }
      .buttonStyle(.borderless).help(L("메모리 삭제"))
    }
    .padding(.vertical, 5)
  }

  private func importMemoryFile() {
    let panel = NSOpenPanel()
    panel.title = L("공통 메모리 가져오기")
    panel.allowedContentTypes = [.json]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    if panel.runModal() == .OK, let url = panel.url {
      store.importMemory(from: url)
    }
  }

  private func exportMemoryFile() {
    let panel = NSSavePanel()
    panel.title = L("공통 메모리 내보내기")
    panel.nameFieldStringValue = "quicktalk-memory.json"
    panel.allowedContentTypes = [.json]
    if panel.runModal() == .OK, let url = panel.url {
      store.exportMemory(to: url)
    }
  }
}

// MARK: - 편집 시트

struct MemoryEditorSheet: View {
  @State var entry: GlobalMemoryEntry
  let isNew: Bool
  let onSave: (GlobalMemoryEntry) -> Void
  let onCancel: () -> Void
  @State private var tagInput = ""

  init(entry: GlobalMemoryEntry, isNew: Bool,
       onSave: @escaping (GlobalMemoryEntry) -> Void,
       onCancel: @escaping () -> Void) {
    _entry = State(initialValue: entry)
    self.isNew = isNew
    self.onSave = onSave
    self.onCancel = onCancel
    _tagInput = State(initialValue: entry.tags.joined(separator: ", "))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(isNew ? L("공통 메모리 추가") : L("공통 메모리 편집"))
        .font(.headline)
      TextField(L("제목 (선택)"), text: $entry.title)
        .textFieldStyle(.roundedBorder)
      VStack(alignment: .leading, spacing: 4) {
        Text(L("내용")).font(.callout)
        TextEditor(text: $entry.content)
          .font(.body)
          .frame(minHeight: 120)
          .padding(4)
          .background(RoundedRectangle(cornerRadius: 6)
            .fill(Color(nsColor: .textBackgroundColor)))
          .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color.secondary.opacity(0.25), lineWidth: 1))
        Text(Lf("약 %d토큰", ConversationMemory.estimateTokens(entry.content)))
          .font(.caption).foregroundColor(.secondary)
      }
      TextField(L("태그 (쉼표로 구분: 개발, 맥사양)"), text: $tagInput)
        .textFieldStyle(.roundedBorder)
      Toggle(L("항상 포함 — 관련 항목만 모드에서도 항상 넣기"), isOn: $entry.alwaysInclude)
      Toggle(L("사용"), isOn: $entry.enabled)
      Text(L("예: “내 맥은 M4 Pro 24GB이고 개발은 Xcode·SwiftUI를 쓴다.”처럼 변하지 않는 사실을 적으면 매번 다시 묻지 않습니다."))
        .font(.caption).foregroundColor(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Spacer()
        Button(L("취소")) { onCancel() }
          .keyboardShortcut(.cancelAction)
        Button(isNew ? L("추가") : L("저장")) {
          var copy = entry
          copy.tags = GlobalMemoryEntry.normalizeTags(tagInput)
          onSave(copy)
        }
        .keyboardShortcut(.defaultAction)
        .disabled(entry.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && entry.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
    }
    .padding(18)
    .frame(width: 480)
  }
}
