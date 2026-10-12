module main

// Пример 15. ImageView: показ картинки из файла с режимом масштабирования .fit.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/15_image_view.v

import os
import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ImageView - demo')!

	// Путь к картинке вычисляем относительно исходника, чтобы пример
	// работал независимо от текущего каталога запуска.
	img := os.join_path(os.dir(@FILE), '..', 'assets', 'icons', 'home.png')

	mut status := vgui.label('Колесо мыши — зум, перетаскивание — панорама')
	status.color = vgui.Color{180, 180, 180, 255}

	// ImageView с режимом масштабирования .fit (вписать целиком).
	mut iv := vgui.image_view_file(img)
	iv.set_mode(.fit)
	iv.border_color = vgui.Color{80, 80, 80, 255}

	mut b_in := vgui.button('Zoom +')
	b_in.on_click = fn [mut iv] () {
		iv.zoom_in()
	}
	mut b_out := vgui.button('Zoom -')
	b_out.on_click = fn [mut iv] () {
		iv.zoom_out()
	}
	mut b_reset := vgui.button('Reset')
	b_reset.style = .outline
	b_reset.on_click = fn [mut iv] () {
		iv.reset_zoom()
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(b_in, flex: 1)
	row.add(b_out, flex: 1)
	row.add(b_reset, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(iv, flex: 1)
	root.add(row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
