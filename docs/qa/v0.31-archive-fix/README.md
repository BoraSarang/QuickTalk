# 보관함 복원 · 타이틀바 정렬 — QA (2026-11-05)

> 상태: **구현·검증·병합·배포·실측 완료(2026-11-05 23:53, 사용자 확인: 전부 정상)**
> 계기: 사용자 지적 — *"타이틀과 시스템 버튼과의 정렬이 깨졌는데?"*, *"보관함에 있던 기능들은 다 어디갔어?"*
> 병합: **PR #99 → squash merge `bd0fc99`** · 설치본 SHA-256 `1f95612d…`

## 1. 렌더 (실제 코드, 오프스크린)

| 파일 | 화면 | 크기(pt) |
| --- | --- | --- |
| `archive-ko.png` | 보관함(다크) — 진행 중 · 비서별 그룹 · 변경/삭제 | 400×560 |
| `light/archive-ko.png` | 보관함(라이트) | 400×560 |
| `en/archive-en.png` | 보관함(영어) | 400×560 |
| `search/archive-search-ko.png` | `부산` 검색 결과 | 460×620 |
| `current-delete-ko.png` | 진행 중 대화 행에 **🗑 삭제**(삭제 후 새 대화) | 400×560 |
| `shelf-chats-ko.png` / `light/…` / `en/…` | QuickShelf 대화 탭 — 하단 "보관함 전체 열기" | 300×560 |

```bash
BIN=build-debug/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk
"$BIN" --render=docs/qa/v0.31-archive-fix --lang=korean --theme=dark --demo-archive
"$BIN" --render=docs/qa/v0.31-archive-fix/light --lang=korean --theme=light --demo-archive
"$BIN" --render=docs/qa/v0.31-archive-fix/en --lang=english --theme=dark --demo-archive
"$BIN" --render=docs/qa/v0.31-archive-fix/search --lang=korean --theme=light --demo-archive-search=부산
```

- `--demo-archive`: 비서 2명 + 대화 4개를 **메모리에서만** 넣고 렌더 후 복원한다(저장 없음).
- `--demo-archive-search=부산`: 검색 결과 상태를 재현한다.
- 렌더 모드에서는 `UIStore.isRenderHarness` 로 실제 `history.json` 로드를 막는다 — 개인 대화가 문서에 남지 않는다.

## 2. 실제 창 체크리스트 (재실행 후)

| # | 확인 | 기대 |
| --- | --- | --- |
| A1 | 제목/도구와 신호등(빨강·노랑·초록)의 세로 중심 | 같은 높이 — 4pt 처짐 없음 |
| A2 | 보관함 진입: `⋯` → "보관함 — 검색·삭제" | 창 안 보관함 탭이 열림 |
| A3 | 보관함 상단 검색창 | 제목·본문 검색, 결과 행 선택 시 해당 턴으로 스크롤·강조 |
| A4 | 행의 `변경` / `🗑` | 제목 변경 시트 · 삭제 확인 시트(되돌릴 수 없음 안내) |
| A4-1 | **진행 중** 행의 `🗑` | 확인 후 그 대화를 지우고 **새 대화 화면**으로 이동 |
| A5 | 비서별 그룹 | "기본" 먼저, 그 다음 설정 순서 · 행에 비서 이모지/이름 |
| A6 | 보관함·설정에서 `‹` | 대화 탭으로 복귀 |
| A7 | QuickShelf 대화 탭 하단 | "보관함 전체 열기 — 검색·삭제·이름 변경" → 창 안 보관함 |
| A8 | 메뉴바 `⌘1` · 허브 · pill "보관함" | 모두 창 안 보관함 탭 |
| A9 | 보관함에서 검색어 입력 후 QuickShelf 행 선택 | 그 단어가 나온 턴으로 이동 |

> 신호등은 오프스크린 렌더에 그려지지 않아 **A1 은 실앱에서만 확인 가능**하다.
> `TitlebarCenterReader` 가 창의 `closeButton` 프레임을 읽어 중심을 계산한다(현재 macOS 26: 16pt).

## 3. 구현 메모

- `ContentView.openArchiveTab()` — 창 안 보관함 탭. QuickShelf 오버레이는 닫는다.
- `ContentView.headerRow` — `titlebarCenter`(실측) × 2 높이의 띠에 내용을 가운데 정렬, 바깥 40pt 는 호버·구분선용.
- 보관함 목록은 `List` → `ScrollView`+`LazyVStack` — 오프스크린 렌더에서 List 행이 그려지지 않아 QA 가 불가능했고, custom 디자인과도 맞는다.
- 비대화 탭에서는 대화 전용 도구(🧠·🔖)를 숨긴다.
- `ShelfPanel`/`ShelfView` 의 `onOpenArchive` → `.quickTalkOpenArchive` → `AppDelegate.openPanel(tab: 1)`.
