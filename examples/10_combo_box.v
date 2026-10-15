module main

// Пример 10. ComboBox: выпадающий список, колбэк on_change и подсказка-плейсхолдер.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/10_combo_box.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ComboBox - demo')!

	mut status := vgui.label('Выбор: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Выпадающий список. Колбэк on_change получает (индекс, текст).
	mut city := vgui.combo_box()
	city.add_items(['Москва', 'Санкт-Петербург', 'Новосибирск',
		'Екатеринбург', 'Казань'])
	city.set_selected(0)
	city.on_change = fn [mut status] (idx int, text string) {
		status.text = 'Город [${idx}]: ${text}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Список с подсказкой-плейсхолдером (ничего не выбрано)
	mut lang := vgui.combo_box()
	lang.placeholder = '— выберите язык —'
	lang.add_items(['V', 'Python', 'Rust', 'Go', 'C'])
	lang.on_change = fn [mut status] (idx int, text string) {
		status.text = 'Язык: ${text}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Город:'))
	root.add(city)
	root.add(vgui.label('Язык (с placeholder):'))
	root.add(lang)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
