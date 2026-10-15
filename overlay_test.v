module vgui

import os

// Тесты слота оверлея попапа (overlay.v, аудит 2.4).
//
// Слот один на окно, у него есть владелец. Проверяется: чужой попап явно
// закрывает текущий, поздний close вытесненного попапа не стирает чужой
// оверлей, повторная установка тем же владельцем ничего не ломает, а
// release_overlay (путь vgui_destroy) убирает попап с экрана.
//
// Нужно реальное окно (шрифты для размеров попапа), под dummy-драйвером.
// Запуск: SDL_VIDEODRIVER=dummy v test vgui/overlay_test.v

fn make_overlay_test_window() !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'overlay test', width: 400, height: 300, theme: light_theme())!
	app.add_window(win)
	return app, win
}

fn open_test_combo(mut ctx RenderContext) &ComboBox {
	mut cb := combo_box()
	cb.add_items(['a', 'b', 'c'])
	cb.bounds = Rect{10, 10, 120, 28}
	cb.open_dropdown(mut ctx)
	return cb
}

// ─── Вытеснение: второй попап явно закрывает первый ────
//
// Раньше ContextMenu просто перетирал слот: ComboBox оставался open = true,
// но не рисовался и не получал событий (а клавиатура у него глохла — при
// open его handle_event отдаёт клавиши оверлею, которого уже нет).

fn test_context_menu_preempts_open_combo() {
	mut app, mut win := make_overlay_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut cb := open_test_combo(mut win.ctx)
	assert cb.open
	assert win.ctx.overlay_owner == voidptr(cb)

	mut cm := context_menu()
	cm.add(menu_action('Копировать'))
	cm.show(200, 100, mut win.ctx)

	assert !cb.open, 'вытесненный ComboBox должен закрыться явно'
	assert cm.is_open()
	assert win.ctx.overlay_owner == voidptr(cm)
	assert win.ctx.overlay_cb != unsafe { nil }
	assert win.ctx.overlay_ev != unsafe { nil }

	win.cleanup()
	app.cleanup()
}

fn test_combo_preempts_menu_button() {
	mut app, mut win := make_overlay_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut mb := menu_button('Действие')
	mb.add(menu_action('Один'))
	mb.bounds = Rect{200, 10, 120, 28}
	mb.open_menu(mut win.ctx)
	assert mb.open && mb.state.open
	assert win.ctx.overlay_owner == voidptr(mb)

	cb := open_test_combo(mut win.ctx)
	assert !mb.open && !mb.state.open, 'вытесненный MenuButton должен закрыться явно'
	assert win.ctx.overlay_owner == voidptr(cb)

	win.cleanup()
	app.cleanup()
}

// ─── Поздний close не трогает чужой слот ───────────────
//
// Вторая половина бага: close_dropdown/close_all обнуляли слот без проверки.
// Например, ComboBox закрывается по потере фокуса из draw() уже после того,
// как слот занял ContextMenu, — и стирал его меню.

fn test_late_close_of_preempted_popup_keeps_foreign_overlay() {
	mut app, mut win := make_overlay_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut cb := open_test_combo(mut win.ctx)
	mut cm := context_menu()
	cm.add(menu_action('Копировать'))
	cm.show(200, 100, mut win.ctx)

	cb.close_dropdown(mut win.ctx)
	assert win.ctx.overlay_owner == voidptr(cm), 'close вытесненного ComboBox стёр чужой оверлей'
	assert win.ctx.overlay_cb != unsafe { nil }
	assert cm.is_open()

	// Меню, которое ни разу не открывалось (owner ещё nil), тоже не должно
	// ничего стирать своим close.
	mut never := context_menu()
	never.close(mut win.ctx)
	assert win.ctx.overlay_owner == voidptr(cm)

	cm.close(mut win.ctx)
	assert win.ctx.overlay_owner == unsafe { nil }
	assert win.ctx.overlay_cb == unsafe { nil }
	assert win.ctx.overlay_ev == unsafe { nil }
	assert win.ctx.overlay_close == unsafe { nil }

	win.cleanup()
	app.cleanup()
}

// ─── Тот же владелец переустанавливает слот ────────────

fn test_menu_bar_switching_entries_keeps_its_overlay() {
	mut app, mut win := make_overlay_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut bar := menu_bar()
	bar.add_menu('Файл', [menu_action('Открыть')])
	bar.add_menu('Правка', [menu_action('Вставить')])
	bar.bounds = Rect{0, 0, 400, 28}

	bar.open_entry(0, mut win.ctx)
	assert bar.state.open && bar.state.bar_active == 0
	bar.open_entry(1, mut win.ctx)
	assert bar.state.open, 'переключение пункта MenuBar закрыло его же меню'
	assert bar.state.bar_active == 1
	assert win.ctx.overlay_owner == voidptr(bar)

	win.cleanup()
	app.cleanup()
}

// ─── release_overlay: путь vgui_destroy ────────────────

fn test_release_overlay_erases_popup_of_destroyed_widget() {
	mut app, mut win := make_overlay_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	cb := open_test_combo(mut win.ctx)
	win.render()
	assert win.prev_overlayish, 'раскрытый список должен рисоваться оверлеем'

	// Чужой адрес слот не трогает.
	other := combo_box()
	app.release_overlay(voidptr(other))
	assert win.ctx.overlay_owner == voidptr(cb)

	app.release_overlay(voidptr(cb))
	assert win.ctx.overlay_owner == unsafe { nil }
	assert win.ctx.overlay_cb == unsafe { nil }
	assert win.ctx.overlay_ev == unsafe { nil }
	assert win.ctx.overlay_close == unsafe { nil }

	// Следующий кадр полный (prev_overlayish) и оверлей в нём уже не рисуется.
	win.render()
	assert !win.prev_overlayish, 'список уничтоженного ComboBox всё ещё рисуется'

	win.cleanup()
	app.cleanup()
}
