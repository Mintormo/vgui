module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'ColorPicker - demo')!

	mut status := vgui.label('Цвет: rgb(255, 0, 0)')
	status.color = vgui.Color{180, 180, 180, 255}

	// Встроенный выбор цвета с HSV-палитрой и альфа-каналом.
	mut cp := vgui.color_picker_with_color(vgui.Color{255, 0, 0, 255})
	cp.show_alpha = true
	cp.on_change = fn [mut status] (c vgui.Color) {
		status.text = 'Цвет: rgba(${c.r}, ${c.g}, ${c.b}, ${c.a})'
		status.color = c
	}

	// Кнопка читает текущее значение
	mut btn := vgui.button('get_color()')
	btn.on_click = fn [mut cp, mut status] () {
		c := cp.get_color()
		status.text = 'get_color() = rgb(${c.r}, ${c.g}, ${c.b})'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(cp, flex: 1)
	root.add(btn)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
