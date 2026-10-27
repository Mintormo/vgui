module vgui

// ═══════════════════════════════════════════════════════
// Texture — типизированный хэндл текстуры бэкенда (сейчас SDL_Texture).
// ═══════════════════════════════════════════════════════
//
// Виджеты не зовут SDL сами (PROJECT.md, «Бэкенд рисования: виджеты не зовут
// SDL напрямую»): вместо `voidptr` на SDL_Texture в своих полях они держат
// Texture, создают её только через RenderContext (texture_from_file,
// texture_from_bytes, texture_from_pixels) и рисуют через ctx.draw_texture.
//
// Главное, что прячет этот тип, — инвариант «Время жизни SDL-текстур»
// (PROJECT.md): SDL_DestroyRenderer освобождает и все текстуры рендерера,
// поэтому SDL_DestroyTexture допустим, только пока жив ИМЕННО тот рендерер,
// что создал текстуру. Texture запоминает пару (рендерер, поколение) при
// создании, и destroy() сверяет её с реестром живых рендереров
// (is_renderer_alive_gen) — каждому виджету больше не нужно повторять это.
//
// Texture — значение: копию можно хранить где угодно, но освобождать её
// должен один владелец (две копии и два destroy() — двойное освобождение,
// если рендерер жив). Пустая Texture{} — «текстуры нет»; рисовать её можно,
// это no-op.

// Texture - хэндл текстуры с размером в пикселях. Поля handle/renderer/gen -
// дело бэкенда, снаружи модуля их не видно; w/h - только для чтения.
pub struct Texture {
mut:
	// handle - SDL_Texture*; nil - текстуры нет
	handle voidptr
	// renderer и gen - рендерер-создатель и его поколение в реестре живых
	// рендереров (sdl3_window.v): одного указателя мало, новый рендерер может
	// занять адрес умершего (ABA)
	renderer voidptr
	gen      u64
pub:
	// размер текстуры в пикселях
	w int
	h int
}

// TextureScale - фильтр при растяжении текстуры: nearest - пиксели остаются
// квадратами (увеличение холста), linear - сглаживание (фото, иконки).
pub enum TextureScale {
	linear
	nearest
}

// TextureDrawOpts - необязательные параметры draw_texture_ex.
@[params]
pub struct TextureDrawOpts {
pub:
	// src - часть текстуры в пикселях; none - вся текстура
	src ?Rect
	// alpha - общая прозрачность (альфа-модуляция) на время этого вызова
	alpha u8 = 255
	// angle - поворот в градусах по часовой стрелке вокруг центра dst
	angle f64
}

// is_valid - есть ли текстура (создание удалось и destroy ещё не звали).
pub fn (t &Texture) is_valid() bool {
	return t.handle != unsafe { nil }
}

// belongs_to - создана ли текстура рендерером этого контекста и жив ли он
// (то же поколение). Кэшу, общему для нескольких окон (MarkdownView), так
// видно, что запись чужая или устарела и рисовать ею нельзя.
pub fn (t &Texture) belongs_to(ctx &RenderContext) bool {
	return t.is_valid() && t.renderer == ctx.renderer
		&& t.gen == renderer_generation(ctx.renderer) && t.gen != 0
}

// destroy освобождает текстуру и обнуляет хэндл (идемпотентно). SDL_DestroyTexture
// зовётся, только если рендерер-создатель жив (то же поколение): иначе SDL уже
// освободил текстуру вместе с рендерером, и повторное освобождение - use-after-free.
// Контекст не нужен - поэтому его можно звать из destroy_texture() виджета,
// когда окна уже нет (teardown из Python/GC).
pub fn (mut t Texture) destroy() {
	if t.handle != unsafe { nil } && is_renderer_alive_gen(t.renderer, t.gen) {
		C.SDL_DestroyTexture(t.handle)
	}
	t = Texture{}
}

// set_scale - фильтр растяжения текстуры (TextureScale).
pub fn (mut t Texture) set_scale(mode TextureScale) {
	if t.handle == unsafe { nil } {
		return
	}
	sdl_mode := match mode {
		.linear { sdl_scalemode_linear }
		.nearest { sdl_scalemode_nearest }
	}
	C.SDL_SetTextureScaleMode(t.handle, sdl_mode)
}

// ─── Создание ──────────────────────────────────────────

// wrap_texture оборачивает только что созданную SDL-текстуру этого контекста:
// включает альфа-смешивание (картинки с прозрачностью) и запоминает размер,
// рендерер и его поколение. nil даёт пустую Texture.
fn (ctx &RenderContext) wrap_texture(handle voidptr) Texture {
	if handle == unsafe { nil } {
		return Texture{}
	}
	C.SDL_SetTextureBlendMode(handle, sdl_blendmode_blend)
	mut wf := f32(0)
	mut hf := f32(0)
	C.SDL_GetTextureSize(handle, &wf, &hf)
	return Texture{
		handle:   handle
		renderer: ctx.renderer
		gen:      renderer_generation(ctx.renderer)
		w:        int(wf)
		h:        int(hf)
	}
}

// texture_from_surface делает текстуру из SDL_Surface и освобождает поверхность
// (в любом случае). nil-поверхность (ошибка загрузки) даёт пустую Texture.
fn (ctx &RenderContext) texture_from_surface(surface voidptr) Texture {
	if surface == unsafe { nil } {
		return Texture{}
	}
	handle := C.SDL_CreateTextureFromSurface(ctx.renderer, surface)
	C.SDL_DestroySurface(surface)
	return ctx.wrap_texture(handle)
}

// texture_from_file загружает картинку (png, jpg, svg, webp... - что умеет
// SDL_image) в текстуру. Ошибка чтения или декодирования - пустая Texture
// (is_valid() == false), не исключение: виджет сам решает, что показать.
pub fn (ctx &RenderContext) texture_from_file(path string) Texture {
	if path.len == 0 {
		return Texture{}
	}
	return ctx.texture_from_surface(C.IMG_Load(path.str))
}

// texture_from_bytes - то же из байтов файла картинки в памяти. SDL читает байты
// только во время вызова, хранить их дольше не нужно.
pub fn (ctx &RenderContext) texture_from_bytes(data []u8) Texture {
	if data.len == 0 {
		return Texture{}
	}
	io := C.SDL_IOFromConstMem(data.data, usize(data.len))
	if io == unsafe { nil } {
		return Texture{}
	}
	return ctx.texture_from_surface(C.IMG_Load_IO(io, true)) // closeio: поток закрывает SDL
}

// texture_streaming создаёт пустую текстуру w×h для частого обновления
// пикселей (update): формат ABGR8888 - байты R,G,B,A, как у буфера Canvas
// (image_io.v). Растяжение - scale (у холста пиксели квадратные: .nearest).
// Ошибка или нулевой размер - пустая Texture.
pub fn (ctx &RenderContext) texture_streaming(w int, h int, scale TextureScale) Texture {
	if w <= 0 || h <= 0 {
		return Texture{}
	}
	handle := C.SDL_CreateTexture(ctx.renderer, sdl_pixelformat_abgr8888, sdl_textureaccess_streaming,
		w, h)
	mut tex := ctx.wrap_texture(handle)
	tex.set_scale(scale)
	return tex
}

// update заливает в текстуру пиксели целиком: pixels - w*h*4 байт ABGR8888,
// строки плотно (pitch = w*4). Пустая текстура или короткий буфер - no-op.
pub fn (mut t Texture) update(pixels []u8) {
	if t.handle == unsafe { nil } || pixels.len < t.w * t.h * 4 {
		return
	}
	C.SDL_UpdateTexture(t.handle, unsafe { nil }, pixels.data, t.w * 4)
}

// ─── Рисование ─────────────────────────────────────────

// draw_texture рисует всю текстуру в прямоугольник dst (логические координаты).
// Пустая текстура - no-op.
pub fn (mut ctx RenderContext) draw_texture(t &Texture, dst Rect) {
	ctx.draw_texture_ex(t, dst)
}

// draw_texture_ex - draw_texture с частью текстуры (src), общей прозрачностью
// (alpha) и поворотом (angle), см. TextureDrawOpts. Альфа-модуляция ставится
// только на время вызова и возвращается к 255: текстура может быть общей
// (кэш иконок), и следующий её пользователь не должен получить чужую альфу.
pub fn (mut ctx RenderContext) draw_texture_ex(t &Texture, dst Rect, opts TextureDrawOpts) {
	if t.handle == unsafe { nil } {
		return
	}
	sdl_dst := C.SDL_FRect{
		x: dst.x
		y: dst.y
		w: dst.w
		h: dst.h
	}
	mut sdl_src := C.SDL_FRect{}
	mut src_ptr := unsafe { nil }
	if src := opts.src {
		sdl_src = C.SDL_FRect{
			x: src.x
			y: src.y
			w: src.w
			h: src.h
		}
		src_ptr = &sdl_src
	}
	if opts.alpha != 255 {
		C.SDL_SetTextureAlphaMod(t.handle, opts.alpha)
	}
	if opts.angle != 0 {
		C.SDL_RenderTextureRotated(ctx.renderer, t.handle, src_ptr, &sdl_dst, opts.angle,
			unsafe { nil }, 0)
	} else {
		C.SDL_RenderTexture(ctx.renderer, t.handle, src_ptr, &sdl_dst)
	}
	if opts.alpha != 255 {
		C.SDL_SetTextureAlphaMod(t.handle, 255)
	}
}
