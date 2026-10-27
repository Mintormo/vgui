module vgui

// ═══════════════════════════════════════════════════════
// Canvas — a drawable pixel surface with direct pixel-array access.
//
// The canvas owns an RGBA byte buffer of width*height*4 bytes (`pixels`) and a
// streaming SDL texture that mirrors it. Drawing primitives write into the
// buffer and mark it dirty; on the next frame the texture is refreshed via
// SDL_UpdateTexture. The buffer is exposed to callers (pixels_ptr / set_pixels)
// so Python can read/write it wholesale (bytes / bytearray / numpy).
//
// Pixel layout: SDL_PIXELFORMAT_ABGR8888, whose in-memory byte order is
// R, G, B, A — i.e. pixels[i*4+0]=R, +1=G, +2=B, +3=A, which is the intuitive
// layout for callers.
//
// Mouse drawing: while the left button is held inside the widget, the pixel
// coordinate under the cursor is reported through `on_draw(x, y)`, letting a
// caller implement freehand painting by writing into the buffer.
//
// The display rect (where the buffer is shown inside `bounds`) is computed each
// frame in fit mode (aspect-preserved, centered) or stretch mode, and reused to
// map mouse coordinates back to pixel coordinates.
//
// Связи с остальной библиотекой (PROJECT.md, разделы «Canvas (kind 50)»,
// «Canvas: инструменты поверх снимка», «Canvas: слой детализации»,
// «Кольцо пипетки», «Текстовый ввод SDL - только по фокусу; Canvas.take_keys»):
//   - Фокус: draw() регистрирует холст в ctx.focus (register_canvas), клик
//     инструмента берёт фокус (focus_canvas) - иначе клавиши не дойдут до on_input.
//   - Текстура: потоковая Texture (sdl3_texture.v) помнит рендерер-создатель и
//     его поколение; destroy() освобождает её, только если рендерер ещё жив
//     (PROJECT.md «Время жизни SDL-текстур»). Файлы картинок - image_io.v.
//   - Раскладка: bounds выставляет контейнер (Layouted/widget_tree.v), размер
//     по содержимому не считается (см. Canvas.measure в layout_measure.v).
//   - C-ABI: поля/методы отдаются в Python через vgui_canvas_* (vgui_capi);
//     событие on_input передаётся указателем на CanvasInputEvent
//     (VOIDP_DISPATCHER), Python читает поля геттерами.
//
// Порядок слоёв при отрисовке (draw): основное изображение -> слой детализации
// (detail) -> полосы прокрутки -> on_overlay (графика инструмента) -> кольцо
// кисти (brush_cursor). Три последних не трогают буфер пикселей.
//
// Приоритет обработки событий (handle_event): активный штрих (drawing) >
// перетаскивание панорамы (panning) > перетаскивание полос прокрутки > обычные
// события (hover/enter/leave, нажатие, колесо, клавиши).
// ═══════════════════════════════════════════════════════

// Ширина полосы прокрутки (логические px) и границы масштаба (экранных px на пиксель буфера).
const cv_sb_w = f32(12)
// Отступ миникарты от края видимой части и её рамка (подложка)
const cv_nav_margin = f32(10)
const cv_nav_pad = f32(3)
const cv_min_zoom = f32(0.02)
const cv_max_zoom = f32(32.0)

// Pan-button bitmask: which mouse buttons trigger built-in panning. Buttons NOT
// in this set are delivered to on_input as pointer events, so a tool can claim
// them (e.g. drop the right button from the set to make it an eyedropper).
pub const cv_pan_left = 1
pub const cv_pan_middle = 2
pub const cv_pan_right = 4

// CanvasEventKind tags every CanvasInputEvent delivered to on_input. Pointer
// down/move/up form a stroke (a button is held); hover is a button-less move;
// enter/leave bracket the pointer crossing the widget; wheel and key_* round out
// the set so a tool has the full input it needs.
pub enum CanvasEventKind {
	pointer_down // 0
	pointer_move // 1
	pointer_up   // 2
	hover        // 3
	enter        // 4
	leave        // 5
	wheel        // 6
	key_down     // 7
	key_up       // 8
}

// CanvasInputEvent is the single rich event the canvas hands to on_input. It is a
// plain value struct (no pointers) so it crosses the C-ABI cleanly; the Python
// layer reads its fields through vgui_canvas_event_* getters, exactly like
// PropertyGrid reads a &Property. Extending it = appending a field + a getter,
// without touching any dispatcher signature.
pub struct CanvasInputEvent {
pub mut:
	kind     CanvasEventKind
	x        int  // buffer pixel x (clamped to [0,width))
	y        int  // buffer pixel y (clamped to [0,height))
	in_image bool // true when the pointer was actually inside the image, not just clamped to it
	button   int  // 0 none, 1 left, 2 middle, 3 right
	clicks   int  // 2 = double-click
	wheel_x  f32
	wheel_y  f32
	keycode  int
	scancode int
	shift    bool
	ctrl     bool
	alt      bool
	// rctrl: specifically the RIGHT Ctrl key (see GuiEvent.rctrl) — lets a tool
	// claim a wheel gesture (e.g. brush size) without colliding with the
	// built-in left-Ctrl zoom shortcuts.
	rctrl bool
	// fx, fy: the pointer in buffer pixels as floats, NOT clamped (may be
	// negative or past width/height) — for tools that grab handles sitting on
	// or just outside the image edge (crop frame) or need sub-pixel positions.
	fx f32
	fy f32
}

// mouse_btn_to_int maps the V MouseButton enum to the stable wire values used in
// CanvasInputEvent (independent of the enum's ordinals).
fn mouse_btn_to_int(b MouseButton) int {
	return match b {
		.left { 1 }
		.middle { 2 }
		.right { 3 }
		.none_ { 0 }
	}
}

// Canvas - виджет-холст: RGBA-буфер + потоковая текстура + навигация
// (zoom/pan/полосы прокрутки) + мышиный/клавиатурный ввод для инструментов.
// Режимы показа: auto_fit (вписать с сохранением пропорций), stretch (растянуть
// на bounds без пропорций), либо ручной zoom со scroll_x/scroll_y.
@[heap]
pub struct Canvas {
pub mut:
	type_tag int = kind_canvas // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	width    int
	height   int
	pixels   []u8
	visible  bool = true
	enabled  bool = true
	tooltip  string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd      &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	// passive - холст только рисует: события не берёт и в фокус-учёт не
	// встаёт, ввод идёт виджету под ним (как у Icon/ImageBackground). Не
	// путать с enabled = false - тот рисует холст неактивным (вуаль).
	passive bool
	stretch bool // false = fit (preserve aspect), true = stretch to bounds
	// ── Zoom / pan / scroll (image navigation) ──
	// auto_fit = whole buffer scaled to fit bounds (the original behaviour). Once
	// the user zooms or pans it turns off and zoom + scroll take over, with
	// scrollbars; fit_to_view() returns to it. This lets a full-resolution image
	// be loaded (native size) yet navigated by zooming in and panning around.
	auto_fit     bool = true
	zoom         f32  = 1.0
	scroll_x     f32
	scroll_y     f32
	scroll_speed f32 = 40
	zoom_speed   f32 = 0.15
	hovered      bool
	// Pan drag (middle/right button)
	panning      bool
	pan_start_x  f32
	pan_start_y  f32
	pan_start_sx f32
	pan_start_sy f32
	// Scrollbar drag
	vsb_dragging          bool
	vsb_hovered           bool
	vsb_drag_start_y      f32
	vsb_drag_start_scroll f32
	hsb_dragging          bool
	hsb_hovered           bool
	hsb_drag_start_x      f32
	hsb_drag_start_scroll f32
	// Streaming texture mirroring `pixels` (sdl3_texture.v)
	texture Texture
	dirty   bool = true
	// Destination rect of the buffer inside bounds (computed in draw, reused in events)
	disp_x f32
	disp_y f32
	disp_w f32
	disp_h f32
	// Freehand drawing. `drawing` means a tool pointer-press is active (button
	// held after a non-pan press); `draw_button` remembers which button so the
	// matching release ends the stroke.
	drawing     bool
	draw_button MouseButton       = .none_
	on_draw     fn (x int, y int) = unsafe { nil }
	// Stroke drawing with phase: 0 = down, 1 = move, 2 = up. Unlike on_draw it
	// also fires on release (phase 2) and clamps the coordinate into the buffer,
	// so callers can implement shape tools (line/rect) with a rubber-band preview.
	on_stroke fn (phase int, x int, y int) = unsafe { nil }
	// ── Unified rich input (the full toolset surface) ──
	// on_input receives every pointer/hover/wheel/key event with modifiers,
	// button and clicks. It is a superset of on_draw/on_stroke (which remain as
	// conveniences for simple brushes); a real editor tool uses on_input alone.
	on_input  fn (ev &CanvasInputEvent) = unsafe { nil }
	cur_event CanvasInputEvent // reused storage; the pointer handed out is valid only during the call
	inside    bool             // pointer currently within bounds (drives enter/leave)
	// ── Brush-size cursor (overlay preview) ──
	// An outline circle drawn at the pointer to show a paint brush's reach. Off by
	// default; a paint tool turns it on and sets brush_radius (in BUFFER pixels —
	// scaled to screen by the current zoom) and brush_cursor_color (usually semi-
	// transparent). Purely an overlay: it is drawn on top of the image each frame
	// and never touches the pixel buffer.
	brush_cursor       bool
	brush_radius       int
	brush_cursor_color Color = Color{255, 255, 255, 140}
	// brush_min_px: the circle is never smaller than this on screen (logical
	// px) — a small sampling spot (eyedropper) stays visible when the image is
	// zoomed out. brush_ring: outline only (two strokes, light and dark), so the
	// spot under the cursor stays visible — for a picker rather than a brush.
	brush_min_px f32
	brush_ring   bool
	// ── Overlay (tool graphics on top of the image) ──
	// on_overlay is called at the end of draw, clipped to the viewport, to draw
	// a tool's frame/handles/guides in SCREEN coordinates (buf_to_screen maps
	// buffer pixels there, screen_scale gives screen px per buffer px). It never
	// touches the pixel buffer, so redrawing it costs no texture upload. V only.
	on_overlay fn (mut ctx RenderContext) = unsafe { nil }
	// Миникарта (навигатор): при увеличении, когда изображение не
	// помещается целиком, в правом нижнем углу - всё изображение
	// уменьшенным и рамка видимой части; щелчок и перетаскивание по ней
	// переносят вид в эту точку (см. nav_rect, draw_navigator).
	navigator      bool
	navigator_size f32 = 160 // длинная сторона миникарты, px
	nav_dragging   bool
	// ── Detail layer (high-resolution tile over the image) ──
	// A second RGBA picture drawn over the buffer rect detail_rect (BUFFER
	// pixels, fractional) after the image and before on_overlay - e.g. a
	// full-resolution fragment over a half-size preview: at zoom the screen
	// shows the dense tile instead of the magnified buffer. Its own texture,
	// so setting it never re-uploads the main buffer. set_detail/clear_detail.
	detail_px    []u8
	detail_w     int
	detail_h     int
	detail_rect  Rect
	detail_dirty bool
	detail_tex   Texture
	// ── Input routing policy ──
	// pan_buttons: bitmask (cv_pan_*) of buttons that drive built-in panning.
	// wheel_zoom: when true the wheel zooms; when false wheel events go to on_input
	// (so a tool can map the wheel to e.g. brush size, or zoom only with Ctrl).
	pan_buttons int  = cv_pan_middle | cv_pan_right
	wheel_zoom  bool = true
	// ── Keyboard focus (so tool shortcuts / Esc / arrows reach on_input) ──
	focused     bool
	focus_group int
	// take_keys: холст в фокусе забирает клавиши себе (on_input). false -
	// клавиши идут дальше: в меню, горячие клавиши окна (холст только для
	// мыши - пипетка, щелчки по индикатору)
	take_keys bool = true
}

// ─── Constructor ───────────────────────────────────────

// canvas создаёт холст width x height, залитый непрозрачным белым. Размеры
// меньше 1 заменяются на 1 (пустой буфер сломал бы деление в map_to_pixel).
pub fn canvas(width int, height int) &Canvas {
	w := if width > 0 { width } else { 1 }
	h := if height > 0 { height } else { 1 }
	mut px := []u8{len: w * h * 4, init: u8(255)} // opaque white
	return &Canvas{
		width:  w
		height: h
		pixels: px
	}
}

// ─── Pixel access ──────────────────────────────────────

// in_bounds - лежит ли пиксель (x, y) внутри буфера.
@[inline]
fn (c &Canvas) in_bounds(x int, y int) bool {
	return x >= 0 && y >= 0 && x < c.width && y < c.height
}

// set_pixel записывает пиксель (молча игнорирует выход за границы) и помечает
// буфер грязным: текстура обновится при следующем draw(); окно перерисуется
// само (widget_changed).
pub fn (mut c Canvas) set_pixel(x int, y int, col Color) {
	widget_changed()
	if !c.in_bounds(x, y) {
		return
	}
	i := (y * c.width + x) * 4
	c.pixels[i] = col.r
	c.pixels[i + 1] = col.g
	c.pixels[i + 2] = col.b
	c.pixels[i + 3] = col.a
	c.dirty = true
}

// get_pixel читает пиксель; вне буфера - прозрачный чёрный {0,0,0,0}.
pub fn (c &Canvas) get_pixel(x int, y int) Color {
	if !c.in_bounds(x, y) {
		return Color{0, 0, 0, 0}
	}
	i := (y * c.width + x) * 4
	return Color{c.pixels[i], c.pixels[i + 1], c.pixels[i + 2], c.pixels[i + 3]}
}

// fill заливает весь буфер цветом col (включая альфу, без смешивания).
pub fn (mut c Canvas) fill(col Color) {
	for i := 0; i < c.pixels.len; i += 4 {
		c.pixels[i] = col.r
		c.pixels[i + 1] = col.g
		c.pixels[i + 2] = col.b
		c.pixels[i + 3] = col.a
	}
	c.dirty = true
}

// clear resets every pixel to fully transparent.
pub fn (mut c Canvas) clear() {
	for i := 0; i < c.pixels.len; i++ {
		c.pixels[i] = 0
	}
	c.dirty = true
}

// pixels_ptr - указатель на сырой RGBA-буфер (width*height*4 байт) для прямого
// чтения/записи из Python. Указатель действителен, пока буфер не пересоздан
// (load_*, изменение размера); после записи надо вызвать mark_dirty().
pub fn (c &Canvas) pixels_ptr() voidptr {
	if c.pixels.len == 0 {
		return unsafe { nil }
	}
	return c.pixels.data
}

// pixels_len - размер буфера в байтах (width*height*4).
pub fn (c &Canvas) pixels_len() int {
	return c.pixels.len
}

// set_pixels overwrites the buffer from `src` (up to the buffer length).
pub fn (mut c Canvas) set_pixels(src voidptr, n int) {
	widget_changed()
	if unsafe { src == nil } || n <= 0 || c.pixels.len == 0 {
		return
	}
	count := if n < c.pixels.len { n } else { c.pixels.len }
	unsafe { vmemcpy(c.pixels.data, src, count) }
	c.dirty = true
}

// mark_dirty сообщает, что буфер изменён снаружи (через pixels_ptr): текстура
// будет перезалита при следующем draw().
pub fn (mut c Canvas) mark_dirty() {
	c.dirty = true
}

// ─── Primitives ────────────────────────────────────────
// Примитивы рисуют прямо в буфер через set_pixel: без сглаживания, без
// смешивания альфы (пиксель заменяется), выход за границы отсекается.

// draw_line - линия Брезенхэма от (x0,y0) до (x1,y1) включительно.
pub fn (mut c Canvas) draw_line(x0 int, y0 int, x1 int, y1 int, col Color) {
	// Bresenham
	mut x := x0
	mut y := y0
	dx := abs_int(x1 - x0)
	dy := -abs_int(y1 - y0)
	sx := if x0 < x1 { 1 } else { -1 }
	sy := if y0 < y1 { 1 } else { -1 }
	mut err := dx + dy
	for {
		c.set_pixel(x, y, col)
		if x == x1 && y == y1 {
			break
		}
		e2 := 2 * err
		if e2 >= dy {
			err += dy
			x += sx
		}
		if e2 <= dx {
			err += dx
			y += sy
		}
	}
}

// fill_rect - залитый прямоугольник x,y,w,h (w/h <= 0 - ничего).
pub fn (mut c Canvas) fill_rect(x int, y int, w int, h int, col Color) {
	for yy in y .. y + h {
		for xx in x .. x + w {
			c.set_pixel(xx, yy, col)
		}
	}
}

// draw_rect - контур прямоугольника толщиной 1 px.
pub fn (mut c Canvas) draw_rect(x int, y int, w int, h int, col Color) {
	if w <= 0 || h <= 0 {
		return
	}
	c.draw_line(x, y, x + w - 1, y, col)
	c.draw_line(x, y + h - 1, x + w - 1, y + h - 1, col)
	c.draw_line(x, y, x, y + h - 1, col)
	c.draw_line(x + w - 1, y, x + w - 1, y + h - 1, col)
}

// draw_circle - контур окружности радиуса r алгоритмом средней точки
// (восемь симметричных октантов за итерацию).
pub fn (mut c Canvas) draw_circle(cx int, cy int, r int, col Color) {
	if r < 0 {
		return
	}
	mut x := r
	mut y := 0
	mut err := 1 - r
	for x >= y {
		c.set_pixel(cx + x, cy + y, col)
		c.set_pixel(cx + y, cy + x, col)
		c.set_pixel(cx - y, cy + x, col)
		c.set_pixel(cx - x, cy + y, col)
		c.set_pixel(cx - x, cy - y, col)
		c.set_pixel(cx - y, cy - x, col)
		c.set_pixel(cx + y, cy - x, col)
		c.set_pixel(cx + x, cy - y, col)
		y++
		if err < 0 {
			err += 2 * y + 1
		} else {
			x--
			err += 2 * (y - x) + 1
		}
	}
}

// fill_circle - залитый круг: перебор квадрата со стороной 2r+1 и проверка dx^2+dy^2 <= r^2.
pub fn (mut c Canvas) fill_circle(cx int, cy int, r int, col Color) {
	if r < 0 {
		return
	}
	for dy in -r .. r + 1 {
		for dx in -r .. r + 1 {
			if dx * dx + dy * dy <= r * r {
				c.set_pixel(cx + dx, cy + dy, col)
			}
		}
	}
}

// ─── Image I/O ─────────────────────────────────────────
//
// load_* decode an image (any format SDL_image can read: png, jpg, webp, gif,
// tiff, bmp, ...) and replace the buffer with it, resizing the canvas to the
// image dimensions. save_file encodes the buffer to a file; the output format
// is chosen from the file extension (png/jpg/webp/gif/bmp; tiff is read-only -
// SDL_image cannot write it). Декодирование и кодирование - image_io.v.

// load_file loads an image file onto the canvas. Returns true on success.
pub fn (mut c Canvas) load_file(path string) bool {
	img := decode_image_file(path) or { return false }
	c.load_image(img)
	return true
}

// load_data loads an image from raw encoded bytes (png/jpg/... in memory).
pub fn (mut c Canvas) load_data(data []u8) bool {
	img := decode_image_bytes(data) or { return false }
	c.load_image(img)
	return true
}

// load_image replaces the buffer with a decoded picture (its pixel format,
// ABGR8888 tightly packed, is the canvas buffer format) and resizes the canvas.
fn (mut c Canvas) load_image(img RgbaImage) {
	c.width = img.w
	c.height = img.h
	c.pixels = img.pixels
	// Dimensions changed: drop the streaming texture so draw() recreates it at
	// the new size.
	c.destroy_texture()
	c.dirty = true
}

// save_file encodes the canvas buffer to an image file, format chosen from the
// extension. Returns true on success.
pub fn (mut c Canvas) save_file(path string) bool {
	if c.width <= 0 || c.height <= 0 || c.pixels.len == 0 {
		return false
	}
	return encode_image_file(path, c.width, c.height, c.pixels)
}

// ─── Texture management ────────────────────────────────

// ensure_texture гарантирует живую потоковую текстуру под текущий рендерер и
// размер буфера. Если текстура уже есть, принадлежит рендереру этого окна
// (проверка с поколением - защита от ABA, когда адрес рендерера переиспользован)
// и совпадает по размеру, ничего не делает. Иначе освобождает старую (destroy()
// сам не тронет текстуру мёртвого рендерера - SDL уже освободил её вместе с
// ним), создаёт новую и взводит dirty, чтобы буфер залился заново.
fn (mut c Canvas) ensure_texture(ctx &RenderContext) {
	if c.texture.belongs_to(ctx) && c.texture.w == c.width && c.texture.h == c.height {
		return
	}
	c.texture.destroy()
	c.texture = ctx.texture_streaming(c.width, c.height, .nearest)
	c.dirty = true
}

// destroy_texture освобождает основную и detail-текстуры (Texture.destroy:
// только при живом рендерере - у уничтоженного текстуры уже освобождены, и
// повторное удаление было бы use-after-free). Зовётся из load_image и слоем
// C-ABI при уничтожении виджета.
pub fn (mut c Canvas) destroy_texture() {
	c.texture.destroy()
	c.destroy_detail_texture()
}

// ─── Detail layer ──────────────────────────────────────

// set_detail shows an RGBA picture w x h (pixels: w*h*4 bytes, copied) over
// the buffer rect (x, y, rw, rh) in BUFFER pixels (fractional allowed): a
// tile denser than the buffer (rw < w) stays sharp at zoom. Replaces the
// previous detail; n < w*h*4 or empty size - clear_detail.
pub fn (mut c Canvas) set_detail(pixels voidptr, n int, w int, h int, x f32, y f32, rw f32, rh f32) {
	widget_changed()
	if unsafe { pixels == nil } || w <= 0 || h <= 0 || n < w * h * 4 || rw <= 0 || rh <= 0 {
		c.clear_detail()
		return
	}
	if c.detail_px.len != w * h * 4 {
		c.detail_px = []u8{len: w * h * 4}
	}
	unsafe { vmemcpy(c.detail_px.data, pixels, w * h * 4) }
	c.detail_w = w
	c.detail_h = h
	c.detail_rect = Rect{x, y, rw, rh}
	c.detail_dirty = true
}

// clear_detail removes the detail layer (the texture is kept for reuse)
pub fn (mut c Canvas) clear_detail() {
	c.detail_px = []u8{}
	c.detail_w = 0
	c.detail_h = 0
	c.detail_dirty = false
}

// has_detail - задан ли слой детализации.
pub fn (c &Canvas) has_detail() bool {
	return c.detail_w > 0
}

// visible_buf_rect - the part of the buffer visible in the viewport in the
// last drawn frame (BUFFER pixels, clipped to the buffer): what a detail
// tile must cover. Empty before the first draw.
pub fn (c &Canvas) visible_buf_rect() Rect {
	if c.disp_w <= 0 || c.disp_h <= 0 || c.width <= 0 || c.height <= 0 {
		return Rect{}
	}
	vp := c.viewport()
	kx := f32(c.width) / c.disp_w
	ky := f32(c.height) / c.disp_h
	x0 := max_f32(0, (vp.x - c.disp_x) * kx)
	y0 := max_f32(0, (vp.y - c.disp_y) * ky)
	x1 := min_f32(f32(c.width), (vp.x + vp.w - c.disp_x) * kx)
	y1 := min_f32(f32(c.height), (vp.y + vp.h - c.disp_y) * ky)
	if x1 <= x0 || y1 <= y0 {
		return Rect{}
	}
	return Rect{x0, y0, x1 - x0, y1 - y0}
}

// destroy_detail_texture - то же, что destroy_texture, но для текстуры слоя детализации.
fn (mut c Canvas) destroy_detail_texture() {
	c.detail_tex.destroy()
}

// draw_detail - the detail tile over the image (after compute_disp), clipped
// to the viewport. The texture is recreated on size or renderer change.
// Прямоугольник назначения получается переводом detail_rect из пикселей буфера
// в экранные координаты (buf_to_screen), поэтому плитка автоматически следует
// за zoom/pan. Пиксели заливаются в текстуру только когда detail_dirty (плитка менялась).
fn (mut c Canvas) draw_detail(mut ctx RenderContext, vp Rect) {
	if c.detail_w <= 0 {
		return
	}
	if !c.detail_tex.belongs_to(ctx) || c.detail_tex.w != c.detail_w
		|| c.detail_tex.h != c.detail_h {
		c.detail_tex.destroy()
		c.detail_tex = ctx.texture_streaming(c.detail_w, c.detail_h, .nearest)
		if !c.detail_tex.is_valid() {
			return
		}
		c.detail_dirty = true
	}
	if c.detail_dirty {
		c.detail_tex.update(c.detail_px)
		c.detail_dirty = false
	}
	r := c.detail_rect
	x0, y0 := c.buf_to_screen(r.x, r.y)
	x1, y1 := c.buf_to_screen(r.x + r.w, r.y + r.h)
	ctx.push_clip(vp)
	ctx.draw_texture(c.detail_tex, Rect{x0, y0, x1 - x0, y1 - y0})
	ctx.pop_clip()
}

// ─── Drawing ───────────────────────────────────────────

// buf_to_screen maps a buffer point (pixels, may be fractional or outside the
// buffer) to screen coordinates of the last drawn frame — for on_overlay.
pub fn (c &Canvas) buf_to_screen(x f32, y f32) (f32, f32) {
	if c.width <= 0 || c.height <= 0 {
		return c.disp_x, c.disp_y
	}
	return c.disp_x + x / f32(c.width) * c.disp_w, c.disp_y + y / f32(c.height) * c.disp_h
}

// screen_scale — screen pixels per buffer pixel in the last drawn frame
pub fn (c &Canvas) screen_scale() f32 {
	if c.width <= 0 {
		return 1
	}
	return c.disp_w / f32(c.width)
}

// eff_scale is the current display scale in screen pixels per buffer pixel.
fn (c &Canvas) eff_scale() f32 {
	if c.width <= 0 || c.height <= 0 {
		return 1.0
	}
	if c.auto_fit {
		b := c.bounds
		return min_f32(b.w / f32(c.width), b.h / f32(c.height))
	}
	return c.zoom
}

// displayed_size is the buffer's on-screen size in pixels.
fn (c &Canvas) displayed_size() (f32, f32) {
	if c.stretch {
		return c.bounds.w, c.bounds.h
	}
	z := c.eff_scale()
	return f32(c.width) * z, f32(c.height) * z
}

// needs_scrollbars - (нужна горизонтальная, нужна вертикальная) полоса.
// Полосы бывают только в ручном режиме масштаба (не auto_fit/stretch), когда
// показанное изображение больше bounds по соответствующей оси.
fn (c &Canvas) needs_scrollbars() (bool, bool) {
	if c.stretch || c.auto_fit {
		return false, false
	}
	dw, dh := c.displayed_size()
	return dw > c.bounds.w, dh > c.bounds.h
}

// viewport - область, где реально видно изображение: bounds минус место под
// полосы прокрутки (справа/снизу). Клип отрисовки и расчёт прокрутки идут по ней.
fn (c &Canvas) viewport() Rect {
	b := c.bounds
	h_sb, v_sb := c.needs_scrollbars()
	mut w := b.w
	mut h := b.h
	if v_sb {
		w -= cv_sb_w
	}
	if h_sb {
		h -= cv_sb_w
	}
	return Rect{b.x, b.y, max_f32(w, 0), max_f32(h, 0)}
}

// max_scroll - максимальные scroll_x/scroll_y: размер показанного изображения
// минус размер viewport (не меньше 0).
fn (c &Canvas) max_scroll() (f32, f32) {
	dw, dh := c.displayed_size()
	vp := c.viewport()
	return max_f32(0, dw - vp.w), max_f32(0, dh - vp.h)
}

// clamp_scroll зажимает scroll_x/scroll_y в [0, max_scroll].
fn (mut c Canvas) clamp_scroll() {
	ms_x, ms_y := c.max_scroll()
	c.scroll_x = clamp_f32(c.scroll_x, 0, ms_x)
	c.scroll_y = clamp_f32(c.scroll_y, 0, ms_y)
}

// image_draw_rect is the destination rect the buffer is rendered into; it is also
// what map_to_pixel uses, so mouse→pixel mapping stays correct under zoom/pan.
// Если изображение меньше viewport по оси (или режим fit/stretch) - оно
// центрируется; иначе левый верхний угол сдвинут на -scroll.
fn (c &Canvas) image_draw_rect() Rect {
	dw, dh := c.displayed_size()
	vp := c.viewport()
	if c.stretch || c.auto_fit {
		x := vp.x + (vp.w - dw) * 0.5
		y := vp.y + (vp.h - dh) * 0.5
		return Rect{x, y, dw, dh}
	}
	mut x := vp.x - c.scroll_x
	mut y := vp.y - c.scroll_y
	if dw < vp.w {
		x = vp.x + (vp.w - dw) * 0.5
	}
	if dh < vp.h {
		y = vp.y + (vp.h - dh) * 0.5
	}
	return Rect{x, y, dw, dh}
}

// compute_disp запоминает image_draw_rect в disp_x/y/w/h. Эти поля - «снимок
// последнего кадра»: по ним события переводят координаты мыши в пиксели буфера
// (map_to_pixel*), а buf_to_screen/screen_scale отдают их инструментам.
// Пересчитывается в начале каждого draw().
fn (mut c Canvas) compute_disp() {
	dr := c.image_draw_rect()
	c.disp_x = dr.x
	c.disp_y = dr.y
	c.disp_w = dr.w
	c.disp_h = dr.h
}

// Scrollbar geometry (track, thumb).
// Вертикальная: дорожка у правого края viewport; высота бегунка пропорциональна
// доле видимого (но не меньше 20 px), позиция - доле прокрутки от максимума.
// Пустые Rect{}, если прокрутка не нужна.
fn (c &Canvas) vsb_rects() (Rect, Rect) {
	_, dh := c.displayed_size()
	vp := c.viewport()
	b := c.bounds
	if dh <= vp.h {
		return Rect{}, Rect{}
	}
	track := Rect{b.x + b.w - cv_sb_w, vp.y, cv_sb_w, vp.h}
	thumb_h := max_f32(20, vp.h * (vp.h / dh))
	_, ms_y := c.max_scroll()
	ratio := if ms_y > 0 { c.scroll_y / ms_y } else { f32(0) }
	thumb := Rect{track.x + 1, track.y + ratio * (vp.h - thumb_h), cv_sb_w - 2, thumb_h}
	return track, thumb
}

// hsb_rects - то же для горизонтальной полосы (дорожка у нижнего края).
fn (c &Canvas) hsb_rects() (Rect, Rect) {
	dw, _ := c.displayed_size()
	vp := c.viewport()
	b := c.bounds
	if dw <= vp.w {
		return Rect{}, Rect{}
	}
	track := Rect{vp.x, b.y + b.h - cv_sb_w, vp.w, cv_sb_w}
	thumb_w := max_f32(20, vp.w * (vp.w / dw))
	ms_x, _ := c.max_scroll()
	ratio := if ms_x > 0 { c.scroll_x / ms_x } else { f32(0) }
	thumb := Rect{track.x + ratio * (vp.w - thumb_w), track.y + 1, thumb_w, cv_sb_w - 2}
	return track, thumb
}

// ─── Миникарта ─────────────────────────────────────────

// nav_rect - где рисуется миникарта (экранные px); пусто - не нужна:
// выключена, режим вписывания/растяжки или изображение видно целиком.
// Пропорции - как у буфера, длинная сторона navigator_size, но не больше
// половины видимой части (на маленьком окне не закрывать снимок).
fn (c &Canvas) nav_rect() Rect {
	if !c.navigator || c.stretch || c.auto_fit || c.width <= 0 || c.height <= 0 {
		return Rect{}
	}
	h_sb, v_sb := c.needs_scrollbars()
	if !h_sb && !v_sb {
		return Rect{}
	}
	vp := c.viewport()
	size := min_f32(c.navigator_size, min_f32(vp.w, vp.h) * 0.5)
	if size < 24 {
		return Rect{}
	}
	mut w := size
	mut h := size
	if c.width >= c.height {
		h = size * f32(c.height) / f32(c.width)
	} else {
		w = size * f32(c.width) / f32(c.height)
	}
	return Rect{vp.x + vp.w - w - cv_nav_margin, vp.y + vp.h - h - cv_nav_margin, w, h}
}

// draw_navigator - миникарта: подложка, та же текстура холста уменьшенной
// (своей копии нет - сглаживание linear только на время этого вызова) и
// рамка видимой части (светлая с тёмной обводкой - видна на любом снимке).
fn (mut c Canvas) draw_navigator(mut ctx RenderContext) {
	nr := c.nav_rect()
	if nr.w <= 0 || !c.texture.is_valid() {
		return
	}
	bg := Rect{nr.x - cv_nav_pad, nr.y - cv_nav_pad, nr.w + 2 * cv_nav_pad, nr.h + 2 * cv_nav_pad}
	ctx.fill_rounded_rect(bg, Color{20, 20, 22, 210}, 4)
	c.texture.set_scale(.linear)
	ctx.draw_texture(c.texture, nr)
	c.texture.set_scale(.nearest)
	vis := c.visible_buf_rect()
	if vis.w <= 0 {
		return
	}
	kx := nr.w / f32(c.width)
	ky := nr.h / f32(c.height)
	r := Rect{nr.x + vis.x * kx, nr.y + vis.y * ky, max_f32(vis.w * kx, 3), max_f32(vis.h * ky, 3)}
	ctx.draw_rect(Rect{r.x - 1, r.y - 1, r.w + 2, r.h + 2}, Color{0, 0, 0, 200})
	ctx.draw_rect(r, Color{255, 255, 255, 235})
}

// nav_center - точка миникарты (экранные px) - в центр видимой части
fn (mut c Canvas) nav_center(mx f32, my f32) {
	nr := c.nav_rect()
	if nr.w <= 0 {
		return
	}
	bx := clamp_f32((mx - nr.x) / nr.w, 0, 1) * f32(c.width)
	by := clamp_f32((my - nr.y) / nr.h, 0, 1) * f32(c.height)
	z := c.eff_scale()
	vp := c.viewport()
	c.scroll_x = bx * z - vp.w * 0.5
	c.scroll_y = by * z - vp.h * 0.5
	c.clamp_scroll()
}

// ─── Zoom / pan API ────────────────────────────────────

// get_zoom - текущий масштаб (экранных px на пиксель буфера); в auto_fit - вычисленный.
pub fn (c &Canvas) get_zoom() f32 {
	return c.eff_scale()
}

// set_zoom выключает auto_fit и ставит масштаб z (зажимается в
// [cv_min_zoom, cv_max_zoom]); прокрутка корректируется под новый размер.
pub fn (mut c Canvas) set_zoom(z f32) {
	widget_changed()
	c.auto_fit = false
	c.zoom = clamp_f32(z, cv_min_zoom, cv_max_zoom)
	c.clamp_scroll()
}

// set_pan_buttons sets which mouse buttons drive built-in panning (a cv_pan_*
// bitmask). Buttons left out of the set arrive at on_input as pointer events.
pub fn (mut c Canvas) set_pan_buttons(mask int) {
	widget_changed()
	c.pan_buttons = mask
}

// set_wheel_zoom toggles built-in cursor-anchored wheel zoom. When off, wheel
// events are delivered to on_input instead.
pub fn (mut c Canvas) set_wheel_zoom(on bool) {
	widget_changed()
	c.wheel_zoom = on
}

// set_focus_group assigns the Tab-navigation group for keyboard focus.
pub fn (mut c Canvas) set_focus_group(group int) {
	widget_changed()
	c.focus_group = group
}

// fit_to_view returns to the auto-fit state: the whole buffer centered, no scrollbars.
pub fn (mut c Canvas) fit_to_view() {
	c.auto_fit = true
	c.zoom = 1.0
	c.scroll_x = 0
	c.scroll_y = 0
}

// zoom_in / zoom_out - шаг масштаба в (1 + zoom_speed) раз вокруг центра bounds.
pub fn (mut c Canvas) zoom_in() {
	cx := c.bounds.x + c.bounds.w * 0.5
	cy := c.bounds.y + c.bounds.h * 0.5
	c.zoom_at(cx, cy, c.eff_scale() * (1.0 + c.zoom_speed))
}

pub fn (mut c Canvas) zoom_out() {
	cx := c.bounds.x + c.bounds.w * 0.5
	cy := c.bounds.y + c.bounds.h * 0.5
	c.zoom_at(cx, cy, c.eff_scale() / (1.0 + c.zoom_speed))
}

// zoom_at sets a new zoom level while keeping the buffer point under (mx,my) fixed
// on screen (cursor-anchored zoom). Uses the last drawn disp rect for the old scale.
// Алгоритм: точка буфера под курсором (img_x, img_y) в пикселях буфера
// = (mx - disp_x) / старый_масштаб; после смены масштаба хотим, чтобы она
// осталась в (mx, my), т.е. новый левый верхний угол = m - img * новый_масштаб,
// откуда scroll = viewport.origin - угол. Затем scroll зажимается.
fn (mut c Canvas) zoom_at(mx f32, my f32, new_zoom f32) {
	old_z := if c.disp_w > 0 { c.disp_w / f32(c.width) } else { c.eff_scale() }
	nz := clamp_f32(new_zoom, cv_min_zoom, cv_max_zoom)
	img_x := (mx - c.disp_x) / old_z
	img_y := (my - c.disp_y) / old_z
	c.auto_fit = false
	c.zoom = nz
	vp := c.viewport()
	new_dx := mx - img_x * nz
	new_dy := my - img_y * nz
	c.scroll_x = vp.x - new_dx
	c.scroll_y = vp.y - new_dy
	c.clamp_scroll()
}

// draw: регистрация в фокусе, создание/обновление текстуры (SDL_UpdateTexture
// только при dirty), расчёт disp-прямоугольника, вывод изображения под клипом
// viewport, затем detail-слой, полосы прокрутки, on_overlay и кольцо кисти.
// Если текстуру создать не удалось (нет рендерера) - не рисует ничего.
pub fn (mut c Canvas) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(c.enabled)
	if !c.visible {
		return
	}
	if !ctx.is_in_clip(c.bounds) {
		return
	}
	// Встроенные виджеты (ячейки, редакторы) неактивны вместе с владельцем;
	// всё содержимое приглушается вуалью поверх (enabled.v)
	ctx.begin_disabled(c.enabled)
	defer {
		ctx.end_disabled(c.enabled)
		if !en {
			ctx.draw_disabled_veil(c.bounds, ctx.theme.border_radius)
		}
	}

	if en && !c.passive {
		ctx.focus.register_canvas(&c, c.focus_group)
	} else {
		ctx.focus_block(&c)
	}

	c.ensure_texture(ctx)
	if !c.texture.is_valid() {
		return
	}

	if c.dirty {
		c.texture.update(c.pixels)
		c.dirty = false
	}

	c.clamp_scroll()
	c.compute_disp()
	vp := c.viewport()
	ctx.push_clip(vp)
	ctx.draw_texture(c.texture, Rect{c.disp_x, c.disp_y, c.disp_w, c.disp_h})
	ctx.pop_clip()
	c.draw_detail(mut ctx, vp)

	// Scrollbars (only when zoomed past fit)
	h_sb, v_sb := c.needs_scrollbars()
	if v_sb {
		track, thumb := c.vsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if c.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if c.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
	if h_sb {
		track, thumb := c.hsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if c.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if c.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}

	if c.on_overlay != unsafe { nil } {
		ctx.push_clip(vp)
		c.on_overlay(mut ctx)
		ctx.pop_clip()
	}
	// Миникарта - поверх подписей приложения (on_overlay), в своём углу
	c.draw_navigator(mut ctx)

	// Brush-size cursor: a filled (semi-transparent) disc at the pointer showing
	// the paint brush's reach. Drawn last (on top of the image), clipped to the
	// viewport, and only while the pointer hovers the widget. A faint dark outline
	// ring keeps its edge legible over light areas.
	if c.brush_cursor && c.hovered && c.brush_radius > 0 {
		mx := ctx.mouse_x
		my := ctx.mouse_y
		if vp.contains(mx, my) {
			mut rr := f32(c.brush_radius) * c.eff_scale()
			if rr < c.brush_min_px {
				rr = c.brush_min_px
			}
			ctx.push_clip(vp)
			if c.brush_ring {
				ctx.draw_circle(mx, my, rr + 1, Color{0, 0, 0, 200})
				ctx.draw_circle(mx, my, rr, c.brush_cursor_color)
				ctx.draw_circle(mx, my, rr - 1, Color{0, 0, 0, 200})
			} else {
				ctx.fill_circle(mx, my, rr, c.brush_cursor_color)
				ctx.draw_circle(mx, my, rr, Color{0, 0, 0, c.brush_cursor_color.a / 2})
			}
			ctx.pop_clip()
		}
	}
}

// ─── Events ────────────────────────────────────────────

// map_to_pixel converts widget coordinates to buffer pixel coordinates.
// Returns (x, y, true) when the point is inside the displayed buffer rect.
fn (c &Canvas) map_to_pixel(mx f32, my f32) (int, int, bool) {
	if c.disp_w <= 0 || c.disp_h <= 0 {
		return 0, 0, false
	}
	if mx < c.disp_x || my < c.disp_y || mx >= c.disp_x + c.disp_w || my >= c.disp_y + c.disp_h {
		return 0, 0, false
	}
	px := int((mx - c.disp_x) / c.disp_w * f32(c.width))
	py := int((my - c.disp_y) / c.disp_h * f32(c.height))
	cx := clamp_int(px, 0, c.width - 1)
	cy := clamp_int(py, 0, c.height - 1)
	return cx, cy, true
}

// emit вызывает on_draw(x, y) для пикселя под точкой, если она ВНУТРИ показанного
// изображения (за его краем - ничего: свободная кисть не должна "липнуть" к краю).
fn (mut c Canvas) emit(mx f32, my f32) {
	if c.on_draw == unsafe { nil } {
		return
	}
	px, py, ok := c.map_to_pixel(mx, my)
	if ok {
		c.on_draw(px, py)
	}
}

// map_to_pixel_clamped maps widget coords to buffer pixel coords, clamping the
// result into [0,width)/[0,height) instead of rejecting out-of-rect points. Used
// for strokes so dragging past the edge clamps to the border rather than vanishing.
fn (c &Canvas) map_to_pixel_clamped(mx f32, my f32) (int, int) {
	if c.disp_w <= 0 || c.disp_h <= 0 {
		return 0, 0
	}
	px := int((mx - c.disp_x) / c.disp_w * f32(c.width))
	py := int((my - c.disp_y) / c.disp_h * f32(c.height))
	return clamp_int(px, 0, c.width - 1), clamp_int(py, 0, c.height - 1)
}

// emit_stroke вызывает on_stroke(phase, x, y) с координатой, зажатой в буфер
// (в отличие от emit, штрих за краем не пропадает). phase: 0 - нажатие, 1 - движение, 2 - отпускание.
fn (mut c Canvas) emit_stroke(phase int, mx f32, my f32) {
	if c.on_stroke == unsafe { nil } {
		return
	}
	px, py := c.map_to_pixel_clamped(mx, my)
	c.on_stroke(phase, px, py)
}

// dispatch_input fills cur_event from the raw event and the (already mapped) pixel
// coordinate, then hands a pointer to on_input. The pointer is valid only for the
// duration of the call (single-threaded, synchronous), like the &Property handed
// to PropertyGrid.on_change.
fn (mut c Canvas) dispatch_input(kind CanvasEventKind, ev &GuiEvent, px int, py int, in_img bool) {
	if c.on_input == unsafe { nil } {
		return
	}
	c.cur_event = CanvasInputEvent{
		kind:     kind
		x:        px
		y:        py
		in_image: in_img
		button:   mouse_btn_to_int(ev.mouse_btn)
		clicks:   ev.clicks
		wheel_x:  ev.wheel_x
		wheel_y:  ev.wheel_y
		keycode:  ev.keycode
		scancode: ev.scancode
		shift:    ev.shift()
		ctrl:     ev.ctrl()
		alt:      ev.alt()
		rctrl:    ev.rctrl()
		fx:       if c.disp_w > 0 { (ev.mouse_x - c.disp_x) / c.disp_w * f32(c.width) } else { 0 }
		fy:       if c.disp_h > 0 { (ev.mouse_y - c.disp_y) / c.disp_h * f32(c.height) } else { 0 }
	}
	c.on_input(&c.cur_event)
}

// emit_pointer dispatches a pointer event to on_input, mapping coordinates the same
// way strokes do (clamped into the buffer) while reporting whether the point was
// genuinely inside the image rect.
fn (mut c Canvas) emit_pointer(kind CanvasEventKind, ev &GuiEvent) {
	if c.on_input == unsafe { nil } {
		return
	}
	px, py := c.map_to_pixel_clamped(ev.mouse_x, ev.mouse_y)
	_, _, in_img := c.map_to_pixel(ev.mouse_x, ev.mouse_y)
	c.dispatch_input(kind, ev, px, py, in_img)
}

// handle_event - маршрутизация ввода холста; true - событие поглощено.
// Схема по состояниям (первое подходящее выигрывает):
//   drawing    - идёт штрих инструмента: поглощает ВСЁ, пока не отпущена та же
//                кнопка; on_input получает pointer_move/pointer_up, а старые
//                on_draw/on_stroke - только для левой кнопки;
//   panning    - перетаскивание панорамы (кнопки из pan_buttons): двигаем scroll
//                на смещение мыши с момента нажатия;
//   vsb/hsb_dragging - перетаскивание бегунка полосы: смещение мыши в пикселях
//                дорожки переводится в прокрутку через ms / drag_range;
//   иначе      - mouse_move (enter/leave/hover + hover полос), нажатие
//                (полоса > панорама > инструмент), колесо, клавиши.
// Клавиши принимаются только при focused и take_keys; Tab отдаётся фокус-менеджеру.
pub fn (mut c Canvas) handle_event(event &GuiEvent, app &App) bool {
	if !c.visible || !c.enabled || c.passive {
		return false
	}

	ctx_ptr := app.get_active_ctx()

	// Active tool stroke (a pointer press is held) — highest priority. The
	// convenience on_draw/on_stroke fire only for the left button (their historical
	// semantics); on_input fires for whichever button started the stroke.
	if c.drawing {
		match event.typ {
			.mouse_move {
				c.emit_pointer(.pointer_move, event)
				if c.draw_button == .left {
					c.emit(event.mouse_x, event.mouse_y)
					c.emit_stroke(1, event.mouse_x, event.mouse_y) // move
				}
				return true
			}
			.mouse_up {
				if event.mouse_btn == c.draw_button {
					c.emit_pointer(.pointer_up, event)
					if c.draw_button == .left {
						c.emit_stroke(2, event.mouse_x, event.mouse_y) // up
					}
					c.drawing = false
					c.draw_button = .none_
				}
				return true
			}
			else {}
		}

		return true
	}

	// Перетаскивание по миникарте: вид следует за мышью
	if c.nav_dragging {
		match event.typ {
			.mouse_move {
				c.nav_center(event.mouse_x, event.mouse_y)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					c.nav_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// Pan drag (middle/right button).
	if c.panning {
		match event.typ {
			.mouse_move {
				dx := event.mouse_x - c.pan_start_x
				dy := event.mouse_y - c.pan_start_y
				c.scroll_x = c.pan_start_sx - dx
				c.scroll_y = c.pan_start_sy - dy
				c.clamp_scroll()
				return true
			}
			.mouse_up {
				if event.mouse_btn == .middle || event.mouse_btn == .right {
					c.panning = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// Vertical scrollbar drag.
	if c.vsb_dragging {
		match event.typ {
			.mouse_move {
				_, dh := c.displayed_size()
				vp := c.viewport()
				if vp.h <= 0 {
					return true
				}
				thumb_h := max_f32(20, vp.h * (vp.h / dh))
				drag_range := vp.h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - c.vsb_drag_start_y
				_, ms_y := c.max_scroll()
				c.scroll_y = clamp_f32(c.vsb_drag_start_scroll + dy * (ms_y / drag_range), 0, ms_y)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					c.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// Horizontal scrollbar drag.
	if c.hsb_dragging {
		match event.typ {
			.mouse_move {
				dw, _ := c.displayed_size()
				vp := c.viewport()
				if vp.w <= 0 {
					return true
				}
				thumb_w := max_f32(20, vp.w * (vp.w / dw))
				drag_range := vp.w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - c.hsb_drag_start_x
				ms_x, _ := c.max_scroll()
				c.scroll_x = clamp_f32(c.hsb_drag_start_scroll + dx * (ms_x / drag_range), 0, ms_x)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					c.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_leave {
			// курсор ушёл с виджета (event_route.v) - как движение за его пределы
			// событие leave приложению - как при движении за пределы
			if c.inside {
				c.emit_pointer(.leave, event)
			}
			c.inside = false
			c.hovered = false
			c.vsb_hovered = false
			c.hsb_hovered = false
		}
		.mouse_move {
			now_inside := c.bounds.contains(event.mouse_x, event.mouse_y)
			// enter / leave bracket the pointer crossing the widget; hover is a
			// button-less move inside it.
			if now_inside && !c.inside {
				c.emit_pointer(.enter, event)
			} else if !now_inside && c.inside {
				c.emit_pointer(.leave, event)
			}
			c.inside = now_inside
			c.hovered = now_inside
			if now_inside {
				c.emit_pointer(.hover, event)
				h_sb, v_sb := c.needs_scrollbars()
				if v_sb {
					track, _ := c.vsb_rects()
					c.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					c.vsb_hovered = false
				}
				if h_sb {
					track, _ := c.hsb_rects()
					c.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					c.hsb_hovered = false
				}
			} else {
				c.vsb_hovered = false
				c.hsb_hovered = false
			}
		}
		// Второй быстрый щелчок приходит обычным mouse_down с clicks = 2 (его
		// получает и on_input); следующий за ним mouse_dbl_click холсту не нужен
		.mouse_down {
			// нажатие мимо холста сюда не приходит: фокус снимает окно
			// (event_route.v, route_blur_outside)
			if !c.bounds.contains(event.mouse_x, event.mouse_y) {
				return false
			}
			btn := event.mouse_btn
			btn_bit := match btn {
				.left { cv_pan_left }
				.middle { cv_pan_middle }
				.right { cv_pan_right }
				.none_ { 0 }
			}

			// Миникарта - раньше всего: щелчок по ней не доходит до инструментов
			if btn == .left {
				nr := c.nav_rect()
				if nr.w > 0 && nr.contains(event.mouse_x, event.mouse_y) {
					c.nav_dragging = true
					c.nav_center(event.mouse_x, event.mouse_y)
					return true
				}
			}
			// The left button grabs a scrollbar thumb before anything else.
			if btn == .left {
				h_sb, v_sb := c.needs_scrollbars()
				if v_sb {
					_, thumb := c.vsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						c.vsb_dragging = true
						c.vsb_drag_start_y = event.mouse_y
						c.vsb_drag_start_scroll = c.scroll_y
						return true
					}
				}
				if h_sb {
					_, thumb := c.hsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						c.hsb_dragging = true
						c.hsb_drag_start_x = event.mouse_x
						c.hsb_drag_start_scroll = c.scroll_x
						return true
					}
				}
			}
			// Pan buttons (configurable) start panning.
			if btn_bit & c.pan_buttons != 0 {
				c.panning = true
				c.pan_start_x = event.mouse_x
				c.pan_start_y = event.mouse_y
				c.pan_start_sx = c.scroll_x
				c.pan_start_sy = c.scroll_y
				return true
			}
			// Otherwise it is a tool press: take keyboard focus and start a stroke.
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				ctx_mut.focus.focus_canvas(&c, c.focus_group)
			}
			c.focused = true
			c.drawing = true
			c.draw_button = btn
			c.emit_pointer(.pointer_down, event)
			if btn == .left {
				c.emit(event.mouse_x, event.mouse_y)
				c.emit_stroke(0, event.mouse_x, event.mouse_y) // down
			}
			return true
		}
		.mouse_wheel {
			// Read the live cursor position from the active context (wheel events
			// may carry a stale x/y).
			mut mx := event.mouse_x
			mut my := event.mouse_y
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if !c.bounds.contains(mx, my) {
				return false
			}
			if c.wheel_zoom && !event.rctrl() {
				// Built-in cursor-anchored zoom. Right-Ctrl is excluded so a tool can
				// reserve that combination (e.g. brush size) without it also zooming.
				if event.wheel_y > 0 {
					c.zoom_at(mx, my, c.eff_scale() * (1.0 + c.zoom_speed))
					return true
				} else if event.wheel_y < 0 {
					c.zoom_at(mx, my, c.eff_scale() / (1.0 + c.zoom_speed))
					return true
				}
			} else {
				// Hand the wheel to the tool (e.g. brush size, or Ctrl-to-zoom).
				px, py := c.map_to_pixel_clamped(mx, my)
				_, _, in_img := c.map_to_pixel(mx, my)
				c.dispatch_input(.wheel, event, px, py, in_img)
				return c.on_input != unsafe { nil }
			}
		}
		.key_down {
			if !c.focused || !c.take_keys {
				return false
			}
			// Tab keeps moving focus through the UI; every other key (Esc, arrows,
			// letters, …) is a tool shortcut delivered to on_input, reported at the
			// current cursor pixel so a tool can act under the pointer.
			if event.keycode == sdl_k_tab {
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.tab(event.shift())
				}
				return true
			}
			kx, ky, kin := c.key_cursor_pixel(ctx_ptr)
			c.dispatch_input(.key_down, event, kx, ky, kin)
			return c.on_input != unsafe { nil }
		}
		.key_up {
			if !c.focused || !c.take_keys {
				return false
			}
			kx, ky, kin := c.key_cursor_pixel(ctx_ptr)
			c.dispatch_input(.key_up, event, kx, ky, kin)
			return c.on_input != unsafe { nil }
		}
		else {}
	}

	return false
}

// key_cursor_pixel resolves the buffer pixel under the live cursor, used to report
// a position alongside keyboard events (key events carry no reliable mouse coords).
fn (c &Canvas) key_cursor_pixel(ctx_ptr &RenderContext) (int, int, bool) {
	if unsafe { ctx_ptr == nil } {
		return 0, 0, false
	}
	px, py := c.map_to_pixel_clamped(ctx_ptr.mouse_x, ctx_ptr.mouse_y)
	_, _, in_img := c.map_to_pixel(ctx_ptr.mouse_x, ctx_ptr.mouse_y)
	return px, py, in_img
}
