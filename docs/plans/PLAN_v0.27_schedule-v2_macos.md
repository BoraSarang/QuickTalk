# PLAN v0.27 — 예약 작업 v2: 규칙 고도화 + 조회/변경/삭제 도구 + 웹 본문 읽기 (macOS)

> 상태: **1단계 구현 완료 · 2단계(도구) 미구현** (2026-11-04) · 플랫폼: macos · 언어: `ko` + `en`
> 선행: `PLAN_v0.26_assistant-persona_macos.md`
> 번역 리소스: `Sources/QuickTalkCore/LocalizationTable.swift` (한국어 원문 → 영어)

## 0. 진행 상태 (2026-11-04)

**PR #83 → squash merge** 로 1단계가 `main` 에 들어갔다. 배포본 SHA-256 `12719362…`.

- [x] `ScheduleRule` v2 — `weekly(days:)` · `everyNDays` · `interval` · `once` (기존 `weekly(weekday:)` 팩토리 유지)
- [x] `ScheduleSkip` — 주말 · 대한민국 공휴일(음력·대체공휴일) · `extraDates`
- [x] `ScheduledTask.skip` 저장·정규화, 다음 시각 계산에 제외 적용
- [x] `schedules.json` `schemaVersion` 1 → 2, `weekly.weekday` 하위 호환
- [x] `/할일` 편집기 — 5종 규칙 칩 · 요일 다중 선택 · N일 + 첫 실행일 · 구간/간격 · 제외 토글/날짜
- [x] 목록 삭제 즉시 반영 — `UIStore.scheduleRevision` + `삭제 중…` 오버레이
- [x] 규칙·제외·공휴일·Codable 회귀 테스트 14건
- [x] `swift test` **782/782**(6 skip) · Debug/Release **BUILD SUCCEEDED**
- [ ] `schedule_list` 도구 (읽기 — 카드 없음)
- [ ] `schedule_update` / `schedule_delete` 도구 (쓰기 + 확인 카드, UUID 로만 대상 지정)
- [ ] `ScheduleChangeProposal` — 변경 전 → 변경 후 카드
- [ ] `ScheduleProposal` — 새 규칙(`weekly(days:)`·`everyNDays`·`interval`)·`skip` 파싱
- [ ] `ExaContentsClient` + `web_fetch` (Exa `/contents`, 같은 키)
- [ ] 예약 실행 중 변경·삭제 금지, 실행 중 일정 변경 금지, 턴당 변경 1건
- [ ] 오프스크린 렌더(편집 시트 5종·제외, 목록 카드, 확인 카드 3종)
- [ ] 사용자 실측 S1~S6


## 1. 계기

v0.26 예약 작업은 `매일 1회` · `매주 요일 1개` · `한 번` 만 표현할 수 있었다.
사용자 요구:

- 매일 09:00~21:00 **2시간마다**
- **주말·공휴일 제외**
- **이틀에 한 번**
- **월·수·금** (요일 여러 개)
- 대화에서 **"예약 목록 보여줘" · "그 일정 취소(삭제)해줘" · "시간 바꿔줘"**
- 웹 검색은 Exa 인데, **특정 URL 본문을 읽는 도구**가 없다

## 2. 범위

### 2.1 규칙 (`ScheduleRule`)

| 규칙 | 예 | 비고 |
|---|---|---|
| `daily(hour, minute)` | 매일 09:00 | 기존 |
| `weekly(days: [Int], hour, minute)` | 매주 월·수·금 09:00 | 기존 `weekly(weekday:)` 는 팩토리로 유지 |
| `everyNDays(days, hour, minute, anchor)` | 2일마다 09:00 | `anchor` = 첫 실행일(그 날짜 기준 N일 간격) |
| `interval(start…, end…, everyMinutes)` | 매일 09:00~21:00 2시간마다 | 같은 날 구간만. 09,11,13,15,17,19,21 |
| `once(Date)` | 한 번 | 기존 |

### 2.2 제외 (`ScheduleSkip`)

- `weekends` — 토·일
- `holidays` — **대한민국 공휴일 자동 계산** (양력·음력·대체공휴일)
- `extraDates` — 사용자가 직접 추가한 `yyyy-MM-dd` (임시공휴일·회사 휴무일)

계산 불가한 것: 임시공휴일·선거일. UI에 한 줄로 명시하고 직접 추가로 보완한다.
공휴일 계산은 `Foundation.Calendar(.chinese)` 로 음력을 구하고, 관공서 공휴일 규정의
대체공휴일 규칙(설·추석 연휴의 일요일/중복, 어린이날의 주말/중복, 국경일·부처님오신날·성탄절의 주말)을 적용한다.
결과는 연도별로 캐시한다. 계산 범위를 벗어나면 양력 고정 공휴일만 적용한다.

### 2.3 도구

| 도구 | 권한 | 동작 |
|---|---|---|
| `schedule_list` | 읽기 | ID·제목·비서·규칙·다음 실행·사용/중지·제외·마지막 상태·지시문(앞 300자) |
| `schedule_update` | 쓰기 + 확인 카드 | `id` 필수. 바꿀 필드만 전달. **변경 전 → 변경 후** 카드 |
| `schedule_delete` | 쓰기 + 확인 카드 | `id` 필수. **"취소" = 삭제**. 리포트 파일은 유지 |
| `schedule_task` | 쓰기 + 확인 카드 | 기존 등록 제안 (규칙·제외 확장) |
| `web_fetch` | 읽기 | Exa `/contents` 로 URL 본문 읽기 (같은 Exa 키) |

안전장치:

- 모든 변경은 `schedule_list` 에서 받은 **UUID** 로만 대상 지정. 제목 매칭 금지.
- 예약 실행 중(`ScheduledRunContext != nil`)에는 목록만 허용, 변경·삭제 금지.
- 실행 중인 일정(`SchedulerService.isRunning`)은 변경·삭제 금지.
- 한 턴에 변경 1건(카드가 모달로 기다린다).
- 감사 로그: `schedule_update <제목>`, `schedule_delete <제목>`.
- 모델은 "등록/변경/삭제했다"고 승인 전에 말하지 않는다.

### 2.4 UI

- `/할일` 편집 시트: 반복 5종 칩, 요일 다중 선택, 구간 시작·끝·간격, N일마다 + 첫 실행일,
  주말/공휴일 제외 토글, 제외 날짜 추가·삭제.
- 목록 카드: 규칙 + 제외를 한 줄로 표시.
- 확인 카드: 등록 / 변경(전→후) / 삭제 3종.

## 3. 저장·마이그레이션

- `schedules.json` `schemaVersion` **1 → 2**.
- `ScheduleRule` 은 `kind` 태그로 분기하고, 기존 `weekly` 의 `weekday`(Int)도 읽는다.
- `ScheduledTask.skip` 은 키가 없으면 `.none`.
- 기존 일정의 `nextFireAt` 은 그대로 두고, 규칙·제외가 바뀔 때만 `nil` 로 비워 재계산한다.

## 4. 검증

- `swift test`: 규칙 5종 다음 시각·DST·월말, 공휴일(2025~2028 고정 날짜), 제외 적용,
  제안 파싱(새 kind·skip), 변경/삭제 파싱, 마이그레이션.
- `xcodebuild` Debug/Release BUILD SUCCEEDED.
- 오프스크린 렌더: 편집 시트(5종·제외), 목록 카드, 확인 카드 3종.
- 실측(사용자): S1 09~21 2시간마다, S2 주말·공휴일 제외, S3 2일마다, S4 월·수·금,
  S5 대화에서 목록/변경/삭제, S6 `web_fetch`.

## 5. 하지 않는 것

- 월 단위·분기 단위 반복 (YAGNI — 필요해지면 `monthly` 추가).
- 자정을 넘는 구간(22:00~02:00).
- 임시공휴일·선거일 자동 수집(외부 API·키 필요).
- 예약 실행 중 일정 변경(사람이 없는 자리).
- 모델에 의한 비서 생성·삭제.
