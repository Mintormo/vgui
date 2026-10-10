module vgui

// ═══════════════════════════════════════════════════════
// Icon font cache + glyph rendering for the Lucide icon font.
//
// Mirrors the shape of font_cache.v / sdl3_fonts.v but is kept separate
// on purpose: the icon font is a single fixed embedded TTF (never a path
// or user-supplied bytes), so it only needs to be cached by the physical
// pixel size it was opened at. It must never be mixed into FontSet/
// g_font_cache — that cache is keyed by regular-text font configuration
// and is shared across windows for label/button/etc. text.
// ═══════════════════════════════════════════════════════

// Keyed by physical (dpi * ui_scale adjusted) pixel size. Never freed
// mid-process (same lifetime contract as g_font_cache); closed only in
// destroy_font_cache() at app shutdown.
__global g_icon_font_cache = map[int]voidptr{}

// icon_open_size computes the physical pixel size a logical icon size
// should be opened at, mirroring the get_font() calculation for regular text.
fn icon_open_size(ctx &RenderContext, logical_size int) int {
	combined := ctx.dpi_scale * ctx.ui_scale
	if combined > 1.0 {
		return int(f32(logical_size) * combined + 0.5)
	}
	return logical_size
}

// get_icon_font returns a cached TTF_Font* for the Lucide icon font at the
// given logical size (opened at the correct physical size for this context).
fn get_icon_font(ctx &RenderContext, logical_size int) voidptr {
	size := if logical_size <= 0 { 16 } else { logical_size }
	open_size := icon_open_size(ctx, size)

	if open_size in g_icon_font_cache {
		cached := g_icon_font_cache[open_size] or { unsafe { nil } }
		if unsafe { cached != nil } {
			return cached
		}
	}

	data, blob_size := embedded_icon_font()
	io := C.SDL_IOFromConstMem(data, usize(blob_size))
	if unsafe { io == nil } {
		return unsafe { nil }
	}
	font := C.TTF_OpenFontIO(io, true, f32(open_size))
	if unsafe { font == nil } {
		return unsafe { nil }
	}
	C.TTF_SetFontHinting(font, ttf_hinting_light_subpixel)
	g_icon_font_cache[open_size] = font
	return font
}

// destroy_icon_font_cache closes all cached icon font sizes. Called from
// destroy_font_cache() at app shutdown.
pub fn destroy_icon_font_cache() {
	for _, ptr in g_icon_font_cache {
		if unsafe { ptr != nil } {
			C.TTF_CloseFont(ptr)
		}
	}
	g_icon_font_cache = map[int]voidptr{}
}

// A style tag reserved in the text cache key space for icon glyphs, distinct
// from the FontStyle int values (0..5) used by regular text so an icon glyph
// can never collide-and-misrender as a same-hash regular-text entry.
const icon_style_tag = 100

// draw_icon_glyph renders one Lucide glyph centered inside `bounds`, at
// logical `size` and `color`. Goes through the same text_cache map as
// draw_text_with_font (keyed so it cannot collide with regular text — see
// icon_style_tag), so repeated draws of the same icon/size/color are cached
// exactly like label text.
pub fn (mut ctx RenderContext) draw_icon_glyph(codepoint u32, bounds Rect, size int, c Color) {
	if codepoint == 0 {
		return
	}
	font := get_icon_font(ctx, size)
	if unsafe { font == nil } {
		return
	}
	text := rune(codepoint).str()

	key := text_cache_key(text, size, icon_style_tag, c)
	ctx.cache_tick++

	cached := ctx.text_cache[key] or {
		TextCacheEntry{
			texture: unsafe { nil }
			w:       0
			h:       0
		}
	}
	mut texture := cached.texture
	mut tw := cached.w
	mut th := cached.h

	if unsafe { texture != nil } {
		if cached.text != text || cached.font_size != size || cached.style_int != icon_style_tag
			|| cached.color != c {
			C.SDL_DestroyTexture(texture)
			texture = unsafe { nil }
		}
	}

	if unsafe { texture != nil } {
		ctx.text_cache[key] = TextCacheEntry{
			texture:   texture
			w:         tw
			h:         th
			last_used: ctx.cache_tick
			text:      cached.text
			font_size: cached.font_size
			style_int: cached.style_int
			color:     cached.color
		}
	} else {
		sdl_color := C.SDL_Color{
			r: c.r
			g: c.g
			b: c.b
			a: c.a
		}
		surface := C.TTF_RenderText_Blended(font, text.str, usize(0), sdl_color)
		if unsafe { surface == nil } {
			return
		}
		texture = C.SDL_CreateTextureFromSurface(ctx.renderer, surface)
		C.SDL_DestroySurface(surface)
		if unsafe { texture == nil } {
			return
		}
		C.SDL_SetTextureBlendMode(texture, sdl_blendmode_blend)
		C.SDL_SetTextureScaleMode(texture, sdl_scalemode_nearest)

		mut iw := 0
		mut ih := 0
		C.TTF_GetStringSize(font, text.str, usize(0), &iw, &ih)
		tw = iw
		th = ih

		if ctx.text_cache.len >= ctx.cache_max {
			ctx.evict_text_cache_lru()
		}
		ctx.text_cache[key] = TextCacheEntry{
			texture:   texture
			w:         tw
			h:         th
			last_used: ctx.cache_tick
			text:      text
			font_size: size
			style_int: icon_style_tag
			color:     c
		}
	}

	s := ctx.dpi_scale * ctx.ui_scale
	inv_s := if s > 0 { f32(1.0) / s } else { f32(1.0) }
	dw := if s > 1.0 { f32(tw) / s } else { f32(tw) }
	dh := if s > 1.0 { f32(th) / s } else { f32(th) }

	cx := bounds.x + bounds.w * 0.5 - dw * 0.5
	cy := bounds.y + bounds.h * 0.5 - dh * 0.5
	px_f := f32(int(cx * s + 0.5)) * inv_s
	py_f := f32(int(cy * s + 0.5)) * inv_s

	dst := C.SDL_FRect{
		x: px_f
		y: py_f
		w: dw
		h: dh
	}
	C.SDL_RenderTexture(ctx.renderer, texture, unsafe { nil }, &dst)
}
