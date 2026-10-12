module main

// Пример 40. UI Scale: масштабирование всего интерфейса окна через win.set_ui_scale().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/40_ui_scale.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'UI Scale - demo')!

	mut status := vgui.label('Текущий масштаб: 1.0')
	status.color = vgui.Color{180, 180, 180, 255}
	status.font_size = 16

	// win.set_ui_scale(factor) масштабирует ВЕСЬ интерфейс окна:
	// шрифты, отступы, размеры виджетов. Это логический масштаб поверх
	// автоматического DPI-масштаба ОС. Удобно для доступности.
	mut sample := vgui.label('Образец текста для масштабирования')
	sample.valign = .middle

	mut sample_input := vgui.text_input('Поле тоже масштабируется...')

	mk_scale_btn := fn [mut win, mut status] (label string, scale f32) &vgui.Button {
		mut b := vgui.button(label)
		b.on_click = fn [mut win, mut status, scale, label] () {
			win.set_ui_scale(scale)
			status.text = 'Текущий масштаб: ${label}'
		}
		return b
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(mk_scale_btn('0.75', 0.75), flex: 1)
	row.add(mk_scale_btn('1.0', 1.0), flex: 1)
	row.add(mk_scale_btn('1.25', 1.25), flex: 1)
	row.add(mk_scale_btn('1.5', 1.5), flex: 1)
	row.add(mk_scale_btn('2.0', 2.0), flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(sample)
	root.add(sample_input)
	root.add(vgui.create_spacer(), flex: 1)
	root.add(vgui.label('Выберите масштаб интерфейса:'))
	root.add(row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Начальный масштаб
	win.set_ui_scale(1.0)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
