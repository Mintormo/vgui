# vgui

**English** | [Русский](README.ru.md) | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | [Português](README.pt.md) | [Polski](README.pl.md)

A GUI library for the [V](https://vlang.io) language on top of
[SDL3](https://libsdl.org). vgui draws the whole interface itself (no
native OS widgets), supports HiDPI, themes, animations and translations,
and redraws only the parts of the window that changed.

![vgui showcase, dark theme](screenshots/showcase-dark.png)

## Features

- **Controls** — Label, Button, CheckBox, RadioButton, ToggleSwitch,
  Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner, ProgressBar,
  Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Complex widgets** — CodeEditor with syntax highlighting,
  MarkdownView, ListBox, TableView (virtual mode for millions of rows),
  TreeView, PropertyGrid, PlotView, Canvas (drawing with direct pixel
  access), ImageView.
- **Containers** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Layout without pixels: a widget gets its
  natural size or a share of the free space (`flex`), with `min`, `max`
  and alignment.
- **Menus and overlays** — MenuBar with keyboard shortcuts, MenuButton,
  ContextMenu, tooltips on any widget, notifications, modal dialogs.
- **OS integration** — native file and folder dialogs, system tray,
  drag-and-drop from other applications, borderless windows.
- **Look** — 15 built-in themes (Dark, Light, Monokai, Windows 10/11,
  KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua, Mac OS 9 Platinum —
  light and dark variants), CSS-like stylesheets, animations, UI scaling.
- **Batteries included** — Lucide icons and Roboto fonts are embedded in
  the binary, interface translation (`vgui.i18n`), undo/redo, a compact
  `.vui` markup for describing interfaces.
- **Testing** — `testkit.v`: synthetic input and render snapshots; tests
  run without a display.

## Screenshots

The same window ([`examples/59_showcase.v`](examples/59_showcase.v)) in
the Light and Monokai themes; the theme can be switched on the fly.

![Light theme](screenshots/showcase-light.png)

![Monokai theme](screenshots/showcase-monokai.png)

A real application built with vgui is
[vraw](https://github.com/Mintormo/vraw), a RAW photo developer:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Quick start

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

`box.add(w)` gives a widget its natural size, `box.add(w, flex: 1)` — a
share of the free space; there are also `min:`, `max:` and `align:`. A
window without an explicit size fits its content.

## Building and dependencies

vgui is a source module: there is nothing to build separately, it is
compiled into your program. The main platform is Linux (tested on
Ubuntu 24.04). Windows programs are cross-compiled on Linux (this is how
the Windows version of vraw is made); building natively on Windows in
MSYS2 should work, but has not been tested yet. A macOS branch is laid
out but not tested.

| Component | Version | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| V compiler | 0.5.2 (a1c9e93) or newer | from source (step 3) | from source |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | from source (step 2), not in the repositories yet | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | from source (step 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | from source (step 2) | `mingw-w64-x86_64-sdl3-image` |

vgui builds only with gcc (`-cc gcc`).

### Linux

**1. System packages** — compiler and the libraries SDL3 is built
against:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

On Fedora, Arch and other distributions install the same libraries with
their package manager. If it already ships SDL3, SDL3_ttf and SDL3_image
3.4 or newer (with `-devel`/`-dev` packages), skip step 2.

**2. SDL3, SDL3_ttf, SDL3_image** — built from source and installed to
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

**3. V compiler:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** The repository root is the `vgui` module itself; V finds it
through `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Cross-compiling on Linux.** Install MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) and put the Windows builds of
SDL3, SDL3_ttf and SDL3_image (headers, import libraries and DLLs from
the MSYS2 `mingw64` packages) into a prefix, for example
`~/soft/mingw64`. Then:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Put the DLLs from `$pfx/bin` that the exe depends on next to it. A
complete working example — downloading the MSYS2 packages
(`tools/win_deps.py`) and collecting the DLLs (`tools/windows.sh`) — is
in the [vraw](https://github.com/Mintormo/vraw) repository.

**Natively in MSYS2 (not tested yet).** Install
[MSYS2](https://www.msys2.org), open the **MSYS2 MINGW64** shell and run:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Examples

[`examples/`](examples) contains 58 small programs, one per widget or
feature (their interface text is in Russian), plus
[`59_showcase.v`](examples/59_showcase.v) with everything in one window.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # one example
PATH=~/soft/v:$PATH examples/build.sh          # build all into examples/bin/
```

## Tests

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

No display is needed: SDL runs with the `dummy` driver.

## Documentation

The code is commented in detail: every file starts with a header
describing it. Design notes are in Russian:
[PROJECT.md](PROJECT.md) — how every subsystem works (layout,
invalidation, rendering, focus, overlays, threads, themes, i18n) and
why, [ROADMAP.md](ROADMAP.md) — the development plan,
[docs/](docs) — audits and reviews.

## Made with Claude Code

vgui was vibe-coded: written together with
[Claude Code](https://claude.com/claude-code), Anthropic's AI coding
assistant.

## License

[MIT](LICENSE). Third-party resources in `assets/` are under their own
licenses: Roboto fonts — Apache License 2.0, DejaVu fonts — Bitstream
Vera license, Lucide icons — ISC.
