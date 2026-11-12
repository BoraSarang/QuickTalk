# PLAN v0.38.3 — 격리 브라우저 보이는 창 · 주소창 (macOS)

> 상태: **착수** · 2026-11-13 · 크기: **M**
> 앞 문서: `PLAN_v0.38.1_browser_macos.md` (격리 브라우저) · `PLAN_v0.38.2_artifacts_macos.md` (산출물 카드)
> 원칙: **새 브라우저 엔진을 만들지 않는다.** v0.38.1의 `BrowserService`·URL 정책·승인·감사·출처 카드를 그대로 쓰고, 창과 크롬만 더한다.

---

## 1. 목표 (1줄)

모델이 격리 브라우저로 페이지를 열면 **무슨 페이지를 읽고 있는지 눈으로 볼 수 있게** 하고, 사용자가 같은 창에서 **주소·뒤로·앞으로·새로고침**을 직접 조작할 수 있게 한다.

## 2. 이번 버전이 아닌 것

- **Safari 대체 브라우저** — 격리 프로필 하나를 보여 주는 창이다. 탭·북마크·확장·다운로드·인쇄는 없다.
- **모델의 승인 없는 상태 변경** — 클릭·입력·제출의 승인 규칙은 v0.38.1 그대로다. 보이는 창은 승인 카드를 대체하지 않는다.
- **원격 승인** — v0.39+.
- **주소창에서 로컬·사설 주소 열기** — URL 정책(`BrowserURLPolicy`)을 그대로 적용한다.
- **여러 페이지 탭** — 대화별 브라우저 1개(페이지 1개)다.

## 3. 경험

> "이사 업체 견적들 비교해 줘."
> → 모델이 `browser_open`을 호출하면 **격리 브라우저 창이 뒤에 나타난다**(포커스는 빼앗지 않는다).
> → 주소창에 실제 주소가 보이고, 오른쪽에 **격리 프로필** 배지가 있다.
> → 모델이 읽는 동안 **"모델이 페이지를 읽는 중"** 표시가 돈다.
> → 사용자는 같은 창에서 뒤로·앞으로·새로고침을 누르거나 주소를 직접 입력할 수 있다.
> → 창을 닫아도 페이지는 남아 있고, 모델은 계속 읽는다. 15분 유휴 뒤 정리된다.

## 4. 화면

```
┌──────────────────────────────────────────────────────────────┐
│ ● ● ●   example.com — 격리 브라우저                          │  ← 표준 타이틀바
├──────────────────────────────────────────────────────────────┤
│ ‹  ›  ↻  │ https://example.com/quote        │ 🛡 격리 프로필 │ ● 모델이 읽는 중 │
├──────────────────────────────────────────────────────────────┤
│ (페이지)                                                      │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

- **타이틀바**: 페이지 제목(없으면 호스트) — `격리 브라우저`. 표준 macOS 창(이동·최소화·확대·닫기).
- **툴바**: 뒤로(⌘[) · 앞으로(⌘]) · 새로고침/중지(⌘R) · 주소창(Enter로 이동) · 격리 배지 · 모델 활동.
- **격리 배지**: `lock.shield.fill` + "격리 프로필". 툴팁으로 "Safari와 쿠키·캐시를 공유하지 않습니다."
- **모델 활동**: 모델이 도구를 실행하는 동안 작은 스피너 + "모델이 페이지를 여는/읽는/클릭하는/입력하는/제출하는 중". 끝나면 사라진다.
- **빈 상태**: 주소창은 활성. 가운데에 "아직 페이지가 없습니다 — 모델이 페이지를 열면 여기에 표시됩니다. 주소를 직접 입력해도 됩니다."
- **안내 띠**: 다운로드·새 창·로컬 주소 차단, 로딩 실패를 툴바 아래 한 줄로 보여 준다. [×]로 닫는다.
- **진행 표시**: 페이지 로딩 중이면 툴바 아래 2pt 선.

## 5. 동작

### 5.1 창 열기

| 진입점 | 동작 |
|---|---|
| 설정 › 도구·권한 › 격리 브라우저 › **[브라우저 창 열기]** | 현재 대화의 브라우저를 앞으로 가져온다(앱 활성화). 페이지가 없으면 빈 상태. |
| 메뉴바 Hub › 실행 탭 › **격리 브라우저** | 위와 같다. 브라우저가 꺼져 있으면 행을 숨긴다. |
| 모델의 첫 `browser_*` 호출 | 설정 **모델이 페이지를 열면 창 표시**(기본 켜짐)일 때 창을 **활성화 없이** 뒤에 띄운다. |

- 창은 **대화별**로 하나. 대화 A와 B의 페이지는 섞이지 않는다.
- 창을 닫으면 `orderOut`만 하고 페이지는 유지한다. 다음에 열면 같은 페이지가 보인다.
- 창 위치·크기는 `setFrameAutosaveName("QuickTalkBrowserWindow")`로 기억한다.

### 5.2 주소·이동

- 주소창 Enter: `BrowserURLPolicy.validate` → 차단이면 툴바 아래 이유를 보여 주고 기존 페이지를 유지한다.
- 뒤로·앞으로·새로고침은 사용자 직접 조작 — 모델 승인과 무관하다.
- 주소창은 페이지 이동·모델 도구 실행 때 자동 갱신된다. 사용자가 편집 중이면 덮어쓰지 않는다.
- 사용자가 링크를 눌러 이동하는 것도 허용한다(정책에 걸리면 차단 안내).
- `http/https`·공인 호스트만. `localhost`·사설 IP·`.local`·자격 증명 포함 주소는 거부.

### 5.3 모델 활동

- `AgentExecutor+Browser`는 승인 직후 작업을 시작할 때 `service.beginModelActivity(tool)` / `defer endModelActivity()`를 부른다.
- 활동 중에는 창이 자동으로 열려 있지 않으면 연다(자동 표시가 켜진 경우).
- 활동은 **승인 대기 시간을 포함하지 않는다** — 승인 카드에서 거부하면 창도 활동 표시도 남지 않는다.
- 활동 라벨은 도구 이름으로 정한다. 여러 작업이 겹치면 깊이 카운터로 마지막 하나가 끝날 때까지 유지한다.

## 6. 안전·개인정보

| 항목 | 결정 |
|---|---|
| 프로필 | v0.38.1 그대로 `WKWebsiteDataStore(forIdentifier: settings.browserProfileID)`. Safari와 쿠키·캐시 분리. |
| URL | `BrowserURLPolicy` 그대로. 주소창·링크·리다이렉트 모두 같은 정책. |
| 승인 | 클릭(링크 제외)·입력·제출은 항상 승인. 보이는 창은 승인을 우회하지 않는다. |
| 민감 필드 | 스냅샷 제외·입력 거부 그대로. |
| 다운로드·팝업·파일·미디어 | 차단하고 안내 띠로 알린다. |
| 포커스 | 자동 표시는 `orderFrontRegardless` — 앱을 활성화하거나 키보드 포커스를 빼앗지 않는다. 사용자가 직접 열 때만 활성화. |
| 감사 | `browser_*` 감사·출처 카드는 그대로. 창 조작은 감사 대상이 아니다(사용자 직접 행동). |

## 7. 설정

`QuickTalkSettings`에 추가:

```swift
/// 모델이 브라우저 도구를 쓸 때 보이는 창을 자동으로 띄울지(v0.38.3). 기본 켜짐.
public var browserShowWindowAutomatically: Bool = true
```

- Codable 키 추가. 구버전 JSON(키 없음)은 **켜짐**으로 읽는다.
- 설정 › 도구·권한 › 격리 브라우저에 토글 + [브라우저 창 열기] 버튼.
- 토글 설명: "모델이 브라우저 도구를 쓸 때 격리 브라우저 창을 자동으로 띄웁니다. 창은 포커스를 빼앗지 않고 뒤에 나타납니다."

## 8. 구현

### 8.1 새 파일 `QuickTalkApp/BrowserWindow.swift`

- `BrowserChromeState` — 주소·제목·호스트·뒤로/앞으로·로딩·빈 상태·안내·활동 라벨·진행률.
- `BrowserWindowModel: ObservableObject` — 서비스 약한 참조, `@Published` 상태, 주소 편집·이동·뒤로·앞으로·새로고침 액션.
- `BrowserWindowView` — SwiftUI 크롬. `BrowserWebViewHost`(NSViewRepresentable)가 `WKWebView`를 창에 붙인다.
- `BrowserWindowController: NSWindowController, NSWindowDelegate` — 표준 타이틀바 창, 프레임 autosave, 닫기 = 숨김.
- 창 ↔ 서비스는 **약한 참조**로 연결해 순환 보유를 만들지 않는다.

### 8.2 `BrowserService` 확장

- `webViewForWindow`(읽기 전용 노출) · `chromeState` · `autoShowWindowEnabled` · `isWindowVisible`.
- `showWindow(activate:qaOffscreen:)` · `hideWindow()` · `clearNotice()` · `beginModelActivity/endModelActivity`.
- `navigateUser(to:) -> String?` — 사용자 주소 이동. 정책 위반은 이유 문자열.
- `userGoBack/userGoForward/userReloadOrStop`.
- KVO(`url`·`title`·`canGoBack`·`canGoForward`·`isLoading`·`estimatedProgress`)로 크롬 상태를 갱신.
- 보이는 창을 닫으면 `WKWebView`를 **오프스크린 창으로 되돌린다** — 창이 숨겨져도 모델의 읽기·클릭이 안정적으로 동작하게.
- `teardown()`은 보이는 창을 닫고 웹뷰·델리게이트·관측을 모두 정리한다.
- 기존 `notice`(스냅샷 1회성)와 별도로 `userNotice`(창 안내 띠)를 둔다.

### 8.3 `AgentExecutor+Browser`

- 6개 도구 실행부에서 승인 직후 `beginModelActivity`/`defer endModelActivity`.
- 승인 전·검증 실패 시에는 활동을 시작하지 않는다.

### 8.4 `UIStore+Browser`

- `browserService(for:)`가 서비스의 `autoShowWindowEnabled`를 설정에서 갱신.
- `openBrowserWindow() -> Bool` — 설정·도구 게이트 확인 후 현재 대화의 창을 연다.

### 8.5 진입점

- `SettingsView+Tools`: 토글·버튼·캡션.
- `MenuBarHubView` + `HubMenuAction.openBrowser` + `AppDelegate.hubAction`.
- `AppDelegate`: 브라우저가 꺼져 있으면 로그만 남기고 열지 않는다(Hub 행 자체를 숨김).

## 9. QA

### 9.1 단위 테스트(`swift test`)

- `browserShowWindowAutomatically` 기본 **true**.
- 설정 왕복(켜짐/꺼짐).
- 구버전 JSON(키 없음) → true.
- 기존 BrowserTests 18건 유지.

### 9.2 헤드리스 QA `--qa-browser-window`

실제 `BrowserService`·`BrowserWindowController`로 확인한다(창은 화면 밖으로 옮겨 사용자 방해 없음).

1. 초기 상태 — 창 없음.
2. 로컬 HTML 로드 — 주소·제목·canGoBack=false.
3. `showWindow(activate:false, qaOffscreen:true)` — 창 존재·표시·타이틀바 스타일·닫기=숨김.
4. 주소 정책 — `file:`·`127.0.0.1` 거부, 오류 문자열 반환.
5. `hideWindow()` — 창 숨김, 웹뷰가 오프스크린으로 복귀.
6. 자동 표시 — 켜짐이면 `beginModelActivity`가 창을 열고, 꺼짐이면 열지 않는다.
7. 활동 라벨 — `browser_read` → "모델이 페이지를 읽는 중".
8. `teardown()` — 창·웹뷰 정리.

### 9.3 회귀

- `--qa-browser-routing`(기존 23/23)
- `--qa-browser-live`(기존 14/14)
- `--qa-artifact-routing`·`--qa-job-routing`·`--qa-plan-routing`·`--qa-execute-routing`·`--qa-skills-routing`

### 9.4 빌드

- `xcodebuild ... Debug clean build` · Release clean build · **경고 0**.
- 번역 커버리지 테스트 통과(새 키 전부 en/ko).

## 10. 지원 언어·i18n

- 지원 언어: **en(기본) + ko**.
- 새 사용자 문자열은 전부 `Sources/QuickTalkCore/LocalizationTable.swift`에 한국어 키 + 영어 값을 같은 커밋에 추가한다.
- 창 제목·버튼·툴팁·빈 상태·활동 라벨·안내 띠 모두 번역 대상.

## 11. 파일

| 파일 | 변경 |
|---|---|
| `QuickTalkApp/BrowserWindow.swift` | **신규** — 크롬·모델·창 컨트롤러 |
| `QuickTalkApp/BrowserService.swift` | 보이는 창·사용자 이동·활동·상태 노출 |
| `QuickTalkApp/UIStore+Browser.swift` | 자동 표시 설정 동기화·창 열기 |
| `QuickTalkApp/AgentExecutor+Browser.swift` | 활동 시작/종료 |
| `QuickTalkApp/SettingsView+Tools.swift` | 토글·버튼·캡션 |
| `QuickTalkApp/SettingsView.swift` | (필요 시) 상태 |
| `QuickTalkApp/MenuBarHubView.swift` | Hub 행 |
| `QuickTalkApp/QuickTalkApp.swift` | Hub 액션·QA 디스패치 |
| `QuickTalkApp/SingleInstance.swift` | QA 플래그 |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | `--qa-browser-window` |
| `Sources/QuickTalkCore/Settings.swift` | 설정 키 |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 번역 키 |
| `Tests/QuickTalkCoreTests/BrowserTests.swift` | 설정 테스트 |
| `QuickTalk.xcodeproj/project.pbxproj` | 새 파일 등록 |

## 12. 위험과 완화

| 위험 | 완화 |
|---|---|
| 자동 표시가 작업을 방해 | 기본은 **비활성 표시**(포커스 없음). 끄는 토글 제공. |
| 숨긴 창에서 웹뷰 레이아웃이 멈춤 | 닫을 때 웹뷰를 오프스크린 창으로 되돌린다. QA로 확인. |
| 창 ↔ 서비스 순환 보유 | 모델·컨트롤러는 서비스를 **weak**로 참조. `teardown`에서 contentView를 비운다. |
| 주소창이 모델 이동과 충돌 | 편집 중에는 외부 URL 갱신을 건너뛴다. |
| 사용자가 창을 Safari처럼 오해 | "격리 프로필" 배지·캡션·다운로드/팝업 차단 안내를 상시 노출. |

## 13. 완료 조건

- [ ] 계획 문서·TODO·DESIGN 갱신
- [ ] `browserShowWindowAutomatically` 설정·번역
- [ ] 보이는 창·주소창·뒤로/앞으로/새로고침·격리 배지·활동 표시
- [ ] 설정 버튼·메뉴바 Hub 진입점
- [ ] `swift test` 전부 통과(BrowserTests 설정 3건 추가)
- [ ] `--qa-browser-window` PASS + 기존 QA 회귀 PASS
- [ ] Debug/Release clean 빌드 경고 0
- [ ] 1.38.3(3803) 버전 범프 · Debug 설치 · HANDOFF/CHANGELOG 갱신
- [ ] 브랜치 → PR → squash merge
