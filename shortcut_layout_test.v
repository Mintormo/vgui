module vgui

// Сочетания с символьной клавишей совпадают и по физической клавише (scancode
// раскладки US): в русской раскладке клавиша «[» даёт keycode «х», и без этого
// «[»/«]» (размер кисти и т.п.) не срабатывали.

fn key_ev(keycode int, scancode int) &GuiEvent {
	return &GuiEvent{
		typ:      .key_down
		keycode:  keycode
		scancode: scancode
	}
}

fn test_shortcut_matches_by_keycode() {
	assert menu_shortcut_matches('[', key_ev(int(`[`), 47))
	assert menu_shortcut_matches('F', key_ev(int(`f`), 9))
	assert menu_shortcut_matches('1', key_ev(int(`1`), 30))
}

fn test_shortcut_matches_by_scancode_on_other_layout() {
	// Русская раскладка: на клавише «[» — «х» (U+0445), на «]» — «ъ» (U+044A).
	assert menu_shortcut_matches('[', key_ev(0x445, 47))
	assert menu_shortcut_matches(']', key_ev(0x44a, 48))
	// Буква без перевода в латиницу (если SDL отдал кириллицу) — по scancode.
	assert menu_shortcut_matches('B', key_ev(0x438, 5))
}

fn test_shortcut_does_not_match_other_key() {
	assert !menu_shortcut_matches('[', key_ev(int(`p`), 19))
	assert !menu_shortcut_matches(']', key_ev(0x445, 47))
	// Модификатор по-прежнему обязателен: «[» без Ctrl не совпадает с «Ctrl+[».
	assert !menu_shortcut_matches('Ctrl+[', key_ev(0x445, 47))
}
