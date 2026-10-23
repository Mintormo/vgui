module main

// Пример 18. CodeEditor: редактор кода с номерами строк, выделением, undo/redo и подсветкой синтаксиса V.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/18_code_editor.v

import vgui

const sample_code = 'module main

fn main() {
	// Code editor with V syntax highlighting
	greeting := "Hello, vgui!"
	for i in 0 .. 3 {
		println("\${i}: \${greeting}")
	}
}
'

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'CodeEditor - demo')!

	mut status := vgui.label('Lines: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Редактор кода: номера строк, выделение, undo/redo, подсветка.
	mut ed := vgui.code_editor()
	ed.set_highlighter(vgui.v_highlighter())
	ed.set_text(sample_code)
	ed.show_line_numbers = true
	ed.on_change = fn [mut ed, mut status] () {
		status.text = 'Lines: ${ed.get_line_count()}'
	}

	mut b_get := vgui.button('get_line_count()')
	b_get.on_click = fn [mut ed, mut status] () {
		status.text = 'Lines: ${ed.get_line_count()}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(ed, flex: 1)
	root.add(b_get)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
