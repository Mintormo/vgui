module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Spinner - demo')!

	mut status := vgui.label('Spinner крутится...')
	status.color = vgui.Color{180, 180, 180, 255}

	// Индикатор загрузки. Анимируется, пока spinning = true.
	mut sp_arc := vgui.spinner()

	// Спиннер с текстом рядом
	mut sp_text := vgui.spinner_with_text('Загрузка...')

	// Управление через start() / stop()
	mut sp_ctl := vgui.spinner()
	mut btn := vgui.button('start / stop')
	btn.on_click = fn [mut sp_ctl, mut status] () {
		if sp_ctl.is_spinning() {
			sp_ctl.stop()
			status.text = 'Остановлен'
		} else {
			sp_ctl.start()
			status.text = 'Запущен'
		}
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(16)
	row.add(sp_arc)
	row.add(sp_text, flex: 1)

	mut ctl_row := vgui.create_hbox_fill()
	ctl_row.set_spacing(12)
	ctl_row.add(sp_ctl)
	ctl_row.add(btn, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(row)
	root.add(ctl_row)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
