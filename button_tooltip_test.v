module vgui

// Button.tooltip: подсказку держит и обслуживает сама кнопка (раньше поле
// хранилось, но ничего не рисовало). Проверяем показ после задержки, скрытие
// при уходе курсора, работу у неактивной кнопки и отсутствие подсказки без
// текста.

fn tip_ui() (&TestUi, &Button) {
	mut t := new_test_ui() or { panic(err) }
	mut b := button('OK')
	b.tooltip = 'Подсказка'
	mut row := create_hbox_fill()
	row.add(b)
	row.add(create_spacer(), flex: 1)
	t.add(row)
	return t, b
}

// hover наводит курсор на кнопку и «проматывает» задержку подсказки.
fn hover(mut t TestUi, mut b Button) {
	t.move(b.bounds.x + b.bounds.w / 2, b.bounds.y + b.bounds.h / 2)
	t.frame()
	assert b.tip != unsafe { nil }
	b.tip.delay_ms = 0 // без ожидания: SDL_GetTicks в тесте считает от старта SDL
	t.frame()
}

fn test_button_tooltip_shows_and_hides() {
	mut t, mut b := tip_ui()
	hover(mut t, mut b)
	assert b.tip.showing, 'подсказка должна появиться после задержки'
	assert b.tip.text == 'Подсказка'
	t.move(b.bounds.x + b.bounds.w + 100, b.bounds.y + b.bounds.h / 2)
	t.frame()
	assert !b.tip.showing, 'подсказка должна скрыться при уходе курсора'
}

fn test_button_tooltip_on_disabled_button() {
	mut t, mut b := tip_ui()
	b.enabled = false
	hover(mut t, mut b)
	assert b.tip.showing, 'у неактивной кнопки подсказка тоже показывается'
}

fn test_button_tooltip_text_update_and_clear() {
	mut t, mut b := tip_ui()
	hover(mut t, mut b)
	b.tooltip = 'Другая'
	t.frame()
	assert b.tip.text == 'Другая'
	b.tooltip = ''
	t.frame()
	assert !b.tip.showing, 'пустой tooltip гасит подсказку'
}

fn test_button_without_tooltip_has_no_tip() {
	mut t := new_test_ui() or { panic(err) }
	mut b := button('OK')
	t.add(b)
	t.move(b.bounds.x + 2, b.bounds.y + 2)
	t.frame()
	assert b.tip == unsafe { nil }
}
