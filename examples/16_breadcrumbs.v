module main

// Пример 16. Breadcrumbs: хлебные крошки - цепочка навигации с колбэком on_click(index, text).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/16_breadcrumbs.v

import vgui

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'Breadcrumbs - demo')!

	mut status := vgui.label('Кликните по сегменту пути')
	status.color = vgui.Color{180, 180, 180, 255}

	// Хлебные крошки: цепочка навигации. on_click(index, text).
	mut bc := vgui.breadcrumbs_with_items(['Главная', 'Документы', 'Проекты',
		'vgui'])
	bc.on_click = fn [mut status, mut bc] (idx int, text string) {
		status.text = 'Переход: ${text} [${idx}]'
		status.color = vgui.Color{66, 165, 245, 255}
		// Обрезаем путь до выбранного сегмента
		items := bc.get_items()[..idx + 1]
		bc.set_items(items)
	}

	// Кнопка добавляет новый уровень
	mut btn := vgui.button('Войти глубже')
	btn.on_click = fn [mut bc, mut status] () {
		bc.push('Подпапка ${bc.count()}')
		status.text = 'Добавлен уровень'
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(status)
	root.add(vgui.hseparator())
	root.add(bc)
	root.add(btn)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
