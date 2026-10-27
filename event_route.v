// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════════
//  Доставка событий по маршруту (PROJECT.md, «Доставка событий»;
//  план перевода - docs/event_routing.md)
// ═══════════════════════════════════════════════════════════
//
//  Раньше событие спускалось от корней окна: каждый контейнер в своём
//  handle_event раздавал его детям (event_child), пока кто-то не поглотит,
//  а каждый виджет сам решал, его ли оно (наведение по bounds.contains на
//  каждом движении, свой флаг фокуса и снятие его по клику мимо). Теперь
//  указателем и фокусом владеет окно: оно само находит, кому событие, и
//  доставляет его по пути от этого виджета к корню («всплытие»). Контейнер
//  обрабатывает только своё (полосы прокрутки, заголовки, разделитель) и
//  детям событий не раздаёт.
//
//  Мышь (Window.route_mouse_event), по шагам:
//    1. слои-наблюдатели - корни окна, прозрачные для курсора (ContextMenu,
//       NotificationManager, Tooltip): событие первым и с настоящими
//       координатами - меню ловит правый клик по своей цели;
//    2. нажатие мимо виджета с фокусом снимает фокус (FocusManager.
//       blur_current) - в одном месте, а не в каждом поле ввода. Раньше
//       маршрута: нажатый виджет может тут же взять фокус себе;
//    3. mouse_leave / mouse_enter (только при движении) - виджетам, ушедшим
//       из пути под курсором и вошедшим в него; раньше самого движения, как
//       в браузере: ушедший вернёт стрелку до того, как новый поставит свой
//       курсор мыши;
//    4. захват - виджет, поглотивший нажатие, получает движения и
//       отпускание первым до конца жеста (ползунок, разделитель, выделение
//       текста мышью), где бы ни был курсор; поглотил - дальше не идёт;
//    5. маршрут - путь до виджета под курсором (widget_path_at, тот же
//       поиск, что у наведения и подсказок), событие от листа к корню.
//       Нажатие, отпускание, колесо, двойной клик - до первого поглотившего.
//       Движение - всем на пути: по нему предки следят за наведением
//       (разделитель, ScrollBox, заголовки Accordion) и над ребёнком.
//
//  Клавиатура и ввод текста (Window.route_key_event):
//    1. виджет с фокусом и его предки (составной виджет, у которого фокус
//       у внутренней части, находится через FocusOwner);
//    2. виджет под курсором и его предки - просмотрщики (ImageView,
//       PlotView, MarkdownView) принимают клавиши масштаба без фокуса;
//    ShortcutOverride: пока в фокусе виджет текстового ввода, печатная
//       клавиша без Ctrl/Alt дальше не идёт (shortcut_overridden);
//    3. глобальные слушатели: корни-наблюдатели (ContextMenu) и строки меню
//       (сочетания клавиш пунктов меню);
//    4. горячие клавиши окна и приложения - в dispatch_event_inner.
//
//  Прочее (изменение размера окна, сброс файлов) - спуском от корней.

// is_routed_mouse_event — событие мыши, доставляемое маршрутом.
fn is_routed_mouse_event(ev &GuiEvent) bool {
	return ev.typ in [.mouse_move, .mouse_down, .mouse_up, .mouse_wheel, .mouse_dbl_click]
}

// is_routed_key_event — клавиатура и ввод текста, доставляемые маршрутом.
fn is_routed_key_event(ev &GuiEvent) bool {
	return ev.typ in [.key_down, .key_up, .text_input]
}

// HitsSelf — у контейнера есть своя «рамка» поверх детей: полоса прокрутки
// ScrollBox, расширенная зона захвата разделителя Splitter. Точка на ней
// принадлежит самому контейнеру: widget_at и маршрут событий не спускаются
// в ребёнка под ней.
pub interface HitsSelf {
	hits_self(x f32, y f32) bool
}

// widget_hits_self — точка (x, y) на своей «рамке» виджета (HitsSelf).
// Отдельной функцией: `if w is HitsSelf` сужает w, и вернуть его как &Widget
// внутри проверки уже нельзя.
fn widget_hits_self(w &Widget, x f32, y f32) bool {
	if w is HitsSelf {
		return w.hits_self(x, y)
	}
	return false
}

// FocusOwner — составной виджет, у которого фокус-учёт держит внутреннюю
// часть, а не сам виджет: поле ввода Spinbox, кнопка ShortcutInput, поле
// правки PropertyGrid. Внутренней части нет в дереве (её рисует и кормит
// событиями владелец), поэтому маршрут клавиш идёт к владельцу.
pub interface FocusOwner {
	owns_focus(ptr voidptr) bool
}

// widget_has_focus_of — виджет w сам в фокусе (ptr) или владеет им.
fn widget_has_focus_of(w &Widget, ptr voidptr) bool {
	if widget_object_addr(w) == ptr {
		return true
	}
	if w is FocusOwner {
		return w.owns_focus(ptr)
	}
	return false
}

// route_is_observer_root — корень окна, которому события достаются всегда и
// первыми: служебный слой, прозрачный для курсора.
fn route_is_observer_root(w &Widget) bool {
	return w is ContextMenu || w is Tooltip || w is NotificationManager
}

// route_is_key_listener — виджет слушает клавиши глобально, без фокуса:
// строка меню и корни-наблюдатели (сочетания клавиш пунктов меню).
fn route_is_key_listener(w &Widget) bool {
	return w is MenuBar || route_is_observer_root(w)
}

// shortcut_overridden — клавишу забирает виджет текстового ввода в фокусе
// (ShortcutOverride, route_key_event): key_down печатного символа (не
// служебная клавиша: у стрелок и F-клавиш в keycode бит 1 << 30; не Esc,
// Enter, Tab, Backspace, Delete) без Ctrl и Alt, пока фокус-учёту нужен
// текстовый ввод (wants_text: поле ввода, текстовая область, редактор
// кода, правка в дереве и сетке свойств).
fn shortcut_overridden(fm &FocusManager, ev &GuiEvent) bool {
	if ev.typ != .key_down || !fm.wants_text() {
		return false
	}
	if ev.mod_keys & (sdl_kmod_ctrl | sdl_kmod_alt) != 0 {
		return false
	}
	return ev.keycode >= 32 && ev.keycode != 127 && ev.keycode & (1 << 30) == 0
}

// route_children — дети, которые сейчас получают ввод: у вкладок - только
// активная, у Accordion - раскрытые секции, у ListBox - видимые строки
// (hit_children), у остальных - все.
fn route_children(n &Widget) []&Widget {
	if n is HitTestable {
		return n.hit_children()
	}
	if n is HasChildren {
		return n.child_widgets()
	}
	return []&Widget{}
}

// route_path_at — путь от корня окна до виджета под точкой (x, y): верхний
// по z-порядку корень, тот же поиск, что у наведения (widget_path_at).
// Путь обрывается перед первым отключённым виджетом - отключённая ветка
// ввода не получает.
fn (w &Window) route_path_at(x f32, y f32) []&Widget {
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root == nil } || !widget_is_visible(root) {
			continue
		}
		path := widget_path_at(root, x, y)
		if path.len == 0 {
			continue
		}
		return route_cut_disabled(path)
	}
	return []&Widget{}
}

// route_cut_disabled — путь до первого отключённого виджета (не включая его).
fn route_cut_disabled(path []&Widget) []&Widget {
	for j, p in path {
		if !widget_enabled(p) {
			return path[..j]
		}
	}
	return path
}

// route_find_path — путь от корня окна до первого видимого виджета (обход в
// глубину по детям, получающим ввод), для которого pred вернул true. Пусто -
// не нашёлся (скрыт, на неактивной вкладке, удалён).
fn (w &Window) route_find_path(pred fn (&Widget) bool) []&Widget {
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root == nil } {
			continue
		}
		mut path := []&Widget{}
		if route_find_impl(root, pred, mut path, 0) {
			return route_cut_disabled(path.reverse())
		}
	}
	return []&Widget{}
}

// route_find_impl — рекурсия route_find_path; путь копится на обратном ходе.
fn route_find_impl(n &Widget, pred fn (&Widget) bool, mut path []&Widget, depth int) bool {
	if depth > widget_tree_max_depth || !widget_is_visible(n) {
		return false
	}
	if pred(n) {
		path << unsafe { n }
		return true
	}
	for c in route_children(n) {
		if unsafe { c != nil } && route_find_impl(c, pred, mut path, depth + 1) {
			path << unsafe { n }
			return true
		}
	}
	return false
}

// route_deliver — событие одному виджету (детям он его не раздаёт).
fn route_deliver(w &Widget, ev &GuiEvent, app &App) bool {
	mut target := unsafe { *w }
	return target.handle_event(ev, app)
}

// route_contains — есть ли виджет (по адресу объекта) в пути.
fn route_contains(path []&Widget, w &Widget) bool {
	addr := widget_object_addr(w)
	for p in path {
		if widget_object_addr(p) == addr {
			return true
		}
	}
	return false
}

// RouteScope — на время доставки по маршруту: активный контекст окна
// (виджеты берут его в handle_event для измерения текста). Обработчик мог
// запустить вложенный цикл (модальный диалог), который сбросил активный
// контекст, - route_activate ставит его перед каждой доставкой, route_end
// возвращает прежний.
struct RouteScope {
	ctx &RenderContext = unsafe { nil }
}

fn (mut w Window) route_begin(app &App) RouteScope {
	return RouteScope{
		ctx: app.active_ctx
	}
}

fn (mut w Window) route_activate(app &App) {
	mut mapp := unsafe { &App(app) }
	mapp.active_ctx = &w.ctx
}

fn (mut w Window) route_end(app &App, s RouteScope) {
	mut mapp := unsafe { &App(app) }
	mapp.active_ctx = s.ctx
}

// ─── Мышь ──────────────────────────────────────────────

// route_mouse_event — доставка события мыши по маршруту (шаги - в шапке
// файла). true - кто-то его поглотил.
fn (mut w Window) route_mouse_event(ev &GuiEvent, app &App) bool {
	// у колеса своих координат нет - курсор берётся из контекста окна
	x := if ev.typ == .mouse_wheel { w.ctx.mouse_x } else { ev.mouse_x }
	y := if ev.typ == .mouse_wheel { w.ctx.mouse_y } else { ev.mouse_y }
	path := w.route_path_at(x, y)
	scope := w.route_begin(app)
	defer {
		w.route_end(app, scope)
	}

	// 1. слои-наблюдатели: настоящие координаты, первыми
	if w.route_observers(path, ev, app) {
		w.route_end_gesture(ev)
		return true
	}

	// 2. нажатие мимо виджета с фокусом снимает фокус
	owner := w.route_capture_owner()
	if ev.typ == .mouse_down {
		w.route_blur_outside(path)
	}

	// 3. уход и вход курсора - раньше доставки самого движения (как в
	// браузере): ушедший виджет возвращает свой курсор мыши (стрелку) до
	// того, как новый под курсором поставит свой
	if ev.typ == .mouse_move {
		w.route_hover_change(path, owner, ev, app)
	}

	// 4. захват жеста
	mut handled := false
	if w.route_capture.len > 0 && ev.typ in [.mouse_move, .mouse_up] {
		w.route_activate(app)
		handled = w.route_deliver_css(w.route_capture, w.route_capture.len - 1, ev, app)
	}

	// 5. маршрут: от листа к корню
	if !handled && path.len > 0 {
		consumer := w.route_bubble(path, ev, app, ev.typ == .mouse_move)
		if consumer >= 0 {
			handled = true
			if ev.typ == .mouse_down {
				// поглотивший нажатие ведёт жест до отпускания
				w.route_capture = path[..consumer + 1].clone()
			}
		}
	}

	w.route_end_gesture(ev)
	return handled
}

// route_observers — шаг 1: корни-наблюдатели (не на пути - те получат
// событие в маршруте). true - кто-то поглотил.
fn (mut w Window) route_observers(path []&Widget, ev &GuiEvent, app &App) bool {
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root == nil } || !route_is_observer_root(root) || !widget_is_visible(root) {
			continue
		}
		if route_contains(path, root) {
			continue
		}
		w.route_activate(app)
		if route_deliver(root, ev, app) {
			return true
		}
	}
	return false
}

// route_blur_outside — шаг 2: нажатие не по виджету с фокусом (и не по его
// потомку - путь его не содержит) снимает фокус. Сам виджет при этом
// сбрасывает выделение, перетаскивание, закрывает попап (blur_current).
fn (mut w Window) route_blur_outside(path []&Widget) {
	fm := &w.ctx.focus
	if fm.current < 0 || fm.current >= fm.entries.len {
		return
	}
	ptr := fm.entries[fm.current].ptr
	for p in path {
		if widget_has_focus_of(p, ptr) {
			return
		}
	}
	w.ctx.focus.blur_current()
}

// route_hover_change — шаг 3: mouse_leave виджетам прошлого пути, которых
// нет в новом (от листа к корню), mouse_enter - вошедшим (от корня к листу).
// Ведущий жест их не получает: для него курсор по-прежнему «его».
fn (mut w Window) route_hover_change(path []&Widget, owner voidptr, ev &GuiEvent, app &App) {
	mut leave := *ev
	leave.typ = .mouse_leave
	for i := w.route_hover.len - 1; i >= 0; i-- {
		p := w.route_hover[i]
		if route_contains(path, p) || (!isnil(owner) && widget_object_addr(p) == owner) {
			continue
		}
		w.route_activate(app)
		route_deliver(p, &leave, app)
	}
	mut enter := *ev
	enter.typ = .mouse_enter
	for p in path {
		if route_contains(w.route_hover, p) {
			continue
		}
		w.route_activate(app)
		route_deliver(p, &enter, app)
	}
	w.route_hover = path.clone()
}

// route_end_gesture — отпускание кнопки завершает жест: захвата больше нет.
fn (mut w Window) route_end_gesture(ev &GuiEvent) {
	if ev.typ == .mouse_up {
		w.route_capture.clear()
	}
}

// route_capture_owner — адрес виджета, ведущего жест (nil - жеста нет).
fn (w &Window) route_capture_owner() voidptr {
	if w.route_capture.len == 0 {
		return unsafe { nil }
	}
	return widget_object_addr(w.route_capture.last())
}

// route_bubble — событие по пути от листа (path.last()) к корню. Шрифт и
// отступы из CSS - как при отрисовке: стили входят по пути от корня, а при
// всплытии выходят по одному уровню (css_enter_layout/css_leave_layout).
// all_on_path - не останавливаться на поглотившем (движение мыши). skip -
// виджеты, которые событие уже получили (маршрут клавиш: фокус, потом
// курсор). Возвращает индекс первого поглотившего (-1 - никто).
fn (mut w Window) route_bubble_skip(path []&Widget, ev &GuiEvent, app &App, all_on_path bool, skip []&Widget) int {
	css := w.ctx.css_layout_active()
	mut saved := []CssLayoutSaved{cap: path.len}
	if css {
		for p in path {
			saved << w.ctx.css_enter_layout(widget_object_addr(p), css_tags_of(p))
		}
	}
	mut consumer := -1
	for i := path.len - 1; i >= 0; i-- {
		if !route_contains(skip, path[i]) {
			w.route_activate(app)
			if route_deliver(path[i], ev, app) && consumer < 0 {
				consumer = i
			}
		}
		if css {
			w.ctx.css_leave_layout(saved[i])
		}
		if consumer >= 0 && !all_on_path {
			// оставшиеся уровни стилей - снять до корня
			if css {
				for j := i - 1; j >= 0; j-- {
					w.ctx.css_leave_layout(saved[j])
				}
			}
			break
		}
	}
	return consumer
}

fn (mut w Window) route_bubble(path []&Widget, ev &GuiEvent, app &App, all_on_path bool) int {
	return w.route_bubble_skip(path, ev, app, all_on_path, []&Widget{})
}

// route_deliver_css — событие только виджету path[idx] (захват жеста), со
// стилями всего пути до него.
fn (mut w Window) route_deliver_css(path []&Widget, idx int, ev &GuiEvent, app &App) bool {
	css := w.ctx.css_layout_active()
	mut saved := []CssLayoutSaved{cap: idx + 1}
	if css {
		for i in 0 .. idx + 1 {
			saved << w.ctx.css_enter_layout(widget_object_addr(path[i]), css_tags_of(path[i]))
		}
	}
	handled := route_deliver(path[idx], ev, app)
	if css {
		for i := idx; i >= 0; i-- {
			w.ctx.css_leave_layout(saved[i])
		}
	}
	return handled
}

// ─── Клавиатура и ввод текста ──────────────────────────

// route_key_event — клавиша или ввод текста по маршруту (шаги - в шапке
// файла; горячие клавиши - у вызывающего). true - кто-то поглотил.
fn (mut w Window) route_key_event(ev &GuiEvent, app &App) bool {
	scope := w.route_begin(app)
	defer {
		w.route_end(app, scope)
	}
	// 1. виджет с фокусом и его предки
	mut visited := []&Widget{}
	fm := &w.ctx.focus
	if fm.current >= 0 && fm.current < fm.entries.len {
		ptr := fm.entries[fm.current].ptr
		path := w.route_find_path(fn [ptr] (n &Widget) bool {
			return widget_has_focus_of(n, ptr)
		})
		if path.len > 0 {
			if w.route_bubble(path, ev, app, false) >= 0 {
				return true
			}
			visited << path
		}
	}
	// ShortcutOverride (как в Qt): пока в фокусе виджет текстового ввода,
	// печатная клавиша без Ctrl/Alt принадлежит ему - символ он получит
	// событием text_input, а key_down отдаёт дальше. Ни виджет под курсором,
	// ни сочетания меню, ни горячие клавиши её не видят: однобуквенное
	// сочетание (Q, цифры рейтинга) не сработает посреди набора текста.
	if shortcut_overridden(&w.ctx.focus, ev) {
		return true
	}
	// 2. виджет под курсором и его предки (кто ещё не получил)
	if ev.typ != .text_input {
		hover := route_cut_disabled(w.route_hover)
		if hover.len > 0 && w.route_bubble_skip(hover, ev, app, false, visited) >= 0 {
			return true
		}
		visited << hover
	}
	// 3. глобальные слушатели (корни-наблюдатели, строки меню)
	if ev.typ != .text_input {
		listeners := w.route_key_listeners()
		for l in listeners {
			if route_contains(visited, l) {
				continue
			}
			w.route_activate(app)
			if route_deliver(l, ev, app) {
				return true
			}
		}
	}
	return false
}

// route_key_listeners — глобальные слушатели клавиш (шаг 3): корни-наблюдатели
// (ContextMenu ловит сочетания клавиш своих пунктов) и строки меню в дереве.
// Своему коду приложения слушать клавиши всего окна - фильтром событий
// (Window.add_event_filter), а не невидимым виджетом.
fn (w &Window) route_key_listeners() []&Widget {
	mut out := []&Widget{}
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root != nil } {
			route_collect_listeners(root, mut out, 0)
		}
	}
	return out
}

fn route_collect_listeners(n &Widget, mut out []&Widget, depth int) {
	if depth > widget_tree_max_depth || !widget_enabled(n) {
		return
	}
	if !widget_is_visible(n) {
		// скрытая строка меню с keys_when_hidden (полноэкранный режим
		// приложения) сочетания своих пунктов ловит и скрытой
		if n is MenuBar && n.keys_when_hidden {
			out << unsafe { n }
		}
		return
	}
	if route_is_key_listener(n) {
		out << unsafe { n }
	}
	for c in route_children(n) {
		if unsafe { c != nil } {
			route_collect_listeners(c, mut out, depth + 1)
		}
	}
}

// ─── Прочие события: рассылка ──────────────────────────

// route_broadcast — событие, у которого нет одного адресата (изменение размера
// окна, начало/ход/конец перетаскивания файла над окном, сброс файла или
// текста), - всем видимым виджетам, получающим ввод, пока кто-то не поглотит.
// Обход - окном, а не контейнерами: корни и дети с конца (верхний по
// z-порядку первым, как раньше), сам виджет раньше своих детей (корневой
// контейнер при изменении окна сначала подгоняет свой размер). DropZone
// уведомления о перетаскивании не поглощает - их видят все зоны, а сброс
// поглощает зона под курсором.
fn (mut w Window) route_broadcast(ev &GuiEvent, app &App) bool {
	scope := w.route_begin(app)
	defer {
		w.route_end(app, scope)
	}
	for i := w.widgets.len - 1; i >= 0; i-- {
		root := w.widgets[i]
		if unsafe { root != nil } && w.route_broadcast_impl(root, ev, app, 0) {
			return true
		}
	}
	return false
}

fn (mut w Window) route_broadcast_impl(n &Widget, ev &GuiEvent, app &App, depth int) bool {
	if depth > widget_tree_max_depth || !widget_is_visible(n) {
		return false
	}
	// отключённая ветка ввода не получает; изменение окна - получает
	if is_input_event(ev) && !widget_enabled(n) {
		return false
	}
	w.route_activate(app)
	if route_deliver(n, ev, app) {
		return true
	}
	children := route_children(n)
	for i := children.len - 1; i >= 0; i-- {
		c := children[i]
		if unsafe { c != nil } && w.route_broadcast_impl(c, ev, app, depth + 1) {
			return true
		}
	}
	return false
}

// route_forget — окно забывает пути маршрута (закрытие, очистка): они
// держат указатели на виджеты, и GC не освободил бы удалённые.
fn (mut w Window) route_forget() {
	w.route_capture.clear()
	w.route_hover.clear()
}
