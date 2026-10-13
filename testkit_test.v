module vgui

import os

// Тесты самого testkit.v: синтетический ввод проходит настоящий путь событий
// (очередь SDL -> process_events -> виджет), снимок кадра и снапшоты.
//
// Запуск: v -enable-globals test testkit_test.v

@[heap]
struct TkCounter {
mut:
	n    int
	text string
}

fn test_click_and_dbl_click_reach_button() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut c := &TkCounter{}
	mut b := button('OK')
	b.on_click = fn [mut c] () {
		c.n++
	}
	mut col := create_vbox_fill()
	col.add(b, flex: 1)
	t.add(col)
	t.click_widget(b)
	assert c.n == 1
	// двойной клик - два нажатия (второе с clicks = 2), кнопка видит оба
	x, y := t.center_of(b)
	t.dbl_click(x, y)
	assert c.n == 3
	// клик мимо кнопки не засчитывается
	t.click(-50, -50)
	assert c.n == 3
}

fn test_keys_and_text_input() {
	mut t := new_test_ui(width: 240, height: 80)!
	defer {
		t.close()
	}
	mut ti := text_input('')
	mut col := create_vbox_fill()
	col.add(ti)
	t.add(col)
	t.click_widget(ti) // фокус кликом
	t.type_text('привет')
	assert ti.get_text() == 'привет'
	t.key(sdl_k_backspace, 0)
	assert ti.get_text() == 'приве'
	// Ctrl+A и ввод заменяют выделенное - модификатор доходит до виджета
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('x')
	assert ti.get_text() == 'x'
}

fn test_drag_slider_and_ui_scale() {
	// координаты логические: при ui_scale 1.5 sim_* сами переводят их в оконные
	mut t := new_test_ui(width: 300, height: 90, ui_scale: 1.5)!
	defer {
		t.close()
	}
	mut s := slider_horizontal(0, 100, 0)
	mut col := create_vbox_fill()
	col.set_padding(10)
	col.add(s)
	t.add(col)
	b := s.bounds
	t.drag(b.x + 2, b.y + b.h * 0.5, b.x + b.w + 20, b.y + b.h * 0.5)
	assert s.value > 95
}

fn test_wheel_scrolls_list() {
	mut t := new_test_ui(width: 200, height: 120)!
	defer {
		t.close()
	}
	mut lb := list_box()
	for i in 0 .. 50 {
		lb.add_item('строка ${i}')
	}
	mut col := create_vbox_fill()
	col.add(lb, flex: 1)
	t.add(col)
	x, y := t.center_of(lb)
	t.wheel(x, y, -3)
	assert lb.scroll_y > 0
}

fn test_capture_and_snapshot_roundtrip() {
	mut t := new_test_ui(width: 160, height: 90)!
	defer {
		t.close()
	}
	mut p := panel()
	p.bg = Color{200, 30, 30, 255}
	t.add(p)
	f := t.capture()
	assert f.w == 160 && f.h == 90
	assert f.count(Rect{0, 0, 160, 90}, Color{200, 30, 30, 255}, 3) > 160 * 90 / 2

	dir := os.join_path(os.temp_dir(), 'vgui_testkit_${os.getpid()}')
	defer {
		os.rmdir_all(dir) or {}
	}
	golden := os.join_path(dir, 'red.png')
	// эталона нет - записывается, проверка проходит
	t.match_snapshot(golden)!
	assert os.exists(golden)
	// тот же кадр совпадает с эталоном
	t.match_snapshot(golden)!
	// другой кадр - ошибка с числами и .actual.png рядом
	p.bg = Color{30, 30, 200, 255}
	t.redraw()
	t.match_snapshot(golden) or {
		assert err.msg().contains('отличаются')
		assert os.exists(os.join_path(dir, 'red.actual.png'))
		return
	}
	assert false, 'расхождение со снапшотом не замечено'
}
