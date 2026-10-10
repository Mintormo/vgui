module vgui

// ═══════════════════════════════════════════════════════
// Label — text display widget
// ═══════════════════════════════════════════════════════

pub enum TextAlign {
	left
	center
	right
}

pub enum VAlign {
	top
	middle
	bottom
}

pub enum FontStyle {
	regular
	bold
	italic
	bold_italic
	mono
	mono_bold
}

pub struct Label {
pub mut:
	type_tag   int = kind_label // тег типа, см. widget_tag.v
	bounds     Rect
	text       string
	color      Color     = Color{0, 0, 0, 0}
	align      TextAlign = .left
	valign     VAlign    = .top
	font_style FontStyle = .regular
	font_size  int
	visible    bool = true
	wrap       bool
	clip       bool
	pad        f32 = 4
	line_gap   f32 = 2
}

// ───────────── Конструкторы ────────────────────────────

pub fn label(text string) &Label {
	return &Label{
		text: text
	}
}

// For use inside containers, with wrap
pub fn label_wrap(text string) &Label {
	return &Label{
		text: text
		wrap: true
		clip: true
	}
}

// ───────────── Отрисовка ───────────────────────────────

pub fn (mut l Label) draw(mut ctx RenderContext) {
	if !l.visible || l.text.len == 0 {
		return
	}
	if !ctx.is_in_clip(l.bounds) {
		return
	}

	color := if l.color.a > 0 { l.color } else { ctx.theme.text_primary }
	has_rect := l.bounds.w > 0 && l.bounds.h > 0

	if has_rect {
		l.draw_in_rect(mut ctx, color)
	} else {
		l.draw_auto(mut ctx, color)
	}
}

fn (mut l Label) draw_auto(mut ctx RenderContext, color Color) {
	font := ctx.get_font(l.font_style, l.font_size)
	sz := ctx.measure_text_with_font(l.text, font)
	l.bounds.w = sz.x
	l.bounds.h = sz.y

	x := match l.align {
		.left { l.bounds.x }
		.center { l.bounds.x - sz.x / 2.0 }
		.right { l.bounds.x - sz.x }
	}

	ctx.draw_text_with_font(l.text, x, l.bounds.y, color, font)
}

fn (mut l Label) draw_in_rect(mut ctx RenderContext, color Color) {
	if l.clip {
		ctx.push_clip(l.bounds)
	}

	font := ctx.get_font(l.font_style, l.font_size)
	fh := ctx.font_height_of(font)
	line_step := fh + l.line_gap

	// Используем всю область bounds для размещения текста (без shrink для расчёта позиции)
	// pad применяется только как отступ от краёв для wrap-ширины
	wrap_w := l.bounds.w - l.pad * 2.0
	lines := l.wrap_lines(ctx, font, wrap_w)

	total_h := if lines.len > 0 {
		f32(lines.len) * line_step - l.line_gap
	} else {
		f32(0)
	}

	// Вертикальное выравнивание внутри всего bounds
	mut y := match l.valign {
		.top { l.bounds.y + l.pad }
		.middle { l.bounds.y + (l.bounds.h - total_h) / 2.0 }
		.bottom { l.bounds.y + l.bounds.h - total_h - l.pad }
	}

	content_x := l.bounds.x + l.pad

	for line in lines {
		// Рисуем строку, если она хотя бы частично видна
		if y + fh < l.bounds.y {
			y += line_step
			continue
		}
		if y > l.bounds.y + l.bounds.h {
			break
		}

		if line.len > 0 {
			lw := ctx.measure_text_with_font(line, font).x
			x := match l.align {
				.left { content_x }
				.center { l.bounds.x + (l.bounds.w - lw) / 2.0 }
				.right { l.bounds.x + l.bounds.w - l.pad - lw }
			}

			ctx.draw_text_with_font(line, x, y, color, font)
		}

		y += line_step
	}

	if l.clip {
		ctx.pop_clip()
	}
}

// ───────────── Word-wrap ───────────────────────────────

fn (l &Label) wrap_lines(ctx &RenderContext, font voidptr, max_w f32) []string {
	paragraphs := l.text.split('\n')
	mut result := []string{cap: paragraphs.len * 2}

	if !l.wrap || max_w <= 0 {
		for p in paragraphs {
			result << p
		}
		return result
	}

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

// ───────────── События ─────────────────────────────────

pub fn (mut l Label) handle_event(event &GuiEvent, app &App) bool {
	return false
}
