module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Centered - demo')!

	// Centered центрирует ребёнка заданного размера внутри доступной области.
	// create_centered_fill(child_w, child_h) — ребёнок фиксированного размера
	// по центру, остальное пространство пустое.

	mut card_text := vgui.label_wrap('Эта карточка размером 240x120 всегда остаётся по центру окна при изменении его размера.')
	card_text.align = .center
	card_text.valign = .middle
	card_text.color = vgui.Color{255, 255, 255, 255}

	mut card := vgui.panel()
	card.set_child(card_text)
	card.pad = 12
	card.bg = vgui.Color{46, 125, 50, 255}
	card.radius = 10

	mut centered := vgui.create_centered_fill(240, 120)
	centered.set_child(card)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.add(centered, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
