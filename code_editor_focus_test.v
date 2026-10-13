module vgui

import os

// CodeEditor и фокус (аудит 2026-10, раздел 6.1): редактор участвует в Tab-порядке
// окна через FocusManager. Tab вставляет отступ, Ctrl+Tab передаёт фокус дальше,
// Esc и клик мимо снимают его. Плюс «желаемая» колонка вертикального движения.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test code_editor_focus_test.v

fn ce_key(key int, mods u16) &GuiEvent {
	return &GuiEvent{
		typ:      .key_down
		keycode:  key
		mod_keys: mods
	}
}

fn test_ctrl_tab_moves_focus_tab_indents() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'ce', width: 400, height: 300)!
	app.add_window(win)
	app.active_ctx = &win.ctx

	mut e := code_editor()
	e.bounds = Rect{0, 0, 300, 200}
	mut ti := text_input('')
	ti.bounds = Rect{0, 210, 300, 30}
	// регистрация в Tab-порядке происходит в draw
	e.draw(mut win.ctx)
	ti.draw(mut win.ctx)

	// клик в редакторе берёт фокус через FocusManager
	e.handle_event(&GuiEvent{ typ: .mouse_move, mouse_x: 50, mouse_y: 50 }, app)
	e.handle_event(&GuiEvent{ typ: .mouse_down, mouse_x: 50, mouse_y: 50, mouse_btn: .left },
		app)
	e.handle_event(&GuiEvent{ typ: .mouse_up, mouse_x: 50, mouse_y: 50, mouse_btn: .left },
		app)
	assert win.ctx.focus.is_focused(unsafe { voidptr(e) })
	assert win.ctx.focus.wants_text()

	// Tab - отступ, фокус остаётся
	e.handle_event(ce_key(sdl_k_tab, 0), app)
	assert e.get_line(0).starts_with('    ')
	assert win.ctx.focus.is_focused(unsafe { voidptr(e) })

	// Ctrl+Tab - фокус следующему виджету, текст не меняется
	e.handle_event(ce_key(sdl_k_tab, u16(sdl_kmod_ctrl)), app)
	assert e.get_line(0) == '    '
	assert win.ctx.focus.is_focused(unsafe { voidptr(ti) })
	e.draw(mut win.ctx)
	assert !e.focused

	// Shift+Tab из поля - снова в редактор (цикл из двух записей)
	win.ctx.focus.tab(true)
	assert win.ctx.focus.is_focused(unsafe { voidptr(e) })
	e.draw(mut win.ctx)
	assert e.focused

	// Esc снимает фокус в FocusManager, а не только флаг
	e.handle_event(ce_key(sdl_k_escape, 0), app)
	assert !e.focused
	assert !win.ctx.focus.is_focused(unsafe { voidptr(e) })
	assert !win.ctx.focus.wants_text()

	app.active_ctx = unsafe { nil }
	win.cleanup()
	app.cleanup()
}

// В readonly отступов нет: Tab сразу передаёт фокус.
fn test_readonly_tab_moves_focus() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'ce', width: 400, height: 300)!
	app.add_window(win)
	app.active_ctx = &win.ctx

	mut e := code_editor()
	e.readonly = true
	e.set_text('x')
	mut ti := text_input('')
	e.draw(mut win.ctx)
	ti.draw(mut win.ctx)
	win.ctx.focus.focus_code_editor(e, 0)
	e.handle_event(ce_key(sdl_k_tab, 0), app)
	assert e.get_line(0) == 'x'
	assert win.ctx.focus.is_focused(unsafe { voidptr(ti) })

	app.active_ctx = unsafe { nil }
	win.cleanup()
	app.cleanup()
}

// Проход стрелками через короткую строку возвращает курсор на прежнюю колонку;
// горизонтальное движение задаёт новую желаемую колонку.
fn test_vertical_move_keeps_goal_column() {
	mut e := code_editor()
	e.set_text('abcdefgh\nab\nabcdefgh')
	e.cur_line, e.cur_col = 0, 6
	e.move_cursor_down(false)
	assert e.cur_col == 2
	e.move_cursor_down(false)
	assert e.cur_col == 6
	e.move_cursor_up(false)
	e.move_cursor_up(false)
	assert e.cur_line == 0 && e.cur_col == 6

	e.move_cursor_down(false) // строка 'ab', колонка 2
	e.move_cursor_left(false, false) // колонка 1 - новая желаемая
	e.move_cursor_down(false)
	assert e.cur_line == 2 && e.cur_col == 1
}
