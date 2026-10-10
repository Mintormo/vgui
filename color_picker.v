// Файл: ./color_picker.v
module vgui

import math

// ═══════════════════════════════════════════════════════
// ColorPicker — color selection widget
//
// Shows a color swatch button. Click opens a dialog with:
//   - SV rectangle (saturation x, value y) for current hue
//   - Hue vertical strip
//   - Alpha vertical strip (optional)
//   - Preview (old / new)
//   - Hex input (#RRGGBBAA)
//   - R/G/B/A numeric inputs (0-255)
//   - H/S/V numeric inputs (H: 0-360, S/V: 0-100)
//
// Usage:
//   mut cp := vgui.color_picker()
//   cp.color = Color{255, 0, 0, 255}
//   cp.on_change = fn (c Color) { ... }
// ═══════════════════════════════════════════════════════

@[heap]
pub struct ColorPicker {
pub mut:
	type_tag   int = kind_color_picker // тег типа, см. widget_tag.v
	bounds     Rect
	color      Color = Color{255, 0, 0, 255}
	visible    bool  = true
	enabled    bool  = true
	hovered    bool
	show_alpha bool       = true
	on_change  fn (Color) = unsafe { nil }
}

pub fn color_picker() &ColorPicker {
	return &ColorPicker{}
}

pub fn color_picker_with_color(c Color) &ColorPicker {
	return &ColorPicker{
		color: c
	}
}

pub fn (cp &ColorPicker) get_color() Color {
	return cp.color
}

pub fn (mut cp ColorPicker) set_color(c Color) {
	cp.color = c
}

fn cp_color_to_hex(c Color, alpha bool) string {
	if alpha && c.a != 255 {
		return '#${cp_hex2(c.r)}${cp_hex2(c.g)}${cp_hex2(c.b)}${cp_hex2(c.a)}'
	}
	return '#${cp_hex2(c.r)}${cp_hex2(c.g)}${cp_hex2(c.b)}'
}

fn cp_hex2(v u8) string {
	hi := v >> 4
	lo := v & 0x0F
	mut buf := []u8{cap: 2}
	buf << if hi < 10 { hi + `0` } else { hi - 10 + `A` }
	buf << if lo < 10 { lo + `0` } else { lo - 10 + `A` }
	return buf.bytestr()
}

// ─── HSV ↔ RGB conversion ─────────────────────────────

fn cp_rgb_to_hsv(r u8, g u8, b u8) (f32, f32, f32) {
	rf := f32(r) / 255.0
	gf := f32(g) / 255.0
	bf := f32(b) / 255.0
	mx := max_f32(rf, max_f32(gf, bf))
	mn := min_f32(rf, min_f32(gf, bf))
	d := mx - mn
	mut h := f32(0)
	s := if mx > 0 { d / mx } else { f32(0) }
	v := mx
	if d > 0 {
		if mx == rf {
			h = (gf - bf) / d
			if h < 0 {
				h += 6
			}
		} else if mx == gf {
			h = (bf - rf) / d + 2
		} else {
			h = (rf - gf) / d + 4
		}
		h *= 60
	}
	return h, s, v
}

fn cp_hsv_to_rgb(h f32, s f32, v f32) (u8, u8, u8) {
	if s <= 0 {
		val := u8(v * 255 + 0.5)
		return val, val, val
	}
	hh := if h >= 360 { f32(0) } else { h } / 60.0
	i := int(hh)
	ff := hh - f32(i)
	p := v * (1.0 - s)
	q := v * (1.0 - s * ff)
	t := v * (1.0 - s * (1.0 - ff))
	mut rf, mut gf, mut bf := f32(0), f32(0), f32(0)
	match i {
		0 {
			rf = v
			gf = t
			bf = p
		}
		1 {
			rf = q
			gf = v
			bf = p
		}
		2 {
			rf = p
			gf = v
			bf = t
		}
		3 {
			rf = p
			gf = q
			bf = v
		}
		4 {
			rf = t
			gf = p
			bf = v
		}
		else {
			rf = v
			gf = p
			bf = q
		}
	}

	return u8(rf * 255 + 0.5), u8(gf * 255 + 0.5), u8(bf * 255 + 0.5)
}

fn cp_hue_color(h f32) Color {
	r, g, b := cp_hsv_to_rgb(h, 1.0, 1.0)
	return Color{r, g, b, 255}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut cp ColorPicker) draw(mut ctx RenderContext) {
	if !cp.visible {
		return
	}
	if !ctx.is_in_clip(cp.bounds) {
		return
	}
	rad := ctx.theme.border_radius
	ctx.fill_rounded_rect(cp.bounds, cp.color, rad)
	if cp.color.a < 255 {
		ctx.draw_rounded_rect(cp.bounds, ctx.theme.input_border, rad)
	}
	bc := if cp.hovered && cp.enabled { ctx.theme.accent } else { ctx.theme.input_border }
	ctx.draw_rounded_rect(cp.bounds, bc, rad)
	font := ctx.get_font(.mono, 0)
	fh := ctx.font_height_of(font)
	hex := cp_color_to_hex(cp.color, cp.show_alpha)
	tw := ctx.measure_text_with_font(hex, font).x
	tx := cp.bounds.x + (cp.bounds.w - tw) * 0.5
	ty := cp.bounds.y + (cp.bounds.h - fh) * 0.5
	lum := f32(cp.color.r) * 0.299 + f32(cp.color.g) * 0.587 + f32(cp.color.b) * 0.114
	tc := if lum > 128 { color_black } else { color_white }
	ctx.draw_text_with_font(hex, tx, ty, tc, font)
}

// ─── Events ────────────────────────────────────────────

pub fn (mut cp ColorPicker) handle_event(event &GuiEvent, app &App) bool {
	if !cp.visible || !cp.enabled {
		return false
	}
	match event.typ {
		.mouse_move {
			cp.hovered = cp.bounds.contains(event.mouse_x, event.mouse_y)
		}
		.mouse_down {
			if event.mouse_btn == .left && cp.hovered {
				cp_open_dialog(mut cp, app)
				return true
			}
		}
		else {}
	}

	return false
}

// ─── Standalone dialog ─────────────────────────────────

@[params]
pub struct ColorDialogConfig {
pub mut:
	title      string = 'Color Picker'
	color      Color  = Color{255, 0, 0, 255}
	show_alpha bool   = true
}

// color_dialog opens a modal color picker dialog and returns the chosen
// color along with a `confirmed` flag (false when the user cancels or
// closes the window). It is fully standalone — invoke it from any callback
// (e.g. a button's on_click), it is not tied to a ColorPicker widget.
pub fn color_dialog(parent &Window, mut app App, cfg ColorDialogConfig) (Color, bool) {
	return cp_run_dialog(parent, mut app, cfg.color, cfg.show_alpha, cfg.title)
}

// ─── Widget dialog ─────────────────────────────────────

fn cp_open_dialog(mut cp ColorPicker, app &App) {
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
	chosen, confirmed := cp_run_dialog(parent, mut mapp, cp.color, cp.show_alpha, 'Color Picker')
	if confirmed {
		cp.color = chosen
		if cp.on_change != unsafe { nil } {
			cp.on_change(cp.color)
		}
	}
}

// ─── Shared modal dialog implementation ────────────────

fn cp_run_dialog(parent &Window, mut app App, initial Color, show_alpha bool, title string) (Color, bool) {
	if unsafe { parent == nil } {
		return initial, false
	}

	mut state := &CpState{
		original: initial
		current:  initial
		app_ptr:  unsafe { app }
	}
	h, s, v := cp_rgb_to_hsv(initial.r, initial.g, initial.b)
	state.hue = h
	state.sat = s
	state.val = v
	state.alpha = f32(initial.a) / 255.0
	state.show_alpha = show_alpha

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
	}) or { return initial, false }

	state.dlg_ptr = dlg

	mut area := &CpArea{
		state: state
	}

	// ── Hex input ──
	mut hex_input := text_input('#RRGGBB')
	hex_input.set_text(cp_color_to_hex(state.current, state.show_alpha))
	state.hex_input = hex_input

	hex_input.on_submit = fn [mut state] (text string) {
		c := vui_parse_color(text)
		if c.a > 0 || text.contains('00') {
			state.current = c
			hh, ss, vv := cp_rgb_to_hsv(c.r, c.g, c.b)
			state.hue = hh
			state.sat = ss
			state.val = vv
			state.alpha = f32(c.a) / 255.0
			cp_sync_component_inputs(state)
		}
	}

	// ── RGBA component inputs ──
	mut inp_r := text_input('R')
	inp_r.chars = 4
	mut inp_g := text_input('G')
	inp_g.chars = 4
	mut inp_b := text_input('B')
	inp_b.chars = 4
	mut inp_a := text_input('A')
	inp_a.chars = 4
	inp_r.max_len = 3
	inp_g.max_len = 3
	inp_b.max_len = 3
	inp_a.max_len = 3
	inp_r.set_text('${state.current.r}')
	inp_g.set_text('${state.current.g}')
	inp_b.set_text('${state.current.b}')
	inp_a.set_text('${state.current.a}')

	state.inp_r = inp_r
	state.inp_g = inp_g
	state.inp_b = inp_b
	state.inp_a = inp_a

	inp_r.on_submit = fn [mut state] (text string) {
		cp_apply_rgba_from_inputs(mut state)
	}
	inp_g.on_submit = fn [mut state] (text string) {
		cp_apply_rgba_from_inputs(mut state)
	}
	inp_b.on_submit = fn [mut state] (text string) {
		cp_apply_rgba_from_inputs(mut state)
	}
	inp_a.on_submit = fn [mut state] (text string) {
		cp_apply_rgba_from_inputs(mut state)
	}

	// ── HSV component inputs ──
	mut inp_h := text_input('H')
	inp_h.chars = 4
	mut inp_s := text_input('S')
	inp_s.chars = 4
	mut inp_v := text_input('V')
	inp_v.chars = 4
	inp_h.max_len = 3
	inp_s.max_len = 3
	inp_v.max_len = 3
	inp_h.set_text('${int(state.hue + 0.5)}')
	inp_s.set_text('${int(state.sat * 100 + 0.5)}')
	inp_v.set_text('${int(state.val * 100 + 0.5)}')

	state.inp_h = inp_h
	state.inp_s = inp_s
	state.inp_v = inp_v

	inp_h.on_submit = fn [mut state] (text string) {
		cp_apply_hsv_from_inputs(mut state)
	}
	inp_s.on_submit = fn [mut state] (text string) {
		cp_apply_hsv_from_inputs(mut state)
	}
	inp_v.on_submit = fn [mut state] (text string) {
		cp_apply_hsv_from_inputs(mut state)
	}

	// ── helper: make a label+input pair row ──
	lbl_color := Color{180, 180, 180, 255}

	make_lbl := fn [lbl_color] (text string) &Label {
		mut l := label(text)
		l.color = lbl_color
		l.align = .right
		l.valign = .middle
		return l
	}

	// Подпись забирает остаток ряда (прижата вправо) - поля одной
	// ширины (chars) встают ровной колонкой у правого края
	make_field_row := fn [make_lbl] (lbl_text string, inp &TextInput) &HBox {
		mut row := create_hbox_fill()
		row.set_spacing(4)
		row.set_padding(0)
		row.add(make_lbl(lbl_text), flex: 1)
		row.add(unsafe { inp })
		return row
	}

	// Section title aligned to the left edge of the whole label+input group
	make_title_row := fn (text string) &HBox {
		mut title := label(text)
		title.font_style = .bold
		title.color = Color{140, 200, 255, 255}
		title.align = .left
		title.valign = .middle
		title.pad = 0
		mut row := create_hbox_fill()
		row.set_spacing(0)
		row.set_padding(0)
		row.add(title, flex: 1)
		return row
	}

	// ── Buttons ──
	mut btn_ok := button('OK')
	btn_ok.style = .accent
	btn_ok.on_click = fn [mut state] () {
		state.confirmed = true
	}

	mut btn_cancel := button('Cancel')
	btn_cancel.on_click = fn [mut state] () {
		state.cancelled = true
	}

	// ── Right column: HSV + RGB(A), top-aligned via spacer ──
	mut right_col := create_vbox_fill()
	right_col.set_spacing(4)
	right_col.set_padding(0)

	right_col.add(make_title_row('HSV'))
	right_col.add(make_field_row('H:', inp_h))
	right_col.add(make_field_row('S:', inp_s))
	right_col.add(make_field_row('V:', inp_v))
	right_col.add(hseparator())

	right_col.add(make_title_row(if state.show_alpha { 'RGB(A)' } else { 'RGB' }))
	right_col.add(make_field_row('R:', inp_r))
	right_col.add(make_field_row('G:', inp_g))
	right_col.add(make_field_row('B:', inp_b))
	if state.show_alpha {
		right_col.add(make_field_row('A:', inp_a))
	}
	right_col.add(create_spacer(), flex: 1)

	// ── Bottom row: preview + hex + OK + Cancel ──
	mut preview := &CpPreview{
		state: state
	}
	mut btn_row := create_hbox_fill()
	btn_row.set_spacing(6)
	btn_row.set_padding(0)
	// Ширина превью - по подписям "Old"/"New" (CpPreview.measure)
	btn_row.add(preview)
	btn_row.add(hex_input, flex: 1)
	btn_row.add(btn_ok)
	btn_row.add(btn_cancel)

	// ── Middle: SV area left + right col ──
	mut mid_row := create_hbox_fill()
	mid_row.set_spacing(10)
	mid_row.set_padding(0)
	mid_row.add(area)
	mid_row.add(right_col)

	mut main := create_vbox_fill()
	main.set_spacing(6)
	main.set_padding(12)
	main.add(mid_row, flex: 1)
	main.add(hseparator())
	main.add(btn_row)

	dlg.add_widget(main)
	app.add_dialog(dlg)
	dlg.show()

	// Modal loop
	for app.running && dlg.is_open() && !state.confirmed && !state.cancelled {
		app.process_events()
		// Sync hex input (only when not focused)
		if unsafe { state.hex_input != nil } {
			expected := cp_color_to_hex(state.current, state.show_alpha)
			if state.hex_input.get_text() != expected && !state.hex_input.focused {
				state.hex_input.set_text(expected)
			}
		}
		// Sync RGBA/HSV inputs (only when not focused)
		cp_sync_inputs_if_not_focused(state)
		app.render_all()
		C.SDL_Delay(16)
	}

	result := state.current
	confirmed := state.confirmed
	dlg.close_with_result(if confirmed { 1 } else { 0 })

	// Single-use dialog: free its SDL window/renderer and drop from app.dialogs.
	app.remove_dialog(dlg)
	dlg.win.cleanup()

	return result, confirmed
}

// ─── Internal dialog state ─────────────────────────────

struct CpState {
mut:
	original   Color
	current    Color
	hue        f32
	sat        f32
	val        f32
	alpha      f32 = 1.0
	show_alpha bool
	confirmed  bool
	cancelled  bool
	app_ptr    &App       = unsafe { nil }
	dlg_ptr    &Dialog    = unsafe { nil }
	hex_input  &TextInput = unsafe { nil }
	// RGBA inputs
	inp_r &TextInput = unsafe { nil }
	inp_g &TextInput = unsafe { nil }
	inp_b &TextInput = unsafe { nil }
	inp_a &TextInput = unsafe { nil }
	// HSV inputs
	inp_h      &TextInput = unsafe { nil }
	inp_s      &TextInput = unsafe { nil }
	inp_v      &TextInput = unsafe { nil }
	drag_sv    bool
	drag_hue   bool
	drag_alpha bool
}

fn (mut s CpState) update_current() {
	r, g, b := cp_hsv_to_rgb(s.hue, s.sat, s.val)
	s.current = Color{r, g, b, u8(s.alpha * 255 + 0.5)}
}

// Apply RGBA from text inputs → state
fn cp_apply_rgba_from_inputs(mut s CpState) {
	r := clamp_int(if unsafe { s.inp_r != nil } { s.inp_r.get_text().int() } else { 0 }, 0, 255)
	g := clamp_int(if unsafe { s.inp_g != nil } { s.inp_g.get_text().int() } else { 0 }, 0, 255)
	b := clamp_int(if unsafe { s.inp_b != nil } { s.inp_b.get_text().int() } else { 0 }, 0, 255)
	a := clamp_int(if unsafe { s.inp_a != nil } { s.inp_a.get_text().int() } else { 255 }, 0, 255)
	s.current = Color{u8(r), u8(g), u8(b), u8(a)}
	h, sv_s, v := cp_rgb_to_hsv(u8(r), u8(g), u8(b))
	s.hue = h
	s.sat = sv_s
	s.val = v
	s.alpha = f32(a) / 255.0
}

// Apply HSV from text inputs → state
fn cp_apply_hsv_from_inputs(mut s CpState) {
	h := clamp_int(if unsafe { s.inp_h != nil } { s.inp_h.get_text().int() } else { 0 }, 0, 360)
	sv := clamp_int(if unsafe { s.inp_s != nil } { s.inp_s.get_text().int() } else { 0 }, 0, 100)
	v := clamp_int(if unsafe { s.inp_v != nil } { s.inp_v.get_text().int() } else { 0 }, 0, 100)
	s.hue = f32(h)
	s.sat = f32(sv) / 100.0
	s.val = f32(v) / 100.0
	s.update_current()
}

// Force-sync all component inputs to current state values
fn cp_sync_component_inputs(s &CpState) {
	if unsafe { s.inp_r != nil } {
		mut r := unsafe { s.inp_r }
		r.set_text('${s.current.r}')
	}
	if unsafe { s.inp_g != nil } {
		mut g := unsafe { s.inp_g }
		g.set_text('${s.current.g}')
	}
	if unsafe { s.inp_b != nil } {
		mut b := unsafe { s.inp_b }
		b.set_text('${s.current.b}')
	}
	if unsafe { s.inp_a != nil } {
		mut a := unsafe { s.inp_a }
		a.set_text('${s.current.a}')
	}
	if unsafe { s.inp_h != nil } {
		mut h := unsafe { s.inp_h }
		h.set_text('${int(s.hue + 0.5)}')
	}
	if unsafe { s.inp_s != nil } {
		mut sv := unsafe { s.inp_s }
		sv.set_text('${int(s.sat * 100 + 0.5)}')
	}
	if unsafe { s.inp_v != nil } {
		mut v := unsafe { s.inp_v }
		v.set_text('${int(s.val * 100 + 0.5)}')
	}
}

// Sync inputs only when they are NOT focused (avoids fighting with user typing)
fn cp_sync_inputs_if_not_focused(s &CpState) {
	if unsafe { s.inp_r != nil } && !s.inp_r.focused {
		mut r := unsafe { s.inp_r }
		expected := '${s.current.r}'
		if r.get_text() != expected {
			r.set_text(expected)
		}
	}
	if unsafe { s.inp_g != nil } && !s.inp_g.focused {
		mut g := unsafe { s.inp_g }
		expected := '${s.current.g}'
		if g.get_text() != expected {
			g.set_text(expected)
		}
	}
	if unsafe { s.inp_b != nil } && !s.inp_b.focused {
		mut b := unsafe { s.inp_b }
		expected := '${s.current.b}'
		if b.get_text() != expected {
			b.set_text(expected)
		}
	}
	if unsafe { s.inp_a != nil } && !s.inp_a.focused {
		mut a := unsafe { s.inp_a }
		expected := '${s.current.a}'
		if a.get_text() != expected {
			a.set_text(expected)
		}
	}
	if unsafe { s.inp_h != nil } && !s.inp_h.focused {
		mut h := unsafe { s.inp_h }
		expected := '${int(s.hue + 0.5)}'
		if h.get_text() != expected {
			h.set_text(expected)
		}
	}
	if unsafe { s.inp_s != nil } && !s.inp_s.focused {
		mut sv := unsafe { s.inp_s }
		expected := '${int(s.sat * 100 + 0.5)}'
		if sv.get_text() != expected {
			sv.set_text(expected)
		}
	}
	if unsafe { s.inp_v != nil } && !s.inp_v.focused {
		mut v := unsafe { s.inp_v }
		expected := '${int(s.val * 100 + 0.5)}'
		if v.get_text() != expected {
			v.set_text(expected)
		}
	}
}

// ─── Custom draw area for SV + Hue + Alpha ─────────────

struct CpArea {
mut:
	bounds Rect
	state  &CpState = unsafe { nil }
}

fn (mut a CpArea) draw(mut ctx RenderContext) {
	if unsafe { a.state == nil } {
		return
	}
	s := a.state

	strip_w := f32(18)
	gap := f32(8)
	strips_count := if s.show_alpha { 2 } else { 1 }
	strips_total := f32(strips_count) * strip_w + f32(strips_count) * gap
	sv_size := min_f32(a.bounds.w - strips_total, a.bounds.h)
	if sv_size < 20 {
		return
	}

	sv_x := a.bounds.x
	sv_y := a.bounds.y
	hue_x := sv_x + sv_size + gap
	hue_w := strip_w
	alpha_x := hue_x + hue_w + gap
	alpha_w := strip_w

	// ── SV rectangle ──
	steps := 32
	cell_w := sv_size / f32(steps)
	cell_h := sv_size / f32(steps)
	for yi in 0 .. steps {
		for xi in 0 .. steps {
			sv_s := (f32(xi) + 0.5) / f32(steps)
			sv_v := 1.0 - (f32(yi) + 0.5) / f32(steps)
			r, g, b := cp_hsv_to_rgb(s.hue, sv_s, sv_v)
			cx := sv_x + f32(xi) * cell_w
			cy := sv_y + f32(yi) * cell_h
			ctx.fill_rect(Rect{cx, cy, cell_w + 1, cell_h + 1}, Color{r, g, b, 255})
		}
	}
	ctx.draw_rounded_rect(Rect{sv_x, sv_y, sv_size, sv_size}, ctx.theme.border, 2)

	// SV cursor
	cur_x := sv_x + s.sat * sv_size
	cur_y := sv_y + (1.0 - s.val) * sv_size
	ctx.draw_circle(cur_x, cur_y, 6, color_white)
	ctx.draw_circle(cur_x, cur_y, 5, color_black)

	// ── Hue strip ──
	hue_steps := 36
	hue_cell_h := sv_size / f32(hue_steps)
	for i in 0 .. hue_steps {
		h := f32(i) / f32(hue_steps) * 360.0
		c := cp_hue_color(h)
		hy := sv_y + f32(i) * hue_cell_h
		ctx.fill_rect(Rect{hue_x, hy, hue_w, hue_cell_h + 1}, c)
	}
	ctx.draw_rounded_rect(Rect{hue_x, sv_y, hue_w, sv_size}, ctx.theme.border, 2)
	hue_cy := sv_y + (s.hue / 360.0) * sv_size
	ctx.fill_rect(Rect{hue_x - 2, hue_cy - 2, hue_w + 4, 4}, color_white)
	ctx.draw_rect(Rect{hue_x - 2, hue_cy - 2, hue_w + 4, 4}, color_black)

	// ── Alpha strip ──
	if s.show_alpha {
		for i in 0 .. hue_steps {
			a_val := 1.0 - f32(i) / f32(hue_steps)
			r, g, b := cp_hsv_to_rgb(s.hue, s.sat, s.val)
			c := Color{r, g, b, u8(a_val * 255 + 0.5)}
			ay := sv_y + f32(i) * hue_cell_h
			ctx.fill_rect(Rect{alpha_x, ay, alpha_w, hue_cell_h + 1}, c)
		}
		ctx.draw_rounded_rect(Rect{alpha_x, sv_y, alpha_w, sv_size}, ctx.theme.border, 2)
		alpha_cy := sv_y + (1.0 - s.alpha) * sv_size
		ctx.fill_rect(Rect{alpha_x - 2, alpha_cy - 2, alpha_w + 4, 4}, color_white)
		ctx.draw_rect(Rect{alpha_x - 2, alpha_cy - 2, alpha_w + 4, 4}, color_black)
	}

	_ = math.cosf(0) // ensure math import used
}

fn (mut a CpArea) handle_event(event &GuiEvent, _ &App) bool {
	if unsafe { a.state == nil } {
		return false
	}
	mut s := a.state

	strip_w := f32(18)
	gap := f32(8)
	strips_count := if s.show_alpha { 2 } else { 1 }
	strips_total := f32(strips_count) * strip_w + f32(strips_count) * gap
	sv_size := min_f32(a.bounds.w - strips_total, a.bounds.h)
	if sv_size < 20 {
		return false
	}

	sv_x := a.bounds.x
	sv_y := a.bounds.y
	hue_x := sv_x + sv_size + gap
	hue_w := strip_w
	alpha_x := hue_x + hue_w + gap
	alpha_w := strip_w

	sv_rect := Rect{sv_x, sv_y, sv_size, sv_size}
	hue_rect := Rect{hue_x, sv_y, hue_w, sv_size}
	alpha_rect := Rect{alpha_x, sv_y, alpha_w, sv_size}

	match event.typ {
		.mouse_down {
			if event.mouse_btn == .left {
				if sv_rect.contains(event.mouse_x, event.mouse_y) {
					s.drag_sv = true
					s.sat = clamp_f32((event.mouse_x - sv_x) / sv_size, 0, 1)
					s.val = clamp_f32(1.0 - (event.mouse_y - sv_y) / sv_size, 0, 1)
					s.update_current()
					return true
				}
				if hue_rect.contains(event.mouse_x, event.mouse_y) {
					s.drag_hue = true
					s.hue = clamp_f32((event.mouse_y - sv_y) / sv_size, 0, 1) * 360.0
					s.update_current()
					return true
				}
				if s.show_alpha && alpha_rect.contains(event.mouse_x, event.mouse_y) {
					s.drag_alpha = true
					s.alpha = clamp_f32(1.0 - (event.mouse_y - sv_y) / sv_size, 0, 1)
					s.update_current()
					return true
				}
			}
		}
		.mouse_move {
			if s.drag_sv {
				s.sat = clamp_f32((event.mouse_x - sv_x) / sv_size, 0, 1)
				s.val = clamp_f32(1.0 - (event.mouse_y - sv_y) / sv_size, 0, 1)
				s.update_current()
				return true
			}
			if s.drag_hue {
				s.hue = clamp_f32((event.mouse_y - sv_y) / sv_size, 0, 1) * 360.0
				s.update_current()
				return true
			}
			if s.drag_alpha {
				s.alpha = clamp_f32(1.0 - (event.mouse_y - sv_y) / sv_size, 0, 1)
				s.update_current()
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left {
				s.drag_sv = false
				s.drag_hue = false
				s.drag_alpha = false
			}
		}
		else {}
	}

	return false
}

// ─── Preview widget: shows old vs new color ────────────

struct CpPreview {
mut:
	bounds Rect
	state  &CpState = unsafe { nil }
}

fn (mut p CpPreview) draw(mut ctx RenderContext) {
	if unsafe { p.state == nil } {
		return
	}
	s := p.state
	half_w := p.bounds.w * 0.5
	ctx.fill_rounded_rect(Rect{p.bounds.x, p.bounds.y, half_w, p.bounds.h}, s.original, 3)
	ctx.fill_rounded_rect(Rect{p.bounds.x + half_w, p.bounds.y, half_w, p.bounds.h}, s.current, 3)
	ctx.draw_rounded_rect(Rect{p.bounds.x, p.bounds.y, p.bounds.w, p.bounds.h}, ctx.theme.border, 3)
	// Клип на собственный bounds — не даёт подписям 'Old'/'New' вылезти
	// на соседний виджет в строке (btn_row), если превью когда-нибудь
	// окажется у́же, чем нужно этим подписям. От взаимного наложения
	// 'Old' на 'New' клип не защищает — это на ширине p.bounds.w (сама
	// подпись начинается на half_w + 4), не на этом push_clip.
	ctx.push_clip(p.bounds)
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	ctx.draw_text_with_font('Old', p.bounds.x + 4, p.bounds.y + (p.bounds.h - fh) * 0.5,
		ctx.theme.text_secondary, font)
	ctx.draw_text_with_font('New', p.bounds.x + half_w + 4, p.bounds.y + (p.bounds.h - fh) * 0.5,
		ctx.theme.text_secondary, font)
	ctx.pop_clip()
}

fn (mut p CpPreview) handle_event(_ &GuiEvent, _ &App) bool {
	return false
}
