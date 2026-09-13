#!/bin/bash
# 릴리즈 zip 생성: build/G560Studio-<version>.zip  (사용: scripts/release.sh)
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/bundle.sh release >/dev/null
VER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' build/G560Studio.app/Contents/Info.plist)
OUT="build/G560Studio-$VER.zip"
rm -f "$OUT"
ditto -c -k --keepParent build/G560Studio.app "$OUT"
shasum -a 256 "$OUT"
echo "$OUT"
