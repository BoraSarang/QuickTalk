# PLAN v0.26 — 비서(페르소나) · 예약 작업 · 리포트 (macOS)

> 작성: 2026-11-03 · 상태: **1~5단계 구현 완료 (실측 대기)**
> 상위 문서: `docs/HANDOFF.md`(단일 출처) · `docs/CHANGELOG.md` · `docs/plans/PLAN_v0.18_agent-runtime_macos.md` · `PLAN_v0.25_computer-control_macos.md`
> i18n: 사용자 노출 문자열은 **`en`(기본) + `ko`** 동시 등록 — `Sources/QuickTalkCore/LocalizationTable.swift` 한 곳(기존 방식). 새 키 누락은 `LocalizationCoverageTests` 가 실패시킨다.

## 0. 한 줄 요약

**성격을 가진 비서 여러 명**을 만들고, 그 비서에게 **매일/매주 정해진 시각에 자동으로 일을 시킨다**. 결과는 **지정 폴더에 Markdown 파일**로 저장하고, 대화에는 **성공/실패 + 핵심 요약 + 파일 경로**만 남기며, **알림**으로 알린다. 사용자가 없을 때 권한이 필요하면 **멈추고 "승인 대기" 알림**을 띄운다 — 승인 없이는 아무것도 실행하지 않는다.

사용자 요청(원문 요지):
> "돌쇠라는 놈을 영입하고 싶다. 아침에 이 문서 읽어서 리포트 만들어서 매일 9시에 만들어놔(알람 포함). 졸쇠는 매일 아침 테크 상품 10개 정리. `/할일`로 목록 보고 삭제하고, 대화하다가 '이 리포트대로 매일 10시에' 하면 일정이 추가되고, 성격·말투가 있는 비서를 부려먹고 싶다."

## 1. 왜 지금인가 · 무엇이 달라졌나

| 지금 | v0.26 이후 |
|---|---|
| 앱은 **내가 물을 때만** 답한다 | **정해진 시각에 먼저** 일하고 결과를 쌓는다 |
| 시스템 프롬프트는 전역 1개 | **페르소나별** 말투·역할 (돌쇠·졸쇠 …) |
| 대화는 휘발성 기록 | **리포트 파일**이 남아 나중에 다시 열 수 있다 |
| 알림 없음(`UserNotifications` 사용처 0) | 완료·승인 대기 **배너 알림(소리 포함)** |
| 예약 개념 없음(타이머는 클립보드·UI용) | **스케줄러** + 놓친 작업 1회 따라잡기 |

## 2. 범위

### 2.1 Phase 1 — 페르소나 · 예약 · 리포트 · 알림 · `/할일`

- **페르소나 여러 명** — 이름·역할·말투·기본 모델·기본 도구 선택. 채팅 상단에서 선택, `/돌쇠` 같은 호출은 Phase 2.
- **일정 등록 3경로** — ① 설정 화면 ② `/할일` 팔레트에서 "새 일정" ③ **대화 중 모델이 `schedule_task` 도구 호출**(확인 카드 필수).
- **반복 규칙** — 매일 HH:mm · 매주 N요일 HH:mm · 한 번(지정 일시). 시간대는 시스템 로컬.
- **실행** — 앱이 실행 중일 때 정각(±10초)에 턴 실행. 놓쳤으면 **최근 24시간 내 1회만 따라잡기**.
- **결과** — ① 지정 폴더에 Markdown 파일 ② 대화(비서 전용)에 **요약 카드** ③ 배너 알림.
- **권한** — **항상 승인**. 승인이 필요하면 실행을 멈추고 **"승인 대기" 알림** → 사용자가 승인하면 그 지점부터 이어서 실행.
- **`/할일`** — 목록(다음 실행·마지막 결과·상태) · `[지금 실행] [일시 중지] [삭제]`.

### 2.2 Phase 2 — 대화에서 일정 만들기 강화 · 히스토리

- 모델이 **대화 맥락에서** 일정 생성("이 리포트대로 매일 10시") — 지시문에 직전 턴 내용을 참조로 넣는다.
- 실행 이력 화면(최근 30회: 시작·종료·결과·파일·실패 사유).
- `/돌쇠`·`/졸쇠` 호출(페르소나 이름으로 대화 시작).
- 앱이 꺼져 있을 때를 대비한 **대체 알림**("앱을 열면 오늘 몫을 실행합니다").

### 2.3 Phase 3 (비목표)

- 조건부 스케줄("가격이 바뀌면"), 외부 파일 감시, 클라우드 동기화, 다중 기기.
- 자동 승인 범위 세분화(일정별 읽기/쓰기/실행) — **지금은 의도적으로 넣지 않는다**(항상 승인 원칙).
- macOS LaunchAgent로 앱이 꺼져 있어도 실행 — 앱 번들 밖 시스템 변경이라 **비목표**.

## 3. 용어

| 용어 | 정의 |
|---|---|
| **페르소나** | 이름·역할·말투·기본 모델·기본 도구를 가진 비서 정체성. 시스템 프롬프트 **앞**에 붙는다 |
| **일정** | 페르소나 + 지시문 + 반복 규칙 + 다음 실행 시각 |
| **실행(run)** | 일정이 실제로 돈 1회. 상태: `running`·`succeeded`·`failed`·`awaitingApproval`·`cancelled`·`missed` |
| **리포트** | 실행 결과 Markdown 파일(기본 `~/Documents/Reports/`) |
| **요약 카드** | 대화에 남는 한 장 — 성공/실패 · 핵심 2~3줄 · 파일 경로 |

## 4. 데이터 모델 (Core, 전부 순수)

### 4.1 `Persona` (`Sources/QuickTalkCore/Persona.swift`)

```swift
public struct Persona: Codable, Identifiable, Equatable {
  public var id: UUID
  public var name: String            // "돌쇠" (1~20자)
  public var role: String            // "매일 아침 테크 소식을 정리하는 비서"
  public var tone: String            // "짧고 딱딱하게, 존댓말 없이"
  public var emoji: String?          // 카드·알림 아이콘(선택)
  public var providerID: String?     // nil = 설정의 활성 프로바이더
  public var tools: PersonaTools     // 사용할 도구 집합
  public var reportFolder: String?   // nil = 설정의 기본 리포트 폴더
  public var createdAt: Date
}
```

- `PersonaPrompt.compose(persona:base:)` — **기존 `AgentInstructions.text` 를 유지**하고 앞에 정체성 3~5줄만 붙인다(전역 안전 규칙은 지우지 않는다). 이름·역할·말투는 **보간하지 않고 그대로** 넣되 길이 상한(이름 20자·역할 200자·말투 200자).
- `PersonaTools` — `read/web/shell/write/execute/ui` 중 무엇을 허용할지. **도구를 꺼도 권한 판정은 그대로**(이중 게이트).

### 4.2 `ScheduleRule` (`Sources/QuickTalkCore/ScheduleRule.swift`)

```swift
public enum ScheduleRule: Codable, Equatable {
  case daily(hour: Int, minute: Int)
  case weekly(weekday: Int, hour: Int, minute: Int)   // 1=일 … 7=토
  case once(Date)
}
```

핵심 함수(순수, 테스트 대상):

- `next(after:calendar:)` — 다음 실행 시각. **DST·자정 경계** 테스트 포함.
- `missedRun(now:lastScheduled:)` — 최근 24시간 내 놓친 1회 여부(따라잡기 판정). 24시간을 넘겼으면 `missed` 로 기록하고 건너뛴다.
- `humanDescription(language:)` — "매일 오전 9:00" / "Every day at 9:00 AM".

### 4.3 `ScheduledTask` (`Sources/QuickTalkCore/ScheduledTask.swift`)

```swift
public struct ScheduledTask: Codable, Identifiable, Equatable {
  public var id: UUID
  public var personaID: UUID?        // nil = 기본(비서 없음)
  public var title: String            // "OpenCode V2 데스크톱 리포트"
  public var instruction: String      // 실제 지시문(그때 만든 리포트 내용 포함 가능)
  public var rule: ScheduleRule
  public var enabled: Bool
  public var nextFireAt: Date?
  public var lastRun: RunRecord?
  public var createdAt: Date
  public var conversationID: UUID?    // 결과 카드를 남길 대화
}
```

- `RunRecord` — `startedAt`·`finishedAt`·`status`·`filePath`·`summary`·`failureReason`. 최근 30건만 보관.
- `ReportNaming.fileName(title:date:)` — `2026-11-04-opencode-v2-desktop-리포트.md`(공백·경로 구분자·예약어 정리, 같은 이름이면 `-2`).
- `ScheduleSummaryCard.text(run:)` — 대화 카드 문구(성공/실패 두 형태).

### 4.4 저장 (`Sources/QuickTalkCore/ScheduleStore.swift`)

- 파일: `~/Library/Application Support/QuickTalk/schedules.json` (원자적 쓰기 — `PersistenceService` 패턴).
- **대화 삭제와 분리** — 대화를 지워도 일정·리포트는 남는다. 페르소나는 설정 JSON(`QuickTalk.settings.personas`)에 둔다.
- 스키마 버전 키(`schemaVersion`) — 이후 마이그레이션 대비.

## 5. 실행 흐름

```
스케줄러(앱 실행 중, 20초 주기 폴링)
  └ due? → 실행 시작
       ① 페르소나·일정 로드 → 비서 전용 대화 확보(없으면 생성)
       ② 요약 카드 "실행 중" 추가 (upsertAgentEvent 규칙 준수 — 카드 1장)
       ③ 일반 턴 실행(기존 AgentRunner 재사용, 페르소나 프롬프트 주입)
       ④ 도구가 승인을 요구하면 → 상태 awaitingApproval + "승인 대기" 알림
            · 앱이 살아 있는 동안 턴은 대기 상태 유지
            · 사용자가 승인 → 그 지점부터 이어서 실행
            · 거부/시간 초과(10분) → 실패로 기록하고 종료
       ⑤ 완료 → 리포트 파일 쓰기 → 카드 갱신(성공/실패+요약+경로) → 완료 알림
       ⑥ nextFireAt 재계산 → 저장
```

- **중복 방지**: `nextFireAt` 을 **실행 시작 전에** 미리 갱신하고 저장(크래시 후 재실행 중복 방지).
- **동시 실행 금지**: 한 번에 1개 실행, 나머지는 `queued`. 밀린 일정이 3개를 넘으면 1개만 실행하고 나머지는 `missed` 기록.
- **앱 종료**: `running`/`awaitingApproval` 상태로 남은 실행은 다음 기동 때 `interrupted` 로 정리하고, 그 일정은 **다음 정시**에 다시 실행(즉시 재실행은 중복 비용·부작용 위험).

## 6. 권한 · 안전

| 규칙 | 내용 |
|---|---|
| **항상 승인** | 예약 실행도 사용자 설정의 권한 정책을 그대로 따른다. 자동 허용 예외를 만들지 않는다 |
| 승인 대기 알림 | 배너 + 소리. 클릭하면 해당 대화·카드로 이동. 액션 버튼은 **"열기"만**(알림에서 바로 승인 불가 — 오탭 위험) |
| 승인 대기 만료 | 10분. 넘으면 실패로 기록하고 알림("승인 대기 만료 — 다시 실행하세요") |
| 금지 | 예약 실행에서도 `allowCritical=false`(치명적 차단)·상승 권한 차단은 그대로. **끄는 UI를 만들지 않는다** |
| 감사 | 모든 실행을 `agent-audit.log` 에 `task:<id>` 태그로 남긴다. 리포트 파일 경로도 기록 |
| 파일 | 리포트 폴더를 벗어나는 경로(심볼릭 링크·`..`) 거부. 폴더가 없으면 만들되 **사용자 홈 밖은 거부** |
| 시크릿 | 페르소나·일정·리포트에 API 키를 쓰지 않는다. 프롬프트에 시크릿을 넣지 않는다(테스트로 고정) |

## 7. 도구 `schedule_task` (Phase 1 ③)

- 스키마: `{ title, instruction, rule: {kind: daily|weekly|once, hour, minute, weekday, date}, persona }`
- 실행 경로: 모델 호출 → **검증(Core 순수)** → **확인 카드**(제목·시각·지시문 요약·사용 도구) → 승인 시 등록.
- **금지**: 일정 자체를 만드는 것도 `write` 단계로 취급(설정 변경과 동급). 승인 없이 등록되지 않는다.
- 모델이 이미 있는 일정과 같은 제목·시각을 요청하면 **중복 확인 카드**("이미 있습니다 — 수정할까요?").
- 일정 삭제 도구는 만들지 않는다 — 삭제는 `/할일` UI에서만(모델이 실수로 지우는 경로 차단).

## 8. UI

### 8.1 설정 › 새 탭 `비서`

- 페르소나 목록(이름·역할·이모지) + 편집 시트(이름·역할·말투·모델·도구·리포트 폴더) + `[+]`.
- 기본 리포트 폴더 선택(`NSOpenPanel` — custom 프로필 규칙상 시스템 패널은 파일 선택에 한해 허용, 기존 창 연결과 동일).
- 일정 목록은 `/할일` 과 같은 뷰를 공유(중복 구현 금지).

### 8.2 `/할일` 팔레트

- 기존 `SlashCommand` 에 `id: "tasks"`, 이름 `할일`/`Tasks`, 템플릿은 **팔레트가 아니라 전용 시트**를 연다(기존 명령은 템플릿 채우기 — 예외 규칙을 SlashCommand 에 명시).
- 시트: 일정 카드(페르소나 이모지·제목·다음 실행·마지막 결과·상태 칩) + 버튼 `[지금 실행] [일시 중지] [삭제] [편집]`.
- 삭제는 확인 시트(기존 `DeleteConfirmSheet` 패턴).

### 8.3 채팅

- 입력독 위(또는 헤더)에 **페르소나 선택 칩** — **비서가 1명 이상일 때만** 표시. 목록 맨 위는 **`기본`(페르소나 없음) = 현재 동작**.
- 대화별 저장은 `Conversation.personaID: UUID?` — **nil = 기본**. 기존 대화는 nil 이므로 마이그레이션 없음.
- 새 대화 기본값은 `기본`(설정 `defaultPersonaID` 로 바꿀 수 있지만 기본값은 nil).
- 비서 전용 대화는 제목에 `🦾 돌쇠` 처럼 표시(자동 생성, 핀 처리).

### 8.4 알림

- `NotificationService` — 첫 사용 시 권한 요청, 거부되면 설정에 안내 + 시스템 설정 딥링크.
- 알림 2종: **완료**(성공/실패 + 파일명) · **승인 대기**. 소리 포함(사용자 요청 "알람 포함").
- **야간 무음 22:00~08:00** — 소리 없이 배너만. 시간대는 설정에서 변경(`notificationsQuietFrom/To`).

## 9. 파일 계획

### 신규 (Core — 순수, 단위 테스트 대상)

| 파일 | 내용 |
|---|---|
| `Persona.swift` | 모델·검증·프롬프트 합성·도구 집합 |
| `ScheduleRule.swift` | 다음 시각·따라잡기·설명 문구 |
| `ScheduledTask.swift` | 모델·`RunRecord`·파일 이름·요약 카드 문구 |
| `ScheduleStore.swift` | `schedules.json` 로드/저장(원자적)·스키마 버전 |

### 신규 (App — 시스템 접촉면)

| 파일 | 내용 |
|---|---|
| `SchedulerService.swift` | 20초 폴링·중복 방지·동시 1개·따라잡기·앱 종료 정리 |
| `ScheduledRunRunner.swift` | 턴 실행·승인 대기 처리·리포트 저장·카드 갱신 |
| `ReportWriter.swift` | 폴더 검증·파일 이름·원자적 쓰기·덮어쓰기 회피 |
| `NotificationService.swift` | 권한·배너·소리·클릭 이동 |
| `SettingsView+Assistant.swift` | 설정 › 비서 |
| `TaskListSheet.swift` | `/할일` 시트 |
| `PersonaPickerChip.swift` | 채팅 페르소나 선택 (기존 파일에 합쳐도 됨 — `project.pbxproj` 명시 등록 주의) |

### 수정 (요지)

- `ToolSchemas.swift` — `schedule_task` 스키마 + 카탈로그 등록(도구가 켜진 턴에만).
- `AgentExecutor*.swift` — `schedule_task` 처리(검증 → 확인 카드 → 등록).
- `SlashCommand.swift` — `tasks` 명령(전용 시트 예외).
- `Settings.swift` — `personas`, `defaultReportFolder`, `notificationsEnabled`(기본 켜짐), `quietHours`(기본 22:00~08:00), `schedulerEnabled`(기본 켜짐).
- `Models.swift` — `Conversation.personaID`(`decodeIfPresent`, 구버전 nil).
- `QuickTalkApp.swift` — `SchedulerService` 기동/정지·알림 delegate 연결.
- `LocalizationTable.swift` — 신규 키(한/영) 일괄.
- `project.pbxproj` — 새 파일 등록(앱 타깃은 SPM 아님 — 명시 등록 필요).

## 10. 검증 계획

### 10.1 단위 테스트 (Core, 순수) — 목표 30~40건

- `ScheduleRuleTests` — 매일/매주/한 번 다음 시각 · 자정·월말·**DST** · 과거 시각 · 따라잡기 24시간 경계(정확히 24h, 24h+1s) · 설명 문구 한/영.
- `ScheduledTaskTests` — 파일 이름 정리(공백/`/`/`..`/이모지) · 충돌 시 `-2` · 요약 카드 성공/실패 문구 · 30건 이력 상한.
- `PersonaTests` — 이름·역할·말투 상한 · 프롬프트에 **전역 안전 규칙이 남아 있는지** · 시크릿 미포함 · 도구 집합 검증.
- `ScheduleStoreTests` — 저장/로드 왕복 · 손상 파일 → 빈 목록 + 백업 · 스키마 버전.
- `ScheduleToolTests` — 스키마 필수 키 · 잘못된 시각 거부 · 중복 감지 · 삭제 도구 부재.

### 10.2 빌드·렌더

- `swift test` 전체 통과 · Debug/Release `xcodebuild` BUILD SUCCEEDED.
- 오프스크린 렌더: 설정 › 비서(한/영) · `/할일` 시트(일정 3개·상태 3종) · 요약 카드(성공/실패) · 알림 문구는 텍스트 렌더로 확인.

### 10.3 실측(사용자) — `docs/qa/assistant-persona-2026-11-03/CHECKLIST.md`

| # | 항목 | 기대 |
|---|---|---|
| S1 | 페르소나 2명 만들고 채팅에서 전환 | 말투가 실제로 달라진다 |
| S2 | `/할일` → 새 일정(1분 뒤, 읽기 전용 지시) | 정시에 실행·카드·알림·파일 생성 |
| S3 | 승인 필요한 지시("파일 만들어") | 멈추고 "승인 대기" 알림 → 승인 시 이어서 완료 |
| S4 | 승인 거부 | 실패 기록 + 카드에 사유, 파일 없음 |
| S5 | 앱 종료 후 예약 시각 경과 → 재실행 | 24시간 내 1회 따라잡기, 중복 없음 |
| S6 | 대화에서 "이거 매일 10시에" | 확인 카드 → 등록 → `/할일` 목록에 표시 |
| S7 | 일정 삭제 | 목록에서 사라지고 더 이상 실행 안 됨(파일은 유지) |
| S8 | 알림 권한 거부 | 실행은 되고, 설정에 안내 + 딥링크 |

## 11. 위험 · 한계 (미리 적는다)

- **앱이 꺼져 있으면 실행 없음** — 로그인 자동 시작이 전제. 따라잡기는 "최근 24시간 1회"만 보장한다(그 이상 놓치면 `missed`).
- **승인 대기 중 앱 종료** — 대기 턴은 사라진다. 다음 정시에 재시도하며, 그 사이 파일·부작용은 남지 않는다(승인 전이므로).
- **모델이 만든 일정의 품질** — 지시문이 모호하면 리포트도 모호하다. 확인 카드에 지시문 전문을 보여 주고, 사용자가 수정할 수 있게 한다.
- **비용** — 매일 자동 실행은 토큰을 소비한다. 일정별 하루 1회 한도·실패 시 재시도 없음(다음 정시에만)으로 제한.
- **알림은 앱 실행 중에만** — 앱이 꺼진 동안의 "대체 알림"은 Phase 2.
- **시간대 변경·DST** — 로컬 시간 기준. 시계 변경 시 `nextFireAt` 재계산(중복 실행 방지 테스트 포함).

## 12. 작업 순서

### Phase 1 — 5단계(각 단계 끝에 `swift test` + 빌드)

1. **Core 모델·규칙** — `Persona`·`ScheduleRule`·`ScheduledTask`·`ScheduleStore` + 테스트 30건.
2. **저장·설정 연결** — `Settings.personas`·`Conversation.personaID`·설정 › 비서 탭(페르소나 CRUD·리포트 폴더).
3. **실행 엔진** — `SchedulerService`·`ScheduledRunRunner`·`ReportWriter`(승인 대기 포함).
4. **UI·도구** — `/할일` 시트·페르소나 칩·`schedule_task` 도구·확인 카드·번역 키.
5. **알림·검증** — `NotificationService`·렌더·QA 체크리스트·실측.

### 이후

- Phase 2: 대화 맥락 일정 생성 · 실행 이력 화면 · `/돌쇠` 호출 · 대체 알림.
- DESIGN.md §11(코드 구조)에 새 모듈 4개 반영(구현 시).

### 12.3 리포트 형식 (출처 자동)

```markdown
# 2026-11-04 아침 테크 리포트

> 돌쇠 · 매일 09:00 · 출처: 웹 검색 4건

## 3줄 요약
- …
- …

## 항목
### 1. OpenCode V2 데스크톱 — 무료 LLM 4종 추가
- 핵심: …
- 출처: https://…   ← 웹 검색을 쓴 항목은 **자동으로** 붙는다

## 다음 실행
2026-11-05 09:00
```

- 검색을 쓰지 않은 턴에는 `출처` 줄 자체가 없다(빈 절을 만들지 않는다).
- 이 골격은 **강제하지 않는다** — 사용자가 지시문에서 형식을 바꾸면 그쪽이 우선한다.

## 13. 결정 (2026-11-03 사용자 확정)

0. **비서는 선택 사항** — 비서가 없으면 지금과 **완전히 동일**하게 동작한다. `Conversation.personaID = nil` 이 기본이고 기존 대화는 마이그레이션이 필요 없다. 비서 UI(칩)는 비서를 1명 이상 만들었을 때만 나타나며, 목록 맨 위는 `기본`. 예약 작업도 `기본`을 허용한다.

1. **페르소나 여러 명** — 이름·말투·담당 일을 다르게, 일정도 페르소나별 분리.
2. **결과물**: 지정 폴더 **Markdown 파일** + 대화에는 **성공/실패 · 핵심 요약 · 파일 경로**만.
3. **권한**: **항상 승인**. 사람이 없으면 멈추고 **"승인 대기" 알림** → 승인 시 **이어서 실행**.
4. **놓친 작업**: **최근 24시간 내 1회 따라잡기**.
5. **리포트 폴더**: **설정에서 지정**(기본 `~/Documents/Reports/`).
6. **삭제는 UI에서만** — 모델에게 일정 삭제 도구를 주지 않는다.

## 14. 결정 (2026-11-03, 목업 확정)

7. **알림**: macOS 기본 알림음 + **야간 무음 22:00~08:00**(배너만, 소리 없음). 소리·무음 시간대는 설정에서 바꿀 수 있다.
8. **기억 공유**: **공통 메모리를 모든 비서가 공유**한다 — "내 취향·상황"을 한 번 알려주면 비서를 바꿔도 유지. 페르소나별 비공개 메모리는 만들지 않는다(Phase 3 후보).
9. **출처 링크**: 웹 검색을 쓴 턴은 리포트에 **출처 URL을 자동으로 붙인다**(각 항목 끝). 검색을 안 썼으면 링크 절 없음.
10. **목업 확정**: 대화 구조 유지 + 헤더 비서 칩 · `/할일`은 **시트** · 설정 › 기능 묶음에 **비서** 탭 · 결과는 요약 카드 1장. 근거: `docs/mockups/persona-2026-11-03/index.html`.

## 15. 미정 (구현 중 확인)

- 없음 — 구현을 막는 미정 항목은 모두 정리됐다. §2.3(Phase 3 후보)만 남는다.
