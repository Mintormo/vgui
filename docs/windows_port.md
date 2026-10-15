# Перенос на Windows — разбор (20.09.2026)

Статус (09.10.2026): **V-часть собирается под Windows кросс-компиляцией на
Linux и работает под Wine** (проверено на vraw), на настоящей Windows ещё не
запускалась. Добавлено: `SDL_EVENT_RENDER_TARGETS_RESET` даёт полный кадр
(Direct3D теряет содержимое постоянной текстуры окна при сбросе устройства —
PROJECT.md, раздел о dirty-region rendering). Замечено на vraw: с `-flto`
(включается `-prod`) MinGW собирает vraw.exe с пустым окном, примеры vgui —
нормально; vraw собирается с `-fno-lto`, причина не найдена. Сделано: путь по
умолчанию нативного диалога — `os.join_path` (собственный файловый диалог с его
правками под Windows удалён 13.10.2026 — остались только нативные); язык системы уже берётся
из `SDL_GetPreferredLocales`. Не сделано: Python-обвязка (`vgui.dll`, пункт 2,
тесты и `check_capi.py` из пункта 3) и всё из пункта 4.

Сборка V-приложения на Linux (так собирается vraw — `tools/windows.sh` в
его репозитории): MinGW из apt (`gcc-mingw-w64-x86-64`), SDL3/SDL3_ttf/
SDL3_image — готовые пакеты MSYS2 mingw64 (msvcrt, совместимы с MinGW из
Ubuntu), распакованные в префикс:

```bash
v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$PFX/include" -ldflags "-L$PFX/lib" -o app.exe app.v
```

DLL из `$PFX/bin` — рядом с exe (`objdump -p` показывает зависимости).

Ниже — исходный разбор (20.09.2026).

## Что уже переносимо

Почти всё платформенное идёт через SDL3, а SDL3 кроссплатформенная: окна,
отрисовка, шрифты (встроены через `$embed_file`), буфер обмена, трей,
нативные файловые диалоги, открытие ссылок (`SDL_OpenURL`). Прямых вызовов
POSIX/Linux API в V-коде нет: из не-SDL C-функций объявлена только `C.system`
в `markdown_view.v`, и она не используется.

Заготовки под Windows уже есть:

- ветка `MINGW* | MSYS* | CYGWIN* | Windows_NT` в `v/build.sh` (собирает `vgui.dll`);
- `#flag windows -lSDL3 -lSDL3_ttf -lSDL3_image` в `v/vgui/sdl3_bindings.v`;
- поиск `vgui.dll` / `libvgui.dll` в `_find_lib` (`python/vguipy/_lib.py`);
- `vgui.dll` в `setup.py` (`lib_name()`);

## 1. Окружение для сборки на Windows

- **Компилятор V для Windows.** Новый компилятор под Windows не проверялся;
  если не справится, есть откат на старый (PROJECT.md, «Компилятор V»).
- **C-компилятор.** Проще всего MinGW-w64 через MSYS2: он же даёт bash, в
  котором запустятся `build.sh` и `examples/build.sh`.
- **SDL3, SDL3_ttf и SDL3_image для разработки** (заголовки и библиотеки).
  Скорее всего, в MSYS2 они есть пакетами — проверить. Сейчас для Windows
  указано только `-lSDL3 ...`, без `-I`/`-L`: если SDL3 лежит не в
  стандартных путях компилятора, пути нужно дописать в `sdl3_bindings.v`
  (для Linux там есть `#flag linux -I/usr/include/SDL3`).

## 2. SDL3 придётся класть рядом с библиотекой

Главное отличие от Linux. Сейчас решено SDL3 не бандлить, а брать из системы
(PROJECT.md, «Зависимости SDL3»), но на Windows системной SDL3 нет. Кроме того,
Python 3.8+ ищет зависимые DLL не по `PATH`, а только в каталоге загружаемой DLL,
системных каталогах и каталогах из `os.add_dll_directory`. Нужно:

- класть `SDL3.dll`, `SDL3_ttf.dll`, `SDL3_image.dll` (и их зависимости, если
  они не вшиты статически) рядом с `vgui.dll`;
- в `_lib.py` на Windows перед `ctypes.CDLL` вызывать
  `os.add_dll_directory(<каталог vgui.dll>)`;
- в `build.sh` (ветка Windows) копировать эти DLL в `python/`, а в
  `setup.py` (`BuildPyWithLib`) — внутрь wheel;
- обновить PROJECT.md, «Зависимости SDL3» и «Упаковка»: на Windows SDL3
  бандлится, на Linux — нет.

## 3. Правки в коде

| Где | Проблема | Как чинить |
|---|---|---|
| `v/vgui/native_file_dialog.v:139` | Путь по умолчанию склеивается через `/` | Скорее всего, работает (Windows принимает `/`), но лучше `os.join_path` |
| `v/vgui/i18n.v`, `detect_system_locale` | На Windows язык берётся из `LANG`/`LC_*`, а их там обычно нет, так что язык всегда английский | `SDL_GetPreferredLocales()` — работает на всех ОС |
| `python/tests/support.py`, `sdl()` | Грузит `libSDL3.so.0`; на Windows тесты кликов тихо пропустятся | На Windows грузить `SDL3.dll` |
| `tools/check_capi.py`, `check_shared_object` | Экспорт сверяется через `nm -D` и ищется только `libvgui.so`: на Windows пункт 4 проверки молча пропускается | `objdump -p vgui.dll` (MinGW) или явное предупреждение о пропуске |

## 4. Что проверить на самой Windows

- **Баг нового компилятора с замыканиями (vlang/v#28795).** Скорее всего, он
  там тот же, и обход в `gen_capi.py` уже работает — подтвердить кликом по
  кнопке в Python-примере.
- **Сборщик мусора Boehm** на Windows (V поддерживает, у нас не проверялся).
- **HiDPI** — масштаб экрана 125–150 %.
- **Нативные файловые диалоги** и трей.
- **Пути с кириллицей** (`C:\Users\Игорь\...`) — в `Image`, шрифтах из файла,
  файловом диалоге.
- **Все тесты и примеры:** `v test vgui/`, `python -m unittest discover -s
  python/tests`, прогон `python/examples/*.py` и V-примеров.

## Можно ли начать с Linux

- Правки из пунктов 2 и 3 можно сделать на Linux: работе на Linux они не мешают.
- Собрать `vgui.dll` на Linux можно кросс-компиляцией V (`-os windows`), но
  нужен MinGW (`sudo apt install gcc-mingw-w64`, на 20.09.2026 не установлен)
  и SDL3 в сборке для MinGW. Wine установлен, но годится только для грубой
  проверки — настоящая проверка только на живой Windows.
