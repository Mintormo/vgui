module vgui

import os

// Тесты anim.v: кривые, режимы Anim, шаг кадра в Window.render() и то, что
// виджеты с анимацией фокуса просят следующий кадр.

fn close_to(a f32, b f32, eps f32) bool {
	return abs_f32(a - b) < eps
}

fn test_ease_endpoints_and_shape() {
	for e in [Easing.linear, .in_quad, .out_quad, .in_out_quad, .in_cubic, .out_cubic, .in_out_cubic,
		.out_back] {
		assert close_to(ease(e, 0), 0, 1e-6), '${e} в 0'
		assert close_to(ease(e, 1), 1, 1e-6), '${e} в 1'
		assert ease(e, -1) == ease(e, 0) && ease(e, 2) == ease(e, 1) // t зажат
	}
	assert ease(.in_quad, 0.5) < 0.5 && ease(.out_quad, 0.5) > 0.5
	assert close_to(ease(.in_out_cubic, 0.5), 0.5, 1e-6)
	// out_back перелетает цель
	mut over := false
	for i in 1 .. 20 {
		if ease(.out_back, f32(i) / 20) > 1 {
			over = true
		}
	}
	assert over
}

// При 60 fps .smooth повторяет прежнее «x += (цель - x) * k за кадр».
fn test_smooth_matches_old_per_frame_factor() {
	for pair in [[anim_tau_focus, f32(0.18)], [anim_tau_hover, f32(0.2)], [anim_tau_toggle, f32(0.25)],
		[anim_tau_press, f32(0.3)]] {
		mut a := anim_smooth(pair[0])
		a.set_target(1)
		a.advance(anim_nominal_dt)
		assert close_to(a.value, pair[1], 0.003), 'tau ${pair[0]}: ${a.value}'
	}
}

// Два кадра по 8 мс — то же, что один на 16 мс: скорость не зависит от fps.
fn test_smooth_is_frame_rate_independent() {
	mut fast := anim_smooth(anim_tau_hover)
	mut slow := anim_smooth(anim_tau_hover)
	fast.set_target(1)
	slow.set_target(1)
	for _ in 0 .. 10 {
		fast.advance(anim_nominal_dt / 2)
		fast.advance(anim_nominal_dt / 2)
		slow.advance(anim_nominal_dt)
	}
	assert close_to(fast.value, slow.value, 1e-4)
}

fn test_smooth_settles_and_retargets() {
	mut a := anim_smooth(anim_tau_hover)
	assert !a.animating()
	a.set_target(1)
	assert a.animating()
	mut frames := 0
	for a.animating() && frames < 1000 {
		a.advance(anim_nominal_dt)
		frames++
	}
	assert a.value == 1 && !a.animating()
	assert frames > 10 && frames < 40, '${frames}'
	// смена цели на ходу — без рывка
	a.set_target(0)
	a.advance(anim_nominal_dt)
	mid := a.value
	a.set_target(1)
	a.advance(anim_nominal_dt)
	assert a.value > mid && a.value < 1
}

fn test_tween_duration_easing_restart() {
	mut a := anim_tween(100, .linear)
	a.set_target(10)
	a.advance(25)
	assert close_to(a.value, 2.5, 1e-4)
	a.advance(25)
	assert close_to(a.value, 5, 1e-4)
	// новая цель — новый переход от текущего значения
	a.set_target(0)
	a.advance(50)
	assert close_to(a.value, 2.5, 1e-4)
	a.advance(50)
	assert a.value == 0 && !a.animating()
	// шаг ограничен anim_max_dt: после подвисания переход не перескакивает
	mut b := anim_tween(1000, .linear)
	b.set_target(1)
	b.advance(5000)
	assert close_to(b.value, anim_max_dt / 1000, 1e-4)
}

fn test_snap_and_at() {
	mut a := anim_smooth(anim_tau_hover).at(1)
	assert a.value == 1 && a.goal == 1 && !a.animating()
	a.set_target(0)
	a.advance(anim_nominal_dt)
	a.snap(0.5)
	assert a.value == 0.5 && !a.animating()
}

// update() шагает не больше раза за кадр (arrange + draw одного кадра).
fn test_update_steps_once_per_frame() {
	mut ctx := RenderContext{
		frame_no: 7
	}
	mut a := anim_smooth(anim_tau_hover)
	a.update(1, ctx)
	v1 := a.value
	a.update(1, ctx)
	assert a.value == v1
	ctx.frame_no++
	a.update(1, ctx)
	assert a.value > v1
	// без номера кадра (ручной контекст) — шаг на каждый вызов
	mut bare := RenderContext{}
	mut b := anim_smooth(anim_tau_hover)
	b.update(1, bare)
	w1 := b.value
	b.update(1, bare)
	assert b.value > w1
}

fn make_anim_test_window() !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'anim test', width: 300, height: 200, theme: light_theme())!
	app.add_window(win)
	return app, win
}

// Шаг кадра: после простоя — номинальный (иначе анимация, начатая сейчас,
// перепрыгнула бы через секунды тишины), во время анимации — по часам с
// потолком, при anim_fixed_dt — ровно он.
fn test_render_frame_dt() {
	mut app, mut win := make_anim_test_window() or {
		assert false, 'window: ${err}'
		return
	}
	now := C.SDL_GetTicks()
	win.ctx.anim_last_ms = 1 // «давно»
	win.ctx.needs_animation = false
	win.render()
	assert win.ctx.anim_dt == anim_nominal_dt

	win.ctx.anim_last_ms = now - 10_000
	win.ctx.needs_animation = true
	win.render()
	assert win.ctx.anim_dt == anim_max_dt

	win.ctx.anim_fixed_dt = 5
	win.ctx.needs_animation = true
	win.render()
	assert win.ctx.anim_dt == 5

	win.cleanup()
	app.cleanup()
}

// Раньше ComboBox, ListBox, TabBox, TableView, TreeView, PropertyGrid,
// TextInput, TextArea и CodeEditor шагали кольцо фокуса, но кадр не просили:
// после потери фокуса кольцо застывало на первом шаге до следующего события.
fn test_focus_fade_requests_next_frame() {
	mut app, mut win := make_anim_test_window() or {
		assert false, 'window: ${err}'
		return
	}
	mut cb := combo_box()
	mut lb := list_box()
	mut tb := tab_box()
	tb.add_tab('A', create_spacer()) // пустой TabBox не рисуется вовсе
	mut tbl := table_view()
	tbl.add_column('A', 80) // таблица без колонок не рисуется
	mut tv := tree_view()
	mut pg := property_grid()
	mut ti := text_input('')
	mut ta := text_area('')
	mut ce := code_editor()
	// «только что потеряли фокус»: кольцо видно, цель — 0
	cb.focus_anim = cb.focus_anim.at(1)
	lb.focus_anim = lb.focus_anim.at(1)
	tb.focus_anim = tb.focus_anim.at(1)
	tbl.focus_anim = tbl.focus_anim.at(1)
	tv.focus_anim = tv.focus_anim.at(1)
	pg.focus_anim = pg.focus_anim.at(1)
	ti.focus_t = ti.focus_t.at(1)
	ta.focus_t = ta.focus_t.at(1)
	ce.focus_anim = ce.focus_anim.at(1)
	widgets := [&Widget(cb), lb, tb, tbl, tv, pg, ti, ta, ce]
	for w in widgets {
		mut root := create_vbox_fill()
		root.add(w, flex: 1)
		win.widgets.clear()
		win.add_widget(root)
		win.ctx.invalidate_all()
		win.render()
		assert win.ctx.needs_animation, 'виджет не попросил кадр: ${w.type_name()}'
	}
	win.cleanup()
	app.cleanup()
}
