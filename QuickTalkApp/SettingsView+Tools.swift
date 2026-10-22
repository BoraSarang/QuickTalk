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
        AgentAuditLogView()
      }
      caption(L("대화 속 실행 내역은 답변 아래 카드에 보입니다. 이 목록은 앱이 실행한 모든 명령의 감사 기록입니다 — 대화를 지워도 남고, 토큰·키·비밀번호는 가려집니다."))
    }
  }
}

// MARK: - 실행 기록 목록

/// 감사 기록을 **읽을 수 있게** 그린다(2026-10-22 사용자 지적: "실행 기록 보기.. 어떻게 보라는 건지").
/// 예전에는 JSON 한 줄을 그대로 보여 줬다 — 시간·판정·결과·명령을 열로 나눠 보여 준다.
private struct AgentAuditLogView: View {
  @State private var entries: [AgentAuditEntry] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      if entries.isEmpty {
        Text(L("아직 실행 기록이 없습니다."))
          .font(.caption)
          .foregroundColor(.secondary)
      } else {
        ScrollView {
          VStack(spacing: 0) {
            ForEach(entries) { entry in
              AgentAuditRow(entry: entry)
              if entry.id != entries.last?.id {
                Divider()
              }
            }
          }
          .padding(.horizontal, 8)
          .padding(.vertical, 2)
        }
        .frame(maxHeight: 190)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.4),
                    in: RoundedRectangle(cornerRadius: 8))

        HStack {
          Text(Lf("최근 %d건", entries.count))
            .font(.caption)
            .foregroundColor(.secondary)
          Spacer()
          Button(L("기록 지우기")) {
            AgentAudit.clear()
            entries = []
          }
        }
      }
    }
    .onAppear { reload() }
  }

  private func reload() {
    entries = AgentAudit.recentEntries(limit: 30)
  }
}

/// 감사 기록 1행 — 판정 · 명령 · 결과 · 시각.
private struct AgentAuditRow: View {
  let entry: AgentAuditEntry

  private var tint: Color { entry.allowed ? .green : .orange }

  private var outcome: String {
    if !entry.allowed { return L("실행 안 함") }
    if entry.exitCode == 0 { return L("성공") }
    return Lf("실패 · 종료 코드 %d", Int(entry.exitCode))
  }

  private var duration: String? {
    guard entry.elapsedMs > 0 else { return nil }
    if entry.elapsedMs < 1000 { return Lf("%dms", entry.elapsedMs) }
    return Lf("%.1fs", Double(entry.elapsedMs) / 1000)
  }

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Text(entry.allowed ? L("허용") : L("거부"))
        .font(.system(size: 10, weight: .semibold))
        .foregroundColor(tint)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(tint.opacity(0.14), in: Capsule())

      VStack(alignment: .leading, spacing: 2) {
        Text(entry.command)
          .font(.system(size: 11, design: .monospaced))
          .lineLimit(1)
          .truncationMode(.middle)
          .textSelection(.enabled)
        HStack(spacing: 6) {
          Text(entry.levelName)
          Text("·")
          Text(outcome)
          if let duration {
            Text("·")
            Text(duration)
          }
          if let risk = entry.riskName {
            Text("·")
            Text(risk).foregroundColor(.orange)
          }
        }
        .font(.system(size: 10))
        .foregroundColor(.secondary)
      }

      Spacer(minLength: 8)

      Text(entry.date.map { RelativeTime.text(for: $0) } ?? "—")
        .font(.system(size: 10))
        .foregroundColor(.secondary)
        .help(entry.date.map { RelativeTime.absolute($0) } ?? entry.raw)
    }
    .padding(.vertical, 5)
    .contentShape(Rectangle())
    .help(entry.raw)
  }
}
