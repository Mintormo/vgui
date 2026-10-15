module main

// Пример 13. Badge: бейджи-варианты, счётчик и точка.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/13_badge.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Badge - demo')!

	// Бейджи разных вариантов (variant). Вариант задаёт цвет.
	mut b_info := vgui.badge('INFO')
	b_info.variant = .info

	mut b_ok := vgui.badge('SUCCESS')
	b_ok.variant = .success

	mut b_warn := vgui.badge('WARNING')
	b_warn.variant = .warning

	mut b_err := vgui.badge('ERROR')
	b_err.variant = .error

	// Счётчик и точка
	mut b_count := vgui.badge_count(42)
	mut b_dot := vgui.badge_dot()
	b_dot.variant = .success

	mut row1 := vgui.create_hbox_fill()
	row1.set_spacing(8)
	row1.add(b_info)
	row1.add(b_ok)
	row1.add(b_warn)
	row1.add(b_err)
	row1.add(vgui.create_spacer(), flex: 1)

	mut count_label := vgui.label('Непрочитанных:')
	count_label.valign = .middle
	mut dot_label := vgui.label('Статус (точка):')
	dot_label.valign = .middle

	mut row2 := vgui.create_hbox_fill()
	row2.set_spacing(8)
	row2.add(count_label)
	row2.add(b_count)
	row2.add(vgui.create_spacer(), flex: 1)

	mut row3 := vgui.create_hbox_fill()
	row3.set_spacing(8)
	row3.add(dot_label)
	row3.add(b_dot)
	row3.add(vgui.create_spacer(), flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(vgui.label('Варианты бейджей:'))
	root.add(row1)
	root.add(vgui.hseparator())
	root.add(row2)
	root.add(row3)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
