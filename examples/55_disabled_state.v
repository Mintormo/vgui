module main

// Пример 55. Неактивное состояние (enabled): отдельный виджет, весь контейнер, пункт меню.
//
// Отключённый виджет не реагирует на ввод, выпадает из обхода по Tab и рисуется
// приглушённо. Отключённый контейнер гасит всё содержимое, но собственные флаги
// детей не трогает: включили контейнер - каждый ребёнок снова такой, каким был.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/55_disabled_state.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Disabled state - widgets, containers, menu items')!

	mut status := vgui.label('Toggle the checkboxes above')
	status.color = vgui.Color{180, 180, 180, 255}

	// Меню: неактивный пункт рисуется серым и не выбирается
	mut bar := vgui.menu_bar()
	mut m_undo := vgui.menu_action('Undo')
	m_undo.shortcut = 'Ctrl+Z'
	m_undo.enabled = false
	mut m_redo := vgui.menu_action('Redo')
	m_redo.shortcut = 'Ctrl+Y'
	m_redo.enabled = false
	mut m_edit := vgui.menu_action('Change')
	m_edit.on_click = fn [mut status, mut m_undo] () {
		// После правки «Отменить» становится доступным
		m_undo.enabled = true
		status.text = 'Edit -> Change: the "Undo" item is enabled'
	}
	m_undo.on_click = fn [mut status, mut m_undo] () {
		m_undo.enabled = false
		status.text = 'Edit -> Undo: the item is disabled again'
	}
	bar.add_menu('Edit', [m_edit, vgui.menu_separator(), m_undo, m_redo])

	// Форма с разными виджетами. Все они лежат в одной панели.
	mut name := vgui.text_input('Name')
	mut subscribe := vgui.checkbox('Subscribe to news')
	subscribe.set_checked(true)
	mut r_mail := vgui.radio_button('Email')
	r_mail.radio_group = 'channel'
	r_mail.set_selected(true)
	mut r_phone := vgui.radio_button('Phone')
	r_phone.radio_group = 'channel'
	mut radios := vgui.create_hbox_fill()
	radios.set_spacing(16)
	radios.add(r_mail)
	radios.add(r_phone)

	mut volume := vgui.slider_horizontal(0, 100, 40)
	mut count := vgui.spinbox()
	count.set_range(1, 10)
	count.set_value(3)
	mut lang := vgui.combo_box()
	lang.add_items(['Russian', 'English', 'Deutsch'])
	lang.set_selected(0)
	mut progress := vgui.progress_bar()
	progress.set_value(0.6)

	mut send := vgui.button('Send')
	send.on_click = fn [mut status] () {
		status.text = 'Form sent'
	}

	mut form := vgui.create_vbox_fill()
	form.set_padding(16)
	form.set_spacing(10)
	form.add(vgui.label('Questionnaire'))
	form.add(name)
	form.add(subscribe)
	form.add(radios)
	form.add(volume)
	form.add(count)
	form.add(lang)
	form.add(progress)
	form.add(send)

	mut panel := vgui.panel()
	panel.set_child(form)

	// Управление: переключатель гасит панель целиком, флажок - только кнопку.
	// Отключите кнопку, затем панель и включите панель обратно: кнопка
	// останется неактивной - её собственный флаг контейнер не менял.
	mut panel_on := vgui.toggle_switch('Panel enabled')
	panel_on.set_on(true)
	panel_on.on_change = fn [mut panel, mut status] (on bool) {
		panel.enabled = on
		status.text = if on { 'Panel is enabled' } else { 'The whole panel is disabled' }
	}
	mut send_off := vgui.checkbox('Disable only the "Send" button')
	send_off.on_change = fn [mut send, mut status] (off bool) {
		send.enabled = !off
		status.text = if off { 'Button disabled' } else { 'Button enabled' }
	}
	// Виджет можно создать сразу неактивным
	mut locked := vgui.checkbox('Unavailable option (enabled = false from the start)')
	locked.enabled = false

	mut controls := vgui.create_vbox_fill()
	controls.set_spacing(8)
	controls.add(panel_on)
	controls.add(send_off)
	controls.add(locked)

	mut body := vgui.create_vbox_fill()
	body.set_padding(16)
	body.set_spacing(12)
	body.add(controls)
	body.add(panel)
	body.add(status)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.add(bar)
	root.add(body)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
