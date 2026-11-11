# v0.36.1 — "리포트 폴더" → 작업 폴더

설정 › 비서 탭의 폴더 섹션을 **작업 폴더**(`~/Documents/QuickTalkWorkspace`)로 바꾼 렌더.

| 파일 | 내용 |
| --- | --- |
| `settings-assistant-ko.png` | 설정 › 비서 — "작업 폴더" 제목, `~/Documents/QuickTalkWorkspace` 경로, 캡션 "도우미가 만든 파일과 예약 리포트가 저장되는 곳입니다." |

## 이전 규칙 (자동으로 옮기는 범위)

- 저장된 경로의 **마지막 조각이 `QuickTalkReport`** 일 때만 `~/Documents/QuickTalkWorkspace` 로 이름을 바꾼다.
- 새 폴더가 이미 있으면 **합치지 않는다** — 둘 다 있으면 설정을 그대로 두고 로그만 남긴다.
- 옛 폴더가 없으면 **설정만** 새 기본값으로 바꾼다(폴더는 필요할 때 만든다).
- 사용자가 직접 고른 경로·비슷한 이름(`QuickTalkReportOld`)은 건드리지 않는다.

렌더 명령:

```sh
"$HOME/Library/Developer/Xcode/DerivedData/QuickTalk-eqgngjmrotqlcqdfzibbjwejdqqt/Build/Products/Debug/QuickTalk.app/Contents/MacOS/QuickTalk" \
  --render=docs/qa/v0.36.1-workspace --settings-tab=assistant --lang=korean
```

> 렌더 하네스는 실제 `UIStore` 를 만든다 — 실행 중 이전이 아직 안 됐다면 이 명령이 실제 작업 폴더를 옮길 수 있다.
