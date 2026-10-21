# PLAN_v0.10_settings-hub_macos.md
> 생성일: 2026-10-19 | 플랫폼: macos | 작성자: OpenCode
> 목표: AI 프로바이더를 확장 가능한 목록으로 전환 + 설정 창·메뉴바를 ApexKey 형식으로 재설계

## 1. 목표 (1줄)
LLM 프로바이더를 "고정 3종"에서 "추가 가능한 목록 + 활성 프로바이더 선택"으로 바꾸고,
설정 창과 메뉴바 좌클릭 Hub를 `/Users/lee/Documents/Apps/ApexKey` 형식으로 교체한다.

## 2. 사용자 지시 (원문 요지)
1. AI 설정 3종 등록 — Local Apple FM / Local Ollama / Remote OpenAI 호환. **계속 추가 가능**해야 함
2. Remote OpenAI 호환: Addr `http://192.168.86.30:8791/v1` + Key(사용자 제공) — 키는 **키체인 저장**([HARD] 8)
3. 기본 프로바이더 = **Apple FM**
4. 설정 창이 마음에 안 듦 → ApexKey 형식으로 변경. "기본 설정 + 모든 설정 보는 형식"
5. 메뉴바 구성도 ApexKey와 동일하게

## 3. 범위
- 모델: `LLMProviderType` + `LLMProviderConfig`(id/name/type/baseURL/model/keychainAccount/enabled) 도입, `QuickTalkSettings.providers[]` + `activeProviderID`
- 마이그레이션: 구버전 단일 프로바이더 설정(JSON) → 목록형으로 자동 승계. 기존 키체인 계정 승계
- 설정 창: 커스텀 사이드바 + 도움말 카드(뭐고·언제·이렇게) + groupBox 카드 + 라벨 좌/컨트롤 우 행 규칙
- 메뉴바: 좌클릭 = Hub 팝오버(실행/설정 2탭), 우클릭 = 컨텍스트 메뉴
- Hub 설정 탭 = 기본 설정(빠른 토글 + 활성 AI 선택) + "모든 설정 열기" → 전면 설정 창

## 4. ApexKey 형식 대응표 (근거)
| ApexKey | QuickTalk 적용 |
|---|---|
| `SettingsView` 커스텀 사이드바(190pt, 아이콘+라벨, 액센트 하이라이트) | 동일 |
| `FeatureHelpCard`(what/when/how 3줄) | 탭별 도움말 카드 한국어 문구 |
| `groupBox(title)` + `toggleRow` + 들여쓰기 캡션 | 동일 헬퍼 이식 |
| 좌클릭 `MenuHubView`(실행/설정 2탭, hero 버튼, 최신 실행 행) | 좌클릭 Hub: hero=새 대화, 최신 행=최근 대화 |
| 설정 탭: "모든 설정 열기" 카드 + quick Toggle 4종 + 힌트 | 동일 구조(토글은 QuickTalk 항목) |
| 우클릭 `buildMenu()`(패널 열기/정보/설정…/업데이트/종료) | 우클릭 메뉴(대화/보관함/설정…/정보/종료) |

## 5. 성능 예산
- budgets.json 준수: Cold Start ≤1.5s, 메모리 ≤300MB. Hub 팝오버는 지연 생성(최초 클릭 시)
- 원격 모델 목록 조회는 사용자가 "불러오기"를 눌렀을 때만 수행(상주 요청 금지)

## 6. 에러 코드
- 기존: E-MAC-NET-0001, E-MAC-MODEL-0001, E-MAC-AUDIO-0001, E-MAC-RENDER-0001
- 추가: `E-MAC-KEY-0001`(키 없음/키체인 실패), `E-MAC-NET-0002`(프로바이더 미설정·모델 미선택)

## 7. 검증 계획
- `swift test` (Core unit) — 기존 7개 유지 + 신규 프로바이더 테스트
- `xcodebuild` 빌드 → `~/Applications/QuickTalk.app` 복사 → smoke 실행
- 실측: Apple FM 응답, Ollama 응답, Remote OpenAI 호환 응답(3종 모두 이미 실호출 확인 완료)

## 8. 실행 스펙 (UI 고정값)
- 설정 창: min 700x460, 사이드바 190pt, 탭 = 일반/단축키/AI/음성/보관함/정보
- Hub 팝오버: 340x492 콘텐츠 + 10 패딩, radius 16, 실행/설정 탭
- 프로바이더 기본 3종 ID: `local-apple-fm`(활성 기본), `local-ollama`, `remote-openai`

## 9. 범위 구분 (workflow §6)
- 앱 소유: 프로바이더 설정·키체인 항목·Hub/설정 창 UI
- 시스템 공유물(전제조건+게이트): Ollama 데몬(`ollama serve`), 원격 OpenAI 호환 서버(192.168.86.30:8791), Apple Intelligence 모델. 미준비 시 앱은 실패 문구를 표시하고 목업으로 숨기지 않음

## 10. 리스크
- 원격 서버는 비-loopback 요청에 토큰을 요구함(E-AND-AUTH-0004) → 키 필수. 키 미저장 시 사용자에게 문구 표시
- Ollama 기본 모델명은 사용자 머신 실보유 모델(`Local-Qwen2.5-32B:latest`)로 시드, 설정에서 "설치된 모델 불러오기"로 교체 가능

## 11. 결정 변경 (2026-10-19, 사용자 지시)
- **키체인 폐기 → 로컬 파일**: ad-hoc 서명이라 키체인 접근 허용 창이 실행마다 떠서 사용자가 중단 지시.
  `SecretStore`(`~/Library/Application Support/QuickTalk/secrets.json`, 600)로 대체, 설정에는 `secretID`만 저장.
- 설정 창은 SwiftUI `Settings` 씬 대신 **전용 NSWindow**로 관리(메인 메뉴 교체 시 씬 셀렉터가 열리지 않는 문제 회피).
- QA 플래그 추가: `--open-settings`, `--settings-tab=<탭>`, `--open-hub`, `--hub-tab=<run|settings>`, `--selftest=<프로바이더ID>`.

## 12. 검증 결과 (2026-10-19)
- `swift test` 21/21 통과 (기존 11 + 프로바이더·마이그레이션·SecretStore 10)
- `xcodebuild` BUILD SUCCEEDED → `~/Applications/QuickTalk.app` 배포, smoke ERROR 0
- 앱 내부 경로 실호출 자가진단 3종 통과: `local-apple-fm` OK / `remote-openai` OK / `local-ollama` OK
- 화면 확인: Hub 실행 탭, Hub 설정 탭(기본 설정 + 모든 설정 열기), 설정 창 일반 탭·AI 탭(3종 목록 + "키 저장됨")
- 미검증: Hub 각 행의 실제 클릭 동작(합성 클릭이 팝오버에 전달되지 않아 코드·스크린샷까지만 확인), 대화 1턴 E2E


## 13. 마무리 수정 (2026-10-19, 사용자 지시 "바탕화면 클릭 후 단축키 동작 무" + 설정 정렬)
- **전역 단축키**: `NSEvent` 전역 모니터(입력 모니터링 권한 필요, 권한 없으면 조용히 무응답) → Carbon `RegisterEventHotKey`로 교체.
  `GlobalHotKey`(호출 단축키 + 임시 단축키 토큰 관리), 설정 > 단축키에 `전역 등록: 동작 중/실패` 표시.
  검증: Finder(바탕화면) 활성 상태에서 Cmd+Space → 대화 창 열림 + 입력한 텍스트가 창에 들어감, 로그 `전역 단축키 등록 완료/창 표시: isActive=Y isKey=Y`.
- **포인터 모드**: 메뉴바에서 열면 커서가 메뉴바 위라 애매하게 붙던 문제 → `.mousePointer`일 때만 0.6초 타이머로 직전 커서 위치를 기억(`pointerCache`)하고
  현재 커서가 작업 영역 밖(메뉴바·Dock)이면 기억값 사용, 없으면 화면 중앙 폴백. `--panel-position=<center|mousePointer>` QA 플래그 추가.
  검증: 커서 (700,500) 고정 후 실행 → `창 배치: 포인터 모드 origin=(470, 373)` = 커서 중심, AX position/size 일치.
- **표시 시 활성화**: 창만 뜨고 앱이 앞으로 오지 않던 문제 → `activateApp()`(NSApp.activate + NSRunningApplication 보강), 0.35초 후 isActive 재확인.
- **설정 창 정렬**: 픽커가 카드 오른쪽 끝에 붙지 않고 프레임 가운데에 떠 있던 문제 → `pickerRow`를 `frame(minWidth:180, maxWidth:280, alignment:.trailing)`,
  보관함 `보관일수` Stepper도 라벨 좌/컨트롤 우 규칙으로 정리. 화면 확인: 일반/단축키/AI/음성/보관함 5탭.
- **편집 단축키(⌘C/V/X/A/Z)**: LSUIElement(메뉴바 없음) 앱은 ⌘ 키 등가가 macOS 정책상 불안정하게만 앱에 전달된다.
  우리 창이 키일 때만 Carbon으로 일시 등록 + 로컬 키 모니터(키코드 비교, 한글 입력 소스 대응)로 보강.
  검증: 등록/해제 로그 확인(`편집 단축키 등록: 6개`), 해제는 창이 키를 잃을 때. 실키 ⌘V 붙여넣기는 사용자 확인 필요(합성 ⌘V는 OS 라우팅이 달라 재현 불가).
- `swift test` 22/22, BUILD SUCCEEDED, `~/Applications/QuickTalk.app` 재배포(19:15).

## 14. 검증 마감 + 표시 정책 수정 (2026-10-19, 사용자 확인)
- **T-13 마감**: 실키보드로 대화 창 ⌘V/⌘C/⌘A/⌘Z 전부 정상 동작(사용자 확인). `setActivationPolicy(.regular)` 전환은 불필요 → 현재 Carbon 임시 등록 + 로컬 모니터 방식 유지.
  (참고: unified log는 NSLog `%@` 인자를 `<private>`로 마스킹해 문자열 대조가 불가 → 판정 근거는 사용자 실동작)
- **Hub 팝오버 실제 클릭 확인**: 실행 탭 `새 대화`·최근/진행 중 대화 행, 설정 탭 토글·활성 AI 드롭다운·`모든 설정 열기`, 우클릭 컨텍스트 메뉴 모두 정상(사용자 확인).
- **대화 1턴 E2E 확인**: 실제 전송/응답 1턴 성공(사용자 확인).
- **표시 정책 수정 (사용자 지시)**: "메뉴바에서 숨김을 하면 Dock 표시를 자동 활성화해야 하는 것 아니냐" →
  기존 동작은 둘 다 숨김 요청 시 메뉴바를 조용히 유지하고 `NSLog` 경고만 남겨 UI와 실제 상태가 어긋났음.
  정책을 **진입점 최소 1개 보장**으로 확정:
  - `QuickTalkSettings.setMenuBarIcon(_:)` — 메뉴바 숨김 시 `showDockIcon = true`
  - `QuickTalkSettings.setDockIcon(_:)` — Dock 숨김 시 `showMenuBarIcon = true`
  - `QuickTalkSettings.normalizeVisibility()` — 저장값이 둘 다 숨김이면 Dock ON으로 자가치유(로드 시 1회)
  - `UIStore.setMenuBarIcon/setDockIcon` + `visibilityHint` 안내 문구(설정 일반 탭·Hub 설정 탭 공용)
  - `applyVisibility`의 E-MAC-RENDER-0001 경로는 정책 위반 상태가 저장될 수 없어 방어선으로만 유지
- 검증: `swift test` **26/26**(T-14 신규 4), BUILD SUCCEEDED, `~/Applications/QuickTalk.app` 재배포 후 사용자 확인.
