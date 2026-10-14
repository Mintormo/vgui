module vgui

// Регрессия: measure() метки с нестандартным размером шрифта до первой отрисовки.
//
// get_font_immut (sdl3_fonts.v) раньше не открывал шрифт нового размера и отдавал
// regular базового размера, пока draw() не «прогреет» нужный. Первая раскладка
// идёт до первой отрисовки, поэтому метка size=20 мерилась неверно, со второго кадра
// раскладка сдвигалась, а экран перерисовывался только по dirty-областям - оставались
// куски кадра со старыми позициями (полоски поверх рамок полей ввода в примере 56).
//
// Запуск: SDL_VIDEODRIVER=dummy v -enable-globals test font_measure_test.v

fn test_label_measure_uses_requested_size_before_first_draw() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	// необычный размер, чтобы шрифт точно не был открыт кем-то раньше
	mut big := label('Заголовок')
	big.font_size = 23
	base := label('Заголовок')
	before := big.measure(t.win.ctx)
	assert before.h > base.measure(t.win.ctx).h, 'размер 23 мерился базовым шрифтом'
	t.add(big)
	after := big.measure(t.win.ctx)
	assert before.h == after.h
	assert before.w == after.w
}

// Первый кадр окна совпадает с полной перерисовкой: раскладка не «доезжает»
// на втором кадре, оставляя на экране старые куски.
fn test_first_frames_match_full_redraw() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut box := create_vbox_fill()
	mut title := label('Заголовок')
	title.font_size = 27
	box.add(title)
	box.add(text_input('поле'))
	t.add(box)
	t.settle(30)
	first := t.capture()
	t.redraw()
	full := t.capture()
	assert first.diff(full, 8).count == 0
}
