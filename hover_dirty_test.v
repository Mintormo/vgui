module vgui

import os

// ═══════════════════════════════════════════════════════
// Точечная инвалидация hover (аудит 3.C) — dispatch_event_with_app больше
// не форсирует полный кадр на каждое mouse_move, а перерисовывает только
// виджет, потерявший hover, и виджет, его получивший
// (sdl3_window.v: invalidate_hover_change / hover_target / hover_partial_ok).
//
// Здесь — только бухгалтерия dirty-региона. Пиксельная эквивалентность
// частичного и полного кадров после движения мыши проверяется в
// render_dirty_test.v (там живёт инструмент capture_rgba/diff_count):
// test_partial_hover_frame_matches_full_frame_pixels.
//
// Запуск: v test vgui/hover_dirty_test.v
// ═══════════════════════════════════════════════════════

// make_hover_window собирает окно 200x200 с колонкой из двух кнопок по
// всей ширине: верхняя занимает верхнюю половину, нижняя — нижнюю.
// Возвращает их, чтобы тест мог сверять инвалидированный прямоугольник с
// реальными bounds, а не с координатами, посчитанными на глаз.
fn make_hover_window() !(&App, &Window, &Button, &Button) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'hover test', width: 200, height: 200, theme: light_theme())!
	mut top := button('top')
	mut bottom := button('bottom')
	mut col := create_vbox_fill()
	col.add(top, flex: 1)
	col.add(bottom, flex: 1)
	win.add_widget(col)
	app.add_window(win)
	// Первый кадр — полный (свежий render target), после него окно в покое:
	// bounds выставлены, dirty пуст.
	win.render()
	return app, win, top, bottom
}

fn move_to(x f32, y f32) GuiEvent {
	return GuiEvent{
		typ:     .mouse_move
		mouse_x: x
		mouse_y: y
	}
}

// covers сообщает, полностью ли inner лежит внутри outer (с запасом на
// visual_margin/инфляцию, которые invalidate() добавляет сам).
fn covers(outer Rect, inner Rect) bool {
	return outer.x <= inner.x && outer.y <= inner.y && outer.x + outer.w >= inner.x + inner.w
		&& outer.y + outer.h >= inner.y + inner.h
}

// ─── Движение мыши больше не форсирует полный кадр ───

fn test_mouse_move_over_widget_marks_only_that_widget() {
	mut app, mut win, mut top, mut bottom := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	assert win.ctx.dirty.is_empty(), 'сцена в покое: кадр не нужен'

	ev := move_to(100, top.bounds.y + top.bounds.h * 0.5)
	win.dispatch_event_with_app(&ev, app)

	assert !win.ctx.dirty.full, 'mouse_move не должен просить полный кадр'
	r := win.ctx.dirty.union_rect()
	assert covers(r, top.bounds), 'верхняя кнопка обязана попасть в грязную область'
	// Нижняя кнопка hover не меняла — её перерисовывать незачем.
	assert r.y + r.h < bottom.bounds.y + bottom.bounds.h

	win.cleanup()
	app.cleanup()
}

fn test_hover_leaving_widget_repaints_both_old_and_new() {
	mut app, mut win, mut top, mut bottom := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	first := move_to(100, top.bounds.y + top.bounds.h * 0.5)
	win.dispatch_event_with_app(&first, app)
	win.render()

	second := move_to(100, bottom.bounds.y + bottom.bounds.h * 0.5)
	win.dispatch_event_with_app(&second, app)

	assert !win.ctx.dirty.full
	r := win.ctx.dirty.union_rect()
	// Обе кнопки: у одной подсветка гаснет, у другой зажигается.
	assert covers(r, top.bounds)
	assert covers(r, bottom.bounds)

	win.cleanup()
	app.cleanup()
}

fn test_mouse_move_over_empty_background_needs_no_frame() {
	mut app, mut win, _, _ := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	// Колонка растянута на всё окно, поэтому «пустого» места в ней нет —
	// проверяем вырожденный случай честно: убираем виджеты вовсе.
	win.widgets.clear()
	win.ctx.dirty.clear()
	win.hover_widget = unsafe { nil }
	win.hover_rect = Rect{}

	ev := move_to(50, 50)
	win.dispatch_event_with_app(&ev, app)

	assert win.ctx.dirty.is_empty(), 'движение по пустому фону не должно будить рендер'

	win.cleanup()
	app.cleanup()
}

// ─── Случаи, где два прямоугольника недостаточны ───

fn test_drag_move_still_forces_full_frame() {
	mut app, mut win, mut top, _ := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	mut ev := move_to(100, top.bounds.y + top.bounds.h * 0.5)
	ev.mouse_buttons = 1 // левая кнопка зажата — идёт перетаскивание
	win.dispatch_event_with_app(&ev, app)

	assert win.ctx.dirty.full, 'при зажатой кнопке кадр обязан остаться полным'

	win.cleanup()
	app.cleanup()
}

fn test_modal_backdrop_forces_full_frame() {
	mut app, mut win, mut top, _ := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	win.has_modal_child = true
	ev := move_to(100, top.bounds.y + top.bounds.h * 0.5)
	win.dispatch_event_with_app(&ev, app)

	assert win.ctx.dirty.full, 'подложка модального диалога рисуется вне bounds виджетов'

	win.has_modal_child = false
	win.cleanup()
	app.cleanup()
}

// Полный кадр по «широким» причинам всё равно обязан вести учёт hover'а:
// иначе следующий частичный кадр стёр бы не тот прямоугольник.
fn test_hover_is_tracked_even_when_frame_is_full() {
	mut app, mut win, mut top, mut bottom := make_hover_window() or {
		assert false, 'setup failed: ${err}'
		return
	}
	mut drag := move_to(100, top.bounds.y + top.bounds.h * 0.5)
	drag.mouse_buttons = 1
	win.dispatch_event_with_app(&drag, app)
	assert win.ctx.dirty.full
	assert win.hover_rect == top.bounds, 'учёт hover ведётся и на полном кадре'

	win.render()
	next := move_to(100, bottom.bounds.y + bottom.bounds.h * 0.5)
	win.dispatch_event_with_app(&next, app)
	r := win.ctx.dirty.union_rect()
	assert covers(r, top.bounds), 'прошлый hover известен — его место перерисовано'
	assert covers(r, bottom.bounds)

	win.cleanup()
	app.cleanup()
}
