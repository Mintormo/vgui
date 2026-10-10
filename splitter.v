module vgui

// ═══════════════════════════════════════════════════════
// Splitter — resizable split container
//
// Divides available space between two child widgets
// with a draggable divider bar. Supports horizontal
// (left|right) and vertical (top|bottom) orientations.
//
// Usage (code):
//   mut sp := vgui.splitter(.horizontal)
//   sp.set_first(left_widget)
//   sp.set_second(right_widget)
//   sp.ratio = 0.3          // 30% to first, 70% to second
//   sp.min_first = 100      // first pane at least 100px
//   sp.min_second = 150     // second pane at least 150px
//
// Usage (YAML):
//   type: splitter
//   dir: horizontal
//   ratio: 0.3
//   min_first: 100
//   min_second: 150
//   bar_size: 4
//   first:
//     type: panel
//     ...
//   second:
//     type: vbox
//     ...
// ═══════════════════════════════════════════════════════

pub enum SplitDir {
	horizontal // first=left, second=right, bar is vertical line
	vertical   // first=top, second=bottom, bar is horizontal line
}

pub struct Splitter {
pub mut:
	type_tag   int = kind_splitter // тег типа, см. widget_tag.v
	bounds     Rect
	dir        SplitDir = .horizontal
	ratio      f32      = 0.5               // 0..1, fraction of space for first pane
	min_first  f32      = 50                // minimum size of first pane (px)
	min_second f32      = 50                // minimum size of second pane (px)
	bar_size   f32      = 4                 // thickness of the divider bar (thin; see bar_hit_rect for grab area)
	bar_color  Color    = Color{0, 0, 0, 0} // 0 = use theme
	bar_hover  Color    = Color{0, 0, 0, 0}
	bar_drag   Color    = Color{0, 0, 0, 0}
	visible    bool     = true
	// Children
	first  &Widget = unsafe { nil }
	second &Widget = unsafe { nil }
	// Internal drag state
	dragging    bool
	hovered     bool
	drag_offset f32 // offset from bar center to mouse at drag start
	// Callback
	on_resize fn (f32) = unsafe { nil } // called with new ratio
}

// ─── Constructors ──────────────────────────────────────

pub fn splitter(dir SplitDir) &Splitter {
	return &Splitter{
		dir: dir
	}
}

pub fn splitter_horizontal() &Splitter {
	return &Splitter{
		dir: .horizontal
	}
}

pub fn splitter_vertical() &Splitter {
	return &Splitter{
		dir: .vertical
	}
}

// ─── Public API ────────────────────────────────────────

pub fn (mut s Splitter) set_first(w &Widget) {
	s.first = unsafe { w }
}

pub fn (mut s Splitter) set_second(w &Widget) {
	s.second = unsafe { w }
}

// clear_first / clear_second detach a pane (no free — caller owns it).
pub fn (mut s Splitter) clear_first() {
	s.first = unsafe { nil }
}

pub fn (mut s Splitter) clear_second() {
	s.second = unsafe { nil }
}

pub fn (mut s Splitter) set_ratio(r f32) {
	s.ratio = clamp_f32(r, 0.0, 1.0)
}

pub fn (s &Splitter) get_ratio() f32 {
	return s.ratio
}

// ─── Geometry helpers ──────────────────────────────────

// Total available space along the split axis
fn (s &Splitter) total_main() f32 {
	return match s.dir {
		.horizontal { s.bounds.w }
		.vertical { s.bounds.h }
	}
}

// Clamp ratio so both panes respect min sizes
fn (s &Splitter) clamped_ratio() f32 {
	total := s.total_main()
	usable := total - s.bar_size
	if usable <= 0 {
		return 0.5
	}
	first_sz := s.ratio * usable
	second_sz := usable - first_sz

	mut r := s.ratio
	if first_sz < s.min_first {
		r = s.min_first / usable
	}
	if second_sz < s.min_second {
		r = (usable - s.min_second) / usable
	}
	return clamp_f32(r, 0.0, 1.0)
}

fn (s &Splitter) first_rect() Rect {
	r := s.clamped_ratio()
	usable := s.total_main() - s.bar_size
	first_sz := r * usable

	return match s.dir {
		.horizontal {
			Rect{s.bounds.x, s.bounds.y, first_sz, s.bounds.h}
		}
		.vertical {
			Rect{s.bounds.x, s.bounds.y, s.bounds.w, first_sz}
		}
	}
}

fn (s &Splitter) bar_rect() Rect {
	r := s.clamped_ratio()
	usable := s.total_main() - s.bar_size
	first_sz := r * usable

	return match s.dir {
		.horizontal {
			Rect{s.bounds.x + first_sz, s.bounds.y, s.bar_size, s.bounds.h}
		}
		.vertical {
			Rect{s.bounds.x, s.bounds.y + first_sz, s.bounds.w, s.bar_size}
		}
	}
}

fn (s &Splitter) second_rect() Rect {
	br := s.bar_rect()
	return match s.dir {
		.horizontal {
			x2 := br.x + br.w
			Rect{x2, s.bounds.y, s.bounds.x + s.bounds.w - x2, s.bounds.h}
		}
		.vertical {
			y2 := br.y + br.h
			Rect{s.bounds.x, y2, s.bounds.w, s.bounds.y + s.bounds.h - y2}
		}
	}
}

// Expanded hit area for easier grabbing (± 4px beyond visual bar) — the visual
// bar is thin (bar_size), so the hit zone is widened to keep it easy to grab.
fn (s &Splitter) bar_hit_rect() Rect {
	br := s.bar_rect()
	expand := f32(4)
	return match s.dir {
		.horizontal {
			Rect{br.x - expand, br.y, br.w + expand * 2, br.h}
		}
		.vertical {
			Rect{br.x, br.y - expand, br.w, br.h + expand * 2}
		}
	}
}

// ─── Effective colors ──────────────────────────────────

fn (s &Splitter) eff_bar_color(ctx &RenderContext) Color {
	if s.bar_color.a > 0 {
		return s.bar_color
	}
	return ctx.theme.eff_splitter_handle()
}

fn (s &Splitter) eff_bar_hover(ctx &RenderContext) Color {
	if s.bar_hover.a > 0 {
		return s.bar_hover
	}
	return ctx.theme.eff_splitter_hover().with_alpha(120)
}

fn (s &Splitter) eff_bar_drag(ctx &RenderContext) Color {
	if s.bar_drag.a > 0 {
		return s.bar_drag
	}
	return ctx.theme.eff_splitter_hover().with_alpha(180)
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut s Splitter) arrange(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if is_bounds_unset(s.bounds) {
		s.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	if unsafe { s.first != nil } {
		arrange_child(mut s.first, s.first_rect(), mut ctx)
	}
	if unsafe { s.second != nil } {
		arrange_child(mut s.second, s.second_rect(), mut ctx)
	}
}

pub fn (mut s Splitter) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}

	// Draw first child
	if unsafe { s.first != nil } {
		fr := s.first_rect()
		ctx.push_clip(fr)
		s.first.draw(mut ctx)
		ctx.pop_clip()
	}

	// Draw second child
	if unsafe { s.second != nil } {
		sr := s.second_rect()
		ctx.push_clip(sr)
		s.second.draw(mut ctx)
		ctx.pop_clip()
	}

	// Draw bar. Idle state is invisible (unless a custom bar_color is set) —
	// the bar only lights up on hover/drag; discoverability comes from the
	// resize cursor and the expanded hit zone (bar_hit_rect).
	if !s.dragging && !s.hovered && s.bar_color.a == 0 {
		return
	}
	br := s.bar_rect()
	bar_c := if s.dragging {
		s.eff_bar_drag(ctx)
	} else if s.hovered {
		s.eff_bar_hover(ctx)
	} else {
		s.eff_bar_color(ctx)
	}
	ctx.fill_rect(br, bar_c)

	// Draw grip dots in the center of the bar
	s.draw_grip(br, bar_c, mut ctx)
}

fn (s &Splitter) draw_grip(br Rect, bar_c Color, mut ctx RenderContext) {
	grip_c := bar_c.brighten(0.15)
	dot_r := f32(1.5)
	dot_gap := f32(6)
	dot_count := 3

	cx := br.x + br.w * 0.5
	cy := br.y + br.h * 0.5

	match s.dir {
		.horizontal {
			// Vertical dots
			start_y := cy - f32(dot_count - 1) * dot_gap * 0.5
			for i in 0 .. dot_count {
				dy := start_y + f32(i) * dot_gap
				ctx.fill_circle(cx, dy, dot_r, grip_c)
			}
		}
		.vertical {
			// Horizontal dots
			start_x := cx - f32(dot_count - 1) * dot_gap * 0.5
			for i in 0 .. dot_count {
				dx := start_x + f32(i) * dot_gap
				ctx.fill_circle(dx, cy, dot_r, grip_c)
			}
		}
	}
}

// ─── Events ────────────────────────────────────────────

pub fn (mut s Splitter) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible {
		return false
	}

	// While dragging, consume all mouse move/up globally
	if s.dragging {
		match event.typ {
			.mouse_move {
				s.update_ratio_from_mouse(event.mouse_x, event.mouse_y)
				// Set appropriate cursor
				s.set_resize_cursor()
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					s.dragging = false
					s.restore_cursor()
					if s.on_resize != unsafe { nil } {
						s.on_resize(s.ratio)
					}
					return true
				}
			}
			else {}
		}

		return true
	}

	hit := s.bar_hit_rect()

	match event.typ {
		.mouse_move {
			was_hovered := s.hovered
			s.hovered = hit.contains(event.mouse_x, event.mouse_y)
			// Don't change cursor if we're in a borderless drag zone
			// (the app-level cursor management handles that)
			ctx_ptr := app.get_active_ctx()
			mut skip_cursor := false
			if unsafe { ctx_ptr != nil } {
				// Check if any parent window has in_drag_zone set
				for i in 0 .. app.windows.len {
					w_ptr := app.windows[i]
					if w_ptr.open && unsafe { &w_ptr.ctx == ctx_ptr } {
						if w_ptr.in_drag_zone {
							skip_cursor = true
						}
						break
					}
				}
			}
			if !skip_cursor {
				if s.hovered && !was_hovered {
					s.set_resize_cursor()
				} else if !s.hovered && was_hovered {
					s.restore_cursor()
				}
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && hit.contains(event.mouse_x, event.mouse_y) {
				s.dragging = true
				// Calculate offset from bar center
				br := s.bar_rect()
				match s.dir {
					.horizontal {
						s.drag_offset = event.mouse_x - (br.x + br.w * 0.5)
					}
					.vertical {
						s.drag_offset = event.mouse_y - (br.y + br.h * 0.5)
					}
				}

				s.set_resize_cursor()
				return true
			}
		}
		else {}
	}

	// Pass events to children (second first for z-order, then first)
	if unsafe { s.second != nil } {
		if s.second.handle_event(event, app) {
			return true
		}
	}
	if unsafe { s.first != nil } {
		if s.first.handle_event(event, app) {
			return true
		}
	}

	return false
}

fn (mut s Splitter) update_ratio_from_mouse(mx f32, my f32) {
	usable := s.total_main() - s.bar_size
	if usable <= 0 {
		return
	}

	// Mouse position along split axis, minus offset, minus bounds origin
	mouse_pos := match s.dir {
		.horizontal { mx - s.drag_offset - s.bounds.x }
		.vertical { my - s.drag_offset - s.bounds.y }
	}

	// mouse_pos is where bar center should be
	// first_size = mouse_pos - half_bar
	first_sz := mouse_pos - s.bar_size * 0.5
	new_ratio := first_sz / usable

	// Clamp with min constraints
	mut r := clamp_f32(new_ratio, 0.0, 1.0)
	if r * usable < s.min_first {
		r = s.min_first / usable
	}
	if (1.0 - r) * usable < s.min_second {
		r = (usable - s.min_second) / usable
	}
	s.ratio = clamp_f32(r, 0.0, 1.0)
}

fn (s &Splitter) set_resize_cursor() {
	cursor_id := match s.dir {
		.horizontal { sdl_system_cursor_sizewe }
		.vertical { sdl_system_cursor_sizens }
	}

	cursor := C.SDL_CreateSystemCursor(cursor_id)
	C.SDL_SetCursor(cursor)
}

fn (s &Splitter) restore_cursor() {
	cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
	C.SDL_SetCursor(cursor)
}
