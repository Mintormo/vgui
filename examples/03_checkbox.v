module main

// Пример 03. CheckBox: колбэк on_change, начальное состояние, отключённый чекбокс и программное управление (set_checked / toggle / is_checked).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/03_checkbox.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'CheckBox - demo')!

	mut status := vgui.label('Состояние: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Обычный чекбокс с колбэком on_change
	mut cb1 := vgui.checkbox('Включить уведомления')
	cb1.on_change = fn [mut status] (checked bool) {
		status.text = 'Уведомления: ${checked}'
		status.color = if checked {
			vgui.Color{72, 199, 142, 255}
		} else {
			vgui.Color{244, 67, 54, 255}
		}
	}

	// Отмечен по умолчанию
	mut cb2 := vgui.checkbox('Отмечен по умолчанию')
	cb2.checked = true

	// Отключённый чекбокс
	mut cb3 := vgui.checkbox('Недоступен (enabled = false)')
	cb3.enabled = false

	// Программное управление: set_checked / toggle / is_checked
	mut cb4 := vgui.checkbox('Управляемый кнопками')

	mut b_toggle := vgui.button('toggle()')
	b_toggle.on_click = fn [mut cb4, mut status] () {
		cb4.toggle()
		status.text = 'is_checked() = ${cb4.is_checked()}'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(10)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(cb1)
	root.add(cb2)
	root.add(cb3)
	root.add(cb4)
	root.add(b_toggle)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
