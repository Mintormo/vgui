module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'ScrollBox - demo')!

	// ScrollBox прокручивает содержимое, которое выше видимой области.
	// scroll_box(content_h) — вертикальная прокрутка; 0 = высота по контенту.

	mut content := vgui.create_vbox_fill()
	content.set_spacing(6)
	content.set_padding(8)
	for i in 1 .. 41 {
		mut row := vgui.label('Элемент списка № ${i}')
		row.valign = .middle
		mut p := vgui.panel()
		p.set_child(row)
		p.pad = 8
		content.add(p)
	}

	mut sb := vgui.scroll_box(0)
	sb.add(content)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(vgui.label('Прокрутите колесом мыши:'))
	root.add(sb, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
