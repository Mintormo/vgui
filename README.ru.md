# vgui

[English](README.md) | **Русский** | [Deutsch](README.de.md) | [Français](README.fr.md) | [Español](README.es.md) | [Italiano](README.it.md) | [Nederlands](README.nl.md) | [Português](README.pt.md) | [Polski](README.pl.md)

GUI-библиотека для языка [V](https://vlang.io) поверх
[SDL3](https://libsdl.org). vgui рисует весь интерфейс сама (без
нативных виджетов ОС), поддерживает HiDPI, темы, анимации и перевод
интерфейса и перерисовывает только изменившиеся части окна.

![Витрина vgui, тёмная тема](screenshots/showcase-dark.png)

## Возможности

- **Элементы управления** — Label, Button, CheckBox, RadioButton,
  ToggleSwitch, Slider, Spinbox, TextInput, TextArea, ComboBox, Spinner,
  ProgressBar, Badge, DatePicker, ColorPicker, CurveEditor, ShortcutInput.
- **Сложные виджеты** — CodeEditor с подсветкой синтаксиса,
  MarkdownView, ListBox, TableView (виртуальный режим на миллионы строк),
  TreeView, PropertyGrid, PlotView, Canvas (рисование с прямым доступом
  к пикселям), ImageView.
- **Контейнеры** — VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox,
  TabBox, Accordion, Splitter. Раскладка без пикселей: виджет получает
  естественный размер или долю свободного места (`flex`), есть `min`,
  `max` и выравнивание.
- **Меню и оверлеи** — MenuBar с сочетаниями клавиш, MenuButton,
  ContextMenu, подсказки у любого виджета, уведомления, модальные
  диалоги.
- **Интеграция с ОС** — нативные диалоги выбора файлов и папок,
  системный трей, приём drag-and-drop из других приложений, окна без
  рамки.
- **Внешний вид** — 15 встроенных тем (Dark, Light, Monokai,
  Windows 10/11, KDE Breeze, GNOME Adwaita, macOS, Mac OS X Aqua,
  Mac OS 9 Platinum — светлые и тёмные варианты), стили в духе CSS,
  анимации, масштаб интерфейса.
- **Всё с собой** — иконки Lucide и шрифты Roboto встроены в бинарник,
  перевод интерфейса (`vgui.i18n`), undo/redo, компактная разметка
  интерфейса `.vui`.
- **Тестирование** — `testkit.v`: синтетический ввод и снапшоты рендера;
  тесты идут без дисплея.

## Скриншоты

То же окно ([`examples/59_showcase.v`](examples/59_showcase.v)) в темах
Light и Monokai; тема переключается на ходу.

![Светлая тема](screenshots/showcase-light.png)

![Тема Monokai](screenshots/showcase-monokai.png)

Настоящее приложение на vgui —
[vraw](https://github.com/Mintormo/vraw), проявщик RAW-фотографий:

![vraw](https://raw.githubusercontent.com/Mintormo/vraw/main/screenshots/main.jpg)

## Быстрый старт

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

`box.add(w)` даёт виджету размер по содержимому, `box.add(w, flex: 1)` —
долю свободного места; есть ещё `min:`, `max:` и `align:`. Окно без
заданного размера подстраивается под содержимое.

## Сборка и зависимости

vgui — модуль в исходниках: отдельно собирать ничего не нужно, она
компилируется вместе с программой. Основная платформа — Linux
(проверено на Ubuntu 24.04). Программы для Windows собираются
кросс-компиляцией на Linux (так собрана Windows-версия vraw); сборка
прямо на Windows в MSYS2 должна работать, но пока не проверялась.
Ветка для macOS заложена, но не проверена.

| Компонент | Версия | Linux (Ubuntu / Debian / Mint) | Windows (MSYS2, MINGW64) |
|---|---|---|---|
| Компилятор V | 0.5.2 (a1c9e93) или новее | из исходников (шаг 3) | из исходников |
| gcc | 13+ | `build-essential` | `mingw-w64-x86_64-gcc` |
| SDL3 | 3.2+ | из исходников (шаг 2), в репозиториях её пока нет | `mingw-w64-x86_64-sdl3` |
| SDL3_ttf | 3.2+ | из исходников (шаг 2) | `mingw-w64-x86_64-sdl3-ttf` |
| SDL3_image | 3.4+ | из исходников (шаг 2) | `mingw-w64-x86_64-sdl3-image` |

vgui собирается только gcc (`-cc gcc`).

### Linux

**1. Системные пакеты** — компилятор и библиотеки, с которыми
собирается SDL3:

```bash
sudo apt install build-essential git cmake pkg-config \
  libx11-dev libxext-dev libxrandr-dev libxcursor-dev libxfixes-dev \
  libxi-dev libxss-dev libxtst-dev libxkbcommon-dev libwayland-dev \
  libdecor-0-dev libegl1-mesa-dev libgl1-mesa-dev libgles2-mesa-dev \
  libdrm-dev libgbm-dev libdbus-1-dev libibus-1.0-dev libudev-dev \
  libasound2-dev libpulse-dev libpipewire-0.3-dev \
  libfreetype-dev libharfbuzz-dev libpng-dev libjpeg-dev libwebp-dev libtiff-dev
```

В Fedora, Arch и других дистрибутивах поставьте те же библиотеки своим
менеджером пакетов. Если в нём уже есть SDL3, SDL3_ttf и SDL3_image 3.4
или новее (с пакетами `-devel`/`-dev`), шаг 2 можно пропустить.

**2. SDL3, SDL3_ttf, SDL3_image** — сборка из исходников с установкой в
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

**3. Компилятор V:**

```bash
git clone https://github.com/vlang/v ~/soft/v
cd ~/soft/v && make
```

**4. vgui.** Корень репозитория — это и есть модуль `vgui`; компилятор V
находит его через `~/.vmodules`:

```bash
mkdir -p ~/.vmodules ~/projects
git clone https://github.com/Mintormo/vgui ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
cd ~/projects/vgui
~/soft/v/v -cc gcc run examples/59_showcase.v
```

### Windows

**Кросс-компиляция на Linux.** Поставьте MinGW-w64
(`sudo apt install gcc-mingw-w64-x86-64`) и положите Windows-сборки
SDL3, SDL3_ttf и SDL3_image (заголовки, библиотеки импорта и DLL из
пакетов MSYS2 `mingw64`) в один префикс, например `~/soft/mingw64`.
Затем:

```bash
pfx=~/soft/mingw64
~/soft/v/v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$pfx/include" -ldflags "-L$pfx/lib" -o app.exe app.v
```

Рядом с exe положите нужные ему DLL из `$pfx/bin`. Полный рабочий
пример — скачивание пакетов MSYS2 (`tools/win_deps.py`) и сбор DLL
(`tools/windows.sh`) — в репозитории
[vraw](https://github.com/Mintormo/vraw).

**Прямо в MSYS2 (пока не проверено).** Установите
[MSYS2](https://www.msys2.org), откройте оболочку **MSYS2 MINGW64** и
выполните:

```bash
pacman -S --needed git make mingw-w64-x86_64-gcc \
  mingw-w64-x86_64-sdl3 mingw-w64-x86_64-sdl3-ttf mingw-w64-x86_64-sdl3-image
git clone https://github.com/vlang/v ~/v
(cd ~/v && make)
mkdir -p "$USERPROFILE/.vmodules"
git clone https://github.com/Mintormo/vgui "$USERPROFILE/.vmodules/vgui"
cd "$USERPROFILE/.vmodules/vgui" && ~/v/v -cc gcc run examples/59_showcase.v
```

## Примеры

В [`examples/`](examples) — 58 небольших программ, по одной на виджет
или возможность, и
[`59_showcase.v`](examples/59_showcase.v) — всё в одном окне.

```bash
~/soft/v/v -cc gcc run examples/01_label.v    # один пример
PATH=~/soft/v:$PATH examples/build.sh          # собрать все в examples/bin/
```

## Тесты

```bash
SDL_VIDEODRIVER=dummy ~/soft/v/v -cc gcc test .
```

Дисплей не нужен: SDL работает с драйвером `dummy`.

## Документация

Код подробно прокомментирован: у каждого файла есть шапка с описанием.
[PROJECT.md](PROJECT.md) — устройство каждой подсистемы (раскладка,
инвалидация, рендеринг, фокус, оверлеи, потоки, темы, i18n) и причины
решений, [ROADMAP.md](ROADMAP.md) — план развития,
[docs/](docs) — аудиты и обзоры.

## Сделано с Claude Code

vgui создана вайбкодингом — вместе с
[Claude Code](https://claude.com/claude-code), ИИ-помощником для
программирования от Anthropic.

## Лицензия

[MIT](LICENSE). Сторонние ресурсы в `assets/` — под своими лицензиями:
шрифты Roboto — Apache License 2.0, шрифты DejaVu — лицензия Bitstream
Vera, иконки Lucide — ISC.
