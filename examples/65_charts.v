module main

// Пример 65. Графики: Sparkline (sparkline.v) - компактный график последних значений, как в
// мониторах сетевого трафика, и Chart (chart.v) - диаграммы всех видов.
//
// Что показано:
//   - вверху - «монитор сети»: два Sparkline (приём и отдача) и общий на две серии; значения
//     идут из фонового потока через app.post (каждые 300 мс), график едет влево, шкала
//     подстраивается плавно; наведите мышь - линия и значения под курсором;
//   - вкладки Chart:
//       «Lines»     - линия и область, поток значений push с capacity (живой график загрузки CPU);
//       «Bars»      - столбцы рядом и стопкой (кнопка Stacked), кнопка Shuffle - новые данные
//                     с плавным переходом от старых;
//       «Histogram» - гистограмма 2000 нормально распределённых значений;
//       «Pie/Donut» - круговая и кольцевая диаграммы (наведение выдвигает сектор);
//       «Steps»     - ступенчатая линия и облако точек по числовой оси X;
//   - щелчок по пункту легенды прячет/показывает серию;
//   - стиль из CSS: вкладке «Bars» свои цвета серий через `chart.custom { series-1-color: ... }`.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/65_charts.v

import vgui
import rand
import math
import time

// Monitor - виджеты, которые обновляет фоновый поток (через app.post, в главном потоке).
@[heap]
struct Monitor {
mut:
	rx       &vgui.Sparkline
	tx       &vgui.Sparkline
	both     &vgui.Sparkline
	rx_label &vgui.Label
	tx_label &vgui.Label
	cpu      &vgui.Chart
}

// speed - подпись скорости: значения - в КБ/с.
fn speed(v f32) string {
	if v >= 1024 {
		return '${v / 1024:.1f} MB/s'
	}
	return '${v:.0f} KB/s'
}

// traffic - ФОНОВЫЙ поток: «измеряет» трафик и CPU (случайное блуждание) и отдаёт значения в
// главный поток. Виджеты здесь трогать нельзя - только через app.post.
fn traffic(app &vgui.App, mon &Monitor) {
	mut a := unsafe { app }
	mut m := unsafe { mon }
	mut down := f32(800)
	mut up := f32(120)
	mut cpu := f32(30)
	for {
		time.sleep(300 * time.millisecond)
		// случайное блуждание и редкие «всплески» загрузки
		down = f32(math.max(20, down + rand.f32_in_range(-250, 260) or { 0 }))
		if rand.intn(12) or { 1 } == 0 {
			down += 2500
		}
		down = f32(math.min(down, 6000))
		up = f32(math.max(5, math.min(900, up + rand.f32_in_range(-60, 62) or { 0 })))
		cpu = f32(math.max(2, math.min(98, cpu + rand.f32_in_range(-12, 12) or { 0 })))
		d, u, c := down, up, cpu
		a.post(fn [mut m, d, u, c] () {
			m.rx.push(0, d)
			m.tx.push(0, u)
			m.both.push_all([d, u])
			m.rx_label.text = 'Download  ${speed(d)}'
			m.tx_label.text = 'Upload  ${speed(u)}'
			m.cpu.push(0, c)
		})
	}
}

// normal - нормально распределённое значение (преобразование Бокса - Мюллера).
fn normal(mean f32, sd f32) f32 {
	u1 := math.max(rand.f64(), 1e-9)
	u2 := rand.f64()
	return mean + sd * f32(math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2))
}

// random_values - n случайных целых от lo до hi.
fn random_values(n int, lo int, hi int) []f32 {
	mut out := []f32{}
	for _ in 0 .. n {
		out << f32(rand.int_in_range(lo, hi) or { lo })
	}
	return out
}

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'Charts - Sparkline and Chart', width: 820, height: 640)!

	// CSS: свои цвета серий для диаграммы с классом .custom (вкладка Bars)
	ss := vgui.parse_stylesheet('
		chart.custom { series-1-color: #7c6cf0; series-2-color: #f0b429; bar-radius: 4; }
	', 'charts.css')!
	app.set_stylesheet(ss)

	// ── Монитор сети: Sparkline ──
	mut rx := vgui.sparkline(capacity: 80)
	rx.format = speed
	rx.add_series('Download', vgui.chart_auto_color)
	mut tx := vgui.sparkline(capacity: 80)
	tx.format = speed
	tx.add_series('Upload', vgui.chart_auto_color)
	// общий: две серии, сетка, рамка, подпись верха шкалы и последнего значения
	mut both := vgui.sparkline(capacity: 120)
	both.format = speed
	both.show_grid = true
	both.show_frame = true
	both.show_scale = true
	both.show_last = true
	both.add_series('Down', vgui.chart_auto_color)
	both.add_series('Up', vgui.chart_auto_color)

	mut rx_label := vgui.label('Download')
	mut tx_label := vgui.label('Upload')
	mut net := vgui.create_vbox_fill()
	net.set_spacing(6)
	net.set_padding(0)
	mut row1 := vgui.create_hbox_fill()
	row1.set_spacing(10)
	row1.add(rx_label, min: 150)
	row1.add(rx, flex: 1)
	mut row2 := vgui.create_hbox_fill()
	row2.set_spacing(10)
	row2.add(tx_label, min: 150)
	row2.add(tx, flex: 1)
	net.add(row1)
	net.add(row2)
	net.add(both, min: 80)

	// ── Lines: линия и область, поток push ──
	months := ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']
	mut lines := vgui.chart(title: 'Visitors', categories: months)
	lines.y_title = 'thousands'
	lines.add_series('Organic', .area, [f32(12), 15, 14, 19, 23, 26, 25, 29, 27, 31, 35, 38])
	lines.add_series('Ads', .line, [f32(5), 7, 9, 8, 11, 10, 13, 14, 12, 15, 16, 18])
	mut cpu := vgui.chart(title: 'CPU load, %')
	cpu.capacity = 60
	cpu.show_legend = false
	cpu.set_y_range(0, 100)
	cpu.format = fn (v f32) string {
		return '${v:.0f}%'
	}
	cpu.add_series('CPU', .area, []f32{})
	mut lines_tab := vgui.create_hbox_fill()
	lines_tab.set_spacing(8)
	lines_tab.add(lines, flex: 1)
	lines_tab.add(cpu, flex: 1)

	// ── Bars: рядом / стопкой, новые данные с переходом ──
	mut bars := vgui.chart(title: 'Sales by quarter', categories: ['Q1', 'Q2', 'Q3', 'Q4'])
	bars.css = vgui.CssTags{
		classes: ['custom']
	}
	bars.add_series('Hardware', .bar, [f32(32), 45, 38, 52])
	bars.add_series('Software', .bar, [f32(21), 28, 35, 41])
	bars.add_series('Services', .bar, [f32(12), 15, 19, 22])
	bars.on_click = fn [mut win] (s int, i int) {
		win.set_title('Charts - clicked series ${s}, point ${i}')
	}
	mut stacked := vgui.button('Stacked')
	stacked.on_click = fn [mut bars] () {
		bars.set_stacked(!bars.stacked)
	}
	mut shuffle := vgui.button('Shuffle')
	shuffle.on_click = fn [mut bars] () {
		for i in 0 .. bars.series_count() {
			bars.set_values(i, random_values(4, 10, 60))
		}
	}
	mut bar_buttons := vgui.create_hbox_fill()
	bar_buttons.set_spacing(8)
	bar_buttons.add(stacked)
	bar_buttons.add(shuffle)
	bar_buttons.add(vgui.label('Click a legend item to hide a series'))
	mut bars_tab := vgui.create_vbox_fill()
	bars_tab.set_spacing(8)
	bars_tab.add(bar_buttons)
	bars_tab.add(bars, flex: 1)

	// ── Histogram ──
	mut samples := []f32{}
	for _ in 0 .. 2000 {
		samples << normal(170, 9)
	}
	mut hist := vgui.chart(title: 'Height distribution, cm')
	hist.show_legend = false
	hist.x_title = 'height'
	hist.y_title = 'people'
	hist.add_histogram('People', samples, 24)

	// ── Pie / Donut ──
	share := ['Video', 'Web', 'Games', 'Updates', 'Other']
	mut pie := vgui.chart(mode: .pie, title: 'Traffic by app', categories: share)
	pie.legend_pos = .bottom
	pie.add_series('Share', .bar, [f32(48), 22, 14, 9, 7])
	mut donut := vgui.chart(mode: .donut, title: 'Disk usage', categories: ['System', 'Photos',
		'Video', 'Free'])
	donut.legend_pos = .right
	donut.center_text = '512 GB'
	donut.format = fn (v f32) string {
		return '${v:.0f} GB'
	}
	donut.add_series('Disk', .bar, [f32(64), 180, 150, 118])
	mut pie_tab := vgui.create_hbox_fill()
	pie_tab.set_spacing(8)
	pie_tab.add(pie, flex: 1)
	pie_tab.add(donut, flex: 1)

	// ── Steps и scatter: числовая ось X ──
	mut xs := []f32{}
	mut ys := []f32{}
	mut sx := []f32{}
	mut sy := []f32{}
	for i in 0 .. 20 {
		xs << f32(i) * 0.5
		ys << f32(rand.int_in_range(0, 5) or { 0 })
	}
	for _ in 0 .. 120 {
		x := rand.f32_in_range(0, 10) or { 0 }
		sx << x
		sy << x * 0.4 + normal(0, 0.6)
	}
	mut steps := vgui.chart(title: 'Steps and scatter')
	steps.x_format = fn (v f32) string {
		return '${v:.0f}s'
	}
	steps.add_xy_series('Queue length', .step, xs, ys)
	steps.add_xy_series('Latency', .scatter, sx, sy)

	mut tabs := vgui.tab_box()
	tabs.add_tab('Lines', lines_tab)
	tabs.add_tab('Bars', bars_tab)
	tabs.add_tab('Histogram', hist)
	tabs.add_tab('Pie / Donut', pie_tab)
	tabs.add_tab('Steps', steps)

	mut root := vgui.create_vbox_fill()
	root.set_padding(12)
	root.set_spacing(10)
	root.add(net)
	root.add(tabs, flex: 1)
	win.add_widget(root)
	app.add_window(win)

	mon := &Monitor{
		rx:       rx
		tx:       tx
		both:     both
		rx_label: rx_label
		tx_label: tx_label
		cpu:      cpu
	}
	spawn traffic(app, mon)
	app.run()
}
