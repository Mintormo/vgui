module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'ComboBox - demo')!

	mut status := vgui.label('Выбор: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Выпадающий список. Колбэк on_change получает (индекс, текст).
	mut city := vgui.combo_box()
	city.add_items(['Москва', 'Санкт-Петербург', 'Новосибирск',
		'Екатеринбург', 'Казань'])
	city.set_selected(0)
	city.on_change = fn [mut status] (idx int, text string) {
		status.text = 'Город [${idx}]: ${text}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Список с подсказкой-плейсхолдером (ничего не выбрано)
	mut lang := vgui.combo_box()
	lang.placeholder = '— выберите язык —'
	lang.add_items(['V', 'Python', 'Rust', 'Go', 'C'])
	lang.on_change = fn [mut status] (idx int, text string) {
		status.text = 'Язык: ${text}'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Город:'))
	root.add(city)
	root.add(vgui.label('Язык (с placeholder):'))
	root.add(lang)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
