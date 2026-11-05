import SwiftUI

/// 비서 선택 목록 — 헤더 칩·입력독·⌘Space pill 이 **같은 목록**을 쓴다.
/// 목록 맨 위는 `비서 없음` = 지금과 같은 동작. 지금 선택된 항목은 **체크 + "(지금)"** 으로 분명히 보인다.
struct PersonaMenuList: View {
  let personas: [Persona]
  let current: Persona?
  let onSelect: (UUID?) -> Void

  var body: some View {
    // 메뉴를 열자마자 현재 상태를 한 줄로 읽을 수 있게 한다.
    Text(current == nil
         ? L("지금: 비서 없음")
         : Lf("지금: %@ %@", current!.displayEmoji, current!.name))
      .font(.caption)
    Divider()
    Button {
      onSelect(nil)
    } label: {
      Label(current == nil ? L("비서 없음 (지금)") : L("비서 없음"),
            systemImage: current == nil ? "checkmark.circle.fill" : "circle")
    }
    Divider()
    ForEach(personas) { persona in
      let selected = current?.id == persona.id
      Button {
        onSelect(persona.id)
      } label: {
        Label(selected
              ? Lf("%@ %@ (지금)", persona.displayEmoji, persona.name)
              : Lf("%@ %@", persona.displayEmoji, persona.name),
              systemImage: selected ? "checkmark.circle.fill" : "circle")
      }
    }
  }
}

/// 비서 선택 메뉴 내용 — 헤더 칩과 입력독 버튼이 **같은 목록**을 쓴다.
struct PersonaMenuItems: View {
  @EnvironmentObject var store: UIStore

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
    PersonaMenuList(personas: store.settings.personas, current: current) { id in
      store.selectPersona(id)
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
  /// v0.31 — 상단 도구가 떠 있는 동안에는 이모지만 남겨 대화 제목 자리를 확보한다.
  var compact: Bool = false

  private var current: Persona? { store.settings.persona(store.conversation.personaID) }

  var body: some View {
    Menu {
      PersonaMenuItems()
    } label: {
      HStack(spacing: 3) {
        if let current {
          Text(current.displayEmoji)
            .font(.system(size: 10))
        } else {
          Image(systemName: "person.crop.circle")
            .font(.system(size: 10, weight: .medium))
        }
        if !compact {
          Text(current?.name ?? L("비서 없음"))
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
          if current != nil {
            Image(systemName: "checkmark.circle.fill")
              .font(.system(size: 8, weight: .bold))
          }
        }
      }
      .padding(.horizontal, compact ? 4 : 6)
      .padding(.vertical, 2)
      .background(Capsule().fill(Color.purple.opacity(current == nil ? 0.08 : 0.18)))
      .foregroundColor(current == nil ? .secondary : .primary)
      .contentShape(Capsule())
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(current == nil
          ? L("비서 없음 — 눌러서 이 대화의 비서를 고릅니다")
          : L("이 대화의 비서를 고릅니다 — 말투가 바뀌고, 예약 작업도 이 비서로 실행할 수 있습니다"))
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
      ZStack(alignment: .bottomTrailing) {
        Group {
          if let current {
            Text(current.displayEmoji).font(.system(size: 13))
          } else {
            Image(systemName: "person.crop.circle")
              .font(.system(size: 13, weight: .medium))
          }
        }
        .frame(width: 26, height: 26)
        .background(Circle().fill(Color.purple.opacity(current == nil ? 0.10 : 0.22)))
        .overlay(Circle().stroke(Color.purple.opacity(current == nil ? 0.20 : 0.45),
                                lineWidth: 1))
        .foregroundColor(current == nil ? .secondary : .primary)
        .contentShape(Circle())

        // 선택됨을 작은 체크 배지로도 보여 준다 — 아이콘만으로는 구분이 어려울 때가 있다.
        if current != nil {
          Image(systemName: "checkmark")
            .font(.system(size: 7, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 11, height: 11)
            .background(Circle().fill(Color.purple))
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 1.5))
            .offset(x: 3, y: 1)
        }
      }
      .fixedSize()
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .help(current == nil
          ? L("비서 없음 — 눌러서 이 대화의 비서를 고릅니다")
          : L("이 대화의 비서를 고릅니다 — 말투가 바뀌고, 예약 작업도 이 비서로 실행할 수 있습니다"))
  }
}
