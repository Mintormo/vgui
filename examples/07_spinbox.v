module main

// Пример 07. SpinBox: целочисленный счётчик с диапазоном, шагом, префиксом и суффиксом.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/07_spinbox.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Spinbox - demo')!

	mut status := vgui.label('Значение: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Целочисленный счётчик с диапазоном и шагом
	mut sp1 := vgui.spinbox()
	sp1.set_range(0, 100)
	sp1.set_value(10)
	sp1.on_change = fn [mut status] (v int) {
		status.text = 'Количество: ${v}'
	}

	// Шаг = 5
	mut sp2 := vgui.spinbox()
	sp2.set_range(0, 1000)
	sp2.set_step(5)
	sp2.set_value(50)

	// С префиксом / суффиксом
	mut sp3 := vgui.spinbox()
	sp3.set_range(0, 100)
	sp3.set_value(20)
	sp3.set_suffix(' %')

	mut sp4 := vgui.spinbox()
	sp4.set_range(-50, 50)
	sp4.set_value(0)
	sp4.set_prefix('T = ')
	sp4.set_suffix(' °C')

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Диапазон 0-100, шаг 1:'))
	root.add(sp1)
	root.add(vgui.label('Шаг = 5:'))
	root.add(sp2)
	root.add(vgui.label('Суффикс " %":'))
	root.add(sp3)
	root.add(vgui.label('Префикс/суффикс:'))
	root.add(sp4)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
