module vgui

import math

// Файл chart_common.v: общее для графиков Chart (chart.v) и Sparkline (sparkline.v).
//
//   - встроенная палитра серий chart_default_palette - цвет серии без своего цвета, если тема не
//     задала chart_series_N (Theme.eff_chart_series);
//   - ChartRing - кольцевой буфер последних N значений (поток «отсчёт в секунду» у Sparkline и
//     Chart.push): добавление за O(1), самое старое значение вытесняется;
//   - chart_nice_range - «красивые» границы и шаг шкалы (0, 25, 50, 75, 100 вместо 0, 23.7, ...);
//   - chart_format_value - подпись значения: целое без хвоста «.0», дробное - до двух знаков,
//     большие числа - с суффиксом k/M/G (1.5k, 12M);
//   - chart_area_triangles - треугольники заливки под ломаной (два на каждый отрезок), с
//     вертикальным градиентом цвета (RenderContext.fill_triangles_colored).
//
// Шаг сетки nice_step и подпись деления format_tick - из plot_view.v (те же, что у PlotView).

// chart_palette_size - сколько цветов в палитре серий (и полей chart_series_N в теме).
pub const chart_palette_size = 6

// chart_default_palette - встроенная палитра: насыщенные, хорошо различимые между собой цвета,
// которые читаются и на тёмном, и на светлом фоне (синий, оранжевый, зелёный, красный,
// фиолетовый, бирюзовый - порядок как в большинстве библиотек графиков: первые две серии самые
// контрастные друг к другу).
pub const chart_default_palette = [
	Color{66, 153, 225, 255},
	Color{237, 137, 54, 255},
	Color{72, 187, 120, 255},
	Color{229, 83, 83, 255},
	Color{159, 122, 234, 255},
	Color{56, 178, 172, 255},
]

// ─── Кольцевой буфер ───────────────────────────────────

// ChartRing - кольцевой буфер f32 на cap значений. head - индекс, куда ляжет следующее значение;
// count - сколько значений уже лежит (≤ cap). at(0) - самое старое, at(len() - 1) - последнее.
// Буфер не растёт: при полном буфере push затирает самое старое значение.
struct ChartRing {
mut:
	data  []f32
	head  int
	count int
}

// new_chart_ring - пустой буфер на capacity значений (меньше 1 - 1).
fn new_chart_ring(capacity int) ChartRing {
	return ChartRing{
		data: []f32{len: max_int(capacity, 1)}
	}
}

fn (r &ChartRing) capacity() int {
	return r.data.len
}

fn (r &ChartRing) len() int {
	return r.count
}

// push - добавить значение в конец; при полном буфере оно встаёт на место самого старого.
fn (mut r ChartRing) push(v f32) {
	r.data[r.head] = v
	r.head = (r.head + 1) % r.data.len
	if r.count < r.data.len {
		r.count++
	}
}

// at - значение номер i от самого старого (0..len()-1). Индекс вне диапазона - 0: рисующий код
// не должен падать из-за гонки «очистили буфер между двумя чтениями».
fn (r &ChartRing) at(i int) f32 {
	if i < 0 || i >= r.count {
		return 0
	}
	// Самое старое значение лежит на head - count (по модулю ёмкости)
	start := (r.head - r.count + r.data.len) % r.data.len
	return r.data[(start + i) % r.data.len]
}

// last - последнее добавленное значение (пустой буфер - 0).
fn (r &ChartRing) last() f32 {
	return r.at(r.count - 1)
}

fn (mut r ChartRing) clear() {
	r.head = 0
	r.count = 0
}

// to_array - значения от самого старого к последнему (копия).
fn (r &ChartRing) to_array() []f32 {
	mut out := []f32{cap: r.count}
	for i in 0 .. r.count {
		out << r.at(i)
	}
	return out
}

// resized - копия буфера на новую ёмкость: сохраняются последние min(len, capacity) значений.
fn (r &ChartRing) resized(capacity int) ChartRing {
	mut out := new_chart_ring(capacity)
	from := max_int(0, r.count - out.capacity())
	for i in from .. r.count {
		out.push(r.at(i))
	}
	return out
}

// ─── Шкала ─────────────────────────────────────────────

// chart_nice_range - границы шкалы, накрывающие [lo, hi], и шаг делений: шаг «красивый»
// (nice_step: 1/2/5·10^n, примерно ticks делений), границы - кратны шагу. Вырожденный диапазон
// (lo == hi) раздвигается: у нуля - до [0, 1], иначе на 10% значения в обе стороны (одна точка
// не должна давать деление на ноль и «плоский» график по краю рамки).
// Возвращает (низ, верх, шаг).
fn chart_nice_range(lo f32, hi f32, ticks int) (f32, f32, f32) {
	mut a := min_f32(lo, hi)
	mut b := max_f32(lo, hi)
	if !chart_is_finite(a) || !chart_is_finite(b) {
		return 0, 1, 0.25
	}
	if b - a < 1e-12 {
		pad := if abs_f32(a) < 1e-12 { f32(1) } else { abs_f32(a) * 0.1 }
		// значения строго неотрицательные держатся от нуля: [0, 1] вместо [-1, 1]
		a = if a >= 0 && a - pad < 0 { 0 } else { a - pad }
		b = b + pad
	}
	step := nice_step(b - a, ticks)
	nlo := f32(math.floor(f64(a / step))) * step
	nhi := f32(math.ceil(f64(b / step))) * step
	return nlo, nhi, step
}

// chart_is_finite - не NaN и не ±Inf (такие значения в данных пропускаются, а не ломают шкалу).
fn chart_is_finite(v f32) bool {
	return !math.is_nan(f64(v)) && !math.is_inf(f64(v), 0)
}

// ─── Подписи значений ──────────────────────────────────

// chart_format_value - короткая подпись значения для плашки под курсором и подписей Sparkline:
// |v| ≥ 1000 - с суффиксом k / M / G и одним знаком (1.5k, 12M, «.0» отбрасывается); целое -
// без дробной части; дробное - до двух знаков без хвостовых нулей (0.25, 3.5).
pub fn chart_format_value(v f32) string {
	if !chart_is_finite(v) {
		return '-'
	}
	av := abs_f32(v)
	units := [f32(1e9), 1e6, 1e3]
	suffixes := ['G', 'M', 'k']
	for i, u in units {
		if av >= u {
			return chart_trim_zeros('${v / u:.1f}') + suffixes[i]
		}
	}
	if abs_f32(v - f32(math.round(f64(v)))) < 1e-4 {
		return '${i64(math.round(f64(v)))}'
	}
	return chart_trim_zeros('${v:.2f}')
}

// chart_trim_zeros - '1.50' -> '1.5', '2.0' -> '2' (строка с точкой; без точки - как есть).
fn chart_trim_zeros(s string) string {
	if !s.contains('.') {
		return s
	}
	return s.trim_right('0').trim_right('.')
}

// chart_tick_label - подпись деления шкалы шагом step: большие значения - через
// chart_format_value (k/M/G, иначе «1000000» не помещается слева от графика), остальные -
// format_tick, как у PlotView (знаков столько, сколько нужно, чтобы деления различались).
fn chart_tick_label(v f32, step f32) string {
	if abs_f32(v) >= 10000 && step >= 1000 {
		return chart_format_value(v)
	}
	return format_tick(v, step)
}

// ─── Заливка под линией ────────────────────────────────

// chart_gradient_color - цвет заливки в точке на высоте y: непрозрачность alpha у края области
// данных, прозрачный у нулевой линии base_y, между ними - линейно по ВЫСОТЕ. Край - top_y для
// значений выше нуля и bottom_y для отрицательных (заливка от нуля вниз).
//
// Почему от высоты, а не «у линии - цвет, у основания - прозрачный»: SDL смешивает цвета вершин
// внутри каждого треугольника, и у соседних отрезков разной высоты одна и та же высота получала
// разную прозрачность - заливка шла вертикальными полосами по швам треугольников. Цвет, линейный
// по y, барицентрическая интерполяция воспроизводит точно - швов нет.
fn chart_gradient_color(c Color, alpha u8, y f32, base_y f32, top_y f32, bottom_y f32) Color {
	span := if y <= base_y { base_y - top_y } else { bottom_y - base_y }
	if span <= 0 {
		return c.with_alpha(alpha)
	}
	t := clamp_f32(abs_f32(base_y - y) / span, 0, 1)
	return c.with_alpha(u8(f32(alpha) * t))
}

// chart_area_triangles - треугольники заливки между ломаной pts и нулевой линией base_y и цвета
// их вершин (для fill_triangles_colored) - градиент по высоте chart_gradient_color в области
// данных от top_y до bottom_y. Каждый отрезок (p0, p1) - трапеция до base_y, она же - два
// треугольника. Меньше двух точек - пустые массивы.
fn chart_area_triangles(pts []Vec2, base_y f32, top_y f32, bottom_y f32, c Color, alpha u8) ([]Vec2, []Color) {
	mut bottom := []Vec2{cap: pts.len}
	for p in pts {
		bottom << Vec2{p.x, base_y}
	}
	return chart_band_triangles(pts, bottom, base_y, top_y, bottom_y, c, alpha)
}

// chart_band_triangles - треугольники полосы между ломаными upper и lower (общие X, одинаковая
// длина; лишние точки длинной отбрасываются) с тем же градиентом по высоте: так заливаются и
// области до нуля, и слои stacked-областей (низ слоя - верх предыдущего).
fn chart_band_triangles(upper []Vec2, lower []Vec2, base_y f32, top_y f32, bottom_y f32, c Color, alpha u8) ([]Vec2, []Color) {
	n := min_int(upper.len, lower.len)
	if n < 2 {
		return []Vec2{}, []Color{}
	}
	mut tri := []Vec2{cap: (n - 1) * 6}
	for k in 0 .. n - 1 {
		tri << upper[k]
		tri << upper[k + 1]
		tri << lower[k + 1]
		tri << upper[k]
		tri << lower[k + 1]
		tri << lower[k]
	}
	mut cols := []Color{cap: tri.len}
	for p in tri {
		cols << chart_gradient_color(c, alpha, p.y, base_y, top_y, bottom_y)
	}
	return tri, cols
}

// chart_small_font - шрифт подписей графика: на 2 пункта мельче текста поддерева (CSS font-size или
// размер окна), но не мельче 8 - подписи делений и легенда вторичны и не должны спорить с данными.
fn chart_small_font(ctx &RenderContext) voidptr {
	size := max_int(ctx.default_font_size() - 2, 8)
	return ctx.get_font_immut(.regular, size)
}

// chart_auto_color - «своего цвета нет, взять из палитры темы» (альфа 0). Именно так, а не
// Color{}: у Color по умолчанию a = 255, и Color{} - непрозрачный чёрный.
pub const chart_auto_color = Color{0, 0, 0, 0}
