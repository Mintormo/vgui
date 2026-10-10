module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'TextArea - demo')!

	mut status := vgui.label('Символов: 0')
	status.color = vgui.Color{180, 180, 180, 255}

	// Многострочное поле ввода. Колбэк on_change получает весь текст.
	mut ta := vgui.text_area('Введите многострочный текст...')
	ta.set_text('Первая строка.\nВторая строка.\n\nTextArea поддерживает перенос, выделение, undo/redo (Ctrl+Z).')
	ta.on_change = fn [mut status] (text string) {
		status.text = 'Символов: ${text.len}'
	}

	// Кнопки: дописать текст и прочитать
	mut b_append := vgui.button('append_text()')
	b_append.on_click = fn [mut ta] () {
		ta.append_text('\n+ дописанная строка')
	}

	mut b_clear := vgui.button('Очистить')
	b_clear.style = .outline
	b_clear.on_click = fn [mut ta, mut status] () {
		ta.set_text('')
		status.text = 'Символов: 0'
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(b_append, flex: 1)
	row.add(b_clear, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(ta, flex: 1)
	root.add(row)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
