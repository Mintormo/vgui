# vgui

[English](README.md) | [Русский](README.ru.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | **Nederlands** | [Português](README.pt.md) | [Polski](README.pl.md)

Een GUI-bibliotheek voor de taal [V](https://vlang.io) bovenop
[SDL3](https://libsdl.org). vgui tekent de hele interface zelf (zonder
native widgets van het besturingssysteem), ondersteunt HiDPI, thema's,
animaties en vertalingen, en tekent alleen de delen van het venster
opnieuw die veranderd zijn.

![vgui-etalage, donker thema](screenshots/showcase-dark.png)

## Mogelijkheden

- **Bedieningselementen** — Label, Button, CheckBox, RadioButton,
  ToggleSwitch, Slider, Spinbox, TextInput, TextArea, ComboBox,
  Spinner, ProgressBar, Badge, DatePicker, ColorPicker, CurveEditor,
  ShortcutInput.
- **Complexe widgets** — CodeEditor met syntaxiskleuring,
  MarkdownView, ListBox, TableView (virtuele modus voor miljoenen
  rijen), TreeView, PropertyGrid, PlotView, Canvas (tekenen met directe
  toegang tot pixels), ImageView.
- **Containers** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Opmaak zonder pixels: een widget krijgt
  zijn natuurlijke grootte of een deel van de vrije ruimte (`flex`),
  met `min`, `max` en uitlijning.
- **Menu's en overlays** — MenuBar met sneltoetsen, MenuButton,
  ContextMenu, tooltips op elke widget, meldingen, modale dialogen.
- **Integratie met het systeem** — native bestands- en mapdialogen,
  systeemvak, slepen en neerzetten vanuit andere programma's, vensters
  zonder rand.
- **Uiterlijk** — 15 ingebouwde thema's (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — lichte en donkere varianten), CSS-achtige
  stylesheets, animaties, schaling van de interface.
- **Alles inbegrepen** — Lucide-pictogrammen en Roboto-lettertypen zijn
  in het programma ingebouwd, vertaling van de interface (`vgui.i18n`),
  ongedaan maken/opnieuw, compacte interfacebeschrijving `.vui`.
- **Testen** — `testkit.v`: synthetische invoer en render-snapshots;
  tests draaien zonder scherm.

## Schermafbeeldingen

Hetzelfde venster ([`examples/59_showcase.v`](examples/59_showcase.v))
in de thema's Light en Monokai; het thema wissel je terwijl het
programma draait.

![Licht thema](screenshots/showcase-light.png)

![Monokai-thema](screenshots/showcase-monokai.png)

Een echt programma gemaakt met vgui is
[vraw](https://github.com/Mintormo/vraw), een RAW-ontwikkelaar:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Snel aan de slag

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

`box.add(w)` geeft een widget zijn natuurlijke grootte,
`box.add(w, flex: 1)` een deel van de vrije ruimte; er zijn ook `min:`,
`max:` en `align:`. Een venster zonder vaste grootte past zich aan de
inhoud aan.

## Bouwen en afhankelijkheden

vgui is een bronmodule: er hoeft niets apart gebouwd te worden, de
bibliotheek wordt mee gecompileerd in uw programma. Het hoofdplatform
is Linux (getest op Ubuntu 24.04). Windows-programma's worden op Linux
gecross-compileerd (zo wordt de Windows-versie van vraw gemaakt);
rechtstreeks bouwen op Windows in MSYS2 zou moeten werken, maar is nog
niet getest. Een macOS-tak is aanwezig, maar niet getest.

| Onderdeel | Versie | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| V-compiler | 0.5.2 (a1c9e93) of nieuwer | vanuit de broncode (stap 3) | vanuit de broncode |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | vanuit de broncode (stap 2), nog niet in de pakketbronnen | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | vanuit de broncode (stap 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | vanuit de broncode (stap 2) | `mingw-w64-x86_64-sdl3-image` |

vgui bouwt alleen met gcc (`-cc gcc`).

### Linux

**1. Systeempakketten** — compiler en de bibliotheken waarmee SDL3
wordt gebouwd:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

Op Fedora, Arch en andere distributies installeert u dezelfde
bibliotheken met hun pakketbeheerder. Levert die al SDL3, SDL3_ttf en
SDL3_image 3.4 of nieuwer (met `-devel`/`-dev`-pakketten), sla dan
stap 2 over.

**2. SDL3, SDL3_ttf, SDL3_image** — vanuit de broncode gebouwd en
geïnstalleerd in `/usr/local`:

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

**3. V-compiler:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** De hoofdmap van de repository is zelf de module `vgui`; V
vindt die via `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Cross-compileren op Linux.** Installeer MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) en zet de Windows-builds van
SDL3, SDL3_ttf en SDL3_image (headers, importbibliotheken en DLL's uit
de MSYS2-pakketten `mingw64`) in één prefix, bijvoorbeeld
`~/soft/mingw64`. Daarna:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Zet de benodigde DLL's uit `$pfx/bin` naast de exe. Een volledig
werkend voorbeeld — downloaden van de MSYS2-pakketten
(`tools/win_deps.py`) en verzamelen van de DLL's (`tools/windows.sh`) —
staat in de repository [vraw](https://github.com/Mintormo/vraw).

**Rechtstreeks in MSYS2 (nog niet getest).** Installeer
[MSYS2](https://www.msys2.org), open de shell **MSYS2 MINGW64** en voer
uit:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Voorbeelden

[`examples/`](examples) bevat 58 kleine programma's, één per widget of
functie, plus
[`59_showcase.v`](examples/59_showcase.v) met alles in één venster.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # één voorbeeld
PATH=~/soft/v:$PATH examples/build.sh          # alles bouwen in examples/bin/
```

## Tests

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Er is geen scherm nodig: SDL draait met het stuurprogramma `dummy`.

## Documentatie

De code is uitgebreid van commentaar voorzien: elk bestand begint met
een beschrijving. De ontwerpnotities zijn in het Russisch:
[PROJECT.md](PROJECT.md) — hoe elk subsysteem werkt (opmaak,
invalidatie, rendering, focus, overlays, threads, thema's, i18n) en
waarom, [ROADMAP.md](ROADMAP.md) — het ontwikkelplan,
[docs/](docs) — audits en reviews.

## Gemaakt met Claude Code

vgui is gevibecodeerd: samen geschreven met
[Claude Code](https://claude.com/claude-code), de
AI-programmeerassistent van Anthropic.

## Licentie

[MIT](LICENSE). Bronnen van derden in `assets/` vallen onder hun eigen
licenties: Roboto-lettertypen — Apache License 2.0,
DejaVu-lettertypen — Bitstream Vera-licentie, Lucide-pictogrammen —
ISC.
