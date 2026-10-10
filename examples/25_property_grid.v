module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'PropertyGrid - demo')!

	// Сетка свойств: строки "имя — редактор" разных типов, сгруппированы.
	// set_app нужен типам, открывающим диалоги (цвет, дата).
	mut pg := vgui.property_grid()
	pg.set_app(app)

	mut g_general := pg.add_group('Общие')
	g_general.add_string('Название', 'Мой проект')
	g_general.add_int('Версия', 3)
	g_general.add_bool('Включено', true)
	g_general.add_choice('Тема', ['Тёмная', 'Светлая', 'Monokai'], 0)

	mut g_view := pg.add_group('Вид')
	g_view.add_color('Цвет фона', vgui.Color{30, 30, 30, 255})
	g_view.add_float('Прозрачность', 0.85)
	g_view.add_date('Дата сборки', 2026, 6, 25)

	mut g_paths := pg.add_group('Пути')
	g_paths.add_folder_path('Каталог', '/home/igor/projects')
	g_paths.add_file_path('Иконка', 'icon.png')

	mut status := vgui.label('Прочитать значение:')
	status.color = vgui.Color{180, 180, 180, 255}

	mut btn := vgui.button('get_string("Название")')
	btn.on_click = fn [mut pg, mut status] () {
		status.text = 'Название = "${pg.get_string('Название')}"'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(pg, flex: 1)
	root.add(status)
	root.add(btn)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
