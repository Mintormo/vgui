module vgui

// ═══════════════════════════════════════════════════════
// Spinbox — integer input with increment/decrement buttons
//
// Features:
//   - Min/max range (integers)
//   - Step size for increment/decrement (integer)
//   - Editable text input (digits and optional leading minus only)
//   - Optional prefix/suffix text
//   - Callbacks on value change
// ═══════════════════════════════════════════════════════
import strconv

@[heap]
pub struct Spinbox {
pub mut:
	type_tag    int = kind_spinbox // тег типа, см. widget_tag.v
	bounds      Rect
	value       int
	min         int
	max         int  = 100
	step        int  = 1
	visible     bool = true
	enabled     bool = true
	focus_group int
	focus_anim  Anim = Anim{
		tau_ms:  anim_tau_focus
		epsilon: 0.02
	} // animated focus ring strength (0..1)
	hovered_dec bool // hover state for decrement button
	hovered_inc bool // hover state for increment button
	active_dec  bool // pressed state for decrement button
	active_inc  bool // pressed state for increment button
	// Text input part for editing
	text_input &TextInput = unsafe { nil }
	prefix     string
	suffix     string
	on_change  fn (int) = unsafe { nil }
	// Tracks the previous focus state of the embedded text input so we
	// can normalize (clamp + reformat) the entered text exactly once,
	// on the focused→unfocused transition.
	was_ti_focused bool
}

// ─── Constructors ──────────────────────────────────────

pub fn spinbox() &Spinbox {
	mut s := &Spinbox{}
	mut ti := text_input('')
	ti.max_len = 16
	// Spinbox draws its own rounded background and border; the inner
	// text input must blend in with square edges, otherwise we get a
	// rounded rectangle inside a rounded rectangle.
	ti.flat = true
	// Spinbox holds integer values only — the filter blocks anything
	// other than digits and an optional leading minus at insertion
	// time, so we no longer need to overwrite the text on every
	// keystroke.
	ti.input_filter = r'^-?[0-9]*$'
	ti.input_filter_mode = .pattern
	// While the user is typing, just track the parsed value without
	// clamping or reformatting — clamping during entry would block
	// transitional strings like "" or "-" before the user types the
	// rest of the number. Normalization happens on blur.
	ti.on_change = fn [mut s] (txt string) {
		if txt.len == 0 || txt == '-' {
			return
		}
		val := strconv.atoi(txt) or { return }
		s.value = val
		if s.on_change != unsafe { nil } {
			s.on_change(s.value)
		}
	}
	s.text_input = ti
	s.update_text_input()
	return s
}

// ─── Internal ──────────────────────────────────────────

fn (mut s Spinbox) init_buttons_bounds() (Rect, Rect) {
	btn_w := s.bounds.h
	dec_r := Rect{s.bounds.x + s.bounds.w - btn_w * 2, s.bounds.y, btn_w, s.bounds.h}
	inc_r := Rect{s.bounds.x + s.bounds.w - btn_w, s.bounds.y, btn_w, s.bounds.h}
	return dec_r, inc_r
}

fn (s &Spinbox) format_value() string {
	return '${s.prefix}${s.value}${s.suffix}'
}

fn (mut s Spinbox) update_text_input() {
	if s.text_input != unsafe { nil } {
		txt := s.format_value()
		if txt != s.text_input.get_text() {
			mut ti := unsafe { s.text_input }
			ti.set_text(txt)
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut s Spinbox) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if !ctx.is_in_clip(s.bounds) {
		return
	}

	rad := ctx.theme.border_radius

	// Animated focus ring strength — real focus lives on the embedded
	// text input, not on Spinbox itself (see `focused` field removal note).
	ti_has_focus := s.text_input != unsafe { nil } && unsafe { s.text_input.focused }
	target_focus := if ti_has_focus && s.enabled { f32(1.0) } else { f32(0.0) }
	if s.focus_anim.update(target_focus, ctx) {
		// mark_anim_rect — см. button.v; кольцо фокуса рисуется внутрь bounds.
		ctx.mark_anim_rect('spinbox', s.bounds)
	}

	// Background
	bg := if s.enabled {
		ctx.theme.eff_spinbox_bg()
	} else {
		ctx.theme.eff_spinbox_bg().darken(0.1)
	}
	ctx.fill_rounded_rect(s.bounds, bg, rad)

	// Border
	bc := if ti_has_focus {
		ctx.theme.input_focus
	} else {
		ctx.theme.eff_spinbox_border()
	}
	ctx.draw_rounded_rect(s.bounds, bc, rad)

	// Focus ring
	ctx.draw_focus_ring_edge(s.bounds, rad, s.focus_anim.value)

	// Draw text input
	mut ti := unsafe { s.text_input }
	if ti != unsafe { nil } {
		ti.bounds = Rect{s.bounds.x, s.bounds.y, s.bounds.w - s.bounds.h * 2, s.bounds.h}
		ti.draw(mut ctx)
	}

	// Draw buttons [+] and [-]
	dec_rect, inc_rect := s.init_buttons_bounds()

	// Flat buttons: no permanent background or border. We only paint a
	// subtle overlay on hover/press so the buttons feel responsive but
	// stay visually merged with the Spinbox surface.
	transparent := Color{0, 0, 0, 0}
	dec_bg := if !s.enabled {
		transparent
	} else if s.active_dec {
		ctx.theme.button_pressed
	} else if s.hovered_dec {
		ctx.theme.eff_spinbox_btn_hover()
	} else {
		transparent
	}

	inc_bg := if !s.enabled {
		transparent
	} else if s.active_inc {
		ctx.theme.button_pressed
	} else if s.hovered_inc {
		ctx.theme.eff_spinbox_btn_hover()
	} else {
		transparent
	}

	// Clip to the outer rounded shape so the hover/press overlay never
	// pokes past the rounded edge when the widget is small.
	ctx.push_clip(s.bounds)
	if dec_bg.a > 0 {
		ctx.fill_rect(dec_rect, dec_bg)
	}
	if inc_bg.a > 0 {
		ctx.fill_rect(inc_rect, inc_bg)
	}
	ctx.pop_clip()

	sign_c := ctx.theme.eff_spinbox_text()
	// Draw minus sign
	mx := dec_rect.x + dec_rect.w * 0.5
	my := dec_rect.y + dec_rect.h * 0.5
	sign_size := dec_rect.h * 0.4
	ctx.draw_line(mx - sign_size * 0.5, my, mx + sign_size * 0.5, my, sign_c)

	// Draw plus sign
	px := inc_rect.x + inc_rect.w * 0.5
	py := inc_rect.y + inc_rect.h * 0.5
	ctx.draw_line(px - sign_size * 0.5, py, px + sign_size * 0.5, py, sign_c)
	ctx.draw_line(px, py - sign_size * 0.5, px, py + sign_size * 0.5, sign_c)
}

// ─── Events ────────────────────────────────────────────

pub fn (mut s Spinbox) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible || !s.enabled {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	match event.typ {
		.mouse_move {
			dec_rect, inc_rect := s.init_buttons_bounds()
			s.hovered_dec = dec_rect.contains(event.mouse_x, event.mouse_y)
			s.hovered_inc = inc_rect.contains(event.mouse_x, event.mouse_y)

			if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
				mut ti := unsafe { s.text_input }
				ti.handle_event(event, app)
			}
		}
		.mouse_down {
			if event.mouse_btn == .left {
				dec_rect, inc_rect := s.init_buttons_bounds()
				if dec_rect.contains(event.mouse_x, event.mouse_y) {
					s.active_dec = true
					return true
				}
				if inc_rect.contains(event.mouse_x, event.mouse_y) {
					s.active_inc = true
					return true
				}
				if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
					mut ti := unsafe { s.text_input }
					if ti.handle_event(event, app) {
						return true
					}
				}
			}
		}
		.mouse_up {
			if event.mouse_btn == .left {
				handled := s.active_dec || s.active_inc
				// Commit any text the user typed but never blurred. If
				// the typed value was out of range, clamping it counts
				// as the user action — don't ALSO step. Stepping only
				// happens when the typed value was already valid (or
				// the field hadn't been edited).
				mut stepped_value_was_clamped := false
				if handled {
					before := s.value
					s.normalize_text()
					if s.value != before {
						stepped_value_was_clamped = true
					}
				}
				if !stepped_value_was_clamped {
					if s.active_dec && s.value > s.min {
						s.set_value(s.value - s.step)
					}
					if s.active_inc && s.value < s.max {
						s.set_value(s.value + s.step)
					}
				}
				s.active_dec = false
				s.active_inc = false

				if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
					mut ti := unsafe { s.text_input }
					ti.handle_event(event, app)
				}

				return handled
			}
		}
		.key_down {
			if unsafe { ctx_ptr != nil } {
				mut ti := unsafe { s.text_input }
				if ti != unsafe { nil } && ti.handle_event(event, app) {
					return true
				}
				if s.text_input != unsafe { nil } && unsafe { s.text_input.focused } {
					match event.keycode {
						sdl_k_up {
							s.set_value(s.value + s.step)
							return true
						}
						sdl_k_down {
							s.set_value(s.value - s.step)
							return true
						}
						sdl_k_home {
							s.set_value(s.min)
							return true
						}
						sdl_k_end {
							s.set_value(s.max)
							return true
						}
						sdl_k_tab {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.tab(event.shift())
							return true
						}
						sdl_k_escape {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.blur_current()
							return true
						}
						else {}
					}
				}
			}
		}
		else {}
	}

	// Detect focused→unfocused on the embedded text input and run a
	// one-shot normalization (clamp into [min, max] + reformat). Doing
	// it only on blur means the field is not rewritten on every key
	// press, so the caret and selection are preserved while typing.
	if s.text_input != unsafe { nil } {
		ti_focused := unsafe { s.text_input.focused }
		if s.was_ti_focused && !ti_focused {
			s.normalize_text()
		}
		s.was_ti_focused = ti_focused
	}

	return s.hovered_dec || s.hovered_inc
		|| (s.text_input != unsafe { nil } && unsafe { s.text_input.handle_event(event, app) })
}

// normalize_text clamps the parsed value into [min, max] and rewrites
// the text input so it matches `format_value()`. Called on blur so that
// half-typed strings like "" or "-" are never persisted.
fn (mut s Spinbox) normalize_text() {
	if s.text_input == unsafe { nil } {
		return
	}
	txt := unsafe { s.text_input.get_text() }
	mut v := s.value
	if txt.len == 0 || txt == '-' {
		v = s.min
	} else {
		v = strconv.atoi(txt) or { s.value }
	}
	s.set_value(v)
	s.update_text_input()
}

// ─── Public API ────────────────────────────────────────

pub fn (s &Spinbox) get_value() int {
	return s.value
}

pub fn (mut s Spinbox) set_value(v int) {
	mut clamped := v
	if clamped < s.min {
		clamped = s.min
	}
	if clamped > s.max {
		clamped = s.max
	}
	if clamped != s.value {
		s.value = clamped
		if s.text_input != unsafe { nil } {
			s.update_text_input()
		}
		if s.on_change != unsafe { nil } {
			s.on_change(s.value)
		}
	}
}

// min > max меняются местами — так же, как в Slider.set_range.
pub fn (mut s Spinbox) set_range(min int, max int) {
	s.min = if min <= max { min } else { max }
	s.max = if min <= max { max } else { min }
	if s.value < s.min {
		s.set_value(s.min)
	}
	if s.value > s.max {
		s.set_value(s.max)
	}
}

pub fn (mut s Spinbox) set_step(step int) {
	if step > 0 {
		s.step = step
	}
}

pub fn (mut s Spinbox) set_prefix(p string) {
	s.prefix = p
	if s.text_input != unsafe { nil } {
		s.update_text_input()
	}
}

pub fn (mut s Spinbox) set_suffix(suf string) {
	s.suffix = suf
	if s.text_input != unsafe { nil } {
		s.update_text_input()
	}
}
