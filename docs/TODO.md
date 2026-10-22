# TODO.md — QuickTalk

> 현재 상태·다음 작업·실측 대기는 **`docs/HANDOFF.md`**가 단일 출처다. 이 파일은 작업 이력이다.
> 마지막 갱신: 2026-10-22 22:42 KST

## 지금 (2026-10-22 22:42) — T-18 도우미 도구 실측 완료 ✅

- **사용자 확인**: "T-18 도우미 도구 — 사용자 실측 체크리스트 → 체크 다 했어" (P1~P19)
- **기록**: `docs/qa/t18-agent/CHECKLIST.md` — P1~P19 ✅ + 결과 블록(실측 빌드·P2 의미 변경)
- **P2 변경**: `ps`/`top` 은 setuid 라 **실행 불가** 안내, 값은 **`processes`** (2026-10-22 21:33, N24)
- **남은 실측**: N22·N24·N25·N26·N27·N28 · T-21 27건 · QA 배치 3·4
- **다음**: **v0.19**(쓰기 단계 경로 스코프 승인 + 휴지통 rewrite + `UndoStack` + [되돌리기] 카드)

## 이전 (2026-10-22 22:30) — 토큰 표시를 헤더 → 대화 영역 위 플로팅 칩으로

- **사용자 지적**: "제목과 토큰이 두줄… 다른 탭으로 이동하면 사이즈가 달라서 울렁거림 / 왼쪽·오른쪽 상단에 플로팅으로"
- **원인**: `headerRow` 가 대화 탭에서만 `VStack`(제목+토큰) → 탭마다 헤더 높이가 달랐다
- **한 것**: ① 헤더를 **모든 탭 한 줄**로 통일 ② 토큰은 대화 영역 **우상단 플로팅 칩**
  (캡슐·머티리얼·기준 초과 주황·툴팁 유지) ③ 첫 메시지 가림 방지로 내용 상단 14pt 예약
- **검증**: `swift test` **403/403**(6 skip) · BUILD SUCCEEDED · 렌더 `chat-ko`·`archive-search-ko`
- **배포**: 2026-10-22 22:30 · SHA-256 `0fa743d736971a19…` · **앱 재실행 필요**
- **재실행 후 확인**: **N28**(탭 전환 시 헤더 고정·칩 위치·툴팁) · N27(📌 + 설정 창) · N26(창 위치)
  → T-18 실측 → v0.19

## 이전 (2026-10-22 22:10) — 📌 항상 위가 설정 창과 함께 뜨면 꺼지던 문제

- **사용자 보고**: "대화창에서 최상위 클릭 해 놨는데 동작 안하는데? 다른 창 뜨면 뒤로 가려짐 / 대화창 + 설정창이 떠 있으면 먹히질 않음"
- **원인**: `applyPanelLevel()` 이 **설정·정보 창이 보이면 대화 창을 `.normal` 로 내렸다**(2026-10-20 가림 방지 장치) →
  핀의 의미(다른 앱 위)까지 같이 꺼졌다.
- **한 것**: ① Core `WindowLevelPolicy` — 핀 ON 이면 설정 창과 무관하게 `.floating`, 설정 창은 **쓰고 있을 때만**
  그 위(`floatingAbove`), 앱 비활성·시스템 안내 중에는 내림 ② `didBecomeKey`·`didResignActive` 관찰로
  "클릭한 창이 위로" ③ 설정 설명·툴팁 문구 갱신
- **검증**: `swift test` **403/403**(6 skip, 신규 8) · BUILD SUCCEEDED
- **배포**: 2026-10-22 22:10 · SHA-256 `291fe2ea65288b21…` · **앱 재실행 필요**
- **재실행 후 확인**: **N27**(📌 + 설정 창 동시에 → 대화 창이 다른 앱 위 유지, 설정 창은 그 위)
  · **N26**(창 위치) · N22·N24·N25 → T-18 실측 → v0.19

## 이전 (2026-10-22 21:50) — 대화 창 위치 조율 (pill 은 입력한 자리 · 설정 3옵션)

- **사용자 지적**: "pill 대화는 언제나 마우스 포인터 잖아?? … 이거 설정 핵갈리지 않니??"
- **원인**: pill 은 항상 `NSEvent.mouseLocation`(설정 무시), 창은 열 때마다 `newWindowPosition` 으로 재배치
  → 중앙 모드에서 **포인터에서 입력 → 화면 중앙으로 점프**. 창을 옮겨도 다음에 설정 위치로 되돌아감.
- **결정**(사용자 선택): **"입력한 자리 유지"** + **"마지막 위치" 옵션 추가**
- **한 것**: ① Core `WindowPlacement` — pill 자리(anchor) 우선 · 중앙/포인터 · `lastPosition` 은 지금 자리 유지
  · 화면 밖 클램프 ② `NewWindowPosition.lastPosition`(3옵션) ③ `PointerPillController.lastAnchor` →
  `showPanel(tab:anchor:)` → `positionPanel(anchor:)` ④ 라벨 "대화 창 위치" + 캡션 2줄, 번역 4키
- **검증**: `swift test` **395/395**(6 skip, 신규 10) · BUILD SUCCEEDED · 렌더 `settings-general-ko`
- **배포**: 2026-10-22 21:50 · SHA-256 `759918eaf13a93f1…` · **앱 재실행 필요**
- **재실행 후 확인**: **N26**(pill → 입력한 자리 / 보관함·Hub → 설정 / 마지막 위치 기억) · N22·N24·N25(직전 변경)
  → T-18 실측 → v0.19

## 이전 (2026-10-22 21:34) — 🧠 표시·카드 순서·`ps`/`top` 실행 불가

- **사용자 보고**: ① N22 `ERR`(🧠 가 회색으로도 안 보임) ② 실행 카드가 응답 **아래**에 뜬다
  ③ `top`/`ps` 가 `Operation not permitted`
- **원인**: ① `brain.slash` 가 **없는 SF Symbol** (macOS 27.2) → `Image(systemName:)` 이 빈 뷰
  ② `.ps/top` 은 **setuid root** → 샌드박스가 exec 자체를 거부(프로파일로 해결 불가)
  ③ 실측이 exec 거부를 **쓰기 거부**로 오분류 → 승인해도 계속 실패, `ps | head` 는 종료코드 0 이라 "성공"으로 오판
- **한 것**: ① 🧠 = `brain` 하나 + **색**으로 상태 구분(켜짐 보라·꺼짐 회색), 앱 전체 SF Symbol 점검
  ② 실행 카드를 답변 **위**로(검색 출처는 아래 유지) ③ setuid 실행 위치 탐지 → **`.blocked`**(실행 안 함) +
  "권한을 열어도 안 됨, `processes` 를 쓰라" 안내 ④ **새 도구 `processes`** — libproc 으로 CPU%/RSS 직접 읽기
  (`sort=cpu|memory`, `limit≤30`) ⑤ `AgentCapability.unprobed` 분리(중요 명령은 승인 후 실측)
- **검증**: `swift test` **385/385**(6 skip, 신규 9) · BUILD SUCCEEDED(경고 0) · 렌더 확인(회색 🧠·카드 위)
  · `--agent-test="CPU 많이 쓰는 프로세스 3개만 알려줘"` → `tool=processes state=done` 2스텝
- **배포**: 2026-10-22 21:33 · SHA-256 `c701008c270e79de…` · **앱 재실행 필요**
- **재실행 후 확인**: **N22**(회색 🧠 보임 + 눌러서 보라) · **N24**(ps/top → 실행 불가 + `processes` 값)
  · **N25**(카드가 답변 위) → N20·N21·N23(직전 확인 OK) → T-18 실측 → v0.19

## 이전 (2026-10-22 21:10) — 공용 메모리 기본값 Off

- **사용자 요청**: "공용 메모리 기본 값 Off 로 해줘"
- **한 것**: ① `globalMemoryEnabled` 기본값 `true` → `false` ② 구버전 설정 fallback 도 `false` 로 ③
  저장된 사용자 값(`~/Library/Preferences/com.borasarang.QuickTalk` 의 `QuickTalk.settings`)도 `false` 로 갱신.
- **부수(같은 세션)**: 헤더 🧠 아이콘 — 전역 OFF 여도 항상 표시(회색 · 눌러서 켜기). [2026-10-22 21:00 완료분]
- **검증**: `swift test` **376/376**(6 skip, 신규 2 = 기본 OFF) · BUILD SUCCEEDED(경고 0) · 배포 SHA-256 `f3d9b697a91174e7…`
- **재실행 후 확인**: N20(중복 실행) · N21(`rm -rf /` 차단) · N22(헤더 🧠) · **N23(공용 메모리 기본 OFF)** → T-18 실측 → v0.19

## 이전 (2026-10-22 21:00) — 공용 메모리 아이콘 (꺼도 항상 보임)

- **사용자 보고**: "공용 메모리 껐을때 안보이네???" (헤더 오른쪽 아이콘 줄 스크린샷)
- **원인**: 🧠 버튼이 **전역 설정이 켜져 있을 때만** 그려졌다 → 끄면 헤더에서 되돌릴 방법이 없었음.
- **한 것**: ① 🧠 버튼을 **항상 표시**(꺼져 있으면 `brain.slash` + 회색) ② 누르면
  전역 OFF → 전역 켜기 / 이 대화만 꺼짐 → 이 대화 켜기 / 켜짐 → 이 대화만 끄기
  ③ 툴팁을 상태별로 구분 + 영어 테이블에 없던 툴팁 문자열 정리
- **검증**: `swift test` 375/375(6 skip) · BUILD SUCCEEDED(경고 0) · 오프스크린 렌더 확인
- **배포**: SHA-256 `f83e3286e8c79d6b…` (2026-10-22 21:00). **재실행 필요**
- **다음**: 재실행 후 N20·N21·N22 확인 → T-18 실측 → v0.19

## 이전 (2026-10-22 20:40) — 안전장치 사고 대응 (`rm -rf /` 로 앱이 멈춤)

- **사용자 보고**: "이 대화 입력 후.. 열심히 뭔가 하더니.. 앱 죽었음 · 앱 강제 종료된 후 다시 실행시 응답이 사라짐 ·
  Document Music, Download 폴더의 접근 권한을 물어 봄 · 심각한 문제인데.. 내 시스템에 이 놈이 영향을 줬는지 바로 확인해"
- **시스템 영향 확인 → 없음**: `rm -rf /` 는 **한 번도 실행되지 않음**(감사 로그에 `rm` 0건).
  실측은 읽기 전용 샌드박스라 지울 수 없었고, 루트·홈·Applications·System 정상, 여분 522Gi.
- **원인 3가지**: ① [실측(실행) → 정책] 순서라 치명적 명령이 **차단 전에 실행** ② 실행이 **메인 스레드** → UI 얼음
  ③ `readDataToEndOfFile()` 를 **타임아웃 검사 전에** → 무한 대기
- **한 것**: ① `PolicyEngine.plan()` (위험→정책→실측, **실행은 마지막**) ② 실측·실행 `Task.detached` (메인 밖)
  ③ stdout/stderr 동시 비동기 읽기 + 기한 지키기 ④ 시스템 전역 경로 쓰기 **차단** ⑤ 치명적 판정 대소문자 버그 수정
  ⑥ 끊긴 질문은 다음 실행 때 "응답이 끊겼습니다" 안내로 남김 ⑦ 설정 실행 기록을 **표**로(원문 JSON 아님)
- **검증**: `swift test` **375/375**(6 skip, 신규 13) · BUILD SUCCEEDED(경고 0) · 배포 SHA-256 `6a61b998…`. **재실행 필요**
- **다음**: 재실행 후 `rm -rf / 해줘` → **즉시 차단 안내 + 앱 멈추지 않음** 확인(N21) → T-18 실측 → v0.19

## 이전 (2026-10-22 18:27) — 중복 실행 방지 (앱은 하나만)

- **사용자 보고**: "앱이 동시에 두개가 실행중이다 · 이 앱은 하나만 실행 되어야 함 · 중복 실행이 되면 안됨"
  (pill 창이 두 개 겹쳐 뜬 스크린샷).
- **원인**: 단일 인스턴스 장치가 없었다 — 설치본 + 이전 QA `--ask=` 디버그 실행 2개가 동시에 떠 있었고,
  각 프로세스가 메뉴바 아이콘·단축키·pill 창을 따로 만들었다.
- **한 것**: ① **`InstanceLock`(Core)** — `flock(2)` 파일 잠금(프로세스 종료 시 OS 가 자동 해제)
  ② **`QuickTalkLauncher`** — UIStore·AppKit 창 생성 **전**에 잠금 판정, 두 번째 실행은 기존 인스턴스를
  앞으로 올리고 `exit(0)`(분산 알림으로 기존 창 열기) ③ `Info.plist` `LSMultipleInstancesProhibited`
  ④ 예외는 **오프스크린 QA 하네스만**(`--render=`·`--*-test`·`--selftest=`)
- **검증**: `swift test` **362/362**(6 skip, 신규 4) · BUILD SUCCEEDED(경고 0) ·
  실제 바이너리 `--instance-selftest` ACQUIRED(0) → 동시 실행 BLOCKED(3) → 해제 후 ACQUIRED(0).
  배포 2026-10-22 18:27, SHA-256 `99308aec19542e10499c74f7ce809de37b6e19b4f4d51bc717778220ff7610aa`. **재실행 필요**.
- **다음**: 재실행 후 앱을 한 번 더 실행해 **새 인스턴스가 뜨지 않는지** 확인 → T-18 실측 → v0.19(쓰기·되돌리기).

## 이전 (2026-10-22 14:25) — 도구 실행 내역 보기 (실제 쉘 실행 화면)

- **사용자 요청**: "tool 명령 실행시에 **빈 칸**이 생기는 것 같다 · 저거 실제 쉘 실행 화면인가? ·
  실행하는 걸 보여줄 수 있나 · **설정에서 보여주기/보여주지 않기** 옵션".
- **한 것**: ① **빈 칸 제거**(실행 기록이 없으면 카드 자체를 그리지 않음)
  ② 카드에 **실제 명령(`$ …`) + 실제 stdout/stderr**(스크롤되는 작은 터미널 창) + 단계·위험도·경과시간 표시
  (모델이 답변에 붙인 코드블록이 아니라 **앱이 실제로 실행한 결과**)
  ③ **실행 기록을 턴에 저장**(`Turn.agentEvents`) → history.json 에 남아 나중에 다시 열어도 보임
  ④ **설정 › 도구 › "실행 과정 표시"** 토글 — 끄면 한 줄 요약만.
- **검증**: `swift test` **358/358**(6 skip) · BUILD SUCCEEDED(경고 0) · 렌더 `docs/qa/t18-agent/chat-agent-ko.png`.
  배포 2026-10-22 14:25, SHA-256 `1c7463205440aaa5fc509d60b7502e67c24809f82dab4eadc63b0f42480b98cc`. **재실행 필요**.
- **다음**: 재실행 후 확인 → v0.19(쓰기·되돌리기) → v0.20(실행 고도화).

## 이전 (2026-10-22 14:00) — 에이전트 라우팅 개편 (도구 선택을 본 모델에)

- **사용자 보고**: "지금 메모리 얼마나 차지 하고 있냐?" 가 **통하지 않음**(명령을 복사해 줘야 됨) → 퀄리티 불만.
- **원인**: v0.18 이 **"도구가 필요한가?"를 별도 분류기 모델에 물어** YES/NO 로 갈라 쓰고 있었음.
  그 분류기가 **"메모리"를 앱의 '대화 기억'으로 오해**해 NO → 도구 미사용. (질문마다 모델을 1회 더 불러 지연도 늘었음)
- **해결 — 판정 제거**: 도구가 켜져 있으면 **항상** 도구를 넘기고 **답을 쓰는 본 모델이 직접** 고른다.
  스트리밍을 유지하려고 **스트리밍 중 도구 호출 조각을 파싱**하도록 확장
  (`SSEEvent.toolCallDelta`·`.reasoning` · `OpenAIClient/OllamaClient.streamWithTools`).
  도구 호출이 오면 실행 → 결과를 되돌려 같은 대화에서 이어서 최종 답. 도구 미지원 서버(400)는 자동 폴백.
- **같이 고친 것**: ① **실패한 명령을 권한 문제로 오판**(존재하지 않는 명령까지 승인 요구) → 권한 거부 신호가 보일 때만 승격,
  나머지는 읽기로 분류해 오류를 모델에 그대로 전달 ② **같은 명령 무한 반복**(온디바이스가 `free -h` 8회) →
  같은 명령 2번까지만 실행 + Apple FM 전용 짧은 지시문(`AgentInstructions.compactText`).
- **실측(같은 질문)**: 원격(주) ✅ `vm_stat`·`sysctl hw.memsize`·`sysctl vm.swapusage` **3개 명령 자동 실행** → "총 32 GiB" ·
  Apple FM ⚠️ 도구 호출은 하지만 macOS 명령을 몰라 반복(→반복 방지로 종료) · 평범한 질문은 도구 0회.
- **검증**: `swift test` **358/358**(6 skip, 신규 4) · BUILD SUCCEEDED(경고 0) · 헤드리스 `--agent-test` 실측.
  배포 2026-10-22 14:00, SHA-256 `e66acb6d0973e9504f457836876c7362cdfe3b348bb2c77cd1f05f420aab78c6`. **실행 중 앱은 종료하지 않음 — 재실행 필요**.
- **다음**: 재실행 후 같은 질문 확인 → v0.19(쓰기·되돌리기) → v0.20(실행 고도화) → v0.21 → v0.22.

## 이전 (2026-10-22 13:05) — 캡처 윈도우 모드 수정 + pill 다중줄 입력

- **보고 1 — 윈도우 캡처가 안 된다**: 드래그 캡처 → Space → 라벨만 "윈도우"로 바뀌고 창이 안 잡힘.
  **원인**: `CaptureService.startOverlay` 가 창 목록을 **"처음부터 윈도우 모드일 때만"** 모으고 있었음(드래그→전환 시 목록이 빈 상태).
  → **모드와 무관하게 항상 수집** + 윈도우 모드 **전환 시 재수집**. 창이 0개면 힌트 문구를 바꿈.
  **검증**: QA 하네스 `--capture-selftest` 신규 → `mode=window windows=2 highlight=Y` ✅
  (시스템 창 선택 UI·OS 레벨 창 캡처는 정상 → **macOS 문제가 아니라 앱 버그**)
- **보고 2 — pill Shift+Enter 줄바꿈이 안 된다**: 요청 = "새 대화창의 대화창 입력 방식과 동일하게".
  → pill 입력을 **대화 입력창과 같은 컴포넌트(`ChatInputField`)** 로 교체(Shift+Enter 줄바꿈 · Enter 전송 · ⌘Return 대화 창 · Esc 닫기).
  pill 은 **아래 기준선 고정 + 위로 성장** → 오브·보관함 아이콘은 그 자리에 남고, 목록은 그대로 아래.
  1줄일 때 모양은 이전과 동일, 최대 4줄.
  **같이 고친 버그 2건**: SwiftUI 가 폭을 정하기 전에 측정해 높이가 1줄로 남던 문제(텍스트 뷰 폭 확정 시 재측정) ·
  값을 프로그램적으로 넣을 때 측정이 안 되던 문제(넣은 직후 재측정).
- **검증**: `swift test` **354/354**(6 skip) · BUILD SUCCEEDED(경고 0) · 렌더 `docs/qa/t18-agent/pill-multiline-ko.png` ·
  실제 앱 화면 캡처로 2줄·아이콘 유지 확인. 배포 2026-10-22 13:05,
  SHA-256 `c8118e010d684822de58ed7beeabb276ce667d945e4db76436a72aab6d73e734`. **실행 중 앱은 종료하지 않음 — 재실행 필요**.
- **다음**: 재실행 후 `docs/qa/t21-pill/CHECKLIST.md` P28~P31 · `docs/QA-CHECKLIST-2026-10-20.md` D2-1 확인 →
  T-18 실측(P1~P19) → v0.19 → v0.20.

## 이전 (2026-10-22 00:20) — T-18 v0.18 구현·배포 (도우미 도구)

- **구현**: 자연어 한마디로 앱이 **직접 명령을 실행**하고 그 결과로 답한다(v0.18).
  예: "하드 용량 얼마나 남았어" → 실제 `df -h` 실행 → "521 GiB 남음".
- **앱은 명령어 이름을 모른다** — 도구 3종(`shell`·`read_file`·`list_dir`)뿐. 모델이 정한 명령을 그대로 실행한다.
- **권한(사용자 확정)**: 배포 GitHub · **읽기(기본 자동)/쓰기/실행** 3단계를 설정 › 도구에서 선택
  + 허용 규칙(사용자가 직접 쓰는 패턴) + 대화별 오버라이드 + 전역 자동 수락 + 치명적 차단.
  판정은 **샌드박스 실측** — 읽기 전용으로 먼저 돌려 요구 권한을 알아내고, 쓰기가 막히면 경로가 나와
  "이 경로만 허용"으로 재실행한다(승인이 스코프로 제한됨). 위험도는 구조적 신호만(명령 목록 없음).
- **UI**: 대화 안에 실행 카드 + 확인 카드([한 번 허용][항상 허용][거부]) · 설정 › 도구 탭 · 실행 기록(키 가림).
- **프로바이더 3종 통일**: Apple FM(FoundationModels `Tool`) · 원격 OpenAI 호환(`tools`) · Ollama(`/api/chat`).
  **실측**: Apple FM ✅(`df -h` → 521 GiB, 16초) · 원격 ✅(도구 3 + 거부 1, 20초) · Ollama 구현만(로컬 32B 로 느려 미실측).
- **구현 중 잡은 문제 3건**: thinking 모델 2차 요청 400(`reasoning_content` 되돌려야 함) ·
  Apple FM `GeneratedContent` JSON 직렬화 크래시(`jsonValue` 변환기) · 시스템 경로 **참조**를 위험으로 오판.
- **검증**: `swift test` **354/354**(6 skip, 신규 22) · BUILD SUCCEEDED(경고 0) · 헤드리스 `--agent-test` 신규
  · 로그 `docs/qa/t18-agent/`. 배포 2026-10-22 00:06, `codesign --verify --strict` OK,
  SHA-256 `a261f40ba070a92baf33875906bbe37e2f249c8cec9def6a8d85ab0767a87327`. **실행 중 앱은 종료하지 않음 — 재실행 필요**.
- **git**: `feat/t18-agent-runtime` → **PR #4** → squash merge `23d8820`. `main` 직접 push 없음.
- **다음**: **사용자 실측**(`docs/qa/t18-agent/CHECKLIST.md` P1~P19) → v0.19(쓰기·되돌리기) → v0.20(실행 고도화) →
  v0.21(스크린샷·Shortcuts) → v0.22(스트리밍 tool_calls 수집). 그 사이 T-21 실측·QA 배치 3·4 대기 유지.

## 이전 (2026-10-21 23:20) — T-18 에이전트 런타임 설계 + 스파이크 2개

- **문제(사용자)**: QuickTalk은 "맥 도우미"다. 자연어 한마디로 앱이 **직접 행동**해 답해야 한다
  ("인터넷 속도 체크", "하드 용량", "다크 모드", "이번주 일정", "산소방문 일정", "S22에 앱 설치", "whisper-cpp 설치").
- **설계 정정(중요)**: 도구 카탈로그(`disk_usage`·`calendar_list`…)는 **천장이 있다** — `brew`·`adb`·`pip`·`uv`·`ollama`는
  사용자가 든 예시일 뿐이고, 모델이 정하는 명령을 **앱은 그대로 실행만** 해야 한다.
  → **"실행 원시(`shell`·`read_file`·`list_dir`·`web_search`) + 에이전트 루프"** 로 전환. 앱에 명령어 사전 0개.
- **권한(사용자 확정)**: 배포는 **GitHub**(샌드박스 OFF 유지) · **읽기(기본 자동)/쓰기/실행** 3단계를 설정에서 선택
  + 허용 규칙 + 대화별 오버라이드 + **전역 자동 수락**(OpenCode 방식) + 치명적 명령 차단.
- **권한 판정 방식**: **분류가 아니라 협상** — 읽기 전용 샌드박스로 먼저 실행해 요구 권한을 **실측**한다.
  쓰기가 막히면 에러 메시지에 경로가 함께 나온다 → "이 경로만 쓰기 허용"으로 재실행(스코프 제한).
  위험도는 **구조적 신호**만(상승권·시스템영역·파이프→인터프리터·재귀삭제 대상) — 명령/패키지 이름 목록 없음.
- **스파이크 2개 PASS** (`docs/qa/t18-spike/`):
  ① Apple FM tool calling — FoundationModels `Tool` 직접 구현으로 실제 호출 성공(4.0초).
     `call(arguments:)` 는 `respond(to:)` 안에서 자동 실행 → 정책 게이트는 `Tool.call` 안에서.
  ② 샌드박스 권한 협상 — 읽기 4종·쓰기(경로)·네트워크·상승 권한 정확히 분류, 허용 밖 쓰기 차단, 위험도 7/7 정확.
- **스파이크가 찾은 함정 4건(수정 완료)**: 경로가 메시지보다 먼저 옴 / 네트워크 차이는 도구 신호로 옴(curl 6·ping 68) /
  `"rm -rf /"` 접두사 오판 / `|` 토큰화 누락. 추가로 `resolvingSymlinksInPath` 는 `/var` 를 못 풀므로 `realpath(3)` 사용.
- **문서**: `docs/plans/PLAN_v0.18_agent-runtime_macos.md` (설계·권한 모델·로드맵 v0.18~v0.22).
- **git**: 브랜치 `feat/t18-agent-runtime` (main 기준 분기, push 전).
- **다음**: **v0.18 구현**(`AgentTool`·`AgentClient`·`AgentRunner`·`SandboxRunner`·`RiskClassifier`·`PolicyEngine`·실행 카드)
  → v0.19(쓰기·되돌리기) → v0.20(실행·확인 시트·감사 로그) → v0.21(스크린샷·Shortcuts) → v0.22(권한 고도화).
  그 사이 T-21 실측(P1~P27)·QA 배치 3·4는 대기 유지.

## 이전 (2026-10-21 20:43) — T-21 포인터 pill 구현·배포

- **확정(사용자)**: pill은 대화 창과 **별개가 아니라 같은 대화의 컴팩트 표현**. 설정 › 일반 “단축키로 열 때 유지” 규칙을 **그대로** 따르고, 결과가 **새 대화**일 때만 pill. **0(사용 안 함) = 항상 pill**. **마이크 삭제**, 보관함은 **최근 대화 4개 작은 목록(1클릭 이어가기)**.
- **판단(Core)**: `ShortcutEntryPresentation.decide` — 유지 시간 이내 + 턴 있음 = 대화 창 / 초과·턴 없음·활동 없음·0 = pill. 설정 의미·기본값(10분)·픽커는 **변경 없음**.
- **구현**: `QuickTalkApp/PointerPill.swift` — borderless `NSPanel`(380×56, 모서리 28), 포인터=캐럿 위치(왼쪽 −55pt, 세로 중심), 화면 안 클램프. 입력은 단일 행 `NSTextField`(한글 조합 Enter 확정). **Enter = 새 대화 + 질문 전송 + 대화 창**, **⌘Return = 대화 창만(초안 유지 — 첨부용)**, **Esc/바깥 클릭/⌘Space = 닫기**, 닫을 때 직전 앱으로 포커스 복귀(바깥 클릭 제외). 보관함 아이콘 → **같은 창을 아래로 늘여** 최근 4개 + `보관함 전체 열기(⌘L)`. pill이 떠도 대화 상태는 건드리지 않고, 전송 시점에만 `startShortcutSession()`.
- **시각**: 액센트 `#7A5CFF`. 시스템 머티리얼은 창 가장자리 1pt 이음새가 보여 반투명 솔리드로 대체. **`Capsule().strokeBorder`가 좌우 끝에 남기는 1pt 세로 이음새**를 렌더로 발견 → `RoundedRectangle(cornerRadius: 28, style: .circular)`로 교체.
- **검증**: `swift test` **332/332**(6 skip, 신규 6), BUILD SUCCEEDED(경고 0), 오프스크린 렌더 `docs/qa/t21-pill/`(빈·입력 중·목록, 한/영) · `docs/qa/t21-pill-light/`.
- **문서**: `docs/plans/PLAN_v0.17_pointer-pill_macos.md`, `docs/qa/t21-pill/CHECKLIST.md`(P1~P27).
- **배포**: 2026-10-21 20:43 `~/Applications/QuickTalk.app` 교체·`codesign --verify --strict` OK, SHA-256 `ebc78fe9a55fb962467a89928d43d95a3fb91aad1bd895b14cac021f5ab2ca7c`. **실행 중 앱은 종료하지 않음 — 재실행 필요**.
- **git**: `feat/t21-pointer-pill` → PR #2 → squash merge `6d344cf`. 디버그 렌더는 `.gitignore` 제외.
- **다음**: **사용자 실측**(재실행 후 P1~P27) → QA 배치 3(기억·공통 메모리 21건) → 배치 4(QuickShelf·캡처·음성·오류 27건).

## 이전 (2026-10-21 15:14) — 실사용 크래시 수정 + 헤더 정리·상대 시간·맨 아래로

- **신고**: 배치 2 A·B **OK**, **K 도중 앱 사망** — "이미지 첨부 있는 질문 수정 후 대화 요청 시 죽음".
  추가 요청 4건: 뇌 아이콘 설명 · 헤더 아이콘 크기/툴팁 · 응답 상대 시간 + 보관함 마지막 대화 시간 · 맨 아래로 버튼.
- **크래시 원인**(`QuickTalk-2026-10-21-145819.ips`): `searchWeb`이 `await` 뒤 **협력 스레드에서 `settings`(@Published)를 수정**
  → SwiftUI가 메인 밖에서 `ChatInputField`를 갱신 → `NSWindow drag regions should only be invalidated on the Main Thread!` NSException → SIGABRT.
  첨부 자체가 아니라 **검색 판정이 붙는 경로**가 방아쇠였다.
- **수정**: `searchWeb`·`answerWeb` **`@MainActor`**, `ChatInputField.measure`에 **메인 스레드 가드**(재발 시 크래시 대신 측정만 건너뜀).
- **UI**: ① `headerIcon` 헬퍼로 핀·🧠·🔖·✏️·퀵셸프·탭 3종을 **22×22 동일 크기**·활성 보라·**전부 툴팁**(🧠는 공통 메모리 설명) ② 토큰 진행률 축약(`92 / 21k · 0%`, 정확한 값은 툴팁) ③ `Turn.createdAt` + Core `RelativeTime` → 답변 푸터 `9분 전 · 1.2초`, 보관함 행 상대 시간, 60초마다 갱신 ④ `GeometryReader`+`PreferenceKey`로 바닥 감지 → **우하단 원형 ↓ 버튼**.
- **검증**: `swift test` **326/326**(6 skip, 신규 6), BUILD SUCCEEDED, 오프스크린 렌더 `docs/qa/t74-ko/chat-ko.png`(바닥에서 버튼 숨김 확인 — 첫 렌더에서 뷰포트 갱신 순서 버그를 발견해 수정).
- **배포**: 2026-10-21 15:14, SHA-256 `4b82e52d02bf78c92b884c27530affb6d95aefe7b8b5eee8ac48d1ad4c25c4c4`. **재실행 필요**.
- **사용자 확인(15:55)**: **배치 2 34건 전부 OK**(K3 포함), **N16·N17~N19 OK**. 크래시 재현 없음.
- **다음**: **QA 배치 3**(기억·공통 메모리 21건) → **배치 4**(QuickShelf·캡처·음성·오류 27건).

## 이전 (2026-10-21 14:34) — 응답 중지(⏹) · Ollama 전용 범위 검증

- **배경**: Ollama 타임아웃을 300초로 늘리자 **멈춘 요청에서 빠져나갈 수단이 없었다**(대기 중 입력독·전송 비활성, 취소 경로 없음). 로컬 32B는 정상 동작도 1~2분.
- **수정**: `UIStore.replyTask` + `cancelReply()` — 응답 중 전송 버튼이 **⏹ 중지**(빨강)로 바뀐다. 부분 출력은 남기고 `⏹ 중지됨`만 덧붙임(출력 없으면 `응답을 중지했습니다.`). 취소는 **오류로 처리하지 않는다**.
- **폴백 가드**: `ProviderFallback.allowed` — `CancellationError`·`URLError.cancelled`는 **예비 모델로 넘어가지 않는다**(멈춘 응답이 Apple FM에서 되살아나는 것 방지). 시간 초과는 그대로 폴백.
- **범위 검증(Ollama 전용 확인)**: Apple FM `results=8 chars=2000 cap=938`·6.1초(원복 확인) / 원격 `cap=10154`·13.1초(변화 없음) / Ollama 판정 `YES 5,815ms`(20초 상한 유지).
- **검증**: `swift test` **320/320**(6 skip, 신규 1), BUILD SUCCEEDED, `codesign --verify --strict` OK.
- **배포**: 2026-10-21 14:34, SHA-256 `e70d4cf011d62cde2215c72015471ff14d34170b339550a9217c41a2041419c1`. **재실행 필요**.
- **다음**: QA **N16**(중지 버튼) → **배치 2**.
- **2026-10-21 14:40 사용자 확인**: "Ollama 동작 잘되, 배치 2로" → Ollama 작업 종료, **배치 2 진행**. K12 기대값을 새 트리거(**Ollama ≈2,150토큰**)로 갱신.

## 이전 (2026-10-21 14:15) — 로컬 Ollama 시간 초과·느림 수정

- **신고**: `ollama ps`는 정상(21GB·100% GPU)인데 답변이 없고 `시간 초과 (NSURLError -1001)` → 예비 Apple FM이 대신 답변.
- **원인(서버 로그 근거)**: 앱이 보낸 프롬프트 **6,765토큰**, 60초 동안 4,647토큰만 처리(프롬프트 72~140 tok/s·생성 3.8~6.4 tok/s), **정확히 1m0s에 클라이언트가 끊음**(`aborting chat request due to client closing the connection`). Ollama는 정상. 같은 로그의 47토큰 요청은 13초에 완료 — "Ollama 앱은 빠르다"의 이유는 프롬프트가 140배 작기 때문.
- **수정 A**: `OllamaClient.requestTimeout = 300`(원격은 60 유지).
- **수정 B**: `WebSearchPromptLimits`(Core 신규) — **Ollama만 4건·800자**(컨텍스트 상한 1,200토큰) / Apple FM·원격은 설정값 그대로·입력예산 1/3. `ConversationMemory.promptBudget` — Ollama 기본 **3,072토큰**(명시한 컨텍스트 토큰은 존중). UIStore 3개 주입 경로·출처 카드 수·하네스까지 같은 한도. 설정 캡션 2개(Ollama일 때만) + 번역.
- **검증**: `swift test` **319/319**(6 skip, 신규 9). E2E `--search-answer-test` Ollama: 프롬프트 6,765→**1,516토큰**, 서버 처리 110.3→**28.5초**, 60초 차단 → **OK**(답변 122자·인용 2). 전체 139.9초 중 93초는 다른 요청과의 경합 대기.
- **배포**: 2026-10-21 14:25(범위 축소 후 재배포) `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK, SHA-256 `53f1ddc01cfd7b728a0e337c47d1d09cef9b188a361de48f5c5f0b417f92efb8`. **재실행 필요**(구 빌드 실행 중).
- **범위 확정**: 사용자 지시("Ollama에만 적용해놔")로 **Ollama 전용**. Apple FM에 잠깐 걸렸던 축소(3건·600자·상한 900)는 원복 — Apple FM은 원래 잘 동작하므로 손대지 않는다.
- **N15 사용자 확인 완료**(14:26) — Ollama 답변 O. 로컬 32B 속도 한계는 수용.
- **한계**: 32B Q4는 이 맥에서 생성 4~6 tok/s — 300토큰 답변이면 50~75초는 구조적. **14B 이하 모델 권장**. Ollama 앱과 동시 사용 시 요청 직렬화로 대기.
- **운용 방침**: **원격 OpenAI 호환 주 + Apple FM 예비**. 로컬 Ollama는 보조.
- **다음**: **배치 2**(대화·입력·보관함 34건).

## 이전 (2026-10-21 13:51) — QA 배치 1 완료 (실패 0)

- **배치 1 실측 결과**: 웹 검색·폴백 17건 **실패 0건**.
  - 사용자 직접 확인: I1(설정) · I2(검색 테스트) · I3(뉴스 자동 판정) · I4(출처 클릭) · I5(🌐 강제) · I5-1(불필요 질문 미검색) · L1(인용 `[n]` 클릭) · N12(판정 타임아웃 수정) · N13(재시도·[웹에서 찾기]) · N14(예비 AI 폴백).
  - 판단 확인(이전 세션 근거): I6(키 삭제 시 답변 지속) · I7(검색 끄면 외부 요청 0) · L4(하루 한도·사용량).
  - 간접 확인: L2([웹에서 찾기] = N13 경로) · L3(판정 캐시 TTL 로직) · N11(헤드리스·단위 테스트).
  - 미확인(선택): I8 영어 모드.
  - **해석**: 오늘 수정한 4건(10:39 판정 타임아웃 · 11:05 판정 재시도·감지 확장 · 12:40 예비 AI 폴백 · 13:05 폴백 문구)이 **모두 실사용에서 통과**했다.
- **다음**: **QA 배치 2 — 대화·입력·보관함 34건**(A1~A14 · B1~B5·B2a · K1~K13·K12a). 결과 형식 `배치2: A1 OK / A3 새 대화 안 됨`.
- **문서**: `docs/QA-CHECKLIST-2026-10-20.md` 헤더·배치표·집계(**102→86**·배치1 근거 표), HANDOFF §0·§3, 이 항목.

## 이전 (2026-10-21 13:20) — 세션 41 종료 (예비 AI 폴백 실측 확인)

- **마지막 완료**: 사용자 요청("AI 폴백 기능에 대해서 적용 된거 있나 확인하고 설명해봐") → 감사 후 **예비 모델 폴백** 구현.
  ① **감사 결과**: 폴백은 부분적이었다 — 키 없는 원격 → Apple FM(시작 시), 툴 콜링 → 주입, `/answer` → `/search`, 스트리밍 → JSON, 첨부 재시도 사다리. **요청 실패로 다른 프로바이더로 넘어가는 경로는 0건**이었고, 어제 429도 그래서 사용자가 직접 다시 보내야 했다.
  ② **설정**: `fallbackProviderID`(기본 "" = 사용 안 함, 구버전 JSON 호환) + `fallbackProvider`(같은 모델·비활성이면 nil). 설정 › AI에 **예비 AI (실패 시 1회)** 픽커, 주 모델 변경·예비 삭제 시 자동 해제.
  ③ **판정**(Core `ProviderFallback.allowed`): 429·5xx·빈 응답·키/요청 거부·시간 초과·연결 실패 → 전환. **403(정책)·첨부 거부(413/422)·설정 오류는 전환 안 함**.
  ④ **실행**(`UIStore.streamReplyWithFallback`): 준비된 예비 모델로 **1회만**. 예비 예산이 작으면 `fitHistory`로 오래된 턴을 덜어낸다. 첫 델타에서 `⚠️ 주 모델(X) … 예비 모델(Y)로 답했습니다 — 원인` 안내. 예비도 실패하면 두 실패를 합친 오류. `E-MAC-FALLBACK-0001/0002`.
  ⑤ **검증**: `swift test` **309/309**(6 skip, 신규 5), BUILD SUCCEEDED, QA `--fallback-test` → `[WARN] E-MAC-FALLBACK-0001 …` + `OK chars=88 deltas=2 ms=1979 note=1`(주 모델 127.0.0.1:9 즉시 실패 → Apple FM 답변), 렌더 `docs/qa/fallback-settings-ko`.
  ⑥ **배포**: 2026-10-21 12:40 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK, SHA-256 `ca903581b5fe8d6812345e4c0ec3c5822e8ae9d8665a96e4839c16d7e6dfb911`. QA **N14**, HANDOFF §2.0.4.
  ⑦ **실사용 확인 + 문구 정리(13:05)**: 스크린샷에서 429 → `예비 모델(Local Apple FM)` 답변 + 안내 확인 ✅. 안내가 길고 `[server_error]`가 섞여 `ProviderFallback.reason(for:)`로 `사용 제한 (HTTP 429 · E-MAC-NET-0004)` 한 줄만 남김(업스트림 코드 문자열 비노출), 데모 렌더 `--demo-fallback` 추가. 테스트 **310/310**, 렌더 `docs/qa/fallback-note-ko`, 13:05 재배포 SHA-256 `86a35425176e858287e34efc6dab897ca1720817ea18a6379b5e268fc6327bbf`.

  ⑧ **세션 종료(13:20)** — 13:05 빌드·문서 sync 완료, **미해결 결함 없음**. 다음 세션은 QA **배치 1**(웹 검색·폴백 17건)부터: `docs/QA-CHECKLIST-2026-10-20.md` 상단 `## 실측 순서 (배치)` 표. 남은 개선 후보(미승인): 일반 질문 429/5xx 재시도.

## 이전 (2026-10-21 11:05) — 판정 일시 오류 1회 재시도 + [웹에서 찾기] 감지 확장

- **마지막 완료**: 사용자 스크린샷 신고 대응 — `오늘 서울 날씨를 보내 주세요`가 **검색 없이** 답변됨.
  ① **진단**: 실행 앱은 10:39 배포본(`51ccbb0f…`), `history.json` 1번째 답변 `sources=0`(=검색 미실행), 같은 문장 지금 판정 **YES 1,963ms**, 같은 시각 2번째 응답 **HTTP 429**, Exa 사용 10→11(검색 1회는 실행) → **판정 호출이 429를 맞고 실패 → 조용히 "검색 안 함"**.
  ② **수정 A — 재시도**: `WebSearchQuery.classifierRetryAllowed(after:)`(Core) — 429·5xx·네트워크·인증은 400ms 후 **1회 재시도**, **시간 초과(`E-MAC-SEARCH-0004`)는 재시도 안 함**(이미 제한 시간만큼 대기). 로그에 `시도 1/2`·최종 실패 사유(코드·제한·경과). 화면 배너는 띄우지 않는다.
  ③ **수정 B — 감지 확장**: `looksLikeSearchRefusal`이 **도구·기능 부재 + 실시간/웹 맥락**을 잡는다("실시간 날씨 정보를 **조회하는 기능이 없**습니다" = 실사용 문구). 오탐 방지 — "최신 버전에서는 이 기능이 없습니다"·"웹사이트 디자인을 추천해 드릴게요"는 제외(테스트 고정). 효과: 판정이 두 번 실패해도 **[웹에서 찾기]**로 한 번에 복구.
  ④ **하네스 수정**: `--demo-search-refusal=tool`처럼 값이 붙은 인자를 `.contains`(정확 일치)로 비교해 기본 데모가 그려지던 버그 → `hasPrefix`.
  ⑤ **검증**: `swift test` **304/304**(6 skip, `testClassifierRetryPolicy` 신규·`testSearchRefusalDetection` 확장), BUILD SUCCEEDED, 정상 경로 `--search-decide-test` **YES 2,444ms·시도 1**, 렌더 `docs/qa/web-retry-tool-ko`·`web-retry-classic-ko` 둘 다 [웹에서 찾기] 확인.
  ⑥ **배포**: 2026-10-21 11:05 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK, SHA-256 `70a15deed1bd04c496e4536082097c5169d40866f0f908c6a360cd8d7df2a98a`. QA **N13**, HANDOFF §2.0.3. **재시도 경로는 429를 결정적으로 재현할 수 없어** 단위 테스트+정상 경로로만 검증.
  ⑦ **참고**: 429는 앱 결함이 아니라 **프록시(192.168.86.30:8791) 사용 제한**이다. 사용자 사용 중 실측을 줄인다.

## 이전 (2026-10-21 10:40) — 헤드리스 실측 + 검색 필요 판정 타임아웃 수정

- **마지막 완료**: **헤드리스 실측**(툴 콜링·`/answer`·검색→주입→스트리밍·기억 정리·사용량·파일 권한) **+ 판정 타임아웃 결함 수정**.
  ① **실측 결과**: `--tool-test` 8건 16.3초(프록시 tools 지원), `--provider=applefm --tool-test` `FALLBACK unsupported` 10ms(네트워크 0회), `--answer-test` 183자·인용 8건 2.6초, `--search-test` 8건 6.4초, `--search-answer-test` 8건·922자·인용 4·델타 594·9.6초, `--compact-test=20` 2,100→868토큰(요약 296자·recent 5), `--provider=applefm --compact-auto-test=20` `expected=YES → summary=YES` 2,160→537, 하루 사용량 4→9(성공 시에만), `memory.json` 0600.
  ② **결함**: 검색 필요 판정이 **고정 4초**라 원격에서 `오늘 서울 날씨` **3/3 = 4,015ms 초과 → NO 오답**(Ollama 4,249ms 초과도 동일) — 검색을 켜 둬도 그 질문은 검색되지 않았다(로그만, 화면 표시 없음).
  ③ **수정**: `WebSearchQuery.classifierTimeout(for:)`(Core, 테스트 대상) = **Apple FM 5초 / 원격 8초 / Ollama 20초**. Apple FM 실측 0.5~3.0초, 원격 1.2~5.6초, Ollama는 **모델 로드 13초**(`eval_count=2`, 워밍 후 0.4~1.0초) — 취소하면 로드가 중단되어 다음 답변도 콜드가 되므로 로컬은 기다린다. 실패 로그에 **원인 코드 + 적용된 제한**을 남긴다.
  ④ **보류(검토 후)**: 일시적 오류 1회 재시도 — 최악 대기가 두 배가 되어 지연 우선 원칙과 충돌.
  ⑤ **검증**: `swift test` **303/303**(6 skip, `testClassifierTimeoutIsProviderAware` 신규), BUILD SUCCEEDED(경고 0), 수정 후 재실측 원격 6/6 YES(1.2~1.7초)·`구구단` NO 유지·Apple FM YES/NO·Ollama 워밍 YES, 2026-10-21 10:39 배포·`codesign --verify --strict` OK, SHA-256 `51ccbb0fc9b5c10830a2b4b4fa6a5a8cc0130fbc00e9a472ada8db448d84ad1f`. QA **N12**, HANDOFF §2.0.2.

## 이전 (2026-10-21 07:02) — 공통 메모리 P1~P3 · 웹 툴 콜링 · Exa `/answer` + 감사

- **마지막 완료**: 사용자 요청 **“공통 메모리 P1·P2·P3 다 구현” + “웹 툴콜링·/answer API 구현”**.
  ① **공통 메모리**(`GlobalMemory.swift`, 설정 › AI › 공통 메모리): 모든 대화에 적용되는 사용자 작성 사실을 여러 개 저장·편집·삭제·켜기/끄기·순서 변경. **P1** 항상 주입 + 토큰 예산(기본 800, 400/1600/3200 선택) + 대화별 🧠 끄기. **P2** 태그·검색·JSON 가져오기/내보내기·`항상 포함`·관련 항목만 모드. **P3** 로컬 해시 임베딩(2,048차원, 2-gram) cosine으로 질문 관련 항목만 선택(외부 API 없음). 저장 `~/Library/Application Support/QuickTalk/memory.json`, 요청 순서 `공통 메모리 → 대화 요약 → 최근 원문 → 검색 → 질문`, `fitHistory(extraTokens:)`로 기록 예산에서 메모리 몫 선예약.
  ② **웹 툴 콜링**: `WebSearchTool` OpenAI `tools` 스키마 + `tool_calls` 파싱, `OpenAIClient.completion(messages:tools:)`/`stream(messages:)`. 모델이 `web_search`를 호출하면 앱이 검색해 결과를 주입하고 최종 답변을 스트리밍. `tools` 미지원(400)·키 없음이면 기존 주입으로 자동 폴백. 실측 `--tool-test` → 검색 8건·7.4초.
  ③ **Exa `/answer`**: `ExaAnswer` 요청/파싱/프롬프트 참고 블록 + `ExaAnswerClient`. `answer`+`citations`를 참고 초안으로 넣고 선택 모델이 다시 씀(인용 유지), 실패 시 `/search` 폴백. 설정 › AI [답변 방식] 픽커 + [/answer 테스트]. 실측 `--answer-test` → 답변 218자·인용 8건·3.4초.
  ④ **감사·리팩터링**: ① 툴 콜링 모드에서 Apple FM/Ollama가 검색을 아예 건너뛰던 버그 수정(주입 판정 폴백) ② 400/404/422만 주입 폴백, 401·429·5xx·네트워크는 검색 없이 답변(`E-MAC-TOOL-0004`) ③ 검색 컨텍스트를 입력 예산의 1/3로 자르고 실제 토큰으로 기록 재조정 ④ 한도 도달 후 캐시 우선, `/answer` 10분 캐시 ⑤ 알 수 없는 enum 1개가 설정 전체를 초기화하던 문제 수정 ⑥ `memory.json`·`.corrupt` `0600`, 깨진 파일 백업 ⑦ 메모리 임베딩 캐시·`fitHistory` O(n²)→선형·이진 탐색 자르기.
  ⑤ **검증**: `swift test` **302/302**(6 skip, 기능 31 + 감사 10), BUILD SUCCEEDED, `codesign --verify --strict` OK, 오프스크린 렌더 `docs/qa/audit-2026-10-21-memory/`·`...-chat/` 확인. 계획 `docs/plans/PLAN_v0.16_common_memory_macos.md`, `PLAN_v0.14` P3 갱신, QA 체크리스트 **N1~N11**. **사용자 실측 대기**.


## 이전 (2026-10-21 04:30)

- **마지막 완료**: **사용자 확인 후속 4건** — ① 질문 `⋯`를 사용자 말풍선 **오른쪽·세로 중앙**으로 ② `E-MAC-NET-0003`(HTTP 503·`server_error`)을 **모델 서버 과부하·점검·프록시 오류**로 설명, 상태 카드·말풍선·연결 테스트에 원인/HTTP/서버 코드 표시 ③ QuickShelf에서 **첨부로 사용한 파일·캡처 카드는 목록에서 제거**(파일 원본 유지, 캡처는 임시 복사 후 원본 삭제) ④ 설정 › AI 기억 카드에 **[보기]** + 두 위치 안내. 테스트 **261/261**(6 skip), BUILD SUCCEEDED, 렌더 `docs/qa/question-menu-ko`, `memory-view-ko`, `ai-503-ko`, 2026-10-21 04:30 배포·서명 OK.
- **직전 완료**: **macOS 잔여 로드맵 배치** — H4 핸들 제거, T-17 설정 하단 여백, 웹 P2/P3, 기억 강제 축약·요약 편집, QuickShelf 캡처 후 툴바. 테스트 **260/260**(6 skip), 2026-10-21 02:20 배포·서명 OK.
- **그 이전 완료**: **T-73 대화 헤더 기억 토큰 진행률** — 제목 아래 `현재 / 자동 정리 기준 · %`, 기준 초과 시 주황. 테스트 **252/252**(6 skip), 2026-10-21 01:07 배포·서명 OK.
- **다음 작업**: **사용자 실측** — 새 빌드로 완전 종료 후 재실행. ① 질문 오른쪽 `⋯` 위치·다시 응답/질문 수정 ② 설정 › AI › 대화 기억 정리 **[보기]**와 입력독 위 배너 [보기] ③ QuickShelf 파일·캡처를 첨부하면 **카드가 사라지는지** ④ AI 오류 상태 카드의 HTTP·서버 코드·원인·다음 행동. 확인 항목은 `docs/QA-CHECKLIST-2026-10-20.md` **M**.
- **요약 시점 안내**: 자동 정리는 **요청 문맥 예산의 70%**를 넘은 뒤 **다음 답변을 마친 뒤** 실행된다. Apple FM ≈1,971토큰, **Ollama 기본 ≈2,150토큰**(문맥 3,072의 70% — 2026-10-21 Ollama 전용 절약), 원격 기본 32,768이면 **≈21,324토큰**부터. 더 일찍 원하면 프로바이더의 `컨텍스트 토큰`을 실제 모델 값보다 낮게(예: 8,192) 두거나 [지금 정리]를 누른다.
- **실측 대기**: 이번 후속(질문 메뉴·503 상세·QuickShelf 사용 후 제거·기억 [보기]), T-71(대화 기억), T-67(AI 오류 원인), T-59~60(단축키 녹화·Piper), T-43(QuickShelf 오버레이 — 이전 확인 범위 밖이면). 전체는 `docs/QA-CHECKLIST-2026-10-20.md`.
- **보류·미착수**: H3(다크/틴티드 아이콘 아트워크 에셋). 기억 **임베딩/장기 기억 검색**, QuickShelf **주석·스크롤 캡처·OCR**, 웹 **툴콜링·Exa `/answer`**는 미착수. T-22(전체 클립보드 검색 레이어)는 사용자 결정으로 **현재 스트립으로 충분 — 종료**. T-21(포인터 pill)은 2026-10-21 20:35 **구현 완료**(실측 대기).
- **기준선**: `swift test` **261/261**(6 skip = QT_LIVE 4 + QT_LIVE_STREAM 2), BUILD SUCCEEDED(경고 0). git 저장소 아님.
- **사용자 확인 OK (2026-10-21)**: T-72·T-70·T-27·T-28·T-18·T-20·T-36·T-56~T-58·T-62~T-66·T-68~T-69. 이력의 “실측 대기” 표기는 작성 당시 상태다.

## 전체 이력

- 2026-10-21 macos: **[실측] QA 배치 1 완료(웹 검색·폴백 17건, 실패 0)** — 13:05 빌드로 I1~I5·I5-1·L1·N12·N13·N14 직접 확인, I6·I7·L4 판단 확인, L2·L3·N11 간접 확인, I8(영어 선택) 미확인. **오늘 수정한 4건이 실사용에서 모두 통과**. 코드 변경 없음, QA 미체크 102→**86**, 다음은 **배치 2(대화·입력·보관함 34건)**.

- 2026-10-21 macos: **[기능] 예비 AI 폴백** — 위 §지금 참조. 429·5xx·시간 초과·연결 실패에서 설정한 예비 모델로 **1회** 전환, 403·첨부 거부·설정 오류는 제외. `ProviderFallback`(Core) + `streamReplyWithFallback` + 설정 픽커 + 테스트 5건 + QA `--fallback-test`. 테스트 **309/309**, 12:40 배포·서명 OK, QA **N14**.
- 2026-10-21 macos: **[수정] 판정 일시 오류 1회 재시도 + [웹에서 찾기] 감지 확장** — 위 §지금 참조. 실사용에서 프록시 429 중 판정이 조용히 실패해 `오늘 서울 날씨`가 검색 없이 답변됨 → `classifierRetryAllowed`(시간 초과만 제외, 400ms 후 1회), `looksLikeSearchRefusal`에 **도구·기능 부재** 패턴 추가("실시간 … 조회하는 기능이 없습니다"), 하네스 `hasPrefix` 수정. 테스트 **304/304**, BUILD SUCCEEDED, 11:05 배포·서명 OK, QA **N13**.
- 2026-10-21 macos: **[실측+수정] 헤드리스 실측 · 검색 필요 판정 타임아웃 프로바이더별** — 위 §지금 참조. 툴 콜링·`/answer`·검색 E2E·기억 정리·사용량·파일 권한 실측에서 **고정 4초 판정 타임아웃**이 원격·Ollama의 `오늘 서울 날씨`를 조용히 "검색 안 함"으로 만들던 결함을 찾아 `WebSearchQuery.classifierTimeout`(Apple FM 5/원격 8/Ollama 20초)으로 수정. 테스트 **303/303**, BUILD SUCCEEDED, 10:39 배포·서명 OK, QA **N12**.
- 2026-10-21 macos: **[감사] 기능 오동작·성능·문서 sync** — 위 §지금 참조. ① 툴 콜링 + 비 OpenAI 검색 누락, 툴 실패 분류(폴백 vs 중단), 검색 컨텍스트 예산(입력 1/3 + 기록 재조정), 캐시/한도 순서, `/answer` 캐시, enum 설정 복원, 가져오기 저장 안내, `memory.json` `0600`·`.corrupt` 백업, 메모리 임베딩 캐시·`fitHistory` 선형화. 테스트 **302/302**(6 skip, 감사 신규 10), BUILD SUCCEEDED, 렌더 `docs/qa/audit-2026-10-21-*`.
- 2026-10-21 macos: **[기능] 공통 메모리 P1~P3 + 웹 툴 콜링 + Exa `/answer`** — 위 §지금 참조. `GlobalMemory`(항목·태그·예산·로컬 임베딩·JSON), 설정 카드/편집 시트/가져오기·내보내기, 대화별 🧠, `memory.json`, `WebSearchTool`·`ExaAnswer`, `WebSearchMode`(주입/툴/answer), `--tool-test`·`--answer-test` 하네스. 테스트 292/292(당시, 신규 31: 공통 메모리 18 + 웹 툴/answer 12 + 기록 예산 1), BUILD SUCCEEDED. 계획 `PLAN_v0.16`, QA **N**.
- [x] **사용자 확인 후속 — 질문 메뉴 위치·503 상세·QuickShelf 사용 항목 제거·기억 [보기]**(2026-10-21 04:30) — ① `ContentView` 사용자 말풍선 오른쪽에 26pt 예약 + `questionMenu`를 trailing overlay로 옮겨 세로 중앙 정렬. ② `ServerFailure.upstream`을 “모델 서버 과부하·점검·프록시 오류”로 설명하고 `userMessage`에 원인·HTTP·서버 코드·host, `statusMessage`에 2줄 상태 카드 문구. `E-MAC-NET-0003` = 업스트림 5xx(503/`server_error`)임을 명시. ③ `attachShelfFile`은 첨부 후 카드 제거, `attachCapture`는 `QuickTalk/clip` 임시 복사 후 원본+카드 삭제. ④ 설정 › AI 기억 [보기] + `MemorySheet` 연결, 캡션에 입력독 위 배너와 이 화면 두 위치 안내. 테스트 **261/261**(6 skip, 503/server code/host 1건 추가), BUILD SUCCEEDED, 렌더 `docs/qa/question-menu-ko`, `memory-view-ko`, `ai-503-ko`; 배포·서명 OK.
- [x] **macOS 잔여 로드맵 배치 — H4·T-17·웹 P2/P3·기억 편집·캡처 툴바**(2026-10-21) — 사용자 결정(H4 제거 / T-17 추천 / T-22 현재 스트립 충분 / H2 워터마크 없음 / 4-3 추천 방향 진행)에 따라 구현. ① **H4**: `ShelfHandleView`·`handleWindow`·`buildHandle`·`handleFrame`·`repositionHandle`·`setHandleVisible`·`shelfEnabled` 설정/UI를 제거. QuickShelf는 `⇧⌥V`·헤더 버튼·창 안 오버레이로만 연다. ② **T-17**: 기본 창 높이 유지, 전면 설정 상세 하단 18→10pt, 대화 창 설정 카드 마지막 하단 여백 제거. ③ **웹 P2**: `CitationLinks`가 코드 블록/인라인 코드 밖의 `[n]`을 `[[n]](url)`로 바꾸고 `MarkdownInline`이 `[n]` 라벨 링크로 렌더 → 클릭 가능. `WebSearchQuery.looksLikeSearchRefusal` + 답변 아래 **[웹에서 찾기]** → 같은 질문을 `forceWebSearch`로 재전송. 판정 캐시 10분·직전 질문 맥락 유지. ④ **웹 P3**: `webSearchDailyLimit`(기본 50, 0=무제한)·`webSearchUsageDay/Count`·`WebSearchQuota`·`E-MAC-SEARCH-0006`·설정 카드의 오늘 N회/예상 비용(Exa $7/1k, 캐시 제외). ⑤ **기억**: `ConversationMemory.fitHistory`가 요청 예산 초과 시 오래된 턴을 요청에서만 제외하고 `%d개 제외` 배너 표시(원문 불변). `MemorySheet`를 편집 가능하게 + `ConversationStore.replaceSummary`(경계·일시 중지 유지). ⑥ **QuickShelf 캡처 후 툴바**: 카드 호버 시 클립보드 복사·다른 이름으로 저장·Finder, 우클릭 메뉴. 검증: `swift test` **260/260**(6 skip, 신규 1+3), BUILD SUCCEEDED, 렌더 `docs/qa/t17-ko`, `web-ko`, `web-retry-ko|en`, `web-ai-ko`; 배포·서명 OK. **남은 미착수**: 임베딩 검색, 주석·스크롤 캡처·OCR, 웹 툴콜링·Exa `/answer`, T-21, H3 에셋.

- [x] T-73 **대화 헤더 기억 토큰 진행률** — 제목 아래에 `현재 / 자동 정리 기준 · %`를 항상 표시. 기준 이상이면 주황, 그 전에는 회색. 툴팁은 기존 두 번역 키를 합쳐 영어에서도 한국어가 새지 않게 했다. 설정 › AI를 열지 않고도 T-71 자동 정리 시점을 확인할 수 있다. `swift test` **252/252**(6 skip), BUILD SUCCEEDED, 렌더 `docs/qa/t73-ko|en|dark`, 2026-10-21 01:07 배포·`codesign --verify --strict` OK.

- [x] T-72 **질문 되돌리기·다시 응답 + 입력창/가독성/보관함 후속**(사용자 요청 9건) — ① `ConversationStore.rewind(toUserTurnID:)`: 대상 사용자 턴과 이후 전부 삭제, 원래 `Turn` 반환. 첫 질문이면 자동 제목 초기화(직접 바꾼 제목 유지), 삭제된 경계를 가리키는 요약은 무효화. `UIStore.editQuestion/regenerateAnswer`: 텍스트·첨부(경로 포함)를 `PendingAttachment`로 복원, `composerFocusToken`으로 입력창 포커스, 다시 응답은 `send(allowCommands:false)` ② `ChatInputField`: 줄바꿈으로 끝날 때 `extraLineFragmentRect`를 높이·캐럿에 포함, 첫 레이아웃 뒤 재측정 → Shift+Enter 커서 가림 해결 ③ 입력독 버튼 `.bottomTrailing`+아래 9pt ④ 사용자 말풍선 `Color.accentColor.opacity(0.16)`+테두리 ⑤ 호버 미리보기 `hoverPreviewKey`(NSImage 비교 제거), Esc 숨은 버튼+`onExitCommand`, 탭/대화/첨부 수/앱 비활성/`onDisappear`에서 닫기, `esc` 안내 ⑥ 스트리밍 중 복사·읽어주기 `opacity 0`(자리 유지) ⑦ 보관함 행 전체 폭 열기 버튼 + 우측 변경/삭제 오버레이 ⑧ 검색어 지우기 버튼 ⑨ 설정 › AI에 `현재 약 N토큰 · 자동 정리 기준 M토큰`+실행 시점 캡션. 검증: `swift test` **252/252**(6 skip, `ConversationRewindTests` 5건), BUILD SUCCEEDED, 렌더 `docs/qa/t72/*`·`t72-en/*`, 2026-10-21 00:09 배포·서명 OK — **사용자 확인 OK (2026-10-21)**

- [x] T-71 **자동 대화 기억 정리**(사용자: "내가 일일이 compact를 쳐야 할까? 그냥 판단해서 정리가 필요하다고 생각되면 알아서") — ① **언제=결정론, 어떻게=모델**: 입력 예산의 **70%** 초과 시에만, **답변 성공 후 백그라운드**로 정리(매 턴 판정 호출 없음, 현재 답변 지연 없음) ② `Conversation.summary`·`summaryThroughTurnID`·`compactPaused`(전부 `decodeIfPresent` 구버전 호환), `activeSummary`/`summaryBoundaryIndex`/`summarizedTurnCount` ③ `ConversationMemory.swift`: 보수적 토큰 추정(비ASCII 1자≈1, ASCII 4자≈1), 프로바이더 예산(Apple FM 4,096→입력 2,816 / Ollama 8,192 / 원격 32,768, `contextTokens` 재정의), 70% 트리거, **짝수 경계**(최근 6, Apple FM 4), 전사·청크·롤링 요약 프롬프트·길이 상한, `requestHistory`/`memoryPromptPrefix` ④ `Store`: `applySummary`/`clearSummary(pauseAuto:)`/`resumeAutoCompact`, reset·clear 시 요약 정리 ⑤ `UIStore`: 정확히 `/compact`일 때만 수동 정리(턴 미생성), 답변 후 자동 Task, 앱 시작·보관함 열기 시 예산 초과면 정리, 적용 전 대화방 ID·경계 턴·일시 중지 확인, 실패 시 무변경 ⑥ **전송**: 요약을 **프롬프트 앞에 고정**(Apple FM 6턴 제한 회피) + 경계 이후 원문만, 웹 검색 컨텍스트와도 결합 ⑦ **UI**: 입력독 위 배너(정리 중/요약됨/일시 중지/실패)·[보기] 요약 시트·[해제]/[다시 켜기], 설정 › AI › **대화 기억 정리** 카드(자동 토글·최근 원문 4/6/8/12·지금 정리·요약 해제), 프로바이더 편집의 **컨텍스트 토큰(선택)** ⑧ 오류 `E-MAC-MEM-0001`, 번역 30키 ⑨ QA `--demo-memory`·`--compact-test[=N]`·`--compact-auto-test[=N]`·`--render-height`, **자가검증 history 저장 차단**. 검증: `swift test` **247/247**(6 skip, 신규 21), BUILD SUCCEEDED, Apple FM 20턴 2,100→513(6.6초), 원격 2,100→903(3.5초), 자동 20턴 YES/10턴 NO, 렌더 `docs/qa/memory-chat-ko|en`·`memory-settings-ko|en`, 22:45 배포·서명 OK — **사용자 실측 대기**

- [x] T-70 **Exa 웹 검색 P1**(사용자 결정: Exa만·네이버 제외 / **자동 = 필요할 때만**) — ① `Settings`: `webSearchProvider`(.none/.exa)·`webSearchResultCount`(3/5/8)·`webSearchFreshness`(24시간/7일/없음)·`webSearchMaxCharacters`(1k/2k/4k)·`exaSecretID` 추가, 전부 `decodeIfPresent` ② `WebSearch.swift`: `ExaSearch`(요청 본문·응답 파싱·401/403/429/5xx 매핑)·`WebText`(script/style·태그·엔티티·제어문자 제거, 공백 접기)·`WebSearchQuery`(**모델 Y/N 판정** `classifierPrompt`/`parseNeed`, 🌐 강제)·`WebSearchContext`(도메인 중복 제거·번호·URL·날짜·2,000자 제한·지시문은 데이터 규칙)·`SearchCache`(10분·50개) ③ `UIStore`: 전송 전 **필요 여부 판정(모델 1회, 4초 제한)** → 필요할 때만 검색 → 프롬프트 주입(스트리밍 유지), 검색 실패/0건은 답변 앞 경고만, `Turn.sources` 저장 ④ UI: 입력독 🌐(이번 질문만), "웹에서 찾는 중…", 답변 아래 출처 카드(클릭=브라우저), 설정 › AI › 웹 검색 카드(검색 시점 `필요할 때만` 고정·키 저장·검색 테스트·캐시 비우기) ⑤ 오류 코드 `E-MAC-SEARCH-0001~0005` + `error_message_ko.json` ⑥ QA `--demo-search`·`--demo-search-sources`·`--demo-search-error`·`--demo-websearch`, 헤드리스 `--search-test=`·`--search-decide-test=`·`--search-answer-test=`. **후속(같은 날)**: 사용자 지적 "최신 질문은 예시일 뿐" → 키워드 목록·`WebSearchMode`(자동/항상) 삭제, 검색 시점을 `필요할 때만`으로 고정. 검증: `swift test` **226/226**(신규 30), BUILD SUCCEEDED, 판정 YES/NO 4종 실측, Exa 실검색 **5건 2.2초**, 검색+원격 모델 **454 델타·인용 4종·5.6초**, 렌더 `docs/qa/search-*` — **사용자 확인 OK (2026-10-21)**

- [x] T-1 Siri AI.app 정적 인벤토리 확정 (Info.plist, 리소스, strings, entitlements)
- [x] T-2 대화·응답 UX 관찰 기록 (미니/설정/풀앱 캡처 3종 + 목업-0.1 고정)
- [x] T-3 DESIGN.md custom 토큰 정의 (v0.7 전 기능: 듀얼 입력, 클립보드 레이어, 메뉴바 토글)
- [x] T-4 QuickTalk 대화 상태머신 + SwiftUI 뼈대 구현 (QuickTalkCore unit 5 통과)
- [x] T-5 빌드 검증 (xcodebuild + ~/Applications 복사 + smoke 로그)
- [x] T-6 단축키 Cmd+Space 전환 + 설정 변경 + 단축키 호출 시 새 대화·중앙 배치 (unit 5/5, BUILD SUCCEEDED, smoke RUNNING)
- [x] T-6b LLM/음성/저장 기반 (3종 프로바이더 + 키체인 + Ollama/AppleFM 스텁, 음성 2종 설정, 핀만 영속 JSON)
- [x] T-7 LLM 실연동 (3종 전부 앱 내부 경로 실호출 통과: Apple FM / Ollama / Remote OpenAI 호환, 2026-10-19 자가진단)
- [x] T-8 음성 실구현 (Apple STT+TTS, Whisper CLI+base모델 전사 실측·사용자 확인)
- [x] T-9 보관함 UI (검색·열기·삭제 + 핀 영속 + 비우기, archive 단일소스 저장으로 수정)
- [x] T-10 설정 독립 창 리뉴얼 (사이드바 일반/단축키/LLM/음성/보관함, 패널 기어탭은 요약+열기 버튼)
- [x] T-11 AI 프로바이더 확장 목록(3종 시드+추가/삭제) + Remote OpenAI 호환 등록 + 설정창·메뉴바 ApexKey 형식 재설계 (PLAN_v0.10, unit 21/21, BUILD SUCCEEDED, 3종 실호출 OK)
- [x] T-12 전역 단축키 Carbon 전환 + 포인터 모드 커서 기억 + 창 활성화 보강 + 설정 정렬 통일 + 편집 단축키 창 한정 등록 (PLAN_v0.10 §13, unit 22/22, 화면·로그 검증)
- [x] T-13 실키보드로 대화 창 ⌘V/⌘C/⌘A/⌘Z 동작 확인 — 사용자 실키 입력 5종 전부 정상, 정책 전환 불필요로 종료(2026-10-19)
- [x] T-14 메뉴바·Dock 표시 정책 (진입점 최소 1개 보장) — 메뉴바 숨기면 Dock 자동 ON, Dock 숨기면 메뉴바 자동 ON, 구버전 둘 다 숨김 상태 자가치유 + 안내 문구 (unit 26/26, BUILD SUCCEEDED, 사용자 확인)
- [x] T-15 Hub 팝오버 실제 클릭 확인 (실행 탭 새 대화·최근 대화 행, 설정 탭 토글·활성 AI·모든 설정 열기, 우클릭 메뉴) + 대화 1턴 E2E 실전송/응답 확인
- [x] T-16 대화 창 설정 탭 재설계 (PLAN_v0.11) — Hub 설정 탭과 **공유 뷰**(`QuickSettingsCardsView`)로 통일: 활성 AI 라디오 선택 + 모델 custom 드롭다운(가로 채움) + 상태 3행(읽기 전용) + 모든 설정 열기. 표시 토글 3종·단축키·음성 조작은 제거. custom 프로필 준수(네이티브 팝업 금지) (unit 26/26, BUILD SUCCEEDED, 캡처 확인)
- [x] T-16b CI성 QA 플래그 `--panel-tab=<chat|archive|settings>` 추가 (대화 창 탭 지정 실행)
- [x] T-17 **대화 창 기본 크기·여백 조정** — 2026-10-21: **기본 창 높이는 유지**하고, 전면 설정 상세의 하단 패딩 18→10pt·대화 창 설정 카드의 마지막 하단 여백을 줄였다. 짧은 설정 화면에서 창 바닥에 남는 빈 공간은 창 높이를 사용자가 줄이면 사라진다(기본 크기 강제 축소 없음).
- [x] T-18 모델 드롭다운 펼침·선택 실사용 확인(사용자 클릭) + `⟳` 목록 조회 3종 확인 — **사용자 확인 OK (2026-10-21)**
- [x] T-19 **대화 창 = 가변 크기 + 클립보드 스트립 + 입력독 정리** (PLAN_v0.12) — 사용자 확정(입력독 바로 위 · 2분·5개 · 민감 기본 마스킹 · 가변) 후 구현. `Clipboard.swift`(Core 정책/링버퍼) + `ClipboardService.swift`(AppKit 감시) + `＋` 자체 첨부 메뉴 + 실제 파일 선택(NSOpenPanel) + 최소 420×420 리사이즈·크기 기억 + 설정 카드 520pt 제한 (unit 36/36, BUILD SUCCEEDED, 캡처·실클릭 확인)
- [x] T-20 클립보드 레일 이미지 항목 실사용 확인(사용자): 스크린샷 복사 → 썸네일 카드 등장 → 누르면 첨부로 추가되고 목록에서 사라짐 — **사용자 확인 OK (2026-10-21)**
- [x] T-21 **포인터 pill** — 2026-10-21 구현. pill은 별개 창이 아니라 **⌘Space "새 대화"의 컴팩트 표현**(유지 시간 초과·턴 없음·0 = 항상 pill). 380×56·포인터=캐럿·Enter(전송+대화 창)·⌘Return(대화 창)·Esc·보관함 최근 4개(1클릭 이어가기). Core `ShortcutEntryPresentation` + `PointerPill.swift`, 테스트 332/332, 렌더 `docs/qa/t21-pill`. **사용자 실측 대기** — `docs/qa/t21-pill/CHECKLIST.md`
- [x] T-22 클립보드 전체 검색 레이어(📋) — 사용자 결정(2026-10-21): 현재 QuickShelf 클립보드 스트립으로 충분. 전체 검색 레이어는 **범위 종료**(미구현).
- [x] T-23 응답 대기 표시 + 전송 상태 (v0.12 개정) — 전송 직후 입력창 즉시 비움, 대화 영역에 "응답 중…" 자체 점 애니메이션 + `프로바이더·모델·N초`, 대기 중 `↑`→`…`(중복 전송 차단), 새 턴 시 자동 하단 스크롤, QA `--ask=<질문>` 추가 (unit 36/36, BUILD SUCCEEDED, 캡처 `docs/capture-replying.png`)
- [x] T-25 **클립보드 = 오른쪽 세로 레일 + 사용 후 소비 + 호버 미리보기** — 가로 스트립 폐기, 오른쪽 레일(텍스트 3줄·이미지 썸네일·남은시간·개수·비우기), 호버 시 전문/큰 이미지 미리보기, 누르면 삽입·첨부 후 항목 제거(민감은 공개→사용 2단계), 첨부 칩 썸네일·크기 표시, 핀·새 대화를 헤더 오른쪽으로 이동, 이미지 임시 파일명 가독화, QA `--prefill=` 추가 (unit 36/36, BUILD SUCCEEDED, 캡처 확인)
- [x] T-26 **입력창 Siri형 상자** — 한 상자 안 ＋(왼쪽 아래)·🎤/↑(오른쪽 아래), 1~5줄까지 늘어나고 넘치면 상자 안 스크롤, Enter=전송 / Shift+Enter=줄바꿈, AppKit `NSTextView` 직접 사용(한글 조합 확정 후 전송·전송 시 직접 비움). 이 환경은 AppKit 기본 클리핑이 없어 `tv.clipsToBounds = true` + 안쪽 여백 밀기로 스크롤 구현 (BUILD SUCCEEDED, 1줄·5줄 캡처 확인)
- [x] T-27 **입력창 스크롤 상단 잘림** — 5줄 초과(스크롤) 상태에서 맨 위 줄이 반쯤 잘려 보임 → **수정 적용**: 높이를 전체 높이(`usedRect`)가 아니라 **보이는 마지막 줄의 아래 경계(`lineFragmentRect.maxY`)** 까지로 잘라 줄 경계에 정렬(`ChatInputField.Coordinator.layoutPass`). — **사용자 확인 OK (2026-10-21)**
- [x] T-28 **사용자 실키보드 확인(입력창)** — 한글 조합 Enter 전송 시 입력창 비움 / Shift+Enter 줄바꿈 / 스크롤 휠 / 레일 항목 클릭 후 사라짐 — **사용자 확인 OK (2026-10-21)**
- [x] T-29 클립보드 이미지 임시 파일명 가독화 — `붙여넣은 이미지 600x300-215412.png` (첨부 칩에서 사람이 알아보게)
- [x] T-24 (T-28로 대체) 한글 IME 전송 잔존 문제 — SwiftUI `TextField`를 버리고 AppKit `NSTextView`로 바꾸면서 전송 시 `string`을 직접 읽고 직접 비우도록 구조 변경(에코 방어 `suppressEcho`도 유지). 최종 확인은 T-28로 통합
- [x] T-42 **첨부 핸드오프 P1~P3 처리** (프록시 세션 핸드오프 2026-10-20 검증 후 수정) — **P1 클립보드 파일이 이름만 전송되던 문제**: `ClipboardItem.fileURL` 신설 → `ClipboardService`가 파일 URL 보존 → `attachClipboard`가 경로 전달 → `AttachmentLoader`가 본문을 읽는다(경로가 없거나 사라졌으면 배너로 알림). **P2 4xx 일괄 "이미지 거부" 오분류 수정**: `ServerFailure`(401·403·413·429·400/422·5xx·빈 본문·기타 4xx) 신설 + 프록시 `error.code`(E-AND-AUTH 등) 파싱 우선, 상태별 재시도(5xx·429 = 같은 요청 1회, 413 = 더 작게, 400/422 = 텍스트만, 401/403 = 재시도 없음), 사다리를 Core `AttachmentRetry`로 옮겨 단위 테스트로 고정, 응답 본문은 문구에 노출하지 않고 서버 코드만 표기, `send()`의 실패도 분류 코드로 표시(모두 NET-0001로 뭉개지 않게). **P3 지원 형식 확대 + 무음 실패 제거**: 텍스트·코드 계열 60여 확장자 + **PDF 텍스트 추출(PDFKit)**, 파일 선택 패널 필터도 Core 목록에서 생성, 클립보드·⌘O·QuickShelf 파일 탭에서 걸러낸 항목은 "첨부할 수 없는 형식입니다: 이름" 배너/안내(9초 자동 닫힘). 검증: unit 79/79(신규 18: 클립보드 URL 보존·분류 7종·사다리 4종·PDF 추출/빈 PDF·레거시 디코딩) — 완료
- [x] T-41 **보낸 메시지에 첨부 표시**(사용자 보고: "내가 보낸 대화에는 어떤 것을 첨부해서 보냈는지 보이지 않음") — `Attachment.path`(원본 경로) 추가(하위 호환 Optional) + `AttachmentPreview`/`AttachmentThumbCache`(썸네일 캐시·픽셀 크기 헤더 읽기) 신설, 입력 전 칩과 전송 후 말풍선이 **같은 호버 미리보기 카드**를 쓰도록 통합. 말풍선 위에 이미지 썸네일(150×100, `930×432 · 74KB` 배지) 또는 파일 카드(아이콘+이름+크기), 4건 이상은 `+N`, 원본이 지워지면 주황 테두리 + 사유, 우클릭 `미리보기 열기`/`Finder에서 보기` — 완료
- [x] T-40 **Whisper 두 백엔드 지원(mlx-whisper + whisper.cpp)**(사용자 요청) — `WhisperBackend`(자동/mlx/whisper.cpp) 신설, 모델 폴더 자동 탐색(`~/Documents/Files/whisper` · 앱 지원 폴더, 중첩 1단계) + `ggml-*.bin`/MLX 폴더(config.json+가중치) 구분, **자동 선택 = 폴더 우선 · 큰 모델 우선**, 백엔드별 인자(`-m/-f/-nt/-np/-l` ↔ `--model/--output-format txt/--output-dir/--verbose False/--language`)·mlx 결과 txt 읽기·임시 폴더 정리, **언어 설정(기본 한국어)** 추가(짧은 음성 자동 감지가 영어로 새던 문제), 실행은 메인 밖 + stdout/stderr 동시 읽기(파이프 교착 방지) + PATH 보강(venv·ffmpeg), 설정 화면에 백엔드·언어·모델 드롭다운(감지 목록)·모델 폴더 지정. 검증: unit 61/61(신규 13) + `QT_LIVE_WHISPER` 실측 — 합성 음성("안녕하세요 오늘 회의는 세 시에 시작합니다")을 **mlx-whisper 1.9초 · whisper.cpp 1.1초 모두 정확히 전사**, 자동 선택이 `mlx-whisper-large-v3-turbo`·`ggml-large-v3-turbo-q5_0.bin`을 고르는지 확인 — 완료
- [x] T-39 **첨부 전송 버그 수정 — 첨부 내용이 모델로 전달되지 않던 문제**(사용자 보고: "이미지·파일 첨부가 안 되는 것 같다") — 원인: `send()`가 첨부를 `Attachment(name:kind:)`로만 넘기고 클라이언트는 `content` 문자열만 보내 **파일 본문·이미지가 전혀 실리지 않았다**. `OutgoingAttachment` + `AttachmentLoader` 신설(텍스트 본문 인라인, 이미지 data URL/Ollama base64, 5MB·3000px 상한·단계 축소), `OpenAIClient.buildMessages`·`OllamaClient.buildMessages`로 `image_url` 파트·`images` 필드 전송, 거부 시 **재시도 사다리**(그대로 → 더 작게 → 텍스트만, `E-MAC-ATT-0001`), 줄임·잘림·미전송은 답변 앞 `⚠️ 첨부 안내`로 표시. QA `--attach=`, 살아있는 검증 `QT_LIVE=1 swift test --filter LiveAttachmentCheck`(좌우 색 이미지 → "왼쪽=빨강, 오른쪽=파랑" 확인, 3024×1964 4MB → 2048 1MB로 줄여서도 인식). unit 46/46(신규 10) — 완료
- [x] T-43 **QuickShelf 표시 방식 수정 — 창 안 엣지 패널 오버레이**(사용자 지적: "오른쪽이 확장되네? 안쪽에 엣지 패널처럼 표시는 안 되?") — 목업 v0.6(`.panel{position:absolute; right:0; top:8px; bottom:8px; width:300px}` + `.scrim`)과 달리 창을 301pt 넓히고 있었다. `ContentView`를 `ZStack`으로 바꿔 창 폭은 그대로 두고 오른쪽 위에 폭 300pt 카드를 겹쳐 띄운다(여백 8·모서리 12·왼쪽 그림자, 뒤 대화는 scrim 28%). **바깥 클릭·Esc·✕**로 닫기, 도킹일 때만 동작하는 로컬 키 모니터(Esc·⌘O·⌘⇧O), 창 확장·폭 복원 로직 제거(최소 폭 420 유지), `ShelfMetrics`로 치수 단일화, **항목 선택 시 허브 자동 접기**(입력독 가림 방지). BUILD SUCCEEDED — 실측 대기
- [x] T-69 **보관함 기록 삭제 확인 시트**(사용자: "보관함에서 대화 기록 삭제시에 컨펌 추가") — 휴지통이 즉시 `deleteConversation`을 호출하던 것을 **자체 확인 시트**(`DeleteConfirmSheet`, design_profile=custom)로 교체. 제목·`N개 턴`·되돌릴 수 없음 안내, **취소 기본(Esc)**, 빨간 [삭제], Enter 실행 없음. 설정 › 보관함의 **[기록 모두 지우기]**도 같은 확인(대화 N개·보관 포함) 후 실행. QA `docs/qa/delete-confirm-ko|en`(개별/전체 4장), `--demo-delete-confirm[=all]`, 196/196(6 skip), BUILD SUCCEEDED — **실측 대기**
- [x] T-68 **스트리밍 응답 — 토큰이 오는 대로 출력 + 자동 스크롤**(사용자: "응답 오는 대로 출력 해줘 자동 스크롤 되면서 지금 처럼 한 번에 출력 하지 말고") — ① Core `LLMClient.stream`(기본=한 번에) + `OpenAIClient` **SSE**(`stream:true`, `delta.content`, `[DONE]`) + `OllamaClient` **NDJSON**(`message.content`, `done`) — `URLSession.bytes(for:)`/`bytes.lines` ② 프록시가 스트리밍을 무시하면 JSON 폴백, SSE인데 델타가 없으면 비스트리밍 1회 폴백 ③ `AttachmentRetry.stream` — **부분 출력 후 재시도 금지**(중복 방지), 재시도 응답은 안내와 함께 한 번에 ④ UI 80ms 스로틀·첫 글자에 점 숨김·`followStream` 자동 스크롤·부분 출력 유지한 채 오류 덧붙임 ⑤ 스트리밍 턴을 붙이기 전에 `history`를 잡아 질문 중복 전송 방지. 195/195(6 skip, 실제 HTTP SSE/NDJSON 2건은 `QT_LIVE_STREAM=1`), BUILD SUCCEEDED, QA `docs/qa/streaming-ko|en`, 18:54 재배포 — **실측 대기**
- [x] T-67 **AI 오류에 정확한 원인 표시**(사용자: "AI 오류 일때 정확한 메시지를 표시 해줘..") — `AIErrorText`(Core)가 `URLError`를 앱 언어로 매핑(연결 거부 -1004·시간 초과 -1001·오프라인 -1009·DNS -1006·TLS -1200)해 말풍선에 `(오류 CODE) 원인 (host:port) (NSURLError n)`으로, 상태 카드에 `연결 거부 (-1004)` 한 줄로 표시. 서버 오류는 `HTTP 상태 · 서버 코드`. Ollama의 전면 삼킴 제거(연결 실패만 안내, 401·404·5xx는 그대로). `ServerFailure`에 HTTP 상태 병기. 테스트 9건 신규(185/185), QA `docs/qa/ai-error-ko|en`, 18:33 재배포 — **실측 대기**
- [x] T-66 **설정 탭 가로 가변 · 선택 모델 연결 테스트(ping)**(사용자: "대화창 리사이즈 했을때 설정도 가로가 가변 되게… 보관함 처럼?" + "선택한 모델을 테스트 해보는 기능이 없나? ping 이라고 대화 보내 보는 거.. 설정에는 있는데 지금 이 화면에는 없네?") — ① `ContentView.settingsTab`의 520pt 폭 제한 제거(보관함처럼 창 폭 추종, Hub 340pt 유지) ② 모델 카드 **[연결 테스트]** — `UIStore.testActiveProvider`가 활성 AI·모델로 `ping` 1건 전송, 응답 60자·에러코드 표시 + `AI 연결` 상태 갱신, 대화 기록 미변경, 프로바이더/모델 전환 시 결과 초기화 ③ 캡션 `⟳` 글자 깨짐 → "새로고침 버튼" 문구. 176/176, BUILD SUCCEEDED, QA `docs/qa/settings-wide-ko|en`, 18:15 재배포 — **실측 대기**
- [x] T-65 **대화방 제목 — 첫 질문 자동 생성 · 대화방/보관함에서 변경**(사용자: "대화방에는 언제나 타이틀이 새 대화… 질문을 가지고 자동으로 제목을 만들어 주고, 보관함이나 대화방에서 변경") — ① `Conversation.autoTitle`/`applyAutoTitle()`(줄바꿈·연속 공백 접기, 30자+…) ② `titleEdited`(구버전 decodeIfPresent=false)로 사용자 제목 보호 ③ `displayTitle`(사용자 > 저장 > 첫 질문 > 새 대화) + `ConversationHistory.normalized`로 옛 기록 마이그레이션, 헤더의 `turns.isEmpty` 조건 제거 ④ 헤더 제목 클릭·보관함 [변경] → 공용 `RenameSheet`(Enter 저장·Esc 취소·빈 제목 거부) ⑤ `UIStore.renameConversation`이 현재/보관함/파일 동시 갱신. 테스트 9건 신규(176/176), QA 렌더 `docs/qa/title-ko|en`, 17:52 재배포 — **실측 대기**
- [x] T-62 **보관함 검색 결과 → 찾은 턴으로 포커스·깜빡임**(사용자: "검색된 대화방을 클릭하면 무조건 마지막으로 간다. 검색된 질문·응답에 포커스가 가면서 테두리가 깜빡이면") — `Conversation.firstTurn(matching:)`(Core)로 검색어와 처음 일치하는 턴을 찾고, `SearchFocusRequest` + `ScrollViewReader`로 중앙 스크롤 + 보라 테두리 3회 깜빡임. 탭 전환 직후 4회 보정, 포커스 중 바닥 스크롤 차단, 같은 결과 재클릭도 재깜빡. 테스트 4건 신규(167/167), 17:09 재배포 — **실측 대기**
- [x] T-63 **캡처 오버레이 — Space 모드 전환 · 십자 커서 유지**(사용자: "Shift+Option+4 ... Space 누르면 드래그↔윈도우, 포인터가 기본으로 바뀜") — 오버레이 안 Space로 드래그↔윈도우 모드 전환(힌트 갱신), 앱 활성화·첫 프레임에서 커서가 화살표로 돌아가던 문제를 커서 사각형 재확정 + 이벤트마다 십자 재지정으로 수정 — **실측 대기**
- [x] T-64 **퀵셸프 기본 단축키 ⇧⌥V**(사용자: "⌥⌘V가 경로 복사와 겹친다") — Core 기본값·레거시 디코딩 변경 + 저장값이 옛 기본값이면 실행 때 자동 승격, 설정 칩·문서 갱신. 17:09 재배포 — **실측 대기**
- [x] T-61 **코드 리팩터링 — 중복 제거·대형 파일 분할·데드 코드**(사용자 요청: "전체적으로 코드 리펙토링 한번 해줘") — ① TTS 공통 뼈대 `ProcessSpeechService`(Edge/Piper는 `makeJob`만 구현, 143/158→40/53줄) ② `SettingsView` 1082→277줄 + 섹션 5파일(+`ProviderEditorSheet`) ③ `ShelfView` 811→477줄 + 탭 3파일(`ShelfTheme` 강조색 단일화) ④ `CaptureService` 578→295줄 + `CaptureOverlay` ⑤ QA 렌더 하네스 분리(`AppDelegate+RenderHarness`) ⑥ 데드 코드(`GlobalHotKey` 호출 단축키 경로·`unregisterAll`, `pickAttachments`, `availableShortcuts`) 제거 ⑦ `import Combine` 경고 수정. `swift test` 163/163, 경고 0, 렌더 17장 픽셀 동일, 13:53 재배포 — **동작 변화 없음(실측 불필요)**
- [x] T-60 **Piper TTS(로컬·오프라인) 엔진**(사용자 요청, 모델 `~/Documents/Files/piper-ko-eva`) — ① `TTSEngine.piper` + `PiperTTS`(모델/실행 파일 탐색, `--length-scale` 환산, CLI 인자) ② `PiperSpeechService`(`piper` 프로세스 → WAV → `AVAudioPlayer`, 중지 시 프로세스 종료·임시 파일 정리) ③ 설정 › 음성에 모델(파일/폴더 선택)·실행 파일·상태·최근 오류·미리 듣기 ④ 세 엔진 `isSpeaking` 통합, `E-MAC-AUDIO-0003` ⑤ 이 머신에 `~/.venvs/piper`(piper-tts 1.8.0) 설치·한국어 WAV 합성 확인. `swift test` 163/163, 13:08 재배포 — **실측 대기**(실제 재생·중지·속도)
- [x] T-59 **전역 단축키 5종 + 직접 변경(녹화)**(사용자 요청: "단축키는 Cmd+Space만 있는 게 아니잖아? 각각 다 추가하고 매뉴얼로 변경할 수 있게") — ① `ShortcutAction`(대화 열기·퀵셸프·캡처 3종) + `ShortcutCombo`(토큰/기호 파싱·정규화·표시·중복 검사, Core) ② 설정 › 단축키 [조합 칩][변경][↺ 기본값], 로컬 keyDown 모니터(Esc 취소·Delete 기본값), 중복·등록 실패(⚠️) 안내 ③ 녹화 중 전역 핫키 일시 해제(suspend/resume)로 이미 등록된 조합도 입력 가능 ④ 등록을 `AppDelegate.applyShortcuts`로 단일화(바뀐 것만 재등록), `ShelfController` 자체 등록 제거 ⑤ 화면의 하드코딩 조합 문구를 설정값 표시로 ⑥ "창 안에서 쓰는 키" 읽기 전용 목록. `swift test` 152/152, 12:52 재배포 — **실측 대기**(변경 후 실제 동작·⌘Space 유지)
- [x] T-58 **Edge TTS 읽어주기 엔진** — `ttsEngine`(apple/edge) 설정, `edge-tts` CLI → mp3 → `AVAudioPlayer`, 목소리 13종 + ID 직접 입력, 속도 환산(-50%~+55%), 미리 듣기, 실행 파일 자동 탐색·직접 지정, 상태/최근 오류, 두 엔진 `isSpeaking` 통합 — **실측 대기**(한국어·영어 목소리 실제 재생, 미리 듣기)
- [x] T-57 **캡처 Esc·십자 커서 · 입력독 버튼 26pt · 새 대화 워터마크 · 한글 퀵셸프** — ① borderless 창이 key가 못 돼 Esc가 전달되지 않던 문제(전용 NSWindow + cancelOperation + 로컬 모니터) ② `resetCursorRects`로 십자 커서 유지 ③ 🎤·↑ 축소·수직 중앙 정렬 ④ 빈 대화 중앙에 앱 아이콘 워터마크 ⑤ `QuickShelf` → **퀵셸프**(ko) ⑥ 도움말 카드가 언어 변경에 다시 그려지게 — **실측 대기**(Esc·커서·버튼 여백)
- [x] T-56 **영어 UI 마무리(Core 문구) · 마크다운 체크박스 · QA 렌더 하네스** — ① Core 표시 문구 번역(프로바이더 종류·시드 이름·창 위치·분 단위·음성 엔진·Whisper 상태/힌트·음성 품질·전사 언어·서버 실패/재시도/첨부 안내), 번역표 454키 ② `valueRow` 줄바꿈(영어 잘림) ③ QuickShelf 라이트 대비(`accentText`) ④ `--render=`(+`--lang/--theme/--settings-tab/--shelf-tab/--demo-chat`) 오프스크린 QA ⑤ 체크박스 목록(`- [ ]`→☐, `- [x]`→☑) — **실측 대기**(영어 모드·체크박스)
- [x] T-54 **드래그 캡처 돋보기 제거** — 오버레이의 4배 확대 돋보기(`drawLoupe`) 삭제, 커서 이동 재그리기 제거(크기 라벨·십자 커서는 유지) — **실측 대기**
- [x] T-53 **테마 · 한/영 전환** — ① `L10n`(한국어 원문 키 + 400여 English 번역) + `L()`/`Lf()` ② 설정 › 언어 · 테마(시스템 기본/한국어/English · 시스템/라이트/다크) ③ `NSApp.appearance` 적용, QuickShelf·말풍선의 하드코딩 다크 제거 ④ 날짜·메뉴·창 제목도 언어 따라감 — **실측 대기**
- [x] T-52 **읽어주기 중지 · 새 메뉴바 아이콘** — ① TTS 토글이 `synthesizer.isSpeaking`의 지연 때문에 무음이 되던 문제 → 서비스는 항상 재생, 토글은 UI 상태로 ② 말풍선 ⏹·헤더 중지·Hub 중지 행, 전송/녹음/새 대화 시 자동 중지 ③ `MenuBarIcon`을 새 아트워크(말풍선+스파클)로 교체 — **실측 대기**
- [x] T-51 **권한 유지(안정 서명) · 권한 안내 클릭 요청 · 입력독 버튼 여백** — ① ad-hoc 서명 → DR=cdhash → 빌드마다 TCC 무효. Apple Development 서명으로 DR 고정 ② 안내 배너 클릭 → `CGRequestScreenCaptureAccess`/시스템 설정 딥링크 ③ 🎤·↑ 위/아래 여백 4pt로 통일 — **실측 대기**
- [x] T-50 **창을 열 때 대화 스크롤 맨 아래** — `.defaultScrollAnchor(.bottom)` + 창 표시 알림(`quickTalkScrollToBottom`) + 3회 보정 + 대화 전환 `onChange` — **실측 대기**
- [x] T-49 **입력창 기본 여백 정렬 · QuickShelf 영문 문구** — 빈 상태 플레이스홀더가 컨테이너 leading 14pt를 중복 적용해 캐럿보다 14pt 오른쪽에서 시작 → 제거(픽셀 검증), `Drop to attach` → 한국어. 06:20 재배포 — **실측 대기**
- [ ] **실측 체크리스트** — `docs/QA-CHECKLIST-2026-10-20.md` (T-27·T-28·T-36·T-37·T-43~T-69 사용자 확인 **43항목**, A~H)
- [x] T-48 **응답 복사·응답 시간 · ⌘Space 세션 규칙**(사용자 요청) — ① AI 말풍선 📋 복사(원문, 1.2초 체크) + 🔊 읽어주기 ② `Turn.elapsedMs`로 응답 시간 표시·저장(구버전 nil 생략) ③ `shortcutSessionMinutes`(5/10/30/사용 안 함, 기본 10분): 유지 시간 안이면 이어서, 지났으면 새 대화. 창이 보이면 미적용 ④ `openNewWindowAsNewConversation` 삭제 → 설정 픽커 교체. 테스트 11건 → 129/129 — **실측 대기**
- [x] T-47 **대화 기록 · 창 레벨 수정**(사용자 보고) — ① 모든 대화 자동 저장(`PersistenceService`/`history.json`, `ConversationHistory` 정리 규칙) + 시작 시 마지막 대화 복원 + 보관함 탭 기록 목록 ② 대화 창 기본 레벨 `.normal`(이전 `isFloatingPanel = true`가 원인), 헤더 📌 = 항상 위(`alwaysOnTop`), 보관은 🔖 ③ 설정·정보 창 및 시스템 권한 안내 중 자동 레벨 강등(`applyPanelLevel`, 30초 복구) ④ 뒤에 있을 때 단축키 = 닫지 않고 앞으로(`togglePanel`). 테스트 8건 → 118/118, 03:47 재배포 — **실측 대기**
- [x] T-46 **AI 답변 마크다운 렌더링**(사용자 요청: "CapsuleStash에서 렌더링한 정도면") — `Sources/QuickTalkCore/Markdown.swift`(블록 파서 + 인라인 토크나이저 + `MarkdownPlain` 낭독 평문)와 `QuickTalkApp/MarkdownText.swift`(렌더 뷰)를 CapsuleStash `MarkdownBody`(T-26)에서 옮기고 번호 목록·중첩 들여쓰기·링크·구분선을 추가. AI 말풍선만 마크다운, 사용자 말풍선·복사·저장은 원문 유지, **읽어주기는 평문**. 코드 블록은 줄바꿈(중첩 가로 ScrollView는 스크롤 충돌 + 오프스크린 렌더에서 빈 상자), 표 60행 제한, 파싱 메모. 오프스크린 렌더로 확인(`docs/markdown-preview.png`), 테스트 16건 → `swift test` 110/110, 03:33 재배포 — **실측 대기**
- [x] T-45 **음성 언어·읽어주기 목소리 선택**(사용자 질문: "Apple 음성인식·Whisper는 음성 선택 같은 기능은 없니? 그냥 한국어만 선택 가능? 읽어 주기 할 때 소리") — Apple 받아쓰기 언어를 한국어 고정에서 `appleSpeechLocale`(시스템 지원 62개)로, 읽어주기를 한국어 고정 목소리에서 `ttsLanguage`·`ttsVoiceID`·`ttsRate`(슬라이더)로 확장. 설정 › 음성에 언어/목소리 드롭다운·속도·**미리 듣기**. `SpeechCatalog`(Core·순수 함수)가 품질 순 정렬·중복(compact/super-compact) 제거·Siri 목소리 이름 보정, 선택이 비면 그 언어 최고 품질 자동 선택(한국어 = 향상 Siri 자연스러운). 테스트 9건, `swift test` 94/94, 03:27 재배포 — **실측 대기**
- [x] T-44 **윈도우 캡처가 엉뚱한 창/영역을 잡는 버그 수정**(사용자 지적: "캡처 윈도우를 잘못 잡는 것 같은데?") — 원인 2개. ① **좌표계 혼용**: `CGWindowList` 사각형(좌상단 원점·y아래)을 오버레이(좌하단 원점·y위) 좌표로 그대로 써서 강조·선택이 세로로 뒤집혔다 → `Sources/QuickTalkCore/CaptureGeometry.swift`(순수 함수)로 변환을 한 곳에 모으고 `windowTargets`가 AppKit 전역 좌표로 변환해 넘긴다. ② **윈도우 캡처가 화면 스냅샷 자르기**여서 겹친 창·바탕화면까지 찍혔다 → `SCContentFilter(desktopIndependentWindow:)`로 그 창의 표면만 다시 캡처(`ignoreShadowsSingleWindow`, 창이 놓인 화면의 배율 사용). 강조 라벨에 **앱 이름** 표시, 창이 사라졌으면 `windowGone` 안내. 회귀 테스트 5건(`CaptureGeometryTests`) 추가 — `swift test` 85/85(4 skip=QT_LIVE), BUILD SUCCEEDED, 03:20 재배포. **실측 대기**

- [x] T-38 **QuickShelf 창 안 도킹 개정**(사용자 결정, T-43에서 오버레이 방식으로 재개정) — 대화창 헤더에 QuickShelf 버튼(`sidebar.right`) 추가, 누르면 창이 301pt 넓어지며 같은 `ShelfView`가 창 안 오른쪽에 도킹(`ShelfChrome.docked` — 모서리·테두리 없는 사이드바 크롬). 가장자리 핸들은 **대화창이 닫혀 있을 때만** 쓰는 보조 진입점으로 유지하고, 두 위치가 겹치지 않게 도킹 시 플로팅 패널은 접는다. `⌥⌘V`/핸들은 대화창이 떠 있으면 도킹을 토글. 캡처 시 대화창(도킹 포함)도 숨김. 도킹 폭이 창 위치 자동 저장에 남지 않게 접힌 폭 복원. QA: `--open-panel --open-shelf` = 도킹 상태 — 완료(실측 대기)
- [x] T-37 **앱 아이콘·메뉴바 아이콘 적용** — `Assets.xcassets`(AppIcon 10종 + MenuBarIcon 템플릿 18pt@1x/@2x) 신설, 메뉴바 상태 아이콘·Hub 헤더 배지 교체(폴백 유지). `AppIcon.icns`·`Assets.car`·`CFBundleIconName` 생성 확인. 세트의 Light/Dark/Tinted는 바이트 동일이라 클래식 슬롯만 사용(실측 대기: Dock/Finder 아이콘 캐시 갱신은 재실행·로그아웃 필요) — 완료
- [x] T-30 **QuickShelf 확장 — Edge 허브(클립보드·파일·캡처)** (PLAN_v0.13, 목업 v0.6) — 확정: 이름 QuickShelf · 핸들=화면 가장자리 · 입력창 ＋ 제거 · 캡처=자체 단축키 ⌥⇧3/4 + ScreenCaptureKit. 대화창 오른쪽 레일은 패널로 이전/제거 → **구현 완료**: `ShelfModel.swift`·`ShelfView.swift`·`ShelfPanel.swift`·`CaptureService.swift` 신설, `UIStore`에 파일·캡처·미리보기 상태, 설정 `shelfEnabled`·`shelfCopyCaptureToClipboard`. unit 36/36, BUILD SUCCEEDED
- [x] T-31 QuickShelf S1 — Edge 핸들 윈도우(14×122, `.statusBar`, 모든 Space, 포커스 비탈취) + NSPanel 껍데기 + 탭 3개 + 열기/닫기(핸들·⌥⌘V·Esc·key 상실 시 자동 닫힘) — 완료
- [x] T-32 QuickShelf S2 — 클립보드 탭 이식(패널 카드, 별도 창 호버 미리보기, 사용 후 소비, 검색·종류 필터) + 대화창 레일 제거 — 완료
- [x] T-33 QuickShelf S3 — 파일·이미지 탭(⌘O/⌘⇧O, 드래그 앤 드롭, 클릭 → 대화 첨부) + **입력창 ＋·첨부 메뉴 제거** — 완료
- [x] T-34 QuickShelf S4 — 캡처 3모드(전체/윈도우/드래그) ScreenCaptureKit + 오버레이(돋보기·크기·힌트·윈도우 강조·Esc) + 캡처 탭 썸네일 — 완료. **선택 후 툴바(복사·저장·첨부)는 미구현**: 마우스를 떼면 곧바로 QuickShelf에 추가하고 설정에 따라 클립보드에도 복사한다
- [x] T-35 QuickShelf S5 — 설정 화면 **QuickShelf 탭 신설**(핸들 on/off·캡처 클립보드 복사·단축키 표시·화면 기록 권한 요청/시스템 설정 딥링크·저장 정책·폴더 열기) + 캡처 단축키 ⌥⇧3/⌥⇧4/⌥⇧⌘4 등록 — 완료
- [x] T-36 QuickShelf S6 — 캡처 3모드 실측 · 다중 모니터 · 전체화면 앱 · 핸들 클릭/드래그 · Esc/바깥 클릭 닫힘 · 화면 기록 권한 허용 후 재실행 + 문서/캡처 갱신 — **사용자 확인 OK (2026-10-21)**
