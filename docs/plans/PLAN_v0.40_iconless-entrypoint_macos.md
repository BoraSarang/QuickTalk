# PLAN v0.40 — 아이콘 없이 상주 · 재실행 진입점 복구 (macOS)

> 상태: **구현·검증(오프스크린) 완료 · 사용자 실측 대기** (2026-11-19)
> 크기: **M(표시 정책 변경 + 앱 수명주기)** — 사용자 요청 2026-11-19
> "메뉴바에 아이콘이 너무 많아서 줄여 볼라고" · "앱을 실행(.app)하면 그때 메뉴바나 Dock이 보이면 될 것 같은데"
> 지원 언어: **ko + en** (`L10n.table`)

## 1. 목표

- 메뉴바·Dock 아이콘을 **둘 다 끌 수 있게** 한다(현재는 "진입점 최소 1개" 정책이 강제로 되돌린다).
- 아이콘이 0개여도 **전역 단축키는 그대로** 동작한다(이미 Carbon 핫키라 아이콘과 무관).
- 아이콘이 0개일 때 **앱을 다시 열면** 메뉴바 아이콘(이번 실행 한정)과 설정 창이 열린다 — PopClip과 같은 복구 계약.
- 로그인 자동 시작에서는 아이콘·창이 **저절로 뜨지 않는다**.

## 2. 조사

### 2.1 PopClip
- 공식 문서: "Show in menu bar를 끄면 메뉴바 아이콘이 숨겨진다. 설정을 다시 열려면 **앱이 실행 중일 때 Applications 폴더에서 PopClip을 더블클릭**한다."
- 2025.9 릴리스: "Finder·Spotlight 등에서 다시 실행하면 언제든 설정 창이 열린다. 메뉴바의 모든 기능을 설정 창에 복제해 아이콘을 영구히 숨겨도 된다."
- 구버전: "재실행하면 메뉴바에 **일시적으로** 다시 나타난다."
- 즉 "재실행 = 진입점 복구"가 실제로 쓰이는 패턴이다.

### 2.2 macOS
- `LSUIElement=true`는 Dock을 숨긴다. `.accessory` ↔ `.regular` 전환으로 런타임에 Dock을 켜고 끌 수 있다.
- 전역 단축키는 Carbon `RegisterEventHotKey`라 상태 아이템·Dock과 무관하다.
- 실행 중인 앱을 다시 열면 LaunchServices가 `applicationShouldHandleReopen`을 보내거나, 새 프로세스가 뜨는 경우 `SingleInstance` 분산 알림으로 기존 인스턴스가 깨어난다 — **두 경로 모두** 처리해야 한다.
- 로그인 항목 실행은 `kAEOpenApplication` Apple Event의 `keyAELaunchedAsLogInItem`으로 구분한다. `currentAppleEvent`를 읽을 수 없는 환경이 있어 **판별 실패 시 조용히 시작**을 기본값으로 둔다.

### 2.3 QuickTalk 현재
- `LSUIElement=true`, 기본 메뉴바 ON / Dock OFF.
- `setMenuBarIcon(false)` → Dock 자동 ON, `setDockIcon(false)` → 메뉴바 자동 ON(`Settings.swift`).
- `normalizeVisibility()`가 저장값이 둘 다 꺼짐이면 Dock을 켠다(`UIStore` 로드).
- `applyVisibility`가 둘 다 꺼짐이면 메뉴바를 다시 만든다(`E-MAC-RENDER-0001`).
- 재실행 경로(`applicationShouldHandleReopen`·분산 알림)는 지금 **대화 창만** 연다.
- 시작 시 `setupStatusItem()`을 무조건 호출한 뒤 설정을 적용해, 숨김 설정이면 아이콘이 순간 깜빡일 수 있다.

## 3. 동작 사양

| 메뉴바 | Dock | .app 재실행(실행 중/꺼짐) | 로그인 자동 시작 |
|---|---|---|---|
| ON | OFF/ON | 대화 창 (현행) | 아이콘만 |
| OFF | ON | 대화 창 (Dock이 진입점) | Dock만 |
| **OFF** | **OFF** | **메뉴바 아이콘(이번 실행 한정) + 설정 창** | **아무것도 띄우지 않음** |

- 복구는 **진입점이 0개일 때만** 발동한다. 메뉴바만 숨긴 사용자의 Dock 클릭은 지금처럼 대화 창을 연다.
- 임시 메뉴바 아이콘은 **이번 실행 동안** 유지된다(종료하면 사라짐). 설정에서 다시 켜면 영구 반영, 다시 끄면 임시 아이콘도 내려간다.
- 임시 아이콘 우클릭 메뉴에 **[메뉴바 아이콘 숨기기]** 를 추가해 바로 되돌릴 수 있다.
- 설정 › 일반에 경고 카드와 **[지금 메뉴바 아이콘 표시]** 버튼.

## 4. 설계

### 4.1 설정 정책 (Core)
- `setMenuBarIcon` / `setDockIcon`: 상호 자동 보정 **제거**.
- `normalizeVisibility()` 제거, `UIStore` 로드 보정 제거.
- `hasNoEntryPoint` 추가: `!showMenuBarIcon && !showDockIcon`.
- 기존 저장값은 그대로 둔다(마이그레이션 없음). 이전에 둘 다 꺼도 Dock이 켜져 저장됐다면 지금도 Dock ON이다.

### 4.2 세션 한정 아이콘 (AppDelegate)
- `sessionMenuBarIcon: Bool` — 저장하지 않는다.
- `applyVisibility`: `showMenuBarIcon || sessionMenuBarIcon`이면 상태 아이템 생성, 아니면 제거. 둘 다 꺼짐 WARN 제거.
- 사용자가 설정에서 메뉴바를 직접 끄면(직전 저장값 true → false) `sessionMenuBarIcon = false`.
- 앱 시작 시 상태 아이템을 **조건부** 생성해 깜빡임을 없앤다.

### 4.3 재실행 복구
- `handleUserReopen()` 하나로 통합:
  - `hasNoEntryPoint == false` → `openPanel(tab: 0)` (현행)
  - `hasNoEntryPoint == true` → `sessionMenuBarIcon = true` → `applyVisibility` → `openSettings()`
- 호출 지점: `applicationShouldHandleReopen`, `SingleInstance.activateNotification` 옵저버.
- 콜드 런치: `applicationDidFinishLaunching`에서 사용자 실행이면 같은 복구를 수행(설정 창 열기). QA 하네스(`isHeadlessHarness`)는 제외.
- 로그인 판별: `detectedLoginItemLaunch()`. `currentAppleEvent == nil`이면 로그인 실행으로 간주(조용히 시작). 이 경우 콜드 런치 복구는 안 되지만 재실행하면 복구된다.

### 4.4 UI / i18n
- 설정 › 일반 토글 설명 갱신, 경고 카드 + [지금 메뉴바 아이콘 표시].
- 도움말 카드: "둘 다 꺼도 됩니다."
- 상태 아이템 우클릭: [메뉴바 아이콘 숨기기] (임시 아이콘일 때만).
- 새 문구는 `L10n.table`에 en 번역 추가(키 누락 테스트가 강제).

## 5. 변경 파일

- `Sources/QuickTalkCore/Settings.swift` — 정책·`hasNoEntryPoint`
- `QuickTalkApp/UIStore.swift` — 로드 보정 제거, `visibilityHint`, 세션 표시 요청
- `QuickTalkApp/QuickTalkApp.swift` — 세션 아이콘, `handleUserReopen`, 로그인 판별, 조건부 상태 아이템, 메뉴 항목
- `QuickTalkApp/SettingsView+General.swift` — 토글 설명·경고 카드·버튼
- `QuickTalkApp/SettingsView.swift` — 도움말 카드
- `Sources/QuickTalkCore/LocalizationTable.swift` — en 문구
- `Tests/QuickTalkCoreTests/VisibilityPolicyTests.swift` — 새 계약으로 교체
- `docs/TODO.md`, `docs/CHANGELOG.md`, `docs/HANDOFF.md`, `docs/DESIGN.md`(표시 정책 절)
- 버전: `1.40.0`(build 4000), `scripts/bump-version.sh 40 0`

## 6. 위험 · 엣지

- **로그인 판별 실패** → 조용히 시작(폴백). 콜드 런치 복구는 재실행 1회로 대체.
- **메뉴바 관리 앱**(Bartender·Ice)이 아이콘을 화면 밖으로 옮기면 아이콘은 있어도 안 보인다. 설정 창은 정상적으로 열린다.
- **단축키 충돌**로 등록이 실패하면 아이콘 0개 상태에서는 알림이 없다 — 설정 창의 단축키 경고(⚠️)로 확인.
- 아이콘 0개 + 앱 종료 → 다음 실행 전까지 단축키만 남는다(의도).
- `LSMultipleInstancesProhibited` 때문에 재실행이 새 프로세스를 띄우지 않을 수 있다 — reopen/분산 알림 두 경로를 모두 처리한다.
- QA 하네스·`--render` 실행은 복구 동작을 하지 않는다.

## 7. 검증

- 단위: `VisibilityPolicyTests` 7 — 독립 토글·둘 다 끔·저장/복원·시작 복구 조건(사용자 실행/로그인/QA 하네스).
- 전체: `swift test` **1126/1126**(6 skip), `LocalizationCoverageTests` 통과(신규 9키).
- 빌드: Debug/Release clean `BUILD SUCCEEDED · 경고 0`.
- 수동(사용자): ① 둘 다 끔 → 메뉴바·Dock 사라짐 ② 단축키 동작 ③ .app 재실행 → 아이콘+설정 창 ④ 설정에서 다시 끔 → 아이콘 사라짐 ⑤ 로그인 자동 시작 → 아무것도 안 뜸 ⑥ 메뉴바만 끄고 Dock 클릭 → 대화 창.

## 8. 롤백

- 기능 커밋 revert 후 1.39.1 재빌드. 설정 스키마 변경 없음(키 추가/삭제 없음) — 롤백 시 둘 다 꺼진 값은 구버전이 Dock을 켜서 복구한다.

## 9. 완료 기준

- [x] 둘 다 꺼진 설정이 저장·복원된다
- [x] 재실행 복구(아이콘+설정) 두 경로 모두 — 코드 경로 통합, 실기 확인 대기
- [x] 로그인 실행은 조용히 — Apple Event 판별, 실기 확인 대기
- [x] 설정 UI·i18n·테스트·빌드 통과
- [x] 문서(TODO·CHANGELOG·HANDOFF·DESIGN) 갱신
- [ ] 사용자 실측 6항목(§7) — 설치 후 확인
