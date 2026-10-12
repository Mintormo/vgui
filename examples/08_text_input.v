module main

// Пример 08. TextInput: однострочное поле - on_change/on_submit, пароль, ограничение длины, чтение через get_text().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/08_text_input.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'TextInput - demo')!

	mut status := vgui.label('Событие: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Базовое однострочное поле: on_change при вводе, on_submit по Enter
	mut inp := vgui.text_input('Введите имя...')
	inp.on_change = fn [mut status] (text string) {
		status.text = 'Ввод: "${text}"'
	}
	inp.on_submit = fn [mut status] (text string) {
		status.text = 'Enter: "${text}"'
		status.color = vgui.Color{72, 199, 142, 255}
	}

	// Поле для пароля
	mut pass := vgui.text_input('Пароль')
	pass.pw_mode = true

	// Ограничение длины
	mut code := vgui.text_input('Не более 6 символов')
	code.max_len = 6

	// Чтение значения программно через get_text()
	mut read := vgui.text_input('Что-нибудь...')
	read.set_text('Начальный текст')
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
	root.add(vgui.label('Обычное поле:'))
	root.add(inp)
	root.add(vgui.label('Пароль (pw_mode):'))
	root.add(pass)
	root.add(vgui.label('Макс. длина = 6:'))
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
