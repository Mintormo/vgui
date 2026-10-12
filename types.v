module vgui

// ═══════════════════════════════════════════════════════
// types.v - базовые типы-значения и числовые помощники всей библиотеки.
//
// Здесь лежит то, на чём строится всё остальное:
//   - Rect  - прямоугольник в логических пикселях окна (bounds виджетов,
//             клип-области, dirty regions, hit-test);
//   - Color - RGBA-цвет темы и отрисовки с операциями смешивания;
//   - Vec2  - пара координат;
//   - min/max/clamp/abs для f32 и int, lerp.
// Вся геометрия библиотеки в f32, а math.* работает с f64 - собственные
// помощники избавляют от преобразований туда-обратно на каждом вызове.
// Файл не зависит ни от SDL, ни от других частей vgui.
// ═══════════════════════════════════════════════════════

// Rect - прямоугольник: (x, y) - левый верхний угол, w/h - ширина и высота.
// Координаты логические (до умножения на ui_scale), начало - левый верхний
// угол окна. Отрицательные w/h нигде не нормализуются - вызывающий код
// сам следит, чтобы их не было (shrunk() на слишком маленьком Rect их даёт).
pub struct Rect {
pub mut:
	x f32
	y f32
	w f32
	h f32
}

// contains - попадает ли точка (px, py) в прямоугольник. Обе границы
// включительно: точка на правом/нижнем крае тоже считается внутри, поэтому
// у соседних виджетов, стоящих встык, общий край попадает в оба.
pub fn (r Rect) contains(px f32, py f32) bool {
	return px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h
}

// intersects - перекрываются ли прямоугольники. Строгие неравенства: прямоугольники,
// лишь касающиеся краем, НЕ пересекаются (так работает отсечение по клипу и
// dirty regions - касание не требует перерисовки).
pub fn (r Rect) intersects(other Rect) bool {
	return r.x < other.x + other.w && r.x + r.w > other.x && r.y < other.y + other.h
		&& r.y + r.h > other.y
}

// intersection - общая часть двух прямоугольников. Если они не пересекаются
// (или пересечение вырождено в линию), возвращается нулевой Rect{0,0,0,0}.
pub fn (r Rect) intersection(other Rect) Rect {
	x1 := max_f32(r.x, other.x)
	y1 := max_f32(r.y, other.y)
	x2 := min_f32(r.x + r.w, other.x + other.w)
	y2 := min_f32(r.y + r.h, other.y + other.h)
	if x2 <= x1 || y2 <= y1 {
		return Rect{0, 0, 0, 0}
	}
	return Rect{x1, y1, x2 - x1, y2 - y1}
}

// expanded - прямоугольник, раздвинутый на pad со всех четырёх сторон
// (например, для кольца фокуса вокруг виджета). Отрицательный pad сжимает.
pub fn (r Rect) expanded(pad f32) Rect {
	return Rect{r.x - pad, r.y - pad, r.w + pad * 2, r.h + pad * 2}
}

// shrunk - обратное expanded: отступ pad внутрь со всех сторон (рамки,
// внутренние поля). Если pad больше половины стороны, w/h станут отрицательными.
pub fn (r Rect) shrunk(pad f32) Rect {
	return Rect{r.x + pad, r.y + pad, r.w - pad * 2, r.h - pad * 2}
}

// Color - цвет RGBA, по байту на канал; альфа по умолчанию 255 (непрозрачный),
// поэтому Color{r, g, b} - сплошной цвет.
pub struct Color {
pub mut:
	r u8
	g u8
	b u8
	a u8 = 255
}

// with_alpha - тот же цвет с другой прозрачностью.
pub fn (c Color) with_alpha(a u8) Color {
	return Color{c.r, c.g, c.b, a}
}

// blend - линейная интерполяция цвета к other: t = 0 даёт c, t = 1 даёт other,
// 0.3 - «на 30% ближе к other». Смешиваются все четыре канала, включая альфу.
// t за пределами [0, 1] не обрезается - вызывающий код передаёт значения
// анимаций, которые и так лежат в [0, 1]. Дробная часть отбрасывается (u8()).
pub fn (c Color) blend(other Color, t f32) Color {
	it := 1.0 - t
	return Color{
		r: u8(f32(c.r) * it + f32(other.r) * t)
		g: u8(f32(c.g) * it + f32(other.g) * t)
		b: u8(f32(c.b) * it + f32(other.b) * t)
		a: u8(f32(c.a) * it + f32(other.a) * t)
	}
}

// brighten - осветлить: прибавить amount * 255 к каждому RGB-каналу с
// насыщением на 255 (amount = 0.1 - примерно «на 10% светлее»). Альфа не меняется.
pub fn (c Color) brighten(amount f32) Color {
	return Color{
		r: u8(min_f32(255, f32(c.r) + 255.0 * amount))
		g: u8(min_f32(255, f32(c.g) + 255.0 * amount))
		b: u8(min_f32(255, f32(c.b) + 255.0 * amount))
		a: c.a
	}
}

// darken - затемнить: вычесть amount * 255 из RGB-каналов с насыщением на 0.
// Это не умножение яркости, поэтому тёмные цвета быстро уходят в чёрный.
pub fn (c Color) darken(amount f32) Color {
	return Color{
		r: u8(max_f32(0, f32(c.r) - 255.0 * amount))
		g: u8(max_f32(0, f32(c.g) - 255.0 * amount))
		b: u8(max_f32(0, f32(c.b) - 255.0 * amount))
		a: c.a
	}
}

// Vec2 - точка или вектор на плоскости в f32.
pub struct Vec2 {
pub mut:
	x f32
	y f32
}

// Числовые помощники для f32 и int: работают в исходном типе, без
// преобразования в f64, как у math.max/min.
pub fn max_f32(a f32, b f32) f32 {
	return if a > b { a } else { b }
}

pub fn min_f32(a f32, b f32) f32 {
	return if a < b { a } else { b }
}

pub fn abs_f32(v f32) f32 {
	return if v < 0 { -v } else { v }
}

// clamp_f32 - ограничить v отрезком [lo, hi]. При lo > hi результат зависит от v (v < lo -> lo, иначе v > hi -> hi), поэтому
// вызывающий должен сам следить, чтобы lo <= hi.
pub fn clamp_f32(v f32, lo f32, hi f32) f32 {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

pub fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

pub fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

// clamp_int - ограничить v отрезком [lo, hi]. При lo > hi результат зависит от v (v < lo -> lo, иначе v > hi -> hi), поэтому
// вызывающий должен сам следить, чтобы lo <= hi.
pub fn clamp_int(v int, lo int, hi int) int {
	if v < lo {
		return lo
	}
	if v > hi {
		return hi
	}
	return v
}

pub fn abs_int(v int) int {
	return if v < 0 { -v } else { v }
}

// lerp - линейная интерполяция между a и b: t = 0 -> a, t = 1 -> b.
// t не ограничивается - при t вне [0, 1] получается экстраполяция.
pub fn lerp(a f32, b f32, t f32) f32 {
	return a + (b - a) * t
}

// anim_running - «ещё не доехало ли значение до цели» с допуском 0.005.
// Остаток эпохи до общего класса Anim (anim.v): сейчас в библиотеке не
// вызывается, анимации проверяют завершение через Anim.update()/animating().
fn anim_running(current f32, target f32) bool {
	return abs_f32(current - target) > 0.005
}
