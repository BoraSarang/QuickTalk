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

    groupBox(L("실행 방식")) {
      toggleRow(L("전역 자동 수락"), isOn: $store.settings.agentPolicy.autoAcceptAll,
                description: L("일반 명령은 확인 없이 실행합니다. 중요·치명적 위험과 상승 권한(sudo)은 그대로 확인·차단합니다."))
      toggleRow(L("실행 중 출력 표시"), isOn: $store.settings.agentStreamOutput,
                description: L("명령이 출력하는 내용을 실행되는 동안 카드에 보여 줍니다."))
      pickerRow(L("실행 제한 시간"), selection: $store.settings.agentTimeoutSeconds,
                options: [(30, Lf("%d초", 30)), (60, Lf("%d초", 60)),
                          (120, Lf("%d초", 120)), (300, Lf("%d초", 300))])
      caption(L("제한 시간을 넘기면 앱이 프로세스를 멈춥니다. 실행 중에는 카드의 [중단]으로 직접 멈출 수 있습니다."))
    }

    groupBox(L("이 대화의 권한")) {
      caption(L("전역 설정 위에 이 대화만 덮어씁니다. 치명적 차단·상승 권한 제한은 전역 설정을 그대로 따릅니다."))
      overridePolicyRow(L("읽기"), keyPath: \.readPolicy)
      overridePolicyRow(L("쓰기"), keyPath: \.writePolicy)
      overridePolicyRow(L("실행"), keyPath: \.executePolicy)
      if let summary = store.conversation.agentOverride?.summary {
        caption(Lf("이 대화에 적용 중: %@", summary))
      }
      if let override = store.conversation.agentOverride, !override.isEmpty {
        Button(L("설정 따름으로 되돌리기")) {
          store.setAgentOverride { $0 = AgentOverride() }
        }
      }
    }

    groupBox(L("승인된 폴더")) {
      if store.approvedWriteScopes.isEmpty {
        caption(L("이 대화에서 승인한 폴더가 없습니다. 승인 카드의 [이 폴더 허용]으로 추가됩니다."))
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(store.approvedWriteScopes, id: \.self) { scope in
            HStack(spacing: 6) {
              Image(systemName: "folder.badge.checkmark")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
              Text(scope)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Button(L("해제")) { store.removeWriteScope(scope) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
        }
      }
      caption(L("이 폴더 안의 쓰기는 이번 대화에서 다시 묻지 않습니다. 앱을 다시 켜면 초기화됩니다."))
    }

    groupBox(L("규칙 테스터")) {
      TextField(L("명령을 넣어 판정을 미리 확인 (예: rm -rf ~/Documents/tmp)"),
                text: $agentRuleProbe)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11, design: .monospaced))
      if let result = agentRuleProbeResult {
        VStack(alignment: .leading, spacing: 3) {
          HStack(spacing: 6) {
            badgeText(result.risk.displayName, color: riskColor(result.risk))
            badgeText(result.verdict.label, color: result.verdict.color)
            if result.matchedRule { badgeText(L("규칙 일치"), color: .green) }
            Spacer(minLength: 0)
          }
          Text(result.verdict.detail)
            .font(.system(size: 10.5))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.primary.opacity(0.04)))
      }
      caption(L("여기서는 **위험도·허용 규칙·단계 정책**만 미리 봅니다. 샌드박스 실측(실제 실행)은 하지 않습니다 — 실측은 명령을 승인한 뒤에만 합니다."))
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

      caption(L("확인이 필요한 명령은 대화 카드에 나타나고, [한 번 허용] [이 폴더 허용] [항상 허용] [거부] 중 고를 수 있습니다. [이 폴더 허용] 은 이번 대화에서 그 폴더의 쓰기를 다시 묻지 않습니다."))
    }

    groupBox(L("되돌리기 · 휴지통")) {
      Button(L("휴지통 열기")) {
        let url = UndoStack.shared.trashRoot
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
      }
      caption(L("쓰기 전에 되돌릴 지점을 만들어 둡니다. 단순한 rm 은 파일을 지우지 않고 QuickTalk 휴지통으로 옮깁니다 — 실행 카드의 [되돌리기] 로 되살릴 수 있습니다."))
      caption(L("백업은 최근 30건까지 보관합니다. 되돌리기 버튼은 앱을 다시 켜기 전까지 카드에 남습니다."))
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

// MARK: - 대화별 권한 · 규칙 테스터 (v0.22)

extension SettingsView {
  /// 대화별 오버라이드 한 줄 — **설정 따름 / 항상 허용 / 매번 확인** 3분할.
  /// (네이티브 Picker 대신 직접 그린다 — design_profile = custom)
  @ViewBuilder
  func overridePolicyRow(_ label: String,
                         keyPath: WritableKeyPath<AgentOverride, AgentAutoApprove?>) -> some View {
    let current = store.conversation.agentOverride?[keyPath: keyPath]
    HStack(spacing: 8) {
      Text(label).font(.body)
      Spacer(minLength: 12)
      HStack(spacing: 0) {
        overrideSegment(L("설정 따름"), selected: current == nil) {
          store.setAgentOverride { $0[keyPath: keyPath] = nil }
        }
        overrideSegment(L("항상 허용"), selected: current == .alwaysAllow) {
          store.setAgentOverride { $0[keyPath: keyPath] = .alwaysAllow }
        }
        overrideSegment(L("매번 확인"), selected: current == .alwaysAsk) {
          store.setAgentOverride { $0[keyPath: keyPath] = .alwaysAsk }
        }
      }
      .padding(2)
      .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
        .fill(Color.primary.opacity(0.06)))
    }
    .padding(.vertical, 2)
  }

  private func overrideSegment(_ title: String, selected: Bool,
                               action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(title)
        .font(.system(size: 11, weight: selected ? .semibold : .regular))
        .foregroundColor(selected ? .primary : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
          .fill(selected ? Color(nsColor: .controlBackgroundColor) : Color.clear))
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(L("이 대화에만 적용됩니다"))
  }

  /// 규칙 테스터 결과 — **실행하지 않고** 위험도·규칙·단계 정책만 계산한다.
  struct AgentRuleProbe {
    let risk: AgentRiskLevel
    let verdict: AgentRuleVerdict
    let matchedRule: Bool
  }

  enum AgentRuleVerdict {
    case allow
    case ask(String)
    case deny(String)

    var label: String {
      switch self {
      case .allow: return L("실행")
      case .ask: return L("확인 필요")
      case .deny: return L("차단")
      }
    }

    var color: Color {
      switch self {
      case .allow: return .green
      case .ask: return .orange
      case .deny: return .red
      }
    }

    var detail: String {
      switch self {
      case .allow:
        return L("지금 설정이면 확인 없이 실행됩니다(샌드박스 실측은 실행 직전에 합니다).")
      case .ask(let reason):
        return reason
      case .deny(let reason):
        return reason
      }
    }
  }

  var agentRuleProbeResult: AgentRuleProbe? {
    let command = agentRuleProbe.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return nil }
    let risk = RiskClassifier.classify(command)
    let policy = store.effectiveAgentPolicy
    let matched = PolicyEngine.matchesRule(command: command, rules: policy.rules)
    // ★ 실측(샌드박스 실행)은 하지 않는다 — 상승 권한이 필요하면 그 단계,
    //   아니면 보수적으로 "실행" 단계로 가정해 판정한다.
    let capability: AgentCapability = RiskClassifier.requiresElevation(command)
      ? .elevated : .unprobed
    let decision = PolicyEngine.decide(command: command, capability: capability,
                                       risk: risk, policy: policy,
                                       approvedScopes: store.approvedWriteScopes)
    let verdict: AgentRuleVerdict
    switch decision {
    case .allow:
      verdict = .allow
    case .ask(let request):
      verdict = .ask(request.reason)
    case .deny(let reason):
      verdict = .deny(reason)
    }
    return AgentRuleProbe(risk: risk, verdict: verdict, matchedRule: matched)
  }

  func riskColor(_ risk: AgentRiskLevel) -> Color {
    switch risk {
    case .normal: return .secondary
    case .important: return .orange
    case .critical: return .red
    }
  }

  func badgeText(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundColor(color)
      .padding(.horizontal, 5)
      .padding(.vertical, 1.5)
      .background(Capsule().fill(color.opacity(0.12)))
  }
}
