# Перенос на Windows

Статус (28.10.2026): **V-часть собирается под Windows кросс-компиляцией на Linux и работает под
Wine**; на настоящей Windows ещё не запускалась. На этой V-части выпускается Windows-сборка vraw
(`tools/windows.sh` в его репозитории, `dist/vraw-windows-x86_64.zip`, помечена экспериментальной).
Python-обёртка (`vgui.dll` для vguipy) под Windows не собиралась.

Документ начинался как разбор 20.09.2026, до разделения на три проекта; пути ниже - нынешние:
`vgui/` (библиотека), `vgui-capi/` (C-ABI, `build.sh`, `tools/check_capi.py`), `vguipy/`
(Python: `vguipy/_lib.py`, `setup.py`, `tests/`).

## Как собирается сейчас

На Linux: MinGW из apt (`gcc-mingw-w64-x86-64`, `x86_64-w64-mingw32-gcc-posix`), SDL3/SDL3_ttf/
SDL3_image - готовые пакеты MSYS2 mingw64 (msvcrt, совместимы с MinGW из Ubuntu), распакованные в
префикс:

```bash
v -os windows -cc x86_64-w64-mingw32-gcc-posix -subsystem windows \
  -cflags "-I$PFX/include" -ldflags "-L$PFX/lib" -o app.exe app.v
```

DLL из `$PFX/bin` - рядом с exe (`objdump -p` показывает зависимости). Проверка - под Wine (стоит в
системе).

## Что уже сделано

- `SDL_EVENT_RENDER_TARGETS_RESET` даёт полный кадр: Direct3D теряет содержимое постоянной текстуры
  окна при сбросе устройства (PROJECT.md, раздел о dirty-region rendering).
- Язык системы - из `SDL_GetPreferredLocales` (`i18n.v`), а не из `LANG`/`LC_*`, которых на Windows
  обычно нет.
- Путь по умолчанию нативного файлового диалога - `os.join_path` (`native_file_dialog.v`); свой
  файловый диалог, где были правки разбора путей и дисков, удалён 13.10.2026 - остались нативные.
- **Пустое окно с LTO** (vraw.exe, `-flto` от `-prod`) - причина найдена: трамплин замыканий V на
  amd64 передавал данные в `xmm15`, а в Windows x64 регистры xmm6-xmm15 сохраняет вызываемая функция,
  и вызов замыкания портил `xmm15` вызывающего (с LTO - мусор в раскладке, без LTO - пустые превью
  после кадрирования). Исправлено в V (issue vlang/v#29822, PR vlang/v#29831; есть в V a1c9e93), LTO
  возвращён. Подробности - ROADMAP vraw.
- Заготовки для Python: ветка `MINGW* | MSYS* | CYGWIN* | Windows_NT` в `vgui-capi/build.sh`,
  `#flag windows -lSDL3 -lSDL3_ttf -lSDL3_image` в `sdl3_bindings.v`, поиск `vgui.dll` /
  `libvgui.dll` в `vguipy/_lib.py`, `vgui.dll` в `vguipy/setup.py`.

## Что осталось

### 1. Проверка на настоящей Windows

Wine хорошо имитирует Windows, но не всё. Проверить (список совпадает с ROADMAP vraw):

- нативные файловые диалоги, трей, экспорт из окна;
- HiDPI - масштаб экрана 125-150 %;
- нужен ли Visual C++ Redistributable;
- пути с кириллицей (`C:\Users\Игорь\...`) - в картинках, шрифтах из файла, диалогах (под Wine
  vraw их уже открывает);
- сборщик мусора Boehm под нагрузкой;
- все V-примеры.

### 2. Python: SDL3 рядом с `vgui.dll`

Главное отличие от Linux. Там SDL3 не бандлится, а берётся из системы (PROJECT.md, «Зависимости
SDL3»); на Windows системной SDL3 нет. Кроме того, Python 3.8+ ищет зависимые DLL не по `PATH`, а
только в каталоге загружаемой DLL, системных каталогах и каталогах из `os.add_dll_directory`. Нужно:

- класть `SDL3.dll`, `SDL3_ttf.dll`, `SDL3_image.dll` (и их зависимости) рядом с `vgui.dll`;
- в `vguipy/_lib.py` на Windows перед `ctypes.CDLL` звать `os.add_dll_directory(<каталог vgui.dll>)`;
- в `vgui-capi/build.sh` (ветка Windows) копировать эти DLL к библиотеке, а в `vguipy/setup.py` -
  внутрь wheel;
- обновить PROJECT.md, «Зависимости SDL3» и «Упаковка»: на Windows SDL3 бандлится, на Linux - нет.

### 3. Проверка C-ABI

`vgui-capi/tools/check_capi.py` сверяет экспорт через `nm -D` и ищет только `libvgui.so`: на Windows
эта часть проверки молча пропустится. Нужен `objdump -p vgui.dll` (MinGW) или хотя бы явное
предупреждение о пропуске.

### 4. Тесты vguipy на Windows

`python -m unittest discover -s tests` и прогон `examples/*.py`. Обход бага замыканий в
сгенерированном C-ABI (vlang/v#28795, PROJECT.md, «Компилятор V») - подтвердить кликом по кнопке в
Python-примере.
