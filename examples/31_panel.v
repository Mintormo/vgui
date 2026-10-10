module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Panel - demo')!

	// Panel — контейнер с фоном, рамкой, скруглением и отступом
	// вокруг единственного ребёнка (set_child).

	mut text := vgui.label_wrap('Panel задаёт фон, рамку, скругление углов и внутренний отступ вокруг вложенного виджета.')
	text.valign = .middle

	mut p_default := vgui.panel()
	p_default.set_child(text)
	p_default.pad = 12

	// Своя расцветка
	mut inner := vgui.label('Своя расцветка фона и рамки')
	inner.align = .center
	inner.valign = .middle
	inner.color = vgui.Color{255, 255, 255, 255}

	mut p_custom := vgui.panel()
	p_custom.set_child(inner)
	p_custom.pad = 12
	p_custom.bg = vgui.Color{21, 101, 192, 255}
	p_custom.border = vgui.Color{144, 202, 249, 255}
	p_custom.radius = 10

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(p_default, flex: 1)
	root.add(p_custom, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
