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

## 5. 디자인 토큰 (custom 프로필일 때)
- 색/폰트/간격 등은 docs/DESIGN.md에 정의, 여기서는 프로필만 확정

## 6. 문서 진입점 (새 세션)
- **`docs/HANDOFF.md`부터** → `docs/TODO.md` §지금 → 최근 `.agent/session-*.md`
- 기능 설계는 `docs/plans/`, 실측은 `docs/QA-CHECKLIST-2026-10-20.md`
- **git 저장소 있음**(`github.com/BoraSarang/QuickTalk`) — `main` 직접 push 금지. 작업 브랜치에서 커밋하고, 변경 파일·검증·배포 상태를 문서에도 남긴다.
