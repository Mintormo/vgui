module main

// Пример 09. TextArea: многострочное поле ввода, колбэк on_change получает весь текст.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/09_text_area.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'TextArea - demo')!

	mut status := vgui.label('Characters: 0')
	status.color = vgui.Color{180, 180, 180, 255}

	// Многострочное поле ввода. Колбэк on_change получает весь текст.
	mut ta := vgui.text_area('Enter multi-line text...')
	ta.set_text('First line.\nSecond line.\n\nTextArea supports wrapping, selection, undo/redo (Ctrl+Z).')
	ta.on_change = fn [mut status] (text string) {
		status.text = 'Characters: ${text.len}'
	}

	// Кнопки: дописать текст и прочитать
	mut b_append := vgui.button('append_text()')
	b_append.on_click = fn [mut ta] () {
		ta.append_text('\n+ appended line')
	}

	mut b_clear := vgui.button('Clear')
	b_clear.style = .outline
	b_clear.on_click = fn [mut ta, mut status] () {
		ta.set_text('')
		status.text = 'Characters: 0'
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(b_append, flex: 1)
	row.add(b_clear, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(ta, flex: 1)
	root.add(row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
