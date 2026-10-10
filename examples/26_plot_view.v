module main

import math
import vgui

fn f_sin(x f32) f32 {
	return f32(math.sin(x))
}

fn f_cos(x f32) f32 {
	return f32(math.cos(x))
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
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

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(plot, flex: 1)
	root.add(row)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
