module vgui

import os

// ═══════════════════════════════════════════════════════
// Tests for the Window.render() dirty-region seam itself — as opposed to
// dirty_test.v, which only exercises DirtyRegion's own bookkeeping in
// isolation and therefore did not catch any of the render()-level defects
// found in review (see PROJECT.md / branch history): the render scale not
// being re-applied to the persistent render target, dirty.clear() wiping
// animation requests made from inside draw() before the NEXT frame could
// see them, dispatch_event_with_app skipping invalidation on early returns,
// and a partial dirty rect not covering a widget's shadow.
//
// Runs under SDL_VIDEODRIVER=dummy (no display needed), same as
// text_font_cache_test.v. It also doubles as the pixel-diff instrument asked
// for in review: capture_rgba()/get_px() read real rendered pixels back via
// SDL_RenderReadPixels, so any future "does a partial frame match a full one"
// question can be answered the same way instead of by eyeballing screenshots.
//
// Запуск: v test vgui/render_dirty_test.v

fn make_render_test_window(w int, h int) !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'render test', width: w, height: h, theme: light_theme())!
	// Кадры в тесте идут подряд за доли мс — анимациям нужен шаг кадра, а не часы.
	win.ctx.anim_fixed_dt = anim_nominal_dt
	app.add_window(win)
	return app, win
}

// ─── A minimal Widget for driving render() from a test ───

struct MockWidget {
pub mut:
	bounds         Rect
	fill_color     Color
	draw_count     int
	mark_each_draw bool
	mark_rect      Rect
}

fn (mut m MockWidget) draw(mut ctx RenderContext) {
	m.draw_count++
	if m.fill_color.a > 0 {
		ctx.fill_rect(m.bounds, m.fill_color)
	}
	if m.mark_each_draw {
		ctx.mark_anim_rect('mock', m.mark_rect)
	}
}

fn (mut m MockWidget) handle_event(_ &GuiEvent, _ &App) bool {
	return false
}

// TooltipMockWidget enqueues a Tooltip into ctx.pending_tooltips from INSIDE
// its own draw() on every call — exactly like the real Tooltip.draw() does
// (tooltip.v:219) — without depending on Tooltip's own hover-timing/target
// logic, so the render()-level seam (does a tooltip queued mid-loop actually
// get drawn THIS frame) can be tested in isolation.
struct TooltipMockWidget {
pub mut:
	bounds Rect
	tip    &Tooltip = unsafe { nil }
}

fn (mut m TooltipMockWidget) draw(mut ctx RenderContext) {
	ctx.fill_rect(m.bounds, Color{40, 40, 40, 255})
	ctx.pending_tooltips << m.tip
}

fn (mut m TooltipMockWidget) handle_event(_ &GuiEvent, _ &App) bool {
	return false
}

// ─── Pixel readback helpers (frame-diff instrument) ───

// capture_rgba / get_px / diff_count - тонкие обёртки над testkit.v
// (capture_frame, Frame.diff), оставленные ради множества вызовов ниже:
// пиксели R,G,B,A построчно, плюс ширина/высота/pitch. Кадр читается из
// w.rt - persistent render target - а не из backbuffer после present (его
// содержимое SDL не гарантирует), см. capture_frame.
fn capture_rgba(mut w Window) ([]u8, int, int, int) {
	f := capture_frame(mut w)
	return f.pixels, f.w, f.h, f.pitch
}

fn get_px(buf []u8, pitch int, x int, y int) (u8, u8, u8, u8) {
	off := y * pitch + x * 4
	return buf[off], buf[off + 1], buf[off + 2], buf[off + 3]
}

// diff_count - сколько пикселей двух одинаковых по размеру снимков различаются
// хоть на единицу, и наибольшая разница канала - те же два числа, что
// приводило ревью («14 040 pixels, max diff 75/255»).
fn diff_count(a []u8, b []u8, pitch int, w int, h int) (int, int) {
	fa := Frame{
		w:      w
		h:      h
		pitch:  pitch
		pixels: a
	}
	fb := Frame{
		w:      w
		h:      h
		pitch:  pitch
		pixels: b
	}
	d := fa.diff(&fb, 0)
	return d.count, d.max_delta
}

// ═══════════════════════════════════════════════════════
// BLOCKER 2 — mark_anim_rect()/invalidate() called from inside a widget's
// OWN draw() must survive the frame that made the request: it describes
// what's needed on the NEXT frame, not this one. dirty.clear() must run
// BEFORE the widget draw loop, not after it.
// ═══════════════════════════════════════════════════════

fn test_mark_anim_rect_from_draw_survives_to_next_frame() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut mock := &MockWidget{
		bounds:         Rect{10, 10, 40, 20}
		mark_each_draw: true
		mark_rect:      Rect{10, 10, 40, 20}
	}
	win.add_widget(mock)

	win.render()
	// The widget's draw() just requested its own rect for the NEXT frame —
	// if clear() ran after the draw loop (the bug), this would be empty.
	assert !win.ctx.dirty.is_empty()
	assert win.ctx.needs_animation

	// A second frame must still see the request (self-perpetuating, exactly
	// what an every-frame animation like a cursor blink or a spinner needs):
	win.render()
	assert !win.ctx.dirty.is_empty()
	assert win.ctx.needs_animation

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// IMPORTANT 5 — an empty dirty region (nothing forces a full frame, nothing
// was invalidated) must be treated as "nothing to redraw": the widget tree
// must not be walked at all.
// ═══════════════════════════════════════════════════════

fn test_empty_dirty_skips_widget_draw() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut mock := &MockWidget{
		bounds: Rect{10, 10, 40, 20}
	}
	win.add_widget(mock)

	win.render() // frame 1: rt just created -> full, draws once
	assert mock.draw_count == 1
	assert win.ctx.dirty.is_empty()

	win.render() // frame 2: nothing changed -> skip_draw, must NOT redraw
	assert mock.draw_count == 1

	win.ctx.invalidate(Rect{10, 10, 40, 20}) // simulate an external change
	win.render() // frame 3: dirty non-empty again -> must redraw
	assert mock.draw_count == 2

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// IMPORTANT 3 — dispatch_event_with_app must invalidate on EVERY exit path,
// not just the final fallthrough (a hotkey match returns early).
// ═══════════════════════════════════════════════════════

fn test_dispatch_invalidates_on_hotkey_early_return() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.render() // settle into a clean, non-dirty state
	assert win.ctx.dirty.is_empty()

	win.bind_hotkey('F5', fn () {})
	ev := GuiEvent{
		typ:     .key_down
		keycode: sdl_k_f5
	}
	win.dispatch_event_with_app(&ev, app)
	// The hotkey branch returns early inside dispatch_event_with_app — it
	// must still have invalidated before doing so.
	assert win.ctx.dirty.full

	win.cleanup()
	app.cleanup()
}

// invalidate_all_windows (used for app.post()/tray activity, neither of
// which produces a GuiEvent for dispatch_event_with_app to invalidate from)
// must mark every window dirty.
fn test_invalidate_all_windows_marks_every_window() {
	mut app, mut win := make_render_test_window(120, 90) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.render()
	assert win.ctx.dirty.is_empty()

	app.invalidate_all_windows()
	assert win.ctx.dirty.full

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// BLOCKER 1 — render scale must be re-applied to the persistent render
// target every time it becomes the active target; it is NOT inherited from
// the default backbuffer (SDL3 keeps scale/viewport/cliprect per target).
// ═══════════════════════════════════════════════════════

fn test_ui_scale_applied_to_render_target() {
	mut app, mut win := make_render_test_window(100, 100) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut mock := &MockWidget{
		bounds:     Rect{10, 10, 20, 20} // logical
		fill_color: Color{255, 0, 0, 255}
	}
	win.add_widget(mock)
	win.set_ui_scale(2.0)
	win.render()

	buf, _, _, pitch := capture_rgba(mut win)
	assert buf.len > 0

	// Logical bounds {10,10,20,20} at ui_scale 2.0 (dpi_scale 1.0 under the
	// dummy driver) must occupy PHYSICAL pixels 20..60. (50,50) is the
	// center of that scaled rect — filled only if the scale actually
	// reached the render target. Before the fix, drawing happened 1:1 into
	// the (still correctly physical-sized) target texture, so the widget
	// only ever painted physical pixels 10..30, leaving (50,50) as bg.
	r, g, b, _ := get_px(buf, pitch, 50, 50)
	assert r == 255 && g == 0 && b == 0

	// Sanity: well outside the scaled widget must remain background, not
	// also flooded red (guards against a "scale=huge, whole window red"
	// false pass).
	br, bgc, bb, _ := get_px(buf, pitch, 90, 90)
	assert !(br == 255 && bgc == 0 && bb == 0)

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// BLOCKER 4 — a dirty rect covering exactly a widget's `bounds` must still
// be widened enough to cover a shadow drawn outside those bounds, or ending
// a hover state leaves the old shadow behind as a ghost.
// ═══════════════════════════════════════════════════════

fn test_invalidate_widens_by_shadow_margin() {
	mut app, mut win := make_render_test_window(100, 100) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.ctx.theme.shadow_blur = 6.0
	win.ctx.theme.shadow_offset = 2.0
	win.render() // settle
	win.ctx.dirty.clear()

	r := Rect{20, 20, 10, 10}
	win.ctx.invalidate(r)
	got := win.ctx.dirty.union_rect()
	// Must be strictly larger than the raw rect (plus DirtyRegion's own 1px
	// AA inflation) by roughly shadow_blur+shadow_offset on each side.
	margin := win.ctx.visual_margin()
	assert margin == f32(8.0)
	assert got.x <= r.x - margin
	assert got.y <= r.y - margin
	assert got.x + got.w >= r.x + r.w + margin
	assert got.y + got.h >= r.y + r.h + margin

	win.cleanup()
	app.cleanup()
}

// End-to-end: a real Button with a shadow, hovered then un-hovered, where
// only the button's bounds is invalidated (as a widget using precise
// mark_anim_rect/invalidate — rather than the blanket mark_anim() Button
// itself currently uses — would). The resulting partial frame must be
// pixel-identical to a full frame of the same final (un-hovered) state: no
// leftover shadow ghost outside bounds.
fn test_partial_frame_with_shadow_matches_full_frame() {
	mut app, mut win := make_render_test_window(160, 120) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.set_theme(dark_theme()) // dark_theme has a visible shadow_blur/offset

	mut btn := button('Hover me')
	btn.bounds = Rect{40, 40, 80, 30}
	btn.no_focus = true
	btn.hovered = true
	btn.hover_anim.snap(1.0) // settled, no further mark_anim() from Button itself
	win.add_widget(btn)

	win.render() // full: hovered, shadow visible
	assert !win.ctx.dirty.full

	// Un-hover and invalidate exactly the button's bounds (simulating a
	// widget that migrated to precise invalidation) — NOT the whole window.
	btn.hovered = false
	btn.hover_anim.snap(0.0)
	win.ctx.invalidate(btn.bounds)
	assert !win.ctx.dirty.full // still a partial frame, not full
	win.render()
	partial_buf, pw, ph, p_pitch := capture_rgba(mut win)

	// Reference: the SAME final state, but rendered fully.
	win.ctx.invalidate_all()
	win.render()
	full_buf, _, _, f_pitch := capture_rgba(mut win)

	assert p_pitch == f_pitch
	n, max_d := diff_count(partial_buf, full_buf, p_pitch, pw, ph)
	assert n == 0, 'partial vs full frame differ in ${n} pixels (max ${max_d}/255) — shadow ghost outside dirty rect'

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// prev_overlayish — re-checked live now that partial frames are actually
// reachable (they used to always degrade to full before Blocker 2 was
// fixed). An overlay (ComboBox dropdown, context menu, tooltip) paints
// OUTSIDE any widget's clip rect; closing it must force a full frame so its
// pixels get erased, or it ghosts on the persistent render target forever
// (every later "nothing changed" frame would just re-blit the stale content
// — this is exactly what skip_draw would do if prev_overlayish were wrong).
// ═══════════════════════════════════════════════════════

fn test_closing_overlay_erases_ghost_without_freezing_skip_draw() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	overlay_rect := Rect{120, 10, 60, 40} // deliberately outside any widget's bounds
	win.ctx.overlay_cb = fn (mut ctx RenderContext) {
		ctx.fill_rect(Rect{120, 10, 60, 40}, Color{0, 200, 0, 255})
	}
	win.render() // frame 1: overlay active -> full, paints the green rect
	assert win.prev_overlayish

	buf1, _, _, pitch1 := capture_rgba(mut win)
	r1, g1, b1, _ := get_px(buf1, pitch1, 150, 30)
	assert r1 == 0 && g1 == 200 && b1 == 0

	// Close the overlay (as ComboBox/menu/tooltip do) and render again.
	win.ctx.overlay_cb = unsafe { nil }
	win.render() // frame 2: prev_overlayish forces full -> erases the ghost
	assert !win.prev_overlayish

	buf2, _, _, pitch2 := capture_rgba(mut win)
	r2, g2, b2, _ := get_px(buf2, pitch2, 150, 30)
	assert !(r2 == 0 && g2 == 200 && b2 == 0), 'overlay ghost still visible after closing it'

	// One more frame: nothing changed since frame 2, so this MUST be the
	// empty-dirty skip_draw fast path — and it must NOT resurrect the ghost.
	win.render()
	buf3, _, _, pitch3 := capture_rgba(mut win)
	n, _ := diff_count(buf2, buf3, pitch2, win.rt_w, win.rt_h)
	assert n == 0, 'skip_draw frame changed pixels vs. the previous settled frame'

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// CRITICAL 1/2 regression — a partial-frame repaint used to leave the
// renderer's blend mode at `none` (set for the dirty-rect clear, never
// restored). Spinner's background ring is drawn by spinner_draw_circle_arc
// via a raw SDL_RenderGeometry call that (before the fix) never set its own
// blend mode, so it inherited "none": a semi-transparent fill (alpha 60) got
// written verbatim instead of composited, producing a visibly different —
// and, combined with CRITICAL 2's blend-mode texture blit, progressively
// darkening/smeared — ring. Uses spinning=false (draw_static) so the ring is
// the ONLY thing drawn and is time-independent (no moving foreground arc to
// make the sampled pixel's color depend on real wall-clock ticks).
// ═══════════════════════════════════════════════════════

fn test_spinner_background_ring_stable_across_partial_frames() {
	mut app, mut win := make_render_test_window(120, 120) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.set_theme(dark_theme())
	mut sp := spinner()
	sp.thickness = 6
	sp.spinning = false
	win.add_widget(sp)

	win.render() // frame 1: rt just created -> full; also lays sp.bounds out to
	// fill the whole window (a top-level widget added directly to a Window
	// gets set_widget_bounds(screen_rect) on the first frame's size_changed
	// pass — see render()'s `if size_changed` block), so sp.bounds is now
	// exactly Rect{0,0,120,120}, not whatever it was constructed with.
	buf1, _, _, pitch1 := capture_rgba(mut win)

	// Geometry mirrors spinner_geometry(): size==0 and bounds is now the full
	// 120x120 window, so diameter = min(120,120) = 120, radius =
	// (120 - thickness*2)*0.5 = 54, center = (60, 60). Sample the ring at
	// angle 0 (east): x = cx + radius, y = cy — inside the
	// [radius - thickness/2, radius + thickness/2] band the arc fan actually
	// paints (verified against a raw pixel dump — the naive "sample near the
	// original small bounds" version of this test missed the ring entirely
	// because of the resize-to-fill-window step above).
	sample_x := 114
	sample_y := 60
	r1, g1, b1, a1 := get_px(buf1, pitch1, sample_x, sample_y)

	// 29 more partial frames (rt already exists, nothing else forces `full`;
	// invalidate() is the same "some rect changed" path a real spinning
	// spinner drives via mark_anim_rect every frame).
	for _ in 0 .. 29 {
		win.ctx.invalidate(sp.bounds)
		win.render()
	}
	buf2, _, _, pitch2 := capture_rgba(mut win)
	r2, g2, b2, a2 := get_px(buf2, pitch2, sample_x, sample_y)

	assert r1 == r2 && g1 == g2 && b1 == b2 && a1 == a2, 'spinner background ring color drifted over 29 partial frames: (${r1},${g1},${b1},${a1}) at frame 1 vs (${r2},${g2},${b2},${a2}) at frame 30 — blend mode leak'

	win.cleanup()
	app.cleanup()
}

// NOTE: an earlier version of this file also had a test that queried
// SDL_GetRenderDrawBlendMode() directly after render() (re-binding w.rt as
// the target first). It was dropped: probing showed that by the time
// render() returns, something between the dirty-rect fill and the final
// SDL_SetRenderTarget(nil)/RenderTexture blit already reports blend mode
// back as `blend` on this SDL backend EVEN WITH THE RESTORE FIX REMOVED —
// i.e. the API-level read doesn't reliably reflect the state a mid-loop
// render_* call actually saw, so a test built on it would pass regardless of
// whether the bug is present (verified experimentally by disabling the fix
// and re-running it). test_spinner_background_ring_stable_across_partial_frames
// above is the reliable regression check for CRITICAL 1: it reads back
// actual composited pixels, which the leaked blend mode visibly corrupts,
// and was verified to fail without the fix and pass with it.

// ═══════════════════════════════════════════════════════
// CRITICAL 3 regression — a Tooltip enqueued into ctx.pending_tooltips from
// INSIDE a widget's own draw() (exactly how the real Tooltip.draw() works,
// see tooltip.v:219) must be painted in THAT SAME frame, not the next one.
// The bug: the drawing decision after the widget loop used a boolean
// snapshot taken BEFORE the loop, which is always stale/empty on the very
// frame a tooltip first gets queued — delaying it by a frame and, with any
// concurrent per-frame invalidation, making it flicker on/off every other
// frame.
// ═══════════════════════════════════════════════════════

fn test_tooltip_queued_inside_draw_paints_same_frame_no_flicker() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.ctx.mouse_x = 50
	win.ctx.mouse_y = 50

	mut tip := tooltip('hi')
	tip.showing = true
	tip.bg = Color{255, 0, 255, 255} // opaque, distinctive — easy exact match
	tip.border = Color{255, 0, 255, 255}
	mut mock := &TooltipMockWidget{
		bounds: Rect{10, 10, 20, 20}
		tip:    tip
	}
	win.add_widget(mock)

	// Sample well inside the popup's fill area (offset in from the top-left
	// past the rounded-corner radius) — see tooltip_draw()'s positioning math
	// (popup starts at roughly mouse + (tt_offset_x, tt_offset_y)).
	sample_x := 60
	sample_y := 72

	win.render() // frame 1: mock's draw() queues the tooltip for the FIRST time
	buf1, _, _, pitch1 := capture_rgba(mut win)
	r1, g1, b1, _ := get_px(buf1, pitch1, sample_x, sample_y)
	assert r1 == 255 && g1 == 0 && b1 == 255, 'tooltip queued inside draw() did not paint in the same frame (got ${r1},${g1},${b1})'

	// Frame 2: the widget re-queues it again every draw — must paint again,
	// not skip (which is what the flicker looked like).
	win.render()
	buf2, _, _, pitch2 := capture_rgba(mut win)
	r2, g2, b2, _ := get_px(buf2, pitch2, sample_x, sample_y)
	assert r2 == 255 && g2 == 0 && b2 == 255, 'tooltip flickered: missing on the very next frame (got ${r2},${g2},${b2})'

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// Third-review regression 1 — needs_animation must never stay stuck true
// forever. Two independent failure modes, each with its own test:
//
//  (a) mark_anim_rect's rect clamps away to nothing (widget bounds fully
//      outside the window) — DirtyRegion.add rejects it, so needs_animation
//      must NOT be set in the first place (mark_anim_rect must check
//      invalidate()'s return value).
//  (b) even if needs_animation somehow ends up true with an empty dirty
//      region (belt-and-braces — should not happen given (a), but is the
//      documented safety net), render()'s skip_draw branch must still clear
//      it, or the app spins at 60fps forever redrawing nothing.
// ═══════════════════════════════════════════════════════

// MarkOnlyWidget calls mark_anim_rect with an externally-controlled rect on
// every draw(), without actually painting anything — lets a test drive
// mark_anim_rect with an out-of-window rect directly.
struct MarkOnlyWidget {
pub mut:
	bounds     Rect
	mark_rect  Rect
	draw_count int
}

fn (mut m MarkOnlyWidget) draw(mut ctx RenderContext) {
	m.draw_count++
	ctx.mark_anim_rect('mark_only', m.mark_rect)
}

fn (mut m MarkOnlyWidget) handle_event(_ &GuiEvent, _ &App) bool {
	return false
}

fn test_mark_anim_rect_outside_window_does_not_stick_needs_animation() {
	mut app, mut win := make_render_test_window(100, 100) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	// Rect entirely outside the 100x100 window — invalidate() must clamp
	// this away to nothing (DirtyRegion.add returns false), so
	// mark_anim_rect must NOT set needs_animation off the back of it.
	mut mock := &MarkOnlyWidget{
		bounds:    Rect{500, 500, 20, 20}
		mark_rect: Rect{500, 500, 20, 20}
	}
	win.add_widget(mock)

	win.render() // frame 1: rt just created -> full, draws once, marks (rejected)
	assert !win.ctx.needs_animation, 'needs_animation stuck true from an out-of-window mark_anim_rect'
	assert win.ctx.dirty.is_empty()

	// A second frame must be the skip_draw fast path (nothing dirty, nothing
	// forcing full) — proving the app would actually go back to sleep
	// instead of spinning at 60fps.
	win.render()
	assert mock.draw_count == 1, 'skip_draw did not skip: widget drew on frame 2 despite an empty dirty region'
	assert !win.ctx.needs_animation

	win.cleanup()
	app.cleanup()
}

fn test_needs_animation_cleared_even_on_skip_draw_frame() {
	mut app, mut win := make_render_test_window(100, 100) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.render() // settle: rt created, dirty now empty
	assert win.ctx.dirty.is_empty()

	// Simulate the belt-and-braces scenario directly: needs_animation set
	// true with nothing in the dirty region (as if some future call site set
	// it without going through mark_anim_rect's guards). skip_draw must fire
	// (full stays false, dirty stays empty) AND the reset must still happen,
	// since it now lives outside the `!skip_draw` branch.
	win.ctx.needs_animation = true
	win.ctx.anim_reason = 'synthetic'
	assert !win.ctx.dirty.full

	win.render()
	assert !win.ctx.needs_animation, 'needs_animation survived a skip_draw frame — would spin the event loop at 60fps forever'
	assert win.ctx.anim_reason == ''

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// Third-review regression 2 — mark_anim_rect must not force 60fps for a
// widget that's currently outside the repaint area, but must still keep
// animating one that IS inside it. Both ends of the same behavior change,
// tested together so a fix for one end can't accidentally regress the
// other.
// ═══════════════════════════════════════════════════════

fn test_mark_anim_rect_outside_partial_clip_does_not_mark() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.render() // settle
	assert win.ctx.dirty.is_empty()

	// Force a partial frame whose dirty rect covers only the left third of
	// the window — a widget entirely in the right two-thirds is out of this
	// frame's actual repaint area.
	win.ctx.invalidate(Rect{0, 0, 20, 20})
	assert !win.ctx.dirty.full

	mut outside := &MarkOnlyWidget{
		bounds:    Rect{150, 100, 20, 20}
		mark_rect: Rect{150, 100, 20, 20}
	}
	win.add_widget(outside)

	win.render() // partial frame; outside's mark_rect doesn't intersect the clip
	assert !win.ctx.needs_animation, 'mark_anim_rect marked animation for a widget outside the current partial-frame clip'

	win.cleanup()
	app.cleanup()
}

fn test_mark_anim_rect_inside_partial_clip_keeps_animating() {
	mut app, mut win := make_render_test_window(200, 150) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	win.render() // settle
	assert win.ctx.dirty.is_empty()

	mut inside := &MarkOnlyWidget{
		bounds:    Rect{10, 10, 20, 20}
		mark_rect: Rect{10, 10, 20, 20}
	}
	win.add_widget(inside)

	// Kick off a partial frame covering exactly the widget's own rect (as a
	// real self-perpetuating animation like a cursor blink does every frame).
	win.ctx.invalidate(Rect{10, 10, 20, 20})
	assert !win.ctx.dirty.full

	win.render()
	assert win.ctx.needs_animation, 'mark_anim_rect failed to keep animating a widget inside the current partial-frame clip'
	assert !win.ctx.dirty.is_empty()

	// And it must keep going for another frame — this is the "self
	// perpetuating" property an every-frame animation needs.
	win.render()
	assert win.ctx.needs_animation
	assert !win.ctx.dirty.is_empty()

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// MenuButton в фокусе реально рисует focus-ring (аудит, пункт 2.2).
//
// Тест живёт здесь, а не в focus_test.v, ради пиксельной оснастки выше
// (make_render_test_window/capture_rgba/diff_count): focus_test.v намеренно
// обходится без SDL, а вопрос «кольцо действительно попадает в кадр» иначе
// проверяется только глазами. До правки MenuButton регистрировался чужим
// kind, is_entry_available всегда возвращал false, и фокус на него не вставал
// вообще — значит и кольца не было.
// ═══════════════════════════════════════════════════════

fn test_menu_button_focus_ring_is_rendered() {
	mut app, mut win := make_render_test_window(200, 80) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut mb := menu_button('Действие')
	mb.bounds = Rect{20, 20, 160, 32}
	win.add_widget(mb)

	// Кадр без фокуса — эталон.
	win.render()
	before, w, h, pitch := capture_rgba(mut win)
	assert before.len > 0

	// Регистрация идёт из draw() — она обязана лечь СВОИМ kind, иначе
	// is_entry_available читает чужие смещения (тот самый баг 2.2).
	assert win.ctx.focus.entries.len == 1
	assert win.ctx.focus.entries[0].kind == .menu_button

	// Фокус ставится не событием, поэтому кадр надо пометить вручную
	// (контракт инвалидации: сеттеры кадр не инвалидируют).
	win.ctx.focus.focus_menu_button(mb, 0)
	assert win.ctx.focus.is_focused(unsafe { voidptr(mb) })
	win.ctx.invalidate_all()

	// Кольцо появляется плавно (focus_anim), поэтому даём анимации сойтись.
	// Кадры идут только потому, что draw() сам метит себя через mark_anim —
	// если эту пометку убрать, анимация замрёт на первом кадре.
	for _ in 0 .. 40 {
		win.render()
	}
	after, _, _, _ := capture_rgba(mut win)
	assert after.len == before.len

	n, max_d := diff_count(before, after, pitch, w, h)
	assert n > 200, 'focus-ring изменил всего ${n} пикселей — кольцо не нарисовалось'
	// Порог отделяет доигравшую анимацию от замершей: с mark_anim замер даёт
	// max 142, без него (focus_anim застывает на первом шаге, 0.18) — 26.
	assert max_d > 60, 'кольцо слишком бледное (max ${max_d}) — анимация focus_anim замерла, проверьте mark_anim в MenuButton.draw'

	win.cleanup()
	app.cleanup()
}

// Клип контейнера не должен срезать тень ребёнка.
//
// BoxLayout/Panel клипают детей по своим bounds, а виджет рисует тень ЗА
// bounds (draw_shadow сдвигает её на shadow_offset и размывает на
// shadow_blur наружу). Бокс обычно обтягивает детей вплотную, поэтому клип
// строго по bounds срезал тень крайнего ребёнка — заметнее всего снизу,
// куда её и уводит offset: под кнопкой оставалась одна строка вместо
// восьмипиксельного градиента. Проверяем на кнопке, занимающей внутренний
// бокс целиком: под её нижней границей обязаны быть пиксели темнее фона.
fn test_container_clip_keeps_child_shadow() {
	mut app, mut win := make_render_test_window(200, 140) or {
		eprintln('skip: ${err}')
		return
	}
	// Тень рисуется только у наведённой кнопки (см. button.v).
	mut btn := button('Hover')
	btn.style = .accent
	btn.hovered = true
	btn.hover_anim.snap(1.0)

	// Внутренний бокс ровно по кнопке — именно его клип и срезал тень.
	mut inner := create_vbox_fill()
	inner.add(btn)

	mut root := create_vbox_fill()
	root.add(inner)
	root.add(create_spacer(), flex: 1)
	win.add_widget(root)

	win.render()
	buf, _, _, pitch := capture_rgba(mut win)
	assert buf.len > 0

	// Фон окна берём заведомо ниже тени (blur 6 + offset 2 = 8 px).
	bg_r, bg_g, bg_b, _ := get_px(buf, pitch, 100, 60)

	// Считаем строки под кнопкой (y = 32), где пиксель темнее фона.
	mut shadow_rows := 0
	for y in 33 .. 41 {
		r, g, b, _ := get_px(buf, pitch, 100, y)
		if int(r) + int(g) + int(b) < int(bg_r) + int(bg_g) + int(bg_b) - 6 {
			shadow_rows++
		}
	}
	// До правки клип оставлял максимум одну строку на самой границе.
	assert shadow_rows >= 5, 'под кнопкой всего ${shadow_rows} строк тени — клип контейнера снова режет её по bounds'

	win.cleanup()
	app.cleanup()
}

// ═══════════════════════════════════════════════════════
// Точечная инвалидация hover (аудит 3.C): mouse_move перерисовывает только
// виджет под курсором и тот, с которого курсор ушёл. Проверка того, что
// «точечно» не значит «неправильно»: серия частичных кадров после движений
// мыши обязана совпасть попиксельно с полным кадром той же сцены.
//
// Бухгалтерия самого dirty-региона (какие прямоугольники накопились, когда
// кадр остаётся полным) проверяется в hover_dirty_test.v — здесь только
// пиксели, ради инструмента capture_rgba/diff_count.
// ═══════════════════════════════════════════════════════

fn test_partial_hover_frames_match_full_frame_pixels() {
	mut app, mut win := make_render_test_window(200, 200) or {
		eprintln('skip: ${err}')
		return
	}
	mut top := button('top')
	mut bottom := button('bottom')
	mut col := create_vbox_fill()
	col.add(top, flex: 1)
	col.add(bottom, flex: 1)
	win.add_widget(col)
	win.render()

	// Наводимся на верхнюю кнопку, затем переводим курсор на нижнюю —
	// оба кадра частичные (hover-анимация кнопки тоже помечает только
	// свои bounds, см. button.v).
	first := GuiEvent{
		typ:     .mouse_move
		mouse_x: 100
		mouse_y: top.bounds.y + top.bounds.h * 0.5
	}
	win.dispatch_event_with_app(&first, app)
	assert !win.ctx.dirty.full, 'движение мыши не должно требовать полного кадра'
	win.render()

	second := GuiEvent{
		typ:     .mouse_move
		mouse_x: 100
		mouse_y: bottom.bounds.y + bottom.bounds.h * 0.5
	}
	win.dispatch_event_with_app(&second, app)
	win.render()
	// Анимация hover идёт несколько кадров — дорисовываем её до конца
	// частичными кадрами, чтобы сравнивать устоявшуюся картинку.
	for _ in 0 .. 40 {
		win.render()
	}
	partial, pw, ph, pitch := capture_rgba(mut win)
	assert pw > 0 && ph > 0, 'не удалось прочитать пиксели'

	// Та же сцена, нарисованная целиком.
	win.ctx.invalidate_all()
	win.render()
	full, fw, fh, fpitch := capture_rgba(mut win)
	assert fw == pw && fh == ph && fpitch == pitch

	n, max_d := diff_count(partial, full, pitch, pw, ph)
	assert n == 0, 'частичные кадры разошлись с полным: ${n} пикселей, макс. отличие ${max_d}'

	// Страховка от «зелёного из-за того, что сравнивать было нечего»: hover
	// обязан быть виден в пикселях, иначе совпадение кадров ничего не
	// доказывает. Наведена нижняя кнопка — её фон должен отличаться от фона
	// ненаведённой верхней.
	scale := int(win.ctx.dpi_scale * win.ctx.ui_scale)
	tr, tg, tb, _ := get_px(partial, pitch, 100 * scale, int(top.bounds.y +
		top.bounds.h * 0.5) * scale)
	br, bg_, bb, _ := get_px(partial, pitch, 100 * scale, int(bottom.bounds.y +
		bottom.bounds.h * 0.5) * scale)
	assert tr != br || tg != bg_ || tb != bb, 'подсветка hover не видна в пикселях — сравнивать было нечего'

	win.cleanup()
	app.cleanup()
}

// Частичный кадр рисует далёкие области отдельными проходами
// (DirtyRegion.passes): пиксели МЕЖДУ ними не перерисовываются. Средний
// виджет поменял цвет без инвалидации - на экране он остаётся старым, а
// крайние, инвалидированные, - новые.
fn test_partial_frame_paints_far_rects_separately() {
	mut app, mut win := make_render_test_window(400, 300) or {
		assert false, 'window creation failed: ${err}'
		return
	}
	red := Color{220, 0, 0, 255}
	green := Color{0, 200, 0, 255}
	blue := Color{0, 0, 220, 255}
	mut a := &MockWidget{
		bounds:     Rect{10, 10, 30, 30}
		fill_color: red
	}
	mut mid := &MockWidget{
		bounds:     Rect{180, 130, 40, 40}
		fill_color: red
	}
	mut b := &MockWidget{
		bounds:     Rect{350, 250, 30, 30}
		fill_color: red
	}
	win.add_widget(a)
	win.add_widget(mid)
	win.add_widget(b)
	win.ctx.invalidate_all()
	win.render()

	a.fill_color = green
	b.fill_color = green
	mid.fill_color = blue // без инвалидации: его область перерисовываться не должна
	win.ctx.invalidate(a.bounds)
	win.ctx.invalidate(b.bounds)
	assert win.ctx.dirty.passes().len == 2
	win.render()
	buf, _, _, pitch := capture_rgba(mut win)
	scale := win.ctx.dpi_scale * win.ctx.ui_scale
	px := fn [buf, pitch, scale] (x f32, y f32) (u8, u8, u8, u8) {
		return get_px(buf, pitch, int(x * scale), int(y * scale))
	}
	ar, ag, _, _ := px(25, 25)
	assert ag > 150 && ar < 60, 'левый верхний перерисован'
	br, bgc, _, _ := px(365, 265)
	assert bgc > 150 && br < 60, 'правый нижний перерисован'
	mr, _, mb, _ := px(200, 150)
	assert mr > 150 && mb < 60, 'середина между ними не перерисована (отдельные проходы)'

	win.cleanup()
	app.cleanup()
}
