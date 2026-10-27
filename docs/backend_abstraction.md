# План: абстракция бэкенда рисования

Составлен 27.10.2026. Пункт ROADMAP.md, раздел 9, «Backend-абстракция».

**Состояние (27.10.2026):** этапы 0–5 и 7 сделаны - виджеты SDL не зовут, это проверяет
`backend_lint_test.v`; описание - PROJECT.md, «Бэкенд рисования: виджеты не зовут SDL напрямую».
Этап 6 (интерфейс `RenderBackend`) не делался: без второго бэкенда он даёт только косвенный вызов на
каждый примитив. Таблица «Текущее состояние» ниже - замер ДО работы.

## Цель и границы

Цель - вынести все обращения к SDL_Renderer / SDL_ttf / SDL_image за один слой (`RenderContext`
+ интерфейс бэкенда), чтобы виджеты не знали про SDL. Второй бэкенд в этот план **не входит**:
он имеет смысл только под конкретную цель (GPU-ускорение canvas/plot, запись видео и т.п.).

Что даёт уже первый этап, даже без второго бэкенда:
- инварианты времени жизни текстур (`SDL_DestroyTexture` только при `is_renderer_alive_gen`),
  blend mode и масштаб после `SDL_SetRenderTarget` соблюдаются в одном месте, а не в каждом виджете;
- `voidptr` на текстуры в полях виджетов заменяется типизированным хэндлом;
- время кадра берётся из одних часов: это закрывает пункт ROADMAP 5 про `SDL_GetTicks`.

Не трогаем: окно, цикл событий, трей, нативные диалоги, DnD файлов, borderless, буфер обмена,
локаль. Это платформенный слой, его роль и так выполняет SDL3; события уже абстрагированы
(`GuiEvent`).

## Текущее состояние (замер 27.10.2026)

87 исходных файлов, около 70k строк. SDL/TTF/IMG вызываются в 37 файлах, всего около 150 разных функций.
У `RenderContext` около 60 методов рисования (`fill_rect`, `draw_text*`, `push_clip`, `draw_icon`...).
Большинство виджетов SDL не трогает.

Утечки SDL **из виджетов в обход RenderContext** (то, что надо убрать):

| Файл | Что использует напрямую |
|---|---|
| `canvas.v` | свои текстуры (Create/Update/Destroy, ScaleMode, BlendMode), `SDL_Surface`, IMG_Load/Save |
| `spinner.v` | `SDL_RenderGeometry` + `SDL_Vertex`, `SDL_SetRenderDrawBlendMode`, `SDL_GetTicks` |
| `markdown_view.v` | картинки: IMG_Load, текстуры, `SDL_RenderTexture`; `SDL_GetTicks`; `SDL_OpenURL` |
| `plot_view.v` | `SDL_RenderLines` + `SDL_FPoint`, свой цвет/blend |
| `image_view.v`, `image_background.v` | IMG_Load(_IO), текстура из surface, `SDL_RenderTexture` |
| `icon_font.v` | свой `TTF_Font`, рендер глифа в текстуру |
| `item_icon.v` | `SDL_SetTextureAlphaMod` |
| `image_export.v` | `SDL_RenderReadPixels`, IMG_Save* |
| часы: `notification`, `tooltip`, `tooltip_manager`, `progress_bar`, `text_input`, `text_area`, `code_editor`, `table`, `tree_view`, `css_apply`, `borderless` | `SDL_GetTicks` |
| ввод: `table`, `tree_view`, `code_editor` | `SDL_GetModState` (модификаторы мимо `GuiEvent`) |
| `splitter.v` | `SDL_SetCursor`/`GetCursor` |
| `date_picker`, `color_picker` | `SDL_Delay` |

Поля-текстуры `voidptr`: `canvas.v` (`texture`, `detail_tex`), `image_view.v`, `image_background.v`,
`markdown_view.v` (`tex`), `render_context.v` (кэш иконок, `draw_icon(texture voidptr...)`,
`render_copy_rotated`).

Соседи: `vgui-capi/vgui_capi.v` зовёт `SDL_DestroySurface`, трей и `SDL_SetWindowMin/MaximumSize`,
то есть только платформенный слой, рендер не трогает. `vraw` SDL не использует.

## Этапы

Каждый этап - отдельный коммит, после него всё зелёное: `v test .`, снапшоты **без перезаписи**
(кадр обязан совпасть пиксель в пиксель), пересборка примеров, сборка vgui-capi и vraw.

### Этап 0. Подготовка (полдня) - сделано
- Проверить, что галерея снапшотов покрывает canvas, spinner, plot_view, image_view, markdown с
  картинкой, иконки. Недостающее добавить **до** рефакторинга: это страховочная сетка.
- Раздел в PROJECT.md «Бэкенд рисования» (пустой каркас, пополнять по ходу).

### Этап 1. Часы кадра (1 день) - сделано (`clock.v`)
- `ctx.now_ms()` (и аналог в `App`/`Window` для кода вне `draw`) поверх `SDL_GetTicks`;
  с `anim_fixed_dt` / `tip_clock_ms` в тестах время подменяется единообразно.
- Заменить `SDL_GetTicks` во всех виджетах из таблицы. Мигание курсора, спиннер, прогресс,
  таймер уведомлений теперь детерминированы в тестах; заодно снимается препятствие для снапшотов
  DatePicker (ROADMAP 8, если «сегодня» тоже взять из этих часов).
- `SDL_GetModState` → модификаторы из `GuiEvent` (или `app.mod_state()`), `SDL_Delay` - разобрать,
  зачем он там, скорее всего убрать.

### Этап 2. Тип текстуры (1–2 дня) - сделано (`sdl3_texture.v`)
- `pub struct Texture { handle voidptr  w f32  h f32  gen u64 }` (или `&Texture`), создаётся только
  через `RenderContext`: `ctx.texture_from_image(path|bytes)`, `ctx.texture_from_pixels(w, h, rgba)`,
  `ctx.update_texture(mut t, pixels)`, `ctx.destroy_texture(mut t)` (внутри - проверка поколения
  рендерера, это инвариант «Время жизни SDL-текстур»).
- Свойства: `scale_mode` (nearest/linear), альфа-модуляция, blend - параметрами рисования, а не
  вызовами SDL у виджета.
- `ctx.draw_texture(t, src ?Rect, dst Rect, opts)`, `draw_icon` и `render_copy_rotated` переходят на `Texture`.
- Перевести `image_view`, `image_background`, `markdown_view` (картинки), `item_icon`, кэш иконок.

### Этап 3. Геометрия и линии (1 день) - сделано
- `ctx.draw_polyline(points []Point, color, width)` для `plot_view`;
  `ctx.fill_triangles(verts []Vertex)` (вершина = позиция + цвет [+ uv]) для `spinner`.
- Учесть HiDPI: сейчас виджеты сами масштабируют точки или полагаются на `SDL_SetRenderScale`;
  после переноса масштабирование - только внутри `RenderContext`. Проверять через `set_ui_scale`
  и снапшоты 1.25/2.

### Этап 4. Canvas (2–3 дня, самый объёмный) - сделано (`image_io.v`)
- Битмап холста и `detail_tex` на `Texture` + `update_texture`.
- Загрузка/сохранение изображений (IMG_Load/IMG_Save, `SDL_Surface`, ConvertSurface) - в отдельный
  модуль-утилиту `image_io.v` (декодирование в RGBA-буфер и обратно), без рендерера. Ею же
  пользуются этап 2 и `image_export.v`.

### Этап 5. Иконочный шрифт (полдня–день) - сделано (`sdl3_icon_font.v`, общий `cached_text_texture`)
- `icon_font.v` держит свой `TTF_Font` в обход `FontSet` - перевести на общий путь текста
  (`draw_icon_glyph` через кэш текстур текста) или хотя бы спрятать за `RenderContext`.

### Этап 6. Интерфейс бэкенда (2–3 дня) - не делался
- Теперь весь SDL-рендер собран в `sdl3_render.v`, `sdl3_fonts.v`, `font_cache.v`, `render_context.v`.
  Выделить `interface RenderBackend` (примитивы: rect/rounded/line/geometry/texture/clip/target/
  read_pixels, текст: open_font/measure/render_glyph_run) и `SdlRenderBackend`.
- `RenderContext` хранит `backend RenderBackend` вместо `renderer voidptr`; поле `renderer`
  остаётся приватным у SDL-бэкенда.
- Решить по производительности: вызов через интерфейс в V - косвенный вызов на каждый примитив;
  замерить на тяжёлом окне (markdown, таблица, 59_showcase). Если заметно - бэкенд выбирается на
  этапе компиляции (`$if`), а не интерфейсом.
- Тесты-заглушка: `NullRenderBackend`, считающий вызовы, - полезен для тестов раскладки/
  инвалидации без SDL-рендерера.

### Этап 7. Защита от регресса (полдня) - сделано (`backend_lint_test.v`)
- Тест-линтер (как `widget_tag_test.v`): grep по `*.v`, кроме разрешённого списка файлов
  (`sdl3_*`, `render_context.v`, `font_cache.v`, `image_io.v`, платформенный слой), не должен
  находить `C.SDL_Render*`, `C.SDL_*Texture*`, `C.TTF_`, `C.IMG_`, `C.SDL_GetTicks`.
- Обновить CLAUDE.md (инвариант: «виджет не зовёт SDL напрямую») и PROJECT.md.

Итого около 1,5–2 недель работы.

## Риски и на что смотреть

- **Текст** - самая хрупкая часть: кэш текстур текста с проверкой коллизий хэша, привязка глифов к
  физическим пикселям при дробном ui_scale (см. память о feedback_text_rendering). На этапе 6 не
  менять алгоритм, только переносить.
- **Blend mode / масштаб после SetRenderTarget** - сейчас каждый путь выставляет сам; после
  переноса инвариант должен жить в бэкенде, проверять снапшотами и `render_dirty_test.v`.
- **Частичная перерисовка** - `snapshot_ui_test.v` сверяет «частичная = полная», гонять на каждом этапе.
- **Публичный API**: `draw_icon(texture voidptr...)`, `load_icon_texture` и поля `texture` -
  публичные; проверить vgui-capi (`vgui_capi_gen.v`, спека) и vguipy, если что-то из них проброшено.
- **Агенты**: этапы независимы после 2, но делать по одному-два за раз на Sonnet
  (см. память feedback_agent_budget).

## Если когда-нибудь второй бэкенд

Кандидаты: SDL_GPU (тот же SDL, шейдеры), NanoVG/Skia (векторный рендер, сглаживание). Главная
трудность - текст: метрики обязаны совпасть с SDL_ttf, иначе сдвинется раскладка и все снапшоты.
Снапшоты под второй бэкенд - отдельный набор эталонов.
