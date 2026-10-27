// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════
// Дерево виджетов — доступ к bounds и обход детей через
// интерфейсы вместо ручных switch/if-else по типам.
//
// Раньше get_widget_bounds (layout.v) и set_widget_bounds
// (containers.v) были одним длинным if-else по всем типам
// виджетов: забытая при добавлении нового виджета ветка
// молча рендерила его в (0,0) с нулевым размером — баг,
// который обнаруживался только визуально. Теперь каждый тип
// сам заявляет о поддержке через Layouted.
//
// ВАЖНО: это НЕ самопроверяющийся механизм. В V нельзя
// перечислить все реализации интерфейса программно, поэтому
// widget_tree_test.v — не более чем набор вручную написанных
// проверок (по одной на уже известный тип; сейчас около семи десятков тестов). Новый тип
// виджета, для которого забыли добавить bounds_of/set_bounds
// сюда, компилируется молча и просто НЕ ломает тест — тест
// проверяет только то, что уже в него вписано руками. Полнота
// поддерживается дисциплиной (чек-лист «Добавление нового
// виджета» в PROJECT.md), а не компилятором или тестом.
//
// Указателя на родителя (parent) у Widget НАМЕРЕННО нет:
// цикл владения ребёнок→родитель→ребёнок сломал бы якоря
// Boehm-GC в реестрах *_capi.v (см. vgui-capi/PROJECT.md, «Реестры объектов» в
// PROJECT.md) — структуры держали бы друг друга живыми даже
// без внешних ссылок. Обход дерева поэтому идёт только сверху
// вниз, через HasChildren.
// ═══════════════════════════════════════════════════════

// Layouted — виджет умеет сообщить и принять свой Rect.
// Реализован всеми типами, ранее перечисленными в
// get_widget_bounds/set_widget_bounds.
pub interface Layouted {
	bounds_of() Rect
mut:
	set_bounds(r Rect)
}

// HasChildren — контейнер, реально держащий детей-Widget.
// Разные контейнеры хранят детей по-разному (один child,
// slice, first/second, ячейки сетки, строки списка...),
// child_widgets() нормализует это в единый []&Widget для
// walk_widgets/widget_at.
// Примечание о цене: child_widgets() аллоцирует новый []&Widget
// на каждый вызов (даже там, где внутреннее хранилище уже
// []&Widget, отдаётся .clone(), а не сам слайс — вызывающая
// сторона не должна получить доступ к внутреннему буферу
// контейнера). Сегодня это безразлично: единственный
// потребитель — тесты. Но если hit-testing (walk_widgets/
// widget_at) когда-нибудь заменит текущий handle_event-based
// путь в dispatch_event_with_app, это станет аллокацией на
// каждое событие на каждый уровень дерева — тогда стоит
// подумать про итератор/callback без аллокации.
pub interface HasChildren {
	child_widgets() []&Widget
}

// Arrangeable — контейнер, раздающий детям bounds в фазе arrange
// (PROJECT.md, «Фаза arrange»). arrange() выставляет bounds ровно тем
// детям, которых потом нарисует draw(), и спускается в них через
// arrange_child/arrange_widget. draw() контейнера bounds детям больше
// НЕ выставляет — только рисует. Лист (не контейнер) arrange не нужен.
pub interface Arrangeable {
mut:
	arrange(mut ctx RenderContext)
}

// arrange_widget — точка входа рекурсии: у не-Arrangeable виджета ничего
// не делает. Глубина ограничена widget_tree_max_depth, как у walk_widgets.
pub fn arrange_widget(mut w Widget, mut ctx RenderContext) {
	if ctx.arrange_depth >= widget_tree_max_depth {
		return
	}
	// шрифт и отступы из CSS - те же, что при измерении и отрисовке (css_apply.v)
	// (адрес и метки - до сужения типа, `if mut w is` сужает w)
	if ctx.css_layout_active() {
		addr := widget_object_addr(&w)
		tags := css_tags_of(&w)
		if mut w is Arrangeable {
			saved := ctx.css_enter_layout(addr, tags)
			ctx.arrange_depth++
			w.arrange(mut ctx)
			ctx.arrange_depth--
			ctx.css_leave_layout(saved)
		}
		return
	}
	if mut w is Arrangeable {
		ctx.arrange_depth++
		w.arrange(mut ctx)
		ctx.arrange_depth--
	}
}

// arrange_child выставляет ребёнку bounds и раскладывает его поддерево.
// Прямоугольник уменьшается на margin ребёнка из CSS (place_child).
fn arrange_child(mut w Widget, r Rect, mut ctx RenderContext) {
	place_child(mut w, r, ctx)
	arrange_widget(mut w, mut ctx)
}

// HitTestable — опциональное сужение HasChildren для hit-testing
// (widget_at). У части контейнеров child_widgets() отдаёт ВСЕХ
// детей (нужно для инспекции/обхода), но bounds выставляется
// в arrange() не всем: TabBox раздаёт bounds только активной вкладке
// (у неактивных остаются УСТАРЕВШИЕ bounds с момента, когда они
// были активны), Accordion — только развёрнутым секциям, ListBox
// — только строкам в текущем видимом диапазоне скролла. Если
// widget_at пойдёт по child_widgets() таких контейнеров, он может
// попасть в чужой устаревший Rect (пример: открыть вкладку 1,
// переключиться на вкладку 0, кликнуть — клик уйдёт в виджет
// вкладки 1). widget_at использует hit_children(), если тип его
// реализует, иначе падает обратно на child_widgets().
pub interface HitTestable {
	hit_children() []&Widget
}

// HasVisibility — поле-интерфейс (не метод): любой Widget-тип,
// у которого есть ТОП-УРОВНЕВОЕ поле `visible bool` (таких
// большинство — см. PROJECT.md), автоматически ему удовлетворяет
// без единой лишней строчки кода — V сопоставляет интерфейсы с
// полями структур напрямую, не только с методами. widget_at
// использует его, чтобы не попадать в скрытые виджеты
// (handle_event их и так не получает — см. например
// ListBox.handle_event, `if !lb.visible { return false }`).
//
// ИЗВЕСТНОЕ ИСКЛЮЧЕНИЕ: HBox/VBox не имеют собственного поля
// `visible` — их флаг лежит на уровень глубже, в `box.visible`
// (общем движке BoxLayout), поэтому они НЕ удовлетворяют этому
// интерфейсу и требуют явной проверки в widget_at (см. там же).
// Panel/Stack/Spacer/ScrollBox/WindowTitleDrag от этой проблемы
// не страдают — у каждого из них есть собственное топ-уровневое
// поле `visible` (у WindowTitleDrag оно отдельное от вложенного
// `box.visible`; `box.draw_impl`/`event_impl` его читают, но нигде
// в репозитории — ни в V, ни в capi, ни в Python — нет кода, который
// его ПРИСВАИВАЕТ: у HBox/VBox нет `set_visible`, поэтому скрыть бокс
// через публичный API сегодня нельзя, и явная проверка здесь — защита
// на будущее). Если появится
// ещё один тип-обёртка над BoxLayout (или другим вложенным полем)
// без собственного `visible` — он попадёт в ту же ловушку молча;
// единственная защита — чек-лист «Добавление нового виджета» в
// PROJECT.md и тест на скрытый контейнер в widget_tree_test.v.
pub interface HasVisibility {
	visible bool
}

// ─── Layouted: bounds_of / set_bounds ──────────────────
// Ниже идут однотипные пары bounds_of/set_bounds: bounds_of отдаёт сохранённый
// Rect виджета, set_bounds кладёт новый (его вызывает arrange_child после
// того, как контейнер рассчитал место для ребёнка). Отдельно комментируются
// только типы с побочным эффектом в set_bounds (Label, MarkdownView) и
// обёртки над BoxLayout (HBox/VBox/WindowTitleDrag — bounds лежит в w.box).
// Порядок и состав — как в бывших get_widget_bounds/
// set_widget_bounds (списки были сверены и совпадали 1:1).

pub fn (w &HBox) bounds_of() Rect {
	return w.box.bounds
}

pub fn (mut w HBox) set_bounds(r Rect) {
	w.box.bounds = r
}

pub fn (w &VBox) bounds_of() Rect {
	return w.box.bounds
}

pub fn (mut w VBox) set_bounds(r Rect) {
	w.box.bounds = r
}

pub fn (w &Panel) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Panel) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Stack) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Stack) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Spacer) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Spacer) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Centered) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Centered) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ScrollBox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ScrollBox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Button) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Button) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Label) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Label) set_bounds(r Rect) {
	// Метка с переносом: высота зависит от ширины (Label.measure) -
	// ширина сменилась, раскладку надо пройти ещё раз (Window.arrange)
	if w.wrap && abs_f32(w.bounds.w - r.w) > 0.5 {
		g_relayout = true
	}
	w.bounds = r
}

// g_relayout - в проходе arrange сменилась ширина метки с переносом:
// Window.arrange проходит раскладку ещё раз с новыми высотами
__global g_relayout = false

pub fn (w &TextInput) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w TextInput) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ListBox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ListBox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ComboBox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ComboBox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &CheckBox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w CheckBox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &RadioButton) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w RadioButton) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ToggleSwitch) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ToggleSwitch) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &TabBox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w TabBox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &MenuBar) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w MenuBar) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ContextMenu) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ContextMenu) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Splitter) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Splitter) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Separator) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Separator) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &TreeView) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w TreeView) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &WindowTitleDrag) bounds_of() Rect {
	return w.box.bounds
}

pub fn (mut w WindowTitleDrag) set_bounds(r Rect) {
	w.box.bounds = r
}

pub fn (w &Spinner) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Spinner) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Tooltip) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Tooltip) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &CodeEditor) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w CodeEditor) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Slider) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Slider) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ProgressBar) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ProgressBar) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ImageView) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ImageView) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &MenuButton) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w MenuButton) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ColorPicker) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ColorPicker) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &DatePicker) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w DatePicker) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &CpArea) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w CpArea) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &DpArea) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w DpArea) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Accordion) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Accordion) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &TableView) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w TableView) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &PlotView) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w PlotView) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Spinbox) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Spinbox) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &PropertyGrid) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w PropertyGrid) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Breadcrumbs) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Breadcrumbs) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &MarkdownView) bounds_of() Rect {
	return w.bounds
}

// MarkdownView помимо bounds обязан выставить dirty — это
// сохранённая особенность из старого set_widget_bounds,
// заставляющая перерисовать (перевёрстать) содержимое при
// изменении размера.
pub fn (mut w MarkdownView) set_bounds(r Rect) {
	w.bounds = r
	w.dirty = true
}

pub fn (w &ShortcutInput) bounds_of() Rect {
	return w.bounds
}

// ShortcutInput: внутренняя кнопка получает те же bounds (рисует и ловит щелчки она).
pub fn (mut w ShortcutInput) set_bounds(r Rect) {
	w.bounds = r
	if w.btn != unsafe { nil } {
		w.btn.bounds = r
	}
}

pub fn (w &NotificationManager) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w NotificationManager) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &TextArea) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w TextArea) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Badge) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Badge) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Calendar) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Calendar) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &GridLayout) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w GridLayout) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &DropZone) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w DropZone) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &ImageBackground) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w ImageBackground) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Canvas) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Canvas) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Icon) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Icon) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &CurveEditor) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w CurveEditor) set_bounds(r Rect) {
	w.bounds = r
}

pub fn (w &Notification) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w Notification) set_bounds(r Rect) {
	w.bounds = r
}

// CpPreview (color_picker.v) — унаследованный пропуск из старого
// ручного switch (он тоже его не знал): без этой пары превью
// "Old/New" в диалоге выбора цвета рисуется в Rect{0,0,0,0} и
// невидимо, потому что btn_row.add(preview) кладёт его
// в HBox, а HBox выставляет bounds только через set_widget_bounds.
pub fn (w &CpPreview) bounds_of() Rect {
	return w.bounds
}

pub fn (mut w CpPreview) set_bounds(r Rect) {
	w.bounds = r
}

// ─── HasChildren: child_widgets ────────────────────────
// HBox/VBox/WindowTitleDrag держат детей в box.children (записи с полем
// widget); Panel/Centered — один child; Stack/ScrollBox — срез children;
// Splitter — first/second; TabBox — widget каждой вкладки; Accordion —
// widget секций; GridLayout — widget ячеек; ListBox — widget ячеек строк.
// Во всех случаях возвращается новый срез, nil-дети пропускаются там, где
// они допустимы (Panel/Centered/Splitter/Accordion/ListBox).
// Только реальные контейнеры, держащие детей-Widget (не
// MenuItem/TreeNode/Property — те не Widget, а отдельные
// типы, принадлежащие своему владельцу, не слою раскладки).

pub fn (w &HBox) child_widgets() []&Widget {
	mut out := []&Widget{cap: w.box.children.len}
	for c in w.box.children {
		out << c.widget
	}
	return out
}

pub fn (w &VBox) child_widgets() []&Widget {
	mut out := []&Widget{cap: w.box.children.len}
	for c in w.box.children {
		out << c.widget
	}
	return out
}

pub fn (w &WindowTitleDrag) child_widgets() []&Widget {
	mut out := []&Widget{cap: w.box.children.len}
	for c in w.box.children {
		out << c.widget
	}
	return out
}

pub fn (w &Panel) child_widgets() []&Widget {
	if unsafe { w.child == nil } {
		return []&Widget{}
	}
	return [w.child]
}

pub fn (w &Centered) child_widgets() []&Widget {
	if unsafe { w.child == nil } {
		return []&Widget{}
	}
	return [w.child]
}

pub fn (w &Stack) child_widgets() []&Widget {
	return w.children.clone()
}

pub fn (w &ScrollBox) child_widgets() []&Widget {
	return w.children.clone()
}

pub fn (w &Splitter) child_widgets() []&Widget {
	mut out := []&Widget{}
	if unsafe { w.first != nil } {
		out << w.first
	}
	if unsafe { w.second != nil } {
		out << w.second
	}
	return out
}

pub fn (w &TabBox) child_widgets() []&Widget {
	mut out := []&Widget{cap: w.tabs.len}
	for t in w.tabs {
		out << t.widget
	}
	return out
}

pub fn (w &Accordion) child_widgets() []&Widget {
	mut out := []&Widget{}
	for s in w.sections {
		if unsafe { s.widget != nil } {
			out << s.widget
		}
	}
	return out
}

pub fn (w &GridLayout) child_widgets() []&Widget {
	mut out := []&Widget{cap: w.cells.len}
	for c in w.cells {
		out << c.widget
	}
	return out
}

pub fn (w &ListBox) child_widgets() []&Widget {
	mut out := []&Widget{}
	for row in w.rows {
		for cell in row.cells {
			if unsafe { cell.widget != nil } {
				out << cell.widget
			}
		}
	}
	return out
}

// ─── HitTestable: только реально «живые» для клика дети ─

// TabBox: кликабельна только активная вкладка — bounds неактивных устарели.

pub fn (w &TabBox) hit_children() []&Widget {
	if w.active >= 0 && w.active < w.tabs.len {
		return [w.tabs[w.active].widget]
	}
	return []&Widget{}
}

// Только развёрнутые секции — ориентируется на предикат, которым
// Accordion.handle_event реально решает, кому из детей отдать
// событие (accordion.v:455, `sec.expanded && sec.anim > 0.5`).
// Здесь только `expanded` (без `anim > 0.5`) — упрощение: пока
// секция сворачивается/разворачивается (0 < anim <= 0.5), окно
// в несколько кадров, где hit_children() покажет её кликабельной
// на долю секунды раньше/позже, чем реально начинает получать
// события handle_event. Не то же самое, что draw() — там условие
// вообще другое (viewport/анимация высоты), поэтому ссылка теперь
// на handle_event, а не на draw().
pub fn (w &Accordion) hit_children() []&Widget {
	mut out := []&Widget{}
	for s in w.sections {
		if s.expanded && unsafe { s.widget != nil } {
			out << s.widget
		}
	}
	return out
}

// ListBox использует те же visible_row_range_v/_h + row_visible_v/_h,
// что draw() и arrange() (list_box.v) — единый источник правды
// для "какие строки реально на экране прямо сейчас", вместо третьей
// копии тех же формул. Диапазон first..last, который отдают
// visible_row_range_*, — консервативный супернабор (последний индекс
// может оказаться уже за пределами vp из-за "+1" на частично видимую
// строку), поэтому каждый индекс дополнительно фильтруется через
// row_visible_v/_h — тем самым воспроизводится ровно то же множество
// строк, которому draw() в этом кадре проставляет bounds.
pub fn (w &ListBox) hit_children() []&Widget {
	mut out := []&Widget{}
	vp := w.viewport_rect()
	if w.horizontal {
		iw := w.eff_item_width()
		first, last := w.visible_row_range_h(vp, iw)
		for i := first; i <= last; i++ {
			if i < 0 || i >= w.rows.len || w.rows[i].cells.len == 0 {
				continue
			}
			if !w.row_visible_h(i, vp, iw) {
				continue
			}
			cell := w.rows[i].cells[0]
			if unsafe { cell.widget != nil } {
				out << cell.widget
			}
		}
		return out
	}
	if w.columns.len == 0 {
		return out
	}
	// item_height <= 0 is handled by visible_row_range_v itself (returns
	// an empty range), so the check doesn't need duplicating here.
	first, last := w.visible_row_range_v(vp)
	for i := first; i <= last; i++ {
		if i < 0 || i >= w.rows.len {
			continue
		}
		if !w.row_visible_v(i, vp) {
			continue
		}
		// Внутри строки — только ячейки, реально видимые по горизонтали
		// (тот же фильтр `cx + col_w > vp.x && cx < vp.x + vp.w`, что
		// ListBox.draw() применяет в своей многоколоночной ветке), а не
		// все ячейки строки.
		mut cx := vp.x - w.scroll_x
		for ci in 0 .. min_int(w.rows[i].cells.len, w.columns.len) {
			col_w := if ci < w.columns.len { w.columns[ci].width } else { f32(0) }
			if cx + col_w > vp.x && cx < vp.x + vp.w {
				cell := w.rows[i].cells[ci]
				if unsafe { cell.widget != nil } {
					out << cell.widget
				}
			}
			cx += col_w
		}
	}
	return out
}

// ─── Обход дерева ───────────────────────────────────────

// Потолок глубины для walk_widgets/widget_at — защита от
// переполнения стека, если контейнер по ошибке (или зловредно)
// содержит сам себя где-то в поддереве (A→B→A). При достижении
// потолка обход этой ветки просто останавливается — cb для уже
// пройденных узлов был вызван, для узлов глубже потолка не будет
// (для widget_at это значит, что настолько глубоко вложенная
// точка не даст попадания глубже потолка — тот же исход, что и у
// листового виджета).
const widget_tree_max_depth = 256

// walk_widgets обходит дерево виджетов в pre-order (сначала
// сам виджет, потом его дети слева направо/снизу вверх по
// z-порядку) и вызывает cb для каждого. Контейнеры, не
// реализующие HasChildren, — листья обхода.
//
// V-only API: у него нет ни capi-биндинга, ни вызывающих из
// Python; сейчас это не используется даже внутри самой vgui
// (hit-testing по-прежнему идёт через handle_event каждого
// контейнера) — инфраструктура готова, потребителей пока нет.
pub fn walk_widgets(w &Widget, cb fn (&Widget)) {
	walk_widgets_impl(w, cb, 0)
}

// walk_widgets_impl — рекурсия walk_widgets: cb вызывается до спуска в детей
// (pre-order), на глубине widget_tree_max_depth ветка обрывается.
fn walk_widgets_impl(w &Widget, cb fn (&Widget), depth int) {
	cb(w)
	if depth >= widget_tree_max_depth {
		return
	}
	if w is HasChildren {
		for c in w.child_widgets() {
			if unsafe { c == nil } {
				continue
			}
			walk_widgets_impl(c, cb, depth + 1)
		}
	}
}

// widget_is_visible — «виджет сейчас нарисован и должен ловить курсор».
// Вынесено из widget_at_impl, потому что тем же правилом пользуется
// Window.hover_target (sdl3_window.v): widget_at проверяет видимость только
// ДЕТЕЙ, а корень поддерева — забота вызывающего.
// HBox/VBox — исключение из HasVisibility (см. коммент у интерфейса): их флаг
// видимости лежит в box.visible, не в топ-уровневом поле, поэтому
// field-интерфейс их не ловит.
pub fn widget_is_visible(w &Widget) bool {
	if w is HasVisibility {
		return w.visible
	}
	if w is HBox {
		return w.box.visible
	}
	if w is VBox {
		return w.box.visible
	}
	return true
}

// widget_at ищет самый глубокий виджет, чей bounds содержит
// точку (x, y) — hit-testing для попадания курсора. Среди
// пересекающихся детей выигрывает последний (верхний по
// z-порядку, как в порядке отрисовки/событий у контейнеров).
// Спускается только через детей, реально участвующих в текущем
// кадре: если тип реализует HitTestable — через hit_children(),
// иначе — через весь child_widgets() (для большинства
// контейнеров это одно и то же множество). Пропускает детей
// с visible == false (там, где есть это поле) и с нулевым
// bounds (w <= 0 или h <= 0) — оба признака «сейчас не
// нарисован и не должен ловить клик».
// Возвращает none, если точка не попадает даже в bounds
// самого w.
//
// V-only API (в capi и Python не проброшен). Единственный
// потребитель — Window.hover_target (sdl3_window.v): по нему
// решается, какие прямоугольники перерисовать на mouse_move
// (аудит 3.C). Доставку самих событий он по-прежнему не делает
// — этим занимается handle_event каждого контейнера, — поэтому
// расхождение между этим обходом и реальным hit-testing'ом
// стоит не ошибочного клика, а лишь лишней/недостающей
// перерисовки прямоугольника.
pub fn widget_at(w &Widget, x f32, y f32) ?&Widget {
	mut tip := TipHit{}
	return widget_at_impl(w, x, y, 0, mut tip)
}

// TipHit — результат widget_tip_at. hit — то же, что вернул бы widget_at
// (nil — точка мимо). owner — ближайший к hit виджет с непустым полем
// tooltip: сам hit или его предок на пути от корня. Так подсказку можно
// повесить и на весь ряд (HBox с подписью и ползунком), а не только на
// лист. owner == nil — подсказки нет, text — её текст.
pub struct TipHit {
pub mut:
	hit   &Widget = unsafe { nil }
	owner &Widget = unsafe { nil }
	text  string
}

// widget_tip_at — виджет под точкой (как widget_at) и подсказка для неё за
// один обход дерева. Используется окном (Window.hit_at, tooltip_manager.v).
pub fn widget_tip_at(w &Widget, x f32, y f32) TipHit {
	mut tip := TipHit{}
	if found := widget_at_impl(w, x, y, 0, mut tip) {
		tip.hit = unsafe { found }
	}
	return tip
}

// widget_at_impl — рекурсивная часть widget_at; depth защищает от циклов
// (см. widget_tree_max_depth). tip заполняется на обратном ходе рекурсии:
// самый глубокий кадр завершается первым, поэтому владельцем подсказки
// становится ближайший к найденному виджету носитель непустого tooltip.
fn widget_at_impl(w &Widget, x f32, y f32, depth int, mut tip TipHit) ?&Widget {
	// Нулевой/отрицательный размер = виджет сейчас не нарисован (скрыт,
	// вне видимой области, ещё не раскладывался) — клик ловить не должен.
	b := get_widget_bounds(w)
	if b.w <= 0 || b.h <= 0 {
		return none
	}
	if !b.contains(x, y) {
		return none
	}
	// своя «рамка» контейнера поверх детей (полоса прокрутки, зона
	// разделителя) - точка его, в детей не спускаемся (event_route.v)
	if widget_hits_self(w, x, y) {
		take_tip(mut tip, w)
		return unsafe { w }
	}
	if depth < widget_tree_max_depth {
		children := if w is HitTestable {
			w.hit_children()
		} else if w is HasChildren {
			w.child_widgets()
		} else {
			[]&Widget{}
		}
		// Идём с конца: последний ребёнок рисуется поверх остальных (z-порядок),
		// поэтому при перекрытии побеждает он.
		for i := children.len - 1; i >= 0; i-- {
			c := children[i]
			if unsafe { c == nil } {
				continue
			}
			if !widget_is_visible(c) {
				continue
			}
			if found := widget_at_impl(c, x, y, depth + 1, mut tip) {
				take_tip(mut tip, w)
				return found
			}
		}
	}
	// Ни один ребёнок не попал. «Прозрачный» виджет (см. hit_passes_through)
	// курсор не ловит: точка уходит виджету, лежащему под ним.
	if hit_passes_through(w, x, y) {
		return none
	}
	take_tip(mut tip, w)
	return unsafe { w }
}

// widget_path_at — путь от w до самого глубокого виджета под точкой (x, y):
// path[0] == w, последний элемент — то, что вернул бы widget_at. Пусто —
// точка мимо. Правила спуска те же, что у widget_at (видимость, нулевые
// bounds, HitTestable, прозрачные слои). Нужен, когда важен не только лист,
// но и его предки: перетаскивание (dnd.v) ищет ближайшего к курсору
// источника или цель среди них и проверяет, не отключён ли предок.
pub fn widget_path_at(w &Widget, x f32, y f32) []&Widget {
	mut path := []&Widget{}
	widget_path_impl(w, x, y, 0, mut path)
	return path.reverse()
}

// widget_path_impl — рекурсия widget_path_at. Путь собирается на обратном
// ходе (сначала лист, потом предки), поэтому вызывающий его переворачивает.
// true — точка попала в w или его потомка.
fn widget_path_impl(w &Widget, x f32, y f32, depth int, mut path []&Widget) bool {
	b := get_widget_bounds(w)
	if b.w <= 0 || b.h <= 0 || !b.contains(x, y) {
		return false
	}
	// своя «рамка» контейнера - как в widget_at_impl
	if widget_hits_self(w, x, y) {
		path << unsafe { w }
		return true
	}
	if depth < widget_tree_max_depth {
		children := if w is HitTestable {
			w.hit_children()
		} else if w is HasChildren {
			w.child_widgets()
		} else {
			[]&Widget{}
		}
		// С конца: верхний по z-порядку ребёнок побеждает (как в widget_at_impl)
		for i := children.len - 1; i >= 0; i-- {
			c := children[i]
			if unsafe { c == nil } || !widget_is_visible(c) {
				continue
			}
			if widget_path_impl(c, x, y, depth + 1, mut path) {
				path << unsafe { w }
				return true
			}
		}
	}
	if hit_passes_through(w, x, y) {
		return false
	}
	path << unsafe { w }
	return true
}

// take_tip делает w владельцем подсказки, если её ещё нет, а у w есть текст.
fn take_tip(mut tip TipHit, w &Widget) {
	if unsafe { tip.owner != nil } {
		return
	}
	text := widget_tooltip(w)
	if text.len > 0 {
		tip.owner = unsafe { w }
		tip.text = text
	}
}

// hit_passes_through — виджет не ловит курсор в точке (x, y), хотя его
// bounds её содержат. Window.arrange раздаёт ВСЕМ верхнеуровневым виджетам
// окна прямоугольник всего экрана, а часть из них — не видимое содержимое,
// а служебные слои поверх дерева: без этой проверки hover_target и поиск
// подсказки упирались бы в них и до интерфейса под ними не доходили.
//   - Tooltip — сам рисуется в отдельном слое, места в раскладке не имеет;
//   - ContextMenu — привязка меню к цели, попап живёт в слоте оверлея;
//   - NotificationManager — прозрачен везде, кроме видимых уведомлений;
//   - Canvas.passive — холст только рисует, события идут виджету под ним.
fn hit_passes_through(w &Widget, x f32, y f32) bool {
	if w is Tooltip || w is ContextMenu {
		return true
	}
	if w is Canvas {
		return w.passive
	}
	if w is NotificationManager {
		for n in w.notifications {
			if n.visible && !n.dismissed && n.bounds.contains(x, y) {
				return false
			}
		}
		return true
	}
	return false
}

// HasTooltip — поле-интерфейс (как HasVisibility/HasEnabled): ему
// удовлетворяет любой тип с полем верхнего уровня `tooltip string`. Поле есть
// у всех виджетов, кроме служебных (Tooltip, ContextMenu, Notification,
// NotificationManager) и не-виджетов (MenuItem, TreeNode, Property);
// полноту проверяет при компиляции tooltip_manager_test.v.
pub interface HasTooltip {
mut:
	tooltip string
}

// widget_tooltip — текст подсказки виджета ("" — нет или тип без поля).
pub fn widget_tooltip(w &Widget) string {
	if w is HasTooltip {
		return w.tooltip
	}
	return ''
}

// set_widget_tooltip задаёт подсказку любому виджету; false — у типа нет
// поля (служебные слои). Кадр не инвалидирует (как и прочие сеттеры): в
// живом цикле новый текст подхватится со следующего кадра.
pub fn set_widget_tooltip(mut w Widget, text string) bool {
	if mut w is HasTooltip {
		w.tooltip = text
		return true
	}
	return false
}

// HasWheel - виджет, который берёт колесо мыши (прокрутка, смена
// значения): поле-интерфейс, как HasVisibility. wheel = false - колесо
// уходит дальше, контейнеру (панель в ScrollBox прокручивается, даже
// когда курсор на ползунке).
pub interface HasWheel {
mut:
	wheel bool
}

// set_widget_wheel - включить/выключить колесо у виджета; false - у
// виджета колеса нет (кнопка, метка...)
pub fn set_widget_wheel(mut w Widget, on bool) bool {
	if mut w is HasWheel {
		w.wheel = on
		return true
	}
	return false
}
