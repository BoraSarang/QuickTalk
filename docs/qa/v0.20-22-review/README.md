# v0.19–v0.22 코드 점검 · 오프스크린 렌더 (2026-10-25)

> 대상: `f753dbb`(main) + 브랜치 `fix/macos-p1-review`
> 목적: **배포 없이** 코드 점검 + 오프스크린 렌더로 화면 회귀 확인 → 찾은 결함 중 **P1 3건만** 수정.
> 사용자 맥 사용 중이라 **앱 실행·창 조회·스크린샷·터미널 열기는 하지 않았다.** 점검·렌더는 배포 없이 했고,
> P1 3건 수정 후 **사용자 요청으로 2026-10-25 20:51 배포**(`~/Applications/QuickTalk.app`, SHA-256 `537e570d…`).
> 사용자 실측 항목은 `docs/qa/v0.20-22/CHECKLIST.md`(29항목)에 그대로 남아 있다.

---

## 1. 점검 범위

| 영역 | 파일 |
|---|---|
| 터미널 인계 (v0.20) | `Sources/QuickTalkCore/TerminalHandoff.swift` · `QuickTalkApp/TerminalHandoffService.swift` |
| 대화별 권한 (v0.22) | `Sources/QuickTalkCore/AgentOverride.swift` · `QuickTalkApp/SettingsView+Tools.swift` |
| 앱 지식 (v0.22) | `Sources/QuickTalkCore/SystemKnowledge.swift` |
| 정책·실행 | `Sources/QuickTalkCore/PolicyEngine.swift` · `Sources/QuickTalkCore/SandboxRunner.swift` · `QuickTalkApp/AgentExecutor.swift` · `QuickTalkApp/AgentRunner.swift` |
| 되돌리기 (v0.19 WIP) | `Sources/QuickTalkCore/UndoStack.swift` · `TrashRewrite.swift` · `WriteScope.swift` |
| 슬래시·Shortcuts (v0.21) | `Sources/QuickTalkCore/SlashCommand.swift` · `QuickTalkApp/QuickTalkIntents.swift` |
| 창 연결 | `QuickTalkApp/WindowAttachmentService.swift` |
| 화면 | `QuickTalkApp/AgentCard.swift` · `SettingsView+Tools.swift` · `ContentView.swift` |

---

## 2. P1 수정 3건 (이번 브랜치)

### P1-1 되돌리기 기록이 등록되지 않음 — [되돌리기]가 **항상 실패**

- **증상**: 쓰기 실행 후 카드의 [되돌리기] → `기록을 찾지 못했습니다`.
- **원인**: `AgentExecutor.executeShell` 이 `UndoStack.snapshot()` 만 부르고 `commit()` 을 부르지 않았다.
  `snapshot()` 은 백업 폴더만 만들고 `entries` 에 넣지 않았으므로 `undo(id:)` 가 **항상 notFound**.
  부수 효과로 `trim()`·`save()` 도 돌지 않아 **백업 폴더가 무한정 쌓였다**.
- **근거(재현)**: 임시 테스트에서 `[PROBE] notFound=true entryFound=false` 확인 후 테스트 삭제.
- **수정**:
  - `UndoStack.snapshot()` 이 **스냅샷 시점에 스스로 등록**(`register`). 호출부가 commit 을 잊어도 되돌릴 수 있다 — 결함 부류를 원천 차단.
  - `commit()` 을 **멱등**으로 변경(같은 id 는 교체, 중복 삽입 없음).
  - `AgentExecutor` 는 성공 시 `commit`, **실패·중단 시 `discard`**(쓸모없는 백업을 남기지 않음).
  - `undo(id:)` 의 `undoneAt` 은 **전부 성공했을 때만** 설정(일부 실패면 다시 시도 가능).
- **검증**: `testSnapshotAloneIsUndoable` · `testCommitIsIdempotent` 추가.

### P1-2 긴 제목 + 기본 폭에서 헤더의 `⌘Space` 가 세로로 붕괴

- **증상**: 창 기본 폭(460pt)에서 제목이 길면 헤더가 **6줄**(약 170pt)로 커지고 `⌘Space` 라벨이 한 글자씩 세로로 쌓였다.
- **원인**: `Text(shortcutLabel)` 에 `lineLimit`·`fixedSize` 가 없어 SwiftUI 가 폭 압축 시 **글자 단위로 줄바꿈**했다.
- **수정**: `ViewThatFits(in: .horizontal)` 로 감싸 **한 줄로 들어갈 때만 라벨을 보이고**, 안 들어가면 라벨을 숨긴다(제목이 줄어든다). 넓은 창·짧은 제목에서는 종전과 동일.
- **검증(오프스크린)**: `after-fix/chat-long-title-ko.png`(긴 제목 → 헤더 1줄, `⌘Space` 유지) · `after-fix/chat-short-title-ko.png`(짧은 제목 → 기존과 동일).

### P1-3 [중단]·시간 초과가 **자식 프로세스를 남김**

- **증상**: 실행 중 [중단]을 눌러도 `sandbox-exec` 아래 명령이 계속 돌았다.
- **원인**: `Process.terminate()` 는 앱이 띄운 `sandbox-exec` **한 개만** 종료한다. 그 아래 `/bin/sh`·손자 프로세스는 고아가 되어 살아남는다.
- **근거(실측)**: `sandbox-exec` 부모 종료 후 자식 `sleep 30` **생존** 확인.
- **수정**: `SandboxRunner.terminateProcessTree(_:)` 신설 — `libproc`(`proc_listpids`·`proc_pidinfo`)로 **부모 PID 트리**를 모아 깊은 자식부터 `SIGTERM` → 200ms 뒤 남은 것만 `SIGKILL`. [중단]·시간 초과 두 경로가 모두 이 함수를 쓴다(상한 512개, 순환 방지).
- **검증**: `Tests/QuickTalkCoreTests/ProcessTreeTests.swift` 신규 — `/bin/sh -c "sleep 30.7 & wait"` 의 자식을 실제로 종료하는지 확인(사용자 프로세스와 겹치지 않게 고유 인자).

### 공통 검증

| 항목 | 결과 |
|---|---|
| `swift test` | **502/502**(6 skip = `QT_LIVE` 4 + `QT_LIVE_STREAM` 2) — 수정 전 499 |
| `xcodebuild` | **BUILD SUCCEEDED** |
| 경고 | 2건 그대로 — `AgentExecutor.swift:217`(불필요 `await`, 이번에 `trashRoot` 1건 제거) · `UIStore.swift:940`(P2 백로그) |
| 오프스크린 렌더 | `after-fix/` 5장 — 대화(긴/짧은 제목)·설정 일반·QuickShelf·마크다운 |
| 배포 | **2026-10-25 20:51** — `~/Applications/QuickTalk.app` 교체 · `codesign --verify --strict` OK · SHA-256 `537e570d19c25be0…` · **앱 재실행 필요**(실행 중 앱은 10-23 빌드) |

---

## 3. 렌더 견본

| 파일 | 무엇을 보는가 |
|---|---|
| `settings-tools-ko.png` · `settings-tools-en.png` | 설정 › 도구 — 권한 3단계·자동 수락·제한 시간·허용 규칙·실행 기록. 한/영 문구 폭 |
| `chat-agent-ko.png` | 실행 카드(명령·출력·권한 배지·경과) + 답변 푸터 |
| `chat-agent-write-ko.png` · `-en.png` | 쓰기 실행 카드 + [되돌리기] 노출 위치 |
| `chat-short-title-ko.png` | 짧은 제목 헤더(수정 전 상태) |
| `after-fix/chat-long-title-ko.png` | **P1-2 수정 후** 긴 제목 — 헤더 1줄 |
| `after-fix/chat-short-title-ko.png` | **P1-2 수정 후** 짧은 제목 — 종전과 동일 |
| `after-fix/{settings-general,shelf,markdown}-ko.png` | 수정이 다른 화면을 건드리지 않았는지 스모크 |

렌더 명령(참고):

```
build/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk \
  --render=<dir> --lang=korean|english --theme=light \
  [--demo-agent|--demo-agent-write|--demo-chat] [--settings-tab=tools] [--render-tall]
```

---

## 4. P2 백로그

> 2026-10-29 갱신 — **P2 백로그 12건 모두 완료**(#1·#2·#3·#4·#5·#6·#7·#8·#9·#10·#11·#12 + 덤 2).

| # | 항목 | 위치 | 상태 |
|---|---|---|---|
| 1 | 영어 번역 누락 **74곳** | `LocalizationTable.swift` 등 | ✅ **완료** — 재검사에서 **94곳**이 더 나왔다. 손보충 대신 `LocalizationCoverageTests`(리터럴 커버리지 · 보간 금지 · 한글 잔존 · 스캐너 자기검증)로 구조 고정 + 94건 보충 · PR #44 `484ac12` |
| 2 | 규칙 테스터 캡션에 `**` 노출 | `SettingsView+Tools.swift` | ✅ **완료** — 문구에서 `**` 제거 + `caption(L("…**…"))` 를 잡는 소스 스캔 가드 · PR #45 `8039493` |
| 3 | `screenshot` 이 "읽기 매번 확인" 설정을 무시 | `AgentExecutor` | ✅ **완료** — Core `AgentToolPermission`(도구→권한 단계) 신설, `read_file`·`screenshot` 이 같은 판정. 거부 시 카드·감사 기록 · PR #46 `28054bd` |
| 4 | 샌드박스 프로필 경로 미이스케이프 | `SandboxRunner` | ✅ **완료** — `profilePath(_:)` 로 `\`·`"` 이스케이프 + 제어문자 제거. `/private/tmp` 실측: `qt "q"`·`qt\b`·`qt (1) space` 쓰기 성공 · PR #46 `28054bd` |
| 5 | `usleep` 폴링 | `SandboxRunner`·`TerminalHandoffService` | ✅ **완료** — `SandboxCancellation.addCancelHandler` 로 취소 시 **즉시** 트리 종료(폴링 대기 없음) · 종료 대기는 `terminationHandler`+`DispatchSemaphore` · `terminateProcessTree` 는 자손 소멸 즉시 반환(10ms 확인, 상한 200ms). `TerminalHandoffService` 에는 `usleep` 없음(확인) · PR #52 `066232b` |
| 6 | `matchesRule` 의 `hasPrefix` 과매칭 | `PolicyEngine` | ✅ **완료** — 경계(`pattern + " "`)만 인정. `/tmp/a` vs `/tmp/ab`·`ls` vs `lsof` 회귀 테스트 · PR #46 `28054bd` |
| 7 | 규칙 테스터가 쓰기를 **실행 단계**로 판정 | `PolicyEngine` | ✅ **완료** — `PolicyEngine.stagePreview` 가 **실행 없이** 읽기/쓰기/실행 3단계 판정을 모두 반환 · UI 단계별 칩 + 실측 안내 · 상승 권한은 단일 판정 · 6개 테스트 · PR #52 `066232b` |
| 8 | 스크린샷 후 **원 첨부 대체** | `AgentRunner` | ✅ **완료** — `attachments + images`(예전엔 스크린샷이 있으면 `images` 만 전송). 되돌리면 실패하는 회귀 테스트 · PR #45 `8039493` |
| 9 | `SlashCommands.all` static 고정 | `SlashCommand.swift` | ✅ **완료** — 계산 프로퍼티 + `available(agentToolsEnabled:)` + `requiresTools`(설정·도움말만 도구 없이) · PR #45 `8039493` |
| 10 | `UIStore.swift:940` 경고 | `UIStore` | ✅ **완료** — `markInterruptedQuestion()` 의 `appendAssistant` 결과를 `_ =` 로 받아 경고 제거(되돌리면 `UIStore.swift:950` 재현). Debug 경고 0 · PR #52 `066232b` |
| 11 | **슬래시 팔레트가 설정 언어와 반대로 표시** (2026-10-28 사용자 보고) | `ContentView.slashPalette`·`SlashCommand` | ✅ **완료** — 측정 결과 역전이 아니라 **명령 이름이 한국어 리터럴**이었다(`/화면` 이 영어 UI 에도 남음). `id` 분리 + `name` 번역 + 한/영 별칭 · 532/532 · `docs/qa/palette-lang-2026-10-29/` |
| 12 | 도구 끄는 토글 발견성 | `SettingsView+Tools.swift` | ✅ **완료** — 그룹 "도우미 도구" 안의 토글을 **"도우미 도구 사용"** 으로 통일(사용자 보고) |
| — | (덤) 승인 카드가 "실행 중"으로 굳음 | `AgentExecutor` | ✅ **완료** — 승인 대기 카드 뒤에 실행 카드를 또 추가해 `updateAgentEvent`(첫 장만 수정)가 첫 카드를 못 넘겼다 → `upsertAgentEvent`(호출당 카드 1장) · PR #46 `28054bd` |
| — | (덤) "맨 아래로" 버튼이 스크롤 중 안 뜸 | `ContentView` | ✅ **완료** — `GeometryReader` 추정 → `ScrollMetrics` + `ScrollOffsetObserver`(`NSScrollView` 직접 관찰) · PR #43 `ce7532a` |

---

## 5. 확인 필요 (사용자 결정)

- 설정 › 도구의 **허용 규칙** 1건(내부 주소 `curl -s … http://192.168.86.30:8791/v1/models` + `http://127.0.0.1:8791/v1/models`)
  — 사용자 요청으로 **삭제 완료**(`rules` 1→0, 나머지 53키 보존). 원본 plist 백업: `.agent/backup/com.borasarang.QuickTalk-2026-10-25.plist`.
  되살릴 필요가 있으면 그 백업에서 `QuickTalk.settings` 데이터를 복원하면 된다.
- 실행 중 앱은 **2026-10-27 21:47 빌드**다 — 그 뒤 배포본(23:45, SHA-256 `d04da183…`)은 디스크에만 있다. **앱을 종료·재실행해야** 반영된다.

---

## 6. 미실측 (사용자 맥 사용 중이라 못 한 것)

| 항목 | 왜 |
|---|---|
| 권한 승인/거부 흐름, 실제 창 캡처 | 앱 실행·화면 조회 금지 |
| 터미널 인계(`.command` 열기·Enter) | 터미널 실행 금지 |
| Shortcuts/AppIntents 실행 | 앱 실행 금지 |
| 실제 `screenshot` 도구 결과 | 화면 기록 권한 필요 |
| 되돌리기 실사용 왕복(쓰기 → 되돌리기) | 앱 실행 금지(단위 테스트로 대체) |
| [중단] 실사용 체감(즉시 멈춤) | 앱 실행 금지(프로세스 트리 테스트로 대체) |

→ 위 항목은 **`docs/qa/v0.20-22/CHECKLIST.md` 29항목**에 포함되어 있다. 배포 후 그 체크리스트로 확인한다.
