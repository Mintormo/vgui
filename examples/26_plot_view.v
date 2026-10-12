module main

// Пример 26. PlotView: график функций и точек (колесо - зум, перетаскивание - панорама).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/26_plot_view.v

import math
import vgui

fn f_sin(x f32) f32 {
	return f32(math.sin(x))
}

fn f_cos(x f32) f32 {
	return f32(math.cos(x))
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'PlotView - demo')!

	// График функций и точек. Колесо мыши — зум, перетаскивание — панорама.
	mut plot := vgui.plot_view()
	plot.add_function_named('sin(x)', f_sin, vgui.Color{66, 165, 245, 255})
	plot.add_function_named('cos(x)', f_cos, vgui.Color{255, 120, 0, 255})

	// Набор точек как отдельная серия
	pts := vgui.make_points([f32(-6), -3, 0, 3, 6], [f32(-1), 1, 0, 1, -1])
	plot.add_points_with_markers(pts, vgui.Color{72, 199, 142, 255}, 4)

	plot.set_range(-2 * 3.14159, 2 * 3.14159, -1.5, 1.5)

	mut b_reset := vgui.button('Сбросить вид')
	b_reset.on_click = fn [mut plot] () {
		plot.reset_view()
	}
	mut b_fit := vgui.button('Вписать данные')
	b_fit.style = .outline
	b_fit.on_click = fn [mut plot] () {
		plot.fit_to_data()
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(b_reset, flex: 1)
	row.add(b_fit, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(plot, flex: 1)
	root.add(row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
