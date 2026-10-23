module main

// Пример 38. Splitter: две панели с перетаскиваемой границей.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/38_splitter.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Splitter - demo')!

	mut status := vgui.label('Drag the divider between the panels')
	status.color = vgui.Color{180, 180, 180, 255}

	// Splitter делит область на две части с перетаскиваемой границей.
	// splitter_horizontal() — граница вертикальна (левая/правая панели).

	mut left_lbl := vgui.label('Left panel')
	left_lbl.align = .center
	left_lbl.valign = .middle
	mut left := vgui.panel()
	left.set_child(left_lbl)
	left.bg = vgui.Color{40, 53, 70, 255}

	mut right_lbl := vgui.label('Right panel')
	right_lbl.align = .center
	right_lbl.valign = .middle
	mut right := vgui.panel()
	right.set_child(right_lbl)
	right.bg = vgui.Color{40, 70, 53, 255}

	mut sp := vgui.splitter_horizontal()
	sp.set_first(left)
	sp.set_second(right)
	sp.set_ratio(0.4)
	sp.on_resize = fn [mut status] (ratio f32) {
		status.text = 'Ratio: ${ratio:.2f}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(sp, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
