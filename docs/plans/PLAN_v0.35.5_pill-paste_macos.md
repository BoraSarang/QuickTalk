# PLAN v0.35.5 — ⌘Space pill 입력창 붙여넣기(⌘V) 수정 (macOS)

> 크기: **S(버그 픽스)** — 사용자 보고 "pill 대화에서는 붙여 넣기가 안되는구나?" (2026-11-11)

1. **원인**: 편집 단축키(⌘C/⌘V/⌘X/⌘A/⌘Z/⌘⇧Z)는 LSUIElement 앱의 메뉴 키 등가가 불안정해 **우리 창이 키일 때만** Carbon 임시 등록 + 로컬 키 모니터로 처리한다. 그 판정 `isOwnWindow` 화이트리스트에 **포인터 pill 패널이 빠져** 있어, pill 이 key 가 되면 `syncEditShortcuts` 가 등록을 해제하고 모니터도 이벤트를 넘기지 않았다.
2. **수정**: `PointerPillController.pillWindow` 를 노출하고 `isOwnWindow` 에 포함 — pill 이 key 일 때 대화 창과 같은 경로로 ⌘V/⌘C/⌘A/⌘Z 가 동작한다. `PillRootView` 는 `ChatInputField` 를 그대로 쓰므로 입력창 쪽 추가 수정은 없다.
3. **검증**: `swift test` 964/964(6 skip) · Debug/Release BUILD SUCCEEDED · 경고 0 · **실키 ⌘V 는 사용자 확인 필요**(합성 이벤트는 OS 라우팅이 달라 재현 불가 — PLAN_v0.10 §13 과 같은 한계).
