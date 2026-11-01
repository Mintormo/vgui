module vgui

// Тесты Chart (chart.v): данные и шкалы (stacked, гистограмма, числовая ось), поток push с
// capacity, анимация перехода (значение идёт от старого к новому), щелчок по легенде прячет
// серию, наведение на столбец и сектор, on_click - настоящим путём событий; вид - снапшоты
// столбцов с линией и кольцевой диаграммы.

@[heap]
struct ChartClicks {
mut:
	items [][2]int
}

// new_chart_ui - окно с одной диаграммой на всё место (без анимации - значения сразу целевые).
fn new_chart_ui(mut c Chart, w int, h int, theme Theme) !&TestUi {
	mut t := new_test_ui(width: w, height: h, theme: theme)!
	mut box := create_vbox_fill()
	box.add(c, LayoutParams{ flex: 1 })
	t.add(box)
	t.redraw()
	return t
}

fn test_histogram_bins() {
	edges, counts := histogram_bins([f32(0), 1, 1, 2, 3, 4, 4, 4], 4)
	assert edges.len == 5 && counts.len == 4
	assert edges[0] == 0 && edges[4] == 4
	// максимум попадает в последний интервал
	assert counts == [f32(1), 2, 1, 4]
	e2, c2 := histogram_bins([]f32{}, 3)
	assert e2 == [f32(0), 1] && c2 == [f32(0)]
	_, c3 := histogram_bins([f32(5), 5, 5], 2)
	assert c3[0] + c3[1] == 3
}

fn test_chart_y_extent_stacked_and_bars_from_zero() {
	mut c := chart()
	c.animate = false
	c.add_series('a', .bar, [f32(3), 5, -2])
	c.add_series('b', .bar, [f32(4), 1, -1])
	lo, hi := c.y_extent(1)
	assert lo == -2 && hi == 5, 'рядом: максимум и минимум отдельных столбцов'
	c.set_stacked(true)
	lo2, hi2 := c.y_extent(1)
	assert lo2 == -3 && hi2 == 7, 'стопкой: суммы положительных и отрицательных'
	// линии сами по себе ноль не тянут
	mut l := chart()
	l.animate = false
	l.add_series('t', .line, [f32(10), 12, 11])
	llo, _ := l.y_extent(1)
	assert llo == 10
}

fn test_chart_x_extent_categories_and_numeric() {
	mut c := chart(categories: ['a', 'b', 'c', 'd'])
	c.animate = false
	c.add_series('l', .line, [f32(1), 2, 3, 4])
	lo, hi, _ := c.x_extent()
	assert lo == 0 && hi == 3
	c.set_series_kind(0, .bar)
	lo2, hi2, _ := c.x_extent()
	assert lo2 == -0.5 && hi2 == 3.5, 'у столбцов - полместа с краёв'
	mut h := chart()
	h.animate = false
	h.add_histogram('h', [f32(0), 1, 2, 3, 4, 5, 6, 7], 4)
	assert h.numeric_x()
	hlo, hhi, slot := h.x_extent()
	assert slot > 1.74 && slot < 1.76
	assert hlo > -0.01 && hlo < 0.01 && hhi > 6.99 && hhi < 7.01
}

fn test_chart_push_with_capacity() {
	mut c := chart()
	c.capacity = 3
	c.add_series('s', .line, []f32{})
	for v in [f32(1), 2, 3, 4] {
		c.push(0, v)
	}
	assert c.values(0) == [f32(2), 3, 4]
	// xy-серия: следующий X - на шаг дальше
	mut x := chart()
	x.add_xy_series('xy', .line, [f32(0), 10], [f32(5), 6])
	x.push(0, 7)
	assert x.series[0].xs == [f32(0), 10, 20]
}

fn test_chart_transition_moves_from_old_to_new() {
	mut c := chart()
	c.add_series('s', .bar, [f32(10)])
	// новая серия растёт от нуля
	assert c.series[0].shown(0, 0) == 0
	assert c.series[0].shown(0, 1) == 10
	c.progress.snap(1)
	c.set_values(0, [f32(20)])
	assert c.series[0].shown(0, 0) == 10
	assert c.series[0].shown(0, 0.5) == 15
	// без анимации - сразу цель
	c.animate = false
	c.set_values(0, [f32(30)])
	assert c.progress.value == 1 && c.series[0].shown(0, c.progress.value) == 30
}

fn test_chart_legend_click_toggles_series() {
	mut c := chart(title: 'T')
	c.animate = false
	c.add_series('alpha', .line, [f32(1), 2, 3])
	c.add_series('beta', .line, [f32(3), 2, 1])
	mut t := new_chart_ui(mut c, 360, 240, light_theme())!
	assert c.lay.legend.len == 2
	r := c.lay.legend[1].r
	t.click(r.x + r.w * 0.5, r.y + r.h * 0.5)
	assert !c.series_visible(1) && c.series_visible(0)
	t.frame()
	t.click(r.x + r.w * 0.5, r.y + r.h * 0.5)
	assert c.series_visible(1)
	t.close()
}

fn test_chart_hover_bar_and_on_click() {
	mut c := chart(categories: ['a', 'b', 'c'])
	c.animate = false
	c.show_legend = false
	c.add_series('s', .bar, [f32(5), 10, 5])
	mut log := &ChartClicks{}
	c.on_click = fn [mut log] (s int, i int) {
		log.items << [s, i]!
	}
	mut t := new_chart_ui(mut c, 300, 220, light_theme())!
	// середина столбца «b» - чуть выше нуля
	bx := c.sx(1)
	by := c.sy(1)
	t.move(bx, by)
	assert c.hover_index == 1 && c.hover_series == 0
	t.click(bx, by)
	assert log.items == [[0, 1]!]
	// над пустым местом выше столбца «a» у чистых столбцов плашки нет
	t.move(c.sx(0), c.sy(9))
	assert c.hover_index == -1
	t.close()
}

fn test_chart_pie_slice_hit() {
	mut c := chart(mode: .donut, categories: ['x', 'y'])
	c.animate = false
	c.show_legend = false
	c.add_series('s', .bar, [f32(1), 3])
	mut t := new_chart_ui(mut c, 240, 240, light_theme())!
	cx, cy, r := c.lay.cx, c.lay.cy, c.lay.radius
	// сектор 0 - четверть от «двенадцати часов» по часовой: справа-сверху
	t.move(cx + r * 0.55, cy - r * 0.6)
	assert c.hover_index == 0
	// слева - сектор 1 (три четверти)
	t.move(cx - r * 0.8, cy)
	assert c.hover_index == 1
	// в дырке кольца - ничего
	t.move(cx, cy)
	assert c.hover_index == -1
	c.set_series_visible(0, false)
	assert c.pie_total(1) == 3
	t.close()
}

fn test_chart_snapshot_bars_and_line() {
	mut c := chart(title: 'Sales', categories: ['Q1', 'Q2', 'Q3', 'Q4'])
	c.animate = false
	c.add_series('2025', .bar, [f32(12), 19, 15, 22])
	c.add_series('2026', .bar, [f32(14), 17, 21, 25])
	c.add_series('Plan', .line, [f32(13), 18, 19, 24])
	mut t := new_chart_ui(mut c, 360, 240, dark_theme())!
	t.match_snapshot('testdata/snapshots/chart_bars.png', SnapshotOpts{})!
	t.close()
}

fn test_chart_snapshot_donut() {
	mut c := chart(mode: .donut, categories: ['Video', 'Web', 'Games', 'Other'])
	c.animate = false
	c.legend_pos = .right
	c.add_series('Traffic', .bar, [f32(45), 25, 20, 10])
	mut t := new_chart_ui(mut c, 320, 200, light_theme())!
	t.match_snapshot('testdata/snapshots/chart_donut.png', SnapshotOpts{})!
	t.close()
}
