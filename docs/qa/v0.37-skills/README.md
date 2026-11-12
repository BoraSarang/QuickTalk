# v0.37 — 스킬 설정 UI 렌더·QA 기록

스킬 가져오기·전역 토글·비서 토글·경고 표시를 오프스크린으로 확인했다.
실제 모델 호출(`read_skill`)과 라우팅 게이트는 헤드리스 로그로 검증했다.

## 생성 명령

```bash
APP=build/DerivedData/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk

# 설정 › 도구·권한 — 빈 목록 / 목록 / 경고+권한 필요 / English
"$APP" --render=docs/qa/v0.37-skills/empty --settings-tab=tools --demo-skills=empty --render-height=1500 --lang=korean
"$APP" --render=docs/qa/v0.37-skills/list  --settings-tab=tools --demo-skills=list  --render-height=1500 --lang=korean
"$APP" --render=docs/qa/v0.37-skills/warn  --settings-tab=tools --demo-skills=warn  --render-height=1500 --lang=korean
"$APP" --render=docs/qa/v0.37-skills/en    --settings-tab=tools --demo-skills=list  --render-height=1500 --lang=english

# 비서 편집의 도구·스킬 토글 (시트와 같은 `PersonaToolsSection` 을 그린다)
"$APP" --render=docs/qa/v0.37-skills/persona    --demo-persona-skills --lang=korean
"$APP" --render=docs/qa/v0.37-skills/persona-en --demo-persona-skills --lang=english
```

`--demo-skills=warn` 은 화면 제어를 **메모리에서만** 꺼서 `ui_snapshot` 이 필요한
스킬이 `권한 필요` 로 보이는 상태를 재현한다. 실제 설정은 저장하지 않는다.

| 파일 | 상태 | 확인한 것 |
| --- | --- | --- |
| `empty/settings-tools-ko.png` | 스킬 0개 | 빈 상태 문구 · 전역 토글 기본 **꺼짐** · 가져오기 버튼 |
| `list/settings-tools-ko.png` | 2개 | 이름·설명·`언제` · 기본/사용자 배지 · 읽기/쓰기 배지 · 행별 [사용] 토글 |
| `warn/settings-tools-ko.png` | 경고 2건 | `권한 필요` 배지 + 사유 캡션(`ui_snapshot`) · `무시된 스킬 2개` 펼침 |
| `en/settings-tools-en.png` | English | `Skills` · `Basic`/`User` · `Read`/`Write` · `Import from Folder` |
| `persona/persona-skills-ko.png` | 비서 편집 | `도구` 그룹의 `스킬` 토글 **기본 켜짐** · 전역과 별개 설명 |
| `persona-en/persona-skills-en.png` | English | `Skills` 토글 · 캡션 번역 |

## 헤드리스 라우팅

`--qa-skills-routing` — 모델을 부르지 않고 노출/차단 규칙만 본다.
사용자 설정은 저장하지 않는다(`withSuppressedSettingsSave`).

```
[QA-SKILLS] PASS bundle=PASS risk-read=PASS scripts-empty=PASS
  read-skill-hidden=PASS read-skill-schema=PASS
  general-off=PASS general-on=PASS list-only=PASS
  persona-overrides=PASS persona-off=PASS disabled=PASS
  needs-web-tool=PASS scheduled=PASS scheduled-context=PASS
```

| 항목 | 기대 | 뜻 |
| --- | --- | --- |
| `bundle` | 1 | 설치된 앱 번들에서 `web-research` 를 찾는다 |
| `risk-read` / `scripts-empty` | 1 | 번들 예시는 읽기 전용이고 스크립트가 없다 |
| `general-off` | 1 | 전역 기본값(꺼짐)에서 목록 블록이 없다 |
| `general-on` | 1 | 켜면 `web-research` 가 목록에 들어간다 |
| `list-only` | 1 | 블록에 **본문**이 들어가지 않는다(점진 공개) |
| `persona-overrides` / `persona-off` | 1 | 비서 토글이 전역을 **양방향으로** 덮어쓴다 |
| `disabled` | 1 | 사용자가 끈 스킬은 목록에서 빠진다 |
| `needs-web-tool` | 1 | 필요한 도구가 없으면 프롬프트에서 숨긴다 |
| `scheduled` / `scheduled-context` | 1 | 예약 실행에는 목록·`read_skill` 이 없다 |

## 실제 모델 호출

```
"$APP" --agent-test="read_skill 도구로 web-research 스킬의 절차를 읽고, 첫 단계만 한 줄로 알려줘. 셸이나 다른 도구는 쓰지 마." --skills
```

```
[AGENT-TEST] OK steps=2 tools=1 denied=0 skills=1
  | tool=read_skill level=read risk=0 state=done
  | answer=첫 단계는 **질문을 검색어 2~3개로 나누고...**
```

- 모델이 목록에서 스킬을 고르고 `read_skill` 을 **실제로 호출**했다.
- `read_skill` 은 읽기 전용이라 승인 카드·권한 상승이 없고, 감사 로그만 남는다.
- `--skills` 는 QA 전용 — 전역 토글을 **메모리에서만** 켜고 끝나면 되돌린다(저장 없음).

## 한계(정직)

- 가져오기 패널(NSOpenPanel)과 교체 확인 시트는 오프스크린으로 그릴 수 없다 — 실기에서 확인한다.
- `--agent-test` 는 모델이 `read_skill` 을 고를 때까지의 1회 호출이다. 모델·프롬프트에 따라
  호출하지 않을 수 있다(이번 실행은 호출함).
- `/스킬` 슬래시 명령은 v0.37 범위에서 **선택**이라 구현하지 않았다 — v0.37.1 후보.
- 스킬 스크립트 실행 카드의 `스킬: <id>` 표시는 명령 문자열에 경로가 **드러난 경우만** 잡는다.
  변수·난독화로 숨긴 경로는 표시하지 못한다(권한 판정과는 무관).
