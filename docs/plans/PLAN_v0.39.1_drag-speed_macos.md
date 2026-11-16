# PLAN v0.39.1 — 창 드래그 복구 · 응답 속도(tok/s) 표시 (macOS)

> 크기: **S(버그 픽스 + 작은 표시 추가)** — 사용자 보고 2건 (2026-11-16)
> ① "제목에 마우스 호버 하고 드래그 하려는데 안 될 때가 더 많아" ② "토큰은 나오는데 초당 몇 토큰 쓰는지 같이 표시해줘"

## 1. 드래그 — 원인과 수정

- **원인 후보(코드 실측)**
  1. 제목 드래그 영역(`TitleDragArea`)이 **글자 프레임과 똑같은 높이(≈16pt)** 였다 — 32pt 타이틀바 띠 안에서 세로로 조준이 어긋나면 빗나간다.
  2. 헤더 배경의 `TitlebarCenterReader`(NSViewRepresentable)가 **기본 hitTest 로 헤더 전체의 mouseDown 을 먹었다** — 제목 밖 여백은 `isMovableByWindowBackground` 로도 움직이지 않았다.
  3. 헤더의 `.contentShape(Rectangle()).onHover` 가 빈 곳의 클릭을 SwiftUI 쪽에서 소비했다.
- **수정**
  - `TitleDragArea`: 세로 패딩으로 **26pt 높이**의 드래그 표면, `acceptsFirstMouse` 로 **비활성 창의 첫 클릭**도 바로 드래그.
  - 헤더 40pt 전체에 `HeaderDragArea`(AppKit `performDrag`)를 깔아 **제목·여백 어디를 잡아도** 창이 움직이게 한다. 버튼은 SwiftUI 가 위에서 먼저 받는다.
  - `TitlebarCenterReader` 는 `hitTest → nil`(측정 전용). 호버는 `hitTest nil` 인 `HeaderHoverArea` 트래킹으로 옮겨 클릭을 막지 않는다.
  - 두 번 클릭 이름 변경은 **창이 이미 키일 때만** — 비활성 창의 첫 클릭이 이름 시트를 열지 않게.

## 2. 응답 속도 — tok/s

- **정의**: 초당 토큰(추정) = `ConversationMemory.estimateTokens(답변)` ÷ 걸린 시간(초).
  - 앱은 실제 토크나이저가 없다. 기존 예산 계산과 같은 **보수적 추정**(한국어 1자≈1토큰, ASCII 4자≈1토큰)을 쓴다. 값은 "비교용 추정치"이며 청구 토큰과 다를 수 있다.
  - 너무 짧은 응답(12토큰 미만)·1초 미만은 표시하지 않는다(숫자가 의미 없음).
- **표시**
  - 헤더 아래 토큰 칩: `🧠 923 / 21k · 4% · 34 tok/s` — 응답 중에는 **실시간**(첫 글자 이후), 끝나면 **마지막 답변 평균**. 툴팁에 추정 기준 명시.
  - 답변 하단: `1일 전 · 2분 29초 · 34 tok/s` — 턴마다 남는 값이라 과거 답변도 비교할 수 있다.
  - 도구 호출·첫 토큰 대기까지 포함한 **전체 시간** 기준이라 에이전트 답변은 낮게 나온다(의도된 값).

## 3. 검증

- `swift test` **1123/1123**(6 skip, `TokenSpeedTests` 신규 4) · 번역 키 커버리지(신규 2) · Debug/Release **BUILD SUCCEEDED · 경고 0**(clean).
- 오프스크린 렌더 `docs/qa/v0.39.1-speed/`: `--demo-plan --demo-toolbar --lang=korean|english` — 칩과 답변 하단에 속도가 함께 그려지는지 확인(한/영).
- 드래그는 합성 이벤트로 OS 라우팅을 재현할 수 없다 — **사용자 실측**: 제목/여백/비활성 창 첫 클릭.
