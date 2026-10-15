module vgui

// Виртуальный режим TableView и ListBox (set_virtual): данные - у приложения, виджет
// знает только число строк и спрашивает текст колбэком для видимых строк. Проверяется:
// число строк и текст через колбэк, колбэк зовётся только для видимых строк даже на
// миллионах, клик и клавиши на глубокой прокрутке попадают в нужную строку (f64 в
// расчёте позиций), правка ячейки уходит в on_change, set_virtual_count поправляет
// выбор, clear выключает режим, Shift-диапазон на сотни тысяч строк без квадратичных
// проверок, помощники отсортированных отметок выбора.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test virtual_rows_test.v

// VirtLog - счётчик вызовов колбэка и последние значения из on_select/on_change.
// Именованная структура (указатель на анонимную даёт невалидный C - CLAUDE.md).
struct VirtLog {
mut:
	calls    int
	max_row  int = -1
	sel_row  int = -1
	sel_text string
	changed  string
	sort_col int = -1
}

// virt_table - таблица на count строк, 2 колонки, текст ячейки - 'r<строка>c<колонка>';
// каждый вызов колбэка считается в log.
fn virt_table(count int, mut log VirtLog) &TableView {
	mut t := table_view()
	t.add_column('A', 100)
	t.add_column('B', 100)
	t.set_virtual(count, fn [mut log] (row int, col int) string {
		log.calls++
		if row > log.max_row {
			log.max_row = row
		}
		return 'r${row}c${col}'
	})
	return t
}

fn virt_list(count int, mut log VirtLog) &ListBox {
	mut lb := list_box()
	lb.add_column_sortable('Имя', 120)
	lb.add_column('Размер', 80)
	lb.set_virtual(count, fn [mut log] (row int, col int) string {
		log.calls++
		if row > log.max_row {
			log.max_row = row
		}
		return 'item${row}/${col}'
	})
	return lb
}

fn test_table_virtual_basics() {
	mut log := &VirtLog{}
	mut t := virt_table(1_000_000, mut log)
	assert t.is_virtual
	assert t.row_count() == 1_000_000
	assert t.get_cell(999_999, 1) == 'r999999c1'
	// за пределами - пусто и без вызова колбэка с плохим индексом
	assert t.get_cell(1_000_000, 0) == ''
	assert t.get_cell(5, 2) == ''
	assert log.max_row == 999_999
	// высота и позиции - умножением, без накопленной ошибки f32
	assert t.total_rows_height() == f32(24_000_000)
	assert t.row_y(700_001) == f32(16_800_024)
	idx, top := t.first_row_from(f32(16_800_030))
	assert idx == 700_001 && top == f32(16_800_024)
	// add_row в виртуальном режиме на число строк не влияет
	t.add_row(['x', 'y'])
	assert t.row_count() == 1_000_000
	// clear_rows возвращает обычную пустую таблицу
	t.clear_rows()
	assert !t.is_virtual && t.row_count() == 0
	// nil-колбэк - то же, что clear_virtual
	t.set_virtual(10, unsafe { nil })
	assert !t.is_virtual
}

fn test_table_virtual_draws_only_visible_rows() {
	mut log := &VirtLog{}
	mut ui := new_test_ui(width: 320, height: 240)!
	mut t := virt_table(10_000_000, mut log)
	t.scroll_y = 5_000_000 * 24
	ui.add(t)
	log.calls = 0
	ui.redraw()
	// видно ~9 строк по 2 колонки; с запасом - но никак не миллионы
	assert log.calls > 0 && log.calls < 60
	assert log.max_row >= 5_000_000 && log.max_row < 5_000_020
}

fn test_table_virtual_click_and_keys_far_down() {
	mut log := &VirtLog{}
	mut ui := new_test_ui(width: 320, height: 240)!
	mut t := virt_table(3_000_000, mut log)
	t.on_select = fn [mut log] (row int, col int) {
		log.sel_row = row
	}
	t.scroll_y = 2_345_678 * 24
	ui.add(t)
	vp := t.viewport_rect()
	// середина третьей видимой строки
	ui.click(vp.x + 10, vp.y + 24 * 2 + 12)
	assert t.sel_row == 2_345_680
	assert t.sel_col == 0
	assert log.sel_row == 2_345_680
	// PageDown - на страницу вниз, End - последняя строка, прокрутка за ней
	t.focused = true
	page := int(t.viewport_rect().h / 24)
	ui.key(sdl_k_pagedown, 0)
	assert t.sel_row == 2_345_680 + page
	ui.key(sdl_k_end, 0)
	assert t.sel_row == 2_999_999
	assert t.scroll_y == t.max_scroll_y()
}

fn test_table_virtual_edit_goes_to_on_change() {
	mut log := &VirtLog{}
	mut t := virt_table(100, mut log)
	t.editable = true
	t.on_change = fn [mut log] (row int, col int, text string) {
		log.changed = '${row}:${col}:${text}'
	}
	assert t.is_cell_editable(42, 1)
	t.begin_edit(42, 1)
	assert t.edit_buf.string() == 'r42c1'
	t.edit_buf = 'новое'.runes()
	t.commit_edit()
	assert log.changed == '42:1:новое'
	// хранить негде - ячейка показывает то, что вернёт колбэк
	assert t.get_cell(42, 1) == 'r42c1'
	// своей высоты у виртуальных строк нет - и тянуть за границу нельзя
	t.show_row_numbers = true
	assert t.hit_row_border(t.bounds.x + t.pad + 5, t.data_origin_y() + 24) == -1
}

fn test_table_virtual_count_change_fixes_selection() {
	mut log := &VirtLog{}
	mut t := virt_table(1000, mut log)
	t.set_selected(500, 1)
	t.set_virtual_count(2000)
	assert t.sel_row == 500
	t.set_virtual_count(10)
	assert t.sel_row == 9 && t.sel_col == 1
	t.set_virtual_count(0)
	assert t.sel_row == -1 && t.sel_col == -1
	// в обычном режиме set_virtual_count ничего не делает
	mut plain := table_view()
	plain.add_column('A', 50)
	plain.add_row(['1'])
	plain.set_virtual_count(100)
	assert plain.row_count() == 1
}

fn test_list_virtual_basics_and_text() {
	mut log := &VirtLog{}
	mut lb := virt_list(500_000, mut log)
	assert lb.row_count() == 500_000
	assert lb.get_row_cell_text(123_456, 1) == 'item123456/1'
	assert lb.get_row_cell_text(500_000, 0) == ''
	lb.set_selected(77)
	assert lb.get_selected_text() == 'item77/0'
	assert lb.get_selected_row_text(1) == 'item77/1'
	// иконки - колбэком
	assert !lb.row_icon(3).is_set()
	lb.set_virtual_icons(fn (row int) ItemIcon {
		return if row % 2 == 0 { item_icon('file') } else { ItemIcon{} }
	})
	assert lb.row_icon(4).is_set() && !lb.row_icon(5).is_set()
	// clear - снова обычный пустой список
	lb.clear()
	assert !lb.is_virtual && lb.row_count() == 0
	assert !lb.row_icon(4).is_set()
}

fn test_list_virtual_draw_click_and_select() {
	mut log := &VirtLog{}
	mut ui := new_test_ui(width: 320, height: 240)!
	mut lb := virt_list(5_000_000, mut log)
	lb.on_select = fn [mut log] (idx int, text string) {
		log.sel_row = idx
		log.sel_text = text
	}
	lb.scroll_y = 4_000_000 * 24
	ui.add(lb)
	log.calls = 0
	ui.redraw()
	assert log.calls > 0 && log.calls < 60
	vp := lb.viewport_rect()
	ui.click(vp.x + 20, vp.y + 24 + 12)
	assert lb.selected == 4_000_001
	assert log.sel_row == 4_000_001
	assert log.sel_text == 'item4000001/0'
	// стрелка вниз и End
	ui.key(sdl_k_down, 0)
	assert lb.selected == 4_000_002
	ui.key(sdl_k_end, 0)
	assert lb.selected == 4_999_999
}

fn test_list_virtual_sort_click_only_signals() {
	mut log := &VirtLog{}
	mut ui := new_test_ui(width: 320, height: 240)!
	mut lb := virt_list(1000, mut log)
	lb.on_sort = fn [mut log] (col int, dir LbSortDir) {
		log.sort_col = col
	}
	ui.add(lb)
	// щелчок по середине заголовка сортируемой колонки (не только по стрелке)
	ui.click(lb.bounds.x + lb.pad + 40, lb.bounds.y + lb.pad + lb.header_height / 2)
	assert log.sort_col == 0
	assert lb.columns[0].sort_dir == .asc
	// строк в виджете нет - порядок не трогается, текст - по-прежнему от колбэка
	assert lb.get_row_cell_text(0, 0) == 'item0/0'
	// заголовок несортируемой колонки сортировку не включает
	log.sort_col = -1
	ui.click(lb.bounds.x + lb.pad + 120 + 30, lb.bounds.y + lb.pad + lb.header_height / 2)
	assert log.sort_col == -1
}

fn test_list_virtual_big_shift_range() {
	mut log := &VirtLog{}
	mut lb := virt_list(1_000_000, mut log)
	lb.multi_select = true
	lb.set_selected(10)
	// Shift+щелчок на 300 000 строк ниже: диапазон строится за один проход
	shift := GuiEvent{
		mod_keys: u16(sdl_kmod_shift)
	}
	lb.click_select(300_010, &shift)
	sel := lb.get_selection()
	assert sel.len == 300_001
	assert sel[0] == 10 && sel.last() == 300_010
	assert lb.is_row_selected(150_000) && !lb.is_row_selected(300_011)
	// Ctrl+щелчок снимает строку из середины, отметки остаются отсортированными
	ctrl := GuiEvent{
		mod_keys: u16(sdl_kmod_ctrl)
	}
	lb.click_select(150_000, &ctrl)
	assert !lb.is_row_selected(150_000)
	assert lb.get_selection().len == 300_000
	// данных стало меньше - отметки за концом снимаются
	lb.set_virtual_count(100)
	assert lb.get_selection().len == 90
	assert lb.selected == 99
}

fn test_marks_helpers() {
	found, pos := lb_marks_find([1, 3, 5], 4)
	assert !found && pos == 2
	f2, p2 := lb_marks_find([1, 3, 5], 5)
	assert f2 && p2 == 2
	assert lb_range(5, 2) == [2, 3, 4, 5]
	assert lb_merge_marks([1, 4, 9], [2, 4, 10]) == [1, 2, 4, 9, 10]
	assert lb_merge_marks([]int{}, [3]) == [3]
	// обычный режим: set_selection держит отметки сортированными, текущая - последняя
	// из первых вхождений
	mut lb := list_box()
	lb.multi_select = true
	lb.add_items(['a', 'b', 'c', 'd', 'e'])
	lb.set_selection([4, 1, 3, 1])
	assert lb.sel_marks == [1, 3, 4]
	assert lb.selected == 3
}
