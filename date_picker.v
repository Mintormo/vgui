module vgui

import time

// ═══════════════════════════════════════════════════════
// DatePicker — date selection widget with calendar popup
// Shows current date as text button. Click opens a dialog
// with month/year navigation and a 7×6 day grid.
// Usage:
//   mut dp := vgui.date_picker()
//   dp.on_change = fn (y int, m int, d int) { ... }
// ═══════════════════════════════════════════════════════

@[heap]
pub struct DatePicker {
pub mut:
	type_tag  int = kind_date_picker // тег типа, см. widget_tag.v
	bounds    Rect
	year      int
	month     int // 1-12
	day       int // 1-31
	visible   bool = true
	enabled   bool = true
	hovered   bool
	on_change fn (int, int, int) = unsafe { nil }
}

pub fn date_picker() &DatePicker {
	now := time.now()
	return &DatePicker{
		year:  now.year
		month: now.month
		day:   now.day
	}
}

pub fn date_picker_ymd(y int, m int, d int) &DatePicker {
	return &DatePicker{
		year:  y
		month: m
		day:   d
	}
}

pub fn (dp &DatePicker) get_date() (int, int, int) {
	return dp.year, dp.month, dp.day
}

pub fn (mut dp DatePicker) set_date(y int, m int, d int) {
	dp.year = y
	dp.month = clamp_int(m, 1, 12)
	dp.day = clamp_int(d, 1, dp_days_in_month(y, dp.month))
}

fn dp_format_date(y int, m int, d int) string {
	return '${y}-${dp_pad2(m)}-${dp_pad2(d)}'
}

fn dp_pad2(v int) string {
	return if v < 10 { '0${v}' } else { '${v}' }
}

fn dp_is_leap(y int) bool {
	return (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
}

fn dp_days_in_month(y int, m int) int {
	return match m {
		1 {
			31
		}
		2 {
			if dp_is_leap(y) {
				29
			} else {
				28
			}
		}
		3 {
			31
		}
		4 {
			30
		}
		5 {
			31
		}
		6 {
			30
		}
		7 {
			31
		}
		8 {
			31
		}
		9 {
			30
		}
		10 {
			31
		}
		11 {
			30
		}
		12 {
			31
		}
		else {
			30
		}
	}
}

// Zeller's congruence: day of week for given date (0=Sun, 1=Mon, ..., 6=Sat)
fn dp_day_of_week(y int, m int, d int) int {
	mut yy := y
	mut mm := m
	if mm < 3 {
		mm += 12
		yy -= 1
	}
	k := yy % 100
	j := yy / 100
	h := (d + (13 * (mm + 1)) / 5 + k + k / 4 + j / 4 - 2 * j) % 7
	// h: 0=Sat, 1=Sun, 2=Mon, ...
	dow := ((h + 6) % 7) // 0=Sun, 1=Mon, ...
	return if dow < 0 { dow + 7 } else { dow }
}

fn dp_month_name(m int) string {
	return match m {
		1 { 'January' }
		2 { 'February' }
		3 { 'March' }
		4 { 'April' }
		5 { 'May' }
		6 { 'June' }
		7 { 'July' }
		8 { 'August' }
		9 { 'September' }
		10 { 'October' }
		11 { 'November' }
		12 { 'December' }
		else { '?' }
	}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut dp DatePicker) draw(mut ctx RenderContext) {
	if !dp.visible {
		return
	}
	if !ctx.is_in_clip(dp.bounds) {
		return
	}
	rad := ctx.theme.border_radius
	bg := if dp.hovered && dp.enabled { ctx.theme.button_hover } else { ctx.theme.input_bg }
	ctx.fill_rounded_rect(dp.bounds, bg, rad)
	ctx.draw_rounded_rect(dp.bounds, ctx.theme.input_border, rad)
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	text := dp_format_date(dp.year, dp.month, dp.day)
	tw := ctx.measure_text_with_font(text, font).x
	tx := dp.bounds.x + (dp.bounds.w - tw) * 0.5
	ty := dp.bounds.y + (dp.bounds.h - fh) * 0.5
	tc := if dp.enabled { ctx.theme.text_primary } else { ctx.theme.text_disabled }
	ctx.draw_text_with_font(text, tx, ty, tc, font)
}

// ─── Events ────────────────────────────────────────────

pub fn (mut dp DatePicker) handle_event(event &GuiEvent, app &App) bool {
	if !dp.visible || !dp.enabled {
		return false
	}
	match event.typ {
		.mouse_move {
			dp.hovered = dp.bounds.contains(event.mouse_x, event.mouse_y)
		}
		.mouse_down {
			if event.mouse_btn == .left && dp.hovered {
				dp_open_dialog(mut dp, app)
				return true
			}
		}
		else {}
	}

	return false
}

// ─── Standalone calendar dialog ────────────────────────

@[params]
pub struct DateDialogConfig {
pub mut:
	title string = 'Select Date'
	year  int // 0 = today
	month int // 0 = today
	day   int // 0 = today
}

// date_dialog opens a modal calendar dialog and returns the chosen
// (year, month, day) along with a `confirmed` flag (false when the user
// cancels or closes the window). It is fully standalone — invoke it from
// any callback (e.g. a button's on_click), it is not tied to a DatePicker
// widget. When config year/month/day are 0, today's date is used.
pub fn date_dialog(parent &Window, mut app App, cfg DateDialogConfig) (int, int, int, bool) {
	now := time.now()
	y := if cfg.year > 0 { cfg.year } else { now.year }
	m := if cfg.month > 0 { cfg.month } else { now.month }
	d := if cfg.day > 0 { cfg.day } else { now.day }
	return dp_run_dialog(parent, mut app, y, m, d, cfg.title)
}

// ─── Widget dialog ─────────────────────────────────────

fn dp_open_dialog(mut dp DatePicker, app &App) {
	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return
	}

	mut parent := unsafe { &Window(nil) }
	for w in app.windows {
		if w.open && unsafe { &w.ctx == ctx_ptr } {
			parent = unsafe { w }
			break
		}
	}
	if unsafe { parent == nil } {
		for d in app.dialogs {
			if d.is_open() && unsafe { &d.win.ctx == ctx_ptr } {
				parent = unsafe { &d.win }
				break
			}
		}
	}
	if unsafe { parent == nil } {
		return
	}

	mut mapp := unsafe { &App(app) }
	y, m, d, confirmed := dp_run_dialog(parent, mut mapp, dp.year, dp.month, dp.day,
		'Select Date')
	if confirmed {
		dp.year = y
		dp.month = m
		dp.day = clamp_int(d, 1, dp_days_in_month(y, m))
		if dp.on_change != unsafe { nil } {
			dp.on_change(dp.year, dp.month, dp.day)
		}
	}
}

// ─── Shared modal dialog implementation ────────────────

fn dp_run_dialog(parent &Window, mut app App, year int, month int, day int, title string) (int, int, int, bool) {
	if unsafe { parent == nil } {
		return year, month, day, false
	}

	mut state := &DpState{
		year:    year
		month:   month
		day:     day
		app_ptr: unsafe { app }
	}

	mut dlg := create_dialog(DialogConfig{
		title:     title
		parent:    unsafe { parent }
		theme:     parent.ctx.theme
		font_path: parent.config.font_path
		mono_path: parent.config.mono_path
		font_data: parent.config.font_data
		mono_data: parent.config.mono_data
		font_size: parent.config.font_size
		mono_size: parent.config.mono_size
		ui_scale:  parent.ctx.ui_scale
	}) or { return year, month, day, false }
	state.dlg_ptr = dlg

	mut area := &DpArea{
		state: state
	}

	mut btn_today := button('Today')
	btn_today.style = .flat
	btn_today.on_click = fn [mut state] () {
		now := time.now()
		state.year = now.year
		state.month = now.month
		state.day = now.day
	}

	mut btn_ok := button('OK')
	btn_ok.style = .accent
	btn_ok.on_click = fn [mut state] () {
		state.confirmed = true
	}

	mut btn_cancel := button('Cancel')
	btn_cancel.on_click = fn [mut state] () {
		state.cancelled = true
	}

	mut btn_row := create_hbox_fill()
	btn_row.set_spacing(6)
	btn_row.set_padding(0)
	btn_row.add(btn_today)
	btn_row.add(create_spacer(), flex: 1)
	btn_row.add(btn_ok)
	btn_row.add(btn_cancel)

	mut main := create_vbox_fill()
	main.set_spacing(4)
	main.set_padding(10)
	main.add(area)
	main.add(btn_row)

	dlg.add_widget(main)
	app.add_dialog(dlg)
	dlg.show()

	for app.running && dlg.is_open() && !state.confirmed && !state.cancelled {
		app.process_events()
		app.render_all()
		C.SDL_Delay(16)
	}

	confirmed := state.confirmed
	mut ry := state.year
	mut rm := state.month
	mut rd := state.day
	if confirmed {
		rd = clamp_int(rd, 1, dp_days_in_month(ry, rm))
	}
	dlg.close_with_result(if confirmed { 1 } else { 0 })

	// Single-use dialog: free its SDL window/renderer and drop from app.dialogs.
	app.remove_dialog(dlg)
	dlg.win.cleanup()

	return ry, rm, rd, confirmed
}

// ─── Dialog state ──────────────────────────────────────

struct DpState {
mut:
	year      int
	month     int
	day       int
	confirmed bool
	cancelled bool
	app_ptr   &App    = unsafe { nil }
	dlg_ptr   &Dialog = unsafe { nil }
}

// ─── Calendar draw area ────────────────────────────────

struct DpArea {
mut:
	bounds  Rect
	state   &DpState = unsafe { nil }
	hovered int      = -1 // hovered day (1-based), -1 = none
}

const dp_day_names = ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su']

fn (mut a DpArea) draw(mut ctx RenderContext) {
	if unsafe { a.state == nil } {
		return
	}
	s := a.state

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	font_b := ctx.get_font(.bold, 0)

	pad := f32(4)
	nav_h := f32(28)
	hdr_h := fh + 4
	avail_h := a.bounds.h - nav_h - hdr_h - pad * 2
	cell_h := avail_h / 6.0
	cell_w := a.bounds.w / 7.0

	// ── Month/year navigation ──
	nav_y := a.bounds.y + pad
	title := '${dp_month_name(s.month)} ${s.year}'
	tw := ctx.measure_text_with_font(title, font_b).x
	title_x := a.bounds.x + (a.bounds.w - tw) * 0.5
	title_y := nav_y + (nav_h - fh) * 0.5
	ctx.draw_text_with_font(title, title_x, title_y, ctx.theme.text_primary, font_b)

	// < > arrows
	arrow_c := ctx.theme.text_secondary
	arr_sz := f32(6)
	// Left arrow
	lx := a.bounds.x + 16
	ly := nav_y + nav_h * 0.5
	ctx.fill_triangle(lx + arr_sz, ly - arr_sz, lx + arr_sz, ly + arr_sz, lx, ly, arrow_c)
	// Right arrow
	rx := a.bounds.x + a.bounds.w - 16
	ry := ly
	ctx.fill_triangle(rx - arr_sz, ry - arr_sz, rx - arr_sz, ry + arr_sz, rx, ry, arrow_c)

	// ── Day-of-week header ──
	hdr_y := nav_y + nav_h
	for i in 0 .. 7 {
		dx := a.bounds.x + f32(i) * cell_w
		dw := ctx.measure_text_with_font(dp_day_names[i], font).x
		ctx.draw_text_with_font(dp_day_names[i], dx + (cell_w - dw) * 0.5, hdr_y,
			ctx.theme.text_secondary, font)
	}

	// ── Day grid ──
	grid_y := hdr_y + hdr_h
	// Convert from 0=Sun to 0=Mon: (dow + 6) % 7
	first_dow := (dp_day_of_week(s.year, s.month, 1) + 6) % 7
	days := dp_days_in_month(s.year, s.month)

	for d in 1 .. days + 1 {
		idx := first_dow + d - 1
		col := idx % 7
		row := idx / 7
		cx := a.bounds.x + f32(col) * cell_w
		cy := grid_y + f32(row) * cell_h

		cell_r := Rect{cx + 2, cy + 1, cell_w - 4, cell_h - 2}
		is_sel := d == s.day
		is_hov := d == a.hovered

		if is_sel {
			ctx.fill_rounded_rect(cell_r, ctx.theme.accent, 4)
		} else if is_hov {
			ctx.fill_rounded_rect(cell_r, ctx.theme.button_hover, 4)
		}

		tc := if is_sel { ctx.theme.accent_text } else { ctx.theme.text_primary }
		ds := '${d}'
		dw := ctx.measure_text_with_font(ds, font).x
		ctx.draw_text_with_font(ds, cx + (cell_w - dw) * 0.5, cy + (cell_h - fh) * 0.5, tc, font)
	}
}

fn (mut a DpArea) handle_event(event &GuiEvent, app &App) bool {
	if unsafe { a.state == nil } {
		return false
	}
	mut s := a.state

	// Use fixed font height — we don't need ctx_ptr for event geometry
	fh := f32(16)

	pad := f32(4)
	nav_h := f32(28)
	hdr_h := fh + 4
	avail_h := a.bounds.h - nav_h - hdr_h - pad * 2
	cell_h := avail_h / 6.0
	cell_w := a.bounds.w / 7.0
	nav_y := a.bounds.y + pad
	grid_y := nav_y + nav_h + hdr_h

	first_dow := (dp_day_of_week(s.year, s.month, 1) + 6) % 7
	days := dp_days_in_month(s.year, s.month)

	match event.typ {
		.mouse_move {
			a.hovered = -1
			if event.mouse_y >= grid_y {
				for d in 1 .. days + 1 {
					idx := first_dow + d - 1
					col := idx % 7
					row := idx / 7
					cx := a.bounds.x + f32(col) * cell_w
					cy := grid_y + f32(row) * cell_h
					cell_r := Rect{cx, cy, cell_w, cell_h}
					if cell_r.contains(event.mouse_x, event.mouse_y) {
						a.hovered = d
						break
					}
				}
			}
		}
		.mouse_down {
			if event.mouse_btn == .left {
				// Nav arrows
				if event.mouse_y >= nav_y && event.mouse_y < nav_y + nav_h {
					if event.mouse_x < a.bounds.x + 40 {
						// Prev month
						s.month -= 1
						if s.month < 1 {
							s.month = 12
							s.year -= 1
						}
						s.day = clamp_int(s.day, 1, dp_days_in_month(s.year, s.month))
						return true
					}
					if event.mouse_x > a.bounds.x + a.bounds.w - 40 {
						// Next month
						s.month += 1
						if s.month > 12 {
							s.month = 1
							s.year += 1
						}
						s.day = clamp_int(s.day, 1, dp_days_in_month(s.year, s.month))
						return true
					}
				}
				// Day click
				if a.hovered > 0 {
					s.day = a.hovered
					return true
				}
			}
		}
		.mouse_dbl_click {
			if a.hovered > 0 {
				s.day = a.hovered
				s.confirmed = true
				return true
			}
		}
		.mouse_wheel {
			ctx_ptr := app.get_active_ctx()
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if a.bounds.contains(mx, my) {
				if event.wheel_y > 0 {
					s.month -= 1
					if s.month < 1 {
						s.month = 12
						s.year -= 1
					}
				} else if event.wheel_y < 0 {
					s.month += 1
					if s.month > 12 {
						s.month = 1
						s.year += 1
					}
				}
				s.day = clamp_int(s.day, 1, dp_days_in_month(s.year, s.month))
				return true
			}
		}
		else {}
	}

	return false
}
