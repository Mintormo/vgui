module vgui

// ═══════════════════════════════════════════════════════
// GridLayout — двумерная сетка с фиксированным числом
// колонок. Каждая ячейка задается явно (row, col) и
// может занимать несколько строк/колонок (span).
//
// Колонки (приоритет определения размера - в описании GridLayout ниже):
//   - col_widths[i] > 0 — фиксированная ширина в px
//   - col_widths[i] == 0 — flex, делится по col_weights[i]
// Аналогично для строк.
// ═══════════════════════════════════════════════════════

// GridCell - ребёнок в сетке: адрес ячейки (row, col от 0) и размах row_span x col_span (>= 1). Один виджет - одна ячейка; перекрытия ячеек не проверяются.
pub struct GridCell {
pub mut:
	widget   &Widget
	row      int
	col      int
	row_span int = 1
	col_span int = 1
}

// GridLayout - сетка cols x rows. Ширину каждой колонки (высоту строки) определяет, по приоритету:
// фиксированное значение col_widths[i] > 0, иначе размер по содержимому (col_auto[i], по умолчанию для всех -
// самый широкий ребёнок по measure()), иначе доля свободного места по col_weights[i]. Публичных сеттеров
// для фиксированных размеров нет (col_widths / row_heights меняются только прямой записью в поле).
// Bounds детям раздаются в arrange() (layout), draw() только рисует. Если bounds не заданы родителем -
// сетка занимает весь экран окна (is_bounds_unset).
pub struct GridLayout {
pub mut:
	type_tag    int = kind_grid // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	cols        int = 1
	rows        int = 1
	cells       []GridCell
	col_widths  []f32
	row_heights []f32
	col_weights []f32
	row_weights []f32
	// Авто-размер: колонка/строка получает ширину (высоту)
	// самого широкого (высокого) своего ребёнка по measure().
	col_auto     []bool
	row_auto     []bool
	spacing_x    f32 = 4
	spacing_y    f32 = 4
	pad          f32
	bg           Color = Color{0, 0, 0, 0}
	use_panel_bg bool
	visible      bool = true
	enabled      bool = true // false - неактивны все ячейки (enabled.v)
	tooltip      string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	clip         bool = true
}

// create_grid создаёт сетку; cols и rows меньше 1 заменяются на 1. Все дорожки изначально авто-размера (по содержимому), без весов.
pub fn create_grid(cols int, rows int) &GridLayout {
	c := if cols < 1 { 1 } else { cols }
	r := if rows < 1 { 1 } else { rows }
	mut g := &GridLayout{
		bounds: Rect{0, 0, 0, 0}
		cols:   c
		rows:   r
	}
	g.col_widths = []f32{len: c, init: 0}
	g.row_heights = []f32{len: r, init: 0}
	// Дорожки по умолчанию - по содержимому (как auto в CSS Grid);
	// растягиваются только те, которым задан вес (set_col_weight)
	g.col_weights = []f32{len: c, init: 0}
	g.row_weights = []f32{len: r, init: 0}
	g.col_auto = []bool{len: c, init: true}
	g.row_auto = []bool{len: r, init: true}
	return g
}

// set_cols / set_rows меняют число дорожек и СБРАСЫВАЮТ размеры, веса и авто-режим этого направления в значения по умолчанию. Уже добавленные ячейки не переносятся; ячейки вне сетки при раскладке пропускаются.
pub fn (mut g GridLayout) set_cols(cols int) {
	c := if cols < 1 { 1 } else { cols }
	g.cols = c
	g.col_widths = []f32{len: c, init: 0}
	g.col_weights = []f32{len: c, init: 0}
	g.col_auto = []bool{len: c, init: true}
}

pub fn (mut g GridLayout) set_rows(rows int) {
	r := if rows < 1 { 1 } else { rows }
	g.rows = r
	g.row_heights = []f32{len: r, init: 0}
	g.row_weights = []f32{len: r, init: 0}
	g.row_auto = []bool{len: r, init: true}
}

pub fn (mut g GridLayout) add(widget &Widget, row int, col int) {
	g.add_span(widget, row, col, 1, 1)
}

// add_span - ячейка с объединением: span меньше 1 приводится к 1; выход за край сетки обрезается при раскладке.
pub fn (mut g GridLayout) add_span(widget &Widget, row int, col int, row_span int, col_span int) {
	rs := if row_span < 1 { 1 } else { row_span }
	cs := if col_span < 1 { 1 } else { col_span }
	g.cells << GridCell{
		widget:   unsafe { widget }
		row:      row
		col:      col
		row_span: rs
		col_span: cs
	}
}

// set_col_weight - колонка делит свободное место по весу (weight > 0)
// вместо размера по содержимому; 0 - снова по содержимому
pub fn (mut g GridLayout) set_col_weight(col int, weight f32) {
	if col < 0 || col >= g.col_weights.len {
		return
	}
	g.col_weights[col] = if weight < 0 { 0 } else { weight }
	g.col_auto[col] = g.col_weights[col] <= 0
}

// set_row_weight - то же для строки
pub fn (mut g GridLayout) set_row_weight(row int, weight f32) {
	if row < 0 || row >= g.row_weights.len {
		return
	}
	g.row_weights[row] = if weight < 0 { 0 } else { weight }
	g.row_auto[row] = g.row_weights[row] <= 0
}

// set_col_auto - колонка снова по содержимому (по умолчанию так и
// есть): ширина самого широкого виджета колонки (measure()).
pub fn (mut g GridLayout) set_col_auto(col int) {
	if col < 0 || col >= g.col_auto.len {
		return
	}
	g.col_auto[col] = true
	g.col_weights[col] = 0
}

// set_row_auto — то же для высоты строки.
pub fn (mut g GridLayout) set_row_auto(row int) {
	if row < 0 || row >= g.row_auto.len {
		return
	}
	g.row_auto[row] = true
	g.row_weights[row] = 0
}

pub fn (mut g GridLayout) set_spacing(sx f32, sy f32) {
	g.spacing_x = sx
	g.spacing_y = sy
}

pub fn (mut g GridLayout) set_padding(p f32) {
	g.pad = p
}

pub fn (mut g GridLayout) set_bg(c Color) {
	g.bg = c
}

pub fn (mut g GridLayout) set_panel_bg() {
	g.use_panel_bg = true
}

// ── Layout engine ──────────────────────────────────────

// distribute_sizes - размеры count дорожек вдоль оси длиной total: дорожки с fixed[i] > 0 получают это значение,
// остальное место (минус промежутки) делится между остальными пропорционально weights[i]. Дорожка без
// размера и без веса получает 0. Если места не хватает (avail < 0) - вес-дорожки схлопываются в 0, фиксированные не сжимаются.
fn distribute_sizes(total f32, spacing f32, count int, fixed []f32, weights []f32) []f32 {
	if count <= 0 {
		return []f32{}
	}
	mut out := []f32{len: count, init: 0}
	mut total_fixed := f32(0)
	mut total_weight := f32(0)
	for i in 0 .. count {
		if fixed[i] > 0 {
			total_fixed += fixed[i]
		} else {
			total_weight += weights[i]
		}
	}
	total_spacing := f32(count - 1) * spacing
	avail := max_f32(0, total - total_fixed - total_spacing)
	flex_unit := if total_weight > 0 { avail / total_weight } else { f32(0) }
	for i in 0 .. count {
		out[i] = if fixed[i] > 0 { fixed[i] } else { weights[i] * flex_unit }
	}
	return out
}

// auto_track_sizes измеряет детей и возвращает копию
// col_widths / row_heights, где авто-дорожки заменены на
// запрошенный содержимым размер. Дорожка без ребёнка
// остаётся нулевой и попадает в обычный делёж по весам.
//
// Ребёнок со span распределяется поровну между дорожками,
// которые он занимает: точное решение здесь требует
// системы неравенств, а равная доля даёт предсказуемый
// результат и не раздувает отдельную колонку.
fn (g &GridLayout) auto_track_sizes(ctx &RenderContext, vertical bool) []f32 {
	base := if vertical { g.row_heights } else { g.col_widths }
	auto := if vertical { g.row_auto } else { g.col_auto }
	mut out := base.clone()
	mut any := false
	for a in auto {
		if a {
			any = true
			break
		}
	}
	if !any {
		return out
	}
	for cell in g.cells {
		idx := if vertical { cell.row } else { cell.col }
		span := if vertical { cell.row_span } else { cell.col_span }
		if idx < 0 || idx >= auto.len || !auto[idx] {
			continue
		}
		hint := measure_widget(cell.widget, ctx)
		want := if vertical { hint.h } else { hint.w }
		share := want / f32(if span < 1 { 1 } else { span })
		if share > out[idx] {
			out[idx] = share
		}
	}
	return out
}

// layout - фаза arrange для ячеек: (1) размеры дорожек (авто -> по measure, остальное по весам),
// (2) накопленные смещения колонок/строк с учётом spacing, (3) каждой ячейке прямоугольник от левого верхнего
// угла её первой дорожки с суммой размеров занятых дорожек и промежутков между ними.
fn (mut g GridLayout) layout(ctx &RenderContext) {
	if g.cells.len == 0 || g.cols < 1 || g.rows < 1 {
		return
	}
	inner := g.bounds.shrunk(g.pad)

	col_fixed := g.auto_track_sizes(ctx, false)
	row_fixed := g.auto_track_sizes(ctx, true)
	col_sizes := distribute_sizes(inner.w, g.spacing_x, g.cols, col_fixed, g.col_weights)
	row_sizes := distribute_sizes(inner.h, g.spacing_y, g.rows, row_fixed, g.row_weights)

	// Cumulative offsets
	mut col_off := []f32{len: g.cols, init: 0}
	mut row_off := []f32{len: g.rows, init: 0}
	mut x := inner.x
	for i in 0 .. g.cols {
		col_off[i] = x
		x += col_sizes[i] + g.spacing_x
	}
	mut y := inner.y
	for i in 0 .. g.rows {
		row_off[i] = y
		y += row_sizes[i] + g.spacing_y
	}

	for i, c in g.cells {
		if c.col < 0 || c.row < 0 || c.col >= g.cols || c.row >= g.rows {
			continue
		}
		col_end := if c.col + c.col_span > g.cols { g.cols } else { c.col + c.col_span }
		row_end := if c.row + c.row_span > g.rows { g.rows } else { c.row + c.row_span }

		cx := col_off[c.col]
		cy := row_off[c.row]
		mut cw := f32(0)
		for k in c.col .. col_end {
			cw += col_sizes[k]
		}
		cw += f32(col_end - c.col - 1) * g.spacing_x
		mut ch := f32(0)
		for k in c.row .. row_end {
			ch += row_sizes[k]
		}
		ch += f32(row_end - c.row - 1) * g.spacing_y

		r := Rect{cx, cy, cw, ch}
		set_widget_bounds(mut g.cells[i].widget, r)
	}
}

// arrange: bounds по умолчанию - весь экран; раздаёт bounds ячейкам и рекурсивно спускается в их поддеревья.
pub fn (mut g GridLayout) arrange(mut ctx RenderContext) {
	if !g.visible {
		return
	}
	if is_bounds_unset(g.bounds) {
		g.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	g.layout(ctx)
	for i in 0 .. g.cells.len {
		arrange_widget(mut g.cells[i].widget, mut ctx)
	}
}

pub fn (mut g GridLayout) draw(mut ctx RenderContext) {
	if !g.visible {
		return
	}

	if g.use_panel_bg {
		ctx.fill_rect(g.bounds, ctx.theme.panel_bg)
	} else if g.bg.a > 0 {
		ctx.fill_rect(g.bounds, g.bg)
	}
	if g.clip {
		ctx.push_clip(g.bounds)
	}
	ctx.begin_disabled(g.enabled)
	for mut c in g.cells {
		ctx.draw_child(mut c.widget)
	}
	ctx.end_disabled(g.enabled)
	if g.clip {
		ctx.pop_clip()
	}
}

// handle_event: ячейки получают событие с конца списка (последняя добавленная - сверху); при window_resize корневая сетка подгоняет размер под окно.
pub fn (mut g GridLayout) handle_event(event &GuiEvent, app &App) bool {
	if !g.visible || (!g.enabled && is_input_event(event)) {
		return false
	}
	if event.typ == .window_resize {
		if is_bounds_unset(g.bounds) {
			g.bounds.w = f32(event.win_w)
			g.bounds.h = f32(event.win_h)
		}
	}
	for i := g.cells.len - 1; i >= 0; i-- {
		if g.cells[i].widget.handle_event(event, app) {
			return true
		}
	}
	return false
}
