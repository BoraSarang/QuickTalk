# v0.35.3 — 긴 대화 빈 화면 (수정 전/후 증거)

> 2026-11-09 · Release/Debug 1.35.3 · 실제 저장 대화 4개를 400×560 오프스크린 창에 렌더.

## 수정 전 (v0.35.1 LazyVStack)

| 파일 | 내용 |
|------|------|
| `live-narrow.png` | **빈 화면 재현** — 400×560, 헤더·기억 칩·입력독만 보이고 본문이 없다. |
| `live-wide.png` | 650폭에서는 내용이 보임(추정 오차가 작아 우연히 착지). |

원인: LazyVStack 이 만들지 않은 행의 높이를 **추정**해 문서 끝 핀이 실제 내용 뒤 **빈 꼬리**에 착지.
400폭 추정 8,233pt vs 실제 7,665pt, 34턴은 추정 238,590pt.

## 수정 후 (VStack + 윈도잉)

하네스: `--live-shot-all=<폴더>` (Debug/Release 바이너리, `[LIVE-ALL]` 로그).

| 폴더 | 명령 | 결과 |
|------|------|------|
| `top/` | `--top` | 전 대화 바닥 `dist=0`·`ink>0`, 상단은 `이전 대화 더 보기`부터. |
| `expanded/` | `--expanded` | 34턴 전체(38,085pt)에서도 `dist=0`·`ink>0`. |
| (로그만) | `--rapid` | 8회 연속 대화 전환 뒤 34턴 `dist=0`, `ink=8735`. |
| (로그만) | `--focus-old` | 목차로 가장 오래된 질문 점프 — 문서 7,579→38,085pt 확장, `offset=0`, `ink>0`. |

> ⚠️ 오프스크린 `cacheDisplay` 는 머티리얼(도구 카드·시트·버튼 캡슐)을 **흰 블록**으로 그린다.
> 실앱 렌더와 무관한 캡처 한계이며, 판정은 `dist`(바닥까지 거리)·`ink`(내용 픽셀)로 한다.

## 재현

```bash
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=$PWD/docs/qa/v0.35.3-blank/check --top
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=/tmp/qt-rapid --rapid
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk --switch-perf-live
```

자세한 배경·한계: `docs/plans/PLAN_v0.35.3_chat-blank_macos.md`, `docs/DESIGN.md` §14.5.
