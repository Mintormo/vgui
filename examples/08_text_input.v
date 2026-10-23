module main

// Пример 08. TextInput: однострочное поле - on_change/on_submit, пароль, ограничение длины, чтение через get_text().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/08_text_input.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'TextInput - demo')!

	mut status := vgui.label('Event: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Базовое однострочное поле: on_change при вводе, on_submit по Enter
	mut inp := vgui.text_input('Enter a name...')
	inp.on_change = fn [mut status] (text string) {
		status.text = 'Input: "${text}"'
	}
	inp.on_submit = fn [mut status] (text string) {
		status.text = 'Enter: "${text}"'
		status.color = vgui.Color{72, 199, 142, 255}
	}

	// Поле для пароля
	mut pass := vgui.text_input('Password')
	pass.pw_mode = true

	// Ограничение длины
	mut code := vgui.text_input('At most 6 characters')
	code.max_len = 6

	// Чтение значения программно через get_text()
	mut read := vgui.text_input('Anything...')
	read.set_text('Initial text')
	mut btn := vgui.button('get_text()')
	btn.on_click = fn [mut read, mut status] () {
		status.text = 'get_text() = "${read.get_text()}"'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Plain field:'))
	root.add(inp)
	root.add(vgui.label('Password (pw_mode):'))
	root.add(pass)
	root.add(vgui.label('Max length = 6:'))
	root.add(code)
	root.add(read)
	root.add(btn)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
