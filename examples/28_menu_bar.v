module main

// Пример 28. MenuBar: полоса меню вверху окна.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/28_menu_bar.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'MenuBar - demo')!

	mut status := vgui.label('Menu item: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Полоса меню вверху окна. add_menu(title, []MenuItem).
	mut bar := vgui.menu_bar()

	mut m_new := vgui.menu_action('New')
	m_new.on_click = fn [mut status] () {
		status.text = 'File -> New'
	}
	mut m_open := vgui.menu_action('Open...')
	m_open.on_click = fn [mut status] () {
		status.text = 'File -> Open'
	}
	mut m_exit := vgui.menu_action('Quit')
	m_exit.on_click = fn [mut app] () {
		app.quit()
	}
	bar.add_menu('File', [m_new, m_open, vgui.menu_separator(), m_exit])

	mut m_undo := vgui.menu_action('Undo')
	m_undo.on_click = fn [mut status] () {
		status.text = 'Edit -> Undo'
	}
	mut m_redo := vgui.menu_action('Redo')
	m_redo.on_click = fn [mut status] () {
		status.text = 'Edit -> Redo'
	}
	bar.add_menu('Edit', [m_undo, m_redo])

	mut m_about := vgui.menu_action('About')
	m_about.on_click = fn [mut status] () {
		status.text = 'Help -> About'
	}
	bar.add_menu('Help', [m_about])

	mut body := vgui.create_vbox_fill()
	body.set_padding(16)
	body.set_spacing(8)
	body.add(status)
	body.add(vgui.create_spacer(), flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.add(bar)
	root.add(body, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
