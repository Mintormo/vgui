module main

// Пример 58. Поле ввода сочетания клавиш (ShortcutInput) и настраиваемые горячие клавиши.
//
// Щелчок по полю - ожидание нажатия: новое сочетание становится сочетанием пункта меню.
// Esc - отмена, Backspace - снять, стрелки заняты (on_reject). Сочетание определяется по
// месту клавиши: в русской раскладке Ctrl+«з» - это Ctrl+P, и меню его узнаёт.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/58_shortcut_input.v

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ShortcutInput - configurable shortcuts', width: 520, height: 260)!

	mut status := vgui.label("Press a menu item's shortcut or set a new one")
	status.color = vgui.Color{180, 180, 180, 255}

	// Пункты меню - их сочетания настраиваются полями ниже
	mut m_save := vgui.menu_action('Save')
	m_save.shortcut = 'Ctrl+S'
	m_save.on_click = fn [mut status] () {
		status.text = 'File -> Save'
	}
	mut m_export := vgui.menu_action('Export')
	m_export.shortcut = 'Ctrl+E'
	m_export.on_click = fn [mut status] () {
		status.text = 'File -> Export'
	}
	mut bar := vgui.menu_bar()
	bar.add_menu('File', [m_save, m_export])

	mut col := vgui.create_vbox_fill()
	col.set_padding(12)
	col.set_spacing(8)
	col.add(bar)
	mut items := [m_save, m_export]
	for i in 0 .. items.len {
		mut it := items[i]
		mut si := vgui.shortcut_input(it.shortcut)
		si.reserved = ['Left', 'Right', 'Up', 'Down']
		// Новое сочетание ('' - снято) - сразу в пункт меню
		on_change := fn [mut it, mut status] (s string) {
			it.shortcut = s
			status.text = if s.len > 0 { '${it.text}: ${s}' } else { '${it.text}: no shortcut' }
		}
		si.on_change = on_change
		on_reject := fn [mut status] (s string) {
			status.text = '${s} is used for navigation - choose another'
		}
		si.on_reject = on_reject
		mut row := vgui.create_hbox_fill()
		row.set_spacing(8)
		row.add(vgui.label(it.text), min: 120)
		row.add(si, min: 200)
		row.add(vgui.create_spacer(), flex: 1)
		col.add(row)
	}
	col.add(vgui.create_spacer(), flex: 1)
	col.add(status)

	win.add_widget(col)
	app.add_window(win)
	app.run()
}
