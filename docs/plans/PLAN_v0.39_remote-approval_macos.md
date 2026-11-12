# PLAN v0.39 — 원격 승인: 자리를 떠나도 승인 카드에 응답한다 (macOS)

> 상태: **완료** (2026-11-13, PR 병합 · Debug 1.39.0 설치 · 실측 대기) · 크기: **L**
> 앞 문서: `PLAN_v0.38_delegation_macos.md`(Job) · `PLAN_v0.38.1_browser_macos.md`(격리 브라우저)
> 원칙: **승인 결정 경로를 새로 만들지 않는다.** 기존 `requestScheduledApproval`·10분 만료·Job 상태 전이·감사 로그를 그대로 쓰고, **입력 수단만 Telegram**을 더한다.

---

## 1. 목표 (1줄)

예약 작업이나 맡긴 작업(Job)이 승인 때문에 멈췄을 때, 사용자가 Mac 앞에 없어도 **Telegram 메시지의 버튼**으로 한 번 허용하거나 거부할 수 있게 한다.

## 2. 이번 버전이 아닌 것

- **상시 원격 제어** — 원격에서는 승인/거부만 한다. 새 작업 시작·명령 입력·파일 열람은 없다.
- **항상 허용** — 원격 승인은 **한 번만** 가능하다. `allowsAlwaysAllow` 규칙을 만들지 않는다.
- **대화형 승인** — 사용자가 보고 있는 일반 대화의 승인 카드는 그대로 Mac에서만 응답한다. 원격은 예약·Job처럼 **자리를 비운 실행**만 대상이다.
- **iMessage** — AppleScript·메시지 DB 접근이 필요해 보안·권한 부담이 크다. v0.39는 Telegram만. iMessage는 후속 후보.
- **웹훅 서버** — 인바운드 포트를 열지 않는다. Telegram **long polling**(아웃바운드 HTTPS)만 쓴다.
- **메시지에 페이지·파일 내용** — 명령·이유·경로만. 파일 내용·페이지 본문·입력값은 보내지 않는다.

## 3. 경험

> "이사 업체 견적들 비교해서 정리해 줘." → **[맡기기]** → 밭에 간다.
> → Job이 작업 폴더 밖 파일을 쓰려다 멈춘다.
> → Telegram: **🔐 승인 필요 — 이사 업체 견적 비교**
>   `명령: mkdir -p ~/Documents/이사` · `위험: 보통 · 쓰기` · `이유: 작업 폴더 밖에 폴더를 만듭니다.`
>   **[✅ 허용] [❌ 거부]** · "10분 안에 응답하지 않으면 자동 거부됩니다."
> → [✅ 허용] → Job이 이어서 실행된다. 메시지는 "✅ 허용됨 (원격)"으로 바뀐다.
> → 돌아와서 Job 대화를 열면 승인 카드·감사 로그·산출물 카드가 그대로 있다.

## 4. 안전·개인정보

| 항목 | 결정 |
|---|---|
| 기본값 | **꺼짐**. 사용자가 봇 토큰·chat ID를 넣고 켜야 한다. |
| 토큰 저장 | `SecretStore` (`secrets.json`, 0600). 설정 파일·로그·메시지에 쓰지 않는다. |
| chat ID | 설정한 **단 하나의 chat**만 처리. 다른 chat의 callback은 무시하고 "허용되지 않은 요청"으로 응답한다. |
| nonce | 128비트 랜덤, 요청마다 하나. callback data에는 nonce와 allow/deny만 넣는다(명령 미포함). |
| 만료 | 기존 10분. 만료된 callback은 거부하고 메시지를 "시간 초과"로 바꾼다. |
| 재사용 | nonce는 1회용. 처리 즉시 pending에서 지운다. |
| 결정 범위 | `.allowOnce` / `.deny`만. `.alwaysAllow`·쓰기 범위 영구 승인은 원격에서 만들 수 없다. |
| 노출 | 명령은 300자·한 줄로 줄이고 토큰/비밀번호/Authorization 패턴을 `***`로 마스킹한다. 파일 내용·페이지 본문·입력값은 보내지 않는다. |
| 네트워크 | `https://api.telegram.org` 아웃바운드만. 인바운드 포트·웹훅 없음. |
| 실패 | 전송 실패는 Job을 막지 않는다. 기존 Mac 알림·10분 만료가 그대로 동작한다. |
| 로그 | 토큰·메시지 본문·chat ID 전체를 남기지 않는다. `chat=<뒤 3자리>`·`nonce=<앞 6자>` 정도만. |

## 5. 동작

### 5.1 요청

1. `UIStore.requestScheduledApproval`이 기존대로 `scheduledApproval`을 만들고 10분 타이머를 건다.
2. `RemoteApprovalService.offer(...)`가 켜져 있고 설정이 유효하면 Telegram `sendMessage`를 보낸다.
   - 제목: `🔐 승인 필요 — <Job 목표/예약 제목>`
   - 본문: 명령(마스킹·300자) · 위험/권한 · 이유 · 쓰기 범위(있으면)
   - 버튼: `✅ 허용` / `❌ 거부` (inline keyboard)
3. 전송 실패 시 로그만 남기고 기존 Mac 알림을 그대로 쓴다. **승인 대기 자체는 실패하지 않는다.**

### 5.2 응답

- long polling `getUpdates`가 `callback_query`를 받는다.
- chat ID가 설정과 다르면 무시 + `answerCallbackQuery("허용되지 않은 요청입니다")`.
- nonce가 pending과 다르거나 만료면 무시 + "이미 처리되었거나 만료된 요청입니다".
- 허용: 메시지를 `✅ 허용됨 (원격)`으로 바꾸고 `resolveScheduledApproval(.allowOnce)`.
- 거부: `❌ 거부됨 (원격)`으로 바꾸고 `.deny`.
- Mac에서 먼저 눌렀으면 메시지를 `🖥 Mac에서 처리됨`으로 바꾸고 버튼을 지운다.
- 10분 만료: `⌛ 시간 초과 — 자동 거부`로 바꾼다.

### 5.3 설정

- `remoteApprovalEnabled` 기본 **꺼짐**.
- `remoteApprovalChatID` — Telegram chat ID(문자열, 음수 허용).
- 봇 토큰 — `SecretStore` account `telegramApprovalBotToken`.
- **[연결 테스트]** — `getMe` + 테스트 메시지 1회. 성공하면 봇 이름을 보여 준다.
- 설정 › 비서 › 예약·알림에 그룹. 봇 만들기 안내(BotFather)와 보안 캡션.

### 5.4 수명

- 앱 실행 시 설정이 켜져 있으면 polling 시작, 끄면 중지.
- 앱 종료 시 polling 취소.
- pending은 **앱 전체에 하나**(예약 실행은 동시에 하나). 새 요청이 오면 이전 pending은 "취소됨"으로 정리한다.
- 앱이 꺼지면 Telegram 버튼은 응답할 수 없다 — 메시지에 "QuickTalk가 실행 중일 때만 응답할 수 있습니다"를 넣는다. 앱 재시작 시 이전 메시지는 처리하지 않는다(오래된 승인 방지).

## 6. 구성

### 6.1 Core `Sources/QuickTalkCore/RemoteApproval.swift`

- `RemoteApprovalAction` — nonce + allow/deny, `callbackData`(≤64바이트), `parse`.
- `RemoteApprovalContent` — 제목·본문·버튼 라벨. `AgentApprovalRequest`에서 만든다.
- `RemoteApprovalText.maskedCommand` — 한 줄·300자·비밀 패턴 마스킹.
- `RemoteApprovalConfig` — enabled·chatID·token 존재 여부 검증.
- `TelegramUpdate`·`TelegramCallbackQuery` — Bot API JSON 파싱(Codable).
- `RemoteApprovalTicket` — nonce·messageID·createdAt·expiry 판정.

### 6.2 App `QuickTalkApp/TelegramClient.swift`

- `TelegramTransport` protocol (Core에 선언, 앱에서 구현).
- `URLSessionTelegramTransport` — `getMe`·`sendMessage`·`editMessageText`·`answerCallbackQuery`·`getUpdates`.
- JSON body는 `JSONSerialization`/Codable. 응답 `ok=false`는 `TelegramError`로.
- 로그에 토큰을 넣지 않는다(URL 문자열도 로그 금지).

### 6.3 App `QuickTalkApp/RemoteApprovalService.swift`

- `@MainActor` 서비스. 설정 공급자·토큰 공급자·transport·결정 콜백을 주입받는다(QA fake 가능).
- `applySettings()` — 켜짐/꺼짐에 따라 polling Task 시작·중지.
- `offer(_ approval: ScheduledApproval)` — 메시지 전송·pending 등록.
- `localResolution(_ choice:)` — Mac에서 처리됨을 메시지에 반영.
- `expire()` — 시간 초과 반영.
- `cancelPending()` — 실행 종료·새 요청 시 정리.
- `testConnection()` — getMe + 테스트 메시지.
- polling: `getUpdates(timeout: 25)` → callback 처리 → offset 갱신. 오류는 3→30초 백오프.

### 6.4 연결

- `UIStore` — `var remoteApproval: RemoteApprovalService?`, `requestScheduledApproval`에서 `offer`, `resolveScheduledApproval`에서 `localResolution`, 타이머에서 `expire`.
- `QuickTalkApp` — 서비스 생성·`store.remoteApproval` 연결·설정 변경 시 `applySettings`·종료 시 `stop`.
- `ScheduledRunRunner`/`JobService`에서 실행 종료 시 `cancelPending`.
- `SettingsView+Assistant` — 설정 UI.
- `SingleInstance` — `--qa-remote-approval` 헤드리스.

## 7. QA

### 7.1 Core 테스트 (`swift test`)

- callback data 왕복·잘못된 형식·64바이트 이하.
- 명령 마스킹(토큰·Authorization·비밀번호)·줄바꿈·300자 상한.
- 제목·본문에 명령·이유·경로가 들어가고 파일 내용은 없음.
- config 검증(토큰 없음·chat ID 비어 있음·형식 오류).
- ticket 만료 경계(10분).
- Telegram update JSON 파싱(정상·callback 없음·chat ID 음수).

### 7.2 헤드리스 `--qa-remote-approval`

Fake transport로 실제 서비스 경로를 확인한다(네트워크 없음).

1. 꺼짐 → 전송 없음.
2. 켜짐 + 잘못된 설정 → 전송 없음.
3. 정상 → `sendMessage` 1회, 본문·inline keyboard 확인.
4. 다른 chat callback → 결정 없음 + 거부 응답.
5. 올바른 allow callback → `.allowOnce` 1회, 메시지 편집 `✅ 허용됨 (원격)`.
6. 올바른 deny callback → `.deny`.
7. 같은 nonce 재사용 → 두 번째 결정 없음.
8. 만료 callback → 결정 없음 + `⌛` 편집.
9. Mac에서 먼저 해결 → `🖥 Mac에서 처리됨` 편집.
10. 토큰 마스킹 — 메시지에 원래 토큰 문자열이 없음.

### 7.3 회귀

- `--qa-job-routing`·`--qa-plan-routing`·`--qa-execute-routing`·`--qa-artifact-routing`·`--qa-browser-routing`·`--qa-browser-live`·`--qa-browser-window`·`--qa-skills-routing`·`--qa-paste-routing`.

### 7.4 빌드

- Debug/Release clean build **경고 0**.
- 번역 커버리지 통과.

## 8. 파일

| 파일 | 변경 |
|---|---|
| `Sources/QuickTalkCore/RemoteApproval.swift` | **신규** — 액션·본문·마스킹·config·Telegram 모델 |
| `QuickTalkApp/TelegramClient.swift` | **신규** — Bot API transport |
| `QuickTalkApp/RemoteApprovalService.swift` | **신규** — pending·polling·결정 |
| `Sources/QuickTalkCore/Settings.swift` | 설정 2개 |
| `Sources/QuickTalkCore/LocalizationTable.swift` | 번역 키 |
| `QuickTalkApp/UIStore.swift` | offer·localResolution·expire 연결 |
| `QuickTalkApp/QuickTalkApp.swift` | 서비스 생성·설정 반영·종료 |
| `QuickTalkApp/SettingsView+Assistant.swift` | 설정 UI |
| `QuickTalkApp/SettingsView.swift` | 상태 |
| `QuickTalkApp/ScheduledRunRunner.swift`·`JobService.swift` | 종료 시 정리 |
| `QuickTalkApp/AppDelegate+RenderHarness.swift` | `--qa-remote-approval` |
| `QuickTalkApp/SingleInstance.swift` | QA 플래그 |
| `Tests/QuickTalkCoreTests/RemoteApprovalTests.swift` | **신규** |
| `Tests/QuickTalkCoreTests/BrowserTests.swift` 또는 설정 테스트 | 설정 기본·왕복 |
| `QuickTalk.xcodeproj/project.pbxproj` | 새 파일 등록 |

## 9. 위험과 완화

| 위험 | 완화 |
|---|---|
| 봇 토큰 유출 | SecretStore 0600 · 로그 금지 · 화면에는 저장 여부만 |
| 다른 사람이 버튼을 누름 | 설정한 chat ID만 · nonce 1회용 · 10분 만료 |
| 오탭으로 위험한 명령 허용 | 한 번만 허용 · 명령·위험·이유를 메시지에 표시 · 항상 허용 버튼 없음 |
| Telegram 장애 | 전송 실패는 Job을 막지 않음 · Mac 알림·10분 만료 유지 |
| 오래된 메시지로 재승인 | 앱 재시작 시 pending 없음 · nonce 불일치 무시 |
| polling 중복(다른 앱 인스턴스) | 단일 인스턴스 가드 · 한 서비스에 polling Task 하나 |
| 네트워크 상시 사용 | 켰을 때만 long polling(25초 간격, 아웃바운드) |

## 10. 완료 조건

- [x] 계획·설정·번역
- [x] Core 타입·마스킹·config·Telegram 파싱
- [x] Bot API transport·서비스·polling·pending
- [x] Job/예약 승인 연결·Mac 처리·만료·정리
- [x] 설정 UI·연결 테스트
- [x] `swift test` 전부 통과(신규 20+)
- [x] `--qa-remote-approval` PASS + 기존 QA 회귀 PASS
- [x] Debug/Release clean 빌드 경고 0
- [x] 1.39.0(3900) · Debug 설치 · 문서 갱신
- [x] 브랜치 → PR → squash merge

## 11. 결과 (2026-11-13)

- **검증**: `swift test` **1119/1119**(6 skip, `RemoteApprovalTests` 27) · 번역 키 51개 · Debug/Release **BUILD SUCCEEDED · 경고 0**(clean) · `--qa-remote-approval` **PASS 31/31** · job/plan/execute/artifact(18/18)/browser-routing(23/23)/browser-live(14/14)/browser-window(24/24)/skills/paste PASS.
- **PR**: **#171 → squash merge `ef7fd91`**.
- **설치**: 1.39.0(build 3900) · Debug 번들 `~/Applications/QuickTalk.app` 교체·재실행 · `codesign --verify --strict --deep` OK · 백업 번들 없음.
- **실측 대기**: 실제 BotFather 토큰 저장 → chat ID 연결 테스트 → 예약·Job 승인 시 Telegram 카드 수신 → [✅ 허용]/[❌ 거부] 1회 동작 → 10분 만료 → Mac 처리 시 🖥 표시.
