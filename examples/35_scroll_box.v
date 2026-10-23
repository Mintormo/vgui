module main

// Пример 35. ScrollBox: прокрутка содержимого, не помещающегося в видимую область.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/35_scroll_box.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ScrollBox - demo')!

	// ScrollBox прокручивает содержимое, которое выше видимой области.
	// scroll_box(content_h) — вертикальная прокрутка; 0 = высота по контенту.

	mut content := vgui.create_vbox_fill()
	content.set_spacing(6)
	content.set_padding(8)
	for i in 1 .. 41 {
		mut row := vgui.label('List item #${i}')
		row.valign = .middle
		mut p := vgui.panel()
		p.set_child(row)
		p.pad = 8
		content.add(p)
	}

	mut sb := vgui.scroll_box(0)
	sb.add(content)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(vgui.label('Scroll with the mouse wheel:'))
	root.add(sb, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
