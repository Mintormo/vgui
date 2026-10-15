module main

// Пример 29. ContextMenu: контекстное меню по правому клику, привязанное к виджету через attach().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/29_context_menu.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ContextMenu - demo')!

	mut status := vgui.label('Команда: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Контекстное меню привязывается к виджету через attach()
	// и открывается по правому клику по нему.
	mut target := vgui.label('Кликните правой кнопкой по этой области')
	target.align = .center
	target.valign = .middle

	mut panel := vgui.panel()
	panel.set_child(target)
	panel.pad = 12

	mut menu := vgui.context_menu()

	mut c_cut := vgui.menu_action('Вырезать')
	c_cut.shortcut = 'Ctrl+X'
	c_cut.on_click = fn [mut status] () {
		status.text = 'Команда: Вырезать'
	}
	mut c_copy := vgui.menu_action('Копировать')
	c_copy.shortcut = 'Ctrl+C'
	c_copy.on_click = fn [mut status] () {
		status.text = 'Команда: Копировать'
	}
	mut c_paste := vgui.menu_action('Вставить')
	c_paste.shortcut = 'Ctrl+V'
	c_paste.on_click = fn [mut status] () {
		status.text = 'Команда: Вставить'
	}

	menu.add(c_cut)
	menu.add(c_copy)
	menu.add(c_paste)
	menu.add(vgui.menu_separator())
	mut c_check := vgui.menu_checkbox('Показывать сетку', true)
	c_check.on_toggle = fn [mut status] (on bool) {
		status.text = 'Сетка: ${on}'
	}
	menu.add(c_check)
	menu.attach(panel)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(panel, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Контекстное меню добавляется в окно отдельно, чтобы рисоваться поверх.
	win.add_widget(menu)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
