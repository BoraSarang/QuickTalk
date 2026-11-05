# AGENTS.local.md — 프로젝트별 확장 규칙
> 위치: /Users/lee/Documents/Apps/QuickTalk/AGENTS.local.md
> 공통 가이드는 재작성 금지. 변경점만 기록.

## 1. 프로젝트 정보
- **프로젝트명**: QuickTalk
- **플랫폼**: macos
- **기술 스택**: SwiftUI 기본 + 필요 시 AppKit (NSViewRepresentable) + Apple Intelligence / LLM API 연동
- **선정 이유**: Siri AI.app 대화·응답 기능을 macOS 네이티브로 재현하기 위함
- **design_profile**: custom — 자체 카드·시트·입력독. 네이티브 alert/Picker/NSPopUpButton 금지(전면 설정의 기존 `pickerRow`만 예외)
- **작업 모드 기본값**: 정식

## 2. 번들ID / 앱 ID
- macOS bundleIdentifier: `com.borasarang.QuickTalk` (변경 시 파괴적 변경 가드 적용)

## 3. 성능 예산 Override (필요 시)
- 없음. budgets.json 기본값 준수 (Cold Start ≤1.5s, 메모리 ≤300MB)

## 4. 프로젝트 특화 예외 규칙
- 분석 대상 `/System/Applications/Siri AI.app` (bundle `com.apple.campo`)는 읽기 전용으로만 취급. 복사·수정·재배포 금지, 동작 관찰 + 리소스 인벤토리만 수행
- QuickTalk는 Siri AI 복제가 아니라 대화·응답 UX 호환 구현을 목표로 함
- **[HARD] 배포 시 이전 버전 백업 번들을 만들지 않는다** — `~/Applications/` 안에 `.QuickTalk.old`, `.QuickTalk.v0xx`, `QuickTalk copy`, `QuickTalk.app.new` 같은 **어떤 이름의 복제본도 금지**. 같은 bundle id 번들이 두 개 이상 존재하면 시스템 설정 › 개인정보 보호 및 보안(카메라·마이크·손쉬운 사용·화면 기록 등)에 유령 항목이 쌓여 쓰레기 데이터가 된다(2026-11-02 요청, 2026-11-05 재확인).
- **배포 절차(고정)**: ① `~/Applications/` **밖**(예: `build-release/…/Release/`)에서 빌드·코드서명 확인 → ② 실행 중이면 사용자에게 종료 요청 → ③ `rm -rf ~/Applications/QuickTalk.app` → ④ 새 번들을 **한 번에** `~/Applications/QuickTalk.app` 으로 이동 → ⑤ `codesign --verify --strict --deep` + SHA-256 기록. 임시 스테이징 경로도 `~/Applications/` 밖에 둔다. 롤백은 백업 번들이 아니라 git 커밋 되돌리기 + 재빌드로 한다.

## 5. 디자인 토큰 (custom 프로필일 때)
- 색/폰트/간격 등은 docs/DESIGN.md에 정의, 여기서는 프로필만 확정

## 6. 문서 진입점 (새 세션)
- **`docs/HANDOFF.md`부터** → `docs/TODO.md` §지금 → 최근 `.agent/session-*.md`
- 기능 설계는 `docs/plans/`, 실측은 `docs/QA-CHECKLIST-2026-10-20.md`
- **git 저장소 있음**(`github.com/BoraSarang/QuickTalk`) — `main` 직접 push 금지. 작업 브랜치에서 커밋하고, 변경 파일·검증·배포 상태를 문서에도 남긴다.
