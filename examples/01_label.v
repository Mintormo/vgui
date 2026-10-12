module main

// Пример 01. Label: текстовая метка - обычный, цветной, курсивный, моноширинный текст, выравнивание и перенос строк (label_wrap).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/01_label.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Label - demo')!

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)

	mut title := vgui.label('Label - текст-метка')
	title.font_style = .bold
	title.font_size = 18
	root.add(title)

	root.add(vgui.hseparator())

	mut l_plain := vgui.label('Обычный текст')
	root.add(l_plain)

	mut l_color := vgui.label('Цветной текст (.color)')
	l_color.color = vgui.Color{72, 199, 142, 255}
	root.add(l_color)

	mut l_italic := vgui.label('Курсив (.font_style = .italic)')
	l_italic.font_style = .italic
	root.add(l_italic)

	mut l_mono := vgui.label('Моноширинный: fn main() {}')
	l_mono.font_style = .mono
	l_mono.color = vgui.Color{102, 217, 239, 255}
	root.add(l_mono)

	mut l_right := vgui.label('Выравнивание вправо (.align)')
	l_right.align = .right
	root.add(l_right)

	mut l_wrap := vgui.label_wrap('Это Label с переносом строк. При длинном тексте слова автоматически переносятся на новую строку по ширине виджета.')
	root.add(l_wrap, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
