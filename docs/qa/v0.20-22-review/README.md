# v0.19–v0.22 코드 점검 · 오프스크린 렌더 (2026-10-25)

> 대상: `f753dbb`(main) + 브랜치 `fix/macos-p1-review`
> 목적: **배포 없이** 코드 점검 + 오프스크린 렌더로 화면 회귀 확인 → 찾은 결함 중 **P1 3건만** 수정.
> 사용자 맥 사용 중이라 **앱 실행·창 조회·스크린샷·터미널 열기·배포는 하지 않았다.**
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
| 배포 | **안 함** — `~/Applications/QuickTalk.app` 은 2026-10-23 17:50 빌드(v0.19 WIP·v0.20~22 미포함) |

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

## 4. P2 백로그 (이번에 고치지 않음)

| # | 항목 | 위치 | 비고 |
|---|---|---|---|
| 1 | 영어 번역 누락 **74곳** | `LocalizationTable.swift` 등 | 신규 화면 문구가 한국어로 폴백. 영어 UI 실측 전에 정리 |
| 2 | 규칙 테스터 캡션에 `**` 노출 | `SettingsView+Tools.swift:95` | 마크다운 미적용 문자열 |
| 3 | `screenshot` 이 "읽기 매번 확인" 설정을 무시 | `AgentExecutor` | 권한 단계 판정이 실행 단계 고정 |
| 4 | 샌드박스 프로필 경로 미이스케이프 | `SandboxRunner` | 공백·괄호 포함 경로에서 규칙이 깨질 수 있음 |
| 5 | `usleep` 폴링 | `SandboxRunner`·`TerminalHandoffService` | 50~200ms 대기. 취소 응답성 개선 여지 |
| 6 | `matchesRule` 의 `hasPrefix` 과매칭 | `PolicyEngine` | `rm -rf /tmp/a` 규칙이 `/tmp/ab` 까지 허용 |
| 7 | 규칙 테스터가 쓰기를 **실행 단계**로 판정 | `PolicyEngine` | 테스터 결과와 실제 실행 단계가 다를 수 있음 |
| 8 | 스크린샷 후 **원 첨부 대체** | `AgentExecutor` | 첨부가 있으면 스크린샷이 밀려남 |
| 9 | `SlashCommands.all` static 고정 | `SlashCommand.swift` | 설정 변경(도구 on/off)이 팔레트에 즉시 반영되지 않음 |
| 10 | `UIStore.swift:940` 경고 | `UIStore` | 컴파일 경고 1건 |

---

## 5. 확인 필요 (사용자 결정)

- 설정 › 도구의 **허용 규칙**에 아래 항목이 저장되어 있다:
  `curl -s -m 5 -o /dev/null -w … http://127.0.0.1:8791/v1/models`
  — 이번 세션에서 **삭제하지 않았다**(사용자 데이터). 내부 주소라 그대로 두어도 위험은 낮지만, 남길지 지울지는 사용자가 정한다.
- 실행 중 앱은 2026-10-23 빌드다. **이번 수정은 배포 전이므로 실사용 화면에는 아직 반영되지 않았다.**

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
