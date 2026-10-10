module vgui

// ═══════════════════════════════════════════════════════
// Separator — visual divider line widget
//
// A thin line used inside VBox/HBox to separate groups
// of widgets. Can be horizontal or vertical, with
// customizable thickness, color and margin (inset from
// edges).
//
// In a VBox the separator is horizontal (stretches width).
// In an HBox the separator is vertical (stretches height).
// Direction is auto-detected from bounds aspect ratio,
// or can be forced via `dir`.
//
// Usage (code):
//   v.add(vgui.separator())        // 1px high
//   v.add(vgui.hseparator())       // with margins
//   h.add(vgui.vseparator())
//
// Usage (YAML):
//   - type: separator
//     fixed: 1
//   - type: separator
//     fixed: 9
//     thickness: 1
//     margin: 4
//     color: "#3a3a3a"
// ═══════════════════════════════════════════════════════

pub enum SeparatorDir {
	auto       // detect from bounds: wider → horizontal, taller → vertical
	horizontal // ─── line
	vertical   // │ line
}

pub struct Separator {
pub mut:
	type_tag  int = kind_separator // тег типа, см. widget_tag.v
	bounds    Rect
	dir       SeparatorDir = .auto
	thickness f32          = 1
	color     Color        = Color{0, 0, 0, 0} // 0 = theme.border
	margin    f32 // inset from edges (both sides)
	visible   bool = true
}

// ─── Constructors ──────────────────────────────────────

// Generic separator (auto direction)
pub fn separator() &Separator {
	return &Separator{}
}

// Explicitly horizontal separator (for VBox)
pub fn hseparator() &Separator {
	return &Separator{
		dir: .horizontal
	}
}

// Explicitly vertical separator (for HBox)
pub fn vseparator() &Separator {
	return &Separator{
		dir: .vertical
	}
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut s Separator) draw(mut ctx RenderContext) {
	if !s.visible {
		return
	}
	if !ctx.is_in_clip(s.bounds) {
		return
	}

	c := if s.color.a > 0 { s.color } else { ctx.theme.eff_sep_color() }

	actual_dir := match s.dir {
		.horizontal {
			SeparatorDir.horizontal
		}
		.vertical {
			SeparatorDir.vertical
		}
		.auto {
			if s.bounds.w >= s.bounds.h {
				SeparatorDir.horizontal
			} else {
				SeparatorDir.vertical
			}
		}
	}

	match actual_dir {
		.horizontal, .auto {
			// Horizontal line centered vertically in bounds
			ly := s.bounds.y + (s.bounds.h - s.thickness) * 0.5
			lx := s.bounds.x + s.margin
			lw := s.bounds.w - s.margin * 2
			if lw > 0 {
				ctx.fill_rect(Rect{lx, ly, lw, s.thickness}, c)
			}
		}
		.vertical {
			// Vertical line centered horizontally in bounds
			lx := s.bounds.x + (s.bounds.w - s.thickness) * 0.5
			ly := s.bounds.y + s.margin
			lh := s.bounds.h - s.margin * 2
			if lh > 0 {
				ctx.fill_rect(Rect{lx, ly, s.thickness, lh}, c)
			}
		}
	}
}

pub fn (mut s Separator) handle_event(event &GuiEvent, app &App) bool {
	return false
}
