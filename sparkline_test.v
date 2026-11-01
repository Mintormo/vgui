module vgui

// Тесты Sparkline (sparkline.v) и общих частей графиков (chart_common.v): кольцевой буфер,
// «красивая» шкала, подписи значений; push и вытеснение старых значений, наведение мышью
// настоящим путём событий; вид - снапшот (заливка градиентом, две серии, сетка, рамка).

fn test_chart_ring_push_wraps_and_keeps_order() {
	mut r := new_chart_ring(3)
	assert r.len() == 0 && r.last() == 0
	for v in [f32(1), 2, 3, 4, 5] {
		r.push(v)
	}
	// ёмкость 3: остались три последних, от старого к новому
	assert r.len() == 3
	assert r.to_array() == [f32(3), 4, 5]
	assert r.at(0) == 3 && r.last() == 5
	assert r.at(-1) == 0 && r.at(3) == 0, 'индекс вне диапазона - 0, не паника'
	bigger := r.resized(5)
	assert bigger.to_array() == [f32(3), 4, 5]
	smaller := r.resized(2)
	assert smaller.to_array() == [f32(4), 5]
	r.clear()
	assert r.len() == 0
}

fn test_chart_nice_range() {
	lo, hi, step := chart_nice_range(0, 87, 4)
	assert lo == 0 && hi == 100 && step == 20
	lo2, hi2, _ := chart_nice_range(-3, 7, 5)
	assert lo2 == -4 && hi2 == 8
	// вырожденный диапазон раздвигается и не уходит ниже нуля у неотрицательных данных
	lo3, hi3, _ := chart_nice_range(0, 0, 4)
	assert lo3 == 0 && hi3 >= 1
	lo4, hi4, _ := chart_nice_range(50, 50, 4)
	assert lo4 < 50 && hi4 > 50
}

fn test_chart_format_value() {
	assert chart_format_value(0) == '0'
	assert chart_format_value(42) == '42'
	assert chart_format_value(2.5) == '2.5'
	assert chart_format_value(0.125) == '0.13' || chart_format_value(0.125) == '0.12'
	assert chart_format_value(1500) == '1.5k'
	assert chart_format_value(2000000) == '2M'
	assert chart_format_value(-1200) == '-1.2k'
}

fn test_sparkline_push_creates_series_and_drops_old() {
	mut s := sparkline(capacity: 4)
	s.push(0, 1) // первая серия создаётся сама
	assert s.series_count() == 1
	for v in [f32(2), 3, 4, 5, 6] {
		s.push(0, v)
	}
	assert s.values(0) == [f32(3), 4, 5, 6]
	assert s.last_value(0) == 6
	s.push(5, 1) // несуществующая серия - без действия
	assert s.series_count() == 1
	tx := s.add_series('tx', chart_auto_color)
	s.push_all([f32(7), 70])
	assert s.values(tx) == [f32(70)] && s.last_value(0) == 7
	s.set_capacity(2)
	assert s.values(0) == [f32(6), 7]
	s.clear()
	assert s.values(0).len == 0 && s.series_count() == 2
}

fn test_sparkline_scale_auto_and_fixed() {
	mut s := sparkline()
	s.set_values(0, [f32(10), 37, 22])
	assert s.scale_target() == 40
	s.set_range(0, 100)
	assert s.scale_target() == 100
	s.set_range(0, 0) // снова автомасштаб
	assert s.scale_target() == 40
}

fn test_sparkline_hover_by_mouse() {
	mut t := new_test_ui(width: 220, height: 80)!
	mut s := sparkline(capacity: 10)
	s.set_values(0, [f32(1), 2, 3, 4, 5, 6, 7, 8, 9, 10])
	mut box := create_vbox_fill()
	box.set_padding(10)
	box.add(s, LayoutParams{ flex: 1 })
	t.add(box)
	t.frame()
	b := s.bounds
	// правый край - последний отсчёт, левый - самый старый
	t.move(b.x + b.w - 1, b.y + b.h * 0.5)
	assert s.hover_index == 9
	t.move(b.x + 1, b.y + b.h * 0.5)
	assert s.hover_index == 0
	t.move(b.x + b.w + 5, b.y - 5) // мимо виджета
	assert s.hover_index == -1
	t.close()
}

fn test_sparkline_snapshot() {
	mut t := new_test_ui(width: 200, height: 70, theme: dark_theme())!
	mut s := sparkline(capacity: 20)
	s.show_grid = true
	s.show_frame = true
	rx := s.add_series('rx', chart_auto_color)
	tx := s.add_series('tx', chart_auto_color)
	for i in 0 .. 20 {
		s.push(rx, f32(20 + (i * 37) % 60))
		s.push(tx, f32(5 + (i * 13) % 25))
	}
	mut box := create_vbox_fill()
	box.set_padding(8)
	box.add(s, LayoutParams{ flex: 1 })
	t.add(box)
	t.redraw()
	t.match_snapshot('testdata/snapshots/sparkline.png', SnapshotOpts{})!
	t.close()
}
