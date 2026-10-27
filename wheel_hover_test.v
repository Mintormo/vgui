module vgui

// ═══════════════════════════════════════════════════════
// Hover после прокрутки колесом: содержимое уехало из-под неподвижного
// курсора - подсветка должна перейти на виджет, который теперь под ним,
// без движения мыши (синтетический mouse_move в dispatch_event_with_app).
//
// Ввод идёт настоящим путём (testkit): колесо SDL не несёт координат, окно
// адресует его по последней позиции мыши - это тоже проверяется.
//
// Запуск: SDL_VIDEODRIVER=dummy v test wheel_hover_test.v (из корня vgui)
// ═══════════════════════════════════════════════════════

fn test_wheel_scroll_updates_hover() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut col := create_vbox_fill()
	col.set_spacing(0)
	mut btns := []&Button{}
	for i in 0 .. 10 {
		b := button('b${i}')
		col.add(b)
		btns << b
	}
	mut sb := scroll_box(0)
	sb.add(col)
	t.add(sb)

	// Курсор над первой кнопкой
	t.move(50, 20)
	assert btns[0].hovered

	// Колесо вниз - содержимое сдвинулось, курсор на месте
	t.wheel(50, 20, -1)
	assert sb.scroll_y > 0
	assert !btns[0].hovered
	// Подсвечена ровно та кнопка, что теперь под курсором
	mut under := -1
	for i, b in btns {
		if b.bounds.contains(50, 20) {
			under = i
		}
	}
	assert under > 0
	assert btns[under].hovered
}
