# PLAN v0.15 — 자동 대화 기억 정리 (T-71, macOS)

> 상태: **구현 완료 · 사용자 실측 대기** (2026-10-20 22:45 KST, 2026-10-21 강제 축약·요약 직접 편집 추가)
> 관련: T-70 웹 검색, `docs/HANDOFF.md` §2, `docs/QA-CHECKLIST-2026-10-20.md` §J

## 1. 문제

QuickTalk은 대화가 길어질수록 **매 턴 전체 기록을 다시 전송**한다.

- 원격·Ollama: 입력 토큰이 계속 늘어 첫 토큰 지연·비용이 커진다.
- Apple FM: 컨텍스트가 **4,096토큰**이라 어느 순간 요청이 실패한다.
- 사용자는 `/compact` 같은 명령을 직접 치고 싶지 않다. “필요하면 앱이 알아서” 정리해야 한다.

## 2. 결정

| 질문 | 결정 |
|---|---|
| 언제 정리하나 | **결정론적 임계치** — 입력 예산의 **70%** 초과 |
| 어떻게 요약하나 | **모델 1회(또는 청크 롤링)** — 판정을 매 턴 호출하지 않는다 |
| 언제 실행하나 | **답변 완료 후 백그라운드** — 현재 답변 지연 없음 |
| 원문을 지우나 | **아니오** — 화면·보관함·검색의 원문 턴은 그대로 |
| 무엇을 보내나 | `요약 + 경계 이후 최근 원문`만 |
| 최근 원문 몇 개 | 기본 **6개**(짝수 보정), Apple FM은 **4개** |
| 사용자가 해제하면 | 요약 삭제 + **자동 정리 일시 중지**(다시 켜기 전까지) |
| 수동 명령 | `/compact`는 **보조 수단**으로만 유지(일반 UX 아님) |

핵심 원칙: **원문은 기억의 단일 출처**로 남기고, 요약은 **전송용 캐시**로만 쓴다.

## 3. 프로바이더 예산

| 종류 | 전체 컨텍스트 | 입력 예산(출력·지시문 예약 후) | 70% 트리거 |
|---|---:|---:|---:|
| Apple FM | 4,096 고정 | 2,816 | 1,971 |
| Ollama | 기본 8,192 (`contextTokens`로 재정의) | 5,888 | 4,121 |
| OpenAI 호환(원격) | 기본 32,768 (`contextTokens`로 재정의) | 30,464 | 21,324 |

- 토큰 추정은 보수적이다: 비ASCII 1자 ≈ 1토큰, ASCII 4자 ≈ 1토큰, 메시지당 4토큰 + 첨부 이름.
- 프로바이더 편집 시트에 **컨텍스트 토큰(선택)** 입력을 추가했다. 비우면 위 기본값.

## 4. 데이터 모델

`Conversation`에 구버전과 호환되는 선택 필드를 추가했다.

```swift
public var summary: String?              // 요약 본문
public var summaryThroughTurnID: UUID?   // 요약이 커버하는 마지막 턴
public var compactPaused: Bool?          // 사용자가 자동 정리를 멈춤
```

- `activeSummary`: `summary`가 있고 경계 턴이 실제로 존재할 때만 유효.
- `summaryBoundaryIndex` / `summarizedTurnCount`: 배너·전송 경계 계산.
- 모두 `decodeIfPresent`라 옛 `history.json`도 그대로 열린다.
- `LLMProviderConfig.contextTokens: Int?`도 선택 필드라 옛 설정 JSON과 호환.

## 5. 동작

### 5.1 전송

```
[이전 대화 요약(사실·결정·선호)]  ← 프롬프트 앞에 고정
+ 경계 이후 최근 원문 턴들
+ (필요할 때만) 웹 검색 결과
+ 이번 질문
```

- 요약을 **턴이 아니라 프롬프트 앞**에 두어 Apple FM의 6턴 제한에 잘리지 않게 했다.
- 요약 경계가 사라진 기록(편집·손상)은 요약을 무시하고 전체 원문을 보낸다.
- `requestHistory`와 `memoryPromptPrefix`는 Core 순수 함수라 단위 테스트로 고정했다.

### 5.2 자동 정리

1. 답변 성공 후 `startAutoCompact(convID:)`.
2. 예산 70% 미만이면 아무 일도 하지 않는다.
3. 초과면 최근 원문 `N`개를 남기는 **짝수 경계**를 잡는다.
4. 경계 이전 턴 + 기존 요약을 모델에 넣어 **롤링 요약**을 만든다.
   - Apple FM: 1,500자 청크 / 요약 800자 상한.
   - 원격·Ollama: 12,000자 청크 / 요약 4,000자 상한.
5. 성공하면 `summary`·`summaryThroughTurnID`만 갱신하고 `history.json`에 저장.
6. 실패하면 **아무것도 바꾸지 않고** 로그만 남긴다(다음 성공 턴에 재시도).

추가 트리거:
- 앱 시작 시 마지막 대화 복원 직후
- 보관함에서 대화를 열 때
- 답변 후

답변 도중에는 절대 정리하지 않는다. 정리 Task는 `isCompacting`으로 중복 실행을 막고,
대화방 ID·경계 턴이 그대로일 때만 적용한다.

### 5.3 수동 `/compact`

- 입력이 정확히 `/compact`(공백·대소문자 무시)이면 전송하지 않고 즉시 정리한다.
- 일시 중지 상태였다면 자동 정리를 다시 켠 뒤 정리한다.
- 정리할 과거가 없으면 “정리할 이전 대화가 없습니다.”만 표시한다.

### 5.4 요약 해제·다시 켜기

- 배너 **[해제]**: `summary` 삭제 + `compactPaused = true` → 자동 정리 중지.
- 배너 **[다시 켜기]**: `compactPaused = nil` → 즉시 예산을 넘었으면 백그라운드 정리.
- 해제해도 원문은 그대로이며, 다음 요청은 전체 원문을 보낸다(사용자 선택 존중).

## 6. UI

### 입력독 위 기억 배너

| 상태 | 문구 | 동작 |
|---|---|---|
| 정리 중 | `이전 대화를 정리하는 중…` + 스피너 | — |
| 요약됨 | `이전 N개 메시지를 요약해 기억 중` | [보기] 요약 시트 · [해제] |
| 일시 중지 | `자동 정리가 일시 중지되어 있습니다` | [다시 켜기] |
| 실패(수동) | `대화 정리에 실패했습니다 (E-MAC-MEM-0001)` | [x] 닫기 |

- [보기] 시트: 모델이 보는 요약 전문 + “원문은 화면·보관함에 그대로 남아 있습니다.”
- 정리 중인 대화방이 아닐 때는 배너를 띄우지 않는다.

### 설정 › AI › 대화 기억 정리

- **자동으로 정리** 토글(기본 켜짐)
- **최근 원문 유지** 4/6/8/12개
- **[지금 정리]**, 요약이 있으면 **[요약 해제]**
- **현재 약 N토큰 · 자동 정리 기준 M토큰** — T-72 후속. 사용자가 “요약은 언제 하냐”고 물었을 때 화면에서 바로 확인할 수 있게 현재 추정치와 70% 트리거를 함께 보여 준다.
- “기준을 넘으면 다음 답변을 마친 뒤 백그라운드에서 정리합니다.” — 실행 시점을 명시.
- Apple FM은 4,096 예산에 맞춰 최근 4개로 자동 제한한다는 설명

### QA 렌더

- `docs/qa/memory-chat-ko.png` · `-en.png` — 기억 배너
- `docs/qa/memory-settings-ko.png` · `-en.png` — 설정 카드

## 7. 안전·오류

- **원문 불변**: 정리는 `summary`만 바꾼다. 턴 삭제·이동 없음.
- **로그 최소화**: 턴 수·요약 글자 수·지연만 남기고 대화 내용·요약 본문은 로그에 쓰지 않는다.
- **경계 검증**: 적용 직전에 대화방 ID와 경계 턴 존재를 확인한다. 사용자가 해제했으면 적용하지 않는다.
- **오류**: `E-MAC-MEM-0001` (요약 생성 실패/빈 요약). 자동 정리는 조용히, 수동은 배너로 알린다.
- **자가검증 보호**: QA용 `applyConversationForSelfTest`는 `syncArchive()` 저장을 차단해 실제 `history.json`을 덮어쓰지 않는다.

## 8. 검증 (2026-10-20)

- `swift test` **247/247**, 6 skip(`QT_LIVE` 4 + `QT_LIVE_STREAM` 2), BUILD SUCCEEDED.
- 신규 테스트 21건: 토큰 추정·예산·경계·요약 컨텍스트·트리거·전사/청크·프롬프트·Codable/구버전.
- 헤드리스 Apple FM: 20턴, before **2,100** → after **513**, recent 3, **6.6초**.
- 헤드리스 원격: 20턴, before **2,100** → after **903**, recent 5, **3.5초**.
- 자동 트리거: 20턴 `expected=YES → summary=YES`, 10턴 `expected=NO → summary=NO`.
- 실제 `history.json`은 자가검증 전후 **SHA-256 동일**(테스트 오염 없음).

## 9. 비목표 (다음 단계)

- 대화별 자동 정리 on/off(현재는 전역 + 대화별 일시 중지)
- 요약 임베딩/장기 기억 검색

> 2026-10-21 추가 구현: **최근 원문이 예산을 넘는 장문 대화**는 `ConversationMemory.fitHistory`가
> 오래된 턴을 이번 요청에서만 제외하고 배너로 알린다(원문 저장은 불변). **요약 직접 편집**은
> `MemorySheet` + `ConversationStore.replaceSummary`로 경계·일시 중지 상태를 유지한다.
> 웹 검색 P2·P3는 `PLAN_v0.14`에서 완료했다.

## 10. 파일

- `Sources/QuickTalkCore/ConversationMemory.swift` — 예산·트리거·경계·전사·청크·요약 프롬프트
- `Sources/QuickTalkCore/Models.swift` — 요약 필드·경계·배너 카운트
- `Sources/QuickTalkCore/Store.swift` — 요약 적용·해제·재개
- `Sources/QuickTalkCore/Settings.swift` — `autoCompact`·`compactKeepTurns`
- `Sources/QuickTalkCore/LLMProvider.swift` — `contextTokens`
- `QuickTalkApp/UIStore.swift` — `/compact`·자동 트리거·백그라운드 요약·요청 조립
- `QuickTalkApp/ContentView.swift` — 기억 배너·요약 시트
- `QuickTalkApp/SettingsView+AI.swift` — 설정 카드
- `QuickTalkApp/ProviderEditorSheet.swift` — 컨텍스트 토큰 입력
- `QuickTalkApp/AppDelegate+RenderHarness.swift` — `--compact-test`, `--compact-auto-test`, `--demo-memory`
- `Tests/QuickTalkCoreTests/ConversationMemoryTests.swift` — 21건
