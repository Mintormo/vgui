// @[has_globals] разрешает объявлять `__global` в этом файле без флага `-enable-globals`
// (атрибут действует на файл, а не на модуль; vgui/PROJECT.md, «Компилятор V»).
@[has_globals]
module vgui

// ═══════════════════════════════════════════════════════
// SDL3 C bindings
// ═══════════════════════════════════════════════════════

// Файл sdl3_bindings.v: единственное место, где V подключает C-библиотеки SDL3, SDL3_ttf и
// SDL3_image (флаги линковки, #include) и объявляются используемые функции (fn C.*), C-структуры
// (@[typedef] struct C.*) и числовые константы SDL (sdl_*, ttf_*). Объявлено только то, что
// реально нужно библиотеке; значения констант и раскладка структур - от SDL 3.2+
// (не от SDL2; где значения совпадают с SDL2, это отмечено). SDL3 в проект не вшивается и должна стоять в системе (PROJECT.md,
// «Зависимости SDL3»). Остальные sdl3_*.v используют эти объявления: sdl3_app.v - цикл событий,
// sdl3_window.v - окна и рендерер, sdl3_render.v / sdl3_fonts.v - рисование, tray.v и
// native_file_dialog.v - трей и диалоги.

// Флаги линковки и заголовки. Путь /usr/include/SDL3 нужен на Linux для поиска заголовков.
#flag linux -lSDL3 -lSDL3_ttf -lSDL3_image
#flag linux -I/usr/include/SDL3
#flag windows -lSDL3 -lSDL3_ttf -lSDL3_image

#include <SDL3/SDL.h>
#include <SDL3_ttf/SDL_ttf.h>
#include <SDL3_image/SDL_image.h>
#include <locale.h>

// Нужен create_app: без setlocale SDL на X11 не может записать UTF-8 заголовок окна.
fn C.setlocale(category int, locale &char) &char

// ─── SDL3 Core ───

// Основной API SDL3: инициализация, время, окна. В SDL3 большинство функций возвращает bool
// (true - успех, причина ошибки в SDL_GetError), а не int, как в SDL2.
fn C.SDL_Init(flags u32) bool
fn C.SDL_Quit()
fn C.SDL_GetError() &char
fn C.SDL_Delay(ms u32)
fn C.SDL_GetTicks() u64
fn C.SDL_GetModState() u16

fn C.SDL_CreateWindow(title &char, w int, h int, flags u64) voidptr
fn C.SDL_SetWindowBordered(win voidptr, bordered bool)
fn C.SDL_DestroyWindow(win voidptr)
fn C.SDL_GetWindowSize(win voidptr, w &int, h &int) bool
fn C.SDL_GetWindowDisplayScale(win voidptr) f32
fn C.SDL_SetWindowTitle(win voidptr, title &char) bool
fn C.SDL_GetWindowFlags(win voidptr) u64

// Рендерер: цвет/режим смешивания, очистка и показ кадра, отсечение, прямоугольники и линии,
// вывод текстур (в том числе с поворотом).
fn C.SDL_WaitEventTimeout(event voidptr, timeout_ms i32) bool
fn C.SDL_CreateRenderer(win voidptr, name &char) voidptr
fn C.SDL_DestroyRenderer(ren voidptr)
fn C.SDL_SetRenderDrawColor(ren voidptr, r u8, g u8, b u8, a u8) bool
fn C.SDL_SetRenderDrawBlendMode(ren voidptr, mode int) bool
fn C.SDL_RenderClear(ren voidptr) bool
fn C.SDL_RenderPresent(ren voidptr) bool
fn C.SDL_SetRenderClipRect(ren voidptr, rect &C.SDL_Rect) bool
fn C.SDL_RenderFillRect(ren voidptr, rect voidptr) bool
fn C.SDL_RenderFillRects(renderer voidptr, rects &C.SDL_FRect, count int) bool
fn C.SDL_RenderRect(ren voidptr, rect voidptr) bool
fn C.SDL_RenderLine(ren voidptr, x1 f32, y1 f32, x2 f32, y2 f32) bool
fn C.SDL_RenderLines(ren voidptr, points voidptr, count int) bool
fn C.SDL_RenderTexture(ren voidptr, tex voidptr, src voidptr, dst voidptr) bool
fn C.SDL_RenderTextureRotated(ren voidptr, tex voidptr, src voidptr, dst voidptr, angle f64, center voidptr, flip int) bool
// Surface (пиксели в памяти CPU): создание, смешивание, blit.
fn C.SDL_CreateSurface(width int, height int, format u32) voidptr
fn C.SDL_SetSurfaceBlendMode(surface voidptr, mode int) bool
fn C.SDL_BlitSurface(src voidptr, srcrect voidptr, dst voidptr, dstrect voidptr) bool

// Текстуры (память GPU): создание, загрузка пикселей, размер, смешивание, цель рендера
// (SDL_SetRenderTarget - на нём построен постоянный render target окна), режим масштабирования, vsync.
fn C.SDL_CreateTexture(ren voidptr, format u32, access int, w int, h int) voidptr
fn C.SDL_CreateTextureFromSurface(ren voidptr, surface voidptr) voidptr
fn C.SDL_UpdateTexture(tex voidptr, rect voidptr, pixels voidptr, pitch int) bool

// SDL_TextureAccess (target/static already defined below; streaming is new)
pub const sdl_textureaccess_static = 0
pub const sdl_textureaccess_streaming = 1

fn C.SDL_GetTextureSize(tex voidptr, w &f32, h &f32) bool
fn C.SDL_DestroyTexture(tex voidptr)
fn C.SDL_SetTextureBlendMode(tex voidptr, mode int) bool
fn C.SDL_SetTextureAlphaMod(tex voidptr, a u8) bool
fn C.SDL_SetRenderTarget(renderer voidptr, texture voidptr) bool
fn C.SDL_GetRenderTarget(renderer voidptr) voidptr
fn C.SDL_SetTextureScaleMode(texture voidptr, scale_mode int) bool
fn C.SDL_SetHint(name &char, value &char) bool
fn C.SDL_SetRenderVSync(renderer voidptr, vsync int) bool

fn C.SDL_DestroySurface(surface voidptr)

// События (опрос), текстовый ввод, буфер обмена, курсоры, hit-test безрамочных окон.
fn C.SDL_PollEvent(event voidptr) bool

// Оба потокобезопасны по контракту SDL - основа app.post()
fn C.SDL_PushEvent(event voidptr) bool
fn C.SDL_RegisterEvents(numevents int) u32
fn C.SDL_StartTextInput(win voidptr) bool
fn C.SDL_StopTextInput(win voidptr) bool
fn C.SDL_SetClipboardText(text &char) bool
fn C.SDL_GetClipboardText() &char
fn C.SDL_OpenURL(url &char) bool
fn C.SDL_free(mem voidptr)

fn C.SDL_ShowCursor() bool
fn C.SDL_HideCursor() bool
fn C.SDL_CreateSystemCursor(id int) voidptr
fn C.SDL_SetCursor(cursor voidptr) bool
fn C.SDL_GetCursor() voidptr
fn C.SDL_DestroyCursor(cursor voidptr)

// Hit-test callback for borderless resize
fn C.SDL_SetWindowHitTest(win voidptr, callback voidptr, callback_data voidptr) bool
fn C.SDL_GetGlobalMouseState(x &f32, y &f32) u32

// ─── SDL3 Render geometry (replaces SDL2_gfx) ───

// Геометрия (SDL_RenderGeometry - произвольные треугольники; заменила SDL2_gfx) и масштаб
// рендера (SDL_SetRenderScale - основа HiDPI и ui_scale).
fn C.SDL_RenderGeometry(renderer voidptr, texture voidptr, vertices voidptr, num_vertices int, indices voidptr, num_indices int) bool
fn C.SDL_SetRenderScale(renderer voidptr, scale_x f32, scale_y f32) bool
fn C.SDL_GetRenderScale(renderer voidptr, scale_x &f32, scale_y &f32) bool

// ─── SDL3 HiDPI ───

fn C.SDL_GetWindowSizeInPixels(win voidptr, w &int, h &int) bool
fn C.SDL_GetCurrentRenderOutputSize(renderer voidptr, w &int, h &int) bool

// Результаты hit-test для безрамочных окон (SDL_HitTestResult): что находится под курсором -
// обычная область, зона перетаскивания или одна из восьми зон изменения размера.
pub const sdl_hittest_normal = 0
pub const sdl_hittest_draggable = 1
pub const sdl_hittest_resize_topleft = 2
pub const sdl_hittest_resize_top = 3
pub const sdl_hittest_resize_topright = 4
pub const sdl_hittest_resize_right = 5
pub const sdl_hittest_resize_bottomright = 6
pub const sdl_hittest_resize_bottom = 7
pub const sdl_hittest_resize_bottomleft = 8
pub const sdl_hittest_resize_left = 9

// ─── SDL3_ttf ───

// SDL3_ttf: открытие шрифтов из файла или из памяти (через SDL_IOFromConstMem), рендер текста
// в surface, измерение, стиль и хинтинг. В SDL3_ttf размеры шрифта - f32, а длина строки -
// usize (0 означает "до нулевого байта").
fn C.TTF_Init() bool
fn C.TTF_Quit()
fn C.TTF_OpenFont(file &char, ptsize f32) voidptr
fn C.TTF_OpenFontIO(src voidptr, closeio bool, ptsize f32) voidptr
fn C.SDL_IOFromConstMem(mem voidptr, size usize) voidptr
fn C.TTF_CloseFont(font voidptr)
fn C.TTF_RenderText_Blended(font voidptr, text &char, length usize, fg C.SDL_Color) voidptr
fn C.TTF_GetStringSize(font voidptr, text &char, length usize, w &int, h &int) bool
fn C.TTF_SetFontStyle(font voidptr, style int)
fn C.TTF_GetFontHeight(font voidptr) int
fn C.TTF_SetFontHinting(font voidptr, hinting int)

// ─── SDL3_image ───

// SDL3_image: загрузка (из файла и из памяти) и сохранение картинок.
fn C.IMG_Init(flags int) int
fn C.IMG_Quit()
fn C.IMG_Load(file &char) voidptr
fn C.IMG_SavePNG(surface voidptr, file &char) bool
fn C.IMG_SaveJPG(surface voidptr, file &char, quality int) bool
fn C.IMG_SaveWEBP(surface voidptr, file &char, quality f32) bool

// IMG_Save picks the output format from the file extension (png/jpg/webp/gif/bmp/...).
fn C.IMG_Save(surface voidptr, file &char) bool

// SDL_ConvertSurface returns a new surface in the requested pixel format.
fn C.SDL_ConvertSurface(surface voidptr, format u32) voidptr

// ─── SDL3 surface/pixel ops ────────────────────────────

// ─── SDL3 Tray (cross-platform system tray, SDL >= 3.2) ───

// Системный трей (SDL >= 3.2): иконка, подсказка, меню и пункты. Используется tray.v.
fn C.SDL_CreateTray(icon voidptr, tooltip &char) voidptr
fn C.SDL_SetTrayIcon(tray voidptr, icon voidptr)
fn C.SDL_SetTrayTooltip(tray voidptr, tooltip &char)
fn C.SDL_CreateTrayMenu(tray voidptr) voidptr
fn C.SDL_CreateTraySubmenu(entry voidptr) voidptr
fn C.SDL_GetTrayMenu(tray voidptr) voidptr
fn C.SDL_InsertTrayEntryAt(menu voidptr, pos int, label &char, flags u32) voidptr
fn C.SDL_RemoveTrayEntry(entry voidptr)
fn C.SDL_SetTrayEntryLabel(entry voidptr, label &char)
fn C.SDL_GetTrayEntryLabel(entry voidptr) &char
fn C.SDL_SetTrayEntryChecked(entry voidptr, checked bool)
fn C.SDL_GetTrayEntryChecked(entry voidptr) bool
fn C.SDL_SetTrayEntryEnabled(entry voidptr, enabled bool)
fn C.SDL_SetTrayEntryCallback(entry voidptr, callback voidptr, userdata voidptr)
fn C.SDL_DestroyTray(tray voidptr)
fn C.SDL_UpdateTrays()

// Loads an image into a surface from raw bytes in memory (for embedded icons).
fn C.IMG_Load_IO(src voidptr, closeio bool) voidptr

// SDL_TrayEntryFlags
pub const sdl_trayentry_button = u32(0x00000001)
pub const sdl_trayentry_checkbox = u32(0x00000002)
pub const sdl_trayentry_submenu = u32(0x00000004)
pub const sdl_trayentry_disabled = u32(0x80000000)
pub const sdl_trayentry_checked = u32(0x40000000)

// Чтение пикселей рендерера и сохранение/ввод-вывод (скриншоты).
fn C.SDL_RenderReadPixels(renderer voidptr, rect &C.SDL_Rect) voidptr
fn C.SDL_SaveBMP(surface voidptr, file &char) bool
fn C.SDL_IOFromFile(file &char, mode &char) voidptr
fn C.SDL_CloseIO(ctx voidptr) bool

// Форматы пикселей (SDL_PixelFormat). Значения - числовые коды формата SDL3; rgba32 совпадает
// с abgr8888 (порядок байт для little-endian).
pub const sdl_pixelformat_rgba8888 = u32(0x16462004)
pub const sdl_pixelformat_abgr8888 = u32(0x16762004)
pub const sdl_pixelformat_argb8888 = u32(0x16362004)

// ─── SDL3 Structures ───

// Зеркала C-структур SDL. @[typedef] говорит V, что тип уже определён в C-заголовке, поэтому
// объявлять нужно только поля, к которым обращается V-код (SDL_Surface - лишь начало структуры).
// Раскладка полей обязана совпадать с C: порядок и типы менять нельзя.
@[typedef]
struct C.SDL_Rect {
pub mut:
	x int
	y int
	w int
	h int
}

// Partial mirror of SDL_Surface — only the fields we read (pixel access). As a
// @[typedef] V trusts the real C layout, so undeclared trailing fields are fine.
@[typedef]
struct C.SDL_Surface {
pub mut:
	flags  u32
	format u32
	w      int
	h      int
	pitch  int
	pixels voidptr
}

@[typedef]
struct C.SDL_Point {
pub mut:
	x int
	y int
}

@[typedef]
struct C.SDL_FPoint {
pub mut:
	x f32
	y f32
}

@[typedef]
struct C.SDL_FRect {
pub mut:
	x f32
	y f32
	w f32
	h f32
}

@[typedef]
struct C.SDL_Color {
pub mut:
	r u8
	g u8
	b u8
	a u8
}

@[typedef]
struct C.SDL_Vertex {
pub mut:
	position  C.SDL_FPoint
	color     C.SDL_FColor
	tex_coord C.SDL_FPoint
}

@[typedef]
struct C.SDL_FColor {
pub mut:
	r f32
	g f32
	b f32
	a f32
}

// SDL_Event - union размером 128 байт; V-код читает общее поле type, затем приводит указатель
// к нужной структуре события (клавиатура, мышь, окно, drop, текстовый ввод).
@[typedef]
union C.SDL_Event {
pub mut:
	@type   u32
	padding [128]u8
}

// Конкретные структуры событий (поле type читается из общего начала union).
// Поле repeat - автоповтор удерживаемой клавиши (GuiEvent.repeat).
@[typedef]
struct C.SDL_KeyboardEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	which     u32
	scancode  int
	key       int
	mod_keys  u16
	raw       u16
	down      bool
	repeat    bool
}

@[typedef]
struct C.SDL_TextInputEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	text      &char
}

@[typedef]
struct C.SDL_MouseButtonEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	which     u32
	button    u8
	down      bool
	clicks    u8
	padding   u8
	x         f32
	y         f32
}

@[typedef]
struct C.SDL_MouseMotionEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	which     u32
	state     u32
	x         f32
	y         f32
	xrel      f32
	yrel      f32
}

@[typedef]
struct C.SDL_MouseWheelEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	which     u32
	x         f32
	y         f32
	direction u32
	mouse_x   f32
	mouse_y   f32
}

@[typedef]
struct C.SDL_WindowEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	data1     i32
	data2     i32
}

@[typedef]
struct C.SDL_DropEvent {
pub mut:
	@type     u32
	reserved  u32
	timestamp u64
	windowID  u32
	x         f32
	y         f32
	source    &char = unsafe { nil }
	data      &char = unsafe { nil }
}

// ─── SDL3 Constants ───

// Константы SDL3: флаги инициализации и окон (u64 - в SDL3 флаги окна 64-битные), режимы
// смешивания, типы событий, модификаторы. Значения совпадают с C-заголовками SDL3. Отдельного
// флага "fullscreen_desktop" в SDL3 нет (полноэкранный режим без смены видеорежима - это
// sdl_window_fullscreen без SDL_SetWindowFullscreenMode), поэтому и константы такой нет.
pub const sdl_init_video = u32(0x00000020)
pub const sdl_init_audio = u32(0x00000010)
pub const sdl_init_events = u32(0x00004000)

// SDL3 window flags are u64
pub const sdl_window_resizable = u64(0x0000000000000020)
pub const sdl_window_minimized = u64(0x0000000000000040)
pub const sdl_window_maximized = u64(0x0000000000000080)
pub const sdl_window_fullscreen = u64(0x0000000000000001)
pub const sdl_window_borderless = u64(0x0000000000000010)
pub const sdl_window_hidden = u64(0x0000000000000008)
pub const sdl_window_high_pixel_density = u64(0x0000000000002000)

pub const sdl_renderer_presentvsync = u32(0x00000004)

pub const sdl_blendmode_none = 0
pub const sdl_blendmode_blend = 1

pub const sdl_windowpos_centered = 0x2FFF0000

// SDL3 event types
pub const sdl_quit_event = u32(0x100)
pub const sdl_keydown = u32(0x300)
pub const sdl_keyup = u32(0x301)
pub const sdl_textinput = u32(0x303)
pub const sdl_mousemotion = u32(0x400)
pub const sdl_mousebuttondown = u32(0x401)
pub const sdl_mousebuttonup = u32(0x402)
pub const sdl_mousewheel = u32(0x403)

// SDL3 window events — each is a separate event type (not sub-event)
// У SDL3 каждое событие окна - самостоятельный тип события (в SDL2 было одно событие
// с под-типом).
pub const sdl_event_window_shown = u32(0x202)
pub const sdl_event_window_hidden = u32(0x203)
pub const sdl_event_window_exposed = u32(0x204)
pub const sdl_event_window_resized = u32(0x206)
pub const sdl_event_window_pixel_size_changed = u32(0x207)
pub const sdl_event_window_minimized = u32(0x209)
pub const sdl_event_window_maximized = u32(0x20A)

// SDL3 render events: the persistent render target's content was lost
pub const sdl_event_render_targets_reset = u32(0x2000)
pub const sdl_event_render_device_reset = u32(0x2001)
pub const sdl_event_window_restored = u32(0x20B)
pub const sdl_event_window_mouse_leave = u32(0x20D)
pub const sdl_event_window_focus_gained = u32(0x20E)
pub const sdl_event_window_focus_lost = u32(0x20F)
pub const sdl_event_window_close_requested = u32(0x210)

// SDL3 drag-and-drop events
pub const sdl_event_drop_file = u32(0x1000)
pub const sdl_event_drop_text = u32(0x1001)
pub const sdl_event_drop_begin = u32(0x1002)
pub const sdl_event_drop_complete = u32(0x1003)
pub const sdl_event_drop_position = u32(0x1004)

// Key modifiers
// Маски модификаторов клавиатуры: ctrl/shift/alt - объединённые левый+правый, rctrl - только правый.
pub const sdl_kmod_ctrl = u16(0x00C0)
pub const sdl_kmod_shift = u16(0x0003)
pub const sdl_kmod_alt = u16(0x0300)
pub const sdl_kmod_rctrl = u16(0x0080)

// key_mods — modifier keys held right now (sdl_kmod_* bits). For handlers that
// get no event with modifiers (e.g. a slider drag that wants Alt).
pub fn key_mods() u16 {
	return C.SDL_GetModState()
}

// set_cursor — system mouse cursor (sdl_system_cursor_*), e.g. a resize arrow
// over a crop handle. Cursors are created once per kind and cached (SDL owns
// them for the process lifetime). Always re-applied: other widgets set the
// cursor directly, so a remembered "current" kind could be stale.
pub fn set_cursor(kind int) {
	if kind < 0 {
		return
	}
	if kind !in g_cursors {
		g_cursors[kind] = C.SDL_CreateSystemCursor(kind)
	}
	cur := g_cursors[kind] or { return }
	if unsafe { cur != nil } {
		C.SDL_SetCursor(cur)
	}
}

// open_system_browser открывает URL во внешней программе по умолчанию (SDL_OpenURL).
pub fn open_system_browser(url string) {
	C.SDL_OpenURL(url.str)
}

// current_cursor - непрозрачный хэндл курсора, стоящего сейчас (SDL_Cursor*), чтобы
// потом вернуть его restore_cursor_handle. Виджету (Splitter) так не нужно звать SDL
// самому. Курсоры vgui живут до конца процесса (g_cursors), их хэндл не протухает.
fn current_cursor() voidptr {
	return C.SDL_GetCursor()
}

// restore_cursor_handle ставит курсор по хэндлу из current_cursor; nil - no-op.
fn restore_cursor_handle(cur voidptr) {
	if cur != unsafe { nil } {
		C.SDL_SetCursor(cur)
	}
}

// Кэш системных курсоров по их типу (создаются один раз, живут до конца процесса). Глобальное
// состояние главного потока.
__global g_cursors = map[int]voidptr{}

// Key codes (SDLK_*) — same values as SDL2
// Коды клавиш (SDLK_*): печатные символы совпадают с ASCII, функциональные и навигационные -
// с флагом 1<<30 (scancode | 0x40000000). Значения те же, что в SDL2.
pub const sdl_k_return = 13
pub const sdl_k_escape = 27
pub const sdl_k_backspace = 8
pub const sdl_k_tab = 9
pub const sdl_k_space = 32
pub const sdl_k_delete = 127
pub const sdl_k_up = 1073741906
pub const sdl_k_down = 1073741905
pub const sdl_k_left = 1073741904
pub const sdl_k_right = 1073741903
pub const sdl_k_home = 1073741898
pub const sdl_k_end = 1073741901
pub const sdl_k_pageup = 1073741899
pub const sdl_k_pagedown = 1073741902
pub const sdl_k_insert = 1073741897
pub const sdl_k_f1 = 1073741882
pub const sdl_k_f2 = 1073741883
pub const sdl_k_f3 = 1073741884
pub const sdl_k_f4 = 1073741885
pub const sdl_k_f5 = 1073741886
pub const sdl_k_f6 = 1073741887
pub const sdl_k_f7 = 1073741888
pub const sdl_k_f8 = 1073741889
pub const sdl_k_f9 = 1073741890
pub const sdl_k_f10 = 1073741891
pub const sdl_k_f11 = 1073741892
pub const sdl_k_f12 = 1073741893
pub const sdl_k_a = 97
pub const sdl_k_c = 99
pub const sdl_k_d = 100
pub const sdl_k_s = 115
pub const sdl_k_v = 118
pub const sdl_k_x = 120
pub const sdl_k_z = 122
pub const sdl_k_kp_9 = 1073741921
pub const sdl_k_kp_3 = 1073741915
pub const sdl_k_kp_enter = 1073741912

// Mouse buttons
// Номера кнопок мыши.
pub const sdl_button_left = u8(1)
pub const sdl_button_middle = u8(2)
pub const sdl_button_right = u8(3)

// Cursor types (SDL3 SDL_SystemCursor enum values)
// Типы системных курсоров (SDL_SystemCursor). Часть имён - алиасы, оставшиеся от SDL2:
// например sdl_system_cursor_arrow и _default - одно значение 0, ibeam = TEXT, hand = POINTER.
pub const sdl_system_cursor_default = 0 // SDL_SYSTEM_CURSOR_DEFAULT
pub const sdl_system_cursor_arrow = 0 // SDL_SYSTEM_CURSOR_DEFAULT
pub const sdl_system_cursor_ibeam = 1 // SDL_SYSTEM_CURSOR_TEXT
pub const sdl_system_cursor_wait = 2 // SDL_SYSTEM_CURSOR_WAIT
pub const sdl_system_cursor_crosshair = 3 // SDL_SYSTEM_CURSOR_CROSSHAIR
pub const sdl_system_cursor_sizenwse = 5 // SDL_SYSTEM_CURSOR_NWSE_RESIZE
pub const sdl_system_cursor_sizenesw = 6 // SDL_SYSTEM_CURSOR_NESW_RESIZE
pub const sdl_system_cursor_sizewe = 7 // SDL_SYSTEM_CURSOR_EW_RESIZE
pub const sdl_system_cursor_sizens = 8 // SDL_SYSTEM_CURSOR_NS_RESIZE
pub const sdl_system_cursor_sizeall = 9 // SDL_SYSTEM_CURSOR_MOVE
pub const sdl_system_cursor_no = 10 // SDL_SYSTEM_CURSOR_NOT_ALLOWED
pub const sdl_system_cursor_hand = 11 // SDL_SYSTEM_CURSOR_POINTER
pub const sdl_system_cursor_waitarrow = 4 // SDL_SYSTEM_CURSOR_PROGRESS

// TTF styles
// Стили и хинтинг SDL3_ttf. ttf_hinting_light_subpixel даёт самый чёткий текст при дробном
// масштабе (используется в open_font_for_role).
pub const ttf_style_normal = 0
pub const ttf_style_bold = 1
pub const ttf_style_italic = 2

// TTF hinting
pub const ttf_hinting_normal = 0
pub const ttf_hinting_light = 1
pub const ttf_hinting_mono = 2
pub const ttf_hinting_none = 3
pub const ttf_hinting_light_subpixel = 4

pub const sdl_pixelformat_rgba32 = u32(0x16762004)
pub const sdl_textureaccess_target = 2

// Режимы масштабирования текстур: nearest не размывает уже сглаженные глифы.
pub const sdl_scalemode_nearest = 0
pub const sdl_scalemode_linear = 1

// ─── SDL3 native file dialogs (SDL >= 3.2) ───
//
// These are *asynchronous*: SDL spawns the OS dialog and invokes `callback`
// later, from the event loop, once the user picks a file / cancels. The
// vgui wrappers (native_file_dialog.v) drive a local event pump until the
// callback fires, so the public V/Python API stays synchronous.

@[typedef]
struct C.SDL_DialogFileFilter {
pub mut:
	name    &char = unsafe { nil }
	pattern &char = unsafe { nil }
}

// callback signature: fn (userdata voidptr, filelist &&char, filter int)
//   filelist: null-terminated array of C strings, or nil on error,
//             or an array whose first element is nil on user-cancel.
//   filter:   index of the selected filter, or -1 if unavailable.
// Три асинхронных нативных диалога: открыть файл, сохранить файл, выбрать папку.
fn C.SDL_ShowOpenFileDialog(callback voidptr, userdata voidptr, window voidptr, filters &C.SDL_DialogFileFilter, nfilters int, default_location &char, allow_many bool)
fn C.SDL_ShowSaveFileDialog(callback voidptr, userdata voidptr, window voidptr, filters &C.SDL_DialogFileFilter, nfilters int, default_location &char)
fn C.SDL_ShowOpenFolderDialog(callback voidptr, userdata voidptr, window voidptr, default_location &char, allow_many bool)
