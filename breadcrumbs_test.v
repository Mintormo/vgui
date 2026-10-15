module vgui

import os

// Breadcrumbs (аудит 2026-10, 2.14): наведение переживает пересборку сегментов в
// draw (раньше подсветка не рисовалась вовсе), корень пути виден в свёрнутом виде.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test breadcrumbs_test.v

fn test_collapsed_view_keeps_root_and_hover() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'bc', width: 400, height: 100)!
	app.add_window(win)

	mut bc := breadcrumbs_with_items(['Root', 'aaaaaaaaaa', 'bbbbbbbbbb', 'cccccccccc', 'dddddddddd',
		'Last'])
	font := win.ctx.get_font_immut(bc.font_style, bc.font_size)
	root_w := win.ctx.measure_text_with_font('Root', font).x
	last_w := win.ctx.measure_text_with_font('Last', font).x
	ell_w := win.ctx.measure_text_with_font('…', font).x
	sep_w := win.ctx.measure_text_with_font(bc.separator, font).x
	// Влезают корень, многоточие и последний, но не средние элементы.
	bc.bounds = Rect{0, 0, root_w + ell_w + last_w + sep_w * 2 + bc.pad_h * 2 + 4, 30}
	bc.layout(win.ctx)
	assert bc.overflow
	assert bc.segments.map(it.item) == [0, -1, 5]
	assert bc.segment_to_item_index(0) == 0
	assert bc.hidden_before == 4

	// Наведение на корень (кликабелен) сохраняется после draw с его пересборкой.
	seg := bc.segments[0]
	app.active_ctx = &win.ctx
	bc.handle_event(&GuiEvent{
		typ:     .mouse_move
		mouse_x: seg.x + 1
		mouse_y: 15
	}, app)
	assert bc.hover_seg == 0
	bc.draw(mut win.ctx)
	assert bc.hover_seg == 0
	app.active_ctx = unsafe { nil }

	win.cleanup()
	app.cleanup()
}
