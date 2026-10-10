module vgui

import math

// ═══════════════════════════════════════════════════════
// CurveEditor — редактор тональной кривой (как «Кривые» в фоторедакторах)
//
// Кривая y(x) на квадрате 0..1 задаётся опорными точками и проходит через
// них монотонным кубическим сплайном (Фрич–Карлсон): без выбросов между
// точками, монотонные точки дают монотонную кривую. Крайние точки есть
// всегда (x = 0 и x = 1) и двигаются только по вертикали.
//
// Мышь: левая кнопка на точке — перетаскивание; на пустом месте — новая
// точка в месте клика (и сразу перетаскивание); правая кнопка на точке —
// удаление (кроме крайних); двойной клик — сброс кривой в диагональ.
//
// on_change зовётся при каждом движении точки (живой предпросмотр),
// on_release — один раз по окончании правки (отпускание, добавление,
// удаление, сброс двойным кликом). Тяжёлую работу вешать на on_release.
//
// Фон: необязательная гистограмма (histogram, значения 0..1 по x) и
// «призрачные» кривые (ghosts) — например, кривые других каналов.
//
// Usage:
//   mut ce := vgui.curve_editor()
//   ce.curve_color = vgui.Color{220, 60, 60, 255}
//   ce.on_release = fn [mut ce] () { lut := ce.lut(256) ... }
// ═══════════════════════════════════════════════════════

pub struct CurvePoint {
pub mut:
	x f32
	y f32
}

// CurveGhost — фоновая кривая для сравнения (не редактируется)
pub struct CurveGhost {
pub mut:
	points []CurvePoint
	color  Color
}

const ce_max_points = 16
const ce_min_gap = f32(0.01) // минимальный зазор по x между соседними точками

@[heap]
pub struct CurveEditor {
pub mut:
	type_tag int = kind_curve_editor // тег типа, см. widget_tag.v
	bounds   Rect
	visible  bool         = true
	enabled  bool         = true
	points   []CurvePoint = [CurvePoint{0, 0}, CurvePoint{1, 1}]
	// Цвет кривой; a == 0 — акцент темы. Значение по умолчанию задано
	// явно: у Color альфа по умолчанию 255 (это был бы чёрный)
	curve_color  Color = Color{0, 0, 0, 0}
	point_radius f32   = 4
	grid_divs    int   = 4
	// Гистограмма под кривой: столбцы по x, высоты 0..1; пусто — нет
	histogram       []f32
	histogram_color Color = Color{0, 0, 0, 0} // a == 0 — приглушённый цвет текста темы
	ghosts          []CurveGhost
	on_change       fn () = unsafe { nil }
	on_release      fn () = unsafe { nil }
	// Состояние мыши
	hovered_pt int = -1
	drag_pt    int = -1
}

pub fn curve_editor() &CurveEditor {
	return &CurveEditor{}
}

// ─── Public API ────────────────────────────────────────

// set_points заменяет точки: сортирует по x, клампит в 0..1, добавляет
// крайние точки, если их нет. Меньше двух точек — диагональ.
pub fn (mut ce CurveEditor) set_points(pts []CurvePoint) {
	ce.points = normalize_curve_points(pts)
	ce.hovered_pt = -1
	ce.drag_pt = -1
}

// reset — диагональ (тождественная кривая)
pub fn (mut ce CurveEditor) reset() {
	ce.set_points([])
}

// is_identity — кривая совпадает с диагональю (все точки на ней)
pub fn (ce &CurveEditor) is_identity() bool {
	return curve_is_identity(ce.points)
}

// value — значение кривой в x (0..1)
pub fn (ce &CurveEditor) value(x f32) f32 {
	return curve_eval(ce.points, x)
}

// lut — кривая, выбранная в n равномерных точках x = i/(n-1), значения 0..1
pub fn (ce &CurveEditor) lut(n int) []f32 {
	return curve_lut(ce.points, n)
}

pub fn (mut ce CurveEditor) add_ghost(pts []CurvePoint, color Color) {
	ce.ghosts << CurveGhost{normalize_curve_points(pts), color}
}

pub fn (mut ce CurveEditor) clear_ghosts() {
	ce.ghosts.clear()
}

// ─── Математика кривой (свободные функции — годятся и без виджета) ───

// normalize_curve_points — точки по возрастанию x, в 0..1, с крайними
fn normalize_curve_points(pts []CurvePoint) []CurvePoint {
	mut p := []CurvePoint{}
	for q in pts {
		p << CurvePoint{clamp_f32(q.x, 0, 1), clamp_f32(q.y, 0, 1)}
	}
	p.sort(a.x < b.x)
	if p.len == 0 {
		return [CurvePoint{0, 0}, CurvePoint{1, 1}]
	}
	// Крайние точки продолжают кривую горизонтально от ближайшей точки
	if p[0].x > 0 {
		first_y := p[0].y
		p.insert(0, CurvePoint{
			x: 0
			y: first_y
		})
	}
	if p[p.len - 1].x < 1 {
		last_y := p[p.len - 1].y
		p << CurvePoint{
			x: 1
			y: last_y
		}
	}
	return p
}

pub fn curve_is_identity(pts []CurvePoint) bool {
	for q in pts {
		if math.abs(q.x - q.y) > 1e-4 {
			return false
		}
	}
	return true
}

// curve_tangents — касательные монотонного кубического сплайна
// (Фрич–Карлсон): на участке с нулевым наклоном касательные нулевые,
// иначе ограничены так, чтобы кривая не выходила за соседние точки.
fn curve_tangents(p []CurvePoint) []f32 {
	n := p.len
	mut d := []f32{len: n - 1}
	for i in 0 .. n - 1 {
		dx := p[i + 1].x - p[i].x
		d[i] = if dx > 0 { (p[i + 1].y - p[i].y) / dx } else { f32(0) }
	}
	mut m := []f32{len: n}
	m[0] = d[0]
	m[n - 1] = d[n - 2]
	for i in 1 .. n - 1 {
		m[i] = if d[i - 1] * d[i] <= 0 { f32(0) } else { (d[i - 1] + d[i]) * 0.5 }
	}
	for i in 0 .. n - 1 {
		if d[i] == 0 {
			m[i] = 0
			m[i + 1] = 0
			continue
		}
		a := m[i] / d[i]
		b := m[i + 1] / d[i]
		s := a * a + b * b
		if s > 9 {
			t := 3 / math.sqrtf(s)
			m[i] = t * a * d[i]
			m[i + 1] = t * b * d[i]
		}
	}
	return m
}

fn hermite(p []CurvePoint, m []f32, x f32) f32 {
	n := p.len
	if x <= p[0].x {
		return p[0].y
	}
	if x >= p[n - 1].x {
		return p[n - 1].y
	}
	mut i := 0
	for i < n - 2 && x > p[i + 1].x {
		i++
	}
	h := p[i + 1].x - p[i].x
	if h <= 0 {
		return p[i].y
	}
	t := (x - p[i].x) / h
	t2 := t * t
	t3 := t2 * t
	return (2 * t3 - 3 * t2 + 1) * p[i].y + (t3 - 2 * t2 + t) * h * m[i] +
		(-2 * t3 + 3 * t2) * p[i + 1].y + (t3 - t2) * h * m[i + 1]
}

// curve_eval — значение кривой в точке x (0..1), результат в 0..1
pub fn curve_eval(pts []CurvePoint, x f32) f32 {
	if pts.len < 2 {
		return x
	}
	m := curve_tangents(pts)
	return clamp_f32(hermite(pts, m, x), 0, 1)
}

// curve_lut — n равномерных выборок кривой (x = i/(n-1)), значения 0..1
pub fn curve_lut(pts []CurvePoint, n int) []f32 {
	mut out := []f32{len: n}
	if n <= 0 {
		return out
	}
	if pts.len < 2 {
		for i in 0 .. n {
			out[i] = if n > 1 { f32(i) / f32(n - 1) } else { 0 }
		}
		return out
	}
	m := curve_tangents(pts)
	for i in 0 .. n {
		x := if n > 1 { f32(i) / f32(n - 1) } else { f32(0) }
		out[i] = clamp_f32(hermite(pts, m, x), 0, 1)
	}
	return out
}

// ─── Геометрия ─────────────────────────────────────────

fn (ce &CurveEditor) plot_rect() Rect {
	return ce.bounds.shrunk(ce.point_radius + 2)
}

fn (ce &CurveEditor) to_screen(r Rect, x f32, y f32) (f32, f32) {
	return r.x + x * r.w, r.y + (1 - y) * r.h
}

fn (ce &CurveEditor) from_screen(r Rect, sx f32, sy f32) (f32, f32) {
	if r.w <= 0 || r.h <= 0 {
		return 0, 0
	}
	return clamp_f32((sx - r.x) / r.w, 0, 1), clamp_f32(1 - (sy - r.y) / r.h, 0, 1)
}

// point_at — индекс точки под курсором (радиус захвата вдвое больше точки)
fn (ce &CurveEditor) point_at(sx f32, sy f32) int {
	r := ce.plot_rect()
	grab := ce.point_radius * 2 + 2
	mut best := -1
	mut best_d := grab * grab
	for i, p in ce.points {
		px, py := ce.to_screen(r, p.x, p.y)
		d := (px - sx) * (px - sx) + (py - sy) * (py - sy)
		if d <= best_d {
			best_d = d
			best = i
		}
	}
	return best
}

// move_point двигает точку i в (x, y): крайние — только по вертикали,
// внутренние — между соседями с зазором ce_min_gap.
fn (mut ce CurveEditor) move_point(i int, x f32, y f32) {
	n := ce.points.len
	mut nx := x
	if i == 0 {
		nx = 0
	} else if i == n - 1 {
		nx = 1
	} else {
		nx = clamp_f32(x, ce.points[i - 1].x + ce_min_gap, ce.points[i + 1].x - ce_min_gap)
	}
	ce.points[i] = CurvePoint{nx, clamp_f32(y, 0, 1)}
}

// insert_point вставляет точку по порядку x; -1 — нельзя (лимит или
// слишком близко к соседней).
fn (mut ce CurveEditor) insert_point(x f32, y f32) int {
	if ce.points.len >= ce_max_points {
		return -1
	}
	mut idx := ce.points.len - 1
	for i in 1 .. ce.points.len {
		if x < ce.points[i].x {
			idx = i
			break
		}
	}
	if x - ce.points[idx - 1].x < ce_min_gap || ce.points[idx].x - x < ce_min_gap {
		return -1
	}
	ce.points.insert(idx, CurvePoint{x, clamp_f32(y, 0, 1)})
	return idx
}

fn (ce &CurveEditor) fire_change() {
	if ce.on_change != unsafe { nil } {
		ce.on_change()
	}
}

fn (ce &CurveEditor) fire_release() {
	if ce.on_release != unsafe { nil } {
		ce.on_release()
	}
}

// ─── Drawing ───────────────────────────────────────────

fn (ce &CurveEditor) draw_curve(mut ctx RenderContext, r Rect, pts []CurvePoint, col Color, thick u8) {
	if pts.len < 2 {
		return
	}
	m := curve_tangents(pts)
	steps := int(math.max(r.w / 2, 16))
	mut px, mut py := ce.to_screen(r, 0, clamp_f32(hermite(pts, m, 0), 0, 1))
	for i in 1 .. steps + 1 {
		x := f32(i) / f32(steps)
		nx, ny := ce.to_screen(r, x, clamp_f32(hermite(pts, m, x), 0, 1))
		ctx.draw_line_thick(px, py, nx, ny, thick, col)
		px = nx
		py = ny
	}
}

pub fn (mut ce CurveEditor) draw(mut ctx RenderContext) {
	if !ce.visible || !ctx.is_in_clip(ce.bounds) {
		return
	}
	r := ce.plot_rect()
	ctx.fill_rect(ce.bounds, ctx.theme.plot_bg)
	ctx.push_clip(ce.bounds)

	// Гистограмма
	if ce.histogram.len > 0 {
		hc := if ce.histogram_color.a > 0 {
			ce.histogram_color
		} else {
			c := ctx.theme.text_secondary
			Color{c.r, c.g, c.b, 40}
		}
		// Столбцы стык в стык по целым пикселям: дробная ширина с нахлёстом
		// дважды накладывала полупрозрачный цвет - светлые полосы
		n := ce.histogram.len
		bw := r.w / f32(n)
		for i, v in ce.histogram {
			hv := clamp_f32(v, 0, 1) * r.h
			if hv <= 0 {
				continue
			}
			x0 := math.floorf(r.x + f32(i) * bw)
			x1 := math.floorf(r.x + f32(i + 1) * bw)
			if x1 <= x0 {
				continue // столбцы уже пикселя - соседний покроет этот пиксель
			}
			ctx.fill_rect(Rect{x0, r.y + r.h - hv, x1 - x0, hv}, hc)
		}
	}

	// Сетка и диагональ
	divs := if ce.grid_divs > 0 { ce.grid_divs } else { 4 }
	gc := ctx.theme.plot_grid_major
	for i in 1 .. divs {
		gx := r.x + r.w * f32(i) / f32(divs)
		gy := r.y + r.h * f32(i) / f32(divs)
		ctx.draw_line(gx, r.y, gx, r.y + r.h, gc)
		ctx.draw_line(r.x, gy, r.x + r.w, gy, gc)
	}
	ctx.draw_line(r.x, r.y + r.h, r.x + r.w, r.y, ctx.theme.plot_grid_minor)
	ctx.draw_rect(r, ctx.theme.plot_border)

	// Призрачные кривые, затем своя
	for g in ce.ghosts {
		if !curve_is_identity(g.points) {
			ce.draw_curve(mut ctx, r, g.points, g.color, 1)
		}
	}
	cc := if ce.curve_color.a > 0 { ce.curve_color } else { ctx.theme.accent }
	ce.draw_curve(mut ctx, r, ce.points, cc, 2)

	// Точки: активная (под курсором / перетаскиваемая) крупнее и с обводкой
	for i, p in ce.points {
		px, py := ce.to_screen(r, p.x, p.y)
		active := i == ce.drag_pt || (ce.drag_pt < 0 && i == ce.hovered_pt)
		rad := if active { ce.point_radius + 1.5 } else { ce.point_radius }
		ctx.fill_circle(px, py, rad + 1, ctx.theme.plot_bg)
		ctx.fill_circle(px, py, rad, cc)
		if active {
			ctx.draw_circle(px, py, rad + 2, ctx.theme.text_primary)
		}
	}
	ctx.pop_clip()
}

// ─── Events ────────────────────────────────────────────

pub fn (mut ce CurveEditor) handle_event(event &GuiEvent, app &App) bool {
	if !ce.visible || !ce.enabled {
		return false
	}
	r := ce.plot_rect()
	inside := ce.bounds.contains(event.mouse_x, event.mouse_y)
	match event.typ {
		.mouse_move {
			if ce.drag_pt >= 0 {
				x, y := ce.from_screen(r, event.mouse_x, event.mouse_y)
				ce.move_point(ce.drag_pt, x, y)
				ce.fire_change()
				return true
			}
			ce.hovered_pt = if inside { ce.point_at(event.mouse_x, event.mouse_y) } else { -1 }
		}
		.mouse_down {
			if !inside {
				return false
			}
			if event.mouse_btn == .left {
				mut i := ce.point_at(event.mouse_x, event.mouse_y)
				if i < 0 {
					x, y := ce.from_screen(r, event.mouse_x, event.mouse_y)
					i = ce.insert_point(x, y)
					if i >= 0 {
						ce.fire_change()
					}
				}
				ce.drag_pt = i
				return true
			}
			if event.mouse_btn == .right {
				i := ce.point_at(event.mouse_x, event.mouse_y)
				if i > 0 && i < ce.points.len - 1 {
					ce.points.delete(i)
					ce.hovered_pt = -1
					ce.fire_change()
					ce.fire_release()
				}
				return true
			}
		}
		.mouse_dbl_click {
			// Первый клик пары уже пришёл как mouse_down (точка могла
			// добавиться) - сброс в диагональ всё равно убирает всё
			if inside && event.mouse_btn == .left {
				ce.reset()
				ce.fire_change()
				ce.fire_release()
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && ce.drag_pt >= 0 {
				ce.drag_pt = -1
				ce.hovered_pt = if inside { ce.point_at(event.mouse_x, event.mouse_y) } else { -1 }
				ce.fire_release()
				return true
			}
		}
		else {}
	}
	return false
}
