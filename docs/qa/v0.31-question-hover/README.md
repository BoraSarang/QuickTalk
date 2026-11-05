# 질문 호버 — 말풍선 폭 고정 QA (2026-11-06)

> 계기: 사용자 지적 — *"질문 호버 시 가로 사이즈가 변하는 게 아니라 세로로 변하네"*
> 원인: `⋯` 메뉴를 말풍선 `HStack` 안에 넣어, 호버할 때마다 말풍선 폭이 26pt 줄고 글자가 다시 접혔다.

## 수정
- `⋯` 를 **레이아웃 밖**(`.overlay`)으로 옮기고 오른쪽 여백 안쪽(`offset x: 16`)에 띄운다.
- 말풍선 폭·줄바꿈·높이가 호버 전후로 **완전히 동일**하다.
- 호버 판정은 행 전체(`.onHover`)로 넓혀, `⋯` 로 마우스를 옮겨도 사라지지 않는다.

## 렌더

| 파일 | 상태 |
| --- | --- |
| `question-normal-ko.png` / `-en` | 호버 없음 |
| `question-hover-ko.png` / `-en` | 첫 질문 호버 — `⋯` 표시 |

```bash
BIN=build-debug/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk
"$BIN" --render=docs/qa/v0.31-question-hover --lang=korean --theme=dark --demo-question-hover
```

`--demo-question-hover` 는 예시 대화를 메모리에서만 넣고, `hoverFirstQuestion` 로 첫 질문의
호버 상태를 재현한다(저장 없음). 두 PNG 의 말풍선 오른쪽 끝과 줄 수가 같은지 비교한다.
