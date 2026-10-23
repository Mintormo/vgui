module main

// Пример 41. Themes: встроенные темы и переключение темы окна через win.set_theme().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/41_themes.v

import vgui

struct ThemeEntry {
	name  string
	theme vgui.Theme
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Themes - demo')!

	mut status := vgui.label('Theme: Dark')
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
		status.text = 'Theme: ${text}'
	}

	// Набор виджетов, чтобы видеть, как тема влияет на их вид
	mut sample := vgui.create_vbox_fill()
	sample.set_spacing(8)
	sample.add(vgui.button('Normal'))
	mut accent := vgui.button('Accent')
	accent.style = .accent
	sample.add(accent)
	sample.add(vgui.checkbox('Checkbox'))
	sample.add(vgui.toggle_switch('Switch'))
	sample.add(vgui.text_input('Input field...'))
	mut pb := vgui.progress_bar()
	pb.set_value(0.6)
	sample.add(pb)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.label('Choose a theme:'))
	root.add(combo)
	root.add(vgui.hseparator())
	root.add(sample, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
