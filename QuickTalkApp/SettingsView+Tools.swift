import SwiftUI

// [FEATURE] 도우미 도구 설정 (PLAN_v0.18 §4.5) — 설정 › 도구.
//
// 사용자가 고르는 3가지를 그대로 둔다.
//   ① 단계별 자동 처리(읽기/쓰기/실행) — 각각 "항상 허용" 또는 "매번 확인"
//   ② 제한 — 치명적 명령 · 상승 권한
//   ③ 허용 규칙 — **사용자가 직접 쓰는 패턴**(앱이 주는 화이트리스트 없음)
extension SettingsView {
  @ViewBuilder
  var toolsSection: some View {
    groupBox(L("도우미 도구")) {
      toggleRow(L("도구 사용"), isOn: $store.settings.agentToolsEnabled,
                description: L("질문하면 앱이 직접 확인하고 행동합니다. 예를 들어 디스크 용량이나 프로세스를 실제로 조회합니다."))
      caption(L("꺼도 일반 대화는 그대로 동작합니다. 앱은 명령어 이름을 몰라요 — 모델이 정한 명령을 그대로 실행하고, 그 명령이 무슨 권한을 요구하는지는 샌드박스로 확인합니다."))
      toggleRow(L("실행 과정 표시"), isOn: $store.settings.agentShowExecution,
                description: L("대화에 실제 실행한 명령과 그 출력을 보여줍니다. 끄면 도구 이름·결과 한 줄만 남습니다."))
    }

    groupBox(L("권한")) {
      pickerRow(L("읽기"), selection: $store.settings.agentPolicy.readPolicy,
                options: AgentAutoApprove.allCases.map { ($0, $0.displayName) })
      caption(AgentPermissionLevel.read.explanation)

      pickerRow(L("쓰기"), selection: $store.settings.agentPolicy.writePolicy,
                options: AgentAutoApprove.allCases.map { ($0, $0.displayName) })
      caption(AgentPermissionLevel.write.explanation)

      pickerRow(L("실행"), selection: $store.settings.agentPolicy.executePolicy,
                options: AgentAutoApprove.allCases.map { ($0, $0.displayName) })
      caption(AgentPermissionLevel.execute.explanation)

      caption(L("확인이 필요한 명령은 대화 카드에 나타나고, [한 번 허용] [항상 허용] [거부] 중 고를 수 있습니다."))
    }

    groupBox(L("제한")) {
      toggleRow(L("치명적 명령 허용"), isOn: $store.settings.agentPolicy.allowCritical,
                description: L("rm -rf / · mkfs 같은 복구 불가능한 명령. 기본은 차단입니다."))
      toggleRow(L("상승 권한 허용"), isOn: $store.settings.agentPolicy.allowElevated,
                description: L("sudo 가 필요한 명령. 앱은 비밀번호를 묻지 않습니다."))
    }

    groupBox(L("항상 허용 규칙")) {
      if store.settings.agentPolicy.rules.isEmpty {
        caption(L("규칙이 없습니다. 앱이 정해 주는 목록은 없습니다 — 직접 필요한 패턴만 추가하세요."))
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(store.settings.agentPolicy.rules, id: \.self) { rule in
            HStack(spacing: 6) {
              Image(systemName: "checkmark.shield")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
              Text(rule)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Button {
                store.settings.agentPolicy.rules.removeAll { $0 == rule }
              } label: {
                Image(systemName: "xmark.circle.fill")
                  .font(.system(size: 11))
                  .foregroundColor(.secondary)
              }
              .buttonStyle(.plain)
              .help(L("규칙 삭제"))
            }
          }
        }
      }
      HStack(spacing: 8) {
        TextField(L("예: brew install *"), text: $newAgentRule)
          .textFieldStyle(.roundedBorder)
          .font(.system(size: 11, design: .monospaced))
        Button(L("추가")) {
          let p = newAgentRule.trimmingCharacters(in: .whitespacesAndNewlines)
          guard !p.isEmpty else { return }
          if !store.settings.agentPolicy.rules.contains(p) {
            store.settings.agentPolicy.rules.append(p)
          }
          newAgentRule = ""
        }
        .disabled(newAgentRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      caption(L("* 는 와일드카드입니다. 예: brew install * · adb * install * · ls *"))
    }

    groupBox(L("실행 기록")) {
      Button(showAgentAudit ? L("기록 숨기기") : L("기록 보기")) {
        showAgentAudit.toggle()
      }
      if showAgentAudit {
        let lines = AgentAudit.recent(limit: 30)
        if lines.isEmpty {
          caption(L("아직 실행 기록이 없습니다."))
        } else {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
              Text(line)
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            }
          }
          Button(L("기록 지우기")) { AgentAudit.clear() }
        }
      }
      caption(L("무엇을 언제 실행했는지 남습니다. 명령에 붙은 토큰·키·비밀번호는 가려집니다."))
    }
  }
}
