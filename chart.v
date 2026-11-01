module vgui

import math

// Файл chart.v: Chart - диаграммы «для отчёта»: линии, области, столбцы, ступени, точки,
// гистограмма, круговая и кольцевая диаграммы. В отличие от PlotView (plot_view.v - график
// функций с панорамой и зумом, «для исследования») Chart показывает готовый набор данных
// целиком: шкалы подбираются сами, есть заголовок, легенда, подписи осей, плашка значений под
// курсором и плавная анимация смены данных.
//
// Модель данных:
//   - серия - имя, вид (ChartKind: line, area, bar, step, scatter), цвет (a=0 - палитра темы по
//     номеру серии) и значения Y. X точки i - xs[i], если серия задана парами (add_xy_series),
//     иначе номер i: тогда ось X - категории, подписи - categories[i] (или номер с 1);
//   - stacked - столбцы складываются в один столбец на категорию (положительные вверх,
//     отрицательные вниз), области - друг на друга; без stacked столбцы серий стоят рядом;
//   - гистограмма (add_histogram) - столбцы по интервалам значений вплотную друг к другу; на
//     оси X - числовая шкала, а не категории;
//   - mode = .pie / .donut - круговая диаграмма по первой серии: доля значения i - сектор,
//     подписи - categories, цвета - палитра по номеру сектора.
//
// Шкалы. Y - от минимума до максимума видимых значений (у столбцов и областей - всегда с нулём),
// округлённые до «красивых» делений (chart_nice_range); set_y_range задаёт свои границы. X у
// категорий - по месту на категорию (у столбцов - с полуместом по краям), у числовых данных -
// от минимума до максимума xs.
//
// Анимация (animate). Новые данные (add_series, set_values, set_xy) не появляются скачком:
// каждое значение плавно идёт от того, что было на экране, к новому (у новой серии - от нуля),
// сектора круговой диаграммы - так же. Поток (push) анимацию не запускает: значения просто
// добавляются в конец, а самые старые при capacity > 0 вытесняются.
//
// Мышь: наведение - вертикальная линия на ближайшей точке X и плашка значений всех серий в ней
// (у круговой - выдвинутый сектор и его доля); щелчок по пункту легенды прячет/показывает серию
// (у круговой - сектор); щелчок по данным - on_click(серия, номер точки). Фокуса и клавиш нет.
//
// Внешний вид - тема и CSS (PROJECT.md, «Chart и Sparkline»): фон chart_bg, рамка chart_border,
// сетка chart_grid, оси chart_axis, подписи и легенда chart_text, заголовок chart_title, линия
// наведения chart_hover, плашка chart_tip_bg / chart_tip_text, палитра chart_series_1..6, толщина
// линий chart_line_width, заливка областей chart_fill_alpha, скругление столбцов chart_bar_radius.
// Не заданные поля chart_* берутся из plot_* (как у PlotView), затем из общих цветов темы. В CSS -
// тип `chart`: `chart { background; border-color; grid-color; axis-color; color; title-color;
// hover-color; tip-background; tip-color; line-width; fill-opacity; bar-radius;
// series-1-color ... series-6-color }`.
//
// Рисование - только примитивы RenderContext (PROJECT.md, «Бэкенд рисования»).
// Тег типа kind_chart - widget_kinds.v.

// ChartKind - вид серии декартова графика.
pub enum ChartKind {
	line    // ломаная через точки
	area    // ломаная с градиентной заливкой до нуля (или до предыдущей серии при stacked)
	bar     // столбцы от нуля
	step    // ступенчатая линия: значение держится до следующей точки
	scatter // только точки, без линий
}

// ChartMode - вид диаграммы целиком: декартова (оси и серии) или круговая по первой серии.
pub enum ChartMode {
	cartesian
	pie
	donut
}

// ChartLegendPos - где легенда: над графиком (под заголовком), под графиком или справа.
pub enum ChartLegendPos {
	top
	bottom
	right
}

// ChartSeries - серия Chart (приватна: создаётся add_*_series, меняется по номеру).
// values - целевые значения; from - значения на экране в момент начала перехода (анимация
// смены данных), длина from всегда равна длине values (sync_from).
struct ChartSeries {
mut:
	name    string
	kind    ChartKind
	color   Color
	xs      []f32 // пусто - X точки i равен i (категории)
	values  []f32
	from    []f32
	visible bool = true
	// gap_free - столбцы вплотную (гистограмма): промежутка bar_gap между ними нет
	gap_free bool
}

// shown - значение точки i, которое сейчас на экране: от from[i] к values[i] на долю перехода p.
// NaN/Inf в цели - как есть (точка не рисуется); в начале перехода - сразу цель.
fn (s &ChartSeries) shown(i int, p f32) f32 {
	to := s.values[i]
	if p >= 1 || i >= s.from.len {
		return to
	}
	f := s.from[i]
	if !chart_is_finite(to) || !chart_is_finite(f) {
		return to
	}
	return f + (to - f) * p
}

// x_of - X точки i в координатах данных.
fn (s &ChartSeries) x_of(i int) f32 {
	return if i < s.xs.len { s.xs[i] } else { f32(i) }
}

// ChartItemRect - прямоугольник, по которому щелчок попадает в элемент (пункт легенды):
// index - номер серии (декартова) или сектора (круговая).
struct ChartItemRect {
	r     Rect
	index int
}

// ChartLayout - разметка последнего кадра: где область данных и пункты легенды. Считается в
// draw (нужны шрифты), ею пользуются события: они всегда приходят после хотя бы одного кадра.
struct ChartLayout {
mut:
	plot   Rect
	legend []ChartItemRect
	// X-шкала последнего кадра: видимый диапазон данных и шаг места категории
	x_lo f32
	x_hi f32
	slot f32 = 1
	y_lo f32
	y_hi f32 = 1
	// y_step - шаг делений Y: тот же, по которому округлены y_lo/y_hi (иначе верхнее деление
	// не совпадёт с верхом шкалы и останется без подписи)
	y_step f32 = 1
	// pie: центр и радиус круга
	cx f32
	cy f32
	radius f32
}

// Chart - диаграмма. Поля настройки можно менять напрямую (после - Window.invalidate*) или
// через set_*.
@[heap]
pub struct Chart {
pub mut:
	type_tag int = kind_chart // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	visible  bool = true
	enabled  bool = true
	tooltip  string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd      &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	mode     ChartMode
	title    string
	// x_title / y_title - подписи осей (под осью X и повёрнутая слева от оси Y)
	x_title string
	y_title string
	// categories - подписи точек по X (и секторов круговой); пусто - номера с 1
	categories []string
	stacked    bool
	show_grid  bool = true
	show_legend bool = true
	legend_pos  ChartLegendPos = .top
	hover_info  bool           = true
	// animate - плавный переход к новым данным
	animate bool = true
	// show_markers - точки на вершинах линий и областей: .auto - если между точками хватает места
	show_markers ChartMarkers
	// bar_gap - доля места категории между группами столбцов (0..0.9)
	bar_gap f32 = 0.25
	// donut_ratio - внутренний радиус кольца в долях внешнего (mode = .donut)
	donut_ratio f32 = 0.58
	// center_text - текст в центре кольца; пусто - сумма видимых секторов
	center_text string
	// capacity - сколько последних точек держит push (0 - без ограничения)
	capacity int
	// format - подпись значения Y (шкала, плашка); nil - chart_format_value / деления шкалы
	format fn (f32) string = unsafe { nil }
	// value_suffix - единицы после значения в плашке и в центре кольца без своего format
	// (' GB', '%'); шкала - без них, чтобы подписи делений оставались узкими. Нужен и
	// биндингам: колбэк, возвращающий строку, через C-ABI не передать
	value_suffix string
	// x_format - подпись числового X (шкала, заголовок плашки); nil - деления шкалы
	x_format fn (f32) string = unsafe { nil }
	// on_click(серия, точка) - щелчок по данным: столбец или ближайшая точка (серия -1 - линии,
	// номер - ближайший X); у круговой - сектор (серия 0)
	on_click fn (int, int) = unsafe { nil }
mut:
	series []ChartSeries
	// y_fixed - границы Y заданы set_y_range
	y_fixed bool
	y_min   f32
	y_max   f32
	// pie_hidden[i] - сектор i спрятан щелчком по легенде
	pie_hidden []bool
	// hover_index - точка (категория) под курсором, -1 - нет; hover_series - столбец/сектор
	// под курсором (-1 - не над столбцом)
	hover_index  int = -1
	hover_series int = -1
	hover_x      f32
	hover_y      f32
	progress     Anim = Anim{
		mode:        .tween
		duration_ms: 450
		easing:      .out_cubic
		value:       1
		goal:        1
	}
	lay ChartLayout
}

// ChartMarkers - когда рисовать точки на вершинах линий.
pub enum ChartMarkers {
	auto   // если между соседними точками не меньше 14 px
	always
	never
}

// ChartConfig - параметры chart(...).
@[params]
pub struct ChartConfig {
pub:
	mode       ChartMode
	title      string
	categories []string
	stacked    bool
}

// chart создаёт пустую диаграмму: chart(title: 'Продажи', categories: ['Янв', 'Фев']).
pub fn chart(cfg ChartConfig) &Chart {
	return &Chart{
		mode:       cfg.mode
		title:      cfg.title
		categories: cfg.categories.clone()
		stacked:    cfg.stacked
	}
}

// ─── Данные ────────────────────────────────────────────

// add_series добавляет серию значений по категориям (X = номер точки) и возвращает её номер.
// Цвет - из палитры темы по номеру серии (свой - add_series_colored / set_series_color).
pub fn (mut c Chart) add_series(name string, kind ChartKind, values []f32) int {
	return c.add_series_colored(name, kind, values, chart_auto_color)
}

// add_series_colored - как add_series, со своим цветом (a=0 - палитра темы).
pub fn (mut c Chart) add_series_colored(name string, kind ChartKind, values []f32, color Color) int {
	widget_changed()
	c.begin_transition()
	c.series << ChartSeries{
		name:   name
		kind:   kind
		color:  color
		values: values.clone()
		// новая серия вырастает от нуля
		from: []f32{len: values.len}
	}
	c.finish_if_static()
	return c.series.len - 1
}

// add_xy_series добавляет серию пар (xs[i], ys[i]) - числовая ось X (длина - меньшая из двух).
pub fn (mut c Chart) add_xy_series(name string, kind ChartKind, xs []f32, ys []f32) int {
	n := min_int(xs.len, ys.len)
	idx := c.add_series(name, kind, ys[..n])
	c.series[idx].xs = xs[..n].clone()
	return idx
}

// add_histogram строит гистограмму значений data на bins интервалов (столбцы вплотную, ось X -
// значения). Возвращает номер серии. Интервалы - histogram_bins.
pub fn (mut c Chart) add_histogram(name string, data []f32, bins int) int {
	edges, counts := histogram_bins(data, bins)
	mut centers := []f32{cap: counts.len}
	for i in 0 .. counts.len {
		centers << (edges[i] + edges[i + 1]) * 0.5
	}
	idx := c.add_xy_series(name, .bar, centers, counts)
	c.series[idx].gap_free = true
	return idx
}

// histogram_bins раскладывает значения data по bins равным интервалам от минимума до максимума
// (NaN/Inf пропускаются). Возвращает границы интервалов (bins + 1 штук) и число значений в
// каждом (bins штук). Максимум попадает в последний интервал. Пустые данные - один интервал
// [0, 1] с нулём; все значения равны - интервалы вокруг этого значения шириной 1.
pub fn histogram_bins(data []f32, bins int) ([]f32, []f32) {
	n := max_int(bins, 1)
	mut lo := f32(0)
	mut hi := f32(0)
	mut first := true
	for v in data {
		if !chart_is_finite(v) {
			continue
		}
		if first {
			lo, hi = v, v
			first = false
		} else {
			lo = min_f32(lo, v)
			hi = max_f32(hi, v)
		}
	}
	if first {
		return [f32(0), 1], [f32(0)]
	}
	if hi - lo < 1e-12 {
		lo -= 0.5
		hi += 0.5
	}
	width := (hi - lo) / f32(n)
	mut edges := []f32{len: n + 1}
	for i in 0 .. n + 1 {
		edges[i] = lo + width * f32(i)
	}
	mut counts := []f32{len: n}
	for v in data {
		if !chart_is_finite(v) {
			continue
		}
		bin := clamp_int(int((v - lo) / width), 0, n - 1)
		counts[bin] += 1
	}
	return edges, counts
}

// set_values заменяет значения серии idx (с анимацией перехода от текущих).
pub fn (mut c Chart) set_values(idx int, values []f32) {
	if idx < 0 || idx >= c.series.len {
		return
	}
	widget_changed()
	c.begin_transition()
	c.series[idx].values = values.clone()
	c.series[idx].sync_from()
	if c.series[idx].xs.len > 0 {
		c.series[idx].xs = c.series[idx].xs[..min_int(c.series[idx].xs.len, values.len)]
	}
	c.finish_if_static()
}

// set_xy заменяет пары (xs, ys) серии idx (с анимацией перехода по Y).
pub fn (mut c Chart) set_xy(idx int, xs []f32, ys []f32) {
	if idx < 0 || idx >= c.series.len {
		return
	}
	n := min_int(xs.len, ys.len)
	c.set_values(idx, ys[..n])
	c.series[idx].xs = xs[..n].clone()
}

// push добавляет точку в конец серии idx без анимации (поток значений); при capacity > 0 самые
// старые точки вытесняются. Категории (если заданы) не сдвигаются - для потока их обычно нет.
pub fn (mut c Chart) push(idx int, v f32) {
	if idx < 0 || idx >= c.series.len {
		return
	}
	widget_changed()
	mut s := &c.series[idx]
	s.sync_from()
	s.values << v
	s.from << v
	if s.xs.len > 0 {
		// у числовой серии следующий X - на шаг дальше последнего
		step := if s.xs.len > 1 { s.xs[s.xs.len - 1] - s.xs[s.xs.len - 2] } else { f32(1) }
		s.xs << s.xs[s.xs.len - 1] + step
	}
	if c.capacity > 0 && s.values.len > c.capacity {
		drop := s.values.len - c.capacity
		s.values = s.values[drop..].clone()
		s.from = s.from[drop..].clone()
		if s.xs.len > 0 {
			s.xs = s.xs[drop..].clone()
		}
	}
}

// sync_from - выровнять длину from по values: лишнее отрезать, недостающее - сразу цель
// (новые точки появляются на месте, без «вырастания»).
fn (mut s ChartSeries) sync_from() {
	if s.from.len > s.values.len {
		s.from = s.from[..s.values.len].clone()
	}
	for s.from.len < s.values.len {
		s.from << s.values[s.from.len]
	}
}

// begin_transition - начало перехода к новым данным: то, что сейчас на экране, становится
// стартом (from) каждой серии, доля перехода - с нуля. Зовётся ДО замены данных.
fn (mut c Chart) begin_transition() {
	p := c.progress.value
	for mut s in c.series {
		mut now := []f32{len: s.values.len}
		for i in 0 .. s.values.len {
			now[i] = s.shown(i, p)
		}
		s.from = now
	}
	c.progress.snap(0)
	c.progress.set_target(1)
}

// finish_if_static - без анимации переход сразу закончен.
fn (mut c Chart) finish_if_static() {
	if !c.animate {
		c.progress.snap(1)
	}
}

// series_count - сколько серий.
pub fn (c &Chart) series_count() int {
	return c.series.len
}

// values - целевые значения серии idx (копия; нет серии - пусто).
pub fn (c &Chart) values(idx int) []f32 {
	if idx < 0 || idx >= c.series.len {
		return []f32{}
	}
	return c.series[idx].values.clone()
}

// clear удаляет все серии.
pub fn (mut c Chart) clear() {
	widget_changed()
	c.series.clear()
	c.pie_hidden.clear()
	c.hover_index = -1
	c.hover_series = -1
}

// set_categories - подписи точек по X (и секторов круговой).
pub fn (mut c Chart) set_categories(labels []string) {
	widget_changed()
	c.categories = labels.clone()
}

// set_series_color - свой цвет серии (a=0 - палитра темы).
pub fn (mut c Chart) set_series_color(idx int, color Color) {
	widget_changed()
	if idx >= 0 && idx < c.series.len {
		c.series[idx].color = color
	}
}

// set_series_kind - сменить вид серии (line, area, bar, step, scatter).
pub fn (mut c Chart) set_series_kind(idx int, kind ChartKind) {
	widget_changed()
	if idx >= 0 && idx < c.series.len {
		c.series[idx].kind = kind
	}
}

// set_series_visible - показать/спрятать серию (то же делает щелчок по легенде). У круговой
// диаграммы idx - номер сектора.
pub fn (mut c Chart) set_series_visible(idx int, on bool) {
	widget_changed()
	if c.mode != .cartesian {
		c.ensure_pie_hidden(idx + 1)
		if idx >= 0 {
			c.pie_hidden[idx] = !on
		}
		return
	}
	if idx >= 0 && idx < c.series.len {
		c.series[idx].visible = on
	}
}

// series_visible - видна ли серия (у круговой - сектор) idx.
pub fn (c &Chart) series_visible(idx int) bool {
	if c.mode != .cartesian {
		return !(idx >= 0 && idx < c.pie_hidden.len && c.pie_hidden[idx])
	}
	return idx >= 0 && idx < c.series.len && c.series[idx].visible
}

// set_y_range - свои границы оси Y (hi <= lo - снова автоматически).
pub fn (mut c Chart) set_y_range(lo f32, hi f32) {
	widget_changed()
	c.y_fixed = hi > lo
	c.y_min = lo
	c.y_max = hi
}

// set_mode - декартова / круговая / кольцевая.
pub fn (mut c Chart) set_mode(m ChartMode) {
	widget_changed()
	c.mode = m
	c.hover_index = -1
	c.hover_series = -1
}

// set_title - заголовок над графиком ("" - без заголовка).
pub fn (mut c Chart) set_title(t string) {
	widget_changed()
	c.title = t
}

// set_stacked - столбцы и области складываются.
pub fn (mut c Chart) set_stacked(on bool) {
	widget_changed()
	c.stacked = on
}

fn (mut c Chart) ensure_pie_hidden(n int) {
	for c.pie_hidden.len < n {
		c.pie_hidden << false
	}
}

// ─── Цвета и подписи ───────────────────────────────────

// series_color - действующий цвет серии i: свой или палитры темы.
fn (c &Chart) series_color(i int, ctx &RenderContext) Color {
	col := c.series[i].color
	return if col.a > 0 { col } else { ctx.theme.eff_chart_series(i) }
}

// fmt_y - подпись значения Y: свой format или короткая подпись chart_format_value.
fn (c &Chart) fmt_y(v f32) string {
	return if isnil(c.format) { chart_format_value(v) + c.value_suffix } else { c.format(v) }
}

// category_label - подпись категории i: categories[i] или номер с 1.
fn (c &Chart) category_label(i int) string {
	return if i >= 0 && i < c.categories.len { c.categories[i] } else { '${i + 1}' }
}

// numeric_x - ось X числовая: хотя бы у одной серии заданы xs.
fn (c &Chart) numeric_x() bool {
	for s in c.series {
		if s.xs.len > 0 {
			return true
		}
	}
	return false
}

// point_count - число точек самой длинной серии (не меньше числа категорий у категорий).
fn (c &Chart) point_count() int {
	mut n := if c.numeric_x() { 0 } else { c.categories.len }
	for s in c.series {
		n = max_int(n, s.values.len)
	}
	return n
}

// has_kind - есть ли видимая серия вида k.
fn (c &Chart) has_kind(k ChartKind) bool {
	for s in c.series {
		if s.visible && s.kind == k {
			return true
		}
	}
	return false
}

// visible_bars - номера видимых серий-столбцов по порядку (раскладка столбцов в группе).
fn (c &Chart) visible_bars() []int {
	mut out := []int{}
	for i, s in c.series {
		if s.visible && s.kind == .bar {
			out << i
		}
	}
	return out
}

// ─── Шкалы ─────────────────────────────────────────────

// y_extent - мин/макс значений Y на экране с учётом stacked (сумма столбцов и областей) и нуля у
// столбцов и областей. p - доля перехода анимации.
fn (c &Chart) y_extent(p f32) (f32, f32) {
	mut lo := f32(math.max_f32)
	mut hi := f32(-math.max_f32)
	n := c.point_count()
	mut pos := []f32{len: n} // стопки столбцов вверх
	mut neg := []f32{len: n} // и вниз
	mut area := []f32{len: n} // стопка областей
	for s in c.series {
		if !s.visible {
			continue
		}
		for i in 0 .. s.values.len {
			v := s.shown(i, p)
			if !chart_is_finite(v) {
				continue
			}
			mut top := v
			mut bottom := v
			if c.stacked && s.kind == .bar && i < n {
				if v >= 0 {
					pos[i] += v
					top = pos[i]
				} else {
					neg[i] += v
					bottom = neg[i]
				}
			} else if c.stacked && s.kind == .area && i < n {
				area[i] += v
				top = area[i]
			}
			lo = min_f32(lo, min_f32(top, bottom))
			hi = max_f32(hi, max_f32(top, bottom))
		}
	}
	if lo > hi {
		return 0, 1
	}
	if c.has_kind(.bar) || c.has_kind(.area) {
		lo = min_f32(lo, 0)
		hi = max_f32(hi, 0)
	}
	return lo, hi
}

// x_extent - видимый диапазон X и ширина места одной точки (slot). Категории: точки на 0..n-1, у
// столбцов - по полуместа с краёв (столбцы не обрезаются рамкой). Числовая ось: от минимума до
// максимума xs, slot - наименьший шаг между соседними точками (ширина столбца гистограммы).
fn (c &Chart) x_extent() (f32, f32, f32) {
	bars := c.has_kind(.bar)
	if !c.numeric_x() {
		mut n := c.point_count()
		// поток с ограничением (capacity): ось сразу на все capacity мест - иначе каждая новая
		// точка растягивала ось и сжимала всю линию по горизонтали
		if c.capacity > 0 {
			n = max_int(n, c.capacity)
		}
		if n <= 1 || bars {
			return -0.5, f32(max_int(n, 1)) - 0.5, 1
		}
		return 0, f32(n - 1), 1
	}
	mut lo := f32(math.max_f32)
	mut hi := f32(-math.max_f32)
	mut slot := f32(math.max_f32)
	for s in c.series {
		if !s.visible {
			continue
		}
		for i in 0 .. s.values.len {
			x := s.x_of(i)
			lo = min_f32(lo, x)
			hi = max_f32(hi, x)
			if i > 0 {
				d := abs_f32(x - s.x_of(i - 1))
				if d > 1e-12 {
					slot = min_f32(slot, d)
				}
			}
		}
	}
	if lo > hi {
		return 0, 1, 1
	}
	if slot == f32(math.max_f32) {
		slot = 1
	}
	if bars {
		lo -= slot * 0.5
		hi += slot * 0.5
	}
	if hi - lo < 1e-12 {
		lo -= 0.5
		hi += 0.5
	}
	return lo, hi, slot
}

// sx / sy - экранные координаты значения данных по последней разметке.
fn (c &Chart) sx(x f32) f32 {
	l := c.lay
	span := l.x_hi - l.x_lo
	return l.plot.x + (x - l.x_lo) / span * l.plot.w
}

fn (c &Chart) sy(y f32) f32 {
	l := c.lay
	span := l.y_hi - l.y_lo
	return l.plot.y + l.plot.h - (y - l.y_lo) / span * l.plot.h
}

// ─── Разметка ──────────────────────────────────────────

// legend_entries - подписи и цвета пунктов легенды: серии с именем (декартова) или сектора.
// Третье значение - номер серии/сектора (для щелчка) и признак «спрятан».
fn (c &Chart) legend_entries(ctx &RenderContext) ([]string, []Color, []int, []bool) {
	mut names := []string{}
	mut colors := []Color{}
	mut ids := []int{}
	mut hidden := []bool{}
	if c.mode == .cartesian {
		for i, s in c.series {
			if s.name == '' {
				continue
			}
			names << s.name
			colors << c.series_color(i, ctx)
			ids << i
			hidden << !s.visible
		}
	} else if c.series.len > 0 {
		for i in 0 .. c.series[0].values.len {
			names << c.category_label(i)
			colors << c.slice_color(i, ctx)
			ids << i
			hidden << !c.series_visible(i)
		}
	}
	return names, colors, ids, hidden
}

// slice_color - цвет сектора i круговой диаграммы: палитра по номеру сектора. Свой цвет первой
// серии - только у первого сектора не берётся: сектора различаются цветом, один цвет на всех
// сделал бы круг сплошным.
fn (c &Chart) slice_color(i int, ctx &RenderContext) Color {
	return ctx.theme.eff_chart_series(i)
}

// layout_frame - раскладка кадра: заголовок, легенда, подписи осей и область данных. Ширина
// подписей Y зависит от шкалы, поэтому шкала Y считается здесь же. Результат - в c.lay.
fn (mut c Chart) layout_frame(mut ctx RenderContext) {
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	mut area := c.bounds.shrunk(8)
	// Заголовок - полужирным, сверху по центру
	if c.title != '' {
		tf := ctx.get_font(.bold, 0)
		area.y += ctx.font_height_of(tf) + 6
		area.h -= ctx.font_height_of(tf) + 6
	}
	// Легенда: пункты «квадрат + имя» в ряд (сверху/снизу, с переносом) или столбиком справа
	c.lay.legend.clear()
	names, _, ids, _ := c.legend_entries(ctx)
	if c.show_legend && names.len > 0 {
		sq := fh * 0.7
		if c.legend_pos == .right {
			mut lw := f32(0)
			for nm in names {
				lw = max_f32(lw, ctx.measure_text_with_font(nm, font).x)
			}
			lw += sq + 6
			lx := area.x + area.w - lw
			for k, _ in names {
				c.lay.legend << ChartItemRect{Rect{lx, area.y + f32(k) * (fh + 4), lw, fh}, ids[k]}
			}
			area.w -= lw + 12
		} else {
			// ряды пунктов по ширине области
			mut rows := [][]int{}
			mut row := []int{}
			mut row_w := f32(0)
			for k, nm in names {
				w := sq + 6 + ctx.measure_text_with_font(nm, font).x + 14
				if row.len > 0 && row_w + w > area.w {
					rows << row
					row = []int{}
					row_w = 0
				}
				row << k
				row_w += w
			}
			rows << row
			legend_h := f32(rows.len) * (fh + 4)
			ly0 := if c.legend_pos == .top { area.y } else { area.y + area.h - legend_h }
			for r, items in rows {
				mut tot := f32(0)
				for k in items {
					tot += sq + 6 + ctx.measure_text_with_font(names[k], font).x + 14
				}
				mut lx := area.x + (area.w - tot + 14) * 0.5
				for k in items {
					w := sq + 6 + ctx.measure_text_with_font(names[k], font).x
					c.lay.legend << ChartItemRect{Rect{lx, ly0 + f32(r) * (fh + 4), w, fh}, ids[k]}
					lx += w + 14
				}
			}
			if c.legend_pos == .top {
				area.y += legend_h + 6
			}
			area.h -= legend_h + 6
		}
	}
	if c.mode != .cartesian {
		c.lay.plot = area
		c.lay.cx = area.x + area.w * 0.5
		c.lay.cy = area.y + area.h * 0.5
		c.lay.radius = max_f32(min_f32(area.w, area.h) * 0.5 - 8, 4)
		return
	}
	// Подписи осей
	if c.x_title != '' {
		area.h -= fh + 4
	}
	if c.y_title != '' {
		area.x += fh + 4
		area.w -= fh + 4
	}
	// Шкала Y: деления примерно каждые 40 px высоты. Шкала - по ЦЕЛЕВЫМ значениям (доля 1), а не по
	// тем, что сейчас на экране: иначе во время перехода (столбцы растут из нуля) шкала и ширина
	// подписей пересчитывались каждый кадр, и вся область графика дёргалась
	ticks := clamp_int(int(area.h / 40), 2, 8)
	mut ylo, mut yhi := c.y_extent(1)
	mut step := f32(1)
	if c.y_fixed {
		ylo, yhi = c.y_min, c.y_max
		step = nice_step(yhi - ylo, ticks)
	} else {
		nlo, nhi, nstep := chart_nice_range(ylo, yhi, ticks)
		ylo, yhi, step = nlo, nhi, nstep
	}
	c.lay.y_lo = ylo
	c.lay.y_hi = if yhi > ylo { yhi } else { ylo + 1 }
	c.lay.y_step = step
	// Место под подписи Y - по самой широкой подписи деления
	mut label_w := f32(0)
	for v in chart_ticks(c.lay.y_lo, c.lay.y_hi, step) {
		label_w = max_f32(label_w, ctx.measure_text_with_font(c.y_tick_label(v, step), font).x)
	}
	area.x += label_w + 6
	area.w -= label_w + 6
	area.h -= fh + 6 // подписи X
	c.lay.plot = Rect{area.x, area.y, max_f32(area.w, 1), max_f32(area.h, 1)}
	xl, xh, slot := c.x_extent()
	c.lay.x_lo = xl
	c.lay.x_hi = xh
	c.lay.slot = slot
}

// y_tick_label - подпись деления Y: свой format или подпись деления шкалы.
fn (c &Chart) y_tick_label(v f32, step f32) string {
	return if isnil(c.format) { chart_tick_label(v, step) } else { c.format(v) }
}

// chart_ticks - значения делений от lo до hi с шагом step (кратные шагу, с допуском на
// погрешность f32 у верхней границы).
fn chart_ticks(lo f32, hi f32, step f32) []f32 {
	mut out := []f32{}
	if step <= 0 {
		return out
	}
	mut k := math.ceil(f64(lo / step) - 1e-4)
	for out.len < 100 {
		v := f32(k) * step
		if v > hi + step * 1e-4 {
			break
		}
		out << v
		k += 1
	}
	return out
}

// ─── Рисование ─────────────────────────────────────────

pub fn (mut c Chart) draw(mut ctx RenderContext) {
	if !c.visible || c.bounds.w < 16 || c.bounds.h < 16 {
		return
	}
	en := ctx.is_enabled(c.enabled)
	// Шаг анимации перехода: пока идёт - кадр только своего прямоугольника
	if c.progress.update(1, ctx) {
		ctx.mark_anim_rect('chart', c.bounds)
	}
	p := c.progress.value
	c.layout_frame(mut ctx)

	ctx.fill_rect(c.bounds, ctx.theme.eff_chart_bg())
	ctx.draw_rect(c.bounds, ctx.theme.eff_chart_border())
	ctx.push_clip(c.bounds)
	if c.title != '' {
		tf := ctx.get_font(.bold, 0)
		tw := ctx.measure_text_with_font(c.title, tf).x
		ctx.draw_text_with_font(c.title, c.bounds.x + (c.bounds.w - tw) * 0.5, c.bounds.y + 8,
			if en { ctx.theme.eff_chart_title() } else { ctx.theme.text_disabled }, tf)
	}
	c.draw_legend(mut ctx, en)
	if c.mode == .cartesian {
		c.draw_axes(mut ctx, en)
		ctx.push_clip(c.lay.plot.expanded(4))
		c.draw_series(mut ctx, p, en)
		ctx.pop_clip()
		if en && c.hover_info && c.hover_index >= 0 {
			c.draw_hover(mut ctx, p)
		}
	} else {
		c.draw_pie(mut ctx, p, en)
	}
	ctx.pop_clip()
}

// draw_legend - пункты легенды: квадрат цвета и имя; спрятанная серия - бледный квадрат-контур и
// бледное имя.
fn (c &Chart) draw_legend(mut ctx RenderContext, en bool) {
	if c.lay.legend.len == 0 {
		return
	}
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	sq := fh * 0.7
	names, colors, _, hidden := c.legend_entries(ctx)
	tc := if en { ctx.theme.eff_chart_text() } else { ctx.theme.text_disabled }
	for k, it in c.lay.legend {
		if k >= names.len {
			break
		}
		mut col := if en { colors[k] } else { ctx.disabled_color(colors[k]) }
		sr := Rect{it.r.x, it.r.y + (fh - sq) * 0.5, sq, sq}
		if hidden[k] {
			ctx.draw_rounded_rect(sr, col.with_alpha(120), 2)
			ctx.draw_text_with_font(names[k], it.r.x + sq + 6, it.r.y, tc.with_alpha(110), font)
		} else {
			ctx.fill_rounded_rect(sr, col, 2)
			ctx.draw_text_with_font(names[k], it.r.x + sq + 6, it.r.y, tc, font)
		}
	}
}

// draw_axes - сетка, линии осей, подписи делений и подписи осей.
fn (c &Chart) draw_axes(mut ctx RenderContext, en bool) {
	pr := c.lay.plot
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	tc := if en { ctx.theme.eff_chart_text() } else { ctx.theme.text_disabled }
	grid := ctx.theme.eff_chart_grid()
	axis := ctx.theme.eff_chart_axis()
	// Y: горизонтальные линии сетки и подписи слева
	ystep := c.lay.y_step
	for v in chart_ticks(c.lay.y_lo, c.lay.y_hi, ystep) {
		y := c.sy(v)
		if c.show_grid {
			ctx.draw_line(pr.x, y, pr.x + pr.w, y, grid)
		}
		lbl := c.y_tick_label(v, ystep)
		lw := ctx.measure_text_with_font(lbl, font).x
		ctx.draw_text_with_font(lbl, pr.x - lw - 6, y - fh * 0.5, tc, font)
	}
	// X: категории (с прореживанием, чтобы подписи не налезали) или числовые деления
	ly := pr.y + pr.h + 4
	if !c.numeric_x() {
		n := c.point_count()
		mut widest := f32(0)
		for i in 0 .. n {
			widest = max_f32(widest, ctx.measure_text_with_font(c.category_label(i), font).x)
		}
		slot_px := if n > 0 { abs_f32(c.sx(1) - c.sx(0)) } else { pr.w }
		every := max_int(1, int(math.ceil(f64((widest + 8) / max_f32(slot_px, 1)))))
		for i := 0; i < n; i += every {
			lbl := c.category_label(i)
			lw := ctx.measure_text_with_font(lbl, font).x
			ctx.draw_text_with_font(lbl, c.sx(f32(i)) - lw * 0.5, ly, tc, font)
		}
	} else {
		xstep := nice_step(c.lay.x_hi - c.lay.x_lo, clamp_int(int(pr.w / 60), 2, 12))
		for v in chart_ticks(c.lay.x_lo, c.lay.x_hi, xstep) {
			x := c.sx(v)
			if c.show_grid {
				ctx.draw_line(x, pr.y, x, pr.y + pr.h, grid.with_alpha(u8(int(grid.a) / 2)))
			}
			lbl := c.x_label(v, xstep)
			lw := ctx.measure_text_with_font(lbl, font).x
			ctx.draw_text_with_font(lbl, x - lw * 0.5, ly, tc, font)
		}
	}
	// Ось X - по нулю, если он в шкале, иначе по низу; ось Y - слева
	zero_y := if c.lay.y_lo <= 0 && c.lay.y_hi >= 0 { c.sy(0) } else { pr.y + pr.h }
	ctx.draw_line(pr.x, zero_y, pr.x + pr.w, zero_y, axis)
	ctx.draw_line(pr.x, pr.y, pr.x, pr.y + pr.h, axis)
	if c.x_title != '' {
		tw := ctx.measure_text_with_font(c.x_title, font).x
		ctx.draw_text_with_font(c.x_title, pr.x + (pr.w - tw) * 0.5, ly + fh + 2, tc, font)
	}
	if c.y_title != '' {
		ctx.draw_text_rotated_center(c.y_title, c.bounds.x + 8 + fh * 0.5, pr.y + pr.h * 0.5,
			-90, tc, font)
	}
}

// x_label - подпись числового X: свой x_format или подпись деления.
fn (c &Chart) x_label(v f32, step f32) string {
	return if isnil(c.x_format) { chart_tick_label(v, step) } else { c.x_format(v) }
}

// draw_series - серии: сначала заливки областей (чтобы не закрывали линии), затем столбцы,
// затем линии, ступени и точки.
fn (c &Chart) draw_series(mut ctx RenderContext, p f32, en bool) {
	pr := c.lay.plot
	n := c.point_count()
	lw := ctx.theme.eff_chart_line_width()
	fill_a := ctx.theme.eff_chart_fill_alpha()
	zero := clamp_f32(0, c.lay.y_lo, c.lay.y_hi)
	// stacked: накопленная высота областей по точкам (низ следующей области - верх предыдущей)
	mut area_base := []f32{len: n}
	// Точки линий каждой серии - для второго прохода (линии поверх заливок и столбцов)
	mut lines := map[int][]Vec2{}
	for i, s in c.series {
		if !s.visible || s.kind == .bar {
			continue
		}
		mut col := c.series_color(i, ctx)
		if !en {
			col = ctx.disabled_color(col)
		}
		mut pts := []Vec2{}
		mut base_pts := []Vec2{}
		for j in 0 .. s.values.len {
			v := s.shown(j, p)
			if !chart_is_finite(v) {
				continue
			}
			mut y := v
			mut base := zero
			if c.stacked && s.kind == .area && j < n {
				base = area_base[j]
				y = base + v
				area_base[j] = y
			}
			x := c.sx(s.x_of(j))
			pts << Vec2{x, c.sy(y)}
			base_pts << Vec2{x, c.sy(base)}
		}
		if s.kind == .area && pts.len > 1 {
			// Градиент - по высоте над нулём во всей области данных (chart_gradient_color); у
			// stacked низ слоя - верх предыдущего (base_pts), у простой области - нулевая линия
			lower := if c.stacked { base_pts } else { pts.map(Vec2{it.x, c.sy(zero)}) }
			tri, cols := chart_band_triangles(pts, lower, c.sy(zero), pr.y, pr.y + pr.h, col,
				fill_a)
			ctx.fill_triangles_colored(tri, cols)
		}
		lines[i] = pts
	}
	c.draw_bars(mut ctx, p, en)
	// Линии и точки
	slot_px := if n > 1 { abs_f32(c.sx(c.lay.slot) - c.sx(0)) } else { pr.w }
	markers := match c.show_markers {
		.always { true }
		.never { false }
		.auto { slot_px >= 14 }
	}
	for i, s in c.series {
		pts := lines[i] or { continue }
		mut col := c.series_color(i, ctx)
		if !en {
			col = ctx.disabled_color(col)
		}
		match s.kind {
			.line, .area {
				ctx.draw_polyline(pts, col, lw)
				if markers {
					for pt in pts {
						ctx.fill_circle(pt.x, pt.y, lw + 2, col)
						ctx.fill_circle(pt.x, pt.y, lw, ctx.theme.eff_chart_bg())
					}
				}
			}
			.step {
				ctx.draw_polyline(chart_step_points(pts), col, lw)
			}
			.scatter {
				for pt in pts {
					ctx.fill_circle(pt.x, pt.y, lw + 2, col.with_alpha(210))
				}
			}
			.bar {}
		}
	}
}

// chart_step_points - ступенчатая ломаная: от точки k по горизонтали до X точки k+1, затем по
// вертикали к её значению.
fn chart_step_points(pts []Vec2) []Vec2 {
	mut out := []Vec2{cap: pts.len * 2}
	for k, pt in pts {
		if k > 0 {
			out << Vec2{pt.x, pts[k - 1].y}
		}
		out << pt
	}
	return out
}

// bar_rect - прямоугольник столбца точки j серии si (номер среди видимых столбцов - slot_k из
// count) при доле перехода p; base/top - низ и верх в данных (stacked считает их снаружи).
fn (c &Chart) bar_rect(si int, j int, k int, count int, base f32, top f32) Rect {
	s := c.series[si]
	slot_px := abs_f32(c.sx(c.lay.slot) - c.sx(0))
	gap := if s.gap_free { f32(0) } else { clamp_f32(c.bar_gap, 0, 0.9) }
	group_w := slot_px * (1 - gap)
	cx := c.sx(s.x_of(j))
	mut x := cx - group_w * 0.5
	mut w := group_w
	if !c.stacked && count > 1 {
		w = group_w / f32(count)
		x += w * f32(k)
	}
	// столбцы вплотную (гистограмма) - с волосяным зазором, иначе они сливаются в одну фигуру
	if s.gap_free && w > 3 {
		x += 0.5
		w -= 1
	}
	y0 := c.sy(base)
	y1 := c.sy(top)
	return Rect{x, min_f32(y0, y1), max_f32(w, 1), abs_f32(y1 - y0)}
}

// draw_bars - столбцы видимых серий-столбцов: рядом (группа на категорию) или стопкой (stacked).
// Столбцы категории под курсором - светлее.
fn (c &Chart) draw_bars(mut ctx RenderContext, p f32, en bool) {
	bars := c.visible_bars()
	if bars.len == 0 {
		return
	}
	n := c.point_count()
	mut pos := []f32{len: n}
	mut neg := []f32{len: n}
	zero := clamp_f32(0, c.lay.y_lo, c.lay.y_hi)
	radius := if c.stacked { f32(0) } else { ctx.theme.eff_chart_bar_radius() }
	for k, si in bars {
		s := c.series[si]
		mut col := c.series_color(si, ctx)
		if !en {
			col = ctx.disabled_color(col)
		}
		for j in 0 .. s.values.len {
			v := s.shown(j, p)
			if !chart_is_finite(v) {
				continue
			}
			mut base := zero
			mut top := v
			if c.stacked && j < n {
				if v >= 0 {
					base = pos[j]
					pos[j] += v
					top = pos[j]
				} else {
					base = neg[j]
					neg[j] += v
					top = neg[j]
				}
			}
			r := c.bar_rect(si, j, k, bars.len, base, top)
			hot := c.hover_index == j && (c.hover_series < 0 || c.hover_series == si)
			fill := if hot && en { col.brighten(0.12) } else { col }
			ctx.fill_rounded_rect(r, fill, min_f32(radius, r.w * 0.5))
		}
	}
}

// draw_hover - вертикальная линия на точке под курсором, кольца на точках линий и плашка
// значений: заголовок - категория (или X), ниже «цвет - имя: значение» по видимым сериям.
fn (c &Chart) draw_hover(mut ctx RenderContext, p f32) {
	pr := c.lay.plot
	j := c.hover_index
	mut hx := f32(0)
	mut header := ''
	if c.numeric_x() {
		// X ближайшей точки первой серии, где эта точка есть
		for s in c.series {
			if j < s.values.len {
				hx = c.sx(s.x_of(j))
				header = c.x_label(s.x_of(j), nice_step(c.lay.x_hi - c.lay.x_lo, 10))
				break
			}
		}
	} else {
		hx = c.sx(f32(j))
		header = c.category_label(j)
	}
	if !c.has_kind(.bar) || c.has_kind(.line) || c.has_kind(.area) {
		ctx.draw_line(hx, pr.y, hx, pr.y + pr.h, ctx.theme.eff_chart_hover())
	}
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	mut rows := []string{}
	mut colors := []Color{}
	n := c.point_count()
	mut area_base := []f32{len: n}
	for i, s in c.series {
		if !s.visible || j >= s.values.len {
			continue
		}
		v := s.shown(j, p)
		if c.stacked && s.kind == .area {
			// кольцо - на верхе стопки, подпись - собственное значение серии
			area_base[j] += if chart_is_finite(v) { v } else { 0 }
		}
		if !chart_is_finite(v) {
			continue
		}
		col := c.series_color(i, ctx)
		if s.kind != .bar {
			yv := if c.stacked && s.kind == .area { area_base[j] } else { v }
			ctx.fill_circle(c.sx(s.x_of(j)), c.sy(yv), 4.5, col)
			ctx.fill_circle(c.sx(s.x_of(j)), c.sy(yv), 2.5, ctx.theme.eff_chart_bg())
		}
		name := if s.name != '' { s.name } else { '${i + 1}' }
		rows << '${name}: ${c.fmt_y(v)}'
		colors << col
	}
	if rows.len == 0 {
		return
	}
	// Плашка: справа от линии, а если не помещается - слева; по вертикали - у курсора, в рамке
	mut w := ctx.measure_text_with_font(header, font).x
	for r in rows {
		w = max_f32(w, ctx.measure_text_with_font(r, font).x + 14)
	}
	w += 16
	h := f32(rows.len + 1) * (fh + 2) + 10
	mut bx := hx + 12
	if bx + w > c.bounds.x + c.bounds.w - 4 {
		bx = hx - 12 - w
	}
	bx = max_f32(bx, c.bounds.x + 4)
	by := clamp_f32(c.hover_y - h * 0.5, c.bounds.y + 4, c.bounds.y + c.bounds.h - h - 4)
	box := Rect{bx, by, w, h}
	ctx.draw_shadow(box, 6)
	ctx.fill_rounded_rect(box, ctx.theme.eff_chart_tip_bg(), 6)
	ctx.draw_rounded_rect(box, ctx.theme.eff_tooltip_border(), 6)
	tc := ctx.theme.eff_chart_tip_text()
	ctx.draw_text_with_font(header, bx + 8, by + 5, tc, ctx.get_font(.bold, max_int(ctx.default_font_size() - 2, 8)))
	for k, r in rows {
		ry := by + 5 + f32(k + 1) * (fh + 2)
		ctx.fill_rounded_rect(Rect{bx + 8, ry + fh * 0.5 - 4, 8, 8}, colors[k], 2)
		ctx.draw_text_with_font(r, bx + 22, ry, tc, font)
	}
}

// ─── Круговая диаграмма ────────────────────────────────

// pie_total - сумма видимых положительных значений первой серии (на экране, доля p).
fn (c &Chart) pie_total(p f32) f32 {
	if c.series.len == 0 {
		return 0
	}
	s := c.series[0]
	mut total := f32(0)
	for i in 0 .. s.values.len {
		v := s.shown(i, p)
		if c.series_visible(i) && chart_is_finite(v) && v > 0 {
			total += v
		}
	}
	return total
}

// pie_slices - углы секторов (радианы, от -pi/2 - «двенадцать часов» - по часовой стрелке):
// для каждого значения - (начало, конец); спрятанный, неположительный сектор - нулевой ширины.
// Вся окружность ещё умножается на p - первое появление разворачивает круг по часовой.
fn (c &Chart) pie_slices(p f32) [][2]f32 {
	mut out := [][2]f32{}
	if c.series.len == 0 {
		return out
	}
	s := c.series[0]
	total := c.pie_total(p)
	mut a := f32(-math.pi / 2)
	for i in 0 .. s.values.len {
		v := s.shown(i, p)
		mut sweep := f32(0)
		if total > 0 && c.series_visible(i) && chart_is_finite(v) && v > 0 {
			sweep = v / total * f32(2 * math.pi)
		}
		out << [a, a + sweep]!
		a += sweep
	}
	return out
}

// draw_pie - сектора (кольцо у .donut), выдвинутый сектор под курсором, проценты на крупных
// секторах, тонкие разделители цветом фона и текст в центре кольца.
fn (c &Chart) draw_pie(mut ctx RenderContext, p f32, en bool) {
	slices := c.pie_slices(p)
	if slices.len == 0 {
		return
	}
	cx, cy, r := c.lay.cx, c.lay.cy, c.lay.radius
	inner := if c.mode == .donut { r * clamp_f32(c.donut_ratio, 0.1, 0.9) } else { f32(0) }
	font := chart_small_font(ctx)
	fh := ctx.font_height_of(font)
	total := c.pie_total(p)
	bg := ctx.theme.eff_chart_bg()
	for i, sl in slices {
		if sl[1] - sl[0] <= 0 {
			continue
		}
		mut col := c.slice_color(i, ctx)
		if !en {
			col = ctx.disabled_color(col)
		}
		// Сектор под курсором выдвигается на 6 px по своей биссектрисе
		mid := (sl[0] + sl[1]) * 0.5
		off := if en && c.hover_index == i { f32(6) } else { f32(0) }
		ox := cx + off * math.cosf(mid)
		oy := cy + off * math.sinf(mid)
		ctx.fill_triangles(chart_ring_segment(ox, oy, inner, r, sl[0], sl[1]), col)
		// Разделитель - линия цветом фона по началу сектора
		ctx.draw_line_thick(ox + inner * math.cosf(sl[0]), oy + inner * math.sinf(sl[0]),
			ox + r * math.cosf(sl[0]), oy + r * math.sinf(sl[0]), 2, bg)
		// Процент - внутри сектора, если он шире ~20° и подпись помещается
		if sl[1] - sl[0] > 0.35 && total > 0 && p >= 1 {
			v := c.series[0].values[i]
			pct := '${int(math.round(f64(v / total * 100)))}%'
			lr := if inner > 0 { (inner + r) * 0.5 } else { r * 0.62 }
			tw := ctx.measure_text_with_font(pct, font).x
			ctx.draw_text_with_font(pct, ox + lr * math.cosf(mid) - tw * 0.5, oy + lr * math.sinf(mid) - fh * 0.5,
				chart_contrast_text(col), font)
		}
	}
	// Центр кольца: свой текст или сумма
	if c.mode == .donut && total > 0 {
		txt := if c.center_text != '' { c.center_text } else { c.fmt_y(total) }
		tf := ctx.get_font(.bold, ctx.default_font_size() + 4)
		ts := ctx.measure_text_with_font(txt, tf)
		if ts.x < inner * 1.8 {
			ctx.draw_text_with_font(txt, cx - ts.x * 0.5, cy - ts.y * 0.5, if en {
				ctx.theme.eff_chart_title()
			} else {
				ctx.theme.text_disabled
			}, tf)
		}
	}
	// Плашка сектора под курсором: «категория: значение (доля)»
	if en && c.hover_info && c.hover_index >= 0 && c.hover_index < slices.len && total > 0 {
		v := c.series[0].values[c.hover_index]
		txt := '${c.category_label(c.hover_index)}: ${c.fmt_y(v)} (${v / total * 100:.1f}%)'
		tw := ctx.measure_text_with_font(txt, font).x
		mut bx := c.hover_x + 14
		if bx + tw + 16 > c.bounds.x + c.bounds.w {
			bx = c.hover_x - 14 - tw - 16
		}
		box := Rect{bx, c.hover_y - fh - 8, tw + 16, fh + 8}
		ctx.draw_shadow(box, 6)
		ctx.fill_rounded_rect(box, ctx.theme.eff_chart_tip_bg(), 6)
		ctx.draw_rounded_rect(box, ctx.theme.eff_tooltip_border(), 6)
		ctx.draw_text_with_font(txt, bx + 8, box.y + 4, ctx.theme.eff_chart_tip_text(), font)
	}
}

// chart_ring_segment - треугольники сектора кольца между радиусами r0 (0 - сектор круга) и r1
// от угла a0 до a1: дуга бьётся на шаги не крупнее ~3°, каждый шаг - трапеция (два треугольника).
fn chart_ring_segment(cx f32, cy f32, r0 f32, r1 f32, a0 f32, a1 f32) []Vec2 {
	steps := max_int(1, int(math.ceil(f64((a1 - a0) / 0.05))))
	mut out := []Vec2{cap: steps * 6}
	for k in 0 .. steps {
		t0 := a0 + (a1 - a0) * f32(k) / f32(steps)
		t1 := a0 + (a1 - a0) * f32(k + 1) / f32(steps)
		c0, s0 := math.cosf(t0), math.sinf(t0)
		c1, s1 := math.cosf(t1), math.sinf(t1)
		o0 := Vec2{cx + r1 * c0, cy + r1 * s0}
		o1 := Vec2{cx + r1 * c1, cy + r1 * s1}
		i0 := Vec2{cx + r0 * c0, cy + r0 * s0}
		i1 := Vec2{cx + r0 * c1, cy + r0 * s1}
		out << i0
		out << o0
		out << o1
		if r0 > 0 {
			out << i0
			out << o1
			out << i1
		}
	}
	return out
}

// chart_contrast_text - белый или почти чёрный текст поверх цвета c (по яркости).
fn chart_contrast_text(c Color) Color {
	lum := 0.299 * f32(c.r) + 0.587 * f32(c.g) + 0.114 * f32(c.b)
	return if lum > 150 { Color{20, 20, 20, 255} } else { Color{255, 255, 255, 255} }
}

// ─── Попадание мышью ───────────────────────────────────

// nearest_index - номер точки, ближайшей к экранному X: категория (округление) или ближайшая по
// X точка самой длинной видимой серии (числовая ось). Вне области данных - -1.
fn (c &Chart) nearest_index(x f32, y f32) int {
	pr := c.lay.plot
	if !pr.expanded(4).contains(x, y) {
		return -1
	}
	n := c.point_count()
	if n == 0 {
		return -1
	}
	l := c.lay
	dx := l.x_lo + (x - pr.x) / pr.w * (l.x_hi - l.x_lo)
	if !c.numeric_x() {
		return clamp_int(int(math.round(f64(dx))), 0, n - 1)
	}
	mut best := -1
	mut best_d := f32(math.max_f32)
	for s in c.series {
		if !s.visible {
			continue
		}
		for i in 0 .. s.values.len {
			d := abs_f32(s.x_of(i) - dx)
			if d < best_d {
				best_d = d
				best = i
			}
		}
	}
	return best
}

// bar_at - серия-столбец под точкой (x, y) в точке j (-1 - не над столбцом).
fn (c &Chart) bar_at(j int, x f32, y f32) int {
	bars := c.visible_bars()
	n := c.point_count()
	if j < 0 || bars.len == 0 {
		return -1
	}
	p := c.progress.value
	zero := clamp_f32(0, c.lay.y_lo, c.lay.y_hi)
	mut pos := f32(0)
	mut neg := f32(0)
	for k, si in bars {
		s := c.series[si]
		if j >= s.values.len {
			continue
		}
		v := s.shown(j, p)
		if !chart_is_finite(v) {
			continue
		}
		mut base := zero
		mut top := v
		if c.stacked && j < n {
			if v >= 0 {
				base = pos
				pos += v
				top = pos
			} else {
				base = neg
				neg += v
				top = neg
			}
		}
		if c.bar_rect(si, j, k, bars.len, base, top).contains(x, y) {
			return si
		}
	}
	return -1
}

// slice_at - сектор круговой диаграммы под точкой (x, y), -1 - мимо (в том числе в дырке кольца).
fn (c &Chart) slice_at(x f32, y f32) int {
	dx := x - c.lay.cx
	dy := y - c.lay.cy
	d := math.sqrtf(dx * dx + dy * dy)
	inner := if c.mode == .donut { c.lay.radius * clamp_f32(c.donut_ratio, 0.1, 0.9) } else { f32(0) }
	if d > c.lay.radius + 6 || d < inner {
		return -1
	}
	// угол курсора в той же системе, что pie_slices: от -pi/2 по часовой
	mut a := f32(math.atan2(f64(dy), f64(dx)))
	if a < -math.pi / 2 {
		a += f32(2 * math.pi)
	}
	for i, sl in c.pie_slices(c.progress.value) {
		if a >= sl[0] && a < sl[1] {
			return i
		}
	}
	return -1
}

// legend_at - номер серии/сектора пункта легенды под точкой (-1 - мимо).
fn (c &Chart) legend_at(x f32, y f32) int {
	for it in c.lay.legend {
		if it.r.expanded(2).contains(x, y) {
			return it.index
		}
	}
	return -1
}

// ─── События ───────────────────────────────────────────

pub fn (mut c Chart) handle_event(event &GuiEvent, app &App) bool {
	if !c.visible {
		return false
	}
	if !c.enabled && is_input_event(event) {
		c.set_hover(-1, -1)
		return false
	}
	match event.typ {
		.mouse_move {
			c.update_hover(event.mouse_x, event.mouse_y)
		}
		.mouse_leave {
			c.set_hover(-1, -1)
		}
		.mouse_down {
			if event.mouse_btn != .left || !c.bounds.contains(event.mouse_x, event.mouse_y) {
				return false
			}
			// Щелчок по легенде - спрятать/показать серию (сектор)
			li := c.legend_at(event.mouse_x, event.mouse_y)
			if li >= 0 {
				c.set_series_visible(li, !c.series_visible(li))
				c.update_hover(event.mouse_x, event.mouse_y)
				return true
			}
			if !isnil(c.on_click) && c.hover_index >= 0 {
				series := if c.mode == .cartesian { c.hover_series } else { 0 }
				c.on_click(series, c.hover_index)
				return true
			}
		}
		else {}
	}
	return false
}

// update_hover - пересчитать, что под курсором (точка, столбец, сектор).
fn (mut c Chart) update_hover(x f32, y f32) {
	if !c.hover_info && isnil(c.on_click) {
		return
	}
	mut idx := -1
	mut ser := -1
	if c.mode == .cartesian {
		idx = c.nearest_index(x, y)
		ser = c.bar_at(idx, x, y)
		// над чистыми столбцами плашка - только над самим столбцом, а не над пустым местом
		if ser < 0 && c.has_kind(.bar) && !c.has_kind(.line) && !c.has_kind(.area)
			&& !c.has_kind(.step) && !c.has_kind(.scatter) {
			idx = -1
		}
	} else {
		idx = c.slice_at(x, y)
	}
	// плашка следует за курсором - перерисовка и при той же точке, но другом месте
	moved := idx >= 0 && (x != c.hover_x || y != c.hover_y)
	c.hover_x = x
	c.hover_y = y
	if moved {
		widget_changed()
	}
	c.set_hover(idx, ser)
}

// set_hover - сменить точку/столбец под курсором; перерисовка - только при изменении.
fn (mut c Chart) set_hover(idx int, ser int) {
	if idx != c.hover_index || ser != c.hover_series {
		c.hover_index = idx
		c.hover_series = ser
		widget_changed()
	}
}
