module vgui

// Неактивное состояние (enabled.v): флаг у каждого виджета, наследование от
// отключённого контейнера (ввод не доходит, Tab пропускает, фокус снимается),
// разметка disabled. Вид проверяют снапшоты *_disabled_* в snapshot_test.v.
//
// Запуск: v test enabled_test.v

@[heap]
struct EnCounter {
mut:
	n int
}

fn test_set_widget_enabled_covers_boxes_and_plain_widgets() {
	mut v := create_vbox_fill()
	mut wv := &Widget(v)
	assert widget_enabled(wv)
	assert set_widget_enabled(mut wv, false)
	assert !v.box.enabled
	assert !widget_enabled(wv)

	mut td := window_title_drag()
	mut wt := &Widget(td)
	assert set_widget_enabled(mut wt, false)
	assert !td.box.enabled

	// виджеты без ввода тоже несут флаг: единый set_enabled для всех
	mut sp := create_spacer()
	mut ws := &Widget(sp)
	assert set_widget_enabled(mut ws, false)
	assert !sp.enabled
	mut l := label('x')
	mut wl := &Widget(l)
	assert set_widget_enabled(mut wl, false)
	assert !l.enabled
}

fn test_disabled_container_blocks_clicks_to_children() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut c := &EnCounter{}
	mut b := button('OK')
	b.on_click = fn [mut c] () {
		c.n++
	}
	mut col := create_vbox_fill()
	col.add(b, flex: 1)
	t.add(col)
	t.click_widget(b)
	assert c.n == 1

	col.box.enabled = false
	t.redraw()
	t.click_widget(b)
	assert c.n == 1, 'клик прошёл сквозь отключённый контейнер'
	// собственный флаг ребёнка не тронут
	assert b.enabled

	col.box.enabled = true
	t.redraw()
	t.click_widget(b)
	assert c.n == 2
}

fn test_window_events_pass_disabled_container() {
	assert is_input_event(&GuiEvent{
		typ: .mouse_down
	})
	assert is_input_event(&GuiEvent{
		typ: .drop_file
	})
	assert !is_input_event(&GuiEvent{
		typ: .window_resize
	})
	assert !is_input_event(&GuiEvent{
		typ: .window_focus_lost
	})
}

fn test_tab_skips_widgets_of_disabled_container() {
	mut t := new_test_ui(width: 300, height: 120)!
	defer {
		t.close()
	}
	mut a := text_input('a')
	mut b := text_input('b')
	mut inner := create_vbox_fill()
	inner.add(b)
	mut col := create_vbox_fill()
	col.add(a)
	col.add(inner)
	t.add(col)

	// Tab обрабатывает виджет с фокусом - первый фокус кликом
	t.click_widget(a)
	assert t.win.ctx.focus.is_focused(a)
	t.key(sdl_k_tab, 0)
	assert t.win.ctx.focus.is_focused(b)

	// отключение контейнера снимает фокус с ребёнка уже на следующем кадре
	inner.box.enabled = false
	t.redraw()
	assert !t.win.ctx.focus.is_focused(b)
	assert !b.focused

	// клик по b не доходит; по Tab от a - снова a, b пропускается
	t.click_widget(b)
	assert !t.win.ctx.focus.is_focused(b)
	t.click_widget(a)
	t.key(sdl_k_tab, 0)
	assert t.win.ctx.focus.is_focused(a)

	inner.box.enabled = true
	t.redraw()
	t.key(sdl_k_tab, 0)
	assert t.win.ctx.focus.is_focused(b)
}

fn test_own_flag_blurs_focused_widget() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut a := text_input('a')
	mut col := create_vbox_fill()
	col.add(a)
	t.add(col)
	t.click_widget(a)
	assert a.focused
	a.enabled = false
	t.redraw()
	assert !a.focused
	assert !t.win.ctx.focus.is_focused(a)
}

fn test_disabled_depth_balanced_after_frame() {
	mut t := new_test_ui(width: 300, height: 200)!
	defer {
		t.close()
	}
	mut p := panel()
	p.enabled = false
	p.set_child(label('x'))
	mut col := create_vbox_fill()
	col.box.enabled = false
	col.add(p, flex: 1)
	t.add(col)
	t.redraw()
	assert t.win.ctx.disabled_depth == 0
}

fn test_markup_disabled_on_any_element() {
	mut ui := ui_parse('vbox disabled\n  label "a" #l disabled\n  hbox #h\n    button "b"\n',
		't')!
	root := ui.root
	if root is VBox {
		assert !root.box.enabled
	} else {
		assert false, 'корень не VBox'
	}
	l := ui.widget('l') or { panic('нет элемента') }
	assert !widget_enabled(l)
	h := ui.widget('h') or { panic('нет элемента') }
	assert widget_enabled(h)
}

// Пассивный холст (Canvas.passive) - не то же, что неактивный: рисуется как
// обычно, а щелчок отдаёт виджету под ним (раньше для этого ставили
// enabled = false, и холст теперь накрывался бы вуалью).
fn test_passive_canvas_lets_clicks_through() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut c := &EnCounter{}
	mut b := button('OK')
	b.on_click = fn [mut c] () {
		c.n++
	}
	mut cv := canvas(20, 10)
	mut st := stack()
	st.add(b)
	st.add(cv)
	t.add(st)
	t.redraw()
	t.click_widget(b)
	assert c.n == 0, 'активный холст сверху должен забирать щелчок'
	cv.passive = true
	t.redraw()
	t.click_widget(b)
	assert c.n == 1, 'щелчок не прошёл сквозь пассивный холст'
	assert cv.enabled
}
