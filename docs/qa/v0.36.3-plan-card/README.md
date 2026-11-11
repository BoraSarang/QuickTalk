# v0.36.3 — 실행 계획 카드 렌더·QA 기록

계획 카드(`propose_plan`)의 **네 상태**와 한/영 표시를 오프스크린으로 확인했다.
생성: `--render=docs/qa/v0.36.3-plan-card --demo-plan[=running|done] --lang=korean|english`

| 파일 | 상태 | 확인한 것 |
| --- | --- | --- |
| `chat-ko.png` | 제안 직후 | 권한 칩(읽기·쓰기) · 목표 1줄 · 단계 4개 미체크 · [수정] [실행] · **[▶ 실행] 없음** |
| `chat-running-ko.png` | 실행 중 | 스피너 + `실행 중` · 버튼 숨김 · 아래 실행 턴이 응답 중 |
| `chat-done-ko.png` | 실행 완료 | 전 단계 체크 + `실행 완료` · 실행 턴의 도구 카드 4장 |
| `chat-idle-en.png` | English | `Execution plan` · `Read`/`Write` · `Edit`/`Run` |

## 헤드리스 라우팅

`--qa-plan-routing` — 턴 기록만 만들어 다섯 경계를 본다(모델·도구 호출 없음).

```
[QA-PLAN] offered=1 hidesExecute=1 hiddenAfterRun=1 finished=1 notPlan=1 — 기대: 1/1/1/1/1
[QA-PLAN] result=PASS
```

| 항목 | 기대 | 뜻 |
| --- | --- | --- |
| `offered` | 1 | 계획 답변에 [실행]이 보인다 |
| `hidesExecute` | 1 | 같은 답변에 [▶ 실행]은 보이지 않는다 |
| `hiddenAfterRun` | 1 | 계획 뒤 실행 턴이 붙으면 [실행]을 숨긴다 |
| `finished` | 1 | 실행이 끝나면 전 단계가 체크된다 |
| `notPlan` | 0 | 계획 없는 턴에는 카드가 없다 |

회귀: `--qa-execute-routing` **PASS**(`normal=1 hiddenResult=1 hiddenPersona=1`).

## 한계(정직)

- 모델이 실제로 `propose_plan` 을 고르는지는 오프스크린에서 확인할 수 없다 — 사용자 실측(P1-1~P1-4)이 필요하다.
- 단계 체크는 **순차 추정**이다(도구 `.done` 개수). 모델이 단계를 건너뛰거나 한 단계에 도구를 여러 번 쓰면 어긋난다.
- 카드의 단계는 8개에서 잘린다 — 9개 이상을 준 모델은 뒤 단계가 보이지 않는다.
