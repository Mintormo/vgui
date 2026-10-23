# vgui

[English](README.md) | [Русский](README.ru.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | **Italiano** | [Nederlands](README.nl.md) | [Português](README.pt.md) | [Polski](README.pl.md)

Una libreria grafica per il linguaggio [V](https://vlang.io) basata su
[SDL3](https://libsdl.org). vgui disegna da sé l'intera interfaccia
(senza widget nativi del sistema), supporta HiDPI, temi, animazioni e
traduzioni e ridisegna solo le parti della finestra che sono cambiate.

![Vetrina di vgui, tema scuro](screenshots/showcase-dark.png)

## Funzionalità

- **Controlli** — Label, Button, CheckBox, RadioButton, ToggleSwitch,
  Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner, ProgressBar,
  Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Widget complessi** — CodeEditor con evidenziazione della sintassi,
  MarkdownView, ListBox, TableView (modalità virtuale per milioni di
  righe), TreeView, PropertyGrid, PlotView, Canvas (disegno con accesso
  diretto ai pixel), ImageView.
- **Contenitori** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Layout senza pixel: un widget riceve la
  sua dimensione naturale o una quota dello spazio libero (`flex`), con
  `min`, `max` e allineamento.
- **Menu e sovrapposizioni** — MenuBar con scorciatoie da tastiera,
  MenuButton, ContextMenu, suggerimenti su qualsiasi widget,
  notifiche, finestre di dialogo modali.
- **Integrazione con il sistema** — finestre di dialogo native per file
  e cartelle, area di notifica, trascinamento da altre applicazioni,
  finestre senza bordo.
- **Aspetto** — 15 temi integrati (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — varianti chiare e scure), fogli di stile in stile
  CSS, animazioni, ridimensionamento dell'interfaccia.
- **Tutto incluso** — icone Lucide e font Roboto incorporati nel
  binario, traduzione dell'interfaccia (`vgui.i18n`), annulla/ripeti,
  descrizione compatta dell'interfaccia `.vui`.
- **Test** — `testkit.v`: input sintetico e istantanee del rendering; i
  test girano senza schermo.

## Screenshot

La stessa finestra ([`examples/59_showcase.v`](examples/59_showcase.v))
con i temi Light e Monokai; il tema si cambia al volo.

![Tema chiaro](screenshots/showcase-light.png)

![Tema Monokai](screenshots/showcase-monokai.png)

Un'applicazione reale costruita con vgui è
[vraw](https://github.com/Mintormo/vraw), uno sviluppatore di foto RAW:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Avvio rapido

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

`box.add(w)` dà al widget la sua dimensione naturale,
`box.add(w, flex: 1)` una quota dello spazio libero; ci sono anche
`min:`, `max:` e `align:`. Una finestra senza dimensione esplicita si
adatta al contenuto.

## Compilazione e dipendenze

vgui è un modulo sorgente: non c'è nulla da compilare a parte, la
libreria viene compilata insieme al vostro programma. La piattaforma
principale è Linux (provato su Ubuntu 24.04). I programmi per Windows
vengono cross-compilati su Linux (così è fatta la versione Windows di
vraw); la compilazione direttamente su Windows in MSYS2 dovrebbe
funzionare, ma non è ancora stata provata. Un ramo per macOS è
predisposto, ma non provato.

| Componente | Versione | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| Compilatore V | 0.5.2 (a1c9e93) o successiva | dai sorgenti (passo 3) | dai sorgenti |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | dai sorgenti (passo 2), non ancora nei repository | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | dai sorgenti (passo 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | dai sorgenti (passo 2) | `mingw-w64-x86_64-sdl3-image` |

vgui si compila solo con gcc (`-cc gcc`).

### Linux

**1. Pacchetti di sistema** — compilatore e librerie con cui viene
compilata SDL3:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

Su Fedora, Arch e altre distribuzioni installate le stesse librerie con
il loro gestore di pacchetti. Se fornisce già SDL3, SDL3_ttf e
SDL3_image 3.4 o successive (con i pacchetti `-devel`/`-dev`), saltate
il passo 2.

**2. SDL3, SDL3_ttf, SDL3_image** — compilate dai sorgenti e installate
in `/usr/local`:

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

**3. Compilatore V:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** La radice del repository è il modulo `vgui` stesso; V lo
trova tramite `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Cross-compilazione su Linux.** Installate MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) e mettete le versioni per
Windows di SDL3, SDL3_ttf e SDL3_image (header, librerie di
importazione e DLL dai pacchetti MSYS2 `mingw64`) in un prefisso, ad
esempio `~/soft/mingw64`. Poi:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Mettete accanto all'exe le DLL di `$pfx/bin` di cui ha bisogno. Un
esempio completo e funzionante — download dei pacchetti MSYS2
(`tools/win_deps.py`) e raccolta delle DLL (`tools/windows.sh`) — è nel
repository [vraw](https://github.com/Mintormo/vraw).

**Direttamente in MSYS2 (non ancora provato).** Installate
[MSYS2](https://www.msys2.org), aprite il terminale **MSYS2 MINGW64** ed
eseguite:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Esempi

[`examples/`](examples) contiene 58 piccoli programmi, uno per widget o
funzionalità, più
[`59_showcase.v`](examples/59_showcase.v) con tutto in una finestra.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # un esempio
PATH=~/soft/v:$PATH examples/build.sh          # compilare tutti in examples/bin/
```

## Test

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Non serve uno schermo: SDL funziona con il driver `dummy`.

## Documentazione

Il codice è commentato in dettaglio: ogni file inizia con
un'intestazione che lo descrive. Le note di progetto sono in russo:
[PROJECT.md](PROJECT.md) — come funziona ogni sottosistema (layout,
invalidazione, rendering, focus, sovrapposizioni, thread, temi, i18n) e
perché, [ROADMAP.md](ROADMAP.md) — il piano di sviluppo,
[docs/](docs) — audit e revisioni.

## Fatto con Claude Code

vgui è stata scritta in vibe coding, insieme a
[Claude Code](https://claude.com/claude-code), l'assistente di
programmazione IA di Anthropic.

## Licenza

[MIT](LICENSE). Le risorse di terze parti in `assets/` sono soggette
alle proprie licenze: font Roboto — Apache License 2.0, font DejaVu —
licenza Bitstream Vera, icone Lucide — ISC.
