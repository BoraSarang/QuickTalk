# v0.36 P0 — 답변 → 실행 `[▶ 실행]` 화면 증거 (2026-11-11)

Debug 1.36.0(build 3600) 오프스크린 렌더 · 400×560 · 도구 사용 ON(기본).

| 파일 | 확인 내용 |
|---|---|
| `chat-agent-ko.png` | 답변 footer 오른쪽에 보라색 **[▶ 실행]** — 호버와 무관하게 보인다 |
| `chat-agent-en.png` | 영어 UI에서는 **Run** |

재현:

```sh
QuickTalk --render=<폴더> --demo-agent --lang=korean
QuickTalk --render=<폴더> --demo-agent --lang=english
```

동작(표시 조건)은 헤드리스 하네스로 확인한다:

```sh
QuickTalk --qa-execute-routing
# [QA-EXECUTE] normal=1 hiddenResult=1 hiddenPersona=1 — 기대: 1/1/1
# [QA-EXECUTE] result=PASS
```
