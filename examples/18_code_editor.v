module main

import vgui

const sample_code = 'module main

fn main() {
	// Редактор кода с подсветкой синтаксиса V
	greeting := "Привет, vgui!"
	for i in 0 .. 3 {
		println("\${i}: \${greeting}")
	}
}
'

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'CodeEditor - demo')!

	mut status := vgui.label('Строк: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Редактор кода: номера строк, выделение, undo/redo, подсветка.
	mut ed := vgui.code_editor()
	ed.set_highlighter(vgui.v_highlighter())
	ed.set_text(sample_code)
	ed.show_line_numbers = true
	ed.on_change = fn [mut ed, mut status] () {
		status.text = 'Строк: ${ed.get_line_count()}'
	}

	mut b_get := vgui.button('get_line_count()')
	b_get.on_click = fn [mut ed, mut status] () {
		status.text = 'Строк: ${ed.get_line_count()}'
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(ed, flex: 1)
	root.add(b_get)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
