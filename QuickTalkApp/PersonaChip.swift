import SwiftUI

/// 비서 선택 메뉴 내용 — 헤더 칩과 입력독 버튼이 **같은 목록**을 쓴다.
/// 목록 맨 위는 `기본(비서 없음)` = 지금과 같은 동작.
struct PersonaMenuItems: View {
  @EnvironmentObject var store: UIStore

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
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
  }
}

/// 채팅 헤더의 비서 칩 (v0.26) — **비서가 1명 이상일 때만** 보인다.
struct PersonaChip: View {
  @EnvironmentObject var store: UIStore

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
    Menu {
      PersonaMenuItems()
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
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L("이 대화의 비서를 고릅니다 — 말투가 바뀌고, 예약 작업도 이 비서로 실행할 수 있습니다"))
  }
}

/// 입력독 왼쪽의 비서 버튼 (v0.28).
///
/// 새 대화(첫 턴 전)에도 보여서 **입력하기 전에** 비서를 고를 수 있다.
/// 비서가 0명이면 `ContentView` 가 이 뷰를 아예 넣지 않는다(기존 화면과 동일).
struct PersonaDockButton: View {
  @EnvironmentObject var store: UIStore

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
    Menu {
      PersonaMenuItems()
    } label: {
      Text(current?.normalized().emoji ?? "🗣")
        .font(.system(size: 13))
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.purple.opacity(current == nil ? 0.10 : 0.22)))
        .overlay(Circle().stroke(Color.purple.opacity(current == nil ? 0.20 : 0.45),
                                lineWidth: 1))
        .contentShape(Circle())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(L("이 대화의 비서를 고릅니다 — 말투가 바뀌고, 예약 작업도 이 비서로 실행할 수 있습니다"))
  }
}
