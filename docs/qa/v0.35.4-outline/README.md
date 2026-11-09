# v0.35.4 — 대화 목차 현재 위치 (수정 전/후 증거)

> 2026-11-09 · Release/Debug 1.35.4 · 실제 저장 대화를 400×560 오프스크린 창에 렌더.

## 증상 (수정 전 v0.35.3)

- 대화를 열거나 갈아타면 오른쪽 목차 레일의 보라색 표시가 **항상 첫 질문**.
- 펼친 목차도 첫 질문을 강조하고 그 위치로 스크롤.

## 실측 (`--outline-probe`)

```bash
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=/tmp/qt-outline --outline-probe
```

수정 전 (34턴, 바닥에 있는데도):

```
[OUTLINE] offset=7113 anchor=7121 entries=17 start=32 known=0 [] current=0
```

좌표가 0개라 `visibleIndex` 가 첫 질문을 반환했다. 대화 전환·폭 변경에서 측정값을 비운 뒤
VStack 이 같은 좌표를 다시 올리지 않아 생긴 문제(자세한 원인: PLAN §2).

수정 후:

```
[OUTLINE] offset=0    anchor=8    entries=17 start=32 floor=16 known=1 [16:62] current=16
[OUTLINE] offset=3556 anchor=3564 entries=17 start=32 floor=16 known=1 [16:62] current=16
[OUTLINE] offset=7113 anchor=7121 entries=17 start=32 floor=16 known=1 [16:62] current=16
```

`--expanded`(17질문 전부): 위 `0` · 중간 `11` · 아래 `16`.
22턴 대화로 전환: `floor=6`, 아래 `9` — 새 대화 기준으로 다시 잡힌다.

## 화면 증거

| 파일 | 내용 |
|------|------|
| `all-3-34t.png` | 34턴 대화 바닥 핀. 레일 눈금 17개 중 **마지막**이 보라 막대(최상위 아님). |
| `all-1-22t.png` | 22턴 대화 바닥 핀. 보라 막대가 아래쪽(10번째 질문). |
| `all-0-6t.png`, `all-2-4t.png` | 짧은 대화 — 표시가 마지막 질문 근처. |

> ⚠️ 오프스크린 `cacheDisplay` 는 머티리얼(도구 카드·입력독 캡슐)을 **흰 블록**으로 그린다.
> 실앱 렌더와 무관한 캡처 한계이며, 위치 판정은 `[OUTLINE]` 로그와 레일 픽셀로 한다.

## 재현

```bash
# 목차 위치 로그 (열기·중간·위·아래·대화 전환)
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=/tmp/qt-outline --outline-probe

# 윈도 없이 전 턴을 그린 상태에서 위치 매핑
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=/tmp/qt-outline --outline-probe --expanded

# 빈 화면 회귀 확인
./build-release/Build/Products/Release/QuickTalk.app/Contents/MacOS/QuickTalk \
  --live-shot-all=$PWD/docs/qa/v0.35.4-outline
```

배경·한계: `docs/plans/PLAN_v0.35.4_outline-position_macos.md`, `docs/DESIGN.md` §14.7.
