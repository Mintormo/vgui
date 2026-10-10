module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Separator - demo')!

	// hseparator() — горизонтальная разделительная линия в VBox.
	// vseparator() — вертикальная линия в HBox.

	mut sep_color := vgui.hseparator()
	sep_color.color = vgui.Color{66, 165, 245, 255}
	sep_color.thickness = 2

	// Горизонтальная компоновка с вертикальным разделителем
	mut left := vgui.label('Слева')
	left.valign = .middle
	left.align = .center
	mut right := vgui.label('Справа')
	right.valign = .middle
	right.align = .center

	mut hrow := vgui.create_hbox_fill()
	hrow.set_spacing(8)
	hrow.add(left, flex: 1)
	hrow.add(vgui.vseparator())
	hrow.add(right, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(vgui.label('Секция 1'))
	root.add(vgui.hseparator())
	root.add(vgui.label('Секция 2'))
	root.add(sep_color)
	root.add(vgui.label('Цветной разделитель сверху'))
	root.add(vgui.hseparator())
	root.add(vgui.label('Вертикальный разделитель:'))
	root.add(hrow)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
