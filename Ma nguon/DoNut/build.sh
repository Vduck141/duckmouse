#!/bin/bash
# Build «DuckMouse Dò nút» (chỉ arm64). Dùng: ./build.sh <thư mục ra>  → <ra>/DuckMouse Dò nút.app + .zip
set -e
cd "$(dirname "$0")"
OUT="${1:-${TMPDIR:-/tmp}/DoNut-build}"
APP="$OUT/DuckMouse Dò nút.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 *.swift -o "$APP/Contents/MacOS/DoNut"
cp Info.plist "$APP/Contents/Info.plist"
cp ../AppIcon.icns "$APP/Contents/Resources/"
KY="${KY_APP:-$(cat ../.ky-app 2>/dev/null)}"
codesign --force --deep --options runtime -s "${KY:--}" "$APP"
(cd "$OUT" && rm -f "DuckMouse-Do-nut.zip" && ditto -c -k --keepParent "DuckMouse Dò nút.app" "DuckMouse-Do-nut.zip")
echo "Đã build: $APP"
