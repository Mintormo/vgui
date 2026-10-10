module vgui

@[heap]
pub struct ToggleSwitch {
pub mut:
	type_tag    int = kind_toggle_switch // тег типа, см. widget_tag.v
	bounds      Rect
	text        string
	on          bool
	visible     bool = true
	enabled     bool = true
	hovered     bool
	focus_anim  Anim = Anim{
		tau_ms:  anim_tau_focus
		epsilon: 0.02
	}
	slide_anim  Anim = Anim{
		tau_ms:  anim_tau_hover
		epsilon: 0.02
	}
	pressed     bool // левая кнопка нажата над виджетом; действие - по mouse_up
	focus_group int
	track_w     f32       = 40
	track_h     f32       = 22
	gap         f32       = 8
	on_change   fn (bool) = unsafe { nil }
}

pub fn toggle_switch(text string) &ToggleSwitch {
	return &ToggleSwitch{
		text: text
	}
}

pub fn (ts &ToggleSwitch) is_on() bool {
	return ts.on
}

pub fn (mut ts ToggleSwitch) set_on(v bool) {
	ts.on = v
}

pub fn (mut ts ToggleSwitch) toggle() {
	ts.on = !ts.on
	if ts.on_change != unsafe { nil } {
		ts.on_change(ts.on)
	}
}

fn (ts &ToggleSwitch) track_rect() Rect {
	ty := ts.bounds.y + (ts.bounds.h - ts.track_h) * 0.5
	// Inset by 1px so the outer border contour doesn't get clipped by the container.
	return Rect{ts.bounds.x + 1, ty, ts.track_w, ts.track_h}
}

pub fn (mut ts ToggleSwitch) draw(mut ctx RenderContext) {
	if !ts.visible {
		return
	}
	if !ctx.is_in_clip(ts.bounds) {
		return
	}

	if ts.enabled {
		ctx.focus.register_toggle_switch(&ts, ts.focus_group)
	}

	is_focused := ctx.focus.is_focused(unsafe { &ts })
	target_focus := if is_focused && ts.enabled { f32(1.0) } else { f32(0.0) }
	mut animating := ts.focus_anim.update(target_focus, ctx)

	target_slide := if ts.on { f32(1.0) } else { f32(0.0) }
	animating = ts.slide_anim.update(target_slide, ctx) || animating

	// Mark animation only when not yet settled (о mark_anim_rect — см. button.v)
	if animating {
		ctx.mark_anim_rect('toggle', ts.bounds)
	}

	trk := ts.track_rect()
	track_rad := trk.h * 0.5

	off_c := if ts.enabled {
		ctx.theme.eff_tog_track_off().blend(ctx.theme.button_hover, if ts.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	} else {
		ctx.theme.button_disabled_bg
	}
	on_c := if ts.enabled {
		ctx.theme.eff_tog_track_on().blend(ctx.theme.accent_hover, if ts.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	} else {
		ctx.theme.eff_tog_track_on().darken(0.2)
	}
	track_c := off_c.blend(on_c, ts.slide_anim.value)
	ctx.fill_rounded_rect(trk, track_c, track_rad)

	tbc := if ts.slide_anim.value > 0.5 {
		ctx.theme.eff_tog_track_on().darken(0.1)
	} else {
		ctx.theme.eff_tog_track_off()
	}
	ctx.draw_rounded_rect(trk, tbc, track_rad)

	// expanded(4) so the inset ring lands at the original expanded(2) geometry around the pill
	ctx.draw_focus_ring(trk.expanded(4), track_rad + 4, ts.focus_anim.value)

	thumb_pad := f32(2)
	thumb_r := (trk.h - thumb_pad * 2) * 0.5
	thumb_min_x := trk.x + thumb_pad + thumb_r
	thumb_max_x := trk.x + trk.w - thumb_pad - thumb_r
	thumb_cx := lerp(thumb_min_x, thumb_max_x, ts.slide_anim.value)
	thumb_cy := trk.y + trk.h * 0.5
	thumb_c := if ts.enabled { ctx.theme.eff_tog_thumb() } else { ctx.theme.text_disabled }
	ctx.fill_circle(thumb_cx, thumb_cy, thumb_r, thumb_c)

	if ts.text.len > 0 {
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		tx := trk.x + trk.w + ts.gap
		ty := ts.bounds.y + (ts.bounds.h - fh) * 0.5
		tc := if ts.enabled { ctx.theme.text_primary } else { ctx.theme.text_disabled }
		ctx.push_clip(ts.bounds)
		ctx.draw_text_with_font(ts.text, tx, ty, tc, font)
		ctx.pop_clip()
	}
}

pub fn (mut ts ToggleSwitch) handle_event(event &GuiEvent, app &App) bool {
	if !ts.visible || !ts.enabled {
		return false
	}

	match event.typ {
		.mouse_move {
			ts.hovered = ts.bounds.contains(event.mouse_x, event.mouse_y)
			if !ts.hovered {
				ts.pressed = false
			}
		}
		// Как у Button: нажатие только фокусирует, переключение - по
		// отпусканию над виджетом. Тяжёлый on_change не выполняется, пока
		// кнопка зажата, а увод курсора с виджета отменяет клик.
		.mouse_down {
			if event.mouse_btn == .left && ts.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_toggle_switch(&ts, ts.focus_group)
				}
				ts.pressed = true
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && ts.pressed {
				ts.pressed = false
				if ts.hovered {
					ts.toggle()
				}
				return true
			}
		}
		.key_down {
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				if ctx_mut.focus.is_focused(unsafe { &ts }) {
					if event.keycode == sdl_k_tab {
						ctx_mut.focus.tab(event.shift())
						return true
					}
					if event.keycode == sdl_k_space || event.keycode == sdl_k_return {
						ts.toggle()
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
