# PLAN_v0.1_macos.md
> 생성일: 2026-10-16 | 플랫폼: macos | 작성자: OpenCode
> 목표: Siri AI.app 대화·응답 스타일 분석 후 QuickTalk macOS 앱으로 재현

## 1. 목표 (1줄)
Siri AI.app의 대화·응답 UX를 분석하여 QuickTalk에서 동일 기능의 macOS 대화 앱을 구현한다.

## 2. 범위
- 플랫폼: macos
- 기술 스택: SwiftUI 기본 + 필요 시 AppKit 허용 + LLM/음성 입출력 연동
- 선정 이유: macOS 네이티브 대화 UI를 가장 빠르게 재현 가능
- design_profile: custom (플로팅 오브 + transcript 패널)

## 3. 문서 위치
- PLAN: 본 문서 (`docs/plans/PLAN_v0.1_macos.md`)
- TODO: `docs/TODO.md` T-1 ~ T-5 등록
- DESIGN: `docs/DESIGN.md` 갱신
- API: `docs/api/ENDPOINTS.md` (LLM/음성 연동 확정 시)

## 4. 성능 예산
- budgets.json 참조: Cold Start ≤1.5s, 메모리 ≤300MB, 60fps
- override 없음

## 5. 에러 코드
- 사용할 에러 코드 범위: E-MAC-NET-0001~, E-MAC-AUDIO-0001~, E-MAC-RENDER-0001~, E-MAC-MODEL-0001~

## 6. 빌드 & 검증 계획
- `xcodebuild` 기반 빌드, 결과물 `~/Applications/QuickTalk.app` 복사 검증
- 테스트: smoke (앱 실행 + 대화 1턴) → unit (대화 상태머신) → full (음성+텍스트 E2E, 해당 시)
- DebugPanel 검증 항목: ERROR 0, [PERF] Cold Start, [CACHE] 대화 컨텍스트 캐시

## 9. 실행 스펙 (v0.3 확정 + v0.6 PopClip 규칙)
- 상주: 메뉴바 Extra + 백그라운드 상주 기본, 로그인 항목 등록. Siri 원본 `LSUIElement=true`, `LSLaunchDLabel=com.apple.campo` 준용
- 메뉴바 표시 토글: 설정에 `메뉴바에 표시` on/off. 끄면 아이콘 숨김, 단축키로만 호출 (PopClip 방식). 기본 on
- 호출: 글로벌 단축키(기본 Ctrl+Space, 홀드/토글) + 메뉴바 클릭. 호출 시에만 입력독 전면, 포커스 스틸 금지
- 창: 풀앱 900x770(사이드바 336) / 미니 400x432 전환. 새창=새대화 기본
- Dock: 기본 숨김. 설정 `Dock에 표시` 토글로 전환. 개발 중 표시, 배포 숨김 권장
- 목업: `docs/mockup-0.1.html` 전 기능 통합본 고정, SwiftUI 이식 전 승인용

## 7. 예외 규칙 (있으면)
- 없음. 공통 규칙과 충돌 시 DESIGN.md에 예외 1줄 기록 후 진행 ([HARD]는 사용자 승인 필요)

## 8. 분석 전제 체인 (workflow.md §6)
- 필요 조건: Siri AI.app 읽기 전용 인벤토리 → 대화 UX 관찰 → QuickTalk 상태머신 설계 → 구현
- 깨지는 지점: 시스템 앱 바이너리 난독화/서명 영역 접근 불가, 실시간 음성·LLM 연동 미확정, Apple Intelligence 비공개 API 의존
- 범위 구분: 앱 소유 영역(QuickTalk 내 venv·모델·캐시)은 내장. 시스템 공유물(음성 인식·TTS 런타임 등)은 전제조건+게이트로 명시
