module main

// Пример 31. Panel: контейнер с фоном, рамкой, скруглением и отступом вокруг одного ребёнка.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/31_panel.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Panel - demo')!

	// Panel — контейнер с фоном, рамкой, скруглением и отступом
	// вокруг единственного ребёнка (set_child).

	mut text := vgui.label_wrap('Panel adds a background, a border, rounded corners and padding around the nested widget.')
	text.valign = .middle

	mut p_default := vgui.panel()
	p_default.set_child(text)
	p_default.pad = 12

	// Своя расцветка
	mut inner := vgui.label('Custom background and border colors')
	inner.align = .center
	inner.valign = .middle
	inner.color = vgui.Color{255, 255, 255, 255}

	mut p_custom := vgui.panel()
	p_custom.set_child(inner)
	p_custom.pad = 12
	p_custom.bg = vgui.Color{21, 101, 192, 255}
	p_custom.border = vgui.Color{144, 202, 249, 255}
	p_custom.radius = 10

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(p_default, flex: 1)
	root.add(p_custom, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
