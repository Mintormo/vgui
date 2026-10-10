module vgui

import math

pub enum SpinnerStyle {
	arc
	dots
	dual
}

pub struct Spinner {
pub mut:
	type_tag  int = kind_spinner // тег типа, см. widget_tag.v
	bounds    Rect
	visible   bool         = true
	spinning  bool         = true
	style     SpinnerStyle = .arc
	color     Color        = Color{0, 0, 0, 0}
	bg_color  Color        = Color{0, 0, 0, 0}
	size      f32
	thickness f32 = 3
	speed     f32 = 1.0
	text      string
	text_gap  f32 = 4
	dot_count int = 8
	dot_size  f32 = 3
}

pub fn spinner() &Spinner {
	return &Spinner{}
}

pub fn spinner_with_text(text string) &Spinner {
	return &Spinner{
		text: text
	}
}

pub fn (mut s Spinner) start() {
	s.spinning = true
}

pub fn (mut s Spinner) stop() {
	s.spinning = false
}

pub fn (s &Spinner) is_spinning() bool {
	return s.spinning
}

fn (s &Spinner) eff_color(ctx &RenderContext) Color {
	if s.color.a > 0 {
		return s.color
	}
	return ctx.theme.eff_spin_color()
}

fn (s &Spinner) eff_bg_color(ctx &RenderContext) Color {
	if s.bg_color.a > 0 {
		return s.bg_color
	}
	return ctx.theme.eff_spin_bg().with_alpha(60)
}

fn (s &Spinner) spinner_geometry(ctx &RenderContext) (f32, f32, f32) {
	mut text_h := f32(0)
	if s.text.len > 0 {
		font := ctx.get_font_immut(.regular, 0)
		text_h = ctx.font_height_of(font) + s.text_gap
	}

	avail_h := s.bounds.h - text_h

	diameter := if s.size > 0 {
		s.size
	} else {
		min_f32(s.bounds.w, max_f32(avail_h, 4))
	}

	cx := s.bounds.x + s.bounds.w * 0.5
	cy := s.bounds.y + avail_h * 0.5

	return diameter, cx, cy
}

fn spinner_angle(speed f32) f32 {
	ms := C.SDL_GetTicks()
	t := f32(ms) * 0.001 * speed
	return t * 6.2831853
}

pub fn (mut s Spinner) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	// Mark animation needed if spinner is actually visible and spinning.
	// mark_anim_rect (not a raw ctx.needs_animation = true write) so the
	// dirty tracker actually schedules s's rect for the NEXT frame.
	// Standing here, above the is_in_clip early-return, is cosmetic:
	// mark_anim_rect re-checks is_in_clip(s.bounds) itself, so the order
	// changes nothing. What keeps the animation from freezing when a partial
	// frame misses this widget is the bbox invariant documented at
	// mark_anim_rect in render_context.v.
	if s.spinning {
		ctx.mark_anim_rect('spinner', s.bounds)
	}

	if !ctx.is_in_clip(s.bounds) {
		return
	}

	if !s.spinning {
		s.draw_static(mut ctx)
		return
	}

	match s.style {
		.arc { s.draw_arc(mut ctx) }
		.dots { s.draw_dots(mut ctx) }
		.dual { s.draw_dual(mut ctx) }
	}

	if s.text.len > 0 {
		s.draw_label(mut ctx)
	}
}

fn (s &Spinner) draw_arc(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed)
	c := s.eff_color(ctx)
	bg := s.eff_bg_color(ctx)

	// Background: full circle using SDL2_gfx aacircle
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)
	// Foreground: spinning arc (~270°)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle, angle + 4.712, c)
}

fn (s &Spinner) draw_dual(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed)
	c := s.eff_color(ctx)
	bg := s.eff_bg_color(ctx)

	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle, angle + 2.094, c)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, angle + 3.1416, angle + 3.1416 +
		2.094, c)
}

fn (s &Spinner) draw_dots(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.dot_size * 2) * 0.5
	if radius < 1 {
		return
	}

	angle := spinner_angle(s.speed * 0.5)
	c := s.eff_color(ctx)
	count := max_int(3, s.dot_count)

	for i in 0 .. count {
		t := f32(i) / f32(count)
		a := angle + t * 6.2831853
		dx := cx + radius * math.cosf(a)
		dy := cy + radius * math.sinf(a)

		fade := f32(count - i) / f32(count)
		alpha := u8(fade * fade * f32(c.a))
		dot_c := Color{c.r, c.g, c.b, alpha}
		dot_r := s.dot_size * (0.5 + fade * 0.5)

		ctx.fill_circle(dx, dy, dot_r, dot_c)
	}
}

fn (s &Spinner) draw_static(mut ctx RenderContext) {
	diameter, cx, cy := s.spinner_geometry(ctx)
	radius := (diameter - s.thickness * 2) * 0.5
	if radius < 1 {
		return
	}

	bg := s.eff_bg_color(ctx)
	spinner_draw_circle_arc(mut ctx, cx, cy, radius, s.thickness, 0, 6.2831853, bg)

	if s.text.len > 0 {
		s.draw_label(mut ctx)
	}
}

fn (s &Spinner) draw_label(mut ctx RenderContext) {
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	tw := ctx.measure_text_with_font(s.text, font).x

	tc := if s.color.a > 0 { s.color } else { ctx.theme.text_secondary }

	tx := s.bounds.x + (s.bounds.w - tw) * 0.5
	ty := s.bounds.y + s.bounds.h - fh
	ctx.draw_text_with_font(s.text, tx, ty, tc, font)
}

fn spinner_draw_circle_arc(mut ctx RenderContext, cx f32, cy f32, radius f32, thickness f32, start f32, end f32, c Color) {
	if c.a == 0 || radius < 1 {
		return
	}

	arc_span := end - start
	if arc_span <= 0 {
		return
	}

	half_t := thickness * 0.5
	r_inner := max_f32(0.5, radius - half_t)
	r_outer := radius + half_t

	arc_len_px := r_outer * abs_f32(arc_span)
	segments := max_int(48, int(arc_len_px * 1.2))
	step := arc_span / f32(segments)

	fc := C.SDL_FColor{
		r: f32(c.r) / 255.0
		g: f32(c.g) / 255.0
		b: f32(c.b) / 255.0
		a: f32(c.a) / 255.0
	}

	// Match the convention every render_* primitive in sdl3_render.v follows:
	// set the blend mode explicitly rather than relying on whatever the
	// renderer was last left in. This matters especially for this widget's
	// own semi-transparent background ring (alpha 60, drawn via this same
	// function) — with blend mode "none" left over from elsewhere it would
	// be written verbatim instead of composited.
	C.SDL_SetRenderDrawBlendMode(ctx.renderer, sdl_blendmode_blend)

	mut verts := []C.SDL_Vertex{cap: segments * 6}

	mut a0 := start
	mut ix0 := cx + r_inner * math.cosf(a0)
	mut iy0 := cy + r_inner * math.sinf(a0)
	mut ox0 := cx + r_outer * math.cosf(a0)
	mut oy0 := cy + r_outer * math.sinf(a0)

	z := C.SDL_FPoint{0, 0}
	for i in 1 .. segments + 1 {
		a1 := start + f32(i) * step
		ix1 := cx + r_inner * math.cosf(a1)
		iy1 := cy + r_inner * math.sinf(a1)
		ox1 := cx + r_outer * math.cosf(a1)
		oy1 := cy + r_outer * math.sinf(a1)

		// Trapezoid = 2 triangles: (ix0,iy0),(ox0,oy0),(ox1,oy1) and (ix0,iy0),(ox1,oy1),(ix1,iy1)
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ix0, iy0}
			color:     fc
			tex_coord: z
		}
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ox0, oy0}
			color:     fc
			tex_coord: z
		}
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ox1, oy1}
			color:     fc
			tex_coord: z
		}
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ix0, iy0}
			color:     fc
			tex_coord: z
		}
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ox1, oy1}
			color:     fc
			tex_coord: z
		}
		verts << C.SDL_Vertex{
			position:  C.SDL_FPoint{ix1, iy1}
			color:     fc
			tex_coord: z
		}

		ix0 = ix1
		iy0 = iy1
		ox0 = ox1
		oy0 = oy1
	}

	C.SDL_RenderGeometry(ctx.renderer, unsafe { nil }, verts.data, verts.len, unsafe { nil }, 0)
}

pub fn (mut s Spinner) handle_event(event &GuiEvent, app &App) bool {
	return false
}
