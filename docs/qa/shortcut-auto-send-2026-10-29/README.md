# Shortcuts 자동 전송 — 옵트인 (2026-10-29)

## 무엇을 바꿨나

지금까지 Shortcuts/Siri는 입력창에 질문을 **채우기만** 했다("자동 전송하지 않는다" 원칙, v0.21).
사용자가 명시적으로 켠 경우에만 '질문하고 보내기' 동작이 확인 없이 전송하도록 옵트인 설정을 넣었다.

- **설정** `QuickTalkSettings.shortcutAutoSend` — 기본 **꺼짐**. 구버전 설정(키 없음)도 꺼짐으로 읽힌다.
- **판정** `ShortcutAutoSend.shouldSend(requested:enabled:)` — 요청이 '보내기'이고 설정이 켜져 있을 때만 참.
  기존 "질문 채우기"는 `requested = false` 라서 **설정과 무관하게 항상 초안만** 채운다.
- **라우터** `QuickTalkIntentRouter.Request{text, ask}` — 앱이 준비되기 전에 들어온 요청도
  `ask` 플래그를 그대로 들고 있다가 준비되면 전달한다.
- **새 AppIntent** "QuickTalk에 질문하고 보내기"(`QuickTalkAskIntent`, `paperplane`) + AppShortcut 문구.
  기존 "질문 채우기"는 그대로 둔다.
- **UI** 설정 › 단축키에 `Shortcuts · Siri` 그룹 — 토글 1개 + 캡션 2줄(한/영 키 4개 추가).

## 렌더 명령

```sh
# 한국어 — 토글 기본 꺼짐
QuickTalk --render=docs/qa/shortcut-auto-send-2026-10-29 --settings-tab=shortcut --render-height=1200

# 영어 — 캡션이 2줄로 늘어나도 잘리지 않는지
QuickTalk --render=docs/qa/shortcut-auto-send-2026-10-29 --settings-tab=shortcut \
          --render-height=1200 --lang=english
```

## 파일

| 파일 | 상태 |
|---|---|
| `settings-shortcut-ko.png` | "Shortcuts · Siri" 그룹 · "질문을 받으면 바로 전송" **꺼짐** · 캡션 2줄 잘림 없음 |
| `settings-shortcut-en.png` | `Shortcuts · Siri` · `Send questions immediately` 꺼짐 · 문장 잘림 없음 |

## 자동 검증

`swift test --filter ShortcutAutoSendTests` — 3건.

- 구버전 설정(키 없음) → `shortcutAutoSend == false`
- 켠 값 저장·복원(JSON 왕복)
- 판정: `requested && enabled` 에서만 전송 · '질문 채우기'(`requested = false`)는 설정이 켜져도 전송 안 함

되돌려 실패 확인: `shouldSend` 를 `requested` 만 반환하게 바꾸면 1건이 실패했다.

## 실측 대기

- Shortcuts 앱에서 "QuickTalk에 질문하고 보내기"를 추가해 실행 → 설정 **꺼짐**: 입력창에만 들어간다.
- 설정 **켜짐**: 앱이 뒤에 있어도 답변이 시작된다. (`openAppWhenRun = true` 라 실행 시 앱이 앞으로 온다)
- Siri 문구 등록 여부는 앱 실행 후 시스템이 정한다 — 앱 재실행 뒤 확인이 필요하다.
