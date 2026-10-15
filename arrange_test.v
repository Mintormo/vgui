module vgui

import os

// ═══════════════════════════════════════════════════════
// Фаза arrange (аудит 3.A, PROJECT.md «Фаза arrange»): раскладка отделена от
// draw(). Проверяется то, ради чего фаза заведена:
//   - событие видит раскладку, изменённую предыдущим событием, ещё ДО кадра
//     (раньше bounds обновлялись только в draw() следующего кадра);
//   - skip_draw-кадр раскладывает, если раскладку просили;
//   - анимация, шагающая в arrange(), шагает раз за кадр, а не на каждое
//     событие, и дети Accordion стоят там же, где рисуются заголовки.
//
// Запуск: v test vgui/arrange_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

fn make_arrange_test_window(w int, h int) !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'arrange test', width: w, height: h, theme: light_theme())!
	// Кадры в тесте идут подряд за доли мс — анимациям нужен шаг кадра, а не часы.
	win.ctx.anim_fixed_dt = anim_nominal_dt
	app.add_window(win)
	return app, win
}

// ProbeWidget запоминает bounds в момент получения события и считает draw();
// естественная высота - want_h (measure), 0 - растягивается
struct ProbeWidget {
pub mut:
	bounds Rect
	seen   Rect
	draws  int
	want_h f32
}

fn (p &ProbeWidget) measure(ctx &RenderContext) SizeHint {
	if p.want_h <= 0 {
		return SizeHint{
			h_policy: .expanding
			v_policy: .expanding
		}
	}
	return SizeHint{
		w:        10
		h:        p.want_h
		min_h:    p.want_h
		max_h:    p.want_h
		v_policy: .fixed
	}
}

fn (p &ProbeWidget) bounds_of() Rect {
	return p.bounds
}

fn (mut p ProbeWidget) set_bounds(r Rect) {
	p.bounds = r
}

fn (mut p ProbeWidget) draw(mut ctx RenderContext) {
	p.draws++
}

fn (mut p ProbeWidget) handle_event(event &GuiEvent, app &App) bool {
	p.seen = p.bounds
	return false
}

fn test_event_sees_layout_change_before_next_frame() {
	mut app, mut win := make_arrange_test_window(200, 200) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut top := &ProbeWidget{
		want_h: 50
	}
	mut bottom := &ProbeWidget{}
	mut v := create_vbox_fill()
	v.set_spacing(0)
	v.add(top)
	v.add(bottom, flex: 1)
	win.add_widget(v)

	win.render()
	assert bottom.bounds.y == 50

	// Изменение раскладки внутри обработки события: оно заканчивается
	// invalidate_all(), и следующее событие обязано увидеть новые bounds —
	// без кадра между ними.
	top.want_h = 120
	win.ctx.invalidate_all()
	ev := GuiEvent{
		typ:     .mouse_move
		mouse_x: 10
		mouse_y: 150
	}
	win.dispatch_event_with_app(&ev, app)
	assert bottom.seen.y == 120
	assert bottom.seen.h == 80

	win.cleanup()
	app.cleanup()
}

fn test_tab_switch_gives_new_tab_bounds_before_next_frame() {
	mut app, mut win := make_arrange_test_window(300, 200) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut p0 := &ProbeWidget{}
	mut p1 := &ProbeWidget{}
	mut tb := tab_box()
	tb.add_tab('A', p0)
	tb.add_tab('B', p1)
	win.add_widget(tb)

	win.render()
	assert p0.bounds.w > 0
	assert p1.bounds.w == 0 // неактивная вкладка не раскладывается

	tb.set_active(1)
	win.ctx.invalidate_all()
	ev := GuiEvent{
		typ:     .mouse_move
		mouse_x: 150
		mouse_y: 150
	}
	win.dispatch_event_with_app(&ev, app)
	// Hit-test второй вкладки сразу, а не после кадра: раньше здесь был
	// Rect{0,0,0,0}, и клик мимо.
	assert p1.bounds == p0.bounds

	win.cleanup()
	app.cleanup()
}

fn test_skip_draw_frame_arranges_only_on_request() {
	mut app, mut win := make_arrange_test_window(200, 200) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut top := &ProbeWidget{
		want_h: 50
	}
	mut bottom := &ProbeWidget{}
	mut v := create_vbox_fill()
	v.set_spacing(0)
	v.add(top)
	v.add(bottom, flex: 1)
	win.add_widget(v)

	win.render()
	assert bottom.draws == 1

	// Без запроса раскладка ленивая: сеттер без invalidate ничего не двигает
	// (тот же контракт, что у отрисовки).
	top.want_h = 120
	win.render()
	assert bottom.draws == 1 // skip_draw
	assert bottom.bounds.y == 50

	// С запросом — раскладывается даже кадр, который ничего не рисует.
	win.ctx.request_layout()
	win.render()
	assert bottom.draws == 1
	assert bottom.bounds.y == 120
	assert !win.ctx.layout_dirty

	win.cleanup()
	app.cleanup()
}

fn test_accordion_animation_steps_once_per_frame() {
	mut app, mut win := make_arrange_test_window(200, 300) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut a := accordion_multi()
	mut p0 := &ProbeWidget{}
	mut p1 := &ProbeWidget{}
	a.add_section('A', p0)
	a.add_section('B', p1)
	win.add_widget(a)
	win.render()

	a.set_expanded(0, true)
	win.ctx.invalidate_all()
	win.render()
	anim1 := a.sections[0].anim.value
	assert anim1 > 0 && anim1 < 1

	// arrange перед каждым событием не должен двигать анимацию.
	ev := GuiEvent{
		typ:     .mouse_move
		mouse_x: -10
		mouse_y: -10
	}
	for _ in 0 .. 5 {
		win.dispatch_event_with_app(&ev, app)
	}
	assert a.sections[0].anim.value == anim1

	win.render()
	assert a.sections[0].anim.value > anim1

	win.cleanup()
	app.cleanup()
}

fn test_accordion_child_positions_match_headers_mid_animation() {
	mut app, mut win := make_arrange_test_window(200, 400) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut a := accordion_multi()
	mut p0 := &ProbeWidget{}
	mut p1 := &ProbeWidget{}
	a.add_section('A', p0)
	a.add_section('B', p1)
	a.set_expanded(1, true)
	win.add_widget(a)
	for _ in 0 .. 60 {
		win.ctx.invalidate_all()
		win.render()
	}
	assert a.sections[1].anim.value == 1

	// Разворачиваем секцию выше: секция B и её ребёнок едут вниз по кадрам.
	a.set_expanded(0, true)
	win.ctx.invalidate_all()
	win.render()
	anim0 := a.sections[0].anim.value
	assert anim0 > 0.01 && anim0 < 1

	// Ребёнок B стоит под своим заголовком по anim ЭТОГО кадра — тем же
	// значениям, по которым draw() рисовал заголовки.
	child_h := a.section_child_height()
	expected := a.header_height + child_h * anim0 + a.spacing + a.header_height - a.scroll_y
	assert abs_f32(p1.bounds.y - expected) < 0.001

	win.cleanup()
	app.cleanup()
}

fn test_arrange_survives_cycle_in_tree() {
	mut a := create_vbox_fill()
	mut b := create_vbox_fill()
	a.add(b, flex: 1)
	b.add(a, flex: 1)
	mut ctx := RenderContext{
		screen_width:  100
		screen_height: 100
	}
	mut w := Widget(a)
	arrange_widget(mut w, mut ctx)
	assert ctx.arrange_depth == 0
}
