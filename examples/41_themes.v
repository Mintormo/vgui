module main

import vgui

struct ThemeEntry {
	name  string
	theme vgui.Theme
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Themes - demo')!

	mut status := vgui.label('Тема: Dark')
	status.color = vgui.Color{180, 180, 180, 255}

	// Встроенные темы. win.set_theme(theme) применяет тему ко всему окну.
	themes := [
		ThemeEntry{'Dark', vgui.dark_theme()},
		ThemeEntry{'Light', vgui.light_theme()},
		ThemeEntry{'Monokai', vgui.monokai_theme()},
		ThemeEntry{'Win10', vgui.win10_theme()},
		ThemeEntry{'Win10 Dark', vgui.win10_dark_theme()},
		ThemeEntry{'Win11', vgui.win11_theme()},
		ThemeEntry{'Win11 Dark', vgui.win11_dark_theme()},
		ThemeEntry{'KDE Breeze', vgui.kde_breeze_theme()},
		ThemeEntry{'KDE Breeze Dark', vgui.kde_breeze_dark_theme()},
		ThemeEntry{'Adwaita', vgui.gtk_adwaita_theme()},
		ThemeEntry{'Adwaita Dark', vgui.gtk_adwaita_dark_theme()},
		ThemeEntry{'macOS', vgui.macos_theme()},
		ThemeEntry{'macOS Dark', vgui.macos_dark_theme()},
		ThemeEntry{'Mac OS X Aqua', vgui.mac_os_x_aqua_theme()},
		ThemeEntry{'Mac OS 9 Platinum', vgui.mac_os_9_platinum_theme()},
	]

	// ComboBox для выбора темы
	mut combo := vgui.combo_box()
	mut names := []string{}
	for t in themes {
		names << t.name
	}
	combo.add_items(names)
	combo.set_selected(0)
	combo.on_change = fn [mut win, mut status, themes] (idx int, text string) {
		win.set_theme(themes[idx].theme)
		status.text = 'Тема: ${text}'
	}

	// Набор виджетов, чтобы видеть, как тема влияет на их вид
	mut sample := vgui.create_vbox_fill()
	sample.set_spacing(8)
	sample.add(vgui.button('Normal'))
	mut accent := vgui.button('Accent')
	accent.style = .accent
	sample.add(accent)
	sample.add(vgui.checkbox('Чекбокс'))
	sample.add(vgui.toggle_switch('Переключатель'))
	sample.add(vgui.text_input('Поле ввода...'))
	mut pb := vgui.progress_bar()
	pb.set_value(0.6)
	sample.add(pb)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.label('Выберите тему:'))
	root.add(combo)
	root.add(vgui.hseparator())
	root.add(sample, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
