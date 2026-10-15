module main

// Пример 39. DropZone: зона приёма перетаскиваемых файлов (drag-and-drop) и выбор файла кликом.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/39_drop_zone.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'DropZone - demo')!

	mut status := vgui.label('Перетащите файл из проводника в область ниже')
	status.color = vgui.Color{180, 180, 180, 255}

	// Зона приёма drag-and-drop. on_drop_file срабатывает на брошенный файл.
	// click_to_browse = true: клик по зоне открывает диалог выбора файла,
	// результат приходит в тот же on_drop_file.
	mut dz := vgui.drop_zone('Перетащите файлы сюда\nили кликните для выбора')
	dz.click_to_browse = true
	dz.on_drop_file = fn [mut status] (path string) {
		status.text = 'Файл: ${path}'
		status.color = vgui.Color{72, 199, 142, 255}
	}
	dz.on_drop_text = fn [mut status] (text string) {
		status.text = 'Текст: ${text}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(dz, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
