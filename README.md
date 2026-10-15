# vgui

GUI-библиотека для языка [V](https://vlang.io) поверх [SDL3](https://libsdl.org). Рисует интерфейс
сама (без нативных виджетов ОС), поддерживает HiDPI, темы, анимации, перевод интерфейса и
перерисовывает только изменившиеся области окна.

Что есть:

- **элементы управления** - Label, Button, CheckBox, RadioButton, ToggleSwitch, Slider, Spinbox,
  TextInput, TextArea, ComboBox, Spinner, ProgressBar, DatePicker, ColorPicker, CurveEditor;
- **сложные виджеты** - CodeEditor с подсветкой синтаксиса, MarkdownView, ListBox, TableView,
  TreeView, PropertyGrid, PlotView, Canvas (рисование с доступом к пикселям), ImageView;
- **контейнеры** - VBox/HBox, Panel, Grid, Stack, Centered, ScrollBox, TabBox, Accordion, Splitter;
- **меню и оверлеи** - MenuBar, MenuButton, ContextMenu, всплывающие подсказки, уведомления,
  модальные диалоги;
- **интеграция с ОС** - нативные диалоги файлов, системный трей, приём drag-and-drop, окна без
  рамки;
- **прочее** - иконки Lucide (встроены в бинарник), шрифты Roboto (встроены), темы (в том числе
  в стиле macOS), перевод интерфейса (`vgui.i18n`), undo/redo, инструмент тестов интерфейса
  (`testkit.v`: синтетический ввод и снапшоты рендера), компактная разметка интерфейса `.vui`.

## Связанные проекты

vgui самостоятельна и ничего не знает о биндингах. Рядом живут:

| проект | что это |
|---|---|
| [`vgui-capi`](../vgui-capi) | C-ABI-мост: собирает `libvgui.so` с плоскими функциями `vgui_*`, чтобы библиотекой пользовались из других языков |
| [`vguipy`](../vguipy) | Python-обёртка над `libvgui.so` через `ctypes` |

## Требования

- **Компилятор V** - свежий, из исходников ([vlang/v](https://github.com/vlang/v)). Какие версии
  проверены и какие баги компилятора обходятся - [PROJECT.md](PROJECT.md), «Компилятор V».
- **SDL3 >= 3.2, SDL3_ttf, SDL3_image >= 3.4** - не бандлятся, должны стоять в системе. В
  репозиториях дистрибутивов их обычно ещё нет, поэтому их собирают из исходников и ставят в
  `/usr/local/lib` (подробности - [PROJECT.md](PROJECT.md), «Зависимости SDL3»).
- Проверено на **Linux**. Ветки для macOS и Windows заложены, но не проверены
  (план переноса - [docs/windows_port.md](docs/windows_port.md)).

## Установка

Корень репозитория - это и есть модуль `vgui`. Компилятор V находит его через `~/.vmodules`:

```bash
git clone <адрес репозитория> ~/projects/vgui
ln -s ~/projects/vgui ~/.vmodules/vgui
```

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

	mut counter := vgui.label('Нажатий: 0')
	mut clicks := 0
	mut btn := vgui.button('Нажми')
	btn.on_click = fn [mut counter, mut clicks] () {
		clicks++
		counter.text = 'Нажатий: ${clicks}'
	}
	root.add(counter)
	root.add(btn)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
```

```bash
v run hello.v
```

Флаг `-enable-globals` не нужен: файлы с `__global`-переменными помечены атрибутом `@[has_globals]`.

**Раскладка без пикселей.** `box.add(w)` даёт виджету размер по содержимому, `box.add(w, flex: 1)` -
долю свободного места; есть ещё `min:`, `max:` и `align:`. Окно без заданного размера подстраивается
под содержимое.

## Примеры

В [`examples/`](examples) - 53 небольшие программы, по одной на виджет или возможность; список с
описаниями - в [examples/README.md](examples/README.md).

```bash
v run examples/01_label.v      # один пример
./examples/build.sh                            # собрать все в examples/bin/
```

Примеры статически включают vgui: после правок библиотеки их нужно пересобрать.

## Тесты

```bash
SDL_VIDEODRIVER=dummy v test .
```

Дисплей не нужен: SDL работает с драйвером `dummy`.

## Документация

- [PROJECT.md](PROJECT.md) - устройство каждой подсистемы (раскладка, инвалидация, рендеринг, фокус,
  оверлеи, потоки, тема, i18n) и причины решений;
- [ROADMAP.md](ROADMAP.md) - план развития;
- [docs/](docs) - аудиты и обзоры;
- сам код подробно прокомментирован: у каждого файла есть шапка с описанием.

## Лицензия

[MIT](LICENSE). Сторонние ресурсы в `assets/` - под своими лицензиями: шрифты Roboto - Apache
License 2.0, DejaVu - лицензия Bitstream Vera, иконки Lucide - ISC.
