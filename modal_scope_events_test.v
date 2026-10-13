module vgui

import os

// ═══════════════════════════════════════════════════════
// Область модальности, сквозная проверка (аудит 3.D): события, реально
// пропущенные через app.process_events(), доходят до соседнего окна, пока
// открыт модальный диалог другого окна. Решение о блокировке принимает
// modal_blocker_index (modal_scope.v, свои тесты в modal_scope_test.v) —
// здесь проверяется, что оно правильно подключено к циклу событий.
//
// События подкладываются в очередь SDL (testkit.v, sim_click: SDL_PushEvent +
// process_events), дисплей не нужен (SDL_VIDEODRIVER=dummy).
//
// Запуск: v -enable-globals test vgui/modal_scope_events_test.v
// ═══════════════════════════════════════════════════════

@[heap]
struct ClickCounter {
mut:
	n int
}

// make_two_windows собирает два независимых окна, в каждом — кнопка на всю
// клиентскую область, считающая клики.
fn make_two_windows() !(&App, &Window, &Window, &ClickCounter, &ClickCounter) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win1 := create_window(title: 'win1', width: 200, height: 200)!
	mut win2 := create_window(title: 'win2', width: 200, height: 200)!

	mut c1 := &ClickCounter{}
	mut c2 := &ClickCounter{}

	mut b1 := button('one')
	b1.on_click = fn [mut c1] () {
		c1.n++
	}
	mut b2 := button('two')
	b2.on_click = fn [mut c2] () {
		c2.n++
	}

	mut col1 := create_vbox_fill()
	col1.add(b1, flex: 1)
	mut col2 := create_vbox_fill()
	col2.add(b2, flex: 1)

	win1.add_widget(col1)
	win2.add_widget(col2)
	app.add_window(win1)
	app.add_window(win2)
	win1.render()
	win2.render()
	return app, win1, win2, c1, c2
}

// open_modal_over открывает модальный диалог над parent (nil — без родителя).
fn open_modal_over(mut app App, parent &Window) !&Dialog {
	mut dlg := create_dialog(
		title:  'modal'
		width:  160
		height: 120
		parent: unsafe { parent }
	)!
	app.add_dialog(dlg)
	dlg.show()
	dlg.win.render()
	return dlg
}

// Модальный диалог окна 1 блокирует окно 1 и не трогает окно 2.
fn test_modal_blocks_only_its_own_window_end_to_end() {
	mut app, mut win1, mut win2, mut c1, mut c2 := make_two_windows() or {
		assert false, err.msg()
		return
	}
	defer {
		app.cleanup()
	}

	// До диалога кликаются оба окна.
	sim_click(mut app, win1, 100, 100, .left, 1, 0)
	sim_click(mut app, win2, 100, 100, .left, 1, 0)
	assert c1.n == 1
	assert c2.n == 1

	mut dlg := open_modal_over(mut app, win1) or {
		assert false, err.msg()
		return
	}

	sim_click(mut app, win1, 100, 100, .left, 1, 0)
	sim_click(mut app, win2, 100, 100, .left, 1, 0)
	assert c1.n == 1, 'окно под модальным диалогом должно молчать'
	assert c2.n == 2, 'соседнее окно должно продолжать получать события'

	// После закрытия диалога первое окно снова живое.
	dlg.close_with_result(0)
	app.remove_dialog(dlg)
	dlg.win.cleanup()

	sim_click(mut app, win1, 100, 100, .left, 1, 0)
	assert c1.n == 2
}

// Диалог без родителя модален для всего приложения — поведение до 3.D.
fn test_parentless_modal_blocks_all_windows_end_to_end() {
	mut app, mut win1, mut win2, mut c1, mut c2 := make_two_windows() or {
		assert false, err.msg()
		return
	}
	defer {
		app.cleanup()
	}

	mut dlg := open_modal_over(mut app, unsafe { nil }) or {
		assert false, err.msg()
		return
	}

	sim_click(mut app, win1, 100, 100, .left, 1, 0)
	sim_click(mut app, win2, 100, 100, .left, 1, 0)
	assert c1.n == 0
	assert c2.n == 0

	dlg.close_with_result(0)
	app.remove_dialog(dlg)
	dlg.win.cleanup()
}

// Немодальный диалог не блокирует даже собственное окно.
fn test_modeless_dialog_blocks_nothing_end_to_end() {
	mut app, mut win1, _, mut c1, _ := make_two_windows() or {
		assert false, err.msg()
		return
	}
	defer {
		app.cleanup()
	}

	mut dlg := create_dialog(
		title:  'modeless'
		width:  160
		height: 120
		parent: unsafe { win1 }
	) or {
		assert false, err.msg()
		return
	}
	dlg.modal = false
	app.add_dialog(dlg)
	dlg.show()

	sim_click(mut app, win1, 100, 100, .left, 1, 0)
	assert c1.n == 1

	dlg.close_with_result(0)
	app.remove_dialog(dlg)
	dlg.win.cleanup()
}
