module vgui

// TextArea и сочетания Ctrl+буква (аудит 2026-10, 2.12). Без окна и SDL.
//
// Запуск (из корня vgui): v test text_area_test.v

// max_len ограничивает ввод: лишнее обрезается, без места - правки нет.
fn test_max_len_limits_input() {
	mut ta := text_area('')
	ta.max_len = 5
	ta.insert_text('abc')
	ta.insert_text('\ndefg') // влезает только "\nd"
	assert ta.get_text() == 'abc\nd'
	ta.insert_text('x')
	assert ta.get_text() == 'abc\nd'
	assert ta.text_len() == 5
}

// append_text очищает историю: старый снимок не откатит дописанный лог.
fn test_append_text_clears_history() {
	mut ta := text_area('')
	ta.insert_text('a')
	ta.append_text('\nlog')
	assert !ta.undo()
	assert ta.get_text() == 'a\nlog'
}

// Enter - вставка перевода строки по общему пути (с undo).
fn test_enter_splits_line_with_undo() {
	mut ta := text_area('')
	ta.focused = true
	ta.set_text('ab')
	ta.cur_c = 1
	ta.insert_text('\n')
	assert ta.lines == ['a', 'b']
	assert ta.undo()
	assert ta.get_text() == 'ab'
}

// Колесо поглощается, только если прокрутка сдвинулась.
fn test_wheel_passes_through_at_edge() {
	mut ta := text_area('')
	ta.hovered = true
	ta.max_scroll_y = 100
	up := GuiEvent{
		typ:     .mouse_wheel
		wheel_y: 1
	}
	app := &App{}
	assert !ta.handle_event(&up, app) // уже у верхнего края
	down := GuiEvent{
		typ:     .mouse_wheel
		wheel_y: -1
	}
	assert ta.handle_event(&down, app)
	assert ta.scroll_y == 30
}

// Латинская буква сравнивается по keycode (AZERTY: Z на месте QWERTY-W), нелатинская
// раскладка - по scancode.
fn test_ctrl_letter_layouts() {
	azerty_z := GuiEvent{
		keycode:  int(`z`)
		scancode: 26 // физическая W в QWERTY
	}
	assert ctrl_letter(&azerty_z, `z`, ti_sc_letter_z)
	azerty_w_on_z := GuiEvent{
		keycode:  int(`w`)
		scancode: ti_sc_letter_z
	}
	assert !ctrl_letter(&azerty_w_on_z, `z`, ti_sc_letter_z)
	russian_ya := GuiEvent{
		keycode:  0x44f // 'я'
		scancode: ti_sc_letter_z
	}
	assert ctrl_letter(&russian_ya, `z`, ti_sc_letter_z)
}
