#!/bin/bash
# G560Studio.app 번들 생성 (개인용, ad-hoc 서명). 사용: scripts/bundle.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
CFG=${1:-debug}
swift build -c "$CFG" --product G560Studio
APP=build/G560Studio.app
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CFG/G560Studio" "$APP/Contents/MacOS/"
cp Sources/G560Studio/Info.plist "$APP/Contents/"
[ -d Assets ] && cp Assets/* "$APP/Contents/Resources/" 2>/dev/null || true
# 고정 identity로 서명해야 TCC 권한(오디오/화면 기록)이 빌드 후에도 유지된다. 없으면 ad-hoc.
xattr -cr "$APP"   # 확장 속성이 있으면 codesign이 거부한다
IDENTITY=${CODESIGN_IDENTITY:-"G560Studio Dev"}
if security find-identity -v -p codesigning | grep -q "\"$IDENTITY\""; then
  codesign --force --sign "$IDENTITY" "$APP"
  codesign -dvv "$APP" 2>&1 | grep "Authority=$IDENTITY" >/dev/null || { echo "error: 서명 실패"; exit 1; }
else
  echo "warning: '$IDENTITY' 인증서 없음 → ad-hoc 서명 (권한이 빌드마다 초기화됨). README 참고"; codesign --force --sign - "$APP"
fi
echo "built $APP"
echo "설치: cp -R $APP /Applications/   (로그인 시 시작은 /Applications 에서만 안정적)"
