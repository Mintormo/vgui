module vgui

import time

// ═══════════════════════════════════════════════════════════
// Calendar — full-page calendar widget with month/year views
// ═══════════════════════════════════════════════════════════

pub enum CalendarView {
	month
	year
}

@[heap]
pub struct Calendar {
pub mut:
	type_tag    int = kind_calendar // тег типа, см. widget_tag.v
	bounds      Rect
	visible     bool = true
	enabled     bool = true
	focused     bool
	focus_group int
	// Current display state
	view  CalendarView = .month
	year  int
	month int // 1..12
	// Selection
	sel_year  int
	sel_month int
	sel_day   int // 0 = none
	// Hover
	hov_year  int
	hov_month int
	hov_day   int
	hov_prev  bool
	hov_next  bool
	hov_title bool
	// Callbacks
	on_select      fn (int, int, int) = unsafe { nil } // year, month, day
	on_view_change fn (CalendarView)  = unsafe { nil }
}

// ─── Localisation ─────────────────────────────────────────

// These are module-level vars so the C-ABI bridge (vgui-capi) can overwrite them.
pub fn cal_set_month_names_short(names [12]string) {
	for i in 0 .. 12 { cal_month_names_short[i] = names[i] }
}

pub fn cal_set_month_names_full(names [12]string) {
	for i in 0 .. 12 { cal_month_names_full[i] = names[i] }
}

pub fn cal_set_day_names(names [7]string) {
	for i in 0 .. 7 { cal_day_name_list[i] = names[i] }
}

__global cal_month_names_short = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep',
	'Oct', 'Nov', 'Dec']!

__global cal_month_names_full = ['January', 'February', 'March', 'April', 'May', 'June', 'July',
	'August', 'September', 'October', 'November', 'December']!

__global cal_day_name_list = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']!

fn cal_month_name_short(m int) string {
	if m < 1 || m > 12 { return '' }
	return cal_month_names_short[m - 1]
}

fn cal_month_name_full(m int) string {
	if m < 1 || m > 12 { return '' }
	return cal_month_names_full[m - 1]
}

fn cal_today() (int, int, int) {
	now := time.now()
	return now.year, int(now.month), now.day
}

// Add n days to (y,m,d)
fn cal_add_days(y int, m int, d int, n int) (int, int, int) {
	mut ry := y
	mut rm := m
	mut rd := d + n
	if n >= 0 {
		for {
			dim := dp_days_in_month(ry, rm)
			if rd <= dim { break }
			rd -= dim
			rm++
			if rm > 12 {
				rm = 1
				ry++
			}
		}
	} else {
		for rd < 1 {
			rm--
			if rm < 1 {
				rm = 12
				ry--
			}
			rd += dp_days_in_month(ry, rm)
		}
	}
	return ry, rm, rd
}

const cal_hdr_h = f32(40)
const cal_btn_w = f32(28)

// ─── Constructor ──────────────────────────────────────────

pub fn calendar_new() &Calendar {
	y, m, _ := cal_today()
	return &Calendar{
		year:  y
		month: m
	}
}

// ─── Public API ───────────────────────────────────────────

pub fn (mut c Calendar) set_view(v CalendarView) {
	c.view = v
}

pub fn (mut c Calendar) set_date(y int, m int, d int) {
	c.year = y
	c.month = m
	c.sel_year = y
	c.sel_month = m
	c.sel_day = d
}

// ─── Drawing ──────────────────────────────────────────────

pub fn (mut c Calendar) draw(mut ctx RenderContext) {
	if !c.visible { return }
	if !ctx.is_in_clip(c.bounds) { return }

	bg := ctx.theme.input_bg
	brd := if c.focused { ctx.theme.input_focus } else { ctx.theme.input_border }
	ctx.fill_rounded_rect(c.bounds, bg, ctx.theme.border_radius)
	ctx.draw_rounded_rect(c.bounds, brd, ctx.theme.border_radius)

	match c.view {
		.month { c.draw_month(mut ctx) }
		.year { c.draw_year(mut ctx) }
	}
}

// ─── Header (prev / title / next) ─────────────────────────

fn (mut c Calendar) draw_header(mut ctx RenderContext, title string, can_drill_up bool) {
	font_b := ctx.get_font(.bold, 0)
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)

	hdr := Rect{c.bounds.x, c.bounds.y, c.bounds.w, cal_hdr_h}

	// Prev button
	prev_r := Rect{hdr.x + 4, hdr.y + (hdr.h - cal_btn_w) * 0.5, cal_btn_w, cal_btn_w}
	prev_bg := if c.hov_prev { ctx.theme.button_hover } else { Color{0, 0, 0, 0} }
	if prev_bg.a > 0 { ctx.fill_rounded_rect(prev_r, prev_bg, 6) }
	pw := ctx.measure_text_with_font('<', font).x
	ctx.draw_text_with_font('<', prev_r.x + (cal_btn_w - pw) * 0.5,
		prev_r.y + (cal_btn_w - fh) * 0.5, ctx.theme.text_primary, font)

	// Next button
	next_r := Rect{hdr.x + hdr.w - cal_btn_w - 4, hdr.y + (hdr.h - cal_btn_w) * 0.5, cal_btn_w, cal_btn_w}
	next_bg := if c.hov_next { ctx.theme.button_hover } else { Color{0, 0, 0, 0} }
	if next_bg.a > 0 { ctx.fill_rounded_rect(next_r, next_bg, 6) }
	nw := ctx.measure_text_with_font('>', font).x
	ctx.draw_text_with_font('>', next_r.x + (cal_btn_w - nw) * 0.5,
		next_r.y + (cal_btn_w - fh) * 0.5, ctx.theme.text_primary, font)

	// Title
	title_col := if can_drill_up && c.hov_title { ctx.theme.accent } else { ctx.theme.text_primary }
	tw := ctx.measure_text_with_font(title, font_b).x
	ctx.draw_text_with_font(title, hdr.x + (hdr.w - tw) * 0.5,
		hdr.y + (hdr.h - fh) * 0.5, title_col, font_b)
}

// ─── Month view ───────────────────────────────────────────

// Returns how many grid rows the month needs (5 or 6)
fn cal_month_rows(year int, month int) int {
	first_dow := (dp_day_of_week(year, month, 1) + 6) % 7 // 0=Mon
	days := dp_days_in_month(year, month)
	last_slot := first_dow + days - 1
	return if last_slot >= 35 { 6 } else { 5 }
}

fn (mut c Calendar) draw_month(mut ctx RenderContext) {
	c.draw_header(mut ctx, '${cal_month_name_full(c.month)} ${c.year}', true)

	font := ctx.get_font(.regular, 0)
	font_b := ctx.get_font(.bold, 0)
	fh := ctx.font_height_of(font)

	body := Rect{c.bounds.x, c.bounds.y + cal_hdr_h, c.bounds.w, c.bounds.h - cal_hdr_h}
	cell_w := body.w / 7
	dow_h := fh + 8

	// Day-of-week header
	for i in 0 .. 7 {
		dx := body.x + f32(i) * cell_w
		dw := ctx.measure_text_with_font(cal_day_name_list[i], font).x
		col := if i >= 5 { ctx.theme.error_color } else { ctx.theme.text_hint }
		ctx.draw_text_with_font(cal_day_name_list[i], dx + (cell_w - dw) * 0.5,
			body.y + 4, col, font)
	}

	num_rows := cal_month_rows(c.year, c.month)
	cell_h := (body.h - dow_h) / f32(num_rows)
	first_dow := (dp_day_of_week(c.year, c.month, 1) + 6) % 7 // 0=Mon
	days := dp_days_in_month(c.year, c.month)
	ty, tm, td := cal_today()

	for d := 1; d <= days; d++ {
		col_idx := (first_dow + d - 1) % 7
		row_idx := (first_dow + d - 1) / 7
		cx := body.x + f32(col_idx) * cell_w
		cy := body.y + dow_h + f32(row_idx) * cell_h

		is_today := d == td && c.month == tm && c.year == ty
		is_selected := c.sel_day > 0 && d == c.sel_day && c.month == c.sel_month && c.year == c.sel_year
		is_hovered := d == c.hov_day && c.month == c.hov_month && c.year == c.hov_year
		is_weekend := col_idx >= 5

		cell_r := Rect{cx + 2, cy + 2, cell_w - 4, cell_h - 4}

		if is_selected {
			ctx.fill_rounded_rect(cell_r, ctx.theme.accent, 6)
		} else if is_today {
			ctx.draw_rounded_rect(cell_r, ctx.theme.accent, 6)
		} else if is_hovered {
			ctx.fill_rounded_rect(cell_r, ctx.theme.button_hover, 6)
		}

		ds := '${d}'
		dw2 := ctx.measure_text_with_font(ds, font).x
		text_col := if is_selected {
			ctx.theme.accent_text
		} else if is_weekend {
			ctx.theme.error_color
		} else {
			ctx.theme.text_primary
		}
		if is_today && !is_selected {
			ctx.draw_text_with_font(ds, cx + (cell_w - dw2) * 0.5,
				cy + (cell_h - fh) * 0.5, text_col, font_b)
		} else {
			ctx.draw_text_with_font(ds, cx + (cell_w - dw2) * 0.5,
				cy + (cell_h - fh) * 0.5, text_col, font)
		}
	}
}

// ─── Year view ────────────────────────────────────────────

fn (mut c Calendar) draw_year(mut ctx RenderContext) {
	c.draw_header(mut ctx, '${c.year}', false)

	font := ctx.get_font(.regular, 0)
	font_b := ctx.get_font(.bold, 0)
	fh := ctx.font_height_of(font)

	body := Rect{c.bounds.x + 8, c.bounds.y + cal_hdr_h + 4, c.bounds.w - 16, c.bounds.h - cal_hdr_h - 8}
	cols := 4
	rows := 3
	cell_w := body.w / f32(cols)
	cell_h := body.h / f32(rows)
	ty, tm, td := cal_today()
	_ = td

	for mi in 0 .. 12 {
		m := mi + 1
		col := mi % cols
		row := mi / cols
		cx := body.x + f32(col) * cell_w
		cy := body.y + f32(row) * cell_h

		mini_r := Rect{cx + 4, cy + 4, cell_w - 8, cell_h - 8}

		is_cur_month := m == tm && c.year == ty

		if is_cur_month {
			ctx.fill_rounded_rect(mini_r, ctx.theme.button_bg, 8)
		}

		// Month name
		mname := cal_month_name_short(m)
		mw := ctx.measure_text_with_font(mname, font_b).x
		mname_col := if m == tm && c.year == ty { ctx.theme.accent } else { ctx.theme.text_primary }
		ctx.draw_text_with_font(mname, cx + (cell_w - mw) * 0.5,
			cy + 8, mname_col, font_b)

		// Mini grid — fit 5 or 6 rows dynamically
		grid_top := cy + 8 + fh + 4
		grid_h := mini_r.y + mini_r.h - grid_top
		mini_cell_w := (cell_w - 8) / 7
		num_rows_m := cal_month_rows(c.year, m)
		mini_cell_h := grid_h / f32(num_rows_m)

		first_dow := (dp_day_of_week(c.year, m, 1) + 6) % 7
		days := dp_days_in_month(c.year, m)

		for d := 1; d <= days; d++ {
			ci := (first_dow + d - 1) % 7
			ri := (first_dow + d - 1) / 7
			if ri >= num_rows_m { break }
			dcx := cx + 4 + f32(ci) * mini_cell_w
			dcy := grid_top + f32(ri) * mini_cell_h

			is_today := d == td && m == tm && c.year == ty
			is_sel := c.sel_day > 0 && d == c.sel_day && m == c.sel_month && c.year == c.sel_year
			is_hov_day := d == c.hov_day && c.hov_day > 0 && m == c.hov_month && c.year == c.hov_year
			is_weekend := ci >= 5

			if is_sel {
				ctx.fill_circle(dcx + mini_cell_w * 0.5, dcy + mini_cell_h * 0.5,
					mini_cell_w * 0.45, ctx.theme.accent)
			} else if is_today {
				ctx.fill_circle(dcx + mini_cell_w * 0.5, dcy + mini_cell_h * 0.5,
					mini_cell_w * 0.45, ctx.theme.accent.with_alpha(120))
			} else if is_hov_day {
				ctx.fill_circle(dcx + mini_cell_w * 0.5, dcy + mini_cell_h * 0.5,
					mini_cell_w * 0.45, ctx.theme.button_hover)
			}

			ds := '${d}'
			dsw := ctx.measure_text_with_font(ds, font).x
			dc := if is_sel {
				ctx.theme.accent_text
			} else if is_weekend {
				ctx.theme.error_color
			} else {
				ctx.theme.text_hint
			}
			ctx.draw_text_with_font(ds, dcx + (mini_cell_w - dsw) * 0.5,
				dcy + (mini_cell_h - fh) * 0.5, dc, font)
		}
	}
}

// ─── Hit testing helpers ──────────────────────────────────

fn (c &Calendar) prev_rect() Rect {
	return Rect{c.bounds.x + 4, c.bounds.y + (cal_hdr_h - cal_btn_w) * 0.5, cal_btn_w, cal_btn_w}
}

fn (c &Calendar) next_rect() Rect {
	return Rect{c.bounds.x + c.bounds.w - cal_btn_w - 4, c.bounds.y + (cal_hdr_h - cal_btn_w) * 0.5, cal_btn_w, cal_btn_w}
}

fn (c &Calendar) title_rect() Rect {
	return Rect{c.bounds.x + cal_btn_w + 8, c.bounds.y, c.bounds.w - (cal_btn_w + 8) * 2, cal_hdr_h}
}

// ─── Navigation ───────────────────────────────────────────

fn (mut c Calendar) navigate_prev() {
	match c.view {
		.month {
			c.month--
			if c.month < 1 {
				c.month = 12
				c.year--
			}
		}
		.year { c.year-- }
	}
}

fn (mut c Calendar) navigate_next() {
	match c.view {
		.month {
			c.month++
			if c.month > 12 {
				c.month = 1
				c.year++
			}
		}
		.year { c.year++ }
	}
}

fn (mut c Calendar) drill_up() {
	match c.view {
		.month { c.view = .year }
		.year {}
	}
	if c.on_view_change != unsafe { nil } {
		c.on_view_change(c.view)
	}
}

// ─── Month-view hit test ──────────────────────────────────

fn (c &Calendar) hit_month_day(mx f32, my f32) (int, int, int) {
	body := Rect{c.bounds.x, c.bounds.y + cal_hdr_h, c.bounds.w, c.bounds.h - cal_hdr_h}
	cell_w := body.w / 7
	font_placeholder := f32(14)
	dow_h := font_placeholder + 8
	num_rows := cal_month_rows(c.year, c.month)
	cell_h := (body.h - dow_h) / f32(num_rows)
	first_dow := (dp_day_of_week(c.year, c.month, 1) + 6) % 7
	days := dp_days_in_month(c.year, c.month)
	for d := 1; d <= days; d++ {
		col_idx := (first_dow + d - 1) % 7
		row_idx := (first_dow + d - 1) / 7
		cx := body.x + f32(col_idx) * cell_w
		cy := body.y + dow_h + f32(row_idx) * cell_h
		if mx >= cx && mx < cx + cell_w && my >= cy && my < cy + cell_h {
			return c.year, c.month, d
		}
	}
	return 0, 0, 0
}

// Returns (month, day) under (mx,my) in year view mini-grids, or (0,0).
// font_h is an approximate font height used for the month name row.
fn (c &Calendar) hit_year_day(mx f32, my f32, font_h f32) (int, int) {
	body := Rect{c.bounds.x + 8, c.bounds.y + cal_hdr_h + 4, c.bounds.w - 16, c.bounds.h - cal_hdr_h - 8}
	cell_w := body.w / 4
	cell_h := body.h / 3
	if mx < body.x || mx > body.x + body.w || my < body.y || my > body.y + body.h {
		return 0, 0
	}
	col := int((mx - body.x) / cell_w)
	row := int((my - body.y) / cell_h)
	m := row * 4 + col + 1
	if m < 1 || m > 12 { return 0, 0 }

	cx := body.x + f32(col) * cell_w
	cy := body.y + f32(row) * cell_h
	grid_top := cy + 8 + font_h + 4
	grid_h := (cy + 4 + cell_h - 8) - grid_top
	mini_cell_w := (cell_w - 8) / 7
	num_rows_m := cal_month_rows(c.year, m)
	mini_cell_h := grid_h / f32(num_rows_m)
	first_dow := (dp_day_of_week(c.year, m, 1) + 6) % 7
	days := dp_days_in_month(c.year, m)

	for d := 1; d <= days; d++ {
		ci := (first_dow + d - 1) % 7
		ri := (first_dow + d - 1) / 7
		if ri >= num_rows_m { break }
		dcx := cx + 4 + f32(ci) * mini_cell_w
		dcy := grid_top + f32(ri) * mini_cell_h
		if mx >= dcx && mx < dcx + mini_cell_w && my >= dcy && my < dcy + mini_cell_h {
			return m, d
		}
	}
	return 0, 0
}

// ─── Events ───────────────────────────────────────────────

pub fn (mut c Calendar) handle_event(event &GuiEvent, app &App) bool {
	if !c.visible || !c.enabled { return false }
	match event.typ {
		.mouse_move { return c.on_mouse_move(event) }
		.mouse_down { return c.on_mouse_down(event) }
		else { return false }
	}
}

fn (mut c Calendar) on_mouse_move(ev &GuiEvent) bool {
	mx := ev.mouse_x
	my := ev.mouse_y
	if !c.bounds.contains(mx, my) {
		c.hov_prev = false
		c.hov_next = false
		c.hov_title = false
		c.hov_day = 0
		c.hov_month = 0
		c.hov_year = 0
		return false
	}
	c.hov_prev = c.prev_rect().contains(mx, my)
	c.hov_next = c.next_rect().contains(mx, my)
	c.hov_title = c.title_rect().contains(mx, my)

	match c.view {
		.month {
			hy, hm, hd := c.hit_month_day(mx, my)
			c.hov_year = hy
			c.hov_month = hm
			c.hov_day = hd
		}
		.year {
			hm, hd := c.hit_year_day(mx, my, 14)
			if hm > 0 && hd > 0 {
				c.hov_year = c.year
				c.hov_month = hm
				c.hov_day = hd
			} else {
				c.hov_year = 0
				c.hov_month = 0
				c.hov_day = 0
			}
		}
	}
	return true
}

fn (mut c Calendar) on_mouse_down(ev &GuiEvent) bool {
	mx := ev.mouse_x
	my := ev.mouse_y
	if !c.bounds.contains(mx, my) { return false }

	if c.prev_rect().contains(mx, my) {
		c.navigate_prev()
		return true
	}
	if c.next_rect().contains(mx, my) {
		c.navigate_next()
		return true
	}
	if c.title_rect().contains(mx, my) {
		c.drill_up()
		return true
	}

	match c.view {
		.month {
			hy, hm, hd := c.hit_month_day(mx, my)
			if hd > 0 {
				c.sel_year = hy
				c.sel_month = hm
				c.sel_day = hd
				if c.on_select != unsafe { nil } {
					c.on_select(hy, hm, hd)
				}
			}
		}
		.year {
			hm, hd := c.hit_year_day(mx, my, 14)
			if hm > 0 && hd > 0 {
				c.sel_year = c.year
				c.sel_month = hm
				c.sel_day = hd
				if c.on_select != unsafe { nil } {
					c.on_select(c.year, hm, hd)
				}
			}
		}
	}
	return true
}
