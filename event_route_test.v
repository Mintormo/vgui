module vgui

// Доставка событий по маршруту (event_route.v, PROJECT.md «Доставка событий»):
// всплытие от виджета под курсором, захват жеста, mouse_leave, снятие фокуса
// кликом мимо, маршрут клавиш (фокус, внутреннее поле составного виджета),
// «рамка» контейнера (HitsSelf), отключённая ветка, фокус таблиц.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test event_route_test.v

struct RouteLog {
mut:
	clicks []string
}

// Клик достаётся виджету под курсором; контейнер-предок своё не делает,
// раз ребёнок поглотил. Отключённая ветка клик не получает.
fn test_click_goes_to_widget_under_cursor() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut log := &RouteLog{}
	mut root := create_vbox_fill()
	mut a := button('A')
	a.on_click = fn [mut log] () {
		log.clicks << 'A'
	}
	mut off_box := create_vbox_fill()
	off_box.box.enabled = false
	mut b := button('B')
	b.on_click = fn [mut log] () {
		log.clicks << 'B'
	}
	off_box.add(b)
	root.add(a)
	root.add(off_box)
	t.add(root)
	t.click_widget(a)
	t.click_widget(b)
	assert log.clicks == ['A'], 'отключённая ветка ввода не получает'
}

// Захват жеста: ползунок, нажатый мышью, получает движения и за своими
// пределами; отпускание где угодно жест заканчивает.
fn test_capture_keeps_drag_outside() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut s := slider_horizontal(0, 100, 50)
	mut other := button('other')
	root.add(s)
	root.add(other)
	t.add(root)
	cx, cy := t.center_of(s)
	t.move(cx, cy)
	t.press(cx, cy)
	// далеко правее и ниже ползунка, над другой кнопкой и за ней
	t.move(s.bounds.x + s.bounds.w + 100, other.bounds.y + 5)
	assert s.value == 100, 'ползунок ведёт жест и за своими пределами'
	assert !other.pressed
	t.release(s.bounds.x + s.bounds.w + 100, other.bounds.y + 5)
	assert t.win.route_capture.len == 0, 'отпускание заканчивает жест'
	t.move(s.bounds.x + 1, cy)
	assert s.value == 100, 'после отпускания движение ползунок не двигает'
}

// mouse_leave: подсветка снимается, когда курсор уходит с виджета, а
// контейнер под курсором (предок) наведение сохраняет.
fn test_mouse_leave_clears_hover() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut a := button('A')
	root.add(a)
	t.add(root)
	cx, cy := t.center_of(a)
	t.move(cx, cy)
	assert a.hovered
	t.move(cx, a.bounds.y + a.bounds.h + 40)
	assert !a.hovered
}

// Клик мимо поля ввода снимает с него фокус (окно, а не само поле); клик по
// другому полю переносит фокус; текст идёт только полю с фокусом.
fn test_focus_and_keys_follow_focus() {
	mut t := new_test_ui(width: 300, height: 240)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut a := text_input('a')
	mut b := text_input('b')
	root.add(a)
	root.add(b)
	t.add(root)
	t.click_widget(a)
	assert a.focused
	t.type_text('xy')
	assert a.get_text() == 'xy' && b.get_text() == ''
	t.click_widget(b)
	assert b.focused && !a.focused
	t.type_text('z')
	assert b.get_text() == 'z' && a.get_text() == 'xy'
	// пустое место ниже полей
	t.click(150, 220)
	t.frame()
	assert !b.focused
	t.type_text('q')
	assert b.get_text() == 'z', 'без фокуса текст никому'
}

// Фокус у внутреннего поля Spinbox (FocusOwner): клавиши доходят через
// владельца, которого маршрут находит в дереве.
fn test_keys_reach_inner_field_of_spinbox() {
	mut t := new_test_ui(width: 300, height: 160)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut sb := spinbox()
	sb.set_value(5)
	root.add(sb)
	t.add(root)
	t.click(sb.text_input.bounds.x + 4, sb.text_input.bounds.y + sb.text_input.bounds.h / 2)
	t.frame()
	assert t.win.ctx.focus.is_focused(voidptr(sb.text_input))
	t.key(sdl_k_up, 0)
	assert sb.value == 6, 'стрелка вверх дошла до Spinbox через внутреннее поле'
}

// «Рамка» контейнера: клик по полосе прокрутки ScrollBox - прокрутка, а не
// нажатие кнопки, растянутой под полосой.
fn test_scrollbar_click_is_not_childs() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut log := &RouteLog{}
	mut sb := scroll_box(1000)
	mut inner := create_vbox_fill()
	mut big := button('big')
	big.on_click = fn [mut log] () {
		log.clicks << 'big'
	}
	inner.add(big, flex: 1)
	sb.add(inner)
	t.add(sb)
	track, _ := sb.scrollbar_rects()
	assert track.w > 0
	before := sb.scroll_y
	t.click(track.x + track.w / 2, track.y + track.h - 4)
	assert log.clicks.len == 0, 'кнопка под полосой клик не получила'
	assert sb.scroll_y > before, 'клик по дорожке прокрутил'
}

// Таблица - в фокус-учёте окна: клик по второй снимает фокус с первой.
fn test_tables_share_window_focus() {
	mut t := new_test_ui(width: 400, height: 300)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut ta := table_view()
	ta.add_column('A', 100)
	ta.add_row(['1'])
	mut tb := table_view()
	tb.add_column('B', 100)
	tb.add_row(['2'])
	root.add(ta, flex: 1)
	root.add(tb, flex: 1)
	t.add(root)
	ra := ta.viewport_rect()
	t.click(ra.x + 10, ra.y + 5)
	t.frame()
	assert ta.focused
	rb := tb.viewport_rect()
	t.click(rb.x + 10, rb.y + 5)
	t.frame()
	assert tb.focused && !ta.focused
}
