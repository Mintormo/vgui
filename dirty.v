module vgui

// ═══════════════════════════════════════════════════════
// DirtyRegion — pure accumulation of "changed" rectangles.
// No SDL here: Window.render() decides what to do with it.
// ═══════════════════════════════════════════════════════
//
// Связь с остальной библиотекой (PROJECT.md, «Инвалидация и dirty regions»):
// экземпляр живёт в RenderContext.dirty (render_context.v). Его наполняют
// mark_anim_rect (точечная перерисовка области виджета), mark_anim /
// invalidate_all (mark_full - полный кадр) и Window.invalidate_hover_change.
// Window.render() (sdl3_window.v) в начале кадра решает: полный кадр
// (full), частичный (клип по union_rect() поверх persistent render target)
// или пропуск рисования (is_empty()), а после кадра вызывает clear().

// dirty_max_rects caps how many separate rectangles DirtyRegion tracks
// before collapsing them into a single bounding box. Keeps the list from
// growing unboundedly when many small areas change in one frame; the cost
// of collapsing early is a slightly larger repaint, never incorrectness.
pub const dirty_max_rects = 8

// Отдельные прямоугольники нужны Window.render(): частичный кадр рисует их
// по отдельности (passes), когда они далеко друг от друга, - мигающий курсор
// в одном углу и крутящийся спиннер в другом не перерисовывают всё между
// ними. До 27.10.2026 render() брал только охватывающий прямоугольник
// (union_rect), и список был заделом на эту перерисовку.
pub struct DirtyRegion {
pub mut:
	rects []Rect // накопленные изменённые прямоугольники (уже расширенные и обрезанные по окну)
	full  bool   // true - перерисовать весь кадр; rects при этом не важны
}

// add registers r as changed, clamped to bounds (normally the window's
// screen rect). Every incoming rectangle is inflated by 1 logical pixel in
// each direction first, to cover sub-pixel edges and anti-aliased rounded
// corners that sit just outside the widget's own bounds. Empty/degenerate
// rects (including ones that clamp away to nothing) are ignored. Once the
// region is already full, further adds are no-ops — there is nothing more
// to accumulate.
//
// Returns true if r was actually accepted into the region (or the region
// was already full, in which case it's covered regardless) — false if it
// was degenerate or clamped away to nothing outside bounds. Callers that
// derive other state from "did this add do anything" (e.g. mark_anim_rect
// deciding whether to keep the animation flag alive — see PROJECT.md,
// "needs_animation залипает навсегда") must check this return value instead
// of assuming every add() succeeds.
pub fn (mut d DirtyRegion) add(r Rect, bounds Rect) bool {
	if d.full {
		return true
	}
	if r.w <= 0 || r.h <= 0 {
		return false
	}
	inflated := r.expanded(1.0)
	clamped := inflated.intersection(bounds)
	if clamped.w <= 0 || clamped.h <= 0 {
		return false
	}
	d.rects << clamped
	// Достигли лимита - схлопываем список в один охватывающий прямоугольник.
	// После этого в списке снова один элемент, и накопление продолжается.
	if d.rects.len >= dirty_max_rects {
		bbox := d.union_rect()
		d.rects = [bbox]
	}
	return true
}

// mark_full flags the whole frame as dirty. Idempotent: calling it again,
// or calling add() afterwards, changes nothing further.
pub fn (mut d DirtyRegion) mark_full() {
	d.full = true
}

// clear resets the region to empty — called once per frame after the
// window has consumed it.
pub fn (mut d DirtyRegion) clear() {
	d.rects.clear()
	d.full = false
}

// is_empty - true, если за кадр ничего не изменилось: ни полного кадра, ни
// прямоугольников. Window.render() по этому признаку пропускает рисование.
pub fn (d &DirtyRegion) is_empty() bool {
	return !d.full && d.rects.len == 0
}

// dirty_merge_gap — прямоугольники ближе этого (логические пиксели) сливаются в
// один: отдельный проход ради узкой щели между ними дороже, чем её перерисовка.
const dirty_merge_gap = f32(24)

// dirty_split_ratio — рисовать области по отдельности, только если вместе они
// меньше этой доли охватывающего прямоугольника; иначе выгоднее один проход.
const dirty_split_ratio = f32(0.5)

// passes — прямоугольники частичного кадра, каждый рисуется своим проходом
// (Window.render: очистка фона и обход дерева в клипе этого прямоугольника).
// Шаги: (1) пересекающиеся и близкие (dirty_merge_gap) сливаются в их
// охватывающий, пока есть что сливать; (2) если остался один или они вместе
// занимают больше dirty_split_ratio охватывающего прямоугольника, - один проход
// по нему (дерево обходится один раз). Каждый проход обходит всё дерево, но
// виджеты вне клипа отсекаются сразу (is_in_clip), поэтому несколько маленьких
// проходов дешевле одного большого, когда области далеко друг от друга.
pub fn (d &DirtyRegion) passes() []Rect {
	if d.rects.len <= 1 {
		return d.rects.clone()
	}
	mut rs := d.rects.clone()
	mut merged := true
	for merged {
		merged = false
		outer: for i in 0 .. rs.len {
			for j in i + 1 .. rs.len {
				if rs[i].expanded(dirty_merge_gap).intersects(rs[j]) {
					rs[i] = rect_union(rs[i], rs[j])
					rs.delete(j)
					merged = true
					break outer
				}
			}
		}
	}
	bbox := d.union_rect()
	mut area := f32(0)
	for r in rs {
		area += r.w * r.h
	}
	if rs.len == 1 || area > bbox.w * bbox.h * dirty_split_ratio {
		return [bbox]
	}
	return rs
}

// rect_union — охватывающий прямоугольник двух.
fn rect_union(a Rect, b Rect) Rect {
	x1 := min_f32(a.x, b.x)
	y1 := min_f32(a.y, b.y)
	x2 := max_f32(a.x + a.w, b.x + b.w)
	y2 := max_f32(a.y + a.h, b.y + b.h)
	return Rect{x1, y1, x2 - x1, y2 - y1}
}

// union_rect returns the bounding box of every accumulated rectangle, or a
// zero Rect if nothing was ever added (full is a separate concern — callers
// check that themselves; union_rect only makes sense for the partial case).
pub fn (d &DirtyRegion) union_rect() Rect {
	if d.rects.len == 0 {
		return Rect{}
	}
	// Обычный поиск охватывающего прямоугольника: минимумы левых/верхних
	// краёв и максимумы правых/нижних по всем элементам.
	mut x1 := d.rects[0].x
	mut y1 := d.rects[0].y
	mut x2 := d.rects[0].x + d.rects[0].w
	mut y2 := d.rects[0].y + d.rects[0].h
	for i in 1 .. d.rects.len {
		r := d.rects[i]
		x1 = min_f32(x1, r.x)
		y1 = min_f32(y1, r.y)
		x2 = max_f32(x2, r.x + r.w)
		y2 = max_f32(y2, r.y + r.h)
	}
	return Rect{x1, y1, x2 - x1, y2 - y1}
}
