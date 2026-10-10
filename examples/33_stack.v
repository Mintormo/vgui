module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Stack - demo')!

	// Stack накладывает детей друг на друга (z-порядок: добавленные позже
	// рисуются сверху). Удобно для оверлеев, бейджей поверх контента и т.п.

	mut bg := vgui.label('Фоновый слой')
	bg.align = .center
	bg.valign = .middle
	bg.color = vgui.Color{255, 255, 255, 255}
	mut bg_panel := vgui.panel()
	bg_panel.set_child(bg)
	bg_panel.bg = vgui.Color{21, 101, 192, 255}

	// Верхний слой — бейдж в правом верхнем углу через Centered-обёртку
	mut overlay := vgui.create_vbox_fill()
	mut badge_row := vgui.create_hbox_fill()
	badge_row.add(vgui.create_spacer(), flex: 1)
	badge_row.add(vgui.badge_count(7))
	overlay.add(badge_row)
	overlay.add(vgui.create_spacer(), flex: 1)

	mut stack := vgui.stack()
	stack.add(bg_panel)
	stack.add(overlay)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(vgui.label('Бейдж наложен поверх синей панели:'))
	root.add(stack, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
