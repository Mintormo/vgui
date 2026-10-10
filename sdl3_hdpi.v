module vgui

// ═══════════════════════════════════════════════════════
// HiDPI / High Resolution support (SDL3)
// SDL3 removes SDL_GL_GetDrawableSize and SDL_GetDisplayDPI.
// Use SDL_GetWindowSizeInPixels to get physical pixel count.
// ═══════════════════════════════════════════════════════

fn C.SDL_SetRenderScale(renderer voidptr, scale_x f32, scale_y f32) bool

pub struct DpiInfo {
pub:
	scale      f32
	logical_w  int
	logical_h  int
	physical_w int
	physical_h int
	dpi        f32
	is_hidpi   bool
}

pub fn detect_dpi(window voidptr) DpiInfo {
	mut lw := 0
	mut lh := 0
	mut pw := 0
	mut ph := 0

	C.SDL_GetWindowSize(window, &lw, &lh)
	// SDL3: SDL_GetWindowSizeInPixels replaces SDL_GL_GetDrawableSize
	C.SDL_GetWindowSizeInPixels(window, &pw, &ph)

	mut scale := f32(1.0)
	if lw > 0 {
		scale = f32(pw) / f32(lw)
	}

	// SDL3 removed SDL_GetDisplayDPI; approximate from pixel ratio
	approx_dpi := scale * 96.0

	return DpiInfo{
		scale:      scale
		logical_w:  lw
		logical_h:  lh
		physical_w: pw
		physical_h: ph
		dpi:        approx_dpi
		is_hidpi:   scale > 1.1
	}
}

pub fn (mut ctx RenderContext) init_hidpi(window voidptr) {
	if window == unsafe { nil } {
		return
	}

	ctx.dpi_info = detect_dpi(window)
	ctx.dpi_scale = ctx.dpi_info.scale

	if ctx.dpi_info.is_hidpi {
		C.SDL_SetRenderScale(ctx.renderer, ctx.dpi_scale, ctx.dpi_scale)

		ctx.screen_width = f32(ctx.dpi_info.logical_w)
		ctx.screen_height = f32(ctx.dpi_info.logical_h)
		// Fonts are NOT reloaded here: ctx.fonts is a FontSet shared through
		// g_font_cache, and re-initialising it in place leaked the old TTF
		// handles and silently changed the font size of every other window
		// holding the same set. create_window calls Window.reload_scaled_fonts,
		// which takes a separate FontSet for the scaled size.
	}
}

pub fn (ctx &RenderContext) logical_to_physical(x f32, y f32) (f32, f32) {
	return x * ctx.dpi_scale, y * ctx.dpi_scale
}

pub fn (ctx &RenderContext) scale_rect(r Rect) Rect {
	return Rect{r.x * ctx.dpi_scale, r.y * ctx.dpi_scale, r.w * ctx.dpi_scale, r.h * ctx.dpi_scale}
}

pub fn (ctx &RenderContext) scale_value(v f32) f32 {
	return v * ctx.dpi_scale
}
