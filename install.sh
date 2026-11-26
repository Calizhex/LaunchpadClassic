#!/bin/bash
# Instaluje najnowszą wersję Launchpad Classic do /Applications.
# Użycie: curl -fsSL https://raw.githubusercontent.com/Calizhex/LaunchpadClassic/main/install.sh | bash
set -euo pipefail

APP="Launchpad Classic.app"
URL="https://github.com/Calizhex/LaunchpadClassic/releases/latest/download/LaunchpadClassic.dmg"
TMP="$(mktemp -d)"
MNT="$TMP/mnt"
trap 'hdiutil detach "$MNT" -quiet 2>/dev/null || true; rm -rf "$TMP"' EXIT

echo "▸ Pobieranie najnowszej wersji…"
curl -fsSL -o "$TMP/LaunchpadClassic.dmg" "$URL"

echo "▸ Instalowanie…"
mkdir -p "$MNT"
hdiutil attach "$TMP/LaunchpadClassic.dmg" -nobrowse -noautoopen -readonly -mountpoint "$MNT" -quiet
pkill -x LaunchpadClassic 2>/dev/null || true
rm -rf "/Applications/$APP"
ditto "$MNT/$APP" "/Applications/$APP"
xattr -dr com.apple.quarantine "/Applications/$APP" 2>/dev/null || true

echo "✓ Zainstalowano w /Applications. Uruchamiam…"
open "/Applications/$APP"
