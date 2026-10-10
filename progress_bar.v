module vgui

import math

pub enum ProgressStyle {
	linear
	circular
}

pub struct ProgressBar {
pub mut:
	type_tag      int = kind_progress_bar // тег типа, см. widget_tag.v
	bounds        Rect
	value         f32
	visible       bool          = true
	style         ProgressStyle = .linear
	indeterminate bool
	// Appearance
	thickness     f32 = 8
	radius        f32 // circular: 0 → auto
	corner_radius f32 = -1 // linear: <0 → pill (bar_h/2), 0 → sharp, >0 → explicit
	show_text     bool
	text_format   string = '%.0f%%'
	text          string
	// Colors (0 = theme)
	bg_color   Color = Color{0, 0, 0, 0}
	fill_color Color = Color{0, 0, 0, 0}
	text_color Color = Color{0, 0, 0, 0}
	// Text color over the filled portion (0 = same as text_color). When set,
	// the label is drawn twice: text_color over the track and text_fill_color
	// clipped to the filled region — so it stays legible on both backgrounds.
	text_fill_color Color = Color{0, 0, 0, 0}
	// Animation
	anim_speed f32 = 1.0
}

// ─── Constructors ──────────────────────────────────────

pub fn progress_bar() &ProgressBar {
	return &ProgressBar{}
}

pub fn progress_bar_linear() &ProgressBar {
	return &ProgressBar{
		style: .linear
	}
}

pub fn progress_bar_sharp() &ProgressBar {
	return &ProgressBar{
		style:         .linear
		corner_radius: 0
	}
}

pub fn progress_circular() &ProgressBar {
	return &ProgressBar{
		style: .circular
	}
}

pub fn progress_indeterminate() &ProgressBar {
	return &ProgressBar{
		indeterminate: true
	}
}

// ─── Public API ────────────────────────────────────────

pub fn (p &ProgressBar) get_value() f32 {
	return p.value
}

pub fn (mut p ProgressBar) set_value(v f32) {
	p.value = clamp_f32(v, 0.0, 1.0)
}

pub fn (mut p ProgressBar) set_percent(pct f32) {
	p.value = clamp_f32(pct / 100.0, 0.0, 1.0)
}

pub fn (p &ProgressBar) get_percent() f32 {
	return p.value * 100.0
}

// ─── Helpers ───────────────────────────────────────────

fn (p &ProgressBar) eff_bg_color(ctx &RenderContext) Color {
	if p.bg_color.a > 0 {
		return p.bg_color
	}
	return ctx.theme.eff_prog_track()
}

fn (p &ProgressBar) eff_fill_color(ctx &RenderContext) Color {
	if p.fill_color.a > 0 {
		return p.fill_color
	}
	return ctx.theme.eff_prog_fill()
}

fn (p &ProgressBar) eff_text_color(ctx &RenderContext) Color {
	if p.text_color.a > 0 {
		return p.text_color
	}
	return ctx.theme.eff_prog_text()
}

fn (p &ProgressBar) eff_corner_radius(bar_h f32) f32 {
	if p.corner_radius < 0 {
		return bar_h * 0.5 // pill shape
	}
	return p.corner_radius
}

fn (p &ProgressBar) label_text() string {
	if p.text.len > 0 {
		return p.text
	}
	if p.indeterminate {
		return ''
	}
	return progress_format(p.value * 100.0, p.text_format)
}

fn progress_format(v f32, fmt string) string {
	if fmt.len == 0 {
		return '${int(v + 0.5)}%'
	}
	if fmt.contains('%.') && fmt.contains('f') {
		dot_idx := fmt.index('%.') or { -1 }
		f_idx := fmt.index_after('f', if dot_idx >= 0 { dot_idx } else { 0 }) or { -1 }
		if dot_idx >= 0 && f_idx > dot_idx + 2 {
			digits_str := fmt[dot_idx + 2..f_idx]
			digits := digits_str.int()
			num := slider_format_f32(v, digits)
			spec := '%.${digits_str}f'
			return fmt.replace(spec, num).replace('%%', '%')
		}
	}
	if fmt.contains('%d') {
		return fmt.replace('%d', '${int(v + 0.5)}').replace('%%', '%')
	}
	if fmt.contains('%f') {
		return fmt.replace('%f', slider_format_f32(v, 1)).replace('%%', '%')
	}
	return '${int(v + 0.5)}%'
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut p ProgressBar) draw(mut ctx RenderContext) {
	if !p.visible {
		return
	}
	// Mark animation needed if indeterminate and visible. mark_anim_rect (not
	// a raw ctx.needs_animation = true write) so the dirty tracker actually
	// schedules p's rect for the NEXT frame. Standing here, above the
	// is_in_clip early-return, is cosmetic: mark_anim_rect re-checks
	// is_in_clip(p.bounds) itself, so the order changes nothing. What keeps
	// the animation from freezing when a partial frame misses this widget is
	// the bbox invariant documented at mark_anim_rect in render_context.v.
	if p.indeterminate {
		ctx.mark_anim_rect('progressbar', p.bounds)
	}

	if !ctx.is_in_clip(p.bounds) {
		return
	}

	match p.style {
		.linear { p.draw_linear(mut ctx) }
		.circular { p.draw_circular(mut ctx) }
	}
}

// text_bar_h - толщина полосы: с текстом внутри - по строке текста
// (чуть выше неё, чтобы буквы помещались, но не толще: мелкий текст
// в толстой полосе некрасив), thickness тогда не действует
fn (p &ProgressBar) text_bar_h(ctx &RenderContext) f32 {
	if !p.show_text || p.indeterminate {
		return p.thickness
	}
	font := ctx.get_font_immut(.regular, 0)
	return ctx.font_height_of(font) + 4
}

fn (p &ProgressBar) draw_linear(mut ctx RenderContext) {
	mut bar_h := p.text_bar_h(ctx)
	if bar_h <= 0 || bar_h > p.bounds.h {
		bar_h = p.bounds.h
	}
	bar_y := p.bounds.y + (p.bounds.h - bar_h) * 0.5
	bar := Rect{p.bounds.x, bar_y, p.bounds.w, bar_h}
	rad := p.eff_corner_radius(bar_h)

	bg_c := p.eff_bg_color(ctx)
	fill_c := p.eff_fill_color(ctx)

	// Background — use pill composer (no middle seam)
	if rad > 0 {
		ctx.fill_pill_rect(bar, bg_c, rad)
	} else {
		ctx.fill_rect(bar, bg_c)
	}

	// Fill
	if p.indeterminate {
		ms := C.SDL_GetTicks()
		t := f32(ms) * 0.001 * p.anim_speed
		band_w := bar.w * 0.3
		period := f32(2.0)
		phase := (t - f32(int(t / period)) * period) / period
		start := -band_w + phase * (bar.w + band_w)
		mut bx := bar.x + start
		mut bw := band_w
		if bx < bar.x {
			bw -= (bar.x - bx)
			bx = bar.x
		}
		if bx + bw > bar.x + bar.w {
			bw = bar.x + bar.w - bx
		}
		if bw > 0 {
			ctx.push_clip(Rect{bx, bar.y, bw, bar.h})
			if rad > 0 {
				ctx.fill_pill_rect(bar, fill_c, rad)
			} else {
				ctx.fill_rect(bar, fill_c)
			}
			ctx.pop_clip()
		}
	} else {
		fill_w := bar.w * clamp_f32(p.value, 0, 1)
		if fill_w > 0.5 {
			ctx.push_clip(Rect{bar.x, bar.y, fill_w, bar.h})
			if rad > 0 {
				ctx.fill_pill_rect(bar, fill_c, rad)
			} else {
				ctx.fill_rect(bar, fill_c)
			}
			ctx.pop_clip()
		}
	}

	// Text
	if p.show_text && !p.indeterminate {
		lbl := p.label_text()
		if lbl.len > 0 {
			font := ctx.get_font(.regular, 0)
			sz := ctx.measure_text_with_font(lbl, font)
			tx := p.bounds.x + (p.bounds.w - sz.x) * 0.5
			ty := p.bounds.y + (p.bounds.h - sz.y) * 0.5
			ctx.draw_text_with_font(lbl, tx, ty, p.eff_text_color(ctx), font)
			// Redraw the part over the filled bar in a distinct color so the
			// label stays readable on both the track and the fill.
			if p.text_fill_color.a > 0 {
				fill_w := bar.w * clamp_f32(p.value, 0, 1)
				if fill_w > 0.5 {
					ctx.push_clip(Rect{bar.x, p.bounds.y, fill_w, p.bounds.h})
					ctx.draw_text_with_font(lbl, tx, ty, p.text_fill_color, font)
					ctx.pop_clip()
				}
			}
		}
	}
}

fn (p &ProgressBar) draw_circular(mut ctx RenderContext) {
	cx := p.bounds.x + p.bounds.w * 0.5
	cy := p.bounds.y + p.bounds.h * 0.5

	thick := if p.thickness > 0 { p.thickness } else { f32(8) }
	mut outer_r := if p.radius > 0 {
		p.radius
	} else {
		min_f32(p.bounds.w, p.bounds.h) * 0.5 - thick * 0.5 - 2
	}
	if outer_r < 2 {
		outer_r = 2
	}

	bg_c := p.eff_bg_color(ctx)
	fill_c := p.eff_fill_color(ctx)

	spinner_draw_circle_arc(mut ctx, cx, cy, outer_r, thick, 0, 6.2831853, bg_c)

	if p.indeterminate {
		ms := C.SDL_GetTicks()
		t := f32(ms) * 0.001 * p.anim_speed
		angle := t * 6.2831853
		arc_span := f32(1.8)
		spinner_draw_circle_arc(mut ctx, cx, cy, outer_r, thick, angle, angle + arc_span, fill_c)
	} else {
		val := clamp_f32(p.value, 0, 1)
		if val > 0.0001 {
			start := f32(-1.5707963)
			end := start + val * 6.2831853
			spinner_draw_circle_arc(mut ctx, cx, cy, outer_r, thick, start, end, fill_c)
		}
	}

	if p.show_text && !p.indeterminate {
		lbl := p.label_text()
		if lbl.len > 0 {
			font := ctx.get_font(.regular, 0)
			sz := ctx.measure_text_with_font(lbl, font)
			tx := cx - sz.x * 0.5
			ty := cy - sz.y * 0.5
			ctx.draw_text_with_font(lbl, tx, ty, p.eff_text_color(ctx), font)
		}
	}
	_ = math.cosf(0)
}

pub fn (mut p ProgressBar) handle_event(event &GuiEvent, app &App) bool {
	return false
}
