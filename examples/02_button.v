module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Button - demo')!

	mut status := vgui.label('Нажмите кнопку...')
	status.color = vgui.Color{180, 180, 180, 255}

	// Стили кнопок задаются через поле .style
	mut b_normal := vgui.button('Normal')
	b_normal.on_click = fn [mut status] () {
		status.text = 'Normal нажата'
	}

	mut b_accent := vgui.button('Accent')
	b_accent.style = .accent
	b_accent.on_click = fn [mut status] () {
		status.text = 'Accent нажата'
	}

	mut b_danger := vgui.button('Danger')
	b_danger.style = .danger
	b_danger.on_click = fn [mut status] () {
		status.text = 'Danger нажата'
	}

	mut b_outline := vgui.button('Outline')
	b_outline.style = .outline

	// Отключённая кнопка
	mut b_disabled := vgui.button('Disabled')
	b_disabled.enabled = false

	// Toggle-кнопка с колбэком on_toggle
	mut b_toggle := vgui.toggle_button('Toggle: OFF')
	b_toggle.on_toggle = fn [mut b_toggle, mut status] (active bool) {
		b_toggle.text = if active { 'Toggle: ON' } else { 'Toggle: OFF' }
		status.text = 'Toggle = ${active}'
	}

	mut row1 := vgui.create_hbox_fill()
	row1.set_spacing(6)
	row1.add(b_normal, flex: 1)
	row1.add(b_accent, flex: 1)
	row1.add(b_danger, flex: 1)

	mut row2 := vgui.create_hbox_fill()
	row2.set_spacing(6)
	row2.add(b_outline, flex: 1)
	row2.add(b_disabled, flex: 1)
	row2.add(b_toggle, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(row1)
	root.add(row2)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
