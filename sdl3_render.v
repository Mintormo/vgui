module vgui

// ═══════════════════════════════════════════════════════
// SDL3 implementation of RenderContext drawing methods
// ═══════════════════════════════════════════════════════

// Файл sdl3_render.v: реализация рисовальных примитивов RenderContext поверх SDL3: отсечение
// (clip), прямоугольники, скруглённые прямоугольники, линии, круги, треугольники. Все координаты -
// ЛОГИЧЕСКИЕ; физический масштаб задаёт SDL_SetRenderScale = dpi_scale * ui_scale (выставляется
// окном, sdl3_hdpi.v / sdl3_window.v). Скруглённые фигуры, круги и т.п. рисуются не через
// SDL2_gfx, а треугольниками (SDL_RenderGeometry): заполненные - веером от центра, контуры -
// полосой трапеций между внешним и внутренним контуром, чтобы граница получалась ровно в
// один физический пиксель и без смещения, свойственного SDL_RenderLine. Каждая функция сама
// выставляет blend mode (alpha-смешивание), на предыдущем состоянии не полагаясь.
// Текст и иконки - в sdl3_fonts.v и других файлах; высокоуровневые виджеты вызывают методы
// RenderContext отсюда, а функции render_* - внутренние.

import math

// ─── Clipping ───

// clip_pad — на сколько логических пикселей реальный клип SDL шире клипа из
// clip_stack. Одна константа для clip_sdl_rect и RenderContext.is_in_clip: что
// очищено при частичной перерисовке, то обязано и перерисовываться.
const clip_pad = 1

// Переводит логический Rect в целочисленный SDL_Rect для SDL_SetRenderClipRect: границы
// округляются наружу (floor/ceil) и расширяются ещё на clip_pad со всех сторон, чтобы обводка
// ровно по границе области не обрезалась половиной своего пикселя.
fn clip_sdl_rect(r Rect) C.SDL_Rect {
	// Use floor/ceil to avoid losing fractional pixels when converting to int,
	// then expand by 1 extra logical unit so border strokes drawn exactly on
	// the boundary are never clipped by the half-pixel outer contour.
	x0 := int(math.floor(f64(r.x))) - clip_pad
	y0 := int(math.floor(f64(r.y))) - clip_pad
	x1 := int(math.ceil(f64(r.x + r.w))) + clip_pad
	y1 := int(math.ceil(f64(r.y + r.h))) + clip_pad
	return C.SDL_Rect{x0, y0, x1 - x0, y1 - y0}
}

// Включает область отсечения r, пересекая её с текущей (вложенные клипы только сужают область) и
// запоминает в clip_stack. Каждому push_clip обязан соответствовать pop_clip.
pub fn (mut ctx RenderContext) push_clip(r Rect) {
	actual := if ctx.clip_stack.len > 0 {
		r.intersection(ctx.clip_stack[ctx.clip_stack.len - 1])
	} else {
		r
	}
	ctx.clip_stack << actual
	sdl_rect := clip_sdl_rect(actual)
	C.SDL_SetRenderClipRect(ctx.renderer, &sdl_rect)
}

// Снимает последнюю область отсечения и возвращает предыдущую; при пустом стеке отсечение
// отключается совсем (nil).
pub fn (mut ctx RenderContext) pop_clip() {
	if ctx.clip_stack.len > 0 {
		ctx.clip_stack.delete(ctx.clip_stack.len - 1)
	}
	if ctx.clip_stack.len > 0 {
		last := ctx.clip_stack[ctx.clip_stack.len - 1]
		sdl_rect := clip_sdl_rect(last)
		C.SDL_SetRenderClipRect(ctx.renderer, &sdl_rect)
	} else {
		C.SDL_SetRenderClipRect(ctx.renderer, unsafe { nil })
	}
}

// ─── Primitives ───

// Заливка прямоугольника цветом c с alpha-смешиванием. Без привязки к физическим пикселям:
// края могут быть дробными.
pub fn (mut ctx RenderContext) fill_rect(r Rect, c Color) {
	C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)
	C.SDL_SetRenderDrawColor(ctx.renderer, c.r, c.g, c.b, c.a)
	sdl_rect := C.SDL_FRect{
		x: r.x
		y: r.y
		w: r.w
		h: r.h
	}
	C.SDL_RenderFillRect(ctx.renderer, &sdl_rect)
}

// Рамка толщиной ровно 1 физический пиксель (а не логический): границы округляются до
// физической сетки и рисуются четырьмя заливками. Так линия не расплывается при дробном масштабе.
pub fn (mut ctx RenderContext) draw_rect(r Rect, c Color) {
	// Snap to physical pixels to avoid sub-pixel bleed at fractional render scale.
	// SDL render scale = dpi_scale * ui_scale; all geometry is in logical units.
	s := ctx.dpi_scale * ctx.ui_scale
	inv := if s > 0 { 1.0 / s } else { f32(1.0) }
	x0 := f32(int(r.x * s + 0.5)) * inv
	y0 := f32(int(r.y * s + 0.5)) * inv
	x1 := f32(int((r.x + r.w) * s + 0.5)) * inv
	y1 := f32(int((r.y + r.h) * s + 0.5)) * inv
	pw := inv // one physical pixel in logical units
	ctx.fill_rect(Rect{x0, y0, x1 - x0, pw}, c)
	ctx.fill_rect(Rect{x0, y1 - pw, x1 - x0, pw}, c)
	ctx.fill_rect(Rect{x0, y0 + pw, pw, y1 - y0 - pw * 2}, c)
	ctx.fill_rect(Rect{x1 - pw, y0 + pw, pw, y1 - y0 - pw * 2}, c)
}

// Привязывает все четыре границы прямоугольника к физической пиксельной сетке (округление к
// ближайшему). Нужна скруглённым фигурам, чтобы заливка и обводка совпадали попиксельно.
fn (ctx &RenderContext) snap_rect(r Rect) Rect {
	s := ctx.dpi_scale * ctx.ui_scale
	if s <= 0 {
		return r
	}
	inv := f32(1.0) / s
	x0 := f32(math.round(f64(r.x) * f64(s))) * inv
	y0 := f32(math.round(f64(r.y) * f64(s))) * inv
	x1 := f32(math.round(f64(r.x + r.w) * f64(s))) * inv
	y1 := f32(math.round(f64(r.y + r.h) * f64(s))) * inv
	return Rect{x0, y0, x1 - x0, y1 - y0}
}

// Скруглённый прямоугольник (радиус <= 0 - обычный fill_rect). Границы привязываются к пикселям.
pub fn (mut ctx RenderContext) fill_rounded_rect(r Rect, c Color, radius f32) {
	if radius <= 0 {
		ctx.fill_rect(r, c)
		return
	}
	sr := ctx.snap_rect(r)
	render_fill_rounded_rect(ctx.renderer, sr.x, sr.y, sr.w, sr.h, radius, c)
}

// Контур скруглённого прямоугольника толщиной в 1 физический пиксель (радиус <= 0 - draw_rect).
pub fn (mut ctx RenderContext) draw_rounded_rect(r Rect, c Color, radius f32) {
	if radius <= 0 {
		ctx.draw_rect(r, c)
		return
	}
	sr := ctx.snap_rect(r)
	render_draw_rounded_rect(ctx.renderer, sr.x, sr.y, sr.w, sr.h, radius, c, ctx.dpi_scale * ctx.ui_scale)
}

// Тонкая линия (1 пиксель, средствами SDL).
pub fn (mut ctx RenderContext) draw_line(x1 f32, y1 f32, x2 f32, y2 f32, c Color) {
	C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)
	C.SDL_SetRenderDrawColor(ctx.renderer, c.r, c.g, c.b, c.a)
	C.SDL_RenderLine(ctx.renderer, x1, y1, x2, y2)
}

// Линия толщиной thickness (в логических единицах); при thickness <= 1 - обычная draw_line.
pub fn (mut ctx RenderContext) draw_line_thick(x1 f32, y1 f32, x2 f32, y2 f32, thickness u8, c Color) {
	if thickness <= 1 {
		ctx.draw_line(x1, y1, x2, y2, c)
		return
	}
	render_thick_line(ctx.renderer, x1, y1, x2, y2, f32(thickness), c)
}

// Заполненный круг с центром (cx, cy). Тонкие обёртки над render_* ниже.
pub fn (mut ctx RenderContext) fill_circle(cx f32, cy f32, radius f32, c Color) {
	render_fill_circle(ctx.renderer, cx, cy, radius, c)
}

// Кольцо-контур круга шириной 1 логическая единица (в отличие от draw_rect, не 1 физический пиксель).
pub fn (mut ctx RenderContext) draw_circle(cx f32, cy f32, radius f32, c Color) {
	render_draw_circle(ctx.renderer, cx, cy, radius, c)
}

// Заполненный треугольник по трём вершинам.
pub fn (mut ctx RenderContext) fill_triangle(x1 f32, y1 f32, x2 f32, y2 f32, x3 f32, y3 f32, c Color) {
	render_fill_triangle(ctx.renderer, x1, y1, x2, y2, x3, y3, c)
}

// То же, что fill_rounded_rect, но БЕЗ привязки к физическим пикселям. Для "таблеток" (радиус
// равен половине меньшей стороны), у которых точные границы и так задаются размером.
pub fn (mut ctx RenderContext) fill_pill_rect(r Rect, c Color, radius f32) {
	if radius <= 0 {
		ctx.fill_rect(r, c)
		return
	}
	render_fill_rounded_rect(ctx.renderer, r.x, r.y, r.w, r.h, radius, c)
}

// ═══════════════════════════════════════════════════════
// GFX replacement: filled rounded rect via SDL_RenderGeometry
// ═══════════════════════════════════════════════════════

// Renders a filled rounded rectangle using SDL_RenderGeometry.
// This replaces SDL2_gfx roundedBoxRGBA.
// Радиус ограничивается половиной меньшей стороны. Контур строится из четырёх дуг по 90
// градусов (n+1 точек на дугу, n растёт с радиусом, минимум 8); дуги идут по часовой стрелке
// начиная с левого верхнего угла, соседние дуги соединяются прямыми рёбрами автоматически, так
// как последняя точка одной дуги и первая следующей соседние в массиве. Заливка - веер
// треугольников от центра прямоугольника по точкам контура (веер корректен, т.к. фигура выпуклая).
fn render_fill_rounded_rect(renderer voidptr, x f32, y f32, w f32, h f32, radius f32, c Color) {
	if w <= 0 || h <= 0 {
		return
	}
	mut r := radius
	max_r := min_f32(w, h) * 0.5
	if r > max_r {
		r = max_r
	}

	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}

	// Use the same contour geometry as render_draw_rounded_rect so the fill boundary
	// is pixel-identical to the border outline drawn on top of it.
	// Outer contour = the arc at radius r.
	// Inner "spine" points collapse toward the rect centre — we use a quad strip
	// where inner points are the corner centres (x+r,y+r etc.), giving a proper fill
	// without fan seams at the straight-edge junctions.
	n := int(math.max(8.0, f64(r) * 2.0))

	corners := [
		[x + r, y + r, f32(180.0), f32(270.0)], // top-left
		[x + w - r, y + r, f32(270.0), f32(360.0)], // top-right
		[x + w - r, y + h - r, f32(0.0), f32(90.0)], // bottom-right
		[x + r, y + h - r, f32(90.0), f32(180.0)], // bottom-left
	]

	mut arc_pts := []C.SDL_FPoint{cap: (n + 1) * 4}
	for seg in corners {
		cx_ := seg[0]
		cy_ := seg[1]
		sa := seg[2]
		ea := seg[3]
		for i in 0 .. n + 1 {
			a_deg := sa + f32(i) * (ea - sa) / f32(n)
			a := math.pi * f64(a_deg) / 180.0
			arc_pts << C.SDL_FPoint{cx_ + f32(math.cos(a)) * r, cy_ + f32(math.sin(a)) * r}
		}
	}

	// Centre of the whole rect — all triangles fan from here.
	cx := x + w * 0.5
	cy := y + h * 0.5
	cv := C.SDL_Vertex{ position: C.SDL_FPoint{cx, cy}, color: fc, tex_coord: C.SDL_FPoint{0, 0} }

	total := arc_pts.len
	mut verts := []C.SDL_Vertex{cap: (total + 1) * 3}
	for i in 0 .. total - 1 {
		verts << cv
		verts << C.SDL_Vertex{ position: arc_pts[i], color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		verts << C.SDL_Vertex{ position: arc_pts[i + 1], color: fc, tex_coord: C.SDL_FPoint{0, 0} }
	}
	// close the loop
	verts << cv
	verts << C.SDL_Vertex{ position: arc_pts[total - 1], color: fc, tex_coord: C.SDL_FPoint{0, 0} }
	verts << C.SDL_Vertex{ position: arc_pts[0], color: fc, tex_coord: C.SDL_FPoint{0, 0} }

	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

// Renders an outline rounded rectangle as a geometry ring (quad strips).
// Each segment is a trapezoid between the outer and inner contour — no SDL_RenderLine bias.
// Параметр ui_scale здесь на самом деле комбинированный масштаб (dpi_scale * ui_scale) - так его
// передаёт draw_rounded_rect. Толщина обводки = 1 физический пиксель: внутренний контур
// смещён на радиус r - 2t, где t = 0.5/scale (полутолщина в логических единицах).
fn render_draw_rounded_rect(renderer voidptr, x f32, y f32, w f32, h f32, radius f32, c Color, ui_scale f32) {
	if w <= 0 || h <= 0 {
		return
	}
	mut r := radius
	max_r := min_f32(w, h) * 0.5
	if r > max_r {
		r = max_r
	}

	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}

	// Build one closed contour of (outer, inner) point pairs going around the rect.
	// Each segment of the contour covers a corner arc plus the joining straight edges.
	// This avoids any seams between arcs and straights.
	n := int(math.max(8.0, f64(r) * 2.0))
	// Half-stroke in logical units: 0.5 physical px / render_scale.
	// SDL_SetRenderScale = dpi_scale * ui_scale; all geometry coords are in logical units
	// and get multiplied by that combined scale. So t = 0.5 / combined_scale yields
	// exactly 1 physical pixel of stroke width at any scale.
	s := if ui_scale > 0 { ui_scale } else { f32(1.0) }
	t := f32(0.5) / s

	// Corner definitions: center, start angle (deg), end angle (deg)
	corners := [
		[x + r, y + r, f32(180.0), f32(270.0)], // top-left
		[x + w - r, y + r, f32(270.0), f32(360.0)], // top-right
		[x + w - r, y + h - r, f32(0.0), f32(90.0)], // bottom-right
		[x + r, y + h - r, f32(90.0), f32(180.0)], // bottom-left
	]

	// Build a closed contour as a sequence of (outer, inner) point pairs.
	// For each corner: emit n+1 arc points (sa..ea inclusive).
	// Between consecutive corners the arc endpoints are NOT at the same location
	// (they are at opposite ends of a straight edge), so we just let the quad strip
	// span that gap — each straight edge is a degenerate-free trapezoid quad.
	mut outer_pts := []C.SDL_FPoint{cap: (n + 1) * 4}
	mut inner_pts := []C.SDL_FPoint{cap: (n + 1) * 4}

	for seg in corners {
		cx_ := seg[0]
		cy_ := seg[1]
		sa := seg[2]
		ea := seg[3]
		for i in 0 .. n + 1 {
			a_deg := sa + f32(i) * (ea - sa) / f32(n)
			a := math.pi * f64(a_deg) / 180.0
			ca := f32(math.cos(a))
			sn := f32(math.sin(a))
			outer_pts << C.SDL_FPoint{cx_ + ca * r, cy_ + sn * r}
			inner_pts << C.SDL_FPoint{cx_ + ca * (r - 2.0 * t), cy_ + sn * (r - 2.0 * t)}
		}
	}

	// Quad strip: iterate consecutive pairs, closing the loop at the end.
	total := outer_pts.len
	mut verts := []C.SDL_Vertex{cap: (total + 1) * 6}
	push_strip_quad := fn [fc] (mut vs []C.SDL_Vertex, o1 C.SDL_FPoint, i1 C.SDL_FPoint, o2 C.SDL_FPoint, i2 C.SDL_FPoint) {
		vo1 := C.SDL_Vertex{ position: o1, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vi1 := C.SDL_Vertex{ position: i1, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vo2 := C.SDL_Vertex{ position: o2, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vi2 := C.SDL_Vertex{ position: i2, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vs << vo1
		vs << vi1
		vs << vo2
		vs << vi1
		vs << vi2
		vs << vo2
	}
	// Внутри каждого угла - геометрия (соседние точки одной дуги). Четыре соединяющих
	// четырёхугольника (последняя точка угла -> первая следующего) - это прямые стороны:
	// полосы шириной ровно 1 физический пиксель, выровненные по осям. Их рисуем
	// SDL_RenderFillRects, а не геометрией: программный рендерер SDL распознаёт пару
	// треугольников-прямоугольник и рисует его как прямоугольник, ОТБРАСЫВАЯ дробную
	// часть размеров. Концы дуг несут погрешность float, и при дробном масштабе (1.25,
	// 1.5) ширина выходила 0.9999 пикселя -> 0: сторона рамки пропадала (GPU-рендереры
	// рисовали её верно). Поэтому стороны считаются, как в draw_rect: от границ,
	// привязанных к пиксельной сетке, с шириной ровно pw = 1 физический пиксель.
	per_corner := n + 1
	for i in 0 .. total {
		if (i + 1) % per_corner != 0 {
			next := (i + 1) % total
			push_strip_quad(mut verts, outer_pts[i], inner_pts[i], outer_pts[next], inner_pts[next])
		}
	}
	pw := f32(1.0) / s
	x0 := f32(int(x * s + 0.5)) * pw
	y0 := f32(int(y * s + 0.5)) * pw
	x1 := f32(int((x + w) * s + 0.5)) * pw
	y1 := f32(int((y + h) * s + 0.5)) * pw
	edges := [
		C.SDL_FRect{x0 + r, y0, x1 - x0 - 2 * r, pw}, // верх
		C.SDL_FRect{x0 + r, y1 - pw, x1 - x0 - 2 * r, pw}, // низ
		C.SDL_FRect{x0, y0 + r, pw, y1 - y0 - 2 * r}, // лево
		C.SDL_FRect{x1 - pw, y0 + r, pw, y1 - y0 - 2 * r}, // право
	]

	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
	C.SDL_SetRenderDrawColor(renderer, c.r, c.g, c.b, c.a)
	C.SDL_RenderFillRects(renderer, edges.data, edges.len)
}

// Filled circle via geometry.
// Replaces SDL2_gfx filledCircleRGBA.
// Круг - веер из n треугольников; n растёт с радиусом (минимум 12).
fn render_fill_circle(renderer voidptr, cx f32, cy f32, radius f32, c Color) {
	if radius <= 0 {
		return
	}
	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}
	n := int(math.max(12.0, f64(radius) * 1.2))
	mut verts := []C.SDL_Vertex{cap: n * 3}
	center := C.SDL_Vertex{
		position:  C.SDL_FPoint{cx, cy}
		color:     fc
		tex_coord: C.SDL_FPoint{0, 0}
	}
	for i in 0 .. n {
		a1 := 2.0 * math.pi * f64(i) / f64(n)
		a2 := 2.0 * math.pi * f64(i + 1) / f64(n)
		p1 := C.SDL_Vertex{
			position:  C.SDL_FPoint{cx + f32(math.cos(a1)) * radius, cy + f32(math.sin(a1)) * radius}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		}
		p2 := C.SDL_Vertex{
			position:  C.SDL_FPoint{cx + f32(math.cos(a2)) * radius, cy + f32(math.sin(a2)) * radius}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		}
		verts << center
		verts << p1
		verts << p2
	}
	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

// Circle outline as geometry ring — no SDL_RenderLine bias.
// Кольцо шириной 1 логическая единица: ro = r + 0.5, ri = r - 0.5. Число сегментов растёт с радиусом.
fn render_draw_circle(renderer voidptr, cx f32, cy f32, radius f32, c Color) {
	if radius <= 0 {
		return
	}
	t := f32(1.0)
	ro := radius + t * 0.5
	ri := f32(math.max(0.0, f64(radius) - f64(t) * 0.5))
	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}
	n := int(math.max(16.0, f64(radius) * 3.0))
	mut verts := []C.SDL_Vertex{cap: n * 6}
	for i in 0 .. n {
		a1 := 2.0 * math.pi * f64(i) / f64(n)
		a2 := 2.0 * math.pi * f64(i + 1) / f64(n)
		ca1 := f32(math.cos(a1))
		sa1 := f32(math.sin(a1))
		ca2 := f32(math.cos(a2))
		sa2 := f32(math.sin(a2))
		vo1 := C.SDL_Vertex{ position: C.SDL_FPoint{cx + ca1 * ro, cy + sa1 * ro}, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vi1 := C.SDL_Vertex{ position: C.SDL_FPoint{cx + ca1 * ri, cy + sa1 * ri}, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vo2 := C.SDL_Vertex{ position: C.SDL_FPoint{cx + ca2 * ro, cy + sa2 * ro}, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		vi2 := C.SDL_Vertex{ position: C.SDL_FPoint{cx + ca2 * ri, cy + sa2 * ri}, color: fc, tex_coord: C.SDL_FPoint{0, 0} }
		verts << vo1
		verts << vi1
		verts << vo2
		verts << vi1
		verts << vi2
		verts << vo2
	}
	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

// Filled triangle via geometry.
// Replaces SDL2_gfx filledTrigonRGBA.
fn render_fill_triangle(renderer voidptr, x1 f32, y1 f32, x2 f32, y2 f32, x3 f32, y3 f32, c Color) {
	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}
	verts := [
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x1, y1}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x2, y2}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x3, y3}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
	]
	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

// Thick line via filled quad (2 triangles).
// Replaces SDL2_gfx thickLineRGBA.
// Линия как прямоугольник из двух треугольников: вершины смещены на половину толщины вдоль
// нормали к направлению (nx, ny). Линия нулевой длины не рисуется (иначе деление на ноль).
fn render_thick_line(renderer voidptr, x1 f32, y1 f32, x2 f32, y2 f32, thickness f32, c Color) {
	dx := x2 - x1
	dy := y2 - y1
	len := f32(math.sqrt(f64(dx * dx + dy * dy)))
	if len < 0.001 {
		return
	}
	half := thickness * 0.5
	nx := -dy / len * half
	ny := dx / len * half

	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}
	verts := [
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x1 + nx, y1 + ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x2 + nx, y2 + ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x1 - nx, y1 - ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x2 + nx, y2 + ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x2 - nx, y2 - ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
		C.SDL_Vertex{
			position:  C.SDL_FPoint{x1 - nx, y1 - ny}
			color:     fc
			tex_coord: C.SDL_FPoint{0, 0}
		},
	]
	C.SDL_SetRenderDrawBlendMode(renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

// ═══════════════════════════════════════════════════════
// Ломаные и наборы треугольников (PlotView, Spinner)
// ═══════════════════════════════════════════════════════
//
// Виджеты с собственной геометрией раньше собирали массивы SDL_FPoint /
// SDL_Vertex сами и звали SDL напрямую (PROJECT.md, «Бэкенд рисования: виджеты
// не зовут SDL напрямую»). Теперь они передают точки в логических координатах
// (Vec2), а SDL-типы и blend mode - забота этого файла. Масштаб HiDPI, как и у
// остальных примитивов, делает SDL_SetRenderScale окна.

// to_sdl_points переводит точки в массив SDL_FPoint (раскладка Vec2 та же, но
// полагаться на это - лишняя хрупкость; копия на кадр дешёвая).
fn to_sdl_points(pts []Vec2) []C.SDL_FPoint {
	mut out := []C.SDL_FPoint{len: pts.len}
	for i, pt in pts {
		out[i] = C.SDL_FPoint{pt.x, pt.y}
	}
	return out
}

// draw_polyline рисует ломаную через точки pts цветом c. thickness округляется
// до целого числа проходов: толщина 1 - одна ломаная SDL_RenderLines, толщина
// n - n копий, сдвинутых по вертикали, и n - по горизонтали, с шагом 1
// логический пиксель вокруг исходной линии (одним вызовом SDL на проход, а не
// на отрезок - графику на тысячи точек это важно). Толстые линии (> 4) лучше
// рисовать отрезками draw_line_thick: проходы дают «лесенку» на наклонах.
// Меньше двух точек - ничего не рисуется.
pub fn (mut ctx RenderContext) draw_polyline(pts []Vec2, c Color, thickness f32) {
	if pts.len < 2 {
		return
	}
	C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)
	C.SDL_SetRenderDrawColor(ctx.renderer, c.r, c.g, c.b, c.a)
	sdl_pts := to_sdl_points(pts)
	passes := int(thickness + 0.5)
	if passes <= 1 {
		C.SDL_RenderLines(ctx.renderer, sdl_pts.data, sdl_pts.len)
		return
	}
	// Проходы симметричны относительно исходной линии: смещения от -half до +half.
	half := f32(passes - 1) * 0.5
	mut shifted := []C.SDL_FPoint{len: sdl_pts.len}
	for dy in 0 .. passes {
		offset := f32(dy) - half
		for i, pt in sdl_pts {
			shifted[i] = C.SDL_FPoint{pt.x, pt.y + offset}
		}
		C.SDL_RenderLines(ctx.renderer, shifted.data, shifted.len)
	}
	for dx in 0 .. passes {
		offset := f32(dx) - half
		for i, pt in sdl_pts {
			shifted[i] = C.SDL_FPoint{pt.x + offset, pt.y}
		}
		C.SDL_RenderLines(ctx.renderer, shifted.data, shifted.len)
	}
}

// fill_triangles заливает набор треугольников одним цветом c: каждые три точки
// pts - один треугольник (лишние 1-2 точки в конце отбрасываются). Один вызов
// SDL_RenderGeometry на весь набор - так рисуются дуги спиннера из сотен
// трапеций. Blend mode выставляется здесь (полупрозрачное кольцо-фон иначе
// записалось бы как есть, если рендерер остался в режиме «none»).
pub fn (mut ctx RenderContext) fill_triangles(pts []Vec2, c Color) {
	n := pts.len - pts.len % 3
	if n == 0 {
		return
	}
	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}
	z := C.SDL_FPoint{0, 0}
	mut verts := []C.SDL_Vertex{len: n}
	for i in 0 .. n {
		verts[i] = C.SDL_Vertex{
			position:  C.SDL_FPoint{pts[i].x, pts[i].y}
			color:     fc
			tex_coord: z
		}
	}
	C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)
	C.SDL_RenderGeometry(ctx.renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}
