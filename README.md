# Launchpad Classic

Klon klasycznego Launchpada (macOS Big Sur – Sequoia) dla macOS 26 Tahoe.

## Budowanie i instalacja

Potrzebny jest Xcode albo same narzędzia wiersza poleceń (`xcode-select --install`).

```bash
cd LaunchpadClassic
chmod +x build.sh
./build.sh install      # buduje, kopiuje do /Applications i uruchamia
```

Samo `./build.sh` buduje aplikację do katalogu `build/`.

Następnie przeciągnij **Launchpad Classic** z /Applications do Docka (w miejsce systemowej ikony „Aplikacje”).

## Co działa jak w oryginale

- Pełnoekranowa siatka 7 × 5 na rozmytej tapecie, strony z kropkami na dole.
- Przewijanie stron gestem dwoma palcami na gładziku, kółkiem myszy, ⌘← / ⌘→ i kliknięciem w kropki.
- Wyszukiwanie: wystarczy zacząć pisać; ↑↓←→ wybiera, Return uruchamia.
- Tryb edycji („trzęsące się” ikony): przytrzymaj ikonę albo od razu ją przeciągnij.
- Przestawianie ikon z płynnym rozsuwaniem, przenoszenie na inną stronę przez przytrzymanie przy krawędzi ekranu.
- Foldery: upuść ikonę na ikonę. Nazwa folderu bierze się z kategorii aplikacji (np. „Produktywność”) i można ją zmienić kliknięciem w tytuł.
  Wyciągnięcie ikony poza otwarty folder przenosi ją na stronę; folder z jedną aplikacją znika.
- Nowe aplikacje pojawiają się na końcu, usunięte (w Finderze) znikają automatycznie.
- Esc zamyka kolejno: wyszukiwanie, folder, tryb edycji, Launchpada. Kliknięcie w tło też zamyka.
- Domyślny układ: aplikacje Apple, folder „Inne” z narzędziami systemowymi, potem pozostałe alfabetycznie.
- Przy pierwszym uruchomieniu program próbuje zaimportować Twój stary układ z bazy dawnego Launchpada, jeśli przetrwała aktualizację.

## Ustawienia (prawy klik na tle)

- **Skrót klawiszowy**: domyślnie ⌃⌘L, do wyboru ⌥⌘L, ⌥ Spacja, ⌃⌥ Spacja.
- **Gorący narożnik**: dowolny róg ekranu. Wyłącz systemowy narożnik w tym samym rogu, żeby się nie gryzły.
- **Otwieraj przy logowaniu**
- Odśwież listę aplikacji / Importuj układ ze starego Launchpada / Ułóż alfabetycznie.

Układ zapisuje się w `~/Library/Application Support/LaunchpadClassic/layout.json`, a przed resetem lub importem robiona jest kopia `layout.backup.json`.

## Ograniczenia

- Systemowego gestu szczypnięcia i klawisza F4 nie da się przejąć bez grzebania w systemie; one dalej otwierają „Aplikacje”.
  Gest możesz wyłączyć w Ustawieniach systemowych → Gładzik → Więcej gestów.
- Usuwanie aplikacji odbywa się w Finderze (celowo nie ma krzyżyków).
