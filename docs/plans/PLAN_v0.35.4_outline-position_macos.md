# PLAN v0.35.4 — 대화 목차 현재 위치가 늘 맨 위로 보이던 문제 (macOS)

> 작성 2026-11-09 · 브랜치 `fix/v0.35.4-outline-position` · 앱 버전 **1.35.4 (build 3504)**
> 관련: DESIGN §14.5·§14.7 (윈도잉·목차 위치) · HANDOFF 인계 (17)

## 1. 증상

- v0.35.3(Debug 1.35.3)에서 **대화를 열거나 갈아타면** 오른쪽 목차 레일의 보라색 위치 표시가
  **항상 첫 질문**에 있다. 목차를 펼쳐도 첫 질문이 강조되고, 그 위치로 스크롤한다.
- 스크롤을 내리거나 목차에서 질문을 골라도 표시가 따라오지 않는다(사용자 신고, 2026-11-09).
- v0.35.1(LazyVStack) QA 캡처(`docs/qa/v0.35.1-switch/live-outline-panel-bottom-ko.png`)에서는
  맨 아래에서 5번째 질문이 강조됐다 — v0.35.3 윈도잉 뒤 생긴 회귀.

## 2. 원인 (실측)

`--outline-probe` 하네스로 34턴 대화를 400×560 오프스크린 창에 열어 확인:

```
[OUTLINE] offset=6754 anchor=6762 entries=17 start=32 known=1 [16:62] current=15   ← 열자마자
[OUTLINE] offset=6754 anchor=6762 entries=17 start=32 known=0 []       current=0    ← 곧 사라짐
[PROBE]   after-pin doc=7579 offset=7113 max=7113                                  ← 바닥에 있는데
[OUTLINE] offset=7113 anchor=7121 entries=17 start=32 known=0 []       current=0    ← 표시는 1번
```

1. **측정값을 비운 뒤 다시 오지 않는다.**
   대화 전환·창 폭 변경에서 `outlineOffsets = [:]` 로 전부 비웠다. 그런데 VStack 은 줄바꿈·좌표가
   그대로면 **같은 Preference 값을 다시 올리지 않아** `onPreferenceChange` 가 다시 불리지 않았다.
   → 좌표 0개 → `visibleIndex` 가 0(첫 질문) 반환.
   LazyVStack 시절에는 스크롤할 때마다 행이 새로 만들어져 자동으로 다시 측정됐다.
2. **윈도 밖 질문을 "위쪽에 있다"고 추정했다.**
   창이 마지막 질문(#16)부터 시작하면 기준선(y=8)이 그 질문(y=62)보다 위에 있다. 기존 추정식은
   "바로 위 질문"(#15)을 골랐는데, 그 질문은 **화면에 그려지지도 않았다**.

## 3. 결정

1. **측정값은 비우지 않고 걸러 낸다.**
   - 대화 전환: 현재 대화의 턴 ID 만 남긴다. 새 대화의 측정값이 이미 도착한 뒤 비우는 경쟁도 없어진다.
   - 폭 변경: 지금 그리는(윈도 안) 턴만 남긴다. 줄바꿈이 바뀐 턴은 새 측정값이 덮어쓴다.
2. **`ConversationOutline.visibleIndex` 에 윈도 하한(`minimumPosition`)을 넘긴다.**
   - 그려진 첫 질문보다 앞선 좌표는 보간·추정에서 제외한다.
   - 모든 측정값이 기준선 아래일 때 추정 결과를 `minimumPosition` 아래로 내리지 않는다
     → 창 맨 위에서도 **화면에 보이는 질문**을 가리킨다.
3. 회귀 방지: Core 테스트 2건 + QA 하네스 `--outline-probe`.

## 4. 구현

| 파일 | 변경 |
|------|------|
| `Sources/QuickTalkCore/ConversationOutline.swift` | `visibleIndex(..., minimumPosition:)` — 윈도 하한 필터·추정 클램프 |
| `Tests/QuickTalkCoreTests/ConversationOutlineTests.swift` | 신규 2건 — 창 하한 아래로 추정하지 않음·이전 창 좌표 무시 |
| `QuickTalkApp/ContentView.swift` | `firstRenderedOutlinePosition` 추가 · 대화 전환/폭 변경은 clear 대신 prune |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | 신규 QA 하네스 `--outline-probe` — 열기·중간·위·아래·대화 전환에서 위치 로그 |
| `QuickTalkApp/Info.plist` | 1.35.4 (build 3504) — `scripts/bump-version.sh 35 4` |

## 5. 검증

- `swift test` **964/964**(6 skip, 신규 2).
- Debug/Release `xcodebuild` **BUILD SUCCEEDED · 경고 0**.
- Release `--outline-probe` (실제 34턴 대화, 400×560):
  - 윈도 상태(`start=32`, `floor=16`) — 위·중간·아래 모두 **`current=16`**(마지막 질문).
  - `--expanded`(17질문 전부) — 위 `0` · 중간 `11`(y 18,818 → #11) · 아래 `16`.
  - 22턴 대화로 전환 — `floor=6`, 아래에서 `current=9`(11개 중 10번째, 화면 위쪽 기준).
  - 다시 34턴으로 복귀 — `floor=16`, `current=16`.
- Release `--live-shot-all` — 전 대화 `dist=0`, `ink>0`(빈 화면 회귀 없음).
- 레일 캡처(`docs/qa/v0.35.4-outline/all-3-34t.png`) — 보라 막대가 **마지막 눈금**.

## 6. 한계 (정직)

- 윈도잉 때문에 34턴 대화는 처음에 **마지막 교환만** 그린다. 목차는 그 교환의 질문(#17)을 가리키며,
  `이전 대화 N개 더 보기`로 펼치면 위쪽 질문 좌표가 측정되어 표시가 함께 이동한다.
- "현재 질문"의 정의는 v0.32 그대로 **화면 위쪽에 걸린 질문**이다. 아주 긴 답변의 맨 아래에서는
  직전 질문이 강조될 수 있다(마지막 질문은 화면 중간에 있어도 기준선 아래이기 때문).
- 오프스크린 캡처는 머티리얼을 흰 블록으로 그린다 — 레일 눈금 판정에는 영향 없음.

## 7. 다음

1. ~~사용자 실측~~ — **확인 완료(2026-11-09)**: "잘 되는 것 같음". 대화 열기·갈아타기 후 목차 표시가 실제 읽는 위치를 가리킨다.
2. 문제가 생기면 `fix/v0.35.4-*` → PR.
3. 다음 릴리스는 v0.36 — 실사용 피드백에서 후보 선정. (후속 후보: 바닥에서 마지막 질문 강조 규칙, 목차 패널 현재 행 자동 스크롤 개선.)
