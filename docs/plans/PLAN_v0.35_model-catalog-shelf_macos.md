# PLAN v0.35 — 모델 카탈로그 · 비서별 모델 · 퀵셀프 목차 · 비서별 리포트 (macOS)

> 상태: **제안 — 구현 전 (PLAN만 작성)** (2026-11-08)
> 작성: 2026-11-08
> 근거: 사용자 요청 4건(모델 목록·캐싱·비서 모델·상세 정보 / 퀵셀프 목차 / 리포트 폴더 / 대화 전환 지연)
> 참고: `/Users/lee/Documents/Apps/ZenFreeProxy/docs/OPENCODE_MODEL_SYNC.md` · OpenCode 모델 피커 화면
> 관련 브랜치(예정): `feat/v0.35-model-catalog` · `fix/v0.35-shelf-outline` · `perf/v0.35-chat-switch`
> 선행 조건: v0.33(`feat/v0.33-fresh-pill-file-links`)·v0.34(`fix/v0.34-agent-appdata-guard`) 병합 후 `main` 에서 분기

---

## 1. 문제

### 1.1 모델 목록·캐싱·상세 (요청 1·2·4)

- 모델 목록은 `GET /v1/models` 의 **ID 문자열만** 받는다(`Sources/QuickTalkCore/LLMProvider.swift:495`). 컨텍스트·입력 형식·도구 지원·추론 강도를 알 수 없다.
- 목록은 `UIStore.modelOptions` 메모리에만 있고, 프로바이더를 바꾸면 비워진다(`UIStore.swift:1109–1128`). 설정을 다시 열거나 프로바이더를 편집할 때마다 **[모델 목록 불러오기]** 를 눌러야 한다.
- OpenCode는 `models.dev` 레지스트리로 `26만 context · Text Image · Tools · Low/High/Max` 를 보여 준다. QuickTalk에는 같은 정보가 없다.

> 사용자 요청 — *"모델 목록 확인 시에 opencode 처럼 할 수 있나"*, *"모델 목록을 매번 불러 오는 거 같은데 … 캐싱 했으면"*, *"선택할 때 세부 정보도 보여 줬으면 … 이 모델이 뭘 할 수 있는지"*

### 1.2 비서별 모델 (요청 3)

- `Persona.providerID/model` 필드는 있지만 **예약 실행에만** 적용된다(`Persona.swift:94`, `SettingsView+Assistant.swift:486`).
- 일반 대화는 항상 `settings.activeProvider` 를 쓴다(`UIStore.swift:1741`). "코딩 특화 비서"를 만들어도 코딩 모델을 고정할 수 없다.

> 사용자 요청 — *"비서에는 모델도 선택 하게 하고 싶은데"*

### 1.3 퀵셀프 대화 목차 (요청 5)

- 목차 카드가 **'새 대화' 버튼과 대화 목록 사이**에 있다(`ShelfView.swift:288`). 어느 대화의 목차인지 시각적으로 애매하다.
- 다른 대화의 목차를 보려면 `대화 클릭 → 셸프 닫힘 → 셸프 다시 열기 → 목차 클릭` 또는 `대화 열고 오른쪽 레일` 이다.

> 사용자 요청 — *"그 대화 아래에 목차가 있어야 할 것 같아"*, *"퀵셀프에서 한 단계로 줄일 수 있으면 줄여줘"*

### 1.4 비서별 리포트 폴더 (요청 6)

- 비서가 `reportFolder` 를 지정하지 않으면 **모든 비서가 같은 기본 폴더 루트**를 쓴다(`Sources/QuickTalkCore/SystemKnowledge.swift:92`).
- 프롬프트는 "하위 폴더로 정리해도 된다"고만 한다(`SystemKnowledge.swift:100`). 강제가 아니므로 파일이 루트에 섞인다.

> 사용자 요청 — *"비서별 리포트 폴더 … 하위 폴더를 지가 만든다던지 … 하는게 좋지 않을까?"*

### 1.5 대화 전환 지연 (요청 7)

- 퀵셀프에서 다른 대화를 클릭하면 약 3초 멈춘다는 보고.
- **현재 설치본은 Debug 빌드**다(`~/Applications/QuickTalk.app/Contents/MacOS/QuickTalk.debug.dylib`, 2026-11-08 13:14). Debug SwiftUI는 Release보다 뷰 생성·레이아웃이 크게 느리다.
- 구조적으로도 대화 본문은 `ScrollView { VStack { ForEach(turns) } }` 로 **모든 턴을 즉시 렌더**한다(`ContentView.swift:699–710`). 메시지마다 `.textSelection(.enabled)` 가 붙는다.

---

## 2. 요구사항

### 모델 카탈로그

| ID | 요구 |
| --- | --- |
| R1 | 모델 선택 UI에서 ID뿐 아니라 **컨텍스트·출력·입력 형식·도구·추론 강도**를 보여 준다 |
| R2 | 모델 정보를 **캐시**해, 목록을 열 때 네트워크를 기다리지 않는다 |
| R3 | 새로고침 시점: 앱 실행(캐시 만료 시) · 프로바이더 전환(캐시 없음) · **수동 ⟳** |
| R4 | 네트워크 실패·오프라인에서도 **마지막 캐시**를 보여 준다 |
| R5 | 정보가 없는 모델은 "정보 없음"으로 표시하고, 선택을 막지 않는다 |
| R6 | 모델 정보 자동 업데이트를 끌 수 있다(외부 요청 0) |
| R7 | OpenAI 호환·Ollama·Apple FM 모두 같은 피커를 쓴다(Apple FM은 고정 안내) |

### 비서 모델

| ID | 요구 |
| --- | --- |
| R8 | 비서마다 프로바이더·모델을 고를 수 있고, **일반 대화와 예약 실행 모두**에 적용된다 |
| R9 | 비우면 설정 › AI의 활성 AI를 따른다(기존 동작과 호환) |
| R10 | 비서가 지정한 프로바이더가 없거나 꺼져 있으면 **활성 AI로 폴백**하고, 비서 편집에 경고를 보여 준다 |
| R11 | 모델 해석은 **한 곳**에서만 결정한다(전송·대화 정리·후속 질문·웹 판정·헤더 토큰 예산이 같은 값을 쓴다) |

### 퀵셀프 목차

| ID | 요구 |
| --- | --- |
| R12 | 목차는 **그 대화 줄 아래**에 붙어, 어느 대화의 목차인지 즉시 보인다 |
| R13 | 다른 대화의 목차를 **셸프를 다시 열지 않고** 펼칠 수 있다 |
| R14 | 목차 항목 클릭 → 그 대화 활성화 + 그 질문으로 스크롤 + 셸프 닫기 (총 **2동작**) |
| R15 | 펼친 목차가 잘리지 않게 자동 스크롤, 한 번에 하나만 펼침 |
| R16 | 대화 줄 클릭은 지금처럼 "그 대화 열기" (역할 분리) |

### 리포트 폴더

| ID | 요구 |
| --- | --- |
| R17 | 비서마다 기본 저장 폴더가 **자동으로 분리**된다(비서 폴더 미지정 시) |
| R18 | 사용자가 직접 지정한 폴더는 **그대로** 존중한다 |
| R19 | 경로 계산은 `SystemKnowledge`·`ScheduledRunRunner`·설정 화면이 **같은 함수**를 쓴다 |
| R20 | 기존 루트 파일을 **자동으로 옮기지 않는다**(파괴적 변경 금지) |

### 성능

| ID | 요구 |
| --- | --- |
| R21 | Release 빌드에서 11턴 대화 전환이 **체감 즉시**(목표: 첫 페인트 300ms 이내, M1 Max) |
| R22 | 개선 전후를 **측정값**으로 남긴다(추측 금지) |
| R23 | 목차·스크롤·강조 등 기존 기능의 동작이 변하지 않는다 |

---

## 3. 조사

### 3.1 현재 코드

| 경로 | 내용 |
| --- | --- |
| `LLMProvider.swift:495` | `OpenAIClient.listModels` → `[String]` (id만) |
| `LLMProvider.swift:695` | `OllamaClient.listModels` → `[String]` (name만) |
| `UIStore.swift:1109` | `modelOptions: [String]`, `loadingModels`, `modelNote` |
| `UIStore.swift:1114` | `activeModelChoices` — 저장된 모델 + 조회 목록 |
| `UIStore.swift:1142` | `refreshModels()` — **수동 호출만** |
| `UIStore.swift:1121` | `setActiveProvider` 가 `modelOptions = []` 로 비움 |
| `ProviderEditorSheet.swift:158` | 편집 시트의 별도 `loadModels()` (목록 중복 구현) |
| `Persona.swift:90–96` | `providerID`·`model` — "예약 실행에만 적용" 주석 |
| `SettingsView+Assistant.swift:466–486` | 라벨 `예약 실행에 사용할 AI` + "일반 대화는 설정 › AI" 캡션 |
| `UIStore.swift:1741` | 일반 전송이 `settings.activeProvider` 직접 사용 |
| `SystemKnowledge.swift:92` | `persona?.reportFolder ?? settings.reportFolderPath` |
| `ScheduledRunRunner.swift:180` | 같은 계산을 **다시** 구현 |
| `ShelfView.swift:288` | 목차 카드가 새 대화 버튼 아래, 목록 위 |
| `ShelfView.swift:312–370` | 목차는 **현재 대화**(`store.conversation`)만 계산 |
| `ShelfView.swift:373` | 점프도 현재 대화 ID로 고정 |
| `ContentView.swift:699–710` | 모든 턴 즉시 렌더(VStack) |

### 3.2 models.dev 실측 (2026-11-08)

`GET https://models.dev/api.json` — 235개 프로바이더, 5.9MB. `opencode` 프로바이더에 134개 모델.

```json
"deepseek-v4.1-flash-free": {
  "name": "DeepSeek V4.1 Flash Free",
  "tool_call": true, "reasoning": true, "attachment": true,
  "limit": {"context": 200000, "output": 32000},
  "modalities": {"input": ["text", "image"], "output": ["text"]},
  "reasoning_options": [{"type": "toggle"},
                        {"type": "effort", "values": ["low", "high", "max"]}]
}
```

- `glm-5.3-flash-free`: 200K/32K · text+image+video · tools · effort low/high/max
- `iceman-free`: 262K/131K · text · tools · effort 없음
- `big-pickle`: 200K/32K · text · tools · effort 없음
- **User-Agent가 없으면 403** (ZenFreeProxy 문서와 동일). 기존 `QuickTalkUserAgent` 를 쓴다.

### 3.3 캐시 크기

전체 5.9MB를 저장하지 않고, 현재 프로바이더의 모델에 매칭된 항목만 저장한다. 10~30개 모델 기준 **수십 KB**.

---

## 4. 설계

### 4.1 `ModelCatalog` (Core, 신규)

```swift
public struct ModelInfo: Codable, Hashable, Sendable {
  public var id: String
  public var name: String
  public var context: Int?
  public var output: Int?
  public var input: [String]      // text, image, video, pdf …
  public var toolCall: Bool
  public var reasoning: Bool
  public var attachment: Bool
  public var effort: [String]     // low, high, max …
}

public struct ModelCatalogEntry: Codable, Equatable, Sendable {
  public var baseURL: String
  public var fetchedAt: Date
  public var models: [ModelInfo]
}
```

- 저장 위치: `~/Library/Application Support/QuickTalk/model-catalog.json`
  - 디코드 실패 시 빈 카탈로그로 시작(파일은 `.corrupt` 로 보존하지 않아도 됨 — 재조회 가능)
  - 원자적 쓰기(기존 `PersistenceService` 패턴)
- 키: 프로바이더 `id` (baseURL 변경 시 무효화)
- TTL: **24시간** (`ModelCatalog.ttl`)

**조회 파이프라인**

1. `GET {baseURL}/models` → ID 목록 (기존 `listModels` 재사용)
2. models.dev 조회
   - `opencode` 프로바이더에서 ID 매칭
   - 없으면 235개 프로바이더를 ID로 검색해 **가장 정보가 많은 항목** 채택
   - 그래도 없으면 `ModelInfo(id:name:id)` — "정보 없음"
3. 병합 후 저장. **ID 순서는 서버 응답 순서 유지**(모델 제공자가 정한 순서)

**갱신 정책**

| 시점 | 동작 |
| --- | --- |
| 앱 실행 | 캐시 만료(24h)면 **백그라운드** 갱신. 화면은 캐시 즉시 표시 |
| 프로바이더 전환 | 해당 프로바이더 캐시가 없으면 1회 조회 |
| 모델 피커 열기 | **조회하지 않음** (캐시만) |
| 수동 ⟳ | 강제 조회 |
| 자동 업데이트 끔 | 앱 실행 자동 갱신 생략, 수동 ⟳만 |

**표시**
- `모델 24개 · 2026-11-08 19:10 기준`
- 만료: `오래된 목록 · 새로고침` 배지
- 실패: 마지막 캐시 유지 + `E-MAC-NET-0002` 한 줄(기존 코드 재사용)
- Ollama: `/api/tags` 에 크기·양자화 정보가 있으면 `details.parameter_size`·`quantization_level` 을 `ModelInfo` 확장 필드로 표시(선택)

### 4.2 모델 피커 + 상세 (App)

- `ProviderEditorSheet` 의 모델 `TextField` 를 **검색형 피커**로 교체. 직접 입력도 허용(서버가 목록에 없는 ID를 받는 경우).
- 상세는 시트 하단 고정 블록(폭 520pt에서 2단은 좁다):

```
┌ 모델 ─────────────────────────────────────┐
│ 🔍 검색…                                  │
│ ✓ DeepSeek V4.1 Flash Free      [무료]    │
│   Big Pickle                    [무료]    │
│   GLM-5.3-Flash Free            [무료]    │
├───────────────────────────────────────────┤
│ DeepSeek V4.1 Flash Free                  │
│ 200K context · 32K output                 │
│ 입력 Text·Image · Tools · 추론 low/high/max │
│ 참고: models.dev · 19:10 기준              │
└───────────────────────────────────────────┘
```

- 메뉴바 허브의 모델 드롭다운(`MenuBarHubView.swift:423`)도 같은 상세 한 줄을 툴팁/하단에 표시.
- `무료` 배지는 모델 ID가 `-free` 로 끝나거나 cost가 0일 때. **과장하지 않는다**(서버 정책이 바뀔 수 있음).
- 추론 강도는 **표시만** 한다. 실제 요청 파라미터는 §11 미해결.

### 4.3 비서 모델 (Core + App)

`Persona.providerID/model` 의 의미를 **"이 비서의 AI(대화+예약)"** 로 확장한다.

```swift
// Core — 테스트 가능한 순수 해석
public enum ProviderResolver {
  public static func resolve(settings: QuickTalkSettings, personaID: UUID?) -> LLMProviderConfig?
}
```

우선순위
1. 비서 `providerID` 가 유효하고 `enabled` → 그 프로바이더, `persona.model` 이 있으면 덮어씀
2. 비서에 `model` 만 있고 `providerID` 없음 → 활성 프로바이더 + 비서 모델
3. 그 외 → `settings.activeProvider`

적용 지점(전부 같은 함수 사용)
- `UIStore.send` 의 provider (현재 `UIStore.swift:1741`)
- 대화 정리 예산·요약 호출(`effectiveKeepTurns`, `makeSummary`)
- 후속 질문 생성
- 웹 검색 판정·`web_search` 도구 클라이언트
- 헤더 기억 토큰 진행률(프로바이더 예산)
- 연결 테스트는 **설정 › AI의 활성 AI** 그대로(그 화면의 목적이 활성 AI 확인)

UI
- 라벨 `예약 실행에 사용할 AI` → **`이 비서의 AI`**
- 캡션: `대화와 예약 실행에 모두 적용됩니다. 비우면 설정 › AI를 따릅니다.`
- 모델 칸은 §4.2 피커
- 프로바이더가 꺼져 있으면: `지정한 AI가 꺼져 있어 설정의 활성 AI로 동작합니다.` (주황 1줄)
- 비서 목록 행에 `개발e · DeepSeek V4.1 Flash` 배지(선택)

### 4.4 퀵셀프 목차 — 대화 줄에 붙는 아코디언 (App)

```
＋ 새 대화
┌───────────────────────────────────────────┐
│ 🧠 IINA kill 시키는…            ✓  목차 11 ⌄ │  ← 활성 대화 기본 펼침
│    • 최소화는 못하나?                       │
│    • --mpv-window-minimized=yes 동작 안하네 │
│    • killall IINA                           │
│    … 외 5개                                 │
└───────────────────────────────────────────┘
│ 🔎 iPhone 이 내년에 20주년인가?      목차 4 › │
│ 🦉 테크충이 얼마나…                  목차 3 › │
```

- 독립 카드(`shelfOutlineSection`) 제거 → `chatRow` 안/아래로 이동
- `@State private var expandedOutlineID: UUID?`
  - 셸프를 열 때 **활성 대화가 펼쳐진 상태**(질문 3개 이상일 때)
  - 다른 대화의 `목차 N` 을 누르면 그 대화만 펼침(활성 대화는 접힘)
  - 대화를 전환해도 셸프는 닫지 않음(목차를 보는 중에는)
- 줄 오른쪽 `목차 N` 은 호버 시 진하게, 클릭 영역은 아이콘보다 넓게(기존 `⋯` 패턴)
- 항목 클릭:
  ```swift
  store.openConversation(c, focusTurnID: entry.id)  // 신규
  onClose()
  NotificationCenter.default.post(name: .quickTalkOpenChat, object: nil)
  ```
  - `openConversation` 은 활성화 후 `searchFocus` 설정(현재 `searching:` 경로와 같은 소비자)
- 아래쪽 대화를 펼치면 `ScrollViewReader.scrollTo(c.id, anchor: .top)`
- 목차가 없는 대화(질문 2개 이하)는 `목차` 버튼을 숨긴다(`ConversationOutline.minimumQuestions`)
- 성능: 펼친 대화만 `ConversationOutline.entries` 계산. 접힌 줄은 질문 수만 센다.
- 키보드: `목차` 버튼은 Tab으로 닿고, Esc는 셸프 닫기(기존)

### 4.5 비서별 리포트 폴더 (Core + App)

```swift
public enum PersonaReports {
  /// 비서 이름 → 안전한 폴더명(공백·/·: 제거, 24자, 중복 시 ID 앞 4자)
  public static func folderName(for persona: Persona, all: [Persona]) -> String
  /// 최종 저장 경로. 비서가 직접 지정했으면 그 경로 그대로.
  public static func folder(settings: QuickTalkSettings, persona: Persona?) -> String
}
```

```
~/Documents/Reports/            ← 설정의 기본 폴더(기존)
├── 개발e/                      ← 비서 폴더 미지정 시 자동
├── 테크충/
└── (루트 파일)                 ← 비서 없는 대화
```

- 비서가 직접 지정한 `persona.reportFolder` → **그대로** (하위 폴더를 강제로 붙이지 않음)
- 이름 충돌: `개발e` / `개발e` → 뒤에 `-3F2A`(ID 앞 4자)
- 앱이 전송·예약 실행 시점에 `createDirectory` (에이전트 승인 불필요)
- 프롬프트: `[리포트 폴더] - 쓰기 가능한 경로: …/개발e` + "이 폴더가 이 비서의 폴더다"
- 설정 화면 캡션: `저장 위치: ~/Documents/Reports/개발e`
- 두 비서가 **같은 폴더를 명시**하면 경고: `여러 비서가 같은 폴더를 씁니다.`
- 기존 루트 파일은 이동하지 않는다. 필요하면 후속으로 `기존 리포트 정리` 1회성 도구(확인 시트).

### 4.6 대화 전환 지연 (측정 → 수정)

**P0 — 코드 변경 없이 측정**
1. Release 빌드로 같은 대화 전환 5회, 체감·시간 기록
2. Debug/Release 차이가 크면 → 배포 정책만으로 해결(일상 사용은 Release)

**P0-2 — 계측(필요 시)**
- 실행 인자 `--perf-switch` 로 다음 구간을 `NSLog`:
  - `openConversation` 진입→`activateSession` 완료
  - 대화 본문 첫 레이아웃(`onAppear`)
  - 셸프 `loadArchive` (파일 디코드)
- 로그에는 **ID·ms만** (대화 내용 금지)

**가설과 수정(측정 결과에 따라 선택)**

| 가설 | 근거 | 수정 |
| --- | --- | --- |
| Debug 빌드 | 설치본에 `QuickTalk.debug.dylib` | Release 배포 |
| 모든 턴 즉시 렌더 | `ContentView.swift:700` VStack | 첫 화면만 먼저 + 나머지 다음 프레임 / LazyVStack(목차 좌표 대체) |
| 셸프 열 때마다 디스크 디코드 | `ShelfView.swift:307` `loadArchive()` | mtime 캐시 + 백그라운드 |
| 메시지마다 텍스트 선택 | `ContentView.swift:863` 등 | 범위 축소(컨테이너 1곳) |
| 마크다운 재파싱 | `MarkdownText.init` | 텍스트 해시 캐시 |

**합격 기준**
- Release, 11턴 대화: 전환 후 **첫 페인트 ≤ 300ms**(5회 중앙값)
- 목차 현재 위치·스크롤·깜빡임 회귀 없음

---

## 5. 대안 비교

### 5.1 모델 메타데이터 출처

| 안 | 장 | 단 | 결정 |
| --- | --- | --- | --- |
| A. 프록시가 메타를 내려줌 | 앱 단순 | ZenFreeProxy 수정 필요, 다른 프로바이더에는 없음 | 기각(범용성) |
| B. models.dev (OpenCode 방식) | 235개 프로바이더·풍부한 필드 | 5.9MB, 외부 의존 | **채택** + 서브셋 캐시 |
| C. 앱에 하드코딩 | 네트워크 0 | 모델 추가마다 앱 업데이트 | 기각 |

### 5.2 퀵셀프 목차

| 안 | 장 | 단 | 결정 |
| --- | --- | --- | --- |
| A. 현재 카드 위치만 이동 | 최소 수정 | 다른 대화 목차는 여전히 3동작 | 기각 |
| B. 대화 줄 아코디언 | 2동작, 위치 명확 | 행 높이 증가 | **채택** |
| C. 대화 클릭 시 셸프 유지 + 목차 갱신 | 2동작 | "클릭=열기" 관성이 깨짐 | 보류(설정 옵션) |
| D. 호버 미리보기 패널 | 0클릭 | 오조작·발견성 낮음 | 보류 |

### 5.3 리포트 폴더

| 안 | 장 | 단 | 결정 |
| --- | --- | --- | --- |
| A. 비서별 하위 폴더 자동 | 명확, 마이그레이션 불필요 | 경로가 한 단계 깊어짐 | **채택** |
| B. 파일명에 비서 이름 prefix | 폴더 유지 | 목록에서 지저분, 여전히 섞임 | 기각 |
| C. 기본 폴더를 비서별로 강제 변경 | 완전 분리 | 사용자가 고른 폴더 무시 | 기각 |

---

## 6. 데이터·마이그레이션

- `model-catalog.json` 신규. 기존 설정·대화와 무관, 삭제해도 재조회.
- `Persona` 스키마 변경 **없음** — 기존 `providerID/model` 재사용. 의미만 확장.
- 리포트: 새 파일부터 하위 폴더. 기존 파일 이동 없음.
- v0.33·v0.34 병합 후 분기해 충돌을 줄인다.

---

## 7. i18n (예상 신규 키)

한/영 동시 추가(`LocalizationTable.swift`, 커버리지 테스트가 강제):

- `이 비서의 AI` / `대화와 예약 실행에 모두 적용됩니다. 비우면 설정 › AI를 따릅니다.`
- `지정한 AI가 꺼져 있어 설정의 활성 AI로 동작합니다.`
- `모델 정보 자동 업데이트` / `모델 %d개 · %@ 기준` / `오래된 목록`
- `컨텍스트` / `출력` / `입력` / `도구` / `추론` / `정보 없음` / `참고: models.dev`
- `목차 %d` / `목차 보기` / `목차 접기`
- `저장 위치: %@` / `여러 비서가 같은 폴더를 씁니다.`
- `이 비서의 리포트 폴더` (캡션)

---

## 8. 테스트 계획

**Core (`swift test`)**
- `ModelCatalogTests`: 디코드/인코드 왕복 · TTL 경계 · baseURL 변경 무효화 · ID 매칭 우선순위(opencode → 전체) · 정보 없는 모델 폴백 · 서버 순서 유지
- `PersonaReportsTests`: 비서 폴더명 정리(`/`·공백·길이) · 중복 접미사 · 커스텀 경로 우선 · 비서 없음=루트 · `~` 확장
- `ProviderResolverTests`: 비서 provider/model 우선순위 · 꺼진 프로바이더 폴백 · 모델만 지정 · 전부 없음

**App**
- `--session-test`에 QA 케이스 추가(모델 해석이 대화·예약에서 같은지)
- 오프스크린 렌더: 모델 피커 상세, 퀵셀프 아코디언(펼침/접힘, 아래쪽 대화), 리포트 폴더 캡션 — 한/영 × 다크/라이트

**수동 QA**
- 모델: 캐시 있음/없음, 네트워크 차단, 만료 배지, 수동 ⟳
- 비서: 코딩 비서=코딩 모델로 대화·예약 실행, 꺼진 프로바이더 폴백
- 리포트: 비서 3명이 각자 폴더에 저장, 루트에 안 섞임, 커스텀 폴더 유지
- 퀵셀프: 다른 대화 목차 펼침 → 질문 클릭 → 그 대화 그 턴으로 이동(2동작)
- 전환: Release에서 11턴 대화 5회 전환 시간

---

## 9. 단계·브랜치

| 단계 | 내용 | 브랜치 | 규모 |
| --- | --- | --- | --- |
| P0 | Release로 전환 지연 재측정 (코드 0) | — | XS |
| P1 | Core `ModelCatalog` + 캐시 + 테스트 | `feat/v0.35-model-catalog` | S~M |
| P2 | 모델 피커·상세 UI (편집 시트 + 허브) | 〃 | M |
| P3 | `ProviderResolver` + 비서 모델 UI | 〃 | M |
| P4 | `PersonaReports` + 프롬프트·캡션 | `fix/v0.35-shelf-outline` | S |
| P5 | 퀵셀프 목차 아코디언 + 2동작 이동 | 〃 | S~M |
| P6 | 전환 성능 수정(측정 결과에 따라) | `perf/v0.35-chat-switch` | 0~M |

각 단계 종료 시 `swift test` + Debug/Release `xcodebuild` + 문서 갱신. PR은 단계별 또는 브랜치별 squash merge.

---

## 10. 위험·한계

- **models.dev 의존**: 서비스 장애·스키마 변경 시 상세가 비어도 **모델 선택은 계속 동작**해야 한다. 캐시·폴백 필수.
- **메타데이터 불일치**: 프록시가 실제로 제공하는 모델과 models.dev 설명이 다를 수 있다(양자화·버전). "참고 정보"로 표기하고 차단하지 않는다.
- **비서 모델 확장**: 예산·정리·후속 질문이 활성 AI 기준으로 남으면 토큰 계산이 어긋난다 → R11을 테스트로 고정.
- **리포트 경로 변경**: 사용자가 "리포트가 사라졌다"고 느낄 수 있다 → 에디터에 실제 경로 표시, 기존 파일 미이동, 필요 시 정리 도구.
- **퀵셀프 높이**: 목차를 펼치면 목록이 길어진다 → 한 번에 하나·자동 스크롤·최근 6개 유지.
- **성능**: LazyVStack은 목차 좌표를 깨뜨릴 수 있다. 측정 전에는 손대지 않는다.

---

## 11. 미해결 질문

1. 비서 모델을 `대화`와 `예약 실행`으로 **분리**할 필요가 있는가? (제안: 통합, 기존 예약 전용 사용자는 그대로 동작)
2. 비서 없는 대화의 리포트를 루트에 둘까, `기본/` 하위로 둘까? (제안: 루트 유지 — 기존 동작)
3. 기존 루트 리포트를 비서별로 옮기는 **1회성 도구**가 필요한가?
4. 추론 강도(`low/high/max`)를 실제 요청에 보낼 것인가? 프로바이더별 파라미터 지원 확인 후 별도 결정.
5. 모델 정보 자동 갱신 주기 24시간이 적절한가? (수동 ⟳ 항상 제공)

---

## 12. 완료 기준 (DoD)

- [ ] R1~R21 충족, `swift test` 전체 통과(신규 테스트 포함)
- [ ] Debug/Release `BUILD SUCCEEDED · 경고 0`
- [ ] 한/영 번역 커버리지 통과
- [ ] 오프스크린 QA 렌더(모델 피커·퀵셀프 아코디언·비서 폴더 캡션)
- [ ] Release 전환 시간 측정값 기록
- [ ] TODO·CHANGELOG·HANDOFF·DESIGN 갱신
- [ ] 사용자 실측 후 병합·배포(별도 확인)
