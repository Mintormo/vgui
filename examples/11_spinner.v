module main

// Пример 11. Spinner: индикатор загрузки, спиннер с текстом, управление через start()/stop().
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/11_spinner.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Spinner - demo')!

	mut status := vgui.label('Spinner крутится...')
	status.color = vgui.Color{180, 180, 180, 255}

	// Индикатор загрузки. Анимируется, пока spinning = true.
	mut sp_arc := vgui.spinner()

	// Спиннер с текстом рядом
	mut sp_text := vgui.spinner_with_text('Загрузка...')

	// Управление через start() / stop()
	mut sp_ctl := vgui.spinner()
	mut btn := vgui.button('start / stop')
	btn.on_click = fn [mut sp_ctl, mut status] () {
		if sp_ctl.is_spinning() {
			sp_ctl.stop()
			status.text = 'Остановлен'
		} else {
			sp_ctl.start()
			status.text = 'Запущен'
		}
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(16)
	row.add(sp_arc)
	row.add(sp_text, flex: 1)

	mut ctl_row := vgui.create_hbox_fill()
	ctl_row.set_spacing(12)
	ctl_row.add(sp_ctl)
	ctl_row.add(btn, flex: 1)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(row)
	root.add(ctl_row)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
