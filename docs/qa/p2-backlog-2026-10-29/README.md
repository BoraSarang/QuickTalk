# P2 백로그 #7 — 규칙 테스터 단계별 판정 (2026-10-29)

## 무엇을 확인했나

이전 테스터는 `AgentCapability.unprobed`(단계 = 실행) 하나만 계산해, **쓰기 명령도 "실행" 단계**로
표시했다. 이제 `PolicyEngine.stagePreview` 가 **실행 없이** 읽기·쓰기·실행 세 단계의 판정을 모두
계산하고, UI 는 단계별 칩으로 보여 준다.

- 실제 단계는 **실행 직전 읽기 전용 샌드박스 실측**으로 정해지므로, 테스터는 "각 단계로 판정되면
  어떻게 되는가"를 보여 준다(푸터에 명시).
- 상승 권한(`sudo`) 명령은 단계 구분이 무의미해 **실행 단계 하나**만 표시한다.
- 테스터는 여전히 **아무것도 실행하지 않는다** — `testStagePreviewCriticalDeniesWithoutRunning` 이
  치명적 명령의 파일 쓰기 흔적이 없음을 확인한다.

## 렌더 명령

```sh
# 사용자 설정 그대로(이 맥은 읽기·쓰기·실행 모두 "매번 확인") — 세 단계 모두 확인 필요
QuickTalk --render=docs/qa/p2-backlog-2026-10-29 --settings-tab=tools \
          --render-height=1700 --demo-rule-probe='echo hello > ~/Documents/qt-probe.txt'

# 영어 UI — "Write" 라벨이 잘리지 않는지(레벨 칸 42pt)
QuickTalk --render=docs/qa/p2-backlog-2026-10-29 --settings-tab=tools \
          --render-height=1700 --lang=english \
          --demo-rule-probe='echo hello > ~/Documents/qt-probe.txt'

# 전역 자동 수락을 메모리에서만 켠 상태 — 세 단계 모두 "확인 없이 실행"(초록)
QuickTalk --render=/tmp/qt-render-auto --settings-tab=tools \
          --render-height=1700 --demo-auto-accept \
          --demo-rule-probe='echo hello > ~/Documents/qt-probe.txt'
```

`--demo-rule-probe=` 는 테스터 입력만 채우고, `--demo-auto-accept` 는 `suppressSettingsSave` 로
**저장하지 않는다**. 두 플래그 모두 렌더 하네스 전용이다.

## 파일

| 파일 | 상태 |
|---|---|
| `settings-tools-ko.png` | 사용자 설정(모두 매번 확인) — 읽기·쓰기·실행 모두 `확인 필요` |
| `settings-tools-en.png` | 영어 — `Read`·`Write`·`Run` 정렬, `Write` 잘림 없음 |
| `settings-tools-autoaccept-ko.png` | 자동 수락(메모리) — 세 단계 모두 `확인 없이 실행` |

## 자동 검증

`swift test --filter AgentTests/testStagePreview` — 6건.

- 기본 정책에서 읽기=허용, 쓰기·실행=확인으로 **분리**되는지
- 쓰기 정책만 바꿨을 때 쓰기 단계만 바뀌는지(예전에는 둘 다 "실행")
- `autoAcceptAll` 이면 세 단계 모두 허용
- 치명적 명령은 세 단계 모두 차단 + **파일을 만들지 않음**
- 허용 규칙 일치 시 세 단계 모두 허용 + `matchedRule`
- `sudo` 는 실행 단계 하나 + 기본 차단
