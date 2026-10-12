module vgui

import os

// CodeEditor: кэш ширины строк и hit_pos двоичным поиском (аудит 2026-10, 3.2).
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test code_editor_metrics_test.v

// Прежний перебор всех префиксов - эталон для двоичного поиска.
fn brute_hit_col(e &CodeEditor, ln []rune, rel_x f32, ctx &RenderContext) int {
	font := e.eff_font(ctx)
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
	return best
}

fn test_hit_pos_and_width_cache() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'ce', width: 600, height: 300)!
	app.add_window(win)
	mut e := code_editor()
	e.bounds = Rect{0, 0, 600, 300}
	e.set_text('fn main() {\n\tprintln("привет, мир")\n}')
	cr := e.content_rect(win.ctx)
	ln := e.lines[1]
	for x := f32(-5); x < 400; x += 7 {
		p := e.hit_pos(cr.x + x, cr.y + e.line_height(win.ctx) * 1.5, win.ctx)
		assert p.line == 1
		assert p.col == brute_hit_col(e, ln, x, win.ctx), 'x = ${x}'
	}

	w1 := e.max_content_width(win.ctx)
	assert e.max_content_width(win.ctx) == w1 // из кэша
	e.cur_line, e.cur_col = 1, e.lines[1].len
	e.insert_text(' и ещё длинный хвост строки')
	assert e.max_content_width(win.ctx) > w1, 'правка сбрасывает кэш'
	e.tab_size = 12
	w_tab := e.max_content_width(win.ctx)
	assert w_tab > w1, 'смена таба сбрасывает кэш'

	win.cleanup()
	app.cleanup()
}
