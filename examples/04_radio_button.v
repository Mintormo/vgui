module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'RadioButton - demo')!

	mut status := vgui.label('Выбор: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Кнопки одной группы объединяются полем .radio_group:
	// выбор одной автоматически снимает выбор остальных в группе.
	mut r1 := vgui.radio_button('Маленький')
	r1.radio_group = 'size'
	r1.selected = true
	r1.on_change = fn [mut status] (sel bool) {
		if sel {
			status.text = 'Размер: маленький'
		}
	}

	mut r2 := vgui.radio_button('Средний')
	r2.radio_group = 'size'
	r2.on_change = fn [mut status] (sel bool) {
		if sel {
			status.text = 'Размер: средний'
		}
	}

	mut r3 := vgui.radio_button('Большой')
	r3.radio_group = 'size'
	r3.on_change = fn [mut status] (sel bool) {
		if sel {
			status.text = 'Размер: большой'
		}
	}

	// Вторая независимая группа
	mut c1 := vgui.radio_button('Светлая тема')
	c1.radio_group = 'theme'
	c1.selected = true

	mut c2 := vgui.radio_button('Тёмная тема')
	c2.radio_group = 'theme'

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Группа "size":'))
	root.add(r1)
	root.add(r2)
	root.add(r3)
	root.add(vgui.label('Группа "theme":'))
	root.add(c1)
	root.add(c2)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
