module main

// Пример 05. ToggleSwitch: переключатель on/off с колбэком on_change, отключённый и программно переключаемый.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/05_toggle_switch.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'ToggleSwitch - demo')!

	mut status := vgui.label('Состояние: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Переключатель с колбэком on_change
	mut ts1 := vgui.toggle_switch('Wi-Fi')
	ts1.on = true
	ts1.on_change = fn [mut status] (on bool) {
		status.text = 'Wi-Fi: ${on}'
		status.color = if on { vgui.Color{72, 199, 142, 255} } else { vgui.Color{244, 67, 54, 255} }
	}

	mut ts2 := vgui.toggle_switch('Bluetooth')
	ts2.on_change = fn [mut status] (on bool) {
		status.text = 'Bluetooth: ${on}'
	}

	// Отключённый переключатель
	mut ts3 := vgui.toggle_switch('Режим полёта (недоступен)')
	ts3.enabled = false

	// Программное переключение
	mut ts4 := vgui.toggle_switch('Управляемый кнопкой')
	mut btn := vgui.button('toggle()')
	btn.on_click = fn [mut ts4, mut status] () {
		ts4.toggle()
		status.text = 'is_on() = ${ts4.is_on()}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(ts1)
	root.add(ts2)
	root.add(ts3)
	root.add(ts4)
	root.add(btn)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
