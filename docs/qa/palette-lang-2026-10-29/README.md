# 슬래시 팔레트 언어 — 측정 기록 (2026-10-29)

사용자 보고(**"슬래시 팔레트가 설정 언어와 반대로 나온다 — 한글이면 영문, 영문이면 한글"**)를
**추측으로 고치지 않고** 먼저 캡처로 재현한 기록이다. QA #11 · #12.

## 결론

| 보이는 것 | 측정 결과 |
|---|---|
| 팔레트 **설명·템플릿** | 이미 언어를 따라갔다(시작 시점·런타임 전환 양방향) → **역전 아님** |
| 팔레트 **명령 이름**(`/화면`…) | `SlashCommand.name` 이 **한국어 리터럴**이라 영어 UI 에서도 그대로 → **반쪽 번역** |

→ 사용자가 "언어의 반대"로 느낀 지점은 **이름이 바뀌지 않는 것**이었다. 수정 후 이름도 `L()` 을 따라간다.

## 캡처

| 파일 | 무엇을 보는가 |
|---|---|
| `before/chat-ko.png` | 수정 전 · 한국어 — 전부 한국어(정상) |
| `before/chat-en.png` | 수정 전 · 영어 — 설명은 영어인데 **`/화면`·`/창`… 이름만 한국어** |
| `runtime/ko-to-en.png` | 수정 전 · **설정에서 한국어 → 영어로 바꾼 직후**(sink 경유) — 설명은 영어, 이름만 한국어 |
| `runtime/en-to-ko.png` | 수정 전 · **영어 → 한국어** — 설명·이름 모두 한국어(전환 자체는 정상) |
| `after-fix/chat-en.png` | 수정 후 · 영어 — `/Screen`·`/Window`·`/Disk`·`/Process`·`/Memory`·`/Settings`·`/Help` |
| `after-fix/chat-ko.png` | 수정 후 · 한국어 — 종전과 동일(`/화면`·`/창`…) |
| `after-fix/settings-tools-en.png` | 수정 후 · 설정 › 도구·권한 — 그룹 "Assistant tools" 안 토글 **"Use assistant tools"**(#12 라벨 통일) |

## 재현 명령

```bash
# 수정 전/후 · 시작 시점 언어
QuickTalk --render=<dir> --lang=korean|english --theme=light --demo-chat --demo-slash

# 설정에서 언어를 바꾸는 실제 경로(sink) 재현 — 저장하지 않는다
QuickTalk --render=<dir> --lang=korean --demo-chat --demo-slash --demo-lang-switch=english
```

- `--demo-slash` — 입력독에 `/` 를 넣어 팔레트를 그린다.
- `--demo-lang-switch=<korean|english>` — `store.applyRenderOverride(language:)` 로 설정을 **메모리에서만** 바꾸고
  `RunLoop` 를 0.25초 돌려 AppDelegate sink(`applyLanguage`)를 실제 순서대로 태운다.
  `--lang=` 오버라이드가 있으면 설정 변경이 무시되므로 `clearLaunchLanguageOverride()` 로 먼저 해제한다.
