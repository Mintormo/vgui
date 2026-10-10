module main

import vgui

// Состояние «развёрнуто/восстановлено» для кнопки разворота.
struct WinState {
mut:
	maximized bool
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(
		title:      'Borderless - demo'
		min_width:  320
		min_height: 200
	)!

	// ── Свой заголовок ───────────────────────────────────
	// WindowTitleDrag — строка-контейнер (как HBox), которая делает окно
	// перетаскиваемым: зажав ЛКМ на пустой области, тащим окно; двойной клик
	// по пустому месту разворачивает/восстанавливает окно.
	//
	// ВНИМАНИЕ: рендерер шрифтов не рисует длинное тире и многие
	// декоративные глифы, поэтому в надписях используем простой ASCII.
	mut title := vgui.label('  Моё приложение')
	title.valign = .middle
	title.color = vgui.Color{230, 230, 235, 255}

	mut st := &WinState{}

	mut btn_min := vgui.button('_')
	btn_min.style = .outline
	btn_min.on_click = fn [mut win] () {
		win.minimize()
	}

	mut btn_max := vgui.button('[ ]')
	btn_max.style = .outline
	btn_max.on_click = fn [mut win, mut btn_max, mut st] () {
		if st.maximized {
			win.restore()
			btn_max.text = '[ ]'
		} else {
			win.maximize()
			btn_max.text = ']['
		}
		st.maximized = !st.maximized
	}

	mut btn_close := vgui.button('X')
	btn_close.style = .danger
	btn_close.on_click = fn [mut app] () {
		app.quit()
	}

	mut titlebar := vgui.window_title_drag()
	titlebar.set_bg(vgui.Color{38, 40, 48, 255})
	titlebar.set_padding(6)
	titlebar.set_spacing(4)
	titlebar.add(title, flex: 1.0) // растягивается, по нему таскаем окно
	titlebar.add(btn_min)
	titlebar.add(btn_max)
	titlebar.add(btn_close)

	// ── Тело окна ────────────────────────────────────────
	mut body_text := vgui.label_wrap('Это окно без системной рамки.\n\n' +
		'- Тащите за заголовок, чтобы переместить окно.\n' +
		'- Двойной клик по заголовку - развернуть/восстановить.\n' +
		'- Тяните за края, чтобы изменить размер.\n' +
		'- Кнопки справа сверху: свернуть, развернуть, закрыть.')
	body_text.valign = .top
	body_text.color = vgui.Color{200, 200, 205, 255}

	mut body := vgui.panel()
	body.set_child(body_text)
	body.pad = 18

	// ── Компоновка: заголовок сверху фиксированной высоты ──
	mut root := vgui.create_vbox_fill()
	root.add(titlebar)
	root.add(body, flex: 1.0)

	win.add_widget(root)
	// Убираем системную рамку и включаем resize за края.
	win.set_borderless(true)
	app.add_window(win)
	app.run()
}
