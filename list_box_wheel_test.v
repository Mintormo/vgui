module vgui

import os

// ═══════════════════════════════════════════════════════
// Колесо над ListBox: работает без фокуса (по наведению), у
// горизонтального списка вниз - вправо (как у ScrollBox), на краю
// колесо поглощается и не уходит прокручиваемому родителю; wheel =
// false отдаёт колесо родителю.
//
// Запуск: v test vgui/list_box_wheel_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

// wheel_at - колесо в точке настоящим путём (testkit): событие колеса SDL не
// несёт координат, окно адресует его по последней позиции мыши - sim_wheel
// сначала двигает указатель туда.
fn wheel_at(mut win Window, mut app App, x f32, y f32, dy f32) {
	sim_wheel(mut app, win, x, y, 0, dy, 0)
}

fn test_list_box_h_wheel_without_focus_and_edges() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'list wheel', width: 300, height: 120)!
	app.add_window(win)

	mut lb := list_box_h(80)
	for i in 0 .. 10 {
		lb.add_item_widget(label('item ${i}'))
	}
	// Под списком - ещё содержимое: родительский ScrollBox есть куда крутить
	mut col := create_vbox_fill()
	col.add(lb, min: 60)
	for i in 0 .. 10 {
		col.add(button('b${i}'))
	}
	mut sb := scroll_box(0)
	sb.add(col)
	win.add_widget(sb)
	win.render()

	assert !lb.focused
	assert lb.max_scroll_x() > 0
	assert sb.max_scroll() > 0
	cx := lb.bounds.x + lb.bounds.w / 2
	cy := lb.bounds.y + lb.bounds.h / 2

	// Без фокуса: колесо вниз - список вправо, родитель на месте
	wheel_at(mut win, mut app, cx, cy, -1)
	assert lb.scroll_x > 0
	assert sb.scroll_y == 0

	// До правого края и дальше: родитель не прокручивается
	for _ in 0 .. 100 {
		wheel_at(mut win, mut app, cx, cy, -1)
	}
	assert lb.scroll_x == lb.max_scroll_x()
	assert sb.scroll_y == 0

	// Обратно до левого края и дальше - тоже
	for _ in 0 .. 100 {
		wheel_at(mut win, mut app, cx, cy, 1)
	}
	assert lb.scroll_x == 0
	assert sb.scroll_y == 0

	// wheel = false - колесо уходит родителю
	lb.wheel = false
	wheel_at(mut win, mut app, cx, cy, -1)
	assert lb.scroll_x == 0
	assert sb.scroll_y > 0

	win.cleanup()
	app.cleanup()
}
