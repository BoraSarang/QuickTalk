# 승인된 쓰기 폴더 — 대화별 유지 · 7일 만료 (2026-10-29)

## 무엇을 바꿨나

이전에는 승인 폴더가 `UIStore.writeScopesByConversation` **메모리에만** 있어 앱을 다시 켜면
사라졌고, 설정 화면 캡션도 "앱을 다시 켜면 초기화됩니다"라고 안내했다. 이제 승인은
`Conversation.approvedWriteScopes` 로 **대화 기록과 함께 저장**되고, **7일 뒤 자동 만료**된다.

- 승인 범위는 그대로 **대화별**이다(다른 대화로 옮기면 그 대화의 승인만 적용).
- 만료된 승인은 판정(`AgentExecutor`)·설정 목록에서 빠진다. 만료 시각과 같은 순간도 만료.
- 같은 폴더를 다시 승인하면 **기간이 새로 시작**되고, 만료된 항목은 그때 정리된다.
- 설정 › 도구·권한 › 승인된 폴더에 **만료일**을 표시하고 [해제]는 그대로 유지했다.

## 렌더 명령

```sh
# 한국어 — 승인 2건(3일 뒤·6일 뒤 만료)
QuickTalk --render=docs/qa/write-scope-grants-2026-10-29 --settings-tab=tools \
          --render-height=1400 --demo-write-scopes

# 영어 — 긴 문장으로 잘리지 않는지(1650pt)
QuickTalk --render=docs/qa/write-scope-grants-2026-10-29 --settings-tab=tools \
          --render-height=1650 --demo-write-scopes --lang=english
```

`--demo-write-scopes` 는 렌더 하네스 전용으로, 대화의 승인 목록을 **메모리에만** 채운다(저장 없음).

## 파일

| 파일 | 상태 |
|---|---|
| `settings-tools-ko.png` | 승인 2건 + `11월 1일까지 유효`·`11월 4일까지 유효` · 캡션 "7일 동안 유지" |
| `settings-tools-en.png` | `Valid until Nov 1, 2026` / `Nov 4, 2026` · `Clear` · 문장 잘림 없음 |

## 자동 검증

`swift test --filter WriteScopeGrantTests` — 10건.

- 기본 수명 7일 · 만료 경계(같은 순간 = 만료)
- 재승인 시 같은 경로 기간 갱신 · 만료 승인 정리 · 중복 제거
- 경로 정규화(`~`, `..`, 후행 `/`) · 빈 경로 무시
- 대화의 유효 경로 계산 · 구버전 JSON(키 없음) 디코드 · 왕복 저장
- Store 저장 시 만료 제외 · 활성 0건이면 `nil` 로 정리

되돌려 실패 확인: `isActive` 를 항상 true 로 바꾸면 4건, Store 필터를 제거하면 1건이 실패했다.
