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
codesign --force --sign - "$APP"
echo "built $APP"
