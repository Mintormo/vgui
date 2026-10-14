// Файл: ./table.v
module vgui

// Шапка файла.
// TableView - таблица в стиле электронной таблицы: колонки с заголовками, строки
// ячеек, выделение ячейки или целой строки, встроенное (inline) редактирование
// текста ячейки, изменение ширины колонок и высоты строк мышью, прокрутка по обеим
// осям со своими полосами прокрутки, загрузка из CSV.
//
// Как файл связан с остальной библиотекой:
//   - раскладка: bounds виджету выдаёт контейнер (Layouted/Arrangeable в
//     widget_tree.v), сам виджет размер не вычисляет; measure() - layout_measure.v;
//   - отрисовка: draw() рисует всё за один проход, клипируя содержимое через
//     ctx.push_clip/pop_clip; цвета берутся из темы (ctx.theme.eff_tv_*), если у
//     виджета не задан свой (a == 0 означает «брать из темы»);
//   - события: handle_event() возвращает true, если событие поглощено;
//   - фокус: поле focus_group и FocusKind в focus.v; анимация рамки - focus_anim;
//   - undo/redo редактируемой ячейки - UndoHistory[RuneSnap] (общий для виджетов);
//   - C-ABI: функции vgui_table_* живут в vgui_capi, здесь только методы.
//
// Модель координат. Прокрутка хранится в scroll_x/scroll_y как смещение содержимого
// (данных) относительно viewport'а в логических пикселях. Позиция колонки/строки в
// «пространстве данных» считается суммой ширин/высот предыдущих (col_x/row_y), на
// экран переводится вычитанием scroll_* и прибавлением data_origin_x/y.
import os

// ═══════════════════════════════════════════════════════
// TableView — spreadsheet-style table widget
// ═══════════════════════════════════════════════════════

// CellAlign - выравнивание текста в ячейке. Приоритет при отрисовке: ячейка ->
// колонка -> строка -> .left (см. eff_cell_align). Значение default_ (с
// подчёркиванием, т.к. default - ключевое слово V) означает «не задано здесь,
// смотри уровнем выше».
pub enum CellAlign {
	default_ // use column → row → left fallback
	left
	center
	right
}

// Колонка: заголовок, текущая ширина и нижняя граница ширины (min_w), ниже которой
// колонку нельзя сузить ни мышью, ни set_column_width.
struct TableColumn {
mut:
	title string
	width f32
	min_w f32       = 30
	align CellAlign = .default_
}

// Ячейка. Нулевой Color (a == 0) в color/bg_color значит «цвет не задан, брать
// из темы/виджета».
struct TableCell {
mut:
	text     string
	editable bool      = true // per-cell override; effective only when table.editable
	align    CellAlign = .default_
	color    Color     = Color{0, 0, 0, 0} // per-cell text color
	bg_color Color     = Color{0, 0, 0, 0} // per-cell background color
}

// Строка: ячейки (по одной на колонку на момент add_row), выравнивание по умолчанию
// для строки и своя высота.
struct TableRow {
mut:
	cells  []TableCell
	align  CellAlign = .default_
	height f32 // 0 = use default row_height
}

// Константы геометрии: tbl_sb_w - толщина полос прокрутки; tbl_resize_zone -
// полуширина «горячей зоны» у границы колонки/строки, где мышь захватывает ресайз;
// tbl_cell_pad - горизонтальный отступ текста от краёв ячейки;
// tbl_max_edit_undo - глубина undo при редактировании одной ячейки.
const tbl_sb_w = f32(12)
const tbl_resize_zone = f32(5)
const tbl_cell_pad = f32(6)
const tbl_max_edit_undo = 50

// TableView - сама таблица. Все поля pub mut, но обычно их меняют методами ниже.
// Примечания к полям:
//   sel_row/sel_col - выделенная ячейка (-1 = нет выделения);
//   hover_row       - строка под курсором (для подсветки), -1 если мышь вне;
//   editing/edit_*  - состояние inline-редактора: какая ячейка, буфер рун, позиция
//                     курсора, горизонтальная прокрутка текста, границы выделения
//                     (edit_sel_a/b; -1 = нет), история undo;
//   *_resizing/resize_* - состояние перетаскивания границы колонки/строки: что тянем
//                     и исходные координаты мыши и размер в момент нажатия;
//   vsb_*/hsb_*     - состояние полос прокрутки (наведение, перетаскивание и
//                     исходные координаты/прокрутка в момент нажатия на ползунок).
@[heap]
pub struct TableView {
pub mut:
	type_tag int = kind_table_view // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel       bool = true
	bounds      Rect
	columns     []TableColumn
	rows        []TableRow
	visible     bool = true
	enabled     bool = true
	focused     bool
	hovered     bool
	focus_anim  Anim = anim_smooth(anim_tau_focus)
	focus_group int
	// Behavior
	editable            bool // global edit toggle
	show_row_numbers    bool
	select_full_row     bool // if true, whole row is selected instead of single cell
	highlight_hover_row bool = true
	// Sizing
	header_height  f32 = 26
	row_height     f32 = 24
	min_row_height f32 = 16 // NEW: minimum height for any row (applies to default and per-row)
	row_num_width  f32 = 40
	pad            f32 = 2
	scroll_speed   f32 = 30
	// Selection
	sel_col   int = -1
	sel_row   int = -1
	hover_row int = -1
	// Scroll
	scroll_x f32
	scroll_y f32
	// Colors (0 = theme)
	header_bg    Color = Color{0, 0, 0, 0}
	header_text  Color = Color{0, 0, 0, 0}
	cell_bg      Color = Color{0, 0, 0, 0}
	cell_text    Color = Color{0, 0, 0, 0}
	grid_color   Color = Color{0, 0, 0, 0}
	sel_bg       Color = Color{0, 0, 0, 0}
	sel_text     Color = Color{0, 0, 0, 0}
	hover_bg     Color = Color{0, 0, 0, 0}
	row_num_bg   Color = Color{0, 0, 0, 0}
	row_num_text Color = Color{0, 0, 0, 0}
	// Colors for non-editable cells
	readonly_bg   Color = Color{0, 0, 0, 0}
	readonly_text Color = Color{0, 0, 0, 0}
	// Inline editing
	editing       bool
	edit_row      int = -1
	edit_col      int = -1
	edit_buf      []rune
	edit_cur      int
	edit_scroll_x f32
	edit_sel_a    int                   = -1
	edit_sel_b    int                   = -1
	edit_history  UndoHistory[RuneSnap] = UndoHistory[RuneSnap]{
		limit: tbl_max_edit_undo
	}
	// Column resize drag
	col_resizing   bool
	resize_col     int = -1
	resize_start_x f32
	resize_start_w f32
	// Row resize drag
	row_resizing   bool
	resize_row     int = -1
	resize_start_y f32
	resize_start_h f32
	// Scrollbar drag
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
	// Callbacks
	on_select fn (int, int)         = unsafe { nil } // (row, col)
	on_change fn (int, int, string) = unsafe { nil } // (row, col, new_text)
}

// ─── Constructors ──────────────────────────────────────

// Конструктор: пустая таблица без колонок. Пока колонок нет, draw() и
// handle_event() ничего не делают.
pub fn table_view() &TableView {
	return &TableView{}
}

// ─── Public API ────────────────────────────────────────

// Добавляет колонку; ширина не меньше 30 (min_w по умолчанию). Уже существующим
// строкам ячейки НЕ добавляются, поэтому колонки нужно создавать до add_row.
pub fn (mut t TableView) add_column(title string, width f32) {
	t.columns << TableColumn{
		title: title
		width: max_f32(width, 30)
	}
}

pub fn (mut t TableView) add_column_aligned(title string, width f32, align CellAlign) {
	t.columns << TableColumn{
		title: title
		width: max_f32(width, 30)
		align: align
	}
}

// NEW: Add column with explicit minimum width
pub fn (mut t TableView) add_column_with_min(title string, width f32, min_w f32) {
	t.columns << TableColumn{
		title: title
		width: max_f32(width, min_w)
		min_w: max_f32(min_w, 10)
	}
}

// NEW: Set minimum width for a column
pub fn (mut t TableView) set_column_min_width(col int, min_w f32) {
	if col >= 0 && col < t.columns.len {
		t.columns[col].min_w = max_f32(min_w, 10)
		// Enforce: if current width < new min, expand
		if t.columns[col].width < t.columns[col].min_w {
			t.columns[col].width = t.columns[col].min_w
		}
	}
}

// NEW: Get minimum width of a column
pub fn (t &TableView) get_column_min_width(col int) f32 {
	if col >= 0 && col < t.columns.len {
		return t.columns[col].min_w
	}
	return 30
}

// NEW: Set column width (clamped to min_w)
pub fn (mut t TableView) set_column_width(col int, w f32) {
	if col >= 0 && col < t.columns.len {
		t.columns[col].width = max_f32(w, t.columns[col].min_w)
	}
}

// NEW: Get column width
pub fn (t &TableView) get_column_width(col int) f32 {
	if col >= 0 && col < t.columns.len {
		return t.columns[col].width
	}
	return 0
}

// NEW: Set global minimum row height
pub fn (mut t TableView) set_min_row_height(h f32) {
	t.min_row_height = max_f32(h, 8)
}

// NEW: Get global minimum row height
pub fn (t &TableView) get_min_row_height() f32 {
	return t.min_row_height
}

// Добавляет строку: на каждую существующую колонку создаётся ячейка; недостающие
// тексты заменяются пустой строкой, лишние отбрасываются.
pub fn (mut t TableView) add_row(texts []string) {
	mut cells := []TableCell{cap: t.columns.len}
	for i in 0 .. t.columns.len {
		text := if i < texts.len { texts[i] } else { '' }
		cells << TableCell{
			text: text
		}
	}
	t.rows << TableRow{
		cells: cells
	}
}

// Методы set_cell*/get_cell*/set_row_*/set_column_* ниже молча игнорируют
// индексы вне диапазона (get_* возвращают нейтральное значение: '', false,
// прозрачный цвет). Ни один из сеттеров не инвалидирует кадр - в собственном цикле
// после изменений нужно вызвать Window.invalidate*.
pub fn (mut t TableView) set_cell(row int, col int, text string) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.rows[row].cells[col].text = text
	}
}

pub fn (t &TableView) get_cell(row int, col int) string {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		return t.rows[row].cells[col].text
	}
	return ''
}

pub fn (mut t TableView) set_cell_editable(row int, col int, val bool) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.rows[row].cells[col].editable = val
	}
}

pub fn (mut t TableView) set_cell_align(row int, col int, align CellAlign) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.rows[row].cells[col].align = align
	}
}

pub fn (mut t TableView) set_cell_color(row int, col int, c Color) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.rows[row].cells[col].color = c
	}
}

pub fn (mut t TableView) set_cell_bg_color(row int, col int, c Color) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.rows[row].cells[col].bg_color = c
	}
}

pub fn (t &TableView) get_cell_bg_color(row int, col int) Color {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		return t.rows[row].cells[col].bg_color
	}
	return Color{0, 0, 0, 0}
}

pub fn (t &TableView) get_cell_color(row int, col int) Color {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		return t.rows[row].cells[col].color
	}
	return Color{0, 0, 0, 0}
}

pub fn (t &TableView) get_cell_editable(row int, col int) bool {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		return t.rows[row].cells[col].editable
	}
	return false
}

pub fn (mut t TableView) set_row_align(row int, align CellAlign) {
	if row >= 0 && row < t.rows.len {
		t.rows[row].align = align
	}
}

pub fn (mut t TableView) set_column_align(col int, align CellAlign) {
	if col >= 0 && col < t.columns.len {
		t.columns[col].align = align
	}
}

pub fn (mut t TableView) set_row_height_at(row int, h f32) {
	if row >= 0 && row < t.rows.len {
		t.rows[row].height = max_f32(h, t.min_row_height)
	}
}

// Удаляет все строки, отменяет редактирование (без commit и без on_change), сбрасывает
// выделение и прокрутку. Колонки остаются.
pub fn (mut t TableView) clear_rows() {
	t.cancel_edit()
	t.rows.clear()
	t.sel_row = -1
	t.sel_col = -1
	t.scroll_x = 0
	t.scroll_y = 0
}

pub fn (t &TableView) row_count() int {
	return t.rows.len
}

pub fn (t &TableView) col_count() int {
	return t.columns.len
}

// Возвращает (row, col) выделенной ячейки; (-1, -1), если выделения нет.
pub fn (t &TableView) get_selected() (int, int) {
	return t.sel_row, t.sel_col
}

pub fn (t &TableView) get_selected_row() int {
	return t.sel_row
}

pub fn (t &TableView) get_selected_col() int {
	return t.sel_col
}

pub fn (t &TableView) get_selected_text() string {
	return t.get_cell(t.sel_row, t.sel_col)
}

pub fn (t &TableView) has_selection() bool {
	return t.sel_row >= 0 && t.sel_col >= 0
}

// Программно выделяет ячейку (не вызывает on_select и не прокручивает к ней).
// Некорректные индексы игнорируются.
pub fn (mut t TableView) set_selected(row int, col int) {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		t.sel_row = row
		t.sel_col = col
	}
}

pub fn (mut t TableView) clear_selection() {
	t.sel_row = -1
	t.sel_col = -1
}

// Подгоняет ширину каждой колонки под самый широкий текст (заголовок или ячейка) плюс
// отступы и 4 px запаса, но не меньше min_w. Заголовок измеряется обычным, а не
// жирным шрифтом, поэтому для жирного заголовка запас может оказаться тесноват.
// Нужен ctx, так как ширина текста известна только отрисовщику (шрифты).
pub fn (mut t TableView) auto_fit_columns(ctx &RenderContext) {
	font := ctx.get_font_immut(.regular, 0)
	for ci in 0 .. t.columns.len {
		mut max_w := ctx.measure_text_with_font(t.columns[ci].title, font).x + tbl_cell_pad * 2
		for ri in 0 .. t.rows.len {
			cw := ctx.measure_text_with_font(t.rows[ri].cells[ci].text, font).x + tbl_cell_pad * 2
			if cw > max_w {
				max_w = cw
			}
		}
		t.columns[ci].width = max_f32(max_w + 4, t.columns[ci].min_w)
	}
}

// ─── Geometry helpers ──────────────────────────────────

// Эффективная высота строки: своя (если задана > 0) или общая row_height, но
// всегда не меньше min_row_height.
fn (t &TableView) eff_row_height(row int) f32 {
	if row >= 0 && row < t.rows.len && t.rows[row].height > 0 {
		return max_f32(t.rows[row].height, t.min_row_height)
	}
	return max_f32(t.row_height, t.min_row_height)
}

// Левый верхний угол области данных (под заголовком и правее колонки номеров
// строк) в координатах окна. Прокрутка сюда не входит.
fn (t &TableView) data_origin_x() f32 {
	return t.bounds.x + t.pad + (if t.show_row_numbers {
		t.row_num_width
	} else {
		f32(0)
	})
}

fn (t &TableView) data_origin_y() f32 {
	return t.bounds.y + t.pad + t.header_height
}

fn (t &TableView) total_cols_width() f32 {
	mut w := f32(0)
	for c in t.columns {
		w += c.width
	}
	return w
}

fn (t &TableView) total_rows_height() f32 {
	mut h := f32(0)
	for ri in 0 .. t.rows.len {
		h += t.eff_row_height(ri)
	}
	return h
}

// Видимая область данных: от начала данных до края bounds минус pad и полосы
// прокрутки (если они сейчас показаны). Шириной/высотой никогда не бывает < 0.
fn (t &TableView) viewport_rect() Rect {
	ox := t.data_origin_x()
	oy := t.data_origin_y()
	mut w := t.bounds.x + t.bounds.w - t.pad - ox
	mut h := t.bounds.y + t.bounds.h - t.pad - oy
	if t.has_vsb() {
		w -= tbl_sb_w
	}
	if t.has_hsb() {
		h -= tbl_sb_w
	}
	return Rect{ox, oy, max_f32(w, 0), max_f32(h, 0)}
}

// Максимально допустимая прокрутка по осям: размер всех данных минус размер viewport'а.
fn (t &TableView) max_scroll_x() f32 {
	vp := t.viewport_rect()
	return max_f32(0, t.total_cols_width() - vp.w)
}

fn (t &TableView) max_scroll_y() f32 {
	vp := t.viewport_rect()
	return max_f32(0, t.total_rows_height() - vp.h)
}

// Нужна ли полоса прокрутки. Полосы зависят друг от друга: вертикальная съедает
// ширину, и из-за неё может понадобиться горизонтальная, и наоборот. Раньше каждая
// сравнивалась с областью без вычета соседней, и содержимое, не влезающее только из-за
// соседней полосы, оставалось без полосы. viewport_rect здесь звать нельзя (он сам
// зовёт has_vsb/has_hsb), поэтому область считается напрямую.
fn (t &TableView) scrollbars_needed() (bool, bool) {
	full_w := t.bounds.x + t.bounds.w - t.pad - t.data_origin_x()
	full_h := t.bounds.y + t.bounds.h - t.pad - t.data_origin_y()
	content_w := t.total_cols_width()
	content_h := t.total_rows_height()
	mut need_v := content_h > full_h
	need_h := content_w > full_w - (if need_v { tbl_sb_w } else { 0 })
	if need_h && !need_v {
		need_v = content_h > full_h - tbl_sb_w
	}
	return need_v, need_h
}

fn (t &TableView) has_vsb() bool {
	need_v, _ := t.scrollbars_needed()
	return need_v
}

fn (t &TableView) has_hsb() bool {
	_, need_h := t.scrollbars_needed()
	return need_h
}

// Смещение левого края колонки / верхнего края строки внутри данных (сумма
// размеров предыдущих; без прокрутки). Сложность O(n) на вызов.
fn (t &TableView) col_x(col int) f32 {
	mut x := f32(0)
	for i in 0 .. col {
		x += t.columns[i].width
	}
	return x
}

fn (t &TableView) row_y(row int) f32 {
	mut y := f32(0)
	for i in 0 .. row {
		y += t.eff_row_height(i)
	}
	return y
}

// ─── Effective alignment ───────────────────────────────

// Итоговое выравнивание текста ячейки по цепочке ячейка -> колонка -> строка -> left.
fn (t &TableView) eff_cell_align(row int, col int) TextAlign {
	if row >= 0 && row < t.rows.len && col >= 0 && col < t.columns.len {
		ca := t.rows[row].cells[col].align
		if ca != .default_ {
			return tbl_ca_to_ta(ca)
		}
	}
	if col >= 0 && col < t.columns.len {
		ca := t.columns[col].align
		if ca != .default_ {
			return tbl_ca_to_ta(ca)
		}
	}
	if row >= 0 && row < t.rows.len {
		ra := t.rows[row].align
		if ra != .default_ {
			return tbl_ca_to_ta(ra)
		}
	}
	return .left
}

fn tbl_ca_to_ta(ca CellAlign) TextAlign {
	return match ca {
		.left { TextAlign.left }
		.center { TextAlign.center }
		.right { TextAlign.right }
		.default_ { TextAlign.left }
	}
}

// ─── Effective colors ──────────────────────────────────

// Группа eff_*: «эффективный» цвет - собственное значение виджета, если оно задано
// (альфа > 0), иначе цвет темы (ctx.theme.eff_tv_*, общие с TreeView). Для
// readonly_bg/readonly_text темы нет: возвращается прозрачный цвет, т.е. «ничего
// не рисовать/не менять».
fn (t &TableView) eff_header_bg(ctx &RenderContext) Color {
	if t.header_bg.a > 0 {
		return t.header_bg
	}
	return ctx.theme.eff_tv_header_bg()
}

fn (t &TableView) eff_header_text(ctx &RenderContext) Color {
	if t.header_text.a > 0 {
		return t.header_text
	}
	return ctx.theme.eff_tv_header_text()
}

fn (t &TableView) eff_cell_bg(ctx &RenderContext) Color {
	if t.cell_bg.a > 0 {
		return t.cell_bg
	}
	return ctx.theme.eff_tv_row_bg()
}

fn (t &TableView) eff_cell_text(ctx &RenderContext) Color {
	if t.cell_text.a > 0 {
		return t.cell_text
	}
	return ctx.theme.eff_tv_row_text()
}

fn (t &TableView) eff_grid_color(ctx &RenderContext) Color {
	if t.grid_color.a > 0 {
		return t.grid_color
	}
	return ctx.theme.eff_tv_grid()
}

fn (t &TableView) eff_sel_bg(ctx &RenderContext) Color {
	if t.sel_bg.a > 0 {
		return t.sel_bg
	}
	return ctx.theme.eff_tv_row_selected()
}

fn (t &TableView) eff_sel_text(ctx &RenderContext) Color {
	if t.sel_text.a > 0 {
		return t.sel_text
	}
	return ctx.theme.eff_tv_row_sel_text()
}

fn (t &TableView) eff_hover_bg(ctx &RenderContext) Color {
	if t.hover_bg.a > 0 {
		return t.hover_bg
	}
	return ctx.theme.eff_tv_row_hover()
}

fn (t &TableView) eff_row_num_bg(ctx &RenderContext) Color {
	if t.row_num_bg.a > 0 {
		return t.row_num_bg
	}
	return ctx.theme.eff_tv_rownum_bg()
}

fn (t &TableView) eff_row_num_text(ctx &RenderContext) Color {
	if t.row_num_text.a > 0 {
		return t.row_num_text
	}
	return ctx.theme.eff_tv_rownum_text()
}

fn (t &TableView) eff_readonly_bg(_ &RenderContext) Color {
	if t.readonly_bg.a > 0 {
		return t.readonly_bg
	}
	return Color{0, 0, 0, 0}
}

fn (t &TableView) eff_readonly_text(_ &RenderContext) Color {
	if t.readonly_text.a > 0 {
		return t.readonly_text
	}
	return Color{0, 0, 0, 0}
}

// ─── Hit test ──────────────────────────────────────────

// Какая ячейка под точкой (mx, my) окна. Возвращает (row, col); если точка вне
// viewport'а - (-1, -1); если внутри, но за последней строкой/колонкой - -1 в
// соответствующей позиции (часть может быть валидной, другая нет).
fn (t &TableView) hit_cell(mx f32, my f32) (int, int) {
	vp := t.viewport_rect()
	if !vp.contains(mx, my) {
		return -1, -1
	}
	rel_x := mx - vp.x + t.scroll_x
	rel_y := my - vp.y + t.scroll_y
	mut col := -1
	mut cx := f32(0)
	for ci in 0 .. t.columns.len {
		if rel_x >= cx && rel_x < cx + t.columns[ci].width {
			col = ci
			break
		}
		cx += t.columns[ci].width
	}
	mut row := -1
	mut ry := f32(0)
	for ri in 0 .. t.rows.len {
		rh := t.eff_row_height(ri)
		if rel_y >= ry && rel_y < ry + rh {
			row = ri
			break
		}
		ry += rh
	}
	return row, col
}

// Попадание в «горячую зону» правой границы колонки в строке заголовка. Возвращает
// индекс колонки, чью ширину тянут, или -1. Границы считаются с учётом scroll_x.
fn (t &TableView) hit_col_border(mx f32, my f32) int {
	hdr_y := t.bounds.y + t.pad
	if my < hdr_y || my > hdr_y + t.header_height {
		return -1
	}
	ox := t.data_origin_x()
	mut cx := ox - t.scroll_x
	for ci in 0 .. t.columns.len {
		cx += t.columns[ci].width
		if abs_f32(mx - cx) < tbl_resize_zone {
			return ci
		}
	}
	return -1
}

// Попадание в нижнюю границу строки в колонке номеров. Работает только если
// показаны номера строк (за границу строки без номеров тянуть нельзя).
fn (t &TableView) hit_row_border(mx f32, my f32) int {
	if !t.show_row_numbers {
		return -1
	}
	rn_x := t.bounds.x + t.pad
	if mx < rn_x || mx > rn_x + t.row_num_width {
		return -1
	}
	oy := t.data_origin_y()
	mut ry := oy - t.scroll_y
	for ri in 0 .. t.rows.len {
		ry += t.eff_row_height(ri)
		if abs_f32(my - ry) < tbl_resize_zone {
			return ri
		}
	}
	return -1
}

// ─── Scrollbar geometry ────────────────────────────────

// Геометрия полос прокрутки: возвращает (дорожка, ползунок) или два пустых Rect,
// если всё содержимое помещается. Длина ползунка пропорциональна доле видимой части
// (не меньше 20 px), позиция - доле текущей прокрутки от максимальной.
fn (t &TableView) vsb_rects() (Rect, Rect) {
	vp := t.viewport_rect()
	ch := t.total_rows_height()
	if ch <= vp.h {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: t.bounds.x + t.bounds.w - t.pad - tbl_sb_w
		y: vp.y
		w: tbl_sb_w
		h: vp.h
	}
	thumb_h := max_f32(20, vp.h * (vp.h / ch))
	ms := t.max_scroll_y()
	ratio := if ms > 0 { t.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 1
		y: track.y + ratio * (vp.h - thumb_h)
		w: tbl_sb_w - 2
		h: thumb_h
	}
	return track, thumb
}

fn (t &TableView) hsb_rects() (Rect, Rect) {
	vp := t.viewport_rect()
	cw := t.total_cols_width()
	if cw <= vp.w {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: vp.x
		y: t.bounds.y + t.bounds.h - t.pad - tbl_sb_w
		w: vp.w
		h: tbl_sb_w
	}
	thumb_w := max_f32(20, vp.w * (vp.w / cw))
	ms := t.max_scroll_x()
	ratio := if ms > 0 { t.scroll_x / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vp.w - thumb_w)
		y: track.y + 1
		w: thumb_w
		h: tbl_sb_w - 2
	}
	return track, thumb
}

// ─── Inline edit helpers ───────────────────────────────

// Можно ли редактировать ячейку: нужна и глобальная editable, и её собственная.
fn (t &TableView) is_cell_editable(row int, col int) bool {
	if !t.editable {
		return false
	}
	if row < 0 || row >= t.rows.len || col < 0 || col >= t.columns.len {
		return false
	}
	return t.rows[row].cells[col].editable
}

// Входит в режим редактирования: загружает текст ячейки в буфер рун, ставит курсор
// в конец, выделяет весь текст (первый введённый символ его заменит) и очищает
// историю undo. Ничего не делает для нередактируемой ячейки.
fn (mut t TableView) begin_edit(row int, col int) {
	if !t.is_cell_editable(row, col) {
		return
	}
	t.editing = true
	t.edit_row = row
	t.edit_col = col
	t.edit_buf = t.rows[row].cells[col].text.runes()
	t.edit_cur = t.edit_buf.len
	t.edit_scroll_x = 0
	t.edit_sel_a = 0
	t.edit_sel_b = t.edit_buf.len
	t.edit_history.clear()
}

// Завершает редактирование с сохранением: пишет буфер в ячейку, зовёт on_change
// (row, col, новый текст), только если текст изменился, и выходит из режима. Сначала
// вызывается колбэк, потом сбрасывается состояние: из колбэка edit_row/edit_col ещё
// доступны.
fn (mut t TableView) commit_edit() {
	if !t.editing {
		return
	}
	new_text := if t.edit_buf.len > 0 { t.edit_buf.string() } else { '' }
	changed := t.rows[t.edit_row].cells[t.edit_col].text != new_text
	t.rows[t.edit_row].cells[t.edit_col].text = new_text
	if changed && t.on_change != unsafe { nil } {
		t.on_change(t.edit_row, t.edit_col, new_text)
	}
	t.editing = false
	t.edit_row = -1
	t.edit_col = -1
}

// Завершает редактирование без сохранения (Escape, clear_rows).
fn (mut t TableView) cancel_edit() {
	t.editing = false
	t.edit_row = -1
	t.edit_col = -1
}

// Хелперы выделения внутри редактора: выделение задаётся парой индексов рун
// edit_sel_a (якорь) и edit_sel_b (подвижный конец); lo/hi - упорядоченные границы.
// Выделения нет, если индекс -1 или a == b.
fn (t &TableView) edit_has_sel() bool {
	return t.edit_sel_a >= 0 && t.edit_sel_b >= 0 && t.edit_sel_a != t.edit_sel_b
}

fn (t &TableView) edit_sel_lo() int {
	return min_int(t.edit_sel_a, t.edit_sel_b)
}

fn (t &TableView) edit_sel_hi() int {
	return max_int(t.edit_sel_a, t.edit_sel_b)
}

fn (mut t TableView) edit_clear_sel() {
	t.edit_sel_a = -1
	t.edit_sel_b = -1
}

// Кладёт текущий буфер и курсор в историю undo. Вызывается ПЕРЕД каждой изменяющей
// операцией.
fn (mut t TableView) edit_save_undo() {
	t.edit_history.save(RuneSnap{
		buf: t.edit_buf.clone()
		cur: t.edit_cur
	})
}

// Удаляет выделенный фрагмент из буфера, ставит курсор на его начало. Undo сам не
// сохраняет - это делает вызывающий.
fn (mut t TableView) edit_delete_sel() {
	if !t.edit_has_sel() {
		return
	}
	lo := t.edit_sel_lo()
	hi := t.edit_sel_hi()
	mut out := []rune{cap: t.edit_buf.len - (hi - lo)}
	for i in 0 .. lo {
		out << t.edit_buf[i]
	}
	for i in hi .. t.edit_buf.len {
		out << t.edit_buf[i]
	}
	t.edit_buf = out
	t.edit_cur = lo
	t.edit_clear_sel()
}

// Вставка строки в позицию курсора с заменой выделения. Сохраняет undo один раз
// (замена выделения и вставка откатываются вместе).
fn (mut t TableView) edit_insert(s string) {
	if s.len == 0 {
		return
	}
	t.edit_save_undo()
	if t.edit_has_sel() {
		t.edit_delete_sel()
	}
	rr := s.runes()
	mut out := []rune{cap: t.edit_buf.len + rr.len}
	for i in 0 .. t.edit_cur {
		out << t.edit_buf[i]
	}
	for r in rr {
		out << r
	}
	for i in t.edit_cur .. t.edit_buf.len {
		out << t.edit_buf[i]
	}
	t.edit_buf = out
	t.edit_cur += rr.len
}

// Undo/redo редактора: меняют местами текущее состояние и снимок из истории. Курсор
// после восстановления ограничивается длиной буфера.
fn (mut t TableView) edit_perform_undo() {
	entry := t.edit_history.undo(RuneSnap{
		buf: t.edit_buf.clone()
		cur: t.edit_cur
	}) or { return }
	t.edit_buf = entry.buf.clone()
	t.edit_cur = clamp_int(entry.cur, 0, t.edit_buf.len)
	t.edit_clear_sel()
}

fn (mut t TableView) edit_perform_redo() {
	entry := t.edit_history.redo(RuneSnap{
		buf: t.edit_buf.clone()
		cur: t.edit_cur
	}) or { return }
	t.edit_buf = entry.buf.clone()
	t.edit_cur = clamp_int(entry.cur, 0, t.edit_buf.len)
	t.edit_clear_sel()
}

// Прокручивает так, чтобы выделенная ячейка целиком попала в viewport (по обеим осям).
// Если ячейка шире/выше viewport'а, приоритет у её правого/нижнего края.
fn (mut t TableView) ensure_sel_visible() {
	if t.sel_row < 0 || t.sel_col < 0 {
		return
	}
	vp := t.viewport_rect()
	ry := t.row_y(t.sel_row)
	rh := t.eff_row_height(t.sel_row)
	if ry < t.scroll_y {
		t.scroll_y = ry
	}
	if ry + rh > t.scroll_y + vp.h {
		t.scroll_y = ry + rh - vp.h
	}
	t.scroll_y = clamp_f32(t.scroll_y, 0, t.max_scroll_y())
	cx := t.col_x(t.sel_col)
	cw := t.columns[t.sel_col].width
	if cx < t.scroll_x {
		t.scroll_x = cx
	}
	if cx + cw > t.scroll_x + vp.w {
		t.scroll_x = cx + cw - vp.w
	}
	t.scroll_x = clamp_f32(t.scroll_x, 0, t.max_scroll_x())
}

// Вызывает on_select(row, col), если колбэк задан.
fn (mut t TableView) fire_select() {
	if t.on_select != unsafe { nil } {
		t.on_select(t.sel_row, t.sel_col)
	}
}

// ─── Text clipping helper ──────────────────────────────

// NEW: Truncate text to fit within available width, appending ellipsis if needed
// Обрезает текст по ширине max_w, добавляя многоточие. Двоичным поиском по числу рун
// ищется самый длинный префикс, который вместе с «…» помещается. Возвращает '',
// если не помещается даже многоточие; сам '…', если не помещается ни одной руны.
// Работает по рунам, а не байтам, чтобы не разрезать UTF-8.
fn tbl_clip_text(ctx &RenderContext, text string, max_w f32, font voidptr) string {
	if text.len == 0 || max_w <= 0 {
		return ''
	}
	tw := ctx.measure_text_with_font(text, font).x
	if tw <= max_w {
		return text
	}
	// Measure ellipsis
	ellipsis := '…'
	ew := ctx.measure_text_with_font(ellipsis, font).x
	if ew >= max_w {
		return ''
	}
	target := max_w - ew
	runes := text.runes()
	mut lo := 0
	mut hi := runes.len
	// Binary search for the longest prefix that fits
	for lo < hi {
		mid := (lo + hi + 1) / 2
		sub := runes[..mid].string()
		sw := ctx.measure_text_with_font(sub, font).x
		if sw <= target {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	if lo == 0 {
		return ellipsis
	}
	return runes[..lo].string() + ellipsis
}

// ─── Draw text aligned in cell rect (with clipping) ───

// Рисует однострочный текст в прямоугольнике ячейки: по горизонтали по align с отступом
// tbl_cell_pad, по вертикали по центру; длинный текст обрезается через tbl_clip_text.
fn tbl_draw_text_aligned(mut ctx RenderContext, text string, r Rect, align TextAlign, tc Color, font voidptr) {
	if text.len == 0 {
		return
	}
	avail_w := r.w - tbl_cell_pad * 2
	if avail_w <= 0 {
		return
	}
	// Clip text to fit available width
	display := tbl_clip_text(ctx, text, avail_w, font)
	if display.len == 0 {
		return
	}
	fh := ctx.font_height_of(font)
	tw := ctx.measure_text_with_font(display, font).x
	ty := r.y + (r.h - fh) * 0.5
	tx := match align {
		.left { r.x + tbl_cell_pad }
		.center { r.x + (r.w - tw) * 0.5 }
		.right { r.x + r.w - tw - tbl_cell_pad }
	}

	ctx.draw_text_with_font(display, tx, ty, tc, font)
}

// ─── Drawing ───────────────────────────────────────────

// Отрисовка таблицы. Порядок слоёв: фон и рамка (цвет рамки плавно смешивается с
// цветом фокуса через focus_anim) -> колонка номеров строк -> строка заголовка ->
// ячейки данных (под клипом viewport'а) -> рамка выделенной ячейки -> полосы
// прокрутки. Сначала прокрутка ограничивается допустимым диапазоном (содержимое
// могло уменьшиться). Строки и колонки вне видимой области пропускаются, а
// перебор строк прерывается при выходе за нижний край (rows упорядочены по Y).
pub fn (mut t TableView) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(t.enabled)
	if !t.visible || t.columns.len == 0 {
		return
	}
	if !ctx.is_in_clip(t.bounds) {
		return
	}
	// Встроенные виджеты (ячейки, редакторы) неактивны вместе с владельцем;
	// всё содержимое приглушается вуалью поверх (enabled.v)
	ctx.begin_disabled(t.enabled)
	defer {
		ctx.end_disabled(t.enabled)
		if !en {
			ctx.draw_disabled_veil(t.bounds, ctx.theme.border_radius)
		}
	}

	t.scroll_x = clamp_f32(t.scroll_x, 0, t.max_scroll_x())
	t.scroll_y = clamp_f32(t.scroll_y, 0, t.max_scroll_y())

	rad := ctx.theme.border_radius
	bg := t.eff_cell_bg(ctx)
	ctx.fill_rounded_rect(t.bounds, bg, rad)

	bc := ctx.theme.input_border.blend(ctx.theme.input_focus, t.focus_anim.value)
	ctx.draw_rounded_rect(t.bounds, bc, rad)

	target_focus := if t.focused && en { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if t.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('table', t.bounds.expanded(1))
	}

	font := ctx.get_font(.regular, 0)
	font_b := ctx.get_font(.bold, 0)
	fh := ctx.font_height_of(font)

	vp := t.viewport_rect()
	ox := t.data_origin_x()
	oy := t.data_origin_y()
	grid_c := t.eff_grid_color(ctx)
	hdr_bg := t.eff_header_bg(ctx)
	hdr_tc := t.eff_header_text(ctx)
	sel_bg := t.eff_sel_bg(ctx)
	sel_tc := t.eff_sel_text(ctx)
	hov_bg := t.eff_hover_bg(ctx)
	ro_bg := t.eff_readonly_bg(ctx)
	ro_tc := t.eff_readonly_text(ctx)

	// Колонка номеров строк рисуется отдельно от данных: она не прокручивается по X, но
	// прокручивается по Y вместе со строками (поэтому свой клип по высоте viewport'а).
	// ── Row numbers column ──
	if t.show_row_numbers {
		rn_x := t.bounds.x + t.pad
		rn_bg := t.eff_row_num_bg(ctx)
		rn_tc := t.eff_row_num_text(ctx)

		ctx.fill_rect(Rect{rn_x, t.bounds.y + t.pad, t.row_num_width, t.header_height}, hdr_bg)
		ctx.fill_rect(Rect{rn_x, t.bounds.y + t.pad + t.header_height - 1, t.row_num_width, 1},
			grid_c)
		ctx.fill_rect(Rect{rn_x + t.row_num_width - 1, t.bounds.y + t.pad, 1, t.header_height},
			grid_c)

		ctx.push_clip(Rect{rn_x, oy, t.row_num_width, vp.h})
		mut rn_ry := oy - t.scroll_y
		for ri in 0 .. t.rows.len {
			rh := t.eff_row_height(ri)
			if rn_ry + rh >= oy && rn_ry <= oy + vp.h {
				ctx.fill_rect(Rect{rn_x, rn_ry, t.row_num_width, rh}, rn_bg)
				ctx.fill_rect(Rect{rn_x, rn_ry + rh - 1, t.row_num_width, 1}, grid_c)
				num_str := '${ri + 1}'
				nw := ctx.measure_text_with_font(num_str, font).x
				nx := rn_x + (t.row_num_width - nw) * 0.5
				ny := rn_ry + (rh - fh) * 0.5
				ctx.draw_text_with_font(num_str, nx, ny, rn_tc, font)
			}
			rn_ry += rh
		}
		ctx.pop_clip()
	}

	// Заголовок не прокручивается по Y, но по X идёт вместе с колонками (hx начинается с
	// ox - scroll_x); клип hdr_r не даёт ему залезть на колонку номеров.
	// ── Header row ──
	hdr_r := Rect{ox, t.bounds.y + t.pad, vp.w, t.header_height}
	ctx.fill_rect(hdr_r, hdr_bg)
	ctx.fill_rect(Rect{hdr_r.x, hdr_r.y + hdr_r.h - 1, hdr_r.w, 1}, grid_c)

	ctx.push_clip(hdr_r)
	mut hx := ox - t.scroll_x
	for ci in 0 .. t.columns.len {
		col := t.columns[ci]
		cell_r := Rect{hx, hdr_r.y, col.width, t.header_height}
		if hx + col.width >= ox && hx <= ox + vp.w {
			// Header text also clipped to column width
			tbl_draw_text_aligned(mut ctx, col.title, cell_r, .center, hdr_tc, font_b)
			ctx.fill_rect(Rect{hx + col.width - 1, hdr_r.y, 1, t.header_height}, grid_c)
		}
		hx += col.width
	}
	ctx.pop_clip()

	// ── Data cells ──
	ctx.push_clip(vp)

	// Основной цикл по строкам. ry - Y верхнего края строки на экране (с учётом прокрутки).
	// Приоритет слоёв фона: подсветка наведённой строки -> выделение всей строки ->
	// фон ячейки / readonly-фон / выделение одной ячейки -> текст.
	mut ry := oy - t.scroll_y
	for ri in 0 .. t.rows.len {
		rh := t.eff_row_height(ri)
		if ry + rh < oy {
			ry += rh
			continue
		}
		if ry > oy + vp.h {
			break
		}

		// Hover row highlight
		if t.highlight_hover_row && ri == t.hover_row && !t.editing {
			ctx.fill_rect(Rect{vp.x, ry, vp.w, rh}, hov_bg)
		}

		// Full-row selection
		if t.select_full_row && ri == t.sel_row && !t.editing {
			ctx.fill_rect(Rect{vp.x, ry, vp.w, rh}, sel_bg)
		}

		mut cx := ox - t.scroll_x
		for ci in 0 .. t.columns.len {
			col_w := t.columns[ci].width
			cell_r := Rect{cx, ry, col_w, rh}

			if cx + col_w >= ox && cx <= ox + vp.w {
				cell := t.rows[ri].cells[ci]
				is_sel_cell := ri == t.sel_row && ci == t.sel_col && !t.select_full_row
				is_editing_cell := t.editing && ri == t.edit_row && ci == t.edit_col
				is_readonly := t.editable && !cell.editable

				// Per-cell background color
				if cell.bg_color.a > 0 && !is_sel_cell && !is_editing_cell {
					ctx.fill_rect(cell_r, cell.bg_color)
				} else if is_readonly && ro_bg.a > 0 && !is_sel_cell && !is_editing_cell {
					ctx.fill_rect(cell_r, ro_bg)
				}

				// Cell selection highlight (single cell mode)
				if is_sel_cell && !is_editing_cell {
					ctx.fill_rect(cell_r, sel_bg)
				}

				// Редактируемая ячейка рисуется «вручную»: фон поля ввода, выделение (полупрозрачный
				// accent), текст со сдвигом edit_scroll_x и мигающий курсор. Сдвиг подбирается
				// здесь же, чтобы курсор длинного текста не уходил за край ячейки.
				if is_editing_cell {
					// ── Inline edit ──
					ctx.fill_rect(cell_r, ctx.theme.input_bg)

					edit_inner :=
						Rect{cell_r.x + tbl_cell_pad, cell_r.y, cell_r.w - tbl_cell_pad * 2, cell_r.h}
					ctx.push_clip(edit_inner)
					edit_before := if t.edit_cur > 0 && t.edit_cur <= t.edit_buf.len {
						t.edit_buf[..t.edit_cur].string()
					} else {
						''
					}
					edit_full := if t.edit_buf.len > 0 { t.edit_buf.string() } else { '' }
					t.edit_scroll_x = edit_scroll_for_cursor(ctx.measure_text_with_font(edit_before,
						font).x, ctx.measure_text_with_font(edit_full, font).x, t.edit_scroll_x,
						edit_inner.w)

					if t.edit_has_sel() {
						lo := t.edit_sel_lo()
						hi := t.edit_sel_hi()
						lo_text := if lo > 0 && lo <= t.edit_buf.len {
							t.edit_buf[..lo].string()
						} else {
							''
						}
						hi_text := if hi > 0 && hi <= t.edit_buf.len {
							t.edit_buf[..hi].string()
						} else {
							''
						}
						x1 := ctx.measure_text_with_font(lo_text, font).x - t.edit_scroll_x
						x2 := ctx.measure_text_with_font(hi_text, font).x - t.edit_scroll_x
						ctx.fill_rect(Rect{edit_inner.x + x1, cell_r.y + 2, x2 - x1, rh - 4},
							ctx.theme.accent.with_alpha(80))
					}

					edit_text := if t.edit_buf.len > 0 { t.edit_buf.string() } else { '' }
					ty := ry + (rh - fh) * 0.5
					ctx.draw_text_with_font(edit_text, edit_inner.x - t.edit_scroll_x, ty,
						ctx.theme.text_primary, font)

					// Мигание курсора: период 1060 мс, видим первые 530 мс. Перерисовку по таймеру
					// (чтобы курсор мигал) этот код сам не запрашивает.
					ms := C.SDL_GetTicks()
					if ms % u64(1060) < 530 {
						text_before := if t.edit_cur > 0 && t.edit_cur <= t.edit_buf.len {
							t.edit_buf[..t.edit_cur].string()
						} else {
							''
						}
						ecx := edit_inner.x + ctx.measure_text_with_font(text_before, font).x -
							t.edit_scroll_x
						ctx.fill_rect(Rect{ecx, cell_r.y + 2, 2, rh - 4}, ctx.theme.accent)
					}
					ctx.pop_clip()
				} else {
					// Normal cell text — determine color with priority chain
					cell_tc := if cell.color.a > 0 {
						cell.color
					} else if is_sel_cell || (t.select_full_row && ri == t.sel_row) {
						sel_tc
					} else if is_readonly && ro_tc.a > 0 {
						ro_tc
					} else {
						t.eff_cell_text(ctx)
					}
					align := t.eff_cell_align(ri, ci)
					// Text is clipped inside tbl_draw_text_aligned via tbl_clip_text
					tbl_draw_text_aligned(mut ctx, cell.text, cell_r, align, cell_tc, font)
				}

				// Right grid line
				ctx.fill_rect(Rect{cx + col_w - 1, ry, 1, rh}, grid_c)
			}
			cx += col_w
		}

		// Bottom grid line
		ctx.fill_rect(Rect{vp.x, ry + rh - 1, vp.w, 1}, grid_c)
		ry += rh
	}

	// Selected cell border
	if t.sel_row >= 0 && t.sel_col >= 0 && !t.select_full_row {
		scx := ox + t.col_x(t.sel_col) - t.scroll_x
		scy := oy + t.row_y(t.sel_row) - t.scroll_y
		scw := t.columns[t.sel_col].width
		sch := t.eff_row_height(t.sel_row)
		sel_rect := Rect{scx, scy, scw, sch}
		if t.editing && t.sel_row == t.edit_row && t.sel_col == t.edit_col {
			ctx.draw_rect(sel_rect, ctx.theme.accent)
			ctx.draw_rect(sel_rect.shrunk(1), ctx.theme.accent)
		} else {
			ctx.draw_rect(sel_rect, ctx.theme.accent)
		}
	}

	ctx.pop_clip()

	// Полосы прокрутки рисуются поверх клипа данных, после его снятия. Цвет ползунка:
	// перетаскивание > наведение > обычный.
	// ── Vertical scrollbar ──
	if t.has_vsb() {
		track, thumb := t.vsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		vc := if t.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if t.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, vc, 3)
	}

	// ── Horizontal scrollbar ──
	if t.has_hsb() {
		track, thumb := t.hsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		hc := if t.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if t.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, hc, 3)
	}
}

// ═══════════════════════════════════════════════════════
// Event handling
// ═══════════════════════════════════════════════════════

// Обработка событий. Возвращает true, если событие поглощено таблицей.
// Приоритеты (порядок проверок важен): 1) активные перетаскивания (ползунки, границы
// колонки/строки) забирают ВСЕ события, пока не отпущена левая кнопка; 2) режим
// редактирования ячейки (handle_edit_event); 3) обычные события: наведение, нажатие
// (ползунок -> граница колонки -> граница строки -> ячейка), двойной клик (старт
// редактирования), колесо, клавиши навигации (только при фокусе).
pub fn (mut t TableView) handle_event(event &GuiEvent, app &App) bool {
	if !t.visible || !t.enabled || t.columns.len == 0 {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	// Перетаскивание ползунка: сдвиг мыши в пикселях дорожки переводится в прокрутку
	// пропорционально отношению (макс. прокрутка / ход ползунка).
	// ── Scrollbar drags ──
	if t.vsb_dragging {
		match event.typ {
			.mouse_move {
				track, _ := t.vsb_rects()
				if track.h <= 0 {
					return true
				}
				ch := t.total_rows_height()
				vis_h := track.h
				thumb_h := max_f32(20, vis_h * (vis_h / ch))
				drag_range := vis_h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - t.vsb_drag_start_y
				ms := t.max_scroll_y()
				t.scroll_y = clamp_f32(t.vsb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					t.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}
	if t.hsb_dragging {
		match event.typ {
			.mouse_move {
				track, _ := t.hsb_rects()
				if track.w <= 0 {
					return true
				}
				cw := t.total_cols_width()
				vis_w := track.w
				thumb_w := max_f32(20, vis_w * (vis_w / cw))
				drag_range := vis_w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - t.hsb_drag_start_x
				ms := t.max_scroll_x()
				t.scroll_x = clamp_f32(t.hsb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					t.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Column resize drag ──
	if t.col_resizing {
		match event.typ {
			.mouse_move {
				if t.resize_col >= 0 && t.resize_col < t.columns.len {
					dx := event.mouse_x - t.resize_start_x
					new_w := max_f32(t.columns[t.resize_col].min_w, t.resize_start_w + dx)
					t.columns[t.resize_col].width = new_w
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					t.col_resizing = false
					t.resize_col = -1
					set_cursor(sdl_system_cursor_arrow)
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Row resize drag ──
	if t.row_resizing {
		match event.typ {
			.mouse_move {
				if t.resize_row >= 0 && t.resize_row < t.rows.len {
					dy := event.mouse_y - t.resize_start_y
					new_h := max_f32(t.min_row_height, t.resize_start_h + dy)
					t.rows[t.resize_row].height = new_h
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					t.row_resizing = false
					t.resize_row = -1
					set_cursor(sdl_system_cursor_arrow)
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Inline editing mode ──
	if t.editing {
		return t.handle_edit_event(event, app, ctx_ptr)
	}

	match event.typ {
		.mouse_move {
			t.hovered = t.bounds.contains(event.mouse_x, event.mouse_y)
			if t.hovered {
				row, _ := t.hit_cell(event.mouse_x, event.mouse_y)
				t.hover_row = row

				col_border := t.hit_col_border(event.mouse_x, event.mouse_y)
				row_border := t.hit_row_border(event.mouse_x, event.mouse_y)
				if col_border >= 0 {
					set_cursor(sdl_system_cursor_sizewe)
				} else if row_border >= 0 {
					set_cursor(sdl_system_cursor_sizens)
				} else {
					set_cursor(sdl_system_cursor_arrow)
				}

				if t.has_vsb() {
					track, _ := t.vsb_rects()
					t.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
				if t.has_hsb() {
					track, _ := t.hsb_rects()
					t.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				}
			} else {
				t.hover_row = -1
				t.vsb_hovered = false
				t.hsb_hovered = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && t.hovered {
				if t.has_vsb() {
					_, thumb := t.vsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						t.vsb_dragging = true
						t.vsb_drag_start_y = event.mouse_y
						t.vsb_drag_start_scroll = t.scroll_y
						return true
					}
				}
				if t.has_hsb() {
					_, thumb := t.hsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						t.hsb_dragging = true
						t.hsb_drag_start_x = event.mouse_x
						t.hsb_drag_start_scroll = t.scroll_x
						return true
					}
				}

				col_border := t.hit_col_border(event.mouse_x, event.mouse_y)
				if col_border >= 0 {
					t.col_resizing = true
					t.resize_col = col_border
					t.resize_start_x = event.mouse_x
					t.resize_start_w = t.columns[col_border].width
					return true
				}

				row_border := t.hit_row_border(event.mouse_x, event.mouse_y)
				if row_border >= 0 {
					t.row_resizing = true
					t.resize_row = row_border
					t.resize_start_y = event.mouse_y
					t.resize_start_h = t.eff_row_height(row_border)
					return true
				}

				row, col := t.hit_cell(event.mouse_x, event.mouse_y)
				if row >= 0 && col >= 0 {
					t.focused = true
					t.sel_row = row
					t.sel_col = col
					t.fire_select()
					return true
				}
			}
		}
		.mouse_dbl_click {
			if t.hovered {
				row, col := t.hit_cell(event.mouse_x, event.mouse_y)
				if row >= 0 && col >= 0 && t.is_cell_editable(row, col) {
					t.sel_row = row
					t.sel_col = col
					t.begin_edit(row, col)
					return true
				}
			}
		}
		// Колесо: Shift - горизонтальная прокрутка, иначе вертикальная. Возвращает true только
		// если прокрутка реально изменилась - тогда, дойдя до края, таблица отдаёт колесо
		// родительскому ScrollBox. Позиция мыши берётся из ctx (актуальная для активного
		// окна), а при его отсутствии - из события.
		.mouse_wheel {
			if !t.wheel {
				return false
			}
			if !t.hovered {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if t.bounds.contains(mx, my) {
				if event.shift() {
					old := t.scroll_x
					t.scroll_x -= event.wheel_y * t.scroll_speed
					t.scroll_x = clamp_f32(t.scroll_x, 0, t.max_scroll_x())
					return t.scroll_x != old
				}
				old := t.scroll_y
				t.scroll_y -= event.wheel_y * t.scroll_speed
				t.scroll_y = clamp_f32(t.scroll_y, 0, t.max_scroll_y())
				return t.scroll_y != old
			}
		}
		.key_down {
			if !t.focused {
				return false
			}
			return t.handle_nav_key(event)
		}
		else {}
	}

	return false
}

// ─── Navigation keys ───────────────────────────────────

// Клавиатурная навигация по выделению: стрелки, Tab/Shift+Tab (по ячейкам с
// переходом на соседнюю строку), Enter/F2 (начать правку), Home/End (первая/последняя
// строка, а без select_full_row ещё и колонка), Escape (снять фокус). Любое
// перемещение прокручивает к ячейке и вызывает on_select. Стрелки и Tab поглощают
// событие (true) даже на границе, чтобы фокус не ушёл дальше.
fn (mut t TableView) handle_nav_key(event &GuiEvent) bool {
	if t.rows.len == 0 || t.columns.len == 0 {
		return false
	}

	match event.keycode {
		sdl_k_up {
			if t.sel_row > 0 {
				t.sel_row -= 1
				t.ensure_sel_visible()
				t.fire_select()
			}
			return true
		}
		sdl_k_down {
			if t.sel_row < t.rows.len - 1 {
				t.sel_row += 1
				t.ensure_sel_visible()
				t.fire_select()
			}
			return true
		}
		sdl_k_left {
			if !t.select_full_row && t.sel_col > 0 {
				t.sel_col -= 1
				t.ensure_sel_visible()
				t.fire_select()
			}
			return true
		}
		sdl_k_right {
			if !t.select_full_row && t.sel_col < t.columns.len - 1 {
				t.sel_col += 1
				t.ensure_sel_visible()
				t.fire_select()
			}
			return true
		}
		sdl_k_tab {
			if event.shift() {
				if t.sel_col > 0 {
					t.sel_col -= 1
				} else if t.sel_row > 0 {
					t.sel_row -= 1
					t.sel_col = t.columns.len - 1
				}
			} else {
				if t.sel_col < t.columns.len - 1 {
					t.sel_col += 1
				} else if t.sel_row < t.rows.len - 1 {
					t.sel_row += 1
					t.sel_col = 0
				}
			}
			t.ensure_sel_visible()
			t.fire_select()
			return true
		}
		sdl_k_return, sdl_k_f2 {
			if t.sel_row >= 0 && t.sel_col >= 0 && t.is_cell_editable(t.sel_row, t.sel_col) {
				t.begin_edit(t.sel_row, t.sel_col)
			}
			return true
		}
		sdl_k_escape {
			t.focused = false
			return true
		}
		else {}
	}

	if is_home_key(event.keycode, event.scancode) {
		t.sel_row = 0
		if !t.select_full_row {
			t.sel_col = 0
		}
		t.ensure_sel_visible()
		t.fire_select()
		return true
	}
	if is_end_key(event.keycode, event.scancode) {
		t.sel_row = t.rows.len - 1
		if !t.select_full_row {
			t.sel_col = t.columns.len - 1
		}
		t.ensure_sel_visible()
		t.fire_select()
		return true
	}

	return false
}

// ─── Inline edit event handler ─────────────────────────

// События во время inline-редактирования (аналог TextInput, но для одной строки без
// переноса): ввод текста, Enter (commit и переход вниз), Escape (отмена), Tab (commit
// и переход к следующей редактируемой ячейке), Backspace/Delete, стрелки с Shift
// (выделение), Ctrl+A/C/X/V/Z (Ctrl+Shift+Z - redo), Home/End. Клик вне редактируемой
// ячейки подтверждает правку и выделяет ячейку под курсором. Любая клавиша
// поглощается (true), чтобы не уходить в навигацию.
fn (mut t TableView) handle_edit_event(event &GuiEvent, app &App, _ &RenderContext) bool {
	match event.typ {
		.text_input {
			// При зажатом Ctrl SDL всё равно присылает text_input для горячих клавиш - такие
			// символы вставлять нельзя.
			mod_state := C.SDL_GetModState()
			if (mod_state & sdl_kmod_ctrl) != 0 {
				return true
			}
			t.edit_insert(event.text)
			return true
		}
		.key_down {
			c := event.ctrl()
			s := event.shift()

			match event.keycode {
				sdl_k_return {
					t.commit_edit()
					if t.sel_row < t.rows.len - 1 {
						t.sel_row += 1
						t.ensure_sel_visible()
					}
					return true
				}
				sdl_k_escape {
					t.cancel_edit()
					return true
				}
				sdl_k_tab {
					t.commit_edit()
					if s {
						if t.sel_col > 0 {
							t.sel_col -= 1
						} else if t.sel_row > 0 {
							t.sel_row -= 1
							t.sel_col = t.columns.len - 1
						}
					} else {
						if t.sel_col < t.columns.len - 1 {
							t.sel_col += 1
						} else if t.sel_row < t.rows.len - 1 {
							t.sel_row += 1
							t.sel_col = 0
						}
					}
					t.ensure_sel_visible()
					if t.is_cell_editable(t.sel_row, t.sel_col) {
						t.begin_edit(t.sel_row, t.sel_col)
					}
					return true
				}
				sdl_k_backspace {
					if t.edit_has_sel() {
						t.edit_save_undo()
						t.edit_delete_sel()
					} else if t.edit_cur > 0 {
						t.edit_save_undo()
						mut out := []rune{cap: t.edit_buf.len - 1}
						for i in 0 .. t.edit_cur - 1 {
							out << t.edit_buf[i]
						}
						for i in t.edit_cur .. t.edit_buf.len {
							out << t.edit_buf[i]
						}
						t.edit_buf = out
						t.edit_cur--
					}
					return true
				}
				sdl_k_delete {
					if t.edit_has_sel() {
						t.edit_save_undo()
						t.edit_delete_sel()
					} else if t.edit_cur < t.edit_buf.len {
						t.edit_save_undo()
						mut out := []rune{cap: t.edit_buf.len - 1}
						for i in 0 .. t.edit_cur {
							out << t.edit_buf[i]
						}
						for i in t.edit_cur + 1 .. t.edit_buf.len {
							out << t.edit_buf[i]
						}
						t.edit_buf = out
					}
					return true
				}
				sdl_k_left {
					if s {
						if t.edit_sel_a < 0 {
							t.edit_sel_a = t.edit_cur
							t.edit_sel_b = t.edit_cur
						}
					}
					if !s && t.edit_has_sel() {
						t.edit_cur = t.edit_sel_lo()
						t.edit_clear_sel()
					} else {
						if t.edit_cur > 0 {
							t.edit_cur--
						}
						if s {
							t.edit_sel_b = t.edit_cur
						} else {
							t.edit_clear_sel()
						}
					}
					return true
				}
				sdl_k_right {
					if s {
						if t.edit_sel_a < 0 {
							t.edit_sel_a = t.edit_cur
							t.edit_sel_b = t.edit_cur
						}
					}
					if !s && t.edit_has_sel() {
						t.edit_cur = t.edit_sel_hi()
						t.edit_clear_sel()
					} else {
						if t.edit_cur < t.edit_buf.len {
							t.edit_cur++
						}
						if s {
							t.edit_sel_b = t.edit_cur
						} else {
							t.edit_clear_sel()
						}
					}
					return true
				}
				sdl_k_a {
					if c {
						t.edit_sel_a = 0
						t.edit_sel_b = t.edit_buf.len
						t.edit_cur = t.edit_buf.len
						return true
					}
				}
				sdl_k_c {
					if c {
						if t.edit_has_sel() {
							lo := t.edit_sel_lo()
							hi := t.edit_sel_hi()
							if lo < hi && hi <= t.edit_buf.len {
								app.set_clipboard(t.edit_buf[lo..hi].string())
							}
						}
						return true
					}
				}
				sdl_k_x {
					if c {
						if t.edit_has_sel() {
							lo := t.edit_sel_lo()
							hi := t.edit_sel_hi()
							if lo < hi && hi <= t.edit_buf.len {
								app.set_clipboard(t.edit_buf[lo..hi].string())
							}
							t.edit_save_undo()
							t.edit_delete_sel()
						}
						return true
					}
				}
				sdl_k_v {
					if c {
						cl := app.get_clipboard()
						if cl.len > 0 {
							// Однострочный редактор: переводы строк и табы из буфера обмена заменяются пробелами.
							filtered := cl.replace('\n', ' ').replace('\r', '').replace('\t', ' ')
							t.edit_insert(filtered)
						}
						return true
					}
				}
				sdl_k_z {
					if c && s {
						t.edit_perform_redo()
						return true
					}
					if c {
						t.edit_perform_undo()
						return true
					}
				}
				else {}
			}

			if is_home_key(event.keycode, event.scancode) {
				if s {
					if t.edit_sel_a < 0 {
						t.edit_sel_a = t.edit_cur
						t.edit_sel_b = t.edit_cur
					}
				}
				t.edit_cur = 0
				if s {
					t.edit_sel_b = 0
				} else {
					t.edit_clear_sel()
				}
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				if s {
					if t.edit_sel_a < 0 {
						t.edit_sel_a = t.edit_cur
						t.edit_sel_b = t.edit_cur
					}
				}
				t.edit_cur = t.edit_buf.len
				if s {
					t.edit_sel_b = t.edit_buf.len
				} else {
					t.edit_clear_sel()
				}
				return true
			}

			return true
		}
		.mouse_down {
			if event.mouse_btn == .left {
				row, col := t.hit_cell(event.mouse_x, event.mouse_y)
				if row == t.edit_row && col == t.edit_col {
					return true
				}
				t.commit_edit()
				if row >= 0 && col >= 0 {
					t.sel_row = row
					t.sel_col = col
					t.fire_select()
				}
				return true
			}
		}
		else {}
	}

	return false
}

// ─── CSV loading ───────────────────────────────────────

// Parse CSV text into rows of strings.
//
//   delimiter  — field separator. If empty, auto-detected among , ; \t |
//   has_header — if true, the first non-empty line is used as column titles
//                (only applied when table has no columns yet)
//
// Blank lines and lines starting with '#' are skipped.
pub fn (mut t TableView) load_csv_string(text string, delimiter string, has_header bool) {
	if text.len == 0 {
		return
	}
	normalized := text.replace('\r\n', '\n').replace('\r', '\n')
	raw_lines := normalized.split('\n')

	mut lines := []string{cap: raw_lines.len}
	for rl in raw_lines {
		l := rl.trim_space()
		if l.len == 0 || l.starts_with('#') {
			continue
		}
		lines << l
	}
	if lines.len == 0 {
		return
	}

	delim := if delimiter.len > 0 { delimiter } else { csv_detect_delimiter(lines[0]) }

	mut start := 0
	if has_header {
		header_cols := lines[0].split(delim)
		if t.columns.len == 0 {
			for h in header_cols {
				t.add_column(h.trim_space(), 100)
			}
		}
		start = 1
	}

	for i in start .. lines.len {
		cols := lines[i].split(delim)
		mut trimmed := []string{cap: cols.len}
		for c in cols {
			trimmed << c.trim_space()
		}
		if t.columns.len == 0 {
			for _ in 0 .. trimmed.len {
				t.add_column('', 100)
			}
		}
		t.add_row(trimmed)
	}
}

// Load a CSV file into the table.
pub fn (mut t TableView) load_csv_file(path string, delimiter string, has_header bool) ! {
	text := os.read_file(path)!
	t.load_csv_string(text, delimiter, has_header)
}
