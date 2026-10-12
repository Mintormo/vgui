module vgui

// ═══════════════════════════════════════════════════════
// ListBox — multi-column scrollable list with header,
// optional sort buttons, widget-based rows, keyboard
// navigation, and draggable scrollbar
//
// Backward-compatible: single-column text mode works
// exactly as before when no columns are defined.
//
// Multi-column mode: define columns with add_column(),
// then add rows with add_row_texts() or add_row_widgets().
// Each row is a container whose cells can hold any Widget.
//
// Структура файла (по-русски, для ориентации):
//   * данные: columns (LbColumn), rows (LbRow -> []LbCell), плюс items - зеркало текста первой
//     колонки для старого однострочного API (add_item/get_selected_text и т.п.). rows и items
//     обязаны оставаться одной длины (add_*/clear/set_row_cell_text поддерживают это);
//   * три режима: однострочный текстовый список (columns пуст), таблица с колонками и
//     ячейками-виджетами, горизонтальная «плёнка» (horizontal) - каждая строка это один элемент
//     шириной item_width, виджет лежит в cells[0];
//   * выбор: selected (текущая строка) + необязательный множественный выбор (sel_marks);
//   * прокрутка: scroll_y/scroll_x и две полосы с перетаскиванием; в режиме колонок по ширине
//     прокручивается сумма ширин колонок;
//   * заголовок: сортировка (только сигнал on_sort, сами строки ListBox не переставляет!) и
//     изменение ширины колонок перетаскиванием границы;
//   * раскладка/отрисовка: measure() - layout_measure.v (константный scrollable_hint); виджетам
//     в ячейках bounds раздаёт arrange() (только для видимых строк), draw() их лишь рисует;
//     hit_children - widget_tree.v; фокус - focus.v (register_list_box/focus_list_box);
//   * события: handle_event (ниже) - единый обработчик с приоритетом активных перетаскиваний.
//
// Header is always read-only. Sort buttons are optional
// Header is always read-only. Sort buttons are optional
// per-column (show_sort flag). Clicking sort fires on_sort.
// ═══════════════════════════════════════════════════════

// Направление сортировки колонки: none_ (не сортируется, имя с подчёркиванием - none зарезервировано), по возрастанию, по убыванию.
pub enum LbSortDir {
	none_
	asc
	desc
}

// Колонка: title - заголовок; width - текущая ширина (меняется перетаскиванием границы, не меньше min_w);
// show_sort - рисовать кнопку сортировки; sort_dir - текущее направление; align - выравнивание текста ячеек.
pub struct LbColumn {
pub mut:
	title     string
	width     f32
	min_w     f32 = 30
	show_sort bool
	sort_dir  LbSortDir = .none_
	align     TextAlign = .left
}

// Ячейка строки: либо text, либо widget (виджет имеет приоритет; ListBox его не владеет - ссылку должен держать вызывающий код).
struct LbCell {
mut:
	text   string // used in text-only mode
	widget &Widget = unsafe { nil } // custom widget (overrides text)
}

// Строка: cells по колонкам; text - зеркало текста первой колонки (старый API); user_data - произвольный указатель пользователя.
struct LbRow {
mut:
	cells     []LbCell
	text      string // legacy single-column text
	user_data voidptr = unsafe { nil }
}

// Размеры по умолчанию: толщина полосы прокрутки, высота шапки, ширина кнопки сортировки, внутренний
// отступ ячейки, прозрачность линий сетки между строками/колонками, зона захвата границы колонки
// (± px от границы), ширина элемента в горизонтальном режиме.
const lb_sb_w_default = f32(8)
const lb_header_h = f32(26)
const lb_sort_btn_w = f32(16)
const lb_cell_pad = f32(6)
const lb_grid_color_a = u8(40)
const lb_resize_zone = f32(5)
const lb_item_width_default = f32(120)

// ListBox - список / таблица (см. шапку файла). Публичные поля - состояние и колбэки:
// on_select(индекс, текст первой колонки) - при выборе; on_dbl_click(индекс, текст) - двойной клик
// или Enter; on_sort(колонка, новое направление). Сеттеры кадр не инвалидируют.
@[heap]
pub struct ListBox {
pub mut:
	type_tag int = kind_list_box // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel   bool = true
	bounds  Rect
	columns []LbColumn
	rows    []LbRow
	// Legacy single-column compat
	items       []string
	selected    int = -1
	scroll_y    f32
	item_height f32  = 24
	pad         f32  = 4
	visible     bool = true
	enabled     bool = true
	focused     bool
	hovered     bool
	hover_index int = -1
	// // Анимация кольца фокуса (Anim, anim.v) - шагается в draw().
	focus_anim   Anim = anim_smooth(anim_tau_focus)
	focus_group  int
	scroll_speed f32              = 30
	on_select    fn (int, string) = unsafe { nil }
	on_dbl_click fn (int, string) = unsafe { nil }
	// Called first for key_down while the list is focused; return true to
	// consume the event (lets apps bind e.g. Ctrl+Up/Down before built-ins).
	on_key_down fn (&GuiEvent) bool = unsafe { nil }
	// Множественный выбор: Ctrl+щелчок добавляет/убирает строку,
	// Shift+щелчок и Shift+стрелки выделяют диапазон от якоря (последней
	// строки, выбранной без Shift). selected остаётся текущей строкой
	// (курсором, on_select, Enter), выбранные - get_selection().
	multi_select bool
	// Horizontal (filmstrip) mode
	horizontal bool
	item_width f32 = lb_item_width_default
	// Multi-column additions
	show_header   bool
	header_height f32                 = lb_header_h
	on_sort       fn (int, LbSortDir) = unsafe { nil } // (col_index, new_dir)
	show_grid     bool // draw vertical grid lines between columns
	// Horizontal scroll for wide content
	scroll_x       f32
	scroll_x_speed f32 = 30
	// ── Scrollbar customization ──
	// Необязательные переопределения вида полос прокрутки: 0 / -1 / прозрачный цвет = взять значение по умолчанию
	// или из темы (см. eff_sb_* ниже).
	sb_width             f32
	sb_radius            f32 = -1
	sb_min_thumb         f32
	sb_track_color       Color = Color{0, 0, 0, 0}
	sb_thumb_color       Color = Color{0, 0, 0, 0}
	sb_thumb_hover_color Color = Color{0, 0, 0, 0}
	sb_thumb_drag_color  Color = Color{0, 0, 0, 0}
	// ── Internal ──
	// Внутреннее состояние перетаскивания и наведения (в публичном API не используется). drag_start_* - позиция
	// мыши и прокрутка в момент нажатия: смещение вычисляется от них, а не накапливается.
	sb_dragging           bool
	sb_hovered            bool
	sb_drag_start_y       f32
	sb_drag_start_scroll  f32
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
	// Column resize drag
	col_resizing     bool
	resize_col       int = -1
	resize_start_x   f32
	resize_start_w   f32
	resize_hover_col int = -1 // column border being hovered for resize cursor	
	// Header sort hover
	sort_hover_col int = -1
	// Множественный выбор (multi_select): sel_multi - выбор задан
	// sel_marks (иначе выбрана одна строка selected), sel_anchor - начало
	// диапазона для Shift
	sel_multi  bool
	sel_marks  []int
	sel_anchor int = -1
}

// ─── Constructors ──────────────────────────────────────

// list_box - пустой вертикальный список (однострочный режим, пока не добавлены колонки).
pub fn list_box() &ListBox {
	return &ListBox{}
}

// list_box_h - горизонтальный список-«плёнка»: каждый элемент шириной item_width (<= 0 - ширина по умолчанию).
pub fn list_box_h(item_width f32) &ListBox {
	return &ListBox{
		horizontal: true
		item_width: if item_width > 0 { item_width } else { lb_item_width_default }
	}
}

pub fn (mut lb ListBox) set_item_width(w f32) {
	lb.item_width = max_f32(w, 10)
}

// ─── Column management ─────────────────────────────────

// add_column и add_column_* - добавляют колонку, включают заголовок (show_header) и дополняют уже
// существующие строки пустыми ячейками, чтобы у каждой строки cells.len >= columns.len. Ширина
// зажимается не меньше min_w (min_w >= 10). Варианты отличаются набором параметров:
// sortable - кнопка сортировки, align - выравнивание текста.
pub fn (mut lb ListBox) add_column(title string, width f32) {
	lb.columns << LbColumn{
		title: title
		width: max_f32(width, 30)
	}
	lb.show_header = true
	// Pad existing rows with empty cells
	for i in 0 .. lb.rows.len {
		for lb.rows[i].cells.len < lb.columns.len {
			lb.rows[i].cells << LbCell{}
		}
	}
}

pub fn (mut lb ListBox) add_column_sortable(title string, width f32) {
	lb.columns << LbColumn{
		title:     title
		width:     max_f32(width, 30)
		show_sort: true
	}
	lb.show_header = true
	for i in 0 .. lb.rows.len {
		for lb.rows[i].cells.len < lb.columns.len {
			lb.rows[i].cells << LbCell{}
		}
	}
}

pub fn (mut lb ListBox) add_column_full(title string, width f32, min_w f32, sortable bool, align TextAlign) {
	lb.columns << LbColumn{
		title:     title
		width:     max_f32(width, min_w)
		min_w:     max_f32(min_w, 10)
		show_sort: sortable
		align:     align
	}
	lb.show_header = true
	for i in 0 .. lb.rows.len {
		for lb.rows[i].cells.len < lb.columns.len {
			lb.rows[i].cells << LbCell{}
		}
	}
}

// Set minimum width for a column
pub fn (mut lb ListBox) set_column_min_width(col int, min_w f32) {
	if col >= 0 && col < lb.columns.len {
		lb.columns[col].min_w = max_f32(min_w, 10)
		if lb.columns[col].width < lb.columns[col].min_w {
			lb.columns[col].width = lb.columns[col].min_w
		}
	}
}

// Get minimum width of a column
pub fn (lb &ListBox) get_column_min_width(col int) f32 {
	if col >= 0 && col < lb.columns.len {
		return lb.columns[col].min_w
	}
	return 30
}

// Set column width (clamped to min_w)
pub fn (mut lb ListBox) set_column_width(col int, w f32) {
	if col >= 0 && col < lb.columns.len {
		lb.columns[col].width = max_f32(w, lb.columns[col].min_w)
	}
}

// Get column width
pub fn (lb &ListBox) get_column_width(col int) f32 {
	if col >= 0 && col < lb.columns.len {
		return lb.columns[col].width
	}
	return 0
}

// Add column with explicit minimum width
pub fn (mut lb ListBox) add_column_with_min(title string, width f32, min_w f32) {
	lb.columns << LbColumn{
		title: title
		width: max_f32(width, min_w)
		min_w: max_f32(min_w, 10)
	}
	lb.show_header = true
	for i in 0 .. lb.rows.len {
		for lb.rows[i].cells.len < lb.columns.len {
			lb.rows[i].cells << LbCell{}
		}
	}
}

// Resizable column: sortable with explicit min width
pub fn (mut lb ListBox) add_column_resizable(title string, width f32, min_w f32, sortable bool) {
	lb.columns << LbColumn{
		title:     title
		width:     max_f32(width, min_w)
		min_w:     max_f32(min_w, 10)
		show_sort: sortable
	}
	lb.show_header = true
	for i in 0 .. lb.rows.len {
		for lb.rows[i].cells.len < lb.columns.len {
			lb.rows[i].cells << LbCell{}
		}
	}
}

// set_column_sort ставит индикатор сортировки колонке и снимает у остальных (одновременно сортируется одна колонка). Строки не переставляет и on_sort не зовёт.
pub fn (mut lb ListBox) set_column_sort(col int, dir LbSortDir) {
	if col >= 0 && col < lb.columns.len {
		// Clear other columns' sort
		for i in 0 .. lb.columns.len {
			lb.columns[i].sort_dir = .none_
		}
		lb.columns[col].sort_dir = dir
	}
}

// ─── Row management (multi-column) ─────────────────────

// add_row_texts - строка из текстов; недостающие ячейки пустые, лишние (больше колонок) тоже сохраняются. Текст [0] попадает в items/row.text для старого API.
pub fn (mut lb ListBox) add_row_texts(texts []string) {
	mut cells := []LbCell{cap: max_int(lb.columns.len, texts.len)}
	for i in 0 .. max_int(lb.columns.len, texts.len) {
		text := if i < texts.len { texts[i] } else { '' }
		cells << LbCell{
			text: text
		}
	}
	// Legacy compat: first column text → items array
	first_text := if texts.len > 0 { texts[0] } else { '' }
	lb.items << first_text
	lb.rows << LbRow{
		cells: cells
		text:  first_text
	}
}

// add_item_widget adds a single widget as an item (used in horizontal/filmstrip mode)
pub fn (mut lb ListBox) add_item_widget(widget &Widget) {
	lb.items << ''
	lb.rows << LbRow{
		cells: [LbCell{ widget: unsafe { widget } }]
	}
}

// add_row_widgets - строка из виджетов-ячеек (по одному на колонку). Ссылки на виджеты ListBox не удерживает от GC/удаления - это забота вызывающего (в Python - список _children).
pub fn (mut lb ListBox) add_row_widgets(widgets []&Widget) {
	mut cells := []LbCell{cap: max_int(lb.columns.len, widgets.len)}
	for i in 0 .. max_int(lb.columns.len, widgets.len) {
		if i < widgets.len {
			cells << LbCell{
				widget: unsafe { widgets[i] }
			}
		} else {
			cells << LbCell{}
		}
	}
	lb.items << ''
	lb.rows << LbRow{
		cells: cells
	}
}

// set_row_cell_text заменяет ячейку текстом (виджет в ней сбрасывается); для колонки 0 синхронизирует items и row.text.
pub fn (mut lb ListBox) set_row_cell_text(row int, col int, text string) {
	if row >= 0 && row < lb.rows.len && col >= 0 && col < lb.rows[row].cells.len {
		lb.rows[row].cells[col].text = text
		lb.rows[row].cells[col].widget = unsafe { nil }
		if col == 0 {
			lb.rows[row].text = text
			if row < lb.items.len {
				lb.items[row] = text
			}
		}
	}
}

// set_row_cell_widget ставит виджет в ячейку (текст ячейки остаётся, но виджет приоритетнее).
pub fn (mut lb ListBox) set_row_cell_widget(row int, col int, widget &Widget) {
	if row >= 0 && row < lb.rows.len && col >= 0 && col < lb.rows[row].cells.len {
		lb.rows[row].cells[col].widget = unsafe { widget }
	}
}

pub fn (lb &ListBox) get_row_cell_text(row int, col int) string {
	if row >= 0 && row < lb.rows.len && col >= 0 && col < lb.rows[row].cells.len {
		return lb.rows[row].cells[col].text
	}
	return ''
}

pub fn (mut lb ListBox) set_row_data(row int, data voidptr) {
	if row >= 0 && row < lb.rows.len {
		lb.rows[row].user_data = data
	}
}

pub fn (lb &ListBox) get_row_data(row int) voidptr {
	if row >= 0 && row < lb.rows.len {
		return lb.rows[row].user_data
	}
	return unsafe { nil }
}

// ─── Legacy single-column API (fully preserved) ────────

// add_item - старый API: без колонок добавляет однострочную строку, с колонками - строку add_row_texts([text]).
pub fn (mut lb ListBox) add_item(text string) {
	if lb.columns.len == 0 {
		lb.items << text
		lb.rows << LbRow{
			text:  text
			cells: [LbCell{
				text: text
			}]
		}
	} else {
		lb.add_row_texts([text])
	}
}

pub fn (mut lb ListBox) add_items(items []string) {
	for item in items {
		lb.add_item(item)
	}
}

// clear удаляет все строки, сбрасывает выбор, прокрутку и hover; колонки остаются.
pub fn (mut lb ListBox) clear() {
	lb.items.clear()
	lb.rows.clear()
	lb.selected = -1
	lb.scroll_y = 0
	lb.scroll_x = 0
	lb.hover_index = -1
	lb.reset_marks()
}

pub fn (mut lb ListBox) set_items(items []string) {
	lb.clear()
	lb.add_items(items)
}

// set_selected принимает -1 («нет выбора») или индекс существующей строки.
// Остальное игнорируется, как в ComboBox/TabBox/TableView: иначе get_selected()
// возвращал бы мусорный индекс, которого нет в списке.
// Во множественном выборе set_selected оставляет выбранной одну строку.
pub fn (mut lb ListBox) set_selected(idx int) {
	if idx >= -1 && idx < lb.rows.len {
		lb.selected = idx
		lb.reset_marks()
	}
}

// ─── Множественный выбор (multi_select) ────────────────

// is_row_selected - строка подсвечена как выбранная: при множественном
// выборе - одна из get_selection(), иначе - selected.
pub fn (lb &ListBox) is_row_selected(i int) bool {
	if lb.sel_multi {
		return i in lb.sel_marks
	}
	return i >= 0 && i == lb.selected
}

// get_selection - индексы выбранных строк по возрастанию. Без
// множественного выбора - [selected] или пусто.
pub fn (lb &ListBox) get_selection() []int {
	if lb.sel_multi {
		mut s := lb.sel_marks.filter(it < lb.rows.len)
		s.sort()
		return s
	}
	if lb.selected >= 0 && lb.selected < lb.rows.len {
		return [lb.selected]
	}
	return []int{}
}

// set_selection выбирает строки idxs (индексы вне списка и повторы
// пропускаются); текущей строкой становится последняя из них. Без
// multi_select - как set_selected последней строки (пусто - снять выбор).
pub fn (mut lb ListBox) set_selection(idxs []int) {
	mut marks := []int{}
	for i in idxs {
		if i >= 0 && i < lb.rows.len && i !in marks {
			marks << i
		}
	}
	if !lb.multi_select || marks.len <= 1 {
		lb.set_selected(if marks.len > 0 { marks[0] } else { -1 })
		return
	}
	lb.selected = marks.last()
	lb.sel_marks = marks
	lb.sel_multi = true
	lb.sel_anchor = lb.selected
}

// reset_marks - выбор снова одна строка selected, она же якорь
fn (mut lb ListBox) reset_marks() {
	lb.sel_multi = false
	lb.sel_marks = []int{}
	lb.sel_anchor = lb.selected
}

// click_select - щелчок по строке idx: без модификаторов (или без
// multi_select) - одна строка; Ctrl - добавить/убрать; Shift - диапазон
// от якоря (Ctrl+Shift - добавить диапазон к выбранным).
fn (mut lb ListBox) click_select(idx int, event &GuiEvent) {
	ctrl := lb.multi_select && event.ctrl()
	shift := lb.multi_select && event.shift()
	if shift {
		a := if lb.sel_anchor >= 0 && lb.sel_anchor < lb.rows.len {
			lb.sel_anchor
		} else if lb.selected >= 0 {
			lb.selected
		} else {
			idx
		}
		mut marks := if ctrl { lb.get_selection() } else { []int{} }
		for i in min_int(a, idx) .. max_int(a, idx) + 1 {
			if i !in marks {
				marks << i
			}
		}
		lb.selected = idx
		lb.sel_marks = marks
		lb.sel_multi = true
		lb.sel_anchor = a
	} else if ctrl {
		mut marks := lb.get_selection()
		p := marks.index(idx)
		if p >= 0 {
			marks.delete(p)
		} else {
			marks << idx
		}
		lb.selected = idx
		lb.sel_marks = marks
		lb.sel_multi = true
		lb.sel_anchor = idx
	} else {
		lb.selected = idx
		lb.reset_marks()
	}
}

// key_select - после перехода клавишами: Shift (multi_select) - диапазон
// от якоря до новой строки, иначе одна строка.
fn (mut lb ListBox) key_select(event &GuiEvent) {
	if lb.multi_select && event.shift() && lb.sel_anchor >= 0 && lb.sel_anchor < lb.rows.len {
		mut marks := []int{}
		for i in min_int(lb.sel_anchor, lb.selected) .. max_int(lb.sel_anchor, lb.selected) + 1 {
			marks << i
		}
		lb.sel_marks = marks
		lb.sel_multi = true
	} else {
		lb.reset_marks()
	}
}

pub fn (lb &ListBox) get_selected_text() string {
	if lb.selected >= 0 && lb.selected < lb.items.len {
		return lb.items[lb.selected]
	}
	return ''
}

pub fn (lb &ListBox) get_selected_row_text(col int) string {
	return lb.get_row_cell_text(lb.selected, col)
}

pub fn (lb &ListBox) row_count() int {
	return lb.rows.len
}

// ─── Geometry ──────────────────────────────────────────

// is_multi_col - таблица ли это (есть хотя бы одна колонка).
fn (lb &ListBox) is_multi_col() bool {
	return lb.columns.len > 0
}

// eff_header_h - реальная высота шапки: 0, если шапки нет.
fn (lb &ListBox) eff_header_h() f32 {
	if lb.show_header && lb.columns.len > 0 {
		return lb.header_height
	}
	return f32(0)
}

// content_height - полная высота всех строк (для горизонтального режима 0 - вертикальной прокрутки нет).
pub fn (lb &ListBox) content_height() f32 {
	if lb.horizontal {
		return 0
	}
	return f32(lb.rows.len) * lb.item_height
}

// content_width - полная ширина содержимого: горизонтальный режим - все элементы подряд; таблица - сумма ширин колонок; однострочный режим - 0 (текст по ширине окна).
fn (lb &ListBox) content_width() f32 {
	if lb.horizontal {
		return f32(lb.rows.len) * lb.eff_item_width()
	}
	// Single-column legacy mode: text fills viewport, no horizontal scroll
	if lb.columns.len == 0 {
		return 0
	}
	mut w := f32(0)
	for c in lb.columns {
		w += c.width
	}
	return w
}

fn (lb &ListBox) eff_item_width() f32 {
	return if lb.item_width > 0 { lb.item_width } else { lb_item_width_default }
}

// data_origin_y - верхняя граница области данных (под шапкой).
fn (lb &ListBox) data_origin_y() f32 {
	return lb.bounds.y + lb.pad + lb.eff_header_h()
}

// viewport_rect - область, где видны строки: bounds минус pad, шапка и места под видимые полосы прокрутки. От неё считается вся геометрия строк.
fn (lb &ListBox) viewport_rect() Rect {
	ox := lb.bounds.x + lb.pad
	oy := lb.data_origin_y()
	mut w := lb.bounds.w - lb.pad * 2
	mut h := lb.bounds.y + lb.bounds.h - lb.pad - oy
	if lb.has_scrollbar() {
		w -= lb.eff_sb_width()
	}
	if lb.has_hsb() {
		h -= lb.eff_sb_width()
	}
	return Rect{ox, oy, max_f32(w, 0), max_f32(h, 0)}
}

// ─── Visible-row range (shared by draw / event dispatch / hit-testing) ─
//
// The formulas below are the single source of truth for "which rows can
// possibly be on screen right now" in each layout mode. arrange(), draw(),
// dispatch_to_row_widgets[_h]() (this file) and widget_tree.v's
// ListBox.hit_children() all call these two functions instead of each
// hand-rolling its own skip/break arithmetic — the range they return is
// a CONSERVATIVE SUPERSET (the `+1` at the end covers a
// partially-visible trailing row), so callers MUST additionally check
// row_visible_v/row_visible_h for each index — skipping that check is
// what previously let a stale, invisible trailing row leak into
// hit-testing.

// visible_row_range_v returns the conservative [first, last] row-index
// range for non-horizontal mode. Individual indices in this range still
// need row_visible_v() — `last` in particular can be fully off-screen.
fn (lb &ListBox) visible_row_range_v(vp Rect) (int, int) {
	if lb.item_height <= 0 {
		// item_height is a public field; callers normally clamp it to a
		// positive value before it reaches here (ui_builder.v only
		// assigns when `ih > 0`, and vgui_list_box_set_item_height clamps
		// via max_f32(height, 1)), but a bad value here would divide by
		// zero below, so this guard covers direct field assignment from
		// V code that bypasses both of those paths.
		return 0, -1
	}
	first := max_int(0, int(lb.scroll_y / lb.item_height))
	last := min_int(lb.rows.len - 1, int((lb.scroll_y + vp.h) / lb.item_height) + 1)
	return first, last
}

// row_visible_v reports whether row i is actually painted by draw() at
// the current scroll offset — draw()'s vertical-mode loop filters on
// this directly (see below), so this is not just a mirror.
fn (lb &ListBox) row_visible_v(i int, vp Rect) bool {
	iy := vp.y + f32(i) * lb.item_height - lb.scroll_y
	return !(iy + lb.item_height < vp.y || iy > vp.y + vp.h)
}

// visible_row_range_h is the horizontal-mode (filmstrip) counterpart of
// visible_row_range_v. Same caveat: still needs row_visible_h() per index.
fn (lb &ListBox) visible_row_range_h(vp Rect, iw f32) (int, int) {
	first := max_int(0, int(lb.scroll_x / iw))
	last := min_int(lb.rows.len - 1, int((lb.scroll_x + vp.w) / iw) + 1)
	return first, last
}

// row_visible_h reports whether row i is actually painted by draw() in
// horizontal mode at the current scroll offset — draw()'s
// horizontal-mode loop filters on this directly (see below).
fn (lb &ListBox) row_visible_h(i int, vp Rect, iw f32) bool {
	ix := vp.x + f32(i) * iw - lb.scroll_x
	return !(ix + iw < vp.x || ix > vp.x + vp.w)
}

// max_scroll/max_scroll_x - предел прокрутки (на сколько содержимое больше viewport), не меньше 0.
pub fn (lb &ListBox) max_scroll() f32 {
	if lb.horizontal {
		return 0
	}
	vp := lb.viewport_rect()
	return max_f32(0, lb.content_height() - vp.h)
}

fn (lb &ListBox) max_scroll_x() f32 {
	vp := lb.viewport_rect()
	return max_f32(0, lb.content_width() - vp.w)
}

// has_scrollbar/has_hsb - нужны ли полосы. Вертикальная проверяется по высоте без полосы горизонтальной, поэтому в редком случае, когда появление одной полосы вызывает другую, возможно расхождение на пару px. (Обе ветки has_hsb сейчас идентичны.)
fn (lb &ListBox) has_scrollbar() bool {
	if lb.horizontal {
		return false
	}
	h := lb.bounds.h - lb.pad * 2 - lb.eff_header_h()
	return lb.content_height() > h
}

fn (lb &ListBox) has_hsb() bool {
	if lb.horizontal {
		w := lb.bounds.w - lb.pad * 2
		return lb.content_width() > w
	}
	w := lb.bounds.w - lb.pad * 2
	return lb.content_width() > w
}

// ── Effective scrollbar params ──

fn (lb &ListBox) eff_sb_width() f32 {
	return if lb.sb_width > 0 { lb.sb_width } else { lb_sb_w_default }
}

fn (lb &ListBox) eff_sb_radius() f32 {
	return if lb.sb_radius >= 0 { lb.sb_radius } else { f32(3) }
}

fn (lb &ListBox) eff_sb_min_thumb() f32 {
	return if lb.sb_min_thumb > 0 { lb.sb_min_thumb } else { f32(24) }
}

fn (lb &ListBox) eff_sb_track_color(ctx &RenderContext) Color {
	return if lb.sb_track_color.a > 0 { lb.sb_track_color } else { ctx.theme.scrollbar_bg }
}

fn (lb &ListBox) eff_sb_thumb_color(ctx &RenderContext) Color {
	return if lb.sb_thumb_color.a > 0 { lb.sb_thumb_color } else { ctx.theme.scrollbar_thumb }
}

fn (lb &ListBox) eff_sb_thumb_hover(ctx &RenderContext) Color {
	return if lb.sb_thumb_hover_color.a > 0 {
		lb.sb_thumb_hover_color
	} else {
		ctx.theme.scrollbar_hover
	}
}

fn (lb &ListBox) eff_sb_thumb_drag(ctx &RenderContext) Color {
	return if lb.sb_thumb_drag_color.a > 0 {
		lb.sb_thumb_drag_color
	} else {
		ctx.theme.scrollbar_drag
	}
}

// Vertical scrollbar geometry
// scrollbar_rects/hsb_rects - геометрия полос: (дорожка, бегунок). Длина бегунка = доля видимой части
// (не меньше sb_min_thumb), положение - доля прокрутки * свободный ход. Пустые Rect, если полоса не нужна.
fn (lb &ListBox) scrollbar_rects() (Rect, Rect) {
	vp := lb.viewport_rect()
	ch := lb.content_height()
	vis_h := vp.h
	if ch <= vis_h {
		return Rect{}, Rect{}
	}
	sbw := lb.eff_sb_width()
	track := Rect{
		x: lb.bounds.x + lb.bounds.w - lb.pad - sbw
		y: vp.y
		w: sbw
		h: vis_h
	}
	thumb_h := max_f32(lb.eff_sb_min_thumb(), vis_h * (vis_h / ch))
	ms := lb.max_scroll()
	ratio := if ms > 0 { lb.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 2
		y: track.y + ratio * (vis_h - thumb_h)
		w: sbw - 4
		h: thumb_h
	}
	return track, thumb
}

// Horizontal scrollbar geometry
fn (lb &ListBox) hsb_rects() (Rect, Rect) {
	vp := lb.viewport_rect()
	cw := lb.content_width()
	vis_w := vp.w
	if cw <= vis_w {
		return Rect{}, Rect{}
	}
	sbw := lb.eff_sb_width()
	track := Rect{
		x: vp.x
		y: lb.bounds.y + lb.bounds.h - lb.pad - sbw
		w: vis_w
		h: sbw
	}
	thumb_w := max_f32(lb.eff_sb_min_thumb(), vis_w * (vis_w / cw))
	ms := lb.max_scroll_x()
	ratio := if ms > 0 { lb.scroll_x / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vis_w - thumb_w)
		y: track.y + 2
		w: thumb_w
		h: sbw - 4
	}
	return track, thumb
}

// ensure_visible прокручивает минимально необходимо, чтобы строка selected целиком попала в viewport (после перехода с клавиатуры).
fn (mut lb ListBox) ensure_visible() {
	if lb.selected < 0 || lb.rows.len == 0 {
		return
	}
	vp := lb.viewport_rect()
	if lb.horizontal {
		iw := lb.eff_item_width()
		item_left := f32(lb.selected) * iw
		item_right := item_left + iw
		if item_left < lb.scroll_x {
			lb.scroll_x = item_left
		}
		if item_right > lb.scroll_x + vp.w {
			lb.scroll_x = item_right - vp.w
		}
		lb.scroll_x = clamp_f32(lb.scroll_x, 0, lb.max_scroll_x())
		return
	}
	item_top := f32(lb.selected) * lb.item_height
	item_bot := item_top + lb.item_height
	if item_top < lb.scroll_y {
		lb.scroll_y = item_top
	}
	if item_bot > lb.scroll_y + vp.h {
		lb.scroll_y = item_bot - vp.h
	}
	lb.scroll_y = clamp_f32(lb.scroll_y, 0, lb.max_scroll())
}

// row_at returns the row index under the given window y coordinate (vertical
// lists), or -1. Useful for context menus: the app can select the row that
// was right-clicked before showing the menu.
pub fn (lb &ListBox) row_at(y f32) int {
	if lb.horizontal {
		return -1
	}
	return lb.hit_item(y)
}

// hit_item/hit_item_h - индекс строки под y (вертикальный) / x (горизонтальный режим) с учётом прокрутки, либо -1.
fn (lb &ListBox) hit_item(my f32) int {
	vp := lb.viewport_rect()
	rel_y := my - vp.y + lb.scroll_y
	idx := int(rel_y / lb.item_height)
	if idx >= 0 && idx < lb.rows.len {
		return idx
	}
	return -1
}

fn (lb &ListBox) hit_item_h(mx f32) int {
	vp := lb.viewport_rect()
	rel_x := mx - vp.x + lb.scroll_x
	idx := int(rel_x / lb.eff_item_width())
	if idx >= 0 && idx < lb.rows.len {
		return idx
	}
	return -1
}

// hit_sort_col - индекс колонки, у которой курсор над кнопкой сортировки в шапке, либо -1.
fn (lb &ListBox) hit_sort_col(mx f32, my f32) int {
	if !lb.show_header || lb.columns.len == 0 {
		return -1
	}
	hdr_y := lb.bounds.y + lb.pad
	if my < hdr_y || my > hdr_y + lb.header_height {
		return -1
	}
	mut cx := lb.bounds.x + lb.pad - lb.scroll_x
	for ci in 0 .. lb.columns.len {
		col := lb.columns[ci]
		if col.show_sort {
			sort_x := cx + col.width - lb_sort_btn_w - 2
			if mx >= sort_x && mx <= sort_x + lb_sort_btn_w && my >= hdr_y
				&& my <= hdr_y + lb.header_height {
				return ci
			}
		}
		cx += col.width
	}
	return -1
}

// Hit test for column border resize handle (in header area)
fn (lb &ListBox) hit_col_border(mx f32, my f32) int {
	if !lb.show_header || lb.columns.len == 0 {
		return -1
	}
	hdr_y := lb.bounds.y + lb.pad
	if my < hdr_y || my > hdr_y + lb.header_height {
		return -1
	}
	mut cx := lb.bounds.x + lb.pad - lb.scroll_x
	for ci in 0 .. lb.columns.len {
		cx += lb.columns[ci].width
		if abs_f32(mx - cx) < lb_resize_zone {
			return ci
		}
	}
	return -1
}

// fire_select вызывает on_select(selected, текст), если выбор корректен.
fn (mut lb ListBox) fire_select() {
	if lb.on_select != unsafe { nil } && lb.selected >= 0 && lb.selected < lb.rows.len {
		text := if lb.selected < lb.items.len { lb.items[lb.selected] } else { '' }
		lb.on_select(lb.selected, text)
	}
}

// toggle_sort - цикл none -> asc -> desc -> none для колонки; остальным сбрасывает индикатор и зовёт on_sort. Сортировку данных выполняет вызывающий код.
fn (mut lb ListBox) toggle_sort(col int) {
	if col < 0 || col >= lb.columns.len {
		return
	}
	new_dir := match lb.columns[col].sort_dir {
		.none_ { LbSortDir.asc }
		.asc { LbSortDir.desc }
		.desc { LbSortDir.none_ }
	}

	for i in 0 .. lb.columns.len {
		lb.columns[i].sort_dir = .none_
	}
	lb.columns[col].sort_dir = new_dir
	if lb.on_sort != unsafe { nil } {
		lb.on_sort(col, new_dir)
	}
}

// ─── Drawing ───────────────────────────────────────────

// arrange выставляет bounds виджетам-ячейкам строк видимого диапазона — ровно
// тем, которые рисует draw() (тот же фильтр, что у hit_children).
pub fn (mut lb ListBox) arrange(mut ctx RenderContext) {
	if !lb.visible {
		return
	}
	lb.scroll_y = clamp_f32(lb.scroll_y, 0, lb.max_scroll())
	lb.scroll_x = clamp_f32(lb.scroll_x, 0, lb.max_scroll_x())
	vp := lb.viewport_rect()

	if lb.horizontal {
		iw := lb.eff_item_width()
		ih := vp.h
		first, last := lb.visible_row_range_h(vp, iw)
		for i := first; i <= last; i++ {
			if i < 0 || i >= lb.rows.len || lb.rows[i].cells.len == 0
				|| !lb.row_visible_h(i, vp, iw) {
				continue
			}
			mut w := unsafe { lb.rows[i].cells[0].widget }
			if unsafe { w == nil } {
				continue
			}
			ix := vp.x + f32(i) * iw - lb.scroll_x
			arrange_child(mut w, Rect{ix + lb_cell_pad, vp.y + lb_cell_pad, iw - lb_cell_pad * 2, ih - lb_cell_pad * 2}, mut
				ctx)
		}
		return
	}

	if lb.columns.len == 0 {
		return
	}
	first, last := lb.visible_row_range_v(vp)
	for i := first; i <= last; i++ {
		if i < 0 || i >= lb.rows.len || !lb.row_visible_v(i, vp) {
			continue
		}
		iy := vp.y + f32(i) * lb.item_height - lb.scroll_y
		mut cx := vp.x - lb.scroll_x
		for ci in 0 .. lb.columns.len {
			col_w := lb.columns[ci].width
			if ci < lb.rows[i].cells.len && cx + col_w > vp.x && cx < vp.x + vp.w {
				mut w := unsafe { lb.rows[i].cells[ci].widget }
				if unsafe { w != nil } {
					arrange_child(mut w, Rect{cx + lb_cell_pad, iy + 1, col_w - lb_cell_pad * 2, lb.item_height - 2}, mut
						ctx)
				}
			}
			cx += col_w
		}
	}
}

// draw рисует список. Порядок: регистрация в фокус-менеджере (только enabled) и синхронизация
// флага focused -> анимация кольца фокуса -> фон и рамка -> шапка (колонки, кнопки сортировки,
// линия при перетаскивании границы) -> строки внутри clip(viewport) -> полосы прокрутки.
// Виджеты-ячейки здесь только рисуются: их bounds уже выставил arrange().
pub fn (mut lb ListBox) draw(mut ctx RenderContext) {
	if !lb.visible {
		return
	}

	if !ctx.is_in_clip(lb.bounds) {
		return
	}

	if lb.enabled {
		ctx.focus.register_list_box(&lb, lb.focus_group)
	}

	should_focus := ctx.focus.is_focused(unsafe { &lb })
	if lb.focused && !should_focus {
		lb.focused = false
	} else if !lb.focused && should_focus {
		lb.focused = true
	}

	target_focus := if lb.focused && lb.enabled { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if lb.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('listbox', lb.bounds.expanded(1))
	}

	lb.scroll_y = clamp_f32(lb.scroll_y, 0, lb.max_scroll())
	lb.scroll_x = clamp_f32(lb.scroll_x, 0, lb.max_scroll_x())

	rad := ctx.theme.border_radius
	bg := if lb.enabled { ctx.theme.eff_lb_bg() } else { ctx.theme.eff_lb_bg().darken(0.05) }
	ctx.fill_rounded_rect(lb.bounds, bg, rad)

	bc := ctx.theme.eff_lb_border().blend(ctx.theme.input_focus, lb.focus_anim.value)
	ctx.draw_rounded_rect(lb.bounds, bc, rad)

	ctx.draw_focus_ring(lb.bounds, rad, lb.focus_anim.value)

	font := ctx.get_font(.regular, 0)
	font_b := ctx.get_font(.bold, 0)
	fh := ctx.font_height_of(font)
	vp := lb.viewport_rect()

	// ── Header ──
	if lb.show_header && lb.columns.len > 0 {
		hdr_y := lb.bounds.y + lb.pad
		hdr_r := Rect{lb.bounds.x + lb.pad, hdr_y, vp.w, lb.header_height}
		ctx.fill_rect(hdr_r, ctx.theme.eff_lb_header_bg())
		ctx.fill_rect(Rect{hdr_r.x, hdr_r.y + hdr_r.h - 1, hdr_r.w, 1},
			ctx.theme.eff_lb_header_border())

		ctx.push_clip(hdr_r)
		mut hx := hdr_r.x - lb.scroll_x
		for ci in 0 .. lb.columns.len {
			col := lb.columns[ci]
			if hx + col.width > hdr_r.x && hx < hdr_r.x + hdr_r.w {
				// Title
				avail_w := col.width - lb_cell_pad * 2 -
					(if col.show_sort { lb_sort_btn_w } else { f32(0) })
				title_clip := tbl_clip_text(ctx, col.title, avail_w, font_b)
				ty := hdr_y + (lb.header_height - fh) * 0.5
				ctx.draw_text_with_font(title_clip, hx + lb_cell_pad, ty,
					ctx.theme.eff_lb_header_text(), font_b)

				// Sort button
				if col.show_sort {
					sx := hx + col.width - lb_sort_btn_w - 2
					sy := hdr_y + lb.header_height * 0.5
					arrow_c := if ci == lb.sort_hover_col {
						ctx.theme.accent
					} else {
						ctx.theme.text_secondary
					}
					as_ := f32(3)
					match col.sort_dir {
						.asc {
							ctx.fill_triangle(sx + lb_sort_btn_w * 0.5, sy - as_, sx +
								lb_sort_btn_w * 0.5 - as_, sy + as_,
								sx + lb_sort_btn_w * 0.5 + as_, sy + as_, arrow_c)
						}
						.desc {
							ctx.fill_triangle(sx + lb_sort_btn_w * 0.5, sy + as_, sx +
								lb_sort_btn_w * 0.5 - as_, sy - as_,
								sx + lb_sort_btn_w * 0.5 + as_, sy - as_, arrow_c)
						}
						.none_ {
							// Diamond shape (unsorted)
							mid_x := sx + lb_sort_btn_w * 0.5
							ctx.fill_triangle(mid_x, sy - as_, mid_x - as_ * 0.6, sy, mid_x +
								as_ * 0.6, sy, arrow_c.with_alpha(120))
							ctx.fill_triangle(mid_x, sy + as_, mid_x - as_ * 0.6, sy, mid_x +
								as_ * 0.6, sy, arrow_c.with_alpha(120))
						}
					}
				}

				// Grid line
				if lb.show_grid && ci < lb.columns.len - 1 {
					ctx.fill_rect(Rect{hx + col.width - 1, hdr_y, 1, lb.header_height},
						ctx.theme.eff_lb_grid())
				}
			}
			hx += col.width
		}
		ctx.pop_clip()

		// ── Column resize indicator ──
		if lb.col_resizing && lb.resize_col >= 0 && lb.resize_col < lb.columns.len {
			mut rx := lb.bounds.x + lb.pad - lb.scroll_x
			for ci in 0 .. lb.resize_col + 1 {
				rx += lb.columns[ci].width
			}
			ctx.fill_rect(Rect{rx - 1, hdr_y, 2, lb.header_height}, ctx.theme.accent)
		} else if lb.resize_hover_col >= 0 && lb.resize_hover_col < lb.columns.len {
			mut rx := lb.bounds.x + lb.pad - lb.scroll_x
			for ci in 0 .. lb.resize_hover_col + 1 {
				rx += lb.columns[ci].width
			}
			ctx.fill_rect(Rect{rx - 1, hdr_y, 2, lb.header_height},
				ctx.theme.accent.with_alpha(120))
		}
	}

	// ── Rows / Items ──
	ctx.push_clip(vp)

	if lb.horizontal {
		// Horizontal (filmstrip) mode — items laid out left to right
		iw := lb.eff_item_width()
		ih := vp.h
		h_first, h_last := lb.visible_row_range_h(vp, iw)
		for i := h_first; i <= h_last; i++ {
			if i < 0 || i >= lb.rows.len || !lb.row_visible_h(i, vp, iw) {
				continue
			}
			ix := vp.x + f32(i) * iw - lb.scroll_x
			is_sel := lb.is_row_selected(i)
			is_hov := i == lb.hover_index && lb.hovered
			item_r := Rect{ix, vp.y, iw, ih}
			if is_sel {
				ctx.fill_rect(item_r, ctx.theme.eff_lb_row_selected().with_alpha(180))
			} else if is_hov {
				ctx.fill_rect(item_r, ctx.theme.eff_lb_row_hover().with_alpha(100))
			}
			tc := if is_sel { ctx.theme.eff_lb_row_sel_text() } else { ctx.theme.eff_lb_row_text() }
			// Draw widget or text from first cell
			if lb.rows[i].cells.len > 0 {
				cell := lb.rows[i].cells[0]
				if unsafe { cell.widget != nil } {
					// Bounds set in arrange()
					mut w := unsafe { cell.widget }
					w.draw(mut ctx)
				} else if cell.text.len > 0 {
					ty := vp.y + (ih - fh) * 0.5
					ctx.draw_text_with_font(cell.text, ix + lb_cell_pad, ty, tc, font)
				}
			} else if i < lb.items.len {
				ty := vp.y + (ih - fh) * 0.5
				ctx.draw_text_with_font(lb.items[i], ix + lb_cell_pad, ty, tc, font)
			}
			// Separator between items
			if i < lb.rows.len - 1 {
				ctx.fill_rect(Rect{ix + iw - 1, vp.y, 1, ih},
					ctx.theme.eff_lb_grid().with_alpha(lb_grid_color_a))
			}
		}
	} else {
		v_first, v_last := lb.visible_row_range_v(vp)
		for i := v_first; i <= v_last; i++ {
			if i < 0 || i >= lb.rows.len || !lb.row_visible_v(i, vp) {
				continue
			}
			iy := vp.y + f32(i) * lb.item_height - lb.scroll_y

			is_sel := lb.is_row_selected(i)
			is_hov := i == lb.hover_index && lb.hovered

			// Row background
			if is_sel {
				ctx.fill_rect(Rect{vp.x, iy, vp.w, lb.item_height},
					ctx.theme.eff_lb_row_selected().with_alpha(180))
			} else if is_hov {
				ctx.fill_rect(Rect{vp.x, iy, vp.w, lb.item_height},
					ctx.theme.eff_lb_row_hover().with_alpha(100))
			}

			tc := if is_sel { ctx.theme.eff_lb_row_sel_text() } else { ctx.theme.eff_lb_row_text() }

			if lb.columns.len > 0 {
				// Multi-column: draw each cell
				row := lb.rows[i]
				mut cx := vp.x - lb.scroll_x
				for ci in 0 .. lb.columns.len {
					col_w := lb.columns[ci].width
					if ci < row.cells.len {
						cell := row.cells[ci]
						cell_r := Rect{cx, iy, col_w, lb.item_height}
						if cx + col_w > vp.x && cx < vp.x + vp.w {
							if unsafe { cell.widget != nil } {
								// Custom widget — bounds set in arrange()
								mut w := unsafe { cell.widget }
								w.draw(mut ctx)
							} else if cell.text.len > 0 {
								// Text cell
								align := if ci < lb.columns.len {
									lb.columns[ci].align
								} else {
									TextAlign.left
								}
								tbl_draw_text_aligned(mut ctx, cell.text, cell_r, align, tc, font)
							}
							// Grid line
							if lb.show_grid && ci < lb.columns.len - 1 {
								ctx.fill_rect(Rect{cx + col_w - 1, iy, 1, lb.item_height},
									ctx.theme.eff_lb_grid().with_alpha(lb_grid_color_a))
							}
						}
					}
					cx += col_w
				}
			} else {
				// Single-column legacy
				if i < lb.items.len {
					ty := iy + (lb.item_height - fh) * 0.5
					ctx.draw_text_with_font(lb.items[i], vp.x + 6, ty, tc, font)
				}
			}
		}
	}

	ctx.pop_clip()

	// ── Vertical Scrollbar ──
	if lb.has_scrollbar() {
		track, thumb := lb.scrollbar_rects()
		sb_rad := lb.eff_sb_radius()
		track_c := lb.eff_sb_track_color(ctx)
		if track_c.a > 0 {
			ctx.fill_rounded_rect(track, track_c, sb_rad)
		}
		thumb_c := if lb.sb_dragging {
			lb.eff_sb_thumb_drag(ctx)
		} else if lb.sb_hovered {
			lb.eff_sb_thumb_hover(ctx)
		} else {
			lb.eff_sb_thumb_color(ctx)
		}
		ctx.fill_rounded_rect(thumb, thumb_c, sb_rad)
	}

	// ── Horizontal Scrollbar ──
	if lb.has_hsb() {
		track, thumb := lb.hsb_rects()
		sb_rad := lb.eff_sb_radius()
		track_c := lb.eff_sb_track_color(ctx)
		if track_c.a > 0 {
			ctx.fill_rounded_rect(track, track_c, sb_rad)
		}
		thumb_c := if lb.hsb_dragging {
			lb.eff_sb_thumb_drag(ctx)
		} else if lb.hsb_hovered {
			lb.eff_sb_thumb_hover(ctx)
		} else {
			lb.eff_sb_thumb_color(ctx)
		}
		ctx.fill_rounded_rect(thumb, thumb_c, sb_rad)
	}
}

// ─── Events ────────────────────────────────────────────

// handle_event: true - событие поглощено. Порядок проверок важен:
//   1. активные перетаскивания (границы колонки, вертикальный и горизонтальный бегунок) забирают
//      все события до отпускания левой кнопки;
//   2. иначе по типу события: mouse_move (hover, курсор, hover_index), mouse_down (границы,
//      полосы, сортировка, виджеты в ячейках, выбор строки), mouse_up, двойной клик, колесо,
//      клавиатура (только при focused).
// Курсор мыши переставляется прямо здесь (кэширующий set_cursor).
pub fn (mut lb ListBox) handle_event(event &GuiEvent, app &App) bool {
	if !lb.visible || !lb.enabled {
		return false
	}

	// ── Column resize drag in progress ──
	if lb.col_resizing {
		match event.typ {
			.mouse_move {
				if lb.resize_col >= 0 && lb.resize_col < lb.columns.len {
					dx := event.mouse_x - lb.resize_start_x
					new_w := max_f32(lb.columns[lb.resize_col].min_w, lb.resize_start_w + dx)
					lb.columns[lb.resize_col].width = new_w
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					lb.col_resizing = false
					lb.resize_col = -1
					set_cursor(sdl_system_cursor_arrow)
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Vertical scrollbar drag ──
	if lb.sb_dragging {
		match event.typ {
			.mouse_move {
				track, _ := lb.scrollbar_rects()
				if track.h <= 0 {
					return true
				}
				ch := lb.content_height()
				vis_h := track.h
				thumb_h := max_f32(lb.eff_sb_min_thumb(), vis_h * (vis_h / ch))
				drag_range := vis_h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - lb.sb_drag_start_y
				ms := lb.max_scroll()
				lb.scroll_y = clamp_f32(lb.sb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					lb.sb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Horizontal scrollbar drag ──
	if lb.hsb_dragging {
		match event.typ {
			.mouse_move {
				track, _ := lb.hsb_rects()
				if track.w <= 0 {
					return true
				}
				cw := lb.content_width()
				vis_w := track.w
				thumb_w := max_f32(lb.eff_sb_min_thumb(), vis_w * (vis_w / cw))
				drag_range := vis_w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - lb.hsb_drag_start_x
				ms := lb.max_scroll_x()
				lb.scroll_x = clamp_f32(lb.hsb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					lb.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			lb.hovered = lb.bounds.contains(event.mouse_x, event.mouse_y)
			lb.sort_hover_col = -1
			lb.resize_hover_col = -1
			if lb.hovered {
				// Scrollbar hover check
				if lb.has_scrollbar() {
					track, _ := lb.scrollbar_rects()
					lb.sb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					lb.sb_hovered = false
				}
				if lb.has_hsb() {
					track, _ := lb.hsb_rects()
					lb.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					lb.hsb_hovered = false
				}

				// Column resize cursor (check before sort hover)
				if lb.show_header && lb.columns.len > 0 {
					col_border := lb.hit_col_border(event.mouse_x, event.mouse_y)
					if col_border >= 0 {
						lb.resize_hover_col = col_border
						set_cursor(sdl_system_cursor_sizewe)
					} else {
						// Restore cursor if we were hovering a border before
						// (only if not over scrollbar)
						if !lb.sb_hovered && !lb.hsb_hovered {
							// Header sort button hover
							lb.sort_hover_col = lb.hit_sort_col(event.mouse_x, event.mouse_y)
						}
						set_cursor(sdl_system_cursor_arrow)
					}
				}

				// Row hover (only in data area, not header, not scrollbar)
				vp := lb.viewport_rect()
				if lb.horizontal {
					if vp.contains(event.mouse_x, event.mouse_y) && !lb.hsb_hovered {
						lb.hover_index = lb.hit_item_h(event.mouse_x)
					} else {
						lb.hover_index = -1
					}
				} else if event.mouse_y >= vp.y && event.mouse_y < vp.y + vp.h && !lb.sb_hovered
					&& lb.sort_hover_col < 0 && lb.resize_hover_col < 0 {
					lb.hover_index = lb.hit_item(event.mouse_y)
				} else {
					lb.hover_index = -1
				}
			} else {
				lb.hover_index = -1
				lb.sb_hovered = false
				lb.hsb_hovered = false
			}

			// // Виджеты-ячейки получают mouse_move для собственного hover.
			// Pass move events to widget cells (for hover effects inside custom widgets)
			if lb.columns.len > 0 || lb.horizontal {
				lb.dispatch_to_row_widgets(event, app)
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && lb.hovered {
				// ── Column resize drag start ──
				if lb.show_header && lb.columns.len > 0 {
					col_border := lb.hit_col_border(event.mouse_x, event.mouse_y)
					if col_border >= 0 {
						lb.col_resizing = true
						lb.resize_col = col_border
						lb.resize_start_x = event.mouse_x
						lb.resize_start_w = lb.columns[col_border].width
						return true
					}
				}

				// Scrollbar thumb drag
				if lb.has_scrollbar() {
					_, thumb := lb.scrollbar_rects()
					track, _ := lb.scrollbar_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						lb.sb_dragging = true
						lb.sb_drag_start_y = event.mouse_y
						lb.sb_drag_start_scroll = lb.scroll_y
						return true
					}
					if track.contains(event.mouse_x, event.mouse_y) {
						vis_h := track.h
						if event.mouse_y < thumb.y {
							lb.scroll_y = max_f32(0, lb.scroll_y - vis_h)
						} else {
							lb.scroll_y = min_f32(lb.max_scroll(), lb.scroll_y + vis_h)
						}
						return true
					}
				}
				if lb.has_hsb() {
					_, thumb := lb.hsb_rects()
					track, _ := lb.hsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						lb.hsb_dragging = true
						lb.hsb_drag_start_x = event.mouse_x
						lb.hsb_drag_start_scroll = lb.scroll_x
						return true
					}
					if track.contains(event.mouse_x, event.mouse_y) {
						vis_w := track.w
						if event.mouse_x < thumb.x {
							lb.scroll_x = max_f32(0, lb.scroll_x - vis_w)
						} else {
							lb.scroll_x = min_f32(lb.max_scroll_x(), lb.scroll_x + vis_w)
						}
						return true
					}
				}

				// Header sort button click
				if lb.show_header {
					col := lb.hit_sort_col(event.mouse_x, event.mouse_y)
					if col >= 0 {
						lb.toggle_sort(col)
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.focus_list_box(&lb, lb.focus_group)
						}
						lb.focused = true
						return true
					}
					// Clicks on header area (non-sort, non-resize) don't select rows
					hdr_y := lb.bounds.y + lb.pad
					if event.mouse_y >= hdr_y && event.mouse_y < hdr_y + lb.header_height {
						return true
					}
				}

				// // Клик сначала отдаём виджету-ячейке (кнопке и т.п.); выбор строки - только если ячейка событие не взяла.
				// Try to dispatch to row widget first
				if (lb.columns.len > 0 || lb.horizontal) && lb.dispatch_to_row_widgets(event, app) {
					return true
				}

				// Row selection
				vp := lb.viewport_rect()
				if lb.horizontal {
					if vp.contains(event.mouse_x, event.mouse_y) {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.focus_list_box(&lb, lb.focus_group)
						}
						lb.focused = true
						idx := lb.hit_item_h(event.mouse_x)
						if idx >= 0 {
							lb.click_select(idx, event)
							lb.fire_select()
						}
						return true
					}
				} else if event.mouse_y >= vp.y && event.mouse_y < vp.y + vp.h {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.focus_list_box(&lb, lb.focus_group)
					}
					lb.focused = true
					idx := lb.hit_item(event.mouse_y)
					if idx >= 0 {
						lb.click_select(idx, event)
						lb.fire_select()
					}
					return true
				}
			}
			// // Клик мимо списка: снимаем фокус (событие не поглощаем - его обработают другие виджеты).
			if lb.focused && !lb.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.blur_current()
				}
				lb.focused = false
				return false
			}
		}
		.mouse_up {
			// Forward to widget cells
			if lb.columns.len > 0 || lb.horizontal {
				if lb.dispatch_to_row_widgets(event, app) {
					return true
				}
			}
		}
		.mouse_dbl_click {
			if lb.hovered && lb.focused {
				// Forward to widget cells first
				if (lb.columns.len > 0 || lb.horizontal) && lb.dispatch_to_row_widgets(event, app) {
					return true
				}
				vp := lb.viewport_rect()
				if lb.horizontal {
					if vp.contains(event.mouse_x, event.mouse_y) {
						idx := lb.hit_item_h(event.mouse_x)
						if idx >= 0 {
							lb.selected = idx
							if lb.on_dbl_click != unsafe { nil } {
								text := if idx < lb.items.len { lb.items[idx] } else { '' }
								lb.on_dbl_click(idx, text)
							}
						}
						return true
					}
				} else if event.mouse_y >= vp.y && event.mouse_y < vp.y + vp.h {
					idx := lb.hit_item(event.mouse_y)
					if idx >= 0 {
						lb.selected = idx
						if lb.on_dbl_click != unsafe { nil } {
							text := if idx < lb.items.len { lb.items[idx] } else { '' }
							lb.on_dbl_click(idx, text)
						}
					}
					return true
				}
			}
		}
		.mouse_wheel {
			// // (координаты берутся из живого ctx.mouse_*, т.к. в событии колеса x/y могут быть устаревшими)
			// Колесо - списку под курсором, фокус не нужен (не брать
			// колесо - флажок wheel). Есть что прокручивать по оси - колесо
			// поглощается и на краю: не уходит соседу или родителю.
			if !lb.wheel {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if lb.bounds.contains(mx, my) {
				if lb.horizontal {
					// Как у ScrollBox: колесо вниз (и наклон вправо) - вправо
					delta := if event.wheel_x != 0 { event.wheel_x } else { -event.wheel_y }
					ms := lb.max_scroll_x()
					lb.scroll_x = clamp_f32(lb.scroll_x + delta * lb.scroll_x_speed, 0, ms)
					return ms > 0
				}
				if event.shift() && lb.has_hsb() {
					ms := lb.max_scroll_x()
					lb.scroll_x = clamp_f32(lb.scroll_x - event.wheel_y * lb.scroll_x_speed, 0, ms)
					return ms > 0
				}
				ms := lb.max_scroll()
				lb.scroll_y = clamp_f32(lb.scroll_y - event.wheel_y * lb.scroll_speed, 0, ms)
				return ms > 0
			}
		}
		.key_down {
			if !lb.focused {
				return false
			}

			// App-level hook (custom shortcuts) wins over built-in navigation.
			if lb.on_key_down != unsafe { nil } && lb.on_key_down(event) {
				return true
			}

			// Forward key events to focused widget inside a row first
			if lb.columns.len > 0 || lb.horizontal {
				if lb.dispatch_to_row_widgets(event, app) {
					return true
				}
			}

			// // Home/End/PageUp/PageDown: выбор прыгает, затем ensure_visible (прокрутка) и key_select (Shift - диапазон).
			if is_home_key(event.keycode, event.scancode) {
				if lb.rows.len > 0 {
					lb.selected = 0
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				if lb.rows.len > 0 {
					lb.selected = lb.rows.len - 1
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if tv_is_pageup_key(event.keycode, event.scancode) {
				if lb.rows.len > 0 {
					visible_count := max_int(1, int(lb.viewport_rect().h / lb.item_height))
					lb.selected = max_int(0, lb.selected - visible_count)
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if tv_is_pagedown_key(event.keycode, event.scancode) {
				if lb.rows.len > 0 {
					visible_count := max_int(1, int(lb.viewport_rect().h / lb.item_height))
					lb.selected = min_int(lb.rows.len - 1, lb.selected + visible_count)
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}

			match event.keycode {
				// // Стрелки зацикливают список (с первой на последнюю и обратно). В горизонтальном режиме работают Left/Right.
				sdl_k_up {
					if !lb.horizontal && lb.rows.len > 0 {
						lb.selected = if lb.selected <= 0 {
							lb.rows.len - 1
						} else {
							lb.selected - 1
						}
						lb.ensure_visible()
						lb.key_select(event)
						lb.fire_select()
					}
					return true
				}
				sdl_k_down {
					if !lb.horizontal && lb.rows.len > 0 {
						lb.selected = if lb.selected >= lb.rows.len - 1 {
							0
						} else {
							lb.selected + 1
						}
						lb.ensure_visible()
						lb.key_select(event)
						lb.fire_select()
					}
					return true
				}
				sdl_k_left {
					if lb.horizontal && lb.rows.len > 0 {
						lb.selected = if lb.selected <= 0 {
							lb.rows.len - 1
						} else {
							lb.selected - 1
						}
						lb.ensure_visible()
						lb.key_select(event)
						lb.fire_select()
					}
					return true
				}
				sdl_k_right {
					if lb.horizontal && lb.rows.len > 0 {
						lb.selected = if lb.selected >= lb.rows.len - 1 {
							0
						} else {
							lb.selected + 1
						}
						lb.ensure_visible()
						lb.key_select(event)
						lb.fire_select()
					}
					return true
				}
				sdl_k_return {
					if lb.selected >= 0 && lb.selected < lb.rows.len {
						if lb.on_dbl_click != unsafe { nil } {
							text := if lb.selected < lb.items.len {
								lb.items[lb.selected]
							} else {
								''
							}
							lb.on_dbl_click(lb.selected, text)
						}
					}
					return true
				}
				sdl_k_tab {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.tab(event.shift())
					}
					return true
				}
				sdl_k_escape {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.blur_current()
					}
					return true
				}
				else {}
			}
		}
		else {}
	}

	return false
}

// Dispatch an event to visible cell widgets. Returns true if any widget handled it.
// dispatch_to_row_widgets пересылает событие виджетам-ячейкам видимых строк (снизу вверх - верхний
// рисуется последним, значит первым должен получить событие). Перед этим bounds ячейки пересчитываются
// заново (set_widget_bounds): arrange() мог ещё не успеть после прокрутки/смены колонок, а hit-test виджета
// опирается на его bounds. true - какой-то виджет событие обработал.
fn (mut lb ListBox) dispatch_to_row_widgets(event &GuiEvent, app &App) bool {
	if lb.horizontal {
		return lb.dispatch_to_row_widgets_h(event, app)
	}
	if lb.columns.len == 0 {
		return false
	}
	vp := lb.viewport_rect()

	first, last := lb.visible_row_range_v(vp)
	if last < first {
		return false
	}

	for i := last; i >= first; i-- {
		if i < 0 || i >= lb.rows.len {
			continue
		}
		if !lb.row_visible_v(i, vp) {
			continue
		}
		// Update widget bounds to current position (needed for hit-testing)
		iy := vp.y + f32(i) * lb.item_height - lb.scroll_y
		for ci in 0 .. min_int(lb.rows[i].cells.len, lb.columns.len) {
			mut cell := lb.rows[i].cells[ci]
			if unsafe { cell.widget == nil } {
				continue
			}
			mut cx := vp.x - lb.scroll_x
			for k in 0 .. min_int(ci, lb.columns.len) {
				cx += lb.columns[k].width
			}
			col_w := if ci < lb.columns.len { lb.columns[ci].width } else { f32(0) }
			inner := Rect{cx + lb_cell_pad, iy + 1, col_w - lb_cell_pad * 2, lb.item_height - 2}
			mut w := unsafe { cell.widget }
			set_widget_bounds(mut w, inner)
			if w.handle_event(event, app) {
				return true
			}
		}
	}
	return false
}

// dispatch_to_row_widgets_h - то же для горизонтального режима (виджет только в cells[0]).
fn (mut lb ListBox) dispatch_to_row_widgets_h(event &GuiEvent, app &App) bool {
	vp := lb.viewport_rect()
	iw := lb.eff_item_width()
	ih := vp.h

	first, last := lb.visible_row_range_h(vp, iw)
	if last < first {
		return false
	}

	for i := last; i >= first; i-- {
		if i < 0 || i >= lb.rows.len {
			continue
		}
		if !lb.row_visible_h(i, vp, iw) {
			continue
		}
		if lb.rows[i].cells.len == 0 {
			continue
		}
		mut cell := lb.rows[i].cells[0]
		if unsafe { cell.widget == nil } {
			continue
		}
		ix := vp.x + f32(i) * iw - lb.scroll_x
		inner :=
			Rect{ix + lb_cell_pad, vp.y + lb_cell_pad, iw - lb_cell_pad * 2, ih - lb_cell_pad * 2}
		mut w := unsafe { cell.widget }
		set_widget_bounds(mut w, inner)
		if w.handle_event(event, app) {
			return true
		}
	}
	return false
}
