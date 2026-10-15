module vgui

import math
import strconv

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
//   * заголовок: сортировка (при auto_sort ListBox сам переставляет строки - см. «Сортировка»
//     ниже; иначе только индикатор и сигнал on_sort) и изменение ширины колонок
//     перетаскиванием границы;
//   * раскладка/отрисовка: measure() - layout_measure.v (константный scrollable_hint); виджетам
//     в ячейках bounds раздаёт arrange() (только для видимых строк), draw() их лишь рисует;
//     hit_children - widget_tree.v; фокус - focus.v (register_list_box/focus_list_box);
//   * события: handle_event (ниже) - единый обработчик с приоритетом активных перетаскиваний;
//   * виртуальный режим (set_virtual, раздел «Виртуальный режим» ниже): строк в rows нет,
//     число строк и текст ячеек - от приложения (колбэк для видимых строк). Код, которому
//     всё равно, откуда данные, ходит через row_total/cell_text/item_text/row_icon/cell_widget.
//
// Шапка только для чтения. Сортировка - по колонкам с show_sort: щелчок по всему
// заголовку колонки (не только по стрелке) переключает направление, при auto_sort
// переставляет строки и зовёт on_sort. Вид шапки - draw_header.
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
	// иконка строки (item_icon.v) - слева от текста первой колонки; у ячейки-виджета не рисуется
	icon ItemIcon
	// порядковый номер добавления: по нему сортировка «none_» возвращает
	// исходный порядок, и он же разбивает равенства (сортировка устойчива)
	seq int
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
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
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
	item_height f32 = 24
	// размер иконки строки и зазор до текста (если у строк есть иконки)
	icon_size   f32  = 16
	icon_gap    f32  = 6
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
	// auto_sort - ListBox сам переставляет строки по колонке с индикатором
	// сортировки (щелчок по кнопке в шапке, set_column_sort); false - строки
	// не трогаются, сортирует приложение в on_sort.
	auto_sort bool = true
	// sort_cmp - своё сравнение текстов ячеек колонки col (<0, 0, >0 как у
	// strcmp, по возрастанию); nil - lb_text_cmp (числа как числа, текст без
	// учёта регистра)
	sort_cmp  fn (col int, a string, b string) int = unsafe { nil }
	next_seq  int
	show_grid bool // draw vertical grid lines between columns
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
	// Инвариант: sel_marks отсортирован по возрастанию и без повторов - тогда
	// is_row_selected (зовётся на каждую видимую строку каждого кадра) ищет двоичным
	// поиском, а Shift-диапазон на сотни тысяч строк строится без квадратичных проверок
	// «уже есть ли».
	sel_multi  bool
	sel_marks  []int
	sel_anchor int = -1
	// Виртуальный режим (set_virtual): строки не хранятся, ListBox знает только их
	// число virtual_count и спрашивает текст ячейки (row, col) у virtual_text, а
	// иконку строки - у virtual_icon (nil - без иконок). Менять через set_virtual/
	// set_virtual_count/set_virtual_icons/clear_virtual.
	is_virtual    bool
	virtual_count int
	virtual_text  fn (row int, col int) string = unsafe { nil }
	virtual_icon  fn (row int) ItemIcon        = unsafe { nil }
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

// set_column_sort ставит индикатор сортировки колонке и снимает у остальных (одновременно сортируется одна колонка).
// При auto_sort переставляет строки (dir = none_ - исходный порядок); on_sort не зовёт.
pub fn (mut lb ListBox) set_column_sort(col int, dir LbSortDir) {
	if col >= 0 && col < lb.columns.len {
		// Clear other columns' sort
		for i in 0 .. lb.columns.len {
			lb.columns[i].sort_dir = .none_
		}
		lb.columns[col].sort_dir = dir
		if lb.auto_sort {
			lb.resort()
		}
	}
}

// ─── Сортировка ────────────────────────────────────────
// При auto_sort строки упорядочены по колонке с индикатором сортировки
// (sorted_col): resort() переставляет все строки, push_row вставляет новую
// строку сразу на её место. Сортировка устойчива: равные строки остаются в
// порядке добавления (LbRow.seq), а без индикатора возвращается исходный
// порядок. Выбор (selected, отметки множественного выбора, якорь Shift)
// следует за своими строками. Правка текста ячейки (set_row_cell_text)
// порядок не обновляет - после неё зовите resort().

// lb_text_cmp - сравнение по умолчанию: если оба текста - числа, сравниваются
// как числа (2 < 10), иначе как строки без учёта регистра.
pub fn lb_text_cmp(a string, b string) int {
	if na := lb_number(a) {
		if nb := lb_number(b) {
			return if na < nb {
				-1
			} else if na > nb {
				1
			} else {
				0
			}
		}
	}
	la, lb_ := a.to_lower(), b.to_lower()
	if la != lb_ {
		return if la < lb_ { -1 } else { 1 }
	}
	return if a < b {
		-1
	} else if a > b {
		1
	} else {
		0
	}
}

// lb_number - текст целиком число (пробелы по краям допускаются)
fn lb_number(s string) ?f64 {
	t := s.trim_space()
	if t == '' {
		return none
	}
	for c in t {
		if !(c.is_digit() || c in [`-`, `+`, `.`, `e`, `E`]) {
			return none
		}
	}
	return strconv.atof64(t) or { return none }
}

// sorted_col - колонка с индикатором сортировки (-1 - нет)
pub fn (lb &ListBox) sorted_col() int {
	for i, c in lb.columns {
		if c.sort_dir != .none_ {
			return i
		}
	}
	return -1
}

// row_cmp - порядок строк a и b при сортировке по колонке col (-1 - по
// порядку добавления); равенство разбивает seq
fn (lb &ListBox) row_cmp(a &LbRow, b &LbRow, col int) int {
	if col >= 0 {
		ta := if col < a.cells.len { a.cells[col].text } else { '' }
		tb := if col < b.cells.len { b.cells[col].text } else { '' }
		mut r := if lb.sort_cmp != unsafe { nil } {
			lb.sort_cmp(col, ta, tb)
		} else {
			lb_text_cmp(ta,
				tb)
		}
		if lb.columns[col].sort_dir == .desc {
			r = -r
		}
		if r != 0 {
			return r
		}
	}
	return if a.seq < b.seq {
		-1
	} else if a.seq > b.seq {
		1
	} else {
		0
	}
}

// resort переставляет строки по текущему индикатору сортировки (без него -
// исходный порядок добавления); выбор следует за строками. В виртуальном режиме
// строк в ListBox нет - порядок задаёт приложение (on_sort), здесь ничего не делается.
pub fn (mut lb ListBox) resort() {
	n := lb.rows.len
	if n < 2 || lb.is_virtual {
		return
	}
	col := lb.sorted_col()
	// вставки с бинарным поиском места: устойчиво (равные - по seq), а сдвиги
	// int-массива дёшевы даже для десятков тысяч строк
	mut order := []int{cap: n}
	for i in 0 .. n {
		mut lo, mut hi := 0, order.len
		for lo < hi {
			mid := (lo + hi) / 2
			if lb.row_cmp(&lb.rows[order[mid]], &lb.rows[i], col) <= 0 {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		order.insert(lo, i)
	}
	mut new_pos := []int{len: n}
	mut rows := []LbRow{cap: n}
	mut items := []string{cap: n}
	for ni, oi in order {
		new_pos[oi] = ni
		rows << lb.rows[oi]
		items << if oi < lb.items.len { lb.items[oi] } else { lb.rows[oi].text }
	}
	lb.rows = rows
	lb.items = items
	remap := fn [new_pos] (i int) int {
		return if i >= 0 && i < new_pos.len { new_pos[i] } else { i }
	}
	lb.selected = remap(lb.selected)
	lb.sel_anchor = remap(lb.sel_anchor)
	// после перестановки отметки снова сортируем (инвариант sel_marks)
	mut marks := lb.sel_marks.map(remap(it))
	marks.sort()
	lb.sel_marks = marks
	lb.hover_index = -1
}

// push_row добавляет строку: в конец или, если список отсортирован
// (auto_sort и есть индикатор), сразу на её место по порядку
fn (mut lb ListBox) push_row(row LbRow, item string) {
	mut r := row
	r.seq = lb.next_seq
	lb.next_seq++
	col := if lb.auto_sort { lb.sorted_col() } else { -1 }
	if col < 0 {
		lb.items << item
		lb.rows << r
		return
	}
	mut lo, mut hi := 0, lb.rows.len
	for lo < hi {
		mid := (lo + hi) / 2
		if lb.row_cmp(&lb.rows[mid], &r, col) <= 0 {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	lb.rows.insert(lo, r)
	lb.items.insert(lo, item)
	// индексы за точкой вставки сдвигаются на одну строку
	if lb.selected >= lo {
		lb.selected++
	}
	if lb.sel_anchor >= lo {
		lb.sel_anchor++
	}
	lb.sel_marks = lb.sel_marks.map(if it >= lo { it + 1 } else { it })
	lb.hover_index = -1
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
	lb.push_row(LbRow{
		cells: cells
		text:  first_text
	}, first_text)
}

// add_item_widget adds a single widget as an item (used in horizontal/filmstrip mode)
pub fn (mut lb ListBox) add_item_widget(widget &Widget) {
	lb.push_row(LbRow{
		cells: [LbCell{ widget: unsafe { widget } }]
	}, '')
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
	lb.push_row(LbRow{
		cells: cells
	}, '')
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

// get_row_cell_text - текст ячейки (row, col); в виртуальном режиме - от колбэка
// virtual_text. Неверные индексы - ''.
pub fn (lb &ListBox) get_row_cell_text(row int, col int) string {
	return lb.cell_text(row, col)
}

pub fn (mut lb ListBox) set_row_data(row int, data voidptr) {
	if row >= 0 && row < lb.rows.len {
		lb.rows[row].user_data = data
	}
}

// set_row_icon задаёт иконку строки row (ItemIcon{} - убрать); неверный индекс игнорируется.
// Иконка едет вместе со строкой при сортировке.
pub fn (mut lb ListBox) set_row_icon(row int, ic ItemIcon) {
	if row >= 0 && row < lb.rows.len {
		lb.rows[row].icon = ic
	}
}

// add_item_icon - add_item с иконкой слева от текста.
pub fn (mut lb ListBox) add_item_icon(text string, ic ItemIcon) {
	lb.add_item(text)
	// push_row при auto_sort ставит строку на её место, а не в конец - ищем по seq
	seq := lb.next_seq - 1
	for i, r in lb.rows {
		if r.seq == seq {
			lb.rows[i].icon = ic
			break
		}
	}
}

// draw_row_icon рисует иконку строки i у левого края клетки (x, y, h) и возвращает,
// на сколько сдвинуть текст вправо (0 - иконки нет).
fn (lb &ListBox) draw_row_icon(mut ctx RenderContext, i int, x f32, y f32, h f32, tc Color) f32 {
	ic := lb.row_icon(i)
	if !ic.is_set() {
		return 0
	}
	ctx.draw_item_icon(ic, Rect{x, y, lb.icon_size, h}, lb.icon_size, tc)
	return lb.icon_size + lb.icon_gap
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
		lb.push_row(LbRow{
			text:  text
			cells: [LbCell{
				text: text
			}]
		}, text)
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
// Виртуальный режим тоже выключается: после clear список обычный и пустой.
pub fn (mut lb ListBox) clear() {
	lb.items.clear()
	lb.rows.clear()
	lb.is_virtual = false
	lb.virtual_count = 0
	lb.virtual_text = unsafe { nil }
	lb.virtual_icon = unsafe { nil }
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
	if idx >= -1 && idx < lb.row_total() {
		lb.selected = idx
		lb.reset_marks()
	}
}

// ─── Множественный выбор (multi_select) ────────────────

// Помощники отсортированного списка отметок (инвариант sel_marks - см. поля).

// lb_marks_find - двоичный поиск i в отсортированном marks: (найден ли, позиция -
// где лежит или куда вставить, чтобы порядок сохранился).
fn lb_marks_find(marks []int, i int) (bool, int) {
	mut lo, mut hi := 0, marks.len
	for lo < hi {
		mid := (lo + hi) / 2
		if marks[mid] < i {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo < marks.len && marks[lo] == i, lo
}

// lb_range - отсортированный диапазон a..b включительно (a и b в любом порядке).
fn lb_range(a int, b int) []int {
	lo, hi := min_int(a, b), max_int(a, b)
	mut out := []int{cap: hi - lo + 1}
	for i in lo .. hi + 1 {
		out << i
	}
	return out
}

// lb_merge_marks - слияние двух отсортированных списков без повторов в один такой же,
// за один линейный проход (вместо «для каждого проверить, нет ли уже»).
fn lb_merge_marks(a []int, b []int) []int {
	mut out := []int{cap: a.len + b.len}
	mut i, mut j := 0, 0
	for i < a.len || j < b.len {
		// берём меньший из двух голов; равные - один раз
		v := if j >= b.len || (i < a.len && a[i] <= b[j]) { a[i] } else { b[j] }
		if i < a.len && a[i] == v {
			i++
		}
		if j < b.len && b[j] == v {
			j++
		}
		out << v
	}
	return out
}

// is_row_selected - строка подсвечена как выбранная: при множественном
// выборе - одна из get_selection() (двоичный поиск), иначе - selected.
pub fn (lb &ListBox) is_row_selected(i int) bool {
	if lb.sel_multi {
		found, _ := lb_marks_find(lb.sel_marks, i)
		return found
	}
	return i >= 0 && i == lb.selected
}

// get_selection - индексы выбранных строк по возрастанию (копия). Без
// множественного выбора - [selected] или пусто.
pub fn (lb &ListBox) get_selection() []int {
	if lb.sel_multi {
		// sel_marks уже отсортирован; отметки за концом списка не отдаём
		return lb.sel_marks.filter(it < lb.row_total())
	}
	if lb.selected >= 0 && lb.selected < lb.row_total() {
		return [lb.selected]
	}
	return []int{}
}

// set_selection выбирает строки idxs (индексы вне списка и повторы
// пропускаются); текущей строкой становится последняя из них в порядке idxs. Без
// multi_select (или если осталась одна строка) - как set_selected первой (пусто -
// снять выбор).
pub fn (mut lb ListBox) set_selection(idxs []int) {
	n := lb.row_total()
	mut valid := idxs.filter(it >= 0 && it < n)
	if !lb.multi_select || valid.len == 0 {
		lb.set_selected(if valid.len > 0 { valid[0] } else { -1 })
		return
	}
	// текущая строка - последняя из ПЕРВЫХ вхождений: повтор уже выбранной строки
	// ([3, 0, 3]) текущую не меняет, как и раньше
	mut seen := map[int]bool{}
	mut current := -1
	for v in valid {
		if v !in seen {
			seen[v] = true
			current = v
		}
	}
	valid.sort()
	mut marks := []int{cap: valid.len}
	for v in valid {
		if marks.len == 0 || marks.last() != v {
			marks << v
		}
	}
	if marks.len == 1 {
		lb.set_selected(marks[0])
		return
	}
	lb.selected = current
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
// от якоря (Ctrl+Shift - добавить диапазон к выбранным). Все ветки сохраняют
// sel_marks отсортированным.
fn (mut lb ListBox) click_select(idx int, event &GuiEvent) {
	ctrl := lb.multi_select && event.ctrl()
	shift := lb.multi_select && event.shift()
	if shift {
		a := if lb.sel_anchor >= 0 && lb.sel_anchor < lb.row_total() {
			lb.sel_anchor
		} else if lb.selected >= 0 {
			lb.selected
		} else {
			idx
		}
		rng := lb_range(a, idx)
		lb.sel_marks = if ctrl { lb_merge_marks(lb.get_selection(), rng) } else { rng }
		lb.selected = idx
		lb.sel_multi = true
		lb.sel_anchor = a
	} else if ctrl {
		mut marks := lb.get_selection()
		found, pos := lb_marks_find(marks, idx)
		if found {
			marks.delete(pos)
		} else {
			marks.insert(pos, idx)
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
	if lb.multi_select && event.shift() && lb.sel_anchor >= 0 && lb.sel_anchor < lb.row_total() {
		lb.sel_marks = lb_range(lb.sel_anchor, lb.selected)
		lb.sel_multi = true
	} else {
		lb.reset_marks()
	}
}

pub fn (lb &ListBox) get_selected_text() string {
	if lb.selected >= 0 && lb.selected < lb.row_total() {
		return lb.item_text(lb.selected)
	}
	return ''
}

pub fn (lb &ListBox) get_selected_row_text(col int) string {
	return lb.get_row_cell_text(lb.selected, col)
}

// row_count - число строк: в виртуальном режиме - virtual_count, иначе - rows.len.
pub fn (lb &ListBox) row_count() int {
	return lb.row_total()
}

// ─── Виртуальный режим ─────────────────────────────────
// В обычном режиме каждая строка - LbRow с копией текста ячеек внутри ListBox. Для
// десятков тысяч строк это нормально, для миллиона (лог, выборка из БД, каталог с
// файлами) - лишняя копия данных и долгое заполнение. В виртуальном режиме ListBox
// хранит только число строк, а текст спрашивает у приложения колбэком - и только для
// строк, видимых в этом кадре (visible_row_range_*). Всё остальное работает как
// обычно: колонки, шапка, выбор (в том числе множественный), клавиатура, колесо,
// горизонтальный режим.
//
// Чего в виртуальном режиме нет: виджетов в ячейках (add_row_widgets и т.п.),
// user_data и своих иконок строк через set_row_icon (иконки - колбэком
// set_virtual_icons), auto_sort (сортирует приложение в on_sort и перерисовывает
// окно). Добавление строк через add_* в этом режиме не показывается.

// set_virtual включает виртуальный режим: count строк, текст ячейки (row, col)
// возвращает text_fn (col = 0 - первая колонка, она же текст однострочного списка и
// второй аргумент on_select/on_dbl_click). Строки, добавленные раньше, удаляются;
// выбор и прокрутка сбрасываются, колонки остаются. Данные поменялись при том же
// числе строк - достаточно перерисовать окно (Window.invalidate*), изменилось число
// строк - set_virtual_count. text_fn = nil - то же, что clear_virtual().
//
// Колбэк зовётся из draw() главного потока для видимых строк каждого кадра (и из
// get_selected_text, on_select, Enter): должен быть быстрым и не менять ListBox.
// Индексы приходят только из 0..count-1.
pub fn (mut lb ListBox) set_virtual(count int, text_fn fn (row int, col int) string) {
	lb.clear()
	if text_fn == unsafe { nil } {
		return
	}
	lb.is_virtual = true
	lb.virtual_count = max_int(count, 0)
	lb.virtual_text = text_fn
}

// set_virtual_icons задаёт колбэк иконки строки для виртуального режима
// (ItemIcon{} - без иконки; nil - иконок нет вовсе). Как и текст, спрашивается
// только для видимых строк.
pub fn (mut lb ListBox) set_virtual_icons(icon_fn fn (row int) ItemIcon) {
	lb.virtual_icon = icon_fn
}

// set_virtual_count меняет число строк виртуального списка, не трогая прокрутку
// (типичный случай - в лог дописали строки). Выбор за новым концом списка
// переезжает на последнюю строку, отметки множественного выбора за концом
// снимаются. В обычном режиме ничего не делает.
pub fn (mut lb ListBox) set_virtual_count(count int) {
	if !lb.is_virtual {
		return
	}
	lb.virtual_count = max_int(count, 0)
	n := lb.virtual_count
	if lb.selected >= n {
		lb.selected = n - 1
	}
	if lb.sel_anchor >= n {
		lb.sel_anchor = n - 1
	}
	// sel_marks отсортирован - отрезаем хвост, не нарушая порядка
	for lb.sel_marks.len > 0 && lb.sel_marks.last() >= n {
		lb.sel_marks.delete_last()
	}
	if lb.hover_index >= n {
		lb.hover_index = -1
	}
	lb.scroll_y = clamp_f32(lb.scroll_y, 0, lb.max_scroll())
	lb.scroll_x = clamp_f32(lb.scroll_x, 0, lb.max_scroll_x())
}

// clear_virtual выключает виртуальный режим: список снова обычный и пустой.
pub fn (mut lb ListBox) clear_virtual() {
	lb.clear()
}

// row_total - число строк в любом режиме. Всё, что считает строки, проверяет индекс
// или перебирает видимый диапазон, зовёт его, а не rows.len.
fn (lb &ListBox) row_total() int {
	return if lb.is_virtual { lb.virtual_count } else { lb.rows.len }
}

// cell_text - текст ячейки (row, col) в любом режиме ('' вне диапазона). В обычном
// режиме без колонок текст строки лежит в cells[0] (add_item кладёт его туда).
fn (lb &ListBox) cell_text(row int, col int) string {
	if row < 0 || row >= lb.row_total() || col < 0 {
		return ''
	}
	if lb.is_virtual {
		return lb.virtual_text(row, col)
	}
	if col < lb.rows[row].cells.len {
		return lb.rows[row].cells[col].text
	}
	return ''
}

// item_text - текст строки для старого однострочного API и колбэков
// (on_select, on_dbl_click, get_selected_text): первая колонка. В обычном режиме -
// зеркало items (у строки из виджетов там '').
fn (lb &ListBox) item_text(row int) string {
	if lb.is_virtual {
		return lb.cell_text(row, 0)
	}
	return if row >= 0 && row < lb.items.len { lb.items[row] } else { '' }
}

// row_icon - иконка строки в любом режиме (ItemIcon{} - нет иконки).
fn (lb &ListBox) row_icon(row int) ItemIcon {
	if row < 0 || row >= lb.row_total() {
		return ItemIcon{}
	}
	if lb.is_virtual {
		return if lb.virtual_icon != unsafe { nil } { lb.virtual_icon(row) } else { ItemIcon{} }
	}
	return lb.rows[row].icon
}

// cell_widget - виджет в ячейке (row, col) или nil (текстовая ячейка, виртуальный
// режим, индекс вне диапазона).
fn (lb &ListBox) cell_widget(row int, col int) &Widget {
	if lb.is_virtual || row < 0 || row >= lb.rows.len || col < 0 || col >= lb.rows[row].cells.len {
		return unsafe { nil }
	}
	return unsafe { lb.rows[row].cells[col].widget }
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
	return f32(f64(lb.row_total()) * f64(lb.item_height))
}

// content_width - полная ширина содержимого: горизонтальный режим - все элементы подряд; таблица - сумма ширин колонок; однострочный режим - 0 (текст по ширине окна).
fn (lb &ListBox) content_width() f32 {
	if lb.horizontal {
		return f32(f64(lb.row_total()) * f64(lb.eff_item_width()))
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
		// positive value before it reaches here
		// (vgui_list_box_set_item_height clamps via max_f32(height, 1)),
		// but a bad value here would divide by zero below, so this guard
		// covers direct field assignment from V code.
		return 0, -1
	}
	ih := f64(lb.item_height)
	first := max_int(0, int(f64(lb.scroll_y) / ih))
	last := min_int(lb.row_total() - 1, int((f64(lb.scroll_y) + f64(vp.h)) / ih) + 1)
	return first, last
}

// row_screen_y / item_screen_x - экранная Y строки i (вертикальный режим) / X
// элемента i (горизонтальный) с учётом прокрутки. Произведение и разность считаются
// в f64: в виртуальном списке на миллионы строк i*item_height выходит за 24 бита
// мантиссы f32, и соседние строки рисовались бы с ошибкой в пиксель-другой.
fn (lb &ListBox) row_screen_y(i int, vp Rect) f32 {
	return vp.y + f32(f64(i) * f64(lb.item_height) - f64(lb.scroll_y))
}

fn (lb &ListBox) item_screen_x(i int, vp Rect, iw f32) f32 {
	return vp.x + f32(f64(i) * f64(iw) - f64(lb.scroll_x))
}

// row_visible_v reports whether row i is actually painted by draw() at
// the current scroll offset — draw()'s vertical-mode loop filters on
// this directly (see below), so this is not just a mirror.
fn (lb &ListBox) row_visible_v(i int, vp Rect) bool {
	iy := lb.row_screen_y(i, vp)
	return !(iy + lb.item_height < vp.y || iy > vp.y + vp.h)
}

// visible_row_range_h is the horizontal-mode (filmstrip) counterpart of
// visible_row_range_v. Same caveat: still needs row_visible_h() per index.
fn (lb &ListBox) visible_row_range_h(vp Rect, iw f32) (int, int) {
	first := max_int(0, int(lb.scroll_x / iw))
	last := min_int(lb.row_total() - 1, int((lb.scroll_x + vp.w) / iw) + 1)
	return first, last
}

// row_visible_h reports whether row i is actually painted by draw() in
// horizontal mode at the current scroll offset — draw()'s
// horizontal-mode loop filters on this directly (see below).
fn (lb &ListBox) row_visible_h(i int, vp Rect, iw f32) bool {
	ix := lb.item_screen_x(i, vp, iw)
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

// has_scrollbar/has_hsb - нужны ли полосы. Вертикальная проверяется по высоте без полосы горизонтальной, поэтому в редком случае, когда появление одной полосы вызывает другую, возможно расхождение на пару px.
fn (lb &ListBox) has_scrollbar() bool {
	if lb.horizontal {
		return false
	}
	h := lb.bounds.h - lb.pad * 2 - lb.eff_header_h()
	return lb.content_height() > h
}

fn (lb &ListBox) has_hsb() bool {
	return lb.content_width() > lb.bounds.w - lb.pad * 2
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
	if lb.selected < 0 || lb.row_total() == 0 {
		return
	}
	vp := lb.viewport_rect()
	if lb.horizontal {
		iw := lb.eff_item_width()
		item_left := f32(f64(lb.selected) * f64(iw))
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
	item_top := f32(f64(lb.selected) * f64(lb.item_height))
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
	// f64 - как в row_screen_y: на миллионах строк f32 ошибся бы с номером строки
	rel_y := f64(my) - f64(vp.y) + f64(lb.scroll_y)
	idx := int(math.floor(rel_y / f64(lb.item_height)))
	if idx >= 0 && idx < lb.row_total() {
		return idx
	}
	return -1
}

fn (lb &ListBox) hit_item_h(mx f32) int {
	vp := lb.viewport_rect()
	rel_x := f64(mx) - f64(vp.x) + f64(lb.scroll_x)
	idx := int(math.floor(rel_x / f64(lb.eff_item_width())))
	if idx >= 0 && idx < lb.row_total() {
		return idx
	}
	return -1
}

// hit_sort_col - индекс сортируемой колонки (show_sort), над заголовком которой
// курсор, либо -1. Щёлкнуть для сортировки можно по всему заголовку, а не только по
// стрелке (как в проводниках и таблицах ОС); границы колонок для изменения ширины
// вызывающий проверяет раньше (hit_col_border), так что они сюда не доходят.
// Заголовки правее видимой области (над вертикальной полосой прокрутки) не в счёт.
fn (lb &ListBox) hit_sort_col(mx f32, my f32) int {
	if !lb.show_header || lb.columns.len == 0 {
		return -1
	}
	hdr_y := lb.bounds.y + lb.pad
	if my < hdr_y || my > hdr_y + lb.header_height {
		return -1
	}
	vp := lb.viewport_rect()
	if mx < vp.x || mx >= vp.x + vp.w {
		return -1
	}
	mut cx := vp.x - lb.scroll_x
	for ci in 0 .. lb.columns.len {
		col := lb.columns[ci]
		if mx >= cx && mx < cx + col.width {
			return if col.show_sort { ci } else { -1 }
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
	if lb.on_select != unsafe { nil } && lb.selected >= 0 && lb.selected < lb.row_total() {
		text := lb.item_text(lb.selected)
		lb.on_select(lb.selected, text)
	}
}

// toggle_sort - цикл none -> asc -> desc -> none для колонки; остальным сбрасывает индикатор,
// при auto_sort переставляет строки (resort) и зовёт on_sort.
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
	if lb.auto_sort {
		lb.resort()
	}
	if lb.on_sort != unsafe { nil } {
		lb.on_sort(col, new_dir)
	}
}

// ─── Header ────────────────────────────────────────────

// draw_header рисует шапку колонок (тот же вид, что у TableView.draw_header):
//   - полоса фона на всю внутреннюю ширину (и над вертикальной полосой прокрутки) со
//     скруглёнными верхними углами (tbl_fill_header_band) и линией header_border снизу;
//   - заголовок колонки - обычным шрифтом (синтезированный SDL «жирный» грубо
//     утолщает и расширяет буквы), с выравниванием, как у данных колонки;
//   - сортируемая колонка под курсором подсвечивается целиком - щёлкнуть можно по
//     всему заголовку (hit_sort_col);
//   - индикатор сортировки справа: треугольник по направлению у отсортированной
//     колонки; у неотсортированной - бледный ромб только при наведении (подсказка,
//     что колонку можно отсортировать), а не постоянно, чтобы шапка не пестрела;
//   - между колонками - короткие чёрточки цвета сетки (tbl_header_sep_inset сверху и
//     снизу): видно, где граница, которую можно тянуть;
//   - при наведении на границу или её перетаскивании - акцентная полоса.
fn (lb &ListBox) draw_header(mut ctx RenderContext, vp Rect, font voidptr) {
	hdr_y := lb.bounds.y + lb.pad
	band := Rect{lb.bounds.x + lb.pad, hdr_y, lb.bounds.w - lb.pad * 2, lb.header_height}
	hdr_tc := ctx.theme.eff_lb_header_text()
	tbl_fill_header_band(mut ctx, band, ctx.theme.eff_lb_header_bg(), tbl_header_radius(ctx,
		lb.pad))
	ctx.fill_rect(Rect{band.x, band.y + band.h - 1, band.w, 1}, ctx.theme.eff_lb_header_border())

	sep_h := max_f32(lb.header_height - tbl_header_sep_inset * 2, 1)
	sep_y := hdr_y + (lb.header_height - sep_h) * 0.5
	titles_r := Rect{vp.x, hdr_y, vp.w, lb.header_height}
	ctx.push_clip(titles_r)
	mut hx := vp.x - lb.scroll_x
	for ci in 0 .. lb.columns.len {
		col := lb.columns[ci]
		if hx + col.width > titles_r.x && hx < titles_r.x + titles_r.w {
			hovered := ci == lb.sort_hover_col
			if hovered {
				// лёгкая подсветка цветом текста шапки: видна и на светлой, и на тёмной теме
				ctx.fill_rect(Rect{hx, hdr_y, col.width, lb.header_height - 1}, hdr_tc.with_alpha(18))
			}

			// заголовок: у сортируемой колонки справа место под индикатор
			sort_w := if col.show_sort { lb_sort_btn_w } else { f32(0) }
			title_r := Rect{hx, hdr_y, col.width - sort_w, lb.header_height}
			tbl_draw_text_aligned(mut ctx, col.title, title_r, col.align, hdr_tc, font)

			if col.show_sort {
				lb.draw_sort_indicator(mut ctx, col.sort_dir, hx + col.width - lb_sort_btn_w - 2,
					hdr_y + lb.header_height * 0.5, hovered)
			}

			// чёрточка-разделитель у правой границы колонки
			ctx.fill_rect(Rect{hx + col.width - 1, sep_y, 1, sep_h}, ctx.theme.eff_lb_grid())
		}
		hx += col.width
	}
	ctx.pop_clip()

	// ── Column resize indicator ──
	mark_col := if lb.col_resizing { lb.resize_col } else { lb.resize_hover_col }
	if mark_col >= 0 && mark_col < lb.columns.len {
		mut rx := vp.x - lb.scroll_x
		for ci in 0 .. mark_col + 1 {
			rx += lb.columns[ci].width
		}
		c := if lb.col_resizing { ctx.theme.accent } else { ctx.theme.accent.with_alpha(120) }
		ctx.fill_rect(Rect{rx - 1, hdr_y, 2, lb.header_height}, c)
	}
}

// draw_sort_indicator рисует индикатор сортировки в квадрате шириной lb_sort_btn_w
// с левым краем x и центром по вертикали y: треугольник вверх (asc) или вниз (desc);
// для none_ - бледный ромб, но только при наведении (hovered). Отсортированная
// колонка под курсором - акцентным цветом.
fn (lb &ListBox) draw_sort_indicator(mut ctx RenderContext, dir LbSortDir, x f32, y f32, hovered bool) {
	mid_x := x + lb_sort_btn_w * 0.5
	as_ := f32(3) // полувысота треугольника
	arrow_c := if hovered { ctx.theme.accent } else { ctx.theme.text_secondary }
	match dir {
		.asc {
			ctx.fill_triangle(mid_x, y - as_, mid_x - as_, y + as_, mid_x + as_, y + as_, arrow_c)
		}
		.desc {
			ctx.fill_triangle(mid_x, y + as_, mid_x - as_, y - as_, mid_x + as_, y - as_, arrow_c)
		}
		.none_ {
			if hovered {
				faint := ctx.theme.text_secondary.with_alpha(120)
				ctx.fill_triangle(mid_x, y - as_, mid_x - as_ * 0.6, y, mid_x + as_ * 0.6, y,
					faint)
				ctx.fill_triangle(mid_x, y + as_, mid_x - as_ * 0.6, y, mid_x + as_ * 0.6, y,
					faint)
			}
		}
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
			ix := lb.item_screen_x(i, vp, iw)
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
		iy := lb.row_screen_y(i, vp)
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
	en := ctx.is_enabled(lb.enabled)
	if !lb.visible {
		return
	}

	if !ctx.is_in_clip(lb.bounds) {
		return
	}
	// Встроенные виджеты (ячейки, редакторы) неактивны вместе с владельцем;
	// всё содержимое приглушается вуалью поверх (enabled.v)
	ctx.begin_disabled(lb.enabled)
	defer {
		ctx.end_disabled(lb.enabled)
		if !en {
			ctx.draw_disabled_veil(lb.bounds, ctx.theme.border_radius)
		}
	}

	if en {
		ctx.focus.register_list_box(&lb, lb.focus_group)
	} else {
		ctx.focus_block(&lb)
	}

	should_focus := ctx.focus.is_focused(unsafe { &lb })
	if lb.focused && !should_focus {
		lb.focused = false
	} else if !lb.focused && should_focus {
		lb.focused = true
	}

	target_focus := if lb.focused && en { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if lb.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('listbox', lb.bounds.expanded(1))
	}

	lb.scroll_y = clamp_f32(lb.scroll_y, 0, lb.max_scroll())
	lb.scroll_x = clamp_f32(lb.scroll_x, 0, lb.max_scroll_x())

	rad := ctx.theme.border_radius
	bg := if en { ctx.theme.eff_lb_bg() } else { ctx.theme.eff_lb_bg().darken(0.05) }
	ctx.fill_rounded_rect(lb.bounds, bg, rad)

	bc := ctx.theme.eff_lb_border().blend(ctx.theme.input_focus, lb.focus_anim.value)
	ctx.draw_rounded_rect(lb.bounds, bc, rad)

	ctx.draw_focus_ring(lb.bounds, rad, lb.focus_anim.value)

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	vp := lb.viewport_rect()

	// ── Header ──
	if lb.show_header && lb.columns.len > 0 {
		lb.draw_header(mut ctx, vp, font)
	}

	// ── Rows / Items ──
	ctx.push_clip(vp)

	// В обоих режимах перебираются только строки видимого диапазона, поэтому
	// виртуальный список на миллион строк рисуется так же быстро, как на десять.
	// Строка/ячейка берётся через row_total/cell_widget/cell_text/item_text - они
	// одинаково работают в обычном и виртуальном режиме.
	total := lb.row_total()
	if lb.horizontal {
		// Horizontal (filmstrip) mode — items laid out left to right
		iw := lb.eff_item_width()
		ih := vp.h
		h_first, h_last := lb.visible_row_range_h(vp, iw)
		for i := h_first; i <= h_last; i++ {
			if i < 0 || i >= total || !lb.row_visible_h(i, vp, iw) {
				continue
			}
			ix := lb.item_screen_x(i, vp, iw)
			is_sel := lb.is_row_selected(i)
			is_hov := i == lb.hover_index && lb.hovered
			item_r := Rect{ix, vp.y, iw, ih}
			if is_sel {
				ctx.fill_rect(item_r, ctx.theme.eff_lb_row_selected().with_alpha(180))
			} else if is_hov {
				ctx.fill_rect(item_r, ctx.theme.eff_lb_row_hover().with_alpha(100))
			}
			tc := if is_sel { ctx.theme.eff_lb_row_sel_text() } else { ctx.theme.eff_lb_row_text() }
			// Виджет первой ячейки (bounds ему выставил arrange()) или текст элемента.
			// Текст: у первой ячейки, а у строк без ячеек - зеркало items (item_text).
			mut w := lb.cell_widget(i, 0)
			if unsafe { w != nil } {
				ctx.draw_child(mut w)
			} else {
				mut text := lb.cell_text(i, 0)
				if text.len == 0 && !lb.is_virtual && lb.rows[i].cells.len == 0 {
					text = lb.item_text(i)
				}
				if text.len > 0 {
					ty := vp.y + (ih - fh) * 0.5
					dx := lb.draw_row_icon(mut ctx, i, ix + lb_cell_pad, vp.y, ih, tc)
					ctx.draw_text_with_font(text, ix + lb_cell_pad + dx, ty, tc, font)
				}
			}
			// Separator between items
			if i < total - 1 {
				ctx.fill_rect(Rect{ix + iw - 1, vp.y, 1, ih},
					ctx.theme.eff_lb_grid().with_alpha(lb_grid_color_a))
			}
		}
	} else {
		v_first, v_last := lb.visible_row_range_v(vp)
		for i := v_first; i <= v_last; i++ {
			if i < 0 || i >= total || !lb.row_visible_v(i, vp) {
				continue
			}
			iy := lb.row_screen_y(i, vp)

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
				// Multi-column: draw each cell. У обычной строки ячеек может быть
				// меньше колонок (строка из widget_tree_test и т.п.) - лишние колонки
				// у неё пустые.
				n_cells := if lb.is_virtual { lb.columns.len } else { lb.rows[i].cells.len }
				mut cx := vp.x - lb.scroll_x
				for ci in 0 .. lb.columns.len {
					col_w := lb.columns[ci].width
					if ci < n_cells && cx + col_w > vp.x && cx < vp.x + vp.w {
						cell_r := Rect{cx, iy, col_w, lb.item_height}
						mut w := lb.cell_widget(i, ci)
						text := if unsafe { w == nil } { lb.cell_text(i, ci) } else { '' }
						if unsafe { w != nil } {
							// Custom widget — bounds set in arrange()
							ctx.draw_child(mut w)
						} else if text.len > 0 {
							// Text cell; иконка строки - в первой колонке слева,
							// текст выравнивается в оставшейся части клетки
							align := lb.columns[ci].align
							mut text_r := cell_r
							if ci == 0 {
								dx := lb.draw_row_icon(mut ctx, i, cx + lb_cell_pad, iy,
									lb.item_height, tc)
								text_r = Rect{cx + dx, iy, col_w - dx, lb.item_height}
							}
							tbl_draw_text_aligned(mut ctx, text, text_r, align, tc, font)
						}
						// Grid line
						if lb.show_grid && ci < lb.columns.len - 1 {
							ctx.fill_rect(Rect{cx + col_w - 1, iy, 1, lb.item_height},
								ctx.theme.eff_lb_grid().with_alpha(lb_grid_color_a))
						}
					}
					cx += col_w
				}
			} else {
				// Single-column: текст строки - item_text (зеркало items или колбэк)
				if lb.is_virtual || i < lb.items.len {
					text := lb.item_text(i)
					ty := iy + (lb.item_height - fh) * 0.5
					dx := lb.draw_row_icon(mut ctx, i, vp.x + 6, iy, lb.item_height, tc)
					ctx.draw_text_with_font(text, vp.x + 6 + dx, ty, tc, font)
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
								text := lb.item_text(idx)
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
							text := lb.item_text(idx)
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
				if lb.row_total() > 0 {
					lb.selected = 0
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				if lb.row_total() > 0 {
					lb.selected = lb.row_total() - 1
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if tv_is_pageup_key(event.keycode, event.scancode) {
				if lb.row_total() > 0 {
					visible_count := max_int(1, int(lb.viewport_rect().h / lb.item_height))
					lb.selected = max_int(0, lb.selected - visible_count)
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}
			if tv_is_pagedown_key(event.keycode, event.scancode) {
				if lb.row_total() > 0 {
					visible_count := max_int(1, int(lb.viewport_rect().h / lb.item_height))
					lb.selected = min_int(lb.row_total() - 1, lb.selected + visible_count)
					lb.ensure_visible()
					lb.key_select(event)
					lb.fire_select()
				}
				return true
			}

			match event.keycode {
				// // Стрелки зацикливают список (с первой на последнюю и обратно). В горизонтальном режиме работают Left/Right.
				sdl_k_up {
					if !lb.horizontal && lb.row_total() > 0 {
						lb.selected = if lb.selected <= 0 {
							lb.row_total() - 1
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
					if !lb.horizontal && lb.row_total() > 0 {
						lb.selected = if lb.selected >= lb.row_total() - 1 {
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
					if lb.horizontal && lb.row_total() > 0 {
						lb.selected = if lb.selected <= 0 {
							lb.row_total() - 1
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
					if lb.horizontal && lb.row_total() > 0 {
						lb.selected = if lb.selected >= lb.row_total() - 1 {
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
					if lb.selected >= 0 && lb.selected < lb.row_total() {
						if lb.on_dbl_click != unsafe { nil } {
							text := lb.item_text(lb.selected)
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
		iy := lb.row_screen_y(i, vp)
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
		ix := lb.item_screen_x(i, vp, iw)
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
