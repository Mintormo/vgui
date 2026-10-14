module vgui

// ═══════════════════════════════════════════════════════
// SDL3 implementation — fonts, text rendering, measurement
// ═══════════════════════════════════════════════════════

// Файл sdl3_fonts.v: шрифты и текст на уровне RenderContext. Содержит (1) выбор и ленивое
// открытие шрифтов нужного стиля/размера (get_font, get_font_immut, init_fonts); (2) отрисовку
// текста через кэш готовых текстур (draw_text_with_font); (3) измерение текста (measure_text_with_font,
// font_height_of, Window.measure_text); (4) поворотный текст (draw_text_rotated_center).
// Наборы шрифтов (FontSet) общие для окон и живут в g_font_cache со счётчиком ссылок (sdl3_render.v /
// PROJECT.md, «Архитектура рендеринга»): здесь шрифты только открываются и используются, а закрывает
// их destroy_font_cache. Кэш текстур текста (ctx.text_cache) привязан к рендереру окна и очищается
// в clear_text_cache.

// Константы хэша FNV-1a (64 бита): смещение и простое число из спецификации алгоритма.
// Хэш нужен для ключа кэша текстур текста.
const fnv1a_offset = u64(14695981039346656037)
const fnv1a_prime = u64(1099511628211)

// Ключ кэша текстуры текста: FNV-1a по байтам текста, размеру шрифта, стилю и четырём каналам
// цвета. Цвет входит в ключ, потому что текст запекается в текстуру уже с цветом. Ключ - только
// хэш, коллизии возможны; draw_text_with_font дополнительно сверяет поля записи.
@[inline]
fn text_cache_key(text string, font_size int, style_int int, c Color) u64 {
	mut h := fnv1a_offset
	for i in 0 .. text.len {
		h = (h ^ u64(text[i])) * fnv1a_prime
	}
	h = (h ^ u64(font_size)) * fnv1a_prime
	h = (h ^ u64(style_int)) * fnv1a_prime
	h = (h ^ u64(c.r)) * fnv1a_prime
	h = (h ^ u64(c.g)) * fnv1a_prime
	h = (h ^ u64(c.b)) * fnv1a_prime
	h = (h ^ u64(c.a)) * fnv1a_prime
	return h
}

// Уничтожает все закэшированные текстуры текста и иконок и пересоздаёт кэши пустыми. Вызывать нужно, пока
// рендерер жив (текстура принадлежит рендереру).
pub fn (mut ctx RenderContext) clear_text_cache() {
	for _, entry in ctx.text_cache {
		if unsafe { entry.texture != nil } {
			C.SDL_DestroyTexture(entry.texture)
		}
	}
	ctx.text_cache = map[u64]TextCacheEntry{}
	for _, t in ctx.icon_cache {
		if unsafe { t != nil } {
			C.SDL_DestroyTexture(t)
		}
	}
	ctx.icon_cache = map[string]voidptr{}
}

// Вытеснение по давности использования (LRU), когда кэш достиг cache_max: удаляются записи с
// last_used не новее 25-го перцентиля, т.е. примерно четверть самых старых. Пачкой, а не по
// одной, чтобы не пересчитывать порядок на каждую вставку.
fn (mut ctx RenderContext) evict_text_cache_lru() {
	if ctx.text_cache.len == 0 {
		return
	}
	mut stamps := []u64{cap: ctx.text_cache.len}
	for _, entry in ctx.text_cache {
		stamps << entry.last_used
	}
	stamps.sort()
	cutoff_idx := stamps.len / 4
	cutoff := stamps[cutoff_idx]

	mut to_remove := []u64{}
	for k, entry in ctx.text_cache {
		if entry.last_used <= cutoff {
			to_remove << k
		}
	}
	for k in to_remove {
		entry := ctx.text_cache[k] or { continue }
		if unsafe { entry.texture != nil } {
			C.SDL_DestroyTexture(entry.texture)
		}
		ctx.text_cache.delete(k)
	}
}

// Возвращает TTF_Font для стиля и логического размера (size <= 0 - размер окна). Базовый размер
// берётся из заранее открытого набора. Для других размеров шрифт открывается лениво и кэшируется
// в fonts.size_cache; при ошибке открытия отдаётся regular. Шрифт НЕ нужно закрывать и хранить в
// полях виджетов: им владеет FontSet (PROJECT.md, «Архитектура рендеринга»).
pub fn (mut ctx RenderContext) get_font(style FontStyle, size int) voidptr {
	effective_size := if size <= 0 { ctx.fonts.size } else { size }

	if effective_size == ctx.fonts.size {
		return match style {
			.regular { ctx.fonts.regular }
			.bold { ctx.fonts.bold }
			.italic { ctx.fonts.italic }
			.bold_italic { ctx.fonts.bold_italic }
			.mono { ctx.fonts.mono }
			.mono_bold { ctx.fonts.mono_bold }
		}
	}

	// The physical pixel size the font is actually opened at depends on this
	// window's dpi_scale * ui_scale. A FontSet can be shared (via g_font_cache)
	// between windows with different scales, so the cache key must include the
	// physical size — keying by logical size alone would hand a font opened at
	// one window's scale to a window with another.
	open_size := if ctx.dpi_scale * ctx.ui_scale > 1.0 {
		int(f32(effective_size) * ctx.dpi_scale * ctx.ui_scale + 0.5)
	} else {
		effective_size
	}
	// В ключ входят и логический, и физический (open_size) размеры - см. комментарий выше.
	key := '${int(style)}_${effective_size}_${open_size}'
	if key in ctx.fonts.size_cache {
		cached := ctx.fonts.size_cache[key] or { unsafe { nil } }
		if unsafe { cached != nil } {
			return cached
		}
	}

	is_mono := style == .mono || style == .mono_bold
	// Выбор источника шрифта: если для стиля задан отдельный файл (bold_path и т.п.) - берём его,
	// иначе открываем базовый (regular или mono) и синтезируем стиль флагами TTF ниже.
	dedicated_path := match style {
		.bold { ctx.fonts.bold_path }
		.italic { ctx.fonts.italic_path }
		.bold_italic { ctx.fonts.bold_italic_path }
		.mono_bold { ctx.fonts.mono_bold_path }
		else { '' }
	}
	base_path := if is_mono { ctx.fonts.mono_path } else { ctx.fonts.regular_path }
	path := if dedicated_path.len > 0 { dedicated_path } else { base_path }
	data := if dedicated_path.len > 0 {
		[]u8{}
	} else if is_mono {
		ctx.fonts.mono_data
	} else {
		ctx.fonts.font_data
	}

	font := open_font_for_role(is_mono, path, data, open_size)
	if unsafe { font == nil } {
		return ctx.fonts.regular
	}

	// Synthesize style only when no dedicated font file was provided
	sdl_style := if dedicated_path.len == 0 {
		match style {
			.bold { ttf_style_bold }
			.italic { ttf_style_italic }
			.bold_italic { ttf_style_bold | ttf_style_italic }
			.mono_bold { ttf_style_bold }
			else { ttf_style_normal }
		}
	} else {
		ttf_style_normal
	}

	if sdl_style != ttf_style_normal {
		C.TTF_SetFontStyle(font, sdl_style)
	}

	ctx.fonts.size_cache[key] = font
	ctx.fonts.handle_map[font] = FontHandleInfo{int(style), effective_size}
	return font
}

// Версия get_font для методов с неизменяемым ctx (measure() и прочие измерения).
// Шрифт нужного размера, если его ещё нет в кэше, ОТКРЫВАЕТ - так же, как get_font.
//
// Раньше она не открывала новых шрифтов и при промахе отдавала regular базового
// размера, рассчитывая, что размер «прогреет» draw(). Но первая раскладка идёт ДО
// первой отрисовки: метка size=20 мерилась шрифтом 15 пт (высота 27 вместо 32),
// draw() открывал нужный шрифт, и со второго кадра раскладка сдвигалась на 5 px -
// а перерисовывались лишь dirty-области, и на экране оставались куски кадра со
// старыми позициями (полоски поверх рамок полей ввода в примере 56 при наведении).
//
// Изменение здесь - только заполнение общего кэша шрифтов (ctx.fonts - указатель на
// FontSet, его size_cache/handle_map); поля самого RenderContext не меняются. Для
// вызывающего это мемоизация: результат одинаков при любом вызове, так что measure()
// остаётся чистой (PROJECT.md, «Layout: measure/arrange»). Потоки: как и всё
// остальное - только главный поток (PROJECT.md, «Глобальное изменяемое состояние»).
pub fn (ctx &RenderContext) get_font_immut(style FontStyle, size int) voidptr {
	mut cache_owner := unsafe { &RenderContext(ctx) }
	return cache_owner.get_font(style, size)
}

// open_font_for_role opens a TTF font at `size`.
// Priority: explicit `data` bytes → `path` on disk → built-in embedded default.
// Размер size - в физических пикселях (уже умноженный на dpi/ui scale). Возвращает nil при ошибке.
// Для данных из памяти SDL_IOFromConstMem не копирует байты: буфер должен жить, пока жив шрифт
// (они лежат в FontSet / встроены в бинарник). closeio=true - поток закроет сам SDL3_ttf.
fn open_font_for_role(is_mono bool, path string, data []u8, size int) voidptr {
	mut font := unsafe { voidptr(nil) }
	if data.len > 0 {
		io := C.SDL_IOFromConstMem(data.data, usize(data.len))
		if unsafe { io == nil } {
			return unsafe { nil }
		}
		font = C.TTF_OpenFontIO(io, true, f32(size))
	} else if path.len > 0 {
		font = C.TTF_OpenFont(path.str, f32(size))
	} else {
		def_data, blob_size := if is_mono { embedded_mono_font() } else { embedded_regular_font() }
		io := C.SDL_IOFromConstMem(def_data, usize(blob_size))
		if unsafe { io == nil } {
			return unsafe { nil }
		}
		// closeio=true: SDL3_ttf will close the IOStream after loading
		font = C.TTF_OpenFontIO(io, true, f32(size))
	}
	if unsafe { font != nil } {
		// Light subpixel hinting gives the sharpest result at non-integer scales
		C.TTF_SetFontHinting(font, ttf_hinting_light_subpixel)
	}
	return font
}

// load_style_font opens a font for a styled variant.
// Uses dedicated `data` bytes or `path` if provided; falls back to synthesizing
// `sdl_style` on top of `base_font` by cloning it from `base_path`/`base_data`.
fn load_style_font(path string, data []u8, base_path string, base_data []u8, is_mono bool, sdl_style int, size int) voidptr {
	if data.len > 0 {
		font := open_font_for_role(is_mono, '', data, size)
		if unsafe { font != nil } {
			return font
		}
	}
	if path.len > 0 {
		font := open_font_for_role(is_mono, path, []u8{}, size)
		if unsafe { font != nil } {
			return font
		}
	}
	// Synthesize: clone base font and apply SDL style flags
	font := open_font_for_role(is_mono, base_path, base_data, size)
	if unsafe { font != nil } && sdl_style != ttf_style_normal {
		C.TTF_SetFontStyle(font, sdl_style)
	}
	return font
}

// Открывает шесть базовых шрифтов набора ctx.fonts (regular, bold, italic, bold_italic, mono,
// mono_bold) и заполняет handle_map (указатель шрифта -> стиль и размер): по нему
// draw_text_with_font узнаёт стиль шрифта для ключа кэша. Пути пустые - используются данные в
// ctx.fonts.*_data, а если и их нет - встроенные шрифты. Возвращает false, если не открылся
// regular или mono (остальные стили деградируют до синтеза и ошибкой не считаются).
// У моноширинного набора только два стиля: mono и mono_bold.
pub fn (mut ctx RenderContext) init_fonts(regular_path string, bold_path string, italic_path string, bold_italic_path string, mono_path string, mono_bold_path string, size int, mono_size int) bool {
	ctx.fonts.size = size
	ctx.fonts.mono_size = mono_size
	ctx.fonts.regular_path = regular_path
	ctx.fonts.bold_path = bold_path
	ctx.fonts.italic_path = italic_path
	ctx.fonts.bold_italic_path = bold_italic_path
	ctx.fonts.mono_path = mono_path
	ctx.fonts.mono_bold_path = mono_bold_path

	ctx.fonts.regular = open_font_for_role(false, regular_path, ctx.fonts.font_data, size)
	if unsafe { ctx.fonts.regular == nil } {
		eprintln('Failed to load font: ${regular_path}')
		return false
	}

	ctx.fonts.bold = load_style_font(bold_path, ctx.fonts.bold_data, regular_path, ctx.fonts.font_data,
		false, ttf_style_bold, size)
	ctx.fonts.italic = load_style_font(italic_path, ctx.fonts.italic_data, regular_path, ctx.fonts.font_data,
		false, ttf_style_italic, size)
	ctx.fonts.bold_italic = load_style_font(bold_italic_path, ctx.fonts.bold_italic_data,
		regular_path, ctx.fonts.font_data, false, ttf_style_bold | ttf_style_italic, size)

	ctx.fonts.mono = open_font_for_role(true, mono_path, ctx.fonts.mono_data, mono_size)
	if unsafe { ctx.fonts.mono == nil } {
		eprintln('Failed to load mono font: ${mono_path}')
		return false
	}

	ctx.fonts.mono_bold = load_style_font(mono_bold_path, ctx.fonts.mono_bold_data, mono_path,
		ctx.fonts.mono_data, true, ttf_style_bold, mono_size)

	ctx.fonts.handle_map = map[voidptr]FontHandleInfo{}
	ctx.fonts.handle_map[ctx.fonts.regular] = FontHandleInfo{0, size}
	ctx.fonts.handle_map[ctx.fonts.bold] = FontHandleInfo{1, size}
	ctx.fonts.handle_map[ctx.fonts.italic] = FontHandleInfo{2, size}
	ctx.fonts.handle_map[ctx.fonts.bold_italic] = FontHandleInfo{3, size}
	ctx.fonts.handle_map[ctx.fonts.mono] = FontHandleInfo{4, mono_size}
	ctx.fonts.handle_map[ctx.fonts.mono_bold] = FontHandleInfo{5, mono_size}

	return true
}

// cleanup_fonts releases only renderer-bound texture caches.
// TTF font objects are shared via g_font_cache and freed by destroy_font_cache.
pub fn (mut ctx RenderContext) cleanup_fonts() {
	ctx.clear_text_cache()
}

// ─── Text rendering ───

// Рисует text в логической точке (x, y) (левый верхний угол) цветом c шрифтом font.
// Алгоритм: (1) координаты привязываются к целым физическим пикселям; (2) по ключу ищется
// текстура в кэше, при попадании сверяются текст/размер/стиль/цвет (защита от коллизии хэша -
// поля верификации удалять нельзя); (3) при промахе текст рендерится в surface (Blended - с
// антиалиасингом), превращается в текстуру, размеры берутся у TTF; перед вставкой при
// переполнении кэша вытесняются старые записи; (4) текстура рисуется в логических единицах
// (физические размеры делятся на dpi*ui scale). Пустой текст и nil-шрифт - ничего не делают.
pub fn (mut ctx RenderContext) draw_text_with_font(text string, x f32, y f32, c Color, font voidptr) {
	if text.len == 0 || unsafe { font == nil } {
		return
	}

	// Snap to physical pixel boundary so SDL_SetRenderScale does not
	// land on a fractional physical pixel (which causes "ghost" artifacts
	// with nearest-neighbour texture sampling).
	s := ctx.dpi_scale * ctx.ui_scale
	inv_s := if s > 0 { f32(1.0) / s } else { f32(1.0) }
	px_f := f32(int(x * s + 0.5)) * inv_s
	py_f := f32(int(y * s + 0.5)) * inv_s

	// Для неизвестного шрифта (не из handle_map) стиль = 99: ключ кэша всё равно уникален по размеру.
	info := ctx.fonts.handle_map[font] or { FontHandleInfo{99, ctx.fonts.size} }
	font_size := info.font_size
	style_int := info.style_int

	key := text_cache_key(text, font_size, style_int, c)

	// cache_tick - монотонный "счётчик времени" кэша; last_used хранит его значение для LRU.
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

	// FNV-1a collision check: a hash hit only counts if the entry was rendered
	// from exactly the same inputs. On mismatch, drop the colliding texture and
	// fall through to the miss path (re-render + overwrite) — costs one
	// re-render instead of silently drawing the wrong text forever.
	if unsafe { texture != nil } {
		if cached.text != text || cached.font_size != font_size || cached.style_int != style_int
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
		// SDL3_ttf: TTF_RenderText_Blended takes length (0 = auto from null-terminator)
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
		// Nearest-neighbour prevents SDL from blurring the already-antialiased glyph
		// texture when it is displayed at a non-integer logical size
		C.SDL_SetTextureScaleMode(texture, sdl_scalemode_nearest)

		// SDL3_ttf: TTF_GetStringSize for text measurement
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
			font_size: font_size
			style_int: style_int
			color:     c
		}
	}

	// Keep texture dimensions in logical units as f32 — avoid int rounding
	// that would make SDL re-scale by a non-1 factor, smearing the glyph.
	dw := if s > 1.0 { f32(tw) / s } else { f32(tw) }
	dh := if s > 1.0 { f32(th) / s } else { f32(th) }

	dst := C.SDL_FRect{
		x: px_f
		y: py_f
		w: dw
		h: dh
	}
	C.SDL_RenderTexture(ctx.renderer, texture, unsafe { nil }, &dst)
}

// ─── Measurement ───

// Размер текста в ЛОГИЧЕСКИХ единицах (физический размер от TTF делится на dpi*ui scale).
// Рендерер не используется. Пустой текст - нулевой размер.
pub fn (ctx &RenderContext) measure_text_with_font(text string, font voidptr) Vec2 {
	if text.len == 0 || unsafe { font == nil } {
		return Vec2{0, 0}
	}
	mut tw := 0
	mut th := 0
	C.TTF_GetStringSize(font, text.str, usize(0), &tw, &th)
	combined := ctx.dpi_scale * ctx.ui_scale
	if combined > 1.0 {
		return Vec2{f32(tw) / combined, f32(th) / combined}
	}
	return Vec2{f32(tw), f32(th)}
}

// Высота строки шрифта в логических единицах; для nil-шрифта - заглушка 16.
pub fn (ctx &RenderContext) font_height_of(font voidptr) f32 {
	if unsafe { font == nil } {
		return 16.0
	}
	h := f32(C.TTF_GetFontHeight(font))
	combined := ctx.dpi_scale * ctx.ui_scale
	if combined > 1.0 {
		return h / combined
	}
	return h
}

// TextMeasure selects the font variant for Window.measure_text.
// The defaults match a plain Label: regular style, window font size.
@[params]
pub struct TextMeasure {
pub:
	style FontStyle = .regular
	size  int // 0 = window default font size
}

// measure_text returns the logical size of `text` as this window's widgets
// would render it. Available as soon as create_window returns (fonts are
// loaded there, HiDPI already applied) — layouts can be sized from real
// text before the first frame, without waiting for a draw() RenderContext.
// Only TTF_GetStringSize is used; the renderer is not touched.
pub fn (mut w Window) measure_text(text string, cfg TextMeasure) Vec2 {
	font := w.ctx.get_font(cfg.style, cfg.size)
	return w.ctx.measure_text_with_font(text, font)
}

// ─── Rotated text rendering ───

// Рисует text, повёрнутый на angle градусов (по часовой стрелке в SDL; -90 - снизу вверх),
// так, что центр текста оказывается в (cx, cy). Результат НЕ кэшируется: на каждый вызов
// создаётся и сразу уничтожается текстура. Текст вписывается в квадрат со стороной max(w, h),
// чтобы вращение вокруг центра квадрата не обрезало углы. Размер в логических единицах считается
// делением на dpi*ui scale.
pub fn (mut ctx RenderContext) draw_text_rotated_center(text string, cx f32, cy f32, angle f64, c Color, font voidptr) {
	if text.len == 0 || unsafe { font == nil } {
		return
	}
	sdl_color := C.SDL_Color{
		r: c.r
		g: c.g
		b: c.b
		a: c.a
	}

	mut tw := 0
	mut th := 0
	C.TTF_GetStringSize(font, text.str, usize(0), &tw, &th)

	// Сторона квадратной подложки: у повёрнутого текста при любом угле габарит не превышает max(w, h)
	// по каждой оси.
	pad_side := if tw > th { tw } else { th }

	// SDL3: SDL_CreateSurface instead of SDL_CreateRGBSurfaceWithFormat
	padded := C.SDL_CreateSurface(pad_side, pad_side, sdl_pixelformat_argb8888)
	if unsafe { padded == nil } {
		return
	}

	text_surface := C.TTF_RenderText_Blended(font, text.str, usize(0), sdl_color)
	if unsafe { text_surface == nil } {
		C.SDL_DestroySurface(padded)
		return
	}

	mut dst_rect := C.SDL_Rect{
		x: (pad_side - tw) / 2
		y: (pad_side - th) / 2
		w: tw
		h: th
	}
	C.SDL_SetSurfaceBlendMode(text_surface, sdl_blendmode_none)
	C.SDL_BlitSurface(text_surface, unsafe { nil }, padded, &dst_rect)
	C.SDL_DestroySurface(text_surface)

	texture := C.SDL_CreateTextureFromSurface(ctx.renderer, padded)
	C.SDL_DestroySurface(padded)
	if unsafe { texture == nil } {
		return
	}
	C.SDL_SetTextureBlendMode(texture, sdl_blendmode_blend)

	combined := ctx.dpi_scale * ctx.ui_scale
	ds := if combined > 1.0 { int(f32(pad_side) / combined + 0.5) } else { pad_side }

	sdl_dst := C.SDL_FRect{
		x: cx - f32(ds) / 2.0
		y: cy - f32(ds) / 2.0
		w: f32(ds)
		h: f32(ds)
	}
	C.SDL_RenderTextureRotated(ctx.renderer, texture, unsafe { nil }, &sdl_dst, angle,
		unsafe { nil }, 0)
	C.SDL_DestroyTexture(texture)
}
