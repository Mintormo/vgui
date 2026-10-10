module vgui

pub enum SliderDir {
	horizontal
	vertical
}

@[heap]
pub struct Slider {
pub mut:
	type_tag int = kind_slider // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel       bool = true
	bounds      Rect
	dir         SliderDir = .horizontal
	value       f32
	min         f32
	max         f32 = 100.0
	step        f32 // 0 = continuous
	big_step    f32  = 10
	visible     bool = true
	enabled     bool = true
	hovered     bool
	dragging    bool
	focused     bool
	focus_anim  Anim = Anim{
		tau_ms:  anim_tau_focus
		epsilon: 0.02
	}
	hover_anim  Anim = Anim{
		tau_ms:  anim_tau_hover
		epsilon: 0.02
	}
	focus_group int
	// Visual
	track_thickness f32 = 6
	thumb_size      f32 = 16
	show_value      bool
	show_fill       bool = true // NEW: blue filled portion
	show_ticks      bool // NEW: draw tick marks at each step
	tick_size       f32    = 4 // NEW: tick line length
	value_format    string = '%.0f'
	value_gap       f32    = 8
	// Colors (0 = theme)
	track_color Color = Color{0, 0, 0, 0}
	fill_color  Color = Color{0, 0, 0, 0}
	thumb_color Color = Color{0, 0, 0, 0}
	tick_color  Color = Color{0, 0, 0, 0} // NEW
	// Callback
	on_change fn (f32) = unsafe { nil }
	// Вызывается один раз при отпускании кнопки мыши после перетаскивания —
	// для дорогих пересчётов, которые нельзя запускать на каждый on_change.
	on_release fn (f32) = unsafe { nil }
}

// ─── Constructors ──────────────────────────────────────

pub fn slider() &Slider {
	return &Slider{}
}

pub fn slider_horizontal(min f32, max f32, value f32) &Slider {
	lo, hi := ordered_range_f32(min, max)
	return &Slider{
		dir:   .horizontal
		min:   lo
		max:   hi
		value: clamp_f32(value, lo, hi)
	}
}

pub fn slider_vertical(min f32, max f32, value f32) &Slider {
	lo, hi := ordered_range_f32(min, max)
	return &Slider{
		dir:   .vertical
		min:   lo
		max:   hi
		value: clamp_f32(value, lo, hi)
	}
}

// ─── Public API ────────────────────────────────────────

pub fn (s &Slider) get_value() f32 {
	return s.value
}

pub fn (mut s Slider) set_value(v f32) {
	new_v := slider_snap(s.min, s.max, s.step, clamp_f32(v, s.min, s.max))
	if new_v != s.value {
		s.value = new_v
		if s.on_change != unsafe { nil } {
			s.on_change(s.value)
		}
	}
}

// min > max меняются местами — так же, как в Spinbox.set_range: у одинакового
// входа должен быть одинаковый результат.
pub fn (mut s Slider) set_range(min f32, max f32) {
	s.min, s.max = ordered_range_f32(min, max)
	s.value = clamp_f32(s.value, s.min, s.max)
}

// ─── Helpers ───────────────────────────────────────────

fn ordered_range_f32(a f32, b f32) (f32, f32) {
	return if a <= b { a, b } else { b, a }
}

fn slider_snap(min f32, max f32, step f32, v f32) f32 {
	if step <= 0 {
		return v
	}
	n := f32(int((v - min) / step + 0.5))
	return clamp_f32(min + n * step, min, max)
}

fn (s &Slider) normalized() f32 {
	if s.max <= s.min {
		return 0
	}
	return clamp_f32((s.value - s.min) / (s.max - s.min), 0, 1)
}

fn (s &Slider) label_text() string {
	return slider_format_value(s.value, s.value_format)
}

fn slider_format_value(v f32, fmt string) string {
	if fmt.len == 0 || fmt == '%d' {
		if v >= 0 {
			return '${int(v + 0.5)}'
		}
		return '${int(v - 0.5)}'
	}
	if fmt.starts_with('%.') && fmt.ends_with('f') {
		digits_str := fmt[2..fmt.len - 1]
		return slider_format_f32(v, digits_str.int())
	}
	return '${v}'
}

pub fn slider_format_f32(v f32, digits int) string {
	if digits <= 0 {
		if v >= 0 {
			return '${int(v + 0.5)}'
		}
		return '${int(v - 0.5)}'
	}
	mut mult := f32(1)
	for _ in 0 .. digits {
		mult *= 10
	}
	rounded := f32(int(v * mult + if v >= 0 { f32(0.5) } else { f32(-0.5) })) / mult
	mut s := '${rounded}'
	dot := s.index('.') or { -1 }
	if dot < 0 {
		s = s + '.'
		for _ in 0 .. digits {
			s = s + '0'
		}
	} else {
		frac_len := s.len - dot - 1
		if frac_len > digits {
			s = s[..dot + digits + 1]
		} else if frac_len < digits {
			for _ in 0 .. digits - frac_len {
				s = s + '0'
			}
		}
	}
	return s
}

fn (s &Slider) value_label_width(ctx &RenderContext) f32 {
	if !s.show_value {
		return 0
	}
	font := ctx.get_font_immut(.regular, 0)
	s1 := slider_format_value(s.max, s.value_format)
	s2 := slider_format_value(s.min, s.value_format)
	w1 := ctx.measure_text_with_font(s1, font).x
	w2 := ctx.measure_text_with_font(s2, font).x
	return max_f32(w1, w2) + s.value_gap
}

fn (s &Slider) track_rect(ctx &RenderContext) Rect {
	label_w := s.value_label_width(ctx)
	match s.dir {
		.horizontal {
			avail_w := s.bounds.w - label_w
			ty := s.bounds.y + (s.bounds.h - s.track_thickness) * 0.5
			tx := s.bounds.x + s.thumb_size * 0.5
			tw := max_f32(avail_w - s.thumb_size, 0)
			return Rect{tx, ty, tw, s.track_thickness}
		}
		.vertical {
			font := ctx.get_font_immut(.regular, 0)
			label_h := if s.show_value { ctx.font_height_of(font) + 4 } else { f32(0) }
			avail_h := s.bounds.h - label_h
			tx := s.bounds.x + (s.bounds.w - s.track_thickness) * 0.5
			ty := s.bounds.y + s.thumb_size * 0.5
			th := max_f32(avail_h - s.thumb_size, 0)
			return Rect{tx, ty, s.track_thickness, th}
		}
	}
}

fn (s &Slider) thumb_center(ctx &RenderContext) (f32, f32) {
	trk := s.track_rect(ctx)
	norm := s.normalized()
	match s.dir {
		.horizontal {
			return trk.x + norm * trk.w, trk.y + trk.h * 0.5
		}
		.vertical {
			// min at bottom, max at top
			return trk.x + trk.w * 0.5, trk.y + (1.0 - norm) * trk.h
		}
	}
}

fn (s &Slider) hit_rect(ctx &RenderContext) Rect {
	trk := s.track_rect(ctx)
	expand := s.thumb_size * 0.5 + 2
	match s.dir {
		.horizontal {
			return Rect{trk.x - expand, s.bounds.y, trk.w + expand * 2, s.bounds.h}
		}
		.vertical {
			return Rect{s.bounds.x, trk.y - expand, s.bounds.w, trk.h + expand * 2}
		}
	}
}

fn (s &Slider) value_from_pos(mx f32, my f32, ctx &RenderContext) f32 {
	trk := s.track_rect(ctx)
	match s.dir {
		.horizontal {
			if trk.w <= 0 {
				return s.min
			}
			norm := clamp_f32((mx - trk.x) / trk.w, 0, 1)
			return slider_snap(s.min, s.max, s.step, s.min + norm * (s.max - s.min))
		}
		.vertical {
			if trk.h <= 0 {
				return s.min
			}
			norm := clamp_f32(1.0 - (my - trk.y) / trk.h, 0, 1)
			return slider_snap(s.min, s.max, s.step, s.min + norm * (s.max - s.min))
		}
	}
}

// ─── Colors ────────────────────────────────────────────

fn (s &Slider) eff_track_color(ctx &RenderContext) Color {
	if s.track_color.a > 0 {
		return s.track_color
	}
	return ctx.theme.eff_slider_track()
}

fn (s &Slider) eff_fill_color(ctx &RenderContext) Color {
	if s.fill_color.a > 0 {
		return s.fill_color
	}
	return ctx.theme.eff_slider_fill()
}

fn (s &Slider) eff_thumb_color(ctx &RenderContext) Color {
	if s.thumb_color.a > 0 {
		return s.thumb_color
	}
	return ctx.theme.eff_slider_thumb()
}

fn (s &Slider) eff_tick_color(ctx &RenderContext) Color {
	if s.tick_color.a > 0 {
		return s.tick_color
	}
	return ctx.theme.eff_slider_tick().with_alpha(140)
}

// ─── Tick marks ────────────────────────────────────────

fn (s &Slider) draw_ticks(trk Rect, mut ctx RenderContext) {
	if !s.show_ticks || s.step <= 0 {
		return
	}
	range := s.max - s.min
	if range <= 0 {
		return
	}
	count := int(range / s.step + 0.5)
	if count <= 0 || count > 200 {
		return
	}
	// sanity
	tc := s.eff_tick_color(ctx)
	ts := s.tick_size
	match s.dir {
		.horizontal {
			y1 := trk.y + trk.h + 2
			y2 := y1 + ts
			for i in 0 .. count + 1 {
				t := f32(i) / f32(count)
				x := trk.x + t * trk.w
				ctx.fill_rect(Rect{x - 0.5, y1, 1, y2 - y1}, tc)
			}
		}
		.vertical {
			x1 := trk.x + trk.w + 2
			x2 := x1 + ts
			for i in 0 .. count + 1 {
				t := f32(i) / f32(count)
				y := trk.y + (1.0 - t) * trk.h
				ctx.fill_rect(Rect{x1, y - 0.5, x2 - x1, 1}, tc)
			}
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut s Slider) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if !ctx.is_in_clip(s.bounds) {
		return
	}

	if s.enabled {
		ctx.focus.register_slider(&s, s.focus_group)
	}

	target_hover := if s.hovered && s.enabled { f32(1.0) } else { f32(0.0) }
	target_focus := if s.focused && s.enabled { f32(1.0) } else { f32(0.0) }
	mut animating := s.hover_anim.update(target_hover, ctx)
	animating = s.focus_anim.update(target_focus, ctx) || animating
	// mark_anim_rect — см. button.v; ручка и дорожка не выходят за bounds.
	if animating {
		ctx.mark_anim_rect('slider', s.bounds)
	}

	trk := s.track_rect(ctx)
	track_rad := s.track_thickness * 0.5

	track_c := s.eff_track_color(ctx)
	fill_c := s.eff_fill_color(ctx)
	thumb_c := s.eff_thumb_color(ctx)

	// Background track (always drawn — both for horizontal & vertical)
	bg_c := if s.enabled { track_c } else { track_c.darken(0.1) }
	if trk.w >= 2 && trk.h >= 2 {
		if min_f32(trk.w, trk.h) <= track_rad * 2 {
			ctx.fill_pill_rect(trk, bg_c, track_rad)
		} else {
			ctx.fill_rounded_rect(trk, bg_c, track_rad)
		}
	}

	// Filled portion (optional)
	cx, cy := s.thumb_center(ctx)
	if s.show_fill {
		match s.dir {
			.horizontal {
				fill_w := cx - trk.x
				if fill_w > 0.5 {
					fc := if s.enabled { fill_c } else { fill_c.darken(0.2) }
					fill_r := Rect{trk.x, trk.y, fill_w, trk.h}
					if min_f32(fill_r.w, fill_r.h) <= track_rad * 2 {
						ctx.fill_pill_rect(fill_r, fc, track_rad)
					} else {
						ctx.fill_rounded_rect(fill_r, fc, track_rad)
					}
				}
			}
			.vertical {
				fill_top := cy
				fill_h := trk.y + trk.h - fill_top
				if fill_h > 0.5 {
					fc := if s.enabled { fill_c } else { fill_c.darken(0.2) }
					fill_r := Rect{trk.x, fill_top, trk.w, fill_h}
					if min_f32(fill_r.w, fill_r.h) <= track_rad * 2 {
						ctx.fill_pill_rect(fill_r, fc, track_rad)
					} else {
						ctx.fill_rounded_rect(fill_r, fc, track_rad)
					}
				}
			}
		}
	}

	// Tick marks
	s.draw_ticks(trk, mut ctx)

	// Thumb halo (hover/focus)
	thumb_radius := s.thumb_size * 0.5
	halo_strength := max_f32(s.hover_anim.value, s.focus_anim.value)
	if halo_strength > 0.05 && s.enabled {
		halo_r := thumb_radius + 4 + halo_strength * 2
		halo_a := u8(60.0 * halo_strength)
		ctx.fill_circle(cx, cy, halo_r, thumb_c.with_alpha(halo_a))
	}

	// Thumb body
	tc := if !s.enabled {
		thumb_c.darken(0.25)
	} else if s.dragging {
		thumb_c.darken(0.1)
	} else if s.hovered {
		thumb_c.brighten(0.1)
	} else {
		thumb_c
	}
	ctx.fill_circle(cx, cy, thumb_radius, tc)
	ctx.draw_circle(cx, cy, thumb_radius, ctx.theme.surface)

	// Focus ring
	if s.focus_anim.value > 0.05 {
		fc := ctx.theme.eff_focus_ring_color().with_alpha(u8(200.0 * s.focus_anim.value))
		ctx.draw_circle(cx, cy, thumb_radius + 2, fc)
	}

	// Value label
	if s.show_value {
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		lbl := s.label_text()
		lw := ctx.measure_text_with_font(lbl, font).x
		lc := if s.enabled { ctx.theme.text_primary } else { ctx.theme.text_disabled }

		match s.dir {
			.horizontal {
				lx := s.bounds.x + s.bounds.w - lw
				ly := s.bounds.y + (s.bounds.h - fh) * 0.5
				ctx.draw_text_with_font(lbl, lx, ly, lc, font)
			}
			.vertical {
				lx := s.bounds.x + (s.bounds.w - lw) * 0.5
				ly := s.bounds.y + s.bounds.h - fh
				ctx.draw_text_with_font(lbl, lx, ly, lc, font)
			}
		}
	}
}

// ─── Events ────────────────────────────────────────────

pub fn (mut s Slider) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible || !s.enabled {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	if s.dragging {
		match event.typ {
			.mouse_move {
				if unsafe { ctx_ptr != nil } {
					new_v := s.value_from_pos(event.mouse_x, event.mouse_y, ctx_ptr)
					if new_v != s.value {
						s.value = new_v
						if s.on_change != unsafe { nil } {
							s.on_change(s.value)
						}
					}
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					s.dragging = false
					if s.on_release != unsafe { nil } {
						s.on_release(s.value)
					}
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			s.hovered = s.bounds.contains(event.mouse_x, event.mouse_y)
		}
		.mouse_down {
			if event.mouse_btn == .left && unsafe { ctx_ptr != nil } {
				hit := s.hit_rect(ctx_ptr)
				if hit.contains(event.mouse_x, event.mouse_y) {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_slider(&s, s.focus_group)
					s.focused = true
					s.dragging = true
					new_v := s.value_from_pos(event.mouse_x, event.mouse_y, ctx_ptr)
					if new_v != s.value {
						s.value = new_v
						if s.on_change != unsafe { nil } {
							s.on_change(s.value)
						}
					}
					return true
				}
				if s.focused && !s.bounds.contains(event.mouse_x, event.mouse_y) {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.blur_current()
					s.focused = false
				}
			}
		}
		.mouse_wheel {
			if !s.wheel {
				return false
			}
			if !s.hovered {
				return false
			}
			delta := event.wheel_y
			step := if s.step > 0 { s.step } else { (s.max - s.min) * 0.01 }
			s.set_value(s.value + delta * step)
			return true
		}
		.key_down {
			if !s.focused {
				return false
			}
			step := if s.step > 0 { s.step } else { (s.max - s.min) * 0.01 }
			big := if s.big_step > 0 { s.big_step } else { (s.max - s.min) * 0.1 }

			match event.keycode {
				sdl_k_left, sdl_k_down {
					s.set_value(s.value - step)
					return true
				}
				sdl_k_right, sdl_k_up {
					s.set_value(s.value + step)
					return true
				}
				else {}
			}

			if is_home_key(event.keycode, event.scancode) {
				s.set_value(s.min)
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				s.set_value(s.max)
				return true
			}
			if tv_is_pageup_key(event.keycode, event.scancode) {
				s.set_value(s.value + big)
				return true
			}
			if tv_is_pagedown_key(event.keycode, event.scancode) {
				s.set_value(s.value - big)
				return true
			}

			if event.keycode == sdl_k_tab {
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.tab(event.shift())
				}
				return true
			}
			if event.keycode == sdl_k_escape {
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.blur_current()
				}
				return true
			}
		}
		else {}
	}

	return false
}
