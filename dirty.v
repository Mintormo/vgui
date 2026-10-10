module vgui

// ═══════════════════════════════════════════════════════
// DirtyRegion — pure accumulation of "changed" rectangles.
// No SDL here: Window.render() decides what to do with it.
// ═══════════════════════════════════════════════════════

// dirty_max_rects caps how many separate rectangles DirtyRegion tracks
// before collapsing them into a single bounding box. Keeps the list from
// growing unboundedly when many small areas change in one frame; the cost
// of collapsing early is a slightly larger repaint, never incorrectness.
pub const dirty_max_rects = 8

// Current state (as of the layout-system dirty-regions work): the single
// consumer of this struct is Window.render(), and it only ever reads
// union_rect() — the bounding box of everything in `rects`, never the
// individual rectangles. Since the union of a list of rects is identical to
// the union of its own bounding box, keeping up to `dirty_max_rects`
// separate entries buys nothing today; a single running bbox would behave
// identically for every caller that exists right now. Do NOT simplify this
// away — the list is deliberately kept as scaffolding for a future switch to
// per-rectangle clipping (each rect repainted individually instead of one
// bbox covering all of them, which over-repaints when the rects are far
// apart). That future consumer is what `rects` (plural) is for; there just
// isn't one yet.
pub struct DirtyRegion {
pub mut:
	rects []Rect
	full  bool
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

pub fn (d &DirtyRegion) is_empty() bool {
	return !d.full && d.rects.len == 0
}

// union_rect returns the bounding box of every accumulated rectangle, or a
// zero Rect if nothing was ever added (full is a separate concern — callers
// check that themselves; union_rect only makes sense for the partial case).
pub fn (d &DirtyRegion) union_rect() Rect {
	if d.rects.len == 0 {
		return Rect{}
	}
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
