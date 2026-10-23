module main

// Пример 34. Centered: центрирование ребёнка заданного размера в доступной области.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/34_centered.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Centered - demo')!

	// Centered центрирует ребёнка заданного размера внутри доступной области.
	// create_centered_fill(child_w, child_h) — ребёнок фиксированного размера
	// по центру, остальное пространство пустое.

	mut card_text := vgui.label_wrap('This 240x120 card always stays in the center of the window when it is resized.')
	card_text.align = .center
	card_text.valign = .middle
	card_text.color = vgui.Color{255, 255, 255, 255}

	mut card := vgui.panel()
	card.set_child(card_text)
	card.pad = 12
	card.bg = vgui.Color{46, 125, 50, 255}
	card.radius = 10

	mut centered := vgui.create_centered_fill(240, 120)
	centered.set_child(card)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.add(centered, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
