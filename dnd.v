// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// Перетаскивание между виджетами (drag-and-drop) - PROJECT.md, «Перетаскивание
// между виджетами (dnd.v)».
//
// Что есть:
//   - у каждого виджета поле `dnd &DragSpec` (nil - виджет в перетаскивании не
//     участвует), как поле `tooltip`: источник отдаёт данные (on_drag_start),
//     цель перечисляет принимаемые типы (accepts) и принимает сброс (on_drop);
//   - данные - DragData: тип строкой (`kind`, например 'text/plain', 'files',
//     'myapp/layer') и сами данные строкой (`text`) - так они без реестров
//     проходят через C-ABI и Python;
//   - ListBox и TreeView умеют перетаскивать строки/узлы сами (DndBuiltin):
//     перестановка внутри себя, линия вставки, вынос в другие цели;
//   - файлы и текст, брошенные в окно из других приложений (SDL drop_*),
//     приходят в те же цели как kind 'files' / 'text/plain' (external = true).
//
// Устройство - один сеанс перетаскивания на приложение (g_dnd), его ведёт
// окно, а не виджеты (как подсказки - tooltip_manager.v):
//   1. mouse_down левой кнопкой - сеанс «взводится»: запоминается окно и
//      точка. Само нажатие уходит виджетам как обычно (строка списка
//      выделяется, кнопка нажимается).
//   2. mouse_move с зажатой кнопкой дальше dnd_threshold от точки нажатия -
//      ищется источник: ближайший к курсору (сам виджет под точкой нажатия
//      или его предок), который отдал непустой DragData. Нашёлся - виджетам
//      уходит «отпускание далеко за окном» (кнопка не сработает, выделение
//      текста закончится), и начинается перетаскивание. Не нашёлся -
//      обычный жест виджета (ползунок, выделение) идёт дальше.
//   3. Пока идёт перетаскивание, мышь и клавиши виджетам не передаются. На
//      каждом движении ищется окно под курсором (между окнами приложения -
//      по экранным координатам) и цель в нём: ближайший к курсору включённый
//      виджет, принимающий этот kind. Цель подсвечивается рамкой (ListBox и
//      TreeView рисуют линию вставки сами), у курсора рисуется «призрак» с
//      подписью; без цели курсор - «нельзя».
//   4. Отпускание - сброс в цель (on_drop / DndBuiltin.dnd_drop), затем
//      источнику on_drag_end(data, accepted). Esc или потеря фокуса окна -
//      отмена (on_drag_end с accepted = false).
//
// Между окнами: во время зажатой кнопки SDL «захватывает» мышь, события
// движения и отпускания приходят окну-источнику с координатами за его
// пределами. Экранная точка = позиция окна (SDL_GetWindowPosition) + точка в
// окне * ui_scale; по ней находится окно под курсором. На Wayland окно своей
// позиции не знает (всегда 0, 0) - там перетаскивание только внутри окна
// (dnd_cross_window_ok).
//
// Указатели на окна и виджеты в g_dnd живут только на время сеанса: в конце
// (dnd_reset) они обнуляются, иначе сеанс пинил бы их для GC.

// dnd_threshold - на сколько логических пикселей нужно сдвинуть мышь с
// зажатой кнопкой, чтобы началось перетаскивание (меньше - это ещё клик с
// дрожанием руки). У Qt - 10, у GTK - 8; 6 даёт отзывчивость без ложных
// срабатываний на обычных щелчках.
const dnd_threshold = f32(6)

// dnd_cancel_xy - куда отправляется синтетическое отпускание кнопки, которым
// у источника гасится его собственный жест при начале перетаскивания: точка
// заведомо вне любого виджета, поэтому кнопка не «нажмётся», а строка списка
// не выделится.
const dnd_cancel_xy = f32(-1000000)

// Типы данных, под которыми приходят сбросы из других приложений.
pub const dnd_kind_files = 'files'
pub const dnd_kind_text = 'text/plain'

// DragData - что перетаскивается.
//   kind  - тип данных: цель принимает только перечисленные в DragSpec.accepts.
//           Свои типы приложения - через префикс ('myapp/layer'); встроенные
//           типы ListBox/TreeView - lb_drag_kind / tv_drag_kind.
//   text  - сами данные строкой (текст строки, путь, id объекта в приложении).
//   label - подпись «призрака» у курсора; '' - первая строка text.
//   index - номер строки у источника-ListBox (-1 - нет);
//   node  - узел у источника-TreeView (nil - нет). Оба заполняют встроенные
//           источники, чтобы цель могла найти и убрать перенесённое.
pub struct DragData {
pub mut:
	kind  string
	text  string
	label string
	index int       = -1
	node  &TreeNode = unsafe { nil }
}

// DropPos - куда относительно узла TreeView падает сброс.
pub enum DropPos {
	before // перед узлом, тем же уровнем
	after  // после узла, тем же уровнем
	inside // последним ребёнком узла
}

// DropInfo - всё о состоявшемся сбросе (аргумент on_drop).
//   data     - перетащенные данные;
//   x, y     - точка сброса в логических координатах окна цели;
//   external - пришло из другого приложения (файлы/текст через SDL);
//   source   - виджет-источник (nil - внешний сброс); действителен только во
//              время вызова on_drop, хранить его не нужно;
//   same     - источник и цель - один и тот же виджет;
//   index    - ListBox-цель: позиция вставки (0..число строк), иначе -1;
//   parent, pos, node - TreeView-цель: узел под курсором (node), куда
//              относительно него (pos) и будущий родитель (parent, nil -
//              верхний уровень); index - позиция среди детей parent.
pub struct DropInfo {
pub:
	data     DragData
	x        f32
	y        f32
	external bool
	source   &Widget = unsafe { nil }
	same     bool
	index    int       = -1
	node     &TreeNode = unsafe { nil }
	parent   &TreeNode = unsafe { nil }
	pos      DropPos
}

// DragSpec - роль виджета в перетаскивании (поле `dnd` любого виджета).
// Источник:
//   on_drag_start(x, y) - мышь с зажатой кнопкой ушла от точки нажатия (x, y -
//                         точка нажатия в координатах окна). Вернуть данные
//                         или DragData{} (пустой kind) - «отсюда не тянут».
//   on_drag_end(data, accepted) - перетаскивание закончилось: accepted - цель
//                         приняла сброс (для «переноса» источник тут убирает
//                         у себя перенесённое), false - отмена или мимо цели.
// Цель:
//   accepts      - принимаемые kind: точное имя, '*' - любой, 'myapp/*' -
//                  любой с префиксом 'myapp/'. Пусто - виджет не цель.
//   on_drag_over(data, x, y) - необязательная тонкая проверка над точкой
//                  (например, «на эту ячейку - нельзя»); nil - достаточно kind.
//   on_drop(info) - сброс. Без on_drop виджет целью не считается.
@[heap]
pub struct DragSpec {
pub mut:
	on_drag_start fn (x f32, y f32) DragData        = unsafe { nil }
	on_drag_end   fn (data DragData, accepted bool) = unsafe { nil }
	accepts       []string
	on_drag_over  fn (data DragData, x f32, y f32) bool = unsafe { nil }
	on_drop       fn (info DropInfo)                    = unsafe { nil }
}

// HasDnd - поле-интерфейс (как HasTooltip): любой тип с полем верхнего уровня
// `dnd &DragSpec`. Поле есть у всех виджетов, кроме служебных слоёв (Tooltip,
// ContextMenu, Notification, NotificationManager); полноту проверяет при
// компиляции dnd_test.v.
pub interface HasDnd {
mut:
	dnd &DragSpec
}

// DndBuiltin - виджет, который сам умеет перетаскивание своих элементов
// (ListBox, TreeView). Для такого виджета менеджер не смотрит на DragSpec
// напрямую - виджет сам совмещает своё поведение с полем dnd (см. реализации).
//   dnd_begin(x, y)        - данные для перетаскивания из точки нажатия x, y
//                            (kind '' - отсюда не тянут: полоса прокрутки,
//                            шапка, пустое место);
//   dnd_over(data, same, x, y) - примет ли сброс в точке; запоминает, где
//                            рисовать линию вставки;
//   dnd_leave()            - курсор ушёл: убрать линию вставки;
//   dnd_drop(info, app)    - выполнить сброс; true - принят. Активный контекст
//                            app (get_active_ctx) на время вызова - окна цели:
//                            по нему виджет ставит курсор в точку сброса.
// Кроме ListBox/TreeView, встроенный приём есть у TextInput, TextArea,
// CodeEditor (вставка текста или пути файла) и ImageView (открыть картинку) -
// поле accept_drops, см. «Встроенный приём» ниже.
pub interface DndBuiltin {
mut:
	dnd_begin(x f32, y f32) DragData
	dnd_over(data DragData, same bool, x f32, y f32) bool
	dnd_leave()
	dnd_drop(info DropInfo, app &App) bool
}

// ─── Доступ к полю dnd ───

// widget_dnd - DragSpec виджета (nil - нет или у типа нет поля).
pub fn widget_dnd(w &Widget) &DragSpec {
	if w is HasDnd {
		return w.dnd
	}
	return unsafe { nil }
}

// widget_dnd_spec - DragSpec виджета, создаётся при первом обращении. nil -
// у типа нет поля (служебные слои). Через неё удобно настраивать роль
// по частям: `widget_dnd_spec(mut w).accepts = ['files']`.
pub fn widget_dnd_spec(mut w Widget) &DragSpec {
	if mut w is HasDnd {
		if unsafe { w.dnd == nil } {
			w.dnd = &DragSpec{}
		}
		return w.dnd
	}
	return unsafe { nil }
}

// set_drag_source делает виджет источником: start вызывается в начале
// перетаскивания и отдаёт данные. false - у типа нет поля dnd.
pub fn set_drag_source(mut w Widget, start fn (x f32, y f32) DragData) bool {
	mut spec := widget_dnd_spec(mut w)
	if unsafe { spec == nil } {
		return false
	}
	spec.on_drag_start = start
	return true
}

// set_drop_target делает виджет целью для данных с kind из accepts. false - у
// типа нет поля dnd.
pub fn set_drop_target(mut w Widget, accepts []string, on_drop fn (info DropInfo)) bool {
	mut spec := widget_dnd_spec(mut w)
	if unsafe { spec == nil } {
		return false
	}
	spec.accepts = accepts.clone()
	spec.on_drop = on_drop
	return true
}

// dnd_kind_matches - подходит ли kind под список accepts: точное совпадение,
// '*' - любой, 'префикс/*' - любой kind, начинающийся с 'префикс/'.
pub fn dnd_kind_matches(accepts []string, kind string) bool {
	if kind.len == 0 {
		return false
	}
	for a in accepts {
		if a == '*' || a == kind {
			return true
		}
		if a.ends_with('/*') && kind.starts_with(a[..a.len - 1]) {
			return true
		}
	}
	return false
}

// dnd_spec_accepts - примет ли DragSpec данные в точке (x, y): есть on_drop,
// kind подходит, тонкая проверка (если задана) не против. Общая для обычных
// виджетов и встроенных (ListBox/TreeView принимают чужие данные через неё).
pub fn dnd_spec_accepts(spec &DragSpec, data DragData, x f32, y f32) bool {
	if unsafe { spec == nil } || spec.on_drop == unsafe { nil } {
		return false
	}
	if !dnd_kind_matches(spec.accepts, data.kind) {
		return false
	}
	if spec.on_drag_over != unsafe { nil } {
		return spec.on_drag_over(data, x, y)
	}
	return true
}

// ─── Сеанс перетаскивания ───

// DndSession - состояние перетаскивания приложения (g_dnd). Одно на процесс:
// мышь одна, и перетаскивание может перейти из окна в окно.
//   armed, press_* - нажата левая кнопка, ждём сдвига дальше порога;
//   active         - идёт перетаскивание: data - что тянем, source - откуда
//                    (виджет и окно);
//   hover_*        - окно под курсором и точка в его логических координатах;
//   target         - цель под курсором (nil - нет), target_builtin - она
//                    DndBuiltin (рисует индикатор сама, ей нужен dnd_leave);
//   ext_*          - внешний сброс (файлы/текст из другого приложения): окно
//                    и цель под курсором, пока SDL шлёт drop_position.
struct DndSession {
mut:
	armed     bool
	press_win &Window = unsafe { nil }
	press_x   f32
	press_y   f32

	active     bool
	data       DragData
	source_win &Window = unsafe { nil }
	source     &Widget = unsafe { nil }

	hover_win &Window = unsafe { nil }
	hover_x   f32
	hover_y   f32

	target         &Widget = unsafe { nil }
	target_builtin bool

	ext_win            &Window = unsafe { nil }
	ext_target         &Widget = unsafe { nil }
	ext_target_builtin bool
}

// g_dnd - сеанс перетаскивания. Только главный поток (контракт проекта, см.
// PROJECT.md, «Глобальное изменяемое состояние»). Не виден из _test.v -
// тесты ходят через dnd_active / dnd_target / dnd_ext_target.
__global g_dnd = DndSession{}

// dnd_active - идёт ли сейчас перетаскивание между виджетами.
pub fn dnd_active() bool {
	return g_dnd.active
}

// dnd_data - что перетаскивается сейчас (пустой DragData - ничего).
pub fn dnd_data() DragData {
	if !g_dnd.active {
		return DragData{}
	}
	return g_dnd.data
}

// dnd_target - адрес виджета-цели под курсором в идущем перетаскивании
// (nil - нет). Для тестов и отладки: сравнивать с voidptr(виджет).
pub fn dnd_target() voidptr {
	return dnd_addr(g_dnd.target)
}

// dnd_ext_target - адрес цели под курсором во время внешнего сброса (nil - нет).
pub fn dnd_ext_target() voidptr {
	return dnd_addr(g_dnd.ext_target)
}

// dnd_addr - адрес самого виджета за интерфейсом (nil - nil). Сравнивать
// значения &Widget напрямую нельзя: одна и та же структура может прийти в
// разных обёртках интерфейса (контейнер собирает child_widgets() заново),
// а адрес объекта у них общий (widget_object_addr, measure_cache.v).
fn dnd_addr(w &Widget) voidptr {
	if unsafe { w == nil } {
		return unsafe { nil }
	}
	return widget_object_addr(w)
}

// dnd_same_widget - a и b - один и тот же виджет (оба nil - тоже «один»).
fn dnd_same_widget(a &Widget, b &Widget) bool {
	return dnd_addr(a) == dnd_addr(b)
}

// source_ptr - адрес структуры виджета-источника (nil - внешний сброс) для
// биндингов: по нему C-ABI и Python узнают свой объект (как Ui.widget_ptr).
pub fn (info &DropInfo) source_ptr() voidptr {
	return dnd_addr(info.source)
}

// from - сброс пришёл из виджета w (сравнение по самому виджету, а не по
// обёртке интерфейса): `if info.from(list_a) { ... }`.
pub fn (info &DropInfo) from(w &Widget) bool {
	return unsafe { info.source != nil } && dnd_same_widget(info.source, w)
}

// dnd_cancel прерывает идущее перетаскивание так же, как Esc: цель ничего не
// получает, источник - on_drag_end(data, false). Нужен приложению, которое
// закрывает окно или перестраивает интерфейс посреди перетаскивания.
pub fn dnd_cancel() {
	if g_dnd.active {
		dnd_finish(false, unsafe { nil })
	}
	g_dnd.armed = false
}

// dnd_forget_window - окно закрывается: если сеанс ссылается на него,
// сеанс прекращается (иначе остались бы указатели на освобождённое окно).
// Зовётся из Window.close/cleanup.
fn dnd_forget_window(w &Window) {
	if g_dnd.press_win == w {
		g_dnd.armed = false
		g_dnd.press_win = unsafe { nil }
	}
	if g_dnd.active && (g_dnd.source_win == w || g_dnd.hover_win == w) {
		dnd_finish(false, unsafe { nil })
	}
	if g_dnd.ext_win == w {
		dnd_ext_clear()
	}
}

// ─── События ───

// dnd_on_event - первая остановка события в окне (Window.dispatch_event_inner,
// до оверлея и виджетов). true - событие съедено перетаскиванием, виджетам
// его не передавать. app - для поиска окна под курсором (переход между окнами).
fn dnd_on_event(mut w Window, ev &GuiEvent, app &App) bool {
	if g_dnd.active {
		return dnd_active_event(mut w, ev, app)
	}
	match ev.typ {
		.mouse_down {
			// Взводим только на левую кнопку и только без открытого попапа:
			// при выпадающем списке или меню нажатие - его, а не начало
			// перетаскивания под ним.
			popup_open := w.ctx.overlay_ev != unsafe { nil } || w.ctx.overlay_cb != unsafe { nil }
			if ev.mouse_btn == .left && !popup_open {
				g_dnd.armed = true
				g_dnd.press_win = unsafe { &w }
				g_dnd.press_x = ev.mouse_x
				g_dnd.press_y = ev.mouse_y
			} else {
				g_dnd.armed = false
			}
		}
		.mouse_up, .window_focus_lost {
			g_dnd.armed = false
		}
		.mouse_move {
			if !g_dnd.armed || g_dnd.press_win != unsafe { &w } {
				return false
			}
			// Кнопку отпустили там, где мы этого не увидели (за пределами
			// окна без захвата мыши) - нажатие уже не актуально.
			if ev.mouse_buttons & (u32(1) << (sdl_button_left - 1)) == 0 {
				g_dnd.armed = false
				return false
			}
			dx := ev.mouse_x - g_dnd.press_x
			dy := ev.mouse_y - g_dnd.press_y
			if dx * dx + dy * dy < dnd_threshold * dnd_threshold {
				return false
			}
			// Порог пройден: дальше либо перетаскивание, либо обычный жест
			// виджета - повторно не проверяем.
			g_dnd.armed = false
			return dnd_try_start(mut w, ev, app)
		}
		else {}
	}
	return false
}

// dnd_try_start ищет источник у точки нажатия и, если нашёлся, начинает
// перетаскивание. true - началось (событие съедено).
fn dnd_try_start(mut w Window, ev &GuiEvent, app &App) bool {
	path := w.path_at(g_dnd.press_x, g_dnd.press_y)
	enabled := dnd_enabled_flags(path)
	// От самого глубокого виджета к корню: тянется ближайший к курсору
	// источник (лист в строке - раньше строки). Виджет со своим жестом
	// мыши (ползунок, выделение текста) поиск останавливает: нажатие - его,
	// и перехватывать жест у него нельзя.
	for i := path.len - 1; i >= 0; i-- {
		if !enabled[i] {
			continue
		}
		mut c := path[i]
		data := dnd_source_data(mut c, g_dnd.press_x, g_dnd.press_y)
		if data.kind.len == 0 {
			if dnd_owns_drag(c, i == path.len - 1) {
				return false
			}
			continue
		}
		// Гасим то, что виджеты начали по mouse_down: курсор «уходит» далеко
		// за окно без кнопок (кнопка снимает наведение и потом не нажмётся),
		// и там же кнопка отпускается (снимается флаг нажатия). Сеанс ещё не
		// активен и не взведён - dnd_on_event эти события пропустит.
		leave := GuiEvent{
			typ:       .mouse_move
			window_id: ev.window_id
			mouse_x:   dnd_cancel_xy
			mouse_y:   dnd_cancel_xy
		}
		w.dispatch_event_inner(&leave, app)
		cancel := GuiEvent{
			typ:       .mouse_up
			window_id: ev.window_id
			mouse_btn: .left
			mouse_x:   dnd_cancel_xy
			mouse_y:   dnd_cancel_xy
		}
		w.dispatch_event_inner(&cancel, app)
		g_dnd.active = true
		g_dnd.data = data
		g_dnd.source_win = unsafe { &w }
		g_dnd.source = c
		dnd_track(mut w, ev.mouse_x, ev.mouse_y, app)
		return true
	}
	return false
}

// dnd_owns_drag - у виджета w свой жест «нажал и тянешь», и перетаскивание
// предка поверх него начинаться не должно: значение ползунка, выделение
// текста, рисование на холсте, панорама, ширина колонки. Синтетическое
// движение мыши, которым гасится жест источника (dnd_try_start), такому
// виджету сдвинуло бы значение. leaf - w самый глубокий под курсором: у
// ScrollBox свой жест (бегунок) только тогда, когда нажали на него самого,
// а не на содержимое. ListBox/TreeView (не источники) мешают, только пока
// идёт их собственный жест - нажатие на строку отдаёт перетаскивание предку.
fn dnd_owns_drag(w &Widget, leaf bool) bool {
	if w is Slider || w is Splitter || w is TextInput || w is TextArea || w is CodeEditor
		|| w is Canvas || w is CurveEditor || w is ColorPicker || w is ImageView
		|| w is PlotView || w is TableView || w is MarkdownView || w is NodeEditor {
		return true
	}
	if w is ScrollBox {
		return leaf
	}
	// DockArea: нажатие на вкладку или полосу - его перенос панели / изменение
	// размера; на содержимое панели - не его жест
	if w is DockArea {
		return leaf
	}
	if w is ListBox {
		return w.sb_dragging || w.hsb_dragging || w.col_resizing
	}
	if w is TreeView {
		return w.vsb_dragging || w.hsb_dragging || w.editing
	}
	return false
}

// dnd_source_data - данные, которые отдаёт виджет c при нажатии в (x, y):
// у встроенных (ListBox/TreeView) - их dnd_begin, у прочих - on_drag_start
// поля dnd. Пустой kind - c не источник.
fn dnd_source_data(mut c Widget, x f32, y f32) DragData {
	if mut c is DndBuiltin {
		return c.dnd_begin(x, y)
	}
	spec := widget_dnd(c)
	if unsafe { spec == nil } || spec.on_drag_start == unsafe { nil } {
		return DragData{}
	}
	return spec.on_drag_start(x, y)
}

// dnd_active_event - событие окна во время перетаскивания. Мышь и клавиши
// съедаются; колесо проходит (прокрутить список под курсором, чтобы бросить
// ниже, - обычное дело).
fn dnd_active_event(mut w Window, ev &GuiEvent, app &App) bool {
	match ev.typ {
		.mouse_move {
			dnd_track(mut w, ev.mouse_x, ev.mouse_y, app)
			return true
		}
		.mouse_up {
			if ev.mouse_btn == .left {
				dnd_track(mut w, ev.mouse_x, ev.mouse_y, app)
				dnd_finish(true, app)
			}
			return true
		}
		.mouse_down, .mouse_dbl_click, .key_up, .text_input {
			return true
		}
		.key_down {
			if ev.keycode == sdl_k_escape {
				dnd_finish(false, app)
			}
			return true
		}
		.window_focus_lost {
			// Фокус ушёл из окна-источника (переключение окон с клавиатуры,
			// всплывшее системное окно) - отпускания мы уже не увидим.
			if g_dnd.source_win == unsafe { &w } {
				dnd_finish(false, app)
			}
			return false
		}
		else {
			return false
		}
	}
}

// dnd_track - курсор в точке (x, y) окна w (логические координаты, могут быть
// за пределами окна - мышь захвачена): найти окно под курсором и цель в нём,
// обновить подсветку и форму курсора.
fn dnd_track(mut w Window, x f32, y f32, app &App) {
	mut hw, hx, hy := dnd_window_under(mut w, x, y, app)
	old_win := g_dnd.hover_win
	if old_win != hw && unsafe { old_win != nil } {
		// Окно, откуда ушёл курсор, перерисует себя уже без призрака
		mut ow := unsafe { old_win }
		ow.ctx.invalidate_all()
	}
	g_dnd.hover_win = hw
	g_dnd.hover_x = hx
	g_dnd.hover_y = hy
	mut target := unsafe { &Widget(nil) }
	mut builtin := false
	if unsafe { hw != nil } {
		target, builtin = dnd_find_target(mut hw, g_dnd.data, g_dnd.source, hx, hy)
		hw.ctx.invalidate_all()
	}
	if !dnd_same_widget(target, g_dnd.target) {
		dnd_leave_target(g_dnd.target, g_dnd.target_builtin)
	}
	g_dnd.target = target
	g_dnd.target_builtin = builtin
	set_cursor(if unsafe { target != nil } {
		sdl_system_cursor_default
	} else {
		sdl_system_cursor_no
	})
}

// dnd_find_target ищет цель для data в точке (x, y) окна w: от самого
// глубокого виджета под точкой к корню, первый включённый, кто примет.
// Возвращает цель (nil - нет) и признак «встроенная» (DndBuiltin).
fn dnd_find_target(mut w Window, data DragData, source &Widget, x f32, y f32) (&Widget, bool) {
	w.arrange_if_needed()
	path := w.path_at(x, y)
	enabled := dnd_enabled_flags(path)
	for i := path.len - 1; i >= 0; i-- {
		if !enabled[i] {
			continue
		}
		mut c := path[i]
		same := unsafe { source != nil } && widget_object_addr(c) == widget_object_addr(source)
		if mut c is DndBuiltin {
			if c.dnd_over(data, same, x, y) {
				return path[i], true
			}
			continue
		}
		if dnd_spec_accepts(widget_dnd(c), data, x, y) {
			return path[i], false
		}
	}
	return unsafe { nil }, false
}

// dnd_leave_target - курсор ушёл с цели t: встроенной убрать линию вставки.
fn dnd_leave_target(t &Widget, builtin bool) {
	if unsafe { t == nil } || !builtin {
		return
	}
	mut c := unsafe { t }
	if mut c is DndBuiltin {
		c.dnd_leave()
	}
}

// path_at - путь виджетов под точкой (x, y) окна (корень первым, см.
// widget_path_at) по верхнему из корней окна, в который попала точка.
// Корни обходятся с конца: последний добавленный рисуется поверх.
fn (w &Window) path_at(x f32, y f32) []&Widget {
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root == nil } || !widget_is_visible(root) {
			continue
		}
		path := widget_path_at(root, x, y)
		if path.len > 0 {
			return path
		}
	}
	return []&Widget{}
}

// dnd_enabled_flags - для каждого виджета пути (от корня к листу) включён ли
// он с учётом предков: отключённый контейнер выключает всё поддерево.
fn dnd_enabled_flags(path []&Widget) []bool {
	mut out := []bool{len: path.len}
	mut en := true
	for i, p in path {
		en = en && widget_enabled(p)
		out[i] = en
	}
	return out
}

// dnd_finish завершает перетаскивание: drop = true - сбросить в текущую цель
// (если она есть), false - отмена. Источнику - on_drag_end(data, accepted).
// Колбэки зовутся после того, как сеанс уже сброшен: on_drop может открыть
// диалог или начать новый цикл событий, и старое состояние ему не мешает.
// app - для встроенных целей (контекст окна цели); nil допустим при отмене.
fn dnd_finish(drop bool, app &App) {
	data := g_dnd.data
	source := g_dnd.source
	target := g_dnd.target
	builtin := g_dnd.target_builtin
	mut src_win := g_dnd.source_win
	mut hov_win := g_dnd.hover_win
	hx := g_dnd.hover_x
	hy := g_dnd.hover_y
	dnd_reset()
	set_cursor(sdl_system_cursor_default)
	if unsafe { src_win != nil } {
		src_win.ctx.invalidate_all()
	}
	if unsafe { hov_win != nil } {
		hov_win.ctx.invalidate_all()
	}
	dnd_leave_target(target, builtin)

	mut accepted := false
	if drop && unsafe { target != nil } {
		info := DropInfo{
			data:   data
			x:      hx
			y:      hy
			source: source
			same:   dnd_same_widget(target, source)
		}
		accepted = dnd_deliver_in(target, builtin, info, app, hov_win)
	}
	if unsafe { source != nil } {
		spec := widget_dnd(source)
		if unsafe { spec != nil } && spec.on_drag_end != unsafe { nil } {
			spec.on_drag_end(data, accepted)
		}
	}
}

// dnd_deliver_in - dnd_deliver с активным контекстом окна цели win: при
// переносе между окнами событие пришло окну-источнику, и App держит активным
// его контекст, а встроенная цель меряет текст шрифтами своего окна.
fn dnd_deliver_in(t &Widget, builtin bool, info DropInfo, app &App, win &Window) bool {
	if unsafe { app == nil || win == nil } {
		return dnd_deliver(t, builtin, info, app)
	}
	mut mapp := unsafe { &App(app) }
	saved := mapp.active_ctx
	mapp.active_ctx = &win.ctx
	ok := dnd_deliver(t, builtin, info, app)
	mapp.active_ctx = saved
	return ok
}

// dnd_deliver отдаёт сброс цели t: встроенной - dnd_drop, обычной - on_drop
// поля dnd. true - сброс принят.
fn dnd_deliver(t &Widget, builtin bool, info DropInfo, app &App) bool {
	mut c := unsafe { t }
	if builtin {
		if mut c is DndBuiltin {
			return c.dnd_drop(info, app)
		}
		return false
	}
	spec := widget_dnd(c)
	if unsafe { spec == nil } || spec.on_drop == unsafe { nil } {
		return false
	}
	spec.on_drop(info)
	return true
}

// dnd_reset обнуляет сеанс (кроме внешнего сброса - он живёт по своим
// событиям SDL). Указатели на окна и виджеты обязательно стираются: иначе
// сеанс держал бы их живыми для GC.
fn dnd_reset() {
	g_dnd.armed = false
	g_dnd.press_win = unsafe { nil }
	g_dnd.active = false
	g_dnd.data = DragData{}
	g_dnd.source_win = unsafe { nil }
	g_dnd.source = unsafe { nil }
	g_dnd.hover_win = unsafe { nil }
	g_dnd.target = unsafe { nil }
	g_dnd.target_builtin = false
}

// ─── Окно под курсором (перетаскивание между окнами) ───

fn C.SDL_GetCurrentVideoDriver() &char

// dnd_cross_window_ok - можно ли искать цель в других окнах. На Wayland окно
// не знает своей позиции на экране (SDL_GetWindowPosition даёт 0, 0), и
// экранную точку курсора посчитать нельзя - там перетаскивание только внутри
// окна-источника.
fn dnd_cross_window_ok() bool {
	drv := C.SDL_GetCurrentVideoDriver()
	if unsafe { drv == nil } {
		return true
	}
	return unsafe { cstring_to_vstring(drv) } != 'wayland'
}

// dnd_window_under - окно приложения под курсором и точка в его логических
// координатах. (x, y) - точка в окне w, где пришло событие. Порядок проверки:
// сначала само w (курсор чаще всего в нём), затем открытые диалоги (обычно
// поверх), затем остальные окна. Окна, заблокированные модальным диалогом,
// пропускаются; из модального диалога тянуть можно только внутри него.
// Возвращает nil, если курсор ни над одним окном.
fn dnd_window_under(mut w Window, x f32, y f32, app &App) (&Window, f32, f32) {
	if dnd_window_contains(w, x, y) {
		return unsafe { &w }, x, y
	}
	if !dnd_cross_window_ok() || dnd_is_modal_dialog(w, app) {
		return unsafe { nil }, x, y
	}
	gx, gy := dnd_to_screen(w, x, y)
	for d in app.dialogs {
		if !d.is_open() || d.win == unsafe { &w } {
			continue
		}
		if lx, ly := dnd_from_screen(d.win, gx, gy) {
			return d.win, lx, ly
		}
	}
	for i := app.windows.len - 1; i >= 0; i-- {
		cand := app.windows[i]
		if cand == unsafe { &w } || !cand.open || !cand.visible || cand.minimized
			|| cand.has_modal_child {
			continue
		}
		if lx, ly := dnd_from_screen(cand, gx, gy) {
			return cand, lx, ly
		}
	}
	return unsafe { nil }, x, y
}

// dnd_is_modal_dialog - окно w - открытый модальный диалог.
fn dnd_is_modal_dialog(w &Window, app &App) bool {
	for d in app.dialogs {
		if d.win == w && d.is_open() && d.modal {
			return true
		}
	}
	return false
}

// dnd_window_contains - точка (логические координаты окна) внутри окна.
fn dnd_window_contains(w &Window, x f32, y f32) bool {
	return x >= 0 && y >= 0 && x < w.ctx.screen_width && y < w.ctx.screen_height
}

// dnd_to_screen - логическая точка окна -> экранная (координаты SDL окна
// умножены на ui_scale, плюс позиция окна).
fn dnd_to_screen(w &Window, x f32, y f32) (f32, f32) {
	mut wx := 0
	mut wy := 0
	C.SDL_GetWindowPosition(w.sdl_window, &wx, &wy)
	s := if w.ctx.ui_scale > 0 { w.ctx.ui_scale } else { f32(1) }
	return f32(wx) + x * s, f32(wy) + y * s
}

// dnd_from_screen - экранная точка -> логическая точка окна w, если она
// внутри окна; none - мимо.
fn dnd_from_screen(w &Window, gx f32, gy f32) ?(f32, f32) {
	mut wx := 0
	mut wy := 0
	C.SDL_GetWindowPosition(w.sdl_window, &wx, &wy)
	s := if w.ctx.ui_scale > 0 { w.ctx.ui_scale } else { f32(1) }
	lx := (gx - f32(wx)) / s
	ly := (gy - f32(wy)) / s
	if !dnd_window_contains(w, lx, ly) {
		return none
	}
	return lx, ly
}

// ─── Сбросы из других приложений (SDL drop_*) ───

// dnd_external_event - внешний сброс в окне w (Window.dispatch_event_inner,
// ПОСЛЕ виджетов: DropZone остаётся первой). handled - событие уже съел
// виджет (DropZone). Для drop_file/drop_text возвращает true, если файл или
// текст отдан цели (тогда оконный on_drop_* не зовётся).
//   drop_begin / drop_complete - подсветка цели снимается;
//   drop_position - цель под курсором: kind сброса SDL сообщает только в
//     самом сбросе, поэтому подходит цель, принимающая 'files' или
//     'text/plain';
//   drop_file / drop_text - сброс цели под точкой (каждый файл - отдельным
//     вызовом on_drop, как приходят от SDL).
fn dnd_external_event(mut w Window, ev &GuiEvent, handled bool, app &App) bool {
	match ev.typ {
		.drop_begin, .drop_complete {
			dnd_ext_clear()
		}
		.drop_position {
			mut target, mut builtin := dnd_find_target(mut w, DragData{ kind: dnd_kind_files },
				unsafe { nil }, ev.mouse_x, ev.mouse_y)
			if unsafe { target == nil } {
				target, builtin = dnd_find_target(mut w, DragData{ kind: dnd_kind_text },
					unsafe { nil }, ev.mouse_x, ev.mouse_y)
			}
			if !dnd_same_widget(target, g_dnd.ext_target) {
				dnd_leave_target(g_dnd.ext_target, g_dnd.ext_target_builtin)
			}
			g_dnd.ext_win = if unsafe { target != nil } { unsafe { &w } } else { unsafe { nil } }
			g_dnd.ext_target = target
			g_dnd.ext_target_builtin = builtin
		}
		.drop_file, .drop_text {
			if handled {
				dnd_ext_clear()
				return false
			}
			kind := if ev.typ == .drop_file { dnd_kind_files } else { dnd_kind_text }
			data := DragData{
				kind: kind
				text: ev.text
			}
			target, builtin := dnd_find_target(mut w, data, unsafe { nil }, ev.mouse_x,
				ev.mouse_y)
			// Индикатор снимаем и у прежней цели, и у новой: сброс состоялся.
			// Внешний сеанс не обнуляем целиком - за первым файлом могут идти
			// следующие (SDL шлёт drop_file на каждый), их цель та же точка.
			dnd_leave_target(g_dnd.ext_target, g_dnd.ext_target_builtin)
			g_dnd.ext_target = unsafe { nil }
			g_dnd.ext_target_builtin = false
			g_dnd.ext_win = unsafe { nil }
			if unsafe { target == nil } {
				return false
			}
			info := DropInfo{
				data:     data
				x:        ev.mouse_x
				y:        ev.mouse_y
				external: true
			}
			// Встроенная цель (ImageView и не картинка) может сброс не взять -
			// тогда он уходит дальше, оконному on_drop_*
			return dnd_deliver_in(target, builtin, info, app, &w)
		}
		else {}
	}
	return false
}

// dnd_ext_clear - внешний сброс закончился или начался заново: снять
// подсветку и забыть цель.
fn dnd_ext_clear() {
	dnd_leave_target(g_dnd.ext_target, g_dnd.ext_target_builtin)
	if unsafe { g_dnd.ext_win != nil } {
		mut ew := g_dnd.ext_win
		ew.ctx.invalidate_all()
	}
	g_dnd.ext_win = unsafe { nil }
	g_dnd.ext_target = unsafe { nil }
	g_dnd.ext_target_builtin = false
}

// ─── Встроенный приём (TextInput, TextArea, CodeEditor, ImageView) ───
//
// Эти виджеты принимают сброс сами, без настройки поля dnd (поле
// accept_drops = true по умолчанию, false - выключить):
//   - TextInput/TextArea/CodeEditor - текст ('text/plain') или путь файла
//     ('files') вставляется в точку сброса: курсор ставится туда, выделение
//     снимается (сброс не заменяет выделенный текст - точка сброса обычно в
//     другом месте). Однострочное поле склеивает строки пробелом. CodeEditor
//     с readonly не принимает;
//   - ImageView - файл-картинка открывается (set_path); прочие файлы не
//     принимаются, и сброс уходит дальше (оконному on_drop_file).
// Явная роль цели в поле dnd (set_drop_target) главнее встроенной: если она
// приняла данные, встроенный приём не делается. Порядок для внешних файлов:
// DropZone -> цель под курсором (явная, затем встроенная) -> окно.

// dnd_spec_or_builtin_over - общая часть dnd_over встроенных приёмников:
// примет ли виджет со своим полем spec и флагом встроенного приёма
// builtin_ok данные data. same - тащат из самого виджета: себе в себя
// встроенный приём не делается (текст переехал бы сам в себя).
fn dnd_spec_or_builtin_over(spec &DragSpec, builtin_ok bool, data DragData, same bool, x f32, y f32) bool {
	if dnd_spec_accepts(spec, data, x, y) {
		return true
	}
	return builtin_ok && !same
}

// dnd_spec_drop - если поле dnd принимает сброс, отдать его on_drop и вернуть
// true; false - решать встроенному приёму.
fn dnd_spec_drop(spec &DragSpec, info DropInfo) bool {
	if !dnd_spec_accepts(spec, info.data, info.x, info.y) {
		return false
	}
	spec.on_drop(info)
	return true
}

// dnd_spec_source - источник по полю dnd (on_drag_start) для встроенных
// виджетов, у которых своих перетаскиваемых элементов нет.
fn dnd_spec_source(spec &DragSpec, x f32, y f32) DragData {
	if unsafe { spec == nil } || spec.on_drag_start == unsafe { nil } {
		return DragData{}
	}
	return spec.on_drag_start(x, y)
}

// dnd_is_text_kind - текст или файл: то, что встроенно принимают текстовые
// виджеты.
fn dnd_is_text_kind(kind string) bool {
	return kind == dnd_kind_text || kind == dnd_kind_files
}

// dnd_image_exts - расширения файлов, которые ImageView открывает по
// сбросу: форматы SDL_image. Путь файла SDL сообщает только в самом
// сбросе, поэтому при наведении ImageView подсвечивается на любой файл, а
// не-картинку при сбросе не принимает.
const dnd_image_exts = ['.png', '.jpg', '.jpeg', '.bmp', '.gif', '.webp', '.tga', '.tif', '.tiff',
	'.qoi', '.avif', '.jxl', '.svg', '.ico', '.cur', '.pnm', '.ppm', '.pgm', '.pbm', '.xpm', '.xcf',
	'.lbm', '.pcx']

// dnd_is_image_path - путь похож на картинку (по расширению, без учёта регистра).
fn dnd_is_image_path(path string) bool {
	lower := path.to_lower()
	for ext in dnd_image_exts {
		if lower.ends_with(ext) {
			return true
		}
	}
	return false
}

// ─── Отрисовка ───

// dnd_paints - рисует ли окно w в этом кадре что-то от перетаскивания
// (призрак, подсветку цели). Такой кадр - полный: призрак лежит поверх
// виджетов вне их bounds (как подсказка), и при сдвиге оставил бы след.
fn dnd_paints(w &Window) bool {
	if g_dnd.active && g_dnd.hover_win == w {
		return true
	}
	return g_dnd.ext_win == w && unsafe { g_dnd.ext_target != nil }
}

// dnd_draw рисует поверх всего окна: рамку вокруг цели (ListBox и TreeView
// рисуют свою линию вставки сами, в draw()) и призрак с подписью у курсора.
// Зовётся из Window.render после оверлеев и подсказок.
fn dnd_draw(mut w Window) {
	accent := w.ctx.theme.accent
	if g_dnd.ext_win == unsafe { &w } && unsafe { g_dnd.ext_target != nil }
		&& !dnd_own_marker(g_dnd.ext_target) {
		dnd_draw_target_frame(mut w.ctx, get_widget_bounds(g_dnd.ext_target), accent)
	}
	if !g_dnd.active || g_dnd.hover_win != unsafe { &w } {
		return
	}
	has_target := unsafe { g_dnd.target != nil }
	if has_target && !dnd_own_marker(g_dnd.target) {
		dnd_draw_target_frame(mut w.ctx, get_widget_bounds(g_dnd.target), accent)
	}
	dnd_draw_ghost(mut w.ctx, dnd_ghost_label(g_dnd.data), g_dnd.hover_x, g_dnd.hover_y,
		has_target)
}

// dnd_own_marker - цель рисует место сброса сама (линия вставки ListBox,
// индикатор TreeView), рамка вокруг неё не нужна.
fn dnd_own_marker(t &Widget) bool {
	return t is ListBox || t is TreeView
}

// dnd_draw_target_frame - рамка подсветки цели толщиной 2: акцентный цвет
// поверх содержимого, внутрь bounds (снаружи она залезла бы на соседей).
fn dnd_draw_target_frame(mut ctx RenderContext, b Rect, accent Color) {
	if b.w <= 4 || b.h <= 4 {
		return
	}
	r := ctx.theme.border_radius
	ctx.draw_rounded_rect(b, accent, r)
	ctx.draw_rounded_rect(Rect{b.x + 1, b.y + 1, b.w - 2, b.h - 2}, accent, r)
}

// dnd_ghost_label - подпись призрака: label или первая строка text, не
// длиннее 40 символов (длинный путь или абзац обрезается многоточием).
fn dnd_ghost_label(d DragData) string {
	mut s := if d.label.len > 0 { d.label } else { d.text.all_before('\n') }
	runes := s.runes()
	if runes.len > 40 {
		s = runes[..39].string() + '…'
	}
	return s
}

// dnd_draw_ghost - полупрозрачная плашка с подписью правее и ниже курсора
// (не под ним - иначе закрыла бы место сброса). Без цели плашка тусклее.
fn dnd_draw_ghost(mut ctx RenderContext, label string, x f32, y f32, has_target bool) {
	if label.len == 0 {
		return
	}
	font := ctx.get_font(.regular, 0)
	sz := ctx.measure_text_with_font(label, font)
	pad_x := f32(8)
	pad_y := f32(4)
	r := Rect{x + 14, y + 10, sz.x + pad_x * 2, sz.y + pad_y * 2}
	alpha := if has_target { u8(235) } else { u8(160) }
	mut bg := ctx.theme.panel_bg
	bg.a = alpha
	mut border := if has_target { ctx.theme.accent } else { ctx.theme.border }
	border.a = alpha
	mut fg := ctx.theme.text_primary
	fg.a = alpha
	ctx.fill_rounded_rect(r, bg, ctx.theme.border_radius)
	ctx.draw_rounded_rect(r, border, ctx.theme.border_radius)
	ctx.draw_text_with_font(label, r.x + pad_x, r.y + pad_y, fg, font)
}
