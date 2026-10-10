module vgui

import os

// ═══════════════════════════════════════════════════════
// Hover после прокрутки колесом: содержимое уехало из-под неподвижного
// курсора - подсветка должна перейти на виджет, который теперь под ним,
// без движения мыши (синтетический mouse_move в dispatch_event_with_app).
//
// Запуск: v -enable-globals test vgui/wheel_hover_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

fn test_wheel_scroll_updates_hover() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'wheel hover', width: 200, height: 100)!
	app.add_window(win)

	mut col := create_vbox_fill()
	col.set_spacing(0)
	mut btns := []&Button{}
	for i in 0 .. 10 {
		b := button('b${i}')
		col.add(b)
		btns << b
	}
	mut sb := scroll_box(0)
	sb.add(col)
	win.add_widget(sb)
	win.render()

	// Курсор над первой кнопкой
	win.ctx.mouse_x = 50
	win.ctx.mouse_y = 20
	mv := GuiEvent{
		typ:     .mouse_move
		mouse_x: 50
		mouse_y: 20
	}
	win.dispatch_event_with_app(&mv, app)
	assert btns[0].hovered

	// Колесо вниз - содержимое сдвинулось, курсор на месте
	wh := GuiEvent{
		typ:     .mouse_wheel
		wheel_y: -1
		mouse_x: 50
		mouse_y: 20
	}
	win.dispatch_event_with_app(&wh, app)
	assert sb.scroll_y > 0
	assert !btns[0].hovered
	// Подсвечена ровно та кнопка, что теперь под курсором
	mut under := -1
	for i, b in btns {
		if b.bounds.contains(50, 20) {
			under = i
		}
	}
	assert under > 0
	assert btns[under].hovered

	win.cleanup()
	app.cleanup()
}
