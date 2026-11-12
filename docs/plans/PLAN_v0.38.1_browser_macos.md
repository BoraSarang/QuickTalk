# PLAN v0.38.1 — 격리 브라우저 (macOS)

> 상태: **구현·검증·병합·설치 완료** · 2026-11-12 · 크기: **L**
> 앞 문서: `PLAN_v0.38_delegation_macos.md` (Job) · `PLAN_v0.25_computer-control_macos.md` (화면 조작)
> 원칙: **새 실행 엔진을 만들지 않는다.** 브라우저도 기존 `AgentExecutor`·승인 카드·감사 로그·출처 카드·Job 컨텍스트를 그대로 쓴다.

---

## 1. 목표 (1줄)

모델이 **사용자의 Safari와 분리된 전용 프로필**로 웹 페이지를 열고 읽으며, 입력·폼 제출 같은 상태 변경은 **항상 사용자 승인**을 받는다.

## 2. 이번 버전이 아닌 것

- **로그인·비밀번호 입력** — 모델이 비밀번호를 보면 안 된다. 비밀번호·파일·숨김 필드는 스냅샷에서도 빼고 입력도 거부한다.
- **다운로드·설치·새 창·팝업** — 모두 차단한다. 필요하면 사용자에게 URL을 알려 준다.
- **보이는 브라우저 창·주소창 UI** — v0.38.2 이후 검토. 이번에는 오프스크린에서만 돈다.
- **원격 승인** — v0.39+. 승인이 필요하면 Job은 멈추고 Mac 알림을 보낸다.
- OpenClaw식 채널·플러그인·자가 스킬 — 계속 거부.

## 3. 경험

> "이사 업체 견적들 비교해 줘."
> → 모델이 `browser_open`으로 사이트를 열고 `browser_read`로 본문·링크·양식을 읽는다.
> → 링크 이동은 읽기로 진행한다.
> → 검색어 입력은 카드에서 **[한 번 허용]** 을 눌러야 한다.
> → 폼 제출은 **무엇이 어디로 가는지** 보고 승인한다.
> → 답변 아래 출처 카드에 실제로 읽은 페이지가 쌓인다.

## 4. 도구 6개

| 도구 | 권한 | 승인 | 하는 일 |
|---|---|---|---|
| `browser_open` | 읽기 | 읽기 정책이 "매번 확인"일 때만 | http/https URL을 연다 |
| `browser_read` | 읽기 | 위와 같음 | 현재 페이지를 다시 읽는다 |
| `browser_back` | 읽기 | 위와 같음 | 뒤로 간다 |
| `browser_click` | 링크=읽기 / 그 외=실행 | **버튼·체크박스·탭 클릭은 항상** | 링크는 이동, 나머지는 클릭 |
| `browser_type` | 실행 | **항상** | 텍스트 입력·select 선택 |
| `browser_submit` | 실행 | **항상** | 양식 제출 |

- `browser_open`·`browser_read`는 최대 20,000자(기본 10,000자)를 돌려준다.
- 페이지 본문은 **신뢰할 수 없는 데이터**로 표시하고, 안의 지시를 따르지 말라고 모델에 명시한다.
- 참조(`e1`, `e2`, …)는 **마지막 스냅샷에서만** 유효하다. 페이지가 바뀌면 다시 읽어야 한다.
- `browser_type`은 비밀번호·파일·숨김·결제·인증번호 필드를 **거부**한다. `select`는 값 또는 표시 텍스트로 고른다.
- `browser_submit`은 `ref`가 속한 양식을 제출한다. 필수 항목이 비면 브라우저 검증에서 멈춘다.

### 4.1 읽기 전용 기본

- 링크 이동은 읽기다. 단, 경로·쿼리에 `logout`·`delete`·`unsubscribe`·`checkout` 같은 **상태 변경 신호**가 있으면 승인 카드로 올린다.
- 그 밖의 클릭은 `button`·`input[type=submit]`·`checkbox`·`radio`·`role=button` 등 **모두 승인**이다.
- 페이지 로드 자체가 서버에서 상태를 바꾸는 GET 링크의 위험은 완전히 없앨 수 없다. 이 한계는 설정 화면과 문서에 적는다.

## 5. 격리·보안

### 5.1 전용 프로필

- `WKWebsiteDataStore(forIdentifier:)` — 앱이 만든 고정 UUID 프로필.
- Safari·사용자의 다른 브라우저·앱의 기본 WKWebView 저장소와 **쿠키·캐시를 공유하지 않는다**.
- 프로필 ID는 `settings.browserProfileID`에 저장한다(비밀 아님).
- 설정에서 **브라우저 데이터 지우기** — 쿠키·캐시·로컬 저장소를 모두 지운다.
- 프로필은 `~/Library/Application Support/QuickTalk` 밖(WebKit 관리 영역)에 저장된다. 앱 데이터 가드와 별개임을 문서에 적는다.

### 5.2 URL 정책

- http/https만 허용. `javascript:`·`file:`·`data:`·`mailto:`·`tel:` 거부.
- URL 안의 사용자 이름·비밀번호(`https://user:pass@…`) 거부.
- 길이 2,048자 제한.
- **로컬·사설 네트워크 차단**: `localhost`, `*.localhost`, `*.local`, `*.internal`, `*.lan`, `*.home.arpa`, `127.0.0.0/8`, `10/8`, `172.16/12`, `192.168/16`, `169.254/16`, `100.64/10`, IPv6 loopback·link-local·ULA, 숫자만 있는 호스트.
- DNS가 사설 IP로 풀리는 호스트(리바인딩)는 이번 버전에서 막지 못한다 — 한계로 기록한다.
- 리다이렉트 후 최종 URL도 같은 정책으로 검사한다.

### 5.3 오프스크린

- `1280×900` 테두리 없는 창을 화면 밖 `(-12000, -12000)`에 둔다.
- `canBecomeKey/Main = false`, `ignoresMouseEvents = true`, Dock·Mission Control·창 메뉴에 나오지 않는다.
- 앱을 활성화하지 않는다 — **포커스 스틸 없음**.
- 창을 닫거나 앱이 끝나면 WKWebView를 정리한다. 대화별 최대 2개, 15분 유휴 시 정리.

### 5.4 차단

- 다운로드(`shouldPerformDownload`, 표시할 수 없는 MIME) — 취소.
- 새 창·팝업(`createWebViewWith`) — 취소, 모델에 "새 창은 열지 않습니다" 안내.
- JavaScript `alert`/`confirm`/`prompt` — 자동 취소(확인은 `false`, 입력은 `nil`).
- 파일 선택 — 취소.
- 카메라·마이크·위치·알림 권한 — 거부.
- HTTP 기본 인증·클라이언트 인증서 — 취소(비밀번호 창을 띄우지 않는다).
- TLS 인증서 오류 — 우회하지 않는다.

### 5.5 승인 카드

- `browser_type`: 페이지 URL, 필드 이름·종류, **입력할 내용 미리보기**(최대 120자). 감사 로그에는 내용을 남기지 않는다.
- `browser_submit`: 메서드·대상 URL, 입력된 필드 이름, 다른 사이트로 가는지, 비밀번호·숨김 필드가 있는지.
- `browser_click`(비링크): 페이지 URL, 요소 이름·종류, 양식이 제출될 수 있음.
- 모든 브라우저 상태 변경 승인은 `allowsAlwaysAllow: false` — **항상 허용 규칙을 만들지 않는다**.
- 승인 대기는 기존 경로를 쓴다: 대화 카드 / Job이면 10분 뒤 `.paused` + 알림.

## 6. 아키텍처

```
AgentExecutor+Browser.swift        도구 디스패치·승인·감사·출처
        │
        ▼
UIStore+Browser.swift              대화별 BrowserService 캐시·프로필 ID·데이터 삭제
        │
        ▼
BrowserService.swift               오프스크린 WKWebView 1개
  ├─ WKNavigationDelegate          URL 정책·다운로드·리다이렉트 차단
  ├─ WKUIDelegate                  새 창·다이얼로그·파일·미디어 차단
  ├─ snapshot JS                   본문·요소 참조·양식 추출
  └─ click/type/submit JS          참조 기반 조작
        │
        ▼
QuickTalkCore
  ├─ BrowserPolicy.swift           URL·링크 위험 판정
  ├─ BrowserSnapshot.swift         스냅샷 모델·모델용 텍스트 렌더
  └─ BrowserTools.swift            도구 6개 스키마
```

- 브라우저 상태는 **대화 ID**로 분리한다. 현재 대화와 Job 대화가 서로의 페이지를 덮지 않는다.
- `ScheduledRunContext`가 있으면 `scheduledRun.conversation.id`를 쓴다.
- 도구는 `settings.browserEnabled` + `settings.agentToolsEnabled` + 비서의 `tools.web` 세 게이트를 모두 통과해야 한다.
- Apple FM에는 넘기지 않는다(기존 UI 제어와 같은 이유).

## 7. 데이터 모델

```swift
BrowserPageSnapshot { url, title, text, elements, forms, truncated, notice }
BrowserElement { ref, kind, tag, type, name, label, href, formIndex,
                 required, download, disabled, valueLength, options }
BrowserForm { index, action, method, fields, hasSensitive }
BrowserFormField { ref, name, type, label, required, valueLength, options }
```

- 비밀번호·파일·숨김·민감 autocomplete 필드는 **요소·양식 어디에도 넣지 않는다**.
- `valueLength`만 노출한다 — 입력된 값 자체는 모델에 다시 보내지 않는다.
- 양식별 `hasSensitive`로 "표시하지 않은 필드가 있음"을 알린다.

## 8. 설정

설정 › 도구·권한 › **격리 브라우저**

- `웹 브라우저 사용` 토글 — 기본 **꺼짐**.
- 설명: 전용 프로필, 읽기 전용 기본, 입력·제출은 항상 확인, Safari와 분리.
- `브라우저 데이터 지우기` — 쿠키·캐시·로컬 저장소 삭제.
- 한계 안내: 비밀번호·다운로드·새 창·로그인 페이지 미지원, GET 링크의 서버 상태 변경 가능성.
- 비서 편집 시트의 `웹 검색` 설명을 "검색하고 격리 브라우저로 페이지를 읽습니다"로 갱신.

## 9. 감사·출처

- 감사: `browser_open <url>`, `browser_read <url>`, `browser_back <url>`,
  `browser_click link <url>`, `browser_click <host><path> ref=eN`,
  `browser_type <host><path> field=<name>` (**입력값 없음**),
  `browser_submit <METHOD> <action>`.
- Job·예약 실행은 기존 `recordAudit`가 `job:<id8>`·`task:<id8>`를 붙인다.
- 읽은 페이지는 `TurnSource`로 답변 출처 카드에 쌓인다.
- 실행 카드 출력은 `본문 N자 · 링크 M개 · 양식 K개`처럼 짧게 유지한다(본문은 모델에게만).

## 10. 검증

### 단위 테스트 (QuickTalkCore)

- URL 정책: https/http 허용, 스킴 거부, 자격 증명 거부, 로컬·사설 IP 거부, 숫자 호스트 거부, 길이 제한.
- 링크 위험 판정: `/logout`, `?action=delete` 승인 / `?q=delete` 통과.
- 도구 카탈로그: 기본 6개 유지, `includingBrowser`일 때만 6개 추가, 비서 `web=false`면 제외, `tool(named:)`.
- 스냅샷 렌더: 본문 자름, 참조·양식·민감 필드 안내, 신뢰할 수 없는 데이터 문구.
- 설정 왕복: 새 키가 없던 JSON도 기본값으로 읽힌다.

### QA 하네스

- `--qa-browser-routing` — 게이트·도구 목록·URL 정책·위험 링크·렌더를 헤드리스로 확인.
- `--qa-browser-live` — 오프스크린 WKWebView에 로컬 HTML을 넣어 제목·본문·링크·양식·민감 필드 제외·입력값 길이를 확인. 네트워크 없음.

### 빌드

- `swift test` 전체 통과.
- Debug/Release `xcodebuild` 경고 0.
- 기존 `--qa-job-routing`, `--qa-plan-routing`, `--qa-execute-routing` 유지.

### 실측 결과 (2026-11-12)

| 항목 | 결과 |
|---|---|
| `swift test` | **1078/1078** 통과 (6 skip, 0 failures) — `BrowserTests` 18개 포함 |
| `LocalizationCoverageTests` | 5/5 — 브라우저 문구 102+키 영어 번역 |
| Debug 빌드 | **BUILD SUCCEEDED · 경고 0** |
| Release 빌드 | **BUILD SUCCEEDED · 경고 0** |
| `--qa-browser-routing` | **PASS 23/23** — 카탈로그·게이트·권한·URL 정책·위험 링크·스냅샷 렌더 |
| `--qa-browser-live` | **PASS 14/14** — 실제 오프스크린 WKWebView, 로컬 HTML(네트워크 없음) |
| 회귀 | `--qa-job-routing`·`--qa-plan-routing`·`--qa-execute-routing` PASS |

- `--qa-browser-live` 는 제목·본문·링크·양식·select 선택지·비밀번호/숨김 필드 제외·입력값 길이·링크=읽기/버튼=승인/제출 계획을 확인한다.
- 실제 네트워크 페이지와 실제 모델의 브라우저 도구 호출은 **아직 실측하지 않았다** — QA는 로컬 HTML만 쓴다.

## 11. 단계

1. ✅ 코어: `BrowserPolicy`, `BrowserSnapshot`, `BrowserTools`, 카탈로그·권한·지시문.
2. ✅ 앱: `BrowserService`, `UIStore+Browser`, `AgentExecutor+Browser`, 디스패치.
3. ✅ 설정·비서 문구·영어 번역·QA 하네스.
4. ✅ 테스트·빌드·문서·버전 1.38.1(3801)·설치·알림.
5. ⏳ 실제 모델의 브라우저 도구 호출 1회는 사용자 복귀 시 실측.

## 12. 남는 한계 (정직)

- 로그인·2단계 인증·CAPTCHA가 필요한 페이지는 읽기만 된다.
- 자바스크립트로 늦게 그려지는 페이지는 0.35초 뒤 스냅샷이라 일부가 비어 보일 수 있다 — `browser_read`로 다시 읽으면 된다.
- GET 링크가 서버에서 상태를 바꾸는 사이트는 링크 이동만으로 바뀔 수 있다. 위험 신호가 있는 링크는 승인을 받지만 완전한 보장은 아니다.
- DNS 리바인딩으로 사설 IP에 접속하는 경우는 막지 못한다.
- 다운로드·인쇄·PDF 저장·새 창은 지원하지 않는다.
