# PLAN v0.20–v0.22 — 실행 고도화 · 스크린샷/슬래시/Shortcuts · 대화별 권한 (macOS)

> 작성: 2026-10-25 · 상태: **구현 완료 · 런타임 실측 대기 · 미커밋**
> 상위 문서: `docs/HANDOFF.md`(단일 출처) · `docs/CHANGELOG.md` · `docs/analysis/META-AI-APP-2026-10-25.md`

## 0. 한 줄 요약

v0.18의 에이전트 런타임(도구·권한 게이트) 위에 **"실행을 실제로 쓸 수 있게"** 만드는 3단계를 얹었다.
핵심 원칙은 그대로다 — **앱은 명령어 이름을 모르고, 위험은 구조로 판정하며, 안전장치는 사용자가 끄더라도 한 번 더 확인한다.**

| 버전 | 주제 | 핵심 |
|---|---|---|
| v0.20 | 실행 고도화 | 자동 수락(안전장치 유지) · 실시간 출력 · 중단 · 제한 시간 · 터미널 인계 |
| v0.21 | 관찰·입력 확장 | `screenshot` 도구 · 슬래시 팔레트 · Shortcuts(초안 채움) · 규칙 테스터 |
| v0.22 | 맥락별 권한 | 대화별 오버라이드 · 승인 폴더 UI · 앱 지식 실제값 주입 |

## 1. v0.20 — 실행 고도화

### 1.1 전역 자동 수락 (`AgentPolicy.autoAcceptAll`)

결정 순서를 **바꾸지 않았다**. 자동 수락은 ④번에 들어간다.

```
① 치명적 → (허용 설정 없으면) 차단
② 상승 권한(sudo) → (허용 설정 없으면) 차단
③ 위험도 "중요" → 언제나 확인
④ 자동 수락 → 일반 명령만 통과
⑤ 승인된 폴더 범위 → 통과
⑥ 사용자 허용 규칙 → 통과
⑦ 단계별 정책(읽기/쓰기/실행)
```

즉 **자동 수락을 켜도 `rm -rf /` 는 차단되고 `defaults write` 는 확인**한다. 테스트로 고정했다
(`AgentOverrideTests.testAutoAcceptAllStillAsksForImportant` 등).

### 1.2 스트리밍 실행 · 중단 · 제한 시간

- `SandboxRunner.runStreaming(command:profile:timeout:outputLimit:cancellation:onOutput:)`
  - stdout·stderr 를 **동시에** 비동기로 읽는다(한쪽을 끝까지 읽으면 다른 쪽이 차서 교착).
  - `onOutput` 은 **IO 스레드**에서 호출된다 → 호출부가 메인으로 넘긴다.
- `SandboxCancellation`: `Task.cancel()` 은 `Task.detached` 안의 `Process` 에 닿지 않는다.
  실행 쪽과 취소 쪽이 함께 보는 락 상자를 두고, 20ms 주기로 확인해 `terminate` → 필요하면 `SIGKILL`.
- UI: `LiveShellOutput` 이 0.15초에 한 번만 카드를 갱신한다(조각마다 갱신하면 UI 가 끊긴다).
- 제한 시간: 설정 30/60/120/300초, 코드에서 10~600 으로 클램프.

### 1.3 터미널 인계 (`TerminalHandoff` + `TerminalHandoffService`)

앱이 **실행하지 않는** 두 경우:

1. 상승 권한이 필요하다(`sudo`).
2. 쓰기 범위가 시스템 영역이다.

"안 됩니다"로 끝내지 않고 실행 가능한 `.command` 파일을 만들어 연다.
**AppleScript(`do script`)를 쓰지 않는다** — 자동화(TCC) 권한이 필요하고, 그 권한은 "앱이 터미널을 조종한다"는 뜻이라
최소 권한 원칙에 어긋난다. `.command` 는 Finder/터미널이 직접 여는 것이라 추가 권한이 없다.

시스템 영역 판정(`TerminalHandoff.isSystemWrite`)은 **파일이면 상위 폴더**로 본다.

| 경로 | 판정 | 이유 |
|---|---|---|
| `/etc/hosts` | 인계 | 상위 `/etc` 가 시스템 루트 |
| `/usr/bin/tool` | 인계 | `/usr` 아래 |
| `/Library/LaunchDaemons/x` | 인계 | `/Library` 아래 |
| `/opt/homebrew/…` | **허용** | 도구 설치 경로 — 막으면 `brew install` 이 전부 터미널로 밀린다 |
| `/usr/local/bin/x` | **허용** | 위와 같음 |
| `~/Documents/a.txt` | 허용 | 사용자 홈 |
| `임시 폴더` | 허용 | `/var/folders`·`/private/tmp` |
| `/Users/다른사용자/a` | 인계 | 내 홈 밖 |

### 1.4 카드

- 자동 허용된 실행도 **카드에 남긴다**(예전에는 화면에 전혀 보이지 않았다).
- 실행 중이면 [중단] 버튼.
- `terminalCommand` 가 있으면 [터미널에서 열기] + 인계 실패 사유 안내.
- 중요·치명적 승인은 **2차 확인**: 첫 클릭은 무장(문구·색 변경), 두 번째 클릭에서 실행.

## 2. v0.21 — 스크린샷 · 슬래시 · Shortcuts · 규칙 테스터

### 2.1 `screenshot` 도구

- 대상: `window`(기본, z-order 맨 앞) / `screen`(주 디스플레이).
- `WindowAttachmentService.captureForTool(target:)` — 기존 창 캡처 재사용(그림자 제외, 최대 2048px, 단색 1회 재시도).
- 파일: `~/Library/Application Support/QuickTalk/window/screenshot-<target>-<시각>.png`(7일 정리).
- **읽기 전용** — 클릭·입력·스크롤 없음.
- 권한 없으면 `WindowAttachError.noPermission` → 카드와 모델 응답에 **허용 방법**을 적는다.

**이미지가 다음 스텝에 실리는 방법**: `AgentClients` 는 첨부를 **마지막 메시지가 user 일 때만** 싣는다.
그래서 `AgentRunner` 가 tool 메시지 뒤에 user 메시지("방금 찍은 스크린샷을 첨부했습니다…")를 붙이고,
누적 이미지(최대 3장)를 다음 `nextStep` 의 attachments 로 넘긴다.

**Apple FM**: `AgentClients` 의 FM 경로는 `shell`/`read_file`/`list_dir` 만 도구로 등록한다 →
`screenshot` 은 자동으로 빠지고 텍스트 폴백이 된다(모델이 "볼 수 없다"고 답하는 대신 도구 목록에 없음).

### 2.2 슬래시 팔레트 (`SlashCommand.swift`)

- 표시 조건: 입력이 `/` 로 시작하고 **아직 한 줄·첫 토큰**(공백 없음).
- 명령: 화면 · 창 · 디스크 · 프로세스 · 메모리 · 설정 · 도움말.
- 동작: **클릭하면 템플릿 문장을 입력창에 채운다.** 자유 텍스트를 막지 않는다.
- **Enter 처리(전송)는 건드리지 않았다** — 한글 IME 조합 중 Enter 문제를 다시 만들지 않기 위해.
- 창 연결(🪟)처럼 **권한·선택이 필요한 기능**은 팔레트에 넣지 않았다(입력독 버튼이 담당).

### 2.3 Shortcuts / AppIntents (`QuickTalkIntents.swift`)

- `QuickTalkFillDraftIntent`("질문 채우기") · `QuickTalkOpenIntent`("열기").
- **초안만 채우고 자동 전송하지 않는다** — 사용자가 확인하지 않은 명령이 실행되는 것을 막는다.
- 앱이 막 실행됐으면 `perform()` 이 `applicationDidFinishLaunching` 보다 먼저 끝날 수 있다 →
  `QuickTalkIntentRouter` 가 **대기열**에 들고 있다가 준비되면 넘긴다(질문이 조용히 사라지지 않게).
- `AppShortcutsProvider` 로 Siri 문구 2개 노출.

### 2.4 규칙 테스터 (설정 › 도구)

- 명령을 넣으면 **위험도 · 판정(실행/확인 필요/차단) · 규칙 일치**를 보여 준다.
- **샌드박스 실측(실제 실행)은 하지 않는다.** 실측은 승인 뒤에만.
- 실측 전이므로 단계는 보수적으로 **"실행"으로 가정**한다(상승 권한이면 그 단계).

## 3. v0.22 — 대화별 권한 · 앱 지식 · 승인 폴더

### 3.1 대화별 오버라이드 (`AgentOverride`)

- `nil` = **설정 따름**(구버전 기록 호환). 값이 있으면 그 항목만 덮어쓴다.
- `autoAcceptAll` 도 대화별로 켤 수 있다.
- **치명적 차단·상승 권한 제한은 오버라이드 대상이 아니다** — 대화 하나가 앱 전체 안전장치를 끄지 못한다.
- `Conversation.agentOverride` 는 `decodeIfPresent`(구버전 nil), `Store.setAgentOverride` 는 빈 값을 nil 로 정규화.
- UI: 설정 › 도구 › 이 대화의 권한 — 3분할(설정 따름 / 항상 허용 / 매번 확인), 네이티브 Picker 대신 직접 그린 세그먼트.

### 3.2 승인된 폴더 UI

- 승인 카드의 [이 폴더 허용]이 `writeScopesByConversation` 에 쌓인다(v0.19).
- 설정에서 목록·[해제]. **앱을 다시 켜면 초기화**(세션 한정).

### 3.3 앱 지식 실제값 (`SystemKnowledge`)

- v0.18의 고정 문구를 **설정에서 읽은 사실**로 교체.
- 포함: 저장 위치 · 활성 모델 · 도구/권한 정책 · 자동 수락 · 치명적/상승 권한 · 제한 시간 · 창 연결 · 웹 검색 · 기억 · 음성 · 단축키 · QuickShelf.
- **넣지 않는 것**: API 키 · SecretStore ID · 파일 본문 · 대화 내용.
- "앱에 이미 있는 기능은 다시 만들지 말고 설정 경로만 안내한다"는 규칙 유지.

## 4. 구현 파일

### 신규 (Core)

| 파일 | 내용 |
|---|---|
| `Sources/QuickTalkCore/AgentOverride.swift` | 대화별 오버라이드(병합·요약·빈 값) |
| `Sources/QuickTalkCore/SystemKnowledge.swift` | 설정 → 모델 지식 블록 |
| `Sources/QuickTalkCore/TerminalHandoff.swift` | 인계 판정·`.command` 본문·파일 이름·안내 |
| `Sources/QuickTalkCore/SlashCommand.swift` | 명령 카탈로그·표시 조건·파싱 |

### 신규 (App)

| 파일 | 내용 |
|---|---|
| `QuickTalkApp/TerminalHandoffService.swift` | 파일 생성·실행 권한·`NSWorkspace.open`·7일 정리 |
| `QuickTalkApp/QuickTalkIntents.swift` | AppIntents 2종 + 대기열 라우터 + Siri 문구 |

### 수정 (요지)

- `PolicyEngine` — `autoAcceptAll`(④번) + 디코드 기본값
- `Settings` — `agentStreamOutput`(기본 ON) · `agentTimeoutSeconds`(기본 60) + 디코드/인코드
- `SandboxRunner` — `runStreaming` · `SandboxCancellation` · `StreamCollector`(출력 조각 + 동시 읽기)
- `AgentRunner` — 이미지 누적(최대 3) · 취소 체크 · `screenshot` 제목 · `terminalCommand`
- `AgentTypes`(AgentEvent/AgentToolOutcome) — `terminalCommand` · `imageURL`
- `ToolSchemas` — `screenshot` 도구 + 지시문, `selfKnowledge` → `SystemKnowledge`
- `Models`/`Store` — `Conversation.agentOverride` · `setAgentOverride`
- `AgentExecutor` — 유효 정책 · 자동 허용 카드 · 시스템 경로/상승 권한 인계 · 스트리밍/중단 · `screenshot` · `cancelPending`
- `AgentCard` — 중단 · 터미널 버튼 · 2차 확인 · 인계 안내
- `ContentView` — 슬래시 팔레트 · 카드 새 인자
- `SettingsView(+Tools)` — 실행 방식 · 대화별 권한 · 승인 폴더 · 규칙 테스터
- `UIStore(+Agent)` — `agentRunHandle` · `agentHandoffNotice` · `effectiveAgentPolicy` · `setAgentOverride` · `removeWriteScope` · `cancelAgentRun` · `handoffToTerminal` · `fillDraft` · `cancelReply` → `cancelPending`
- `QuickTalkApp.swift` — `QuickTalkIntentRouter.install`
- `LocalizationTable` — 신규 문구 영어 번역
- `project.pbxproj` — 신규 6파일 등록

## 5. 검증 (2026-10-25)

| 항목 | 결과 |
|---|---|
| `swift build` | OK |
| `swift test` | **499/499**, 6 skip(`QT_LIVE` 4 + `QT_LIVE_STREAM` 2), 실패 0 — 기준선 467 → **+32** |
| `xcodebuild … build` | **BUILD SUCCEEDED** — 경고 1건(사용자 v0.19 WIP `AgentExecutor.swift:217` 의 불필요한 `await`, 이번 변경과 무관) |
| 신규 테스트 | `AgentOverrideTests`(11) · `SlashCommandTests`(6) · `SystemKnowledgeTests`+`TerminalHandoffTests`(11) · `StreamingExecutionTests`(5) |

> 런타임 실측은 **하지 않았다** — 사용자 맥 사용 중이라 앱 실행·권한 승인·실제 캡처·터미널 열기를 수행하지 않았다.

## 6. 실측 체크리스트 (사용자)

체크리스트는 **테스트 문서로 분리**했다 → **`docs/qa/v0.20-22/CHECKLIST.md`**

| 묶음 | 항목 | 내용 |
|---|---|---|
| v0.20 | V20-1~10 | 자동 수락(일반 통과·중요 2차 확인·치명적/상승권 차단) · 실시간 출력 · [중단] · 승인 대기 중 중단 · 제한 시간 · 터미널 인계 · `brew install` 예외 |
| v0.21 | V21-1~12 | `screenshot`(창/화면·권한 없음·Apple FM 제외) · 슬래시 팔레트 · 한글 Enter 회귀 · Shortcuts(초안·대기열) · 규칙 테스터 |
| v0.22 | V22-1~7 | 대화별 3분할·대화 전환 초기화 · 치명적/상승권 유지 · 승인 폴더 목록/해제 · 앱 지식 실제값·키 미노출 |

> 런타임 실측은 **하지 않았다** — 사용자 맥 사용 중이라 앱 실행·권한 승인·실제 캡처·터미널 열기를 수행하지 않았다.

## 7. 알려진 한계 / 하지 않은 것

- **창 제어(computer use)는 넣지 않았다** — Meta AI 분석의 P2. 기본 OFF 로 두는 것보다 아예 넣지 않는 쪽을 택했다(위험 대비 효용).
- **Shortcuts 자동 전송**은 넣지 않았다(초안 채움만).
- **슬래시 팔레트 키보드 탐색(↑↓·Tab)** 은 넣지 않았다 — Enter 처리 변경이 한글 IME 회귀 위험이 있어 클릭 선택만.
- **터미널 인계 파일은 임시 폴더**(`$TMPDIR/QuickTalk/handoff`)에 만들고 7일 뒤 정리한다. 앱은 실행 여부를 알 수 없다.
- **승인된 폴더는 세션 한정** — 앱을 다시 켜면 초기화된다(영구 허용은 전역 허용 규칙으로).
- **스트리밍 출력 조각은 표시용** — UTF-8 문자 중간에서 잘릴 수 있어 최종 문자열은 Data 로 다시 만든다.
- **규칙 테스터는 실측하지 않는다** — 실제 요구 권한(읽기/쓰기/네트워크)은 승인 뒤 샌드박스가 정한다.

## 8. 다음 작업

1. 위 체크리스트 실측 → 실패 항목 수정.
2. v0.19 WIP(쓰기·되돌리기)와 함께 **PR**(hunk 단위 — `project.pbxproj`·`AppDelegate+RenderHarness` 는 WIP 와 섞여 있음).
3. 배포는 사용자 확인 후(`~/Applications/QuickTalk.app`).
4. 남은 실측: N22·N24~N28·N30 · T-21 30건 · QA 미체크 52건.
