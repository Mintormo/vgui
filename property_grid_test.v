module vgui

import os

// PropertyGrid (аудит 2026-10, 2.6): выбор варианта свойства .choice, readonly для
// bool, set_* зовут on_change только при реальном изменении.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test property_grid_test.v

struct PgChangeLog {
mut:
	names []string
}

fn pg_with_log() (&PropertyGrid, &PgChangeLog) {
	mut pg := property_grid()
	mut log := &PgChangeLog{}
	pg.on_change = fn [mut log] (p &Property) {
		log.names << p.name
	}
	return pg, log
}

fn test_setters_fire_on_change_only_on_change() {
	mut pg, log := pg_with_log()
	pg.add_int('n', 1)
	pg.add_choice('mode', ['a', 'b', 'c'], 0)
	pg.set_int('n', 1) // то же значение - тихо
	pg.set_int('n', 2)
	pg.set_choice('mode', 2)
	pg.set_choice('mode', 7) // вне списка - игнор
	assert pg.get_int('n') == 2
	assert pg.get_choice('mode') == 2
	assert log.names == ['n', 'mode']
}

fn test_readonly_bool_is_not_toggled() {
	mut pg, log := pg_with_log()
	mut ro := pg.add_bool('locked', true)
	ro.readonly = true
	rw := pg.add_bool('free', false)
	pg.toggle_bool(ro)
	pg.toggle_bool(rw)
	assert ro.bool_val
	assert rw.bool_val
	assert log.names == ['free']
}

fn test_choice_is_picked_from_menu() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'pg', width: 400, height: 300)!
	app.add_window(win)
	mut pg, log := pg_with_log()
	pg.bounds = Rect{0, 0, 400, 300}
	choice := pg.add_choice('mode', ['a', 'b', 'c'], 0)
	win.add_widget(pg)
	win.render()

	// Двойной клик по ячейке значения - как у пользователя, через окно.
	r := pg.row_rect(0)
	dbl := GuiEvent{
		typ:       .mouse_dbl_click
		mouse_x:   pg.split_x() + 10
		mouse_y:   r.y + r.h / 2
		mouse_btn: .left
	}
	// Как pump_events: на время раздачи события активный контекст - окно.
	app.active_ctx = &win.ctx
	win.dispatch_event_with_app(&dbl, app)
	app.active_ctx = unsafe { nil }
	assert unsafe { pg.choice_menu != nil }
	assert pg.choice_menu.is_open()
	assert !pg.editing, 'для .choice текстовый редактор не открывается'
	ev := win.ctx.overlay_ev
	down := GuiEvent{
		typ:     .key_down
		keycode: sdl_k_down
	}
	ev(&down, app)
	ev(&down, app)
	ev(&GuiEvent{ typ: .key_down, keycode: sdl_k_return }, app)
	assert choice.choice_idx == 1
	assert log.names == ['mode']
	assert !pg.choice_menu.is_open()

	win.cleanup()
	app.cleanup()
}
