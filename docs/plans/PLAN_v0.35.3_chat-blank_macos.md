# PLAN v0.35.3 — 긴 대화를 열면 화면이 비던 문제 (macOS)

> 작성 2026-11-09 · 브랜치 `fix/v0.35.3-chat-blank` · 앱 버전 **1.35.3 (build 3503)**
> 관련: DESIGN §14.5 (전환 성능) · HANDOFF 인계 (16)

## 1. 증상

- v0.35.1(LazyVStack) 배포 뒤, **긴 대화를 열면 대화 영역이 통째로 비어 보인다.**
  헤더·기억 칩·입력독은 정상으로 보이고 본문만 없다. 400폭에서 특히 잘 재현됐다.
- 스크롤을 조금 올리면 내용이 나타난다(그 순간 LazyVStack이 주변 행을 실제로 만든다).

## 2. 원인 (실측)

- `LazyVStack`은 **아직 만들지 않은 행의 높이를 추정**한다. 문서 높이가 실제보다 크게 잡히고,
  AppKit으로 문서 끝까지 핀하면 실제 내용이 끝난 **뒤의 빈 꼬리**에 착지한다.
  - 400폭 실측: 문서 높이 추정 **8,233pt** vs 실제 **7,665pt**.
  - 34턴 대화는 추정 **238,590pt**까지 벌어졌다.
- `.defaultScrollAnchor(.bottom)` 도 같은 추정값에 착지해 해결되지 않았다(v0.35.1 기록).
- 반대로 `VStack`은 높이가 정확해 바닥 핀이 어긋나지 않지만, **모든 턴을 한 번에 레이아웃**해
  전환에 3.8초가 걸린다(v0.35.1 이전 측정).

## 3. 결정

1. 본문은 **정확한 높이의 `VStack`** 으로 되돌린다(바닥 핀 정확성 우선).
2. 대신 **최근 턴만 글자 예산만큼 그린다**(윈도잉). Core `ChatWindowing`(순수 계산).
   - 기본 예산 **6,000자**, 최소 2턴(질문+답변)은 항상 표시.
   - 더 오래된 턴은 본문 맨 위 **`이전 대화 N개 더 보기`** 버튼으로 6,000자씩 펼친다.
   - 다른 대화를 열면 예산은 기본값으로 돌아간다(대화별로 기억하지 않음).
3. 목차·검색에서 **윈도 밖 턴**으로 이동하면 그 턴까지 예산을 늘린 뒤 점프한다
   (`revealTurnIfNeeded`) — 그러지 않으면 `scrollTo` 대상이 화면에 없다.
4. 높이가 늦게 확정되는 경우(마크다운·첨부 이미지·폰트)를 대비해, **내용이 바뀐 뒤 첫 핀만**
   뷰포트 픽셀을 검사해 실제 내용이 보이는지 확인하고 높이가 안정될 때까지 다시 맞춘다
   (`ScrollOffsetObserver.needsVerification`). 스트리밍 핀에서는 캡처하지 않는다.

## 4. 구현

| 파일 | 변경 |
|------|------|
| `Sources/QuickTalkCore/ChatWindowing.swift` | 신규 — `startIndex(charCounts:budget:minimumTurns:)` + 기본 예산·단계 상수 |
| `Tests/QuickTalkCoreTests/ChatWindowingTests.swift` | 신규 — 10건(최소 2턴·경계·예산 확대/축소·무제한·오버플로 방지) |
| `QuickTalkApp/ContentView.swift` | `VStack` 복귀 + 윈도잉, `이전 대화 더 보기`, `revealTurnIfNeeded`, 픽셀 검증 핀, `afterMain` 타이머 |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | 신규 `--live-shot=` · `--live-shot-all=`(+`--rapid`·`--top`·`--focus-old`·`--expanded`) |
| `QuickTalkApp/QuickTalkApp.swift` · `SingleInstance.swift` | 새 QA 하네스 등록(단일 인스턴스 예외) |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 한/영 3키 |
| `project.yml` | `xcodegen generate`가 Info.plist 버전을 되돌리는 주의 주석 |

## 5. 검증

- `swift test` **962/962**(6 skip, 신규 10 `ChatWindowingTests`).
- Debug/Release `xcodebuild` **BUILD SUCCEEDED · 경고 0**.
- Release 실측(400×560, 실제 저장 대화 4개):
  - `--live-shot-all` — 전 대화 `dist=0`, `ink>0`(본문이 실제로 그려짐).
  - `--rapid` — 8회 연속 전환 후 마지막 34턴 `dist=0`, `ink=8735`.
  - `--expanded`(모든 턴) — 34턴 문서 38,085pt, `dist=0`, `ink>0`.
  - `--focus-old`(가장 오래된 질문으로 목차 점프) — 문서 7,579→38,085pt로 확장, `offset=0`, `ink>0`.
- 전환 성능(`--switch-perf-live`, Release): 34턴 **cold 896ms / warm 742ms**, 22턴 578/650ms,
  6턴 476/448ms, 4턴 164/250ms. v0.35.1 이전 **3.8초**에서 크게 줄었고, LazyVStack 시절
  (0.33~0.73초)과 비슷한 수준을 **빈 화면 없이** 달성.
- 시각 증거: `docs/qa/v0.35.3-blank/`(수정 전 빈 화면 · 수정 후 `verify/`·`top/`·`expanded/`).

## 6. 한계 (정직)

- 34턴 대화의 마지막 두 턴이 6,682자(큰 표 포함)라 기본 2턴만으로도 레이아웃 ~330ms다.
  한 턴이 예산보다 크면 그 턴은 통째로 그리므로, 행 내부 윈도잉 없이는 더 줄이기 어렵다.
- 윈도잉으로 **오래된 턴은 처음에 그리지 않는다.** 사용자는 버튼으로 펼쳐야 한다.
- QA 오프스크린 캡처에서 머티리얼(도구 카드·시트)이 **흰 블록**으로 나온다 — 캡처 한계이며
  실앱 렌더와 무관하다. `이전 대화 더 보기` 버튼도 이 캡처에서 흰 캡슐로 보인다.
- 실제 트랙패드 체감·버튼 클릭은 오프스크린에서 확정할 수 없어 **사용자 실측**이 필요하다.

## 7. 다음

1. 사용자 실측: 긴 대화 열기(빈 화면 없음) · 위로 스크롤 · `이전 대화 더 보기` · 목차 점프 · 전환 체감.
2. 문제 없으면 PR → squash merge → 로컬 테스트 설치본(Debug) 교체.
3. 후속 후보: 한 턴이 예산보다 클 때 **행 내부 분할 렌더**, 윈도 크기(폭)별 예산 자동 조정.
