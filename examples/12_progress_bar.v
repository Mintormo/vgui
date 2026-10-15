module main

// Пример 12. ProgressBar: линейный, круговой и неопределённый прогресс.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/12_progress_bar.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ProgressBar - demo')!

	mut status := vgui.label('Прогресс: 40%')
	status.color = vgui.Color{180, 180, 180, 255}

	// Линейный прогресс-бар. Значение 0.0..1.0 через set_value().
	mut pb := vgui.progress_bar()
	pb.set_value(0.4)
	pb.show_text = true

	// Круговой прогресс
	mut pb_circ := vgui.progress_circular()
	pb_circ.set_value(0.7)
	pb_circ.show_text = true

	// Неопределённый (бесконечная анимация)
	mut pb_indet := vgui.progress_indeterminate()

	// Кнопки меняют значение линейного бара
	mut b_minus := vgui.button('-10%')
	b_minus.on_click = fn [mut pb, mut status] () {
		v := vgui.clamp_f32(pb.get_value() - 0.1, 0, 1)
		pb.set_value(v)
		status.text = 'Прогресс: ${v * 100:.0f}%'
	}
	mut b_plus := vgui.button('+10%')
	b_plus.on_click = fn [mut pb, mut status] () {
		v := vgui.clamp_f32(pb.get_value() + 0.1, 0, 1)
		pb.set_value(v)
		status.text = 'Прогресс: ${v * 100:.0f}%'
	}

	mut btn_row := vgui.create_hbox_fill()
	btn_row.set_spacing(6)
	btn_row.add(b_minus, flex: 1)
	btn_row.add(b_plus, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(vgui.label('Линейный:'))
	root.add(pb)
	root.add(btn_row)
	root.add(vgui.label('Круговой:'))
	root.add(pb_circ)
	root.add(vgui.label('Неопределённый:'))
	root.add(pb_indet)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
