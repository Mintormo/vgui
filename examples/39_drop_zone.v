module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'DropZone - demo')!

	mut status := vgui.label('Перетащите файл из проводника в область ниже')
	status.color = vgui.Color{180, 180, 180, 255}

	// Зона приёма drag-and-drop. on_drop_file срабатывает на брошенный файл.
	// click_to_browse = true: клик по зоне открывает диалог выбора файла,
	// результат приходит в тот же on_drop_file.
	mut dz := vgui.drop_zone('Перетащите файлы сюда\nили кликните для выбора')
	dz.click_to_browse = true
	dz.on_drop_file = fn [mut status] (path string) {
		status.text = 'Файл: ${path}'
		status.color = vgui.Color{72, 199, 142, 255}
	}
	dz.on_drop_text = fn [mut status] (text string) {
		status.text = 'Текст: ${text}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(dz, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
