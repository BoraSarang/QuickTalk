# Exa `/answer` 정리 — 옵션 유지 + 중복 경로 정리 (2026-10-29)

## 무엇을 정리했나

`/answer`(Exa 답변 초안+인용) 방식은 **유지**한다. 대신 v0.23 툴 콜링과 겹치던 판정·폴백을 한 곳으로 모았다.

- **판정 통합**: "사전 검색을 건너뛰어도 되는가"가 `UIStore` 안에 흩어져 있었다.
  → `WebSearchRouting`(Core, 순수 함수)으로 옮겨 앱과 설정 화면이 **같은 규칙**을 쓴다.
  - `skipsPreSearch`: 도우미 도구 + 검색 도구 준비 + Apple FM 아님 → 모델이 루프 안에서 검색
  - `usesAnswerDraft`: `.answer` 이고 사전 검색이 살아 있을 때만 초안이 만들어진다
- **폴백 중복 제거**: `/answer` 실패 → 일반 검색 폴백과 일반 검색 성공 경로가 **같은 6줄**을
  복사하고 있었다. `applySearchResults(_:)` 한 곳으로 합쳤다(프롬프트 주입·토큰 계산·출처).
- **안내 정확화**: 기존 캡션은 `agentToolsEnabled` 만 보고 "모델이 직접 검색한다"고 단정했다 —
  Apple FM 이나 Exa 키가 없을 때는 사실이 아니다. 이제 실제 판정(`isAgentDrivenWebSearch`)으로
  안내하고, `/answer` 모드에서는 "초안이 쓰이지 않는다"는 문장으로 바꿔 보여 준다. 중복 캡션도 제거.

## 렌더 명령

```sh
# 도구 ON + OpenAI 호환(가짜) — /answer 초안이 쓰이지 않는 안내
QuickTalk --render=docs/qa/exa-answer-2026-10-29 --settings-tab=search \
          --render-height=900 --demo-web-answer-agent

# 도구 OFF — 초안이 실제로 쓰이는 상태(안내 없음)
QuickTalk --render=docs/qa/exa-answer-2026-10-29 --settings-tab=search \
          --render-height=900 --demo-web-answer-tools-off
```

`--demo-web-answer-agent` 는 실제 키가 있는 `secretID` 를 빌려 OpenAI 호환 프로바이더를
**메모리에만** 심는다(설정 저장 없음). `--demo-web-answer-tools-off` 는 `agentToolsEnabled` 만 끈다.

## 파일

| 파일 | 상태 |
|---|---|
| `settings-search-agent-ko.png` | 도구 ON — "/answer 초안은 쓰이지 않으니, 초안을 쓰려면 도우미 도구를 끄세요." |
| `settings-search-agent-en.png` | 도구 ON(영어) — 문장 잘림 없음 |
| `settings-search-answer-ko.png` | 도구 OFF — 설명만, 경고 없음 |
| `settings-search-answer-en.png` | 도구 OFF(영어) |

## 자동 검증

`swift test --filter WebSearchRoutingTests` — 5건.

- OpenAI 호환·Ollama: 도구+검색 준비 → 사전 검색 생략
- Apple FM: 도구가 켜져도 사전 검색 유지(검색 기회 보존)
- 도구 OFF 또는 검색 키 없음 → 사전 검색 유지
- `.answer` 초안은 사전 검색이 살아 있을 때만 활성 · 다른 모드에서는 비활성

되돌려 실패 확인: `skipsPreSearch` 에서 Apple FM 예외를 지우면 3건이 실패했다.
