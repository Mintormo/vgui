module main

// Пример 27. MenuButton: кнопка с выпадающим меню действий.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/27_menu_button.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'MenuButton - demo')!

	mut status := vgui.label('Действие: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Кнопка с выпадающим меню действий (MenuItem).
	mut mb := vgui.menu_button('Действия')

	mut a_new := vgui.menu_action('Создать')
	a_new.shortcut = 'Ctrl+N'
	a_new.on_click = fn [mut status] () {
		status.text = 'Действие: Создать'
	}

	mut a_open := vgui.menu_action('Открыть...')
	a_open.shortcut = 'Ctrl+O'
	a_open.on_click = fn [mut status] () {
		status.text = 'Действие: Открыть'
	}

	mut a_save := vgui.menu_action('Сохранить')
	a_save.on_click = fn [mut status] () {
		status.text = 'Действие: Сохранить'
	}

	mb.add(a_new)
	mb.add(a_open)
	mb.add_separator()
	mb.add(a_save)

	mut row := vgui.create_hbox_fill()
	row.add(mb)
	row.add(vgui.create_spacer(), flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
