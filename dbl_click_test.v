module vgui

import os

// Двойной клик (аудит 2026-10, раздел 6.3). Раньше второй быстрый клик приходил
// как mouse_dbl_click ВМЕСТО mouse_down, и виджет, слушающий только нажатия
// (кнопка), его терял. Теперь окно рассылает обычный mouse_down с clicks = 2, а
// следом mouse_dbl_click. Виджеты, которые реагируют на оба, не должны
// срабатывать дважды за один клик.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test dbl_click_test.v

struct DblLog {
mut:
	n int
}

fn click_at(mut win Window, app &App, x f32, y f32, clicks int) {
	win.dispatch_event_with_app(&GuiEvent{ typ: .mouse_move, mouse_x: x, mouse_y: y }, app)
	win.dispatch_event_with_app(&GuiEvent{
		typ:       .mouse_down
		mouse_btn: .left
		mouse_x:   x
		mouse_y:   y
		clicks:    clicks
	}, app)
	win.dispatch_event_with_app(&GuiEvent{
		typ:       .mouse_up
		mouse_btn: .left
		mouse_x:   x
		mouse_y:   y
		clicks:    clicks
	}, app)
}

// Быстрый двойной щелчок по кнопке - два on_click.
fn test_button_gets_both_clicks() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'dbl', width: 200, height: 100)!
	app.add_window(win)
	mut b := button('OK')
	mut log := &DblLog{}
	b.on_click = fn [mut log] () {
		log.n++
	}
	win.add_widget(b)
	win.render()
	app.active_ctx = &win.ctx
	cx := b.bounds.x + b.bounds.w / 2
	cy := b.bounds.y + b.bounds.h / 2
	click_at(mut win, app, cx, cy, 1)
	click_at(mut win, app, cx, cy, 2)
	app.active_ctx = unsafe { nil }
	assert log.n == 2

	win.cleanup()
	app.cleanup()
}

// Флажок PropertyGrid в колонке значения: каждый щелчок переключает ровно раз,
// двойной клик - два переключения (возврат к исходному), а не три.
fn test_property_grid_bool_toggles_once_per_click() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'dbl', width: 400, height: 300)!
	app.add_window(win)
	mut pg := property_grid()
	flag := pg.add_bool('flag', false)
	win.add_widget(pg)
	win.render()
	app.active_ctx = &win.ctx
	r := pg.row_rect(0)
	x := pg.split_x() + 10
	y := r.y + r.h / 2
	click_at(mut win, app, x, y, 1)
	assert flag.bool_val
	click_at(mut win, app, x, y, 2)
	assert !flag.bool_val
	app.active_ctx = unsafe { nil }

	win.cleanup()
	app.cleanup()
}

// ListBox: нажатие выбирает строку, двойной клик зовёт on_dbl_click один раз.
fn test_list_box_dbl_click() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'dbl', width: 200, height: 200)!
	app.add_window(win)
	mut lb := list_box()
	lb.add_items(['a', 'b', 'c'])
	mut log := &DblLog{}
	lb.on_dbl_click = fn [mut log] (i int, t string) {
		log.n += 10 + i
	}
	win.add_widget(lb)
	win.render()
	app.active_ctx = &win.ctx
	x := lb.bounds.x + 20
	y := lb.bounds.y + lb.pad + lb.item_height * 1.5
	click_at(mut win, app, x, y, 1)
	click_at(mut win, app, x, y, 2)
	app.active_ctx = unsafe { nil }
	assert lb.selected == 1
	assert log.n == 11

	win.cleanup()
	app.cleanup()
}
