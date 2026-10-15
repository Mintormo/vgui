module main

// Пример 22. ListBox: прокручиваемый список, колбэки on_select и on_dbl_click.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/22_list_box.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ListBox - demo')!

	mut status := vgui.label('Выбор: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Список с прокруткой. on_select(idx, text), on_dbl_click(idx, text).
	mut lb := vgui.list_box()
	lb.add_items([
		'Москва',
		'Санкт-Петербург',
		'Новосибирск',
		'Екатеринбург',
		'Казань',
		'Нижний Новгород',
		'Челябинск',
		'Самара',
		'Омск',
		'Ростов-на-Дону',
	])
	lb.on_select = fn [mut status] (idx int, text string) {
		status.text = 'Выбрано: ${text} [${idx}]'
		status.color = vgui.Color{66, 165, 245, 255}
	}
	lb.on_dbl_click = fn [mut status] (idx int, text string) {
		status.text = 'Двойной клик: ${text}'
		status.color = vgui.Color{72, 199, 142, 255}
	}

	mut btn := vgui.button('get_selected_text()')
	btn.on_click = fn [mut lb, mut status] () {
		status.text = 'Выбрано: "${lb.get_selected_text()}"'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(lb, flex: 1)
	root.add(btn)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
