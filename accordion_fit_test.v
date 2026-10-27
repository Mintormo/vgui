module vgui

import os

// ═══════════════════════════════════════════════════════
// Accordion.fit_content: высота секции по содержимому, а не «всё свободное
// место». В .multiple без него каждая открытая секция занимала бы всю
// высоту аккордеона. В режиме fit_content аккордеон не прокручивается сам,
// а отдаёт полную высоту внешнему ScrollBox.
//
// Запуск: v test vgui/accordion_fit_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

struct FitProbe {
pub mut:
	bounds Rect
	clicks int
	h      f32 // естественная высота (measure)
}

fn (p &FitProbe) measure(ctx &RenderContext) SizeHint {
	return SizeHint{
		w:        10
		h:        p.h
		min_h:    p.h
		max_h:    p.h
		v_policy: .fixed
	}
}

fn (p &FitProbe) bounds_of() Rect {
	return p.bounds
}

fn (mut p FitProbe) set_bounds(r Rect) {
	p.bounds = r
}

fn (mut p FitProbe) draw(mut ctx RenderContext) {}

fn (mut p FitProbe) handle_event(event &GuiEvent, app &App) bool {
	if event.typ == .mouse_down && p.bounds.contains(event.mouse_x, event.mouse_y) {
		p.clicks++
		return true
	}
	return false
}

// fit_section - VBox из рядов естественной высоты row_h (measure)
fn fit_section(rows int, row_h f32) (&VBox, []&FitProbe) {
	mut v := create_vbox_fill()
	v.set_spacing(0)
	mut probes := []&FitProbe{}
	for _ in 0 .. rows {
		p := &FitProbe{
			h: row_h
		}
		v.add(p)
		probes << p
	}
	return v, probes
}

fn settle(mut win Window) {
	for _ in 0 .. 60 {
		win.ctx.invalidate_all()
		win.render()
	}
}

fn test_fit_content_sections_take_own_height() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'fit', width: 300, height: 600)!
	win.ctx.anim_fixed_dt = anim_nominal_dt // шаг кадра, а не часы
	app.add_window(win)

	mut a := accordion_multi()
	a.fit_content = true
	a.spacing = 0
	s0, p0 := fit_section(2, 30) // 60
	s1, p1 := fit_section(3, 20) // 60
	a.add_section('A', s0)
	a.add_section('B', s1)
	a.set_expanded(0, true)
	a.set_expanded(1, true)
	win.add_widget(a)
	settle(mut win)

	hh := a.header_height
	// Секция B начинается сразу под содержимым A, а не через всю высоту окна
	assert abs_f32(p1[0].bounds.y - (hh + 60 + hh)) < 0.001
	assert abs_f32(p0[1].bounds.y - (hh + 30)) < 0.001
	assert abs_f32(a.total_content_height() - (2 * hh + 120)) < 0.001
	// measure отдаёт полную высоту контента
	assert abs_f32(a.measure(win.ctx).h - a.total_content_height()) < 0.001

	// Свёрнутая A: B поднимается к заголовку A
	a.set_expanded(0, false)
	settle(mut win)
	assert abs_f32(p1[0].bounds.y - 2 * hh) < 0.001

	win.cleanup()
	app.cleanup()
}

fn test_fit_content_in_scroll_box_scrolls_and_clicks_below_fold() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'fit scroll', width: 300, height: 200)!
	win.ctx.anim_fixed_dt = anim_nominal_dt // шаг кадра, а не часы
	app.add_window(win)

	mut a := accordion_multi()
	a.fit_content = true
	a.spacing = 0
	s0, _ := fit_section(4, 40) // 160
	s1, p1 := fit_section(4, 40) // 160
	a.add_section('A', s0)
	a.add_section('B', s1)
	a.set_expanded(0, true)
	a.set_expanded(1, true)
	mut sb := scroll_box(0)
	sb.add(a)
	win.add_widget(sb)
	settle(mut win)

	// ScrollBox видит полную высоту аккордеона - есть что прокручивать
	total := a.total_content_height()
	assert abs_f32(sb.eff_content_h - total) < 0.001
	assert total > 200
	// Сам аккордеон не прокручивается
	assert a.max_scroll() == 0

	// Последний ряд B - ниже видимой области; клик по нему после прокрутки
	// доходит до ребёнка (область аккордеона - на всю высоту контента)
	sb.scroll_y = sb.max_scroll()
	settle(mut win)
	last := p1[3]
	assert last.bounds.y + last.bounds.h <= 200 + 0.5
	// Нажатие настоящим путём (testkit): окно -> ScrollBox -> Accordion -> ребёнок.
	sim_press(mut app, win, last.bounds.x + 5, last.bounds.y + 5, .left, 1, 0)
	assert last.clicks == 1

	win.cleanup()
	app.cleanup()
}

// Без fit_content - прежнее поведение: секция занимает всё свободное место
fn test_default_mode_unchanged() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'fit default', width: 300, height: 400)!
	win.ctx.anim_fixed_dt = anim_nominal_dt // шаг кадра, а не часы
	app.add_window(win)
	mut a := accordion_multi()
	s0, _ := fit_section(2, 30)
	a.add_section('A', s0)
	a.set_expanded(0, true)
	win.add_widget(a)
	settle(mut win)
	assert a.child_height_at(0) == a.section_child_height()
	assert a.child_height_at(0) > 60
	win.cleanup()
	app.cleanup()
}
