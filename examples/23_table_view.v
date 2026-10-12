module main

// Пример 23. TableView: таблица с колонками, строками и инлайн-редактированием ячеек.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/23_table_view.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'TableView - demo')!

	mut status := vgui.label('Ячейка: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Таблица: колонки задаются add_column(title, width), строки add_row([...]).
	// t.editable включает редактирование ячеек: двойной клик, Enter или F2
	// на выделенной ячейке открывают инлайн-редактор (Esc - отмена).
	mut t := vgui.table_view()
	t.editable = true
	t.add_column('Имя', 160)
	t.add_column('Возраст', 90)
	t.add_column('Город', 160)

	t.add_row(['Иван', '46', 'Москва'])
	t.add_row(['Анна', '32', 'Казань'])
	t.add_row(['Пётр', '28', 'Самара'])
	t.add_row(['Мария', '41', 'Омск'])

	// Колонку "Имя" запрещаем менять поячеечно: set_cell_editable(row, col, false).
	for r in 0 .. t.row_count() {
		t.set_cell_editable(r, 0, false)
	}

	t.on_select = fn [mut t, mut status] (row int, col int) {
		ro := if t.get_cell_editable(row, col) { '' } else { ' (только чтение)' }
		status.text = 'Ячейка [${row}, ${col}] = "${t.get_cell(row, col)}"${ro}'
		status.color = vgui.Color{66, 165, 245, 255}
	}
	t.on_change = fn [mut status] (row int, col int, text string) {
		status.text = 'Изменено [${row}, ${col}] -> "${text}"'
		status.color = vgui.Color{72, 199, 142, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(t, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
