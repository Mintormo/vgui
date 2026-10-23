module main

// Пример 25. PropertyGrid: сетка свойств "имя - редактор" разных типов, сгруппированная.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/25_property_grid.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'PropertyGrid - demo')!

	// Сетка свойств: строки "имя — редактор" разных типов, сгруппированы.
	// set_app нужен типам, открывающим диалоги (цвет, дата).
	mut pg := vgui.property_grid()
	pg.set_app(app)

	mut g_general := pg.add_group('General')
	g_general.add_string('Name', 'My project')
	g_general.add_int('Version', 3)
	g_general.add_bool('Enabled', true)
	g_general.add_choice('Theme', ['Dark', 'Light', 'Monokai'], 0)

	mut g_view := pg.add_group('View')
	g_view.add_color('Background color', vgui.Color{30, 30, 30, 255})
	g_view.add_float('Opacity', 0.85)
	g_view.add_date('Build date', 2026, 6, 25)

	mut g_paths := pg.add_group('Paths')
	g_paths.add_folder_path('Folder', '/home/igor/projects')
	g_paths.add_file_path('Icon', 'icon.png')

	mut status := vgui.label('Read a value:')
	status.color = vgui.Color{180, 180, 180, 255}

	mut btn := vgui.button('get_string("Name")')
	btn.on_click = fn [mut pg, mut status] () {
		status.text = 'Name = "${pg.get_string('Name')}"'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(pg, flex: 1)
	root.add(status)
	root.add(btn)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
