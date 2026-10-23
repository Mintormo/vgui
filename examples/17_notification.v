module main

// Пример 17. NotificationManager: всплывающие уведомления поверх окна.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/17_notification.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Notification - demo')!

	// NotificationManager рисует всплывающие уведомления поверх окна
	// и добавляется напрямую в окно через win.add_widget(nm).
	mut nm := vgui.notification_manager_at(.bottom_right)
	nm.notif_width = 300

	mut b_info := vgui.button('Info')
	b_info.on_click = fn [mut nm] () {
		nm.show_info('Information message')
	}

	mut b_ok := vgui.button('Success')
	b_ok.style = .success
	b_ok.on_click = fn [mut nm] () {
		nm.show_success('Operation completed successfully')
	}

	mut b_warn := vgui.button('Warning')
	b_warn.on_click = fn [mut nm] () {
		nm.show_warning('Warning: check the data')
	}

	mut b_err := vgui.button('Error')
	b_err.style = .danger
	b_err.on_click = fn [mut nm] () {
		nm.show_error('An error occurred')
	}

	mut b_title := vgui.button('With title')
	b_title.style = .outline
	b_title.on_click = fn [mut nm] () {
		nm.show_with_title(.info, 'Title', 'Notification text with a title')
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(vgui.label('Press a button to show a notification:'))
	root.add(vgui.hseparator())
	for b in [b_info, b_ok, b_warn, b_err, b_title] {
		root.add(b)
	}

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	win.add_widget(nm)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
