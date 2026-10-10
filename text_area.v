module vgui

// ═══════════════════════════════════════════════════════════
//  TextArea — multi-line editable text field with undo/redo,
//  word-wrap, vertical scrolling, and selection.
// ═══════════════════════════════════════════════════════════

const ta_max_undo = 100

struct TaUndoEntry {
	lines []string
	cur_l int
	cur_c int
}

@[heap]
pub struct TextArea {
pub mut:
	type_tag int = kind_text_area // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel       bool = true
	bounds      Rect
	pad         f32      = 6
	lines       []string = ['']
	placeholder string
	visible     bool = true
	enabled     bool = true
	focused     bool
	hovered     bool
	max_len     int = 262144
	// cursor position: line index + column (rune index within line)
	cur_l int
	cur_c int
	// selection anchor
	sel_al int = -1
	sel_ac int = -1
	// scroll
	scroll_y f32
	scroll_x f32
	drag     bool
	// scrollbar drag state
	vscroll_drag     bool
	vscroll_drag_off f32
	hscroll_drag     bool
	hscroll_drag_off f32
	focus_t          Anim = anim_smooth(anim_tau_focus)
	flat             bool
	// undo/redo
	history UndoHistory[TaUndoEntry] = UndoHistory[TaUndoEntry]{
		limit: ta_max_undo
	}

	on_change   fn (string) = unsafe { nil }
	focus_group int
}

pub fn text_area(placeholder string) &TextArea {
	return &TextArea{
		placeholder: placeholder
	}
}

// ───────────── public helpers ───────────────────────────

pub fn (ta &TextArea) get_text() string {
	return ta.lines.join('\n')
}

pub fn (mut ta TextArea) set_text(s string) {
	ta.lines = s.split('\n')
	if ta.lines.len == 0 {
		ta.lines = ['']
	}
	ta.cur_l = ta.lines.len - 1
	ta.cur_c = ta.lines[ta.cur_l].runes().len
	ta.sel_al = -1
	ta.sel_ac = -1
	ta.scroll_y = 0
	ta.scroll_x = 0
	ta.history.clear()
}

pub fn (mut ta TextArea) append_text(s string) {
	if s.len == 0 {
		return
	}
	added := s.split('\n')
	last_idx := ta.lines.len - 1
	ta.lines[last_idx] = ta.lines[last_idx] + added[0]
	for i in 1 .. added.len {
		ta.lines << added[i]
	}
	ta.cur_l = ta.lines.len - 1
	ta.cur_c = ta.lines[ta.cur_l].runes().len
	if ta.on_change != unsafe { nil } {
		ta.on_change(ta.get_text())
	}
}

// ───────────── undo / redo ─────────────────────────────

fn (ta &TextArea) snap() TaUndoEntry {
	return TaUndoEntry{
		lines: ta.lines.clone()
		cur_l: ta.cur_l
		cur_c: ta.cur_c
	}
}

fn (mut ta TextArea) save_undo() {
	ta.history.save(ta.snap())
}

fn (mut ta TextArea) restore(entry TaUndoEntry) {
	ta.lines = entry.lines.clone()
	ta.cur_l = entry.cur_l
	ta.cur_c = entry.cur_c
	ta.clear_sel()
	ta.fire()
}

// undo отменяет последнюю правку (как Ctrl+Z); false — отменять нечего.
pub fn (mut ta TextArea) undo() bool {
	entry := ta.history.undo(ta.snap()) or { return false }
	ta.restore(entry)
	return true
}

// redo повторяет отменённую правку (как Ctrl+Shift+Z).
pub fn (mut ta TextArea) redo() bool {
	entry := ta.history.redo(ta.snap()) or { return false }
	ta.restore(entry)
	return true
}

pub fn (ta &TextArea) can_undo() bool {
	return ta.history.can_undo()
}

pub fn (ta &TextArea) can_redo() bool {
	return ta.history.can_redo()
}

// clear_undo забывает историю правок (например, после загрузки документа).
pub fn (mut ta TextArea) clear_undo() {
	ta.history.clear()
}

// ───────────── selection helpers ───────────────────────

fn (ta &TextArea) has_sel() bool {
	if ta.sel_al < 0 {
		return false
	}
	return ta.sel_al != ta.cur_l || ta.sel_ac != ta.cur_c
}

fn (ta &TextArea) sel_start() (int, int) {
	if ta.sel_al < ta.cur_l || (ta.sel_al == ta.cur_l && ta.sel_ac < ta.cur_c) {
		return ta.sel_al, ta.sel_ac
	}
	return ta.cur_l, ta.cur_c
}

fn (ta &TextArea) sel_end() (int, int) {
	if ta.sel_al < ta.cur_l || (ta.sel_al == ta.cur_l && ta.sel_ac < ta.cur_c) {
		return ta.cur_l, ta.cur_c
	}
	return ta.sel_al, ta.sel_ac
}

fn (mut ta TextArea) clear_sel() {
	ta.sel_al = -1
	ta.sel_ac = -1
}

fn (mut ta TextArea) ensure_sel() {
	if ta.sel_al < 0 {
		ta.sel_al = ta.cur_l
		ta.sel_ac = ta.cur_c
	}
}

fn (ta &TextArea) selected_text() string {
	if !ta.has_sel() {
		return ''
	}
	sl, sc := ta.sel_start()
	el, ec := ta.sel_end()
	if sl == el {
		r := ta.lines[sl].runes()
		return r[sc..ec].string()
	}
	mut parts := []string{}
	parts << ta.lines[sl].runes()[sc..].string()
	for i in sl + 1 .. el {
		parts << ta.lines[i]
	}
	parts << ta.lines[el].runes()[..ec].string()
	return parts.join('\n')
}

// ───────────── drawing ─────────────────────────────────

pub fn (mut ta TextArea) draw(mut ctx RenderContext) {
	if !ta.visible {
		return
	}
	// Registration + focus-sync run regardless of whether this widget falls
	// inside the current (possibly partial) frame's clip — neither is pixel
	// output, both determine tab order / focused state, which must stay
	// correct even for a widget a partial frame happens not to touch.
	//
	// BEHAVIOR CHANGE from before dirty regions: registration used to happen
	// only past the (now-later) is_in_clip check, so a fully-clipped-out
	// TextArea was invisible to the FocusManager and Tab would skip it. Now
	// it registers unconditionally (as long as `enabled`), so Tab can reach
	// it even while it is entirely clipped away — a side effect of moving
	// this block ahead of is_in_clip for the cursor-blink fix below, not an
	// intentional focus-order redesign (mirrors the same change in
	// text_input.v).
	if ta.enabled {
		ctx.focus.register_text_area(&ta, ta.focus_group)
	}

	should_focus := ctx.focus.is_focused(unsafe { &ta })
	if ta.focused && !should_focus {
		ta.focused = false
		ta.drag = false
		ta.clear_sel()
	} else if !ta.focused && should_focus {
		ta.focused = true
	}

	// Re-arm the cursor-blink animation independent of clip: a partial
	// frame's dirty rect can legitimately miss this widget (some OTHER
	// widget's small area changed this frame). mark_anim_rect (not a raw
	// ctx.needs_animation = true write) so the dirty tracker actually
	// schedules ta's rect for the NEXT frame.
	if ta.focused {
		ctx.mark_anim_rect('textarea', ta.bounds)
	}

	if !ctx.is_in_clip(ta.bounds) {
		return
	}

	tgt := if ta.focused { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if ta.focus_t.update(tgt, ctx) {
		ctx.mark_anim_rect('textarea', ta.bounds.expanded(1))
	}

	rad := ctx.theme.border_radius
	if !ta.flat {
		bg := if ta.enabled { ctx.theme.input_bg } else { ctx.theme.input_bg.darken(0.05) }
		ctx.fill_rounded_rect(ta.bounds, bg, rad)
		bc := ctx.theme.input_border.blend(ctx.theme.input_focus, ta.focus_t.value)
		ctx.draw_rounded_rect(ta.bounds, bc, rad)
		ctx.draw_focus_ring_edge(ta.bounds, rad, ta.focus_t.value)
	}

	cr := ta.bounds.shrunk(ta.pad)
	ctx.push_clip(cr)

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	line_step := fh + 2

	// Compute max text width for horizontal scroll
	mut total_w := f32(0)
	for line in ta.lines {
		w := ctx.measure_text_with_font(line, font).x
		if w > total_w {
			total_w = w
		}
	}
	total_w += 4 // small right margin

	// Horizontal scrollbar height (shown when needed)
	sb_h_sz := f32(5)
	h_scroll_visible := total_w > cr.w
	// Effective content height available (leave room for h-scrollbar)
	cr_h := if h_scroll_visible { cr.h - sb_h_sz - 2 } else { cr.h }

	// Clamp vertical scroll
	total_h := f32(ta.lines.len) * line_step
	max_scroll_y := max_f32(0, total_h - cr_h)
	if ta.scroll_y > max_scroll_y {
		ta.scroll_y = max_scroll_y
	}
	if ta.scroll_y < 0 {
		ta.scroll_y = 0
	}

	// Clamp horizontal scroll
	max_scroll_x := max_f32(0, total_w - cr.w)
	if ta.scroll_x > max_scroll_x {
		ta.scroll_x = max_scroll_x
	}
	if ta.scroll_x < 0 {
		ta.scroll_x = 0
	}

	// Show placeholder when empty and not focused
	if ta.lines.len == 1 && ta.lines[0].len == 0 && !ta.focused {
		ph_lines := ta.placeholder.split('\n')
		for pi, ph_line in ph_lines {
			row_y := cr.y + f32(pi) * line_step
			if row_y > cr.y + cr_h { break }
			ctx.draw_text_with_font(ph_line, cr.x, row_y, ctx.theme.text_hint, font)
		}
		ctx.pop_clip()
		return
	}

	// Ensure cursor is visible vertically
	if ta.focused {
		cursor_y := f32(ta.cur_l) * line_step - ta.scroll_y
		if cursor_y < 0 {
			ta.scroll_y = f32(ta.cur_l) * line_step
		} else if cursor_y + fh > cr_h {
			ta.scroll_y = f32(ta.cur_l) * line_step - cr_h + fh + 2
		}
		// Ensure cursor is visible horizontally
		cur_line_runes := ta.lines[ta.cur_l].runes()
		cursor_x := ctx.measure_text_with_font(cur_line_runes[..ta.cur_c].string(), font).x
		if cursor_x - ta.scroll_x < 0 {
			ta.scroll_x = cursor_x
		} else if cursor_x - ta.scroll_x + 4 > cr.w {
			ta.scroll_x = cursor_x - cr.w + 4
		}
	}

	// Draw selection background
	if ta.has_sel() {
		sl, sc := ta.sel_start()
		el, ec := ta.sel_end()
		cc := ctx.theme.accent
		for li in sl .. el + 1 {
			row_y := cr.y + f32(li) * line_step - ta.scroll_y
			if row_y + fh < cr.y || row_y > cr.y + cr_h {
				continue
			}
			rr := ta.lines[li].runes()
			x1 := if li == sl {
				ctx.measure_text_with_font(rr[..sc].string(), font).x
			} else {
				f32(0)
			}
			x2 := if li == el {
				ctx.measure_text_with_font(rr[..ec].string(), font).x
			} else {
				ctx.measure_text_with_font(ta.lines[li], font).x + 4
			}
			sr := Rect{
				x: cr.x + x1 - ta.scroll_x
				y: row_y - 1
				w: x2 - x1
				h: fh + 2
			}
			ctx.fill_rounded_rect(sr, cc.with_alpha(80), 2)
		}
	}

	// Draw text lines
	tc := if ta.enabled { ctx.theme.text_primary } else { ctx.theme.text_secondary }
	for li, line in ta.lines {
		row_y := cr.y + f32(li) * line_step - ta.scroll_y
		if row_y + fh < cr.y {
			continue
		}
		if row_y > cr.y + cr_h {
			break
		}
		ctx.draw_text_with_font(line, cr.x - ta.scroll_x, row_y, tc, font)
	}

	// Draw cursor
	if ta.focused {
		ms := C.SDL_GetTicks()
		phase := ms % u64(1060)
		if phase < 530 {
			cur_line_runes := ta.lines[ta.cur_l].runes()
			cx := ctx.measure_text_with_font(cur_line_runes[..ta.cur_c].string(), font).x
			cy := cr.y + f32(ta.cur_l) * line_step - ta.scroll_y
			cc := ctx.theme.accent
			ctx.fill_rect(Rect{cr.x + cx - ta.scroll_x, cy, 2, fh}, cc)
		}
	}

	ctx.pop_clip()

	// Vertical scrollbar
	if total_h > cr_h {
		ta.draw_vscrollbar(mut ctx, cr, cr_h, total_h, h_scroll_visible)
	}
	// Horizontal scrollbar
	if h_scroll_visible {
		ta.draw_hscrollbar(mut ctx, cr, total_w, sb_h_sz)
	}
}

fn (ta &TextArea) draw_vscrollbar(mut ctx RenderContext, cr Rect, cr_h f32, total_h f32, h_scroll_visible bool) {
	g := ta.vscroll_geom(cr, cr_h, total_h, h_scroll_visible)
	ctx.fill_rounded_rect(Rect{g.sb_x, g.sb_y, g.sb_w, g.sb_h}, ctx.theme.button_border.with_alpha(60), 3)
	ctx.fill_rounded_rect(Rect{g.sb_x, g.thumb_y, g.sb_w, g.thumb_h}, ctx.theme.text_hint.with_alpha(140), 3)
}

fn (ta &TextArea) draw_hscrollbar(mut ctx RenderContext, cr Rect, total_w f32, sb_h_sz f32) {
	g := ta.hscroll_geom(cr, total_w, sb_h_sz)
	ctx.fill_rounded_rect(Rect{g.sb_x, g.sb_y, g.sb_w, g.sb_h}, ctx.theme.button_border.with_alpha(60), 3)
	ctx.fill_rounded_rect(Rect{g.thumb_x, g.sb_y, g.thumb_w, g.sb_h}, ctx.theme.text_hint.with_alpha(140), 3)
}

// ───────────── event dispatch ──────────────────────────

pub fn (mut ta TextArea) handle_event(ev &GuiEvent, app &App) bool {
	if !ta.visible || !ta.enabled {
		return false
	}

	match ev.typ {
		.mouse_move {
			return ta.on_mouse_move(ev, app)
		}
		.mouse_down {
			return ta.on_mouse_down(ev, app)
		}
		.mouse_up {
			return ta.on_mouse_up(ev)
		}
		.mouse_dbl_click {
			if ta.focused && ta.hovered {
				ta.select_word()
				ta.drag = false
				return true
			}
			return false
		}
		.mouse_wheel {
			if !ta.wheel {
				return false
			}
			if ta.hovered {
				if ev.shift() {
					ta.scroll_x -= ev.wheel_y * 30
				} else {
					ta.scroll_y -= ev.wheel_y * 30
				}
				return true
			}
			return false
		}
		.text_input {
			return ta.on_text(ev)
		}
		.key_down {
			return ta.on_key(ev, app)
		}
		else {
			return false
		}
	}
}

fn (mut ta TextArea) on_mouse_move(ev &GuiEvent, app &App) bool {
	ta.hovered = ta.bounds.contains(ev.mouse_x, ev.mouse_y)

	if ta.vscroll_drag || ta.hscroll_drag {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			font := ctx_ptr.get_font_immut(.regular, 0)
			fh := ctx_ptr.font_height_of(font)
			line_step := fh + 2
			cr := ta.bounds.shrunk(ta.pad)

			mut total_w := f32(0)
			for line in ta.lines {
				w := ctx_ptr.measure_text_with_font(line, font).x
				if w > total_w { total_w = w }
			}
			total_w += 4
			sb_h_sz := f32(5)
			h_scroll_visible := total_w > cr.w
			cr_h := if h_scroll_visible { cr.h - sb_h_sz - 2 } else { cr.h }
			total_h := f32(ta.lines.len) * line_step

			if ta.vscroll_drag {
				g := ta.vscroll_geom(cr, cr_h, total_h, h_scroll_visible)
				travel := g.sb_h - g.thumb_h
				if travel > 0 {
					ta.scroll_y = (ev.mouse_y - g.sb_y - ta.vscroll_drag_off) / travel * max_f32(1, total_h - cr_h)
				}
			}
			if ta.hscroll_drag {
				g := ta.hscroll_geom(cr, total_w, sb_h_sz)
				travel := g.sb_w - g.thumb_w
				if travel > 0 {
					ta.scroll_x = (ev.mouse_x - g.sb_x - ta.hscroll_drag_off) / travel * max_f32(1, total_w - cr.w)
				}
			}
		}
		return true
	}

	if ta.drag && ta.focused {
		l, c := ta.hit_pos(ev.mouse_x, ev.mouse_y, app)
		ta.cur_l = l
		ta.cur_c = c
		return true
	}
	return false
}

fn (mut ta TextArea) on_mouse_down(ev &GuiEvent, app &App) bool {
	if ev.mouse_btn != .left {
		return false
	}
	if ta.hovered {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.focus_text_area(&ta, ta.focus_group)

			// Check scrollbar hit before routing to text
			font := ctx_ptr.get_font_immut(.regular, 0)
			fh := ctx_ptr.font_height_of(font)
			line_step := fh + 2
			cr := ta.bounds.shrunk(ta.pad)

			mut total_w := f32(0)
			for line in ta.lines {
				w := ctx_ptr.measure_text_with_font(line, font).x
				if w > total_w { total_w = w }
			}
			total_w += 4
			sb_h_sz := f32(5)
			h_scroll_visible := total_w > cr.w
			cr_h := if h_scroll_visible { cr.h - sb_h_sz - 2 } else { cr.h }
			total_h := f32(ta.lines.len) * line_step

			// Vertical scrollbar hit?
			if total_h > cr_h {
				g := ta.vscroll_geom(cr, cr_h, total_h, h_scroll_visible)
				if ev.mouse_x >= g.sb_x && ev.mouse_x <= g.sb_x + g.sb_w {
					if ev.mouse_y >= g.sb_y && ev.mouse_y <= g.sb_y + g.sb_h {
						ta.vscroll_drag = true
						if ev.mouse_y >= g.thumb_y && ev.mouse_y <= g.thumb_y + g.thumb_h {
							ta.vscroll_drag_off = ev.mouse_y - g.thumb_y
						} else {
							// Click on track — jump thumb center to cursor
							travel := g.sb_h - g.thumb_h
							if travel > 0 {
								ta.scroll_y = (ev.mouse_y - g.sb_y - g.thumb_h / 2) / travel * max_f32(1, total_h - cr_h)
							}
							ta.vscroll_drag_off = g.thumb_h / 2
						}
						return true
					}
				}
			}

			// Horizontal scrollbar hit?
			if h_scroll_visible {
				g := ta.hscroll_geom(cr, total_w, sb_h_sz)
				if ev.mouse_y >= g.sb_y && ev.mouse_y <= g.sb_y + g.sb_h {
					if ev.mouse_x >= g.sb_x && ev.mouse_x <= g.sb_x + g.sb_w {
						ta.hscroll_drag = true
						if ev.mouse_x >= g.thumb_x && ev.mouse_x <= g.thumb_x + g.thumb_w {
							ta.hscroll_drag_off = ev.mouse_x - g.thumb_x
						} else {
							travel := g.sb_w - g.thumb_w
							if travel > 0 {
								ta.scroll_x = (ev.mouse_x - g.sb_x - g.thumb_w / 2) / travel * max_f32(1, total_w - cr.w)
							}
							ta.hscroll_drag_off = g.thumb_w / 2
						}
						return true
					}
				}
			}
		}

		ta.focused = true
		l, c := ta.hit_pos(ev.mouse_x, ev.mouse_y, app)
		ta.cur_l = l
		ta.cur_c = c
		ta.sel_al = l
		ta.sel_ac = c
		ta.drag = true
		return true
	}
	if ta.focused && !ta.hovered {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.blur_current()
		}
		ta.focused = false
		ta.drag = false
		ta.clear_sel()
	}
	return false
}

fn (mut ta TextArea) on_mouse_up(ev &GuiEvent) bool {
	if ev.mouse_btn != .left {
		return false
	}
	if ta.vscroll_drag || ta.hscroll_drag {
		ta.vscroll_drag = false
		ta.hscroll_drag = false
		return true
	}
	if ta.drag {
		ta.drag = false
		if ta.sel_al == ta.cur_l && ta.sel_ac == ta.cur_c {
			ta.clear_sel()
		}
		return ta.focused
	}
	return false
}

fn (mut ta TextArea) on_text(ev &GuiEvent) bool {
	if !ta.focused {
		return false
	}
	ta.insert_text(ev.text)
	return true
}

fn (mut ta TextArea) on_key(ev &GuiEvent, app &App) bool {
	if !ta.focused {
		return false
	}

	c := ev.ctrl()
	s := ev.shift()

	if c {
		if ev.scancode == ti_sc_letter_a {
			ta.sel_al = 0
			ta.sel_ac = 0
			ta.cur_l = ta.lines.len - 1
			ta.cur_c = ta.lines[ta.cur_l].runes().len
			return true
		}
		if ev.scancode == ti_sc_letter_c {
			if ta.has_sel() {
				app.set_clipboard(ta.selected_text())
			}
			return true
		}
		if ev.scancode == ti_sc_letter_x {
			if ta.has_sel() {
				app.set_clipboard(ta.selected_text())
				ta.save_undo()
				ta.delete_selection()
				ta.fire()
			}
			return true
		}
		if ev.scancode == ti_sc_letter_v {
			cl := app.get_clipboard()
			if cl.len > 0 {
				ta.insert_text(cl)
			}
			return true
		}
		if ev.scancode == ti_sc_letter_z {
			if s {
				ta.redo()
			} else {
				ta.undo()
			}
			return true
		}
	}

	if is_home_key(ev.keycode, ev.scancode) {
		if s { ta.ensure_sel() }
		ta.cur_c = 0
		if s {} else { ta.clear_sel() }
		return true
	}
	if is_end_key(ev.keycode, ev.scancode) {
		if s { ta.ensure_sel() }
		ta.cur_c = ta.lines[ta.cur_l].runes().len
		if s {} else { ta.clear_sel() }
		return true
	}

	match ev.keycode {
		sdl_k_return {
			ta.save_undo()
			if ta.has_sel() {
				ta.delete_selection()
			}
			// Split current line at cursor
			rr := ta.lines[ta.cur_l].runes()
			left := rr[..ta.cur_c].string()
			right := rr[ta.cur_c..].string()
			ta.lines[ta.cur_l] = left
			ta.lines.insert(ta.cur_l + 1, right)
			ta.cur_l++
			ta.cur_c = 0
			ta.fire()
			return true
		}
		sdl_k_backspace {
			ta.key_backspace(c)
			return true
		}
		sdl_k_delete {
			ta.key_delete(c)
			return true
		}
		sdl_k_left {
			ta.key_left(c, s)
			return true
		}
		sdl_k_right {
			ta.key_right(c, s)
			return true
		}
		sdl_k_up {
			ta.key_up(s)
			return true
		}
		sdl_k_down {
			ta.key_down_key(s)
			return true
		}
		sdl_k_tab {
			if c {
				// Ctrl+Tab — switch focus
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.tab(s)
				}
			} else {
				ta.insert_text('    ')
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
		sdl_k_insert {
			if c {
				if ta.has_sel() { app.set_clipboard(ta.selected_text()) }
			} else if s {
				cl := app.get_clipboard()
				if cl.len > 0 { ta.insert_text(cl) }
			} else {
				return false
			}
			return true
		}
		else {}
	}
	return false
}

// ───────────── key actions ─────────────────────────────

fn (mut ta TextArea) key_backspace(ctrl bool) {
	if ta.has_sel() {
		ta.save_undo()
		ta.delete_selection()
		ta.fire()
		return
	}
	if ta.cur_c == 0 && ta.cur_l == 0 {
		return
	}
	ta.save_undo()
	if ta.cur_c == 0 {
		// Merge with previous line
		prev_len := ta.lines[ta.cur_l - 1].runes().len
		ta.lines[ta.cur_l - 1] = ta.lines[ta.cur_l - 1] + ta.lines[ta.cur_l]
		ta.lines.delete(ta.cur_l)
		ta.cur_l--
		ta.cur_c = prev_len
	} else {
		if ctrl {
			// Delete word left
			b := ta.word_left()
			rr := ta.lines[ta.cur_l].runes()
			ta.lines[ta.cur_l] = (rr[..b].string()) + (rr[ta.cur_c..].string())
			ta.cur_c = b
		} else {
			rr := ta.lines[ta.cur_l].runes()
			ta.lines[ta.cur_l] = (rr[..ta.cur_c - 1].string()) + (rr[ta.cur_c..].string())
			ta.cur_c--
		}
	}
	ta.fire()
}

fn (mut ta TextArea) key_delete(ctrl bool) {
	if ta.has_sel() {
		ta.save_undo()
		ta.delete_selection()
		ta.fire()
		return
	}
	rr := ta.lines[ta.cur_l].runes()
	if ta.cur_c == rr.len && ta.cur_l == ta.lines.len - 1 {
		return
	}
	ta.save_undo()
	if ta.cur_c == rr.len {
		// Merge with next line
		ta.lines[ta.cur_l] = ta.lines[ta.cur_l] + ta.lines[ta.cur_l + 1]
		ta.lines.delete(ta.cur_l + 1)
	} else {
		if ctrl {
			b := ta.word_right()
			ta.lines[ta.cur_l] = (rr[..ta.cur_c].string()) + (rr[b..].string())
		} else {
			ta.lines[ta.cur_l] = (rr[..ta.cur_c].string()) + (rr[ta.cur_c + 1..].string())
		}
	}
	ta.fire()
}

fn (mut ta TextArea) key_left(ctrl bool, shift bool) {
	if shift { ta.ensure_sel() }
	if !shift && ta.has_sel() {
		// Jump to start of selection
		ta.cur_l, ta.cur_c = ta.sel_start()
		ta.clear_sel()
		return
	}
	if ctrl {
		ta.cur_c = ta.word_left()
	} else if ta.cur_c > 0 {
		ta.cur_c--
	} else if ta.cur_l > 0 {
		ta.cur_l--
		ta.cur_c = ta.lines[ta.cur_l].runes().len
	}
	if !shift { ta.clear_sel() }
}

fn (mut ta TextArea) key_right(ctrl bool, shift bool) {
	if shift { ta.ensure_sel() }
	if !shift && ta.has_sel() {
		ta.cur_l, ta.cur_c = ta.sel_end()
		ta.clear_sel()
		return
	}
	rr := ta.lines[ta.cur_l].runes()
	if ctrl {
		ta.cur_c = ta.word_right()
	} else if ta.cur_c < rr.len {
		ta.cur_c++
	} else if ta.cur_l < ta.lines.len - 1 {
		ta.cur_l++
		ta.cur_c = 0
	}
	if !shift { ta.clear_sel() }
}

fn (mut ta TextArea) key_up(shift bool) {
	if shift { ta.ensure_sel() }
	if ta.cur_l > 0 {
		ta.cur_l--
		new_max := ta.lines[ta.cur_l].runes().len
		if ta.cur_c > new_max {
			ta.cur_c = new_max
		}
	}
	if !shift { ta.clear_sel() }
}

fn (mut ta TextArea) key_down_key(shift bool) {
	if shift { ta.ensure_sel() }
	if ta.cur_l < ta.lines.len - 1 {
		ta.cur_l++
		new_max := ta.lines[ta.cur_l].runes().len
		if ta.cur_c > new_max {
			ta.cur_c = new_max
		}
	}
	if !shift { ta.clear_sel() }
}

// ───────────── insert / delete ─────────────────────────

fn (mut ta TextArea) insert_text(s string) {
	if s.len == 0 {
		return
	}
	ta.save_undo()
	if ta.has_sel() {
		ta.delete_selection()
	}
	parts := s.split('\n')
	rr := ta.lines[ta.cur_l].runes()
	left := rr[..ta.cur_c].string()
	right := rr[ta.cur_c..].string()

	if parts.len == 1 {
		ta.lines[ta.cur_l] = left + parts[0] + right
		ta.cur_c += parts[0].runes().len
	} else {
		ta.lines[ta.cur_l] = left + parts[0]
		for i in 1 .. parts.len - 1 {
			ta.lines.insert(ta.cur_l + i, parts[i])
		}
		ta.lines.insert(ta.cur_l + parts.len - 1, parts[parts.len - 1] + right)
		ta.cur_l += parts.len - 1
		ta.cur_c = parts[parts.len - 1].runes().len
	}
	ta.fire()
}

fn (mut ta TextArea) delete_selection() {
	if !ta.has_sel() {
		return
	}
	sl, sc := ta.sel_start()
	el, ec := ta.sel_end()
	if sl == el {
		rr := ta.lines[sl].runes()
		ta.lines[sl] = (rr[..sc].string()) + (rr[ec..].string())
	} else {
		start_str := ta.lines[sl].runes()[..sc].string()
		end_str := ta.lines[el].runes()[ec..].string()
		ta.lines[sl] = start_str + end_str
		// Remove lines sl+1 .. el
		for _ in sl + 1 .. el + 1 {
			ta.lines.delete(sl + 1)
		}
	}
	ta.cur_l = sl
	ta.cur_c = sc
	ta.clear_sel()
}

// ───────────── word boundaries ─────────────────────────

fn (ta &TextArea) word_left() int {
	rr := ta.lines[ta.cur_l].runes()
	if ta.cur_c == 0 {
		return 0
	}
	mut p := ta.cur_c - 1
	for p > 0 && !is_word(rr[p]) {
		p--
	}
	for p > 0 && is_word(rr[p - 1]) {
		p--
	}
	return p
}

fn (ta &TextArea) word_right() int {
	rr := ta.lines[ta.cur_l].runes()
	n := rr.len
	if ta.cur_c >= n {
		return n
	}
	mut p := ta.cur_c
	for p < n && is_word(rr[p]) {
		p++
	}
	for p < n && !is_word(rr[p]) {
		p++
	}
	return p
}

fn (mut ta TextArea) select_word() {
	rr := ta.lines[ta.cur_l].runes()
	if rr.len == 0 {
		return
	}
	p := clamp_int(ta.cur_c, 0, rr.len - 1)
	mut a := p
	mut b := p
	for a > 0 && is_word(rr[a - 1]) {
		a--
	}
	for b < rr.len && is_word(rr[b]) {
		b++
	}
	ta.sel_al = ta.cur_l
	ta.sel_ac = a
	ta.cur_c = b
}

// ───────────── scrollbar geometry helpers ─────────────

struct VScrollGeom {
	sb_x    f32
	sb_y    f32
	sb_w    f32
	sb_h    f32
	thumb_y f32
	thumb_h f32
}

struct HScrollGeom {
	sb_x    f32
	sb_y    f32
	sb_w    f32
	sb_h    f32
	thumb_x f32
	thumb_w f32
}

fn (ta &TextArea) vscroll_geom(cr Rect, cr_h f32, total_h f32, h_scroll_visible bool) VScrollGeom {
	sb_w := f32(5)
	sb_x := ta.bounds.x + ta.bounds.w - sb_w - 2
	sb_h := if h_scroll_visible { cr_h } else { cr.h }
	sb_y := cr.y
	thumb_h := max_f32(20, sb_h * cr_h / total_h)
	max_sy := max_f32(1, total_h - cr_h)
	travel := sb_h - thumb_h
	thumb_y := sb_y + (ta.scroll_y / max_sy) * travel
	return VScrollGeom{sb_x, sb_y, sb_w, sb_h, thumb_y, thumb_h}
}

fn (ta &TextArea) hscroll_geom(cr Rect, total_w f32, sb_h_sz f32) HScrollGeom {
	sb_h := sb_h_sz
	sb_y := cr.y + cr.h - sb_h
	sb_w := cr.w
	sb_x := cr.x
	thumb_w := max_f32(20, sb_w * cr.w / total_w)
	max_sx := max_f32(1, total_w - cr.w)
	travel := sb_w - thumb_w
	thumb_x := sb_x + (ta.scroll_x / max_sx) * travel
	return HScrollGeom{sb_x, sb_y, sb_w, sb_h, thumb_x, thumb_w}
}

// ───────────── hit-test ────────────────────────────────

fn (ta &TextArea) hit_pos(mx f32, my f32, app &App) (int, int) {
	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return 0, 0
	}
	font := ctx_ptr.get_font_immut(.regular, 0)
	fh := ctx_ptr.font_height_of(font)
	line_step := fh + 2

	cr_x := ta.bounds.x + ta.pad
	cr_y := ta.bounds.y + ta.pad
	lx := mx - cr_x + ta.scroll_x
	ly := my - cr_y + ta.scroll_y

	li := clamp_int(int(ly / line_step), 0, ta.lines.len - 1)
	rr := ta.lines[li].runes()

	if rr.len == 0 {
		return li, 0
	}

	mut best := 0
	mut bd := abs_f32(lx)
	for i := 1; i <= rr.len; i++ {
		w := ctx_ptr.measure_text_with_font(rr[..i].string(), font).x
		d := abs_f32(w - lx)
		if d < bd {
			bd = d
			best = i
		}
	}
	return li, best
}

// ───────────── fire callback ───────────────────────────

fn (mut ta TextArea) fire() {
	if ta.on_change != unsafe { nil } {
		ta.on_change(ta.get_text())
	}
}
