#!/bin/bash
# Build DuckMouse (chỉ arm64). Dùng: ./build.sh <thư mục ra>   (mặc định $TMPDIR/DuckMouse-build)
# Ký bằng chứng chỉ riêng (nếu có) để quyền Trợ năng không mất sau mỗi bản build.
set -e
cd "$(dirname "$0")"
OUT="${1:-${TMPDIR:-/tmp}/DuckMouse-build}"
APP="$OUT/DuckMouse.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 \
  Sources/*.swift -o "$APP/Contents/MacOS/DuckMouse"
cp Info.plist "$APP/Contents/Info.plist"
[ -f AppIcon.icns ] || ./tao-icon.sh
cp AppIcon.icns "$APP/Contents/Resources/"
# Dữ liệu 100 chuột + ảnh chuột minh hoạ
cp Resources/mice.json "$APP/Contents/Resources/mice.json"
[ -f Resources/chuot.png ] && cp Resources/chuot.png "$APP/Contents/Resources/"
# Ký: mã chứng chỉ trong biến KY_APP hoặc file .ky-app (cạnh build.sh); không có → ký tạm (ad-hoc)
KY="${KY_APP:-$(cat .ky-app 2>/dev/null)}"
codesign --force --deep --options runtime -s "${KY:--}" "$APP"
echo "Đã build: $APP"
