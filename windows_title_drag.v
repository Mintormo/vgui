module vgui

// ═══════════════════════════════════════════════════════
// WindowTitleDrag — container widget that enables
// window dragging when the user clicks and drags
// on empty space within its bounds.
//
// Double-click on empty space toggles maximize/restore.
//
// Child widgets (labels, spacers) are placed inside.
// Buttons should be placed OUTSIDE (in the parent HBox).
//
// Multiple WindowTitleDrag widgets can exist in a window.
// Each registers its bounds as a draggable region for
// SDL's hit-test callback.
// ═══════════════════════════════════════════════════════

pub struct WindowTitleDrag {
pub mut:
	type_tag int = kind_window_title_drag // тег типа, см. widget_tag.v
	box      BoxLayout
	visible  bool = true
}

// ─── Constructors ──────────────────────────────────────

pub fn window_title_drag() &WindowTitleDrag {
	return &WindowTitleDrag{
		box: BoxLayout{
			bounds:  Rect{0, 0, 0, 0}
			dir:     .horizontal
			spacing: 0
			pad:     0
		}
	}
}

pub fn window_title_drag_vertical() &WindowTitleDrag {
	return &WindowTitleDrag{
		box: BoxLayout{
			bounds:  Rect{0, 0, 0, 0}
			dir:     .vertical
			spacing: 0
			pad:     0
		}
	}
}

// ─── Public API (same as HBox) ─────────────────────────

// add - как HBox.add: без параметров естественный размер,
// flex: n - доля свободного места
pub fn (mut d WindowTitleDrag) add(widget &Widget, p LayoutParams) {
	d.box.children << p.to_entry(widget)
}

pub fn (mut d WindowTitleDrag) set_spacing(s f32) {
	d.box.spacing = s
}

pub fn (mut d WindowTitleDrag) set_padding(p f32) {
	d.box.pad = p
}

pub fn (mut d WindowTitleDrag) set_bg(c Color) {
	d.box.bg = c
}

pub fn (mut d WindowTitleDrag) set_panel_bg() {
	d.box.use_panel_bg = true
}

// ─── Drawing ───────────────────────────────────────────

pub fn (mut d WindowTitleDrag) arrange(mut ctx RenderContext) {
	if !d.visible {
		return
	}
	if is_bounds_unset(d.box.bounds) {
		d.box.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	d.box.arrange(mut ctx)
}

pub fn (mut d WindowTitleDrag) draw(mut ctx RenderContext) {
	if !d.visible {
		return
	}

	// Register our bounds as a drag rect for the borderless hit-test.
	ctx.pending_drag_rects << d.box.bounds
	// Also register for double-click detection (covers the full titlebar strip).
	ctx.pending_titlebar_rects << d.box.bounds

	d.box.draw_impl(mut ctx)
}

// ─── Events ────────────────────────────────────────────

pub fn (mut d WindowTitleDrag) handle_event(event &GuiEvent, app &App) bool {
	if !d.visible {
		return false
	}

	// Let children handle first
	if d.box.event_impl(event, app) {
		return true
	}

	// We don't handle drag ourselves — SDL hit-test does it.
	// Double-click maximize/restore is handled in sdl2_app.v process_events
	// because SDL hit-test intercepts clicks in drag zones before they reach widgets.
	return false
}
