module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'MenuBar - demo')!

	mut status := vgui.label('Пункт меню: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Полоса меню вверху окна. add_menu(title, []MenuItem).
	mut bar := vgui.menu_bar()

	mut m_new := vgui.menu_action('Новый')
	m_new.on_click = fn [mut status] () {
		status.text = 'Файл -> Новый'
	}
	mut m_open := vgui.menu_action('Открыть...')
	m_open.on_click = fn [mut status] () {
		status.text = 'Файл -> Открыть'
	}
	mut m_exit := vgui.menu_action('Выход')
	m_exit.on_click = fn [mut app] () {
		app.quit()
	}
	bar.add_menu('Файл', [m_new, m_open, vgui.menu_separator(), m_exit])

	mut m_undo := vgui.menu_action('Отменить')
	m_undo.on_click = fn [mut status] () {
		status.text = 'Правка -> Отменить'
	}
	mut m_redo := vgui.menu_action('Повторить')
	m_redo.on_click = fn [mut status] () {
		status.text = 'Правка -> Повторить'
	}
	bar.add_menu('Правка', [m_undo, m_redo])

	mut m_about := vgui.menu_action('О программе')
	m_about.on_click = fn [mut status] () {
		status.text = 'Справка -> О программе'
	}
	bar.add_menu('Справка', [m_about])

	mut body := vgui.create_vbox_fill()
	body.set_padding(16)
	body.set_spacing(8)
	body.add(status)
	body.add(vgui.create_spacer(), flex: 1)

	mut root := vgui.create_vbox_fill()
	root.add(bar)
	root.add(body, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
