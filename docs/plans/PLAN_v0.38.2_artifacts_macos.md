# PLAN v0.38.2 — 산출물 카드 · 파일 생성 도구 (macOS)

> 상위 계획: `PLAN_v0.38_delegation_macos.md` §11
> 목표: 비서가 만든 파일을 **답변 아래 카드**로 보여 주고, 앱을 다시 켜도 남기며,
>       쓰기 전 상태와 비교(diff)하고, 한 번에 되돌릴 수 있게 한다.

## 1. 범위

| 포함 | 제외 |
|---|---|
| `write_file` 도구 — 텍스트 파일 생성·교체(원자적 쓰기) | 임의 바이너리 쓰기 도구 |
| `Turn.artifacts` — 턴에 산출물 기록(재시작 후 유지) | 대화 전체 파일 브라우저 |
| 셸 쓰기 산출물 수집 — `UndoEntry` 기반 생성/수정/삭제 | 셸 명령의 **내용** 해석 |
| 산출물 카드 — 파일명·크기·변경 배지·+/- 줄 수 | 자동 커밋·자동 동기화 |
| 미리보기 시트 — 텍스트·이미지·diff·바이너리 안내 | 앱 안에서의 파일 편집기 |
| [열기] [폴더 열기] [되돌리기] | 파일 내용의 외부 전송 |
| Job 상태 카드 파일 목록에서 미리보기 | Job 산출물의 자동 삭제 |

v0.38.2는 **새 실행 엔진을 만들지 않는다.** 기존 `AgentExecutor`·승인 카드·`UndoStack`·`Turn`
기록을 확장한다. 승인 우선·샌드박스·감사·`AppDataGuard` 신뢰 모델은 그대로다.

## 2. 데이터 모델

### 2.1 `TurnArtifact`

```swift
public struct TurnArtifact: Codable, Equatable, Identifiable {
  public enum Change: String, Codable { case created, modified, deleted }
  public var id: UUID
  public var path: String          // 절대 경로(정규화)
  public var change: Change
  public var byteCount: Int        // 현재 크기(삭제면 삭제 전 크기)
  public var addedLines: Int?      // 텍스트일 때만
  public var removedLines: Int?    // 텍스트일 때만
  public var undoID: String?       // UndoStack 스냅샷 — 있으면 [되돌리기]
  public var createdAt: Date
}
```

- `Turn.artifacts: [TurnArtifact]?` — **옵셔널**이라 구버전 `history.json`과 호환된다.
- 같은 턴에서 같은 경로를 두 번 건드리면 **마지막 기록으로 교체**한다(카드 중복 방지).
- 한 턴 최대 12개. 넘으면 앞의 12개만 남긴다(카드가 대화를 덮지 않게).
- 파일 내용은 `Turn`에 저장하지 않는다. 미리보기는 **디스크를 읽고**, diff는
  `undoID → UndoStack`의 백업과 현재 파일을 비교해 그때 계산한다.
  → 대화 기록이 파일 크기만큼 커지지 않고, 미리보기는 항상 현재 상태를 반영한다.

### 2.2 diff

- 줄 단위 `CollectionDifference`로 added/removed 수를 센다.
- unified diff(3줄 문맥)를 만들어 미리보기 시트에 +/− 색으로 보여 준다.
- 입력이 5,000줄을 넘거나 UTF-8 텍스트가 아니면 줄 수·diff를 생략하고 크기만 보여 준다.
- 출력은 최대 400줄. 길면 UI가 “일부만 표시”를 덧붙인다.

### 2.3 `ArtifactPreview`

- `text` — 현재 파일 앞부분(최대 256KB)
- `diff` — 쓰기 전 백업이 있을 때만
- `image` — png/jpg/… 는 경로만 넘기고 UI가 `NSImage`로 읽는다
- `binary` — NUL·UTF-8 실패
- `missing` — 미리보기 시점에 파일이 사라짐(이동·삭제·되돌리기)

## 3. `write_file` 도구

### 3.1 스키마

| 이름 | 필수 | 설명 |
|---|---|---|
| `path` | ✓ | 절대 경로(`~` 허용). 상대 경로는 거부 |
| `content` | ✓ | UTF-8 텍스트. 최대 300,000자 |
| `purpose` |  | 카드에 보여 줄 한 줄 이유 |

- `mode`는 두지 않는다. **만들기/전체 교체**만 한다(부분 수정은 `shell`의 몫).
- 빈 파일 생성은 허용한다. NUL 문자는 거부한다.

### 3.2 권한 흐름 (기존 게이트 재사용)

1. 경로 정규화 → `..` 정리 → **부모 폴더의 심볼릭 링크 해석**.
   대상이 심볼릭 링크면 거부한다(승인 범위 밖을 가리킬 수 있다).
2. 거부(항상):
   - 앱 자기 데이터(`AppDataGuard.isProtected`)
   - 시스템 영역(`TerminalHandoff.isSystemWrite`, `WriteScope.isSystemPath`)
   - 상대 경로·빈 경로·300,000자 초과·NUL 포함
3. `PolicyEngine.decide(command: "write_file <path>", capability: .write(path:), risk:, policy:, approvedScopes:)`
   - 위험도는 `RiskClassifier.classify("tee <path>")`로 계산한다(시스템 설정 경로면 중요).
   - 승인 범위(Job 작업 폴더·이 대화에서 허용한 폴더) 안이면 자동 허용.
4. 확인이 필요하면 **승인 카드**에 경로·새 파일/덮어쓰기·줄 수·앞 20줄을 보여 준다.
   - [한 번 허용] [이 폴더 허용] [거부]
   - 앱 데이터는 `항상 허용`을 숨긴다(기존 `AppDataGuard` 규칙).
5. 승인 뒤 `UndoStack.snapshot(paths: [path])` — 기존 파일은 백업.
   - 기존 파일인데 **백업에 실패하면 덮어쓰지 않는다**(전용 쓰기 도구의 안전선).
6. 같은 폴더에 임시 파일을 쓰고 `Data.write(options: .atomic)`으로 교체한다.
7. 성공 시 `UndoStack.commit` + `TurnArtifact` + 감사 기록.
   실패 시 `discard` + 카드 실패.

### 3.3 도구 목록

- `AgentToolCatalog.all`에 추가 → **기본 7개**(shell·read_file·list_dir·write_file·processes·screenshot·propose_plan).
- `PersonaTools.write`가 `write_file`을 게이트한다. `readOnly` 비서는 쓸 수 없다.
- `AgentInstructions.text`에 “텍스트 파일은 `write_file`로 한 번에 쓴다. 셸 리다이렉션보다 우선한다.”를 넣는다.
- Apple FM은 기존처럼 shell·path 도구만 쓴다(`write_file` 미지원).

## 4. 셸 쓰기 산출물

`AgentExecutor.finishShell`이 성공한 쓰기의 `UndoEntry`를 받으면:

1. 각 `UndoItem`(디렉터리 제외)에 대해 현재 상태를 읽는다.
2. `existed=false & 지금 있음` → 생성, `existed=true & 지금 있음` → 수정, `existed=true & 지금 없음` → 삭제.
3. 수정인데 백업과 현재 바이트가 같으면 **건드리지 않은 것**이므로 제외한다.
4. 최대 12개를 `TurnArtifact`로 만들어 그 턴에 붙인다.
5. [되돌리기]는 `UndoEntry` 하나를 되돌리므로 **그 실행의 쓰기 전체**가 되돌아간다(카드에 명시).

## 5. UI

### 5.1 답변 아래 산출물 카드

```
📎 산출물 · 2개
📄 이사-체크리스트.md   수정  +34 −2   12 KB   [미리보기] [폴더] [되돌리기]
🖼 평면도.png           생성           240 KB  [미리보기] [폴더] [되돌리기]
```

- 답변 텍스트 아래, 계획 카드 위.
- 변경 배지: 생성=초록, 수정=파랑, 삭제=빨강.
- [되돌리기]는 같은 `undoID`를 가진 카드 전체를 되돌린다. 결과를 카드 아래 한 줄로 남긴다.
- 앱 재시작 후: `Turn.artifacts`로 카드가 남고, [되돌리기]는 `UndoStack` 디스크 기록으로 동작한다.
- 파일이 사라졌으면 카드에 “파일이 없습니다”를 흐리게 표시한다(미리보기에서도).

### 5.2 미리보기 시트

- 헤더: 아이콘·파일명·경로·변경·크기·+/−.
- 본문:
  - 텍스트: [변경 내용 | 현재 파일] 전환(백업이 있을 때)
  - diff: `+` 초록, `−` 빨강, 문맥은 회색. 가로 스크롤 없이 줄바꿈.
  - 이미지: 창 크기에 맞춰 축소.
  - 바이너리: “미리보기를 지원하지 않습니다.”
  - 사라짐: “파일이 없습니다 — 이동·삭제·되돌리기되었을 수 있습니다.”
- 푸터: [열기] [폴더 열기] [되돌리기] [닫기].
- [열기]는 기존 `LocalFileOpen.open`을 쓴다 — `.app`·스크립트는 확인 후 연다.

### 5.3 Job 상태 카드

- 완료 상태의 파일 목록(최대 4개 + 외 N개)을 **버튼**으로 바꿔 미리보기 시트를 연다.
- 미리보기는 `JobWorkspace.artifacts`의 상대 경로를 작업 폴더와 합쳐 연다.
- Job 산출물에는 `undoID`가 없으므로 [되돌리기]를 숨긴다.

## 6. 보안·개인정보

- 미리보기는 **로컬 파일만** 읽는다. 네트워크 전송 없음.
- 파일 내용을 로그·감사 기록·알림에 남기지 않는다(경로·크기·줄 수만).
- 승인 카드 미리보기는 앞 20줄만 — 비밀번호·토큰이 파일에 있어도 카드에 전부 노출되지 않게.
- `AppDataGuard` 보호 경로는 **쓰기 도구에서 무조건 거부**한다(승인으로도 열지 않음).
- 심볼릭 링크 대상은 거부한다. 부모 폴더 링크는 해석한 **실제 경로**로 승인한다.
- `write_file`은 셸을 거치지 않으므로 샌드박스가 없다. 대신 경로 검증·정책·승인·백업·감사로
  같은 신뢰 경계를 만든다(이중 게이트).

## 7. 검증

### 7.1 Core 테스트 (신규 14+)

- `TextDiff` — 추가/삭제 수, unified diff, 문맥 3줄, 5,000줄 초과 생략, CRLF
- `TurnArtifact` — Codable 왕복, 구버전 `Turn`(artifacts 키 없음) 디코드
- `ConversationStore` — 산출물 추가·같은 경로 교체·12개 상한·턴 저장
- `FileArtifacts.collect` — 생성/수정/삭제/무변경 제외/디렉터리 제외
- `ArtifactPreview` — 텍스트·이미지·바이너리·사라짐·diff
- `write_file` 스키마·권한 단계·비서 `write=false` 차단

### 7.2 헤드리스 QA `--qa-artifact-routing`

1. 기본 카탈로그 7개, `write_file` 포함
2. `AgentToolPermission.level("write_file") == .write`
3. 임시 폴더에서 `write_file` 실행 → 파일 생성·`Turn.artifacts` 1개·생성 배지
4. 같은 파일 교체 → 수정 배지·+/− 계산·백업 존재
5. [되돌리기] → 원래 내용 복원·산출물 카드 상태
6. 앱 데이터 경로·시스템 경로 거부
7. 미리보기 로더 — 텍스트/이미지/바이너리/사라짐

### 7.3 회귀

- `swift test` 전체
- `--qa-browser-routing`(기본 6→7 수정), `--qa-job-routing`, `--qa-plan-routing`, `--qa-execute-routing`
- Debug/Release **경고 0**
- 실기: “보고서 파일 만들어 줘” → 승인 카드 미리보기 → 생성 → 카드 → diff → 되돌리기 → 파일 복원

## 8. 단계

| 단계 | 내용 | 상태 |
|---|---|---|
| 1 | 모델·diff·수집기·미리보기 로더 (Core) | ✅ 완료 |
| 2 | `write_file` 도구·승인·원자적 쓰기·감사 | ✅ 완료 |
| 3 | 산출물 카드·미리보기 시트·Job 연결 | ✅ 완료 |
| 4 | 테스트·번역·QA 하네스 | ✅ 완료 |
| 5 | 빌드·버전 1.38.2(3802)·설치·PR·문서 | ✅ 완료 |

## 9. 한계

- 셸이 만든 산출물은 `WriteScope.candidatePaths`가 잡은 경로만 수집한다(글롭·파이프 내부는 놓칠 수 있음).
- 파일 내용은 대화 기록에 저장하지 않으므로, 백업이 정리된 뒤에는 diff를 볼 수 없다(현재 내용은 볼 수 있음).
- 미리보기는 256KB까지만 읽는다. 더 큰 파일은 앞부분만 보여 준다.
- 바이너리 파일은 미리보기 대신 [열기]로 기본 앱에서 연다.
- Job 산출물은 작업 폴더 기준 상대 경로만 나열한다(폴더 밖 파일은 Job 카드에 없다).

## 10. 검증

### 실측 결과 (2026-11-12)

| 항목 | 결과 |
|---|---|
| `swift test` | **1092/1092** 통과 (6 skip, 0 failures) — `ArtifactTests` 14개 포함 |
| `LocalizationCoverageTests` | 5/5 — 산출물·미리보기·`write_file` 문구 47키 영어 번역 |
| Debug 빌드 | **BUILD SUCCEEDED · 경고 0** (clean) |
| Release 빌드 | **BUILD SUCCEEDED · 경고 0** (clean) |
| `--qa-artifact-routing` | **PASS 18/18** |
| 회귀 | `--qa-browser-routing`·`--qa-job-routing`·`--qa-plan-routing`·`--qa-execute-routing`·`--qa-skills-routing` PASS |

- `--qa-artifact-routing` 는 실제 모델 없이 임시 폴더에서 실행기를 돌려 ① 카탈로그 7개·쓰기 권한 ② 새 파일 생성 + 생성 배지·줄 수 ③ 교체 + 수정 배지·+/−·백업 ④ [되돌리기] 복원 ⑤ 앱 데이터·시스템·심볼릭 링크(끊어진 링크 포함) 거부 ⑥ 미리보기 텍스트/이미지/바이너리/사라짐을 확인한다.
- `write_file` 승인 카드는 파일 앞 **20줄**만 보여 주고, 기존 파일 백업에 실패하면 **덮어쓰지 않는다**. 쓰기는 같은 폴더의 임시 파일을 거치는 `.atomic`.
- 셸이 만든 산출물은 기존 `UndoEntry` 의 `UndoItem` 을 읽어 생성/수정/삭제를 판정하고, 백업과 현재 바이트가 같은 **무변경 항목은 제외**한다.

### 실기 대기

- "보고서 파일 만들어 줘" → 승인 카드 미리보기(앞 20줄) → 생성 → 카드 → 미리보기 diff → [되돌리기] → 파일 복원.
- 셸로 파일을 만든 턴에서도 카드가 붙는지(글롭·파이프 내부 경로는 놓칠 수 있음).
- 앱 재시작 후 카드·[되돌리기]가 남는지, Job 완료 카드의 파일 목록에서 미리보기가 열리는지.
