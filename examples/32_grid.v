module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'GridLayout - demo')!

	mut status := vgui.label('Нажата кнопка: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Сетка 3x3. add(widget, row, col); add_span — объединение ячеек.
	mut grid := vgui.create_grid(3, 3)
	grid.set_spacing(6, 6)
	grid.set_padding(4)
	// Дорожки сетки по умолчанию - по содержимому; вес 1 у всех -
	// ячейки поровну делят окно
	for i in 0 .. 3 {
		grid.set_col_weight(i, 1)
		grid.set_row_weight(i, 1)
	}

	for r in 0 .. 3 {
		for c in 0 .. 3 {
			label := '${r},${c}'
			mut b := vgui.button(label)
			b.on_click = fn [mut status, label] () {
				status.text = 'Нажата кнопка: ${label}'
			}
			grid.add(b, r, c)
		}
	}

	// Кнопка, занимающая всю нижнюю строку (col_span = 3)
	mut wide := vgui.button('col_span = 3 (вся строка)')
	wide.style = .accent
	wide.on_click = fn [mut status] () {
		status.text = 'Нажата широкая кнопка'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(grid, flex: 1)
	root.add(wide)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
