module vgui

// Множественный выбор ListBox (multi_select): Ctrl/Shift+щелчок,
// Shift+стрелки, сброс обычным щелчком, set_selected и clear.

fn lb_sel_list(n int) &ListBox {
	mut lb := list_box()
	for i in 0 .. n {
		lb.add_item('item ${i}')
	}
	lb.multi_select = true
	return lb
}

fn lb_ev(mods u16) &GuiEvent {
	return &GuiEvent{
		mod_keys: mods
	}
}

fn test_list_box_ctrl_click() {
	mut lb := lb_sel_list(6)
	lb.click_select(1, lb_ev(0))
	assert lb.get_selection() == [1]
	lb.click_select(3, lb_ev(sdl_kmod_ctrl))
	lb.click_select(4, lb_ev(sdl_kmod_ctrl))
	assert lb.get_selection() == [1, 3, 4]
	assert lb.selected == 4
	assert lb.is_row_selected(3) && !lb.is_row_selected(2)
	// Повторный Ctrl+щелчок убирает строку
	lb.click_select(3, lb_ev(sdl_kmod_ctrl))
	assert lb.get_selection() == [1, 4]
	// Обычный щелчок - снова одна строка
	lb.click_select(2, lb_ev(0))
	assert lb.get_selection() == [2]
}

fn test_list_box_shift_range() {
	mut lb := lb_sel_list(8)
	lb.click_select(5, lb_ev(0))
	lb.click_select(2, lb_ev(sdl_kmod_shift))
	assert lb.get_selection() == [2, 3, 4, 5]
	assert lb.selected == 2
	// Якорь тот же: диапазон пересчитывается от 5
	lb.click_select(7, lb_ev(sdl_kmod_shift))
	assert lb.get_selection() == [5, 6, 7]
	// Ctrl+Shift добавляет диапазон к выбранным
	lb.click_select(0, lb_ev(sdl_kmod_ctrl))
	lb.click_select(1, lb_ev(sdl_kmod_ctrl | sdl_kmod_shift))
	assert lb.get_selection() == [0, 1, 5, 6, 7]
}

fn test_list_box_shift_keys() {
	mut lb := lb_sel_list(5)
	lb.click_select(1, lb_ev(0))
	lb.selected = 3
	lb.key_select(lb_ev(sdl_kmod_shift))
	assert lb.get_selection() == [1, 2, 3]
	lb.selected = 4
	lb.key_select(lb_ev(0))
	assert lb.get_selection() == [4]
}

fn test_list_box_multi_off_and_reset() {
	// Без multi_select модификаторы ничего не добавляют
	mut lb := lb_sel_list(4)
	lb.multi_select = false
	lb.click_select(1, lb_ev(0))
	lb.click_select(2, lb_ev(sdl_kmod_ctrl))
	assert lb.get_selection() == [2]
	// set_selection / set_selected / clear
	lb.multi_select = true
	lb.set_selection([3, 0, 3, 9])
	assert lb.get_selection() == [0, 3]
	assert lb.selected == 0
	lb.set_selected(2)
	assert lb.get_selection() == [2]
	lb.set_selection([1, 2])
	lb.clear()
	assert lb.get_selection() == []int{}
	assert !lb.is_row_selected(1)
}
