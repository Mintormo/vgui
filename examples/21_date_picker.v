module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'DatePicker - demo')!

	mut status := vgui.label('Дата: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Встроенный календарь. Колбэк on_change(year, month, day).
	mut dp := vgui.date_picker_ymd(2026, 6, 25)
	dp.on_change = fn [mut status] (y int, m int, d int) {
		status.text = 'Выбрано: ${d:02d}.${m:02d}.${y}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Кнопка читает текущее значение
	mut btn := vgui.button('get_date()')
	btn.on_click = fn [mut dp, mut status] () {
		y, m, d := dp.get_date()
		status.text = 'get_date() = ${d:02d}.${m:02d}.${y}'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(dp, flex: 1)
	root.add(btn)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
