import SwiftUI

/// 채팅 헤더의 비서 칩 (v0.26) — **비서가 1명 이상일 때만** 보인다.
/// 목록 맨 위는 `기본(비서 없음)` = 지금과 같은 동작.
struct PersonaChip: View {
  @EnvironmentObject var store: UIStore

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
    Menu {
      Button {
        store.selectPersona(nil)
      } label: {
        Label(L("기본(비서 없음)"),
              systemImage: current == nil ? "checkmark" : "person.crop.circle")
      }
      Divider()
      ForEach(store.settings.personas) { persona in
        Button {
          store.selectPersona(persona.id)
        } label: {
          Label("\(persona.normalized().emoji ?? "🗣") \(persona.name)",
                systemImage: current?.id == persona.id ? "checkmark" : "person")
        }
      }
      Divider()
      Button {
        store.showTaskList = true
      } label: {
        Label(L("할일"), systemImage: "calendar.badge.clock")
      }
    } label: {
      HStack(spacing: 3) {
        Text(current?.normalized().emoji ?? "🗣")
          .font(.system(size: 10))
        Text(current?.name ?? L("기본 비서"))
          .font(.system(size: 10.5, weight: .medium))
          .lineLimit(1)
      }
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(Color.purple.opacity(current == nil ? 0.08 : 0.18)))
      .foregroundColor(current == nil ? .secondary : .primary)
      .contentShape(Capsule())
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L("이 대화의 비서를 고릅니다 — 말투가 바뀌고, 예약 작업도 이 비서로 실행할 수 있습니다"))
  }
}
