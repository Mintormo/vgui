module vgui

// ListBox: сортировка строк по колонке (аудит 2026-10, раздел 6.2). Раньше щелчок по
// кнопке сортировки только менял стрелку и звал on_sort, строки оставались на месте.
// Теперь при auto_sort ListBox переставляет их сам. Без окна и SDL.
//
// Запуск (из корня vgui): v -enable-globals test list_box_sort_test.v

struct SortLog {
mut:
	calls []string
}

fn sort_lb() &ListBox {
	mut lb := list_box()
	lb.add_column_sortable('name', 100)
	lb.add_column_sortable('size', 60)
	lb.add_row_texts(['beta', '10'])
	lb.add_row_texts(['Alpha', '2'])
	lb.add_row_texts(['gamma', '2'])
	return lb
}

fn first_col(lb &ListBox) []string {
	return lb.rows.map(it.cells[0].text)
}

fn test_toggle_cycles_asc_desc_original() {
	mut lb := sort_lb()
	mut log := &SortLog{}
	lb.on_sort = fn [mut log] (col int, dir LbSortDir) {
		log.calls << '${col}:${dir}'
	}
	lb.toggle_sort(0)
	assert first_col(lb) == ['Alpha', 'beta', 'gamma'] // без учёта регистра
	assert lb.items == ['Alpha', 'beta', 'gamma']
	lb.toggle_sort(0)
	assert first_col(lb) == ['gamma', 'beta', 'Alpha']
	lb.toggle_sort(0)
	assert first_col(lb) == ['beta', 'Alpha', 'gamma'] // исходный порядок
	assert log.calls == ['0:asc', '0:desc', '0:none_']
}

// Числа сравниваются как числа, равные строки сохраняют порядок добавления
// (и при убывании тоже).
fn test_numeric_and_stable() {
	mut lb := sort_lb()
	lb.set_column_sort(1, .asc)
	assert first_col(lb) == ['Alpha', 'gamma', 'beta']
	lb.set_column_sort(1, .desc)
	assert first_col(lb) == ['beta', 'Alpha', 'gamma']
}

// Выбор, отметки и якорь следуют за своими строками.
fn test_selection_follows_rows() {
	mut lb := sort_lb()
	lb.multi_select = true
	lb.set_selection([0, 2]) // beta, gamma; текущая - gamma
	lb.set_column_sort(0, .asc)
	assert lb.get_selection() == [1, 2]
	assert lb.items[lb.selected] == 'gamma'
	lb.set_selected(0) // Alpha
	lb.set_column_sort(0, .desc)
	assert lb.items[lb.selected] == 'Alpha'
}

// Новая строка в отсортированном списке встаёт на своё место, выбор не сбивается.
fn test_add_into_sorted_list() {
	mut lb := sort_lb()
	lb.set_column_sort(0, .asc)
	lb.set_selected(2) // gamma
	lb.add_row_texts(['Bravo', '1'])
	assert first_col(lb) == ['Alpha', 'beta', 'Bravo', 'gamma']
	assert lb.items[lb.selected] == 'gamma'
}

// auto_sort = false - прежнее поведение: только индикатор и сигнал.
fn test_auto_sort_off_keeps_rows() {
	mut lb := sort_lb()
	lb.auto_sort = false
	lb.toggle_sort(0)
	assert lb.columns[0].sort_dir == .asc
	assert first_col(lb) == ['beta', 'Alpha', 'gamma']
	lb.add_row_texts(['aaa', '0'])
	assert first_col(lb).last() == 'aaa'
}

// Своё сравнение: по длине текста.
fn test_custom_compare() {
	mut lb := sort_lb()
	lb.sort_cmp = fn (col int, a string, b string) int {
		return a.len - b.len
	}
	lb.set_column_sort(0, .asc)
	assert first_col(lb) == ['beta', 'Alpha', 'gamma']
}

fn test_text_cmp() {
	assert lb_text_cmp('2', '10') < 0
	assert lb_text_cmp('a', 'B') < 0
	assert lb_text_cmp('x2', 'x10') > 0 // не числа - как строки
	assert lb_text_cmp('', '0') < 0
	assert lb_text_cmp('A', 'a') < 0 // равны без регистра - решает регистр
}
