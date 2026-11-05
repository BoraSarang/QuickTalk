# PLAN v0.29 — 연결 끊김 이어쓰기 · 예고 답변 방지 · 비서 상태 표시 (macOS)

> 작성 2026-11-05 KST · 상태 **구현·병합 `eec75df`**(사용자 실측·배포 대기)
> 지원 언어: 한국어·영어 (`Sources/QuickTalkCore/LocalizationTable.swift`, 기존 `L()` 경로)
> 관련: `PLAN_v0.28_persona-picker_macos.md` (비서 선택 UI), `PLAN_v0.18_agent-runtime_macos.md` (에이전트 루프)

## 1. 계기 (사용자 보고)

1. **답변이 중간에 끊긴다** — 응답 도중 네트워크가 끊기면 아무 안내 없이 끝난다.
   다시 물어보는 것 말고 방법이 없다 → **기다렸다가 이어서 쓸 수 있어야** 한다.
2. **"확인하겠습니다"만 남는다** — 도구 실행 뒤 최종 답변이 예고 문장 하나로 끝나는 경우가 있다.
   12턴·4회 도구 실행 뒤 **47자**, 25턴·12회 도구 실행 뒤 **131자** 예고만 남은 기록으로 확인.
3. **비서가 자기 리포트 폴더를 모른다** — 쓰기 가능한 경로가 프롬프트에 없어 읽기 전용 폴더를
   추측하고 "쓸 수 없다"고 답한다.
4. **입력독 글자가 위로 붙는다** — 아이콘 줄과 세로 중심이 어긋나 보인다.
5. **비서 선택 상태가 불분명하다** — 메뉴에서 `비서 없음`과 선택된 비서가 구분되지 않는다.

## 2. 목표

- 네트워크 단절 시 **설정한 간격·횟수만큼 자동 재시도**(기본 **5초 × 10회**), 대기 중 **[중지]** 가능.
- 이미 받은 부분 답변은 **버리지 않고 이어쓴다**(같은 요청 재전송 → 첫 글자 전, 이어쓰기 요청 → 첫 글자 후).
- 겹치는 경계는 한 번만 남긴다(`NetworkRetry.mergeContinuation`).
- 최종 답변이 예고·빈 답이면 **도구를 빼고 한 번 더** 최종 답변을 요구하고, 그래도 실패하면
  지금까지 확인한 결과로 **안전망 답변**을 만든다.
- 비서 프롬프트에 **실제 쓰기 가능한 리포트 폴더**와 쓰기 권한 상태를 넣는다.
- 입력독 글자·아이콘의 세로 중심을 맞추고, 비서 메뉴에 **"지금:" 머리줄 + 체크 표시**를 넣는다.

## 3. 비목표

- 대화를 처음부터 다시 생성하는 재시도 — **부분 답변 이어쓰기**만 한다.
- 자동 재시도 중 다른 모델로 전환 — 부분 답변이 섞이지 않게 예비 모델은 첫 글자 전에만 쓴다.
- 리포트 폴더를 앱이 임의로 만드는 것 — 기존 저장 경로·승인 카드 규칙을 그대로 쓴다.

## 4. 구현

### 4.1 Core — `NetworkRetry.swift` (신설)

- `NetworkRetryPolicy` — `enabled` · `intervalSeconds`(1~60) · `maxAttempts`(0~50), 기본 `.standard` = 5초 × 10회.
- `NetworkRetry.isRetryable` — 네트워크 단절·시간 초과·DNS·연결 유실·5xx·429만 참.
  취소(`CancellationError`·`URLError.cancelled`)·401·403·400/422는 거짓.
- `NetworkRetry.mergeContinuation` — 8자 이상 겹치는 꼬리/머리를 한 번만 남기고, 완전 중복은 버린다.
  겹침이 없으면 빈 줄 하나로 구분.
- `NetworkRetry.continuationPrompt(original:partial:)` — 원래 요청 + 이미 쓴 답변 + "반복하지 말고 이어쓰라" 지시.

### 4.2 설정

- `QuickTalkSettings.networkRetryEnabled / IntervalSeconds / MaxAttempts` + `networkRetryPolicy`.
- 구버전 설정(키 없음)은 **5초 · 10회 · 켜짐**. 저장값은 1~60초 · 0~50회로 클램프.
- 설정 › AI › **연결 끊김 대기**: 토글 · 간격 Stepper · 횟수 Stepper · 캡션(한/영).

### 4.3 에이전트 러너 — 예고 답변 방지

- `AgentRunner.run` 에 `retry` · `onStepStart` · `onStepDiscard` · `onRetry` 추가.
- 모델 호출 1회를 `callStep` 으로 감싸 **같은 메시지로 재시도**한다.
  실패한 시도의 부분 글자는 `onStepDiscard` 로 지우고, 도구 호출 예고도 최종 답변에서 지운다.
- `.finalAnswer` 가 비었거나 예고만이면(`looksLikeNarration`) 도구를 뺀 `finalAnswerNudge` 로 한 번 더 요청.
- 스텝 상한·재촉 실패 시 `fallbackAnswer()` — 지금까지 모은 도구 결과를 붙인다.
- `AgentInstructions.text` 에 "예고로 끝내지 않는다" 규칙 추가.

### 4.4 앱 — 스트리밍 재시도·이어쓰기

- `UIStore.streamReplyResuming` — 첫 글자 전 실패는 같은 요청 재전송, 글자 뒤 실패는 이어쓰기 요청.
  돌아온 글은 `mergeContinuation` 으로 합치고 말풍선을 `onReplace` 로 다시 맞춘다.
- `streamReplyWithFallback(allowFallback:)` — 부분 답변이 있으면 예비 모델로 넘어가지 않는다.
- `networkRetryStatus` — 대기 문구를 입력독 위 배너에 표시, `[응답 중지]` 는 기존 취소 경로를 쓴다.
- 에이전트 턴의 `onStepStart`/`onStepDiscard` 로 **도구 호출 예고가 답변에 섞이지 않게** 한다.
- 최종 `reply` 가 스트리밍 글자와 다르면(안전망·재촉 답변) 말풍선을 **최종 답변으로 교체**한다.

### 4.5 비서 · 앱 지식

- `SystemKnowledge.text(settings:persona:)` · `reportFolderText(...)` — 비서 폴더 `~` 확장,
  쓰기 꺼짐이면 "파일을 만들지 말라"고 명시.
- 일반 대화 프롬프트 앞에도 같은 리포트 폴더 블록을 넣는다(`UIStore.send`).
- `makeAgentClientIfEnabled(provider:persona:)` — 도구 경로에도 비서 전달.
- `Persona.displayEmoji` — 이모지가 비어 있으면 ID 기반 **안정적인 기본 아이콘**(기존 `🗣` 일괄 표시 제거).
- 비서 메뉴: `지금: …` 머리줄 · `비서 없음`/선택 항목에 `checkmark.circle.fill` · 칩/독에 체크 배지.

### 4.6 입력독 정렬

- `ChatInputField` 의 텍스트 inset/측정값을 조정해 **입력 글자 중심 = 아이콘 줄 중심**.
  렌더 실측: 입력독 1131~1220(중심 1175.5) · 글자 1164~1189(중심 1176.5) · 전송 아이콘 1150~1201(중심 1175.5).

## 5. 검증

- `swift test` **840/840**(6 skip, 신규 26 — `NetworkRetryTests`).
  - 정책 기본값·클램프 · 재시도 판정(일시/영구/취소) · 병합(겹침/무겹침/전체 중복/빈 값)
  - 설정 기본값·클램프·왕복 · 예고 판정 · 리포트 폴더(기본/비서/읽기 전용) · 기본 아이콘
  - 러너: 연결 유실 후 같은 스텝 재시도(1초 실측) · 401 즉시 실패 · 도구 예고 폐기 · 예고 답변 재촉 · 안전망
- 번역 커버리지 테스트 통과(신규 17키).
- Debug/Release `xcodebuild` **BUILD SUCCEEDED**.
- 오프스크린 렌더 `docs/qa/resume-continuity-2026-11-05/` (한/영 8장).

## 6. 실측 대기

- R1 응답 도중 Wi-Fi 끊기 → 5초 × 10회 대기 후 **이어쓰기**, 부분 답변 유지·중복 없음.
- R2 대기 중 **[응답 중지]** → 즉시 멈추고 받은 답변 유지.
- R3 도구 질문이 "확인하겠습니다"로 끝나지 않고 실제 값으로 끝남.
- R4 비서에게 리포트 저장 → 설정된 리포트 폴더에 생성.
- R5 비서 메뉴에서 `비서 없음` ↔ 선택 비서가 분명히 구분됨.
