# HANDOFF — QuickTalk (macOS)

> **새 세션은 이 문서부터 읽한다.** 마지막 갱신: 2026-10-22 21:34 KST
> **git 저장소 있음**(2026-10-21 20:12 초기화) — `origin https://github.com/BoraSarang/QuickTalk.git`, `main` 추적 중.
> T-21은 **PR #2 → squash merge `6d344cf`**로 `main`에 병합됐다. **`main` 직접 push 금지** — 다음 작업도 브랜치 → PR.
> **현재 작업 브랜치 `main`** — 안전장치(치명적 명령 실행 전 차단)는 PR #13 → squash merge `53c23c4`, 단일 인스턴스 가드는 PR #10 → `5114e08`, 공용 메모리 기본 OFF 는 PR #15 → `998f787`, 🧠·카드 순서·`processes` 는 PR #16 → `9fdc9b9`, 대화 창 위치 조율은 PR #18 로 병합 예정이다.
> **사용자 맥 사용 중** — 앱 실행/종료·스크린샷·창 조회·소리 재생 금지. 코드·빌드·오프스크린 렌더·문서만.

## 0. 30초 요약

| 항목 | 상태 |
|---|---|
| 앱 | QuickTalk macOS, SwiftUI + AppKit, `com.borasarang.QuickTalk`, LSUIElement, 샌드박스 없음 |
| design_profile | **custom** — 네이티브 alert/Picker/NSPopUpButton 금지(전면 설정의 기존 `pickerRow`만 예외) |
| 현재 빌드 | **2026-10-22 21:50 대화 창 위치 조율(pill=입력한 자리 · 마지막 위치)** — `~/Applications/QuickTalk.app`, Apple Development 서명, `codesign --verify --strict` OK, SHA-256 `344e6c486613a7ca…` |
| 테스트 | **395/395**, 6 skip = `QT_LIVE` 4 + `QT_LIVE_STREAM` 2 (신규 10 = 창 배치 9 · 설정 왕복/미지값 1) |
| 마지막 완료 | **대화 창 위치 조율**(2026-10-22 21:50) — pill 은 `lastAnchor`(입력한 자리)에서 창이 이어지고, 설정(중앙/포인터/**마지막 위치**)은 보관함·Hub·QuickShelf·이어서 열기에만 적용. `WindowPlacement`(Core)로 규칙을 테스트 가능하게 분리. **재실행 필요** |
| 다음 작업 | **T-18 실측**(`docs/qa/t18-agent/CHECKLIST.md` P1~P19) → v0.19(쓰기·되돌리기) → v0.20(실행 고도화) → T-21 실측 → QA 배치 3·4 |
| 실측 대기 | **N22·N24·N25·N26 4건** + **T-18 19건** + **T-21 27건** + **QA 미체크 53건**(배치3 21 · 배치4 27 · 외부 2 · L9 1 · I8 1 · N26 1) |
| 운용 방침 | **주 = 원격 OpenAI 호환, 예비 = Local Apple FM.** 로컬 Ollama는 보조(한계 수용). 설정 › AI에서 활성을 원격으로 되돌려 둔다 |
| 실행 중 앱 | **재실행 필요** — 돌아있는 것은 21:05 빌드(`f3d9b697…`). 🧠·카드 순서·`processes`(PR #16) + 창 위치(PR #18)가 재실행 후 함께 반영된다 |
| git | `main` = **`3560fc9`** (HANDOFF SHA 갱신 · PR #17) · 창 위치 조율 = PR #18 (squash merge 예정) |

### 세션 진행 (2026-10-22 21:50) — 대화 창 위치 조율 (pill 은 입력한 자리)

#### 사용자 지적
- "pill 대화는 언제나 마우스 포인터 잖아?? 저게 마우스 포인터라고 되어 있으면 pill 에서 대화 입력하면
  그 포인터 위치에서 대화창이 열리나?? 이거 설정 핵갈리지 않니?? 먼가 조율이 필요 할 것 같은데?"

#### 원인
1. `PointerPillController.frame()` 은 `NSEvent.mouseLocation` 만 보고 pill 을 놓는다 — **설정을 읽지 않는다**.
2. 대화 창은 `showPanel` → `positionPanel()` 이 열 때마다 `newWindowPosition` 으로 **재배치**한다
   (`setFrameAutosaveName` 이 사실상 무력화 — 옮긴 자리를 기억하지 못했다).
3. 그래서 중앙 모드에서는 **포인터에서 입력 → 창이 화면 중앙으로 점프**했고, 포인터 모드에서만 이어졌다.
   메뉴바에서 열면 포인터가 작업 영역 밖이라 `pointerCache`(0.6초 샘플)를 쓰는데 설명이 없었다.

#### 결정 (사용자 선택)
- **입력한 자리 유지** — pill 로 시작한 대화는 포인터 자리에서 창이 이어진다(설정보다 우선).
- **마지막 위치 옵션 추가** — 중앙 / 마우스 포인터 / 마지막 위치 3개.

#### 구현
- `Sources/QuickTalkCore/WindowPlacement.swift` 신설 — `origin(mode:size:anchor:visibleFrame:)`,
  `centered`, `clamped`. anchor 가 있으면 설정을 무시하고 그 자리, `lastPosition` 은 nil(유지).
- `NewWindowPosition.lastPosition` + 라벨 "대화 창 위치" · 캡션 2줄 · 번역 4키.
- `PointerPillController.lastAnchor`(캐럿 지점, `present()` 에서 기록 — `finish()` 는 dismiss 뒤에 콜백).
- `showPanel(tab:anchor:)` · `positionPanel(anchor:)` · `handlePill` 이 anchor 전달.
  보관함(.archive)도 pill 자리에서 열린다 — "입력한 자리에서 이어진다" 규칙 하나로 통일.

#### 검증
- `swift test` **395/395**(6 skip, 신규 10: 중앙·anchor 우선·포인터 폴백·lastPosition 유지·클램프·음수 원점 /
  설정 왕복·미지값 폴백), BUILD SUCCEEDED, 오프스크린 렌더 `settings-general-ko`(3옵션·캡션 2줄) 확인.
- `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict` OK · SHA-256 `344e6c486613a7ca…`.
- **실측 대기** — N26(점프 없음·설정 적용 범위·마지막 위치 기억·화면 밖 클램프).

### 세션 진행 (2026-10-22 21:34) — 🧠 표시 · 카드 순서 · `ps`/`top` 실행 불가

#### 사용자 보고
- N22 **ERR** — "회색 으로 안보임, 기존과 동일"
- "지금 실행한 쉘 명령이 응답 하단에 뜨는데… 순서로 보면 쉘 명령 후 응답이잖아? 검색은 참고니까 하단이 자연스러운데 **쉘 명령은 이질적**이네"
- "Operation not permitted 문제 확인하고"

#### 원인 (실측)
1. **🧠**: `brain.slash` 는 macOS 27.2 에 **존재하지 않는 SF Symbol** → `Image(systemName:)` 이 **빈 뷰**(회색도 안 보임).
   예전 코드가 전역 OFF 일 때 아이콘을 숨긴 것과 겹쳐 "안 보임"이 두 번 발생했다.
2. **카드 순서**: `ContentView` 가 `MarkdownText`(답변) → 시간 → 출처 → `AgentCard`(도구) 순으로 그렸다.
3. **`ps`/`top`**: 둘 다 **setuid root**(`-rwsr-xr-x`). `sandbox-exec` 은 프로파일과 무관하게 setuid 바이너리 **exec 를 거부**
   (`(version 1)(allow default)` 만으로도 실패 — 실측). 실측은 이 메시지를 **쓰기 거부**로 오분류해 "쓰기(/usr/bin/top)" 카드를 띄웠고,
   `ps … | head` 는 파이프 종료코드가 0 이라 **읽기 성공(state=done, 빈 출력)** 으로 오판됐다.

#### 수정
- `ContentView`: 🧠 는 `brain` **하나**로 그리고 **색**으로 상태 구분(켜짐 보라 / 꺼짐 회색). 앱 전체 SF Symbol 이름 자동 점검(오류는 이것 하나).
- `ContentView`: `AgentCard` 를 답변 **위**로 이동(검색 출처 카드는 아래 유지).
- `SandboxRunner`: `isSetuidBinary` · `setuidPrograms(in:)`(실행 위치만 — `grep ps` 오탐 방지) · `blockedNote(for:)`.
  `runProbe` 는 setuid 를 **실행해 보지 않고** `.blocked` 로 돌려준다(파이프 오판 방지).
- `AgentCapability.unprobed` 신설 — 중요·치명적 명령은 **승인 후 실측**(기존 `.blocked` placeholder 와 의미 분리).
- `ProcessSampler`(Core 신설) + **`processes` 도구** — libproc 으로 CPU%/RSS. 셸·권한 불필요.
- `AgentExecutor`: `.blocked` 는 **실행하지 않고** 이유를 모델에 반환, `processes` 핸들러 추가.
- 지시문: `ps`·`top` 은 샌드박스 불가 → `processes` 사용(프로세스 목록에서 `ps` 를 뺐다).

#### 검증
- `swift test` **385/385**(6 skip, 신규 9) · BUILD SUCCEEDED(경고 0).
- 오프스크린 렌더: 헤더에 **회색 🧠 표시**, `--demo-agent` 에서 **도구 카드가 답변 위**.
- 헤드리스: `--agent-test="CPU 많이 쓰는 프로세스 3개만 알려줘"` → `tool=processes state=done` **2스텝**,
  메모리 질문 → WebKit 1.63 GiB · opencode-cli 1.02 GiB 등 실제 값.
- 배포 2026-10-22 21:33 · `codesign --verify --strict` OK · SHA-256 `c701008c270e79de…`.

#### 한계
- 온디바이스 Apple FM 은 짧은 지시문에서 `ps` 를 반복 시도한다(차단 안내는 받지만 도구를 안 고름). 주 모델(원격)에서는 정상.

#### 남은 일
- **재실행** 후 N22(회색 🧠 + 눌러서 보라) · N24(`ps`/`top` → 실행 불가 + `processes` 값) · N25(카드가 답변 위) 확인
  → T-18 실측 → v0.19(쓰기·되돌리기).

### 세션 진행 (2026-10-22 21:10) — 공용 메모리 기본값 Off

#### 사용자 요청
"공용 메모리 기본 값 Off 로 해줘"

#### 한 일
- `QuickTalkSettings.globalMemoryEnabled` 기본값 `true` → `false`(디코딩 fallback 도 `false` 로) + 저장된 사용자 값 갱신.
- 부수: 헤더 🧠 아이콘 — 전역 OFF 여도 항상 표시(회색 · `brain.slash`, 눌러서 켜기/끄기). [2026-10-22 21:00]
- `swift test` **376/376**(6 skip, 신규 2) · BUILD SUCCEEDED · 배포 SHA-256 `f3d9b697a91174e7…` · **재실행 필요**.

#### 남은 일
- 재실행 후 N20·N21·N22·N23 확인 → T-18 실측 → v0.19(쓰기·되돌리기).

### 세션 진행 (2026-10-22 20:40) — 안전장치 사고 대응 (`rm -rf /` 로 앱이 멈춤)

#### 사용자 보고
"이 대화 입력 후.. 열심히 뭔가 하더니.. 앱 죽었음 · 응답에는 실행 할 수 없습니다. 라고 나왔지만 앱 강제 종료된 후 다시 실행시 응답이 사라짐 ·
Document Music, Download 폴더의 접근 권한을 물어 봄 · 심각한 문제인데.. 내 시스템에 이 놈이 영향을 줬는지 바로 확인해"

#### 시스템 영향 확인 → **없음** (2026-10-22 20:20 실측)
- 감사 로그 `~/Library/Application Support/QuickTalk/agent-audit.log` 에 **`rm` 항목 0건** — `rm -rf /` 는 한 번도 실행되지 않았다.
- 루트 전체(`/Applications`·`/System`·`/usr`·`/etc`·`/var`·`/Users`·`/Library`·`/home`·`/bin`·`/sbin`·`/opt`·`/Volumes`) 정상,
  홈 주요 폴더(Documents·Music·Downloads·Movies·Pictures·Desktop) 정상, 여분 522Gi(사용 43%).
- 실행 중인 `rm`·`sandbox-exec` 프로세스 없음, 오늘 크래시 리포트 없음(강제 종료).
- **원리**: 실측은 읽기 전용 샌드박스(`deny file-write*`)라 애초에 지울 수 없었다.

#### 원인 3가지
1. **순서**: [실측(=실제 실행) → 정책 판단] 이라 **치명적 명령이 차단 전에 실행**됐다. `rm -rf /` 가 디스크 전체를 순회.
2. **스레드**: 샌드박스 실행이 **메인 스레드**에서 돌아 UI 가 얼었다(죽은 것처럼 보임).
3. **타임아웃**: `SandboxRunner.run` 이 `readDataToEndOfFile()` 를 **기한 검사 전에** 불러 무한 대기.

#### 수정
- `PolicyEngine.plan()` (Core 신설) — 위험 판정 → 정책 → (일반 명령만) 실측, **실행은 마지막**.
  치명적은 실행 없이 차단, 중요한 명령은 **승인을 먼저** 받고 나서 실측(`probeApproved`).
- 실측·실행을 `Task.detached` 로 **메인 스레드 밖**에서.
- `SandboxRunner.run` — stdout·stderr 를 **동시에 비동기로** 읽고(교착 제거) 기한이 오면 먼저 죽인다.
- **시스템 전역 경로 쓰기 차단** — 실측이 뽑은 쓰기 경로가 `/`·`/Users`·`/System` … 면 쓰기를 아예 열지 않는다.
- `RiskClassifier` 치명적 대상 목록 **대소문자 버그** 수정(`rm -rf /Users` 가 잡히지 않던 문제).
- **끊긴 응답** — 앱이 꺼진 사이에 답이 끝나지 않은 질문은 다음 실행 때 "응답이 끊겼습니다" 안내로 남는다.
- **설정 › 도구 › 실행 기록** — JSON 원문 → 시간·판정·명령·결과·소요시간 표.

#### 검증
- `swift test` **375/375**(6 skip, 신규 13 — 위험 명령 미실측·치명적 대소문자·시스템 전역 쓰기 차단·타임아웃 1초 honored·실행 계획 순서)
- `xcodebuild` BUILD SUCCEEDED(경고 0)
- 배포 2026-10-22 20:40, `codesign --verify --strict` OK, SHA-256 `6a61b998d66852e0290c9c01fcec651af4e4b7f284a866909c2d8240ce8701d1`
- **실행 중 앱은 종료하지 않음 — 재실행 필요**
- **git**: `fix/agent-safety` → **PR #13** → squash merge **`53c23c4`**. `main` 직접 push 없음

#### 참고 — macOS 권한 안내(문서·음악·다운로드)
`du -hd 1 ~` 처럼 홈 전체를 훑는 명령에서 macOS 가 접근 권한을 물었다(앱이 아니라 샌드박스 자식 프로세스).
허용했다면 시스템 설정 › 개인정보 보호 및 보안 › 파일 및 폴더에서 되돌릴 수 있다.

### 세션 진행 (2026-10-22 18:27) — 중복 실행 방지 (앱은 하나만)

#### 사용자 보고
"앱이 동시에 두개가 실행중이다. 이 앱은 하나만 실행 되어야 함. 중복 실행이 되면 안됨"
(스크린샷: pill 창 `무엇이든 물어보세요` 가 두 개 겹쳐 뜸)

#### 원인
- 같은 번들 ID(`com.borasarang.QuickTalk`)의 프로세스가 **3개** 떠 있었다 —
  설치본 1개 + 이전 QA `--ask=` 디버그 실행 2개(4시간 넘게 대기 중).
- 앱에는 **단일 인스턴스 장치가 없었다.** 설치본과 디버그 빌드는 실행 경로가 달라
  LaunchServices 도 막지 않으므로, 두 프로세스가 각각 메뉴바 아이콘·단축키·pill 창을 만들었다.

#### 구현
- **`InstanceLock`(Core)** — `flock(2)` 기반 파일 잠금. 프로세스가 끝나면 OS 가 자동으로 푼다
  (PID 파일만 쓰면 비정상 종료 뒤 찌꺼기로 앱이 영영 안 뜰 수 있다).
- **`QuickTalkLauncher`(새 진입점)** — `QuickTalkApp.main()` **전에** 잠금을 잡는다.
  UIStore·AppKit 창·클립보드 감시가 만들어지기 전이라 두 번째 인스턴스는 흔적을 남기지 않는다.
- 두 번째 실행은 **기존 인스턴스에 분산 알림**을 보내 창을 앞으로 올리고 `exit(0)`.
  기존 인스턴스는 그 알림을 받아 대화 창을 연다(`applicationShouldHandleReopen` 도 같은 동작).
- **예외는 오프스크린 QA 하네스만**(`--render=`·`--*-test`·`--selftest=`). `--ask=`·`--open-panel` 처럼
  **창을 띄우는** 실행은 일반 실행과 똑같이 중복이 막힌다 — 정확히 그 경우에 두 개가 떴기 때문.
- `Info.plist` 에 `LSMultipleInstancesProhibited` 추가(2차 방어).

#### 검증
- `swift test` **362/362**(6 skip, 신규 4 — 두 번째 잠금 실패·해제 후 재실행·자식 프로세스 종료 시 자동 해제·멱등)
- `xcodebuild` BUILD SUCCEEDED(경고 0)
- 실제 바이너리 `--instance-selftest[=hold]` — `ACQUIRED(0)` → 동시 실행 `BLOCKED(3)` → 해제 후 `ACQUIRED(0)`
- 배포 2026-10-22 18:27, `codesign --verify --strict` OK,
  SHA-256 `99308aec19542e10499c74f7ce809de37b6e19b4f4d51bc717778220ff7610aa`
- 남아 있던 QA 중복 프로세스 2개는 종료(설치본은 건드리지 않음)
- **git**: `fix/single-instance` → **PR #10** → squash merge **`5114e08`**. `main` 직접 push 없음

#### 다음
- **사용자가 재실행한 뒤** 앱을 한 번 더 실행해 **새 인스턴스가 뜨지 않는지** 확인
- T-18 실측 → v0.19(쓰기·되돌리기) → v0.20(실행 고도화)

### 세션 진행 (2026-10-22 14:25) — 도구 실행 내역 보기 (실제 쉘 실행 화면)

#### 사용자 요청
"tool 명령 실행시에 저렇게 **빈 칸**이 생기는 것 같은데 · 저거 실제 쉘 실행 화면인가? ·
쉘 실행하면 **실행하는 거 보여 줄 수 있나** · 보여 줄 수 있으면 **설정에서 보여주기/보여주지 않기** 옵션"

#### 한 것
- **빈 칸 제거** — 실행 카드는 **기록이 하나도 없으면 아예 그리지 않게** 했다(조건부 렌더).
- **실제 실행 내역 표시** — 카드에 **실제 명령(`$ …`) + 실제 stdout/stderr(스크롤되는 작은 터미널 창) +
  권한 단계·위험도·경과시간** 이 보인다. 모델이 답변에 붙인 코드블록이 아니라 **앱이 실제로 실행한 것**이다.
- **실행 기록을 턴에 저장**(`Turn.agentEvents`) → 대화 기록(history.json)에 남아 **이후에 다시 열어도 보인다**.
- **설정 › 도구 › "실행 과정 표시"** 토글 추가 — 끄면 카드에 한 줄 요약(도구·단계·결과)만 남는다.
- 렌더 견본: `docs/qa/t18-agent/chat-agent-ko.png` (QA 하네스 `--demo-agent`)

#### 검증·배포
- `swift test` **358/358** (6 skip) · BUILD SUCCEEDED (경고 0)
- 배포 2026-10-22 14:25 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `1c7463205440aaa5fc509d60b7502e67c24809f82dab4eadc63b0f42480b98cc`(빌드와 일치)
- **실행 중 앱은 종료하지 않음 — 재실행해야 반영된다**

### 세션 진행 (2026-10-22 14:00) — 에이전트 라우팅 개편 (도구 선택을 본 모델에)

#### 사용자 보고
"지금 메모리 얼마나 차지 하고 있냐?" → **통하지 않음**(명령을 복사해 줘야 됨). "명령어 복사해서 실행해줘" 로는 됨.
→ **퀄리티가 기대와 다르다**는 지적.

#### 원인 — 내가 만든 "도구 필요 판정"이 잘못되고 있었다
- v0.18 은 **"이 질문에 도구가 필요한가?"를 별도의 작은 분류기 모델에 물어보고** YES 면 에이전트 경로로,
  NO 면 일반 경로로 보내는 구조였다(스트리밍을 유지하려고 그렇게 했다).
- 그 분류기가 **"메모리"를 앱의 '대화 기억'으로 오해**해 NO 를 냈다 → 도구를 안 쓴다.
  (사용자가 "명령을 복사해 줘야" 하면 "실행"이 키워드라서 YES 였다 — 즉 분류기가 유일한 병목)
- 부수 효과: **질문마다 모델을 한 번 더 부르므로** 지연도 늘었다.

#### 해결 — 판정을 없애고 **본 모델이 직접 도구를 고르게**
- **도구 필요 판정 호출 삭제.** 도구가 켜져 있으면 **항상** 도구를 넘기고, **답을 쓰는 모델이 직접** 쓸지 고른다.
- 스트리밍을 유지하려고 **스트리밍 중 도구 호출 조각을 파싱**하도록 확장
  (`SSEEvent.toolCallDelta` · `.reasoning` · `OpenAIClient.streamWithTools` · `OllamaClient.streamWithTools`).
  본문은 그대로 흘러나오고, 도구 호출이 오면 실행 → 결과를 되돌려 **같은 대화에서 이어서** 최종 답.
- 도구를 모르는 서버(400 등)면 **도구 없는 일반 경로로 자동 폴백**(본문이 이미 나오지 않았을 때만).
- 첨부(이미지·문서)가 붙은 질문도 에이전트 경로에서 그대로 전송(마지막 사용자 메시지에 병합).

#### 함께 고친 것 2건
1. **실패한 명령을 권한 문제로 오판** — 존재하지 않는 명령(`free -h`)까지 승인을 요구했다.
   → 이제 "권한 거부 신호가 보일 때만" 승격, 그 외 실패는 **읽기로 분류**해 오류를 그대로 모델에 돌려준다.
2. **같은 명령 무한 반복** — 온디바이스 모델이 `free -h` 를 8번 반복했다.
   → **반복 방지**(같은 명령은 2번까지만 실행, 3번째는 "다른 방법을 쓰라"고 되돌려준다) + Apple FM 전용 **짧은 지시문**.
   (`AgentInstructions.compactText` — 작은 모델은 긴 지시문을 따라가지 못한다)

#### 실측 (같은 질문)
| 프로바이더 | 결과 |
|---|---|
| 원격 OpenAI 호환(주) | ✅ `vm_stat`·`sysctl hw.memsize`·`sysctl vm.swapusage` 등 **3개 명령 자동 실행** → "총 32 GiB" (4스텝·20초) |
| Apple FM(온디바이스) | ⚠️ 도구 호출은 하지만 **macOS 명령을 모름**(Linux식 `free -h` 반복) → 반복 방지로 종료. **주 운영은 원격 권장** |
| 평범한 질문("안녕하세요") | ✅ 도구 0회 · 1스텝 · 바로 답변 (쓸데없는 도구 호출 없음) |

#### 검증·배포
- `swift test` **358/358** (6 skip, 신규 4 — SSE 도구 조각·사고 내용·반복 방지)
- `xcodebuild` BUILD SUCCEEDED (경고 0) · 헤드리스 `--agent-test` 로 실측
- 배포 2026-10-22 14:00 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `e66acb6d0973e9504f457836876c7362cdfe3b348bb2c77cd1f05f420aab78c6`(빌드와 일치)
- **실행 중 앱은 종료하지 않음 — 재실행해야 반영된다**

#### 다음
- 재실행 후 같은 질문으로 확인 → v0.19(쓰기·되돌리기) → v0.20(실행 고도화)
- **남은 개선안**: 작은 모델(온디바이스·무료 프록시)의 도구 선택 품질은 한계가 있다 —
  원격 모델이 훨씬 정확하다(주 운영 권장). 온디바이스를 높이려면 **도구 설명에 자주 쓰는 명령 예시를 넣거나**
  **짧은 지시문을 유지**하는 쪽이 낫다(지금 반영).

### 세션 진행 (2026-10-22 13:05) — 캡처 윈도우 모드 수정 + pill 다중줄 입력

#### 사용자 보고 1 — "윈도우 캡쳐가 안된다"
- 증상: 드래그 캡처(⌥⇧4) 화면에서 **Space** → 라벨만 "윈도우"로 바뀌고, **어떤 창도 잡히지 않음**(드래그가 그대로).
- **원인(찾음)**: `CaptureService.startOverlay` 가 **창 목록을 "처음부터 윈도우 모드일 때만"** 모으고 있었다.
  드래그 모드로 시작해 Space로 전환하면 목록이 비어 있어 → 라벨만 바뀌고 선택이 안 됨.
- **수정**: 창 목록을 **모드와 무관하게 항상** 수집 + 윈도우 모드로 **전환할 때 다시 수집**(그사이 열린 창도 잡히도록).
  잡을 창이 0개면 힌트를 "잡을 수 있는 창이 없습니다"로 바꾼다.
- **검증**: 새 QA 하네스 `--capture-selftest` (드래그 모드 시작 → Space 흉내 → 상태 확인) → `mode=window windows=2 highlight=Y` ✅
- 참고: 시스템 `screencapture -w` 창 선택 UI 는 정상 동작했고, OS 레벨 창 캡처(`screencapture -l<id>`)도 정상 → **macOS 문제가 아니라 앱 버그**였다.

#### 사용자 보고 2 — "pill Shift+Enter 줄넘김이 안된다"
- 요청: pill 입력창을 **대화 창 입력창과 동일하게**(Shift+Enter 줄바꿈 · 위로 성장 · 좌우 아이콘 유지).
- **구현**: pill 의 단일 행 `NSTextField` 를 **대화 입력창과 같은 컴포넌트(`ChatInputField`)** 로 교체.
  - `ChatInputField` 에 폰트(15.5pt)·⌘Return·Esc 훅을 추가 — 주 대화창 동작은 그대로
  - pill 은 **아래 기준선**을 유지하고 위로 자란다 → 오브·보관함 아이콘이 그 자리에 남는다
  - 1줄일 때 모양은 이전과 동일, 최대 4줄
- **동작 중이던 버그 2건도 같이 고침**: (1) SwiftUI 가 폭을 정하기 전에 측정해 높이가 1줄로 남던 문제
  → 텍스트 뷰 폭이 확정될 때 재측정 (2) 값을 프로그램적으로 넣을 때 측정이 안 되던 문제 → 넣은 직후 재측정
- **검증**: 오프스크린 렌더 `docs/qa/t18-agent/pill-multiline-ko.png` (2줄·아이콘 유지) + 실제 앱 화면 캡처로 확인.

#### 검증·배포
- `swift test` **354/354** (6 skip) · `xcodebuild` BUILD SUCCEEDED (경고 0)
- 배포 2026-10-22 13:05 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `c8118e010d684822de58ed7beeabb276ce667d945e4db76436a72aab6d73e734`(빌드와 일치)
- **실행 중 앱은 종료하지 않음 — 재실행해야 반영된다**

#### 다음
- 사용자가 **재실행 후** `docs/qa/t21-pill/CHECKLIST.md` P28~P31(다중줄) · `docs/QA-CHECKLIST-2026-10-20.md` D2-1(윈도우 모드) 확인
- T-18 실측(P1~P19) · T-21 실측(P1~P27) 대기 항목은 그대로

### 세션 진행 (2026-10-22 00:20) — T-18 v0.18 구현·배포 (도우미 도구)

#### 무엇을 만들었나
- **"맥 도우미"의 핵심 기능 구현** — 자연어로 말하면 앱이 **직접 행동**하고 그 결과로 답한다.
  예: "하드 용량 얼마나 남았어" → 실제 `df -h` 실행 → "521 GiB 남음".
- **앱은 명령어 이름을 모른다.** 도구는 3개뿐(`shell`·`read_file`·`list_dir`)이고 모델이 정한 명령을 그대로 실행한다.
  `brew`·`adb`·`pip`·`uv`·`ollama` 를 따로 등록하지 않는다(사용자가 든 예시일 뿐).
- **권한은 분류가 아니라 협상** — 읽기 전용 샌드박스로 먼저 실행해 **요구 권한을 실측**한다.
  쓰기가 막히면 에러에 경로가 같이 나와 "이 경로만 쓰기 허용"으로 재실행한다(승인이 스코프로 제한됨).
- **권한 3단계(읽기/쓰기/실행)** 를 설정 › 도구에서 고른다. 읽기=자동(기본), 쓰기·실행=확인(기본).
  위험도(중요/치명적)는 별도 축 — **중요는 자동 허용이어도 확인**, 치명적은 기본 차단.
- **확인 UI 는 대화 안 카드**(네이티브 alert 금지): [한 번 허용] [항상 허용] [거부]. 거부하면 모델에 알려 다른 방법을 제안.
- **실행 기록**(감사 로그) — `~/Library/Application Support/QuickTalk/agent-audit.log`, 키·토큰은 가림.

#### 프로바이더 3종 통일
| 프로바이더 | 방식 | 실측 |
|---|---|---|
| Apple FM | FoundationModels `Tool` 프로토콜 | ✅ `df -h` 실행 → 521 GiB (3스텝 · 16초) |
| 원격 OpenAI 호환 | `tools` + `tool_calls` | ✅ 도구 3개 실행 + 거부 1개 (4스텝 · 20초) |
| Local Ollama | `/api/chat` 의 `tools` | 구현 완료 · 실측 미수행(로컬 32B 가 느려 세션 시간 제한) |

#### 구현 중 잡은 문제 3건
1. 프록시 thinking 모델이 **2차 요청 400** — `reasoning_content` 를 되돌려 보내야 한다 → `AgentMessage.reasoningContent` 추가
2. Apple FM 의 `GeneratedContent` 를 JSON 직렬화하려다 **NSException 크래시** → `jsonValue` 변환기 추가
3. 위험도 판정이 **시스템 경로 참조**(`/usr/bin/df`)까지 위험으로 봤다 → 변경 명령의 **대상**일 때만 위험으로

#### 검증·배포
- `swift test` **354/354** (6 skip, 신규 22) · `xcodebuild` BUILD SUCCEEDED (경고 0)
- 헤드리스 자가진단 `--agent-test=<질문>` 신규 — 로그 `docs/qa/t18-agent/`
- 배포 2026-10-22 00:06 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `a261f40ba070a92baf33875906bbe37e2f249c8cec9def6a8d85ab0767a87327`(빌드와 일치)
- **실행 중 앱은 종료하지 않았다** — 재실행해야 T-18 이 적용된다.

#### 다음
- **사용자 실측**(P1~P19) → 피드백 반영
- v0.19: 쓰기 단계 + 휴지통 rewrite + 되돌리기 버튼
- v0.20: 실행 단계 + 위험도 고도화 + 백그라운드 실행
- T-21 실측(P1~P27) · QA 배치 3·4 는 그대로 대기

#### git
- `feat/t18-agent-runtime` → **PR #4** → squash merge **`23d8820`** (2026-10-22 00:30 KST).
  `main` 직접 push 는 하지 않았다(문서 기록용 커밋도 별도 PR).

### 세션 진행 (2026-10-21 23:20) — T-18 에이전트 런타임 설계 + 스파이크 2개

#### 사용자 발사 (요약)
- "내 말은 QuickTalk에 입력해서 **응답을 받는** 거잖아" — 자연어 한마디로 **앱이 직접 행동**해야 한다
- "brew, adb, pip, uv, ollama는 **내가 예를 든 것** — 모델이 정하는 거" → **앱은 명령어 사전을 갖지 않는다**
- "권한을 **읽기/쓰기/실행**으로 나눠서 설정에서 선택하게 해줘" + "OpenCode처럼 **자동 수락**"

#### 확정 (사용자)
| 항목 | 확정 |
|---|---|
| 배포 | **GitHub 배포**(스토어 없음) → 샌드박스 OFF 유지 → 셸 자유 |
| 자동 실행 범위 | **읽기(기본 자동) / 쓰기 / 실행** — 설정에서 선택 + 규칙 + 대화별 오버라이드 + 전역 자동 수락 |
| 범위 | **v0.18 ~ v0.22 전체** |
| 프로바이더 | **Apple FM · Local Ollama · 원격 OpenAI 호환 3종 완전 통일** |

#### 설계 (문서: `docs/plans/PLAN_v0.18_agent-runtime_macos.md`)
- **도구 카탈로그가 아니라 "실행 원시 + 에이전트 루프"** — `shell`·`read_file`·`list_dir` + 기존 `web_search`.
  모델이 명령을 정하고 앱은 실행만 한다.
- **권한은 "분류"가 아니라 "협상"** — 읽기 전용 샌드박스로 먼저 실행해 **무슨 권한이 필요한지 실측**한다.
  쓰기가 막히면 에러 메시지에 경로가 같이 나온다 → "이 경로만 쓰기 허용"으로 재실행.
- **위험도는 구조적 신호만** (상승권·시스템영역·파이프→인터프리터·재귀삭제 대상) — 명령/패키지 이름 목록 없음.
- **되돌리기가 권한을 낮춘다** — `rm`은 금지하지 않고 **휴지통 이동**으로 바꿔 실행 → [되돌리기] 버튼.

#### 스파이크 2개 — **둘 다 PASS** (산출물 `docs/qa/t18-spike/`)
1. **Apple FM tool calling** — FoundationModels `Tool` 프로토콜로 도구 1개 호출 → **4.0초, 실제 호출 성공**.
   `call(arguments:)` 는 `respond(to:)` **안에서 자동 실행**된다 → **정책 게이트는 `Tool.call` 안에서** 하면 된다.
   ⚠️ `@Tool` 매크로는 이 SDK에 없다 → 프로토콜 직접 구현. `Arguments` 는 `@Generable` 구조체여야 한다.
2. **샌드박스 권한 협상** — `df`/`ls`/`brew list`/`adb devices` → **읽기**, `echo > 파일` → **쓰기(경로)**, `curl` → **네트워크**, `sudo` → **상승 권한**.
   승인 경로만 열어 재실행 → 허용 밖 쓰기는 차단됨. 위험도 판정 7/7 정확.

#### 스파이크가 찾은 함정 4건 (수정·재검증 완료)
1. 쓰기 차단 메시지에서 **경로가 메시지보다 앞에** 온다(`/bin/sh: /path: Operation not permitted`)
2. **네트워크 차이는 "Operation not permitted"로 오지 않는다** — curl 6 / ping 68 / "Unknown host"
3. `sudo rm -rf /var/tmp/x` 를 치명적으로 오판 — `"rm -rf /"` **접두사** 매칭이 원인 → 토큰 단위 판정으로 교체
4. `curl … | bash` 를 보통으로 오판 — 토큰화 때 `|` 가 구분자로 제거됨
+ **`URL.resolvingSymlinksInPath()` 는 `/var` → `/private/var` 를 못 푼다** → 샌드박스 규칙은 `realpath(3)` 사용

#### 다음
- **v0.18 구현**: `AgentTool`·`AgentClient`·`AgentRunner`(Core) · `SandboxRunner` · `RiskClassifier` · `PolicyEngine` · 실행 카드
- 그 뒤 v0.19(쓰기·되돌리기) → v0.20(실행·확인 시트·감사 로그) → v0.21(스크린샷·Shortcuts) → v0.22(권한 고도화)
- **T-21 실측**(P1~P27)과 QA 배치 3·4는 그대로 대기

### 세션 진행 (2026-10-21 20:43) — T-21 포인터 pill

#### 확정 (사용자)
- pill은 대화 창과 **별개가 아니라 같은 대화의 다른 표현**이다.
- 설정 › 일반 **“단축키로 열 때 유지”** 규칙을 **그대로** 따르고, 그 결과가 **새 대화**일 때만 pill.
- **0(사용 안 함) = 항상 pill** (빈 대화 창을 띄우지 않는다).
- **마이크 삭제**, 보관함 아이콘은 **최근 대화 4개 작은 목록 · 1클릭 이어가기**.

#### 규칙 (`ShortcutEntryPresentation.decide`, Core)
| 현재 대화 | ⌘Space |
|---|---|
| 유지 시간 이내 + 턴 있음 | 대화 창 그대로 |
| 유지 시간 초과 | **pill** |
| 턴 없음 / 활동 없음 | **pill** |
| 설정 0 | **pill** |

설정 기본값·의미·픽커는 바꾸지 않았다. pill이 떠도 대화 상태는 그대로이고,
`store.startShortcutSession()`(만료 시 새 대화 + 기록 저장)은 **전송할 때만** 호출한다.

#### 구현
- `QuickTalkApp/PointerPill.swift` — `PointerPillPanel`(borderless, canBecomeKey) · `PointerPillController` · `PillRootView` · `PillTextField`.
- 크기 **380×56**, 모서리 28. 포인터 = 캐럿: 창 왼쪽을 `pointer.x − 55`(패딩13+오브30+간격12), 세로 중심, 작업 영역 안 클램프.
- **Enter** → 즉시 닫고 대화 창 + `startShortcutSession()` + `draft` 설정 + `send()`.
  **⌘Return** → 대화 창만(입력한 글은 초안으로; 파일 첨부용). **Esc** → 닫기(상태 불변).
  **⌘L** → 보관함 탭. 바깥 클릭 → 닫기. Esc·⌘Space로 닫으면 **직전 앱으로 포커스 복귀**.
- 보관함 목록은 **별도 창을 만들지 않고 같은 창을 아래로 늘인다**(포커스·클릭 문제 회피). 행 34pt·푸터 32pt·폭 300·최대 4행, 화면 아래로 넘치면 창을 위로 민다.
- 입력은 단일 행 `NSTextField`. 한글 조합 중 Enter는 **조합을 먼저 확정**한 뒤 전송(대화 입력창과 같은 규칙). 포커스는 창이 붙은 뒤 0.05초에 한 번 더 요청.
- 실패한 포커스를 잃었을 때 닫히는 동작은 Spotlight과 같다 — 여는 도중 0.25초의 일시적 resign은 무시.
- `QuickTalkApp.swift`의 `togglePanel(fromShortcut:)`에서 분기하고 `handlePill(_:)`가 대화 창으로 이어받는다.

#### 시각·렌더에서 찾은 결함
- 액센트는 DESIGN의 **`#7A5CFF`**(오브 그라디언트·활성 아이콘·핀 점).
- 시스템 머티리얼(`.regularMaterial`)은 창 가장자리에 **1pt 세로 이음새**가 보여 반투명 솔리드로 대체.
- **`Capsule().strokeBorder`가 좌우 끝에 28pt 길이의 1pt 세로선**을 남겼다(오프스크린 렌더 확대·픽셀 측정으로 확인).
  같은 반지름의 **`RoundedRectangle(cornerRadius: 28, style: .circular)`**로 바꾸면 사라진다(`.continuous`는 재현됨).
- 렌더: `docs/qa/t21-pill/`(빈·입력 중·목록, 한/영) · `docs/qa/t21-pill-light/`.

#### 검증
- `swift test` **332/332**(6 skip, 신규 `ShortcutEntryTests` 6: 이내·초과·0·턴 없음·활동 없음·경계).
- `xcodebuild` BUILD SUCCEEDED(경고 0). 오프스크린 렌더 확인.
- **한계**: 실사용 ⌘Space는 사용자 맥 사용 중이라 실행하지 않았다 — P1~P27 실측 대기.

#### 배포
- 2026-10-21 20:43 `~/Applications/QuickTalk.app` 교체(`ditto` → `.QuickTalk.old` 백업 → 교체), `codesign --verify --strict` OK.
- SHA-256 `ebc78fe9a55fb962467a89928d43d95a3fb91aad1bd895b14cac021f5ab2ca7c` — `build/Build/Products/Debug/QuickTalk.app`과 **일치 확인**.
- 실행 중 앱은 종료하지 않았다(**재실행 필요**).

#### git
- `feat/t21-pointer-pill` → **PR #2** → squash merge **`6d344cf`**(2026-10-21 20:47 KST). `main` 직접 push는 하지 않는다.
- 렌더 산출물은 `docs/qa/t21-pill/`·`docs/qa/t21-pill-light/`·`docs/qa/t21-pill-mockup/`을 함께 커밋하고, 디버그 렌더(`*-debug/`)는 `.gitignore`로 제외.

### 세션 진행 (2026-10-21 14:15) — Ollama 시간 초과 조사·수정

#### 사용자 신고
`ollama ps`는 정상인데(Local-Qwen2.5-32B · 21GB · 100% GPU · 8192) QuickTalk 답변이 없고
`⚠️ 주 모델(Local Ollama)이 응답하지 않아 예비 모델(Local Apple FM)로 답했습니다 — 시간 초과 (NSURLError -1001)`.

#### 근거 — Ollama 서버 로그(`~/.ollama/logs/server.log`)
| | 실패 1 | 실패 2 |
|---|---|---|
| 앱이 보낸 프롬프트 | **6,765토큰** | **3,965토큰** |
| 60초 동안 처리 | 4,647토큰 | 2,601토큰 |
| 결과 | **HTTP 500 · 정확히 1m0s** | 동일 |

- 서버 메시지: `aborting chat request due to client closing the connection`
  → **Ollama가 죽은 게 아니라 앱이 60초(URLSession 기본)에 끊었다.**
- 실측 속도(32B Q4 · M1 Max 32GB): 프롬프트 처리 **139→72 tok/s**(문맥이 길수록 느려짐), 생성 **3.8~6.4 tok/s**.
- 그래서 3~7k토큰 프롬프트는 첫 토큰까지 40~110초 + 답변 생성 30~70초 → **60초로는 불가능**.
- 사용자가 본 "Ollama 앱은 빠르다"의 근거도 같은 로그에 있다: 47토큰 요청은 13초에 정상 완료. **읽을 양이 140배 차이**.
- 메모리: 모델 21GB + 와이어드 24.3GB · **스왑 4.2GB** · 여유 10% → 이 환경에서 32B는 구조적으로 느리다.
- 요청 경합: 실측 중 앱과 하네스가 겹치면 한 요청이 **93초 대기**했다(Ollama는 모델당 병렬 1).

#### 수정 (A+B) — **적용 범위는 Ollama 전용**
1. **A — 타임아웃 300초**(`OllamaClient.requestTimeout`, Core): 스트리밍의 첫 데이터까지 유휴 한도를 300초로.
   원격 OpenAI 호환은 60초 유지, Apple FM은 네트워크 요청이 아니라 해당 없음. (`LLMProvider.swift` — Ollama 요청 생성부 한 곳)
2. **B — 문맥 절약(로컬 Ollama 전용)**:
   - `WebSearchPromptLimits`(Core 신설): **Ollama만 4건·800자**, 검색 컨텍스트 상한 **1,200토큰**.
     **Apple FM·원격은 설정값 그대로**이고 상한도 기존 공식(입력 예산 1/3). 설정값을 **키우지 않는다**.
   - `ConversationMemory.promptBudget`(Core 신설): **Ollama만** 기본 문맥 **3,072토큰**(모델 8,192와 별개로 "보내는 양"을 줄임).
     Apple FM·원격은 `inputBudget` 그대로. 프로바이더에 `컨텍스트 토큰`을 직접 넣으면 Ollama도 그 값을 존중한다.
     `fitHistory`·자동 정리 70% 트리거가 같은 예산을 쓴다.
   - UIStore 3개 검색 주입 경로 + 컨텍스트 상한 + `sources` 카드 수가 모두 같은 한도를 쓰고,
     하네스(`--search-answer-test`)도 앱과 같은 한도로 측정하도록 맞췄다(하네스가 더 큰 프롬프트를 보내 측정이 왜곡되던 문제).
   - 설정 캡션: 웹 검색은 **Ollama 활성일 때만** `로컬 모델은 첫 응답이 느려 검색 결과를 N건·M자로 줄여 보냅니다.`,
     기억 카드도 **Ollama일 때만** `Local Ollama는 … 기본 3,072토큰 …`. 번역 2키 추가.

#### 검증
- `swift test` **319/319**(6 skip, 신규 9: 문맥 절약·명시값 우선·원격/Apple FM 불변·fitHistory·트리거·검색 한도·상한·타임아웃).
- 헤드리스 E2E(`--search-answer-test="오늘 서울 날씨" --provider=ollama`) **2회**:
  | | 수정 전 | 수정 후 |
  |---|---|---|
  | 프롬프트 | 6,765토큰 | **1,516토큰**(검색 4건·800자·컨텍스트 1,201) |
  | 서버 프롬프트 처리 | 110.3초 | **28.5초** |
  | 결과 | 60초에 끊김(-1001) | **OK**(답변 122자·인용 2) |
  - 참고: 하네스 전체 시간은 139.9초였고, 그중 93초는 **다른 요청과의 경합 대기**였다(서버 내부 44.6초).
- 배포: 2026-10-21 14:15 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `c5023607d8e343ed628c774b92dc070f4a58f51e43885b57847ea10c4bcf6f90`.
- **후속(14:25) — 적용 범위를 Ollama 전용으로 축소**: 사용자 확인(`Ollama 동작 O`, "Ollama에만 적용해놔")에 따라
  Apple FM에 걸려 있던 축소(3건·600자·상한 900)를 **원복** — Apple FM은 설정값 그대로·상한 = 입력 예산 1/3.
  타임아웃은 원래부터 Ollama 클라이언트에만 있었고, `promptBudget`도 Ollama 분기만 변경이었다.
  재빌드·재배포: `swift test` **319/319**, SHA-256 `53f1ddc01cfd7b728a0e337c47d1d09cef9b188a361de48f5c5f0b417f92efb8`, `codesign --verify --strict` OK.
  **N15 사용자 확인 완료**(14:26) — 로컬 32B 속도 한계는 수용, 운용은 **원격 주 + Apple FM 예비**.

#### 남은 속도 한계 (코드로 해결 불가)
- 32B Q4는 이 맥(32GB·스왑 4.2GB)에서 생성 4~6 tok/s다. 답변이 300토큰이면 **50~75초**는 구조적으로 걸린다.
- **권장**: 로컬은 14B 이하 모델(또는 Q4 이하 양자화)을 쓴다. 7~14B면 2~4배 빨라진다.
  동시에 Ollama 앱과 QuickTalk로 같은 모델을 두드리면 요청이 직렬화되어 대기가 생긴다.

### 세션 진행 (2026-10-21 15:20) — 실사용 크래시(SIGABRT) 수정 + 헤더 정리·상대 시간·맨 아래로

#### 사용자 신고
- 배치 2 **A·B 전체 OK**, **K 도중 앱이 죽음** — "이미지 첨부 있는 질문 수정 후 대화 요청 시 죽음".
- 추가 요청 4건: ① 📌 옆 뇌 아이콘이 뭔지 ② 헤더 아이콘 크기가 제각각 + 툴팁 ③ 응답에 상대 시간("10분 전") + 보관함 마지막 대화 시간 ④ 맨 아래로 플로팅 버튼.

#### 크래시 — 근거는 `~/Library/Logs/DiagnosticReports/QuickTalk-2026-10-21-145819.ips`
- faulting thread = `com.apple.root.user-initiated-qos.cooperative` — **메인 스레드가 아니다**.
  메인 스레드는 `UpdateGroup` 잠금 대기 중이었고, 협력 스레드가 AppKit 레이아웃을 수행하다
  `NSWindow drag regions should only be invalidated on the Main Thread!` NSException → SIGABRT.
- 체인: `SwiftUI PlatformViewChild.updateValue` → `ChatInputField.updateNSView` → `Coordinator.layoutPass` → `measure`
  → `NSTextContainer.setSize` → … → `_postWindowNeedsToResetDragMargins`.
- **기저 원인**: `UIStore.searchWeb`이 `await` 뒤 협력 스레드에서 `settings`(검색 사용량 카운터)를 수정했다.
  `settings`는 `@Published`라 SwiftUI가 **그 스레드에서** 뷰를 갱신 → AppKit 예외. 첨부 질문 수정→전송은
  검색 판정이 붙는 경로라 이 크래시가 드러난 것이다(첨부 자체 문제가 아니다).
- **수정**:
  1. `searchWeb`·`answerWeb`에 **`@MainActor`** — 카운터 갱신이 메인에서만 일어난다(네트워크 await는 그대로 비동기).
  2. `ChatInputField.Coordinator.measure`에 **`Thread.isMainThread` 가드** — 어떤 이유로든 메인 밖 갱신이 오면
     크래시 대신 그 회차 측정만 건너뛴다(다음 메인 패스에서 높이가 맞춰진다).
  3. 다른 async 경로 점검: `toolCallingSelfTest`·`decidesToSearch`는 Published를 쓰지 않고, `loadAttachments`는 `nonisolated`지만 UI 상태를 만지지 않는다.

#### UI 4건 (사용자 요청)
1. **헤더 아이콘 통일** — `ContentView.headerIcon(_:active:tint:help:action:)` 헬퍼 하나로 핀·공통 메모리·보관·새 대화·퀵셸프·탭 3종을
   **22×22·같은 간격·같은 글리프 크기(12pt)**로 맞췄다(이전엔 퀵셸프·탭만 프레임이 없어 크기가 달랐다). 활성=보라, 비활성=기본색.
   **모든 아이콘에 호버 툴팁** — 🧠는 "공통 메모리 켜짐 — 이 대화의 내용을 다른 대화에서도 기억합니다. 눌러서 이 대화에서만 끄기"처럼
   **무엇인지**까지 적었다(사용자: "📌 오른쪽에 뇌?? 저 아이콘은 뭐여??").
2. **토큰 진행률 줄바꿈 제거** — 좁은 창(기본 460)에서 `92 / 21,324 · 0%`가 두 줄로 접히던 것 → 축약 표기 `92 / 21k · 0%`.
   정확한 값은 툴팁에 그대로. 제목에는 `layoutPriority(1)`.
3. **상대 시간** — Core `Turn.createdAt: Date?`(구버전 기록은 nil, 합성 Codable이 `decodeIfPresent`) + Core `RelativeTime`
   (`방금 / N분 전 / N시간 전 / N일 전 / N주 전 / 날짜`). 답변 푸터 = `9분 전 · 1.2초`, 툴팁 = `응답 도착: 10월 21일 15:02 · 걸린 시간 1.2초`.
   **보관함 행**도 `3턴 · 5분 전 · 자동 저장`(툴팁에 정확한 시각). 표기가 낡지 않게 `Timer` 60초로 다시 계산한다.
4. **맨 아래로 버튼** — macOS 14라 `onScrollGeometryChange`(15+)를 못 쓰므로 `GeometryReader`+`PreferenceKey`로
   내용 끝 y와 뷰포트 높이를 재고(24pt 여유), 바닥이 아니면 **우하단 원형 ↓**를 띄운다. 누르면 기존 `scrollToBottom`으로 이동.
   처음 구현에서 뷰포트 높이가 늦게 도착해 **바닥에서도 버튼이 떠 있는** 버그를 오프스크린 렌더로 발견 → 두 값이 올 때마다 함께 재판정하도록 고쳤다.

#### 검증
- `swift test` **326/326**(6 skip, 신규 6: 상대 시간 경계·미래 시각·구버전 `Turn` 디코딩·왕복·제출 시각 기록).
- BUILD SUCCEEDED, 오프스크린 렌더 `docs/qa/t74-ko/chat-ko.png` — 헤더 정렬·토큰 축약·`9분 전 · 1.2초` 확인, 바닥에서 ↓ 버튼이 **사라진** 것 확인.
- 번역 9키 추가(`%d분 전`·`%d시간 전`·`%d일 전`·`%d주 전`·`방금`·`M월 d일`·`yyyy년 M월 d일`·`맨 아래(최신)로 이동`·`응답 도착: %@ · 걸린 시간 %@` 등).
- 배포 2026-10-21 15:14, SHA-256 `4b82e52d02bf78c92b884c27530affb6d95aefe7b8b5eee8ac48d1ad4c25c4c4`, `codesign --verify --strict` OK.
- **재실행 필요** — 실행 중 앱은 14:34 빌드다.

#### 다음 (사용자)
- **K1~K13 재개** — 특히 **K3**(이미지 첨부 질문 수정 → 전송)로 크래시가 재현되지 않는지.
- **N16**(응답 중지) · **N17~N19**(상대 시간·헤더 아이콘/툴팁·맨 아래로 버튼).

### 세션 진행 (2026-10-21 14:34) — 응답 중지(⏹) + Ollama 전용 범위 검증

#### 배경
타임아웃을 300초로 늘린 뒤, **멈춘 로컬 요청에서 빠져나갈 수단이 없었다**
(응답 대기 중 입력독·전송이 모두 비활성, 취소 경로 자체가 없었음). 32B는 정상 동작도 1~2분 걸린다.

#### 수정
- `UIStore.replyTask`(진행 중 Task 보관) + `cancelReply()` — 응답 중 전송 버튼이 **⏹ 중지**(빨강)로 바뀐다.
- 취소는 **오류가 아니다**: 부분 출력은 남기고 `⏹ 중지됨`만 덧붙인다(출력이 없으면 `응답을 중지했습니다.`).
- `ProviderFallback.allowed` — `CancellationError`·`URLError.cancelled`는 **폴백 금지**
  (사용자가 멈춘 응답이 예비 모델에서 되살아나는 것 방지). 대조로 시간 초과는 그대로 폴백한다.
- `Task.isCancelled` 확인 지점 3곳: 첨부 준비 후 / 검색·판정 후 / 모델 호출 직전.

#### 범위 검증 — "Ollama 전용"이 실제로 지켜지는지
| 경로 | 결과 |
|---|---|
| Apple FM (`--search-answer-test --provider=applefm`) | `results=8 chars=2000 cap=938` · 답변 6.1초 — **설정값 그대로·상한 = 입력 예산 1/3**(원복 확인) |
| 원격 (활성 프로바이더) | `results=8 chars=2000 cap=10154` · 13.1초 — **변화 없음** |
| Ollama 판정 (`--search-decide-test --provider=ollama`) | `YES 5,815ms` — 20초 판정 상한 유지(300초 타임아웃 영향 없음) |

- `swift test` **320/320**(6 skip, 신규 1: `testCancellationNeverFallsBack`).
- 배포 2026-10-21 14:34, SHA-256 `e70d4cf011d62cde2215c72015471ff14d34170b339550a9217c41a2041419c1`, `codesign --verify --strict` OK.
- QA **N16** 추가(중지 버튼 — 사용자 실측).

### 세션 진행 (2026-10-21 13:51) — QA 배치 1 완료

- **결과**: 배치 1(웹 검색·폴백 17건) 사용자 실측 — **실패 0건**. I1~I5·I5-1·L1·N12·N13·N14 직접 확인, I6·I7·L4는 이전 세션 근거로 판단 확인, L2·L3·N11은 간접 확인. I8(영어 선택)만 미확인.
- **의미**: 13:05 빌드(`86a3542…`)에서 **웹 검색·판정 타임아웃·판정 재시도·[웹에서 찾기]·예비 AI 폴백·인용 클릭·하루 한도**가 실사용에서 정상 동작함을 확인했다. 오늘 수정한 4건(10:39·11:05·12:40·13:05) 전부 실측 통과.
- **다음**: **배치 2 — 대화·입력·보관함 34건**(A1~A14 · B1~B5·B2a · K1~K13·K12a). 결과는 `배치2: A1 OK / A3 새 대화 안 됨 …` 형식.
- **문서**: `docs/QA-CHECKLIST` 헤더·배치표·집계(102→86)·배치1 근거 표, HANDOFF §0, TODO §지금.

### 세션 종료 (2026-10-21 13:20) — 다음 세션 시작점

- **상태**: 13:05 빌드 배포 완료(`86a35425…`), 테스트 **310/310**, 문서 sync 완료. **미해결 결함 없음.**
- **다음**: QA **배치 1**(웹 검색·폴백 17건)부터. 체크리스트 상단 `## 실측 순서 (배치)` 표 → ID로 본문 검색.
- **실측 결과 전달 형식**: `배치1: N14 OK / N13 재시도 로그 없음 / I3 검색 안 됨` 처럼 번호+결과. 실패는 화면 캡처 또는 해당 대화만.
- **주의**: 실행 중 앱(PID 28143, 12:54 시작)은 **12:40 빌드** → 재실행해야 13:05 문구 정리본이 적용된다.
- **이번 세션에서 바꾼 것**: 판정 타임아웃 프로바이더별(10:39) → 판정 재시도·감지 확장(11:05) → **예비 AI 폴백**(12:40) → 폴백 안내 문구 정리(13:05).
- **남은 개선 후보(미승인)**: 일반 질문의 429/5xx **재시도**(프로바이더 전환 없이 `Retry-After` 존중). 현재는 예비 AI가 없으면 429에서 바로 오류.

## 1. 새 세션 시작 순서

1. `AGENTS.local.md` — 플랫폼·번들 ID·design_profile 확인
2. 이 문서 (`docs/HANDOFF.md`)
3. `docs/TODO.md`의 **§지금** — 현재 작업·다음 결정
4. 최근 세션 로그: `.agent/session-2026-10-21-macos-38.md`, `-39`, `-40`, `-41`
5. 작업 성격에 따라:
   - UI/구조: `docs/DESIGN.md` (§0 현재 요약 → §4~§11 구현 기준, §1~§3은 초기 기록)
   - 대화 기억: `docs/plans/PLAN_v0.15_memory_macos.md` (T-71 구현 완료 + 2026-10-21 강제 축약·요약 편집)
   - 공통 메모리: `docs/plans/PLAN_v0.16_common_memory_macos.md` (P1~P3 구현 완료)
   - 웹 검색: `docs/plans/PLAN_v0.14_websearch_macos.md` (P1~P3 + 툴 콜링·`/answer` 구현 완료)
   - 실측: `docs/QA-CHECKLIST-2026-10-20.md`
6. 기준선 확인: `swift test` → **319/319 (6 skip)**. 실패하면 먼저 원인을 확인한다.
7. **사용자가 Mac을 쓰는 동안 앱을 실행하거나 화면을 제어하지 않는다.** UI 확인은 오프스크린 렌더(`--render=`)만.

## 2. 현재 작업 — 2026-10-21 잔여 배치 · T-73 · T-71 · T-70

### 2.0 2026-10-21 05:30 공통 메모리 P1~P3 · 웹 툴 콜링 · Exa `/answer` (완료, 실측 대기)

#### 공통 메모리 — 모든 대화에 적용되는 사용자 작성 사실
- **P1**: 설정 › AI › **공통 메모리** 카드에서 항목 여러 개 추가/편집/삭제/켜기/끄기. 켜 둔 항목을
  매 요청 프롬프트 **앞**에 넣는다. 토큰 예산 기본 **800**(400/800/1600/3200), 대화 헤더 🧠로
  **그 대화에서만** 끌 수 있다(`Conversation.commonMemoryDisabled`).
- **P2**: 태그·검색·순서 변경·`항상 포함`·JSON 가져오기/내보내기(같은 ID는 건너뜀).
  방식 = **항상 모두**(기본) / **관련 항목만**.
- **P3**: 외부 API 없이 **로컬 해시 임베딩**(FNV-1a, 2,048차원, 한·영 2-gram/단어) cosine +
  제목/태그 보정(≥0.22)으로 질문과 관련된 항목만 선택. `항상 포함`은 관련 모드에서도 들어간다.
- **저장**: `~/Library/Application Support/QuickTalk/memory.json` (대화 기록과 분리, 원자적 쓰기·`0600`).
  깨진 JSON은 `memory.json.corrupt`로 보존한 뒤 빈 목록으로 시작한다(원본 덮어쓰기 방지).
- **프롬프트 순서**: `공통 메모리 → 대화 요약 → 최근 원문 → 검색 결과 → 질문`.
  `ConversationMemory.fitHistory(extraTokens:)`로 기록 예산에서 메모리(+검색 400) 몫을 먼저 예약하고,
  실제 검색 컨텍스트가 400토큰을 넘으면 검색 후 기록을 **다시 맞춘다**.
- **한계**: 모델 학습이 아니라 프롬프트 문맥이다. 원격 프로바이더를 쓰면 켜 둔 항목이 전송된다.
  동의어 검색에 약하고(태그 병행 권장), 민감정보 자동 마스킹은 없다. 대화 기록 전체의 장기 검색은 별개.

#### 웹 툴 콜링 — 모델이 `web_search`를 직접 호출
- `WebSearchTool`(OpenAI `tools` 스키마·`tool_calls`/arguments 파싱·최대 3검색),
  `OpenAIClient.completion(messages:tools:)`. `tool` 메시지 헬퍼와 `stream(messages:)`는 **후속 다중 왕복용**이며
  현재 1왕복 경로는 검색 결과를 프롬프트에 주입하고 `streamReply`로 답한다.
- 모델이 검색을 요청하면 앱이 Exa로 검색해 결과를 프롬프트에 넣고 **최종 답변을 스트리밍**한다.
  검색 없이 답하면 그대로 표시(두 번째 호출 생략).
- **OpenAI 호환에서만** 시도. `tools` 미지원(400)·키 없음은 `E-MAC-TOOL-0001` 경고 후
  **기존 검색 결과 주입으로 자동 폴백**한다. 현재 구현은 **1왕복**이며 `tool` 메시지 다중 왕복은 후속.
- 실측: `--tool-test="오늘 서울 날씨 알려줘"` → 검색 **8건**, **7.4초**.

#### Exa `/answer` — 답변+인용을 한 번에
- `ExaAnswer.request/parse/context` + `ExaAnswerClient`. `answer` + `citations`를 받아
  **참고 초안**으로 프롬프트에 넣고 선택한 모델이 자기 말투로 다시 쓴다(인용 유지).
- 실패하면 같은 질문으로 일반 `/search` 1회 폴백. 일반 검색과 하루 한도를 공유한다.
- 실측: `--answer-test="오늘 서울 날씨"` → 답변 **218자**, 인용 **8건**, **3.4초**.

#### 설정·파일
- 설정 › AI › 웹 검색에 **답변 방식** 픽커(검색 결과 주입 / 툴 콜링 / Exa `/answer`),
  **[검색 테스트]**·**[/answer 테스트]** 버튼. 기본은 안정적인 **검색 결과 주입**.
- 주요 파일: `Sources/QuickTalkCore/GlobalMemory.swift`, `WebTools.swift`,
  `QuickTalkApp/SettingsView+GlobalMemory.swift`, `UIStore.swift`, `ContentView.swift`.
- 계획: `docs/plans/PLAN_v0.16_common_memory_macos.md`, `PLAN_v0.14` P3 갱신.

#### 검증·배포
- `swift test` **302/302**(6 skip, 기능 31 + 감사 10), BUILD SUCCEEDED(경고 0).
- 오프스크린 렌더 `settings-ai`(메모리 3항목·관련 모드), `chat`(헤더 🧠) 확인.
- 배포: 2026-10-21 05:30 `~/Applications/QuickTalk.app`, Apple Development 서명,
  `codesign --verify --strict` OK, SHA-256 `8773dda167786a121cde4652565af08c41b11dc42821593ff2c50dd465e6d80d`.

#### 사용자 확인 (이 순서)
1. 앱 **완전 종료 후 재실행**.
2. 설정 › AI › 공통 메모리에서 항목을 1~3개 추가하고, `내 컴퓨터 사양을 고려해 추천해줘` 질문 →
   모델이 사양을 **다시 묻지 않는지**.
3. 대화 헤더 **🧠**를 끄고 같은 질문 → 그 대화에서만 빠지는지. 새 대화에서는 다시 켜지는지.
4. 방식 = **관련 항목만**으로 바꾸고 무관한 질문 → 관련 항목이 빠지는지.
5. 설정 › AI › 웹 검색 › 답변 방식 = **툴 콜링** → `오늘 서울 날씨 알려줘` → 검색 후 답변·출처.
   프록시가 tools를 지원하지 않으면 경고 후 **그래도 답변**이 나오는지.
6. 답변 방식 = **Exa /answer** → 같은 질문 → 인용이 유지되는지. **[검색 테스트]**·**[/answer 테스트]** 확인.
7. 자세한 항목은 `docs/QA-CHECKLIST-2026-10-20.md` **N1~N11**.


### 2.0.1 2026-10-21 07:02 감사·리팩터링 (완료, 실측 대기)

#### 발견·수정한 기능 버그
- **툴 콜링 + 비 OpenAI 프로바이더**: `webSearchMode = .toolCalling`에서 Apple FM/Ollama를 쓰면
  분류 호출 조건이 false가 되어 **검색이 아예 실행되지 않던 문제**. 비 OpenAI에서는 자동으로
  주입 판정(`decidesToSearch`)으로 폴백한다.
- **툴 실패 분류**: 400/404/422(tools 미지원)만 주입 폴백하고, 401·429·5xx·네트워크 오류는
  두 번째 모델 호출 없이 **검색 없이 답한다**(`E-MAC-TOOL-0004`). 키·주소 오류도 불필요한 폴백을 하지 않는다.
- **검색 컨텍스트 예산**: 설정상 최대 8건×2,000자(≈5k토큰)인데 기록 예산은 400토큰만 예약했다.
  Apple FM 같은 작은 컨텍스트에서 넘칠 수 있어 ① 컨텍스트를 입력 예산의 1/3로 자르고
  ② 실제 컨텍스트 토큰으로 기록을 다시 맞춘다. 검색 중 대화방을 바꾸면 답변을 버린다.
- **일일 한도 + 캐시**: 한도 도달 후에도 이미 받은 검색 결과는 캐시에서 쓸 수 있게 캐시를 한도보다 먼저 확인.
  `/answer`에도 10분 캐시(TTL 600초, 20개)를 추가해 같은 질문의 지연·쿼터를 아낀다.
- **설정 enum 내성**: 알 수 없는 enum 값 하나 때문에 **설정 전체가 기본값으로 초기화되던 문제**.
  해당 필드만 기본값으로 두고 나머지는 보존한다.
- **가져오기 저장 실패**: 가져오기 직후 `memoryEntries` 저장이 실패해도 성공 안내가 덮어쓰던 문제.
- **메모리 파일 보호**: `memory.json`과 `.corrupt` 백업을 `0600`으로 저장. 깨진 파일은 백업 후 빈 목록.

#### 성능·구조
- 공통 메모리 임베딩 캐시(128개)·자르기 이진 탐색·실제 머리말 토큰 계산.
- `fitHistory`의 O(n²) 재계산을 턴별 비용 1회 계산 + 선형 절단으로 변경.
- 검색/`/answer` 캐시, 툴 검색어 중복 제거, 배열형 `content` 응답 파싱, `limit` 0 정규화.
- 사용하지 않는 `commonMemoryPreview`·`MemoryEditorSheet` 환경 객체 제거.

#### 검증
- `swift test` **302/302**(6 skip, 감사 신규 10). `xcodebuild` BUILD SUCCEEDED(경고 0).
- 오프스크린 렌더: `docs/qa/audit-2026-10-21-memory/`, `docs/qa/audit-2026-10-21-chat/`.
- 로컬 파일 `memory.json`은 대화 기록과 분리되며, 원격 프로바이더 사용 시 켜 둔 항목이 전송된다.
- 배포: 2026-10-21 07:02 `~/Applications/QuickTalk.app`, Apple Development 서명,
  `codesign --verify --strict` OK, SHA-256 `2ae82898aa246e0c871c491b44c62fccce6894970ae8e376ac3cdfd2492154e4`.

### 2.0.2 2026-10-21 10:40 헤드리스 실측 + 검색 필요 판정 타임아웃 수정 (완료, 실측 대기)

#### 헤드리스 실측 결과 (활성 = 원격 `192.168.86.30:8791` / `deepseek-v4.1-flash-free`)

| 하네스 | 결과 | 판정 |
|---|---|---|
| `--tool-test` | 검색 **8건** · 16.3초 | ✅ 프록시가 `tools` 지원, 모델이 `web_search` 호출 |
| `--provider=applefm --tool-test` | `FALLBACK unsupported` · **10ms** | ✅ 비 OpenAI는 네트워크 없이 즉시 폴백(감사 수정 확인) |
| `--answer-test` | 답변 **183자** · 인용 **8건** · 2.6초 | ✅ |
| `--search-test` | **8건** · 6.4초 · 도메인 7종 | ✅ (지연은 Exa 변동) |
| `--search-answer-test` | 8건 · 922자 · 인용 4 · 델타 594 · 첫 델타 6.5초 · 총 9.6초 | ✅ 검색→주입→스트리밍 |
| `--compact-test=20` | 요약 296자 · **2,100→868토큰** · recent 5 · 10.3초 | ✅ |
| `--provider=applefm --compact-auto-test=20` | `expected=YES → summary=YES` · **2,160→537** · 7.1초 | ✅ 자동 트리거 |
| 하루 사용량 | `webSearchUsageCount` 4 → **9** (성공 시에만, `/answer` 공유) | ✅ |
| `memory.json` 권한 | `-rw-------` (0600) | ✅ |
| 기준선 | `swift test` **302/302** → 수정 후 **303/303**(6 skip) | ✅ |

#### 발견·수정한 결함 — 검색 필요 판정이 **고정 4초 타임아웃**으로 조용히 실패

- 실측(수정 전): 원격 `오늘 서울 날씨` **3/3 = 4,015ms 초과 → NO 오답**, Ollama 4,249ms 초과 → NO,
  Apple FM은 1.7초/0.5초로 정상. 즉 **웹 검색을 켜 둬도 원격·Ollama에서는 그 질문이 검색되지 않았다**(로그만 남고 화면 표시 없음).
- 수정: `WebSearchQuery.classifierTimeout(for:)`(Core, 테스트 대상) — **Apple FM 5초 / 원격 OpenAI 호환 8초 / Ollama 20초**.
  - 원격 실측: 4초 초과(4.0·5.6초)까지 나와 8초로, 워밍 시 1.2~1.7초.
  - Apple FM 실측: 0.5~3.0초 → 3초는 아슬아슬해 5초.
  - Ollama는 생성이 아니라 **모델 로드(콜드 스타트) 13초**가 원인(`eval_count=2`, 워밍 후 0.4~1.0초).
    취소하면 그 로드가 중단되어 짧은 타임아웃은 기다린 시간을 버리고 **다음 답변도 다시 콜드**로 만든다 → 20초로 로드를 끝까지 기다린다.
- 실패 로그에 **원인 코드**(`E-MAC-SEARCH-0004` = 시간 초과 vs 프로바이더 오류)와 적용된 제한 시간을 남긴다.
- 판정 원칙은 그대로: 실패·애매는 **검색하지 않는다**. 🌐 강제는 판정을 건너뛴다.
- **미구현(검토 후 보류)**: 일시적 프로바이더 오류에서 1회 재시도 — 최악의 경우 대기를 두 배로 늘려 지연 우선 원칙과 충돌한다.

#### 검증·배포
- `swift test` **303/303**(6 skip, `testClassifierTimeoutIsProviderAware` 신규), BUILD SUCCEEDED(경고 0).
- 수정 후 재실측: 원격 `오늘 서울 날씨` **6/6 YES 1.2~1.7초**, `구구단` NO 유지, Apple FM YES 2.7/0.6초·NO 0.6초, Ollama(워밍) YES 0.4초.
- 배포: 2026-10-21 10:39 `~/Applications/QuickTalk.app`, Apple Development 서명, `codesign --verify --strict` OK,
  SHA-256 `51ccbb0fc9b5c10830a2b4b4fa6a5a8cc0130fbc00e9a472ada8db448d84ad1f`.

#### 사용자 확인
1. 앱 **완전 종료 후 재실행**.
2. 설정 › AI › 웹 검색이 켜진 상태에서 `오늘 서울 날씨` → 검색이 **실제로 실행**되는지(`웹에서 찾는 중…`).
3. `구구단 만들어줘` → 검색하지 않고 바로 답하는지.
4. 자세한 항목은 `docs/QA-CHECKLIST-2026-10-20.md` **N12**.

### 2.0.3 2026-10-21 11:05 판정 일시 오류 1회 재시도 + [웹에서 찾기] 감지 확장 (완료, 실측 대기)

#### 사건 — 실사용에서 검색이 조용히 빠짐
사용자 스크린샷(10:42~10:44): `오늘 서울 날씨를 보내 주세요` → 답변이
"제가 지금 사용할 수 있는 도구에는 실시간 날씨 정보를 조회하는 기능이 없습니다" (**검색 없이** 2.7초),
같은 질문 재전송 → `HTTP 429 (E-MAC-NET-0004)`.

| 근거 | 값 | 해석 |
|---|---|---|
| 실행 중 앱 SHA-256 | `51ccbb0f…` = 10:39 배포본 | 새 빌드였음(빌드 문제 아님) |
| `history.json` 1번째 답변 `sources` | **0** | 검색이 **실행되지 않음** |
| 같은 문장 지금 판정 | **YES · 1,963ms** | 문장·프롬프트 문제 아님 |
| 같은 시각 2번째 응답 | `HTTP 429` | 프로바이더가 **사용 제한 중** |
| Exa 오늘 사용량 | 10 → **11** | 검색이 **한 번은 실행**(2번째 턴에서 검색 후 429로 답변 실패) |

→ **판정 호출이 429(일시 오류)를 맞고 실패 → 코드가 조용히 "검색 안 함"으로 처리**했다.
판정 실패는 로그에만 남고 화면에는 아무 표시가 없어, 사용자는 "웹 검색이 켜져 있는데 왜 검색을 안 하지"만 보게 된다.

#### 수정
1. **판정 일시 오류 1회 재시도** — `WebSearchQuery.classifierRetryAllowed(after:)`(Core, 테스트 대상).
   - 429·5xx·네트워크·인증 오류는 **빨리 실패**하므로 400ms 쉬고 1회만 재시도한다(최악 +약 1.6초).
   - **시간 초과(`E-MAC-SEARCH-0004`)는 재시도하지 않는다** — 이미 제한 시간만큼 기다린 뒤라 두 배 대기는 지연 우선 원칙과 충돌.
   - 로그에 `시도 1/2`와 최종 실패 사유(코드·제한 시간·경과)를 남긴다. 화면 표시는 그대로 두지 않는다(일시 오류로 배너를 띄우면 소음).
2. **[웹에서 찾기] 감지 확장** — `looksLikeSearchRefusal`이 기존 "검색할 수 없습니다" 계열뿐 아니라
   **도구·기능 부재 + 실시간/웹 맥락**도 잡는다: "실시간 날씨 정보를 **조회하는 기능이 없**습니다"(실사용 문구),
   "실시간 데이터를 조회할 수 없습니다", "I don't have the ability to access real-time information".
   - 오탐 방지: "최신 버전에서는 이 기능이 없습니다"·"웹사이트 디자인을 추천해 드릴게요"는 **잡지 않는다**(테스트로 고정).
   - 효과: 판정이 두 번 실패해도 답변 아래 **[웹에서 찾기]**로 한 번에 복구할 수 있다.
- 판정 원칙은 그대로: **실패·애매 = 검색 안 함**, 🌐 강제는 판정 생략.

#### 검증·배포
- `swift test` **304/304**(6 skip, `testClassifierRetryPolicy` 신규 · `testSearchRefusalDetection` 확장), BUILD SUCCEEDED.
- 정상 경로 회귀: `--search-decide-test="오늘 서울 날씨를 보내 주세요"` → **YES 2,444ms, 시도 1**.
- QA 렌더: `docs/qa/web-retry-tool-ko`(실사용 문구) · `web-retry-classic-ko`(기존 문구) — 둘 다 **[웹에서 찾기]** 표시 확인.
  - 하네스 버그 동반 수정: `--demo-search-refusal=tool`처럼 값이 붙은 인자는 `.contains("--demo-search-refusal")`(정확 일치)로는 잡히지 않아 기본 데모가 그려졌다 → `hasPrefix` 비교로 변경.
- 배포: 2026-10-21 11:05 `~/Applications/QuickTalk.app`, Apple Development 서명, `codesign --verify --strict` OK,
  SHA-256 `70a15deed1bd04c496e4536082097c5169d40866f0f908c6a360cd8d7df2a98a`.
- **재시도 경로는 429를 결정적으로 재현할 수 없어** 단위 테스트(정책) + 정상 경로 실측으로만 검증했다.

#### 사용자 확인
1. 앱 **완전 종료 후 재실행**(10:39 빌드가 실행 중이면 새 코드가 아니다).
2. `오늘 서울 날씨를 보내 주세요` → `웹에서 찾는 중…`이 뜨고 출처 카드가 붙는지.
3. 검색 없이 "실시간 … 기능이 없습니다" 답변이 나오면 **[웹에서 찾기]** 버튼이 보이는지(누르면 검색 강제 재시도).
4. 상세: `docs/QA-CHECKLIST-2026-10-20.md` **N13**.

### 2.0.4 2026-10-21 12:40 예비 AI 폴백 — 실패 시 다른 모델로 1회 (완료, 실측 대기)

#### 배경
사용자 질문("AI 폴백 기능에 대해서 적용 된거 있나 확인하고 설명해봐")에 대한 감사 결과,
폴백은 **부분적**이었다 — 키 없는 원격 → Apple FM(시작 시), 툴 콜링 → 주입, `/answer` → `/search`,
스트리밍 → JSON, 첨부 재시도 사다리는 있었지만 **요청 실패 시 다른 프로바이더로 넘어가는 경로는 0건**이었다.
어제의 429 사례도 그래서 사용자가 직접 다시 보내야 했다.

#### 구현
- **설정**: `QuickTalkSettings.fallbackProviderID`("" = 사용 안 함, 구버전 JSON은 빈 값 → 동작 변화 없음),
  `fallbackProvider`(주 모델과 같거나 비활성이면 nil). 설정 › AI › 활성 프로바이더에 **예비 AI (실패 시 1회)** 픽커.
  주 모델을 예비로 바꾸거나 예비를 삭제하면 선택이 자동으로 비워진다.
- **판정**(Core `ProviderFallback.allowed`): 429·5xx·빈 응답·키/요청 거부·시간 초과·연결 실패는 **전환**,
  403(정책 거부)·첨부 거부(413/422)·설정 오류는 **전환하지 않는다**(다른 모델로 원인을 숨기지 않는다).
- **실행**(`UIStore.streamReplyWithFallback`): 주 모델 실패 → 예비가 준비됐으면(`ProviderFallback.isUsable`:
  키·모델·주소) **1회만** 시도. 예비 예산이 더 작으면(원격 → Apple FM) `ConversationMemory.fitHistory`로
  오래된 턴을 덜어낸다. **첫 델타가 올 때** `⚠️ 주 모델(X)이 응답하지 않아 예비 모델(Y)로 답했습니다 — <원인>`
  안내를 붙인다(예비도 실패하면 안내만 남지 않고 두 실패를 합친 오류를 보여 준다). 사슬·무한 재시도 없음.
- 오류 코드 `E-MAC-FALLBACK-0001`(전환 시도)·`E-MAC-FALLBACK-0002`(예비도 실패) — 로그에는 코드·지연만.

#### 검증
- `swift test` **309/309**(6 skip, 신규 5: 전환 허용/거부 분류·준비 상태·설정 왕복/구버전·같은 모델 방지) → 문구 정리 후 **310/310**.
- QA `--fallback-test` — 주 모델을 **연결 불가 주소**(127.0.0.1:9)로 즉시 실패시키고 예비(Apple FM)로 답하는지:
  `[WARN] E-MAC-FALLBACK-0001 주 모델 실패(E-MAC-NET-0001) → 예비 모델 1회 시도` →
  `[FALLBACK-TEST] OK chars=88 deltas=2 ms=1979 note=1` ✅ (설정 저장 없음·온디바이스).
- 렌더 `docs/qa/fallback-settings-ko/settings-ai-ko.png` — 예비 AI 픽커·캡션 확인.
- **한계**: 429는 결정적으로 재현할 수 없어 분류·준비 상태는 단위 테스트, 실행 경로는 연결 실패로 검증했다.

#### 후속 (13:05) — 실사용 확인 + 안내 문구 정리
실사용 스크린샷(429)에서 폴백이 실제로 동작했다: `⚠️ 주 모델(Remote OpenAI 호환)이 응답하지 않아 예비 모델(Local Apple FM)로 답했습니다 — … [server_error] (HTTP 429)`.
다만 ① 문장이 길고(`userMessage` 전문 + `[server_error]` 제공자 코드) ② `—`가 겹쳐 읽기 어려웠다.
- `ProviderFallback.reason(for:)` 신설 — 한 줄짜리 원인(`사용 제한 (HTTP 429 · E-MAC-NET-0004)`).
  **업스트림이 준 코드 문자열(`[server_error]`)은 화면에 쓰지 않는다**(서버 본문·코드 노출 금지 원칙, 앱 표준 코드만 남김).
- 안내 문구는 `UIStore.fallbackNote(...)` 한 곳에서 만들고, 데모 렌더(`--demo-fallback`)도 같은 함수를 쓴다.
- 검증: `swift test` **310/310**(신규 `testFallbackReasonIsShortAndHidesProviderCode`), `--fallback-test` OK, 렌더 `docs/qa/fallback-note-ko/chat-ko.png`(라이트).
  - 참고: 오프스크린 채팅 렌더는 **다크에서 글자가 검게** 나온다(호스팅 뷰가 다크 외관을 못 받음 — 하네스 한계, 앱 화면은 정상). 채팅 렌더는 라이트로 남긴다.
- 배포: 2026-10-21 13:05, SHA-256 `86a35425176e858287e34efc6dab897ca1720817ea18a6379b5e268fc6327bbf`.

#### 사용자 확인 (QA N14)
1. 앱 **완전 종료 후 재실행**.
2. 설정 › AI › **예비 AI**에서 다른 모델(예: Local Apple FM)을 고른다.
3. 주 모델을 일부러 실패시키거나(주소 오타·Ollama 중지) 사용 제한이 걸린 뒤 질문 →
   답변 위에 `⚠️ 주 모델 … 예비 모델 …로 답했습니다` 안내가 보이면 정상.
4. 예비 AI가 **사용 안 함**이면 동작은 이전과 완전히 같다(오류만 표시).

### 2.1 2026-10-21 04:30 사용자 확인 후속 (완료, 실측 대기)

#### 질문 메뉴 — 말풍선 오른쪽·세로 중앙
- 사용자 말풍선 오른쪽에 **26pt 자리**를 비우고 `⋯`를 `overlay(alignment: .trailing)`로 배치했다. `Menu`는 **[다시 응답 받기] / [질문 수정하기]**, 말풍선 우클릭도 같은 동작. 응답 대기 중에는 비활성.
- 기존 왼쪽 `⋯`는 제거. 렌더 `docs/qa/question-menu-ko/chat-ko.png`에서 오른쪽·세로 중앙 확인.

#### AI 오류 — `E-MAC-NET-0003` / HTTP 503
- `E-MAC-NET-0003`은 **모델/업스트림 5xx**다. 이번 화면의 `HTTP 503 · server_error`는 모델 서버(또는 그 앞 프록시)가 **과부하·점검·프록시 오류**로 요청을 처리하지 못한 것이며, QuickTalk의 네트워크 연결 실패가 아니다.
- **말풍선·연결 테스트**: `(오류 E-MAC-NET-0003) 모델 서버(업스트림)가 일시적으로 요청을 처리할 수 없습니다 — 과부하·점검·프록시 장애일 수 있습니다. 잠시 후 다시 시도하거나 다른 모델을 선택하세요 [server_error] (HTTP 503) — 서버: host:port`.
- **상태 카드**: `HTTP 503 · server_error — 모델 서버 과부하·점검·프록시 오류 가능. 잠시 후 재시도하거나 다른 모델을 선택하세요` (2줄로 맞춤).
- 서버 응답 **본문은 계속 노출하지 않는다**([HARD]). HTTP 상태·서버 코드·원인·다음 행동만 표시한다.
- 검증: `AIErrorTextTests`에 503/server_error/host/상태 카드 길이 테스트 추가.

#### QuickShelf — 사용한 항목 제거
- **파일 카드**: 대화에 첨부한 뒤 목록에서 제거(원본 파일은 유지).
- **캡처 카드**: `QuickTalk/clip`에 임시 복사본을 만든 뒤 첨부하고, 원본 캡처 파일과 카드를 함께 삭제. 첨부가 삭제된 경로를 가리키지 않는다.
- **클립보드**: 기존대로 사용 시 목록에서 제거.
- 푸터·설정 문구를 `첨부하면 목록에서 사라짐 (복사·저장은 유지)`로 갱신.

#### 기억 [보기] 발견성
- 설정 › AI › **대화 기억 정리**에 **[보기]** 버튼을 추가했다. 입력독 위 배너의 [보기]와 같은 `MemorySheet`를 열고 요약을 직접 편집할 수 있다.
- 캡션에 “요약이 생기면 **이 화면의 [보기] 또는 입력독 위 배너의 [보기]**에서 확인·편집”이라고 두 위치를 명시.
- 렌더 `docs/qa/memory-view-ko/settings-ai-ko.png`에서 버튼·캡션 확인.

#### 검증·배포
- `swift test` **261/261**(6 skip), BUILD SUCCEEDED.
- 렌더: `docs/qa/question-menu-ko/`, `docs/qa/memory-view-ko/`, `docs/qa/ai-503-ko/`(허브 상태 카드).
- 배포: 2026-10-21 04:30 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK, SHA-256 `19fa12c4cf66c19c0697fb3ded1151bbfc29783ef3784eb90d0c6590ed82b2a6`.

#### 사용자 확인 (이 순서)
1. 앱 **완전 종료 후 재실행**.
2. 사용자 질문 오른쪽 `⋯`가 **세로 중앙**에 있고, [다시 응답 받기]/[질문 수정하기]가 동작하는지.
3. 설정 › AI › 대화 기억 정리에 **[보기]**가 보이고, 입력독 위 배너 [보기]와 같은 시트가 열리는지.
4. QuickShelf 파일·캡처 카드를 대화에 첨부 → **목록에서 사라지는지**(파일 원본은 Finder에 남아 있어야 함).
5. AI 오류가 나면 상태 카드에 **HTTP 상태·server_error·원인·다음 행동**이 보이는지. 503은 잠시 후 재시도하거나 다른 모델을 선택.

### 2.2 2026-10-21 잔여 배치 (완료, 실측 대기)

#### QuickShelf 가장자리 핸들 제거 (H4)
- `ShelfHandleView`·`handleWindow`·`buildHandle`·`handleFrame`·`repositionHandle`·`setHandleVisible`와 `shelfEnabled` 설정/UI를 **삭제**했다.
- QuickShelf 진입점은 **`⇧⌥V`**, 대화 헤더의 퀵셸프 버튼, 그리고 대화창이 열려 있을 때의 **창 안 오버레이**뿐이다. 화면 오른쪽 가장자리 탭은 더 이상 없다.
- 캡처 전 `hideForCapture()`는 패널·대화창만 내리고, 끝나면 패널만 복원한다. 설정 › 퀵셸프에서 [가장자리 핸들 표시] 토글도 사라졌다.
- 기존 `settings.json`의 `shelfEnabled` 키는 무시된다(디코딩 호환).

#### T-17 설정 여백
- **기본 창 높이는 그대로** 둔다. 전면 설정 상세의 하단 패딩을 18→10pt로, 대화 창 설정 카드의 마지막 하단 여백을 줄였다.
- 짧은 설정 화면에서 창 바닥까지 남는 빈 공간은 창 높이 자체이므로, 없애려면 사용자가 창 높이를 줄이면 된다(기본 크기 강제 축소 없음).

#### 웹 검색 P2 — 인용 클릭·재시도·판정 캐시
- **`[n]` 클릭**: `CitationLinks`가 코드 블록·인라인 코드 밖의 `[n]`을 `[[n]](url)`로 바꾸고, `MarkdownInline`이 `[n]` 라벨의 링크로 파싱한다. 답변의 인용을 누르면 기본 브라우저로 출처가 열린다. 원문·복사·읽어주기는 그대로.
- **[웹에서 찾기]**: 모델이 “검색할 수 없습니다”라고 답한 경우(`WebSearchQuery.looksLikeSearchRefusal`) 답변 아래 보라색 버튼이 뜬다. 누르면 그 질문과 이후 턴을 되돌리고 같은 질문을 `forceWebSearch`로 재전송한다.
- **판정 캐시**: `providerID + 직전 질문 + 현재 질문` 키로 10분 캐시. 같은 질문을 반복해도 판정 모델을 다시 부르지 않는다. 캐시는 성공한 판정만 저장한다.

#### 웹 검색 P3 — 하루 한도·사용량·예상 비용
- 설정: `webSearchDailyLimit` 기본 **50회**(0=무제한), `webSearchUsageDay`/`Count`.
- 네트워크 검색이 **성공**했을 때만 카운트한다(캐시 적중 제외, 결과 0건이라도 HTTP 응답을 받았으면 카운트). 날짜가 바뀌면 자동 리셋.
- 한도 도달 시 `E-MAC-SEARCH-0006`을 반환하고 **검색만 건너뛴다**(답변은 계속). 설정 › AI에 `오늘 N회 · 예상 $… (Exa $7/1k 기준, 캐시 적중 제외)` 표시.

#### 대화 기억 — 강제 축약·요약 직접 편집
- `ConversationMemory.fitHistory`: 이번 질문·요약·첨부 예약분을 뺀 예산에 최근 원문이 안 들어가면 **오래된 턴부터 요청에서 제외**한다. 저장된 원문은 그대로이고, `모델 예산을 넘어 이전 메시지 N개를 이번 요청에서 제외했습니다. 원문은 그대로 남아 있습니다.` 배너를 띄운다.
- `MemorySheet` [보기]: `TextEditor`로 요약을 직접 고치고 **[저장]**할 수 있다. `ConversationStore.replaceSummary`는 `summaryThroughTurnID`와 `compactPaused`를 유지한다. 빈 요약은 저장하지 않고 [요약 해제]를 안내한다.

#### QuickShelf 캡처 후 툴바
- 캡처 카드에 마우스를 올리면 **클립보드 복사 · 다른 이름으로 저장 · Finder에서 보기** 버튼이 뜬다. 카드 클릭은 기존대로 대화 첨부.
- 우클릭 메뉴에도 같은 동작 + 삭제가 있다. 저장은 `NSSavePanel`(PNG), 복사는 `NSPasteboard`에 이미지로 넣는다.

#### 검증
- `swift test` **260/260**(6 skip), BUILD SUCCEEDED.
- 렌더: `docs/qa/t17-ko/`, `docs/qa/web-ko/`(인용 링크), `docs/qa/web-retry-ko/`·`web-retry-en/`(재시도 버튼, 영어·다크), `docs/qa/web-ai-ko/`(한도·사용량).
- 배포: 2026-10-21 02:20 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK, SHA-256 `08653035…d5bb2c94`.

#### 사용자 확인 (이 순서)
1. 앱 **완전 종료 후 재실행**.
2. 화면 오른쪽 가장자리에 **보라색 탭이 없는지**. QuickShelf는 `⇧⌥V`와 헤더 버튼으로만 열려야 한다.
3. 웹 검색 답변에서 `[1]`을 클릭 → 출처가 브라우저로 열리는지.
4. “검색할 수 없습니다” 답변에서 **[웹에서 찾기]** → 같은 질문으로 검색 포함 답변이 다시 오는지.
5. 설정 › AI에서 **하루 검색 한도**(기본 50회)와 `오늘 N회 · 예상 $…`가 보이는지. [검색 테스트] 후 N이 1 증가하는지(캐시 적중은 증가하지 않음).
6. 기억 배너 [보기] → 요약을 고치고 [저장] → 닫았다가 다시 [보기]에서 유지되는지. [요약 해제]는 그대로 동작.
7. QuickShelf 캡처 탭에서 캡처 카드에 마우스를 올려 **복사·저장·Finder** 버튼이 뜨는지, 카드 클릭은 첨부로 동작하는지.

### T-73 헤더 기억 토큰 진행률 (완료, 실측 대기)

- 대화 탭에서 **제목 아래**에 `뇌 아이콘 + 현재토큰 / 자동 정리 기준 · %`를 표시한다. 대화가 1턴 이상이고 활성 프로바이더가 있을 때만 나온다.
- 현재값은 `ConversationMemory.contextTokens`(요약이 있으면 요약+경계 이후 원문), 기준은 `inputBudget × 0.70`이다. 원격 기본 32,768이면 `21,324`, Ollama 기본이면 `4,121`, Apple FM이면 `1,971`.
- 기준을 넘으면 숫자가 **주황**으로 바뀐다. 자동 정리는 그 다음 답변을 **성공적으로 마친 뒤** 백그라운드에서 실행된다.
- 툴팁: “현재 약 N토큰 · 자동 정리 기준 M토큰. 기준을 넘으면 다음 답변을 마친 뒤 백그라운드에서 정리합니다.”
- 설정 › AI › 대화 기억 정리의 상세 카드는 그대로 유지한다. 헤더는 **한눈에 보는 진행률**, 설정은 실행 버튼·최근 원문 수·해제를 담당한다.
- 검증: `swift test` **252/252**(6 skip), BUILD SUCCEEDED, 렌더 `docs/qa/t73-ko/`·`t73-en/`·`t73-dark/`, 2026-10-21 01:07 배포·서명 OK.

**사용자 확인**
1. 앱 **완전 종료 후 재실행**.
2. 대화가 있는 상태에서 제목 아래 `N / M · %`가 보이는지. 1턴짜리 대화는 0%로 표시되는 것이 정상.
3. 마우스를 올리면 기준 초과 시 동작 설명이 보이는지.
4. 70%를 넘으면 숫자가 주황으로 바뀌는지(현재 대화는 약 59%).
5. [지금 정리] 후에는 현재 토큰이 줄어드는지.

### T-72 질문 되돌리기·다시 응답·입력창 후속 (완료, 사용자 확인 OK)

- **질문 메뉴**: 사용자 말풍선 오른쪽 `⋯`(또는 우클릭) → **[다시 응답 받기]** / **[질문 수정하기]**. (2026-10-21 04:30에 왼쪽→오른쪽·세로 중앙으로 이동)
  - 둘 다 그 질문과 **이후 턴을 모두 삭제**한다. `ConversationStore.rewind(toUserTurnID:)`가 원래 턴을 돌려주고, `UIStore`가 텍스트·첨부(이미지 경로 포함)를 입력창에 복원한다.
  - **다시 응답** = 복원 후 같은 질문을 즉시 재전송. **질문 수정** = 입력창에 채운 채로 두고 커서를 둔다.
  - 첫 질문을 되돌리면 자동 제목을 새 질문에서 다시 만든다(직접 바꾼 제목은 유지). 삭제된 턴을 가리키던 요약은 무효화한다.
  - 응답 대기 중에는 메뉴가 비활성. 다시 응답은 `/compact` 같은 보조 명령으로 해석하지 않는다.
- **입력창 성장**: Shift+Enter로 문자열이 `\n`으로 끝나면 마지막 빈 줄은 글리프가 없어 높이 계산에서 빠졌다 → `extraLineFragmentRect`를 포함하고 캐럿을 그 줄로 계산. 첫 레이아웃 뒤 한 번 더 측정. 5줄까지 자라고 이후에는 내부 스크롤.
- **입력독 버튼**: 🌐·🎤·↑를 `.bottomTrailing` + 아래 9pt로 고정 — 여러 줄에서도 바닥에 붙는다.
- **질문 구분**: 사용자 말풍선만 액센트 틴트 배경(`accentColor 0.16`)+테두리, 답변은 기존 중립.
- **첨부 미리보기**: `AttachmentPreview`의 NSImage 값 비교가 렌더마다 새 이미지라 실패해 호버를 벗어나도 남던 문제 → `hoverPreviewKey` 안정 키로 닫기. **Esc**(숨은 단축 버튼 + `onExitCommand`), 탭/대화/첨부 수 변경, 앱 비활성, 화면 이탈에서도 닫는다. 카드에 `esc Esc로 닫기` 안내.
- **스트리밍 아이콘**: 답변이 오는 동안 복사·읽어주기를 `opacity 0`으로 숨기고 자리는 유지.
- **보관함**: 행 전체 폭 열기 버튼(빈 공간 클릭 가능), 우측 변경/삭제는 오버레이. 검색어를 지우는 `xmark.circle.fill` 버튼 추가.
- **기억 시점 가시화**: 설정 › AI › 대화 기억 정리에 `현재 약 N토큰 · 자동 정리 기준 M토큰`과 "기준을 넘으면 다음 답변을 마친 뒤 백그라운드에서 정리합니다."를 표시.
- **검증**: `swift test` **252/252**(6 skip, `ConversationRewindTests` 5건), BUILD SUCCEEDED, 렌더 `docs/qa/t72/`·`t72-en/`, 2026-10-21 00:09 배포·서명 OK. **2026-10-21 사용자 확인 OK.**

**사용자 확인 (이 순서)**
1. 앱 **완전 종료 후 재실행**.
2. 최근 질문 옆 `⋯` → **[다시 응답 받기]**: 그 질문 이후가 지워지고 새 답변이 와야 한다.
3. 다른 질문 옆 `⋯` → **[질문 수정하기]**: 질문과 이후가 지워지고, 원래 텍스트·이미지 첨부가 입력창에 복원되고 커서가 있어야 한다. 수정 후 Enter.
4. 입력창에서 Shift+Enter를 여러 번: 상자가 **줄마다 자라고**, 마지막 빈 줄에 커서가 보여야 한다. 5줄을 넘으면 안에서 스크롤. 🌐·🎤·↑는 항상 **아래쪽**.
5. 질문 말풍선은 답변과 **배경색이 다르게** 보여야 한다.
6. 첨부 칩/보낸 첨부에 마우스를 올렸다가 **다른 곳으로 이동** → 미리보기가 사라져야 한다. 남아 있으면 **Esc**. (카드 하단 `esc Esc로 닫기`)
7. 답변이 **스트리밍 중일 때** 복사·읽어주기 아이콘이 보이지 않고, 끝나면 나타나야 한다.
8. 보관함에서 검색 → 결과 행의 **제목이 아닌 빈 공간**을 클릭해도 열려야 한다. 검색어 오른쪽 `⊗`로 한 번에 지워져야 한다.
9. 설정 › AI › 대화 기억 정리에서 **현재 토큰 / 자동 정리 기준**이 보이는지. 원격 기본이면 21,324토큰부터라 일반 대화에서는 아직 요약되지 않는 것이 정상. 더 일찍 원하면 컨텍스트 토큰을 낮추거나 [지금 정리].

### T-71 자동 대화 기억 정리 (완료, 실측 대기)

```
대화가 길어짐
  → 입력 예산의 70% 초과?
     → (답변 성공 후, 백그라운드) 오래된 턴을 요약
        → 이후 요청 = 요약 + 경계 이후 최근 원문만
           → 원문 턴은 화면·보관함·검색에 그대로 남음
```

- **자동**: 답변 후 백그라운드. `settings.autoCompact` 기본 켜짐. 현재 답변 지연 없음.
- **트리거**: Apple FM 입력 2,816의 70%(≈1,971), Ollama 5,888의 70%(≈4,121), 원격 30,464의 70%(≈21,324).
- **최근 원문**: 기본 6개(짝수 보정), Apple FM은 4개. 오래된 구간만 요약.
- **저장**: `Conversation.summary` + `summaryThroughTurnID`. 요약은 **턴이 아니라 프롬프트 앞**에 고정(Apple FM 6턴 제한 회피).
- **원문 불변**: 턴 삭제 없음. 요약은 전송용 캐시.
- **수동**: `/compact`는 보조 명령(일반 UX 아님). 정확히 `/compact`일 때만, 턴을 남기지 않는다.
- **해제**: 배너 [해제] → 요약 삭제 + 자동 정리 일시 중지. [다시 켜기] 또는 `/compact`로 재개.
- **안전**: 적용 직전 대화방 ID·경계 턴·일시 중지 여부 확인. 실패하면 아무것도 바꾸지 않음.
- **로그**: 턴 수·요약 글자 수·지연만. 대화 내용·요약 본문 금지.
- 상세: `docs/plans/PLAN_v0.15_memory_macos.md`

**헤드리스 실측 (2026-10-20)**
| 항목 | 결과 |
|---|---|
| Apple FM 20턴 | 2,100 → **513** 토큰, recent 3, 6.6초, 요약 93자 |
| 원격 20턴 | 2,100 → **903** 토큰, recent 5, 3.5초, 요약 323자 |
| 자동 트리거 20턴 | `expected=YES → summary=YES` (**Apple FM 기준** — 원격·Ollama 예산은 훨씬 커서 트리거되지 않음) |
| 자동 트리거 10턴 | `expected=NO → summary=NO` |
| 테스트 | **395/395**, 6 skip = `QT_LIVE` 4 + `QT_LIVE_STREAM` 2 (신규 10 = 창 배치 9 · 설정 왕복/미지값 1) |
| QA 렌더 | `docs/qa/memory-chat-ko` · `-en`, `memory-settings-ko` · `-en` |

**사용자 확인 (이 순서)**
1. 앱 **완전 종료 후 재실행** (실행 중 프로세스는 이전 빌드).
2. 대화를 길게 이어가거나, 설정 › AI › 대화 기억 정리에서 **[지금 정리]**.
   - 기대: 입력독 위 `이전 대화를 정리하는 중…` → `이전 N개 메시지를 요약해 기억 중`.
3. **[보기]** → 모델이 보는 요약 + “원문은 화면·보관함에 그대로 남아 있습니다.”
4. **[해제]** → 배너가 `자동 정리가 일시 중지되어 있습니다`로 바뀌고, 다음 요청은 전체 원문 사용. **[다시 켜기]**로 재개.
5. 설정 › AI › **대화 기억 정리**에서 자동 토글·최근 원문 4/6/8/12·[지금 정리] 확인.
6. `/compact`를 입력해 보조 명령으로도 정리되는지(일반 사용자는 몰라도 됨).

### T-70 웹 검색 (P1 완료, 사용자 확인 OK)

#### 구현된 것
```
질문 → 필요 여부 판정(모델에게 짧게 질문) 또는 🌐 강제 → Exa 1회(3~8건)
     → 상위 결과 제목·URL·날짜·본문(≤2,000자)을 기존 프롬프트에 주입
     → 기존 모델이 스트리밍 + [n] 인용 → 말풍선 아래 출처 카드(클릭=기본 브라우저)
```
- **"필요할 때만"**: 질문 문구의 키워드 목록으로 추측하지 않는다. **활성 프로바이더**(답변을 만들 모델)에게
  "지금 확인해야 하는 최신 사실이 필요한가?"만 짧게 묻고(Y/N), 애매·실패·시간 초과면
  **검색하지 않는다**. 판정 제한은 프로바이더별 **Apple FM 5초 / 원격 8초 / Ollama 20초**(2026-10-21 수정).
  판정에 약 1~2초가 더 걸린다(검색이 켜져 있을 때만).
  - Local Apple FM이 활성이면 **온디바이스가 판정**한다(네트워크 없음, 0.5~2초). 실측 YES/NO 정상.
  - 판정·검색·답변이 모두 같은 활성 프로바이더를 쓴다. 검색(Exa)만 키가 따로 필요하다.
  - Apple FM은 스트리밍 경로가 없어 답변이 **한 번에** 온다 → `웹에서 찾는 중…` 뒤 잠깐 기다렸다가 전체 답변(실측 8.8초, 인용 4종).
- 🌐를 켠 질문은 판정을 건너뛰고 **반드시** 검색한다(전송 후 자동 해제).
- 모델 교체·툴콜링 없음 → OpenAI 호환·Ollama·Apple FM 모두 동일하게 동작
- 검색 실패·0건은 답변을 막지 않고 `⚠️ 웹 검색 실패 (E-MAC-SEARCH-000x) …`만 앞에 붙인다
- 같은 질문은 **10분 캐시**(최대 50개). `웹 검색`을 끄면 외부 요청 0회
- 키는 `SecretStore`(`exa-api-key`)에만, 설정 JSON·로그에 남기지 않는다
- `Turn.sources`는 구버전 `history.json`과 호환(없으면 nil)

### 사용자 확인 (이 순서)
1. 앱 **완전 종료 후 재실행**
2. 설정 › **AI** › 맨 아래 **웹 검색** › 공급자 = **Exa** (키는 이미 저장됨 → `키 저장됨 (로컬 파일)`)
3. 검색 시점 = **필요할 때만** 표시 확인(선택지 없음 — 자동 판정)
4. 대화에서 `오늘 네이버 뉴스 IT 기사 알려줘`
   - 기대: 잠깐 `응답 중…`(판정) → `웹에서 찾는 중…` → 글자가 차례로 → 답변 아래 `[1] yna.co.kr …` 카드 3~5개
   - 카드 클릭 → 기본 브라우저
5. 🌐 버튼(입력독 왼쪽, 마이크 옆)을 켜고 `구구단 만들어줘` → 판정 없이 검색이 1회 실행되는지
6. 설정의 **[검색 테스트]** → `검색 5건 · 2.x초` 표시. **[캐시 비우기]** → 안내 문구

### P2·P3 (2026-10-21 구현 완료)
- P2: `[n]` 클릭 링크, “검색할 수 없습니다” 답변의 **[웹에서 찾기]** 재시도, 판정 10분 캐시·직전 질문 맥락
- P3: 하루 검색 한도(기본 50, 0=무제한)·오늘 사용량·예상 비용, `E-MAC-SEARCH-0006`
- **미착수(명시)**: 모델 툴콜링 방식 검색, Exa `/answer` 폴백 — 현재는 검색 결과를 프롬프트에 주입하는 P1 경로만 쓴다
- 상세: `docs/plans/PLAN_v0.14_websearch_macos.md` §12

## 3. 실측 대기 (사용자 확인)

사용자가 앱을 재실행한 뒤 확인해야 하는 항목. **전체 체크리스트는 `docs/QA-CHECKLIST-2026-10-20.md` (A~K)**.

| ID | 기능 | 확인할 것 | QA 렌더 |
|---|---|---|---|
| 2026-10-21 15:14 | **크래시 수정 + 헤더 정리·상대 시간·맨 아래로** | **K3**(이미지 첨부 질문 수정 → 전송)이 더 이상 죽지 않는지, 아이콘 크기·툴팁, 응답 `N분 전 · N초`, 보관함 마지막 대화 시간, 우하단 ↓ 버튼 | QA **N17~N19** · `docs/qa/t74-ko/chat-ko.png` |
| 2026-10-21 14:25 | **Ollama 응답 없음 / 느림** | ✅ N15 사용자 확인 완료(답변 O). 절약·타임아웃은 **Ollama 전용**으로 확정 — Apple FM·원격 기존 동작 | QA **N15** |
| 2026-10-21 12:40 | **예비 AI 폴백** | **실사용 확인(13:00)** — 429에서 `예비 모델(Local Apple FM)`이 답하고 안내가 붙음 ✅. 13:05 문구 정리 후 재확인 | QA **N14** · `docs/qa/fallback-settings-ko` · `docs/qa/fallback-note-ko` |
| 2026-10-21 11:05 | **판정 실패 재시도·감지 확장** | 레이트리밋(429) 중에도 `오늘 서울 날씨`가 검색되는지, 검색 없이 답한 경우 **[웹에서 찾기]**가 뜨는지 | QA **N13** · `docs/qa/web-retry-tool-ko` · `web-retry-classic-ko` |
| 2026-10-21 10:40 | **검색 필요 판정** | 웹 검색 켠 상태에서 `오늘 서울 날씨` → 실제 검색, `구구단` → 검색 안 함 | QA **N12** |
| 2026-10-21 | 잔여 배치 | 핸들 없음, 인용 클릭, [웹에서 찾기], 하루 한도/사용량, 요약 편집, 캡처 툴바 | `docs/qa/t17-ko` · `web-ko` · `web-retry-ko|en` · `web-ai-ko` |
| T-73 | 헤더 토큰 진행률 | 제목 아래 `현재 / 기준 · %`, 70% 초과 시 주황, 툴팁, [지금 정리] 후 감소 | `docs/qa/t73-ko/` · `t73-en/` · `t73-dark/` |
| T-71 | 대화 기억 정리 | [지금 정리] 또는 70% 도달 후 배너·[보기] 요약·[해제]/[다시 켜기], `/compact` | `docs/qa/memory-chat-ko` · `-en` |
| T-67 | AI 오류 원인 | 연결 거부/시간 초과/HTTP 상태가 정확히 표시되는지 | `docs/qa/ai-error-ko` · `-en` |
| T-59~60 | 단축키 녹화·Piper | 5종 단축키 변경/충돌 안내, Piper 목소리·속도·미리 듣기 | — |

> 2026-10-21 **배치 1 완료**: 아래 표의 웹 검색·폴백 관련(**N12·N13·N14**, 잔여 배치의 인용 클릭·[웹에서 찾기]·하루 한도)은 사용자 실측 **OK**. QuickShelf 캡처 툴바·기억 편집 등 나머지는 배치 2~4에서 확인한다.

> 2026-10-21 사용자 확인 OK: T-72·T-70·T-27·T-28·T-18·T-20·T-36·T-56~T-58·T-62~T-66·T-68~T-69.
> 2026-10-21 15:55 **배치 2(34건)·N16·N17~N19 OK** — K3(이미지 첨부 질문 수정 → 전송)도 더 이상 죽지 않음을 확인.

> T-68 스트리밍이 한 번에 나오면 프록시가 SSE를 지원하지 않는 경우다(JSON 폴백). 사용자에게 알리고 프록시 설정을 확인한다.

## 4. 미완료·보류

| ID | 내용 | 상태 |
|---|---|---|
| T-21 | 포인터 pill(380×56) | **구현 완료(2026-10-21 20:35)** — 사용자 실측 대기(`docs/qa/t21-pill/CHECKLIST.md`), 계획 `docs/plans/PLAN_v0.17_pointer-pill_macos.md` |
| H3 | 다크/틴티드 아이콘 아트워크 | 에셋 대기 |
| H2 | 채팅 배경 워터마크 | **없음 — 종료(2026-10-21)**. 기존 새 대화 아이콘만 유지 |
| H4 | QuickShelf 화면 가장자리 핸들 | **제거 완료(2026-10-21)**. `⇧⌥V`·헤더 버튼·창 안 오버레이만 사용 |
| T-22 | 클립보드 전체 검색 레이어 | **종료(2026-10-21)** — 현재 스트립으로 충분, 미구현 |

> T-18·T-20·T-27·T-28·T-36은 2026-10-21 사용자 확인 OK로 이 표에서 제거했다. QuickShelf 캡처 후속 중 **선택 후 툴바는 완료**, 주석·스크롤 캡처·OCR은 미착수다.

## 5. 빌드·테스트·배포

```bash
cd /Users/lee/Documents/Apps/QuickTalk

# 1) 코어 테스트 (기준선 326/326, 6 skip)
swift test

# 2) 새 파일을 추가했을 때만 프로젝트 재생성
xcodegen generate --spec project.yml

# 3) 앱 빌드
xcodebuild -project QuickTalk.xcodeproj -scheme QuickTalk -configuration Debug \
  -destination 'platform=macOS' -derivedDataPath build build

# 4) 배포 (실행 중 앱은 건드리지 않는다 — 새 빌드는 재실행 때 적용)
rm -rf ~/Applications/.QuickTalk.new
ditto build/Build/Products/Debug/QuickTalk.app ~/Applications/.QuickTalk.new
rm -rf ~/Applications/.QuickTalk.old
if [ -d ~/Applications/QuickTalk.app ]; then mv ~/Applications/QuickTalk.app ~/Applications/.QuickTalk.old; fi
mv ~/Applications/.QuickTalk.new ~/Applications/QuickTalk.app
rm -rf ~/Applications/.QuickTalk.old
codesign --verify --strict ~/Applications/QuickTalk.app
```

- 서명: **Apple Development 수동 서명** (`DEVELOPMENT_TEAM: 6GPJQ7BQC9`). ad-hoc으로 바꾸면 TCC(화면 기록·마이크·음성) 권한이 매번 풀린다.
- `swift test`의 6 skip은 정상: `QT_LIVE` 4 + `QT_LIVE_STREAM` 2.
- QA 하네스: `--tool-test=<질문>`, `--answer-test=<질문>`, `--demo-global-memory`.
  실측 로그는 건수·지연만 남기고 검색어·본문·키는 남기지 않는다.
- 실행 중인 앱을 **죽이지 않는다.** 배포 후 "완전 종료 후 다시 실행해 달라"고 안내한다.
- 새 파일을 추가한 뒤 `xcodegen`을 잊으면 앱 타깃에서 `cannot find ... in scope`가 난다.

## 6. QA 오프스크린 렌더

```bash
APP=build/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk
"$APP" --render=docs/qa/새폴더 --lang=korean --theme=dark --demo-...
```

주요 플래그:
- `--lang=korean|english`, `--theme=light|dark`, `--settings-tab=...`, `--shelf-tab=...`
- `--demo-chat[=empty]`, `--demo-stream`, `--demo-error`, `--demo-rename`, `--demo-memory`
- `--demo-delete-confirm` / `--demo-delete-confirm=all` (T-69)
- `--demo-settings-wide`, `--demo-ping`, `--render-tall`, `--render-height=1400`
- `--demo-search`(검색 중) · `--demo-search-sources`(출처 카드) · `--demo-search-error`(실패 경고) · `--demo-search-refusal`(“검색할 수 없습니다” → [웹에서 찾기])
- `--demo-websearch` — 렌더에서 웹 검색 카드를 켠 상태로 본다(저장 안 함)
- `--search-test="질문"` — 저장된 Exa 키로 실제 검색 1회, **건수·지연·도메인만** 로그
- `--search-decide-test="질문"` — "필요할 때만" 판정만 확인(YES/NO·지연, 질문 내용 로그 없음)
- `--search-answer-test="질문"` — 검색 → 프롬프트 주입 → 모델 스트리밍까지 헤드리스 검증
- `--compact-test[=<턴수>]` — 긴 대화를 만들어 **수동 정리 1회**, 요약 글자 수·전후 토큰·지연만 로그
- `--compact-auto-test[=<턴수>]` — **자동 트리거(70%)** 확인. 20턴 YES / 10턴 NO
- `--provider=applefm|ollama|remote` — 위 실검증에서 활성 프로바이더만 메모리에서 바꾼다(저장 안 함)
- `--demo-pill` — T-21 pill 오프스크린 렌더(빈 입력·입력 중·보관함 목록). 실제 창·단축키는 쓰지 않는다

`--render`은 창을 띄우지 않고 PNG만 만들며 실제 설정·기록을 저장하지 않는다(프로세스 한정 오버라이드). 그래도 사용자 맥 사용 중에는 **오프스크린 렌더만** 허용된다.

## 7. 핵심 파일 지도

### Core (`Sources/QuickTalkCore`)
- `LLMProvider.swift` — `LLMClient`(send/stream), OpenAI SSE, Ollama NDJSON, 폴백
- `WebSearch.swift` — **Exa 검색**(요청·파싱·오류 매핑), HTML 정리, 트리거 판정, 프롬프트 컨텍스트, 10분 캐시, **일일 할당량(`WebSearchQuota`)**·검색 불가 감지
- `ConversationMemory.swift` — **자동 대화 기억 정리**: 토큰 추정·프로바이더 예산·70% 트리거·짝수 경계·전사/청크·롤링 요약 프롬프트·요청 기록·**예산 초과 시 강제 축약(`fitHistory`)**
- `Settings.swift` — 설정 전체 + **커스텀 `decodeIfPresent`** (새 필드 추가 위치)
- `Models.swift` — `Conversation`, `Turn`, `Attachment`
- `Store.swift` — 대화 상태·스트리밍 턴 조작·`replaceSummary`(경계/일시 중지 유지)
- `LocalizationTable.swift` — 한국어 원문 → English 번역표
- `AIErrorText.swift` — 오류 코드·사용자 문구
- `ServerFailure.swift`, `AttachmentRetry.swift` — HTTP 상태 분류·재시도
- `ProviderFallback.swift` — **예비 모델 폴백 판정**(허용/거부 분류·준비 상태 확인)
- `Markdown.swift` — 마크다운 파서 + **`CitationLinks`(웹 인용 `[n]` 클릭 링크)**
- `SpeechCatalog.swift`, `EdgeTTS.swift`, `PiperTTS.swift`, `WhisperService.swift`
- `ConversationHistory.swift`(Persistence), `CaptureGeometry.swift`, `SecretStore.swift`
- `ShortcutEntry.swift` — **⌘Space 표시 판단**(`ShortcutEntryPresentation`: 대화 창 / pill)

### App (`QuickTalkApp`)
- `ContentView.swift` — 대화·보관함·설정 탭, 스크롤, 검색 포커스, 시트 2종(기억 요약 **편집** 포함)
- `UIStore.swift` — send/**streamReplyWithFallback**, 기록 동기화, 삭제/이름 변경, TTS, **웹 재시도·검색 할당량**, **캡처 복사/저장**
- `SettingsView.swift` + `+General` / `+AI` / `+Voice` / `+Archive` — 전면 설정 7탭
- `SettingsView+WebSearch.swift` — 웹 검색 카드(공급자·키·모드·결과 수·신선도·**하루 한도/사용량**·검색 테스트)
- `SettingsView+AI.swift` — 프로바이더 목록 + **예비 AI 픽커** + **대화 기억 정리 카드**
- `ShelfPanel.swift` — QuickShelf 플로팅 패널(가장자리 핸들 없음)
- `ShelfView+Capture.swift` — 캡처 탭 + **카드 호버 툴바(복사·저장·Finder)**
- `ProviderEditorSheet.swift` — 프로바이더 편집 + **컨텍스트 토큰(선택)**
- `RenameSheet.swift`, `DeleteConfirmSheet.swift` — 자체 시트(공용)
- `ShelfView.swift` + `+Clipboard` / `+Files` / `+Capture`, `ShelfPanel.swift`
- `CaptureService.swift` + `CaptureOverlay.swift`
- `QuickTalkApp.swift` + `AppDelegate+RenderHarness.swift`
- `PointerPill.swift` — **T-21 포인터 pill**(패널·컨트롤러·뷰·단일 행 입력)
- `MarkdownText.swift`, `ChatInputField.swift`

## 8. 규칙·주의

- **design_profile = custom**: 앱 자체 화면에서 네이티브 alert/Picker/NSPopUpButton 금지. 확인 UI도 `DeleteConfirmSheet` 같은 자체 시트. (전면 설정의 기존 `pickerRow`는 유지)
- **서버 응답 본문을 사용자 문구로 노출 금지** — 상태코드·서버 코드만. API 키·대화 내용은 로그에 남기지 않는다.
- **키는 `SecretStore`**(`~/Library/Application Support/QuickTalk/secrets.json`, 600)에만. 설정 JSON에 키를 넣지 않는다.
- 기록은 모든 대화 `history.json` 자동 저장. 시작 시 마지막 대화 복원. 창 기본 레벨 `.normal`, 📌=항상 위, 🔖=보관.
- **대화 기억 정리는 요약만 바꾼다** — 원문 턴 삭제·이동 금지. 요약 본문·대화 내용은 로그에 남기지 않는다. [해제]는 자동 정리를 멈추고, [다시 켜기]로 재개한다.
- 대화를 열 때/이어갈 때 스크롤은 **항상 맨 아래**(보관함 검색으로 열 때는 찾은 턴).
- 영어 모드에서는 **모든 화면 문구가 영어**, 한국어에서는 "QuickShelf"도 **퀵셸프**.
- 드래그·윈도우 캡처: **십자 커서**, **Esc 취소**, **Space로 드래그↔윈도우 전환**.
- 클립보드: 후 제거, 민감 마스킹, 2분/최대 5개, 내용 로그 금지.
- **화면 제어 금지**: 실행/종료·스크린샷·창 조회·소리 재생 금지. 오프스크린 렌더는 허용.
- **git 저장소 있음**(2026-10-21 20:12 초기화, `origin BoraSarang/QuickTalk`). `main` 직접 push 금지 — 작업은 브랜치에서. 커밋 전 `git status`로 사용자 변경을 확인한다.

## 9. 알려진 주의점

- **pill은 별개 기능이 아니다**(T-21). ⌘Space의 표현만 다르고, 규칙의 단일 출처는 설정의
  `shortcutSessionMinutes`(+`continuesSession`)이다. pill이 떠 있는 동안에는 대화 상태를 바꾸지 않고,
  **전송할 때만** `startShortcutSession()`을 부른다. 새 규칙을 만들 때 이 두 곳을 갈라놓지 않는다.
- **SwiftUI `Capsule().strokeBorder`는 좌우 끝에 1pt 세로 이음새를 남긴다**(macOS 26, 2026-10-21 렌더에서 확인).
  높이의 절반 길이(28pt) 선이 캡슐 양 끝에 보인다. 같은 반지름의
  `RoundedRectangle(cornerRadius: h/2, style: .circular)`로 그리면 사라진다(`.continuous`는 재현됨).
  시스템 머티리얼(`.regularMaterial`)도 창 가장자리에서 1pt 이음새가 보이므로 pill은 반투명 솔리드로 채운다.
- **`@Published`(설정·상태)는 반드시 메인 액터에서만 고친다**(2026-10-21 실사용 크래시). 비격리 `async` 함수가
  `await` 뒤 협력 스레드에서 `settings`를 수정하면 SwiftUI가 **그 스레드에서** 뷰를 갱신하고, AppKit 입력창이
  `NSWindow drag regions should only be invalidated on the Main Thread!` 예외로 **앱을 죽인다**(SIGABRT).
  UI 상태를 만지는 async 함수는 `@MainActor`로 고정한다(`searchWeb`·`answerWeb`이 그렇게 바뀌었다).
- `ContentView`에 `.sheet(item:)`가 2개(rename/delete) 붙어 있다. macOS 14에서 정상 동작하지만, 한쪽이 안 뜨면 **enum 기반 단일 시트**로 합친다.
- T-68 스트리밍은 프록시가 SSE를 무시하면 JSON 폴백으로 한 번에 나온다(정상 폴백).
- Exa `lite`는 **캐시 전용** — "오늘 뉴스"에는 `auto` + `maxAgeHours`를 쓴다.
  - 현재 구현은 `type=auto` + `startPublishedDate`(24시간/7일/없음) + `userLocation=KR`을 보낸다. `lite`는 쓰지 않는다.
- Exa 응답에서 본문이 비어 있는 결과는 버린다(제목만 있는 항목은 근거가 되지 못한다).
- 검색은 **1메시지 최대 1회**(툴 콜링은 모델이 요청한 검색어, 최대 3개·중복 제거), 결과 3~8건, 결과당 1k~4k자.
  같은 질문은 검색·판정·`/answer` 모두 10분 캐시. 하루 한도에 닿아도 캐시는 먼저 쓴다.
- 검색 컨텍스트는 입력 예산의 1/3로 자르고, 실제 토큰이 400 예약을 넘으면 기록을 다시 맞춘다(작은 컨텍스트 모델 보호).
- **자동 판정은 모델 분류 호출 1회**(Y/N) — 검색을 켜 두면 질문마다 약 1~2초가 더 걸린다.
  판정 프롬프트에는 직전 사용자 질문(200자)만 넣는다. 실패·시간 초과는 "검색 안 함".
  판정은 **활성 프로바이더**가 한다. Local Apple FM이면 온디바이스(0.5~3.0초)이고,
  Apple FM 경로는 스트리밍이 없어 검색을 쓰면 답변이 한 번에 온다(실측 5건·8.8초·인용 4종).
- **판정 제한 시간은 프로바이더별**(`WebSearchQuery.classifierTimeout`, 2026-10-21):
  Apple FM **5초** / 원격 OpenAI 호환 **8초** / Ollama **20초**. 고정 4초일 때 원격·Ollama에서
  `오늘 서울 날씨`가 시간 초과 → **검색 안 함**(오답)이 됐다. 실패 로그에 원인 코드와 제한 시간을 남긴다.
- **Ollama 판정은 콜드 스타트가 13초**(모델 로드, `eval_count=2`)이고 워밍 후 0.4~1.0초이다.
  취소하면 로드가 중단되어 다음 답변도 다시 콜드가 된다 → 로컬은 로드를 기다린다(20초).
- **판정 일시 오류는 1회 재시도**(2026-10-21 실사용 대응): 429·5xx·네트워크·인증은 400ms 후 1회,
  시간 초과(`E-MAC-SEARCH-0004`)는 재시도하지 않는다. 두 번 실패하면 그때는 "검색 안 함".
  재시도해도 실패하는 경우를 위해 답변 문구가 "실시간 … 기능이 없습니다"류면 **[웹에서 찾기]**를 띄운다.
- **예비 AI 폴백**(2026-10-21, **실사용 확인**): 설정 › AI에서 예비 AI를 고르면 429·5xx·시간 초과·연결 실패에서 **1회만**
  다른 모델로 넘어간다(안내의 원인은 `ProviderFallback.reason` — 서버 코드 문자열은 노출하지 않는다). 403·첨부 거부·설정 오류는 넘어가지 않고, 다른 모델이 답하면 답변 위에 안내가 붙는다.
  기본값은 **사용 안 함**(구버전 설정과 동작 동일).
- **HTTP 429는 앱 결함이 아니라 프로바이더(프록시) 사용 제한**이다. 앱은 `E-MAC-NET-0004`로 표시하고
  검색 없이 답할 수 있다. 실측·QA를 같은 프록시로 돌리면 순간적으로 겹칠 수 있으니 사용자 사용 중에는 네트워크 하네스를 줄인다.
- **NSLog는 unified log(`/usr/bin/log show`)에 남지 않는다**(이 앱에서 확인). 사후 진단은 화면·`history.json`·QA 하네스 로그로 한다.
- 실측(2026-10-21 10:40, 원격): 판정 `오늘 서울 날씨` YES **1.2~1.7초**(혼잡 시 5.6초),
  `구구단` NO 1.5초. 검색 8건 6.4초. 검색→주입→스트리밍 922자·인용 4·델타 594·총 9.6초.
  툴 콜링 8건 16.3초. `/answer` 183자·인용 8건 2.6초. (이전 측정: `오늘 네이버 뉴스 IT 기사` 5건 2.2초)
- 네이버 검색 API는 2026-07-31부터 **NCP NAVER API HUB**로 이전. 기존 개발자센터 키는 2027-06-30까지.
- QA 렌더는 실제 설정을 저장하지 않지만, 데모 대화는 메모리에만 넣는다.
- **자동 정리 실측**: Apple FM 20턴 2,100→513토큰(6.6초), 원격 2,100→903토큰(3.5초). 10턴은 트리거되지 않음. 자가검증은 `suppressArchiveSaveForSelfTest`로 `history.json`을 건드리지 않는다.
  - 2026-10-21 10:40 재실측: Apple FM 20턴 2,160→**537**(7.1초, `expected=YES`), 원격 20턴 `expected=NO`(2,160토큰 < 기준 21,324).
  - **"20턴이면 자동 트리거"는 프로바이더 조건이 붙는다** — Apple FM(기준 ≈1,971)만 YES이고, 원격 기본(기준 ≈21,324)은 한참 못 미친다.
- **Apple FM 예산**: 4,096 전체 중 입력 2,816. 요약 800자·청크 1,500자, 최근 원문 4개. 요약은 프롬프트 앞에 고정한다(6턴 제한 회피).
- **요약 해제**는 `compactPaused=true`로 자동 정리를 멈춘다. 다음 요청은 전체 원문을 보낸다(사용자 선택). `clearEphemeral`·`reset`은 요약도 함께 비운다.
- 새 설정 필드는 반드시 `decodeIfPresent`로 기본값을 줘야 구버전 JSON이 깨지지 않는다.
  enum은 `QuickTalkSettings.decodeEnum`으로 **필드별 폴백** — 알 수 없는 값 하나가 설정 전체를 초기화하지 않게 한다.
- `memory.json`·`.corrupt`는 `0600`. 손상 파일은 덮어쓰지 말고 백업 후 빈 목록으로 시작한다.

## 10. 문서 지도

| 문서 | 역할 |
|---|---|
| `docs/HANDOFF.md` | **이 문서 — 새 세션 진입점·현재 상태** |
| `docs/TODO.md` | 작업 이력 + §지금(현재/다음) |
| `docs/DESIGN.md` | 구현 기준 디자인·구조 (§0 요약, §4~§11 현재) |
| `docs/CHANGELOG.md` | 날짜별 변경 이유·검증·배포 |
| `docs/QA-CHECKLIST-2026-10-20.md` | 사용자 실측 체크리스트 A~K |
| `docs/plans/PLAN_v0.15_memory_macos.md` | 자동 대화 기억 정리 설계·검증 (T-71 구현 완료) |
| `docs/plans/PLAN_v0.14_websearch_macos.md` | 웹 검색 설계 (P1~P3 + 툴 콜링·`/answer` 구현 완료) |
| `.agent/session-*.md` | 세션별 8줄 기록(로컬 전용) |
| `AGENTS.local.md` | 프로젝트 규칙(공통 가이드 변경점만) |
