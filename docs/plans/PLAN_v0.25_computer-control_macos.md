# PLAN v0.25 — 컴퓨터 제어 (macOS)

> 작성: 2026-10-29 · 상태: **Phase 1 구현 완료(2026-10-29) · Phase 2 계획**
> 상위 문서: `docs/HANDOFF.md`(단일 출처) · `docs/CHANGELOG.md` · `docs/plans/PLAN_v0.18_agent-runtime_macos.md` · `docs/plans/PLAN_v0.20-0.22_execution_macos.md`
> 선행 결정: `PLAN_v0.20-0.22 §7` — "창 제어(computer use)는 넣지 않았다". 이 문서는 그 결정을 **어떤 조건이면 뒤집어도 되는지**를 정하고, 그 조건을 코드로 고정한다.

## 0. 한 줄 요약

에이전트에게 **세 번째 손**(`ui_snapshot`·`ui_action`)을 준다. 단, 좌표가 아니라 **접근성 요소(role + 이름)** 로만 조작하고,
**앱별 승인 + 금지 앱 + 사용자 입력 우선 + 실행 한도**를 모두 통과해야 클릭·입력이 나간다. 되돌리기는 **없다**고 카드에 명시한다.

| 단계 | 내용 | 위험 | 이 문서 |
|---|---|---|---|
| Phase 1 | `ui_snapshot` — 요소 트리 읽기(읽기 전용) | 낮음 | 설계 확정 |
| Phase 2 | `ui_action` — 요소 클릭·텍스트 입력·키 조합·스크롤·앱 전환 | **높음** | 설계 확정 |
| Phase 3 | 픽셀(스크린샷) 기반 좌표 클릭 | 매우 높음 | **비목표** (별도 계획) |

## 1. 왜 지금인가 · 무엇이 달라졌나

v0.20–0.22에서 넣지 않은 이유는 "위험 대비 효용"이었다. 그 사이 다음이 갖춰져 **위험을 구조로 줄일 수 있게** 됐다.

| 이미 있는 것 | 이 계획에서 쓰는 방식 |
|---|---|
| `PolicyEngine`·`AgentToolPermission` 3단계(읽기/쓰기/실행) | `ui_action` 은 **실행** 단계, `ui_snapshot` 은 **읽기** 단계 |
| 승인 카드 + 2차 확인(중요·치명적) | 클릭·입력도 같은 카드로 **행동 전에** 확인 |
| `Conversation.approvedWriteScopes`(① 7일 만료) | **앱별 승인**도 같은 모델(`UiAppGrant`, 7일) |
| `AgentAudit` 감사 기록(비밀 마스킹) | UI 동작도 감사에 남긴다 |
| `AgentRunHandle`·`SandboxCancellation`([중단]) | UI 동작도 같은 중단 손잡이를 본다 |
| `AXWindowReader`(손쉬운 사용으로 창 텍스트 읽기) | 요소 트리 탐색 코드를 **재사용** |
| `WindowAttachmentService.requestAccessibility()` | 권한 요청 흐름 재사용 |

즉 새로 만드는 것은 **판정(순수 함수) + 요소 참조 + 이벤트 주입** 세 가지이고, 안전장치는 이미 있는 것을 그대로 쓴다.

## 2. 범위

### 2.1 Phase 1 — `ui_snapshot` (읽기 전용, 먼저 배포)

- 대상: **지금 앞에 있는 앱**(또는 `app` 인자로 지정한 실행 중 앱)의 창 1개.
- 반환: 요소 목록(참조 ID·역할·이름·값 유무·중심 좌표) + 창 제목·앱 이름.
- **상태를 바꾸지 않는다** — 클릭·입력·스크롤·포커스 이동 없음.
- 권한 없으면 `noPermission` + **허용 방법**을 카드·모델 응답에 적는다(`screenshot`과 같은 방식).
- Phase 1만으로도 "무엇을 누를 수 있는지"를 사람과 모델이 같은 언어로 말할 수 있게 된다 → Phase 2의 전제.

### 2.2 Phase 2 — `ui_action` (실행)

| action | 인자 | 설명 |
|---|---|---|
| `click` | `ref` | 요소 중심을 **한 번** 클릭(더블클릭은 `clickCount`) |
| `type` | `ref`? , `text` | 포커스된(또는 지정한) 텍스트 필드에 입력 |
| `key` | `keys` | 키 조합(`cmd+s`, `return`, `escape`, `tab`) — 허용 목록만 |
| `scroll` | `ref`? , `direction`, `amount` | 요소(없으면 창) 위에서 스크롤 |
| `open_app` | `bundleID` 또는 `name` | 앱 실행·앞으로 가져오기 |
| `focus_window` | `title` | 같은 앱의 특정 창을 앞으로 |

### 2.3 비목표 (명시)

- **픽셀 좌표 클릭**(스크린샷을 보고 "여기를 눌러라") — Phase 3, 별도 계획. 좌표를 받으면 **검증할 수단이 없다**.
- **AppleScript / System Events** — 자동화(TCC) 권한은 "앱이 터미널·다른 앱을 조종한다"는 뜻이라 v0.20의 결정(터미널 인계도 `.command` 파일로)과 어긋난다.
- **드래그·다중 선택·제스처** — Phase 2에서 뺀다(오조작 시 되돌릴 수 없고, 필요 사례가 아직 없다).
- **무인 자율 실행**(사용자가 자리를 비운 사이 N분간 연속 조작) — 실행 한도(§4.5)로 막는다.
- **QuickTalk 자신 제어** — 승인 게이트를 우회하는 자기 참조가 된다(금지 목록).

## 3. 위협 모델

| 위협 | 예 | 대응 |
|---|---|---|
| 데이터 파괴 | 메일 "전체 삭제" 클릭, 휴지통 비우기 | 앱별 승인 + 행동별 승인 + 금지 앱 |
| 결제·발송 | "구매"·"보내기" 클릭 | 행동 전 카드 확인(**기본이 확인**) |
| 비밀 노출 | 비밀번호 필드 읽기·입력 | 보안 텍스트 필드 **읽기·쓰기 모두 거부** |
| 셸 우회 | 터미널에 명령 입력 | 터미널 계열 **금지 앱** |
| 권한 상승 | 시스템 설정에서 권한 켜기, 관리자 암호 창 | `SecurityAgent`·시스템 설정 **금지 앱** |
| 사용자 방해 | 사용자가 타자를 치는 중에 클릭이 끼어듦 | **사용자 입력 우선** 가드(§4.4) |
| 무한 루프·폭주 | 같은 버튼 100번 클릭 | 턴당 동작 수 한도 + 최소 간격 |
| 자기 참조 | QuickTalk 설정을 에이전트가 바꿈 | 자기 자신 금지 |

## 4. 안전 설계

### 4.1 3중 게이트 — 셋 다 통과해야 나간다

```
① 마스터 토글   설정 › 도구 › 컴퓨터 제어 (기본 OFF)
② 대상 앱 승인  대화별 UiAppGrant (7일, ①과 같은 만료 모델)
③ 단계 정책     실행 = 매번 확인(기본) / 항상 허용 / 차단
```

- ①이 꺼져 있으면 도구 자체가 모델에 **등록되지 않는다**(`screenshot` 이 Apple FM 에서 빠지는 것과 같은 방식). "거부"가 아니라 "없음"이 안전하다.
- ②는 승인 카드의 **[이 앱 허용]** 으로 쌓인다. 앱 번들 ID 단위. 만료되면 다시 묻는다.
- ③은 기존 `AgentToolPermission.needsApproval` 을 그대로 쓴다 — 새 정책 개념을 만들지 않는다.
- **치명적·상승 권한 차단은 UI 제어에도 그대로 적용**: `sudo` 암호 창(SecurityAgent)은 애초에 금지 앱이라 도달 불가.

### 4.2 금지 앱 목록 (`UiGuard.deniedApps`)

번들 ID 기준. 목록은 코드에 고정하고 설정에 **읽기 전용으로 보여 준다**(사용자가 끌 수 없게 — 끄면 게이트가 무너진다).

| 번들 ID(예) | 이유 |
|---|---|
| `com.apple.SecurityAgent` | 관리자 암호·인증 대화상자 |
| `com.apple.loginwindow` | 로그인·잠금 화면 |
| `com.apple.keychainaccess`, `com.apple.Passwords` | 키체인·암호 앱 |
| `com.1password.*`, `com.agilebits.onepassword*`, `com.bitwarden.*`, `com.lastpass.*` | 비밀번호 관리자 |
| `com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.*` | **셸 우회** — 명령은 `shell` 도구 게이트로만 |
| `com.apple.systempreferences` | 권한·보안 설정 변경 |
| `com.borasarang.QuickTalk` | 자기 참조 |

> 번들 ID는 구현 시 `mdls`/`CFBundleIdentifier` 로 **실측해 확정**한다(위 목록은 후보).

### 4.3 키·텍스트 정책

- **거부하는 키 조합**: `cmd+q`, `cmd+opt+esc`(강제 종료), `ctrl+cmd+q`(화면 잠금), `ctrl+opt+cmd+power`(잠자기), `cmd+shift+q`(로그아웃). 그 외 `cmd+s/c/v/a/z/…`, `return`, `escape`, `tab`, `arrows` 는 허용 목록.
- **보안 텍스트 필드**: `AXSecureTextField`(또는 role `AXTextField` + subrole secure)는 **값 읽기 금지 + 입력 금지**. 시도하면 카드에 "비밀번호 필드에는 입력할 수 없습니다"를 남긴다.
- **텍스트 한도**: 1회 2,000자. 초과하면 거부(붙여넣기 폭주 방지).
- **줄바꿈 포함 텍스트**는 허용하되, `return` 이 "전송"인 앱(메일·메신저)에서는 카드에 **"이 동작이 전송일 수 있음"** 을 표시.
- **좌표 인자 거부**: `x`·`y` 필드가 오면 `UiGuard` 가 거부한다(Phase 3 전까지).

### 4.4 사용자 입력 우선 (유휴 가드)

컴퓨터 제어는 필연적으로 포커스를 가져간다. 다음을 **동작마다** 확인한다.

```
CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)  // 하드웨어 입력만 센다
CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .leftMouseDown)
```

- 하드웨어 유휴가 **0.4초 미만**이면 최대 2초 대기, 그래도 계속 입력 중이면 **실행하지 않고** 카드에 남긴다("사용자가 입력 중이라 실행하지 않았습니다").
- 우리가 만든 합성 이벤트는 `.hidSystemState` 에 잡히지 않으므로 **자기 이벤트로 자기 가드가 막히지 않는다**(구현 시 실측으로 확인).
- **[중단]** 은 기존 `AgentRunHandle` 을 그대로 본다 — 동작 사이마다 취소를 확인하고, 취소되면 다음 이벤트를 보내지 않는다.

### 4.5 실행 한도

| 항목 | 값 | 이유 |
|---|---|---|
| 턴당 UI 동작 수 | **30** | 폭주·무한 루프 차단 |
| 동작 간 최소 간격 | **150ms** | UI 가 따라오지 못해 엉뚱한 곳을 누르는 것 방지 |
| 스냅샷 노드 예산 | **400** / 깊이 12 / 6초 | 기존 `WindowContextLimits` 재사용(앱이 멈춰도 앱 전체가 멈추지 않게) |
| AX 메시징 타임아웃 | **1.5초** | 기존과 동일 |

### 4.6 되돌리기 정책 — **없다**

- 클릭·키 입력은 되돌릴 수 없다. `UndoStack`(파일 백업)과 성격이 다르므로 **연결하지 않는다**.
- 대신 **행동 전에** 카드에 무엇을 할지 보여 주고, `type` 은 **기존 값을 카드에 남긴다**(사용자가 직접 복원할 수 있게, 보안 필드는 제외).
- 카드 문구에 "이 동작은 되돌릴 수 없습니다"를 **항상** 넣는다(중요·치명적만이 아니라).

### 4.7 감사

`AgentAudit.record` 확장 — `tool: "ui"`, `command: "ui:click Notes \"저장\""`, 입력 텍스트는 **마스킹**(`AgentAudit.mask` 재사용). 출력 본문은 남기지 않는 기존 원칙 유지.

## 5. 도구 설계

### 5.1 `ui_snapshot` (읽기)

```json
{ "name": "ui_snapshot",
  "parameters": { "app": "앱 이름 또는 번들 ID(생략 시 앞에 있는 앱)" },
  "returns": "[r12] button \"저장\" center=(812,640)\n[r13] textfield \"메모\" value=있음" }
```

- 참조 ID는 `r<n>` — 같은 스냅샷 안에서만 유효.
- 값은 **있음/없음만** 노출(본문은 이미 `window_context` 로 읽는다 — 중복 노출 방지).

### 5.2 `ui_action` (실행)

```json
{ "name": "ui_action",
  "parameters": {
    "action": "click | type | key | scroll | open_app | focus_window",
    "ref": "r12", "text": "...", "keys": "cmd+s",
    "direction": "up | down", "amount": 3,
    "app": "Notes", "title": "메모",
    "purpose": "한 줄 이유 — 카드에 표시"
  } }
```

- `purpose` 는 **필수**(셸의 `purpose` 와 같은 이유 — 카드에서 사람이 판단한다).
- 모든 인자는 `UiActionSpec`(Core, 순수)에서 **검증**한다. 검증 실패는 모델에게 이유를 돌려준다(예: "좌표 클릭은 지원하지 않습니다. ui_snapshot 으로 요소를 고르세요").

## 6. 판정 흐름

```
ui_action 도착
  ├ 마스터 OFF?            → 도구 미등록(애초에 호출 불가)
  ├ 대상 앱이 금지 목록?   → deny(이유)
  ├ 보안 필드 / 금지 키?   → deny(이유)
  ├ 좌표 인자?             → deny(이유 + 스냅샷 안내)
  ├ 실행 한도 초과?        → deny(한도)
  ├ 사용자 입력 중?        → (2초 대기) → 여전히 → deny(사용자 입력 우선)
  ├ 앱 승인 있음?          → 없으면 ask(카드: [허용] [이 앱 허용] [거부])
  ├ 단계 정책 = 매번 확인? → ask(카드: 무엇을 어디에)
  └ allow → 요소 재해석 → role/이름 일치 확인 → 이벤트 주입 → 카드 갱신 → 감사
```

- **요소 재해석**: 스냅샷 이후 UI 가 바뀌었을 수 있다. `UiElementPath`(역할·이름·동일 형제 순번)로 다시 찾고, **역할과 이름이 다르면 실행하지 않는다**("UI가 바뀌었습니다. ui_snapshot 을 다시 호출하세요").
- 카드에는 `agentEvents` 를 그대로 쓴다(`state: .pending/.running/.done/.denied`).

## 7. 파일 계획

### 신규 (Core — 전부 순수 함수, 단위 테스트 대상)

| 파일 | 내용 |
|---|---|
| `Sources/QuickTalkCore/UiAction.swift` | `UiAction`(enum) · `UiActionSpec`(파싱·검증) · 카드 문구 |
| `Sources/QuickTalkCore/UiGuard.swift` | 금지 앱·보안 필드·금지 키·좌표 거부·실행 한도 → `.allow/.ask/.deny` |
| `Sources/QuickTalkCore/UiElementPath.swift` | 요소 경로(역할·이름·형제 순번) 생성·비교 |
| `Sources/QuickTalkCore/UiAppGrant.swift` | 앱별 승인(7일 만료, ①`WriteScopeGrant` 와 같은 형태) |

### 신규 (App — 시스템 API 접촉면)

| 파일 | 내용 |
|---|---|
| `QuickTalkApp/AccessibilityService.swift` | 트리 스냅샷(예산·타임아웃) · 경로로 요소 찾기 · 보안 필드 판정 · 프레임 |
| `QuickTalkApp/UiControlService.swift` | `CGEvent` 클릭·키·텍스트·스크롤 · `NSWorkspace` 앱 실행 · 유휴 가드 |
| `QuickTalkApp/AgentExecutor+UI.swift` | 도구 분기 · 승인 카드 · 감사 · 실행 한도 |

### 수정 (요지)

| 파일 | 변경 |
|---|---|
| `Sources/QuickTalkCore/ToolSchemas.swift` | `ui_snapshot`·`ui_action` 카탈로그 + 지시문(모델이 좌표를 시도하지 않게) |
| `Sources/QuickTalkCore/AgentToolPermission.swift` | `ui_snapshot` = 읽기, `ui_action` = 실행 |
| `Sources/QuickTalkCore/Settings.swift` | `uiControlEnabled`(기본 false) + 디코드/인코드 |
| `Sources/QuickTalkCore/Models.swift`·`Store.swift` | `Conversation.approvedUiApps` · `setUiAppGrants`(만료 정리) |
| `QuickTalkApp/AgentExecutor.swift` | `"ui_snapshot"/"ui_action"` 분기 |
| `QuickTalkApp/AgentRunner.swift` | 도구 등록 조건(마스터 OFF·Apple FM 은 제외) |
| `QuickTalkApp/WindowAttachmentService.swift` | AX 탐색 헬퍼를 `AccessibilityService` 로 이동(중복 제거) |
| `QuickTalkApp/SettingsView+Tools.swift` | `컴퓨터 제어` 그룹 · 손쉬운 사용 캡션 갱신 |
| `QuickTalkApp/AgentCard.swift` | "되돌릴 수 없음" 배지 · [이 앱 허용] |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 신규 문구 영어 키 |
| `Sources/QuickTalkCore/SystemKnowledge.swift` | "컴퓨터 제어" 상태를 모델 지식에 |
| `QuickTalk.xcodeproj/project.pbxproj` | 신규 7파일 등록(C0FFEE 고정 ID) |

## 8. 설정 UI (설정 › 도구·권한)

```
컴퓨터 제어
  [ ] 화면 조작 허용 (기본 꺼짐)
      켜면 모델이 클릭·입력할 수 있습니다. 좌표가 아니라 접근성 요소로만 조작하고,
      앱마다 한 번 더 승인을 받습니다. 이 동작은 되돌릴 수 없습니다.
  손쉬운 사용   허용됨 / 허용되지 않음   [설정 열기]
  이 대화에서 허용한 앱
      Notes — 11월 5일까지 유효  [해제]
  조작할 수 없는 앱 (고정)
      관리자 암호 창 · 키체인 · 암호 앱 · 터미널 · 시스템 설정 · QuickTalk
```

- 기존 `시스템 권한` 그룹의 캡션을 갱신: "손쉬운 사용은 다른 앱 창의 글자를 읽고, **컴퓨터 제어를 켠 경우 클릭·입력**에 씁니다."
- 새 문자열은 전부 `L()` + `LocalizationTable` 영어 키 동시 등록(i18n 키 누락 0).

## 9. 검증 계획

### 9.1 단위 테스트 (Core, 순수)

| 테스트 | 고정하는 계약 |
|---|---|
| `UiGuardTests` | 금지 앱 거부 · 보안 필드 거부 · 금지 키 거부 · 좌표 거부 · 한도 초과 거부 · 마스터 OFF 면 도구 미등록 |
| `UiElementPathTests` | 같은 역할·이름 형제 구분(순번) · 이름 변경 시 불일치 · 깊이/예산 초과 |
| `UiActionSpecTests` | 인자 검증(빈 text·2,000자 초과·알 수 없는 action) · `purpose` 필수 |
| `UiAppGrantTests` | 7일 만료 경계(같은 순간 = 만료) · 재승인 갱신 · 만료 정리 · 구버전 JSON |

각 항목은 **되돌려 실패 확인**(판정을 항상 allow 로 바꾸면 몇 건이 실패하는지)까지 기록한다.

### 9.2 빌드·렌더

- `swift test` 전체 · Debug/Release `xcodebuild`(Debug 경고 0)
- 오프스크린 렌더: 설정 › 도구(마스터 OFF / ON) · 승인 카드 문구(`--demo-ui-action`) · 한/영

### 9.3 실측(사용자, 앱 재실행 후)

| # | 항목 | 기대 |
|---|---|---|
| U1 | 마스터 OFF 상태에서 "메모 앱에 문장 입력해줘" | 모델이 도구를 못 씀 / 도구 목록에 없음 |
| U2 | 마스터 ON → 같은 요청 | 승인 카드에 **무엇을 어디에** 표시, 거부 시 아무 일도 없음 |
| U3 | [이 앱 허용] 후 재요청 | 7일 동안 다시 묻지 않음 · 설정에 만료일 표시 |
| U4 | 비밀번호 필드 입력 요청 | 거부 + 이유 표시 |
| U5 | 터미널 앱 대상 요청 | 금지 앱 거부 |
| U6 | 사용자가 타자를 치는 중 실행 | "입력 중이라 실행하지 않았습니다" |
| U7 | 실행 도중 [중단] | 다음 동작이 나가지 않음 |
| U8 | 31번째 동작 | 한도 초과로 중단 |

## 10. 위험 · 한계 (미리 적는다)

- **포커스 강탈은 피할 수 없다** — 다른 앱을 조작하려면 그 앱이 앞에 있어야 한다. 유휴 가드로 "사용 중"일 때만 피한다.
- **요소 이름이 언어·버전에 따라 다르다** — `ui_snapshot` 을 매 턴 새로 부르는 것이 기본이고, 경로 불일치는 **실행하지 않는 쪽**으로 처리한다.
- **웹 콘텐츠(Chromium)는 트리가 늦게 만들어진다** — `AXManualAccessibility` 힌트를 쓰고, 비어 있으면 "스냅샷이 비었습니다"를 돌려준다(추측 금지).
- **Apple FM 은 도구 목록에 없다**(`shell`/`read_file`/`list_dir` 만 등록) → 컴퓨터 제어는 원격 모델 전용.
- **되돌리기 없음** — 파일 백업(`UndoStack`)과 연결하지 않는다.
- **픽셀 클릭 없음** — 버튼이 AX 로 노출되지 않는 앱(일부 게임·캔버스 앱)은 Phase 2로 조작 불가.

## 11. 작업 순서

### Phase 1 (먼저 배포) — **구현 완료 2026-10-29**

- [x] `UiElementPath` + `AccessibilityService` 스냅샷 (예산·타임아웃)
- [x] `ui_snapshot` 도구 + `AgentToolPermission`(읽기) + 카드·감사
- [x] 설정: `컴퓨터 제어` 그룹 — Phase 1은 **읽기 전용**이므로 토글 이름도 `화면 요소 읽기 허용`
- [x] 테스트 `UiSnapshotTests` 16건 · `AgentTests.testUiSnapshotToolIsOptIn` · 렌더 한/영
- [ ] 실측 U1·U4(읽기 쪽) — **앱 재실행 후 사용자**
- [x] 공통 AX 헬퍼 `AXAccess` 로 `AXWindowReader` 중복 제거
- [x] QuickTalk 자신을 기본 대상에서 제외(다른 앱 창이 없으면 빈 결과)

### Phase 2 — **구현 완료 2026-10-31 (테스트·빌드 통과, 배포·실측 대기)**

- [x] `UiGuard`(금지 앱·키·보안 필드·좌표·한도) + `UiActionSpec`
- [x] `UiAppGrant` + `Conversation.approvedUiApps` + 설정 목록
- [x] `UiControlService`(클릭·키·텍스트·스크롤·앱 실행) + 유휴 가드
- [x] `AgentExecutor+UI` 승인 카드 · [이 앱 허용] · "되돌릴 수 없음" 배지
- [x] 테스트 `UiGuardTests`·`UiActionSpecTests`·`UiAppGrantTests` — **619/619**, 되돌려 실패 확인 완료
- [ ] 실측 U2~U8 — **앱 재실행 후 사용자**(배포 후)

### Phase 3 (비목표, 필요해지면 별도 계획)

- 픽셀 좌표 클릭 · 드래그 · 비전 모델 좌표 해석 · 다중 창 시나리오

## 12. 결정 (2026-10-29 확정)

1. **앱별 승인 기간** — **7일 만료** (①승인 폴더와 같은 모델, 만료 시 재승인·설정에 만료일 표시).
2. **터미널 계열 금지** — **유지** (셸 우회 차단. 명령은 `shell` 도구 게이트로만).
3. **배포 단위** — **Phase 1 먼저** (읽기 전용 배포 → 실측 → Phase 2).

### Phase 1 구현 메모

- `ui_snapshot`은 `AgentToolCatalog.all`에 넣지 않았다 — `available(includingUI:)`로만 추가한다.
  기본 목록에 넣으면 Apple FM·QA 하네스까지 딸려 가고, 마스터 토글이 꺼진 사용자에게도 노출된다.
- 참조 `r<n>`은 스냅샷 안에서만 유효하며, 이름 없는 컨테이너를 평탄화해도 **같은 부모의 순번표를 이어 쓴다**
  (따로 세면 평탄화된 형제끼리 index가 겹쳐 Phase 2에서 엉뚱한 요소를 누른다).
- 비밀번호 필드는 `hasValue = false`로 보고한다 — 값이 있어도 없다고 말한다.
- 손쉬운 사용 권한이 없으면 `noPermission`과 **허용 경로**를 돌려준다(스크린샷과 같은 방식).
