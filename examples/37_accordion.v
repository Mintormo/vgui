module main

// Пример 37. Accordion: разворачиваемые секции (accordion_single - открыта одна, accordion_multi - несколько).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/37_accordion.v

import vgui

fn make_section(text string) &vgui.VBox {
	mut box := vgui.create_vbox_fill()
	box.set_padding(10)
	box.set_spacing(6)
	mut l := vgui.label_wrap(text)
	box.add(l, flex: 1)
	return box
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Accordion - demo')!

	// Аккордеон: разворачиваемые секции.
	// accordion_single() — открыта только одна секция;
	// accordion_multi()  — можно открыть несколько одновременно.
	mut acc := vgui.accordion_single()

	mut general := make_section('General application settings.')
	general.add(vgui.checkbox('Start automatically'))
	general.add(vgui.checkbox('Check for updates'))

	mut appearance := make_section('Appearance settings.')
	appearance.add(vgui.toggle_switch('Dark theme'))

	about := make_section('vgui is a GUI library for the V language. This example shows the Accordion widget in single mode.')

	acc.add_section_expanded('General', general)
	acc.add_section('Appearance', appearance)
	acc.add_section('About', about)
	acc.on_change = fn (idx int, expanded bool) {
		println('Section ${idx}: expanded=${expanded}')
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(vgui.label('Click a section header:'))
	root.add(acc, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
