module main

// Пример 06. Slider: горизонтальный и вертикальный ползунки, отображение значения, шаг и свои цвета.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/06_slider.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Slider - demo')!

	mut status := vgui.label('Значение: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Базовый горизонтальный слайдер: (min, max, value)
	mut s_basic := vgui.slider_horizontal(0, 100, 50)
	s_basic.on_change = fn [mut status] (v f32) {
		status.text = 'Громкость: ${v:.0f}'
	}

	// С отображением значения и шагом
	mut s_step := vgui.slider_horizontal(0, 10, 5)
	s_step.step = 1
	s_step.show_value = true
	s_step.show_ticks = true
	s_step.on_change = fn [mut status] (v f32) {
		status.text = 'Уровень: ${v:.0f}'
	}

	// Свои цвета трека/заливки/ползунка
	mut s_color := vgui.slider_horizontal(0, 100, 30)
	s_color.show_value = true
	s_color.fill_color = vgui.Color{255, 120, 0, 255}
	s_color.thumb_color = vgui.Color{255, 220, 0, 255}

	// Вертикальный слайдер
	mut s_vert := vgui.slider_vertical(0, 100, 70)
	s_vert.show_value = true

	mut left := vgui.create_vbox_fill()
	left.set_spacing(8)
	left.add(status)
	left.add(vgui.hseparator())
	left.add(vgui.label('Базовый 0-100:'))
	left.add(s_basic)
	left.add(vgui.label('Шаг=1 + тики:'))
	left.add(s_step)
	left.add(vgui.label('Свои цвета:'))
	left.add(s_color)

	mut right := vgui.create_vbox_fill()
	right.set_spacing(4)
	right.add(vgui.label('Верт.:'))
	right.add(s_vert, flex: 1)

	mut cols := vgui.create_hbox_fill()
	cols.set_spacing(12)
	cols.add(left, flex: 1)
	cols.add(right)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.add(cols, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
