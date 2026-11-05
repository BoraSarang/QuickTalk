# v0.30 — ⌘Space pill 비서 선택 · 글자/커서 세로 중심 (2026-11-05)

오프스크린 렌더(`--render=`)만 사용했다 — 실행 중인 앱은 건드리지 않았다.

| 파일 | 확인 내용 |
| --- | --- |
| `pill-persona-ko.png` · `pill-persona-en.png` | pill 오른쪽에 **비서 버튼**(이모지 + 체크 배지). 누르면 대화 창과 같은 메뉴가 열린다. |
| `pill-nopersona-ko.png` · `pill-nopersona-en.png` | **비서 없음** — 같은 자리에 `person.crop.circle`(체크 없음)로 구분된다. |
| `pill-typed-ko.png` · `pill-typed-en.png` | 입력한 글자가 본체 **세로 중앙**에 놓인다(글자 잉크 중심 112.75~113.0 / 본체 112.0). |
| `pill-multiline-ko.png` | 여러 줄로 자라도 글자 블록이 위아래 같은 여백, 아이콘은 아래 기준선. |
| `chat-empty-ko.png` · `chat-empty-en.png` | 빈 대화 입력독 — 안내 문구를 `NSTextView` 가 직접 그려 **캐럿과 같은 기준선**에 놓인다. |

## 측정값

- pill 글자 잉크 중심: 수정 전 **114.75** → 수정 후 **112.75~113.0** (본체 중심 112.0).
- 대화 창 입력독: 글자 **588.0** vs 전송 아이콘 **588.25** (2배 렌더 좌표).

## 렌더 재현 명령

```sh
QuickTalk.app/Contents/MacOS/QuickTalk --render=/tmp/qt-v30-ko --lang=korean \
  --demo-pill --demo-composer-text --demo-persona-menu --render-height=400

QuickTalk.app/Contents/MacOS/QuickTalk --render=/tmp/qt-v30-en --lang=english \
  --demo-pill --demo-composer-text --demo-persona-menu --render-height=400

# 빈 대화 입력독(안내 문구)
QuickTalk.app/Contents/MacOS/QuickTalk --render=/tmp/qt-v30-chat --lang=korean \
  --demo-chat --render-height=600
```

## 실측 대기

1. ⌘Space → 비서 버튼으로 비서를 고르면 이름·이모지·체크가 바뀌고 답변 말투가 바뀐다.
2. `무엇이든 물어보세요`와 키보드 커서가 본체 세로 중앙에 보인다.
3. 비서를 고른 뒤 Esc → 다시 ⌘Space 로 열어도 선택이 유지된다.
