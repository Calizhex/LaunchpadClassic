#!/bin/bash
# Buduje „Launchpad Classic.app”. Wymaga Xcode albo Command Line Tools (xcode-select --install).
#   ./build.sh           – zbuduj do ./build
#   ./build.sh install   – zbuduj, skopiuj do /Applications i uruchom
#   ./build.sh dmg       – zbuduj i spakuj do build/LaunchpadClassic.dmg
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Launchpad Classic"
EXEC="LaunchpadClassic"
BUILD="build"
APP="$BUILD/$APP_NAME.app"
ARCH="$(uname -m)"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Brak kompilatora Swift. Zainstaluj Xcode lub uruchom: xcode-select --install"
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "▸ Kompilacja ($ARCH)…"
xcrun swiftc -O -swift-version 5 -parse-as-library \
  -target "$ARCH-apple-macos14.0" \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/$EXEC"

cp Resources/Info.plist "$APP/Contents/Info.plist"
BUILD_NUMBER="${BUILD_NUMBER:-${GITHUB_RUN_NUMBER:-0}}"
/usr/libexec/PlistBuddy \
  -c "Set :CFBundleVersion $BUILD_NUMBER" \
  -c "Set :CFBundleShortVersionString 1.$BUILD_NUMBER" \
  "$APP/Contents/Info.plist"
echo "▸ Wersja: 1.$BUILD_NUMBER (build $BUILD_NUMBER)"

echo "▸ Ikona…"
if xcrun swift Tools/MakeIcon.swift "$BUILD/icon_1024.png" 2>/dev/null; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d "$BUILD/icon_1024.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
else
  echo "  (pominięto – nie udało się wygenerować ikony)"
fi

echo "▸ Podpis lokalny…"
codesign --force --sign - "$APP"

echo "✓ Gotowe: $APP"

if [[ "${1:-}" == "install" ]]; then
  pkill -x "$EXEC" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  echo "✓ Zainstalowano w /Applications"
  open "/Applications/$APP_NAME.app"
fi

if [[ "${1:-}" == "dmg" ]]; then
  echo "▸ Tworzenie obrazu .dmg…"
  STAGE="$BUILD/dmg"
  rm -rf "$STAGE" "$BUILD/LaunchpadClassic.dmg"
  mkdir -p "$STAGE"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/LaunchpadClassic.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "✓ Gotowe: $BUILD/LaunchpadClassic.dmg"
fi
