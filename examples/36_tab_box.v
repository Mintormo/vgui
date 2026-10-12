module main

// Пример 36. TabBox: вкладки, на каждой - свой виджет.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/36_tab_box.v

import vgui

fn make_page(text string) &vgui.VBox {
	mut box := vgui.create_vbox_fill()
	box.set_padding(12)
	box.set_spacing(8)
	mut l := vgui.label_wrap(text)
	box.add(l, flex: 1)
	return box
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'TabBox - demo')!

	mut status := vgui.label('Активная вкладка: 0')
	status.color = vgui.Color{180, 180, 180, 255}

	// Вкладки. add_tab(title, widget) — каждая вкладка содержит свой виджет.
	mut tabs := vgui.tab_box()

	mut form := make_page('Содержимое первой вкладки.')
	form.add(vgui.text_input('Поле ввода...'))

	mut info := make_page('Вторая вкладка с другим содержимым. Переключайтесь кликом по заголовкам сверху.')

	mut settings := make_page('Третья вкладка — настройки.')
	settings.add(vgui.checkbox('Опция A'))
	settings.add(vgui.checkbox('Опция B'))

	tabs.add_tab('Форма', form)
	tabs.add_tab('Инфо', info)
	tabs.add_tab('Настройки', settings)
	tabs.on_change = fn [mut status] (idx int, title string) {
		status.text = 'Активная вкладка: ${idx} (${title})'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(tabs, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
