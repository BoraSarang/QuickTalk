#!/usr/bin/env bash
# QuickTalk 버전 올리기 — Info.plist 한 곳만 고친다(번들 표시 버전의 단일 출처).
#
# 규칙(DESIGN §14.6):
#   CFBundleShortVersionString = 1.<릴리스 번호>.<핫픽스>
#   CFBundleVersion            = <릴리스 번호><2자리 핫픽스>   (예: 35 0 → 3500)
#
# 사용법:
#   scripts/bump-version.sh 35        # v0.35 기능 릴리스   → 1.35.0 (3500)
#   scripts/bump-version.sh 35 1      # v0.35.1 핫픽스      → 1.35.1 (3501)
#   scripts/bump-version.sh --show    # 지금 값 확인
set -euo pipefail

PLIST="$(cd "$(dirname "$0")/.." && pwd)/QuickTalkApp/Info.plist"
PB=/usr/libexec/PlistBuddy

show() {
  echo "CFBundleShortVersionString = $($PB -c 'Print :CFBundleShortVersionString' "$PLIST")"
  echo "CFBundleVersion            = $($PB -c 'Print :CFBundleVersion' "$PLIST")"
}

if [[ "${1:-}" == "--show" ]]; then
  show
  exit 0
fi

release="${1:?릴리스 번호가 필요합니다. 예: scripts/bump-version.sh 36}"
hotfix="${2:-0}"

if ! [[ "$release" =~ ^[0-9]+$ ]]; then
  echo "릴리스 번호는 숫자여야 합니다: $release" >&2
  exit 2
fi
if ! [[ "$hotfix" =~ ^[0-9]+$ ]] || (( hotfix > 99 )); then
  echo "핫픽스는 0~99 사이 숫자여야 합니다: $hotfix" >&2
  exit 2
fi

version="1.${release}.${hotfix}"
build=$(printf "%d%02d" "$release" "$hotfix")

$PB -c "Set :CFBundleShortVersionString ${version}" "$PLIST"
$PB -c "Set :CFBundleVersion ${build}" "$PLIST"

echo "버전 갱신: ${version} (build ${build})"
show
