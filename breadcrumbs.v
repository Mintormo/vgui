// Файл: ./breadcrumbs.v
module vgui

// ═══════════════════════════════════════════════════════
// Breadcrumbs — navigation path widget
//
// Displays a clickable path of items separated by a
// configurable separator (default: "›"). Each item
// fires on_click(index, text) when clicked. The last
// item is rendered as the "current" location and is
// not clickable by default.
//
// Features:
//   - Clickable path segments with hover effect
//   - Configurable separator (text or icon)
//   - Auto-truncation with ellipsis for overflow
//   - Optional home icon for the first item
//   - Custom colors for normal / hover / current states
//
// Usage (code):
//   mut bc := vgui.breadcrumbs()
//   bc.add('Home')
//   bc.add('Documents')
//   bc.add('Projects')
//   bc.add('vgui')
//   bc.on_click = fn (idx int, text string) {
//       println('Clicked: ${idx} = ${text}')
//   }
//
// Usage (YAML):
//   type: breadcrumbs
//   separator: " / "
//   items:
//     - Home
//     - Documents
//     - Projects
//   on_click: nav_handler
// ═══════════════════════════════════════════════════════

const bc_default_separator = ' › '
const bc_pad_h = f32(8)
const bc_pad_v = f32(4)
const bc_sep_pad = f32(2)
const bc_min_segment_w = f32(20)

struct BcSegment {
mut:
	text    string
	hovered bool
	// Computed during layout
	x f32
	w f32
	// True if truncated with ellipsis
	truncated bool
}

@[heap]
pub struct Breadcrumbs {
pub mut:
	type_tag int = kind_breadcrumbs // тег типа, см. widget_tag.v
	bounds   Rect
	items    []string
	visible  bool = true
	enabled  bool = true
	hovered  bool
	// Appearance
	separator         string    = bc_default_separator
	font_style        FontStyle = .regular
	font_size         int
	pad_h             f32 = bc_pad_h
	pad_v             f32 = bc_pad_v
	radius            f32 = -1 // <0 → use theme.border_radius
	current_clickable bool // if true, the last segment is also clickable
	// Colors (a=0 → use theme defaults)
	bg_color        Color = Color{0, 0, 0, 0}
	border_color    Color = Color{0, 0, 0, 0}
	text_color      Color = Color{0, 0, 0, 0}
	hover_color     Color = Color{0, 0, 0, 0}
	current_color   Color = Color{0, 0, 0, 0}
	separator_color Color = Color{0, 0, 0, 0}
	hover_bg_color  Color = Color{0, 0, 0, 0}
	// Internal layout
	segments      []BcSegment
	sep_w         f32  // measured separator width
	overflow      bool // true when items don't fit
	hidden_before int  // count of items hidden at start (after collapse)
	// Callbacks
	on_click fn (int, string) = unsafe { nil }
}

// ─── Constructors ──────────────────────────────────────

pub fn breadcrumbs() &Breadcrumbs {
	return &Breadcrumbs{}
}

pub fn breadcrumbs_with_items(items []string) &Breadcrumbs {
	return &Breadcrumbs{
		items: items.clone()
	}
}

// ─── Public API ────────────────────────────────────────

pub fn (mut bc Breadcrumbs) add(item string) {
	bc.items << item
}

pub fn (mut bc Breadcrumbs) set_items(items []string) {
	bc.items = items.clone()
}

pub fn (mut bc Breadcrumbs) clear() {
	bc.items.clear()
	bc.segments.clear()
	bc.hidden_before = 0
	bc.overflow = false
}

pub fn (bc &Breadcrumbs) get_items() []string {
	return bc.items.clone()
}

pub fn (bc &Breadcrumbs) count() int {
	return bc.items.len
}

pub fn (mut bc Breadcrumbs) push(item string) {
	bc.items << item
}

pub fn (mut bc Breadcrumbs) pop() {
	if bc.items.len > 0 {
		bc.items.delete(bc.items.len - 1)
	}
}

pub fn (mut bc Breadcrumbs) set_path_from_string(path string, sep string) {
	bc.items.clear()
	if path.len == 0 {
		return
	}
	parts := path.split(sep)
	for p in parts {
		t := p.trim_space()
		if t.len > 0 {
			bc.items << t
		}
	}
}

pub fn (bc &Breadcrumbs) get_path(sep string) string {
	return bc.items.join(sep)
}

// ─── Effective colors ──────────────────────────────────

fn (bc &Breadcrumbs) eff_bg(_ &RenderContext) Color {
	if bc.bg_color.a > 0 {
		return bc.bg_color
	}
	return Color{0, 0, 0, 0}
}

fn (bc &Breadcrumbs) eff_border(_ &RenderContext) Color {
	if bc.border_color.a > 0 {
		return bc.border_color
	}
	return Color{0, 0, 0, 0}
}

fn (bc &Breadcrumbs) eff_text(ctx &RenderContext) Color {
	if bc.text_color.a > 0 {
		return bc.text_color
	}
	return ctx.theme.eff_brc_text()
}

fn (bc &Breadcrumbs) eff_hover(ctx &RenderContext) Color {
	if bc.hover_color.a > 0 {
		return bc.hover_color
	}
	return ctx.theme.accent
}

fn (bc &Breadcrumbs) eff_current(ctx &RenderContext) Color {
	if bc.current_color.a > 0 {
		return bc.current_color
	}
	return ctx.theme.eff_brc_active_text()
}

fn (bc &Breadcrumbs) eff_separator(ctx &RenderContext) Color {
	if bc.separator_color.a > 0 {
		return bc.separator_color
	}
	return ctx.theme.eff_brc_separator()
}

fn (bc &Breadcrumbs) eff_hover_bg(ctx &RenderContext) Color {
	if bc.hover_bg_color.a > 0 {
		return bc.hover_bg_color
	}
	return ctx.theme.eff_brc_hover_bg().with_alpha(80)
}

fn (bc &Breadcrumbs) eff_radius(ctx &RenderContext) f32 {
	if bc.radius >= 0 {
		return bc.radius
	}
	return max_f32(ctx.theme.border_radius * 0.5, 3)
}

// ─── Layout ────────────────────────────────────────────

fn (mut bc Breadcrumbs) layout(ctx &RenderContext) {
	bc.segments.clear()
	bc.hidden_before = 0
	bc.overflow = false

	if bc.items.len == 0 {
		return
	}

	font := ctx.get_font_immut(bc.font_style, bc.font_size)
	bc.sep_w = ctx.measure_text_with_font(bc.separator, font).x

	avail_w := bc.bounds.w - bc.pad_h * 2
	if avail_w <= 0 {
		return
	}

	// Build all segments first with full text
	mut segs := []BcSegment{cap: bc.items.len}
	for item in bc.items {
		w := ctx.measure_text_with_font(item, font).x
		segs << BcSegment{
			text: item
			w:    w
		}
	}

	// Calculate total width with separators
	mut total := f32(0)
	for i, s in segs {
		total += s.w
		if i < segs.len - 1 {
			total += bc.sep_w
		}
	}

	// If fits — assign x positions and we're done
	if total <= avail_w {
		mut x := bc.bounds.x + bc.pad_h
		for i in 0 .. segs.len {
			segs[i].x = x
			x += segs[i].w
			if i < segs.len - 1 {
				x += bc.sep_w
			}
		}
		bc.segments = segs
		return
	}

	// Overflow: use "..." prefix and keep last items
	bc.overflow = true
	ellipsis := '…'
	ell_w := ctx.measure_text_with_font(ellipsis, font).x

	// Always keep last item (current). Try to fit as many tail items as possible.
	last_idx := segs.len - 1
	mut tail_w := segs[last_idx].w
	mut keep_count := 1
	mut prefix_w := ell_w + bc.sep_w

	for i := last_idx - 1; i > 0; i-- {
		add_w := segs[i].w + bc.sep_w
		if prefix_w + tail_w + add_w > avail_w {
			break
		}
		tail_w += add_w
		keep_count++
	}

	// If even one item + ellipsis doesn't fit, truncate the last item itself
	if prefix_w + tail_w > avail_w {
		bc.segments.clear()
		// Truncate last item to fit
		max_w := avail_w - prefix_w
		truncated := bc_truncate_text(ctx, segs[last_idx].text, max_w, font)
		tw := ctx.measure_text_with_font(truncated, font).x
		bc.segments << BcSegment{
			text:      ellipsis
			w:         ell_w
			x:         bc.bounds.x + bc.pad_h
			truncated: false
		}
		bc.segments << BcSegment{
			text:      truncated
			w:         tw
			x:         bc.bounds.x + bc.pad_h + ell_w + bc.sep_w
			truncated: true
		}
		bc.hidden_before = segs.len - 1
		return
	}

	// Build collapsed view: ellipsis + last keep_count items
	bc.hidden_before = segs.len - keep_count
	mut x := bc.bounds.x + bc.pad_h
	bc.segments << BcSegment{
		text: ellipsis
		w:    ell_w
		x:    x
	}
	x += ell_w + bc.sep_w

	for i := segs.len - keep_count; i < segs.len; i++ {
		bc.segments << BcSegment{
			text: segs[i].text
			w:    segs[i].w
			x:    x
		}
		x += segs[i].w
		if i < segs.len - 1 {
			x += bc.sep_w
		}
	}
}

// Truncate text to fit max_w with ellipsis
fn bc_truncate_text(ctx &RenderContext, text string, max_w f32, font voidptr) string {
	if max_w <= 0 {
		return ''
	}
	tw := ctx.measure_text_with_font(text, font).x
	if tw <= max_w {
		return text
	}
	ellipsis := '…'
	ew := ctx.measure_text_with_font(ellipsis, font).x
	if ew >= max_w {
		return ellipsis
	}
	target := max_w - ew
	runes := text.runes()
	mut lo := 0
	mut hi := runes.len
	for lo < hi {
		mid := (lo + hi + 1) / 2
		sub := runes[..mid].string()
		sw := ctx.measure_text_with_font(sub, font).x
		if sw <= target {
			lo = mid
		} else {
			hi = mid - 1
		}
	}
	if lo == 0 {
		return ellipsis
	}
	return runes[..lo].string() + ellipsis
}

// Map a visible segment index to the original items index.
// Returns -1 for the ellipsis segment or invalid index.
fn (bc &Breadcrumbs) segment_to_item_index(seg_idx int) int {
	if seg_idx < 0 || seg_idx >= bc.segments.len {
		return -1
	}
	if !bc.overflow {
		return seg_idx
	}
	// Overflow layout: [ellipsis, item, item, ...]
	if seg_idx == 0 {
		return -1 // ellipsis
	}
	// segments[1..] correspond to items[hidden_before..]
	return bc.hidden_before + (seg_idx - 1)
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut bc Breadcrumbs) draw(mut ctx RenderContext) {
	if !bc.visible || bc.items.len == 0 {
		return
	}
	if !ctx.is_in_clip(bc.bounds) {
		return
	}

	// Layout each frame (cheap — only on bounds/items change matters but
	// keeps it simple and correct on resize)
	bc.layout(ctx)

	rad := bc.eff_radius(ctx)

	// Background
	bg := bc.eff_bg(ctx)
	if bg.a > 0 {
		ctx.fill_rounded_rect(bc.bounds, bg, rad)
	}

	// Border
	border := bc.eff_border(ctx)
	if border.a > 0 {
		ctx.draw_rounded_rect(bc.bounds, border, rad)
	}

	if bc.segments.len == 0 {
		return
	}

	font := ctx.get_font(bc.font_style, bc.font_size)
	fh := ctx.font_height_of(font)

	tc_normal := bc.eff_text(ctx)
	tc_hover := bc.eff_hover(ctx)
	tc_current := bc.eff_current(ctx)
	tc_sep := bc.eff_separator(ctx)
	bg_hover := bc.eff_hover_bg(ctx)

	cy := bc.bounds.y + bc.bounds.h * 0.5
	ty := cy - fh * 0.5

	ctx.push_clip(bc.bounds)

	last_seg := bc.segments.len - 1

	for i in 0 .. bc.segments.len {
		seg := bc.segments[i]
		item_idx := bc.segment_to_item_index(i)
		is_last := i == last_seg
		is_current := is_last && item_idx == bc.items.len - 1
		is_ellipsis := bc.overflow && i == 0
		is_clickable := bc.is_segment_clickable(i, item_idx)

		// Hover background pill
		if seg.hovered && is_clickable && bc.enabled {
			pill_r := Rect{
				x: seg.x - bc_sep_pad
				y: cy - fh * 0.5 - bc.pad_v * 0.5
				w: seg.w + bc_sep_pad * 2
				h: fh + bc.pad_v
			}
			ctx.fill_rounded_rect(pill_r, bg_hover, max_f32(rad - 1, 2))
		}

		// Text color
		mut tc := tc_normal
		if !bc.enabled {
			tc = ctx.theme.text_disabled
		} else if is_ellipsis {
			tc = tc_sep
		} else if seg.hovered && is_clickable {
			tc = tc_hover
		} else if is_current {
			tc = tc_current
		}

		ctx.draw_text_with_font(seg.text, seg.x, ty, tc, font)

		// Separator after this segment (but not after last)
		if i < last_seg {
			sep_x := seg.x + seg.w
			ctx.draw_text_with_font(bc.separator, sep_x, ty, tc_sep, font)
		}
	}

	ctx.pop_clip()
}

fn (bc &Breadcrumbs) is_segment_clickable(seg_idx int, item_idx int) bool {
	if !bc.enabled {
		return false
	}
	// Ellipsis is not clickable (could be made into a popup later)
	if bc.overflow && seg_idx == 0 {
		return false
	}
	if item_idx < 0 || item_idx >= bc.items.len {
		return false
	}
	// Last item (current) is clickable only if explicitly enabled
	if item_idx == bc.items.len - 1 && !bc.current_clickable {
		return false
	}
	return true
}

// ─── Hit testing ──────────────────────────────────────

fn (bc &Breadcrumbs) hit_segment(mx f32, my f32) int {
	if my < bc.bounds.y || my > bc.bounds.y + bc.bounds.h {
		return -1
	}
	for i, seg in bc.segments {
		// Hit area extends slightly beyond text for easier clicking
		hx := seg.x - bc_sep_pad
		hw := seg.w + bc_sep_pad * 2
		if mx >= hx && mx < hx + hw {
			return i
		}
	}
	return -1
}

// ─── Events ────────────────────────────────────────────

pub fn (mut bc Breadcrumbs) handle_event(event &GuiEvent, app &App) bool {
	if !bc.visible || !bc.enabled || bc.items.len == 0 {
		return false
	}

	match event.typ {
		.mouse_move {
			bc.hovered = bc.bounds.contains(event.mouse_x, event.mouse_y)
			// Reset all hover flags
			for i in 0 .. bc.segments.len {
				bc.segments[i].hovered = false
			}
			if bc.hovered {
				idx := bc.hit_segment(event.mouse_x, event.mouse_y)
				if idx >= 0 {
					item_idx := bc.segment_to_item_index(idx)
					if bc.is_segment_clickable(idx, item_idx) {
						bc.segments[idx].hovered = true
						// Set hand cursor
						cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_hand)
						C.SDL_SetCursor(cursor)
					} else {
						cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
						C.SDL_SetCursor(cursor)
					}
				} else {
					cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
					C.SDL_SetCursor(cursor)
				}
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && bc.bounds.contains(event.mouse_x, event.mouse_y) {
				idx := bc.hit_segment(event.mouse_x, event.mouse_y)
				if idx >= 0 {
					item_idx := bc.segment_to_item_index(idx)
					if bc.is_segment_clickable(idx, item_idx) {
						if bc.on_click != unsafe { nil } {
							bc.on_click(item_idx, bc.items[item_idx])
						}
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
