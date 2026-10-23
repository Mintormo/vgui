module main

// Пример 50. Область модальности: модальный диалог блокирует только своё окно, а не все окна приложения.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/50_modal_scope.v

import vgui

// Область модальности: модальный диалог блокирует только своё окно.
//
// Два независимых окна, у каждого своя кнопка «Открыть модальный диалог».
// Пока открыт диалог первого окна, само первое окно затемнено и не отвечает
// на клики, а второе окно работает как обычно: счётчик продолжает расти.
// Раньше модальный диалог гасил события всех окон приложения разом.
//
// Диалог, созданный БЕЗ родителя, по-прежнему модален для всего приложения -
// нижняя кнопка первого окна показывает и этот случай.

@[heap]
struct Counter {
mut:
	n     int
	label &vgui.Label = unsafe { nil }
	name  string
}

fn (mut c Counter) tick() {
	c.n++
	c.label.text = '${c.name}: ${c.n} clicks'
}

// open_dialog создаёт и показывает модальный диалог поверх parent.
// parent == nil - диалог без родителя, модальный для всего приложения.
fn open_dialog(parent &vgui.Window, mut app vgui.App, title string) {
	mut dlg := vgui.create_dialog(
		title:  title
		parent: unsafe { parent }
	) or { return }

	mut msg := vgui.label_wrap('While I am open, my window is blocked, ' +
		'but the other one is not. Try clicking there.')

	mut btn_row := vgui.create_hbox_fill()
	btn_row.set_spacing(10)
	btn_row.set_padding(0)
	btn_row.add(vgui.create_spacer(), flex: 1)
	mut close_btn := vgui.button('Close')
	close_btn.on_click = fn [mut dlg] () {
		dlg.close_with_result(0)
	}
	btn_row.add(close_btn)

	// Корневой вертикальный контейнер: растягивается на всё окно, дети идут сверху вниз.
	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(msg, flex: 1)
	root.add(btn_row)

	dlg.add_widget(root)
	app.add_dialog(dlg)
	dlg.show()
}

fn main() {
	// App - один на процесс: инициализирует SDL, шрифты и тему, владеет главным циклом.
	mut app := vgui.create_app()!

	mut win1 := vgui.create_window(title: 'Window 1')!
	mut win2 := vgui.create_window(title: 'Window 2')!

	mut c1 := &Counter{
		label: vgui.label('Window 1: 0 clicks')
		name:  'Window 1'
	}
	mut c2 := &Counter{
		label: vgui.label('Window 2: 0 clicks')
		name:  'Window 2'
	}

	mut tick1 := vgui.button('Count a click')
	tick1.on_click = fn [mut c1] () {
		c1.tick()
	}
	mut tick2 := vgui.button('Count a click')
	tick2.on_click = fn [mut c2] () {
		c2.tick()
	}

	mut open1 := vgui.button('Open a modal dialog')
	open1.on_click = fn [mut app, win1] () {
		open_dialog(win1, mut app, 'Window 1 dialog')
	}
	mut open2 := vgui.button('Open a modal dialog')
	open2.on_click = fn [mut app, win2] () {
		open_dialog(win2, mut app, 'Window 2 dialog')
	}

	// Диалог без родителя блокирует все окна - так вели себя все модальные
	// диалоги до появления областей модальности.
	mut open_global := vgui.button('Dialog without a parent (blocks everything)')
	open_global.on_click = fn [mut app] () {
		open_dialog(unsafe { nil }, mut app, 'Modal for the whole application')
	}

	mut root1 := vgui.create_vbox_fill()
	root1.set_padding(16)
	root1.set_spacing(10)
	root1.add(c1.label)
	root1.add(tick1)
	root1.add(open1)
	root1.add(vgui.create_spacer(), flex: 1)
	root1.add(open_global)

	mut root2 := vgui.create_vbox_fill()
	root2.set_padding(16)
	root2.set_spacing(10)
	root2.add(c2.label)
	root2.add(tick2)
	root2.add(open2)
	root2.add(vgui.create_spacer(), flex: 1)

	win1.add_widget(root1)
	win2.add_widget(root2)
	app.add_window(win1)
	app.add_window(win2)
	app.run()
}
