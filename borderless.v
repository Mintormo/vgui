module vgui

struct BorderlessData {
mut:
	resize_border  int
	drag_rects     []Rect // SDL window-logical coords; used only for hit-test resize
	titlebar_rects []Rect // Y-range of WindowTitleDrag rows (SDL window-logical coords)
	last_zone      int = sdl_hittest_normal
	// Manual drag state
	dragging      bool
	drag_start_mx f32 // global mouse X when drag started
	drag_start_my f32
	drag_start_wx int // window X when drag started
	drag_start_wy int
	// Double-click detection (updated on mouse_up)
	last_click_time   u64
	last_click_x      f32
	last_click_y      f32
	pending_dbl_click bool
}

// Hit-test callback: only resize borders, no DRAGGABLE zone.
// Window dragging is implemented manually so that mouse_down/up/dbl_click
// are still delivered to the application.
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

fn hittest_zone_to_cursor(zone int) int {
	return match zone {
		sdl_hittest_resize_topleft, sdl_hittest_resize_bottomright { sdl_system_cursor_sizenwse }
		sdl_hittest_resize_topright, sdl_hittest_resize_bottomleft { sdl_system_cursor_sizenesw }
		sdl_hittest_resize_left, sdl_hittest_resize_right { sdl_system_cursor_sizewe }
		sdl_hittest_resize_top, sdl_hittest_resize_bottom { sdl_system_cursor_sizens }
		else { sdl_system_cursor_arrow }
	}
}

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
		cursor := C.SDL_CreateSystemCursor(cursor_id)
		C.SDL_SetCursor(cursor)
		bd.last_zone = zone
	}
}

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

fn borderless_clear_drag_rects(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	bd.drag_rects.clear()
	bd.titlebar_rects.clear()
}

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

// Returns true if (lx, ly) in logical coords falls within any titlebar row.
fn borderless_point_in_titlebar(w &Window, lx f32, ly f32) bool {
	if w.hittest_data == unsafe { nil } {
		return false
	}
	bd := unsafe { &BorderlessData(w.hittest_data) }
	s := w.ctx.ui_scale
	px := lx * s
	py := ly * s
	for r in bd.titlebar_rects {
		if px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h {
			return true
		}
	}
	return false
}

// Called on left mouse_down in titlebar drag zone — begins manual drag.
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

	now := C.SDL_GetTicks()
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

fn borderless_force_arrow(w &Window) {
	if w.hittest_data == unsafe { nil } {
		return
	}
	mut bd := unsafe { &BorderlessData(w.hittest_data) }
	if bd.last_zone != sdl_hittest_normal {
		bd.last_zone = sdl_hittest_normal
		cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
		C.SDL_SetCursor(cursor)
	}
}

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

pub fn (mut w Window) disable_borderless_hittest() {
	C.SDL_SetWindowHitTest(w.sdl_window, unsafe { nil }, unsafe { nil })
	w.hittest_data = unsafe { nil }
	cursor := C.SDL_CreateSystemCursor(sdl_system_cursor_arrow)
	C.SDL_SetCursor(cursor)
}
