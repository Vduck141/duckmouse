#!/bin/bash
# Phát hành DuckMouse: build ký tạm (ad-hoc – không lộ email chứng chỉ) → zip + DMG (app + lối tắt Applications + hướng dẫn)
# Dùng: bash "Ma nguon/phat-hanh/phat-hanh.sh" <bản, vd 1.0.0> [--github]   (--github: tạo Release + đính kèm file)
set -e
cd "$(dirname "$0")/.."
BAN="${1:?Thiếu số bản, vd 1.0.0}"
OUT="${TMPDIR:-/tmp}/duckmouse-phat-hanh-$BAN"
rm -rf "$OUT"; mkdir -p "$OUT"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $BAN" Info.plist
KY_APP=- ./build.sh "$OUT/build" >/dev/null
APP="$OUT/build/DuckMouse.app"
codesign -v "$APP"
ditto -c -k --keepParent "$APP" "$OUT/DuckMouse.$BAN.zip"
mkdir -p "$OUT/dmg"; cp -R "$APP" "$OUT/dmg/"; ln -s /Applications "$OUT/dmg/Applications"
cp ../HUONG-DAN-CAI.md "$OUT/dmg/Hướng dẫn mở lần đầu.md"
hdiutil create -volname "DuckMouse $BAN" -srcfolder "$OUT/dmg" -ov -format UDZO "$OUT/DuckMouse.$BAN.dmg" >/dev/null
ls -la "$OUT"/*.zip "$OUT"/*.dmg
if [ "$2" = "--github" ]; then
  cd ..
  gh release create "v$BAN" "$OUT/DuckMouse.$BAN.dmg" "$OUT/DuckMouse.$BAN.zip" --title "DuckMouse $BAN" --notes-file "Ma nguon/phat-hanh/ghi-chu-$BAN.md"
fi
echo "Xong: $OUT"
