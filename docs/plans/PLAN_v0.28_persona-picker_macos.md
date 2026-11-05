# PLAN v0.28 — 비서 선택 상시 노출 · 아이콘 목록 선택 (macOS)

> 작성 2026-11-05 KST · 상태 **구현 완료**(실측 대기)
> 지원 언어: 한국어·영어 (`Sources/QuickTalkCore/LocalizationTable.swift`, 기존 `L()` 경로)
> 관련: `PLAN_v0.26_assistant-persona_macos.md` (비서·헤더 칩), `PLAN_v0.27_schedule-v2_macos.md`

## 1. 계기 (사용자 실측)

- 새 대화를 시작할 때 **비서를 고를 곳이 헤더 칩 하나뿐**이라, 입력 전에는 선택 UI가 눈에 띄지 않는다.
  (첨부 화면처럼 입력독 왼쪽에 현재 비서 아이콘이 있고, 누르면 목록이 열리길 원함)
- 설정 › 비서 편집의 **아이콘 칸이 빈 텍스트필드**라 무엇을 넣어야 하는지 알 수 없다.
  "심볼을 입력하라"는 인상을 준다 → **10~20개 아이콘을 나열하고 클릭해서 고르게** 한다.

## 2. 목표

1. **입력독 왼쪽에 비서 버튼** — 비서가 1명 이상일 때 항상 보이고, 새 대화(첫 턴 전)에서도 바로 선택할 수 있다.
   - 헤더 칩과 **같은 메뉴**를 공유한다(목록 맨 위 `기본(비서 없음)`, 아래 `할일`).
   - 현재 비서 이모지를 원형 버튼으로 표시. 선택하지 않았으면 🗣 + 옅은 보라.
2. **아이콘 그리드** — 편집 시트의 텍스트필드를 20개 프리셋 그리드로 교체.
   - 선택된 칸은 보라 테두리 + 옅은 배경. 기존에 목록에 없는 이모지를 쓰던 비서는 첫 칸에 그 이모지를 추가로 보여 준다.
   - 저장 형식은 기존 `Persona.emoji: String?` 그대로 — 마이그레이션 없음.

## 3. 비목표

- SF Symbol 이름을 저장하는 새 필드 — 기존 이모지 표시(채팅·목록·알림)를 그대로 쓴다.
- 비서가 0명일 때의 UI 변경 — 지금과 완전히 동일해야 한다.
- `/이름` 호출(Phase 2) — 이번 범위 아님.

## 4. 구현

| 위치 | 변경 |
|---|---|
| `Sources/QuickTalkCore/Persona.swift` | `Persona.iconChoices` — 20개 이모지 프리셋(순수 상수) |
| `QuickTalkApp/PersonaChip.swift` | 메뉴 내용을 `PersonaMenuItems` 로 추출 → 헤더 칩·입력독 버튼이 공유. `PersonaDockButton` 추가 |
| `QuickTalkApp/ContentView.swift` | `dockRow` 왼쪽 아래에 `PersonaDockButton`, 입력 인셋을 버튼 폭만큼 확보(비서가 있을 때만) |
| `QuickTalkApp/SettingsView+Assistant.swift` | 아이콘 `TextField` → `PersonaIconGrid` (LazyVGrid, 20칸) |
| `Tests/QuickTalkCoreTests/PersonaTests.swift` | 프리셋 개수·중복 없음·단일 문자 검증 |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | `--demo-persona-chat`(빈 대화 + 비서), `--demo-persona-editor`(아이콘 그리드) 렌더 |

### 레이아웃 주의

- 입력독은 `ZStack(alignment: .bottomTrailing)` 이다. 비서 버튼은 `.bottomLeading` 에 두고,
  입력 영역의 `leading` 여백을 `14 + 34` 로 늘려 글자와 겹치지 않게 한다.
- 버튼 높이 26, 아래 9 → 한 줄 입력(44pt)에서 글자 줄과 세로 중심이 맞는다.
- 비서가 없으면 여백·버튼 모두 기존과 동일(`14`).

## 5. 검증

- `swift test` (기존 813 + 신규 ≥3) · Debug/Release `xcodebuild`.
- 번역 커버리지 테스트 — 새 문구는 기존 키 재사용, 필요 시 en/ko 동시 추가.
- 오프스크린 렌더: 빈 대화(한/영) · 편집 시트 아이콘 그리드(한/영).
- 실측(사용자): ① 새 대화에서 입력독 왼쪽 아이콘 → 비서 선택 → 첫 질문의 답변에 그 비서 표시
  ② 설정 › 비서 편집에서 아이콘 20개 중 선택 → 목록·칩에 즉시 반영 ③ 비서 0명이면 버튼이 없고 기존과 동일.

## 6. 추가 수정 — 실제 대화의 겹침·스크롤 (2026-11-05, 같은 브랜치)

> 계기: 사용자가 `테크충이 얼마나 똑똑 한가`(20턴) 대화가 **겹치고 스크롤이 안 된다**고 보고.
> 조사·측정·수정 기록은 `docs/qa/chat-scroll-2026-11-05/README.md`.

| 원인 | 수정 |
|---|---|
| 도구 카드의 긴 명령 `Text` + `.fixedSize(vertical:)` → 레이아웃 높이와 실제 그리기 높이 불일치(겹침) | `fixedSize` 제거 + 턴 내용 열이 남는 폭을 정확히 차지 |
| `.defaultScrollAnchor(.bottom)` 이 **크기 변화마다** 바닥으로 재고정(읽던 위치 낭치) | 제거. 실제 `NSScrollView` 오프셋을 보고 **위로 움직이면 자동 따라가기 중단**, 바닥에서 재개 |
| 도구 출력 상자가 항상 150pt(짧아도 빈 상자) + 안쪽 스크롤이 휠을 먹음 | 안쪽 스크롤 제거, **8줄 + `전체 보기 · N자`** |
| 복원 직후 문서 높이 0에서 핀 → 맨 위에 남음 | 핀 재시도 + 높이 확정까지 정착 타이머(0.15s × 최대 4s), 사용자가 올리면 즉시 중단 |

검증(오프스크린): 20턴 실데이터 5개 위치 스캔 **겹침 0** · 위로 올린 채 120줄 추가해도 `19,479 → 19,881`(낭치 없음) · `맨 아래로` `distance=0` · 첫 열기 `distance=0` · `swift test` **814/814**(6 skip) · Debug/Release BUILD SUCCEEDED.
렌더: `docs/qa/chat-scroll-2026-11-05/`(한/영 5장씩), 비서 UI `docs/qa/persona-picker-2026-11-05/`(한/영).
