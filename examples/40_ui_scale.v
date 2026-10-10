module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'UI Scale - demo')!

	mut status := vgui.label('Текущий масштаб: 1.0')
	status.color = vgui.Color{180, 180, 180, 255}
	status.font_size = 16

	// win.set_ui_scale(factor) масштабирует ВЕСЬ интерфейс окна:
	// шрифты, отступы, размеры виджетов. Это логический масштаб поверх
	// автоматического DPI-масштаба ОС. Удобно для доступности.
	mut sample := vgui.label('Образец текста для масштабирования')
	sample.valign = .middle

	mut sample_input := vgui.text_input('Поле тоже масштабируется...')

	mk_scale_btn := fn [mut win, mut status] (label string, scale f32) &vgui.Button {
		mut b := vgui.button(label)
		b.on_click = fn [mut win, mut status, scale, label] () {
			win.set_ui_scale(scale)
			status.text = 'Текущий масштаб: ${label}'
		}
		return b
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(mk_scale_btn('0.75', 0.75), flex: 1)
	row.add(mk_scale_btn('1.0', 1.0), flex: 1)
	row.add(mk_scale_btn('1.25', 1.25), flex: 1)
	row.add(mk_scale_btn('1.5', 1.5), flex: 1)
	row.add(mk_scale_btn('2.0', 2.0), flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(sample)
	root.add(sample_input)
	root.add(vgui.create_spacer(), flex: 1)
	root.add(vgui.label('Выберите масштаб интерфейса:'))
	root.add(row)

	win.add_widget(root)
	// Начальный масштаб
	win.set_ui_scale(1.0)
	app.add_window(win)
	app.run()
}
