module vgui

import os

// ═══════════════════════════════════════════════════════
// Image export — save renderer region to PNG/JPG/BMP
// SDL3: SDL_RenderReadPixels returns a surface directly.
// ═══════════════════════════════════════════════════════

// ImageFormat - формат сохраняемого файла; выбирается по расширению пути (image_format_from_path). tiff объявлен, но сохранение в него не поддерживается (всегда ошибка).
pub enum ImageFormat {
	png
	jpg
	bmp
	tiff
	webp
}

// image_format_from_path - формат по расширению (.jpg/.jpeg, .tif/.tiff, ... без учёта регистра); неизвестное расширение даёт png (запись пойдёт PNG-данными под чужим именем).
pub fn image_format_from_path(path string) ImageFormat {
	ext := os.file_ext(path).to_lower()
	return match ext {
		'.png' { ImageFormat.png }
		'.jpg', '.jpeg' { ImageFormat.jpg }
		'.bmp' { ImageFormat.bmp }
		'.tif', '.tiff' { ImageFormat.tiff }
		'.webp' { ImageFormat.webp }
		else { ImageFormat.png }
	}
}

// Save a rectangular region of the window's renderer to a file.
// The rectangle is in LOGICAL coordinates (same as widget bounds).
// Параметры: region - в ЛОГИЧЕСКИХ координатах; quality 1..100 для jpg/webp (<= 0 -> 90, > 100 -> 100). Возвращает false при любой
// ошибке (нет рендерера, пустая или целиком вне окна область, сбой SDL/кодека, tiff).
// Алгоритм: логические координаты переводятся в физические пиксели (умножение на dpi_scale * ui_scale), область
// обрезается по размеру окна, затем SDL_RenderReadPixels читает пиксели из текущего кадра рендерера. Захватывается то,
// что уже нарисовано: для свежего кадра сначала вызовите render() (как PlotView.save_to_image).
pub fn (mut w Window) save_region_to_image(path string, region Rect, quality int) bool {
	if unsafe { w.renderer == nil } {
		return false
	}
	if region.w <= 0 || region.h <= 0 {
		return false
	}

	combined := w.ctx.dpi_scale * w.ctx.ui_scale
	phys_x := int(region.x * combined + 0.5)
	phys_y := int(region.y * combined + 0.5)
	phys_w := int(region.w * combined + 0.5)
	phys_h := int(region.h * combined + 0.5)

	if phys_w <= 0 || phys_h <= 0 {
		return false
	}

	// Размер окна для обрезки области берётся из SDL_GetWindowSize (так в коде; см. замечание в отчёте про HiDPI, где физические и оконные пиксели могут различаться).
	mut win_w := 0
	mut win_h := 0
	C.SDL_GetWindowSize(w.sdl_window, &win_w, &win_h)
	if phys_x >= win_w || phys_y >= win_h {
		return false
	}
	mut capture_w := phys_w
	mut capture_h := phys_h
	if phys_x + capture_w > win_w {
		capture_w = win_w - phys_x
	}
	if phys_y + capture_h > win_h {
		capture_h = win_h - phys_y
	}
	if capture_w <= 0 || capture_h <= 0 {
		return false
	}

	// SDL3: SDL_RenderReadPixels takes a rect and returns a new surface (or
	// nil on error). Real signature is `const SDL_Rect *rect` — ints, NOT
	// SDL_FRect (floats). Passing an SDL_FRect here (as this function did
	// before this fix) reinterprets the float bit patterns as garbage
	// ints, so SDL always rejected the read with "Can't read outside the
	// current viewport", even when the rect exactly matched the window —
	// this function silently returned false on every call. Found while
	// capturing screenshots for the CpPreview review (see report).
	src_rect := C.SDL_Rect{
		x: phys_x
		y: phys_y
		w: capture_w
		h: capture_h
	}
	surface := C.SDL_RenderReadPixels(w.renderer, &src_rect)
	if unsafe { surface == nil } {
		return false
	}
	defer { C.SDL_DestroySurface(surface) }

	fmt := image_format_from_path(path)
	q := if quality <= 0 {
		90
	} else if quality > 100 {
		100
	} else {
		quality
	}

	result := match fmt {
		.png {
			if C.IMG_SavePNG(surface, path.str) { 0 } else { -1 }
		}
		.jpg {
			if C.IMG_SaveJPG(surface, path.str, q) { 0 } else { -1 }
		}
		.bmp {
			// SDL3: SDL_SaveBMP(surface, file) — no more RWops needed for BMP
			if C.SDL_SaveBMP(surface, path.str) { 0 } else { -1 }
		}
		.webp {
			if C.IMG_SaveWEBP(surface, path.str, f32(q)) { 0 } else { -1 }
		}
		.tiff {
			// SDL_image can't write TIFF (read-only support) — mirror
			// Canvas.save_file's behaviour and fail loudly instead of
			// silently writing JPEG data under a .tiff extension.
			-1
		}
	}

	return result == 0
}

// save_window_to_image - сохранить всё окно (логический размер screen_width x screen_height).
pub fn (mut w Window) save_window_to_image(path string, quality int) bool {
	region := Rect{0, 0, w.ctx.screen_width, w.ctx.screen_height}
	return w.save_region_to_image(path, region, quality)
}

// save_to_image - сохраняет область графика: сперва перерисовывает окно (render(), чтобы кадр был актуален), затем снимает bounds виджета. window - окно, в котором лежит график.
pub fn (p &PlotView) save_to_image(window &Window, path string, quality int) bool {
	mut w := unsafe { window }
	w.render()
	return w.save_region_to_image(path, p.bounds, quality)
}
