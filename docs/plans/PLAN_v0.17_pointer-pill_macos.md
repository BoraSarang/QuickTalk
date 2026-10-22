# PLAN v0.17 — 포인터 pill (T-21)

> macOS · QuickTalk · 2026-10-21 · 상태: **구현 완료 / 사용자 실측 대기**

## 1. 확정 사항 (사용자)

| 질문 | 확정 |
|---|---|
| pill과 대화 창의 관계 | **별개 기능이 아니다.** 같은 대화 창의 **표현 방식만 다르다** |
| 언제 pill인가 | 설정 › 일반 “단축키로 열 때 유지” 규칙을 **그대로** 따르고, 결과가 **새 대화**일 때만 pill |
| “사용 안 함(0)” | **항상 pill** (2026-10-21 확정) — 빈 대화 창을 띄우지 않는다 |
| 마이크 | **삭제** — pill에는 음성 입력이 없다(대화 창에서 기존 단축키 사용) |
| 보관함 아이콘 | **작은 목록** — 최근 대화 4개, **1클릭으로 이어가기** |
| Enter / Esc | Enter = 전송하며 대화 창으로 / Esc = pill만 닫기(상태·기록 그대로) |

## 2. 표시 규칙 (`ShortcutEntryPresentation.decide`)

| 현재 대화 | ⌘Space 결과 |
|---|---|
| 유지 시간 이내 + 턴 있음 | `.conversation` — 지금 대화 창 그대로(변화 없음) |
| 유지 시간 초과 | `.pill` — 빈 창 없이 포인터 자리 pill |
| 턴 없음(첫 실행·새 대화 직후) | `.pill` |
| 설정 0(사용 안 함) | `.pill` (항상 새 대화이므로) |

- 판단은 **Core**에 있고 `Settings.continuesSession`을 그대로 쓴다. 설정 의미·기본값(10분)·픽커는 **바꾸지 않았다**.
- pill이 떠도 대화 상태를 건드리지 않는다. `store.startShortcutSession()`(만료 시 새 대화 + 기록 저장)은
  **질문을 보낼 때** 비로소 호출한다 → Esc로 닫으면 아무 일도 일어나지 않는다.

## 3. 흐름

```
⌘Space ─┬─ 유지 시간 이내 ──────────────── 대화 창(마지막 대화)
        └─ 그 외 ── pill(포인터 자리)
                     ├ Enter ── 새 대화 + 질문 전송 + 대화 창
                     ├ ⌘Return ─ 대화 창만 열기(입력한 글은 초안으로; 첨부·설정용)
                     ├ Esc / 바깥 클릭 / ⌘Space ─ 닫기
                     └ 보관함 아이콘 ─ 최근 대화 4개(1클릭 이어가기) + 보관함 전체 열기(⌘L)
```

- 대화 창 위치는 기존 설정(중앙/포인터)을 따른다 — pill 위치와 무관.
- pill에서 대화 창으로 넘어갈 때는 **즉시** pill을 내리고 대화 창을 띄운다(겹침 없음).

## 4. UI

- 크기 **380×56**, 모서리 28pt. 오브(30) + 입력 + 보관함 아이콘(32). 마이크 없음.
- 포인터 = 캐럿: 창 왼쪽을 `pointer.x - 55`(패딩 13 + 오브 30 + 간격 12)에 두고 세로는 포인터 중심.
  화면 밖으로 나가지 않게 작업 영역 안으로 밀어 넣는다.
- 보관함 목록은 **같은 창을 아래로 늘여** 표시한다(별도 창 없음 → 포커스·클릭 문제 없음).
  행 34pt, 푸터 32pt, 폭 300, 최대 4행. 목록이 화면 아래로 넘치면 창을 위로 민다.
- 액센트는 DESIGN의 `#7A5CFF`. 바탕은 반투명 솔리드(시스템 머티리얼은 가장자리 1pt 이음새가 보여 사용하지 않음).
- 라이트/다크·한/영 렌더 확인: `docs/qa/t21-pill/`, `docs/qa/t21-pill-light/`.

## 5. 구현 파일

| 파일 | 역할 |
|---|---|
| `Sources/QuickTalkCore/ShortcutEntry.swift` | 표시 판단(순수 함수) |
| `QuickTalkApp/PointerPill.swift` | `PointerPillPanel` · `PointerPillController` · `PillRootView` · `PillTextField` |
| `QuickTalkApp/QuickTalkApp.swift` | `togglePanel(fromShortcut:)` 분기 · `handlePill(_:)` · 컨트롤러 시작 |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | `--demo-pill` 오프스크린 렌더 |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 문구 5키 |

### 입력창
- 단일 행 `NSTextField` + 필드 에디터. 한글 조합 중 Enter는 **조합을 먼저 확정**한 뒤 전송(대화 입력창과 같은 규칙).
- Esc는 `cancelOperation` → 컨트롤러가 닫는다. ⌘Return·⌘L은 패널 `performKeyEquivalent`에서 처리.
- **2026-10-22 변경 — 다중줄**: pill 입력창을 대화 입력창과 **같은 컴포넌트(`ChatInputField`)** 로 바꿨다.
  - **Shift+Enter = 줄바꿈**, Enter = 전송, ⌘Return = 대화 창만, Esc = 닫기(내용 유지)
  - 여러 줄이 되면 pill 이 **위로** 자란다. 왼쪽 오브·오른쪽 보관함 아이콘은 **아래 기준선에 붙어 그대로**(움직이지 않음)
  - 기준선: pill 본체(capsule)의 아래쪽. 입력이 늘어나면 위쪽만 커지고, 보관함 목록은 그대로 아래에 붙는다
  - 1줄일 때의 모양은 이전과 동일(아이콘이 가운데)
  - 최대 4줄(넘으면 입력창 안에서 스크롤)

### 포커스
- 열 때 앱을 활성화하고 `makeFirstResponder(field)`. 창이 붙은 뒤 0.05초에 한 번 더 요청(첫 update에서 window가 nil일 수 있음).
- Esc·⌘Space로 닫으면 **직전 앱으로 포커스를 돌려준다**. 바깥 클릭으로 닫힐 때는 건드리지 않는다.
- 포커스를 잃으면 닫힌다(Spotlight과 같은 동작). 여는 도중 0.25초의 일시적 resign은 무시.

## 6. 검증

- `swift test` **332/332** (6 skip, 신규 6: `ShortcutEntryTests` — 이내/초과/0/턴 없음/활동 없음/경계).
- `xcodebuild` BUILD SUCCEEDED(경고 0).
- 오프스크린 렌더: 빈 pill · 입력 중 · 보관함 목록(한/영·라이트/다크).
  렌더에서 **Capsule `strokeBorder`가 좌우 끝에 1pt 세로 이음새**를 남기는 것을 발견 →
  같은 반지름의 `RoundedRectangle(..., style: .circular)`로 교체해 해결.
- 배포: 2026-10-21 20:43 `~/Applications/QuickTalk.app` 교체, `codesign --verify --strict` OK,
  SHA-256 `ebc78fe9a55fb962467a89928d43d95a3fb91aad1bd895b14cac021f5ab2ca7c`(빌드 산출물과 일치).

## 7. 사용자 실측 (수동)

`docs/qa/t21-pill/CHECKLIST.md` 참고. 핵심 4건:
1. 10분 지난 뒤 ⌘Space → **pill만** 뜨고 빈 대화 창이 뜨지 않는다.
2. 질문 입력 후 Enter → 대화 창이 열리고 **그 질문이 전송**된다(글 남음 없음, 한글 조합 포함).
3. Esc → pill만 사라지고 대화 기록·상태가 그대로다.
4. 보관함 아이콘 → 최근 대화 목록 → 한 번 클릭으로 그 대화가 열린다.

## 8. 한계·후속

- pill에는 파일 첨부가 없다 — **⌘Return**으로 대화 창을 열어 첨부한다.
- 최근 대화 목록은 pill을 열 때의 스냅숏(최대 4개)이다. 열려 있는 동안 갱신되지 않는다.
- 목록에서 ↑/↓ 키 이동은 넣지 않았다(마우스 1클릭 우선).
- 설정에 pill on/off 토글은 두지 않았다 — “단축키로 열 때 유지” 규칙이 유일한 기준.
