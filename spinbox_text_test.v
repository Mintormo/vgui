module vgui

// Spinbox с prefix/suffix (аудит 2026-10, 2.8): фильтр ^-?[0-9]*$ проверял весь текст
// поля вместе с префиксом и отклонял любой ввод, а atoi по всему тексту не
// разбирал "$5". Без окна и SDL: проверяются разбор и допуск текста.
//
// Запуск (из корня vgui): v test spinbox_text_test.v

fn test_number_part_strips_prefix_and_suffix() {
	mut s := spinbox()
	s.set_prefix('$')
	s.set_suffix(' шт.')
	assert s.number_part('$42 шт.') == '42'
	assert s.number_part('$-7') == '-7'
	assert s.number_part('15') == '15'
	assert s.text_input.get_text() == '$0 шт.'
}

fn test_accepts_partial_and_rejects_garbage() {
	mut s := spinbox()
	s.set_prefix('$')
	assert s.accepts_text('$')
	assert s.accepts_text('$-')
	assert s.accepts_text('$12')
	assert s.accepts_text('')
	assert !s.accepts_text('$1a')
	assert !s.accepts_text('$--1')
}

// Набор в поле с префиксом: вставка цифры принимается и меняет значение.
fn test_typing_with_prefix_updates_value() {
	mut s := spinbox()
	s.set_prefix('$')
	mut ti := s.text_input
	ti.cur = ti.buf.len // курсор после "$0"
	ti.insert('5')
	assert ti.get_text() == '$05'
	assert s.get_value() == 5
	ti.insert('x')
	assert ti.get_text() == '$05'
}
