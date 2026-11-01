module vgui

import math

// Файл sparkline.v: Sparkline - компактный график «последних N значений», как в мониторах
// сетевого трафика и загрузки процессора (Диспетчер задач, System Monitor).
//
// Устройство:
//   - у каждой серии свой кольцевой буфер ChartRing на capacity отсчётов; push(серия, v)
//     добавляет значение справа, самое старое уходит за левый край - график «едет» влево;
//   - по X - capacity мест на всю ширину, последнее значение всегда у правого края; пока буфер не
//     заполнен, линия начинается не с левого края (как в Диспетчере задач: видно, что истории
//     ещё мало);
//   - по Y - от min_value до верха шкалы: max_value > 0 - фиксированный верх (проценты: 100),
//     иначе автомасштаб - «красивое» число не меньше максимума видимых значений
//     (chart_nice_range). Шкала растёт сразу, а при smooth_scale уменьшается плавно (Anim);
//   - заливка под линией - вертикальный градиент от цвета серии к прозрачному
//     (fill_triangles_colored), поверх - линия, на последнем значении - точка (show_dot);
//   - наведение мышью: вертикальная линия на отсчёте под курсором и подпись значений серий
//     (если хватает высоты). Фокуса и клавиш нет.
//
// Внешний вид - тема и CSS (PROJECT.md, «Chart и Sparkline»): фон spark_bg (по умолчанию
// прозрачный), рамка chart_border (только show_frame), сетка chart_grid, подписи chart_text,
// линия наведения chart_hover, палитра серий chart_series_1..6, толщина spark_line_width,
// заливка spark_fill_alpha. В CSS - тип `sparkline`: `sparkline { background; border-color;
// grid-color; color; hover-color; line-width; fill-opacity; series-1-color ... series-6-color }`.
// Свой цвет серии (add_series(name, color) с a > 0) сильнее темы.
//
// Рисование - только примитивы RenderContext (PROJECT.md, «Бэкенд рисования»).
// Тег типа kind_sparkline - widget_kinds.v.

// SparkSeries - одна серия Sparkline: имя (для подписи под курсором), свой цвет (a=0 - цвет
// палитры темы по номеру серии) и буфер значений.
struct SparkSeries {
mut:
	name  string
	color Color
	ring  ChartRing
}

// Sparkline - компактный график последних значений. Поля настройки можно менять напрямую (после
// этого - Window.invalidate*, как у любого виджета) или через set_*.
@[heap]
pub struct Sparkline {
pub mut:
	type_tag int = kind_sparkline // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	visible  bool = true
	enabled  bool = true
	tooltip  string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd      &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	// fill - заливка под линией градиентом
	fill bool = true
	// show_dot - точка на последнем значении каждой серии
	show_dot bool = true
	// show_grid - три горизонтальные линии сетки (1/4, 1/2, 3/4 высоты)
	show_grid bool
	// show_frame - фон (eff_chart_bg, если spark_bg темы не задан) и рамка; без неё sparkline
	// прозрачен и сливается со строкой таблицы или статус-баром
	show_frame bool
	// show_scale - подпись верха шкалы в левом верхнем углу (сколько «в потолке» графика)
	show_scale bool
	// show_last - подпись последнего значения первой серии в правом верхнем углу
	show_last bool
	// hover_info - линия и подпись значений под курсором
	hover_info bool = true
	// min_value - низ шкалы (обычно 0); max_value - верх: > min_value - фиксированный, иначе
	// автомасштаб по видимым значениям
	min_value f32
	max_value f32
	// smooth_scale - верх автомасштаба уменьшается плавно, а не скачком (растёт - всегда сразу,
	// чтобы новое большое значение не упиралось в потолок)
	smooth_scale bool = true
	// line_width - толщина линии; 0 - из темы (eff_spark_line_width)
	line_width f32
	// format - подпись значения (под курсором, show_last, show_scale); nil - chart_format_value
	// и value_suffix
	format fn (f32) string = unsafe { nil }
	// value_suffix - единицы после подписи значения без своего format (' MB/s', '%'). Нужен и
	// биндингам: колбэк, возвращающий строку, через C-ABI не передать
	value_suffix string
mut:
	capacity int = 60
	series   []SparkSeries
	// hover_index - отсчёт под курсором (номер от самого старого), -1 - курсора нет
	hover_index int = -1
	scale_anim  Anim = Anim{
		role:   .custom
		tau_ms: 120
	}
	// scale_ready - верх шкалы уже выставлен хотя бы раз: первый кадр берёт его сразу, без
	// анимации «из нуля»
	scale_ready bool
}

// SparklineConfig - параметры sparkline(...): capacity - сколько последних значений помнит
// каждая серия; max_value > min_value - фиксированная шкала (например, 100 для процентов).
@[params]
pub struct SparklineConfig {
pub:
	capacity  int = 60
	min_value f32
	max_value f32
	fill      bool = true
}

// sparkline создаёт пустой Sparkline без серий: sparkline(capacity: 120, max_value: 100).
// Серии - add_series; для одного ряда значений можно сразу звать push(0, v): первая серия
// создаётся сама.
pub fn sparkline(cfg SparklineConfig) &Sparkline {
	return &Sparkline{
		capacity:  max_int(cfg.capacity, 2)
		min_value: cfg.min_value
		max_value: cfg.max_value
		fill:      cfg.fill
	}
}

// add_series добавляет серию и возвращает её номер (для push). color с a=0 - цвет палитры темы
// по номеру серии (eff_chart_series).
pub fn (mut s Sparkline) add_series(name string, color Color) int {
	widget_changed()
	s.series << SparkSeries{
		name:  name
		color: color
		ring:  new_chart_ring(s.capacity)
	}
	return s.series.len - 1
}

// series_count - сколько серий.
pub fn (s &Sparkline) series_count() int {
	return s.series.len
}

// push добавляет значение в конец серии idx. idx = 0 у Sparkline без серий создаёт первую
// серию сама (самый частый случай - один ряд); другой несуществующий номер - без действия.
// NaN/Inf сохраняются, но не рисуются (разрыв линии) и не влияют на шкалу.
pub fn (mut s Sparkline) push(idx int, v f32) {
	widget_changed()
	if idx == 0 && s.series.len == 0 {
		s.add_series('', chart_auto_color)
	}
	if idx < 0 || idx >= s.series.len {
		return
	}
	s.series[idx].ring.push(v)
}

// push_all - по одному значению в каждую серию разом (values[i] - серии i; лишние значения
// отбрасываются, недостающим сериям ничего не добавляется). Для монитора «приём/отдача»:
// оба отсчёта одного момента.
pub fn (mut s Sparkline) push_all(values []f32) {
	for i, v in values {
		if i >= s.series.len && !(i == 0 && s.series.len == 0) {
			break
		}
		s.push(i, v)
	}
}

// set_values заменяет значения серии idx целиком (берутся последние capacity).
pub fn (mut s Sparkline) set_values(idx int, values []f32) {
	widget_changed()
	if idx == 0 && s.series.len == 0 {
		s.add_series('', chart_auto_color)
	}
	if idx < 0 || idx >= s.series.len {
		return
	}
	s.series[idx].ring.clear()
	for v in values {
		s.series[idx].ring.push(v)
	}
}

// values - значения серии idx от самого старого к последнему (копия; нет серии - пусто).
pub fn (s &Sparkline) values(idx int) []f32 {
	if idx < 0 || idx >= s.series.len {
		return []f32{}
	}
	return s.series[idx].ring.to_array()
}

// last_value - последнее значение серии idx (нет серии или значений - 0).
pub fn (s &Sparkline) last_value(idx int) f32 {
	if idx < 0 || idx >= s.series.len {
		return 0
	}
	return s.series[idx].ring.last()
}

// clear стирает значения всех серий (сами серии остаются).
pub fn (mut s Sparkline) clear() {
	widget_changed()
	for mut ser in s.series {
		ser.ring.clear()
	}
	s.hover_index = -1
}

// capacity - сколько значений помнит каждая серия.
pub fn (s &Sparkline) capacity() int {
	return s.capacity
}

// set_capacity меняет ёмкость буферов (не меньше 2); последние значения сохраняются.
pub fn (mut s Sparkline) set_capacity(n int) {
	widget_changed()
	s.capacity = max_int(n, 2)
	for mut ser in s.series {
		ser.ring = ser.ring.resized(s.capacity)
	}
	s.hover_index = -1
}

// set_range - фиксированная шкала [lo, hi]; hi <= lo - автомасштаб с низом lo.
pub fn (mut s Sparkline) set_range(lo f32, hi f32) {
	widget_changed()
	s.min_value = lo
	s.max_value = hi
}

// set_series_color - свой цвет серии (a=0 - снова цвет палитры темы).
pub fn (mut s Sparkline) set_series_color(idx int, c Color) {
	widget_changed()
	if idx >= 0 && idx < s.series.len {
		s.series[idx].color = c
	}
}

// ─── Геометрия ─────────────────────────────────────────

// plot_rect - область линий: bounds без отступа 1 px сверху и снизу у рамки (show_frame), чтобы
// линия на максимуме и на нуле не сливалась с рамкой.
fn (s &Sparkline) plot_rect() Rect {
	pad := if s.show_frame { f32(2) } else { f32(1) }
	mut r := s.bounds.shrunk(pad)
	// точка последнего значения (show_dot) стоит на правом краю - место под её радиус, иначе
	// рамка срезает половину точки
	if s.show_dot {
		r.w -= 3
	}
	return r
}

// slot_dx - расстояние по X между соседними отсчётами: capacity мест на всю ширину.
fn (s &Sparkline) slot_dx(pr Rect) f32 {
	return pr.w / f32(max_int(s.capacity - 1, 1))
}

// sample_x - экранный X отсчёта i серии с count значениями: последний - у правого края.
fn (s &Sparkline) sample_x(pr Rect, i int, count int) f32 {
	return pr.x + pr.w - f32(count - 1 - i) * s.slot_dx(pr)
}

// longest - число значений в самой длинной серии (по ней отсчитывается наведение).
fn (s &Sparkline) longest() int {
	mut n := 0
	for ser in s.series {
		n = max_int(n, ser.ring.len())
	}
	return n
}

// data_max - максимум конечных значений всех серий (нет значений - min_value).
fn (s &Sparkline) data_max() f32 {
	mut m := s.min_value
	for ser in s.series {
		for i in 0 .. ser.ring.len() {
			v := ser.ring.at(i)
			if chart_is_finite(v) && v > m {
				m = v
			}
		}
	}
	return m
}

// scale_target - верх шкалы, к которому идёт график: фиксированный max_value или «красивое»
// число над максимумом данных (4 деления).
fn (s &Sparkline) scale_target() f32 {
	if s.max_value > s.min_value {
		return s.max_value
	}
	_, hi, _ := chart_nice_range(s.min_value, s.data_max(), 4)
	return hi
}

// value_y - экранный Y значения v при верхе шкалы top (значение за шкалой прижимается к краю).
fn (s &Sparkline) value_y(pr Rect, v f32, top f32) f32 {
	span := top - s.min_value
	t := if span > 0 { clamp_f32((v - s.min_value) / span, 0, 1) } else { f32(0) }
	return pr.y + pr.h - t * pr.h
}

// hover_at - номер отсчёта (от самого старого самой длинной серии) под X курсора: ближайшее
// место сетки отсчётов; левее начала данных - -1.
fn (s &Sparkline) hover_at(x f32) int {
	n := s.longest()
	if n == 0 {
		return -1
	}
	pr := s.plot_rect()
	dx := s.slot_dx(pr)
	// сколько мест от правого края (0 - последний отсчёт)
	back := int(math.round(f64((pr.x + pr.w - x) / dx)))
	i := n - 1 - back
	return if i >= 0 && i < n { i } else { -1 }
}

// fmt - подпись значения: свой format или chart_format_value.
fn (s &Sparkline) fmt(v f32) string {
	return if isnil(s.format) { chart_format_value(v) + s.value_suffix } else { s.format(v) }
}

// series_color - действующий цвет серии i: свой или палитры темы.
fn (s &Sparkline) series_color(i int, ctx &RenderContext) Color {
	c := s.series[i].color
	return if c.a > 0 { c } else { ctx.theme.eff_chart_series(i) }
}

// ─── Рисование ─────────────────────────────────────────

pub fn (mut s Sparkline) draw(mut ctx RenderContext) {
	if !s.visible || s.bounds.w < 2 || s.bounds.h < 2 {
		return
	}
	en := ctx.is_enabled(s.enabled)
	// Шаг 1. Верх шкалы. Сразу (без анимации): первый кадр, smooth_scale = false и РОСТ шкалы -
	// значение, вышедшее за верх, не должно упираться в потолок, пока шкала догоняет (так было на
	// старте: шкала 0..1 без данных ползла к тысячам). Плавно - только уменьшение шкалы, когда
	// всплеск ушёл за левый край. Пока анимация идёт - кадр только своего прямоугольника
	target := s.scale_target()
	if !s.scale_ready || !s.smooth_scale || target > s.scale_anim.value {
		s.scale_anim.snap(target)
		s.scale_ready = true
	} else {
		// epsilon - в долях шкалы: «прилипнуть» к цели, когда разница меньше 0.2% её высоты
		s.scale_anim.epsilon = max_f32(abs_f32(target - s.min_value) * 0.002, 1e-6)
		if s.scale_anim.update(target, ctx) {
			ctx.mark_anim_rect('sparkline', s.bounds)
		}
	}
	top := s.scale_anim.value
	pr := s.plot_rect()

	// Шаг 2. Фон и рамка
	bg := ctx.theme.eff_spark_bg()
	if bg.a > 0 {
		ctx.fill_rect(s.bounds, bg)
	} else if s.show_frame {
		ctx.fill_rect(s.bounds, ctx.theme.eff_chart_bg())
	}
	if s.show_frame {
		ctx.draw_rect(s.bounds, ctx.theme.eff_chart_border())
	}
	ctx.push_clip(s.bounds)
	if s.show_grid {
		grid := ctx.theme.eff_chart_grid()
		for k in 1 .. 4 {
			gy := pr.y + pr.h * f32(k) / 4
			ctx.draw_line(pr.x, gy, pr.x + pr.w, gy, grid)
		}
	}

	// Шаг 3. Серии: сначала все заливки (чтобы заливка второй серии не закрыла линию первой),
	// потом линии и точки
	lw := if s.line_width > 0 { s.line_width } else { ctx.theme.eff_spark_line_width() }
	fill_a := ctx.theme.eff_spark_fill_alpha()
	base_y := pr.y + pr.h
	mut lines := [][][]Vec2{}
	for i, ser in s.series {
		mut c := s.series_color(i, ctx)
		if !en {
			c = ctx.disabled_color(c)
		}
		runs := s.series_runs(ser, pr, top)
		lines << runs
		if s.fill {
			for run in runs {
				tri, cols := chart_area_triangles(run, base_y, pr.y, base_y, c, fill_a)
				ctx.fill_triangles_colored(tri, cols)
			}
		}
	}
	for i, runs in lines {
		mut c := s.series_color(i, ctx)
		if !en {
			c = ctx.disabled_color(c)
		}
		for run in runs {
			if run.len == 1 {
				// одиночное значение между разрывами - точка, иначе его не видно
				ctx.fill_circle(run[0].x, run[0].y, lw, c)
			}
			ctx.draw_polyline(run, c, lw)
		}
		ser := s.series[i]
		if s.show_dot && ser.ring.len() > 0 && chart_is_finite(ser.ring.last()) {
			lx := s.sample_x(pr, ser.ring.len() - 1, ser.ring.len())
			ly := s.value_y(pr, ser.ring.last(), top)
			ctx.fill_circle(lx, ly, lw + 1.5, c)
		}
	}

	// Шаг 4. Подписи и наведение
	s.draw_labels(mut ctx, pr, top, en)
	if en && s.hover_info && s.hover_index >= 0 {
		s.draw_hover(mut ctx, pr, top)
	}
	ctx.pop_clip()
}

// series_runs - ломаные серии на экране: значения NaN/Inf разрывают линию, поэтому серия - это
// несколько отрезков подряд идущих конечных значений.
fn (s &Sparkline) series_runs(ser SparkSeries, pr Rect, top f32) [][]Vec2 {
	n := ser.ring.len()
	mut runs := [][]Vec2{}
	mut cur := []Vec2{}
	for i in 0 .. n {
		v := ser.ring.at(i)
		if !chart_is_finite(v) {
			if cur.len > 0 {
				runs << cur
				cur = []Vec2{}
			}
			continue
		}
		cur << Vec2{s.sample_x(pr, i, n), s.value_y(pr, v, top)}
	}
	if cur.len > 0 {
		runs << cur
	}
	return runs
}

// draw_labels - подписи верха шкалы (слева сверху) и последнего значения (справа сверху), если
// включены и по высоте помещается строка.
fn (s &Sparkline) draw_labels(mut ctx RenderContext, pr Rect, top f32, en bool) {
	if !s.show_scale && !s.show_last {
		return
	}
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	if fh + 2 > s.bounds.h {
		return
	}
	tc := if en { ctx.theme.eff_chart_text() } else { ctx.theme.text_disabled }
	if s.show_scale {
		ctx.draw_text_with_font(s.fmt(top), pr.x + 3, pr.y + 1, tc, font)
	}
	if s.show_last && s.series.len > 0 && s.series[0].ring.len() > 0 {
		txt := s.fmt(s.series[0].ring.last())
		tw := ctx.measure_text_with_font(txt, font).x
		ctx.draw_text_with_font(txt, pr.x + pr.w - tw - 3, pr.y + 1, s.series_color(0, ctx),
			font)
	}
}

// draw_hover - вертикальная линия на отсчёте под курсором, точки серий на ней и плашка
// значений («имя: значение» по сериям) у верхнего края - с той стороны линии, где есть место.
fn (s &Sparkline) draw_hover(mut ctx RenderContext, pr Rect, top f32) {
	n := s.longest()
	if s.hover_index >= n {
		return
	}
	hx := s.sample_x(pr, s.hover_index, n)
	ctx.draw_line(hx, s.bounds.y, hx, s.bounds.y + s.bounds.h, ctx.theme.eff_chart_hover())
	// Точки серий. Серии короче самой длинной выровнены по правому краю: отсчёт под курсором у
	// них - с тем же отступом от конца
	mut parts := []string{}
	mut colors := []Color{}
	for i, ser in s.series {
		j := s.hover_index - (n - ser.ring.len())
		if j < 0 {
			continue
		}
		v := ser.ring.at(j)
		if !chart_is_finite(v) {
			continue
		}
		c := s.series_color(i, ctx)
		ctx.fill_circle(hx, s.value_y(pr, v, top), 3, c)
		parts << if ser.name != '' { '${ser.name}: ${s.fmt(v)}' } else { s.fmt(v) }
		colors << c
	}
	if parts.len == 0 {
		return
	}
	// Плашка: строки в столбик; нет места по высоте - не рисуется (крошечный sparkline в строке
	// таблицы показывает только линию и точки)
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	box_h := f32(parts.len) * fh + 6
	if box_h > s.bounds.h {
		return
	}
	mut box_w := f32(0)
	for p in parts {
		box_w = max_f32(box_w, ctx.measure_text_with_font(p, font).x)
	}
	box_w += 10
	mut bx := hx + 6
	if bx + box_w > s.bounds.x + s.bounds.w {
		bx = hx - 6 - box_w
	}
	bx = max_f32(bx, s.bounds.x)
	by := s.bounds.y + 2
	ctx.fill_rounded_rect(Rect{bx, by, box_w, box_h}, ctx.theme.eff_chart_tip_bg().with_alpha(230),
		4)
	for k, p in parts {
		ctx.draw_text_with_font(p, bx + 5, by + 3 + f32(k) * fh, colors[k], font)
	}
}

// ─── События ───────────────────────────────────────────

pub fn (mut s Sparkline) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible {
		return false
	}
	if !s.enabled && is_input_event(event) {
		s.set_hover(-1)
		return false
	}
	match event.typ {
		.mouse_move {
			if s.hover_info && s.bounds.contains(event.mouse_x, event.mouse_y) {
				s.set_hover(s.hover_at(event.mouse_x))
			} else {
				s.set_hover(-1)
			}
		}
		.mouse_leave {
			s.set_hover(-1)
		}
		else {}
	}
	// Событие не поглощается: sparkline только показывает, щелчок по нему - щелчок по строке
	// таблицы или панели под ним
	return false
}

// set_hover - сменить отсчёт под курсором; перерисовка - только при изменении.
fn (mut s Sparkline) set_hover(i int) {
	if i != s.hover_index {
		s.hover_index = i
		widget_changed()
	}
}
