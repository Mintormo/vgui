module vgui

// Тесты DirtyRegion (dirty.v) - накопителя «грязных» прямоугольников кадра
// (PROJECT.md, «Инвалидация и dirty regions»). Чистая логика без SDL и окон:
// - add() расширяет прямоугольник на пиксель с каждой стороны (запас на
//   сглаживание краёв), обрезает его по границам окна и отбрасывает пустые;
// - его bool-результат управляет needs_animation в mark_anim_rect;
// - при dirty_max_rects прямоугольниках всё схлопывается в общий bbox;
// - флаг full («перерисовать всё») поглощает любые add().

fn test_empty_region_is_empty() {
	d := DirtyRegion{}
	assert d.is_empty()
	assert d.union_rect() == Rect{0, 0, 0, 0}
}

fn test_add_inflates_by_one_pixel() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 1000, 1000}
	d.add(Rect{10, 10, 20, 20}, bounds)
	assert d.rects.len == 1
	r := d.rects[0]
	assert r.x == 9
	assert r.y == 9
	assert r.w == 22
	assert r.h == 22
}

fn test_add_clamps_to_bounds() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	d.add(Rect{95, 95, 20, 20}, bounds)
	assert d.rects.len == 1
	r := d.rects[0]
	assert r.x == 94
	assert r.y == 94
	assert r.x + r.w == 100
	assert r.y + r.h == 100
}

fn test_add_ignores_empty_rect() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	d.add(Rect{10, 10, 0, 0}, bounds)
	d.add(Rect{10, 10, -5, 20}, bounds)
	assert d.rects.len == 0
	assert d.is_empty()
}

fn test_add_ignores_rect_fully_outside_bounds() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	d.add(Rect{200, 200, 10, 10}, bounds)
	assert d.rects.len == 0
}

// ─── add()'s bool return ───
// It is not decoration: mark_anim_rect (render_context.v) gates
// needs_animation on it, so "add returned false" is what keeps the render
// loop from spinning at 60fps for a rect that contributes nothing.

fn test_add_returns_false_for_degenerate_rect() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	assert !d.add(Rect{10, 10, 0, 0}, bounds)
	assert !d.add(Rect{10, 10, -5, 20}, bounds)
	assert !d.add(Rect{10, 10, 20, -5}, bounds)
	assert d.rects.len == 0
}

fn test_add_returns_false_for_rect_outside_bounds() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	assert !d.add(Rect{200, 200, 10, 10}, bounds)
	assert !d.add(Rect{-50, 10, 10, 10}, bounds)
	assert d.rects.len == 0
}

fn test_add_returns_true_when_accepted() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	assert d.add(Rect{10, 10, 20, 20}, bounds)
	assert d.rects.len == 1
	// Partially outside still counts — it clamps to a non-empty rect.
	assert d.add(Rect{95, 95, 50, 50}, bounds)
	assert d.rects.len == 2
}

fn test_add_returns_true_when_already_full() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	d.mark_full()
	// Full means "everything is covered anyway", so even a rect that would
	// otherwise be rejected reports as covered — and nothing is accumulated.
	assert d.add(Rect{10, 10, 20, 20}, bounds)
	assert d.add(Rect{500, 500, 10, 10}, bounds)
	assert d.add(Rect{10, 10, 0, 0}, bounds)
	assert d.rects.len == 0
}

fn test_collapse_triggers_at_max_rects_not_after() {
	// Collapsing must fire once len reaches dirty_max_rects (i.e. on adding
	// the dirty_max_rects-th rect), not only once it exceeds it — see the
	// off-by-one note on the `>=` check in dirty.v's add(). With exactly
	// dirty_max_rects rects added, the dirty_max_rects-th add is the one
	// that collapses them all into a single bbox.
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 1000, 1000}
	for i in 0 .. dirty_max_rects {
		d.add(Rect{f32(i * 10), f32(i * 10), 5, 5}, bounds)
	}
	assert d.rects.len == 1
}

fn test_overflow_merges_into_bbox() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 1000, 1000}
	for i in 0 .. dirty_max_rects + 1 {
		d.add(Rect{f32(i * 10), f32(i * 10), 5, 5}, bounds)
	}
	// One collapse fires at the dirty_max_rects-th add (see the test above),
	// then one more rect is appended on top of that single bbox — so the
	// final count is 2, not 1. What matters is that the UNION of whatever
	// rects remain still covers every rect ever added; a caller only ever
	// consumes union_rect()/is_empty(), never rects.len directly.
	assert d.rects.len == 2
	// bbox must cover every rect added: first at (0,0)-ish, last at (i*10)-ish
	u := d.union_rect()
	assert u.x <= 0
	assert u.y <= 0
	last_i := dirty_max_rects
	assert u.x + u.w >= f32(last_i * 10 + 5)
	assert u.y + u.h >= f32(last_i * 10 + 5)
}

fn test_mark_full_is_idempotent() {
	mut d := DirtyRegion{}
	d.mark_full()
	assert d.full
	d.mark_full()
	assert d.full
	// add() after full is a no-op — full stays the authoritative signal
	bounds := Rect{0, 0, 100, 100}
	d.add(Rect{1, 1, 5, 5}, bounds)
	assert d.rects.len == 0
	assert d.full
}

fn test_clear_resets_everything() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 100, 100}
	d.add(Rect{1, 1, 5, 5}, bounds)
	d.mark_full()
	d.clear()
	assert d.is_empty()
	assert !d.full
	assert d.rects.len == 0
}

fn test_union_rect_of_single_rect() {
	mut d := DirtyRegion{}
	bounds := Rect{0, 0, 1000, 1000}
	d.add(Rect{10, 20, 30, 40}, bounds)
	u := d.union_rect()
	assert u.x == 9
	assert u.y == 19
	assert u.w == 32
	assert u.h == 42
}
