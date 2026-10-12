module main

// Пример 19. MarkdownView: отображение Markdown-текста.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v -enable-globals run examples/19_markdown_view.v

import vgui

const sample_md = '# MarkdownView

Виджет рендерит **Markdown** в форматированный текст.

## Возможности

- Заголовки разных уровней
- *Курсив*, **жирный**, `моноширинный`
- Списки и [ссылки](https://vlang.io)

> Цитаты тоже поддерживаются.

```v
fn main() {
    println("Блок кода")
}
```
'

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// Окно верхнего уровня. В заголовке - дефис-минус: глиф длинного тире не рендерится.
	mut win := vgui.create_window(title: 'MarkdownView - demo')!

	mut status := vgui.label('Клик по ссылке откроет её в статусе')
	status.color = vgui.Color{180, 180, 180, 255}

	// MarkdownView в режиме просмотра.
	mut md := vgui.markdown_view_with_text(sample_md)
	md.on_link_click = fn [mut status] (url string) {
		status.text = 'Ссылка: ${url}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(md, flex: 1)

	// Корень дерева виджетов окна; всё остальное вложено в него.
	win.add_widget(root)
	// Логический масштаб интерфейса (шрифты, отступы, размеры) поверх DPI-масштаба ОС.
	win.set_ui_scale(1.25)
	// Регистрируем окно в App; app.run() блокирует до закрытия всех окон.
	app.add_window(win)
	app.run()
}
