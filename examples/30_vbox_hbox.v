module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'VBox / HBox - demo')!

	// VBox раскладывает детей по вертикали, HBox — по горизонтали.
	// add(widget)          - естественный размер (метка - под строку);
	// add(widget, flex: n) - доля свободного места (растягивается).

	mut color_panel := fn (text string, c vgui.Color) &vgui.Panel {
		mut lbl := vgui.label(text)
		lbl.align = .center
		lbl.valign = .middle
		lbl.color = vgui.Color{255, 255, 255, 255}
		mut p := vgui.panel()
		p.set_child(lbl)
		p.bg = c
		return p
	}

	// HBox: три колонки с разными flex-долями (1 : 2 : 1)
	mut hrow := vgui.create_hbox_fill()
	hrow.set_spacing(8)
	hrow.add(color_panel('flex 1', vgui.Color{198, 40, 40, 255}), flex: 1)
	hrow.add(color_panel('flex 2', vgui.Color{46, 125, 50, 255}), flex: 2)
	hrow.add(color_panel('flex 1', vgui.Color{21, 101, 192, 255}), flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(vgui.label('add(w) - блок по высоте своей подписи:'))
	root.add(color_panel('блок по содержимому', vgui.Color{84, 110, 122, 255}))
	root.add(vgui.label('HBox с flex-долями 1:2:1:'))
	root.add(hrow, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
