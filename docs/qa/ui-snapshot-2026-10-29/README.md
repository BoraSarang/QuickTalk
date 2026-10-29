# 컴퓨터 제어 Phase 1 — 화면 요소 읽기 (2026-10-29)

## 무엇을 바꿨나

`PLAN_v0.25`의 Phase 1. 에이전트가 **다른 앱 창의 접근성 요소를 읽기만** 한다.
클릭·입력·스크롤·포커스 이동은 하지 않는다(Phase 2에서 별도 게이트와 함께 넣는다).

- **도구** `ui_snapshot` — 앱 이름(또는 번들 ID)을 받아 창 1개의 요소 목록을 돌려준다.
  생략하면 QuickTalk를 제외한 **맨 앞 앱**을 읽는다. 참조(`r1`, `r2`, …)는 그 스냅샷 안에서만 유효하다.
- **순수 계산** `Sources/QuickTalkCore/UiSnapshot.swift` · `UiElementPath.swift`
  — 이름 없는 컨테이너를 평탄화하고, 같은 이름 형제는 순번으로 구분하며,
  노드 400 · 깊이 12 · 이름 120자 상한에서 **조용히 자르지 않고** `truncated`로 알린다.
- **AX 접근** `QuickTalkApp/AccessibilityService.swift` — 메인 스레드 밖에서 창 1개만,
  메시징 타임아웃 1.5초 · 전체 6초 예산. `AXManualAccessibility` **읽기 힌트**만 켠다.
- **공통 헬퍼** `QuickTalkApp/AXAccess.swift` — `AXWindowReader`(창 연결)와 같은 AX 규칙을 한 곳에 모았다.
- **권한** 없으면 `noPermission` + **허용 방법**을 돌려준다(`screenshot`과 같은 방식).
- **비밀번호 필드**는 `secure`로만 표시하고 **값은 절대 싣지 않는다**(`hasValue = false`).
- **게이트** 설정 `uiControlEnabled`(기본 **꺼짐**) — 꺼져 있으면 `ui_snapshot`이 도구 목록에 **없다**.
  켜져 있어도 읽기 단계 정책(`읽기: 매번 확인`)을 그대로 따른다.
- **설정** › 도구·권한 › `컴퓨터 제어` 그룹 + `시스템 권한` 손쉬운 사용 캡션 갱신.
- **감사** `ui_snapshot [앱]` 1줄. 출력 본문은 남기지 않는다.

## 렌더 명령

```sh
APP=~/Library/Developer/Xcode/DerivedData/QuickTalk-*/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk

# 한국어 — 마스터 토글 꺼짐 / 켜짐
"$APP" --render=... --settings-tab=tools --render-height=2200
"$APP" --render=... --settings-tab=tools --render-height=2200 --demo-ui-control

# 영어 — 캡션이 길어져도 잘리지 않는지
"$APP" --render=... --settings-tab=tools --render-height=2200 --lang=english
"$APP" --render=... --settings-tab=tools --render-height=2200 --demo-ui-control --lang=english
```

## 파일

| 파일 | 상태 |
|---|---|
| `settings-ui-control-off-ko.png` | `컴퓨터 제어` 그룹 · `화면 요소 읽기 허용` **꺼짐** · 캡션 잘림 없음 |
| `settings-ui-control-on-ko.png` | 같은 그룹 **켜짐** · `시스템 권한` 손쉬운 사용 캡션에 컴퓨터 제어 반영 |
| `settings-ui-control-off-en.png` | `Computer control` · `Allow reading screen elements` **꺼짐** |
| `settings-ui-control-on-en.png` | 같은 그룹 **켜짐** · 영어 캡션 4줄 잘림 없음 |

## 자동 검증

```sh
swift test --filter UiSnapshotTests        # 16건
swift test --filter AgentTests.testUiSnapshotToolIsOptIn
```

- `UiSnapshotTests` — 평탄화 · 순번 경로 · 비밀번호 값 비노출 · 노드/깊이/이름 상한 · 빈 결과 설명 · 카드 제목.
- `AgentTests.testUiSnapshotToolIsOptIn` — 기본 5개에 없음 · `includingUI`일 때만 6번째 · 읽기 단계.
- 전체 `swift test` — **576건 통과(6 skip)**.
- Debug/Release `xcodebuild` — **BUILD SUCCEEDED** (Debug 경고 0).

### 되돌려 실패 확인

| 되돌린 곳 | 실패 |
|---|---|
| 비밀번호 필드 `hasValue` 그대로 노출 | 2건 (`testSecureFieldNeverReportsValue`) |
| 이름 없는 컨테이너도 목록에 포함 | 2건 (`testUnnamedContainersAreFlattened`, `testInteractiveRoleWithoutNameIsKept`) |
| 평탄화된 형제의 순번표를 따로 셈 | 1건 (`testFlattenedContainerKeepsSiblingIndexUnique`) |
| `available`이 `includingUI`를 무시 | 3건 (`testUiSnapshotToolIsOptIn`) |
| `ui_snapshot` 권한 단계를 실행으로 변경 | 1건 (`testUiSnapshotToolIsOptIn`) |

복구 후 전부 통과.

## 실측 대기 (사용자, 앱 재실행 후)

| # | 항목 | 기대 |
|---|---|---|
| U1 | 설정 › 도구·권한 › 컴퓨터 제어 **꺼짐** → "지금 앞 앱에 어떤 버튼이 있어?" | 모델이 `ui_snapshot`을 받지 못한다(도구 목록에 없음) |
| U2 | **켜짐** → 같은 질문 | 요소 목록(역할·이름·center)을 읽어 설명 · 카드에 `화면 요소 — …` |
| U3 | 손쉬운 사용 권한 없이 실행 | "권한이 없어 … 허용한 뒤 앱을 다시 실행하세요" + 아무것도 읽지 않음 |
| U4 | 비밀번호 입력란이 있는 창 | `secure`만 표시되고 값은 보이지 않음 |
| U5 | 읽기 정책 `매번 확인` | 승인 카드가 먼저 뜨고, 거부하면 아무것도 읽지 않음 |

Phase 1은 **화면을 바꾸지 않는다** — 클릭·입력·스크롤·포커스 이동이 없으므로 되돌리기가 필요 없다.
