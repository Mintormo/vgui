module main

// Пример 57. Виртуальный режим ListBox и TableView: миллионы строк без копии данных.
//
// В обычном режиме каждая строка копируется внутрь виджета (add_row_texts / add_row).
// В виртуальном (set_virtual) виджет знает только ЧИСЛО строк, а текст ячейки
// спрашивает у приложения колбэком - и только для строк, видимых на экране. Поэтому
// список на миллион строк открывается мгновенно и не занимает лишней памяти.
//
// Слева - «лог» на 1 000 000 строк (ListBox): сортировка по номеру щелчком по
// заголовку (порядок меняет само приложение в on_sort), иконки строк колбэком,
// множественный выбор, кнопка дописывает ещё 100 000 строк (set_virtual_count).
// Справа - таблица на 2 000 000 строк (TableView) с правкой ячеек двойным щелчком:
// виджет правку не хранит, она приходит в on_change, и приложение кладёт её в свой
// словарь правок.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/57_virtual_rows.v

import vgui

// LogData - данные «лога»: сколько строк и в каком порядке их показывать. Колбэки
// ListBox держат на неё ссылку и читают при каждой отрисовке.
@[heap]
struct LogData {
mut:
	count int = 1_000_000
	desc  bool // true - новые строки сверху (сортировка по убыванию номера)
}

// line_no - номер строки лога, который показывается в позиции row списка.
fn (d &LogData) line_no(row int) int {
	return if d.desc { d.count - 1 - row } else { row }
}

// TableData - правки ячеек таблицы: ключ 'строка:колонка' -> новый текст. Всё
// остальное таблица вычисляет на лету.
@[heap]
struct TableData {
mut:
	edits map[string]string
}

fn (d &TableData) cell(row int, col int) string {
	if text := d.edits['${row}:${col}'] {
		return text
	}
	return match col {
		0 { 'SKU-${row:07d}' }
		1 { 'Product ${row % 997}' }
		else { '${(row * 37) % 10000}.00' }
	}
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(
		title:  'Virtual ListBox and TableView - millions of rows'
		width:  1000
		height: 640
	)!

	mut status := vgui.label('Select a row')

	// ── Лог на миллион строк (ListBox) ──
	mut log := &LogData{}
	mut lb := vgui.list_box()
	lb.multi_select = true
	lb.add_column_full('№', 110, 50, true, .right)
	lb.add_column('Message', 360)
	// Колбэк текста: только для видимых строк каждого кадра - должен быть быстрым.
	lb.set_virtual(log.count, fn [log] (row int, col int) string {
		n := log.line_no(row)
		return if col == 0 {
			'${n}'
		} else {
			level := ['INFO', 'WARN', 'ERROR'][n % 3]
			'${level}: event number ${n}'
		}
	})
	// Иконки строк - тоже колбэком: по уровню сообщения.
	lb.set_virtual_icons(fn [log] (row int) vgui.ItemIcon {
		return match log.line_no(row) % 3 {
			0 { vgui.item_icon('info') }
			1 { vgui.item_icon('triangle-alert') }
			else { vgui.item_icon('circle-x').with_color(vgui.Color{230, 90, 90, 255}) }
		}
	})
	// Сортировка: строк в ListBox нет, порядок задаёт приложение. Порядок меняется
	// в LogData, а список просто перерисуется со следующим кадром.
	lb.on_sort = fn [mut log, mut win] (col int, dir vgui.LbSortDir) {
		log.desc = dir == .desc
		win.invalidate_all()
	}
	lb.on_select = fn [mut status, lb] (idx int, text string) {
		n := lb.get_selection().len
		status.text = 'Log: row ${idx}, number ${text}, rows selected: ${n}'
	}

	mut btn_more := vgui.button('Append 100,000 rows')
	btn_more.on_click = fn [mut log, mut lb, mut status] () {
		log.count += 100_000
		// данных стало больше - сообщаем новое число строк, прокрутка остаётся
		lb.set_virtual_count(log.count)
		status.text = '${log.count} rows in the log'
	}

	mut left := vgui.create_vbox_fill()
	left.set_spacing(8)
	left.add(vgui.label('Log: 1,000,000 rows (ListBox)'))
	left.add(lb, flex: 1)
	left.add(btn_more)

	// ── Таблица на 2 миллиона строк (TableView) ──
	mut data := &TableData{}
	mut tbl := vgui.table_view()
	tbl.show_row_numbers = true
	tbl.row_num_width = 80
	tbl.editable = true
	tbl.add_column('SKU', 120)
	tbl.add_column('Name', 140)
	tbl.add_column_aligned('Price', 90, .right)
	tbl.set_virtual(2_000_000, fn [data] (row int, col int) string {
		return data.cell(row, col)
	})
	// Правка ячейки не хранится в виджете: кладём её в свои данные.
	tbl.on_change = fn [mut data, mut status] (row int, col int, text string) {
		data.edits['${row}:${col}'] = text
		status.text = 'Table: cell ${row}:${col} changed -> ${text}'
	}
	tbl.on_select = fn [mut status] (row int, col int) {
		status.text = 'Table: row ${row}, column ${col}'
	}

	mut right := vgui.create_vbox_fill()
	right.set_spacing(8)
	right.add(vgui.label('Table: 2,000,000 rows (double-click to edit)'))
	right.add(tbl, flex: 1)

	mut row := vgui.create_hbox_fill()
	row.set_spacing(12)
	row.add(left, flex: 1)
	row.add(right, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(12)
	root.set_spacing(8)
	root.add(row, flex: 1)
	root.add(status)

	win.add_widget(root)
	app.add_window(win)
	app.run()
}
