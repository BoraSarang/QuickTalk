# v0.29 — 연결 끊김 이어쓰기 · 예고 답변 방지 · 비서 상태 표시 (2026-11-05)

오프스크린 렌더(`--render=`)만 사용했다 — 실행 중인 앱은 건드리지 않았다.

| 파일 | 확인 내용 |
| --- | --- |
| `retry-banner-ko.png` · `retry-banner-en.png` | 부분 답변을 남긴 채 **연결 끊김 대기 배너**와 [응답 중지]가 함께 보인다. |
| `settings-ai-ko.png` · `settings-ai-en.png` | 설정 › AI 의 **연결 끊김 대기**(토글 · 5초 · 최대 10회 · 캡션). |
| `persona-menu-ko.png` · `persona-menu-en.png` | 비서 메뉴 머리줄 **"지금: …"**, `비서 없음`·선택된 비서의 **체크 표시**, `할일`. |
| `composer-text-ko.png` · `composer-text-en.png` | 입력한 글자가 입력독 아이콘 줄과 **같은 세로 중심**에 놓인다. |

## 렌더 재현 명령

```sh
QuickTalk.app/Contents/MacOS/QuickTalk --render=/tmp/qt-v29 --lang=korean \
  --demo-composer-text --demo-persona-menu --demo-retry-banner \
  --settings-tab=ai --render-height=900
```

## 실측 대기

1. 응답 도중 Wi-Fi 를 끊고 **5초 간격 · 최대 10회** 대기 후 이어쓰기(부분 답변 유지·중복 없음).
2. 대기 중 **[응답 중지]** — 즉시 멈추고 지금까지 받은 답변 유지.
3. 도구를 쓰는 질문이 "확인하겠습니다"로 끝나지 않고 **실제 값**으로 끝난다.
4. 비서에게 리포트 저장을 시키면 **설정된 리포트 폴더**에 만들고, 읽기 전용 폴더를 추측하지 않는다.
5. 비서 메뉴에서 `비서 없음` ↔ 비서 선택이 **눈에 띄게** 구분된다.
