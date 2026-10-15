module vgui

// TableView (аудит 2026-10, 2.9): прокрутка редактора ячейки за курсором, on_change
// только при изменении, полосы прокрутки с учётом соседней полосы. Без окна и SDL.
//
// Запуск (из корня vgui): v test table_view_test.v

fn test_edit_scroll_follows_cursor() {
	// текст помещается - прокрутки нет
	assert edit_scroll_for_cursor(50, 80, 30, 100) == 0
	// курсор у правого края длинного текста - сдвиг с запасом
	assert edit_scroll_for_cursor(300, 400, 0, 100) == 220
	// курсор левее видимой части - сдвиг назад, но не меньше 0
	assert edit_scroll_for_cursor(10, 400, 220, 100) == 0
	// курсор внутри видимой части - прокрутка не меняется
	assert edit_scroll_for_cursor(250, 400, 200, 100) == 200
}

struct TblChangeLog {
mut:
	count int
}

fn test_commit_without_change_is_silent() {
	mut t := table_view()
	t.add_column('A', 100)
	t.add_row(['x'])
	t.editable = true
	t.set_cell_editable(0, 0, true)
	mut log := &TblChangeLog{}
	t.on_change = fn [mut log] (row int, col int, text string) {
		log.count++
	}
	t.begin_edit(0, 0)
	assert t.editing
	t.commit_edit()
	assert log.count == 0
	t.begin_edit(0, 0)
	t.edit_buf = 'y'.runes()
	t.commit_edit()
	assert log.count == 1
	assert t.get_cell(0, 0) == 'y'
}

// Содержимое по высоте влезает только без горизонтальной полосы, а горизонтальная
// нужна: тогда нужна и вертикальная (раньше её не было).
fn test_scrollbars_account_for_each_other() {
	mut t := table_view()
	t.pad = 0
	t.header_height = 0
	t.row_height = 20
	t.bounds = Rect{0, 0, 100, 105}
	t.add_column('A', 150) // шире области - нужна горизонтальная
	for _ in 0 .. 5 {
		t.add_row(['r']) // 5 * 20 = 100 <= 105, но > 105 - 12
	}
	assert t.has_hsb()
	assert t.has_vsb()
}
