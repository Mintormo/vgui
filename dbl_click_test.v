module vgui

// Двойной клик (аудит 2026-10, раздел 6.3). Раньше второй быстрый клик приходил
// как mouse_dbl_click ВМЕСТО mouse_down, и виджет, слушающий только нажатия
// (кнопка), его терял. Теперь окно рассылает обычный mouse_down с clicks = 2, а
// следом mouse_dbl_click. Виджеты, которые реагируют на оба, не должны
// срабатывать дважды за один клик.
//
// Клики идут настоящим путём (testkit: очередь SDL -> parse_sdl_event ->
// process_events -> окно), так что проверяется и разбор clicks из события SDL,
// и рассылка mouse_dbl_click окном, а не только реакция виджета.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test dbl_click_test.v

struct DblLog {
mut:
	n int
}

// Быстрый двойной щелчок по кнопке - два on_click.
fn test_button_gets_both_clicks() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut b := button('OK')
	mut log := &DblLog{}
	b.on_click = fn [mut log] () {
		log.n++
	}
	t.add(b)
	cx, cy := t.center_of(b)
	t.dbl_click(cx, cy)
	assert log.n == 2
}

// Флажок PropertyGrid в колонке значения: каждый щелчок переключает ровно раз,
// двойной клик - два переключения (возврат к исходному), а не три.
fn test_property_grid_bool_toggles_once_per_click() {
	mut t := new_test_ui(width: 400, height: 300)!
	defer {
		t.close()
	}
	mut pg := property_grid()
	flag := pg.add_bool('flag', false)
	t.add(pg)
	r := pg.row_rect(0)
	x := pg.split_x() + 10
	y := r.y + r.h / 2
	t.click(x, y)
	assert flag.bool_val
	// Двойной клик: первый щелчок пары переключает обратно, второй - снова.
	t.dbl_click(x, y)
	assert flag.bool_val
}

// ListBox: нажатие выбирает строку, двойной клик зовёт on_dbl_click один раз.
fn test_list_box_dbl_click() {
	mut t := new_test_ui(width: 200, height: 200)!
	defer {
		t.close()
	}
	mut lb := list_box()
	lb.add_items(['a', 'b', 'c'])
	mut log := &DblLog{}
	lb.on_dbl_click = fn [mut log] (i int, text string) {
		log.n += 10 + i
	}
	t.add(lb)
	x := lb.bounds.x + 20
	y := lb.bounds.y + lb.pad + lb.item_height * 1.5
	t.dbl_click(x, y)
	assert lb.selected == 1
	assert log.n == 11
}
