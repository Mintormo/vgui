module main

import vgui

// UndoStack - стек отменяемых команд приложения. Каждое действие с
// «документом» (числом) кладётся в стек командой с парой redo/undo.
// Подряд идущие «+1» сливаются в один шаг (merge_id), «+1 трижды» - группа
// из трёх команд, отменяется одним шагом. Кнопки «Отменить»/«Повторить»
// включаются по on_change, звёздочка в заголовке - «не сохранено».

const merge_inc = 1

@[heap]
struct Doc {
mut:
	value int
}

// add_cmd - команда «прибавить n».
fn add_cmd(mut doc Doc, n int, text string, merge_id int) vgui.UndoCommand {
	redo_fn := fn [mut doc, n] () {
		doc.value += n
	}
	undo_fn := fn [mut doc, n] () {
		doc.value -= n
	}
	return vgui.UndoCommand{
		text:     text
		merge_id: merge_id
		redo:     redo_fn
		undo:     undo_fn
	}
}

// double_cmd - команда «умножить на 2»: запоминает значение до действия.
fn double_cmd(mut doc Doc) vgui.UndoCommand {
	before := doc.value
	redo_fn := fn [mut doc, before] () {
		doc.value = before * 2
	}
	undo_fn := fn [mut doc, before] () {
		doc.value = before
	}
	return vgui.UndoCommand{
		text: 'x2'
		redo: redo_fn
		undo: undo_fn
	}
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'UndoStack - demo')!
	mut stack := vgui.undo_stack(50)
	mut doc := &Doc{}

	mut value := vgui.label('')
	value.font_size = 28
	mut history := vgui.label('')

	mut btn_inc := vgui.button('+1')
	btn_inc.on_click = fn [mut stack, mut doc] () {
		stack.push(add_cmd(mut doc, 1, '+1', merge_inc))
	}
	mut btn_dec := vgui.button('-1')
	btn_dec.on_click = fn [mut stack, mut doc] () {
		stack.push(add_cmd(mut doc, -1, '-1', 0))
	}
	mut btn_double := vgui.button('x2')
	btn_double.on_click = fn [mut stack, mut doc] () {
		stack.push(double_cmd(mut doc))
	}
	mut btn_triple := vgui.button('+1 трижды')
	btn_triple.on_click = fn [mut stack, mut doc] () {
		stack.begin_group('+1 трижды')
		for _ in 0 .. 3 {
			stack.push(add_cmd(mut doc, 1, '+1', 0))
		}
		stack.end_group()
	}

	mut btn_undo := vgui.button('Отменить')
	btn_undo.on_click = fn [mut stack] () {
		stack.undo()
	}
	mut btn_redo := vgui.button('Повторить')
	btn_redo.on_click = fn [mut stack] () {
		stack.redo()
	}
	mut btn_save := vgui.button('Сохранить')
	btn_save.on_click = fn [mut stack] () {
		stack.set_clean()
	}

	refresh := fn [mut stack, mut doc, mut value, mut history, mut btn_undo, mut btn_redo, mut win] () {
		value.text = 'Значение: ${doc.value}'
		btn_undo.enabled = stack.can_undo()
		btn_redo.enabled = stack.can_redo()
		btn_undo.text = 'Отменить ${stack.undo_text()}'.trim_space()
		btn_redo.text = 'Повторить ${stack.redo_text()}'.trim_space()
		history.text = 'Шаг ${stack.index()} из ${stack.count()}'
		mark := if stack.is_clean() { '' } else { ' *' }
		win.set_title('UndoStack - demo${mark}')
		win.invalidate_all()
	}
	stack.on_change = refresh
	refresh()

	mut actions := vgui.create_hbox_fill()
	actions.set_spacing(8)
	actions.add(btn_inc)
	actions.add(btn_dec)
	actions.add(btn_double)
	actions.add(btn_triple)

	mut edit := vgui.create_hbox_fill()
	edit.set_spacing(8)
	edit.add(btn_undo)
	edit.add(btn_redo)
	edit.add(vgui.create_spacer())
	edit.add(btn_save)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(12)
	root.add(value)
	root.add(history)
	root.add(actions)
	root.add(edit)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}
