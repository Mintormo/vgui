# vgui

[English](README.md) | [Русский](README.ru.md) | **Deutsch** | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | [Português](README.pt.md) | [Polski](README.pl.md)

Eine GUI-Bibliothek für die Sprache [V](https://vlang.io) auf Basis von
[SDL3](https://libsdl.org). vgui zeichnet die gesamte Oberfläche selbst
(ohne native Widgets des Betriebssystems), unterstützt HiDPI, Themes,
Animationen und Übersetzungen und zeichnet nur die Teile des Fensters
neu, die sich geändert haben.

![vgui-Schaufenster, dunkles Theme](screenshots/showcase-dark.png)

## Funktionen

- **Bedienelemente** — Label, Button, CheckBox, RadioButton,
  ToggleSwitch, Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner,
  ProgressBar, Badge, DatePicker, ColorPicker, CurveEditor,
  ShortcutInput.
- **Komplexe Widgets** — CodeEditor mit Syntaxhervorhebung,
  MarkdownView, ListBox, TableView (virtueller Modus für Millionen
  Zeilen), TreeView, PropertyGrid, PlotView, Canvas (Zeichnen mit
  direktem Pixelzugriff), ImageView.
- **Container** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Layout ohne Pixelangaben: Ein Widget
  bekommt seine natürliche Größe oder einen Anteil am freien Platz
  (`flex`), dazu `min`, `max` und Ausrichtung.
- **Menüs und Overlays** — MenuBar mit Tastenkürzeln, MenuButton,
  ContextMenu, Tooltips an jedem Widget, Benachrichtigungen, modale
  Dialoge.
- **Integration ins Betriebssystem** — native Datei- und
  Ordnerdialoge, Infobereich (Tray), Drag-and-drop aus anderen
  Anwendungen, rahmenlose Fenster.
- **Aussehen** — 15 eingebaute Themes (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — helle und dunkle Varianten), CSS-ähnliche
  Stylesheets, Animationen, Skalierung der Oberfläche.
- **Alles dabei** — Lucide-Icons und Roboto-Schriften sind im Binary
  eingebettet, Übersetzung der Oberfläche (`vgui.i18n`), Undo/Redo,
  kompakte Oberflächenbeschreibung `.vui`.
- **Testen** — `testkit.v`: synthetische Eingaben und
  Render-Snapshots; Tests laufen ohne Bildschirm.

## Screenshots

Dasselbe Fenster ([`examples/59_showcase.v`](examples/59_showcase.v))
in den Themes Light und Monokai; das Theme lässt sich im laufenden
Betrieb wechseln.

![Helles Theme](screenshots/showcase-light.png)

![Monokai-Theme](screenshots/showcase-monokai.png)

Eine echte Anwendung mit vgui ist
[vraw](https://github.com/Mintormo/vraw), ein RAW-Entwickler:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Schnellstart

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

`box.add(w)` gibt einem Widget seine natürliche Größe,
`box.add(w, flex: 1)` einen Anteil am freien Platz; außerdem gibt es
`min:`, `max:` und `align:`. Ein Fenster ohne feste Größe passt sich
seinem Inhalt an.

## Bauen und Abhängigkeiten

vgui ist ein Quellmodul: Es muss nichts separat gebaut werden, die
Bibliothek wird in Ihr Programm einkompiliert. Die Hauptplattform ist
Linux (getestet unter Ubuntu 24.04). Windows-Programme werden unter
Linux cross-kompiliert (so entsteht die Windows-Version von vraw); ein
Bau direkt unter Windows in MSYS2 sollte funktionieren, ist aber noch
nicht getestet. Ein macOS-Zweig ist angelegt, aber nicht getestet.

| Komponente | Version | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| V-Compiler | 0.5.2 (a1c9e93) oder neuer | aus dem Quellcode (Schritt 3) | aus dem Quellcode |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | aus dem Quellcode (Schritt 2), noch nicht in den Paketquellen | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | aus dem Quellcode (Schritt 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | aus dem Quellcode (Schritt 2) | `mingw-w64-x86_64-sdl3-image` |

vgui lässt sich nur mit gcc bauen (`-cc gcc`).

### Linux

**1. Systempakete** — Compiler und die Bibliotheken, gegen die SDL3
gebaut wird:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

Unter Fedora, Arch und anderen Distributionen installieren Sie dieselben
Bibliotheken mit deren Paketverwaltung. Bietet sie bereits SDL3,
SDL3_ttf und SDL3_image 3.4 oder neuer (mit `-devel`/`-dev`-Paketen),
kann Schritt 2 entfallen.

**2. SDL3, SDL3_ttf, SDL3_image** — aus dem Quellcode gebaut und nach
`/usr/local` installiert:

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

**3. V-Compiler:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** Das Wurzelverzeichnis des Repositorys ist selbst das Modul
`vgui`; V findet es über `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Cross-Kompilierung unter Linux.** Installieren Sie MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) und legen Sie die
Windows-Builds von SDL3, SDL3_ttf und SDL3_image (Header,
Importbibliotheken und DLLs aus den MSYS2-Paketen `mingw64`) in ein
Präfix, zum Beispiel `~/soft/mingw64`. Dann:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Legen Sie die benötigten DLLs aus `$pfx/bin` neben die exe. Ein
vollständiges funktionierendes Beispiel — Herunterladen der
MSYS2-Pakete (`tools/win_deps.py`) und Einsammeln der DLLs
(`tools/windows.sh`) — findet sich im Repository
[vraw](https://github.com/Mintormo/vraw).

**Direkt in MSYS2 (noch nicht getestet).** Installieren Sie
[MSYS2](https://www.msys2.org), öffnen Sie die Shell **MSYS2 MINGW64**
und führen Sie aus:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Beispiele

[`examples/`](examples) enthält 58 kleine Programme, je eines pro
Widget oder Funktion (ihre Oberfläche ist auf Russisch), sowie
[`59_showcase.v`](examples/59_showcase.v) mit allem in einem Fenster.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # ein Beispiel
PATH=~/soft/v:$PATH examples/build.sh          # alle nach examples/bin/ bauen
```

## Tests

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Ein Bildschirm ist nicht nötig: SDL läuft mit dem Treiber `dummy`.

## Dokumentation

Der Code ist ausführlich kommentiert: Jede Datei beginnt mit einer
Beschreibung. Die Entwurfsnotizen sind auf Russisch:
[PROJECT.md](PROJECT.md) — wie jedes Teilsystem funktioniert (Layout,
Invalidierung, Rendering, Fokus, Overlays, Threads, Themes, i18n) und
warum, [ROADMAP.md](ROADMAP.md) — der Entwicklungsplan,
[docs/](docs) — Audits und Reviews.

## Mit Claude Code gemacht

vgui ist per Vibe-Coding entstanden: gemeinsam mit
[Claude Code](https://claude.com/claude-code), dem
KI-Programmierassistenten von Anthropic.

## Lizenz

[MIT](LICENSE). Fremdressourcen in `assets/` stehen unter ihren eigenen
Lizenzen: Roboto-Schriften — Apache License 2.0, DejaVu-Schriften —
Bitstream-Vera-Lizenz, Lucide-Icons — ISC.
