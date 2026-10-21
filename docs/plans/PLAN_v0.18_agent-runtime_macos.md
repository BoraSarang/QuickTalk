# PLAN v0.18 — 에이전트 런타임 (맥 도우미 도구)

> macOS · QuickTalk · 2026-10-21 · 상태: **설계 확정 / 스파이크 검증 중**
> 선행: `PLAN_v0.14_websearch_macos.md`(웹 툴 콜링) · `PLAN_v0.17_pointer-pill_macos.md`

## 1. 문제

QuickTalk의 정체는 **맥 도우미**다. 사용자가 자연어로 말하면 앱이 **직접 행동**하고 그 결과로 답해야 한다.

| 사용자 발화 | 지금 QuickTalk | 필요한 것 |
|---|---|---|
| "인터넷 속도 체크" | 모른다 (모델의 낡은 지식으로 추측) | 실제 측정 → 요약 |
| "하드 용량 얼마나 남았어" | 모른다 | 실제 조회 |
| "다크 모드로 바꿔줘" | 모른다 | 실제 시스템 변경 + 되돌리기 |
| "이번주 일정 알려줘" | 모른다 | 캘린더 조회 |
| "산소방문 일정 남겨줘" | 모른다 | 일정 생성 |
| "S22에 앱 설치해" | 모른다 | `adb` 실행 |
| "whisper-cpp 설치해줘" | 모른다 | `brew` 실행 |

현재 앱에 붙어 있는 도구는 **`web_search` 하나**뿐이다(PLAN_v0.14). 도구를 하나씩 늘리는 방식은
"pip", "uv", "ollama", "npx" 같은 요청이 들어올 때마다 앱을 고쳐야 하므로 **천장이 있다**.

## 2. 확정 사항 (사용자)

| 질문 | 확정 |
|---|---|
| 배포 방식 | **GitHub 배포(스토어 없음)** → 샌드박스 OFF 유지 → 셸 자유. v0.20(터미널 기능)의 전제 |
| 자동 실행 범위 | **읽기(기본 자동) / 쓰기 / 실행** — 사용자가 설정에서 선택 |
| 범위 | **v0.18 ~ v0.22 전체** |
| 프로바이더 | **Apple FM · Local Ollama · 원격 OpenAI 호환 3종을 동일 기능으로 통일** |

## 3. 핵심 원칙 — 앱은 "명령어"를 모른다

> 앱이 `brew`·`adb`·`pip`·`uv`·`ollama`를 알아야 한다면, 그 목록은 영원히 불완전하다.
> **모델이 정한 명령을 앱은 그대로 실행만 한다.**
> 앱이 판단하는 것은 "이 명령의 이름"이 아니라 **"이 명령이 무슨 권한을 요구하는가"** 다.

- 모델: `ollama pull qwen3` 를 안다 → 앱은 그것을 **실행**한다
- 모델: `brew install whisper-cpp` 를 안다 → 앱은 그것을 **실행**한다
- 모델: 파이썬 패키지 설치 방법(uv/pip/conda)을 안다 → 앱은 **실행만** 한다
- 모델이 모르는 것(이 기기의 실제 상태) → **실행 결과로 관측**한다(에이전트 루프의 존재 이유)

**앱에 하드코딩하는 명령 사전은 없다.** 위험 명령 목록도 없다(§4.3의 구조적 신호 제외).

## 4. 권한 모델

### 4.1 요구 권한은 "분류"가 아니라 "협상"(실측)

`/usr/bin/sandbox-exec` 로 **읽기 전용 환경에서 먼저 실행**한다. 실패하면 샌드박스 에러가
**무엇이 막혔는지(경로 포함)** 알려준다. 이로써 요구 권한이 판별된다.

```
① 읽기 전용 샌드박스로 실행 (deny file-write* · deny network*)
   ├─ 성공  → READ만 필요        → [읽기] 정책(기본 자동 허용) → 완료
   └─ 실패  → 에러가 요구를 알려줌
        ├─ "Operation not permitted: /Users/lee/.ollama" → WRITE 필요(경로까지 알림)
        ├─ 네트워크 차단                                  → NETWORK 필요
        └─ sudo / 시스템 영역                             → ELEVATED 필요
             └─ ② 정책 확인
                  ├─ 자동 허용 → 승인된 범위만 열고 재실행
                  └─ 확인 필요 → ③ 확인 시트 → 승인 시 그 범위만 열고 재실행
```

**승인은 "스위치"가 아니라 "범위"다.** 허락한 경로만 열고 나머지 시스템 영역은 계속 막는다.
명령 목록이 아니라 **스코프**로 안전을 확보한다.

> **구현 시 반드시 지켜야 할 3가지 (스파이크에서 확인)**
> 1. **경로는 `realpath`로 완전히 해석**해 샌드박스 규칙에 넣는다. `/var` → `/private/var` 처럼
>    Seatbelt는 해석된 경로로 매칭한다. `URL.resolvingSymlinksInPath()` 는 `/var` 를 그대로 돌려주므로
>    `realpath(3)` 를 쓴다.
> 2. **네트워크 차단은 "Operation not permitted" 로 오지 않는다.** 샌드박스는 네트워크를 막기만 하고
>    실패는 도구 자신의 신호로 나타난다(curl 종료코드 6 / ping 68 / "Unknown host").
>    → "이 명령은 네트워크가 필요하다"로 판정하고, 재실행 후에도 실패하면 그때는 진짜 네트워크 문제다.
> 3. **쓰기 차단 메시지에서 경로가 메시지보다 앞에 온다** — `/bin/sh: /path: Operation not permitted`.
>    콜론으로 나눈 조각 중 "/" 로 시작하는 **마지막** 조각을 경로로 잡는다.

### 4.2 사용자 단계 (3단계)

| 단계 | 실측 조건 | 예 | 기본 |
|---|---|---|---|
| **읽기** | 쓰기·네트워크 불필요 | `df` `ls` `brew list` `adb devices` `cat` | ✅ **자동 허용** |
| **쓰기** | 파일 쓰기 필요 | `mkdir` `cp` `ollama pull` `defaults write` `git commit` | ❓ 확인(사용자 선택) |
| **실행** | 네트워크·시스템영역·상승권 필요 | `brew install` `adb install` `curl \| sh` `sudo` | ❓ 확인(사용자 선택) |

- 판정 기준은 **기계가 아니라 효과**다. `df`도 결국 프로그램을 실행하지만 결과가 읽기 전용이라 "읽기"다.
- **알 수 없는 명령은 자동으로 가장 높은 단계(실행)** 로 잡힌다.

### 4.3 위험도 (별도 축)

| 위험도 | 예 | 기본 동작 |
|---|---|---|
| 보통 | 되돌릴 수 있거나 영향이 국소 | 4.2 정책대로 |
| 중요 | 되돌리기 어렵거나 **시스템 전역** — `sudo` `killall` `defaults write -g` `brew uninstall` `adb uninstall` 시스템경로 `chmod` | **무조건 확인** (자동 허용이어도) |
| 치명적 | 복구 불가 — `rm -rf /` `mkfs` `dd of=/dev/disk*` fork bomb `diskutil eraseDisk` | **항상 차단** (설정에서 고등급 위험 허용 시 해제) |

- 중요/치명적 판정은 명령 이름이 아니라 **구조적 신호**로 한다(상승권 표시자·시스템 경로·파이프→인터프리터).
  앱·패키지 이름 목록은 쓰지 않는다.

### 4.4 되돌리기가 권한을 낮춘다

`rm -rf ~/Downloads/x` 를 **금지하지 않고**, 실제 실행을 **휴지통 이동(`/usr/bin/trash`)** 으로 바꾼다.
→ 위험도 "중요" → "보통", 단계 "실행" → "쓰기". 그리고 대화창에 **[되돌리기]** 버튼이 뜬다.
QuickTalk이 옮긴 것(휴지통·백업·수정 전 원본)을 앱이 기억한다.

삭제를 금지하는 게 아니라 **되돌릴 수 있게 만드는 것**이다.

### 4.5 설정 (설정 › 도구 › 권한)

```
┌ 권한 ─────────────────────────────────────────────┐
│ 읽기   [ ● 자동 허용 ]   ← 기본                      │
│ 쓰기   [ ○ 매번 확인  ]  ← 기본  · [ 항상 허용 ]    │
│ 실행   [ ○ 매번 확인  ]  ← 기본  · [ 항상 허용 ]    │
│                                                    │
│ [ ] 권한 요청 없이 전부 자동 허용  ← 전역 자동 수락  │
└────────────────────────────────────────────────────┘
┌ 허용 규칙 (사용자가 직접 쓴다 — 앱 기본값 없음) ────┐
│ brew install *                                     │
│ ~/Downloads/**                                     │
└────────────────────────────────────────────────────┘
┌ 이 대화에서만 ─────────────────────────────────────┐
│ [ ] 이 대화에서는 쓰기 자동 허용                     │
└────────────────────────────────────────────────────┘
┌ 제한 ──────────────────────────────────────────────┐
│ [ ] 치명적 명령 허용 (rm -rf /, mkfs, fork bomb)     │  ← 기본 OFF
│ [ ] sudo 등 상승 권한 허용                          │  ← 기본 OFF
└────────────────────────────────────────────────────┘
```

- **앱이 제공하는 화이트리스트는 없다.** 규칙은 사용자가 직접 쓰고, "항상 허용"을 누르면 그 명령이
  규칙으로 저장된다(필요하면 `*`로 편집).
- 대화(프로젝트)별 오버라이드 가능.

### 4.6 승인 UX (커스텀 시트 — 네이티브 alert 금지)

```
┌ 실행 권한 요청 ──────────────────────────────────┐
│ ● 실행 · 쓰기 필요: /Users/lee/.ollama            │
│ ┌──────────────────────────────────────────────┐  │
│ │ ollama pull qwen3:8b                          │  │  ← 모델이 만든 명령 그대로
│ └──────────────────────────────────────────────┘  │
│ 목적: 요청하신 모델을 내려받습니다                 │  ← 모델이 함께 제공(스키마 필드)
│                                                 │
│ 범위:  (●) 이 경로만 쓰기 허용   (○) 전체 쓰기 허용│
│                                                 │
│ [한 번 허용]  [항시 허용]  [거부]  [터미널에서 열기] │
└─────────────────────────────────────────────────┘
```

- 취소/거부 → **모델에 "사용자가 거부했다"를 되돌려** 다른 방법을 제안하게 한다.
- Enter로는 실행 불가(실수 방지) — `DeleteConfirmSheet`와 동일 원칙.
- **[터미널에서 열기]**: `sudo`·대화형 입력·GUI 인증처럼 앱이 못 하는 일은 Terminal.app에 그대로 넘긴다.
  앱은 비밀번호를 요구하지 않는다(보안 원칙).

## 5. 프로바이더 3종 통일

Core에 프로바이더 중립 추상화를 두고 3개가 각각 구현한다. **런너는 공유한다.**

```swift
// Core/AgentTypes.swift
public struct AgentTool {
    public let name: String            // "shell"
    public let description: String
    public let jsonSchema: [String: Any]
}

public protocol AgentClient {
    func nextStep(messages: [AgentMessage], tools: [AgentTool]) async throws -> AgentStep
}

public enum AgentStep {
    case toolCalls([AgentToolCall])   // 실행 → 관찰 → 다음 스텝
    case finalAnswer(String)
}
```

| 프로바이더 | 도구 호출 방식 | 상태 |
|---|---|---|
| 원격 OpenAI 호환 | 기존 `OpenAIClient.completion(messages:tools:)` | 동작 확인 |
| Local Ollama | `/v1/chat/completions` tools (OpenAI 호환) | 동일 경로 |
| **Apple FM** | **FoundationModels `Tool` 프로토콜** — `LanguageModelSession(model:tools:instructions:)` + transcript `.toolCalls` / `.toolOutput` | **SDK 심볼 확인 완료** |

### Apple FM 관련 확정 사실 (SDK 27.2 swiftinterface + 스파이크 실행 결과)

```
3054: public protocol Tool<Arguments, Output> { name, description, parameters: GenerationSchema, call(arguments:) }
3317: public struct GenerationSchema { }        ← 동적 스키마 구성 가능
  38: LanguageModelSession(model:tools:[any Tool], instructions:)
2554: Transcript.ToolCall { id, toolName, arguments: GeneratedContent }
2581: Transcript.ToolOutput { id, toolName, segments }
2266: Transcript.Entry.toolCalls / .toolOutput
3293: GenerationOptions.ToolCallingMode { .allowed/.required/.disallowed }
```

- 현재 `AppleFMClient.swift:51-52` 는 `session.respond(to: full)` 만 호출해 **도구를 전혀 넘기지 않는다.**
  기능이 없는 게 아니라 **안 쓰고 있는 것**이다.
- **⚠️ `@Tool` 매크로는 이 SDK에 없다.** `Tool` 프로토콜을 직접 구현해야 한다
  (`name`·`description`·`call(arguments:)` — `parameters` 는 `@Generable` 인자면 기본 구현이 생긴다).
- **Tool.Arguments 는 `@Generable` 구조체여야 한다**(SDK가 String/Int 인자를 명시적으로 금지) →
  도구마다 정적 구조체를 정의한다(예: `ShellArgs{command, cwd, timeout}`).
- **FoundationModels 는 도구를 자동 실행한다.** `respond(to:)` 안에서 `call(arguments:)` 가 호출되고
  그 결과가 모델에 전달된다(스파이크에서 확인). → **정책 게이트는 `call(arguments:)` 안에서 하면 된다.**
  호출 내역은 `transcriptEntries` 의 `.toolCalls` 에 남으므로 실행 카드·감사 로그에 쓸 수 있다.
- 온디바이스 모델은 작아서 다단계 계획이 불안정 → **스텝당 1개 도구** 원칙 + 실패 시 재시도 1회 +
  그래도 안 되면 사용자에게 되묻기.

## 6. 구현 파일 (예정)

| 파일 | 역할 |
|---|---|
| `Sources/QuickTalkCore/AgentTypes.swift` | `AgentTool` · `AgentClient` · `AgentStep` · `AgentMessage` (프로바이더 중립) |
| `Sources/QuickTalkCore/AgentRunner.swift` | 루프(호출→도구 실행→관찰→반복), 스텝/시간/출력 상한, ⏹ 취소 |
| `Sources/QuickTalkCore/SandboxRunner.swift` | `sandbox-exec` 실행 · 요구 권한 실측 · 스코프 프로파일 생성 |
| `Sources/QuickTalkCore/RiskClassifier.swift` | 구조적 신호(상승권·시스템경로·파이프→인터프리터) → 위험도 판정 |
| `Sources/QuickTalkCore/PolicyEngine.swift` | 권한 단계 × 위험도 → 허용/확인/차단 + 규칙 매칭 + 대화별 오버라이드 |
| `Sources/QuickTalkCore/UndoStack.swift` | 휴지통·백업 이력 → 되돌리기 |
| `Sources/QuickTalkCore/ToolSchemas.swift` | `shell`·`read_file`·`write_file`·`list_dir`·`screenshot` 스키마 |
| `Sources/QuickTalkCore/SystemKnowledge.swift` | 앱 자신 지식(경로·현재 프로바이더·내장 기능) → 시스템 프롬프트 주입 |
| `QuickTalkApp/AppleFMClient.swift` | FoundationModels 도구 루프 적용 (`Tool` 구현체) |
| `QuickTalkApp/UIStore.swift` | `send()`에 에이전트 모드 분기(기존 웹검색 분기와 병렬) |
| `QuickTalkApp/AgentCard.swift` | 실행 스트림 카드(명령·출력·경과·중단) |
| `QuickTalkApp/ToolConfirmSheet.swift` | 승인 시트(커스텀) |
| `QuickTalkApp/UndoCard.swift` | 되돌리기 버튼 |
| `QuickTalkApp/SettingsView+Tools.swift` | 설정 › 도구(권한·규칙·오버라이드·감사 로그) |
| `Sources/QuickTalkCore/Settings.swift` | 권한 설정 모델(단계별 정책·규칙·오버라이드) |

## 7. 로드맵

| 버전 | 내용 | DoD |
|---|---|---|
| **v0.18** | **스파이크 2개**(Apple FM 도구 루프 / 샌드박스 권한 협상) → `AgentTool`·`AgentClient`·`AgentRunner` → `shell`·`read_file`·`list_dir` → `SandboxRunner` → 읽기 자동 허용 → 실행 카드 | "하드 용량 얼마나 남았어" → **3프로바이더 모두** 실제 `df` 실행 후 요약 |
| **v0.19** | 쓰기 단계(경로 스코프 승인) + 휴지통 rewrite + `UndoStack` + [되돌리기] 카드 + 일정/앱설정 쓰기 | "이 파일 지워줘" → 휴지통 이동 + 되돌리기 동작 |
| **v0.20** | 실행 단계(네트워크·시스템영역·상승권) + 확인 시트 + 위험도(중요/치명적) + 전역 자동 수락 + 백그라운드 실행 + 감사 로그 | "whisper-cpp 설치해" → 진행 로그 스트리밍 |
| **v0.21** | 스크린샷(멀티모달) + Shortcuts 연동 + 슬래시 팔레트(`/shell`, `/read`) + 허용 규칙 편집기 | "지금 화면 뭐야" → 모델이 캡처를 봄 |
| **v0.22** | 권한 고도화(대화별 오버라이드 UI·경로 스코프 UI) + 앱 자신 지식 주입 + Terminal 인계 정리 | "이 앱 음성 인식 뭐 써?" → 내부 설정을 정확히 답함 |

## 8. 검증 계획

- **Core 단위 테스트**: 요구 권한 실측 분류(읽기/쓰기/네트워크/상승권), 위험도 판정, PolicyEngine 매트릭스,
  규칙 매칭, 되돌리기 스택.
- **헤드리스 자가진단** `--agent-selftest`: 임시 디렉터리에서 "파일 만들기 → 찾기 → 휴지통" 시나리오 자동 수행.
  기존 `--search-answer-test` / `--tool-selftest` 계열과 같은 결 (CLI 인자).
- **프로바이더 동일성 테스트**: 같은 프롬프트를 3프로바이저에 넣고 "실제로 명령을 실행했는지" 비교.
- **수동 실측**: `docs/qa/t18-agent/CHECKLIST.md`.
- **DoD**: `swift test` 통과 + `xcodebuild` BUILD SUCCEEDED(경고 0) + 오프스크린 렌더 + CHANGELOG + 세션 로그.

## 9. 한계 · 리스크

| # | 내용 | 대응 |
|---|---|---|
| 1 | `sandbox-exec` 는 Apple이 deprecate한 API. macOS 27.2에서 **동작 확인**했지만 언젠가 사라질 수 있음 | 추상화 계층으로 감쌈. 사라지면 "항상 확인"으로 안전 폴백(기능 손실 없음) |
| 2 | 명령이 2회 실행됨(권한 실측 1회 + 실제 1회) | 실측 회차는 네트워크 차단이先行 → 부작용 위험 낮음. 문서화 |
| 3 | `sudo`·대화형 입력은 앱이 못 함 | [터미널에서 열기]로 인계 |
| 4 | 프롬프트 인젝션(웹 결과가 지시를 포함) | 검색 결과는 데이터 취급 + 실행 단계는 사람 확인 + 치명적 차단 |
| 5 | Apple FM은 작아서 다단계 계획이 불안정 | 스텝당 1개 도구 + 재시도 1회 + 되묻기 |
| 6 | 무한 루프·비용 | 스텝 수(기본 20)·총 시간(기본 5분)·총 출력 상한 |
| 7 | Apple Intelligence 미활성/미지원 기기 | Apple FM은 대체 프로바이더로 폴백(현행 동작 유지) |

## 10. 스파이크 결과 (2026-10-21 · 실측)

소스·로그: `docs/qa/t18-spike/` (`.swift` + `.log`)

### 스파이크 1 — Apple FM tool calling → **PASS** (4.0초)

```
[SPIKE] Apple FM 사용 가능
[SPIKE] 세션 생성 완료 (tools: [echo])
[SPIKE] ✅ Tool.call(arguments:) 실행됨 — message=QUICKTALK-OK
[SPIKE] 1차 응답 content=ECHO::QUICKTALK-OK
[SPIKE] tool_call #1: name=echo id=F0A52A9D-…  인자 message=QUICKTALK-OK
[SPIKE] tool_output 추가됨: ECHO::QUICKTALK-OK
[SPIKE] ✅ 최종 답변: ECHO::QUICKTALK-OK
```

**결론**
- 온디바이스 모델이 **도구를 실제로 선택·호출**했다. → 3프로바이더 통일 가능 확인.
- `call(arguments:)` 는 `respond(to:)` **안에서 자동 실행**된다. 결과가 곧 응답에 반영된다.
  → **정책 게이트는 `Tool.call` 안에서** 하면 되고, 별도 왕복 관리가 필요 없다(1왕복으로 끝남).
- 호출 내역은 `transcriptEntries` 의 `.toolCalls` 에 남는다 → 실행 카드·감사 로그에 사용 가능.
- `@Tool` 매크로가 없어 **프로토콜 직접 구현**이 필요하다. `parameters` 는 `@Generable` 인자면 기본 제공.

### 스파이크 2 — 샌드박스 권한 협상 → **PASS** (결함 4건 발견 → 수정 → 재검증)

```
=== 1) 요구 권한 실측 (probe) ===
  df -h / | head -2        → 읽기 · 보통
  ls /Users/lee | head -3  → 읽기 · 보통
  brew list | head -3      → 읽기 · 보통      ← brew를 몰라도 "읽기"임을 앎
  adb devices | head -3    → 읽기 · 보통      ← adb를 몰라도 "읽기"임을 앎
  echo hello > <경로>      → 쓰기(<경로>) · 보통
  curl … https://example.com→ 네트워크 · 보통
  sudo -n true             → 상승 권한 · 중요
=== 2) 승인한 경로만 열어 재실행 ===
  허용 경로 쓰기 → exit=0, 파일 생성됨 ✅
  허용 밖 쓰기   → exit=1, "Operation not permitted", 파일 안 생김 ✅
=== 3) 위험도 판정 (구조적 신호 — 명령 목록 없음) ===
  brew install whisper-cpp        → 보통
  ollama pull qwen3              → 보통
  sudo rm -rf /var/tmp/x         → 중요
  defaults write -g com.apple…   → 중요
  curl -s …/x.sh | bash          → 중요
  rm -rf /                       → 치명적
  dd if=/dev/zero of=/dev/disk3  → 치명적
```

**결론**
- 앱은 `brew`·`adb`·`ollama`의 이름을 **모른다**. 읽기 전용으로 먼저 돌려 "무슨 권한이 필요한지"만 알면 된다.
- 승인은 경로 스코프로 구현하면 실제로 blast radius 가 제한된다(허용 밖 쓰기는 차단됨).
- 위험도는 명령 이름 없이 **구조적 신호**(상승권·시스템영역·파이프→인터프리터·재귀삭제 대상)로 판정된다.

**스파이크가 찾아낸 결함 4건 (모두 수정·재검증 완료)**

| # | 결함 | 원인 | 수정 |
|---|---|---|---|
| 1 | 쓰기 경로가 `"/bin/sh: …"` 로 잘못 추출 | 경로가 메시지보다 **앞에** 옴 | 콜론 분할 후 "/" 시작 마지막 조각 사용 |
| 2 | 네트워크를 "차단됨"으로 오판 | 샌드박스는 네트워크를 **막기만** 하고 실패는 도구 신호로 옴 | curl 6 / ping 68 / "Unknown host" 계열 인식 |
| 3 | `sudo rm -rf /var/tmp/x` 를 치명적으로 오판 | `"rm -rf /"` **접두사** 매칭 | 토큰 단위 판정(대상은 정확히 `/`·`~`·`/System` … 인 경우만 치명적) |
| 4 | `curl … \| bash` 를 보통으로 오판 | 토큰화 때 `\|` 가 구분자로 제거됨 | `|` 를 토큰으로 유지 |

추가로 **`URL.resolvingSymlinksInPath()` 가 `/var` → `/private/var` 를 못 푼다**는 사실을 확인 →
샌드박스 규칙에는 `realpath(3)` 결과를 써야 한다(§4.1 주의 1).

## 11. v0.18 구현 결과 (2026-10-22 00:06)

### 구현 파일

| 파일 | 역할 | 상태 |
|---|---|---|
| `Sources/QuickTalkCore/AgentTypes.swift` | 권한 단계·위험도·자동 처리 정책·`AgentTool`·`AgentMessage`·`AgentStep`·`AgentClient` | 신규 |
| `Sources/QuickTalkCore/SandboxRunner.swift` | 샌드박스 실행 · **요구 권한 실측**(읽기/쓰기(경로)/네트워크/상승) · 스코프 프로파일 | 신규 |
| `Sources/QuickTalkCore/RiskClassifier.swift` | 위험도 판정(구조적 신호만) | 신규 |
| `Sources/QuickTalkCore/PolicyEngine.swift` | `AgentPolicy` + 허용/확인/차단 결정 + 규칙 매칭 | 신규 |
| `Sources/QuickTalkCore/ToolSchemas.swift` | 도구 3종 스키마 + 에이전트 지시문 + 앱 자신 지식 | 신규 |
| `Sources/QuickTalkCore/AgentRunner.swift` | 에이전트 루프(호출→실행→관찰→반복) + 실행 기록 | 신규 |
| `QuickTalkApp/AgentClients.swift` | 3프로바이더 클라이언트(OpenAI 호환 / Ollama `/api/chat` / Apple FM FoundationModels) | 신규 |
| `QuickTalkApp/AgentExecutor.swift` | 정책 게이트 · 샌드박스 실행 · 승인 대기 · 파일 읽기/목록 | 신규 |
| `QuickTalkApp/AgentAudit.swift` | 실행 감사 기록(비밀 마스킹) | 신규 |
| `QuickTalkApp/AgentCard.swift` | 대화 속 실행 카드 + 승인 UI(커스텀, 네이티브 alert 없음) | 신규 |
| `QuickTalkApp/UIStore+Agent.swift` | 도구 필요 판정(모델 판단·캐시 10분) · 에이전트 턴 · 헤드리스 자가진단 | 신규 |
| `QuickTalkApp/SettingsView+Tools.swift` | 설정 › 도구(권한 3단계·제한·허용 규칙·실행 기록) | 신규 |
| `Sources/QuickTalkCore/Settings.swift` | `agentToolsEnabled` · `agentPolicy` (구버전 설정은 기본값) | 수정 |
| `QuickTalkApp/UIStore.swift` | `send()` 에이전트 분기 · 판정을 웹 검색과 **병렬** 실행 | 수정 |
| `QuickTalkApp/ContentView.swift` | 턴 아래 실행 카드 렌더 | 수정 |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 새 문구 영문 번역 66건 | 수정 |

### 동작 흐름

```
질문 → [병렬] 웹 검색 필요 판정 · 도구 필요 판정(모델에게 짧게 질문, 캐시 10분)
     → 도구 필요 없으면: 기존 경로 그대로(스트리밍 유지)
     → 도구 필요 있으면: 에이전트 루프
          모델 → 도구 호출 → 샌드박스로 요구 권한 실측 → 정책 판단
                → 허용: 스코프 프로필로 실행 → 결과를 tool 메시지로 되돌림 → 다음 스텝
                → 확인: 대화 카드에 [한 번 허용][항상 허용][거부] → 사용자 응답 후 진행
                → 차단/거부: 모델에 "거부했다"를 되돌려 다른 방법 제안
          → 최종 답을 답변 말풍선에 표시(실행 카드는 그 아래)
```

### 검증

- `swift test` **354/354** (6 skip, 신규 **22**: 위험도 8 · 정책 6 · 샌드박스 실측 4 · 루프 2 · 스키마 1 · 설정 왕복 2)
- `xcodebuild` **BUILD SUCCEEDED** (경고 0)
- 헤드리스 자가진단 `--agent-test=<질문>` (신규):
  - **Apple FM** — `df -h` 를 직접 실행 → *"실제로 사용 가능한 하드 용량은 521 GiB입니다"* (3스텝 · 16.0초)
  - **원격 OpenAI 호환** — 3개 도구 실행 + 1개 거부(네트워크 명령) → *"측정 명령이 거부되어 … 링크 상태는 읽기 전용으로 확인했습니다"* (4스텝 · 20초)
  - 로그: `docs/qa/t18-agent/selftest-applefm.log` · `selftest-remote.log`
- 배포: 2026-10-22 00:06 `~/Applications/QuickTalk.app`, `codesign --verify --strict` OK,
  SHA-256 `a261f40ba070a92baf33875906bbe37e2f249c8cec9def6a8d85ab0767a87327`(빌드 산출물과 일치)
- 사용자 실측 대기: `docs/qa/t18-agent/CHECKLIST.md` (P1~P19)

### 구현 중 발견·해결한 문제 3건

| # | 문제 | 해결 |
|---|---|---|
| 1 | 프록시의 thinking 모델이 **2차 요청에서 400** — `reasoning_content` 를 되돌려 보내야 한다 | `AgentMessage.reasoningContent` 추가 · OpenAI 형식 변환에 `reasoning_content` 포함 · `WebSearchTool.Response.reasoning` 파싱 |
| 2 | Apple FM 응답의 `GeneratedContent` 를 그대로 JSON 직렬화하려다 **NSException 크래시** | `GeneratedContent.jsonValue` 변환기 추가(JSON 값으로 변환 후 직렬화) |
| 3 | 위험도 판정이 **시스템 경로 참조**까지 위험으로 봤다(`/usr/bin/df` → 중요 → 매번 확인) | 변경 명령의 **대상**이 시스템 경로일 때만 위험 신호. 실행 경로 참조는 읽기로 취급 |

### 남는 한계 (v0.19 이후)

- **일정 조회·생성** 전용 도구가 없다(캘린더는 셸로는 권한이 필요) → v0.20 이후
- **되돌리기(휴지통 rewrite)** 는 설계만 있고 v0.18엔 미구현 → v0.19
- **스크린샷·멀티모달·Shortcuts** → v0.21
- **도구 필요 판정**이 매 질문마다 모델을 한 번 더 부른다(캐시 10분·웹 검색과 병렬 실행으로 지연 억제).
  스트리밍을 유지하려면 이 판정이 필요하다 — v0.22 에서 "스트리밍 중 tool_calls 수집" 방식으로 바꿀 수 있다.
- **Apple FM 은 온디바이스라 다단계 계획이 불안정**하다(같은 명령을 두 번 실행하기도 함). 원격이 주 운영 권장.
- 앱 안의 **일정·설정 변경**은 아직 셸로 접근하지 않는다(권한·안전). 전용 도구로 제공해야 한다.
