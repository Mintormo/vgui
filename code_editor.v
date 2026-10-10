// Файл: ./code_editor.v
module vgui

import os

// ═══════════════════════════════════════════════════════
// CodeEditor — multiline text editor widget with optional minimap
// ═══════════════════════════════════════════════════════

const ce_max_undo = 200
const ce_tab_spaces = 4
const ce_cursor_blink_ms = u64(1060)
const ce_scroll_speed = f32(30)
const ce_gutter_pad = f32(8)
const ce_text_pad = f32(6)
const ce_sb_w = f32(12)

// SDL2 physical scancodes for letter keys — used to recognise Ctrl+A/C/V/X/Z
// regardless of the active keyboard layout (e.g. when Russian/Cyrillic layout
// is active SDL's keysym.sym returns the Cyrillic codepoint, not 'a'/'z').
const sc_letter_a = 4
const sc_letter_c = 6
const sc_letter_v = 25
const sc_letter_x = 27
const sc_letter_z = 29

struct CeUndoEntry {
	lines    [][]rune
	cur_line int
	cur_col  int
}

struct CePos {
mut:
	line int
	col  int
}

fn ce_pos(line int, col int) CePos {
	return CePos{line, col}
}

fn (a CePos) before(b CePos) bool {
	return a.line < b.line || (a.line == b.line && a.col < b.col)
}

fn (a CePos) eq(b CePos) bool {
	return a.line == b.line && a.col == b.col
}

fn ce_pos_min(a CePos, b CePos) CePos {
	return if a.before(b) { a } else { b }
}

fn ce_pos_max(a CePos, b CePos) CePos {
	return if a.before(b) { b } else { a }
}

@[heap]
pub struct CodeEditor {
pub mut:
	type_tag int = kind_code_editor // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel                 bool = true
	bounds                Rect
	visible               bool = true
	enabled               bool = true
	focused               bool
	hovered               bool
	readonly              bool
	lines                 [][]rune
	cur_line              int
	cur_col               int
	sel_a                 CePos = CePos{-1, -1}
	sel_b                 CePos = CePos{-1, -1}
	scroll_x              f32
	scroll_y              f32
	scroll_speed          f32       = ce_scroll_speed
	show_line_numbers     bool      = true
	highlight_cur_line    bool      = true
	auto_indent           bool      = true
	font_style            FontStyle = .mono
	font_size             int
	tab_size              int                      = ce_tab_spaces
	pad                   f32                      = 2
	bg_color              Color                    = Color{0, 0, 0, 0}
	text_color            Color                    = Color{0, 0, 0, 0}
	line_number_color     Color                    = Color{0, 0, 0, 0}
	gutter_bg             Color                    = Color{0, 0, 0, 0}
	cur_line_bg           Color                    = Color{0, 0, 0, 0}
	selection_color       Color                    = Color{0, 0, 0, 0}
	cursor_color          Color                    = Color{0, 0, 0, 0}
	highlighter           &SyntaxHighlighter       = unsafe { nil }
	history               UndoHistory[CeUndoEntry] = UndoHistory[CeUndoEntry]{
		limit: ce_max_undo
	}
	drag                  bool
	focus_anim            Anim = anim_smooth(anim_tau_focus)
	focus_group           int
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
	// ── Minimap ──
	show_minimap     bool
	minimap_width    f32 = 80
	minimap_scale    f32 = 0.25
	minimap_dragging bool
	minimap_hovered  bool
	on_change        fn () = unsafe { nil }
	on_cursor_move   fn () = unsafe { nil }
}

pub fn code_editor() &CodeEditor {
	return &CodeEditor{
		lines: [[]rune{}]
	}
}

pub fn (mut e CodeEditor) set_text(text string) {
	e.lines.clear()
	raw_lines := text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
	for rl in raw_lines {
		e.lines << rl.runes()
	}
	if e.lines.len == 0 {
		e.lines << []rune{}
	}
	e.cur_line = 0
	e.cur_col = 0
	e.scroll_x = 0
	e.scroll_y = 0
	e.clear_sel()
	e.history.clear()
}

pub fn (mut e CodeEditor) load_file(path string) bool {
	content := os.read_file(path) or { return false }
	e.set_text(content)
	return true
}

pub fn (e &CodeEditor) get_text() string {
	mut parts := []string{cap: e.lines.len}
	for line in e.lines {
		parts << if line.len > 0 { line.string() } else { '' }
	}
	return parts.join('\n')
}

fn ce_expand_tabs(s string, tab_size int) string {
	if !s.contains('\t') {
		return s
	}
	spaces := '                '[..tab_size]
	return s.replace('\t', spaces)
}

pub fn (e &CodeEditor) get_line_count() int {
	return e.lines.len
}

pub fn (e &CodeEditor) get_line(idx int) string {
	if idx >= 0 && idx < e.lines.len {
		return if e.lines[idx].len > 0 { e.lines[idx].string() } else { '' }
	}
	return ''
}

pub fn (mut e CodeEditor) set_highlighter(h &SyntaxHighlighter) {
	e.highlighter = unsafe { h }
}

pub fn (mut e CodeEditor) goto_line(line int) {
	e.cur_line = clamp_int(line, 0, e.lines.len - 1)
	e.cur_col = 0
	e.clear_sel()
}

// ─── Selection helpers ─────────────────────────────────

fn (e &CodeEditor) has_sel() bool {
	return e.sel_a.line >= 0 && e.sel_b.line >= 0 && !e.sel_a.eq(e.sel_b)
}

fn (e &CodeEditor) sel_start() CePos {
	return ce_pos_min(e.sel_a, e.sel_b)
}

fn (e &CodeEditor) sel_end() CePos {
	return ce_pos_max(e.sel_a, e.sel_b)
}

fn (mut e CodeEditor) clear_sel() {
	e.sel_a = CePos{-1, -1}
	e.sel_b = CePos{-1, -1}
}

fn (mut e CodeEditor) ensure_sel() {
	if e.sel_a.line < 0 {
		e.sel_a = ce_pos(e.cur_line, e.cur_col)
		e.sel_b = e.sel_a
	}
}

fn (e &CodeEditor) selected_text() string {
	if !e.has_sel() {
		return ''
	}
	s := e.sel_start()
	en := e.sel_end()
	if s.line == en.line {
		line := e.lines[s.line]
		a := clamp_int(s.col, 0, line.len)
		b := clamp_int(en.col, 0, line.len)
		return if b > a { line[a..b].string() } else { '' }
	}
	mut parts := []string{cap: en.line - s.line + 1}
	fl := e.lines[s.line]
	a := clamp_int(s.col, 0, fl.len)
	parts << if a < fl.len { fl[a..].string() } else { '' }
	for i in s.line + 1 .. en.line {
		parts << if e.lines[i].len > 0 { e.lines[i].string() } else { '' }
	}
	ll := e.lines[en.line]
	b := clamp_int(en.col, 0, ll.len)
	parts << if b > 0 { ll[..b].string() } else { '' }
	return parts.join('\n')
}

// ─── Undo/redo ─────────────────────────────────────────

fn (e &CodeEditor) snap() CeUndoEntry {
	mut lines_copy := [][]rune{cap: e.lines.len}
	for line in e.lines {
		lines_copy << line.clone()
	}
	return CeUndoEntry{
		lines:    lines_copy
		cur_line: e.cur_line
		cur_col:  e.cur_col
	}
}

fn (mut e CodeEditor) save_undo() {
	e.history.save(e.snap())
}

fn (mut e CodeEditor) restore(entry CeUndoEntry) {
	e.lines.clear()
	for line in entry.lines {
		e.lines << line.clone()
	}
	e.cur_line = entry.cur_line
	e.cur_col = entry.cur_col
	e.clear_sel()
	e.fire_change()
}

// undo отменяет последнюю правку (как Ctrl+Z); false — отменять нечего.
pub fn (mut e CodeEditor) undo() bool {
	entry := e.history.undo(e.snap()) or { return false }
	e.restore(entry)
	return true
}

// redo повторяет отменённую правку (как Ctrl+Shift+Z).
pub fn (mut e CodeEditor) redo() bool {
	entry := e.history.redo(e.snap()) or { return false }
	e.restore(entry)
	return true
}

pub fn (e &CodeEditor) can_undo() bool {
	return e.history.can_undo()
}

pub fn (e &CodeEditor) can_redo() bool {
	return e.history.can_redo()
}

// clear_undo забывает историю правок (например, после загрузки файла).
pub fn (mut e CodeEditor) clear_undo() {
	e.history.clear()
}

fn (mut e CodeEditor) fire_change() {
	if e.on_change != unsafe { nil } {
		e.on_change()
	}
}

fn (mut e CodeEditor) fire_cursor_move() {
	if e.on_cursor_move != unsafe { nil } {
		e.on_cursor_move()
	}
}

// ─── Delete selection ──────────────────────────────────

fn (mut e CodeEditor) delete_sel() {
	if !e.has_sel() {
		return
	}
	s := e.sel_start()
	en := e.sel_end()
	if s.line == en.line {
		mut line := e.lines[s.line]
		a := clamp_int(s.col, 0, line.len)
		b := clamp_int(en.col, 0, line.len)
		mut nw := []rune{cap: line.len - (b - a)}
		for i in 0 .. a {
			nw << line[i]
		}
		for i in b .. line.len {
			nw << line[i]
		}
		e.lines[s.line] = nw
	} else {
		fl := e.lines[s.line]
		ll := e.lines[en.line]
		a := clamp_int(s.col, 0, fl.len)
		b := clamp_int(en.col, 0, ll.len)
		mut merged := []rune{cap: a + (ll.len - b)}
		for i in 0 .. a {
			merged << fl[i]
		}
		for i in b .. ll.len {
			merged << ll[i]
		}
		e.lines[s.line] = merged
		for _ in 0 .. en.line - s.line {
			if s.line + 1 < e.lines.len {
				e.lines.delete(s.line + 1)
			}
		}
	}
	e.cur_line = s.line
	e.cur_col = s.col
	e.clear_sel()
}

// ─── Insert text at cursor ─────────────────────────────

fn (mut e CodeEditor) insert_text(text string) {
	if text.len == 0 {
		return
	}
	e.save_undo()
	if e.has_sel() {
		e.delete_sel()
	}
	ins_lines := text.replace('\r\n', '\n').replace('\r', '\n').split('\n')
	if ins_lines.len == 1 {
		rr := ins_lines[0].runes()
		mut line := e.lines[e.cur_line]
		col := clamp_int(e.cur_col, 0, line.len)
		mut nw := []rune{cap: line.len + rr.len}
		for i in 0 .. col {
			nw << line[i]
		}
		for r in rr {
			nw << r
		}
		for i in col .. line.len {
			nw << line[i]
		}
		e.lines[e.cur_line] = nw
		e.cur_col = col + rr.len
	} else {
		mut line := e.lines[e.cur_line]
		col := clamp_int(e.cur_col, 0, line.len)
		before := if col > 0 { line[..col].clone() } else { []rune{} }
		after := if col < line.len { line[col..].clone() } else { []rune{} }
		first_rr := ins_lines[0].runes()
		mut first_line := []rune{cap: before.len + first_rr.len}
		for r in before {
			first_line << r
		}
		for r in first_rr {
			first_line << r
		}
		e.lines[e.cur_line] = first_line
		for i in 1 .. ins_lines.len - 1 {
			e.lines.insert(e.cur_line + i, ins_lines[i].runes())
		}
		last_rr := ins_lines[ins_lines.len - 1].runes()
		mut last_line := []rune{cap: last_rr.len + after.len}
		for r in last_rr {
			last_line << r
		}
		for r in after {
			last_line << r
		}
		last_idx := e.cur_line + ins_lines.len - 1
		e.lines.insert(last_idx, last_line)
		e.cur_line = last_idx
		e.cur_col = last_rr.len
	}
	e.fire_change()
}

// ─── Geometry helpers ──────────────────────────────────

fn (e &CodeEditor) eff_font(ctx &RenderContext) voidptr {
	return ctx.get_font_immut(e.font_style, e.font_size)
}

fn (e &CodeEditor) line_height(ctx &RenderContext) f32 {
	font := e.eff_font(ctx)
	return ctx.font_height_of(font)
}

fn (e &CodeEditor) char_width(ctx &RenderContext) f32 {
	font := e.eff_font(ctx)
	return ctx.measure_text_with_font('M', font).x
}

fn (e &CodeEditor) gutter_width(ctx &RenderContext) f32 {
	if !e.show_line_numbers {
		return f32(0)
	}
	digits := max_int(2, ('${e.lines.len}').len)
	cw := e.char_width(ctx)
	return f32(digits) * cw + ce_gutter_pad * 2
}

fn (e &CodeEditor) content_rect(ctx &RenderContext) Rect {
	gw := e.gutter_width(ctx)
	mm := if e.show_minimap { e.minimap_width } else { f32(0) }
	return Rect{
		x: e.bounds.x + e.pad + gw
		y: e.bounds.y + e.pad
		w: e.bounds.w - e.pad * 2 - gw - ce_sb_w - mm
		h: e.bounds.h - e.pad * 2 - ce_sb_w
	}
}

fn (e &CodeEditor) total_content_height(ctx &RenderContext) f32 {
	return f32(e.lines.len) * e.line_height(ctx)
}

fn (e &CodeEditor) max_scroll_y(ctx &RenderContext) f32 {
	cr := e.content_rect(ctx)
	return max_f32(0, e.total_content_height(ctx) - cr.h)
}

fn (e &CodeEditor) max_content_width(ctx &RenderContext) f32 {
	font := e.eff_font(ctx)
	mut max_w := f32(0)
	for line in e.lines {
		text := if line.len > 0 { ce_expand_tabs(line.string(), e.tab_size) } else { '' }
		w := ctx.measure_text_with_font(text, font).x
		if w > max_w {
			max_w = w
		}
	}
	return max_w + ce_text_pad * 2
}

fn (e &CodeEditor) max_scroll_x(ctx &RenderContext) f32 {
	cr := e.content_rect(ctx)
	return max_f32(0, e.max_content_width(ctx) - cr.w)
}

fn (mut e CodeEditor) ensure_cursor_visible(ctx &RenderContext) {
	lh := e.line_height(ctx)
	cr := e.content_rect(ctx)
	cy := f32(e.cur_line) * lh
	if cy < e.scroll_y {
		e.scroll_y = cy
	}
	if cy + lh > e.scroll_y + cr.h {
		e.scroll_y = cy + lh - cr.h
	}
	e.scroll_y = clamp_f32(e.scroll_y, 0, e.max_scroll_y(ctx))
	font := e.eff_font(ctx)
	line := e.lines[e.cur_line]
	col := clamp_int(e.cur_col, 0, line.len)
	text_before := if col > 0 { ce_expand_tabs(line[..col].string(), e.tab_size) } else { '' }
	cx := ctx.measure_text_with_font(text_before, font).x
	if cx - e.scroll_x < 0 {
		e.scroll_x = max_f32(0, cx - 20)
	}
	if cx - e.scroll_x > cr.w - 4 {
		e.scroll_x = cx - cr.w + 20
	}
	e.scroll_x = clamp_f32(e.scroll_x, 0, e.max_scroll_x(ctx))
}

fn (mut e CodeEditor) clamp_cursor() {
	e.cur_line = clamp_int(e.cur_line, 0, e.lines.len - 1)
	e.cur_col = clamp_int(e.cur_col, 0, e.lines[e.cur_line].len)
}

fn (e &CodeEditor) hit_pos(mx f32, my f32, ctx &RenderContext) CePos {
	cr := e.content_rect(ctx)
	lh := e.line_height(ctx)
	font := e.eff_font(ctx)
	rel_y := my - cr.y + e.scroll_y
	line := clamp_int(int(rel_y / lh), 0, e.lines.len - 1)
	rel_x := mx - cr.x + e.scroll_x
	ln := e.lines[line]
	if ln.len == 0 || rel_x <= 0 {
		return ce_pos(line, 0)
	}
	mut best := 0
	mut best_d := abs_f32(rel_x)
	for i in 1 .. ln.len + 1 {
		w := ctx.measure_text_with_font(ce_expand_tabs(ln[..i].string(), e.tab_size), font).x
		d := abs_f32(w - rel_x)
		if d < best_d {
			best_d = d
			best = i
		}
	}
	return ce_pos(line, best)
}

// ─── Scrollbar geometry ────────────────────────────────

fn (e &CodeEditor) vsb_rects(ctx &RenderContext) (Rect, Rect) {
	cr := e.content_rect(ctx)
	ch := e.total_content_height(ctx)
	vis_h := cr.h
	if ch <= vis_h {
		return Rect{}, Rect{}
	}
	mm := if e.show_minimap { e.minimap_width } else { f32(0) }
	track := Rect{
		x: e.bounds.x + e.bounds.w - e.pad - ce_sb_w - mm
		y: cr.y
		w: ce_sb_w
		h: vis_h
	}
	thumb_h := max_f32(20, vis_h * (vis_h / ch))
	ms := e.max_scroll_y(ctx)
	ratio := if ms > 0 { e.scroll_y / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + 2
		y: track.y + ratio * (vis_h - thumb_h)
		w: ce_sb_w - 4
		h: thumb_h
	}
	return track, thumb
}

fn (e &CodeEditor) has_vsb(ctx &RenderContext) bool {
	return e.total_content_height(ctx) > e.content_rect(ctx).h
}

// ─── Horizontal scrollbar ──────────────────────────────

fn (e &CodeEditor) hsb_rects(ctx &RenderContext) (Rect, Rect) {
	cr := e.content_rect(ctx)
	cw := e.max_content_width(ctx)
	vis_w := cr.w
	if cw <= vis_w {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: cr.x
		y: e.bounds.y + e.bounds.h - e.pad - ce_sb_w
		w: vis_w
		h: ce_sb_w
	}
	thumb_w := max_f32(20, vis_w * (vis_w / cw))
	ms := e.max_scroll_x(ctx)
	ratio := if ms > 0 { e.scroll_x / ms } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vis_w - thumb_w)
		y: track.y + 2
		w: thumb_w
		h: ce_sb_w - 4
	}
	return track, thumb
}

fn (e &CodeEditor) has_hsb(ctx &RenderContext) bool {
	return e.max_content_width(ctx) > e.content_rect(ctx).w
}

// ─── Minimap ───────────────────────────────────────────

fn (e &CodeEditor) minimap_rect(ctx &RenderContext) Rect {
	if !e.show_minimap {
		return Rect{}
	}
	cr := e.content_rect(ctx)
	return Rect{
		x: cr.x + cr.w + ce_sb_w
		y: cr.y
		w: e.minimap_width
		h: cr.h
	}
}

fn (e &CodeEditor) minimap_line_h(ctx &RenderContext) f32 {
	return e.line_height(ctx) * e.minimap_scale
}

fn (e &CodeEditor) minimap_total_h(ctx &RenderContext) f32 {
	return f32(e.lines.len) * e.minimap_line_h(ctx)
}

fn (e &CodeEditor) minimap_scroll_y(ctx &RenderContext) f32 {
	mr := e.minimap_rect(ctx)
	total := e.minimap_total_h(ctx)
	if total <= mr.h {
		return 0
	}
	ms := e.max_scroll_y(ctx)
	if ms <= 0 {
		return 0
	}
	return (e.scroll_y / ms) * (total - mr.h)
}

fn (e &CodeEditor) draw_minimap(mut ctx RenderContext) {
	mr := e.minimap_rect(ctx)
	if mr.w < 4 || mr.h < 4 {
		return
	}
	mm_bg := ctx.theme.eff_ce_gutter_bg().darken(0.02)
	ctx.fill_rect(mr, mm_bg)
	ctx.fill_rect(Rect{mr.x, mr.y, 1, mr.h}, ctx.theme.eff_ce_border())

	ctx.push_clip(mr)

	lh := e.line_height(ctx)
	mm_lh := e.minimap_line_h(ctx)
	mut char_w := e.char_width(ctx) * e.minimap_scale
	if char_w < 0.5 {
		char_w = 0.5
	}
	mm_scroll := e.minimap_scroll_y(ctx)
	has_hl := unsafe { e.highlighter != nil }
	tc := if e.text_color.a > 0 { e.text_color } else { ctx.theme.text_primary }
	dim := tc.with_alpha(160)

	for i in 0 .. e.lines.len {
		ly := mr.y + f32(i) * mm_lh - mm_scroll
		if ly + mm_lh < mr.y {
			continue
		}
		if ly > mr.y + mr.h {
			break
		}
		line := e.lines[i]
		if line.len == 0 {
			continue
		}
		text := line.string()
		mut leading := 0
		for r in line {
			if r == ` ` || r == `\t` {
				leading++
			} else {
				break
			}
		}
		start_x := mr.x + 2 + f32(leading) * char_w
		bar_h := max_f32(mm_lh - 0.5, 1)

		if has_hl {
			tokens := e.highlighter.tokenize(text)
			mut ox := mr.x + 2
			for tok in tokens {
				tw := f32(tok.text.runes().len) * char_w
				trimmed := tok.text.trim_space()
				if trimmed.len > 0 {
					ctx.fill_rect(Rect{ox, ly, tw, bar_h}, tok.color.with_alpha(180))
				}
				ox += tw
				if ox > mr.x + mr.w {
					break
				}
			}
		} else {
			bar_w := min_f32(f32(line.len - leading) * char_w, mr.w - 4 - (start_x - mr.x - 2))
			if bar_w > 0 {
				ctx.fill_rect(Rect{start_x, ly, bar_w, bar_h}, dim)
			}
		}
	}

	// Visible viewport indicator
	cr := e.content_rect(ctx)
	vis_top := (e.scroll_y / lh) * mm_lh - mm_scroll
	vis_h := (cr.h / lh) * mm_lh
	vp_rect := Rect{mr.x, mr.y + vis_top, mr.w, vis_h}
	ctx.fill_rect(vp_rect, ctx.theme.accent.with_alpha(40))
	ctx.draw_rect(vp_rect, ctx.theme.accent.with_alpha(100))

	ctx.pop_clip()
}

fn (e &CodeEditor) minimap_y_to_scroll(my f32, ctx &RenderContext) f32 {
	mr := e.minimap_rect(ctx)
	lh := e.line_height(ctx)
	mm_lh := e.minimap_line_h(ctx)
	mm_scroll := e.minimap_scroll_y(ctx)
	rel := my - mr.y + mm_scroll
	line := rel / mm_lh
	cr := e.content_rect(ctx)
	target := line * lh - cr.h * 0.5
	return clamp_f32(target, 0, e.max_scroll_y(ctx))
}

// ═══════════════════════════════════════════════════════
// Drawing
// ═══════════════════════════════════════════════════════

pub fn (mut e CodeEditor) draw(mut ctx RenderContext) {
	if !e.visible {
		return
	}
	// Mark animation needed when focused (for cursor blink). mark_anim_rect
	// (not a raw ctx.needs_animation = true write) so the dirty tracker
	// actually schedules e's rect for the NEXT frame. Standing here, above
	// the is_in_clip early-return, is cosmetic: mark_anim_rect re-checks
	// is_in_clip(e.bounds) itself, so the order changes nothing. What keeps
	// the cursor blink from freezing when a partial frame misses this widget
	// is the bbox invariant documented at mark_anim_rect in
	// render_context.v.
	if e.focused && !e.readonly {
		ctx.mark_anim_rect('codeeditor', e.bounds)
	}

	if !ctx.is_in_clip(e.bounds) {
		return
	}

	lh := e.line_height(ctx)
	font := ctx.get_font(e.font_style, e.font_size)
	fh := ctx.font_height_of(font)
	cr := e.content_rect(ctx)
	gw := e.gutter_width(ctx)

	e.scroll_y = clamp_f32(e.scroll_y, 0, e.max_scroll_y(ctx))
	e.scroll_x = clamp_f32(e.scroll_x, 0, e.max_scroll_x(ctx))

	bg := if e.bg_color.a > 0 { e.bg_color } else { ctx.theme.eff_ce_bg() }
	ctx.fill_rounded_rect(e.bounds, bg, ctx.theme.border_radius)

	bc := ctx.theme.eff_ce_border().blend(ctx.theme.input_focus, e.focus_anim.value)
	ctx.draw_rounded_rect(e.bounds, bc, ctx.theme.border_radius)

	target_focus := if e.focused && e.enabled { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if e.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('codeeditor', e.bounds.expanded(1))
	}
	if e.focus_anim.value > 0.05 {
		glow := ctx.theme.input_focus.with_alpha(u8(30.0 * e.focus_anim.value))
		ctx.draw_rounded_rect(e.bounds.expanded(1), glow, ctx.theme.border_radius + 1)
	}

	// Gutter
	if e.show_line_numbers && gw > 0 {
		gutter_r := Rect{e.bounds.x + e.pad, e.bounds.y + e.pad, gw, e.bounds.h - e.pad * 2}
		gutter_bg := if e.gutter_bg.a > 0 { e.gutter_bg } else { ctx.theme.eff_ce_gutter_bg() }
		ctx.fill_rect(gutter_r, gutter_bg)
		ctx.fill_rect(Rect{gutter_r.x + gutter_r.w - 1, gutter_r.y, 1, gutter_r.h},
			ctx.theme.eff_ce_border())

		ctx.push_clip(gutter_r)
		ln_color := if e.line_number_color.a > 0 {
			e.line_number_color
		} else {
			ctx.theme.eff_ce_gutter_text()
		}
		first_vis := max_int(0, int(e.scroll_y / lh))
		last_vis := min_int(e.lines.len - 1, int((e.scroll_y + cr.h) / lh) + 1)
		for i in first_vis .. last_vis + 1 {
			ly := gutter_r.y + f32(i) * lh - e.scroll_y
			if ly + lh < gutter_r.y || ly > gutter_r.y + gutter_r.h {
				continue
			}
			num_str := '${i + 1}'
			nw := ctx.measure_text_with_font(num_str, font).x
			nx := gutter_r.x + gutter_r.w - ce_gutter_pad - nw - 1
			ny := ly + (lh - fh) * 0.5
			ctx.draw_text_with_font(num_str, nx, ny, ln_color, font)
		}
		ctx.pop_clip()
	}

	// Text area
	ctx.push_clip(cr)

	tc := if e.text_color.a > 0 { e.text_color } else { ctx.theme.eff_ce_text() }
	sel_c := if e.selection_color.a > 0 {
		e.selection_color
	} else {
		ctx.theme.eff_ce_selection()
	}
	cur_line_c := if e.cur_line_bg.a > 0 {
		e.cur_line_bg
	} else {
		ctx.theme.eff_ce_cur_line()
	}
	cursor_c := if e.cursor_color.a > 0 { e.cursor_color } else { ctx.theme.eff_ce_cursor() }

	first_vis := max_int(0, int(e.scroll_y / lh))
	last_vis := min_int(e.lines.len - 1, int((e.scroll_y + cr.h) / lh) + 1)

	has_hl := unsafe { e.highlighter != nil }

	for i in first_vis .. last_vis + 1 {
		ly := cr.y + f32(i) * lh - e.scroll_y
		if ly + lh < cr.y || ly > cr.y + cr.h {
			continue
		}

		if e.highlight_cur_line && i == e.cur_line && e.focused {
			ctx.fill_rect(Rect{cr.x, ly, cr.w, lh}, cur_line_c)
		}

		if e.has_sel() {
			s := e.sel_start()
			en := e.sel_end()
			if i >= s.line && i <= en.line {
				line := e.lines[i]
				mut sx := f32(0)
				mut ex := cr.w
				if i == s.line {
					sc := clamp_int(s.col, 0, line.len)
					sx = if sc > 0 {
						ctx.measure_text_with_font(ce_expand_tabs(line[..sc].string(), e.tab_size), font).x
					} else {
						f32(0)
					}
				}
				if i == en.line {
					ec := clamp_int(en.col, 0, line.len)
					ex = if ec > 0 {
						ctx.measure_text_with_font(ce_expand_tabs(line[..ec].string(), e.tab_size), font).x
					} else {
						f32(0)
					}
				}
				sel_r := Rect{cr.x + sx - e.scroll_x, ly, ex - sx, lh}
				ctx.fill_rect(sel_r, sel_c)
			}
		}

		line := e.lines[i]
		if line.len > 0 {
			text := line.string()
			ty := ly + (lh - fh) * 0.5
			tx := cr.x - e.scroll_x
			if has_hl {
				tokens := e.highlighter.tokenize(text)
				mut offset_x := tx
				for tok in tokens {
					tok_text := ce_expand_tabs(tok.text, e.tab_size)
					tok_w := ctx.measure_text_with_font(tok_text, font).x
					ctx.draw_text_with_font(tok_text, offset_x, ty, tok.color, font)
					offset_x += tok_w
				}
			} else {
				ctx.draw_text_with_font(ce_expand_tabs(text, e.tab_size), tx, ty, tc, font)
			}
		}
	}

	// Cursor
	if e.focused && !e.readonly {
		ms := C.SDL_GetTicks()
		if ms % ce_cursor_blink_ms < ce_cursor_blink_ms / 2 {
			line := e.lines[e.cur_line]
			col := clamp_int(e.cur_col, 0, line.len)
			text_before := if col > 0 {
				ce_expand_tabs(line[..col].string(), e.tab_size)
			} else {
				''
			}
			cx := cr.x + ctx.measure_text_with_font(text_before, font).x - e.scroll_x
			cy := cr.y + f32(e.cur_line) * lh - e.scroll_y
			cty := cy + (lh - fh) * 0.5
			ctx.fill_rect(Rect{cx, cty, 2, fh}, cursor_c)
		}
	}

	ctx.pop_clip()

	// Vertical scrollbar
	if e.has_vsb(ctx) {
		track, thumb := e.vsb_rects(ctx)
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		vsb_c := if e.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if e.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, vsb_c, 3)
	}

	// Horizontal scrollbar
	if e.has_hsb(ctx) {
		track, thumb := e.hsb_rects(ctx)
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		hsb_c := if e.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if e.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, hsb_c, 3)
	}

	// Minimap
	if e.show_minimap {
		e.draw_minimap(mut ctx)
	}
}

// ═══════════════════════════════════════════════════════
// Event handling
// ═══════════════════════════════════════════════════════

pub fn (mut e CodeEditor) handle_event(event &GuiEvent, app &App) bool {
	if !e.visible || !e.enabled {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	// ── Minimap drag in progress ──
	if e.minimap_dragging {
		match event.typ {
			.mouse_move {
				if unsafe { ctx_ptr != nil } {
					e.scroll_y = e.minimap_y_to_scroll(event.mouse_y, ctx_ptr)
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					e.minimap_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Vertical scrollbar drag ──
	if e.vsb_dragging {
		match event.typ {
			.mouse_move {
				if unsafe { ctx_ptr != nil } {
					track, _ := e.vsb_rects(ctx_ptr)
					if track.h <= 0 {
						return true
					}
					ch := e.total_content_height(ctx_ptr)
					vis_h := track.h
					thumb_h := max_f32(20, vis_h * (vis_h / ch))
					drag_range := vis_h - thumb_h
					if drag_range <= 0 {
						return true
					}
					dy := event.mouse_y - e.vsb_drag_start_y
					ms := e.max_scroll_y(ctx_ptr)
					e.scroll_y = clamp_f32(e.vsb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					e.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// ── Horizontal scrollbar drag ──
	if e.hsb_dragging {
		match event.typ {
			.mouse_move {
				if unsafe { ctx_ptr != nil } {
					track, _ := e.hsb_rects(ctx_ptr)
					if track.w <= 0 {
						return true
					}
					cw := e.max_content_width(ctx_ptr)
					vis_w := track.w
					thumb_w := max_f32(20, vis_w * (vis_w / cw))
					drag_range := vis_w - thumb_w
					if drag_range <= 0 {
						return true
					}
					dx := event.mouse_x - e.hsb_drag_start_x
					ms := e.max_scroll_x(ctx_ptr)
					e.scroll_x = clamp_f32(e.hsb_drag_start_scroll + dx * (ms / drag_range), 0, ms)
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					e.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			e.hovered = e.bounds.contains(event.mouse_x, event.mouse_y)
			if e.drag && e.focused && unsafe { ctx_ptr != nil } {
				pos := e.hit_pos(event.mouse_x, event.mouse_y, ctx_ptr)
				e.cur_line = pos.line
				e.cur_col = pos.col
				e.sel_b = ce_pos(pos.line, pos.col)
				e.fire_cursor_move()
				return true
			}
			if e.hovered && unsafe { ctx_ptr != nil } {
				if e.has_vsb(ctx_ptr) {
					track, _ := e.vsb_rects(ctx_ptr)
					e.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					e.vsb_hovered = false
				}
				if e.has_hsb(ctx_ptr) {
					track, _ := e.hsb_rects(ctx_ptr)
					e.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					e.hsb_hovered = false
				}
				if e.show_minimap {
					mr := e.minimap_rect(ctx_ptr)
					e.minimap_hovered = mr.contains(event.mouse_x, event.mouse_y)
				}
			} else {
				e.vsb_hovered = false
				e.hsb_hovered = false
				e.minimap_hovered = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && e.hovered {
				if unsafe { ctx_ptr != nil } {
					// Minimap click
					if e.show_minimap {
						mr := e.minimap_rect(ctx_ptr)
						if mr.contains(event.mouse_x, event.mouse_y) {
							e.minimap_dragging = true
							e.scroll_y = e.minimap_y_to_scroll(event.mouse_y, ctx_ptr)
							e.focused = true
							return true
						}
					}
					// Vertical scrollbar
					if e.has_vsb(ctx_ptr) {
						_, thumb := e.vsb_rects(ctx_ptr)
						if thumb.contains(event.mouse_x, event.mouse_y) {
							e.vsb_dragging = true
							e.vsb_drag_start_y = event.mouse_y
							e.vsb_drag_start_scroll = e.scroll_y
							return true
						}
					}
					// Horizontal scrollbar
					if e.has_hsb(ctx_ptr) {
						_, thumb := e.hsb_rects(ctx_ptr)
						if thumb.contains(event.mouse_x, event.mouse_y) {
							e.hsb_dragging = true
							e.hsb_drag_start_x = event.mouse_x
							e.hsb_drag_start_scroll = e.scroll_x
							return true
						}
					}
					// Focus + cursor
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					e.focused = true
					pos := e.hit_pos(event.mouse_x, event.mouse_y, ctx_ptr)
					e.cur_line = pos.line
					e.cur_col = pos.col
					if event.shift() {
						e.ensure_sel()
						e.sel_b = ce_pos(pos.line, pos.col)
					} else {
						e.sel_a = ce_pos(pos.line, pos.col)
						e.sel_b = e.sel_a
					}
					e.drag = true
					e.fire_cursor_move()
					_ = ctx_mut
				}
				return true
			}
			if e.focused && !e.hovered {
				e.focused = false
				e.drag = false
				e.clear_sel()
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && e.drag {
				e.drag = false
				if e.sel_a.eq(e.sel_b) {
					e.clear_sel()
				}
				return e.focused
			}
		}
		.mouse_dbl_click {
			if e.focused && e.hovered && unsafe { ctx_ptr != nil } {
				e.select_word_at_cursor()
				e.drag = false
				return true
			}
		}
		.mouse_wheel {
			if !e.wheel {
				return false
			}
			if !e.focused {
				return false
			}
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if e.bounds.contains(mx, my) && unsafe { ctx_ptr != nil } {
				if event.shift() {
					old := e.scroll_x
					e.scroll_x -= event.wheel_y * e.scroll_speed
					e.scroll_x = clamp_f32(e.scroll_x, 0, e.max_scroll_x(ctx_ptr))
					return e.scroll_x != old
				}
				old := e.scroll_y
				e.scroll_y -= event.wheel_y * e.scroll_speed
				e.scroll_y = clamp_f32(e.scroll_y, 0, e.max_scroll_y(ctx_ptr))
				return e.scroll_y != old
			}
		}
		.text_input {
			if !e.focused || e.readonly {
				return false
			}
			mod_state := C.SDL_GetModState()
			if (mod_state & sdl_kmod_ctrl) != 0 {
				return true
			}
			e.insert_text(event.text)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		.key_down {
			if !e.focused {
				return false
			}
			return e.handle_key(event, app, ctx_ptr)
		}
		else {}
	}

	return false
}

// ─── Key handling ──────────────────────────────────────

fn (mut e CodeEditor) handle_key(ev &GuiEvent, app &App, ctx_ptr &RenderContext) bool {
	ctrl := ev.ctrl()
	shift := ev.shift()

	// ── Read-only mode: navigation + copy only ──
	if e.readonly {
		if ctrl {
			if ev.keycode == sdl_k_c || ev.scancode == sc_letter_c {
				if e.has_sel() {
					app.set_clipboard(e.selected_text())
				}
				return true
			}
			if ev.keycode == sdl_k_insert {
				if e.has_sel() {
					app.set_clipboard(e.selected_text())
				}
				return true
			}
			if ev.keycode == sdl_k_a || ev.scancode == sc_letter_a {
				e.sel_a = ce_pos(0, 0)
				last := e.lines.len - 1
				e.sel_b = ce_pos(last, e.lines[last].len)
				e.cur_line = last
				e.cur_col = e.lines[last].len
				e.fire_cursor_move()
				return true
			}
		}
		match ev.keycode {
			sdl_k_up {
				e.move_cursor_up(shift)
				if unsafe { ctx_ptr != nil } {
					e.ensure_cursor_visible(ctx_ptr)
				}
				return true
			}
			sdl_k_down {
				e.move_cursor_down(shift)
				if unsafe { ctx_ptr != nil } {
					e.ensure_cursor_visible(ctx_ptr)
				}
				return true
			}
			sdl_k_left {
				e.move_cursor_left(ctrl, shift)
				if unsafe { ctx_ptr != nil } {
					e.ensure_cursor_visible(ctx_ptr)
				}
				return true
			}
			sdl_k_right {
				e.move_cursor_right(ctrl, shift)
				if unsafe { ctx_ptr != nil } {
					e.ensure_cursor_visible(ctx_ptr)
				}
				return true
			}
			else {}
		}

		if is_home_key(ev.keycode, ev.scancode) {
			e.key_home(shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		if is_end_key(ev.keycode, ev.scancode) {
			e.key_end(shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		return false
	}

	// ── Home/End ──
	if is_home_key(ev.keycode, ev.scancode) {
		e.key_home(shift)
		if unsafe { ctx_ptr != nil } {
			e.ensure_cursor_visible(ctx_ptr)
		}
		return true
	}
	if is_end_key(ev.keycode, ev.scancode) {
		e.key_end(shift)
		if unsafe { ctx_ptr != nil } {
			e.ensure_cursor_visible(ctx_ptr)
		}
		return true
	}

	// ── Ctrl+key combinations ──
	if ctrl {
		if ev.keycode == sdl_k_a || ev.scancode == sc_letter_a {
			e.sel_a = ce_pos(0, 0)
			last := e.lines.len - 1
			e.sel_b = ce_pos(last, e.lines[last].len)
			e.cur_line = last
			e.cur_col = e.lines[last].len
			e.fire_cursor_move()
			return true
		}
		if ev.keycode == sdl_k_c || ev.scancode == sc_letter_c {
			if e.has_sel() {
				app.set_clipboard(e.selected_text())
			}
			return true
		}
		if ev.keycode == sdl_k_x || ev.scancode == sc_letter_x {
			if e.has_sel() {
				app.set_clipboard(e.selected_text())
				e.save_undo()
				e.delete_sel()
				e.fire_change()
			}
			return true
		}
		if ev.keycode == sdl_k_v || ev.scancode == sc_letter_v {
			cl := app.get_clipboard()
			if cl.len > 0 {
				e.insert_text(cl)
			}
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		if ev.keycode == sdl_k_z || ev.scancode == sc_letter_z {
			if shift {
				e.redo()
			} else {
				e.undo()
			}
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		if ev.keycode == sdl_k_insert {
			if e.has_sel() {
				app.set_clipboard(e.selected_text())
			}
			return true
		}
	}

	// ── Shift+key combinations (non-ctrl) ──
	if shift && !ctrl {
		match ev.keycode {
			sdl_k_insert {
				cl := app.get_clipboard()
				if cl.len > 0 {
					e.insert_text(cl)
				}
				if unsafe { ctx_ptr != nil } {
					e.ensure_cursor_visible(ctx_ptr)
				}
				return true
			}
			else {}
		}
	}

	// ── Non-modifier keys ──
	match ev.keycode {
		sdl_k_return {
			e.key_enter()
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_backspace {
			e.key_backspace(ctrl)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_delete {
			e.key_delete(ctrl)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_tab {
			if shift {
				e.key_shift_tab()
			} else {
				e.key_tab()
			}
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_up {
			e.move_cursor_up(shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_down {
			e.move_cursor_down(shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_left {
			e.move_cursor_left(ctrl, shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_right {
			e.move_cursor_right(ctrl, shift)
			if unsafe { ctx_ptr != nil } {
				e.ensure_cursor_visible(ctx_ptr)
			}
			return true
		}
		sdl_k_escape {
			e.focused = false
			e.clear_sel()
			return true
		}
		else {}
	}

	// ── Page Up/Down ──
	if tv_is_pageup_key(ev.keycode, ev.scancode) && unsafe { ctx_ptr != nil } {
		cr := e.content_rect(ctx_ptr)
		lh := e.line_height(ctx_ptr)
		page := max_int(1, int(cr.h / lh))
		if shift {
			e.ensure_sel()
		}
		e.cur_line = max_int(0, e.cur_line - page)
		e.clamp_cursor()
		if shift {
			e.sel_b = ce_pos(e.cur_line, e.cur_col)
		} else {
			e.clear_sel()
		}
		e.ensure_cursor_visible(ctx_ptr)
		e.fire_cursor_move()
		return true
	}
	if tv_is_pagedown_key(ev.keycode, ev.scancode) && unsafe { ctx_ptr != nil } {
		cr := e.content_rect(ctx_ptr)
		lh := e.line_height(ctx_ptr)
		page := max_int(1, int(cr.h / lh))
		if shift {
			e.ensure_sel()
		}
		e.cur_line = min_int(e.lines.len - 1, e.cur_line + page)
		e.clamp_cursor()
		if shift {
			e.sel_b = ce_pos(e.cur_line, e.cur_col)
		} else {
			e.clear_sel()
		}
		e.ensure_cursor_visible(ctx_ptr)
		e.fire_cursor_move()
		return true
	}

	return false
}

// ─── Cursor movement ───────────────────────────────────

fn (mut e CodeEditor) move_cursor_up(shift bool) {
	if shift {
		e.ensure_sel()
	}
	if e.cur_line > 0 {
		e.cur_line -= 1
		e.cur_col = min_int(e.cur_col, e.lines[e.cur_line].len)
	}
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

fn (mut e CodeEditor) move_cursor_down(shift bool) {
	if shift {
		e.ensure_sel()
	}
	if e.cur_line < e.lines.len - 1 {
		e.cur_line += 1
		e.cur_col = min_int(e.cur_col, e.lines[e.cur_line].len)
	}
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

fn (mut e CodeEditor) move_cursor_left(ctrl bool, shift bool) {
	if shift {
		e.ensure_sel()
	}
	if ctrl {
		e.cur_col = e.word_left()
	} else if !shift && e.has_sel() {
		s := e.sel_start()
		e.cur_line = s.line
		e.cur_col = s.col
		e.clear_sel()
		e.fire_cursor_move()
		return
	} else {
		if e.cur_col > 0 {
			e.cur_col -= 1
		} else if e.cur_line > 0 {
			e.cur_line -= 1
			e.cur_col = e.lines[e.cur_line].len
		}
	}
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

fn (mut e CodeEditor) move_cursor_right(ctrl bool, shift bool) {
	if shift {
		e.ensure_sel()
	}
	if ctrl {
		e.cur_col = e.word_right()
	} else if !shift && e.has_sel() {
		en := e.sel_end()
		e.cur_line = en.line
		e.cur_col = en.col
		e.clear_sel()
		e.fire_cursor_move()
		return
	} else {
		line := e.lines[e.cur_line]
		if e.cur_col < line.len {
			e.cur_col += 1
		} else if e.cur_line < e.lines.len - 1 {
			e.cur_line += 1
			e.cur_col = 0
		}
	}
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

fn (mut e CodeEditor) key_home(shift bool) {
	if shift {
		e.ensure_sel()
	}
	e.cur_col = 0
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

fn (mut e CodeEditor) key_end(shift bool) {
	if shift {
		e.ensure_sel()
	}
	e.cur_col = e.lines[e.cur_line].len
	if shift {
		e.sel_b = ce_pos(e.cur_line, e.cur_col)
	} else {
		e.clear_sel()
	}
	e.fire_cursor_move()
}

// ─── Editing keys ──────────────────────────────────────

fn ce_leading_indent(line []rune) int {
	mut n := 0
	for r in line {
		if r == ` ` || r == `\t` {
			n++
		} else {
			break
		}
	}
	return n
}

fn (mut e CodeEditor) key_enter() {
	e.save_undo()
	if e.has_sel() {
		e.delete_sel()
	}
	line := e.lines[e.cur_line]
	col := clamp_int(e.cur_col, 0, line.len)
	after := if col < line.len { line[col..].clone() } else { []rune{} }
	e.lines[e.cur_line] = if col > 0 { line[..col].clone() } else { []rune{} }

	mut indent_runes := []rune{}
	if e.auto_indent {
		indent_count := ce_leading_indent(line)
		if indent_count > 0 {
			for i in 0 .. indent_count {
				indent_runes << line[i]
			}
		}
	}

	e.cur_line += 1
	mut new_line := []rune{cap: indent_runes.len + after.len}
	for r in indent_runes {
		new_line << r
	}
	for r in after {
		new_line << r
	}
	e.lines.insert(e.cur_line, new_line)
	e.cur_col = indent_runes.len
	e.fire_change()
}

fn (mut e CodeEditor) key_backspace(ctrl bool) {
	if e.has_sel() {
		e.save_undo()
		e.delete_sel()
		e.fire_change()
		return
	}
	if ctrl {
		if e.cur_col > 0 {
			e.save_undo()
			old_col := e.cur_col
			e.cur_col = e.word_left()
			mut line := e.lines[e.cur_line]
			mut nw := []rune{cap: line.len - (old_col - e.cur_col)}
			for i in 0 .. e.cur_col {
				nw << line[i]
			}
			for i in old_col .. line.len {
				nw << line[i]
			}
			e.lines[e.cur_line] = nw
			e.fire_change()
		} else if e.cur_line > 0 {
			e.save_undo()
			prev := e.lines[e.cur_line - 1]
			e.cur_col = prev.len
			mut merged := prev.clone()
			for r in e.lines[e.cur_line] {
				merged << r
			}
			e.lines[e.cur_line - 1] = merged
			e.lines.delete(e.cur_line)
			e.cur_line -= 1
			e.fire_change()
		}
		return
	}
	if e.cur_col > 0 {
		e.save_undo()
		mut line := e.lines[e.cur_line]
		mut nw := []rune{cap: line.len - 1}
		for i in 0 .. e.cur_col - 1 {
			nw << line[i]
		}
		for i in e.cur_col .. line.len {
			nw << line[i]
		}
		e.lines[e.cur_line] = nw
		e.cur_col -= 1
		e.fire_change()
	} else if e.cur_line > 0 {
		e.save_undo()
		prev := e.lines[e.cur_line - 1]
		e.cur_col = prev.len
		mut merged := prev.clone()
		for r in e.lines[e.cur_line] {
			merged << r
		}
		e.lines[e.cur_line - 1] = merged
		e.lines.delete(e.cur_line)
		e.cur_line -= 1
		e.fire_change()
	}
}

fn (mut e CodeEditor) key_delete(ctrl bool) {
	if e.has_sel() {
		e.save_undo()
		e.delete_sel()
		e.fire_change()
		return
	}
	line := e.lines[e.cur_line]
	if ctrl {
		if e.cur_col < line.len {
			e.save_undo()
			end_col := e.word_right()
			mut nw := []rune{cap: line.len - (end_col - e.cur_col)}
			for i in 0 .. e.cur_col {
				nw << line[i]
			}
			for i in end_col .. line.len {
				nw << line[i]
			}
			e.lines[e.cur_line] = nw
			e.fire_change()
		} else if e.cur_line < e.lines.len - 1 {
			e.save_undo()
			mut merged := line.clone()
			for r in e.lines[e.cur_line + 1] {
				merged << r
			}
			e.lines[e.cur_line] = merged
			e.lines.delete(e.cur_line + 1)
			e.fire_change()
		}
		return
	}
	if e.cur_col < line.len {
		e.save_undo()
		mut nw := []rune{cap: line.len - 1}
		for i in 0 .. e.cur_col {
			nw << line[i]
		}
		for i in e.cur_col + 1 .. line.len {
			nw << line[i]
		}
		e.lines[e.cur_line] = nw
		e.fire_change()
	} else if e.cur_line < e.lines.len - 1 {
		e.save_undo()
		mut merged := line.clone()
		for r in e.lines[e.cur_line + 1] {
			merged << r
		}
		e.lines[e.cur_line] = merged
		e.lines.delete(e.cur_line + 1)
		e.fire_change()
	}
}

fn (mut e CodeEditor) key_tab() {
	spaces := '    '[..e.tab_size]
	e.insert_text(spaces)
}

fn (mut e CodeEditor) key_shift_tab() {
	e.save_undo()
	line := e.lines[e.cur_line]
	indent := ce_leading_indent(line)
	remove := min_int(e.tab_size, indent)
	if remove <= 0 {
		return
	}
	mut nw := []rune{cap: line.len - remove}
	for i in remove .. line.len {
		nw << line[i]
	}
	e.lines[e.cur_line] = nw
	e.cur_col = max_int(0, e.cur_col - remove)
	e.fire_change()
}

// ─── Word boundaries ───────────────────────────────────

fn (e &CodeEditor) word_left() int {
	line := e.lines[e.cur_line]
	if e.cur_col == 0 {
		return 0
	}
	mut p := e.cur_col - 1
	for p > 0 && !is_word(line[p]) {
		p--
	}
	for p > 0 && is_word(line[p - 1]) {
		p--
	}
	return p
}

fn (e &CodeEditor) word_right() int {
	line := e.lines[e.cur_line]
	n := line.len
	if e.cur_col >= n {
		return n
	}
	mut p := e.cur_col
	for p < n && is_word(line[p]) {
		p++
	}
	for p < n && !is_word(line[p]) {
		p++
	}
	return p
}

fn (mut e CodeEditor) select_word_at_cursor() {
	line := e.lines[e.cur_line]
	if line.len == 0 {
		return
	}
	p := clamp_int(e.cur_col, 0, line.len - 1)
	mut a := p
	mut b := p
	for a > 0 && is_word(line[a - 1]) {
		a--
	}
	for b < line.len && is_word(line[b]) {
		b++
	}
	e.sel_a = ce_pos(e.cur_line, a)
	e.sel_b = ce_pos(e.cur_line, b)
	e.cur_col = b
}

// ─── File I/O with encoding ────────────────────────────

pub fn (mut e CodeEditor) load_file_encoded(path string, encoding string) bool {
	data := os.read_bytes(path) or { return false }
	enc := parse_encoding(encoding)
	text := decode_bytes(data, enc)
	e.set_text(text)
	return true
}

pub fn (e &CodeEditor) save_file(path string) bool {
	text := e.get_text()
	os.write_file(path, text) or { return false }
	return true
}

pub fn (e &CodeEditor) save_file_encoded(path string, encoding string, line_ending string) bool {
	mut text := e.get_text()
	le := if line_ending.len > 0 { line_ending } else { '\n' }
	if le == '\r\n' {
		text = text.replace('\n', '\r\n')
	}
	enc := parse_encoding(encoding)
	data := encode_string(text, enc)
	os.write_file_array(path, data) or { return false }
	return true
}

pub fn (mut e CodeEditor) load_file_auto(path string, fallback_encoding string) bool {
	data := os.read_bytes(path) or { return false }
	enc := if data.len >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
		TextEncoding.utf8
	} else {
		parse_encoding(fallback_encoding)
	}
	text := decode_bytes(data, enc)
	e.set_text(text)
	return true
}
