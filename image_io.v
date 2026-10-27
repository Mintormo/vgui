module vgui

// ═══════════════════════════════════════════════════════
// Чтение и запись файлов картинок в RGBA-буфер — без рендерера.
// ═══════════════════════════════════════════════════════
//
// Декодирование и кодирование картинок (SDL_image: png, jpg, webp, gif, tiff,
// bmp, svg...) для кода, которому нужны сами пиксели, а не текстура: Canvas
// (load_file/load_data/save_file). Текстуры из файлов делает sdl3_texture.v.
// Виджеты не зовут SDL_image сами (PROJECT.md, «Бэкенд рисования: виджеты не
// зовут SDL напрямую»).
//
// Формат пикселей буфера - ABGR8888 по классификации SDL: в памяти байты идут
// R, G, B, A (на little-endian), строки плотно, без выравнивания (pitch = w*4).
// Это формат буфера Canvas и его потоковой текстуры.

// RgbaImage - декодированная картинка: w×h пикселей, pixels - w*h*4 байт
// R,G,B,A построчно сверху вниз.
pub struct RgbaImage {
pub:
	w      int
	h      int
	pixels []u8
}

// decode_image_file читает и декодирует файл картинки. none - файла нет,
// формат не поддерживается или данные битые.
pub fn decode_image_file(path string) ?RgbaImage {
	if path.len == 0 {
		return none
	}
	return rgba_from_surface(C.IMG_Load(path.str))
}

// decode_image_bytes декодирует картинку из байтов файла в памяти (png/jpg/...).
// SDL читает байты только во время вызова.
pub fn decode_image_bytes(data []u8) ?RgbaImage {
	if data.len == 0 {
		return none
	}
	io := C.SDL_IOFromConstMem(data.data, usize(data.len))
	if io == unsafe { nil } {
		return none
	}
	return rgba_from_surface(C.IMG_Load_IO(io, true)) // closeio: поток закрывает SDL
}

// rgba_from_surface переводит только что загруженную поверхность в ABGR8888,
// копирует пиксели в плотный буфер и освобождает поверхности (в любом случае).
fn rgba_from_surface(surface voidptr) ?RgbaImage {
	if surface == unsafe { nil } {
		return none
	}
	conv := C.SDL_ConvertSurface(surface, sdl_pixelformat_abgr8888)
	C.SDL_DestroySurface(surface)
	if conv == unsafe { nil } {
		return none
	}
	defer {
		C.SDL_DestroySurface(conv)
	}
	s := unsafe { &C.SDL_Surface(conv) }
	w := s.w
	h := s.h
	if w <= 0 || h <= 0 || s.pixels == unsafe { nil } {
		return none
	}
	row_bytes := w * 4
	mut buf := []u8{len: w * h * 4}
	// Построчно: pitch поверхности может включать выравнивание, а буфер плотный.
	for y in 0 .. h {
		src := unsafe { &u8(s.pixels) + y * s.pitch }
		dst := unsafe { &u8(buf.data) + y * row_bytes }
		unsafe { vmemcpy(dst, src, row_bytes) }
	}
	return RgbaImage{
		w:      w
		h:      h
		pixels: buf
	}
}

// encode_image_file кодирует плотный ABGR8888-буфер w×h (pixels - не меньше
// w*h*4 байт) в файл; формат - по расширению (IMG_Save: png/jpg/webp/gif/bmp;
// tiff SDL_image только читает - тогда false). true - файл записан.
pub fn encode_image_file(path string, w int, h int, pixels []u8) bool {
	if w <= 0 || h <= 0 || pixels.len < w * h * 4 {
		return false
	}
	surface := C.SDL_CreateSurface(w, h, sdl_pixelformat_abgr8888)
	if surface == unsafe { nil } {
		return false
	}
	defer {
		C.SDL_DestroySurface(surface)
	}
	s := unsafe { &C.SDL_Surface(surface) }
	if s.pixels == unsafe { nil } {
		return false
	}
	row_bytes := w * 4
	for y in 0 .. h {
		src := unsafe { &u8(pixels.data) + y * row_bytes }
		dst := unsafe { &u8(s.pixels) + y * s.pitch }
		unsafe { vmemcpy(dst, src, row_bytes) }
	}
	return C.IMG_Save(surface, path.str)
}
