module vgui

import os

// ═══════════════════════════════════════════════════════
// CurveEditor: монотонный сплайн (Фрич–Карлсон) и правка мышью.
//
// Запуск: v test vgui/curve_editor_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

fn test_curve_math() {
	id := [CurvePoint{0, 0}, CurvePoint{1, 1}]
	assert curve_is_identity(id)
	l := curve_lut(id, 5)
	assert l == [f32(0), 0.25, 0.5, 0.75, 1]

	// Через опорные точки, монотонно, без выбросов за 0..1
	pts := [CurvePoint{0, 0}, CurvePoint{0.25, 0.4}, CurvePoint{0.5, 0.6}, CurvePoint{1, 1}]
	assert abs_f32(curve_eval(pts, 0.25) - 0.4) < 1e-5
	assert abs_f32(curve_eval(pts, 0.5) - 0.6) < 1e-5
	lut := curve_lut(pts, 256)
	for i in 1 .. 256 {
		assert lut[i] >= lut[i - 1]
	}
	// Плато: соседние точки с равным y - между ними ровно, без горба
	flat := [CurvePoint{0, 0}, CurvePoint{0.3, 0.5}, CurvePoint{0.7, 0.5}, CurvePoint{1, 1}]
	for x in [f32(0.35), 0.5, 0.65] {
		assert abs_f32(curve_eval(flat, x) - 0.5) < 1e-5
	}
	// normalize: сортировка, кламп, крайние точки
	n := normalize_curve_points([CurvePoint{0.6, 1.4}, CurvePoint{0.2, 0.1}])
	assert n.len == 4
	assert n[0].x == 0 && n[3].x == 1
	assert n[1].x == f32(0.2) && n[2].y == 1
	assert normalize_curve_points([]).len == 2
}

struct CeCounters {
mut:
	changes  int
	releases int
}

fn ce_mouse(mut win Window, app &App, typ EventType, btn MouseButton, x f32, y f32) {
	ev := GuiEvent{
		typ:       typ
		mouse_btn: btn
		mouse_x:   x
		mouse_y:   y
	}
	win.dispatch_event_with_app(&ev, app)
}

fn test_curve_editor_mouse() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'curve', width: 220, height: 220)!
	app.add_window(win)
	mut ce := curve_editor()
	mut cnt := &CeCounters{}
	ce.on_change = fn [mut cnt] () {
		cnt.changes++
	}
	ce.on_release = fn [mut cnt] () {
		cnt.releases++
	}
	win.add_widget(ce)
	win.render()
	r := ce.plot_rect()
	sx := fn [r] (x f32) f32 {
		return r.x + x * r.w
	}
	sy := fn [r] (y f32) f32 {
		return r.y + (1 - y) * r.h
	}

	// Клик на пустом месте - новая точка, перетаскивание, отпускание
	ce_mouse(mut win, app, .mouse_down, .left, sx(0.5), sy(0.2))
	assert ce.points.len == 3
	assert ce.drag_pt == 1
	ce_mouse(mut win, app, .mouse_move, .none_, sx(0.5), sy(0.8))
	assert abs_f32(ce.points[1].y - 0.8) < 0.01
	assert cnt.releases == 0
	ce_mouse(mut win, app, .mouse_up, .left, sx(0.5), sy(0.8))
	assert cnt.releases == 1
	assert cnt.changes >= 2
	assert !ce.is_identity()

	// Крайняя точка двигается только по вертикали
	ce_mouse(mut win, app, .mouse_down, .left, sx(0), sy(0))
	assert ce.drag_pt == 0
	ce_mouse(mut win, app, .mouse_move, .none_, sx(0.3), sy(0.1))
	assert ce.points[0].x == 0
	assert abs_f32(ce.points[0].y - 0.1) < 0.01
	ce_mouse(mut win, app, .mouse_up, .left, sx(0.3), sy(0.1))

	// Внутренняя точка не перескакивает соседей
	ce_mouse(mut win, app, .mouse_down, .left, sx(0.5), sy(0.8))
	ce_mouse(mut win, app, .mouse_move, .none_, sx(1.2), sy(0.8))
	assert ce.points[1].x < ce.points[2].x
	ce_mouse(mut win, app, .mouse_up, .left, sx(0.9), sy(0.8))

	// Правый клик по внутренней точке - удаление; по крайней - нет
	p := ce.points[1]
	ce_mouse(mut win, app, .mouse_down, .right, sx(p.x), sy(p.y))
	assert ce.points.len == 2
	ce_mouse(mut win, app, .mouse_down, .right, sx(1), sy(1))
	assert ce.points.len == 2

	// Двойной клик - сброс в диагональ
	ce_mouse(mut win, app, .mouse_dbl_click, .left, sx(0.4), sy(0.9))
	assert ce.is_identity()

	win.cleanup()
	app.cleanup()
}
