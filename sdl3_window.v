module vgui

// ═══════════════════════════════════════════════════════
// Window — real SDL3 window, parent for all widgets
// Dialog — modal variant that blocks other windows
// ═══════════════════════════════════════════════════════

// Файл sdl3_window.v: окно (Window) и диалог (Dialog) - обёртки над SDL-окном и его рендерером.
// Window владеет SDL_Window, SDL_Renderer, RenderContext (ctx: тема, шрифты, фокус, dirty regions,
// кэши текстур), списком корневых виджетов и постоянной текстурой-целью рендера (rt). Что где:
// создание и режимы окна (create_window, set_mode...), реестр живых рендереров (защита от
// двойного освобождения текстур), кадр (render: arrange -> отрисовка в rt целиком или только
// dirty-прямоугольника -> оверлеи/тултипы -> копия rt на экран), события (dispatch_event_*), точечная
// инвалидация hover при mouse_move, teardown (cleanup), фоновая картинка, а во второй половине
// файла - Dialog (окно фиксированного размера, чаще модальное) и масштаб интерфейса set_ui_scale.
// Окна регистрирует App (sdl3_app.v): он же гонит SDL-события в dispatch_event_with_app и зовёт
// render(). Рисование - sdl3_render.v / sdl3_fonts.v, HiDPI - sdl3_hdpi.v, привязки SDL -
// sdl3_bindings.v, раскладка - PROJECT.md «Layout: measure/arrange», «Фаза arrange».

// Дополнительные C-привязки SDL, нужные только окнам (основные - в sdl3_bindings.v).
fn C.SDL_GetWindowID(win voidptr) u32
fn C.SDL_GetWindowFromID(id u32) voidptr
fn C.SDL_RaiseWindow(win voidptr) bool
fn C.SDL_HideWindow(win voidptr) bool
fn C.SDL_ShowWindow(win voidptr) bool
fn C.SDL_SetWindowSize(win voidptr, w int, h int) bool
fn C.SDL_SetWindowPosition(win voidptr, x int, y int) bool
fn C.SDL_GetDisplayForWindow(win voidptr) u32
fn C.SDL_GetWindowPosition(win voidptr, x &int, y &int) bool
fn C.SDL_SetWindowMinimumSize(win voidptr, w int, h int) bool
fn C.SDL_SetWindowMaximumSize(win voidptr, w int, h int) bool
fn C.SDL_GetWindowMaximumSize(win voidptr, w &int, h &int) bool
fn C.SDL_MinimizeWindow(win voidptr) bool
fn C.SDL_RestoreWindow(win voidptr) bool
fn C.SDL_MaximizeWindow(win voidptr) bool
fn C.SDL_SetWindowFullscreen(win voidptr, fullscreen bool) bool
fn C.SDL_SetWindowIcon(win voidptr, icon voidptr) bool
fn C.SDL_SetWindowResizable(win voidptr, resizable bool) bool
fn C.SDL_SetWindowBordered(win voidptr, bordered bool) bool

// ─── Window mode ───

// Режим окна: resizable - обычное с рамкой и изменяемым размером; fixed - с рамкой, размер
// фиксирован; fullscreen - полноэкранное; borderless - без рамки; borderless_resizable - без рамки,
// размер можно менять (края перетаскиваются через hit-test, см. borderless-функции).
pub enum WindowMode {
	resizable
	fixed
	fullscreen
	borderless
	borderless_resizable
}

// ─── WindowConfig ───

// Параметры create_window. width/height == 0 - размер по содержимому (окно создаётся скрытым и
// показывается после первой раскладки). x/y < 0 - по центру экрана. min_*/max_* - границы
// размера (0 у max - без ограничения). theme == none - тема приложения (применит App.add_window).
// *_path / *_data - шрифты файлом или байтами (data приоритетнее; пусто - встроенные).
// font_size/mono_size - логические размеры; high_dpi - включить HiDPI; borderless/hittest_data -
// служебные поля безрамочного режима. vsync - синхронизация показа кадра с
// обновлением экрана; по умолчанию выключена: частоту кадров задаёт цикл App
// (AppConfig.target_fps), а VSync блокирует показ кадра в каждом окне, и при нескольких
// анимированных окнах частота делилась бы на их число.
@[params]
pub struct WindowConfig {
pub mut:
	title string = 'Window'
	// 0 - размер по содержимому: окно создаётся скрытым и при первой
	// раскладке встаёт под содержимое (не меньше min_width/min_height)
	width      int
	height     int
	x          int        = -1
	y          int        = -1
	mode       WindowMode = .resizable
	min_width  int        = 120
	min_height int        = 80
	max_width  int
	max_height int
	visible    bool = true
	// none - тема приложения: App.add_window применит AppConfig.theme
	// (до этого окно светлое). Заданная тема - явная, приложение её не трогает.
	theme            ?Theme
	font_path        string
	bold_path        string
	italic_path      string
	bold_italic_path string
	mono_path        string
	mono_bold_path   string
	font_data        []u8
	bold_data        []u8
	italic_data      []u8
	bold_italic_data []u8
	mono_data        []u8
	mono_bold_data   []u8
	font_size        int = 16
	mono_size        int = 16
	vsync            bool
	high_dpi         bool = true
	icon_path        string
	borderless       bool
	hittest_data     voidptr = unsafe { nil }
}

// ─── Live-renderer registry ───
//
// SDL ties every texture to the renderer that created it. When a renderer is
// destroyed (Window.cleanup → SDL_DestroyRenderer), SDL also destroys all of
// its textures. A subsequent SDL_DestroyTexture on one of those (e.g. from a
// widget's destructor running after the window during a non-deterministic GC
// teardown) is a use-after-free / double-free.
//
// To guard against this, widgets that own SDL textures (ImageView) record the
// renderer their texture belongs to and consult this registry before calling
// SDL_DestroyTexture: a renderer absent from the registry is dead, so its
// textures are already gone and must not be freed again.
//
// Each registration also gets a monotonically increasing generation id (never
// reused — same ABA rationale as cb_id in vguipy/_lib.py). A bare pointer comparison
// is not enough: a *new* renderer can be allocated at the address of a dead
// one, making the dead renderer look alive to a stale snapshot. Texture owners
// must therefore record (pointer, generation) at texture-creation time and
// validate both via is_renderer_alive_gen before SDL_DestroyTexture.
// Запись реестра: указатель рендерера и номер его "поколения" (generation).
struct LiveRenderer {
	ptr voidptr
	gen u64
}

// Глобальное состояние главного потока: реестр живых рендереров и счётчик поколений
// (не сбрасывается и не переиспользуется - защита от ABA).
__global (
	g_live_renderers = []LiveRenderer{}
	g_renderer_gen   = u64(0)
)

// Заносит свежесозданный рендерер в реестр с новым номером поколения.
fn register_renderer(ren voidptr) {
	if ren == unsafe { nil } {
		return
	}
	g_renderer_gen++
	g_live_renderers << LiveRenderer{
		ptr: ren
		gen: g_renderer_gen
	}
}

// unregister_renderer removes ren from the registry. Lookup by pointer is
// sound here (unlike stale ImageView snapshots): the registry only holds
// currently-living renderers, and two live renderers can never share an
// address.
fn unregister_renderer(ren voidptr) {
	if ren == unsafe { nil } {
		return
	}
	for i, r in g_live_renderers {
		if r.ptr == ren {
			g_live_renderers.delete(i)
			return
		}
	}
}

// renderer_generation returns the generation id of a currently-living
// renderer, or 0 if ren is nil or dead. 0 is never a valid generation
// (the counter starts at 1).
pub fn renderer_generation(ren voidptr) u64 {
	if ren == unsafe { nil } {
		return 0
	}
	for r in g_live_renderers {
		if r.ptr == ren {
			return r.gen
		}
	}
	return 0
}

// is_renderer_alive reports whether ren is a currently-living renderer. A nil
// renderer is treated as dead (nothing to free). NOTE: pointer-only check —
// subject to ABA if the caller's pointer is a stale snapshot; texture owners
// should use is_renderer_alive_gen with the generation recorded at
// texture-creation time.
pub fn is_renderer_alive(ren voidptr) bool {
	return renderer_generation(ren) != 0
}

// is_renderer_alive_gen reports whether ren is alive AND is the same renderer
// instance the caller remembers (its registration generation matches gen).
// Returns false for gen == 0 (no snapshot taken / already cleared).
pub fn is_renderer_alive_gen(ren voidptr, gen u64) bool {
	return gen != 0 && renderer_generation(ren) == gen
}

// ─── Window ───

// Окно SDL вместе со всем состоянием отрисовки. sdl_window/renderer - ресурсы SDL (освобождает
// cleanup); widgets - корневые виджеты в порядке добавления (последний рисуется поверх);
// focused - индекс корня, получающего событие первым (-1 - нет); open/visible - окно "живо" и
// показано; on_close - колбэк закрытия; on_drop_* - запасные получатели drag-and-drop; hotkeys -
// горячие клавиши окна; hittest_data/in_drag_zone - безрамочный режим. Остальные поля -
// служебное состояние раскладки, размера по содержимому, постоянной render-цели (rt*), точечной
// инвалидации hover (hover_*) и пометка prev_overlayish; подробности в комментариях к полям.
pub struct Window {
pub mut:
	sdl_window    voidptr
	sdl_id        u32
	renderer      voidptr
	ctx           RenderContext
	config        WindowConfig
	widgets       []&Widget
	focused       int = -1
	open          bool
	visible       bool = true
	minimized     bool
	maximized     bool
	mouse_x       f32
	mouse_y       f32
	on_close      fn (mut vgui.Window) = unsafe { nil }
	on_drop_file  fn (path string)     = unsafe { nil }
	on_drop_text  fn (text string)     = unsafe { nil }
	hotkeys       HotkeyManager
	hittest_data  voidptr = unsafe { nil }
	in_drag_zone  bool
	last_layout_w f32
	last_layout_h f32
	// Размер экрана, под который корням последний раз выставлены bounds в
	// arrange(). Отдельно от last_layout_*: те решают «полный кадр» в
	// render(), а arrange может пройти раньше — перед событием.
	arranged_w f32
	arranged_h f32
	// Минимальный размер окна по содержимому, уже отданный SDL
	// (fit_min_size): окно не уменьшить так, чтобы содержимое уехало
	// за край
	content_min_w int
	content_min_h int
	// Размер по содержимому (width/height 0 в WindowConfig): первая
	// раскладка с виджетами задаёт размер и показывает окно
	auto_size bool
	// Set each frame by App.render_all() when this window has an open modal
	// dialog child; triggers a dimming backdrop over the window content.
	has_modal_child bool
	// Текстовый ввод SDL сейчас включён (sync_text_input)
	text_input_on bool
	// Тема задана явно (WindowConfig.theme или set_theme). Иначе окно
	// следует теме приложения: add_window и App.set_theme её применяют.
	theme_explicit bool
	// True while this window holds its reference to ctx.fonts in g_font_cache
	// (see font_cache.v). Guards against a double release_fonts in cleanup().
	fonts_held bool
	// Optional window background image, painted behind all widgets. Owned by the
	// window (not anchored in g_image_backgrounds); its texture is freed in
	// cleanup() while the renderer is still alive.
	bg_image &ImageBackground = unsafe { nil }
	// ─── Persistent render target (dirty-region rendering) ───
	// A texture the size of the window's drawable area (PHYSICAL pixels) that
	// widgets draw into. Unlike the default backbuffer, this texture's content
	// survives between frames, so a partial redraw only needs to touch the
	// dirty rectangle — everything else is already correct from last frame.
	// It is copied to the real backbuffer and presented every frame. See the
	// "Time lifetime of SDL textures" note in PROJECT.md: rt_gen records the
	// renderer generation at creation time and destruction is guarded by
	// is_renderer_alive_gen, exactly like ImageView's texture.
	rt     voidptr = unsafe { nil }
	rt_w   int
	rt_h   int
	rt_gen u64
	// Set when SDL_CreateTexture for rt failed for the CURRENT (rt_gen, rt_w,
	// rt_h) combination — see ensure_render_target's guard against retrying
	// that exact failure every single frame.
	rt_create_failed bool
	// ─── Точечная инвалидация hover (PROJECT.md, «Инвалидация и dirty regions») ───
	// Виджет, над которым курсор стоял после ПРЕДЫДУЩЕГО mouse_move, и его
	// bounds на тот момент. hover_widget — сырой адрес (voidptr(&Widget), как
	// в containers.v), и он НИКОГДА не разыменовывается: виджет мог быть
	// уничтожен между событиями. Его единственное назначение — сравнение
	// «тот же или другой», а перерисовывать нужно сохранённый hover_rect,
	// а не свежие bounds уже мёртвого объекта.
	hover_widget voidptr = unsafe { nil }
	hover_rect   Rect
	// Whether the PREVIOUS frame drew an overlay/tooltip/modal-backdrop, all
	// of which paint outside any widget's own bounds without clipping. If the
	// next frame closes them without a full repaint, their pixels would be
	// left as a ghost on the persistent render target — so their presence
	// (this frame OR last frame) forces a full frame.
	prev_overlayish bool
}

// Создаёт окно: SDL_Window с флагами из cfg -> размеры/позиция/иконка -> рендерер (с реестром
// живых рендереров) -> набор шрифтов из общего кэша (get_or_load_fonts) -> RenderContext ->
// HiDPI (init_hidpi; при HiDPI шрифты пересоздаются под физический размер). Ошибки SDL
// возвращаются как error, при этом уже созданные ресурсы освобождаются. Размер "по содержимому"
// (width/height <= 0): окно создаётся скрытым с временным размером 640x480, а на экран его
// выводит первая раскладка (fit_min_size).
pub fn create_window(cfg WindowConfig) !&Window {
	px := if cfg.x < 0 { sdl_windowpos_centered } else { cfg.x }
	py := if cfg.y < 0 { sdl_windowpos_centered } else { cfg.y }

	// SDL3: window flags are u64; no SDL_WINDOW_SHOWN (windows shown by default)
	mut flags := u64(0)
	if !cfg.visible {
		flags = flags | sdl_window_hidden
	}
	if cfg.high_dpi {
		flags = flags | sdl_window_high_pixel_density
	}
	if cfg.borderless {
		flags = flags | sdl_window_borderless
	}

	match cfg.mode {
		.resizable {
			flags = flags | sdl_window_resizable
		}
		.fixed {}
		.fullscreen {
			flags = flags | sdl_window_fullscreen
		}
		.borderless {
			flags = flags | sdl_window_borderless
		}
		.borderless_resizable {
			flags = flags | sdl_window_borderless | sdl_window_resizable
		}
	}

	// Размер по содержимому: до первой раскладки - временный, окно
	// скрыто (не мигает чужим размером), fit_min_size покажет его
	auto_size := cfg.width <= 0 || cfg.height <= 0
	cw := if cfg.width > 0 { cfg.width } else { 640 }
	ch := if cfg.height > 0 { cfg.height } else { 480 }
	if auto_size {
		flags = flags | sdl_window_hidden
	}
	// SDL3: SDL_CreateWindow(title, w, h, flags) — no x,y in creation
	win := C.SDL_CreateWindow(cfg.title.str, cw, ch, flags)
	if win == unsafe { nil } {
		err_msg := unsafe { cstring_to_vstring(C.SDL_GetError()) }
		return error('Window: SDL_CreateWindow failed: ${err_msg}')
	}

	// Position after creation
	if cfg.x >= 0 || cfg.y >= 0 {
		C.SDL_SetWindowPosition(win, px, py)
	}

	if cfg.min_width > 0 && cfg.min_height > 0 {
		C.SDL_SetWindowMinimumSize(win, cfg.min_width, cfg.min_height)
	}
	if cfg.max_width > 0 && cfg.max_height > 0 {
		C.SDL_SetWindowMaximumSize(win, cfg.max_width, cfg.max_height)
	}

	// Icon
	if cfg.icon_path.len > 0 {
		icon_surface := C.IMG_Load(cfg.icon_path.str)
		if unsafe { icon_surface != nil } {
			C.SDL_SetWindowIcon(win, icon_surface)
			C.SDL_DestroySurface(icon_surface)
		}
	}

	// Драйвер рендерера выбирает SDL (name = nil).
	ren := C.SDL_CreateRenderer(win, unsafe { nil })
	if ren == unsafe { nil } {
		C.SDL_DestroyWindow(win)
		err_msg := unsafe { cstring_to_vstring(C.SDL_GetError()) }
		return error('Window: SDL_CreateRenderer failed: ${err_msg}')
	}
	C.SDL_SetRenderDrawBlendMode(ren, sdl_blendmode_blend)
	register_renderer(ren)
	// VSync по WindowConfig.vsync (по умолчанию выключен: частоту кадров задаёт цикл App).
	C.SDL_SetRenderVSync(ren, if cfg.vsync { 1 } else { 0 })

	shared_fonts_ptr := get_or_load_fonts(window_font_config(cfg, cfg.font_size, cfg.mono_size)) or {
		C.SDL_DestroyRenderer(ren)
		C.SDL_DestroyWindow(win)
		return error('Window: Failed to init fonts: ${err}')
	}

	mut rc := RenderContext{
		renderer:      ren
		theme:         cfg.theme or { light_theme() }
		fonts:         unsafe { shared_fonts_ptr }
		screen_width:  f32(cw)
		screen_height: f32(ch)
	}

	if cfg.high_dpi {
		rc.init_hidpi(win)
	}

	// Текстовый ввод SDL не включается сразу: только пока он нужен
	// виджету в фокусе (sync_text_input) - иначе метод ввода (IBus) забирает
	// буквы как текст и однобуквенные сочетания клавиш не доходят

	wid := C.SDL_GetWindowID(win)

	mut w := &Window{
		sdl_window:     win
		sdl_id:         wid
		renderer:       ren
		ctx:            rc
		config:         WindowConfig{
			...cfg
			width:  cw
			height: ch
		}
		open:           cfg.visible
		visible:        cfg.visible
		fonts_held:     true
		theme_explicit: cfg.theme != none
		auto_size:      auto_size
	}
	if rc.dpi_info.is_hidpi {
		w.reload_scaled_fonts()
	}
	// Инвариант: create_window не сохраняет адрес w ни в SDL (свойства окна, hit-test), ни
	// в глобальных реестрах - create_dialog копирует окно по значению, и сохранённый адрес
	// указывал бы на брошенный оригинал. Такая регистрация - только после создания.
	return w
}

// window_font_config builds the g_font_cache request for this window's fonts
// opened at the given (physical) sizes.
fn window_font_config(cfg WindowConfig, size int, mono_size int) FontConfig {
	return FontConfig{
		regular_path:     cfg.font_path
		bold_path:        cfg.bold_path
		italic_path:      cfg.italic_path
		bold_italic_path: cfg.bold_italic_path
		mono_path:        cfg.mono_path
		mono_bold_path:   cfg.mono_bold_path
		size:             size
		mono_size:        mono_size
		font_data:        cfg.font_data
		bold_data:        cfg.bold_data
		italic_data:      cfg.italic_data
		bold_italic_data: cfg.bold_italic_data
		mono_data:        cfg.mono_data
		mono_bold_data:   cfg.mono_bold_data
	}
}

// reload_scaled_fonts switches the window to the FontSet matching its current
// dpi_scale * ui_scale. The new set is acquired BEFORE the old one is released,
// so staying at the same scale never closes and reopens the fonts, and the old
// set is freed only if no other window still holds it. On load failure the
// window keeps its current fonts.
fn (mut w Window) reload_scaled_fonts() {
	s := w.ctx.dpi_scale * w.ctx.ui_scale
	scaled_font := int(f32(w.config.font_size) * s + 0.5)
	scaled_mono := int(f32(w.config.mono_size) * s + 0.5)
	new_fonts := get_or_load_fonts(window_font_config(w.config, scaled_font, scaled_mono)) or {
		return
	}
	old_fonts := voidptr(w.ctx.fonts)
	w.ctx.fonts = new_fonts
	if w.fonts_held {
		release_fonts(old_fonts)
	}
	w.fonts_held = true
}

// Добавляет корневой виджет. Виджет не копируется и не освобождается окном; владельцем остаётся
// вызывающий код. Раскладка выполнится при ближайшей перерисовке (размер корню выдаётся в arrange()).
pub fn (mut w Window) add_widget(widget &Widget) {
	w.widgets << widget
}

// Меняет заголовок окна (и запоминает в config).
pub fn (mut w Window) set_title(title string) {
	w.config.title = title
	C.SDL_SetWindowTitle(w.sdl_window, title.str)
}

// Загружает иконку окна из файла; при ошибке загрузки молча ничего не делает.
pub fn (mut w Window) set_icon(path string) {
	icon_surface := C.IMG_Load(path.str)
	if unsafe { icon_surface != nil } {
		C.SDL_SetWindowIcon(w.sdl_window, icon_surface)
		C.SDL_DestroySurface(icon_surface)
	}
}

// show - показать скрытое окно (hide, сворачивание в трей). Новое окно
// и так видимо - звать show() после create_window не нужно.
pub fn (mut w Window) show() {
	w.visible = true
	w.open = true
	w.minimized = false
	if w.auto_size {
		// Окно «по содержимому» ещё не разложено: на экран его выведет
		// первая раскладка уже в своём размере (fit_min_size)
		return
	}
	C.SDL_ShowWindow(w.sdl_window)
	// A window may be both hidden and minimized; ShowWindow alone leaves a
	// minimized window invisible, so restore it before raising.
	flags := C.SDL_GetWindowFlags(w.sdl_window)
	if (flags & sdl_window_minimized) != 0 {
		C.SDL_RestoreWindow(w.sdl_window)
	}
	C.SDL_RaiseWindow(w.sdl_window)
	w.render()
}

// Скрывает окно (open остаётся true - окно "живо", его можно показать через show()).
pub fn (mut w Window) hide() {
	w.visible = false
	C.SDL_HideWindow(w.sdl_window)
}

// Свернуть / восстановить / развернуть окно. Флаги minimized/maximized выставляются сразу, затем
// их уточняют события SDL (App.handle_window_state_event).
pub fn (mut w Window) minimize() {
	C.SDL_MinimizeWindow(w.sdl_window)
	w.minimized = true
}

pub fn (mut w Window) restore() {
	C.SDL_RestoreWindow(w.sdl_window)
	w.minimized = false
	w.maximized = false
}

pub fn (mut w Window) maximize() {
	C.SDL_MaximizeWindow(w.sdl_window)
	w.maximized = true
}

// Включает/выключает полноэкранный режим; при выключении config.mode становится resizable.
pub fn (mut w Window) set_fullscreen(on bool) {
	C.SDL_SetWindowFullscreen(w.sdl_window, on)
	w.config.mode = if on { WindowMode.fullscreen } else { WindowMode.resizable }
}

// Переключает режим окна на лету, переставляя флаги SDL (полноэкранность, рамка, изменяемость
// размера) и синхронизируя config.mode / config.borderless.
pub fn (mut w Window) set_mode(mode WindowMode) {
	match mode {
		.resizable {
			C.SDL_SetWindowFullscreen(w.sdl_window, false)
			C.SDL_SetWindowBordered(w.sdl_window, true)
			C.SDL_SetWindowResizable(w.sdl_window, true)
			w.config.mode = .resizable
			w.config.borderless = false
		}
		.fixed {
			C.SDL_SetWindowFullscreen(w.sdl_window, false)
			C.SDL_SetWindowBordered(w.sdl_window, true)
			C.SDL_SetWindowResizable(w.sdl_window, false)
			w.config.mode = .fixed
			w.config.borderless = false
		}
		.fullscreen {
			C.SDL_SetWindowFullscreen(w.sdl_window, true)
			w.config.mode = .fullscreen
		}
		.borderless {
			C.SDL_SetWindowFullscreen(w.sdl_window, false)
			C.SDL_SetWindowBordered(w.sdl_window, false)
			C.SDL_SetWindowResizable(w.sdl_window, false)
			w.config.mode = .borderless
			w.config.borderless = true
		}
		.borderless_resizable {
			C.SDL_SetWindowFullscreen(w.sdl_window, false)
			C.SDL_SetWindowBordered(w.sdl_window, false)
			C.SDL_SetWindowResizable(w.sdl_window, true)
			w.config.mode = .borderless_resizable
			w.config.borderless = true
		}
	}
}

// Включает/выключает безрамочный режим. При включении подключается hit-test с зоной изменения
// размера 6 px по краям (enable_borderless_resize), при выключении - отключается.
pub fn (mut w Window) set_borderless(on bool) {
	C.SDL_SetWindowBordered(w.sdl_window, !on)
	w.config.borderless = on
	if on {
		w.enable_borderless_resize(6)
	} else {
		w.disable_borderless_hittest()
	}
}

pub fn (w &Window) is_borderless() bool {
	return w.config.borderless
}

// Задаёт размер окна в логических единицах vgui - тех же, что у виджетов и config.width/
// height: окно SDL получает размер × ui_scale. Раньше значения уходили в SDL как есть, и при
// ui_scale != 1 окно (в том числе после fit_to_content, передающего размер из measure())
// получалось меньше содержимого.
pub fn (mut w Window) set_size(width int, height int) {
	scale := w.ctx.ui_scale
	C.SDL_SetWindowSize(w.sdl_window, int(f32(width) * scale + 0.5), int(f32(height) * scale + 0.5))
	w.config.width = width
	w.config.height = height
	w.ctx.screen_width = f32(width)
	w.ctx.screen_height = f32(height)
}

// apply_sdl_size записывает размер окна SDL (sdl_w x sdl_h) как логический: config.width/
// height и screen_width/height = SDL-размер / ui_scale. Единая точка для событий окна
// (развернуть, восстановить) и первой раскладки по содержимому: раньше часть путей писала в
// config SDL-размер, и set_ui_scale потом считал от неверной базы.
pub fn (mut w Window) apply_sdl_size(sdl_w int, sdl_h int) {
	scale := if w.ctx.ui_scale > 0 { w.ctx.ui_scale } else { f32(1) }
	w.ctx.screen_width = f32(sdl_w) / scale
	w.ctx.screen_height = f32(sdl_h) / scale
	w.config.width = int(w.ctx.screen_width + 0.5)
	w.config.height = int(w.ctx.screen_height + 0.5)
}

// measure_content — сколько места просят корневые виджеты
// окна: максимум по их measure(). Шрифты уже загружены в
// create_window, поэтому размер известен до первой
// отрисовки.
pub fn (w &Window) measure_content() SizeHint {
	mut r := SizeHint{}
	// Все корни — один проход измерения (measure_cache.v).
	measure_pass_enter()
	defer {
		measure_pass_leave()
	}
	for widget in w.widgets {
		h := measure_widget(widget, &w.ctx)
		r.w = max_f32(r.w, h.w)
		r.h = max_f32(r.h, h.h)
		r.min_w = max_f32(r.min_w, h.min_w)
		r.min_h = max_f32(r.min_h, h.min_h)
	}
	return r
}

// fit_to_content подгоняет окно под размер содержимого —
// то, ради чего и нужна фаза измерения: диалог сам находит
// свой размер, вместо подобранных вручную width/height.
//
// Размер зажимается между min_width/min_height конфига и
// max_w/max_h (0 = без верхней границы).
pub fn (mut w Window) fit_to_content(max_w int, max_h int) {
	hint := w.measure_content()
	if hint.w <= 0 && hint.h <= 0 {
		return
	}
	mut cw := int(hint.w)
	mut ch := int(hint.h)
	if cw < w.config.min_width {
		cw = w.config.min_width
	}
	if ch < w.config.min_height {
		ch = w.config.min_height
	}
	if max_w > 0 && cw > max_w {
		cw = max_w
	}
	if max_h > 0 && ch > max_h {
		ch = max_h
	}
	w.set_size(cw, ch)
}

// Позиция окна на экране в пикселях; center() - по центру дисплея, на котором окно сейчас
// (раньше - всегда основного: окно на втором мониторе прыгало на первый).
pub fn (mut w Window) set_position(x int, y int) {
	C.SDL_SetWindowPosition(w.sdl_window, x, y)
}

pub fn (mut w Window) center() {
	mut pos := sdl_windowpos_centered
	if w.sdl_window != unsafe { nil } {
		id := C.SDL_GetDisplayForWindow(w.sdl_window)
		if id != 0 {
			// SDL_WINDOWPOS_CENTERED_DISPLAY(id)
			pos = int(u32(sdl_windowpos_centered) | id)
		}
	}
	C.SDL_SetWindowPosition(w.sdl_window, pos, pos)
}

// Закрывает окно: помечает его не открытым и скрытым, прячет SDL-окно и вызывает on_close.
// Ресурсы SDL при этом НЕ освобождаются - это делает cleanup() (App.cleanup / вызывающий код).
pub fn (mut w Window) close() {
	w.open = false
	w.visible = false
	if unsafe { w.sdl_window != nil } {
		C.SDL_HideWindow(w.sdl_window)
	}
	if w.on_close != unsafe { nil } {
		w.on_close(mut w)
	}
}

// Поднимает окно поверх остальных.
pub fn (mut w Window) raise() {
	C.SDL_RaiseWindow(w.sdl_window)
}

// on_drop_file/on_drop_text fire when a file path or text is dropped onto the
// window from outside. They are the fallback target: a DropZone widget under
// the cursor gets first refusal, and only an unconsumed drop reaches here.
pub fn (mut w Window) set_on_drop_file(cb fn (path string)) {
	w.on_drop_file = cb
}

pub fn (mut w Window) set_on_drop_text(cb fn (text string)) {
	w.on_drop_text = cb
}

// Буфер обмена: чтение возвращает пустую строку, если там нет текста; память SDL освобождается здесь.
pub fn (w &Window) get_clipboard() string {
	ptr := C.SDL_GetClipboardText()
	if ptr == unsafe { nil } {
		return ''
	}
	text := unsafe { cstring_to_vstring(ptr) }
	C.SDL_free(ptr)
	return text
}

pub fn (w &Window) set_clipboard(text string) {
	C.SDL_SetClipboardText(text.str)
}

// set_theme задаёт окну собственную тему: после этого тема приложения
// (App.set_theme) его больше не меняет.
pub fn (mut w Window) set_theme(theme Theme) {
	w.theme_explicit = true
	w.apply_theme(theme)
}

// apply_theme меняет тему, не делая её явной - путь темы приложения.
fn (mut w Window) apply_theme(theme Theme) {
	w.ctx.theme = theme
	w.config.theme = theme
	w.ctx.clear_text_cache()
}

// invalidate/invalidate_all — thin wrappers over the RenderContext dirty
// region, so callers can invalidate through the Window without reaching
// into ctx directly.
//
// ctx.invalidate() returns whether the rect was actually accepted (false =
// degenerate, or clamped away to nothing against the window's screen
// bounds); this wrapper deliberately DROPS that value and stays `void`, all
// the way out to vgui_window_invalidate and Python's Window.invalidate.
// The distinction is only meaningful inside the engine, where mark_anim_rect
// gates needs_animation on it (see render_context.v). For an outside caller
// saying "this area changed" there is nothing to act on either way: if the
// rect fell off-screen, there are no pixels there to repaint, and the frame
// is already as correct as it can be. Don't thread the bool outward on the
// theory that a caller might want to retry — there is nothing to retry.
pub fn (mut w Window) invalidate(r Rect) {
	w.ctx.invalidate(r)
}

// Помечает весь кадр как требующий перерисовки.
pub fn (mut w Window) invalidate_all() {
	w.ctx.invalidate_all()
}

// Передаёт фокус полю ввода / кнопке (например, при открытии диалога) и синхронизирует
// текстовый ввод SDL.
pub fn (mut w Window) set_default_focus_text_input(ti &TextInput) {
	w.ctx.focus.focus_text_input(ti, ti.focus_group)
	w.sync_text_input()
}

pub fn (mut w Window) set_default_focus_button(b &Button) {
	w.ctx.focus.focus_button(b, b.focus_group)
}

// ─── Internal: render & events (called by App) ───

// ensure_render_target (re)creates the persistent render target when it is
// missing, stale (renderer died/was replaced — ABA-guarded via generation,
// same rationale as ImageView's texture; see PROJECT.md), or the window's
// physical pixel size changed. Returns true if the target was (re)created,
// which forces the next frame to be drawn full (a fresh/resized texture has
// undefined/wrong-sized content).
//
// Sized in PHYSICAL pixels deliberately: every widget in this codebase draws
// in LOGICAL coordinates and relies on SDL_SetRenderScale (combined =
// dpi_scale * ui_scale) to remap those onto the physical pixel grid. In SDL3
// the render scale (like the viewport/cliprect) is stored PER RENDER TARGET —
// it does NOT carry over automatically when SDL_SetRenderTarget switches to
// this texture. render() re-applies it explicitly every time it binds w.rt
// (see the SDL_SetRenderScale call right after SDL_SetRenderTarget below).
// This texture is sized to match the physical size SDL would otherwise give
// the default backbuffer (SDL_GetWindowSizeInPixels) so that, once the scale
// is (re-)applied, widgets drawing in logical coordinates fill it exactly,
// and the final blit to the backbuffer is a plain 1:1 pixel copy.
fn (mut w Window) ensure_render_target() bool {
	mut phys_w := 0
	mut phys_h := 0
	C.SDL_GetWindowSizeInPixels(w.sdl_window, &phys_w, &phys_h)

	cur_gen := renderer_generation(w.renderer)

	// If we already tried and failed to create rt for this EXACT
	// (renderer generation, physical size) combination, don't retry every
	// single frame — that would hammer SDL_CreateTexture (and spam
	// SDL_GetError) forever with no chance of a different outcome, since
	// nothing relevant has changed since the last attempt. render() already
	// forces a full frame whenever w.rt is nil regardless of this function's
	// return value (see `full :=` in render(), `w.rt == unsafe { nil }`
	// clause), so widgets keep drawing — just directly onto the backbuffer
	// at 1:1 — this guard only stops the pointless repeated allocation
	// attempt, not that fallback path.
	if w.rt == unsafe { nil } && w.rt_create_failed && w.rt_gen == cur_gen && w.rt_w == phys_w
		&& w.rt_h == phys_h {
		return false
	}

	stale := w.rt == unsafe { nil } || w.rt_gen != cur_gen || w.rt_w != phys_w || w.rt_h != phys_h
	if !stale {
		return false
	}
	if w.rt != unsafe { nil } && is_renderer_alive_gen(w.renderer, w.rt_gen) {
		C.SDL_DestroyTexture(w.rt)
	}
	w.rt = unsafe { nil }
	w.rt_w = phys_w
	w.rt_h = phys_h
	w.rt_gen = cur_gen
	w.rt_create_failed = false
	if phys_w > 0 && phys_h > 0 {
		w.rt = C.SDL_CreateTexture(w.renderer, sdl_pixelformat_abgr8888, sdl_textureaccess_target,
			phys_w, phys_h)
		if w.rt != unsafe { nil } {
			C.SDL_SetTextureScaleMode(w.rt, sdl_scalemode_nearest)
			// none, not blend: the final blit to the backbuffer (see render())
			// is meant to be a plain copy of rt's content, not a composite over
			// whatever the backbuffer previously held. With blend mode, any
			// pixel in rt with alpha < 255 (e.g. a semi-transparent overlay
			// background) would accumulate on top of the previous frame's
			// backbuffer forever, since the backbuffer itself is never cleared
			// (SDL_RenderClear only ever targets rt).
			C.SDL_SetTextureBlendMode(w.rt, sdl_blendmode_none)
		} else {
			w.rt_create_failed = true
		}
	} else {
		// Zero-sized window (minimized, etc.) — nothing to create yet; not a
		// real failure, but the same "don't retry until something changes"
		// logic applies once the size/gen stay put.
		w.rt_create_failed = true
	}
	return true
}

// arrange — фаза arrange окна (PROJECT.md, «Фаза arrange»): при изменении
// размера корням выставляется весь экран, затем рекурсивно раскладывается всё
// дерево. Снимает ctx.layout_dirty.
fn (mut w Window) arrange() {
	// Один проход измерения на весь arrange: кэш SizeHint
	// (measure_cache.v) живёт от этой точки до конца обхода.
	measure_pass_begin()
	if w.ctx.screen_width != w.arranged_w || w.ctx.screen_height != w.arranged_h {
		screen_rect := Rect{0, 0, w.ctx.screen_width, w.ctx.screen_height}
		for mut widget in w.widgets {
			set_widget_bounds(mut widget, screen_rect)
		}
		w.arranged_w = w.ctx.screen_width
		w.arranged_h = w.ctx.screen_height
	}
	g_relayout = false
	w.ctx.arrange_depth = 0
	for mut widget in w.widgets {
		arrange_widget(mut widget, mut w.ctx)
	}
	if g_relayout {
		// Метки с переносом получили новую ширину - их высоты другие:
		// второй проход (свежий кэш измерений) раскладывает по ним
		g_relayout = false
		measure_pass_begin()
		w.ctx.arrange_depth = 0
		for mut widget in w.widgets {
			arrange_widget(mut widget, mut w.ctx)
		}
		g_relayout = false
	}
	w.ctx.layout_dirty = false
	w.fit_min_size()
}

// fit_min_size - минимальный размер окна не меньше минимального размера
// содержимого (measure_content: сумма min детей, без растягивания):
// SDL не даст уменьшить окно так, чтобы содержимое уехало за край, а
// окно, которое уже меньше (мал размер в create_window, сменился шрифт
// или масштаб), увеличивается. Зовётся в конце arrange - внутри того
// же прохода измерения, поэтому почти бесплатно.
fn (mut w Window) fit_min_size() {
	if unsafe { w.sdl_window == nil } {
		return
	}
	hint := w.measure_content()
	scale := if w.ctx.ui_scale > 0 { w.ctx.ui_scale } else { f32(1) }
	mw := max_int(w.config.min_width, int(hint.min_w * scale + 0.999))
	mh := max_int(w.config.min_height, int(hint.min_h * scale + 0.999))
	if w.auto_size && w.widgets.len > 0 {
		// Первая раскладка окна «по содержимому»: размер - желаемый
		// размер содержимого, не меньше минимального; окно - по центру
		// и только теперь на экран
		w.auto_size = false
		w.content_min_w = mw
		w.content_min_h = mh
		C.SDL_SetWindowMinimumSize(w.sdl_window, mw, mh)
		// Не уже заголовка окна с кнопками рамки (~150 px): иначе
		// оконный менеджер обрежет его многоточием
		font := w.ctx.get_font_immut(.regular, 0)
		title_w := int((w.ctx.measure_text_with_font(w.config.title, font).x + 150) * scale)
		sw := max_int(max_int(mw, title_w), int(hint.w * scale + 0.999))
		sh := max_int(mh, int(hint.h * scale + 0.999))
		C.SDL_SetWindowSize(w.sdl_window, sw, sh)
		w.apply_sdl_size(sw, sh)
		if w.config.x < 0 && w.config.y < 0 {
			C.SDL_SetWindowPosition(w.sdl_window, sdl_windowpos_centered, sdl_windowpos_centered)
		}
		if w.visible {
			C.SDL_ShowWindow(w.sdl_window)
		}
		return
	}
	if mw == w.content_min_w && mh == w.content_min_h {
		return
	}
	w.content_min_w = mw
	w.content_min_h = mh
	// Окно фиксированного размера (диалог: min = max) тоже растёт под
	// содержимое - верхняя граница не ниже нижней
	mut xw := 0
	mut xh := 0
	C.SDL_GetWindowMaximumSize(w.sdl_window, &xw, &xh)
	if (xw > 0 && xw < mw) || (xh > 0 && xh < mh) {
		C.SDL_SetWindowMaximumSize(w.sdl_window, if xw > 0 { max_int(xw, mw) } else { 0 },
			if xh > 0 { max_int(xh, mh) } else { 0 })
	}
	C.SDL_SetWindowMinimumSize(w.sdl_window, mw, mh)
	mut ww := 0
	mut wh := 0
	C.SDL_GetWindowSize(w.sdl_window, &ww, &wh)
	if ww < mw || wh < mh {
		C.SDL_SetWindowSize(w.sdl_window, max_int(ww, mw), max_int(wh, mh))
	}
}

// arrange_if_needed — ленивый arrange: только если раскладку просили
// (invalidate*/request_layout) или изменился размер окна.
fn (mut w Window) arrange_if_needed() {
	if w.ctx.layout_dirty || w.ctx.screen_width != w.arranged_w
		|| w.ctx.screen_height != w.arranged_h {
		w.arrange()
	}
}

// Один кадр окна. Шаги: (1) сброс флага анимации и расчёт anim_dt; (2) пропуск, если окно
// закрыто/скрыто; (3) подготовка render-цели rt; (4) решение, какой кадр рисовать: полный
// (full), частичный по dirty-прямоугольнику или никакой (skip_draw - ничего не изменилось);
// (5) arrange; (6) очистка фона и отрисовка корневых виджетов (при частичном кадре - в клипе
// dirty-прямоугольника); (7) подложка модального диалога, оверлей, тултипы - поверх всего
// и без клипа, поэтому их наличие форсирует полный кадр; (8) копирование rt в окно и
// SDL_RenderPresent - каждый кадр, даже пропущенный. Подробные причины каждого шага -
// в комментариях внутри.
fn (mut w Window) render() {
	w.sync_text_input()
	// Reset needs_animation/anim_reason FIRST — before the visibility
	// early-return below, and unconditionally (i.e. also on the skip_draw
	// fast path further down). Two separate holes are closed here:
	//
	//  - Hidden window: a window hidden (hide(), or closed to tray) while the
	//    flag was set never reaches the rest of render(), so a reset placed
	//    any later never runs — and run()'s any_anim check only skips windows
	//    with open == false, not invisible ones. The loop would then spin at
	//    60fps forever redrawing nothing. Showing the window again goes
	//    through an input event → invalidate_all() → a full frame, so nothing
	//    is lost by clearing the flag while hidden.
	//  - skip_draw: with the guards now in mark_anim_rect (is_in_clip +
	//    invalidate()'s return value, see render_context.v) needs_animation
	//    should never be true while the dirty region is empty, but this reset
	//    is the last line of defense against a future call site that sets it
	//    raw (`ctx.needs_animation = true`) without going through them.
	//
	// See PROJECT.md, "needs_animation залипает навсегда". Nothing between
	// here and the widget draw loop sets the flag, so moving the reset up has
	// no effect on this frame's decisions — widgets re-arm it from inside
	// their own draw() (e.g. TextInput's cursor blink), which runs later.
	// Шаг анимаций этого кадра (Anim, anim.v) — по часам, а не «доля за
	// кадр». Настоящий интервал берётся, только если прошлый кадр
	// анимировался (флаг ещё не сброшен строкой ниже): после простоя
	// интервал — это секунды тишины, и анимация, начавшаяся сейчас,
	// перепрыгнула бы в конец. Поэтому первый её кадр — номинальный.
	now_ms := C.SDL_GetTicks()
	w.ctx.anim_dt = if w.ctx.anim_fixed_dt > 0 {
		w.ctx.anim_fixed_dt
	} else if w.ctx.needs_animation && w.ctx.anim_last_ms > 0 {
		clamp_f32(f32(now_ms - w.ctx.anim_last_ms), 0, anim_max_dt)
	} else {
		anim_nominal_dt
	}
	w.ctx.anim_last_ms = now_ms

	w.ctx.needs_animation = false
	w.ctx.anim_reason = ''

	if !w.open || !w.visible {
		return
	}

	rt_recreated := w.ensure_render_target()

	// Reset the clip stack at the start of every frame. The partial-repaint
	// branch below balances its own push_clip()/pop_clip() pair, but a
	// widget with an unbalanced push_clip() (an early return between its own
	// push and pop) would otherwise leave a stale entry that progressively
	// shrinks the effective clip on every subsequent frame.
	w.ctx.clip_stack.clear()

	screen_rect := Rect{0, 0, w.ctx.screen_width, w.ctx.screen_height}
	size_changed := w.ctx.screen_width != w.last_layout_w || w.ctx.screen_height != w.last_layout_h

	// Snapshots taken BEFORE the widget draw loop — used only to decide
	// whether this frame must be FULL. A widget's draw() can legitimately
	// change either condition while the loop runs (e.g. ComboBox/ContextMenu
	// clearing ctx.overlay_cb on focus loss, or a Tooltip enqueueing itself
	// from inside draw() — see tooltip.v), so the actual post-loop drawing
	// decision below is taken from the live state, not these snapshots.
	tooltips_active_before := w.ctx.pending_tooltips.len > 0
	overlay_active_before := w.ctx.overlay_cb != unsafe { nil }

	// A frame is FULL when: the render target was just (re)created (fresh
	// texture, undefined content); the window resized; something explicitly
	// asked for a full frame (ctx.dirty.full, e.g. via mark_anim); or an
	// overlay/tooltip/modal-backdrop is active THIS or was active the
	// PREVIOUS frame — those paint outside any widget's own clip rect, so
	// opening or closing one leaves a ghost on the persistent target unless
	// the whole frame is repainted.
	full := rt_recreated || size_changed || w.ctx.dirty.full || overlay_active_before
		|| tooltips_active_before || w.has_modal_child || w.prev_overlayish || w.rt == unsafe { nil }

	// Nothing-changed fast path: no forcing condition fired and no rect was
	// accumulated since the last frame, so the persistent target's existing
	// content is already correct — there is nothing for the widget tree to
	// redraw. Only re-blit + present (still needed, e.g. after the window
	// was uncovered). Must be decided from THIS frame's accumulated dirt,
	// before it is cleared below.
	skip_draw := !full && w.ctx.dirty.is_empty()

	// Фаза arrange — до отрисовки, отдельно от неё. Кадр, который рисуется,
	// раскладывает дерево всегда (как раньше делал draw() каждого контейнера)
	// и получает новый frame_no — по нему анимации в arrange() шагают раз за
	// кадр. skip_draw-кадр раскладывает, только если раскладку просили, и
	// кадр не считает: дерево не рисуется, анимациям шагать не на что.
	if skip_draw {
		w.arrange_if_needed()
	} else {
		w.ctx.frame_no++
		w.arrange()
	}

	// dirty_rect is captured before dirty.clear() below — it's the region
	// accumulated by EVENTS/animation requests made since the previous
	// frame, i.e. what THIS frame's partial repaint must cover.
	dirty_rect := w.ctx.dirty.union_rect()

	// Consume this frame's accumulated dirt now — BEFORE calling into
	// widgets' draw() below. Widgets request repaint of specific rects FROM
	// INSIDE their own draw() (e.g. TextInput's cursor blink via
	// mark_anim_rect) to mean "redraw me again next frame". Clearing AFTER
	// the draw loop (as this code used to) discarded those requests the
	// instant they were made, so every such animation froze after its first
	// frame. Clearing here means marks made during the draw loop below
	// survive to decide the NEXT frame, while this frame's own full/
	// dirty_rect decision (above) is unaffected, since it was already taken.
	w.ctx.dirty.clear()

	// (needs_animation/anim_reason were already reset at the very top of this
	// function — see the comment there for why it has to happen before the
	// visibility early-return.)

	bg := w.ctx.theme.bg
	combined := w.ctx.dpi_scale * w.ctx.ui_scale

	if !skip_draw {
		if w.rt != unsafe { nil } {
			C.SDL_SetRenderTarget(w.renderer, w.rt)
		}
		// Render scale is per-target in SDL3 (see ensure_render_target's
		// comment) — it must be re-applied every time we're about to draw,
		// regardless of whether w.rt is bound. It is set unconditionally here
		// (not only inside the `w.rt != nil` branch above) because the
		// backbuffer's own scale was reset to 1:1 at the end of the PREVIOUS
		// frame's blit (see the SDL_SetRenderScale(1,1) below), and when
		// texture creation fails (w.rt == nil, an aborted-but-still-drawn
		// fallback — `full` is forced true for exactly this case), widgets
		// draw directly onto that backbuffer. Without this, that fallback
		// path silently rendered the whole UI at 1:1 in physical pixels
		// instead of the intended logical/scaled size.
		C.SDL_SetRenderScale(w.renderer, combined, combined)

		if full {
			C.SDL_SetRenderClipRect(w.renderer, unsafe { nil })
			C.SDL_SetRenderDrawColor(w.renderer, bg.r, bg.g, bg.b, bg.a)
			C.SDL_RenderClear(w.renderer)
		} else {
			// Partial repaint: clear only the accumulated dirty rectangle, then
			// draw the whole tree with that rectangle pushed onto ctx's OWN clip
			// stack (not just a raw SDL clip rect). This matters because many
			// widgets/containers call ctx.push_clip()/pop_clip() themselves
			// (Label, VBox/HBox, ScrollBox, ...), and push_clip() intersects
			// against clip_stack's current top — if the dirty rect had only been
			// set via a bare SDL_SetRenderClipRect call, clip_stack would still
			// look empty to them, so their own push_clip would compute a wider
			// rect and clobber ours, letting stale/duplicate pixels bleed in
			// outside the intended dirty area.
			w.ctx.push_clip(dirty_rect)
			// The rect actually cleared must match the rect the clip stack just
			// applied to the renderer, not the raw (unexpanded) dirty_rect:
			// push_clip()/clip_sdl_rect() inflate the clip by 1 logical pixel in
			// each direction (to cover sub-pixel edges/AA corners — see
			// clip_sdl_rect's comment in sdl3_render.v), and the clip stack was
			// just reset to empty at the top of this frame, so "actual" there
			// equals dirty_rect verbatim. Clearing only the narrower raw
			// dirty_rect left a 1px ring inside the (wider) clip where drawing
			// is allowed but the old frame's pixels were never wiped.
			clip_sdl := clip_sdl_rect(dirty_rect)
			// SDL_RenderClear (the full-frame branch above) always writes the
			// draw color verbatim, ignoring blend mode. This FillRect must match
			// that behavior explicitly — otherwise it inherits whatever blend
			// mode the previous frame's widget drawing left the renderer in, and
			// a non-opaque theme.bg would composite instead of replace.
			C.SDL_SetRenderDrawBlendMode(w.renderer, sdl_blendmode_none)
			C.SDL_SetRenderDrawColor(w.renderer, bg.r, bg.g, bg.b, bg.a)
			fdst := C.SDL_FRect{
				x: f32(clip_sdl.x)
				y: f32(clip_sdl.y)
				w: f32(clip_sdl.w)
				h: f32(clip_sdl.h)
			}
			C.SDL_RenderFillRect(w.renderer, &fdst)
			// Restore blend mode: it is global renderer state that persists
			// into the widget draw loop right below (and into subsequent
			// frames if left unrestored). Almost every render_* primitive in
			// sdl3_render.v sets sdl_blendmode_blend itself before drawing, but
			// spinner_draw_circle_arc (spinner.v) calls SDL_RenderGeometry
			// directly without doing so — leaving the mode at "none" here made
			// its semi-transparent background ring (alpha 60) get written
			// verbatim instead of blended, and that wrong content then got
			// blitted onto the backbuffer every subsequent frame (see the
			// SDL_SetTextureBlendMode note in ensure_render_target above).
			C.SDL_SetRenderDrawBlendMode(w.renderer, sdl_blendmode_blend)
		}

		w.ctx.pending_drag_rects.clear()
		w.ctx.pending_titlebar_rects.clear()

		if size_changed {
			// Сами bounds корням уже выставил arrange() выше.
			w.last_layout_w = w.ctx.screen_width
			w.last_layout_h = w.ctx.screen_height
		}
		// Background image (behind all widgets), filling the whole window.
		if w.bg_image != unsafe { nil } {
			w.bg_image.bounds = screen_rect
			w.bg_image.draw(mut w.ctx)
		}
		for mut widget in w.widgets {
			widget.draw(mut w.ctx)
		}

		if !full {
			// Balance the push_clip() above — clip_stack must be empty again
			// before the overlay/tooltip/modal sections below, which reset the
			// SDL clip directly and assume no leftover entries.
			w.ctx.pop_clip()
		}

		if w.hittest_data != unsafe { nil } {
			borderless_clear_drag_rects(&w)
			for r in w.ctx.pending_drag_rects {
				borderless_register_drag_rect(&w, r)
			}
			for r in w.ctx.pending_titlebar_rects {
				borderless_register_titlebar_rect(&w, r)
			}
		}

		// Dimming backdrop when a modal dialog is open over this window.
		if w.has_modal_child {
			C.SDL_SetRenderClipRect(w.renderer, unsafe { nil })
			w.ctx.fill_rect(screen_rect, w.ctx.theme.modal_backdrop_color)
		}

		// From here on, re-check live state instead of the pre-loop snapshots
		// above: the widget draw loop just ran and can have changed either.
		// overlay_cb in particular can go from set to nil DURING that loop —
		// e.g. ComboBox/ContextMenu clear it on focus loss (combo_box.v's
		// close_dropdown(), menu.v) — so calling it via the snapshot boolean
		// without re-checking the pointer itself risks a null call.
		if w.ctx.overlay_cb != unsafe { nil } {
			C.SDL_SetRenderClipRect(w.renderer, unsafe { nil })
			w.ctx.overlay_cb(mut w.ctx)
		}

		// Likewise re-read pending_tooltips live: Tooltip.draw() (called from
		// inside the widget loop above) is what enqueues it in the first
		// place (tooltip.v), so the pre-loop snapshot is always empty on the
		// very frame a tooltip first becomes due — using the snapshot here
		// delayed the tooltip by one frame and made it flicker on any frame
		// with concurrent animation.
		tooltips_now := w.ctx.pending_tooltips.len > 0
		if tooltips_now {
			C.SDL_SetRenderClipRect(w.renderer, unsafe { nil })
			for tip in w.ctx.pending_tooltips {
				tooltip_draw(tip, mut w.ctx)
			}
			w.ctx.pending_tooltips.clear()
		}

		w.prev_overlayish = (w.ctx.overlay_cb != unsafe { nil }) || tooltips_now || w.has_modal_child
	}

	// Blit the persistent render target to the window's real backbuffer and
	// present. This runs every frame regardless of full/partial/skip — even a
	// frame with nothing new still needs the backbuffer to show correct
	// content (e.g. after being uncovered/exposed). The default backbuffer's
	// render scale is reset to 1:1 here and dst is given in PHYSICAL pixels
	// (rt_w/rt_h, which is exactly rt's own size) — a direct, unscaled copy —
	// rather than relying on the logical/scale math lining up.
	C.SDL_SetRenderTarget(w.renderer, unsafe { nil })
	C.SDL_SetRenderScale(w.renderer, 1.0, 1.0)
	C.SDL_SetRenderClipRect(w.renderer, unsafe { nil })
	if w.rt != unsafe { nil } {
		fdst := C.SDL_FRect{
			x: 0
			y: 0
			w: f32(w.rt_w)
			h: f32(w.rt_h)
		}
		C.SDL_RenderTexture(w.renderer, w.rt, unsafe { nil }, &fdst)
	}
	C.SDL_RenderPresent(w.renderer)
}

// Точка входа события в окно (координаты мыши уже в логических единицах): передаёт событие в
// dispatch_event_inner, затем синхронизирует режим текстового ввода SDL (кроме mouse_move -
// движение мыши фокус не меняет).
fn (mut w Window) dispatch_event_with_app(ev &GuiEvent, app &App) {
	w.dispatch_event_inner(ev, app)
	// Второй и следующий быстрый клик: сначала обычное нажатие (выше), затем
	// mouse_dbl_click в той же точке. Раньше двойной клик приходил вместо
	// нажатия, и кнопка, слушающая только mouse_down, теряла второй клик.
	// Нажатие могло закрыть окно - dispatch_event_inner сам проверит w.open.
	if ev.typ == .mouse_down && ev.clicks >= 2 {
		mut dbl := *ev
		dbl.typ = .mouse_dbl_click
		w.dispatch_event_inner(&dbl, app)
	}
	// Фокус меняется кликом, клавишами, Tab - сверить нужду в текстовом
	// вводе после события (движение мыши фокус не меняет)
	if ev.typ != .mouse_move {
		w.sync_text_input()
	}
}

// sync_text_input включает текстовый ввод SDL, только пока он нужен
// (wants_text_input), и выключает в остальное время. Всегда включённый
// ввод отдаёт клавиши методу ввода (IBus, fcitx): буквы без модификаторов
// приходят только текстом, key_down для них нет, и однобуквенные
// сочетания (J в меню) не срабатывают. Зовётся после каждого события
// (кроме движения мыши) и в начале кадра - на случай смены фокуса из
// кода приложения.
pub fn (mut w Window) sync_text_input() {
	if unsafe { w.sdl_window == nil } {
		return
	}
	want := w.wants_text_input()
	if want == w.text_input_on {
		return
	}
	w.text_input_on = want
	if want {
		C.SDL_StartTextInput(w.sdl_window)
	} else {
		C.SDL_StopTextInput(w.sdl_window)
	}
}

// wants_text_input - кому-то в окне нужен текст: поле ввода, текстовая
// область или редактор кода в фокусе, правка узла дерева или свойства
// (FocusManager.wants_text), правка ячейки таблицы (своей записи в
// фокусе у TableView нет - ищется обходом дерева)
pub fn (w &Window) wants_text_input() bool {
	if w.ctx.focus.wants_text() {
		return true
	}
	mut probe := &TextProbe{}
	for wd in w.widgets {
		walk_widgets(wd, fn [mut probe] (x &Widget) {
			if x is TableView {
				if x.editing {
					probe.found = true
				}
			}
		})
		if probe.found {
			return true
		}
	}
	return false
}

// TextProbe - флаг обхода для wants_text_input (замыкание захватывает
// значения копией - флаг по указателю)
@[heap]
struct TextProbe {
mut:
	found bool
}

// Маршрутизация события: (1) актуализация раскладки; (2) оверлей (выпадающий список/меню)
// перехватывает событие первым; (3) корень с индексом focused; (4) остальные корни сверху вниз
// (последний добавленный - верхний), до первого обработавшего; (5) не обработанный key_down -
// горячие клавиши окна, затем приложения; (6) не обработанный drop - обработчик окна; (7)
// инвалидация: для mouse_move - точечная (invalidate_hover_change), для остального - полный кадр.
fn (mut w Window) dispatch_event_inner(ev &GuiEvent, app &App) {
	if !w.open {
		return
	}
	// Hit-test по свежей раскладке, а не по bounds прошлого кадра: предыдущее
	// событие (переключение вкладки, скролл, add в контейнер) взвело
	// layout_dirty через invalidate_all() в конце этой же функции.
	w.arrange_if_needed()
	if w.ctx.overlay_ev != unsafe { nil } {
		if w.ctx.overlay_ev(ev, app) {
			w.ctx.invalidate_all()
			return
		}
	}
	mut handled := false
	if w.focused >= 0 && w.focused < w.widgets.len {
		mut widget := w.widgets[w.focused]
		handled = widget.handle_event(ev, app)
	}
	if !handled {
		for i := w.widgets.len - 1; i >= 0; i-- {
			if i == w.focused {
				continue
			}
			mut widget := w.widgets[i]
			if widget.handle_event(ev, app) {
				handled = true
				break
			}
		}
	}
	if !handled && ev.typ == .key_down {
		if w.hotkeys.try_match(ev) {
			w.ctx.invalidate_all()
			return
		}
		if app.hotkeys.try_match(ev) {
			w.ctx.invalidate_all()
			return
		}
	}
	// Drop fallback: if no widget (drop zone) consumed the file/text, deliver
	// it to the window-level handler so a whole-window drop target still works.
	if !handled {
		if ev.typ == .drop_file && w.on_drop_file != unsafe { nil } {
			w.on_drop_file(ev.text)
		} else if ev.typ == .drop_text && w.on_drop_text != unsafe { nil } {
			w.on_drop_text(ev.text)
		}
	}

	// Прокрутка колесом сдвигает содержимое под неподвижным курсором, а
	// hover (подсветка кнопок, заголовков Accordion...) виджеты обновляют
	// только по mouse_move - подсветка осталась бы на старом месте до
	// следующего движения мыши. Синтетический mouse_move в текущей точке
	// курсора обновляет hover по новой раскладке (invalidate_all взводит
	// layout_dirty - рекурсивный вызов сначала переразложит окно).
	if handled && ev.typ == .mouse_wheel {
		w.ctx.invalidate_all()
		mv := GuiEvent{
			typ:     .mouse_move
			mouse_x: w.ctx.mouse_x
			mouse_y: w.ctx.mouse_y
		}
		w.dispatch_event_with_app(&mv, app)
		return
	}

	// mouse_move — единственное событие 60fps-частоты, и полный кадр на
	// каждое движение мыши сводил dirty regions на нет (аудит 3.C). Для него
	// отдельный, точечный путь; всё остальное (клики, клавиши, колесо,
	// drop) — по-прежнему полный кадр.
	if ev.typ == .mouse_move {
		w.invalidate_hover_change(ev)
		return
	}

	// Conservative default, matching pre-dirty-region behavior exactly: any
	// event (handled or not — a click that missed everything can still, say,
	// blur a focused widget) forces the next frame to be a full repaint.
	// Individual widgets can migrate to more precise invalidation the same
	// way TextInput's cursor blink did (see mark_anim_rect), but nothing
	// requires it, and event-driven full frames are cheap relative to
	// clicks/keys, which are not a 60fps hot path.
	//
	// This same invalidate_all() is ALSO called from the three early-return
	// branches above (overlay consumed the event; either hotkey table
	// matched) — a hotkey changing widget/label state must still force a
	// repaint even though it never reaches this line.
	w.ctx.invalidate_all()
}

// ═══════════════════════════════════════════════════════
// Точечная инвалидация hover (аудит 3.C)
//
// Наблюдение, на котором всё держится: mouse_move меняет вид РОВНО двух
// мест окна — виджета, который hover потерял, и виджета, который его
// получил. Остальное дерево на движение мыши не реагирует. Поэтому вместо
// invalidate_all() достаточно двух прямоугольников: сохранённого bounds
// прошлого виджета под курсором и bounds нынешнего.
//
// Почему этого достаточно, хотя vgui нигде не спрашивает у виджета «ты
// поменял вид?»: инвалидируется ВСЯ площадь виджета под курсором, что бы
// внутри неё ни подсвечивалось. Строка ListBox, вкладка TabBox, ячейка
// Calendar, кнопка спинбокса — всё это лежит внутри bounds своего виджета,
// а hit-тест (widget_at) спускается ровно по тем детям, которым arrange()
// выставил bounds в этом кадре (hit_children — см. widget_tree.v). Промах
// hit-теста в сторону контейнера безопасен: перерисуется больше нужного,
// но не меньше.
//
// Что НЕ покрывается двумя прямоугольниками — перечислено в
// hover_partial_ok(): такие кадры остаются полными.
//
// Осечка возможна ровно одна: виджет, не реализующий Layouted, для
// get_widget_bounds() имеет нулевой Rect, поэтому widget_at его не видит и
// hover над ним не инвалидирует ничего. Такой виджет и так рисуется в (0,0)
// нулевого размера (см. чек-лист «Добавление нового виджета» в PROJECT.md),
// то есть сломан задолго до hover'а.

// hover_partial_ok — можно ли обойтись двумя прямоугольниками вместо
// полного кадра. Каждое «нет» здесь — случай, когда движение мыши меняет
// пиксели ЗА пределами виджета под курсором:
//
//   - зажата кнопка мыши: идёт перетаскивание (ручка Slider, полоса
//     Splitter, выделение в TextArea/CodeEditor, панорама Canvas), и виджет
//     продолжает меняться, когда курсор давно вне его bounds;
//   - открыт оверлей (список ComboBox, ContextMenu, меню MenuButton) — он
//     рисуется поверх всего окна вне чьих-либо bounds;
//   - показан тултип или подложка модального диалога — то же самое.
//
// Оверлей/тултип/модалка дублируют условия, по которым render() и так
// делает кадр полным (см. `full :=` там), — здесь они перечислены заново,
// чтобы решение «этот кадр частичный» не зависело от того, что именно
// render() сочтёт полным кадром завтра.
fn (w &Window) hover_partial_ok(ev &GuiEvent) bool {
	if ev.mouse_buttons != 0 {
		return false
	}
	if w.ctx.overlay_cb != unsafe { nil } || w.ctx.overlay_ev != unsafe { nil } {
		return false
	}
	if w.has_modal_child || w.prev_overlayish {
		return false
	}
	return w.ctx.pending_tooltips.len == 0
}

// hover_target — самый верхний (по z-порядку) виджет под точкой и его
// bounds. Обход идёт по верхнеуровневым виджетам окна с конца: последний
// добавленный рисуется поверх, значит он же и перехватывает курсор.
// Видимость корня проверяется здесь — widget_at смотрит только на детей.
fn (w &Window) hover_target(x f32, y f32) (voidptr, Rect) {
	for i := w.widgets.len - 1; i >= 0; i-- {
		cw := w.widgets[i]
		if unsafe { cw == nil } {
			continue
		}
		if !widget_is_visible(cw) {
			continue
		}
		if found := widget_at(cw, x, y) {
			return voidptr(found), get_widget_bounds(found)
		}
	}
	return unsafe { nil }, Rect{}
}

// invalidate_hover_change — обработка mouse_move вместо invalidate_all().
//
// Учёт hover'а ведётся ВСЕГДА, даже когда кадр решено сделать полным:
// иначе после любого полного кадра hover_widget остался бы от позапрошлого
// движения, и первый же следующий частичный кадр перерисовал бы не тот
// прямоугольник.
fn (mut w Window) invalidate_hover_change(ev &GuiEvent) {
	ptr, rect := w.hover_target(ev.mouse_x, ev.mouse_y)
	prev_ptr := w.hover_widget
	prev_rect := w.hover_rect
	w.hover_widget = ptr
	w.hover_rect = rect

	if !w.hover_partial_ok(ev) {
		w.ctx.invalidate_all()
		return
	}

	// Прошлый виджет перерисовывается по СОХРАНЁННОМУ прямоугольнику (его
	// собственные bounds читать нельзя — см. поле hover_widget). Сравнение
	// идёт и по адресу, и по прямоугольнику: адрес освобождённого виджета
	// может достаться новому (ABA), а вот совпадение адреса И bounds
	// означает, что перерисовывать прошлое место незачем — оно то же самое.
	if prev_ptr != unsafe { nil } && (prev_ptr != ptr || prev_rect != rect) {
		w.ctx.invalidate(prev_rect)
	}
	if ptr != unsafe { nil } {
		w.ctx.invalidate(rect)
	}
	// Оба nil — курсор идёт по пустому фону окна: перерисовывать нечего,
	// кадр не нужен вообще (render() уйдёт на skip_draw). Это и есть
	// основной выигрыш 3.C.
}

// Освобождает ресурсы окна в строгом порядке: остановка текстового ввода -> кэши текстов ->
// ссылка на общий набор шрифтов (ровно один раз) -> текстура фона -> render-цель rt -> снятие
// рендерера с учёта (его текстуры умирают вместе с ним) -> SDL_DestroyRenderer ->
// SDL_DestroyWindow. Идемпотентна: указатели обнуляются, повторный вызов безопасен.
pub fn (mut w Window) cleanup() {
	if unsafe { w.sdl_window != nil } {
		C.SDL_StopTextInput(w.sdl_window)
	}
	w.ctx.cleanup_fonts()
	// Drop this window's reference to the shared FontSet exactly once (cleanup
	// can run again, e.g. App.cleanup after a temporary dialog's own cleanup).
	// ctx.fonts stays set: nothing may draw on a cleaned-up window.
	if w.fonts_held {
		w.fonts_held = false
		release_fonts(voidptr(w.ctx.fonts))
	}
	// Free the background image texture while the renderer is still alive.
	if w.bg_image != unsafe { nil } {
		w.bg_image.destroy_texture()
	}
	if unsafe { w.renderer != nil } {
		// Free the persistent render target BEFORE dropping the renderer from
		// the live registry / destroying it — same generation-guard pattern
		// as ImageView's texture (see PROJECT.md "SDL texture lifetime").
		if w.rt != unsafe { nil } && is_renderer_alive_gen(w.renderer, w.rt_gen) {
			C.SDL_DestroyTexture(w.rt)
		}
		w.rt = unsafe { nil }
		// Drop from the live-renderer registry first: SDL_DestroyRenderer also
		// destroys every texture tied to this renderer, so any ImageView that
		// still holds one must NOT call SDL_DestroyTexture afterwards.
		unregister_renderer(w.renderer)
		C.SDL_DestroyRenderer(w.renderer)
		w.renderer = unsafe { nil }
	}
	if unsafe { w.sdl_window != nil } {
		C.SDL_DestroyWindow(w.sdl_window)
		w.sdl_window = unsafe { nil }
	}
}

// ─── Window background image ───────────────────────────

// Фоновая картинка окна (рисуется под всеми виджетами, на весь экран): создаётся лениво при первой
// установке; set_background_mode задаёт режим вписывания, clear_background освобождает.
fn (mut w Window) ensure_bg_image() {
	if w.bg_image == unsafe { nil } {
		w.bg_image = &ImageBackground{
			mode: .fill
		}
	}
}

pub fn (mut w Window) set_background_image(path string) {
	w.ensure_bg_image()
	w.bg_image.set_path(path)
}

pub fn (mut w Window) set_background_image_data(data []u8) {
	w.ensure_bg_image()
	w.bg_image.set_data(data)
}

pub fn (mut w Window) set_background_mode(mode BgMode) {
	w.ensure_bg_image()
	w.bg_image.set_mode(mode)
}

pub fn (mut w Window) clear_background() {
	if w.bg_image != unsafe { nil } {
		w.bg_image.destroy_texture()
		w.bg_image = unsafe { nil }
	}
}

// ═══════════════════════════════════════════════════════
// Dialog
// ═══════════════════════════════════════════════════════

// Параметры create_dialog (поля шрифтов/темы - как в WindowConfig). width/height == 0 - размер по
// содержимому (пересчитывается при каждом show()). parent - окно-родитель: даёт тему и масштаб,
// по нему центрируется диалог и определяется модальная область. ui_scale 0 - как у родителя.
@[params]
pub struct DialogConfig {
pub mut:
	title string = 'Dialog'
	// 0 - размер по содержимому: диалог подгоняется под него при
	// каждом show() (fit_to_content); min_*/max_* - границы (0 - нет)
	width      int
	height     int
	min_width  int
	min_height int
	max_width  int
	max_height int
	parent     &Window = unsafe { nil }
	// none - тема родителя, без родителя - тема приложения (App.add_dialog)
	theme            ?Theme
	font_path        string
	bold_path        string
	italic_path      string
	bold_italic_path string
	mono_path        string
	mono_bold_path   string
	font_data        []u8
	bold_data        []u8
	italic_data      []u8
	bold_italic_data []u8
	mono_data        []u8
	mono_bold_data   []u8
	font_size        int = 14
	mono_size        int = 13
	vsync            bool
	high_dpi         bool = true
	icon_path        string
	ui_scale         f32
}

// Диалог: окно фиксированного размера (win) плюс логика результата. modal == true - пока открыт,
// блокирует ввод в окнах своего дерева владения (App.process_events, modal_scope.v).
// result - код закрытия (-1 - пока не закрыт; 0 - отмена по Esc/крестику), on_result вызывается при
// закрытии. base_width/base_height - логический размер без масштаба: из него show() считает
// физический размер окна.
pub struct Dialog {
pub mut:
	win         Window
	parent_id   u32
	modal       bool     = true
	result      int      = -1
	on_result   fn (int) = unsafe { nil }
	parent      &Window  = unsafe { nil }
	base_width  int
	base_height int
	// Размер по содержимому (width/height 0 в DialogConfig): show()
	// подгоняет диалог заново - содержимое могло измениться
	auto_size bool
	max_w     int // верхняя граница размера по содержимому (0 - нет)
	max_h     int
}

// dialog_theme - тема окна диалога: заданная, иначе родителя, иначе none
// (тогда её применит App.add_dialog из AppConfig.theme).
fn dialog_theme(cfg DialogConfig) ?Theme {
	if t := cfg.theme {
		return t
	}
	if unsafe { cfg.parent != nil } {
		return cfg.parent.ctx.theme
	}
	return none
}

// Создаёт скрытое окно диалога (режим fixed) и оборачивает его в Dialog. Окно копируется
// в поле win по значению. Тема: своя -> родителя -> приложения. Масштаб интерфейса берётся из
// cfg.ui_scale либо у родителя. Показывает диалог show().
pub fn create_dialog(cfg DialogConfig) !&Dialog {
	parent_id := if unsafe { cfg.parent != nil } {
		cfg.parent.sdl_id
	} else {
		u32(0)
	}

	// Размер по содержимому узнается при show(), до него - временный
	w0 := if cfg.width > 0 { cfg.width } else { 320 }
	h0 := if cfg.height > 0 { cfg.height } else { 200 }
	// Позиция - при show(): по центру экрана (dialog_center_pos)
	win_cfg := WindowConfig{
		title:            cfg.title
		width:            w0
		height:           h0
		x:                -1
		y:                -1
		mode:             .fixed
		// По содержимому - нижняя граница только заданная min_*
		min_width:        if cfg.width > 0 { cfg.width } else { max_int(1, cfg.min_width) }
		min_height:       if cfg.height > 0 { cfg.height } else { max_int(1, cfg.min_height) }
		max_width:        w0
		max_height:       h0
		visible:          false
		theme:            dialog_theme(cfg)
		font_path:        cfg.font_path
		bold_path:        cfg.bold_path
		italic_path:      cfg.italic_path
		bold_italic_path: cfg.bold_italic_path
		mono_path:        cfg.mono_path
		mono_bold_path:   cfg.mono_bold_path
		font_data:        cfg.font_data
		bold_data:        cfg.bold_data
		italic_data:      cfg.italic_data
		bold_italic_data: cfg.bold_italic_data
		mono_data:        cfg.mono_data
		mono_bold_data:   cfg.mono_bold_data
		font_size:        cfg.font_size
		mono_size:        cfg.mono_size
		vsync:            cfg.vsync
		high_dpi:         cfg.high_dpi
		icon_path:        cfg.icon_path
	}

	mut w := create_window(win_cfg)!

	scale := if cfg.ui_scale > 0 {
		cfg.ui_scale
	} else if unsafe { cfg.parent != nil } && cfg.parent.ctx.ui_scale != 1.0 {
		cfg.parent.ctx.ui_scale
	} else {
		f32(1.0)
	}
	if scale != 1.0 {
		w.set_ui_scale(scale)
	}

	// Окно копируется в Dialog по значению: все ресурсы (SDL-окно, рендерер, шрифты) -
	// указатели и переходят в копию, а оригинал больше не используется и не освобождается.
	// Это безопасно, пока create_window нигде не сохраняет собственный адрес (&Window) -
	// см. инвариант у create_window.
	return &Dialog{
		win:         unsafe { *w }
		parent_id:   parent_id
		modal:       true
		parent:      unsafe { cfg.parent }
		base_width:  w0
		base_height: h0
		auto_size:   cfg.width <= 0 || cfg.height <= 0
		max_w:       cfg.max_width
		max_h:       cfg.max_height
	}
}

// set_size_limits - границы размера диалога «по содержимому»: нижняя
// (min) и верхняя (max, 0 - без границы)
pub fn (mut d Dialog) set_size_limits(min_w int, min_h int, max_w int, max_h int) {
	d.win.config.min_width = max_int(1, min_w)
	d.win.config.min_height = max_int(1, min_h)
	d.max_w = max_w
	d.max_h = max_h
}

// Добавляет корневой виджет в окно диалога.
pub fn (mut d Dialog) add_widget(widget &Widget) {
	d.win.add_widget(widget)
}

// fit_to_content подгоняет диалог под размер содержимого.
//
// В отличие от окна, размер диалога задаётся при show()
// из base_width/base_height (они же масштабируются вместе
// с ui_scale), поэтому измеренный размер пишется именно
// туда — и применится при следующем показе.
//
// max_w/max_h = 0 → без верхней границы.
pub fn (mut d Dialog) fit_to_content(max_w int, max_h int) {
	hint := d.win.measure_content()
	if hint.w <= 0 && hint.h <= 0 {
		return
	}
	mut cw := int(hint.w)
	mut ch := int(hint.h)
	if cw < d.win.config.min_width {
		cw = d.win.config.min_width
	}
	if ch < d.win.config.min_height {
		ch = d.win.config.min_height
	}
	if max_w > 0 && cw > max_w {
		cw = max_w
	}
	if max_h > 0 && ch > max_h {
		ch = max_h
	}
	d.base_width = cw
	d.base_height = ch
	d.win.config.width = cw
	d.win.config.height = ch
	if d.win.open {
		// Диалог уже на экране — применяем сразу.
		d.win.set_size(cw, ch)
	}
}

// Показывает диалог: сбрасывает result в -1, подгоняет размер по содержимому (если auto_size),
// переводит логический размер в физический по масштабу родителя, фиксирует размер окна
// (min = max, пользователь не может его менять), центрирует и поднимает. Позиция
// выставляется дважды - до и после показа, потому что оконный менеджер может проигнорировать
// первую.
pub fn (mut d Dialog) show() {
	d.result = -1
	if d.auto_size {
		d.fit_to_content(d.max_w, d.max_h)
	}

	mut target_scale := d.win.ctx.ui_scale
	if unsafe { d.parent != nil } {
		target_scale = d.parent.ctx.ui_scale
	}
	if target_scale < 0.5 {
		target_scale = 1.0
	}

	pixel_w := int(f32(d.base_width) * target_scale + 0.5)
	pixel_h := int(f32(d.base_height) * target_scale + 0.5)

	C.SDL_SetWindowMinimumSize(d.win.sdl_window, pixel_w, pixel_h)
	C.SDL_SetWindowMaximumSize(d.win.sdl_window, pixel_w, pixel_h)
	C.SDL_SetWindowSize(d.win.sdl_window, pixel_w, pixel_h)

	if d.win.ctx.ui_scale != target_scale {
		d.win.set_ui_scale(target_scale)
	}

	d.win.ctx.screen_width = f32(d.base_width)
	d.win.ctx.screen_height = f32(d.base_height)

	pos := dialog_center_pos(d)
	C.SDL_SetWindowPosition(d.win.sdl_window, pos, pos)

	d.win.open = true
	d.win.visible = true

	C.SDL_ShowWindow(d.win.sdl_window)
	// Ещё раз после показа: оконный менеджер (KWin) ставит новое окно
	// по своим правилам и позицию, заданную до показа, не берёт
	C.SDL_SetWindowPosition(d.win.sdl_window, pos, pos)
	C.SDL_RaiseWindow(d.win.sdl_window)
}

// dialog_center_pos - позиция диалога: по центру экрана, на котором
// родитель (несколько мониторов - на мониторе родителя, а не на
// основном); без родителя - на экране самого диалога
fn dialog_center_pos(d &Dialog) int {
	win := if unsafe { d.parent != nil } { d.parent.sdl_window } else { d.win.sdl_window }
	if win != unsafe { nil } {
		id := C.SDL_GetDisplayForWindow(win)
		if id != 0 {
			return int(u32(sdl_windowpos_centered) | id)
		}
	}
	return sdl_windowpos_centered
}

// Показывает диалог с масштабом интерфейса, как у переданного окна.
pub fn (mut d Dialog) show_scaled(parent &Window) {
	parent_scale := parent.ctx.ui_scale
	if d.win.ctx.ui_scale != parent_scale {
		d.win.set_ui_scale(parent_scale)
	}
	d.show()
}

// Закрывает диалог с кодом result: прячет окно, сбрасывает нажатое состояние кнопок (иначе
// после повторного показа кнопка осталась бы "нажатой") и вызывает on_result. Освобождения
// ресурсов не делает - временные диалоги затем сами зовут app.remove_dialog и win.cleanup().
pub fn (mut d Dialog) close_with_result(result int) {
	d.result = result
	d.win.open = false
	d.win.visible = false
	if unsafe { d.win.sdl_window != nil } {
		C.SDL_HideWindow(d.win.sdl_window)
	}
	for e in d.win.ctx.focus.entries {
		if e.kind == .button {
			mut b := unsafe { &Button(e.ptr) }
			b.pressed = false
		}
	}
	if d.on_result != unsafe { nil } {
		d.on_result(result)
	}
}

// Открыт ли диалог.
pub fn (d &Dialog) is_open() bool {
	return d.win.open
}

pub fn (mut d Dialog) set_title(title string) {
	d.win.set_title(title)
}

pub fn (mut d Dialog) set_theme(theme Theme) {
	d.win.set_theme(theme)
}

// Меняет пользовательский масштаб интерфейса (ограничивается 0.5..4.0). Итоговый масштаб
// рендера = dpi_scale * ui_scale. Окно SDL растягивается на тот же коэффициент, чтобы
// логический размер (config.width x height) остался прежним; кэш текстов сбрасывается, шрифты
// перезагружаются под новый физический размер (reload_scaled_fonts).
pub fn (mut w Window) set_ui_scale(scale f32) {
	s := clamp_f32(scale, 0.5, 4.0)
	w.ctx.ui_scale = s

	combined := w.ctx.dpi_scale * s
	C.SDL_SetRenderScale(w.renderer, combined, combined)

	// Resize the SDL window so the logical widget space stays cfg.width × cfg.height.
	// SDL_SetRenderScale magnifies visually; the window must be bigger to match.
	// The resulting WINDOW_RESIZED event will update config/screen_width via app loop.
	new_sdl_w := int(f32(w.config.width) * s + 0.5)
	new_sdl_h := int(f32(w.config.height) * s + 0.5)
	C.SDL_SetWindowSize(w.sdl_window, new_sdl_w, new_sdl_h)
	w.ctx.screen_width = f32(w.config.width)
	w.ctx.screen_height = f32(w.config.height)

	w.ctx.clear_text_cache()
	w.reload_scaled_fonts()
}

// ─── Window hotkey convenience methods ─────────────────

// Горячие клавиши окна: делегаты к HotkeyManager (hotkeys.v); срабатывают после виджетов, до
// горячих клавиш приложения (см. dispatch_event_inner).
pub fn (mut w Window) bind_hotkey(shortcut string, handler fn ()) {
	w.hotkeys.bind(shortcut, handler)
}

pub fn (mut w Window) unbind_hotkey(shortcut string) {
	w.hotkeys.unbind(shortcut)
}

pub fn (mut w Window) set_hotkey_enabled(shortcut string, enabled bool) {
	w.hotkeys.set_enabled(shortcut, enabled)
}

pub fn (mut w Window) clear_hotkeys() {
	w.hotkeys.clear()
}

// Масштаб интерфейса диалога: делегаты к окну диалога.
pub fn (mut d Dialog) set_ui_scale(scale f32) {
	d.win.set_ui_scale(scale)
}

pub fn (d &Dialog) get_ui_scale() f32 {
	return d.win.ctx.ui_scale
}
