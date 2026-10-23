# vgui

[English](README.md) | [Русский](README.ru.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | [Português](README.pt.md) | **Polski**

Biblioteka GUI dla języka [V](https://vlang.io) oparta na
[SDL3](https://libsdl.org). vgui sama rysuje cały interfejs (bez
natywnych kontrolek systemu), obsługuje HiDPI, motywy, animacje i
tłumaczenia, a przerysowuje tylko te części okna, które się zmieniły.

![Wizytówka vgui, ciemny motyw](screenshots/showcase-dark.png)

## Możliwości

- **Kontrolki** — Label, Button, CheckBox, RadioButton, ToggleSwitch,
  Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner, ProgressBar,
  Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Złożone widżety** — CodeEditor z podświetlaniem składni,
  MarkdownView, ListBox, TableView (tryb wirtualny dla milionów
  wierszy), TreeView, PropertyGrid, PlotView, Canvas (rysowanie z
  bezpośrednim dostępem do pikseli), ImageView.
- **Kontenery** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Układ bez pikseli: widżet dostaje swój
  naturalny rozmiar albo część wolnego miejsca (`flex`), do tego `min`,
  `max` i wyrównanie.
- **Menu i nakładki** — MenuBar ze skrótami klawiszowymi, MenuButton,
  ContextMenu, podpowiedzi przy każdym widżecie, powiadomienia, okna
  modalne.
- **Integracja z systemem** — natywne okna wyboru plików i folderów,
  zasobnik systemowy, przeciąganie i upuszczanie z innych programów,
  okna bez ramki.
- **Wygląd** — 15 wbudowanych motywów (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — jasne i ciemne warianty), arkusze stylów w
  stylu CSS, animacje, skalowanie interfejsu.
- **Wszystko w zestawie** — ikony Lucide i czcionki Roboto wbudowane w
  plik wykonywalny, tłumaczenie interfejsu (`vgui.i18n`), cofnij/ponów,
  zwięzły opis interfejsu `.vui`.
- **Testy** — `testkit.v`: syntetyczne wejście i migawki renderowania;
  testy działają bez ekranu.

## Zrzuty ekranu

To samo okno ([`examples/59_showcase.v`](examples/59_showcase.v)) w
motywach Light i Monokai; motyw można zmieniać w locie.

![Jasny motyw](screenshots/showcase-light.png)

![Motyw Monokai](screenshots/showcase-monokai.png)

Prawdziwy program zbudowany na vgui to
[vraw](https://github.com/Mintormo/vraw), wywoływarka zdjęć RAW:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Szybki start

```v
module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Hello')!

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)

	mut counter := vgui.label('Clicks: 0')
	mut clicks := 0
	mut btn := vgui.button('Click me')
	btn.on_click = fn [mut counter, mut clicks] () {
		clicks++
		counter.text = 'Clicks: ${clicks}'
	}
	root.add(counter)
	root.add(btn)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
```

```bash
~/soft/v/v -cc gcc run hello.v
```

`box.add(w)` daje widżetowi jego naturalny rozmiar,
`box.add(w, flex: 1)` — część wolnego miejsca; są też `min:`, `max:` i
`align:`. Okno bez podanego rozmiaru dopasowuje się do zawartości.

## Budowanie i zależności

vgui to moduł w postaci źródeł: niczego nie trzeba budować osobno,
biblioteka kompiluje się razem z programem. Główną platformą jest Linux
(testowane na Ubuntu 24.04). Programy dla Windows są kompilowane
skrośnie na Linuksie (tak powstaje wersja vraw dla Windows); budowanie
bezpośrednio w Windows w MSYS2 powinno działać, ale nie zostało jeszcze
sprawdzone. Gałąź dla macOS jest przygotowana, ale nie sprawdzona.

| Składnik | Wersja | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| Kompilator V | 0.5.2 (a1c9e93) lub nowszy | ze źródeł (krok 3) | ze źródeł |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | ze źródeł (krok 2), jeszcze nie ma jej w repozytoriach | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | ze źródeł (krok 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | ze źródeł (krok 2) | `mingw-w64-x86_64-sdl3-image` |

vgui buduje się tylko kompilatorem gcc (`-cc gcc`).

### Linux

**1. Pakiety systemowe** — kompilator i biblioteki, z którymi budowane
jest SDL3:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

W Fedorze, Archu i innych dystrybucjach zainstaluj te same biblioteki
ich menedżerem pakietów. Jeśli ma już SDL3, SDL3_ttf i SDL3_image 3.4
lub nowsze (z pakietami `-devel`/`-dev`), pomiń krok 2.

**2. SDL3, SDL3_ttf, SDL3_image** — budowane ze źródeł i instalowane w
`/usr/local`:

```bash
mkdir -p ~/src && cd ~/src
for repo in SDL SDL_ttf SDL_image; do
  git clone --depth 1 https://github.com/libsdl-org/$repo
  cmake -S $repo -B $repo/build -DCMAKE_BUILD_TYPE=Release
  cmake --build $repo/build -j"$(nproc)"
  sudo cmake --install $repo/build
done
sudo ldconfig
```

**3. Kompilator V:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** Katalog główny repozytorium to sam moduł `vgui`; V
znajduje go przez `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Kompilacja skrośna na Linuksie.** Zainstaluj MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) i umieść wersje SDL3,
SDL3_ttf i SDL3_image dla Windows (nagłówki, biblioteki importu i DLL
z pakietów MSYS2 `mingw64`) w jednym prefiksie, na przykład
`~/soft/mingw64`. Następnie:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Obok pliku exe połóż potrzebne mu biblioteki DLL z `$pfx/bin`. Pełny,
działający przykład — pobieranie pakietów MSYS2 (`tools/win_deps.py`) i
zbieranie DLL (`tools/windows.sh`) — jest w repozytorium
[vraw](https://github.com/Mintormo/vraw).

**Bezpośrednio w MSYS2 (jeszcze nie sprawdzone).** Zainstaluj
[MSYS2](https://www.msys2.org), otwórz powłokę **MSYS2 MINGW64** i
wykonaj:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Przykłady

[`examples/`](examples) zawiera 58 małych programów, po jednym na widżet
lub funkcję, oraz
[`59_showcase.v`](examples/59_showcase.v) ze wszystkim w jednym oknie.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # jeden przykład
PATH=~/soft/v:$PATH examples/build.sh          # zbudować wszystkie do examples/bin/
```

## Testy

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Ekran nie jest potrzebny: SDL działa ze sterownikiem `dummy`.

## Dokumentacja

Kod jest szczegółowo skomentowany: każdy plik zaczyna się nagłówkiem z
opisem. Notatki projektowe są po rosyjsku:
[PROJECT.md](PROJECT.md) — jak działa każdy podsystem (układ,
unieważnianie, renderowanie, fokus, nakładki, wątki, motywy, i18n) i
dlaczego, [ROADMAP.md](ROADMAP.md) — plan rozwoju,
[docs/](docs) — audyty i przeglądy.

## Zrobione z Claude Code

vgui powstała metodą vibe codingu: napisana wspólnie z
[Claude Code](https://claude.com/claude-code), asystentem programowania
AI od Anthropic.

## Licencja

[MIT](LICENSE). Zasoby zewnętrzne w `assets/` podlegają własnym
licencjom: czcionki Roboto — Apache License 2.0, czcionki DejaVu —
licencja Bitstream Vera, ikony Lucide — ISC.
