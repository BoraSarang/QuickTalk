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
      toggleRow(L("도우미 도구 사용"), isOn: $store.settings.agentToolsEnabled,
                description: L("질문하면 앱이 직접 확인하고 행동합니다. 예를 들어 디스크 용량이나 프로세스를 실제로 조회합니다."))
      caption(L("꺼도 일반 대화는 그대로 동작합니다. 앱은 명령어 이름을 몰라요 — 모델이 정한 명령을 그대로 실행하고, 그 명령이 무슨 권한을 요구하는지는 샌드박스로 확인합니다."))
      toggleRow(L("실행 과정 표시"), isOn: $store.settings.agentShowExecution,
                description: L("대화에 실제 실행한 명령과 그 출력을 보여줍니다. 끄면 도구 이름·결과 한 줄만 남습니다."))
    }

    // 스킬 — PLAN_v0.37. SKILL.md 의 절차를 필요할 때만 읽는다.
    skillsGroup

    // 격리 브라우저 — PLAN_v0.38.1. Safari 와 분리된 전용 프로필, 읽기 전용 기본.
    groupBox(L("격리 브라우저")) {
      toggleRow(L("웹 브라우저 사용"), isOn: $store.settings.browserEnabled,
                description: L("모델이 Safari와 분리된 전용 프로필로 웹 페이지를 열고 읽습니다. 쿠키·캐시를 Safari와 공유하지 않습니다."))
      caption(L("기본은 꺼짐입니다. 켜면 비서의 '웹 검색' 도구를 가진 대화에서만 브라우저 도구가 모델에 전달됩니다. 읽기(열기·읽기·뒤로)는 읽기 권한 정책을 따르고, 링크가 아닌 클릭·입력·제출은 항상 승인을 받습니다."))
      caption(L("비밀번호·파일·숨김·결제·인증번호 필드는 읽지도 입력하지도 않습니다. 다운로드·새 창·팝업·파일 선택·카메라·마이크는 차단합니다. 로그인·2단계 인증·CAPTCHA가 필요한 페이지는 읽기만 됩니다."))
      caption(L("한계: 주소에 위험 신호(로그아웃·삭제·결제)가 있는 링크는 승인을 받지만, GET 링크가 서버 상태를 바꾸는 경우와 DNS 리바인딩은 완전히 막지 못합니다."))
      toggleRow(L("모델이 페이지를 열면 창 표시"),
                isOn: $store.settings.browserShowWindowAutomatically,
                description: L("모델이 브라우저 도구를 쓸 때 격리 브라우저 창을 자동으로 띄웁니다. 창은 포커스를 빼앗지 않고 뒤에 나타납니다."))
      caption(L("창을 닫아도 페이지는 남아 있고, 모델은 계속 읽을 수 있습니다."))
      HStack(spacing: 8) {
        Button(L("브라우저 창 열기")) {
          browserWindowMessage = store.openBrowserWindow()
            ? nil : L("웹 브라우저 사용을 먼저 켜세요.")
        }
        .disabled(!store.settings.browserEnabled || !store.settings.agentToolsEnabled)
        Button(L("브라우저 데이터 지우기")) {
          browserDataClearing = true
          browserDataMessage = nil
          Task { @MainActor in
            await store.clearBrowserData()
            browserDataClearing = false
            browserDataMessage = L("쿠키·캐시·로컬 저장소를 지웠습니다.")
          }
        }
        .disabled(browserDataClearing)
        if browserDataClearing {
          ProgressView().controlSize(.small)
        }
        Spacer()
      }
      if let browserWindowMessage {
        caption(browserWindowMessage)
      }
      if let browserDataMessage {
        caption(browserDataMessage)
      }
      caption(L("주소창에 직접 주소를 입력해도 됩니다. 로컬·사설 네트워크 주소는 열지 않습니다."))
      caption(L("프로필은 WebKit 관리 영역에 저장되며 QuickTalk의 대화·설정 데이터와 별개입니다."))
    }

    // 컴퓨터 제어 — PLAN_v0.25. Phase 2부터 **읽기 + 조작**이므로 토글 이름이 "화면 조작"이다.
    groupBox(L("컴퓨터 제어")) {
      toggleRow(L("화면 조작 허용"), isOn: $store.settings.uiControlEnabled,
                description: L("켜면 모델이 다른 앱의 버튼을 클릭하고 글자를 입력할 수 있습니다. 좌표가 아니라 접근성 요소로만 조작하고, 앱마다 한 번 더 승인을 받습니다. 이 동작은 되돌릴 수 없습니다."))
      caption(L("이 그룹은 전역 권한(읽기/쓰기/실행)과 별개입니다. 화면 읽기는 이 토글만 보고, 화면 조작은 앱마다 한 번 승인하면 7일 동안 다시 묻지 않습니다."))
      caption(L("기본은 꺼짐입니다. 꺼져 있으면 모델이 이 도구를 아예 받지 않습니다. 읽고 조작하려면 손쉬운 사용 권한이 필요합니다."))
      caption(L("비밀번호 입력란은 읽지도 쓰지도 않습니다. 터미널·비밀번호 관리자·시스템 설정·관리자 암호 창은 조작할 수 없습니다."))
      if store.activeUiAppGrants.isEmpty {
        caption(L("이 대화에서 승인한 앱이 없습니다. 승인 카드의 [이 앱 허용]으로 추가됩니다."))
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(store.activeUiAppGrants) { grant in
            HStack(spacing: 6) {
              Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
              Text(grant.name)
                .font(.system(size: 11))
                .lineLimit(1)
              Spacer()
              Text(Lf("%@까지 유효", grant.expiresAt.formatted(date: .abbreviated, time: .omitted)))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
              Button(L("해제")) { store.removeUiAppGrant(bundleID: grant.bundleID) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
        }
      }
      caption(L("승인한 앱은 이 대화에서 7일 동안 유지됩니다. 만료되거나 [해제]하면 다시 묻습니다."))
      caption(Lf("조작할 수 없는 앱(고정): %@", UiGuard.deniedAppSummary))
      caption(L("한 번의 요청에서 화면 조작은 30번까지, 동작 사이에는 150ms 간격을 둡니다. 사용자가 입력 중이면 실행하지 않습니다."))
    }

    groupBox(L("전역 권한")) {
      caption(L("앱 전체에 적용됩니다. 이 대화만 다르게 하려면 아래 '이 대화의 권한'을 쓰세요."))
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
      caption(L("QuickTalk의 대화 기록·공통 메모리·설정은 자동 허용에서 제외됩니다 — 접근할 때마다 확인합니다."))
    }

    groupBox(L("제한")) {
      toggleRow(L("치명적 명령 허용"), isOn: $store.settings.agentPolicy.allowCritical,
                description: L("rm -rf / · mkfs 같은 복구 불가능한 명령. 기본은 차단입니다."))
      toggleRow(L("상승 권한 허용"), isOn: $store.settings.agentPolicy.allowElevated,
                description: L("sudo 가 필요한 명령. 앱은 비밀번호를 묻지 않습니다."))
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
      if store.activeWriteScopeGrants.isEmpty {
        caption(L("이 대화에서 승인한 폴더가 없습니다. 승인 카드의 [이 폴더 허용]으로 추가됩니다."))
      } else {
        VStack(alignment: .leading, spacing: 4) {
          ForEach(store.activeWriteScopeGrants) { grant in
            HStack(spacing: 6) {
              Image(systemName: "folder.badge.checkmark")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
              Text(grant.path)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
              Spacer()
              Text(Lf("%@까지 유효", grant.expiresAt.formatted(date: .abbreviated, time: .omitted)))
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
              Button(L("해제")) { store.removeWriteScope(grant.path) }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
          }
        }
      }
      caption(L("승인한 폴더는 이 대화에서 7일 동안 유지됩니다. 만료되거나 [해제]하면 다시 묻습니다."))
    }

    groupBox(L("규칙 테스터")) {
      TextField(L("명령을 넣어 판정을 미리 확인 (예: rm -rf ~/Documents/tmp)"),
                text: $agentRuleProbe)
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 11, design: .monospaced))
      if let result = agentRuleProbeResult {
        VStack(alignment: .leading, spacing: 5) {
          HStack(spacing: 6) {
            badgeText(result.risk.displayName, color: riskColor(result.risk))
            badgeText(result.headline.label, color: result.headline.color)
            if result.elevated { badgeText(L("상승 권한"), color: .red) }
            if result.matchedRule { badgeText(L("규칙 일치"), color: .green) }
            Spacer(minLength: 0)
          }
          VStack(alignment: .leading, spacing: 3) {
            ForEach(result.stages) { stage in
              HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(stage.level.displayName)
                  .font(.system(size: 10.5, weight: .medium))
                  .frame(width: 42, alignment: .leading)
                badgeText(stage.label, color: stage.color)
                Text(stage.detail)
                  .font(.system(size: 10.5))
                  .foregroundColor(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
              }
            }
          }
          if !result.elevated {
            Text(L("실제 단계는 실행 직전 읽기 전용 샌드박스 실측으로 정해집니다. 위 결과는 각 단계로 판정됐을 때의 미리보기입니다."))
              .font(.system(size: 10))
              .foregroundColor(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Color.primary.opacity(0.04)))
      }
      caption(L("여기서는 위험도·허용 규칙·단계 정책만 미리 봅니다. 샌드박스 실측(실제 실행)은 하지 않습니다 — 실측은 명령을 승인한 뒤에만 합니다."))
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

    groupBox(L("되돌리기 · 휴지통")) {
      Button(L("휴지통 열기")) {
        let url = UndoStack.shared.trashRoot
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        NSWorkspace.shared.open(url)
      }
      caption(L("쓰기 전에 되돌릴 지점을 만들어 둡니다. 단순한 rm 은 파일을 지우지 않고 QuickTalk 휴지통으로 옮깁니다 — 실행 카드의 [되돌리기] 로 되살릴 수 있습니다."))
      caption(L("백업은 최근 30건까지 보관합니다. 되돌리기 버튼은 앱을 다시 켜기 전까지 카드에 남습니다."))
    }

    // 권한은 **한 곳**에 모은다 — 예전에는 '일반 › 창 연결'과 '퀵셸프'에 같은 화면 기록 권한이
    // 두 번 나왔다(2026-10-27). 기능 탭은 이 그룹을 가리키기만 한다.
    groupBox(L("시스템 권한")) {
      valueRow(L("화면 기록"), CaptureService.hasPermission() ? L("허용됨") : L("허용되지 않음"))
      HStack(spacing: 8) {
        Button(L("권한 요청")) {
          if CaptureService.ensureScreenPermission() {
            store.showShelfNotice(nil)
          } else {
            store.showShelfNotice(L("화면 기록 권한이 필요합니다 — 시스템 설정에서 QuickTalk를 허용한 뒤 앱을 다시 실행하세요."),
                                  action: .screenRecording)
          }
        }
        Button(L("시스템 설정 열기")) { CaptureService.openScreenRecordingSettings() }
        Spacer()
      }
      valueRow(L("손쉬운 사용"), WindowAttachmentService.hasAccessibilityPermission ? L("허용됨") : L("허용되지 않음"))
      HStack(spacing: 8) {
        Button(L("손쉬운 사용 설정 열기")) { WindowAttachmentService.openAccessibilitySettings() }
        Spacer()
      }
      caption(L("화면 기록은 창 목록·스크린샷·퀵셸프 캡처에, 손쉬운 사용은 다른 앱 창의 글자를 읽고 컴퓨터 제어(화면 요소 읽기·조작)에 씁니다. 허용 후에는 앱을 다시 실행해야 반영됩니다."))
      caption(L("이 두 권한은 macOS가 관리합니다 — 앱이 대신 켤 수 없고, 시스템 설정에서 직접 허용해야 합니다."))
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
    /// 가장 강한 판정(차단 > 확인 > 허용) — 한눈에 보여 준다.
    let headline: AgentRuleVerdict
    /// 읽기·쓰기·실행 단계별 미리보기. 상승 권한 명령은 실행 단계 하나뿐이다.
    let stages: [AgentRuleStage]
    let matchedRule: Bool
    let elevated: Bool
  }

  /// 단계 하나의 미리보기 — 라벨·색·안내는 **단계별**로 만든다.
  struct AgentRuleStage: Identifiable {
    let level: AgentPermissionLevel
    let decision: AgentDecision

    var id: String { level.rawValue }

    var label: String {
      switch decision {
      case .allow: return L("확인 없이 실행")
      case .ask: return L("확인 필요")
      case .deny: return L("차단")
      }
    }

    var color: Color {
      switch decision {
      case .allow: return .green
      case .ask: return .orange
      case .deny: return .red
      }
    }

    /// 단계별 안내 — 실측 전이라 쓰기 경로를 모르므로 **비어 있는 경로 사유는 쓰지 않는다**.
    var detail: String {
      switch decision {
      case .allow:
        return L("이 단계로 판정되면 지금 설정은 다시 묻지 않습니다.")
      case .ask:
        return L("이 단계로 판정되면 실행 전에 확인을 받습니다.")
      case .deny(let reason):
        return reason
      }
    }
  }

  enum AgentRuleVerdict {
    case allow
    case ask
    case deny

    init(_ decision: AgentDecision) {
      switch decision {
      case .allow: self = .allow
      case .ask: self = .ask
      case .deny: self = .deny
      }
    }

    var label: String {
      switch self {
      case .allow: return L("확인 없이 실행")
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
  }

  var agentRuleProbeResult: AgentRuleProbe? {
    let command = agentRuleProbe.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !command.isEmpty else { return nil }
    let preview = PolicyEngine.stagePreview(command: command,
                                            risk: RiskClassifier.classify(command),
                                            policy: store.effectiveAgentPolicy,
                                            approvedScopes: store.approvedWriteScopes)
    return AgentRuleProbe(
      risk: preview.risk,
      headline: AgentRuleVerdict(preview.headline),
      stages: preview.stages.map { AgentRuleStage(level: $0.level, decision: $0.decision) },
      matchedRule: preview.matchedRule,
      elevated: preview.elevated)
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

// MARK: - 스킬 (v0.37, PLAN §11.1)

extension SettingsView {
  /// 설정 › 도구·권한 › 스킬 — 목록·가져오기·삭제·경고.
  @ViewBuilder
  var skillsGroup: some View {
    groupBox(L("스킬")) {
      toggleRow(L("일반 대화에서 스킬 사용"),
                isOn: $store.settings.skillsEnabled,
                description: L("켜 두면 평소처럼 질문하기만 하면 됩니다. 필요할 때 모델이 스킬을 골라 읽고 절차를 따릅니다."))
      HStack(alignment: .top, spacing: 4) {
        Image(systemName: store.settings.skillsEnabled ? "checkmark.circle" : "info.circle")
          .font(.system(size: 10))
          .padding(.top, 1)
        Text(store.settings.skillsEnabled
             ? L("일반 대화와 비서 대화에서 사용합니다 — 비서별로 끌 수 있습니다.")
             : L("지금은 비서 대화에서만 사용합니다 — 비서는 기본으로 켜져 있습니다."))
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.caption)
      .foregroundColor(.secondary)
      .padding(.leading, 2)
      HStack(alignment: .top, spacing: 4) {
        Image(systemName: "text.bubble")
          .font(.system(size: 10))
          .padding(.top, 1)
        Text(L("예: “최근 AI 브라우저 3개를 비교해 줘” → 필요할 때 알맞은 스킬의 절차를 읽습니다."))
          .fixedSize(horizontal: false, vertical: true)
      }
      .font(.caption)
      .foregroundColor(.secondary)
      .padding(.leading, 2)

      if loadedSkills.isEmpty {
        caption(L("아직 스킬이 없습니다. SKILL.md 가 있는 폴더를 가져오면 필요할 때 모델이 읽습니다."))
      } else {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(loadedSkills) { skill in
            skillRow(skill)
            if skill.id != loadedSkills.last?.id { Divider() }
          }
        }
      }

      HStack(spacing: 8) {
        Button {
          importSkill()
        } label: {
          Label(L("폴더에서 가져오기"), systemImage: "square.and.arrow.down")
        }
        Spacer()
      }

      if !skillWarnings.isEmpty {
        Button(showSkillWarnings ? L("경고 숨기기")
                                 : Lf("무시된 스킬 %d개", skillWarnings.count)) {
          showSkillWarnings.toggle()
        }
        .buttonStyle(.link)
        if showSkillWarnings {
          VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(skillWarnings.enumerated()), id: \.offset) { _, warning in
              Text("\(warning.id.isEmpty ? L("이름 없음") : warning.id) — \(warning.reason)")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
      }

      caption(L("가져온 스킬은 ~/Library/Application Support/QuickTalk/Skills 에 저장됩니다. 앱은 스킬을 자동으로 실행하거나 업데이트하지 않습니다. 스킬 스크립트도 기존 셸 승인·샌드박스를 그대로 거칩니다."))
    }
    .onAppear { reloadSkills() }
    .alert(L("스킬을 교체할까요?"), isPresented: Binding(
      get: { pendingSkillReplace != nil },
      set: { on in
        if !on {
          pendingSkillReplace?.discard()
          pendingSkillReplace = nil
        }
      }
    )) {
      Button(L("취소"), role: .cancel) {
        pendingSkillReplace?.discard()
        pendingSkillReplace = nil
      }
      Button(L("교체"), role: .destructive) {
        guard let prepared = pendingSkillReplace else { return }
        pendingSkillReplace = nil
        do {
          try SkillImporter.install(prepared)
          reloadSkills()
        } catch {
          skillImportError = error.localizedDescription
          showSkillImportError = true
        }
      }
    } message: {
      Text(Lf("‘%@’ 스킬이 이미 있습니다. 폴더를 교체합니다.",
              pendingSkillReplace?.name ?? ""))
    }
    .alert(L("스킬을 가져오지 못했습니다"), isPresented: $showSkillImportError) {
      Button(L("확인"), role: .cancel) {}
    } message: {
      Text(skillImportError ?? "")
    }
    .sheet(item: $deletingSkill) { skill in
      DeleteConfirmSheet(
        heading: L("스킬을 삭제할까요?"),
        target: skill.name,
        message: L("가져온 스킬 폴더를 삭제합니다. 앱 데이터라서 휴지통으로 가지 않습니다."),
        confirmLabel: L("삭제")
      ) {
        do { try SkillImporter.remove(id: skill.id) } catch {
          skillImportError = error.localizedDescription
          showSkillImportError = true
        }
        reloadSkills()
      }
    }
  }

  private func skillRow(_ skill: Skill) -> some View {
    let enabled = !store.settings.disabledSkillIDs.contains(skill.id)
    let missing = missingTools(for: skill)
    return HStack(alignment: .top, spacing: 8) {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 5) {
          Text(skill.name)
            .font(.system(size: 12, weight: .medium))
          skillBadge(skill.source.displayName, color: .secondary)
          skillBadge(skill.risk.displayName,
                     color: skill.risk == .write ? .orange : .secondary)
          if !missing.isEmpty {
            skillBadge(L("권한 필요"), color: .orange)
          }
        }
        Text(skill.description)
          .font(.system(size: 10.5))
          .foregroundColor(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        if !skill.when.isEmpty {
          Text(Lf("언제: %@", skill.when))
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        if !missing.isEmpty {
          Text(Lf("이 스킬은 %@ 도구가 필요합니다.", missing.joined(separator: ", ")))
            .font(.system(size: 10))
            .foregroundColor(.orange)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      Spacer(minLength: 8)
      Toggle("", isOn: Binding(
        get: { !store.settings.disabledSkillIDs.contains(skill.id) },
        set: { on in setSkill(skill.id, enabled: on) }
      ))
      .labelsHidden()
      .toggleStyle(.switch)
      .controlSize(.mini)
      .help(enabled ? L("이 스킬을 모델에게 보여 주지 않습니다")
                    : L("이 스킬을 모델에게 보여 줍니다"))
      Menu {
        Button(L("Finder에서 보기")) { SkillImporter.reveal(id: skill.id) }
          .disabled(skill.source == .bundled)
        Button(L("삭제"), role: .destructive) { deletingSkill = skill }
          .disabled(skill.source == .bundled)
      } label: {
        Image(systemName: "ellipsis.circle")
      }
      .menuStyle(.borderlessButton)
      .frame(width: 22)
    }
    .padding(.vertical, 3)
  }

  private func skillBadge(_ text: String, color: Color) -> some View {
    Text(text)
      .font(.system(size: 9.5, weight: .semibold))
      .foregroundColor(color)
      .padding(.horizontal, 5)
      .padding(.vertical, 1)
      .background(Capsule().fill(color.opacity(0.12)))
  }

  /// 지금 설정에서 이 스킬이 요구하는 도구 중 **없는 것**.
  /// (스킬은 권한을 넓히지 못한다 — 없으면 프롬프트에서 숨기고 이유를 보여 준다)
  private func missingTools(for skill: Skill) -> [String] {
    guard !skill.tools.isEmpty else { return [] }
    var names = AgentToolCatalog.available(
      for: nil,
      includingWebSearch: store.webSearchToolAvailable,
      includingUI: store.settings.uiControlEnabled,
      includingSchedule: false).map(\.name)
    names.append(AgentToolCatalog.readSkill.name)
    let available = Set(names)
    return skill.tools.filter { !available.contains($0) }
  }

  private func setSkill(_ id: String, enabled: Bool) {
    var ids = store.settings.disabledSkillIDs
    if enabled {
      ids.removeAll { $0 == id }
    } else if !ids.contains(id) {
      ids.append(id)
    }
    store.settings.disabledSkillIDs = ids
  }

  private func reloadSkills() {
    if let initialSkills {
      loadedSkills = initialSkills
      skillWarnings = initialSkillWarnings
      return
    }
    let result = SkillRegistry.load(bundledRoot: SkillLocations.bundledRoot(),
                                    userRoot: SkillLocations.userRoot())
    loadedSkills = result.skills
    skillWarnings = result.warnings
  }

  private func importSkill() {
    do {
      guard let prepared = try SkillImporter.chooseAndPrepare() else { return }
      if SkillImporter.userSkillExists(id: prepared.id) {
        pendingSkillReplace = prepared
      } else {
        try SkillImporter.install(prepared)
        reloadSkills()
      }
    } catch {
      skillImportError = error.localizedDescription
      showSkillImportError = true
    }
  }
}
