module main

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
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'MarkdownView - demo')!

	mut status := vgui.label('Клик по ссылке откроет её в статусе')
	status.color = vgui.Color{180, 180, 180, 255}

	// MarkdownView в режиме просмотра.
	mut md := vgui.markdown_view_with_text(sample_md)
	md.on_link_click = fn [mut status] (url string) {
		status.text = 'Ссылка: ${url}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(md, flex: 1)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
