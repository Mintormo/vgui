# Примеры vgui по виджетам

Каждый файл здесь — небольшая самостоятельная программа на V, иллюстрирующая
применение **одного** виджета или контейнера vgui: один файл — один виджет
или одна возможность.

## Сборка и запуск

Скрипт сборки компилирует все примеры в `examples/bin/`:

```bash
cd examples
./build.sh
```

Запуск одного примера без отдельной сборки (из корня проекта):

```bash
v -enable-globals run examples/01_label.v
```

> Импорт `vgui` компилятор V находит через симлинк `~/.vmodules/vgui` на корень
> этого проекта (`ln -s ~/projects/vgui ~/.vmodules/vgui`). `build.sh` переходит
> в корень проекта только ради аккуратных относительных путей к `examples/bin/`.
>
> Папка `examples/` - отдельный подмодуль (`module main`) и **не** попадает в
> сборку библиотеки: V компилирует только файлы самого каталога модуля, не
> заходя в подпапки.

Примеры статически включают vgui, отдельно собирать библиотеку не нужно.

## Список примеров

### Базовые элементы управления
| Файл | Виджет |
|------|--------|
| `01_label.v` | `Label` — текстовая метка |
| `02_button.v` | `Button` — кнопка, стили, toggle |
| `03_checkbox.v` | `CheckBox` — флажок |
| `04_radio_button.v` | `RadioButton` — переключатели в группах |
| `05_toggle_switch.v` | `ToggleSwitch` — тумблер |
| `06_slider.v` | `Slider` — ползунок (гор./верт.) |
| `07_spinbox.v` | `Spinbox` — числовой счётчик |
| `08_text_input.v` | `TextInput` — однострочный ввод |
| `09_text_area.v` | `TextArea` — многострочный ввод |
| `10_combo_box.v` | `ComboBox` — выпадающий список |
| `11_spinner.v` | `Spinner` — индикатор загрузки |
| `12_progress_bar.v` | `ProgressBar` — прогресс (линейный/круговой) |

### Отображение и оформление
| Файл | Виджет |
|------|--------|
| `13_badge.v` | `Badge` — бейдж/счётчик |
| `14_separator.v` | `Separator` — разделитель |
| `15_image_view.v` | `ImageView` — картинка с зумом |
| `16_breadcrumbs.v` | `Breadcrumbs` — хлебные крошки |
| `17_notification.v` | `NotificationManager` — всплывающие уведомления |

### Текст и rich-контент
| Файл | Виджет |
|------|--------|
| `18_code_editor.v` | `CodeEditor` — редактор кода с подсветкой |
| `19_markdown_view.v` | `MarkdownView` — просмотр Markdown |

### Выбор значений
| Файл | Виджет |
|------|--------|
| `20_color_picker.v` | `ColorPicker` — выбор цвета |
| `21_date_picker.v` | `DatePicker` — выбор даты (календарь) |

### Данные
| Файл | Виджет |
|------|--------|
| `22_list_box.v` | `ListBox` — список с прокруткой |
| `23_table_view.v` | `TableView` — таблица с редактированием |
| `24_tree_view.v` | `TreeView` — дерево |
| `25_property_grid.v` | `PropertyGrid` — сетка свойств |
| `26_plot_view.v` | `PlotView` — график функций/точек |

### Меню
| Файл | Виджет |
|------|--------|
| `27_menu_button.v` | `MenuButton` — кнопка с меню |
| `28_menu_bar.v` | `MenuBar` — полоса меню |
| `29_context_menu.v` | `ContextMenu` — контекстное меню |

### Контейнеры и компоновка
| Файл | Виджет |
|------|--------|
| `30_vbox_hbox.v` | `VBox` / `HBox` — вертикаль/горизонталь, flex |
| `31_panel.v` | `Panel` — панель с фоном/рамкой |
| `32_grid.v` | `GridLayout` — сетка |
| `33_stack.v` | `Stack` — наложение слоёв |
| `34_centered.v` | `Centered` — центрирование |
| `35_scroll_box.v` | `ScrollBox` — прокручиваемая область |
| `36_tab_box.v` | `TabBox` — вкладки |
| `37_accordion.v` | `Accordion` — разворачиваемые секции |
| `38_splitter.v` | `Splitter` — делитель с перетаскиванием |

### Прочее
| Файл | Виджет |
|------|--------|
| `39_drop_zone.v` | `DropZone` — приём drag-and-drop + выбор файла |

### Возможности приложения (не виджеты)
| Файл | Тема |
|------|------|
| `40_ui_scale.v` | Масштаб интерфейса — `win.set_ui_scale(factor)` |
| `41_themes.v` | Встроенные темы — `win.set_theme(...)` |
| `42_i18n.v` | Интернационализация — `add_translations`, `set_locale`, `tr`, `trf` |
| `44_image_background.v` | Фоновая картинка — `ImageBackground`, режимы `BgMode` |
| `45_canvas.v` | Холст с доступом к пикселям — `Canvas`, `on_input`, инструменты рисования |
| `46_borderless_window.v` | Окно без рамки — `WindowTitleDrag`, `set_borderless`, перетаскивание/resize |
| `47_icons.v` | Иконки Lucide — виджет `Icon`, иконки в кнопках |
| `48_auto_layout.v` | Авто-раскладка — `add(w)`, `flex:`, `min:`, `align:`, `set_cross_align`, `set_col_auto` |
| `49_background_thread.v` | Фоновый поток и свой цикл — `app.post()`, `pump_events()`/`render_all()` |
| `50_modal_scope.v` | Область модальности — модальный диалог блокирует только своё окно |
| `52_undo_stack.v` | Стек отмены приложения — `UndoStack`, `UndoCommand`, слияние `merge_id`, группы, `set_clean` |
| `53_animation.v` | Анимации своего виджета — `Anim`: `.tween` + `Easing` (8 кривых), `.smooth` для hover, `mark_anim_rect` |
| `54_item_icons.v` | Иконки элементов — `ItemIcon` (Lucide, файл, байты) в меню, дереве, списке, вкладках, ComboBox, MenuButton, Accordion |
