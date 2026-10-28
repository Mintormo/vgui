module vgui

// ═══════════════════════════════════════════════════════
// borderless.v - поддержка окон без системной рамки (WindowMode
// .borderless_resizable): изменение размера за края и перетаскивание окна
// за "заголовок", нарисованный самим приложением (виджет WindowTitleDrag,
// windows_title_drag.v).
//
// Схема:
//   - BorderlessData лежит в Window.hittest_data (voidptr; nil - режим выключен).
//     Создаётся/обновляется enable_borderless_resize(), сбрасывается
//     disable_borderless_hittest().
//   - SDL hit-test (borderless_hit_test_callback) отвечает ТОЛЬКО за края для
//     ресайза. Перетаскивание окна сознательно сделано вручную (см. ниже), а не
//     через SDL_HITTEST_DRAGGABLE: draggable-зона съедает mouse_down/up и
//     двойной щелчок, а приложению они нужны (кнопки свернуть/развернуть/закрыть
//     лежат прямо на заголовке).
//   - Каждый кадр Window.render() (sdl3_window.v) перерегистрирует прямоугольники
//     перетаскивания и заголовка из ctx.pending_drag_rects/pending_titlebar_rects,
//     которые заполняют виджеты WindowTitleDrag при draw().
//   - Мышиные события из App.process_events (sdl3_app.v) вызывают
//     borderless_on_drag_start / _move / _on_mouse_up, а в конце обработки
//     borderless_check_dbl_click превращается в maximize/restore окна.
//   - Единицы: прямоугольники хранятся в физических координатах окна SDL
//     (логические * ctx.ui_scale), а функции-входы принимают логические
//     координаты и умножают на ui_scale сами.
// ═══════════════════════════════════════════════════════

// BorderlessData - состояние borderless-режима окна (Window.hittest_data).
struct BorderlessData {
mut:
	resize_border  int    // толщина зоны ресайза у краёв окна, SDL-пиксели; 0 - ресайз выключен
	drag_rects     []Rect // зоны, с которых можно тащить окно (физические px); пополняются каждый кадр
	titlebar_rects []Rect // Y-range of WindowTitleDrag rows (SDL window-logical coords)
	last_zone      int = sdl_hittest_normal // последняя зона hit-test: курсор меняем только при её смене
	// Manual drag state: окно двигается по смещению ГЛОБАЛЬНОЙ мыши
	// (SDL_GetGlobalMouseState), а не оконной - координаты в окне плывут,
	// пока само окно движется.
	dragging      bool
	drag_start_mx f32 // global mouse X when drag started
	drag_start_my f32
	drag_start_wx int // window X when drag started
	drag_start_wy int
	// Double-click detection (updated on mouse_up)
	last_click_time   u64
	last_click_x      f32
	last_click_y      f32
	pending_dbl_click bool // двойной щелчок по заголовку замечен; забирается borderless_check_dbl_click
}

// Hit-test callback: only resize borders, no DRAGGABLE zone.
// Window dragging is implemented manually so that mouse_down/up/dbl_click
// are still delivered to the application.
// borderless_hit_test_callback - колбэк SDL_SetWindowHitTest: вызывается SDL
// (возможно, вне нашего цикла событий) для каждой точки мыши и говорит ОС, не
// край ли это окна для ресайза. `area` - точка в оконных координатах, `data` -
// указатель на BorderlessData. Углы проверяются раньше сторон, чтобы угловые
// зоны (диагональный ресайз) выигрывали у боковых. У развёрнутого окна ресайз
// не предлагается.
fn borderless_hit_test_callback(win voidptr, area &C.SDL_Point, data voidptr) int {
	if data == unsafe { nil } {
		return sdl_hittest_normal
	}
	bd := unsafe { &BorderlessData(data) }

	mut ww := 0
	mut wh := 0
	C.SDL_GetWindowSize(win, &ww, &wh)

	x := f32(area.x)
	y := f32(area.y)
	b := f32(bd.resize_border)

	flags := C.SDL_GetWindowFlags(win)
	is_maximized := (flags & sdl_window_maximized) != 0

	if b > 0 && !is_maximized {
		left := x < b
		right := x >= f32(ww) - b
		top := y < b
		bottom := y >= f32(wh) - b
		if left && top { return sdl_hittest_resize_topleft }
		if right && top { return sdl_hittest_resize_topright }
		if left && bottom { return sdl_hittest_resize_bottomleft }
		if right && bottom { return sdl_hittest_resize_bottomright }
		if left { return sdl_hittest_resize_left }
		if right { return sdl_hittest_resize_right }
		if top { return sdl_hittest_resize_top }
		if bottom { return sdl_hittest_resize_bottom }
	}

	return sdl_hittest_normal
}

// hittest_zone_to_cursor сопоставляет зоне hit-test системный курсор
// (диагональные/горизонтальные/вертикальные стрелки ресайза); иначе обычная стрелка.
fn hittest_zone_to_cursor(zone int) int {
	return match zone {
		sdl_hittest_resize_topleft, sdl_hittest_resize_bottomright { sdl_system_cursor_sizenwse }
		sdl_hittest_resize_topright, sdl_hittest_resize_bottomleft { sdl_system_cursor_sizenesw }
		sdl_hittest_resize_left, sdl_hittest_resize_right { sdl_system_cursor_sizewe }
		sdl_hittest_resize_top, sdl_hittest_resize_bottom { sdl_system_cursor_sizens }
		else { sdl_system_cursor_arrow }
	}
}

// borderless_compute_resize_zone - то же определение зоны, что в hit-test
// колбэке, но по координатам (mx, my) и размеру окна (ww, wh) в SDL-пикселях;
// нужна, чтобы выбрать курсор ресайза по движению мыши. Дублирует логику
// колбэка (кроме проверки maximized): при правке менять обе.
fn borderless_compute_resize_zone(bd &BorderlessData, mx f32, my f32, ww int, wh int) int {
	b := f32(bd.resize_border)
	if b <= 0 {
		return sdl_hittest_normal
	}
	left := mx < b
	right := mx >= f32(ww) - b
	top := my < b
	bottom := my >= f32(wh) - b
	if left && top { return sdl_hittest_resize_topleft }
	if right && top { return sdl_hittest_resize_topright }
	if left && bottom { return sdl_hittest_resize_bottomleft }
	if right && bottom { return sdl_hittest_resize_bottomright }
	if left { return sdl_hittest_resize_left }
	if right { return sdl_hittest_resize_right }
	if top { return sdl_hittest_resize_top }
	if bottom { return sdl_hittest_resize_bottom }
	return sdl_hittest_normal
}

// borderless_update_cursor ставит курсор ресайза, когда мышь над краем окна.
// SDL сам курсор по hit-test зонам не меняет, поэтому делаем это вручную по
// mouse_move. Мышь окна переводится в физические px умножением на ui_scale.
// Курсор пересоздаётся только при смене зоны (last_zone).
fn borderless_update_cursor(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	scale := w.ctx.ui_scale
	mx := w.mouse_x * scale
	my := w.mouse_y * scale
	mut ww := 0
	mut wh := 0
	C.SDL_GetWindowSize(w.sdl_window, &ww, &wh)
	zone := borderless_compute_resize_zone(bd, mx, my, ww, wh)

	if zone != bd.last_zone {
		cursor_id := hittest_zone_to_cursor(zone)
		set_cursor(cursor_id)
		bd.last_zone = zone
	}
}

// borderless_register_drag_rect добавляет зону перетаскивания окна; прямоугольник
// приходит в логических координатах и хранится в физических (* ui_scale).
fn borderless_register_drag_rect(w &Window, logical_rect Rect) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	s := w.ctx.ui_scale
	bd.drag_rects << Rect{
		x: logical_rect.x * s
		y: logical_rect.y * s
		w: logical_rect.w * s
		h: logical_rect.h * s
	}
}

// borderless_clear_drag_rects очищает оба списка зон; зовётся в начале каждого
// кадра перед повторной регистрацией зон виджетами.
fn borderless_clear_drag_rects(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	bd.drag_rects.clear()
	bd.titlebar_rects.clear()
}

// borderless_register_titlebar_rect добавляет полосу заголовка (используется
// только по Y для распознавания двойного щелчка); логические -> физические px.
fn borderless_register_titlebar_rect(w &Window, logical_rect Rect) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	s := w.ctx.ui_scale
	bd.titlebar_rects << Rect{
		x: logical_rect.x * s
		y: logical_rect.y * s
		w: logical_rect.w * s
		h: logical_rect.h * s
	}
}

// Returns true if (lx, ly) in logical coords is inside any drag (titlebar) rect.
fn borderless_point_in_drag_rect(w &Window, lx f32, ly f32) bool {
	if w.hittest_data == unsafe { nil } {
		return false
	}
	bd := unsafe { &BorderlessData(w.hittest_data) }
	s := w.ctx.ui_scale
	px := lx * s
	py := ly * s
	for r in bd.drag_rects {
		if px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h {
			return true
		}
	}
	return false
}

// Called on left mouse_down in titlebar drag zone — begins manual drag.
// Запоминает глобальную позицию мыши и позицию окна; у развёрнутого окна
// перетаскивание не начинается.
fn borderless_on_drag_start(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	flags := C.SDL_GetWindowFlags(w.sdl_window)
	if (flags & sdl_window_maximized) != 0 {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	mut gx := f32(0)
	mut gy := f32(0)
	C.SDL_GetGlobalMouseState(&gx, &gy)
	mut wx := 0
	mut wy := 0
	C.SDL_GetWindowPosition(w.sdl_window, &wx, &wy)
	bd.dragging = true
	bd.drag_start_mx = gx
	bd.drag_start_my = gy
	bd.drag_start_wx = wx
	bd.drag_start_wy = wy
}

// Called on mouse_move — moves window while dragging.
// Новая позиция окна = старая позиция + смещение глобальной мыши с начала жеста.
fn borderless_on_drag_move(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	if !bd.dragging {
		return
	}
	mut gx := f32(0)
	mut gy := f32(0)
	C.SDL_GetGlobalMouseState(&gx, &gy)
	nx := bd.drag_start_wx + int(gx - bd.drag_start_mx)
	ny := bd.drag_start_wy + int(gy - bd.drag_start_my)
	C.SDL_SetWindowPosition(w.sdl_window, nx, ny)
}

// Called on left mouse_up — ends drag and handles double-click detection.
fn borderless_on_mouse_up(w &Window, lx f32, ly f32) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }

	bd.dragging = false

	s := w.ctx.ui_scale
	px := lx * s
	py := ly * s

	// Double-click detection: match only Y so clicks on buttons beside drag
	// widget (minimize/maximize/close) are also counted.
	// Двойной щелчок: два отпускания левой в пределах 500 мс и 16 физических px
	// (манхэттенское расстояние) -> pending_dbl_click. После срабатывания
	// last_click_time обнуляется, чтобы третий щелчок не считался новым двойным.
	mut in_titlebar := false
	for r in bd.titlebar_rects {
		if py >= r.y && py <= r.y + r.h {
			in_titlebar = true
			break
		}
	}
	if !in_titlebar {
		return
	}

	now := now_ms()
	dt := now - bd.last_click_time
	dx := px - bd.last_click_x
	dy := py - bd.last_click_y
	dist := if dx < 0 { -dx } else { dx } + if dy < 0 { -dy } else { dy }

	if dt < u64(500) && bd.last_click_time > 0 && dist < 16.0 {
		bd.pending_dbl_click = true
		bd.last_click_time = 0
	} else {
		bd.last_click_time = now
		bd.last_click_x = px
		bd.last_click_y = py
	}
}

// borderless_check_dbl_click возвращает true один раз после двойного щелчка по
// заголовку (флаг сбрасывается); вызывающий (App.process_events) переключает
// развёрнутость окна.
fn borderless_check_dbl_click(w &Window) bool {
	if w.hittest_data == unsafe { nil } {
		return false
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	if bd.pending_dbl_click {
		bd.pending_dbl_click = false
		return true
	}
	return false
}

// enable_borderless_resize включает ресайз за края окна шириной border
// (SDL-пиксели). Первый вызов создаёт BorderlessData и ставит SDL hit-test;
// повторный только меняет толщину границы.
pub fn (mut w Window) enable_borderless_resize(border int) {
	if w.hittest_data == unsafe { nil } {
		bd := &BorderlessData{
			resize_border: border
		}
		C.SDL_SetWindowHitTest(w.sdl_window, voidptr(borderless_hit_test_callback), voidptr(bd))
		w.hittest_data = unsafe { voidptr(bd) }
	} else {
		mut bd := unsafe { &BorderlessData(w.hittest_data) }
		bd.resize_border = border
	}
}

// disable_borderless_hittest снимает hit-test и сбрасывает курсор на стрелку.
// Сам BorderlessData не освобождается: ссылку держит только hittest_data, и она
// обнуляется (память остаётся на сборщике мусора).
pub fn (mut w Window) disable_borderless_hittest() {
	C.SDL_SetWindowHitTest(w.sdl_window, unsafe { nil }, unsafe { nil })
	w.hittest_data = unsafe { nil }
	set_cursor(sdl_system_cursor_arrow)
}
