# HANDOFF — QuickTalk (macOS)

> **새 세션은 이 문서부터 읽는다.** 마지막 갱신: 2026-11-11 KST
> **git 저장소 있음**(2026-10-21 20:12 초기화) — `origin https://github.com/BoraSarang/QuickTalk.git`, `main` 추적 중.
> T-21은 **PR #2 → squash merge `6d344cf`**로 `main`에 병합됐다. **`main` 직접 push 금지** — 다음 작업도 브랜치 → PR.
> **현재 작업 브랜치 `main`** — 2026-10-25 P1 3건 수정(되돌리기·헤더·프로세스 트리)은 **PR #35 → squash merge `e8319f8`**, 이어서 문서 PR **#36·#37·#38** 로 병합됐다. **`main` = 코드 `e8319f8` + 그 뒤 문서 커밋**(SHA 를 외우지 말고 `git log --oneline -1` 로 확인). 안전장치(치명적 명령 실행 전 차단)는 PR #13 → squash merge `53c23c4`, 단일 인스턴스 가드는 PR #10 → `5114e08`, 공용 메모리 기본 OFF 는 PR #15 → `998f787`, 🧠·카드 순서·`processes` 는 PR #16 → `9fdc9b9`, 대화 창 위치 조율은 PR #18 → `8313c56`, 캡션 단축키·배포 SHA 는 PR #20 → `0d2d817` 로 병합됐다. **2026-10-23 변경은 PR #27 → `54a82cd`(pill 본체·로그인 자동 시작), PR #29 → `f0e90bb`(pill 입력창 프레임·정렬) 로 병합됐다. 2026-10-25 변경(v0.19 WIP + 창 연결 + v0.20~v0.22)은 PR #33 → `f46ace8` 로 병합됐다. **2026-10-27 변경(10-26 권한 카드 + v0.23 웹 검색 루프 + v0.24 설정 재구성)은 PR #39 → squash merge `321fd7a` 로 병합됐다.**
> **사용자 맥 사용 중** — 앱 실행/종료·스크린샷·창 조회·소리 재생 금지. 코드·빌드·오프스크린 렌더·문서만.
>
> **2026-10-29 승인 폴더 기억(①)** 은 PR **#55 → `5589105`**, **Exa `/answer` 정리(②)** 는 PR **#58 → `c6f04a2`**, **Shortcuts 자동 전송(③)** 은 PR **#60 → `0fda8a4`**, **컴퓨터 제어 Phase 1(④)** 은 PR **#63 → `8bed1ef`** 로 병합됐다. **컴퓨터 제어 Phase 2 는 PR #66 → `cf5728b`**, **승인 단순화는 PR #70 → `43a4c42`**, **⌘Space 토글 수정은 PR #72 → `7802cfc`**, **User-Agent `QuickTalk/<버전>` 수정은 PR #75 → `5a616c6`**, 최신 빌드는 **2026-11-06 20:21 배포**(v0.32.2 리포트 제안·후속 질문 칩 스크롤 수정, 아래 인계 (10))**했다.

> **v0.35 구현·검증 완료** — 모델 카탈로그·캐시·상세 · 비서별 모델(대화+예약) · 퀵셀프 목차 아코디언(2동작) · 비서별 리포트 폴더 · 전환 성능 측정. PLAN `docs/plans/PLAN_v0.35_model-catalog-shelf_macos.md` §13, 인계 (13).
> **v0.35.3 병합·설치 완료** — LazyVStack 의 빈 화면 회귀를 **VStack + 최근 턴 윈도잉**으로 수정. **PR #130 → squash merge `91508f9`**. PLAN `docs/plans/PLAN_v0.35.3_chat-blank_macos.md`, 인계 (16).
> **v0.35.4 수정·설치·실측 완료** — 윈도잉 뒤 **목차 현재 위치가 늘 첫 질문**으로 보이던 회귀. clear→prune + `visibleIndex(minimumPosition:)`. **PR #132 → squash merge `d8c82d4`** · **사용자 실측 확인(2026-11-09)**. PLAN `docs/plans/PLAN_v0.35.4_outline-position_macos.md`, 인계 (17).
> **현재 설치본은 Debug 1.36.3**(2026-11-11 23:10, `~/Applications/QuickTalk.app`, PID 71206) — 실행 계획 카드(`propose_plan`). v0.35.3~v0.35.5·v0.36 P0~P1 상태는 아래 인계 참조.
> **v0.36 P0 구현·검증 완료(2026-11-11)** — 답변 아래 **[▶ 실행]** + 실행 턴(`Turn.executesTurnID`). **Debug 1.36.0 설치 · 실측 대기**. PLAN `docs/plans/PLAN_v0.36_execution-agent_macos.md`, 인계 (19).
> **v0.35.5 수정·실측·병합 완료** — ⌘Space **pill 입력창 붙여넣기(⌘V) + 이미지·파일 첨부**. 원인은 편집 단축키 판정 `isOwnWindow` 에 pill 패널이 빠진 것. **PR #135 → squash merge `050e024`** · **사용자 실측 확인(2026-11-11)**. PLAN `docs/plans/PLAN_v0.35.5_pill-paste_macos.md`, 인계 (18).
> **성능 측정은 `--switch-perf-live` 로 한다** — 합성 표본 + 레이아웃만 재는 `--switch-perf-test` 는 체감과 어긋난다(DESIGN §14.5).
> **버전 규칙(2026-11-08 확정)**: 표시 버전 = `1.<릴리스>.<핫픽스>` — `v0.35` = 앱 **`1.35.0`**(build 3500). `scripts/bump-version.sh <릴리스> [핫픽스]` 로 올린다(DESIGN §14.6).

### 2026-11-11 인계 (22) — v0.36.3 **실행 계획 카드 `propose_plan`** — **PR #144 병합 · Debug 1.36.3 설치 · 실측 대기**

- **계기(사용자)**: *"실행 하라는게 이렇게 힘든 일인가?? 어디까지 하는건가"* — [▶ 실행]을 누르면 무엇을 어디까지 할지 보이지 않은 채 시작됐다.
- **결정**: 계획은 **입이지 손**. 모델이 계획만 말하고 멈추고, 사용자가 [실행]을 눌러야 실행한다. v0.36 P1 사양(PLAN §4) 그대로.
- **Core**: `ExecutionPlan.swift` — `goal` 1줄 · `steps` **3~8**(넘치면 앞에서 자름·공백 제거) · `permissions`(읽기/쓰기/네트워크, 중복 제거) · `from(call:)` 파싱(형식 오류 nil) · `editableText`. `PlanTool.name = "propose_plan"`. `ExecutionPrompt.planVisibleText`·`planContract(_:alreadyRun:)`(v0.36.2 `alreadyRunBlock` 결합).
- **러너**: `propose_plan` 호출 시 **즉시 반환**(같은 스텝의 다른 도구도 실행하지 않음). 형식 오류면 tool 메시지로 되묻고 계속. `AgentRunResult.plan`.
- **도구**: `AgentToolCatalog.proposePlan` — `all` 에 포함, 비서 경로에서는 도구가 하나라도 켜져 있으면 append. `AgentInstructions` 에 "3단계 이상 작업은 시작 전에 계획하고 멈춘다" 규칙.
- **기록**: `Turn.plan: ExecutionPlan?`(옵셔널 — 구버전 nil), `ConversationStore.setPlan(_:to:)`, `UIStore+Agent` 가 결과의 plan 을 턴에 붙임.
- **UI**: `PlanCard.swift` — 권한 칩 · 목표 · 단계 체크 · [수정] [실행] · 실행 중 스피너 · 완료 시 전 단계 체크. `UIStore.executePlan`(→ `send(planOf:)`) · `editPlan`(draft + `composerFocusToken`) · `planRunState`(실행 턴 `.done` 개수로 **순차 추정**) · `shouldOfferPlan` · `planHasRun`. `shouldOfferExecute` 에 `turn.plan == nil` 추가.
- **주의(이번에 잡은 두 곳)**: ① 계획 실행 턴이 `beginAssistantTurn(executesTurnID:)` 에 `planOf` 를 넘기지 않으면 카드가 "이미 실행됨"을 몰라 [실행]이 계속 보인다. ② 사전 웹 검색 예외(`executionOf == nil`)에도 `planOf == nil` 이 필요하다. 둘 다 수정·머지됨.
- **이름 충돌**: `PolicyEngine.AgentPlan`(정책 판정 enum)이 이미 있어 새 모델은 **`ExecutionPlan`** 으로 지었다(파일도 `ExecutionPlan.swift`).
- **검증**: `swift test` **999/999**(6 skip, 신규 16 — 파싱·상한·권한·Codable 왕복/구버전·계약·`alreadyRun` 결합·**러너 중단·형식 오류 재요청**) · Debug/Release **BUILD SUCCEEDED · 경고 0** · `--qa-plan-routing` **PASS** · `--qa-execute-routing` **PASS** · 렌더 `docs/qa/v0.36.3-plan-card/`(한/영 × 제안·실행 중·완료) · 번역 8키.
- **PR/병합**: **PR #144 → squash merge `b5d6dc5`**.
- **버전/설치**: 1.36.3(build 3603) · **2026-11-11 23:10 Debug 1.36.3** 교체·재실행(PID 71206, `QuickTalk.debug.dylib` SHA-256 `a969e797…`).
- **실측 대기**: ① 3단계 이상 작업("사진 정리", "스크립트 만들어 실행")에서 **계획 카드**가 뜨는지 ② [실행]이 계획 단계만 수행하는지(새 조사·새 파일 없음) ③ [수정]이 입력창으로 가는지 ④ 실행 중 스피너 → 완료 체크 표시. 실패 시 `fix/v0.36.3-*`.
- **다음**: v0.37 스킬(PLAN §5) → v0.38 ego-browser.

### 2026-11-11 인계 (21) — v0.36.2 **[▶ 실행]이 처음부터 다시 하던 문제** — **PR #142 병합 · Debug 1.36.2 설치 · 실측 대기**

- **계기(사용자)**: *"추가한 실행하기 버튼 클릭 했더니.. 뭔가 처음부터 다시 하는 느낌이었는데"* / *"실행 하라는게. 이렇게 힘든일인가?? 어디까지 하는건가"*
- **실측(`run_test` + `agent-audit.log` + undo)**: 원래 제작 **2분 04초·도구 12회** → 첫 실행 **4분 26초·10회**, 같은 `memtop.py` 를 **3번 덮어씀**(22:13:44·22:14:04·22:15:00) 뒤 사용자 중단. 두 번째 실행은 **이미 결과 보고인 답변**에서 검증 6단계를 전부 반복(1분 41초·10회).
- **원인**: ① 계약이 "답변의 절차를 다시 수행" → 설명문·보고서에서는 전체 작업이 대상 ② `AgentRunner` 가 `turn.text` 만 넘겨 **모델이 과거 도구 기록을 받지 못함** ③ 실행 보고인 일반 답변에도 버튼이 붙음.
- **수정(A+B)**: 계약 **"아직 실행하지 않은 부분만"** — 이미 실행·확인한 단계 반복 금지 · 파일 새로 만들기/고치기 금지 · 단일 동작이면 단계 목록 생략 · 새 조사·검증 금지. `ExecutionPrompt.alreadyRunBlock` 로 실행 대상 답변의 `agentEvents` **최근 8개·명령 100자** 주입(성공·실패·거부만, 출력 제외). `UIStore.send(executionOf:)` 가 `agentEvents` 전달.
- **검증**: `swift test` **983/983**(6 skip, 신규 4) · Debug/Release **BUILD SUCCEEDED** · `--qa-execute-routing` **PASS**(`normal=1 hiddenResult=1 hiddenPersona=1`).
- **PR/병합**: **PR #142 → squash merge `5648cb2`**.
- **버전/설치**: 1.36.2(build 3602) · **2026-11-11 22:37 Debug 1.36.2** 교체·재실행(PID 65316, `QuickTalk.debug.dylib` SHA-256 `37be016cf59c9491a56844641fdd5ac88e24346d8991a10e372dad7d13eb3d74`).
- **실측 대기**: `run_test` 와 같은 답변에 [▶ 실행] — ① 파일 재생성 없음 ② 이미 한 검증 반복 없음 ③ 남은 실행만 수행. 실패 시 `fix/v0.36.2-*`.

### 2026-11-11 인계 (20) — v0.36.1 **"리포트 폴더" → 작업 폴더 (`~/Documents/QuickTalkWorkspace`)** — **PR #140 병합 · Debug 1.36.1 설치 · 실측 대기**

- **계기(사용자)**: *"QuickTalkReport 폴더는.. 뭐 이게.. 프로젝트 폴더처럼 사용하네.. 명명을 바꿔야 하지 않을까??"* / *"비서 없는 대화를 하고 있는데.. 여기다가 파일들을 만드네"*
- **진단**: `~/Documents/QuickTalkReport` 에 비서별 리포트 2개 + `memtop.py`·`__pycache__`·`_probe.txt`. `SystemKnowledge.text` 는 **비서가 없어도** `[리포트 폴더] 쓰기 가능한 경로:` 를 넣는다 — 이름은 리포트, 실제는 **도우미의 작업 공간**이었다.
- **결정(사용자)**: `~/Documents/QuickTalkWorkspace` · 기존 파일은 그대로 옮긴다.
- **구현**: `WorkspaceFolder`(신규 Core) — 기본 경로·옛 이름 판정·**1회 이전**. `Settings` 기본/폴백/디코드 기본값, `UIStore.init` 이전 실행, `SystemKnowledge` 문구, 설정 › 비서 라벨·캡션·**"이 비서만 다른 작업 폴더 사용"**, 오류 문구, 번역 6키.
- **이전 규칙**: 마지막 조각이 `QuickTalkReport` 일 때만. 새 폴더가 이미 있으면 **합치지 않는다**(설정 유지+로그). 옛 폴더가 없으면 설정만 변경. 사용자 지정·비슷한 이름은 건드리지 않는다.
- **검증**: `swift test` **979/979**(6 skip, 신규 7 `WorkspaceFolderTests`) · Debug/Release **BUILD SUCCEEDED** · 설정 렌더 `docs/qa/v0.36.1-workspace/` · **실기 이전 확인** — `~/Documents/QuickTalkWorkspace` 에 리포트·`memtop.py` 보존, `defaultReportFolder = ~/Documents/QuickTalkWorkspace`, 옛 폴더 재생성 없음.
- **PR/병합**: **PR #140 → squash merge `d6e64a2`**.
- **버전/설치**: 1.36.1(build 3601) · **2026-11-11 22:24 Debug 1.36.1** 교체·재실행(`~/Applications/QuickTalk.app`, PID 63264, `QuickTalk.debug.dylib` SHA-256 `c4f4b678f984d1e9bf5286d686a7b37ec4ffa50ab173e67091ef34e8e25f1e61`).
- **실측 대기**: ① 설정 › 비서에 **작업 폴더** · `~/Documents/QuickTalkWorkspace` 표시 ② 도우미가 만든 파일이 그 폴더에 쌓인다 ③ 옛 `QuickTalkReport` 가 다시 생기지 않는다.

### 2026-11-11 인계 (19) — v0.36 P0 **답변 → 실행 `[▶ 실행]`** — **Debug 1.36.0 설치 · 실측 대기**

- **계기(사용자)**: *"질문 답변도 좋지만 거의 이거 해줘. '이거 어떻게 하냐?'로 시작해서 '그거 해줘'로 끝나는 용도가 더 어울리네."*
- **결정 6개(사용자 확정)**: ① [실행]은 **모든 답변**(실행 결과 턴만 제외) ② 기록은 **같은 대화 + 작업 카드** ③ 스킬 기본값 **전역 Off · 비서 On** ④ 브라우저는 **스킬+shell 먼저** ⑤ **예약 실행의 쓰기·전송 금지** ⑥ 용어는 **"스킬"**. `edit_file`·`search`·코딩 프로필은 **v0.36.2 후보**로만 기록(지금 만들지 않음).
- **구현**:
  - `Sources/QuickTalkCore/ExecutionPrompt.swift`(신규) — 말풍선은 짧은 문장(`이 답변대로 실행해 주세요.`), 모델에는 **실행 계약**. 계약은 번역표를 거치지 않고 앱 표시 언어가 영어면 **영어 계약**.
  - `Turn.executesTurnID` + `isExecutionRequest`/`isExecutionResult` · `ConversationStore.submit(executesTurnID:)` · `beginAssistantTurn(executesTurnID:)` — **같은 대화**에 실행 출처가 남고 결과 답변에는 버튼을 다시 달지 않는다. 구버전 기록은 nil.
  - `UIStore.send(allowCommands:executionOf:)` — 실행 턴은 **draft·첨부를 보존**하고 사전 웹 검색 판정을 건너뛴다. `shouldOfferExecute`/`executeAnswer`.
  - `ContentView.answerFooter` — 보라색 **[▶ 실행]** 칩. 다른 액션(복사·읽어주기)과 달리 **호버와 무관하게** 보인다.
  - `--qa-execute-routing`(헤드리스) + `SingleInstance` 예외 등록.
- **안전**: **새 실행 경로를 만들지 않았다** — 기존 `AgentExecutor`·승인 카드·[중단]·되돌리기·샌드박스가 그대로 적용된다.
- **검증**: `swift test` **972/972**(6 skip, 신규 8 `ExecutionPromptTests`) · Debug/Release **BUILD SUCCEEDED** · `--qa-execute-routing` **PASS**(`normal=1 hiddenResult=1 hiddenPersona=1`) · 번역 누락 2건 보충.
- **버전/설치**: 1.36.0(build 3600) · `xcodegen generate` 뒤 `scripts/bump-version.sh 36 0` 로 복원 확인 · **2026-11-11 22:08 Debug 1.36.0** 교체·재실행 — `~/Applications/QuickTalk.app`, 백업 없음, `~/Applications/` 밖에서 `codesign --verify --strict --deep` 확인 → 기존 번들 삭제 → 한 번에 복사 · 설치본 `codesign` OK · `QuickTalk.debug.dylib` SHA-256 `d309642a46484f2ca2802a13b77e2df387b9481cd7fb6c125b29ae78c513133a` · **재실행 완료**(PID 60372).
- **실측 대기**: ① 일반 답변에 [▶ 실행]이 보인다 ② 눌러서 실제 실행·승인 카드·[중단]이 동작한다 ③ 실행 결과 답변에는 버튼이 없다 ④ 실행을 눌러도 입력창 draft·첨부가 남는다 ⑤ 도구를 끈 비서에서는 버튼이 없다.
- **다음**: 실측 통과 → v0.36.1 P1 실행 계획 카드(`propose_plan`) · v0.37 스킬 · v0.38 ego-browser.

### 2026-11-11 인계 (18) — v0.35.5 **⌘Space pill 붙여넣기(⌘V) + 이미지·파일 첨부** — **Debug 설치 · 사용자 실측 확인**

- **계기(사용자 지적)**: "pill 대화에서는 붙여 넣기가 안되는구나?" — ⌘Space pill 입력창에서 ⌘V 가 아무것도 넣지 않음.
- **원인**: 편집 단축키는 LSUIElement 앱의 메뉴 키 등가가 불안정해 **QuickTalk 창이 키일 때만** Carbon 임시 등록 + 로컬 키 모니터로 처리한다. `AppDelegate.isOwnWindow` 가 **대화 창·설정 창만** 화이트리스트로 두고 **포인터 pill 패널을 빠뜨렸다** → pill 이 key 가 되면 `syncEditShortcuts` 가 등록을 해제하고, 로컬 모니터도 pill 이벤트를 넘겼다.
- **수정**: `PointerPillController.pillWindow`(신설) + `isOwnWindow` 에 포함. pill 입력은 대화 창과 같은 `ChatInputField` 라 뷰 변경 없음.
- **첨부 동작(사용자 확정)**: pill 에 첨부 UI 를 만들지 않고, ⌘V 에 **이미지·파일**이 있으면 **⌘Return 처럼 대화 창을 열고 그 창에서 붙여넣은 것과 같게** 첨부한다(`PillOutcome.openChatWithAttachment`). draft 는 유지되고 첨부 확인·제거는 대화 창에서 한다. 판정은 읽기 전용 `UIStore.canPasteAttachment(from:)` — 웹 주소는 텍스트로 남긴다.
- **검증**: `swift test` **964/964**(6 skip) · Debug/Release **BUILD SUCCEEDED · 경고 0** · `--qa-paste-routing` **PASS**(web `canPaste=0 consumed=0` · file `1/1` · image `1/1`). 실키 ⌘V 는 합성 이벤트로 재현 불가(OS 라우팅) → **사용자 확인 필요**.
- **설치(사용자 승인)**: **2026-11-11** `~/Applications/QuickTalk.app` 를 **Debug 1.35.5(build 3505)** 로 교체(백업 없음, `~/Applications/` 밖에서 `codesign --verify --strict --deep` 확인 → 기존 번들 삭제 → 한 번에 복사) · 설치본 `codesign` OK · `QuickTalk.debug.dylib` SHA-256 `26bbbb94242def12b6590de8ec32bb270cce83973151dbad2098e9cd79ce5456` · **재실행 완료**(PID 51066).
- **실측(사용자 확인, 2026-11-11)**: "잘됨" — ① pill ⌘V 텍스트 ② pill ⌘V 이미지·파일(대화 창 열림+첨부, draft 유지) ③ pill ⌘C/⌘A ④ 대화 창 ⌘V 회귀 모두 정상.
- **PR/병합**: **PR #135 → squash merge `050e024`** (2026-11-11).
- **다음**: v0.36 후보를 실사용 피드백에서 선정.

### 2026-11-09 인계 (17) — v0.35.4 **대화 목차 현재 위치가 늘 첫 질문으로 보이던 문제** — **PR #132 병합 · Debug 1.35.4 설치 · 실측 확인 완료**

- **계기(사용자 신고)**: "대화 이동시 오른쪽 대화 북마크에서 위치가 해당 위치가 아니라 무조건 최상위 위치로 표시됨". v0.35.1 QA 캡처에서는 맨 아래에서 5번째 질문이 강조됐다 — **v0.35.3 윈도잉 뒤 생긴 회귀**.
- **원인(실측, `--outline-probe`)**: ① 대화 전환·창 폭 변경에서 `outlineOffsets = [:]` 로 비웠는데, `VStack` 은 좌표가 그대로면 **같은 Preference 값을 다시 올리지 않아** `onPreferenceChange` 가 다시 불리지 않았다(34턴: `known=1 → known=0`, 바닥인데 `current=0`). LazyVStack 은 스크롤할 때 행이 새로 만들어져 자동 재측정됐다. ② 창이 마지막 질문부터 시작하면 기준선(y=8)이 그 질문(y=62)보다 위라, "바로 위 질문" 추정이 **화면에 없는 질문**을 골랐다.
- **수정**: ① 측정값을 비우지 않고 **걸러 낸다** — 대화 전환은 현재 대화의 턴 ID, 폭 변경은 지금 그리는 턴만 남긴다(측정 도착 뒤 비우는 경쟁도 없음). ② Core `ConversationOutline.visibleIndex(..., minimumPosition:)` — 윈도 밖(그려진 첫 질문보다 앞선) 좌표는 보간·추정에서 제외하고 추정 하한을 윈도 시작으로 제한(`firstRenderedOutlinePosition`).
- **QA 하네스**: `--outline-probe`(headless, `--live-shot-all=` 과 함께 실행) — 400×560 오프스크린에서 열기·중간·위·아래·대화 전환마다 `[OUTLINE] offset/anchor/start/floor/known/current` 를 남긴다. `--expanded` 와 조합하면 전 턴을 그린 상태를 잰다.
- **검증**: `swift test` **964/964**(6 skip, 신규 2 `ConversationOutlineTests`) · Debug/Release **BUILD SUCCEEDED · 경고 0** · Release 34턴 `start=32`/`floor=16` → 위·중간·아래 모두 `current=16` · `--expanded` 17질문 위 `0`·중간 `11`·아래 `16` · 22턴 전환 `floor=6`/`9` · `--live-shot-all` 전 대화 `dist=0`·`ink>0` · 레일 캡처(`docs/qa/v0.35.4-outline/all-3-34t.png`)의 보라 막대가 **마지막 눈금**.
- **PR/병합**: 브랜치 `fix/v0.35.4-outline-position` → **PR #132 → squash merge `d8c82d4`**.
- **설치(사용자 승인)**: **2026-11-09 17:12** `~/Applications/QuickTalk.app` 를 **Debug 1.35.4(build 3504)** 로 교체(백업 없음, `~/Applications/` 밖에서 `codesign --verify --strict --deep` 확인 → 기존 번들 삭제 → 한 번에 복사) · 설치본 `codesign` OK · `QuickTalk.debug.dylib` SHA-256 `2a852beac15844bf074528529e0e1bafc0557084a9efe48a482ccabd2cbd4331`(31MB) · **재실행 완료**(PID 29761). Release 는 사용자가 명시적으로 요청할 때만.
- **한계(정직)**: 34턴 대화는 윈도잉 때문에 처음엔 마지막 교환만 그린다 — 목차는 그 교환의 질문(#17)을 가리키고, `이전 대화 N개 더 보기`로 펼치면 위쪽 질문으로 이동한다. "현재 질문"은 v0.32 정의 그대로 **화면 위쪽에 걸린 질문**이라, 아주 긴 답변의 맨 아래에서는 직전 질문이 강조될 수 있다.
- **실측(사용자 확인, 2026-11-09)**: "잘 되는 것 같음" — 대화 전환 후 목차 레일 표시가 실제 읽는 위치를 가리킨다. ① 레일 위치 ② 목차 패널 현재 행 ③ 위로 펼친 뒤 스크롤 추적 모두 이상 없음.
- **다음**: v0.36 후보를 실사용 피드백에서 선정. 문제가 생기면 `fix/v0.35.4-*` → PR.

### 2026-11-09 인계 (16) — v0.35.3 **긴 대화 빈 화면 수정 (VStack + 윈도잉)** — **PR #130 병합 · Debug 1.35.3 설치 완료 (실측 대기)**

- **계기**: v0.35.1(LazyVStack) 뒤 긴 대화를 열면 본문이 비어 보임. 헤더·입력독은 정상, 본문만 없음. 400폭에서 잘 재현(`docs/qa/v0.35.3-blank/live-narrow.png`).
- **원인(실측)**: LazyVStack 은 만들지 않은 행의 높이를 **추정**해 문서 끝 핀이 실제 내용 뒤 **빈 꼬리**에 착지(400폭 추정 8,233pt vs 실제 7,665pt, 34턴은 추정 238,590pt). `.defaultScrollAnchor(.bottom)` 도 같은 추정값.
- **수정**: 본문을 정확한 높이의 **`VStack`** 으로 되돌리고 **최근 턴만 글자 예산(기본 6,000자, 최소 질문+답변 2턴)만큼** 그린다(Core `ChatWindowing`). 오래된 턴은 본문 위 **`이전 대화 N개 더 보기`**(+6,000자)로 펼치고, 목차·검색 점프는 그 턴까지 예산을 늘린 뒤 이동(`revealTurnIfNeeded`). 다른 대화를 열면 예산은 기본값으로.
- **핀 보강**: 내용(대화·윈도·턴 수)이 바뀐 뒤 **첫 핀만** 뷰포트 픽셀을 검사해 실제 내용이 보이는지 확인하고, 높이가 안정될 때까지 다시 맞춘다. 스트리밍 핀에서는 캡처하지 않는다. `DispatchQueue.asyncAfter` 는 중첩 런루프에서 안 돌아 `RunLoop.main` 타이머(`afterMain`)로 교체.
- **QA 하네스**: `--live-shot=<폴더>`(최근 대화 3크기) · `--live-shot-all=<폴더>`(+`--rapid` 8회 전환 · `--top` 상단 · `--focus-old` 목차 점프 · `--expanded` 모든 턴). `SingleInstance` 예외 등록.
- **검증**: `swift test` **962/962**(6 skip, 신규 10 `ChatWindowingTests`) · Debug/Release **BUILD SUCCEEDED · 경고 0** · Release `--live-shot-all` 전 대화 `dist=0`·`ink>0` · `--rapid` `dist=0`·`ink=8735` · `--expanded` 34턴 38,085pt `dist=0` · `--focus-old` 7,579→38,085pt 확장·`offset=0`·`ink>0`.
- **성능(Release `--switch-perf-live`)**: 34턴 **cold 896ms / warm 742ms** · 22턴 578/650ms · 6턴 476/448ms · 4턴 164/250ms — v0.35.1 이전 3.8초에서 크게 줄었고 LazyVStack 시절(0.33~0.73초)과 비슷한 수준을 **빈 화면 없이** 달성.
- **주의**: 새 Core 파일 때문에 `xcodegen generate` 를 실행했다 — 이 명령이 `Info.plist` 버전을 `1.0/1` 로 되돌리므로 **generate 뒤에 `scripts/bump-version.sh 35 3`** 으로 복원해야 한다(이번에 1.35.3/3503 확인). `project.yml` 에 주석 추가.
- **한계(정직)**: 마지막 두 턴이 6,682자(큰 표)인 34턴 대화는 2턴만 그려도 레이아웃 ~330ms — 한 턴이 예산보다 크면 통째로 그리므로 행 내부 윈도잉 없이는 더 줄이기 어렵다. 오프스크린 캡처에서 머티리얼(도구 카드·시트)과 `이전 대화 더 보기` 캡슐이 **흰 블록**으로 나온다(캡처 한계, 실앱 무관). 실제 클릭·전환 체감은 사용자 실측 필요.
- **PR/병합**: 브랜치 `fix/v0.35.3-chat-blank`(`32b3b79` 코드 · `8a1f59b` 문서) → **PR #130 → squash merge `91508f9`**.
- **설치(사용자 승인)**: **2026-11-09 00:28** `~/Applications/QuickTalk.app` 를 **Debug 1.35.3(build 3503)** 로 교체(백업 없음, `~/Applications/` 밖에서 `codesign --verify --strict --deep` 확인 → 기존 번들 삭제 → 한 번에 복사) · 설치본 `codesign` OK · `QuickTalk.debug.dylib` SHA-256 `dc7822384266c8838010038e32b976d39eeb59a57abd016334bbc170352da987`(31MB) · **재실행 완료**(PID 56859). Release 는 사용자가 명시적으로 요청할 때만.
- **실측 대기**: ① 긴 대화(34턴) 열기 — 빈 화면 없음 ② 위로 스크롤 → `이전 대화 N개 더 보기` 클릭 시 읽던 위치 유지 ③ 목차 레일·검색에서 오래된 질문 점프 ④ 대화 전환 체감(2~4초 → 1초 이내).
- **다음**: 실측에서 문제가 나오면 `fix/v0.35.3-*` 브랜치 → PR. 문제 없으면 v0.36 후보로.

### 2026-11-08 인계 (15) — v0.35.2 **URL 붙여넣기 수정** — **PR #128 병합 · 1.35.2 배포 완료**

- **계기(사용자 지적)**: 브라우저 주소(YouTube URL)를 대화 입력창에 붙여넣을 수 없다.
- **원인(실측)**: 주소창 복사 → 클립보드에 `public.url` + 텍스트. `readObjects(forClasses: [NSURL.self])` 가 **웹 주소를 NSURL 로** 돌려준다(`count = 1`, `isFileURL = false`). ⌘V 처리 `UIStore.pasteAttachmentFromPasteboard` 가 이를 파일로 오인 → `lastPathComponent = watch` → "지원하지 않는 형식" 안내 후 `return true` 로 **붙여넣기를 삼켰다**.
- **수정**: Core `PasteRouting.fileURLs(from:)`(신규) — `file://` 만 첨부 후보. 웹 주소는 `false` 로 내려 AppKit 기본 붙여넣기가 **URL 텍스트**를 넣는다. 파일 첨부 동작은 변경 없음.
- **주의**: 새 Core 파일은 **`xcodegen generate`** 로 프로젝트에 넣어야 한다(이번에 실행, pbxproj 재생성됨 — 이전 수동 ID 항목들이 xcodegen ID 로 정리됨, 빌드·테스트로 확인).
- **검증**: `--qa-paste-routing`(신규) → `web parsed=1 consumed=0 attachments=0` · `file consumed=1 attachments=1` · **PASS** · `swift test` **952/952**(6 skip, 신규 5 — `PasteRoutingTests`) · Debug/Release **BUILD SUCCEEDED · 경고 0**.
- **버전**: `1.35.2`(build 3502) — `scripts/bump-version.sh 35 2`.
- **PR/배포**: **PR #128 → squash merge `fc3f744`** · **2026-11-08 21:54** Release **1.35.2**(build 3502) 교체(백업 없음) · codesign OK · SHA-256 `ed4f57ac…` · **재실행 PID 30020**.
- **다음**: 사용자가 ⌘V 로 URL 붙여넣기 확인 · 이미지/파일 첨부 유지 확인.

### 2026-11-08 인계 (14) — v0.35.1 **대화 전환 3.8초 → 0.3~0.7초 (LazyVStack)** — **PR #126 병합 · 배포 완료**

- **계기(사용자 지적)**: 1.35.0 Release 배포 후에도 "대화 이동시 2~4초 .. 동일한 증상이다. 전혀 개선되지 않았다". **사용자가 맞았다.**
- **측정 오류 인정**: v0.35 의 "실제형 10턴 294ms" 는 **합성 표본 + 레이아웃만** 잰 값(그리기·실제 길이 미반영). 새 하네스 `--switch-perf-live` 가 실제 `history.json` 을 읽고 `cacheDisplay` 로 그리기까지 강제한다. 재측정 = **34턴/33,424자 3,798ms**(레이아웃 1,591 · 그리기 364 · 런루프 1,843), 22턴 1,185ms, 4턴 248ms.
- **원인**: `VStack` 이 화면 밖 턴까지 **전부** 레이아웃·그리기 → 대화 길이에 거의 선형.
- **수정**: 본문 `VStack` → **`LazyVStack`** (`ContentView.chatTab`). 결과 34턴 **0.33~0.73초**(3회 측정 · 레이아웃 0.07~0.14초), 22턴 0.12~0.21초.
- **목차 회귀 방지**: 화면 밖 턴은 y 좌표가 측정되지 않는다 → `outlineOffsets` 를 **병합**(덮어쓰지 않음), Core `ConversationOutline.visibleIndex`(신규)가 측정값 사이를 선형 보간하고 맨 아래에서는 위로 추정. 창 폭 변경 시 좌표 초기화. 단위 테스트 4개.
- **검증**: 34턴 맨 아래 고정 `distance=0.0` · `--qa-followup-scroll` 칩 삽입 후에도 `distance=0.0` · 목차 렌더 `docs/qa/v0.35.1-switch/`(상단=첫 질문 / 바닥=4번째 질문 강조) · `swift test` **947/947**(6 skip) · Debug/Release **BUILD SUCCEEDED · 경고 0**.
- **버전**: `1.35.1`(build 3501) — `scripts/bump-version.sh 35 1`.
- **PR/배포**: **PR #126 → squash merge `ac88af5`** · **2026-11-08 21:38** Release **1.35.1**(build 3501) 로 `~/Applications/QuickTalk.app` 교체(백업 없음) · codesign OK · SHA-256 `331e9789…` · **재실행 PID 26877**.
- **다음**: 사용자가 34턴 대화 전환 체감 확인 · 목차 현재 위치(스크롤·점프) · 맨 아래 고정 · 검색 점프. 남으면 후속 후보: 스크롤 중 LazyVStack 생성 비용, `.textSelection` 비용.

### 2026-11-08 인계 (13) — v0.35 모델 카탈로그 · 비서별 모델 · 퀵셀프 목차 · 비서별 리포트 **병합 완료** (실측 대기)

- **브랜치/PR**: `feat/v0.35-model-catalog` — v0.33(PR #120 → `249e1f2`)·v0.34(PR #121 → `778a75a`) 병합 후 rebase → **PR #122 → squash merge `a1b3776`**. **`main` 직접 push 금지** 유지.
- **PLAN**: `docs/plans/PLAN_v0.35_model-catalog-shelf_macos.md` §13 에 구현 결과·측정값·남은 일을 기록. P4·P5·P6 는 같은 화면/파일을 건드려 **한 브랜치로 통합**했다.
- **모델 카탈로그**: Core `ModelCatalog` — `/v1/models` ID + `models.dev` 병합(`opencode` 우선 → 상세 점수 최고), **24h TTL**, baseURL 변경 무효화, 실패 시 마지막 캐시. `QuickTalkSettings.modelCatalogAutoUpdate`(기본 켜짐). 앱 실행 시 캐시를 즉시 읽고 만료일 때만 백그라운드 갱신 — 목록을 열 때 네트워크를 기다리지 않는다. `models.dev` 는 **User-Agent 없으면 403**.
- **모델 피커/상세**: `ProviderEditorSheet` 검색 + 컨텍스트·출력·입력 형식·도구·추론·무료 배지, `MenuBarHubView` 모델 카드, 설정 › AI `모델 정보`(마지막 갱신·[지금 새로 고침]).
- **비서별 모델**: Core `ProviderResolver` — 대화·압축·후속 질문·메모리 상태·예약 실행이 **같은 해석**. 꺼진/없는 프로바이더면 **활성 AI로 폴백**(모델만 덮어쓰지 않음) + 에디터 경고.
- **비서별 리포트 폴더**: Core `PersonaReports` — `reportFolder` 우선, 없으면 `리포트 루트/<비서 이름>`, 동명은 `-<ID4>`. **기존 파일 자동 이동 없음**.
- **퀵셀프 목차**: 대화 행 아래 인라인 아코디언(한 번에 하나) · 셸프를 열면 지금 대화 자동 펼침 · `목차 N` 은 전환 없이 펼치기만 · 질문 클릭 = 활성화+포커스+닫힘(2동작).
- **성능(Release, `--switch-perf-test`)**: 실제형 10턴 **cold 243ms / warm 294ms** — PLAN 목표(≤300ms) **충족**. 스트레스 8턴(섹션 18개) 578~775ms. 레이아웃 ~395ms·런루프 170~560ms, 마크다운 파싱 0.1~0.5ms·디코드 직접 6.1ms→캐시 0.3ms·모델 갱신 0.1ms → **병목은 SwiftUI 텍스트 레이아웃**. 목차 레일을 꺼도 레이아웃 동일(레일 원인 아님). `LazyVStack` 은 목차 좌표·스크롤 복원 위험으로 **보류**(근거만 기록).
- **검증(오프스크린)**: `swift test` **931/931**(6 skip, 신규 21) · Debug/Release **BUILD SUCCEEDED · 경고 0** · QA 렌더 `provider-model`·`hub-model`·`shelf-outline-{expanded,lower,collapsed}`·`persona-folder-{shared,default}`·`settings-ai` 확인.
- **한계(정직)**: 전환 시간은 **합성 표본**이다(실사용 11턴 = 실제형에 가깝다). 스트레스 표본은 목표를 넘지만 실제 답변보다 훨씬 긴 문서다. 설치본은 아직 **v0.33 Debug** — Release 수치가 배포 후 체감으로 확인돼야 한다.
- **실측 대기**: ① 모델 목록이 캐시로 즉시 뜨고 ⟳ 없이 상세가 보이는지 ② 비서 모델을 코딩 모델로 고정하고 대화·예약 실행에 적용되는지(꺼진 프로바이더 폴백 포함) ③ 퀵셀프에서 다른 대화 목차 펼침 → 질문 클릭 2동작 이동 ④ 비서 3명 리포트가 각자 폴더에 쌓이고 루트에 섞이지 않는지 ⑤ 설치본 교체 후 전환 체감.
- **배포**: **2026-11-08 20:25** `~/Applications/QuickTalk.app` 를 **Release 1.35.0(build 3500)** 로 교체(백업 없음, 기존 번들 삭제 → 한 번에 이동) · `codesign --verify --strict --deep` OK · SHA-256 `ef72ecb3440a04694e08764c26705f065eedd5d884fd32f0bee8640d71e8a69d`(41MB) · **재실행 완료**(PID 18367).
- **다음**: 실측 5건 → 문제가 있으면 `fix/v0.35-*` 브랜치 → PR.

### 2026-11-08 인계 (12) — v0.34 도우미의 앱 데이터 접근 차단 (`AppDataGuard`)

- **브랜치**: `fix/v0.34-agent-appdata-guard` — v0.33 병합 후 `main` 위로 rebase 완료. **`main` 직접 push 금지** 유지.
- **계기(사용자 지적)**: "대화가 섞여 보인다 · 🧠가 매번 켜져 있다". ① 🧠는 `globalMemoryEnabled` 한 값(당시 `true` → 사용자가 `false` 로 끔) — 헤더 🧠 클릭이 전역 OFF 일 때 **전역을 켜는** UX 함정이 있었다. ② 실제 대화 간 간섭 경로는 **모델이 셸로 `history.json` 을 읽은 것**(`~/Library/Application Support/QuickTalk/agent-audit.log` 2026-11-05 12:16–12:17Z, read_file/shell 7회, 권한은 read/execute `alwaysAllow`).
- **구현**: Core `AppDataGuard.swift`(신설) — 보호 대상 `~/Library/Application Support/QuickTalk/**`(history·memory·schedules·secrets·audit) + `~/Library/Preferences/com.borasarang.QuickTalk.plist`. `~`·`$HOME`·이스케이프 공백 정규화, `QuickTalkReport` 같은 이름 겹침 폴더는 **경계 검사**로 제외. `AgentExecutor.runShell` 은 `PolicyEngine.plan` 결과를 `AppDataGuard.guardedPlan` 으로 통과시켜 `.allow` → `.ask` 승격(기존 `.ask` 는 사유만 교체, `.deny` 는 유지). `read_file`·`list_dir` 는 보호 경로면 정책과 무관하게 승인 카드. `AgentApprovalRequest.allowsAlwaysAllow`(기본 true) 신설 → `AgentCard` 가 보호 요청의 **[항상 허용] 버튼을 숨기고**, 실행기는 보호 명령의 `alwaysAllow` 규칙을 저장하지 않는다. 설정 › 도구·권한에 안내 1줄, 한/영 4키.
- **검증(오프스크린)**: `swift test` **910/910**(6 skip, 신규 17 — `AppDataGuardTests`: 보호 경로·`~`·plist·형제 폴더 오탐·셸/`defaults` 탐지·정책 승격·`.ask`/`.deny` 보존·전역 자동 수락에서도 승격) · Debug clean/Release `xcodebuild` **BUILD SUCCEEDED · 경고 0**.
- **한계(정직)**: 셸 명령 문자열에 경로가 **드러난 경우만** 잡는다. 변수 조합·난독화·`find ~ -name history.json` 같은 우회는 막지 못한다(자동 허용 차단용 **최소 가드**). 필요하면 다음 단계에서 셸 프로세스 자체의 파일 접근(sandbox-exec 프로파일)으로 넓힌다.
- **실측 대기**: 앱 배포 후 ① 보호 경로 읽기 요청 → 승인 카드에 "저장 데이터" 사유 표시 · ② 카드에 **[항상 허용] 없음** · ③ 거부 시 읽지 않음 · ④ 일반 경로 읽기는 예전처럼 자동 통과(회귀 없음).
- **다음**: PR → squash merge → Release 재배포(**사용자 확인 후**, 백업 없음).

### 2026-11-08 인계 (11) — v0.33 **⌘Space pill = 쌩 새 대화 · 답변 파일/폴더 열기 · 코드 블록 복사** **병합 완료** (실측 대기)

- **브랜치/PR**: `feat/v0.33-fresh-pill-file-links` (기준 `main` = `b5288a6`) → **PR #120 → squash merge `249e1f2`**. **`main` 직접 push 금지** 유지.
- **0) pill = 새 대화(사용자 확정)**: *"pill 대화가 나왔다는 것은 그냥 새로운 대화 … 그 전꺼 무시"*. 기존에는 pill 을 열어도 제출 시 `startShortcutSession()` 이 **다시 세션 시간을 검사**했고, pill 에서 비서를 고르면 `store.selectPersona` 가 **지난 대화의 `updatedAt` 을 갱신**해 "새 대화" 판정이 "이어서"로 뒤집혔다(v0.30 `reapplyPersonaIfNeeded` 회귀). 수정 — `UIStore.newFreshConversation(personaID:)` 신설: `defaultPersonaID` 를 **적용하지 않고**, pill 에서 직접 고른 비서만 새 대화에 넣는다. `QuickTalkApp.handlePill` 의 `.send`/`.openChat` 은 항상 이 경로를 쓴다. pill 은 열릴 때마다 `model.persona = nil` 로 **초기 상태**를 보여 주고(`present()`), 선택은 `PointerPillController.selectedPersonaID` 에만 담아 두었다가 새 대화에 적용한다. `reapplyPersonaIfNeeded` 삭제. `.resume(대화)` 는 사용자가 목록에서 고른 명시적 이어가기라 예외.
- **파일·폴더 열기**: 답변의 **존재하는 로컬 경로만** 클릭 링크가 된다 — Core `LocalFileLinks`(순수·신규). 절대 경로(`/…`·`~/…`)는 파일/폴더 모두 링크, **파일명만 나열**된 경우 같은 답변에서 먼저 언급된 폴더(또는 `fileDirectories` = 지금 비서의 리포트 폴더) 기준으로 찾는다. 코드 펜스·인라인 코드·기존 마크다운 링크·웹 URL 은 건드리지 않는다. 인라인 코드 안 경로는 **모노 글꼴 그대로** `MarkdownText.styled` 에서 링크로 만든다. 클릭은 `OpenURLAction` 이 `LocalFileOpen` 으로 넘겨 **폴더 = 파인더 · 파일 = 기본 앱**. `.app`·`.sh`·`.command`·`.pkg`·`.dmg`·`.terminal`·실행 권한 파일은 **NSAlert 확인** 후 연다.
- **코드 블록 복사**: `CodeBlockView`(신규) — 언어 라벨 오른쪽에 **복사 버튼**, 누르면 블록 내용만 `NSPasteboard` 로 복사하고 1.4초 동안 `복사됨` 으로 바뀐다. 버튼은 호버 시 배경이 진해지고 `이 코드 블록을 클립보드에 복사` 도움말·접근성 라벨이 붙는다.
- **검증(오프스크린)**: `swift test` **905/905**(6 skip, 신규 12 — `LocalFileLinksTests`: 절대 파일/폴더·없는 경로·폴더 기준 파일명·추가 폴더·코드 펜스·인라인 코드·기존 링크·웹 URL·문장 끝 점·인라인 해석) · 번역 커버리지 통과(신규 3키) · Debug/Release `xcodebuild` **BUILD SUCCEEDED · 경고 0** · 렌더 `docs/qa/v0.33-file-links/markdown-{ko,en}.png`(파일 링크 밑줄·코드 블록 복사 버튼 한/영·다크/라이트).
- **한계(정직)**: 파일 링크는 **렌더 시점에 존재하는 경로만** 링크한다(답변 뒤 파일이 지워지면 눌러도 무반응·beep). 공백이 포함된 절대 경로는 첫 공백에서 끊겨 링크되지 않는다(현재 답변 예시 기준). 실제 클릭·NSAlert·파인더 열기는 오프스크린에서 확인할 수 없어 **사용자 실측 필요**.
- **실측 대기**: P1) ⌘Space pill → 비서 없이 Enter = **새 대화** · P2) pill 에서 비서 선택 후 Enter = 새 대화에 **그 비서만** 적용 · P3) pill 열기 전 대화의 비서가 pill 에 **체크되어 보이지 않음** · F1) 리포트 폴더 경로 클릭 = 파인더 · F2) 파일명 클릭 = 열림 · F3) `.command`/`.app` 클릭 = 확인 창 · C1) 코드 블록 `복사` = 클립보드에 블록만.
- **테스트 배포(Debug)**: **2026-11-08 13:16** `~/Applications/QuickTalk.app` 교체(**백업 없음**) — 사용자 요청에 따라 **Debug 빌드**(`~/Library/Developer/Xcode/DerivedData/QuickTalk-…/Build/Products/Debug/QuickTalk.app`, 13:14)로 설치. `codesign --verify --strict --deep` OK · SHA-256 `02421af8082cc4f34f0fdfee232e9b9311022f661d3d5f2009c3e2512f8ce548`(바이너리). Release 는 최종 배포 때만 사용.
- **다음**: 설치본(Debug)으로 실측 P1~P3·F1~F3·C1. 최종 Release 배포는 사용자가 명시적으로 요청할 때만.

### 2026-11-06 인계 (10) — v0.32.2 **비서 없는 대화의 리포트 제안 · 후속 질문 칩 스크롤** **병합·배포 완료** (실측 대기)

- **브랜치/PR**: `fix/v0.32.2-report-scroll` (기준 `main` = `506e73a`) → **PR #118 → squash merge `820c93c`**. **`main` 직접 push 금지** 유지. `main` clean.
- **리포트 제안(사용자 지적)**: v0.29부터 `UIStore.send` 가 **모든 요청** 앞에 `[리포트 폴더] 쓰기 가능한 경로: ~/Documents/QuickTalkReport` 를 붙여, 비서가 없어도 모델이 "표로 정리해 파일로 남길까요?"를 먼저 제안했다. `SystemKnowledge.reportFolderPrompt`(신설)는 **비서가 있을 때만** 블록을 반환하고, 블록에 "사용자가 요청하기 전에는 먼저 저장을 제안하지 않는다"를 넣었다. 도구(에이전트) 경로는 기존 시스템 프롬프트가 계속 담당.
- **후속 질문 칩 스크롤(사용자 지적)**: 답변 종료 뒤 칩이 **나중에** 붙을 때 문서 높이는 1425→1539pt(+114)로 늘지만 오프셋이 956.5에 머물러 칩이 뷰포트 아래에 잘렸다. 스크롤 알림 **안에서** 바꾼 `@State` 토큰이 다음 SwiftUI 업데이트까지 묶여 핀 요청이 유실된 것이 원인 — `pinBottom()` 이 `.quickTalkPinChatBottom` 알림으로 `ScrollOffsetObserver` 를 직접 깨워 즉시 재핀하고, `.onChange(followUpToken)` 으로 칩 생성도 따라가기 트리거에 넣었다(위로 읽는 중이면 유지).
- **검증(오프스크린)**: `swift test` **893/893**(6 skip, 신규 2 — 비서 없음/있음 리포트 블록) · Debug/Release **BUILD SUCCEEDED · 경고 0** · QA `--qa-followup-scroll` 실측 — before `distance=0` → 칩 삽입 → after **`offset=1070.5=max`, `distance=0`** · 사고 중 `distance=0` · 스냅샷 `docs/qa/v0.32-outline-followups/v0322-scroll-*.png`.
- **배포**: **2026-11-06 20:21** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음**) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · 설치본 SHA-256 `995497b47515db283627ebc022765ccc5b2a1eb511ced8f01d4c85a0bb472341`(40MB) · **재실행 완료**(PID 21743, 20:21) · 배포본 바이너리로 QA 재실행해 `distance=0` 재확인.
- **실측 대기**: 비서 없는 대화에서 비교 답변을 받아 **파일 저장 제안이 없는지** · 답변 뒤 후속 질문 칩이 **자동으로 보이는지** · 사고 중 하단이 잘리지 않는지 · 위로 올려 읽는 중에는 칩이 나타나도 납치하지 않는지.
- **다음**: 문제가 남으면 `fix/v0.32-*` 브랜치 → PR → squash merge → Release 재배포(백업 없음).

### 2026-11-06 인계 (9) — v0.32.1 **목차 레일·`⋯` 겹침 · 바로가기 후 스크롤 바닥 튐** **병합·배포 완료** (실측 대기)

- **브랜치/PR**: `fix/v0.32-outline-scroll` (기준 `main` = `9f01e9b`) → **PR #116 → squash merge `d92d78e`**. **`main` 직접 push 금지** 유지. `main` clean.
- **겹침(사용자 지적)**: 목차 레일이 질문 `⋯` 툴팁을 덮었다. 본문 오른쪽 여백 **14 → 30pt**(레일 6+22pt+2pt)로 늘려 `⋯`(오른쪽 끝 34pt)와 레일 사이 **6pt**, 답변 글자와 레일 사이 2pt. QA `hoverTurnIndex` 로 두 번째 질문 호버 렌더(`live-outline-hover-{ko,en}.png`).
- **스크롤 튐(사용자 지적)**: 목차 바로가기(`focusTurn`) 뒤 스크롤을 내리면 가끔 맨 아래로 튀었다. 원인 2가지 — ㉠ 점프 직후 `followsBottom` 이 true 로 남아 중간 스크롤을 "내용 증가"로 오판해 `handleScrollDistance` 가 `pinBottom()` 호출, ㉡ 점프 중 레이아웃 확정 전 `distance=0` 보고가 `atBottom` 을 true 로 만들어 따라가기를 재개.
- **수정**: Core `FollowScrollPolicy`(순수 판정, 신규) — 점프 시작 시 따라가기 OFF + **1.0초 자동 핀·재개 억제**, 사용자가 직접 바닥(24pt)에 닿았을 때만 재개, 0.25초 재고정 쿨다운 유지. `jumpToBottom()` 은 억제 해제(명시적 이동), `focusTurn` 의 늦은 `scrollTo` 재시도(0.12·0.28초)는 `focusedTurn` 확인으로 이전 요청을 폐기.
- **검증(오프스크린)**: `swift test` **891/891**(6 skip, 신규 8 — `FollowScrollPolicyTests`: 점프 후 하향 스크롤 무핀 · 점프 중 일시적 `distance=0` 이 따라가기를 되살리지 않음 · 바닥 도달 시 재개 · 스트리밍 핀 · 위로 스크롤 중지 · 0.25초 쿨다운 · 억제 중 위로 스크롤 · 점프 시작 상태) · Debug/Release **BUILD SUCCEEDED · 경고 0** · `--demo-outline-live` 렌더가 수정 전과 **바이트 동일**(레이아웃 회귀 없음).
- **한계(정직)**: 실제 트랙패드 스크롤 튐은 오프스크린에서 재현되지 않는다(타이밍 의존) — 메커니즘을 Core 단위 테스트로 고정했고, 사용자 실측(Q11)로 확인 필요. `--session-test` 는 실행 중 앱의 단일 인스턴스 잠금(`E-MAC-APP-0001`)으로 이번에도 미실행.
- **배포**: **2026-11-06 19:14** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 복사, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · 설치본 SHA-256 `26d345f8f9a696351aa47892060c1e3daa6bbbf99fd413042ccc03455c8a730d`(40MB) · 바이너리에 `FollowScrollPolicy` 심볼 포함 · **앱 재실행 필요**(실행 중 PID 11001 은 18:55 빌드).
- **실측 대기**: QA README §3 Q1~Q11 · F1~F9 · S1~S6 — 특히 **Q4**(항목 이동) 후 **Q11**(위·아래 스크롤 시 바닥으로 튀지 않음)과 Q2(레일·`⋯` 간격).
- **다음**: 앱 완전 종료 → 재실행 → Q11 재현 시도(바로가기 → 스크롤 여러 번). 남으면 `fix/v0.32-*` 브랜치로 추가 수정.

### 2026-11-06 인계 (8) — v0.32 **대화 목차 · 후속 질문 제안** **병합·배포 완료** (실측 대기)

- **브랜치/PR**: `feat/v0.32-outline-followups` (기준 `main` = `f0bb00f`) → **PR #114 → squash merge `a8c641d`**. **`main` 직접 push 금지** 유지. `main` clean.
- **승인 설계**: ① 목차 = **레일 + 셸프 보조(둘 다)** ② 후속 질문 = **모델 생성 + 무료 폴백** ③ 칩 클릭 = **즉시 전송**. 계획 `docs/plans/PLAN_v0.32_outline-followups_macos.md`.
- **목차(Core `ConversationOutline`)**: 사용자 질문만 `OutlineEntry(index, preview 40자)` 로. 현재 위치는 **화면 위쪽 기준선(절대 offsetY+8) 위의 마지막 질문**. 질문 3개 이상일 때만 레일, 8개 이상이면 검색.
- **목차(App `ChatOutlineView`)**: 폭 22pt 눈금 레일(질문 18개 초과 시 균등 샘플링, 현재 눈금은 4×12 보라 막대). 호버 **0.35초**/클릭으로 패널, 클릭은 고정, Esc·접기(›)·항목 선택으로 닫힘. 패널 **오버레이**(리플로우 없음), 폭 `min(216, max(170, w×0.55))`·높이 `min(300, max(150, h−120))`, 현재 질문 중심 자동 스크롤. 항목 선택은 기존 `focusTurn` 재사용(3회 스크롤 + 테두리 깜빡임).
- **목차 좌표**: `ContentView` 가 질문 턴마다 **내용 좌표** y 를 `OutlineOffsetKey` 로 모으고, `ScrollOffsetObserver` 에 `onOffset` 콜백을 추가해 절대 스크롤 값을 받는다. 대화를 바꾸면 측정값을 비운다. 목차를 켜면 질문 수와 무관하게 본문 오른쪽 여백 **30pt** 를 유지한다(레일 6+22pt + 2pt 여유) — 세 번째 질문에서 글자 폭이 갑자기 바뀌지 않고, 질문 `⋯`(오른쪽 끝 34pt)와 레일이 겹치지 않는다.
- **후속 질문(Core `FollowUpSuggest` + `UIStore+FollowUp`)**: 정상 종료 + 답변 80자 이상 + 오류·중단 아님 → 2.5초 뒤 모델 1회(질문 600자/답변 500자, 8초 타임아웃·취소), 실패·빈 응답이면 무료 문구 3개. 무료 문구 모드는 즉시. 새 전송·중지·대화 전환 시 작업·칩 취소. 상태는 `ChatSession.followUpStates[턴 ID]` 로 **대화방별** 분리. 칩 클릭은 `followUpAutoSend` 에 따라 즉시 전송 또는 입력창 채움.
- **QuickShelf**: 대화 탭 상단 접이식 `이 대화 목차`(최근 6개 + `… 외 n개`) — 점프 시 `store.searchFocus` 설정 + 셸프 닫기 + 새 알림 `.quickTalkOpenChat`(창이 닫혀 있을 때만 대화 탭 열기). 기존 `.quickTalkShowChat` 은 맨 아래로 스크롤해 충돌하므로 쓰지 않는다.
- **설정 › 대화**: `outlineDisplay`(기본 **`.both`**) · `outlineShowPosition`(true) · `followUpsEnabled`(true) · `followUpSource`(model) · `followUpAutoSend`(true). 레일 미사용 시 위치 토글 숨김. 한/영 37키.
- **검증(오프스크린)**: `swift test` **883/883**(6 skip, 신규 29 — 목차 10·후속 13·설정 6) · Debug `xcodebuild` **BUILD SUCCEEDED · 경고 0** · 실제 화면 렌더 `docs/qa/v0.32-outline-followups/live-{rail,panel,panel-bottom,narrow,followups,shelf-outline,settings-conversation}-{ko,en}.png` — 400×560/380×420, 바닥에서 펼친 목차, 한/영·다크/라이트 확인.
- **한계(정직)**: `--session-test` 는 **실행 중 QuickTalk 인스턴스의 단일 인스턴스 잠금**(`E-MAC-APP-0001`) 때문에 이번 세션에서 미실행 — v0.31 에서 PASS 한 경로를 건드리지 않았고 `swift test` 로 대체 확인. 사용자가 앱을 종료한 뒤 실행하면 재확인 가능.
- **배포**: **2026-11-06 18:55** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 이동, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · 설치본 SHA-256 `973a6d22216af5ea3c82b998544e3e16b45f351a0bb85054090e3295c55ba089`(40MB) · 바이너리에 `이 대화 목차`·`이어서 물어보기` 포함 확인 · **앱 재실행 필요**(실행 중 PID 67776 은 이전 빌드).
- **실측 대기**: QA README §3 Q1~Q10 · F1~F9 · S1~S6.
- **다음**: 앱 재실행 → 실측 Q1~Q10 · F1~F9 · S1~S6. 문제가 있으면 `fix/v0.32-*` 브랜치로 수정 → PR.

### 2026-11-06 인계 (7) — v0.31 **타임라인 · 사고 과정 표시 설정 · `⋯` 클릭 · 다중 대화 6a/6b** **병합·배포 완료** (실측 대기)

- **브랜치/PR**: `feat/v0.31-timeline` (기준 `main` = `136428e`) → **PR #107 → squash merge `c678ade`** · `feat/v0.31-multi-conversation` (기준 `main` = `c678ade`) → **PR #108 → squash merge `3c46d14`**. **`main` 직접 push 금지** 유지. `main` clean.
- **타임라인(PR #107)**: 사용자 요청 *"질문 → 도구 → 추론 → 쉘 → 추론 → 응답"*. 사고 과정을 **스텝(모델 호출) 단위 구간**으로 나눠 `AgentEvent.reasoningBefore` 에 저장 — 한 스텝에 도구가 여럿이면 첫 카드 앞에만 사고가 붙고 나머지는 같은 카드로 묶인다. 마지막 스텝 사고는 `Turn.reasoning`(기존 자리). 구버전 기록은 도구 카드 한 장(하위 호환). 검색 출처 카드는 지금처럼 **답변 하단** 유지.
- **표시 방식 설정**: 설정 › AI › "사고 과정 표시" — `항상 보기` / `끝나면 자동으로 접기`(기본) / `'생각 중' 표시만`. 직접 누른 펼침·접힘이 설정 기본값보다 우선, 모르는 값은 기본값 폴백.
- **자동 스크롤**: `agentFollowToken` 에 `liveReasoning.count` 를 포함 — 사고가 흐르는 동안에도 바닥을 따라간다(위로 올려 읽는 중이면 멈춤).
- **`⋯` 클릭 불가(PR #107)**: 원인은 메뉴가 행 프레임 **밖**(`offset x: +16`)이라 호버가 풀리고 히트 테스트도 밖이던 것. 질문 행 오른쪽 **20pt 를 행 안에 포함**하고 `.overlay(alignment: .trailing)` + `offset(x: -4)`, 클릭 영역 **32×24** + `contentShape`, 행을 벗어나면 **0.5초 유예** 뒤 숨김.
- **다중 대화 6a/6b(PR #108)**: `ChatSession`(대화방 1개)이 입력 초안·첨부·응답 중·스트리밍 턴·사고 과정·재시도 상태·도구 카드·승인·중지 손잡이·되돌리기·일정 제안과 `ConversationStore` 를 **방마다** 보관. `UIStore` 는 `sessions` + `activeSessionID` 만 들고 기존 프로퍼티는 활성 세션의 계산 속성(세션 변경은 `objectWillChange` 중계). 응답 Task 가 시작 시 그 방의 세션을 잡고 글자·사고·도구 카드·저장을 그 세션에만 쓴다. `AgentExecutor(session:)` 가 카드·승인·셸 손잡이를 방별 라우팅(예약 실행은 기존 컨텍스트). 목록의 "응답 중" 점은 `isSessionReplying(conversationID:)`.
- **검증(오프스크린)**: `swift test` **856/856**(6 skip — 신규 7: `reasoningBefore` 왕복·구버전 디코딩, 표시 모드 기본값·미지 값 폴백) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 신규 헤드리스 `--session-test` **PASS** 9항목 · 렌더 `docs/qa/v0.31-reasoning/` · `docs/qa/v0.31-question-hover/` · QA 문서 `docs/qa/v0.31-multi-conversation/README.md`(M1~M8) · PLAN §7.3.
- **배포**: **2026-11-06 01:37** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 이동, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 설치본 SHA-256 `45618fcb594a4a195dfd88f1216fb2f0a35b7553e144190cbc0900043f0d3f86`(37MB) · Release 바이너리 `--session-test` **PASS**. (01:18 중간 배포 `22b39fe1…` 는 타임라인까지만 포함.)
- **실측 대기**: **R1~R9**(사고 과정 타임라인 순서·접힘·3모드·자동 스크롤·재방문 유지) · **H1~H5**(`⋯` 호버 유지·클릭) · **M1~M8**(다중 대화 동시 응답·방별 응답 중 점·전환 복귀) · **W1**(승인한 `~/Documents/QuickTalkReport` 저장).
- **남은 확인**: Exa 검색 표시 요구 *"검색한거 하단에 출력 한거는 그대로 두고 Exa 검색 사용시 그 아래도 표현"* 의 정확한 의미 — 현재는 "타임라인에 `web_search` 도구 단계 + 출처 카드는 하단 유지"로 해석(별도 변경 없음).
- **정리(PR #110·#111)**: 실행기 확장(예약·화면 조작)이 활성 세션에 카드를 쓰던 경로를 **실행기 세션**으로 통일(백그라운드 응답 중 카드 섞임 방지). 데드 코드 2개 제거, `GeneratedContent.Kind` 비망라 스위치 정리 — **Debug/Release 경고 0**. `swift test` 856/856 · `--session-test` PASS. **2026-11-06 01:51** 교체(백업 없음) · `codesign --verify --strict --deep` OK · SHA-256 `532d1e3fbf0404643fa13355ab98d7e186d608e5b02c44aa852cc9ebc30f3567`(37MB) · Release `--session-test` PASS.

### 2026-11-06 인계 (6) — v0.31 **질문 호버 폭 · 제목 드래그 · 진행 중 대화 삭제** **병합·배포·실측 완료**

- **브랜치**: `fix/v0.31-hover-title-delete` (기준 `main` = `aae7288`) → **PR #102 → squash merge `da3ab52`**. **`main` 직접 push 금지** 유지.
- **계기(사용자 지적)**: *"질문 호버 시 가로 사이즈가 변하는 게 아니라 세로로 변하네"*, *"제목을 클릭하면 바로 수정이라서 드래그가 먹히질 않는데 — 수정을 제목 더블 클릭으로 바꾸면?"*, *"진행 중 대화는 삭제할 수 없는건가?"*.
- **호버 폭**: `⋯` 가 말풍선 `HStack` 안에 있어 호버 때 폭 26pt 감소 → 글자 재접힘으로 **높이가 변했다**. `⋯` 를 레이아웃 밖(`.overlay` + `offset(x: 16)`, 오른쪽 20pt 여백 안쪽)으로 옮겨 **폭·줄바꿈·높이 고정**. 호버는 행 전체 판정(`.onHover`)이라 `⋯` 로 마우스를 옮겨도 유지된다.
- **제목 드래그**: 제목 `Button` 이 mouseDown 을 삼켜 창 이동이 불가능했다 → `TitleDragArea`(NSViewRepresentable) 로 교체. `mouseDown` → `window.performDrag(with:)`, `clickCount >= 2` → 이름 변경. `NSTrackingArea .inVisibleRect` 로 호버 밑줄 유지, 글자는 `allowsHitTesting(false)` 로 표시만. 제목 밖 타이틀바 여백은 종전대로 `isMovableByWindowBackground` 가 이동을 받는다.
- **진행 중 삭제**: 보관함 "진행 중" 행에 🗑 → 확인 시트(문구 분기) → `UIStore.deleteConversation`. 현재 대화면 **`cancelReply()` 먼저**(지운 대화의 답변이 새 대화에 이어 붙는 것 방지) → `stopSpeaking` · `core.reset` · 기본 비서 재적용 · 초안/첨부/검색 포커스/대기 예약 정리 → **대화 탭으로 이동**(빈 보관함에 남기지 않는다).
- **검증(오프스크린)**: `swift test` **840/840**(6 skip) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 3키 · 렌더 `docs/qa/v0.31-question-hover/`(일반/호버 × 한·영) · `docs/qa/v0.31-archive-fix/current-delete-ko.png`.
- **배포**: **2026-11-06 00:13** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 한 번에 이동, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 설치본 SHA-256 `7e90b38d47231cc7c74d7edef3a643310cc7e5afae10777b22cf43cd8ca2a336`(35.6MB) · **00:17 재실행(PID 19500 = 새 빌드)**.
- **실측 완료(2026-11-06 00:17, 사용자 확인 "다 잘 동작 되는거 확인했어")**: ① 질문 호버 전후 말풍선 폭·줄 수 동일 ② 제목 한 번 클릭 후 끌면 창 이동 / 두 번 클릭이면 이름 변경 ③ 진행 중 행 🗑 → 삭제 후 새 대화.
- **실측 완료(2026-11-06, 사용자 확인: 정상)**: **Q1~Q7** — 호버 도구 페이드 인/0.5초 숨김 · `✎`는 `⋯`에만 · 15pt 전체 폭 응답·질문 꼬리 말풍선 · `＋` 3종 성격 · 셸프 대화 탭 이동·자동 닫힘 · 창 400×560 · "도구 항상 보기" 토글.
- **다음**: 다중 대화 **6a**(`UIStore` → 대화별 `ChatSession` 분리, 동작 변화 0, PLAN §5.2) → **6b**(동시 실행·"응답 중" 표시).

### 2026-11-05 인계 (5) — v0.31 **보관함 복원 · 타이틀바 정렬 · 마크다운 강조색** **병합·배포 완료** (실측 대기)

- **브랜치**: `fix/v0.31-archive-titlebar` (기준 `main` = `964a1d0`) → **PR #99 → squash merge `bd0fc99`**. **`main` 직접 push 금지** 유지.
- **계기(사용자 지적)**: *"타이틀과 시스템 버튼과의 정렬이 깨졌는데?"*, *"보관함에 있던 기능들은 다 어디갔어? 검색이라던지, 삭제라던지.. 비서별로 구분되서 표시 되었던 거라던지.."*.
- **타이틀바 정렬**: 헤더 40pt 행 가운데 = 20pt, 실제 신호등 중심 = **16pt**(macOS 26 실측: 버튼 14×14, x=9/32/55) → **4pt 처짐**. `TitlebarCenterReader` 가 `window.standardWindowButton(.closeButton)` 프레임을 읽어 중심을 계산, 헤더 내용을 상단 `center×2`(32pt) 띠에 가운데 정렬. 바깥 40pt 는 호버 감지·구분선용으로 유지.
- **보관함 복원**: v0.31 에서 상단 탭 아이콘을 없애며 보관함을 QuickShelf 대화 목록만 남긴 것이 원인. **창 안 보관함 탭**(검색·이름 변경·삭제·비서별 그룹)을 복원하고 진입점을 통일 — `⋯` "보관함 — 검색·삭제" · QuickShelf 대화 탭 하단 "보관함 전체 열기 — 검색·삭제·이름 변경" · 메뉴바 `⌘1` · 허브 · pill. 비대화 화면에 **‹ 대화로 돌아가기**.
- **목록 구현**: `List` → `ScrollView`+`LazyVStack` 카드형 행. 오프스크린 렌더에서 SwiftUI `List` 행이 전혀 그려지지 않아 QA 가 불가능했고, design_profile=custom 과도 맞는다. 행 선택 시 검색어를 넘겨 해당 턴으로 스크롤·강조.
- **마크다운 대비**(같은 PR 에 포함): 고정 `#7A5CFF`(다크 3.9:1·라이트 4.4:1) → `AccentPalette` 다크 `#CCC0FF`(≈11:1)·라이트 `#6647D1`(≈6.2:1). QuickShelf 강조 문구도 같은 토큰으로 통합.
- **검증(오프스크린)**: `swift test` **840/840**(6 skip) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 커버리지(신규 4키) · 렌더 `docs/qa/v0.31-archive-fix/`(한/영 · 라이트/다크 · 검색) · `docs/qa/markdown-contrast-2026-11-05/`.
- **배포**: **2026-11-05 23:46** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 한 번에 이동, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 설치본 SHA-256 `1f95612d4bafd0465e2048493d35aa1e6ebb88d81df2323c14696539f55cd132`(35MB) · **23:53 재실행(PID 14039 = 새 빌드)**.
- **실측 완료(2026-11-05 23:53, 사용자 확인 "다 정상")**: A1~A9 전부 — 신호등과 제목/도구의 세로 중심 · `⋯`→보관함 · 검색→해당 턴 이동 · 변경/삭제 시트 · 비서별 그룹 · ‹ 복귀 · 셸프 하단 "보관함 전체 열기" · `⌘1`/허브/pill 라우팅 · 셸프 검색어 점프.
- **다음**: v0.31 Q1~Q7(호버 도구·말풍선·`＋` 메뉴·셸프 대화 탭·창 크기·도구 항상 보기) 확인 → 다중 대화 **6a**(`UIStore` → 대화별 `ChatSession` 분리, PLAN §5.2).

### 2026-11-05 인계 (4) — v0.31 **시리식 대화 창** **병합·배포·재실행 완료** (실측 대기)

- **브랜치**: `feat/v0.31-chat-redesign` (기준 `main` = `948ae5e`) → **PR #96 → squash merge `dc2dc49`**. 후속 수정 `fix/v0.31-persona-right` → **PR #97 → `7f21a85`**(비서 칩이 제목에 붙던 문제). **`main` 직접 push 금지** 유지.
- **무엇(창·상단)**: `titleVisibility = .hidden` · `titlebarAppearsTransparent` · 구분선 제거로 콘텐츠가 상단까지 이어지고, **대화 제목(13.5pt)·비서 칩만 항상** 보인다. 📌·🧠·🔖·◫·⋯ 5개 도구는 마우스가 상단 40pt에 올 때 페이드 인, 벗어나면 **0.5초 뒤** 숨는다. **새 대화(✎)는 호버 도구에서 제외**하고 `⋯`(보관함·새 대화·툴바 항상 보기·설정…)에만 둔다. 호버 중에는 비서 칩을 이모지로 축약해 제목 자리를 확보한다.
- **무엇(메시지)**: 응답 배경 카드 제거 · **좌우 20pt·15pt 전체 폭**(기존 13pt) · 도구 실행 카드는 응답 위 유지. 질문은 **오른쪽 꼬리 말풍선**(13.5pt·accent 18%), `⋯`는 말풍선 바깥 호버 시. 하단 왼쪽 `1분 전 · 59.4초`(항상·10.5pt), 오른쪽 복사·읽어주기(호버 시).
- **무엇(입력독)**: 창 연결·웹 검색·음성 입력 3버튼을 **`＋` 도구 메뉴 하나**로 통합 — 창 연결(1회성 시트) · 웹 검색(이번 질문 한정, 전송 시 자동 해제) · 음성 입력(유지형). 유지형이 켜지면 `＋`가 해당 아이콘(🌐 보라/🎤 빨강)으로 바뀌고 작은 점이 붙는다.
- **무엇(QuickShelf)**: **대화** 탭 추가·기본 — 맨 위 `＋ 새 대화`, 최근/보관함(비서 이모지·제목·상대 시간·응답 중 점). 행을 고르면 그 대화로 이동하고 **셸프가 자동으로 닫힌다**. 상단에서 사라진 보관함·새 대화·설정 진입점은 이 허브와 `⋯`로 모았다(메뉴바·pill의 보관함도 같은 경로).
- **무엇(창·설정)**: 기본 **400×560**, 최소 **380×420**, autosave `QuickTalkMainPanelV31`(새 기본 크기가 기존 창 크기에 덮이지 않게 이름을 올림). `chatToolbarAlwaysVisible` + 설정 › 일반 **"대화 창 도구를 항상 보기"** 토글, 한/영 번역 16키.
- **검증(오프스크린)**: `swift test` **840/840**(6 skip) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 커버리지 통과 · 렌더 `docs/qa/chat-redesign-2026-11-05/`(승인 목업 `mock-*` + 구현 `impl-*` 한/영 · 평소/도구/셸프/설정).
- **배포**: **2026-11-05 23:03** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 한 번에 이동, `~/Applications/` 에 `QuickTalk.app` 하나만) · `codesign --verify --strict --deep` OK · 설치본 SHA-256 `98dedb4e548eeb209fef7148263c245850c3872fbf5a564e997554eaa75ed80b`(= Release 빌드 산출물) · **23:04 재실행 완료(PID 1877 = 새 빌드)**.
- **실측 완료(실제 창, 사용자 확인)**: 제목·traffic light 겹침 없음 · 비서 칩 오른쪽 정렬 · 시간/응답 지연이 항상 보임.
- **실측 완료(2026-11-06, 사용자 확인: 정상) — Q1~Q7**: ① 상단 40pt 호버 → 5개 도구 페이드 인, 벗어나면 0.5초 뒤 숨김(스치듯 지나갈 때 깜빡이지 않는지) ② `✎ 새 대화`가 호버 도구에 **없고** `⋯` 메뉴에만 있는지 ③ 응답이 **15pt 전체 폭**·질문이 **꼬리 말풍선**인지 ④ `＋` 메뉴 3종 성격(창 연결=1회성 · 웹 검색=이번 질문 · 음성 입력=유지형)과 활성 시 아이콘 전환·점 ⑤ QuickShelf **대화 탭**에서 최근/보관함 행 선택 → 그 대화로 이동 + 셸프 자동 닫힘 ⑥ 창 기본 400×560·최소 380×420, 재실행해도 크기 유지 ⑦ 설정 › 일반 **"대화 창 도구를 항상 보기"** 가 `⋯` 메뉴와 같은 값으로 동작.
- **다음**: 다중 대화 **6a**(`UIStore` → 대화별 `ChatSession` 분리) → **6b**(동시 실행). PLAN §5.

### 2026-11-05 인계 (3) — v0.30 **⌘Space pill 비서 선택 · 글자/커서 세로 중심** **병합·배포 완료** (실측 대기)

- **브랜치**: `fix/v0.30-pill-persona` (기준 `main` = `99bc577`) → **PR #94 → squash merge `356c4c6`**. **`main` 직접 push 금지** 유지.
- **계기**: 사용자가 v0.29 배포 후 *"CMD+Space 에서 저 화면에서 비서를 선택할 수 없어"*, *"저 화면에서 키보드 커서와 입력 위치가 아래로 치우쳐 있다"*. 둘 다 **pill(⌘Space) 화면**이었고, v0.28/v0.29 에서는 **대화 창**만 고쳤다(첨부 캡처로 확인).
- **비서**: `PillModel.persona/personas` + `PillPersonaButton`(보관함 왼쪽 32pt, 이모지+체크, 없으면 `person.crop.circle`). 메뉴는 `PersonaMenuList` 공통화 — 칩·입력독·pill 이 같은 목록(`지금: …`·`비서 없음`·체크). `NSMenu` 추적 중 pill 닫힘 방지 + 닫히면 입력창 포커스 복귀. 세션 만료로 새 대화가 시작돼도 `reapplyPersonaIfNeeded` 로 선택 유지.
- **세로 중심**: 1줄 상자 30.6(=줄 18.6+여백 12) · 아래 여백 `(capsule-textHeight)/2` · 안내 문구를 `NSTextView` 가 직접 그림(`ChatTextView.placeholder`) — 대화 창 입력독도 동일 경로.
- **검증(픽셀)**: pill 글자 잉크 중심 **114.75 → 112.75~113.0**(본체 112.0) · 대화 창 입력독 588.0 vs 전송 588.25 · `swift test` **840/840**(6 skip) · Debug/Release BUILD SUCCEEDED · 렌더 `docs/qa/pill-persona-2026-11-05/`(한/영).
- **요청 전수 점검**: 2026-11-05 요청 11건 표(PLAN §2) — **미구현은 QuickShelf 클립보드 자동 펼침 1건**(⌘V 대안은 동작). 자동 펼침은 방해 위험이 있어 사용자 요청 시 구현.
- **실측 대기**: P1 pill 비서 선택 → 이름·이모지·체크 변화 + 답변 말투 반영 · P2 pill 글자/커서가 세로 중앙 · P3 선택 후 Esc → 재실행해도 유지.
- **배포**: **2026-11-05 21:13** `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — 기존 번들 삭제 → 새 번들 한 번에 이동) · `codesign --verify --strict --deep` OK · 설치본 SHA-256 `de4de73329bdc4abe588680fc7cd269fc7c7476272dfe690722f8e224c1201b5`(= Release 빌드 산출물) · 34MB · `~/Applications/` 에 `QuickTalk.app` 하나만 · **실행 중 PID 82629 는 이전 빌드 → 종료 후 재실행 필요**.

### 2026-11-05 인계 (2) — v0.29 연결 끊김 이어쓰기 · 예고 답변 방지 · 비서 리포트 폴더 **병합·배포 완료** (실측 대기)

- **브랜치**: `feat/v0.29-resume-continuity` → **PR #90 → squash merge `eec75df`** (기준 `main` = `67ec098`). 기록 PR #91 → `ab4f37e`. **`main` 직접 push 금지** 유지.
- **무엇(연결 끊김)**: `NetworkRetry` 신설 — 기본 **5초 × 최대 10회**(설정 1~60초·0~50회). 첫 글자 전에는 같은 요청 재전송, 글자가 나온 뒤에는 **이미 쓴 답변을 보존하고 이어쓰기**(`mergeContinuation` — 8자 이상 겹침 한 번, 완전 중복 폐기). 입력독 위 배너 + **[응답 중지]**. 네트워크 단절·시간 초과·DNS·연결 유실·5xx·429만 재시도하고 취소·401·403·400/422는 즉시 알린다.
- **무엇(예고 답변)**: `AgentRunner` 가 스텝별 `onStepStart`/`onStepDiscard` 로 도구 호출 예고·실패 시도 글자를 폐기. 최종 답변이 비었거나 "확인하겠습니다"류면 도구를 뺀 `finalAnswerNudge` 로 한 번 더 요청하고, 그래도 실패하면 지금까지의 도구 결과로 안전망 답변.
- **무엇(리포트 폴더)**: `SystemKnowledge.reportFolderText` 가 비서/기본 리포트 폴더(`~` 확장)와 쓰기 꺼짐 상태를 프롬프트에 넣는다. 일반 대화·도구 경로 모두 같은 블록을 쓴다.
- **무엇(비서·입력독)**: `Persona.displayEmoji`(ID 기반 안정 기본 아이콘, `🗣` 일괄 표시 제거) · 메뉴 `지금: …` 머리줄 + `checkmark.circle.fill` · 칩/독 체크 배지 · 입력독 글자 중심 = 아이콘 줄 중심(실측 1176.5 vs 1175.5).
- **검증(오프스크린)**: `swift test` **840/840**(6 skip, 신규 26) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 커버리지 통과(신규 17키) · 렌더 `docs/qa/resume-continuity-2026-11-05/`(한/영 8장).
- **배포**: 2026-11-05 20:36 `~/Applications/QuickTalk.app` 교체(**백업 복제본 없음** — v0.28 번들은 바로 삭제, `.QuickTalk.old` 를 만들지 않는다) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · SHA-256 `35a5ba0a8a01cabccabded641eddeb105d3f6a2dca075f104259b15cd1f6d9e7` · **앱 재실행 필요**.
- **규칙 위반·정정(2026-11-05)**: 이 배포에서 실수로 `~/Applications/.QuickTalk.old`(v0.28 복제본, 33MB)를 만들었다. 사용자 지적으로 **즉시 삭제**(현재 `~/Applications/` 에 `QuickTalk.app` 하나만 존재). 원인은 §4 [HARD] 규칙을 배포 절차에서 확인하지 않은 것 — `AGENTS.local.md` §4 에 금지 이름 목록·고정 절차(빌드·서명 확인 → 종료 요청 → 기존 번들 삭제 → 새 번들 한 번에 이동 → 검증)를 추가했다. 앞으로 백업은 git 커밋 되돌리기 + 재빌드로만 한다.
- **실측 대기(R1~R5)**: ① 응답 도중 Wi-Fi 차단 → 5초×10회 대기 후 부분 답변 유지·중복 없이 이어쓰기 ② 대기 중 [응답 중지] → 즉시 멈추고 받은 답변 유지 ③ 도구 질문이 예고로 끝나지 않고 실제 값으로 종료 ④ 비서에게 리포트 저장 → 설정된 폴더에 생성 ⑤ 비서 메뉴에서 `비서 없음` ↔ 선택 비서 구분.

### 2026-11-05 인계 — v0.28 비서 선택 + **대화 겹침·스크롤 수정** 병합·배포 완료 (실측 대기)

- **브랜치**: `feat/macos-persona-picker` → **PR #88 → squash merge `9115ad8`** (기준 `main` = `08851bf`). **`main` 직접 push 금지** 유지.
- **무엇(비서)**: 입력독 왼쪽 `PersonaDockButton` — 헤더 칩과 같은 메뉴를 공유하고 **첫 턴 전 빈 대화에서도** 선택할 수 있다. 설정 › 비서 편집의 아이콘 입력칸을 `Persona.iconChoices` **20개 그리드**로 교체(저장 형식 `Persona.emoji` 그대로, 마이그레이션 없음). 칩·독 메뉴가 이모지 하나만 보이던 `.borderlessButton` 문제도 수정.
- **무엇(겹침)**: 사용자 보고 *"대화가 완전히 못쓸 정도"* — 실제 기록 `테크충이 얼마나 똑똑 한가`(20턴, 문서 **20,821pt**)로 재현. 원인은 `AgentCard` 긴 명령 `Text` 의 `.fixedSize(horizontal:false, vertical:true)` 였고, 바깥 `ScrollView` 안에서 **계산 높이보다 더 아래로 그려져** 다음 턴과 겹쳤다(8,123자 명령 턴 17). 제거 + 내용 열 `maxWidth: .infinity` → 5개 위치 스캔 **겹침 0**.
- **무엇(스크롤)**: `.defaultScrollAnchor(.bottom)` 이 **크기 변화마다** 바닥으로 재고정해 읽던 위치를 빼앗았다 → 제거. 실제 `NSScrollView` 오프셋을 보고 **위로 움직이면 자동 따라가기 중단 · 바닥에서 재개**, 새 턴·"맨 아래로"·승인 카드는 예외. AppKit 직접 핀(`bottomPinToken`) + 첫 열기 정착 타이머(0.15s × 최대 4s).
- **무엇(출력)**: 도구 출력의 안쪽 `ScrollView` + `maxHeight:150` → **8줄 + `전체 보기 · N자`**(접기). 빈 150pt 상자와 "휠을 안쪽이 먼저 먹는" 문제 해소.
- **검증(오프스크린)**: `swift test` **814/814**(6 skip) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 겹침 0 · 위로 올린 채 120줄 추가 `19,479 → 19,881`(낭치 없음) · `맨 아래로` `distance=0.0` · 첫 열기 `distance=0`.
- **렌더**: `docs/qa/chat-scroll-2026-11-05/`(한/영 5장씩) · `docs/qa/persona-picker-2026-11-05/`(한/영) · 조사 기록 `docs/qa/chat-scroll-2026-11-05/README.md`.
- **배포**: 2026-11-05 19:31 `~/Applications/QuickTalk.app` 교체(백업 없음) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · SHA-256 `dd9a490edfe0c789cc04587ee1d29fa371fe43576c6fe11ac194a459ef9e1006` · **앱 재실행 필요**(실행 중 PID 796 은 이전 빌드).
- **실측 대기(V1~V5)**: ① 같은 대화가 겹치지 않는가 ② 휠·트랙패드·스크롤바가 즉시 반응하는가 ③ 위로 올려 읽는 중 스트리밍/도구 출력이 바닥으로 끌지 않는가 ④ 처음 열 때 바닥(최신)에서 시작하는가 ⑤ 빈 대화에서 입력독 왼쪽 이모지 버튼 → 비서 선택, 편집 시트 아이콘 20개 선택.

### 2026-11-04 인계 (2) — v0.27 **2단계** 일정 도구·`web_fetch`·비서 모델 오버라이드 **병합·배포 완료** (실측 대기)

- **브랜치**: `feat/macos-schedule-tools` → **PR #85 → squash merge `ce48d29`** (기준 `main` = `2217589`). **`main` 직접 push 금지** 유지.
- **무엇(도구)**: `schedule_list`(읽기 — 카드 없음) · `schedule_update`/`schedule_delete`(쓰기 + 확인 카드). 대상은 **`schedule_list` 가 돌려준 UUID 로만** 지정한다(제목 매칭 금지). "취소"는 삭제로 해석하며 지난 리포트 파일은 남긴다. `SchedulePendingAction`(create/update/delete) 하나로 확인 카드 3종을 같은 큐에서 처리한다.
- **무엇(안전)**: 예약 실행에는 `schedule_list` 만 넘긴다(`includingScheduleMutations: false`) — 실행기에서도 재차 차단. 실행 중인 일정은 변경·삭제 불가. 자가진단 모드 차단. 10분 무응답이면 카드 자동 취소.
- **무엇(파싱)**: `ScheduleProposal` 이 `weekly(days:)` · `everyNDays`(anchor 생략 시 다음 정시) · `interval` · `skip`(객체/배열)을 읽는다. `ScheduleChangeProposal` 은 바꾼 필드만 반영하고 **변경 전 → 변경 후** diff 를 만든다.
- **무엇(웹)**: `web_fetch` — Exa `/contents` 로 URL 본문 읽기(같은 Exa 키). http/https 만 허용, 본문은 **신뢰할 수 없는 데이터**로 표시, 출처 카드에 기록. `web_search` 와 같은 준비 조건(Exa 키 + Apple FM 아님)을 공유한다.
- **무엇(비서)**: 설정 › 비서에 `프로바이더 · 모델` 표시 + 모델 덮어쓰기 칸. `Persona.model` 은 **예약 실행에만** 적용된다(`ScheduledRunRunner.provider(for:)` 가 복사본의 모델만 교체).
- **검증**: `swift test` **813/813**(6 skip, 신규 31) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 키 65건 추가(커버리지 테스트 통과) · 오프스크린 렌더 `schedule-list` · `schedule-editor` · `schedule-card-create|update|delete`(한/영).
- **남은 것**: 사용자 실측 **S1~S6**(PLAN §4).
- **병합**: **PR #85 → squash merge `ce48d29`** (2026-11-04).
- **배포**: 2026-11-04 23:04 `~/Applications/QuickTalk.app` 교체(백업 없음) · `codesign --verify --strict --deep` OK · 빌드 산출물과 `diff -rq` 동일 · SHA-256 `753bf6f37b5f8996b46aba35be9e5e3e12adfdd891fffc678170bd69944a41a6` · **앱 재실행 필요**.
- **주의**: `SchedulerService.setPreviewTasks` 는 `--render` 전용 — `isPreview` 동안 `reload`/`save` 가 디스크를 건드리지 않는다.

### 2026-11-04 인계 — v0.27 **1단계** 예약 규칙 v2 + 비서 표시 **병합·배포 완료** (도구는 남음)

- **브랜치**: `feat/macos-schedule-v2` → **PR #83 → squash merge `6271c7d`** (2026-11-04, 기준 `main` = `1c44711`). **`main` 직접 push 금지** 유지.
- **무엇(1단계)**: ① 예약 규칙 v2 — `weekly(days:)`(월·수·금) · `everyNDays(anchor)`(이틀마다) · `interval`(09~21시 2시간마다) · `ScheduleSkip`(주말·대한민국 공휴일 자동[음력·대체공휴일]·직접 지정 날짜). `/할일` 편집기가 5종 규칙·요일 다중 선택·N일 간격·구간/간격·제외 날짜 UI 제공. `schedules.json` **schemaVersion 1 → 2**, 기존 `weekly.weekday` 하위 호환.
- **무엇(수정)**: `/할일` 삭제가 **최대 30초** 뒤에 사라지던 문제 — `SchedulerService.tasks` 가 ObservableObject 가 아니라 시트가 `Timer.publish(every: 30)` 에만 갱신됐다. `UIStore.scheduleRevision`(저장·삭제·중지 때 증가) + `삭제 중…` 오버레이 + 제거 애니메이션으로 즉시 반영.
- **무엇(비서 표시)**: `Turn.personaID` 로 **답변 생성 시점의 비서**를 턴마다 기록 — 대화 중 비서를 바꿔도 이전 답변 귀속 유지. 채팅 답변 위 이모지+비서명, 보관함 행 비서 칩 + **비서별 섹션 그룹**(기본 → 설정 순서 → `삭제된 비서`). 구버전 `history.json` 은 nil 로 읽어 대화의 현재 비서로 표시.
- **커밋**: `489da13` Core 규칙 v2 → `7e9875a` 할일 편집기·삭제 반응성 → `c6de3f9` 비서 표시/보관함 그룹 → `d528a4e` 번역 → (문서 커밋).
- **검증**: `swift test` **782/782**(6 skip, 신규 16) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 번역 키 28건 추가(커버리지 테스트 통과).
- **배포**: 2026-11-03 23:52 `~/Applications/QuickTalk.app` 교체(**백업 번들 없음**) · `codesign --verify --strict --deep` OK · SHA-256 `12719362f285ece13a0e98b98ac6ce68bc5151f04bdec9949220783f6c61c09c` · 빌드 산출물과 `diff -rq` 동일 · 배포 시점에 실행 중 프로세스 없음 → **다음 실행부터 새 빌드**.
- **남은 v0.27 (1단계 시점 기록)**: 당시 미구현이던 `schedule_list` · `schedule_update`/`schedule_delete` · `ScheduleChangeProposal` · `ScheduleProposal` 새 규칙·`skip` 파싱 · `ExaContentsClient` + `web_fetch` · 비서 AI 라벨·모델 오버라이드는 **2단계에서 완료**했다(위 인계 참조).

### 2026-11-03 인계 — v0.26 비서·예약 작업·리포트·알림 **구현 완료** (실측 대기)

- **브랜치**: `feat/macos-assistant-persona` (기준 `main` = v0.26 설계 PR #79 squash merge `df97b50`).
- **무엇**: 성격·말투가 다른 비서 여러 명 + 매일/매주/한 번 예약 실행 + 설정 폴더 Markdown 리포트 + 대화 요약 카드 + `/할일` 목록 + `schedule_task` 확인 카드 + 완료/승인 대기 알림(기본음·야간 무음·딥링크).
- **커밋(5단계)**: ① `28b7d26` Core 모델·규칙·저장 → ② `46c947f` 설정 › 비서·`Conversation.personaID` → ③ `857c040` 실행 엔진·리포트 → ④ `e0fcedd` `/할일`·비서 칩·`schedule_task` → ⑤ `621e80d` 알림·권한 안내·딥링크.
- **핵심 설계**: 예약 실행은 `ScheduledRunContext` 로 **현재 대화와 분리**(세션·승인·쓰기 범위 라우팅). 비서 0명이면 기존과 완전 동일. 모델은 일정을 **제안만** 하고 사용자가 `[등록]` 해야 저장. 일정 삭제 도구 없음(UI 전용).
- **검증**: `swift test` **766/766**(6 skip) · Debug **BUILD SUCCEEDED** · `project.pbxproj` 신규 10파일 등록 · 번역 키 100여 건.
- **실측 대기**: `docs/qa/assistant-persona-2026-11-03/CHECKLIST.md` — S1~S8(비서 전환·예약 실행·승인/거부·따라잡기·`schedule_task`·삭제·권한 거부) + N1~N3(야간 무음·승인 만료·딥링크). **앱 재실행 후 실측.**
- **한계**: 앱이 꺼져 있으면 실행·알림 없음(로그인 자동 시작 전제) · 승인 대기 중 앱 종료 시 다음 정시에 재시도 · 알림은 앱 실행 중에만.
- **병합**: **PR #80 → squash merge `732ea6e`** · **문서 PR #81 → `0f891a1`**(2026-11-03).
- **배포**: 2026-11-03 19:26 `~/Applications/QuickTalk.app` 교체(**백업 번들 없음**) · Release `xcodebuild` **BUILD SUCCEEDED** · `codesign --verify --strict --deep` OK · SHA-256 `b0a73f42a7a371cbdbb3fbb272d6cc44fa443fbb3f073e256eeeab722425be16` · 빌드 산출물과 `diff -rq` 동일 · **앱 재실행 필요**(실행 중 PID 21862 는 이전 빌드 `b0d8ad20…`).
- **다음**: 앱 재실행 → `docs/qa/assistant-persona-2026-11-03/CHECKLIST.md` S1~S8·N1~N3 실측 결과 기록 → 실패 항목은 재현 → 원인 → 되돌려 실패 확인 → 수정 PR.

### 2026-11-03 인계 — 실측 마감: UA · 컴퓨터 제어 Phase 1·2 · 기타 백로그 **전부 정상**

- **무엇**: 사용자가 배포본으로 ① UA `QuickTalk/1.0` ② ④ Phase 2 U2~U8 ③ ④ Phase 1 U1~U5 ④ 그 밖의 백로그(v0.24 3건 · v0.23 3건 · v0.20–0.22 29항목 · 승인 폴더 · Shortcuts · Exa `/answer`)를 실측 → **버그 없음**.
- **기록**: `docs/qa/ui-action-2026-10-31/CHECKLIST.md`(U2~U8 체크·U4 준비 체크) · `docs/qa/ui-snapshot-2026-10-29/README.md`(U1~U5 결과 절) · `PLAN_v0.25` §11 체크박스(Phase 1·2 실측 완료).
- **정정**: 이전 인계의 "**앱 재실행 필요**(PID 44477)" 는 **해소** — 실행 중 앱은 배포(14:35) 이후인 **11-02 18:00 기동(PID 80576)**, 배포 바이너리 SHA-256 `b0d8ad2031e3…` 와 일치.
- **세션 검증**: `swift test` **628/628**(6 skip) 재확인 · `git status` clean · `main = 0aa9308`.
- **한계(정직)**: 항목별 화면 캡처·정확한 문구는 남기지 않았다 — 사용자가 범위 전체를 "전부 정상"으로 확인한 기록만 있다.
- **다음**: 실측 대기 항목이 **비었으므로** 새 작업은 개선·신규 기능 후보에서 고른다. 실제 결함이 다시 나오면 **재현 → 원인 → 되돌려 실패 확인** 순서를 지킨다.
- **병합**: **PR #78**(문서)

### 2026-11-02 인계 — AI API User-Agent: `QuickTalk/<버전>` (배포 완료)

- **계기**: OpenAI 호환 서버 로그의 클라이언트 UA 가 `QuickTalk/1 CFNetwork/3896.200.61 Darwin/27.2.0` — URLSession 기본값이라 앱·CFNetwork·macOS 버전이 노출되고, 버전도 빌드 번호(`1`)였다.
- **수정(Core)**: `QuickTalkUserAgent` (`Sources/QuickTalkCore/LLMProvider.swift`) — `QuickTalk/` + `CFBundleShortVersionString`(없으면 `1.0`), `apply(to:)` 가 요청 헤더를 덮어쓴다. 요청에 UA 가 있으면 CFNetwork 기본 UA 는 붙지 않는다.
- **적용**: `URLRequest` 생성 **8곳 전부** — `OpenAIClient` 채팅(스트리밍 포함)·`/models`, `OllamaClient` 채팅(스트리밍·도구 포함)·`/api/tags`, `ExaSearch`·`ExaAnswer`.
- **검증**: `swift test` **628/628**(6 skip, 신규 7 — `UserAgentTests` 형식·접미사 금지·헤더 교체·OpenAI/Ollama/Exa 빌더) · Debug/Release `xcodebuild` **BUILD SUCCEEDED** · 로컬 HTTP 서버 실측: 기본 `swift-frontend (unknown version) CFNetwork/3896.200.61 Darwin/27.2.0` → 지정 `QuickTalk/1.0` (접미사 없음).
- **병합/배포**: **PR #75 → squash merge `5a616c6`**(2026-11-02) · 14:35 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `b0d8ad2031e3…` · **앱 재실행 필요**(PID 44477 은 이전 빌드).
- **백업 금지**: 기존 `.QuickTalk.old`·`.QuickTalk.old-505f7b84` 는 **삭제**(같은 bundleId 복제본이 권한 목록에 중복으로 남음 — 사용자 요청). 이후 배포는 백업 번들을 만들지 않고 바로 교체한다.
- **다음**: 앱 재실행 후 서버 로그에서 UA 가 `QuickTalk/1.0` 인지 확인. 버전은 Info.plist `CFBundleShortVersionString`(현재 `1.0`)을 따른다.

### 2026-10-31 (3) 인계 — ⌘Space 토글 수정: 보이는 창은 숨긴다 (배포 완료)

- **계기**: 사용자 실측 — 대화 창을 띄운 뒤 다른 앱을 조작하고 ⌘Space 를 다시 누르면, 창이 **사라지지 않고 화면 중앙으로 이동**했다.
- **원인**: `togglePanel` 이 "창이 보이지만 키 창이 아님"을 **"앞으로 가져오기"** 로 해석해 `showPanel` 을 호출했고, `showPanel` → `positionPanel` 이 중앙 모드에서 창을 **다시 배치**했다.
- **수정(Core)**: `PanelToggle.decide(pillVisible:panelVisible:)` 신설 — **pill → 닫기**, **창(키 여부 무관) → 숨기기**, 둘 다 없음 → 열기. 순수 함수라 값으로 고정한다.
- **수정(App)**: `togglePanel` 은 판정 결과의 부수 효과만 실행한다. 숨길 때 **위치·배치를 건드리지 않는다** — 다시 열면 마지막 자리에서 이어진다.
- **Xcode**: 새 Core 파일 `PanelToggle.swift` 를 `project.pbxproj` 의 QuickTalkCore 그룹·Sources 단계에 등록(앱 타깃은 SwiftPM 이 아니라 명시 참조).
- **검증**: `swift test` **621/621**(6 skip, 신규 3 — pill 우선 · 비키 창 숨김 · 없을 때 열기) · Debug/Release **BUILD SUCCEEDED** · **되돌려 실패 확인**(보이는 창 → show 로 되돌림 → 1건).
- **병합**: **PR #72 → squash merge `7802cfc`**(2026-10-31).
- **배포**: 2026-10-31 22:09 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `ca715df81aa2cc051eb63b561b1822644b80b7c267c8ff0d3b2a5c4038ebf727` · 직전 21:50 빌드는 `.QuickTalk.old` · **앱 재실행 필요**(PID 38888 은 이전 빌드).
- **확인**: 2026-10-31 사용자 실측 — ⌘Space 두 번으로 **숨김/재표시 정상**("잘 됨"). 중앙 이동 없음.

### 2026-10-31 (2) 인계 — Phase 2 승인 단순화: 화면 제어를 전역 권한과 분리 (배포 완료)

- **계기**: 사용자 실측 — 한 요청에 승인 카드가 **5장**(open_app · snapshot · click · snapshot · type). 전역 `읽기`/`실행` 이 "매번 확인"이라 **앱 승인과 곱해졌고**, `ui_snapshot` 카드의 `[항상 허용]` 은 읽기 경로가 무시해 눌러도 계속 물었다.
- **결정**: 화면 제어를 **셸·파일 권한 모델과 분리**한다(사용자 선택).
- **Core**: `UiGuard.evaluate` 에서 `policy` 인자 제거 — **앱 승인이 있으면 allow, 없으면 ask**. 금지 앱·키·보안 필드·턴당 30동작은 그대로.
- **읽기**: `ui_snapshot` 은 **마스터 토글만** 확인하고 승인 카드가 없다(읽기 전용 · 토글이 명시적 동의).
- **효과**: 카드 **5장 → 앱당 1장**. `[이 앱 허용]` 후 7일 무질문, `[한 번 허용]` 은 그 동작만.
- **설정**: 컴퓨터 제어 캡션에 "전역 권한과 별개" 명시(한/영 1키). 전역 읽기/쓰기/실행은 셸·파일 전용.
- **검증**: `swift test` **618/618**(6 skip) · Debug/Release **BUILD SUCCEEDED** · **되돌려 실패 확인**(승인 뒤 ask로 되돌림 → 3건).
- **병합**: **PR #70 → squash merge `43a4c42`**(2026-10-31).
- **배포**: 2026-10-31 21:50 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `d47705e69e9714f3caac8a320356f4ff9bab144e2a32ad493a29327c2888bcbd` · 직전 20:41 빌드는 `.QuickTalk.old` · **앱 재실행 필요**(PID 31638 은 이전 빌드).
- **미완**: 재실행 후 U2~U8 재확인(카드가 앱당 1장인지).

### 2026-10-31 인계 — ④ 컴퓨터 제어 Phase 2 구현 완료 (테스트·빌드 통과, **미배포**)

- **무엇**: `PLAN_v0.25` Phase 2. 에이전트가 **다른 앱의 화면 요소를 실제로 조작**한다(`ui_action`) — 클릭 · 텍스트 입력 · 키 조합 · 스크롤 · 앱 열기 · 창 앞으로. **좌표 클릭 없음** — `ui_snapshot` 이 준 참조(`r1`, `r2`, …)만 받는다.
- **Core(순수)**: `UiAction`(6동작 파싱·인자 검증·카드/감사 문구) · `UiGuard`(금지 앱 14개 고정 · 텍스트 입력 가능 역할 4개 · 금지 키 조합 5개 · 턴당 **30동작** · 최소 간격 **0.15초** · 텍스트 **2,000자**) · `UiAppGrant`(앱별 승인 **7일**, 만료 시각과 같은 순간도 만료).
- **실행(App)**: `UiControlService` — `NSWorkspace` 로 앱 활성/열기, `CGEvent` 로 클릭·유니코드 입력·키·스크롤, **유휴 가드**(사용자 입력 후 0.4초 대기, 최대 2초). `AgentExecutor+UI` — 검증 → 앱/요소 해석 → 게이트 → 승인 → 유휴 → **라이브 AX 재해석** → 주입 → 감사.
- **재해석(핵심 안전)**: 승인 후·주입 전에 AX 트리를 **다시 읽는다**. 경로가 사라졌거나 역할/이름이 바뀌면 `elementChanged`(“UI가 바뀌었습니다…”)로 **실행하지 않는다**. 비밀번호 필드는 읽지도 쓰지도 않는다.
- **UI**: 승인 카드 `[거부] [이 앱 허용] [한 번 허용]` · **“되돌릴 수 없음” 배지** · UI 동작에는 “항상 허용” 없음. 설정 › 도구·권한 › **“화면 조작 허용”** 토글 + 승인된 앱 목록(만료일·[해제]) + 금지 앱·한도 캡션.
- **검증**: `swift test` **619/619**(6 skip, 신규 44 — `UiActionSpecTests` 19 · `UiGuardTests` 15 · `UiAppGrantTests` 10) · Debug/Release `xcodebuild` **BUILD SUCCEEDED**(기존 `AgentClients.swift:171` 경고 1건만) · **되돌려 실패 확인**(항상 허용 → 7건 · 금지 키 제거 → 10건 · 좌표 거부 제거 → 1건).
- **병합**: **PR #66 → squash merge `cf5728b`**(2026-10-31).
- **배포**: 2026-10-31 20:41 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `4d3e8e2b4329a8a18c5813617d764d48658b13ec70edf404359016ca2dedc439` · 직전 Phase 1 빌드는 `~/Applications/.QuickTalk.old` · **앱 재실행 필요**(PID 6058 은 이전 빌드).
- **미완**: **실측 U2~U8**(앱 재실행 필요) — U2 승인 카드/거부 · U3 7일 기억·만료일 · U4 비밀번호 거부 · U5 터미널 금지 · U6 입력 중 거부 · U7 [중단] · U8 31번째 동작. **U1·U4(읽기 쪽)도 여전히 대기**(Phase 1).
- **재개 확인**: `git log --oneline -1 && git status --short && swift test` · 설계: `docs/plans/PLAN_v0.25_computer-control_macos.md` · 배포는 사용자 확인 후.

### 2026-10-30 인계 — Phase 1 배포본 재실행 대기 (코드 변경 없음)

- `main` = **`c9d1152`** · 작업 트리 clean · 원격 `origin/main` 과 동일.
- ④ Phase 1 배포본 SHA **`66025bf1d35c…`**(2026-10-29 19:59). 실행 중 PID 44867 은 **이전 빌드**라 사용자가 재실행해야 반영된다.
- 다음 세션 순서: ① 사용자 재실행 후 **U1~U5 실측**(HANDOFF 상단 ④ 절) → ② 결과 기록 → ③ ④ Phase 2(`UiGuard` · `UiAppGrant` 7일 · `UiControlService` · 유휴 가드 · [이 앱 허용] 카드) 착수.
- 재개 확인: `git log --oneline -1 && git status --short && swift test` · 설계: `docs/plans/PLAN_v0.25_computer-control_macos.md` · QA: `docs/qa/ui-snapshot-2026-10-29/`.

## 0. 30초 요약

| 항목 | 상태 |
|---|---|
| 앱 | QuickTalk macOS, SwiftUI + AppKit, `com.borasarang.QuickTalk`, LSUIElement, 샌드박스 없음 |
| design_profile | **custom** — 네이티브 alert/Picker/NSPopUpButton 금지(전면 설정의 기존 `pickerRow`만 예외) |
| 현재 빌드 | **AI API User-Agent `QuickTalk/<버전>`(2026-11-02 14:35)** `~/Applications/QuickTalk.app` · `codesign --verify --strict --deep` OK · SHA-256 `b0d8ad2031e3…` · **백업 번들 없음**(`.QuickTalk.old*` 삭제 — 권한 목록 중복 방지) · **실행 중 앱이 이 빌드**(PID 80576, 11-02 18:00 기동 — 재실행 불필요) |
| 테스트 | **628/628**, 6 skip = `QT_LIVE` 4 + `QT_LIVE_STREAM` 2 (2026-11-03 재확인) |
| 마지막 완료 | **실측 마감(2026-11-03)** — UA `QuickTalk/1.0` · ④ Phase 2 U2~U8 · ④ Phase 1 U1~U5 · v0.24/v0.23/v0.20–0.22·승인 폴더·Shortcuts·Exa `/answer` **전부 정상, 버그 없음** |
| 이전 완료 | **AI API User-Agent `QuickTalk/<버전>`**(`5a616c6`, PR #75, 11-02 14:35) · **⌘Space 토글**(`7802cfc`) · **Phase 2 `ui_action`**(`cf5728b`) · **Phase 1 `ui_snapshot`**(`8bed1ef`) · **Shortcuts 자동 전송**(`0fda8a4`) · **승인 폴더 7일 기억**(`5589105`) |
| 다음 작업 | 실측 대기 **없음** — 새 작업은 개선·신규 기능 후보에서 선택. 결함 재발 시 **재현 → 원인 → 되돌려 실패 확인** 순 |
| 실측 대기 | **없음 (2026-11-03 사용자 확인: 전부 정상)** — 항목별 캡처·문구는 남기지 않음 |
| 운용 방침 | **주 = 원격 OpenAI 호환, 예비 = Local Apple FM.** 로컬 Ollama는 보조(한계 수용). 설정 › AI에서 활성을 원격으로 되돌려 둔다 |
| 실행 중 앱 | **최신 배포본**(PID 80576, 11-02 18:00 기동) — UA `QuickTalk/1.0` 빌드 |
| git | `main` = **`0aa9308`(PR #77 — 배포 백업 금지)** · 이전 `5a616c6`(#75 UA) · `7802cfc`(#72) · `43a4c42`(#70) · `cf5728b`(#66) · `8bed1ef`(#63) · `main` 직접 push 금지 |

### 다음 세션 시작점 (2026-10-29) — **④ 컴퓨터 제어 Phase 1 완료 · 배포 완료**

- **무엇**: `PLAN_v0.25` Phase 1. 에이전트가 **다른 앱 창의 접근성 요소를 읽기만** 한다(`ui_snapshot`). 클릭·입력·스크롤·포커스 이동 없음.
- **순수 계산**: `UiSnapshot`/`UiElementPath` — 이름 없는 컨테이너 평탄화(같은 부모의 순번표 유지) · 같은 이름 형제 순번 · 노드 400/깊이 12/이름 120자 상한 · `truncated`.
- **읽기 전용 AX**: `AccessibilityService` — 메인 스레드 밖 · 창 1개 · 6초 예산 · 1.5초 메시징 타임아웃 · `AXManualAccessibility` 힌트만. `AXAccess` 로 `AXWindowReader` 중복 헬퍼 통합.
- **게이트**: `uiControlEnabled` 기본 **꺼짐** — 꺼져 있으면 도구가 목록에 없다(`AgentToolCatalog.all` 에도 넣지 않음). 켜져 있어도 읽기 정책(매번 확인) 적용.
- **안전**: 비밀번호 필드는 `secure`만, 값은 절대 싣지 않음. 권한 없으면 허용 경로 안내. QuickTalk 자신은 기본 대상에서 제외.
- **설정**: 도구·권한 › `컴퓨터 제어`(읽기 전용) + 손쉬운 사용 캡션 갱신. 번역 20키.
- **검증**: `swift test` **576/576**(6 skip, 신규 17) · Debug/Release BUILD SUCCEEDED · **되돌려 실패 확인**(비밀번호 2 · 평탄화 2 · 옵트인 3 · 권한 단계 1 · 순번표 1) · 렌더 `docs/qa/ui-snapshot-2026-10-29/`.
- **병합/배포**: **PR #63 → squash merge `8bed1ef`** · 2026-10-29 19:59 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `66025bf1d35cb9ca631aed4f107f2064964bc586c33eabcdfd10afd6bc55c808` · **앱 재실행 필요**.
- **실측 대기**(앱 재실행 후): U1 꺼짐 = 도구 미등록 · U2 켜짐 = 요소 읽기 · U3 권한 안내 · U4 비밀번호 값 비노출 · U5 읽기 정책 승인/거부.
- **다음**: ④ Phase 2 — `UiGuard` · `UiAppGrant`(7일) · `UiControlService` · 유휴 가드 · [이 앱 허용] 카드.

### 다음 세션 시작점 (2026-10-29) — **③ Shortcuts 자동 전송 완료 · 배포 완료**

- **무엇**: Shortcuts/Siri는 지금까지 입력창에 질문을 **채우기만** 했다. 사용자가 켠 경우에만 '질문하고 보내기'가 확인 없이 전송하도록 **옵트인 설정**을 넣었다(사용자 선택: 옵트인 · 항상 전송).
- **설정**: `QuickTalkSettings.shortcutAutoSend` — 기본 **꺼짐**, 구버전 설정(키 없음)도 꺼짐.
- **판정**: `ShortcutAutoSend.shouldSend(requested:enabled:)`. '질문 채우기'는 `requested = false` 라서 설정과 무관하게 **항상 초안만**.
- **라우터**: `QuickTalkIntentRouter.Request{text, ask}` — 앱 준비 전에 들어온 요청도 보내기 의도를 보존해 준비 후 전달.
- **Intent**: 새 `QuickTalkAskIntent`('질문하고 보내기', `paperplane`) + AppShortcut 문구. 기존 '질문 채우기'·'QuickTalk 열기'는 그대로.
- **UI**: 설정 › 단축키에 `Shortcuts · Siri` 그룹(토글 1 + 캡션 2줄, 한/영 키 4개).
- **검증**: `swift test` **559/559**(6 skip, 신규 3) · Debug/Release BUILD SUCCEEDED(Debug 경고 0) · **되돌려 실패 확인**(설정 무시 → 1건) · 렌더 `docs/qa/shortcut-auto-send-2026-10-29/`(한/영, 토글 기본 꺼짐).
- **병합/배포**: **PR #60 → squash merge `0fda8a4`** · 2026-10-29 19:29 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `505f7b84279b2f787200517894266adaed6cae6c6d1b69164eeee6b238a7dfaf` · **앱 재실행 필요**(PID 44867 은 이전 빌드).
- **실측 대기**(앱 재실행 후): Shortcuts에서 '질문하고 보내기' 추가 → ① 설정 꺼짐 = 초안만 ② 설정 켜짐 = 뒤에 있어도 전송. Siri 문구 등록 여부도 함께 확인.
- **다음**: ④ **컴퓨터 제어** — 별도 계획 문서부터.

### 다음 세션 시작점 (2026-10-29) — **② Exa `/answer` 정리 완료 · 배포 완료**

- **무엇**: `/answer`(Exa 답변 초안+인용) 옵션은 **유지**하고, v0.23 툴 콜링과 겹치던 판정·폴백을 정리했다.
- **Core `WebSearchRouting`(신설)**: `skipsPreSearch`(도구 + 검색 준비 + Apple FM 아님) · `usesPreSearch` · `usesAnswerDraft` — 앱과 설정 화면이 같은 규칙을 쓴다.
- **중복 제거**: `/answer` 실패 → 일반 검색 폴백과 일반 검색 성공 경로가 복사하던 프롬프트 주입 6줄을 `applySearchResults(_:)` 한 곳으로.
- **안내 정확화**: `agentToolsEnabled` 만 보던 캡션을 실제 판정(`isAgentDrivenWebSearch`)으로 교체 — Apple FM·키 없음에서 "모델이 직접 검색한다"고 잘못 말하지 않는다. `/answer` 모드에서는 "초안이 쓰이지 않는다"는 전용 문구를 보여 주고 중복 캡션을 제거(한/영 키 1개 추가).
- **QA**: `--demo-web-answer-agent`(실제 키의 `secretID` 를 빌린 가짜 OpenAI 호환, 메모리 전용) · `--demo-web-answer-tools-off` · 렌더 `docs/qa/exa-answer-2026-10-29/`(한/영 · 도구 ON/OFF).
- **검증**: `swift test` **556/556**(6 skip, 신규 5) · Debug/Release BUILD SUCCEEDED(Debug 경고 0) · **되돌려 실패 확인**(Apple FM 예외 제거 → 3건).
- **병합/배포**: **PR #58 → squash merge `c6f04a2`** · 2026-10-29 19:11 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `50e232eaaf0505725a6fd4b7d98ee48cad2bf275c364afc4338b0add9b60452b` · **앱 재실행 필요**(PID 44867 은 이전 빌드).
- **다음**: ① 재시작 후 승인 폴더 유지·만료일·[해제]·`/answer` 안내 실측 → ② ③ Shortcuts 자동 전송(완료 — 위 항목 참조).

### 다음 세션 시작점 (2026-10-29) — **① 승인 폴더 기억 완료 · 배포 완료**

- **무엇**: 승인 폴더가 `UIStore` 메모리에만 있어 앱 재시작 시 사라지던 것을 **대화 기록과 함께 저장**하고 **7일 뒤 자동 만료**한다. 승인 범위는 그대로 대화별.
- **모델**: `Conversation.approvedWriteScopes: [WriteScopeGrant]?`(구버전 키 없음 = 승인 없음) · `WriteScopeGrant`(path·approvedAt·expiresAt, 기본 수명 7일, 만료 시각과 같은 순간도 만료).
- **동작**: 재승인 시 같은 경로 **기간 갱신** · 만료 항목은 승인·저장 시 정리 · `Store.setWriteScopeGrants` 는 활성만 저장하고 0건이면 `nil` · `AgentExecutor` 는 `approvedWriteScopes`(계산 프로퍼티, 만료 제외)를 그대로 소비.
- **UI**: 설정 › 도구·권한 › 승인된 폴더에 **만료일**, 캡션 "이 대화에서 7일 동안 유지 · 만료/[해제] 시 다시 묻습니다"(한/영 키). 기존 "앱을 다시 켜면 초기화됩니다" 문구 제거.
- **검증**: `swift test` **551/551**(6 skip, 신규 10) · Debug/Release BUILD SUCCEEDED(Debug 경고 0) · **되돌려 실패 확인**(`isActive` 항상 true → 4건, Store 만료 필터 제거 → 1건) · 렌더 `docs/qa/write-scope-grants-2026-10-29/`(한/영).
- **병합**: **PR #55 → squash merge `5589105`**.
- **배포 완료**: 2026-10-29 18:45 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `4b64ba602ce271d04ff24aaae5a85da43baf07dd4267302c429d1426f0f0ecf9` · 직전 P2 빌드는 `.QuickTalk.old` · **앱 재실행 필요**(PID 44867 은 이전 빌드).
- **다음**: ① 재시작 후 승인 유지·만료일·[해제] 실측 → ② Exa `/answer` 정리(완료 — 아래 ② 항목 참조).

### 다음 세션 시작점 (2026-10-29) — **P2 백로그 3건(#5·#7·#10) 수정 완료, 배포 대기**

- **#5 취소 응답성**: `SandboxCancellation` 에 취소 핸들러를 넣어 `cancel()` 이 **즉시** `terminateProcessTree` 를 호출한다. 실행 대기는 `terminationHandler`+`DispatchSemaphore`(50ms)로 폴링을 없앴고, 트리 종료는 자손 소멸 즉시 반환(10ms 확인·상한 200ms). `ProcessExitGate` 로 종료된 PID 재사용을 막는다.
- **#7 테스터 단계**: `PolicyEngine.stagePreview` — 실행 없이 읽기/쓰기/실행 3단계 판정. UI 단계별 칩 + 실측 안내, `sudo` 는 단일 판정. 렌더 `docs/qa/p2-backlog-2026-10-29/`(사용자 설정 모두 "매번 확인" · 영어 · 자동 수락).
- **#10 경고**: `_ = core.appendAssistant(...)` — Debug 경고 0. Release 의 `GeneratedContent.Kind` 경고는 기존 시스템 API 경고(이번 변경과 무관).
- **검증**: `swift test` **541/541**(6 skip, 신규 9) · Debug/Release BUILD SUCCEEDED · 되돌려 실패 확인 3건.
- **배포 완료**: 2026-10-29 18:03 `~/Applications/QuickTalk.app` 교체 · SHA-256 `351aa836…` · 직전 빌드는 `.QuickTalk.old` · **앱 재실행 필요**(PID 786 은 이전 빌드).
- **실측 대기**: ① [중단] 즉시성(긴 명령 실행 중 [중단]) ② 규칙 테스터에 쓰기 명령을 넣었을 때 `읽기/쓰기/실행`이 **나뉘어** 보이는지 ③ 설정 › 도구 경고 0.

### 다음 세션 시작점 (2026-10-29) — **슬래시 팔레트 언어(#11) · 도구 토글 라벨(#12) 수정**

- **계기**: 10-28 사용자 실측에서 **"슬래시 팔레트가 설정 언어와 반대"**. 이번 세션은 **추측 대신 측정**부터 했다.
- **측정 도구(신규)**: `--demo-slash` — 입력독에 `/` 를 넣어 팔레트를 렌더. `--demo-lang-switch=korean|english` — 설정에서 언어를 바꾸는 **실제 경로**(설정 발행 → sink → `applyLanguage`)를 재현(`suppressSettingsSave` 로 저장 안 함). `--lang=` 오버라이드가 있으면 설정 변경이 무시되므로 `clearLaunchLanguageOverride()` 로 해제한다.
- **측정 결과**: 시작 시점·런타임 전환 **양방향 모두** 설명·템플릿은 언어를 따라갔다 → **역전 아님**. 결함은 **명령 이름**: `SlashCommand.name` 이 한국어 리터럴이라 영어 UI 에도 `/화면`·`/창`·`/디스크` 가 남아 **반쪽 번역**이었고, 이것이 "언어의 반대"로 체감된 지점.
- **수정**: `SlashCommand` 에 언어 무관 `id`(`screen`/`window`/`disk`/`process`/`memory`/`settings`/`help`) 신설(`id = name` 제거) · `name` 은 `L()` → `/Screen`·`/Window`·`/Disk`·`/Process`·`/Memory`·`/Settings`·`/Help` · 한/영 이름을 모두 `aliases` 에 넣어 **예전 이름으로도 입력 가능** · 번역표 `디스크`·`도움말` 신규, `창` → `Window`.
- **#12**: 설정 › 도구·권한 › "도우미 도구" 그룹의 토글을 **"도우미 도구 사용"** 으로 통일(그룹과 이름이 달라 못 찾던 문제).
- **검증**: `swift test` **532/532**(6 skip, 신규 2) · Debug/Release BUILD SUCCEEDED · **되돌려 실패 확인**(이름을 리터럴로 되돌리면 4개 테스트 실패) · 렌더 `docs/qa/palette-lang-2026-10-29/`(전/후 · 한/영 · 런타임 전환) · 설정 › 도구 영어 라벨.
- **미해결**: 사용자가 본 *"한글이면 영문"* 방향은 캡처로 재현되지 않았다. **팔레트 화면 스크린샷**을 받으면 확정한다(그 전에는 "고쳤다"고 단정하지 않는다).
- **병합**: **PR #49 → squash merge `2a38c81`** (2026-10-29).
- **배포**: 2026-10-29 `~/Applications/QuickTalk.app` 교체(직전 빌드는 `.QuickTalk.old`) · `codesign --verify --strict --deep` OK · SHA-256 `c9a05a9a2196b934659c87aa6fadd6fe6127a61b2711b482ebb6a89faecaeca7` · **앱 재실행 필요**.
- **다음**: ① 배포(사용자 확인) → ② 배포본 실측 3건(영어 `/Screen` · 한국어 `/화면` · 양방향 옛 이름) → ③ P2 #5 `usleep` 폴링 · #7 규칙 테스터 단계 · #10 `UIStore:950` 경고 → ④ v0.24·v0.23 실측 6건.

### 다음 세션 시작점 (2026-10-28 마감) — **오늘 할 일: 언어 전환 역전 원인 규명**

- **사용자 실측 결과**: ① 스크롤 중 "맨 아래로" **정상** ④ 읽기="매번 확인" → `/화면` 승인 카드·거부 시 미실행 **정상** ⑤ 규칙 `rm -rf /tmp/a` 가 `/tmp/ab` 를 허용하지 않음 **정상**.
- **열린 버그(1순위)**: **슬래시 팔레트가 설정 언어와 반대로 표시** — "한글이면 영문, 영문이면 한글". 사용자 표현 그대로.
- **이미 확인된 것(추측 금지 — 여기서부터)**:
  - 저장값은 `language = korean`(`defaults export com.borasarang.QuickTalk` → `QuickTalk.settings` 디코드).
  - Core 매핑은 정상: `AppLanguage.korean → L10n.Effective.ko`(`Localization.swift`), `SlashCommands` 는 **계산 프로퍼티**로 바뀌어 매 접근마다 `L()` 을 다시 평가한다.
  - `testCatalogFollowsCurrentLanguage`(L10n 을 ko↔en 으로 바꿔 summary 비교) **통과** → **Core 는 범인 후보가 아니다**.
- **따라서 의심 순서**: ① `applyLanguage`(`QuickTalkApp.swift:364`)가 `store.$settings` sink(`.receive(on: RunLoop.main)`)에서 도는데, SwiftUI 본문이 그 **전에** 그려져 팔레트가 옛 언어로 남는 경로 ② `languageDidChange()` 는 `objectWillChange` 만 보내므로 팔레트가 **다시 만들어지지 않는** 경우 ③ 사용자가 본 것이 "영어인데 `/화면` 같은 **명령 이름**이 한국어로 남는 반쪽 번역"일 가능성(`SlashCommand.name` 은 리터럴 한국어, `aliases` 만 영문).
- **판별 절차(먼저 이걸로 쪼갠다)**: 앱을 **재실행한 뒤** 팔레트를 연다. ① 재실행하면 정상 → **런타임 재구성 문제**(수정: 팔레트에 `.id(L10n.language)` 를 주거나 `applyLanguage` 에서 팔레트 상태를 갱신). ② 재실행해도 반대 → **매핑/표시 문제**(`--render` 로 한/영 팔레트를 캡처해 비교, `L10n.effective` 를 로그로 남겨 확인).
- **주의**: 팔레트는 `ContentView.slashPalette`(1085행) 하나뿐이고 `SlashCommands` 사용처도 한 곳이다 — 다른 창(포인터 필)에는 없다.
- **부수(발견성)**: 도구를 끄는 곳을 사용자가 못 찾았다 → 실경로는 **설정 › 도구·권한 › "도우미 도구" 그룹 › "도구 사용" 토글**. 그룹 이름과 토글 이름이 달라 생긴 문제(QA #12). 라벨 통일(예: "도우미 도구 사용")은 번역 2키 수정으로 끝난다.
- **작업 규칙 유지**: 브랜치 → PR → squash merge · `swift test`(현재 **530/530**, 6 skip) · 수정은 **되돌려 실패 확인** · 배포는 사용자 확인 후.

### 다음 세션 시작점 (2026-10-27 23:50 마감) — **4건 연속(B→C→A) + 한 번에 배포**

- **순서**: 사용자 지정 **B(i18n 자동 검출) → C(체감 버그 3) → A(권한·샌드박스 3)**. 각 건 브랜치 → PR → squash merge, 마지막에 **한 번만 배포**.
- **#43 "맨 아래로"**: `GeometryReader` 추정 → `ScrollMetrics` + `ScrollOffsetObserver`(`NSScrollView` 직접 관찰). 테스트 5건. `ce7532a`.
- **#44 B i18n**: 누락이 74 → 12 → **다시 94**. 손보충을 멈추고 `LocalizationCoverageTests` 4검사로 구조 고정(리터럴 커버리지 · 보간 금지 · 한글 잔존 · 스캐너 자기검증). 94건 보충, 프로브로 검출 실측. `484ac12`.
- **#45 C 체감 3**: ① 스크린샷이 사용자 첨부를 밀어냄(`attachments + images`) ② `caption()` 평문에 `**` 노출(문구 + 소스 스캔 가드) ③ `SlashCommands.all` static 고정(계산 프로퍼티 + `available(agentToolsEnabled:)`). `8039493`.
- **#46 A 권한 3**: ① 규칙 `hasPrefix` 과매칭 → 경계만 ② `profilePath` 이스케이프 ③ `AgentToolPermission` 신설로 스크린샷이 읽기 정책을 따름 + `upsertAgentEvent`(카드 1장). `28054bd`.
- **실측 교훈**: "공백·괄호·따옴표 경로는 샌드박스 프로필로 못 연다"는 앞선 결론은 **틀렸다** — `/tmp` 가 `/private/tmp` 심볼릭 링크라 규칙이 빗나간 것이었다. `SandboxRunner` 가 `realpath` 로 바꾼 뒤 넣으면 `qt "q"`·`qt\b`·`qt (1) space` 모두 쓰기 성공.
- **검증**: `swift test` **530/530**(6 skip) · Debug/Release BUILD SUCCEEDED · 각 수정은 **되돌려** 새 테스트가 실패하는지 확인 후 복구.
- **배포**: 23:45 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict --deep` OK · SHA-256 `d04da183297d398cf2f17e88b72d8c11232eb9ced44c3778e10365d9892eb5c7` · **앱 재실행 필요**(실행 중 앱은 21:47 빌드).
- **다음**: ① 앱 재실행 ② 실측 5건(스크롤 중 버튼 · 영어 팔레트 · 도구 off 팔레트 · 읽기=매번 확인 캡처 승인 · 규칙 경계) ③ 남은 P2 3건(`usleep` 폴링 · 규칙 테스터 단계 판정 · `UIStore:940` 경고).

### 다음 세션 시작점 (2026-10-27 15:35 마감) — **v0.24 설정 재구성 · 배포·PR #39 병합 완료**

- **계기**: 사용자 *"설정 구성이 내가 보기엔 뭔가 복잡하다 … 이게 여기가 맞나? 라는 느낌"* → 8탭 전체 인벤토리를 만들고 기능 단위로 재배치.
- **새 구조(9탭 / 사이드바 3묶음)**: 앱 = 일반 · **대화** · 단축키 / 기능 = AI · **검색** · **도구·권한** · 음성 · 퀵셸프 / 기타 = 정보.
- **옮긴 것**: 웹 검색 `AI→검색`, 공통 메모리·대화 기억 `AI→대화`, 창 연결·창 위치·세션 유지 `일반→대화`, 보관함 `→대화`(보관 정책), 시스템 권한 `일반/퀵셸프→도구·권한`(중복 제거), 실행 기록·휴지통은 권한 다음으로.
- **도구·권한 순서**: 도우미 도구 → 전역 권한 → 제한 → 실행 방식 → 항상 허용 규칙 → 이 대화의 권한 → 승인된 폴더 → 규칙 테스터 → 실행 기록 → 되돌리기·휴지통 → 시스템 권한.
- **코드**: `QuickTalkSettingsTab` case 재정의(`archive` 제거, `conversation`·`search` 추가), 사이드바 3묶음, `SettingsView+General.swift` 에 대화 섹션(창 연결·창 동작) 추가, `+AI` 는 프로바이더만, `+Archive` 는 보관 정책+정보, `+Tools` 재정렬. **새 파일을 만들지 않았다** — `project.pbxproj` 가 파일을 명시 등록하는 구조라 기존 파일에 합쳤다.
- **영어**: 새 문구 번역 + 영어로 새던 기존 12건(예비 AI·실행 과정 표시·휴지통·확인 카드) 보충. `--settings-tab` 값은 `conversation|search|…`(구 `archive` → `general` 폴백).
- **검증**: `swift test` **509/509**(6 skip) · `xcodebuild` BUILD SUCCEEDED · `--render` 로 한/영 9탭 확인.
- **배포**: 2026-10-27 `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict` OK · SHA-256 `1175ec9be19065202116a29ca685b1e128c5a17e2e3c7d9e844464b75c5ee952` · **앱 재실행 필요**.
- **병합**: PR #39 → squash merge **`321fd7a`** · 브랜치 삭제 · `main` clean.
- **다음**: ① 앱 재실행 ② 새 구성 실측 3건(대화 탭 흐름·영어 탭 한 줄·시스템 권한 버튼) ③ v0.23 실측 3건(비교 질문 `web_search` 1회·셸 0회 / "메모리" `processes` / 검색 실패 시 답변 지속).

### 다음 세션 시작점 (2026-10-26 01:00 마감) — **권한 카드 2건 수정 · 빌드만(배포 안 함)**

- **계기**: 사용자가 같은 현상을 두 번 겪었다 — ① 확인 카드가 **맨 끝까지 스크롤되지 않아** [한 번 허용] 버튼이 화면 밖에 잘림 ② [항상 허용]을 눌러도 **계속 다시 물음**.
- **로그 확인**: `~/Library/Application Support/QuickTalk/agent-audit.log` — 2026-10-25 15:24~15:35 의 `defaults read com.apple.*` 7건이 모두 `"risk":1`(중요). 사용자 설정 `agentPolicy.rules` 에는 같은 계열 명령이 **5건** 저장돼 있었다(버튼은 눌렀지만 important 판정이 ⑥규칙 매칭보다 먼저라 무시됨).
- **① 오탐**: `RiskClassifier` 가 `defaults` + `com.apple.*` 만 보고 important — **읽기까지** 잡았다. `write`·`delete`·`rename` 일 때만 중요로 좁혔다(`defaults read`·`read-type`·`domains`·`find`·`export` 는 normal). 부수: `plutil … | python3 -c "…"` 처럼 코드를 인자로 받는 인터프리터는 파이프→인터프리터에서 제외.
- **② 무효 버튼**: 설계상 **중요·치명적은 자동 허용이어도 확인**(`PLAN_v0.18` §4.3) — 규칙을 저장해도 소용없으므로 카드에서 [항상 허용]을 **숨기고** "중요·치명적 명령은 항상 허용할 수 없습니다" 한 줄 추가(안전장치는 그대로).
- **③ 스크롤**: `ContentView` 에 `onChange(of: store.agentApproval)` 를 추가해 카드 등장 시 `scrollToBottom`(+0.18s 재시도 — 긴 명령이 여러 줄로 감기는 경우).
- **검증**: `swift test` **505/505**(6 skip, 신규 3 — `AgentSafetyTests`) · `xcodebuild` **BUILD SUCCEEDED**.
- **미검증**: 앱은 **01:00 교체·재실행 완료**(PID 확인·오류 로그 없음). 화면 실사용 확인은 사용자가 한다.
- **배포**: 2026-10-26 01:00 `~/Applications/QuickTalk.app` 교체(직전 빌드 `.QuickTalk.old`) · `codesign --verify --strict` OK · SHA-256 `db6caf77bc788309d68404eef7c138ad903488384bfcfa897597c7d7aa65d354` · 실행 중 앱 종료 후 재실행(사용자 요청).
- **다음**: 재실행 후 ① 같은 `defaults read` 질문이 **카드 없이** 실행되는지 ② 중요 명령 카드에 [항상 허용]이 **없는지** ③ 카드가 뜰 때 **버튼까지** 보이는지 확인 → 그다음 `docs/qa/v0.20-22/CHECKLIST.md` 29항목.

### 다음 세션 시작점 (2026-10-25 21:00 마감) — **P1 3건 수정 · 배포 완료 · 실측 대기**

- **무엇**: 배포 없이 v0.19~v0.22 코드 점검 + 오프스크린 렌더 → P1 3건 수정.
  상세: **`docs/qa/v0.20-22-review/README.md`**(P1 원인·수정·검증, P2 백로그 10건, 확인 필요 1건, 미실측 목록).
- **P1 3건**:
  ① **되돌리기 기록 미등록** — `snapshot()` 만 부르고 `commit()` 을 안 불러 **항상 notFound** + 백업 폴더 무한 누적 → `snapshot()` 자체 등록·`commit` 멱등·실패는 `discard`.
  ② **헤더 `⌘Space` 세로 붕괴** — 460pt + 긴 제목에서 6줄(약 170pt) → `ViewThatFits` 로 한 줄일 때만 라벨 표시.
  ③ **[중단] 자식 프로세스 생존** — `Process.terminate()` 는 `sandbox-exec` 만 죽임(자식 `sleep 30` 생존 실측) → `SandboxRunner.terminateProcessTree`(libproc 트리 + SIGTERM→SIGKILL).
- **검증**: `swift test` **502/502**(6 skip, 신규 3) · BUILD SUCCEEDED(경고 2 = 기존) · 렌더 `docs/qa/v0.20-22-review/`(점검 6장 + `after-fix/` 5장).
- **배포**: **2026-10-25 20:51** `~/Applications/QuickTalk.app` 교체(`codesign --verify --strict` OK, SHA-256 `537e570d19c25be09971ca1426f654bb28f4884e0280bb19c5404933783ccbc6`) — **앱 재실행 필요**(실행 중 앱은 10-23 빌드). 실행 중 앱은 종료하지 않았다.
- **설정 정리**: 설정 › 도구 허용 규칙 1건(내부 주소 `curl … 192.168.86.30:8791 / 127.0.0.1:8791`) 사용자 요청으로 삭제 — `rules` 1→0, 나머지 53키 보존, 원본 plist 백업 `.agent/backup/com.borasarang.QuickTalk-2026-10-25.plist`.
- **머지**: PR #35 → `e8319f8` · 문서 PR #36·#37·#38 (브랜치 삭제 · `main` 직접 push 없음).
- **주의**: 사용자 맥 사용 중 — 앱 실행·권한 승인·실제 캡처·터미널 열기 금지(이번 세션도 하지 않음). 사용자가 **사용하다가 다시 호출**할 예정 — 다음 세션은 이 문서 §0 과 체크리스트부터.
- **다음**: **재실행 후** `docs/qa/v0.20-22/CHECKLIST.md` 29항목 실측(특히 V20-5·V20-7·되돌리기) → 실패 항목 수정.
- **P2 백로그(이번에 안 고침)**: 영어 번역 누락 74곳 · 규칙 테스터 `**` 노출 · `screenshot` 권한 단계 무시 · 샌드박스 경로 이스케이프 · `usleep` 폴링 · `matchesRule` `hasPrefix` 과매칭 · 테스터 쓰기 단계 · 스크린샷이 원 첨부 대체 · `SlashCommands.all` static · `UIStore.swift:940` 경고.

### 다음 세션 시작점 (2026-10-25 05:30 마감) — **v0.20–v0.22 구현 완료 · 실측 대기**

- **무엇**: v0.18 에이전트 런타임 위에 실행 고도화(0.20) → 스크린샷·슬래시·Shortcuts(0.21) → 대화별 권한(0.22).
  상세 설계·실측 체크리스트: **`docs/plans/PLAN_v0.20-0.22_execution_macos.md`**.
- **검증**: `swift test` **499/499**(6 skip, 신규 32) · `xcodebuild` **BUILD SUCCEEDED**(경고 1 — 사용자 v0.19 WIP `AgentExecutor.swift:217` 의 불필요한 `await`, 이번 변경과 무관).
- **신규 파일 6개(병합됨)**: `Sources/QuickTalkCore/{AgentOverride,SystemKnowledge,TerminalHandoff,SlashCommand}.swift`,
  `QuickTalkApp/{TerminalHandoffService,QuickTalkIntents}.swift` + 테스트 4개(`AgentOverrideTests`·`SlashCommandTests`·`SystemKnowledgeTests`·`StreamingExecutionTests`).
  v0.19 WIP(`TrashRewrite`·`UndoStack`·`WriteScope`)·창 연결 4파일과 함께 **PR #33 → `f46ace8`** 로 squash 병합(빌드 의존으로 분리 불가).
- **실측 대기(사용자)** — `docs/qa/v0.20-22/CHECKLIST.md`:
  - **v0.20**: 자동 수락(일반 통과·중요 2차 확인·치명적/상승권 차단) · 실시간 출력 · [중단] · 승인 대기 중 중단 · 제한 시간 · 시스템 경로/상승 권한 [터미널에서 열기] · `brew install` 이 터미널로 밀리지 않는지.
  - **v0.21**: `screenshot` 도구가 다음 스텝에서 실제로 보이는지 · 권한 없을 때 안내 · Apple FM 에서 도구 제외 · 슬래시 팔레트 클릭 채움 · 한글 Enter 회귀 없음 · Shortcuts 초안 채움(앱 미실행 대기열) · 규칙 테스터가 실행하지 않는지.
  - **v0.22**: 대화별 3분할 반영·대화 전환 시 초기화 · 대화 오버라이드로 치명적/상승권 못 끄는지 · 승인 폴더 목록/해제 · 앱 지식이 실제 설정값과 일치(키 노출 없음).
- **주의**: 사용자 맥 사용 중 — 앱 실행·권한 승인·실제 캡처·터미널 열기 금지(이번 세션도 하지 않음). **배포 안 함**(`~/Applications/QuickTalk.app` 교체 없음 — 검증 빌드는 `build/Build/Products/Debug/QuickTalk.app`).
- **알려진 한계**: 창 제어(computer use) 미구현 · Shortcuts 자동 전송 없음 · 슬래시 키보드 탐색 없음(Enter 처리 보존) · 승인 폴더는 세션 한정 · 규칙 테스터는 실측 안 함.

### 다음 세션 시작점 (2026-10-25 04:40 마감)

- **창 연결(P0-1) 구현 완료 · 실측 대기**: `docs/analysis/META-AI-APP-2026-10-25.md` §7. 새 파일 4개(`Sources/QuickTalkCore/WindowContext.swift`, `QuickTalkApp/WindowAttachmentService.swift`, `QuickTalkApp/WindowPickerSheet.swift`, `Tests/QuickTalkCoreTests/WindowContextTests.swift`)와 수정 5개(`ContentView`·`Settings`·`SettingsView+General`·`LocalizationTable`·`project.pbxproj`) — **PR #33 → `f46ace8` 로 병합됨**.
- **실측 항목**: ① 화면 기록만 허용 → 스크린샷만 첨부 ② 손쉬운 사용 추가 → 글자+스크린샷 ③ 둘 다 거부 → 시트에 권한 카드, 목록 없음 ④ 빈 텍스트 창(예: 이미지 뷰어) → "텍스트 없음" 안내 ⑤ 창을 닫고 연결 → 오류 안내 ⑥ 영어 UI 문구 ⑦ 첨부 후 전송 → 모델이 창 내용을 인용하는지.
- **주의**: 사용자 맥 사용 중에는 앱 실행·창 조회·실제 캡처 금지(이번 세션도 하지 않음). 배포도 하지 않았다.

### 다음 세션 시작점 (2026-10-23 18:05 마감)

- **바로 할 일**: **v0.19(쓰기·되돌리기)** 이어서. **작업 트리에 미커밋 WIP 가 이미 있다**(사용자 작업) —
  수정 12개(`project.pbxproj`·`AgentCard`·`AgentExecutor`·`AppDelegate+RenderHarness`·`ContentView`·`SettingsView+Tools`·`UIStore+Agent`·`UIStore`·`AgentRunner`·`PolicyEngine`·`AgentTests` + 문서)와
  신규 6개(`TrashRewrite`·`UndoStack`·`WriteScope` + 각 테스트). **커밋·폐기 모두 금지** — 이어서 작업하고, PR 은 hunk 단위로 이번 변경만 올린다.
- **커밋 시 주의**: `project.pbxproj`·`AppDelegate+RenderHarness.swift` 는 WIP 와 이번 수정이 섞여 있다.
  `git show main:<path>` 로 기준을 만들고 `git hash-object -w` + `git update-index --cacheinfo` 로 **인덱스만** 깨끗하게 만들어 커밋하는 방법을 썼다(작업 트리는 그대로).
- **실측**: N30(로그인 항목 등록/해제·시스템 설정 동기, QA P33·P34) 1건 남음.


### 세션 진행 (2026-10-23 10:10) — pill 높이 회귀 수정 + 로그인 시 자동 시작

#### 사용자 보고
- ① "pill UI 깨짐 상단에 몰려 있음" — 스크린샷: 빈 입력인데 pill 이 2줄 높이로 남아 오브·글자·보관함 아이콘이 위쪽에 몰리고 아래가 비어 보임.
- ② "로그인시 앱 자동 시작 기능 없네?"

#### ① 원인
- `ChatInputField.layoutPass`: `measure()` 는 **글리프가 없으면 nil** 인데 `guard let info else { return }` 으로 빠져나가
  **높이를 되돌리지 않았다** → 여러 줄 → 지우기 하면 `inputHeight` 가 예전 값으로 남는다.
  pill 은 `capsuleHeight = inputHeight + 26` 이므로 본체가 커진 채 유지되고, 1줄짜리 내용은 위쪽에 붙어 보였다.
  대화 창 입력독도 같은 이유로 지운 뒤 커진 채 남았다.
- 레이아웃에도 8pt 어긋남이 있었다: `VStack(spacing: PillMetrics.gap)` + 창 높이는 `extra + capsule` → 내용이 창보다 8pt 커서 아래가 잘렸다.

#### ① 수정
- `ChatInputField` — 빈 입력은 **1줄 높이로 복귀**(공통 `report()` 로 정리, inset·스크롤 위치 리셋).
  내부 기록과 같아도 **부모 값이 0/다른 값으로 바뀌었으면** 다시 보고한다.
- `PillMetrics.capsuleHeight(text:inputHeight:)` — **빈 입력은 언제나 56pt**(측정이 늦게 와도 안전), 최대 4줄 클램프.
  컨트롤러(`currentFrame`)와 뷰가 같은 규칙을 쓴다. `model.$text`(비었는지) 변화에도 창을 다시 맞춘다.
- `PillRootView` — `VStack(spacing: 0)`, 목록만 `.padding(.top, gap)`, 창이 남아도 **아래 기준선 정렬**.
  `resize()` 는 같은 프레임이면 애니메이션을 생략한다.

#### ② 로그인 시 자동 시작
- `QuickTalkApp/LoginItem.swift` — `SMAppService.mainApp`(macOS 13+) 래퍼. **시스템 로그인 항목이 단일 출처**라
  설정 JSON 에 중복 저장하지 않는다(사용자가 시스템 설정에서 꺼도 화면과 어긋나지 않게).
- 설정 › 일반 › 동작에 토글 + 승인 대기(`.requiresApproval`) 안내·`시스템 설정 열기` 버튼, 실패 사유 캡션.
  설정 창 `onAppear`·앱 활성화(`didBecomeActive`) 때 실제 상태를 다시 읽는다.

#### 검증
- `swift test` **434/434**(6 skip) · BUILD SUCCEEDED(경고 0).
- **PR**: **#27** → squash merge **`54a82cd`**(2026-10-23 17:34 KST). 병합 커밋만으로는 **403/403**(6 skip) — 434 는 작업 트리에 있던 v0.19 WIP 테스트를 포함한 수치다.
- 렌더 `docs/qa/t21-pill-debug/pill-height-2line.png`(2줄 75pt) · `pill-height-cleared.png`(낡은 측정값 49가 남아도 **56pt**) · `settings-general-ko`(새 토글).
- **배포**: 2026-10-23 10:15 · `~/Applications/QuickTalk.app` 교체(백업 `~/Applications/.QuickTalk.old`) · `codesign --verify --strict` OK · SHA-256 `291d1aa1622e6959…` · **앱 재실행 필요**.
- **실측 결과** — **N29 ✅ OK**(2026-10-23 18:00, 사용자 *"잘 된다"*: 2줄 → 모두 지우기 → 56pt·내용 세로 중앙) · **N30**(로그인 항목 등록/해제 · 시스템 설정과 동기) 남음.

### 세션 진행 (2026-10-23 17:45) — pill 2차 수정: **입력창 프레임 높이**

- **사용자 재보고**: *"위로 쏠려 있잖아.. 하나도 고쳐 지지 않았는데?"* (재실행 후에도 그대로)
- **원인**: 1차 수정이 **본체 높이**(`capsuleHeight`)만 잡았다. 그 안의 `ChatInputField` 는
  `.frame(height: max(minTextHeight, model.inputHeight))` 로 **낡은 측정값**을 그대로 썼고,
  NSTextView 는 프레임 **맨 위**에 글자를 그린다 → 한 줄 글자가 위에 붙고 아래가 비었다.
- **수정**: `PillRootView.textHeight` — 빈 입력은 언제나 1줄(24pt). `model.$text` 가 비면 `inputHeight` 도 0으로 리셋.
- **검증**: 오프스크린 렌더 실측 — 낡은 49pt 상태에서 글자 잉크가 **2.5~45.5pt**(중심 24.0/56) → 수정 후 **13.0~42.5pt**(중심 **27.8/56**, 정중앙) · 새로 열기 동일 · 2줄 75pt 유지.
- **PR**: **#29** → squash merge **`f0e90bb`** · 배포 2026-10-23 17:50 · SHA-256 `e50b902063c4025d…` · `codesign --verify --strict` OK · **앱 재실행 필요**.

### 세션 진행 (2026-10-22 22:42) — T-18 도우미 도구 실측 **완료** (사용자 확인)

- 사용자: *"T-18 도우미 도구 — 사용자 실측 체크리스트 -> 체크 다 했어"*
- `docs/qa/t18-agent/CHECKLIST.md` — 표의 P1~P19 에 ✅, 상단에 **결과 블록**(완료 시각·실측 빌드·P2 의미 변경) 추가.
- P2 는 2026-10-22 21:33 이후 기준으로 기대를 고쳤다 — `ps`/`top` 은 setuid 라 **실행 불가** 안내,
  값은 **`processes`**(libproc)가 준다(N24).
- 실측 후 사용자 설정: `읽기=항상 허용` · `쓰기=항상 허용` · `실행=매번 확인` · `치명적 명령=차단`.
- 남은 실측: **N22·N24·N25·N26·N27·N28**(이번 배포분) · **T-21 27건** · QA 배치 3·4.
- 다음: **v0.19**(쓰기 단계 경로 스코프 승인 + 휴지통 rewrite + `UndoStack` + [되돌리기] 카드).

### 세션 진행 (2026-10-22 22:30) — 토큰 표시를 대화 영역 위 플로팅 칩으로

#### 사용자 지적
- "대화창 상단에 제목과 토큰이 두줄로 표시 되기 때문에.. 보관함, 설정 등.. 다른 탭으로 이동하면
  사이즈가 달라서 울렁거림.. 토큰 표시를 다른 곳으로 옮기는게 좋을 것 같은데..
  왼쪽 상단이나 오른쪽 상단에 플로팅으로 뛰우는게 좋을듯"

#### 원인
- `headerRow` 가 대화 탭에서만 `VStack`(제목 + 토큰 줄) → **탭마다 헤더 높이가 달랐다**(보관함·설정은 한 줄).

#### 수정
- 헤더를 **모든 탭 한 줄**로 통일(제목 / "보관함" / "설정").
- 토큰(🧠 `215 / 21k · 1%`)은 대화 영역 **우상단 플로팅 칩** — 캡슐 + `.ultraThinMaterial`,
  기준 초과 시 주황, 툴팁(정확한 토큰·자동 정리 설명) 유지.
- 칩이 첫 메시지를 가리지 않게 대화 내용 상단에 14pt 예약(헤더 높이는 불변).
- 턴이 없거나 활성 모델이 없으면 칩을 숨긴다.

#### 검증
- `swift test` **403/403**(6 skip), BUILD SUCCEEDED.
- 오프스크린 렌더 `chat-ko`(칩·헤더 한 줄), `archive-search-ko`(헤더 높이 동일).
- 22:30 배포 · `codesign --verify --strict` OK · SHA-256 `0fa743d736971a19…`.
- **실측 대기** — N28(탭 전환 시 헤더 고정, 칩 위치·툴팁·첫 메시지 비겹침).

### 세션 진행 (2026-10-22 22:10) — 📌 항상 위가 설정 창과 함께 뜨면 꺼지던 문제

#### 사용자 보고
- "대화창에서 최상위 클릭 해 놨는데 동작 안하는데? 다른 창 뜨면 뒤로 가려짐 / 대화창 + 설정창이 떠 있으면 먹히질 않음"

#### 원인
- `applyPanelLevel()`: `blocked = systemPromptDepth > 0 || auxWindows.contains { $0.isVisible }` →
  `blocked` 면 `.normal`. 즉 **설정 창이 보이는 동안 핀이 무시**됐다.
- 이 장치는 2026-10-20 "대화창이 항상 최상위라 설정·권한 창이 뒤로 숨는다" 요청의 결과였다.
  두 요구가 충돌하므로 **레벨을 분리**해야 한다.

#### 수정
- Core `WindowLevelPolicy` — `panel(wantTop:systemPrompt:)`, `aux(wantTop:systemPrompt:appActive:inUse:)`.
- 대화 창: 핀 ON + 시스템 안내 없음 → `.floating` (설정 창과 무관).
- 설정·정보 창: **키 창(또는 그 시트)일 때만** `.floating + 1`. 앱 비활성·시스템 안내 중에는 `.normal`.
- `didBecomeKey`·`didResignActive` 관찰 추가 → "클릭한 창이 위로".
- 시스템 권한 안내(TCC·시스템 설정 딥링크)는 종전대로 대화 창을 내린다(다른 앱 창이라 올릴 수 없음).

#### 검증
- `swift test` **403/403**(6 skip, 신규 8 = 정책 8), BUILD SUCCEEDED.
- 22:10 배포 · `codesign --verify --strict` OK · SHA-256 `291fe2ea65288b21…`.
- **실측 대기** — N27(📌 켜고 설정 창 열기 → 대화 창이 다른 앱 위 유지 / 설정 창은 그 위, 클릭 전환).

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
- `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict` OK · SHA-256 `759918eaf13a93f1…`.
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
| 테스트 | **403/403**, 6 skip = `QT_LIVE` 4 + `QT_LIVE_STREAM` 2 (신규 18 = 창 배치 10 · 창 레벨 정책 8) |
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
#    ※ .QuickTalk.old 같은 백업 번들을 만들지 않는다 — 같은 bundleId 복제본이
#      시스템 설정 › 개인정보 보호 및 보안 권한 목록에 중복으로 남는다.
rm -rf ~/Applications/.QuickTalk.new
ditto build/Build/Products/Debug/QuickTalk.app ~/Applications/.QuickTalk.new
rm -rf ~/Applications/QuickTalk.app
mv ~/Applications/.QuickTalk.new ~/Applications/QuickTalk.app
codesign --verify --strict ~/Applications/QuickTalk.app
```

- **백업 금지**: 배포할 때 이전 번들을 `~/Applications/.QuickTalk.old` 등으로 **남기지 않는다**. 같은 bundle id 복제본은 손쉬운 사용·화면 기록 권한 목록에 중복 항목으로 남는다(2026-11-02 사용자 요청).
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
