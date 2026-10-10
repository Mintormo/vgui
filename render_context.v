module vgui

// ═══════════════════════════════════════════════════════
// RenderContext — rendering abstraction (struct only)
// Method implementations are in backend-specific files
// (e.g. sdl2_render.v, sdl2_fonts.v)
// ═══════════════════════════════════════════════════════

struct FontHandleInfo {
	style_int int
	font_size int
}

pub struct FontSet {
pub mut:
	regular          voidptr
	bold             voidptr
	italic           voidptr
	bold_italic      voidptr
	mono             voidptr
	mono_bold        voidptr
	size             int = 14
	mono_size        int = 13
	regular_path     string
	bold_path        string
	italic_path      string
	bold_italic_path string
	mono_path        string
	mono_bold_path   string
	// Embedded font data (from $embed_file); takes priority over path when non-empty.
	font_data        []u8
	bold_data        []u8
	italic_data      []u8
	bold_italic_data []u8
	mono_data        []u8
	mono_bold_data   []u8
	size_cache       map[string]voidptr
	// Reverse map: font handle → (style_int, font_size) for O(1) cache key lookup.
	handle_map map[voidptr]FontHandleInfo
	// Shared-cache bookkeeping (font_cache.v): the g_font_cache key this set is
	// stored under and the number of windows holding it.
	cache_key string
	refs      int
}

pub struct RenderContext {
pub mut:
	renderer      voidptr
	theme         Theme
	fonts         &FontSet = unsafe { nil } // shared via g_font_cache; the owning Window releases it (release_fonts)
	screen_width  f32
	screen_height f32
	clip_stack    []Rect
	// HiDPI
	dpi_scale f32 = 1.0
	dpi_info  DpiInfo
	// Focus management
	focus FocusManager
	// Оверлей попапа (ComboBox, меню): один слот с владельцем. Писать только
	// через set_overlay/clear_overlay (overlay.v), не присваиванием.
	overlay_cb    fn (mut vgui.RenderContext)         = unsafe { nil }
	overlay_ev    fn (&vgui.GuiEvent, &vgui.App) bool = unsafe { nil }
	overlay_close fn (mut vgui.RenderContext)         = unsafe { nil }
	overlay_owner voidptr
	// Text cache: key is FNV-1a u64 hash of (text, font_size, style_int, color).
	// Using a hash key eliminates per-call string concatenation on the hot path.
	// Collisions are handled, not assumed away: each entry stores the exact
	// (text, font_size, style_int, color) it was rendered from, and a hash hit
	// with mismatching fields is treated as a miss (the colliding entry is
	// re-rendered and overwritten) — so a collision costs one re-render, never
	// a permanently wrong glyph texture.
	text_cache map[u64]TextCacheEntry
	cache_max  int = 1024
	// Icon cache: separate from text_cache to avoid LRU eviction. Key = file path.
	icon_cache map[string]voidptr
	// Monotonic tick incremented on every cache access; used as LRU stamp.
	cache_tick u64
	// Last known mouse position (for events that don't carry coords, e.g. wheel)
	mouse_x f32
	mouse_y f32
	// UI scale (user-configurable zoom, independent of HiDPI)
	ui_scale f32 = 1.0
	// Pending drag rects from WindowTitleDrag (logical coords, flushed each frame)
	pending_drag_rects []Rect
	// Full bounding box of each WindowTitleDrag widget (logical coords, for dbl-click detection)
	pending_titlebar_rects []Rect
	// Pending tooltips (multiple can register per frame)
	pending_tooltips []&Tooltip
	needs_animation  bool
	anim_reason      string // DEBUG
	// Accumulated changed-rectangles for this frame. Window.render() consumes
	// it to decide between a full repaint and a partial one; see dirty.v.
	dirty DirtyRegion
	// Фаза arrange (PROJECT.md, «Фаза arrange»). layout_dirty взводят
	// invalidate*/request_layout, снимает Window.arrange(); true по умолчанию —
	// первое событие до первого кадра тоже должно видеть раскладку.
	layout_dirty bool = true
	// Номер кадра, который реально рисуется (растёт в render() только вне
	// skip_draw). По нему анимации, шагающие в arrange(), делают ровно один
	// шаг за кадр, сколько бы раз arrange ни звали перед событиями.
	frame_no u64
	// Шаг анимаций текущего кадра в мс (Anim, anim.v) и время прошлого
	// кадра — выставляет Window.render(). Вне render (тесты, ручной
	// контекст) шаг номинальный.
	anim_dt      f32 = anim_nominal_dt
	anim_last_ms u64
	// > 0 — каждый кадр шагает ровно на столько мс, без часов: тесты, запись
	// видео по кадрам. 0 — по часам.
	anim_fixed_dt f32
	// Текущая глубина рекурсии arrange_widget (защита от циклов в дереве).
	arrange_depth int
}

struct TextCacheEntry {
mut:
	texture   voidptr
	w         int
	h         int
	last_used u64
	// Verification fields: the exact inputs this texture was rendered from.
	// Checked on every hash hit to detect FNV-1a collisions (see text_cache).
	text      string
	font_size int
	style_int int
	color     Color
}

// ─── Backend-agnostic convenience methods ───

pub fn (mut ctx RenderContext) draw_shadow(r Rect, radius f32) {
	sc := ctx.theme.shadow_color
	if sc.a == 0 {
		return
	}
	off := ctx.theme.shadow_offset
	layers := if ctx.theme.shadow_layers > 0 { ctx.theme.shadow_layers } else { 1 }
	blur := ctx.theme.shadow_blur
	base_a := f32(sc.a)
	for i := 0; i < layers; i++ {
		// i=0 — widest, most transparent outer layer; i=layers-1 — tightest, densest inner layer
		frac := f32(layers - i) / f32(layers) // 1.0 .. 1/layers
		expand := blur * frac
		layer_rect := Rect{
			x: r.x + off - expand
			y: r.y + off - expand
			w: r.w + expand * 2.0
			h: r.h + expand * 2.0
		}
		layer_radius := radius + expand
		alpha_frac := (1.0 - frac) * (1.0 - frac) // quadratic falloff: density grows toward the center
		a := u8(min_f32(255.0, base_a * (0.15 + 0.85 * alpha_frac) / f32(layers) * 1.6))
		ctx.fill_rounded_rect(layer_rect, Color{sc.r, sc.g, sc.b, a}, layer_radius)
	}
}

// draw_focus_ring draws a unified inset focus ring used by focusable widgets.
// strength (0..1) is the widget's focus animation amount.
pub fn (mut ctx RenderContext) draw_focus_ring(r Rect, radius f32, strength f32) {
	fc := ctx.theme.eff_focus_ring_color()
	ctx.focus_ring_impl(r, radius, strength, ctx.theme.focus_ring_inset, fc, ctx.theme.focus_ring_width)
}

// draw_focus_ring_edge draws the focus ring exactly on the widget's border
// (no inset): used by input fields, where an inset ring reads as a second,
// shifted frame inside the border. Still never goes outside r.
pub fn (mut ctx RenderContext) draw_focus_ring_edge(r Rect, radius f32, strength f32) {
	fc := ctx.theme.eff_focus_ring_color()
	ctx.focus_ring_impl(r, radius, strength, 0, fc, ctx.theme.focus_ring_width)
}

// draw_focus_ring_soft draws a subdued focus ring for buttons: a single
// half-transparent accent line, noticeable but not louder than the button.
pub fn (mut ctx RenderContext) draw_focus_ring_soft(r Rect, radius f32, strength f32) {
	fc := ctx.theme.accent.with_alpha(u8(f32(ctx.theme.accent.a) * 0.55))
	ctx.focus_ring_impl(r, radius, strength, ctx.theme.focus_ring_inset, fc, 1)
}

fn (mut ctx RenderContext) focus_ring_impl(r Rect, radius f32, strength f32, inset f32, base Color, width f32) {
	if strength <= 0.02 {
		return
	}
	fc := base.with_alpha(u8(f32(base.a) * strength))
	// Each extra line is shifted by exactly one PHYSICAL pixel from an already
	// snapped rect: a 1-logical-unit shrink at fractional scale snaps unevenly
	// and leaves a gap on some sides and an overlap on others.
	s := ctx.dpi_scale * ctx.ui_scale
	pw := if s > 0 { f32(1.0) / s } else { f32(1.0) }
	mut rr := ctx.snap_rect(r.shrunk(inset))
	mut rad := max_f32(0, radius - inset)
	for _ in 0 .. int(max_f32(1, width * s + 0.5)) {
		ctx.draw_rounded_rect(rr, fc, rad)
		rr = rr.shrunk(pw)
		rad = max_f32(0, rad - pw)
	}
}

pub fn (mut ctx RenderContext) draw_text(text string, x f32, y f32, c Color) {
	ctx.draw_text_with_font(text, x, y, c, ctx.fonts.regular)
}

pub fn (mut ctx RenderContext) draw_text_bold(text string, x f32, y f32, c Color) {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.bold != nil } {
		font = ctx.fonts.bold
	}
	ctx.draw_text_with_font(text, x, y, c, font)
}

pub fn (mut ctx RenderContext) draw_text_italic(text string, x f32, y f32, c Color) {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.italic != nil } {
		font = ctx.fonts.italic
	}
	ctx.draw_text_with_font(text, x, y, c, font)
}

pub fn (mut ctx RenderContext) draw_text_mono(text string, x f32, y f32, c Color) {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.mono != nil } {
		font = ctx.fonts.mono
	}
	ctx.draw_text_with_font(text, x, y, c, font)
}

pub fn (mut ctx RenderContext) draw_text_mono_bold(text string, x f32, y f32, c Color) {
	mut font := voidptr(ctx.fonts.mono)
	if unsafe { ctx.fonts.mono_bold != nil } {
		font = ctx.fonts.mono_bold
	}
	ctx.draw_text_with_font(text, x, y, c, font)
}

pub fn (mut ctx RenderContext) draw_text_mono_centered(text string, r Rect, c Color) {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.mono != nil } {
		font = ctx.fonts.mono
	}
	if text.len == 0 || unsafe { font == nil } {
		return
	}
	size := ctx.measure_text_with_font(text, font)
	x := r.x + (r.w - size.x) / 2.0
	y := r.y + (r.h - size.y) / 2.0
	ctx.draw_text_with_font(text, x, y, c, font)
}

pub fn (ctx &RenderContext) measure_text_mono(text string) Vec2 {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.mono != nil } {
		font = ctx.fonts.mono
	}
	return ctx.measure_text_with_font(text, font)
}

pub fn (ctx &RenderContext) mono_font_height() f32 {
	mut font := voidptr(ctx.fonts.regular)
	if unsafe { ctx.fonts.mono != nil } {
		font = ctx.fonts.mono
	}
	if unsafe { font == nil } {
		return 14.0
	}
	h := f32(C.TTF_GetFontHeight(font))
	if ctx.dpi_scale > 1.0 {
		return h / ctx.dpi_scale
	}
	return h
}

pub fn (ctx &RenderContext) mono_char_width() f32 {
	return ctx.measure_text_mono('M').x
}

// ─── Icon texture cache ───

pub fn (mut ctx RenderContext) load_icon_texture(path string) voidptr {
	if path.len == 0 {
		return unsafe { nil }
	}
	if path in ctx.icon_cache {
		t := ctx.icon_cache[path] or { unsafe { nil } }
		if unsafe { t != nil } {
			return t
		}
	}
	surface := C.IMG_Load(path.str)
	if unsafe { surface == nil } {
		return unsafe { nil }
	}
	texture := C.SDL_CreateTextureFromSurface(ctx.renderer, surface)
	C.SDL_DestroySurface(surface)
	if unsafe { texture == nil } {
		return unsafe { nil }
	}
	C.SDL_SetTextureBlendMode(texture, sdl_blendmode_blend)
	ctx.icon_cache[path] = texture
	return texture
}

pub fn (mut ctx RenderContext) draw_icon(texture voidptr, x f32, y f32, w f32, h f32) {
	if unsafe { texture == nil } {
		return
	}
	dst := C.SDL_FRect{
		x: x
		y: y
		w: w
		h: h
	}
	C.SDL_RenderTexture(ctx.renderer, texture, unsafe { nil }, &dst)
}

// Returns true if r intersects the topmost clip rect (or no clipping active).
pub fn (ctx &RenderContext) is_in_clip(r Rect) bool {
	if ctx.clip_stack.len == 0 {
		return true
	}
	last := ctx.clip_stack[ctx.clip_stack.len - 1]
	return r.intersects(last)
}

pub fn (mut ctx RenderContext) mark_anim(reason string) {
	ctx.needs_animation = true
	if ctx.anim_reason == '' {
		ctx.anim_reason = reason
	}
	// Unqualified mark_anim doesn't know what changed, so it forces a full
	// frame — the same behavior the codebase already had before dirty
	// regions existed. Widgets that know their own bounds should migrate to
	// mark_anim_rect() instead (see TextInput's cursor blink for the model).
	ctx.invalidate_all()
}

// mark_anim_rect is like mark_anim, but instead of forcing a full frame it
// only invalidates r (widget-local coordinates in the window's logical
// space). This is the migration path for widgets that animate themselves
// without needing the rest of the window redrawn.
//
// Two guards keep this from setting needs_animation without anything to
// show for it — which otherwise wedges the app into a permanent 60fps loop
// (see PROJECT.md, "needs_animation залипает навсегда"): once set with no
// non-empty dirty rect behind it, nothing else ever clears it, since the
// per-frame reset only fires when the frame actually draws, and a frame
// only draws when the dirty region is non-empty.
//
//  1. is_in_clip(r): a widget that calls this from its own draw() may be
//     sitting fully outside this frame's actual repaint area: a ScrollBox's
//     viewport clip, or (during a partial frame) the dirty rect itself. If
//     r doesn't intersect the effective clip, this frame isn't going to
//     redraw it anyway — asking for another one changes nothing and only
//     keeps the render loop spinning at 60fps for a widget that's scrolled
//     out of view or on a hidden tab.
//  2. invalidate(r)'s return value: even when in-clip, r can still clamp
//     away to nothing against the window's own screen bounds (widget
//     positioned or scrolled fully off-window) — see DirtyRegion.add.
//     Setting needs_animation off the back of a rect that contributed
//     nothing to the dirty region is exactly the stuck-flag scenario.
//
// ─── Why guard 1 cannot freeze a running animation (THE invariant) ───
//
// Refusing to re-arm needs_animation for an out-of-clip widget looks like it
// could strand an animation forever: miss one partial frame, never mark
// again, never get drawn again. It cannot, and the reason is that the dirty
// region reaches render() as the BOUNDING BOX of every rect accumulated for
// the frame (DirtyRegion.union_rect — see dirty.v). A widget that marked
// itself during frame N therefore has its own rect inside frame N+1's
// repaint area BY CONSTRUCTION: whatever else got added, the bbox still
// contains it. So it is drawn again, marks itself again, and the animation
// is self-sustaining from the first mark onward. Do not "fix" this by
// removing the guards; that only brings back the stuck flag.
//
// The single way a widget leaves that loop is by becoming genuinely
// invisible: scrolled out of a ScrollBox's viewport, on an inactive TabBox
// tab, inside a collapsed Accordion section, on a hidden Stack layer. In
// every one of those cases becoming visible again happens through an input
// event, and dispatch_event_with_app() calls invalidate_all() for input
// events — the next frame is full, the widget draws, and it re-arms itself.
// The two paths that change state with no input event behind them
// (app.post() closures, tray clicks) are covered by the same hammer via
// App.invalidate_all_windows() in run().
//
// Corollary — do not read anything into call ORDER at the call sites:
// whether a widget calls mark_anim_rect before or after its own
// `if !ctx.is_in_clip(bounds) { return }` is immaterial, because this
// function re-checks that very predicate with that very rect, and nothing
// in between changes it. The four widgets that mark first (spinner.v,
// progress_bar.v, code_editor.v, accordion.v) do so only to keep the
// animation bookkeeping in one place at the top of draw().
pub fn (mut ctx RenderContext) mark_anim_rect(reason string, r Rect) {
	if !ctx.is_in_clip(r) {
		return
	}
	if !ctx.invalidate(r) {
		return
	}
	ctx.needs_animation = true
	if ctx.anim_reason == '' {
		ctx.anim_reason = reason
	}
}

// visual_margin returns how far a widget can paint beyond its own bounds
// under the current theme, so a caller invalidating exactly a widget's
// bounds still covers everything actually drawn for it. The only built-in
// primitive that overshoots bounds is draw_shadow (offset + blur expand
// outward); draw_focus_ring is drawn INSET (shrunk into bounds), so it never
// needs margin. A widget whose custom drawing reaches further out than this
// (e.g. a huge custom shadow_blur) must invalidate an already-widened rect
// itself instead of relying on this default.
pub fn (ctx &RenderContext) visual_margin() f32 {
	return ctx.theme.shadow_blur + abs_f32(ctx.theme.shadow_offset)
}

// invalidate marks r (logical coordinates) as changed and due for repaint on
// the next frame. r is widened by visual_margin() first — callers normally
// pass a widget's own `bounds`, but widgets are routinely drawn with a
// shadow that extends past them (see draw_shadow/theme.shadow_blur), and a
// dirty rect that stops at the bare bounds leaves stale shadow pixels behind
// when the widget's state changes (e.g. hover ending) — a partial repaint
// that doesn't cover them can never erase them. Clamped to the window's
// screen bounds.
//
// Returns true if the rect was actually accepted (or the region was already
// full) — false if it clamped away to nothing against the window's screen
// bounds. See mark_anim_rect for why callers that gate other state on this
// must check it rather than assume every invalidate() sticks.
pub fn (mut ctx RenderContext) invalidate(r Rect) bool {
	// Любая инвалидация — повод пересчитать раскладку: изменение, ради
	// которого перерисовывают прямоугольник, могло сдвинуть и bounds.
	// Консервативно (как и invalidate_all() на каждое событие); разделение
	// «грязно для отрисовки» и «грязно для раскладки» — отдельная задача.
	ctx.layout_dirty = true
	if ctx.dirty.full {
		return true
	}
	bounds := Rect{0, 0, ctx.screen_width, ctx.screen_height}
	visual := r.expanded(ctx.visual_margin())
	return ctx.dirty.add(visual, bounds)
}

// invalidate_all forces the next frame to be a full repaint.
pub fn (mut ctx RenderContext) invalidate_all() {
	ctx.layout_dirty = true
	ctx.dirty.mark_full()
}

// request_layout просит пересчитать раскладку до следующего события или кадра,
// не помечая ничего грязным для отрисовки.
pub fn (mut ctx RenderContext) request_layout() {
	ctx.layout_dirty = true
}
