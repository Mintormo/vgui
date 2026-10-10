module vgui

// Текстовый ввод SDL - только когда нужен (Window.sync_text_input): кому
// он нужен по фокусу и по правке ячейки таблицы; холст с take_keys = false
// не забирает клавиши.

fn test_focus_wants_text() {
	mut fm := FocusManager{}
	assert !fm.wants_text() // фокуса нет
	mut ti := &TextInput{
		visible: true
		enabled: true
	}
	fm.focus_text_input(ti, 0)
	assert fm.wants_text()
	mut cv := canvas(4, 4)
	fm.focus_canvas(cv, 0)
	assert !fm.wants_text()
	mut lb := list_box()
	fm.focus_list_box(lb, 0)
	assert !fm.wants_text()
	// Дерево - только во время правки узла
	mut tv := tree_view()
	fm.focus_tree_view(tv, 0)
	assert !fm.wants_text()
	tv.editing = true
	assert fm.wants_text()
	fm.blur_current()
	assert !fm.wants_text()
}

fn test_window_wants_text_table_edit() {
	mut tbl := table_view()
	mut box := create_vbox_fill()
	box.add(tbl, flex: 1)
	mut w := Window{}
	w.widgets << box
	assert !w.wants_text_input()
	tbl.editing = true
	assert w.wants_text_input()
}

fn test_canvas_take_keys() {
	mut c := canvas(8, 8)
	c.on_input = fn (ev &CanvasInputEvent) {}
	c.focused = true
	app := &App{}
	ev := GuiEvent{
		typ:     .key_down
		keycode: int(`j`)
	}
	assert c.take_keys
	assert c.handle_event(&ev, app) // по умолчанию холст в фокусе забирает клавишу
	c.take_keys = false
	assert !c.handle_event(&ev, app)
	up := GuiEvent{
		typ:     .key_up
		keycode: int(`j`)
	}
	assert !c.handle_event(&up, app)
}
