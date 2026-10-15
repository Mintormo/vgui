// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════
// Global shared font cache — keyed by paths, sizes and a content hash of
// embedded font bytes. Windows with identical font parameters share one
// FontSet, avoiding redundant TTF_OpenFont calls.
//
// Lifetime is reference-counted: every window holds exactly one reference
// (taken in create_window / Window.reload_scaled_fonts, dropped when the
// window switches to another FontSet or in Window.cleanup). When the last
// reference goes away the TTF fonts are closed and the entry is removed.
// Without this every distinct ui_scale value leaked a whole FontSet — a
// single Ctrl+wheel zoom gesture (70 scales) kept ~38 MB of fonts forever.
//
// Stored as voidptr to allow mutable access without V ownership issues.
// ═══════════════════════════════════════════════════════

// g_font_cache: ключ font_cache_key(cfg) -> указатель на общий FontSet (&FontSet, хранится как voidptr). __global не виден из _test.v - тесты ходят через font_cache_* ниже. Только главный поток, без блокировок (инвариант проекта).
__global g_font_cache = map[string]voidptr{}

// font_data_hash is FNV-1a over the bytes (0 for "no embedded data").
// The key used to include the buffer ADDRESS instead: a freed buffer and a
// new one with different bytes at the same address produced the same key
// (ABA). Content hashing also lets separate buffers with equal bytes share.
fn font_data_hash(data []u8) u64 {
	if data.len == 0 {
		return 0
	}
	mut h := fnv1a_offset
	for b in data {
		h = (h ^ u64(b)) * fnv1a_prime
	}
	return h
}

// font_cache_key - строка-ключ набора шрифтов: пути, размеры и пары «длина:хэш» для встроенных байтов каждого
// начертания. Пути и размеры сравниваются дословно; хэш может теоретически столкнуться - это проверяет
// same_font_data при поиске.
fn font_cache_key(cfg FontConfig) string {
	dh := font_data_hash(cfg.font_data)
	bh := font_data_hash(cfg.bold_data)
	ih := font_data_hash(cfg.italic_data)
	bih := font_data_hash(cfg.bold_italic_data)
	mh := font_data_hash(cfg.mono_data)
	mbh := font_data_hash(cfg.mono_bold_data)
	return '${cfg.regular_path}|${cfg.bold_path}|${cfg.italic_path}|${cfg.bold_italic_path}|${cfg.mono_path}|${cfg.mono_bold_path}|${cfg.size}|${cfg.mono_size}|${cfg.font_data.len}:${dh}|${cfg.bold_data.len}:${bh}|${cfg.italic_data.len}:${ih}|${cfg.bold_italic_data.len}:${bih}|${cfg.mono_data.len}:${mh}|${cfg.mono_bold_data.len}:${mbh}'
}

// FontConfig - что загружать: пути к TTF (regular/bold/italic/bold_italic и моно-пара) ИЛИ встроенные байты
// (*_data) - вместо путей. size/mono_size - базовые размеры в логических пикселях. Пустой путь и пустые
// данные - начертание не задано (разбор значений по умолчанию - в RenderContext.init_fonts).
@[params]
pub struct FontConfig {
pub mut:
	regular_path     string
	bold_path        string
	italic_path      string
	bold_italic_path string
	mono_path        string
	mono_bold_path   string
	size             int = 14
	mono_size        int = 13
	font_data        []u8
	bold_data        []u8
	italic_data      []u8
	bold_italic_data []u8
	mono_data        []u8
	mono_bold_data   []u8
}

// same_font_data reports whether the FontSet was built from exactly these
// bytes. Paths and sizes are compared verbatim in the key; only the embedded
// data goes through a hash, so a hash hit is verified here (same approach as
// text_cache: a collision costs a separate FontSet, never a wrong font).
fn (fs &FontSet) same_font_data(cfg FontConfig) bool {
	return fs.font_data == cfg.font_data && fs.bold_data == cfg.bold_data
		&& fs.italic_data == cfg.italic_data && fs.bold_italic_data == cfg.bold_italic_data
		&& fs.mono_data == cfg.mono_data && fs.mono_bold_data == cfg.mono_bold_data
}

// get_or_load_fonts returns a cached FontSet for the given parameters,
// creating and loading it on first use. Every successful call takes one
// reference — pair it with release_fonts().
fn get_or_load_fonts(cfg FontConfig) !&FontSet {
	base_key := font_cache_key(cfg)
	mut key := base_key
	// Probe past (astronomically unlikely) hash collisions. A hole left by an
	// evicted entry ends the probe early — that only creates a duplicate
	// FontSet, never hands out one built from other bytes.
	for n := 1; true; n++ {
		ptr := g_font_cache[key] or { break }
		if unsafe { ptr == nil } {
			break
		}
		mut cached := unsafe { &FontSet(ptr) }
		if cached.same_font_data(cfg) {
			cached.refs++
			return cached
		}
		key = '${base_key}#${n}'
	}

	mut fs := &FontSet{
		font_data:        cfg.font_data
		bold_data:        cfg.bold_data
		italic_data:      cfg.italic_data
		bold_italic_data: cfg.bold_italic_data
		mono_data:        cfg.mono_data
		mono_bold_data:   cfg.mono_bold_data
		cache_key:        key
		refs:             1
	}
	mut ctx := RenderContext{
		fonts: fs
	}
	if !ctx.init_fonts(cfg.regular_path, cfg.bold_path, cfg.italic_path, cfg.bold_italic_path,
		cfg.mono_path, cfg.mono_bold_path, cfg.size, cfg.mono_size) {
		close_font_set(mut fs)
		return error('Failed to load fonts (regular="${cfg.regular_path}", mono="${cfg.mono_path}", size=${cfg.size})')
	}
	g_font_cache[key] = voidptr(fs)
	return fs
}

// release_fonts drops one reference taken by get_or_load_fonts. The last
// reference closes every TTF font of the set and removes it from the cache.
// A FontSet that is no longer the cache entry under its key (already freed by
// destroy_font_cache at app shutdown) is ignored, so a late Window.cleanup
// after App.cleanup is a no-op rather than a double TTF_CloseFont.
fn release_fonts(fs_ptr voidptr) {
	if unsafe { fs_ptr == nil } {
		return
	}
	mut fs := unsafe { &FontSet(fs_ptr) }
	cached := g_font_cache[fs.cache_key] or { return }
	if cached != fs_ptr {
		return
	}
	fs.refs--
	if fs.refs > 0 {
		return
	}
	g_font_cache.delete(fs.cache_key)
	close_font_set(mut fs)
}

// close_font_set closes every TTF font owned by the set (base styles and the
// per-size variants opened lazily by RenderContext.get_font).
// close_font_set закрывает все TTF_Font набора и обнуляет поля, чтобы повторный вызов (например, destroy_font_cache
// после release_fonts) не закрыл шрифт дважды. size_cache - ленивые варианты по размеру из get_font.
fn close_font_set(mut fs FontSet) {
	if unsafe { fs.regular != nil } { C.TTF_CloseFont(fs.regular) }
	if unsafe { fs.bold != nil } { C.TTF_CloseFont(fs.bold) }
	if unsafe { fs.italic != nil } { C.TTF_CloseFont(fs.italic) }
	if unsafe { fs.bold_italic != nil } { C.TTF_CloseFont(fs.bold_italic) }
	if unsafe { fs.mono != nil } { C.TTF_CloseFont(fs.mono) }
	if unsafe { fs.mono_bold != nil } { C.TTF_CloseFont(fs.mono_bold) }
	for _, font in fs.size_cache {
		if unsafe { font != nil } { C.TTF_CloseFont(font) }
	}
	fs.regular = unsafe { nil }
	fs.bold = unsafe { nil }
	fs.italic = unsafe { nil }
	fs.bold_italic = unsafe { nil }
	fs.mono = unsafe { nil }
	fs.mono_bold = unsafe { nil }
	fs.size_cache = map[string]voidptr{}
	fs.handle_map = map[voidptr]FontHandleInfo{}
	fs.refs = 0
}

// Cache accessors. `__global` variables are not visible from _test.v files,
// so font_cache tests inspect and seed the cache through these.
fn font_cache_len() int {
	return g_font_cache.len
}

fn font_cache_entry(key string) voidptr {
	return g_font_cache[key] or { unsafe { nil } }
}

fn font_cache_put(key string, fs voidptr) {
	g_font_cache[key] = fs
}

fn font_cache_drop(key string) {
	g_font_cache.delete(key)
}

// destroy_font_cache closes all cached TTF font objects and clears the cache.
// Called once during app shutdown, after all windows are destroyed; it frees
// whatever windows never released (e.g. windows not added to the App).
pub fn destroy_font_cache() {
	for _, ptr in g_font_cache {
		if unsafe { ptr == nil } {
			continue
		}
		mut fs := unsafe { &FontSet(ptr) }
		close_font_set(mut fs)
	}
	g_font_cache = map[string]voidptr{}
	destroy_icon_font_cache()
}
