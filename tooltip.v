module vgui

const tt_default_delay = u32(600)
const tt_pad = f32(6)
const tt_max_w = f32(280)
const tt_offset_y = f32(16) // below cursor
const tt_offset_x = f32(4) // slight right offset from cursor

@[heap]
pub struct Tooltip {
pub mut:
	type_tag     int = kind_tooltip // тег типа, см. widget_tag.v
	text         string
	visible      bool    = true
	delay_ms     u32     = tt_default_delay
	bg           Color   = Color{0, 0, 0, 0}
	text_color   Color   = Color{0, 0, 0, 0}
	border       Color   = Color{0, 0, 0, 0}
	max_width    f32     = tt_max_w
	wrap         bool    = true
	target       &Widget = unsafe { nil }
	showing      bool
	hover_start  u64
	target_hover bool
	bounds       Rect
}

pub fn tooltip(text string) &Tooltip {
	return &Tooltip{
		text: text
	}
}

pub fn tooltip_delayed(text string, delay_ms u32) &Tooltip {
	return &Tooltip{
		text:     text
		delay_ms: delay_ms
	}
}

pub fn (mut t Tooltip) attach(target &Widget) {
	t.target = unsafe { target }
}

pub fn (mut t Tooltip) set_text(text string) {
	t.text = text
}

pub fn (t &Tooltip) is_showing() bool {
	return t.showing
}

// Раньше это был ручной if-is по типам (Button/Label/TextInput/...),
// со старым неполным списком: Icon/Canvas/TableView/CodeEditor/
// TextArea/GridLayout/Accordion и другие типы, добавленные позже,
// в него не попадали, и tooltip.attach(icon) молча получал Rect{} —
// подсказка просто никогда не показывалась (нулевой bounds наружу
// трактуется как "не показывать", см. tooltip_should_show). Теперь
// схлопнуто в get_widget_bounds (widget_tree.v) — единственный
// источник правды для bounds любого Widget-типа.
fn tooltip_get_target_bounds(t &Tooltip) Rect {
	if unsafe { t.target == nil } {
		return Rect{}
	}
	return get_widget_bounds(t.target)
}

fn tooltip_measure(t &Tooltip, ctx &RenderContext) (f32, f32) {
	if t.text.len == 0 {
		return f32(0), f32(0)
	}
	font := ctx.get_font_immut(.regular, 0)
	fh := ctx.font_height_of(font)
	if !t.wrap {
		sz := ctx.measure_text_with_font(t.text, font)
		return sz.x + tt_pad * 2, fh + tt_pad * 2
	}
	wrap_w := t.max_width - tt_pad * 2
	lines := tooltip_wrap(t.text, ctx, font, wrap_w)
	line_gap := f32(2)
	total_h := f32(lines.len) * (fh + line_gap) - line_gap + tt_pad * 2
	mut max_lw := f32(0)
	for line in lines {
		lw := ctx.measure_text_with_font(line, font).x
		if lw > max_lw {
			max_lw = lw
		}
	}
	return max_lw + tt_pad * 2, total_h
}

fn tooltip_wrap(text string, ctx &RenderContext, font voidptr, max_w f32) []string {
	paragraphs := text.split('\n')
	mut result := []string{cap: paragraphs.len * 2}
	for p in paragraphs {
		if p.len == 0 {
			result << ''
			continue
		}
		words := p.split(' ')
		mut line := ''
		for word in words {
			test := if line.len == 0 { word } else { '${line} ${word}' }
			tw := ctx.measure_text_with_font(test, font).x
			if tw > max_w && line.len > 0 {
				result << line
				line = word
			} else {
				line = test
			}
		}
		if line.len > 0 {
			result << line
		}
	}
	return result
}

fn tooltip_draw(t &Tooltip, mut ctx RenderContext) {
	if !t.showing || t.text.len == 0 {
		return
	}

	tw, th := tooltip_measure(t, ctx)
	if tw <= 0 {
		return
	}

	// Position near mouse cursor
	mut tx := ctx.mouse_x + tt_offset_x
	mut ty := ctx.mouse_y + tt_offset_y

	if ty + th > ctx.screen_height - 2 {
		ty = ctx.mouse_y - th - 4
	}
	if tx + tw > ctx.screen_width - 2 {
		tx = ctx.screen_width - tw - 2
	}
	if tx < 2 {
		tx = 2
	}
	if ty < 2 {
		ty = 2
	}

	popup := Rect{tx, ty, tw, th}

	bg := if t.bg.a > 0 { t.bg } else { ctx.theme.eff_tooltip_bg() }
	bc := if t.border.a > 0 { t.border } else { ctx.theme.eff_tooltip_border() }
	tc := if t.text_color.a > 0 { t.text_color } else { ctx.theme.eff_tooltip_text() }
	rad := max_f32(ctx.theme.border_radius * 0.5, 3)

	if ctx.theme.shadow_offset > 0 {
		ctx.draw_shadow(popup, rad)
	}
	ctx.fill_rounded_rect(popup, bg, rad)
	ctx.draw_rounded_rect(popup, bc, rad)

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	line_gap := f32(2)

	if !t.wrap {
		text_y := popup.y + (popup.h - fh) * 0.5
		ctx.draw_text_with_font(t.text, popup.x + tt_pad, text_y, tc, font)
	} else {
		wrap_w := t.max_width - tt_pad * 2
		lines := tooltip_wrap(t.text, ctx, font, wrap_w)
		mut y := popup.y + tt_pad
		for line in lines {
			if line.len > 0 {
				ctx.draw_text_with_font(line, popup.x + tt_pad, y, tc, font)
			}
			y += fh + line_gap
		}
	}
}

pub fn (mut t Tooltip) draw(mut ctx RenderContext) {
	if !t.visible || t.text.len == 0 || unsafe { t.target == nil } {
		t.showing = false
		return
	}

	// Animation flag — only when waiting for delay timer
	if t.target_hover && !t.showing && t.hover_start > 0 {
		ctx.mark_anim('tooltip')
	}

	// Check delay every frame
	if t.target_hover && !t.showing && t.hover_start > 0 {
		elapsed := C.SDL_GetTicks() - t.hover_start
		if elapsed >= t.delay_ms {
			t.showing = true
		}
	}

	// Fallback: check mouse position from ctx
	if !t.target_hover {
		target_r := tooltip_get_target_bounds(t)
		if target_r.w > 0 && target_r.contains(ctx.mouse_x, ctx.mouse_y) {
			t.target_hover = true
			if t.hover_start == 0 {
				t.hover_start = C.SDL_GetTicks()
			}
		}
	}

	// Also hide if mouse left target (check each frame)
	if t.target_hover {
		target_r := tooltip_get_target_bounds(t)
		if target_r.w > 0 && !target_r.contains(ctx.mouse_x, ctx.mouse_y) {
			t.target_hover = false
			t.showing = false
			t.hover_start = 0
		}
	}

	if t.showing {
		ctx.pending_tooltips << unsafe { t }
	}
}

pub fn (mut t Tooltip) handle_event(event &GuiEvent, app &App) bool {
	if !t.visible || t.text.len == 0 || unsafe { t.target == nil } {
		t.showing = false
		t.target_hover = false
		return false
	}

	match event.typ {
		.mouse_move {
			target_r := tooltip_get_target_bounds(t)
			was_hover := t.target_hover
			t.target_hover = target_r.contains(event.mouse_x, event.mouse_y)

			if t.target_hover && !was_hover {
				t.hover_start = C.SDL_GetTicks()
				t.showing = false
			} else if !t.target_hover {
				t.showing = false
				t.hover_start = 0
			}

			if t.target_hover && !t.showing && t.hover_start > 0 {
				elapsed := C.SDL_GetTicks() - t.hover_start
				if elapsed >= t.delay_ms {
					t.showing = true
				}
			}
		}
		.mouse_down, .mouse_wheel, .key_down {
			if t.showing {
				t.showing = false
			}
			t.target_hover = false
			t.hover_start = 0
		}
		else {}
	}

	return false
}
