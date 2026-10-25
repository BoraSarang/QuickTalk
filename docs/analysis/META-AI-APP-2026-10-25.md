# Meta AI for macOS 기능 분석 (2026-10-25)

> 대상: `/Applications/Meta AI.app` — `com.meta.endo.vanilla`, v10.0(빌드 1092547526), arm64, 최소 macOS 15.0, SDK 27.0
> 목적: 기능 인벤토리 + **"창 연결"** 동작 원리 확인 + QuickTalk 적용 후보 도출
> 방법: REA 정적 분석(배포 아티팩트) + 로컬라이제이션/문자열/심볼 증거. **런타임 실행 관찰은 하지 않았다**(사용자 맥 사용 중).

## 0. 분석 근거와 한계

| 항목 | 내용 |
|---|---|
| JS 앱 그래프 | `Resources/vanilla` (React+WebKit 채팅 UI) — Evidence `ev_7aae6553…` |
| Mach-O 레이아웃 | `Contents/MacOS/Meta AI` (arm64, 73 dylib) — Evidence `ev_21d00983…` |
| 딥 프로바이더 | **없음**(Ghidra/Hopper/IDA 미구성) → 디컴파일·함수 분석 불가 |
| 따라서 | 아래 내용은 **배포 바이너리의 문자열·심볼·로컬라이제이션·Info.plist**에서 관찰된 사실 + 그로부터의 추론이다. 실행 흐름의 세부 순서·스레딩은 단정하지 않는다. |

관찰된 심볼/파일명(EndoVanilla 모듈): `WorkingWindowManager`, `WorkingWindowControlGate`, `WorkingWindowTarget`, `WorkingWindowText`, `WorkingWindowChip`, `WorkingWindowPicker`, `WorkingWindowRow`, `WorkingWindowTextPreview`, `ScreenCapture`, `ScreenCaptureError`, `BlockedAppsService`, `ComputerUseAuthorization`, `EndoDictationSessionController`, `VoyagerDuplexDictationBackend`, `ReminderReader`, `NotesWriter`, `MessagesSender`, `VanillaConnectorApproval`, `VanillaAutomationPermission`, `VanillaScheduledView`, `LibraryWindow`, `VanillaUpdater`, `ShortcutRecorder`, `SystemPermissionMonitor`.

## 1. 앱 구조

- **네이티브 셸 + 웹 UI 하이브리드**: Swift/SwiftUI/AppKit 셸이 창·단축키·권한·로컬 커넥터·창 연결을 담당하고, 대화 화면은 `Resources/vanilla`의 React 번들(WebKit)이 그린다.
- **배포/업데이트**: Sparkle 프레임워크 + Crashpad(`EndoVanillaCrashpadHandler`).
- **로그인**: OAuth 딥링크 `meta-ai://` (URL 타입 `com.meta.endo.vanilla.oauth`), 창 제어용 `endovanilla-window://`.
- **권한 선언**(Info.plist): 마이크, 캘린더(전체), 연락처, 미리 알림, Apple Events(메시지 전송·메모 추가).
- **연결 프레임워크**: ScreenCaptureKit, Vision, EventKit, Contacts, Carbon(단축키), ServiceManagement(로그인 항목), WebKit, AVFoundation, Sparkle.

## 2. 기능 인벤토리

### A. 대화·생성
| 기능 | 동작 |
|---|---|
| 채팅 | 스트리밍 답변, 중지, 재생성, 마크다운/코드 하이라이트(KaTeX·Shiki 번들), 답변 내 카드(지도·장소·상품·릴스) |
| 첨부 | 파일 선택·드래그드롭·붙여넣기(이미지), 개수/용량/형식 제한 메시지, 폴더 미지원 |
| 내 채팅 검색 | 보관된 대화 검색 |
| 이미지/동영상 생성 | Imagine 계열 모드(`AGENT_TYPE_MODE_IMAGINE`, "동영상 생성"), 프리셋 이미지 피커 |
| 라이브러리 | 최근 생성물 갤러리(`LibraryWindow`, 오늘/어제 구분, 레이트리밋 오류 표시) |
| 예약 작업 | `Scheduled` 탭 — 활성/비활성 작업 목록, 대화 열기, 관리 |
| 지도·장소 | MapLibre 기반 지도, 장소 상세 레일 |
| 음성 통화 | 마이크 권한 안내 문구로 존재 확인(통화 UI 자체는 미확인) |

### B. 호출·입력
| 기능 | 동작 |
|---|---|
| Quick Invoke | 전역 단축키로 **다른 앱 위에 컴팩트 컴포저**를 띄운다("창을 전환할 필요 없이"). 기본 단축키는 Hatch/Muse와 충돌 시 양보 규칙이 있다. |
| 받아쓰기 | ① 누르고 말하기 ② 토글 ③ 핸즈프리(오른쪽 Option 두 번) — **Meta AI가 아닌 다른 앱에도 텍스트를 입력**한다. 자동 전송, 시작/종료음 끄기, 입력 장치 선택 |
| 화면 인식 받아쓰기 | 선택한 창의 스크린샷을 참고해 화면에 보이는 이름·파일명·코드 식별자를 정확히 표기(받아쓰기+화면 기록 권한) |
| 단축키 | 녹화 UI, 수정자 필수, 충돌 검사, Esc 취소 |

### C. 화면·창 (핵심 3절에서 상세)
| 기능 | 동작 |
|---|---|
| **창 연결** | 창 하나를 골라 **텍스트(Accessibility) + 스크린샷**을 다음 질문의 컨텍스트로 첨부 |
| 창 제어 | 고른 창 하나만 백그라운드에서 조작(내부 빌드 게이트) |
| 내 화면 보기 | 화면 기록 권한 기반 화면 공유 |

### D. 이 Mac의 앱(로컬 커넥터)
| 커넥터 | 접근 | 승인 |
|---|---|---|
| 미리 알림 | 읽기/추가 | 카드: 묻기·항상 허용·허용, 카드 자체 만료 |
| 캘린더 | 읽기/추가/삭제 | 삭제는 매번 확인 |
| 연락처 | 조회/추가 | 카드 |
| 메모 | 검색/읽기/추가(폴더 지정) | 전체 디스크 액세스 필요, **공유 폴더에는 쓰지 않음** |
| 메시지 | 검색/읽기/보내기 | Automation 권한, 그룹 대화 경고 |
| 파일/폴더 | 찾기·정리·스프레드시트 추출 | 전체 디스크 액세스 + **사용자가 공유한 폴더만**, 자격증명/키 경로는 하드 차단 |
| 3P | Outlook(메일·People·캘린더), Gmail, Google 연락처, Apple Music/Health 등 이름 확인 | OAuth 연결 |

프라이버시 원칙(문자열): "연결된 데이터는 답변 요청 전까지 **이 Mac에 유지**되고, **검색어와 일치하는 데이터만** 전송된다."

### E. 앱·시스템
- 온보딩 v2: 단축키 → 받아쓰기 → **창 연결** → 파일/메시지 접근 → 테마/Dock/로그인 → 완료(권한을 단계별로 요청).
- 설정: 테마·강조색(11색)·채팅 글꼴 크기·글꼴 매끄럽게, 언어(변경 시 재시작), 알림, Dock 표시/숨김, 로그인 시 열기, 단축키, 권한, 데이터 및 공개 범위(AI 학습·내 정보 내보내기), 업데이트.
- 계정: Accounts Center, 로그아웃 시 로컬 커넥터 승인 철회.

## 3. "창 연결" — 어떻게 동작하나

### 3.1 사용자 흐름
1. 설정 › **창 첨부 설정** 토글(끄면 컴포저 버튼이 비활성 + "창 연결이 해제되었습니다" 팝오버로 켜기 안내).
2. 컴포저의 **창 첨부 버튼** → 창 선택 팝오버. 시스템 UI는 목록에서 제외(`com.apple.controlcenter`, `systemuiserver`, `WindowManager`, `notificationcenterui`, `wallpaper`, `Spotlight`, `screencaptureui`). 창이 없으면 "사용 가능한 창 없음".
3. 창을 고르면 **"Meta AI가 읽을 내용"** 미리보기 — 본문, **선택된 텍스트**, "읽을 수 있는 텍스트 없음"(이 경우 스크린샷만), "창의 스크린샷도 전송됩니다" 고지.
4. 전송하면 컴포저에 **창 이름 칩**이 남는다. 탭해서 변경, **"이 창 읽기 중지"** 로 해제.
5. 온보딩에서도 같은 단계를 한 번 시킨다("Meta AI가 읽을 내용" / 두 권한 안내).

### 3.2 권한 2개
| 권한 | 없으면 |
|---|---|
| **화면 기록**(Screen Recording) | 창을 보고 캡처할 수 없다 |
| **손쉬운 사용**(Accessibility) | **텍스트를 못 읽고 스크린샷만** 보낸다 |

권한 대기 로그: `[Permission] Screen Recording not granted (timed out)`, 승인 시 앱 재시작으로 반영, `endo-window://permissions` 딥링크로 설정 창 유도.

### 3.3 내부 동작 (관찰된 문자열 기준)
1. **열거** — ScreenCaptureKit `SCShareableContent`(비동기 콜백 시그니처 `SCShareableContent, NSError`)로 창 목록을 얻고, 시스템 UI/차단 앱을 걸러 `WorkingWindowTarget`(pid·windowID·제목·번들ID·앱이름)을 만든다. 실패는 `[WorkingWindow] Enumeration failed:`.
2. **텍스트 읽기** — `readWindowText(pid:windowTitle:bundleID:)` → `AXUIElement` 트리 순회. 선택 영역은 `AXFocusedUIElement`의 `AXSelectedText`. 터미널·Xcode·Chromium 계열은 `AXManualAccessibility`/`AXEnhancedUserInterface` 보조 속성을 켜서 텍스트를 얻는다. 로그: `[WorkingWindow] Read AX text (window=…`, `[WorkingWindow] No AX text for …`.
3. **스크린샷** — `ScreenCapture`가 해당 창 1프레임을 캡처. `[ScreenCaptureGeometry]`(source/filter rect, point_pixel_scale)로 **창 영역이 실제로 검증되는지** 확인하고, "captured with no content"면 **빈 비트맵 검사(blank-check)** 후 **1회 재시도**. 실패 시 "선택한 창의 화면 영역을 확인할 수 없습니다".
4. **업로드** — 텍스트는 임시 파일로 써서 업로드, 스크린샷은 **JPEG 인코딩 후 업로드**. 인증 토큰이 필요하고(`No auth token for capture`), 실패 지점마다 별도 로그(`Text upload failed`, `Screenshot upload failed`).
5. **프롬프트 주입** — 모델에게 아래 문구와 함께 본문/선택 텍스트가 들어간다(원문):

   > The user has attached the window "…". Below is its current on-screen content, read via macOS Accessibility.
   > This window is read-only context. You cannot click, type, scroll, open menus, or change anything in that app,
   > and you cannot re-read the window on demand — **this is a single snapshot taken when the user sent the message**.
   > Never claim or offer to act on the window; when an action is needed, tell the user what to do.
   > `--- Window text ---` / `[Note: the window text was truncated to fit.]` / `--- Selected text (the user's current selection) ---`

6. **정리** — `[WorkingWindow] Cleared`, `Bound:` 로 상태 전이. 창이 닫히거나 캡처 불가면 "Window no longer capturable".

핵심 설계: **읽기 전용 스냅샷**이다. 모델은 그 창을 다시 읽거나 조작할 수 없다고 명시적으로 교육되고, 길면 잘라서 보낸다.

### 3.4 창 제어(Computer Use) — 별도·게이트됨
- 읽기와 달리 **동의가 한 번 더** 필요하다: `endo_vanilla_window_control_consent`, `WorkingWindowControlGate`, 로그 `[WorkingWindowControl] Disarmed`.
- 칩 상태가 3가지: "이 창의 텍스트 및 스크린샷을 읽습니다"(읽기만) / "Meta AI가 이 창을 제어할 수 있습니다. 변경하려면 누르세요"(제어) / "현재 창 작업이 완료될 때까지 기다리는 중".
- 동작 제한(원문): *"Background computer use is restricted to this exact window. Use normalized 0-1000 coordinates. Supported actions are screenshot, wait, left click, Accessibility context menu/open, exact Accessibility text insertion, one-page Accessibility scroll, and Return/Enter when exposed as Confirm/Press. Mouse move, drag, raw keyboard shortcuts, and synthetic events are unavailable."*
  → **마우스 이동·드래그·원시 키보드·합성 이벤트 금지**, 좌표는 0~1000 정규화, 클릭은 Accessibility 기반.
- 시각 피드백: 제어 중인 창 위에 **커서·클릭 리플 오버레이**(포커스 안전, 미용 목적).
- 차단: `BlockedAppsService` + `Hatch/blocked_apps.json` + 사용자 규칙. Finder·Numbers·Chrome 등은 "차단되었거나 프라이버시 상태를 알 수 없음"으로 거부.
- **가용성 게이트**: "Computer Use is not available in this build" / "내부 빌드 + 직원 상태"에서만 사용 가능. 즉 **읽기(창 연결)는 공개, 제어는 도그푸딩**.

### 3.5 프라이버시 장치
- 보내기 전 **미리보기**(무엇을 읽는지), 스크린샷 전송 고지, "읽기 중지" 버튼, 시스템 UI 제외, 차단 앱 목록, 자격증명 경로 차단.

## 4. QuickTalk 적용 제안

현재 QuickTalk: `SCShareableContent`/`CGWindowList` 기반 창 캡처(`CaptureService`), QuickShelf, 승인 카드, 셸 에이전트(v0.18), pill, 받아쓰기(자체 입력창), 보관함이 이미 있다. 그래서 **재사용 가능한 토대가 좋다.**

### P0 — 바로 넣을 만한 것 (1~2주)
1. **창 연결(읽기 전용)**: 창 선택 → AX 텍스트 + 스크린샷 → 다음 질문 컨텍스트.
   - `WindowAttachmentService`(Core): 열거(SCShareableContent, 시스템 UI 제외) → AX 텍스트(상한 예: 20k자) + 선택 텍스트 → 캡처 1프레임(빈 프레임 1회 재시도) → `WindowAttachment` 모델.
   - 컴포저: 버튼 → 자체 디자인 시트(피커) → **"읽을 내용 미리보기"** → 칩(창 이름·해제).
   - 프롬프트: "읽기 전용 단일 스냅샷, 재읽기·조작 불가" 문구를 시스템 프롬프트에 고정.
   - 권한: `AXIsProcessTrustedWithOptions`, `CGPreflightScreenCaptureAccess` + 설정 딥링크 시트. 없으면 "스크린샷만" 폴백.
2. **민감 앱/경로 차단 목록**: 터미널·암호 관리자·키 파일(`~/.ssh`, Keychain 덤프 등) 기본 제외, 사용자 규칙. (QuickTalk은 이미 시스템 전역 경로 차단이 있으니 자격증명 패턴만 추가)
3. **투명성 UI**: 보내기 전에 "모델에게 무엇이 가는지" 보여주는 미리보기(창 텍스트·이미지·검색 결과). 기존 승인 카드와 같은 컴포넌트로.

### P1 — 다음 단계 (2~4주)
4. **모든 앱 받아쓰기**: 전역 hold-to-talk → 포커스 앱에 텍스트 삽입(AX/CGEvent) + 화면 인식 받아쓰기(선택 창 스크린샷으로 고유명사 보정). 창 연결과 같은 캡처 파이프라인 재사용.
5. **로컬 커넥터(미리 알림·캘린더·메모·연락처)**: EventKit/Contacts/AppleScript + **범위 승인 카드**(묻기/항상/허용, 만료). QuickTalk 승인 카드 구조를 그대로 확장.
6. **에이전트 실행 전 계획 미리보기**: "무엇을 읽고/실행할지" 먼저 보여주고 승인 — v0.19(쓰기·되돌리기)와 자연스럽게 결합.

### P2 — 후순위/주의
7. **창 제어(computer use) 축소판**: 한 창 한정, 정규화 좌표, 액션 5종, 커서 오버레이, armed 게이트. **위험도 높음** — v0.20 실행 고도화 이후, 기본 OFF.
8. **예약 작업·라이브러리(생성물 갤러리)·강조색/글꼴 설정**: 있으면 좋지만 핵심 가치는 낮다.
9. **온보딩 권한 단계화**: QuickTalk은 권한이 늘어날 예정이므로, Meta AI처럼 "기능 → 그 기능이 필요한 권한" 순서로 한 단계씩 요청하는 흐름을 참고할 만하다.

### 가져오지 말아야 할 것
- 창 텍스트·스크린샷의 **서버 업로드**(QuickTalk는 로컬 우선·키체인 원칙). 필요하면 "전송 전 미리보기 + 로컬 모델 우선"으로.
- 전체 디스크 액세스를 전제로 한 파일 커넥터(최소 권한 원칙 위배).
- 내부 빌드 전용 computer use 게이트를 그대로 흉내내는 것(사용자에게 혼란).

## 5. QuickTalk 구현 스케치 (P0-1)

```
Sources/QuickTalkCore/
  WindowAttachment.swift      // 모델 + 프롬프트 조립(순수) + 트렁케이션 규칙
  WindowTextSanitizer.swift   // 빈 줄/중복/제어문자 정리, 상한
QuickTalkApp/
  WindowAttachmentService.swift  // SCShareableContent 열거, AX 읽기, 캡처, 빈 프레임 재시도
  WindowPickerSheet.swift        // 자체 카드/시트(custom 프로필), 미리보기
  ComposerAttachmentChip.swift   // 칩 + 해제
Tests/QuickTalkCoreTests/
  WindowAttachmentTests.swift    // 프롬프트 문구·상한·필터·미리보기 텍스트
```

검증 계획: ① Core 테스트(프롬프트/상한/필터) ② 오프스크린 렌더(피커·미리보기·칩, 한/영) ③ 헤드리스 `--window-attach-test`(열거→읽기→캡처, 실제 앱 창 1개) ④ 사용자 실측(권한 거부/승인, 창 닫힘, 빈 텍스트).

성능 예산: AX 순회는 백그라운드, 텍스트 상한 20k자, 캡처 1프레임, 캐시 없음(전송 시점 스냅샷) — Cold Start 영향 없음.

## 6. 남은 미확인(정직한 한계)
- 딥 디스어셈블러 부재로 **함수 단위 호출 순서·스레드 모델**은 미확인.
- 창 목록이 SCShareableContent인지 CGWindowList 병행인지는 문자열상 둘 다 존재(단정 불가).
- 창 연결 선택이 **다음 메시지 1회만**인지, 칩이 유지되는 동안 **매 전송마다 새 스냅샷**인지는 프롬프트 문구("single snapshot taken when the user sent the message")와 로그로 보아 **전송 시점 캡처**가 맞지만, UI 상태 전이 전체는 미관찰.
- 음성 통화·릴스 등 일부 기능은 문자열만 확인.

## 7. P0-1 구현 결과 (2026-10-25)

Meta AI 분석의 P0-1(창 연결·읽기 전용)을 QuickTalk에 넣었다. **Meta AI의 서버 업로드·창 조작은 가져오지 않았다.**

| 파일 | 역할 |
|---|---|
| `Sources/QuickTalkCore/WindowContext.swift` (신설) | `WindowTarget` · `WindowSnapshot` · `WindowContextLimits` · `WindowContextPrompt` — 순수 계산만(테스트 가능): 창 필터, 텍스트 정리·트렁케이션(20k자, 줄 경계), 첨부 본문 규칙, 파일 이름 |
| `QuickTalkApp/WindowAttachmentService.swift` (신설) | 창 열거(`SCShareableContent` + z-order), AX 텍스트 읽기(백그라운드·1.5s 타임아웃·노드 4,000/깊이 40), 선택 텍스트, 창 캡처(최대 2048px, 단색 프레임 1회 재시도), 임시 파일(7일 정리) |
| `QuickTalkApp/WindowPickerSheet.swift` (신설) | custom 시트 — 권한 카드, 창 목록(아이콘·검색), "QuickTalk가 읽을 내용" 미리보기, 취소/연결 |
| `QuickTalkApp/ContentView.swift` | 입력독 🪟 버튼(🌐 왼쪽) + 시트, 오른쪽 여백 계산 |
| `Sources/QuickTalkCore/Settings.swift` · `SettingsView+General.swift` | `windowAttachmentEnabled`(기본 ON) + 일반 › 창 연결(권한 상태·딥링크) |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 새 문구 55키 영어 번역 |
| `Tests/QuickTalkCoreTests/WindowContextTests.swift` (신설) | 33 테스트 — 정리·트렁케이션·창 필터·본문 규칙·미리보기·파일 이름·번역 |

설계상 지킨 것:
- **첨부는 기존 파이프라인**(텍스트 파일 + PNG)을 그대로 탄다 → Apple FM · Ollama · OpenAI 호환 모두 동작하고 `UIStore.send()`를 건드리지 않는다.
- **한 번의 스냅샷**: 첨부 시점에 읽고, 본문에 "다시 읽을 수 없습니다. 이 스냅샷이 전부입니다."를 고정한다.
- **읽기만**: 클릭·입력·스크롤·메뉴 열기 없음. `AXManualAccessibility`(Chromium 트리 노출 힌트)만 켠다.
- **권한**: 화면 기록 = 창 목록·스크린샷(필수), 손쉬운 사용 = 글자(선택, 없으면 스크린샷만).
- **서버 업로드 없음**: 파일은 로컬 앱 지원 폴더에만 잠깐 남고 7일 뒤 정리된다.

검증·한계:
- `swift test` 467/467(6 skip) · `xcodebuild` BUILD SUCCEEDED(경고 0) · SF Symbol 이름 실측 확인.
- 사용자 맥 사용 중이라 **앱 실행·창 조회·실제 캡처·오프스크린 렌더를 하지 않았다** → 권한 승인/거부, 빈 텍스트 창, 창 닫힘, 다중 모니터 배율은 **사용자 실측 대기**.
- `--window-attach-test` 헤드리스 하네스는 만들지 않았다(창 조회가 필요해 이번 조건에서 실행 불가).
