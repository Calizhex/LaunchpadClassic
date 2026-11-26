#!/bin/bash
# Kliknij dwukrotnie, żeby zbudować i zainstalować Launchpad Classic.
cd "$(dirname "$0")" || exit 1
clear
echo "=== Launchpad Classic – instalacja ==="
echo

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Potrzebne są narzędzia programistyczne Apple (Command Line Tools)."
  echo "Za chwilę pojawi się okno instalatora – kliknij „Instaluj”."
  echo "Gdy instalacja się skończy, kliknij ponownie dwukrotnie ten plik."
  xcode-select --install 2>/dev/null
  echo
  read -r -p "Naciśnij Enter, aby zamknąć…"
  exit 0
fi

if bash ./build.sh install; then
  echo
  echo "✓ Launchpad Classic jest w /Applications i właśnie się uruchomił."
  echo "  Przeciągnij go do Docka. Skrót: ⌃⌘L, ustawienia: prawy klik na tle."
else
  echo
  echo "✗ Budowanie się nie udało. Skopiuj powyższy tekst i wyślij go Claude'owi."
fi
echo
read -r -p "Naciśnij Enter, aby zamknąć…"
