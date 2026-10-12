module vgui

// ═══════════════════════════════════════════════════════
// ImageView - виджет показа растровой картинки из файла (путь в path).
// Файл содержит: перечисление режимов ImageMode, структуру ImageView (состояние зума/прокрутки/
// перетаскивания и кэш SDL-текстуры), конструкторы, публичный API зума, геометрию (вьюпорт,
// полосы прокрутки, прямоугольник вывода), draw() и handle_event().
//
// Связи с остальной библиотекой:
//   * раскладка: measure() - в layout_measure.v (константный scrollable_hint), bounds раздаёт
//     контейнер; Layouted - widget_tree.v;
//   * загрузка: файл читается лениво при первой отрисовке (ensure_texture_loaded) через IMG_Load
//     и превращается в SDL-текстуру текущего renderer'а; время жизни текстуры привязано к
//     renderer'у (PROJECT.md, «Время жизни SDL-текстур»);
//   * фокуса и оверлеев нет; события клавиатуры принимаются только при наведении мыши.
// Описание режимов и жестов (ниже, на английском - оставлено как есть):
// ImageView — image display widget
//
// Display modes:
//   .fit     — scale to fit bounds, preserve aspect
//   .fill    — scale to fill bounds (may crop), preserve aspect
//   .stretch — fill exactly, ignore aspect
//   .native  — original size with scrollbars
//   .zoom    — user-controlled zoom + pan + scrollbars
//
// (Замечание: загрузка идёт через C.IMG_Load, как и в canvas.v; название «SDL2_image» ниже,
// возможно, устарело - проект на SDL3.)
// Supported formats (via SDL2_image):
//   PNG, JPG/JPEG, BMP, TIF/TIFF, WEBP, GIF (first frame), SVG (static)
//
// Interactions:
//   - Middle/Right mouse drag → pan (.native / .zoom)
//   - Wheel → zoom, any mode, no modifier needed — same trigger as Canvas's
//     built-in wheel_zoom (see Canvas.handle_event): a plain wheel tick over
//     the widget auto-leaves .fit/.fill/.stretch for .zoom, no prior click or
//     mode switch required.
//   - Shift+wheel → horizontal scroll (.native / .zoom, once the image is
//     wider than the viewport)
//   - Scrollbar drag
// ═══════════════════════════════════════════════════════

// Режим подгонки картинки под bounds (описание режимов - в шапке файла).
pub enum ImageMode {
	fit
	fill
	stretch
	native
	zoom
}

// Толщина полос прокрутки, минимальный и максимальный зум (1.0 = 100%).
const iv_sb_w = f32(12)
const iv_min_zoom = f32(0.05)
const iv_max_zoom = f32(20.0)

// ImageView: поля состояния сгруппированы - вид (path/mode/цвета), зум и прокрутка, перетаскивание
// (pan_* - панорамирование средней/правой кнопкой, vsb_*/hsb_* - перетаскивание бегунков полос),
// кэш текстуры (texture/tex_*), скорости (scroll_speed - px на шаг прокрутки, zoom_speed - доля
// приращения зума на шаг колеса). scroll_x/scroll_y - смещение в пикселях УЖЕ отмасштабированной картинки.
@[heap]
pub struct ImageView {
pub mut:
	type_tag int = kind_image_view // тег типа, см. widget_tag.v
	// Колесо мыши: false - виджет его не берёт (прокрутка уходит
	// контейнеру, например панели в ScrollBox)
	wheel        bool = true
	bounds       Rect
	path         string
	mode         ImageMode = .fit
	visible      bool      = true
	enabled      bool      = true
	hovered      bool
	pad          f32   = 2
	bg_color     Color = Color{0, 0, 0, 0}
	border_color Color = Color{0, 0, 0, 0}
	// Zoom/pan state
	zoom     f32 = 1.0
	scroll_x f32
	scroll_y f32
	// Pan drag state
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
	// Cached texture
	texture voidptr = unsafe { nil }
	// Renderer the texture belongs to. SDL ties textures to their creating
	// renderer; we must only SDL_DestroyTexture while that renderer is alive
	// (see is_renderer_alive_gen / the live-renderer registry in sdl3_window.v).
	// tex_renderer_gen is the registry generation snapshotted at texture
	// creation: a bare pointer match is ABA-prone (a new renderer can reuse a
	// dead one's address), the (pointer, generation) pair is not.
	tex_renderer     voidptr = unsafe { nil }
	tex_renderer_gen u64
	tex_w            int
	tex_h            int
	tex_path         string
	// Scroll settings
	scroll_speed f32 = 40
	zoom_speed   f32 = 0.15
	// Double-click callback (fires on a left double-click inside bounds). Nil by
	// default; a host uses it e.g. to open a full-size viewer for the image.
	on_dbl_click fn () = unsafe { nil }
}

// ─── Constructors ──────────────────────────────────────

// Конструкторы: пустой виджет, виджет с файлом (режим .fit) и с файлом и режимом.
pub fn image_view() &ImageView {
	return &ImageView{}
}

pub fn image_view_file(path string) &ImageView {
	return &ImageView{
		path: path
	}
}

pub fn image_view_with_mode(path string, mode ImageMode) &ImageView {
	return &ImageView{
		path: path
		mode: mode
	}
}

// ─── Public API ────────────────────────────────────────

// set_path меняет файл; при смене сбрасывает зум и прокрутку. Саму текстуру подменит
// ensure_texture_loaded при следующей отрисовке (сравнивает path с tex_path).
pub fn (mut iv ImageView) set_path(path string) {
	if iv.path != path {
		iv.path = path
		iv.zoom = 1.0
		iv.scroll_x = 0
		iv.scroll_y = 0
	}
}

// set_mode переключает режим и сбрасывает прокрутку; зум сохраняется только для .zoom/.native.
pub fn (mut iv ImageView) set_mode(mode ImageMode) {
	iv.mode = mode
	iv.scroll_x = 0
	iv.scroll_y = 0
	if mode != .zoom && mode != .native {
		iv.zoom = 1.0
	}
}

pub fn (iv &ImageView) get_zoom() f32 {
	return iv.zoom
}

// set_zoom задаёт зум (1.0 = 100%), зажатый в [iv_min_zoom, iv_max_zoom]. Режим не меняет:
// видим результат только в режиме .zoom. Кадр не инвалидирует - в своём цикле зовите Window.invalidate*.
pub fn (mut iv ImageView) set_zoom(z f32) {
	iv.zoom = clamp_f32(z, iv_min_zoom, iv_max_zoom)
}

// zoom_in/zoom_out - шаг зума на zoom_speed (мультипликативный, чтобы шаги были симметричны).
pub fn (mut iv ImageView) zoom_in() {
	iv.set_zoom(iv.zoom * (1.0 + iv.zoom_speed))
}

pub fn (mut iv ImageView) zoom_out() {
	iv.set_zoom(iv.zoom / (1.0 + iv.zoom_speed))
}

// reset_zoom - 100% и прокрутка в начало.
pub fn (mut iv ImageView) reset_zoom() {
	iv.zoom = 1.0
	iv.scroll_x = 0
	iv.scroll_y = 0
}

// image_size - размер исходной картинки в пикселях; (0, 0), пока текстура не загружена или файл не открылся.
pub fn (iv &ImageView) image_size() (int, int) {
	return iv.tex_w, iv.tex_h
}

// ─── Texture management ────────────────────────────────

// ensure_texture_loaded лениво загружает файл в текстуру текущего renderer'а.
// Ничего не делает, если путь пуст или текстура уже загружена для этого пути. При смене пути
// старая текстура уничтожается - но только если её renderer ещё жив (иначе SDL уже освободил её
// вместе с renderer'ом, и повторный SDL_DestroyTexture - двойное освобождение).
// Ошибка загрузки (IMG_Load/CreateTexture вернули nil) не выбрасывается: tex_path запоминается,
// чтобы не пытаться читать битый файл каждый кадр, а draw() покажет «Failed to load».
fn (mut iv ImageView) ensure_texture_loaded(ctx &RenderContext) {
	if iv.path.len == 0 {
		return
	}
	if unsafe { iv.texture != nil } && iv.tex_path == iv.path {
		return
	}
	// Destroy old texture if any (only while its renderer is still alive —
	// generation check guards against a new renderer reusing the old address)
	if unsafe { iv.texture != nil } {
		if is_renderer_alive_gen(iv.tex_renderer, iv.tex_renderer_gen) {
			C.SDL_DestroyTexture(iv.texture)
		}
		iv.texture = unsafe { nil }
		iv.tex_renderer = unsafe { nil }
		iv.tex_renderer_gen = 0
	}
	iv.tex_w = 0
	iv.tex_h = 0

	// // Surface (память CPU) нужен только чтобы создать текстуру; сразу освобождаем.
	// // Размер берём у текстуры (float в SDL3), а не у surface.
	surface := C.IMG_Load(iv.path.str)
	if unsafe { surface == nil } {
		iv.tex_path = iv.path
		return
	}
	texture := C.SDL_CreateTextureFromSurface(ctx.renderer, surface)
	C.SDL_DestroySurface(surface)
	if unsafe { texture == nil } {
		iv.tex_path = iv.path
		return
	}
	C.SDL_SetTextureBlendMode(texture, sdl_blendmode_blend)

	// Query size from the texture
	mut wf := f32(0)
	mut hf := f32(0)
	C.SDL_GetTextureSize(texture, &wf, &hf)
	iv.tex_w = int(wf)
	iv.tex_h = int(hf)

	iv.texture = texture
	iv.tex_renderer = ctx.renderer
	// Запоминаем (renderer, поколение): одного указателя мало, новый renderer может получить адрес умершего (ABA).
	iv.tex_renderer_gen = renderer_generation(ctx.renderer)
	iv.tex_path = iv.path
}

// destroy_texture освобождает текстуру (идемпотентно); зовётся при уничтожении виджета/окна. Ниже - почему проверяется жизнь renderer'а.
pub fn (mut iv ImageView) destroy_texture() {
	if unsafe { iv.texture != nil } {
		// Only free if the owning renderer is still alive. If the window/renderer
		// was already torn down, SDL has already destroyed this texture and a
		// second SDL_DestroyTexture would be a use-after-free / double-free.
		// The generation check additionally rejects a *different* renderer that
		// happens to live at the old address (ABA).
		if is_renderer_alive_gen(iv.tex_renderer, iv.tex_renderer_gen) {
			C.SDL_DestroyTexture(iv.texture)
		}
		iv.texture = unsafe { nil }
		iv.tex_renderer = unsafe { nil }
		iv.tex_renderer_gen = 0
	}
	iv.tex_path = ''
}

// ─── Geometry ──────────────────────────────────────────

// has_texture - есть ли пригодная к рисованию текстура (не nil и ненулевой размер).
fn (iv &ImageView) has_texture() bool {
	return unsafe { iv.texture != nil } && iv.tex_w > 0 && iv.tex_h > 0
}

// Inner rect (bounds minus padding)
// Внутренний прямоугольник: bounds без pad.
fn (iv &ImageView) inner_rect() Rect {
	return iv.bounds.shrunk(iv.pad)
}

// Effective zoom taking mode into account
// effective_zoom - реальный масштаб при текущем режиме: .fit - по меньшей стороне (вписать),
// .fill - по большей (закрыть всё, лишнее обрезается), .native - 1.0, .zoom - поле zoom.
// Для .stretch не используется (масштаб по осям разный, см. displayed_size).
fn (iv &ImageView) effective_zoom() f32 {
	if !iv.has_texture() {
		return 1.0
	}
	inner := iv.inner_rect()
	match iv.mode {
		.fit {
			sx := inner.w / f32(iv.tex_w)
			sy := inner.h / f32(iv.tex_h)
			return min_f32(sx, sy)
		}
		.fill {
			sx := inner.w / f32(iv.tex_w)
			sy := inner.h / f32(iv.tex_h)
			return max_f32(sx, sy)
		}
		.stretch {
			return 1.0 // handled separately
		}
		.native {
			return 1.0
		}
		.zoom {
			return iv.zoom
		}
	}
}

// Displayed image size (scaled)
// displayed_size - размер картинки на экране после масштабирования (для .stretch - ровно inner).
fn (iv &ImageView) displayed_size() (f32, f32) {
	if !iv.has_texture() {
		return 0, 0
	}
	if iv.mode == .stretch {
		inner := iv.inner_rect()
		return inner.w, inner.h
	}
	z := iv.effective_zoom()
	return f32(iv.tex_w) * z, f32(iv.tex_h) * z
}

// needs_scrollbars - (горизонтальная, вертикальная): полосы нужны только в .native/.zoom и когда
// картинка больше внутренней области. Проверка идёт по inner, а не по viewport, поэтому появление
// одной полосы не убирает другую (viewport сам уменьшается на толщину видимой полосы).
fn (iv &ImageView) needs_scrollbars() (bool, bool) {
	if !iv.has_texture() {
		return false, false
	}
	if iv.mode != .native && iv.mode != .zoom {
		return false, false
	}
	dw, dh := iv.displayed_size()
	inner := iv.inner_rect()
	h_sb := dw > inner.w
	v_sb := dh > inner.h
	return h_sb, v_sb
}

// viewport - область, где реально рисуется картинка: inner минус место под видимые полосы прокрутки.
fn (iv &ImageView) viewport() Rect {
	inner := iv.inner_rect()
	h_sb, v_sb := iv.needs_scrollbars()
	mut w := inner.w
	mut h := inner.h
	if v_sb {
		w -= iv_sb_w
	}
	if h_sb {
		h -= iv_sb_w
	}
	return Rect{inner.x, inner.y, max_f32(w, 0), max_f32(h, 0)}
}

// max_scroll - максимальные scroll_x/scroll_y: на сколько картинка шире/выше вьюпорта (не меньше 0).
fn (iv &ImageView) max_scroll() (f32, f32) {
	dw, dh := iv.displayed_size()
	vp := iv.viewport()
	return max_f32(0, dw - vp.w), max_f32(0, dh - vp.h)
}

// Scrollbar geometry
// Геометрия полос: (дорожка, бегунок). Если полоса не нужна - два пустых Rect.
// Длина бегунка пропорциональна доле видимой части (но не меньше 20 px), позиция - доле прокрутки.
fn (iv &ImageView) vsb_rects() (Rect, Rect) {
	_, dh := iv.displayed_size()
	vp := iv.viewport()
	inner := iv.inner_rect()
	if dh <= vp.h {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: inner.x + inner.w - iv_sb_w
		y: vp.y
		w: iv_sb_w
		h: vp.h
	}
	thumb_h := max_f32(20, vp.h * (vp.h / dh))
	_, ms_y := iv.max_scroll()
	ratio := if ms_y > 0 { iv.scroll_y / ms_y } else { f32(0) }
	thumb := Rect{
		x: track.x + 1
		y: track.y + ratio * (vp.h - thumb_h)
		w: iv_sb_w - 2
		h: thumb_h
	}
	return track, thumb
}

fn (iv &ImageView) hsb_rects() (Rect, Rect) {
	dw, _ := iv.displayed_size()
	vp := iv.viewport()
	inner := iv.inner_rect()
	if dw <= vp.w {
		return Rect{}, Rect{}
	}
	track := Rect{
		x: vp.x
		y: inner.y + inner.h - iv_sb_w
		w: vp.w
		h: iv_sb_w
	}
	thumb_w := max_f32(20, vp.w * (vp.w / dw))
	ms_x, _ := iv.max_scroll()
	ratio := if ms_x > 0 { iv.scroll_x / ms_x } else { f32(0) }
	thumb := Rect{
		x: track.x + ratio * (vp.w - thumb_w)
		y: track.y + 1
		w: thumb_w
		h: iv_sb_w - 2
	}
	return track, thumb
}

// clamp_scroll держит прокрутку в допустимых пределах; зовётся после любого изменения зума, режима или размера.
fn (mut iv ImageView) clamp_scroll() {
	ms_x, ms_y := iv.max_scroll()
	iv.scroll_x = clamp_f32(iv.scroll_x, 0, ms_x)
	iv.scroll_y = clamp_f32(iv.scroll_y, 0, ms_y)
}

// Destination rect for drawing the image
// image_draw_rect - куда рисовать картинку. Режимы .fit/.fill/.stretch: по центру вьюпорта
// (у .fill выступающие края обрежет clip). .native/.zoom: прижата к левому верхнему углу
// со сдвигом на прокрутку, а по оси, где картинка меньше вьюпорта, - центрируется.
fn (iv &ImageView) image_draw_rect() Rect {
	dw, dh := iv.displayed_size()
	vp := iv.viewport()

	match iv.mode {
		.fit, .fill, .stretch {
			// Center within viewport (for fit: centered; for fill: centered-cropped)
			mut x := vp.x + (vp.w - dw) * 0.5
			mut y := vp.y + (vp.h - dh) * 0.5
			return Rect{x, y, dw, dh}
		}
		.native, .zoom {
			// Top-left anchored, with scroll offset; center if smaller than viewport
			mut x := vp.x - iv.scroll_x
			mut y := vp.y - iv.scroll_y
			if dw < vp.w {
				x = vp.x + (vp.w - dw) * 0.5
			}
			if dh < vp.h {
				y = vp.y + (vp.h - dh) * 0.5
			}
			return Rect{x, y, dw, dh}
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

// draw: подгружает текстуру при необходимости, фон и рамка (цвета из темы, если свои не заданы),
// затем либо заглушка («(no image)» / «Failed to load»), либо текстура, обрезанная вьюпортом,
// и полосы прокрутки. Побочный эффект - clamp_scroll() каждый кадр, чтобы смена размера окна
// не оставила прокрутку за пределами.
pub fn (mut iv ImageView) draw(mut ctx RenderContext) {
	if !iv.visible {
		return
	}
	if !ctx.is_in_clip(iv.bounds) {
		return
	}

	iv.ensure_texture_loaded(ctx)
	iv.clamp_scroll()

	// Background
	if iv.bg_color.a > 0 {
		ctx.fill_rounded_rect(iv.bounds, iv.bg_color, ctx.theme.border_radius)
	} else {
		ctx.fill_rounded_rect(iv.bounds, ctx.theme.input_bg, ctx.theme.border_radius)
	}

	// Border
	bc := if iv.border_color.a > 0 { iv.border_color } else { ctx.theme.input_border }
	ctx.draw_rounded_rect(iv.bounds, bc, ctx.theme.border_radius)

	if !iv.has_texture() {
		// Placeholder text
		font := ctx.get_font(.regular, 0)
		msg := if iv.path.len == 0 { '(no image)' } else { 'Failed to load:\n${iv.path}' }
		lines := msg.split('\n')
		fh := ctx.font_height_of(font)
		total_h := f32(lines.len) * fh
		mut y := iv.bounds.y + (iv.bounds.h - total_h) * 0.5
		for line in lines {
			lw := ctx.measure_text_with_font(line, font).x
			x := iv.bounds.x + (iv.bounds.w - lw) * 0.5
			ctx.draw_text_with_font(line, x, y, ctx.theme.text_secondary, font)
			y += fh
		}
		return
	}

	vp := iv.viewport()
	dr := iv.image_draw_rect()

	ctx.push_clip(vp)

	// Render texture
	sdl_dst := C.SDL_FRect{
		x: dr.x
		y: dr.y
		w: dr.w
		h: dr.h
	}
	C.SDL_RenderTexture(ctx.renderer, iv.texture, unsafe { nil }, &sdl_dst)

	ctx.pop_clip()

	// Scrollbars
	h_sb, v_sb := iv.needs_scrollbars()
	if v_sb {
		track, thumb := iv.vsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if iv.vsb_dragging {
			ctx.theme.scrollbar_drag
		} else if iv.vsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
	if h_sb {
		track, thumb := iv.hsb_rects()
		if ctx.theme.scrollbar_bg.a > 0 {
			ctx.fill_rounded_rect(track, ctx.theme.scrollbar_bg, 3)
		}
		tc := if iv.hsb_dragging {
			ctx.theme.scrollbar_drag
		} else if iv.hsb_hovered {
			ctx.theme.scrollbar_hover
		} else {
			ctx.theme.scrollbar_thumb
		}
		ctx.fill_rounded_rect(thumb, tc, 3)
	}
}

// ─── Events ────────────────────────────────────────────

// handle_event: возвращает true, если событие поглощено. Приоритет (важен порядок блоков):
//   1. идёт панорамирование (panning) - забирает все события до отпускания средней/правой кнопки;
//   2. идёт перетаскивание вертикального / 3. горизонтального бегунка - то же для левой кнопки;
//   4. иначе обычная обработка: hover, двойной клик (on_dbl_click), нажатия (бегунки, панорама),
//      колесо (зум/горизонтальная прокрутка), стрелки и Ctrl+/-/0.
// Сдвиг бегунка пересчитывается в прокрутку через отношение max_scroll / длина хода бегунка.
pub fn (mut iv ImageView) handle_event(event &GuiEvent, app &App) bool {
	if !iv.visible || !iv.enabled {
		return false
	}

	// Pan drag in progress
	if iv.panning {
		match event.typ {
			.mouse_move {
				dx := event.mouse_x - iv.pan_start_x
				dy := event.mouse_y - iv.pan_start_y
				iv.scroll_x = iv.pan_start_sx - dx
				iv.scroll_y = iv.pan_start_sy - dy
				iv.clamp_scroll()
				return true
			}
			.mouse_up {
				if event.mouse_btn == .middle || event.mouse_btn == .right {
					iv.panning = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// Vertical scrollbar drag
	if iv.vsb_dragging {
		match event.typ {
			.mouse_move {
				_, dh := iv.displayed_size()
				vp := iv.viewport()
				if vp.h <= 0 {
					return true
				}
				thumb_h := max_f32(20, vp.h * (vp.h / dh))
				drag_range := vp.h - thumb_h
				if drag_range <= 0 {
					return true
				}
				dy := event.mouse_y - iv.vsb_drag_start_y
				_, ms_y := iv.max_scroll()
				iv.scroll_y =
					clamp_f32(iv.vsb_drag_start_scroll + dy * (ms_y / drag_range), 0, ms_y)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					iv.vsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	// Horizontal scrollbar drag
	if iv.hsb_dragging {
		match event.typ {
			.mouse_move {
				dw, _ := iv.displayed_size()
				vp := iv.viewport()
				if vp.w <= 0 {
					return true
				}
				thumb_w := max_f32(20, vp.w * (vp.w / dw))
				drag_range := vp.w - thumb_w
				if drag_range <= 0 {
					return true
				}
				dx := event.mouse_x - iv.hsb_drag_start_x
				ms_x, _ := iv.max_scroll()
				iv.scroll_x =
					clamp_f32(iv.hsb_drag_start_scroll + dx * (ms_x / drag_range), 0, ms_x)
				return true
			}
			.mouse_up {
				if event.mouse_btn == .left {
					iv.hsb_dragging = false
				}
				return true
			}
			else {}
		}

		return true
	}

	match event.typ {
		.mouse_move {
			iv.hovered = iv.bounds.contains(event.mouse_x, event.mouse_y)
			if iv.hovered {
				h_sb, v_sb := iv.needs_scrollbars()
				if v_sb {
					track, _ := iv.vsb_rects()
					iv.vsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					iv.vsb_hovered = false
				}
				if h_sb {
					track, _ := iv.hsb_rects()
					iv.hsb_hovered = track.contains(event.mouse_x, event.mouse_y)
				} else {
					iv.hsb_hovered = false
				}
			} else {
				iv.vsb_hovered = false
				iv.hsb_hovered = false
			}
		}
		.mouse_dbl_click {
			// A left double-click inside the view fires the host callback (e.g. open
			// a full-size viewer). Only claim the event if a callback is set.
			if iv.bounds.contains(event.mouse_x, event.mouse_y) && iv.on_dbl_click != unsafe { nil } {
				iv.on_dbl_click()
				return true
			}
		}
		.mouse_down {
			if !iv.hovered {
				return false
			}

			// Scrollbar thumb drag
			if event.mouse_btn == .left {
				h_sb, v_sb := iv.needs_scrollbars()
				if v_sb {
					_, thumb := iv.vsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						iv.vsb_dragging = true
						iv.vsb_drag_start_y = event.mouse_y
						iv.vsb_drag_start_scroll = iv.scroll_y
						return true
					}
				}
				if h_sb {
					_, thumb := iv.hsb_rects()
					if thumb.contains(event.mouse_x, event.mouse_y) {
						iv.hsb_dragging = true
						iv.hsb_drag_start_x = event.mouse_x
						iv.hsb_drag_start_scroll = iv.scroll_x
						return true
					}
				}
			}

			// Pan drag with middle or right mouse button (native/zoom modes)
			if (event.mouse_btn == .middle || event.mouse_btn == .right)
				&& (iv.mode == .native || iv.mode == .zoom) {
				iv.panning = true
				iv.pan_start_x = event.mouse_x
				iv.pan_start_y = event.mouse_y
				iv.pan_start_sx = iv.scroll_x
				iv.pan_start_sy = iv.scroll_y
				return true
			}
		}
		.mouse_wheel {
			if !iv.wheel {
				return false
			}
			// Recompute containment from the LIVE cursor position (wheel events
			// may carry stale x/y, same as Canvas.handle_event) instead of
			// gating on `iv.hovered` — that flag only updates on `.mouse_move`,
			// so without a prior pointer move over the widget (e.g. right after
			// switching tabs, cursor already sitting over it) it stayed false
			// and silently ate every wheel tick until the next mouse move.
			mut mx := event.mouse_x
			mut my := event.mouse_y
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mx = ctx_ptr.mouse_x
				my = ctx_ptr.mouse_y
			}
			if !iv.bounds.contains(mx, my) {
				return false
			}
			if event.wheel_y == 0 {
				return false
			}

			// Shift+wheel pans horizontally once the image is wider than the
			// viewport (native/zoom modes); otherwise the wheel always zooms —
			// no Ctrl or prior mode switch needed (matches Canvas's default
			// wheel_zoom), auto-leaving .fit/.fill/.stretch for .zoom on the
			// first tick.
			if event.shift() && (iv.mode == .native || iv.mode == .zoom) {
				old := iv.scroll_x
				iv.scroll_x -= event.wheel_y * iv.scroll_speed
				iv.clamp_scroll()
				return iv.scroll_x != old
			}

			if iv.mode != .zoom {
				// Seed the zoom level from the CURRENT effective scale (fit/fill)
				// before switching, same as Canvas.zoom_at starting from
				// eff_scale() — otherwise the image would jump to 100% first and
				// only then zoom from there, a visible snap on the first tick.
				cur_scale := iv.effective_zoom()
				iv.set_mode(.zoom)
				iv.zoom = clamp_f32(cur_scale, iv_min_zoom, iv_max_zoom)
			}
			old_zoom := iv.zoom
			if event.wheel_y > 0 {
				iv.zoom_to_center(iv.zoom * (1.0 + iv.zoom_speed))
			} else {
				iv.zoom_to_center(iv.zoom / (1.0 + iv.zoom_speed))
			}
			return iv.zoom != old_zoom
		}
		.key_down {
			if !iv.hovered {
				return false
			}
			if iv.mode != .native && iv.mode != .zoom {
				return false
			}

			match event.keycode {
				sdl_k_up {
					iv.scroll_y -= iv.scroll_speed
					iv.clamp_scroll()
					return true
				}
				sdl_k_down {
					iv.scroll_y += iv.scroll_speed
					iv.clamp_scroll()
					return true
				}
				sdl_k_left {
					iv.scroll_x -= iv.scroll_speed
					iv.clamp_scroll()
					return true
				}
				sdl_k_right {
					iv.scroll_x += iv.scroll_speed
					iv.clamp_scroll()
					return true
				}
				else {}
			}

			if event.ctrl() && iv.mode == .zoom {
				if event.keycode == int(`+`) || event.keycode == int(`=`) {
					iv.zoom_in()
					return true
				}
				if event.keycode == int(`-`) {
					iv.zoom_out()
					return true
				}
				if event.keycode == int(`0`) {
					iv.reset_zoom()
					return true
				}
			}
		}
		else {}
	}

	return false
}

// Zoom keeping the center of the current viewport fixed on the same image point.
// new_zoom is the desired zoom level (will be clamped).
fn (mut iv ImageView) zoom_to_center(new_zoom f32) {
	old_z := iv.zoom
	iv.zoom = clamp_f32(new_zoom, iv_min_zoom, iv_max_zoom)
	if iv.zoom == old_z {
		return
	}

	vp := iv.viewport()

	// The image-space coordinate at the center of the viewport before zoom:
	//   center_img_x = (scroll_x + vp.w/2) / old_z
	//   center_img_y = (scroll_y + vp.h/2) / old_z
	// After zoom, we want the same image point at viewport center:
	//   new_scroll_x = center_img_x * new_zoom - vp.w/2
	// Note: viewport geometry doesn't change because scrollbar presence
	// is recalculated lazily — but the approximation is good enough.

	half_w := vp.w * 0.5
	half_h := vp.h * 0.5
	// Image-space center point
	cx := (iv.scroll_x + half_w) / old_z
	cy := (iv.scroll_y + half_h) / old_z
	// New scroll to keep that point centered
	iv.scroll_x = cx * iv.zoom - half_w
	iv.scroll_y = cy * iv.zoom - half_h
	iv.clamp_scroll()
}
