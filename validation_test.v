module vgui

// Аудит 2.7: одинаковый вход — одинаковый результат, мусорный индекс не
// сохраняется.

fn test_list_box_set_selected_ignores_out_of_range() {
	mut lb := list_box()
	lb.add_items(['a', 'b'])
	lb.set_selected(1)
	assert lb.selected == 1
	lb.set_selected(9999)
	assert lb.selected == 1
	lb.set_selected(2)
	assert lb.selected == 1
	lb.set_selected(-42)
	assert lb.selected == 1
	lb.set_selected(-1)
	assert lb.selected == -1
}

fn test_slider_and_spinbox_agree_on_inverted_range() {
	mut s := slider_horizontal(0, 100, 0)
	s.set_range(10, 0)
	s.set_value(5)
	mut sb := spinbox()
	sb.set_range(10, 0)
	sb.set_value(5)
	assert s.min == 0 && s.max == 10
	assert sb.min == 0 && sb.max == 10
	assert s.value == 5
	assert sb.value == 5
}

fn test_inverted_range_clamps_current_value() {
	mut s := slider_horizontal(0, 100, 50)
	s.set_range(20, 10)
	assert s.value == 20
	mut sb := spinbox()
	sb.set_range(0, 100)
	sb.set_value(50)
	sb.set_range(20, 10)
	assert sb.value == 20
}

fn test_slider_factories_order_range() {
	h := slider_horizontal(10, 0, 5)
	assert h.min == 0 && h.max == 10 && h.value == 5
	v := slider_vertical(10, 0, 50)
	assert v.min == 0 && v.max == 10 && v.value == 10
}

struct SliderChangeLog {
mut:
	values []f32
}

// Slider.set_range, сдвинувший значение, зовёт on_change, как Spinbox.set_range
// (аудит 2026-10, 2.11); без сдвига - тихо.
fn test_slider_set_range_reports_shift() {
	mut s := slider()
	s.set_range(0, 100)
	s.set_value(50)
	mut log := &SliderChangeLog{}
	s.on_change = fn [mut log] (v f32) {
		log.values << v
	}
	s.set_range(0, 80) // 50 внутри - без события
	s.set_range(0, 30) // 50 -> 30
	assert log.values == [f32(30)]
}
