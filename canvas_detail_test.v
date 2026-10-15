module vgui

import os

// ═══════════════════════════════════════════════════════
// Слой детализации Canvas (set_detail): плотная картинка поверх буфера на
// прямоугольнике в пикселях буфера рисуется после снимка; clear_detail
// убирает её; visible_buf_rect - видимая часть буфера. Проверка - по
// настоящим пикселям кадра (SDL_RenderReadPixels).
//
// Запуск: v test vgui/canvas_detail_test.v (из v/, SDL_VIDEODRIVER=dummy)
// ═══════════════════════════════════════════════════════

// detail_capture - кадр окна (testkit.v, capture_frame): пиксели и pitch
fn detail_capture(mut w Window) ([]u8, int) {
	f := capture_frame(mut w)
	return f.pixels, f.pitch
}

// detail_rgb - цвет пикселя кадра (x, y)
fn detail_rgb(buf []u8, pitch int, x int, y int) (u8, u8, u8) {
	i := y * pitch + x * 4
	return buf[i], buf[i + 1], buf[i + 2]
}

fn test_canvas_detail_layer() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'detail', width: 200, height: 200)!
	app.add_window(win)

	// Буфер 100x100 синий, вписан в окно 200x200 - два экранных пикселя на
	// пиксель буфера
	mut cv := canvas(100, 100)
	cv.fill(Color{0, 0, 255, 255})
	win.add_widget(cv)
	win.render()
	assert !cv.has_detail()
	vr := cv.visible_buf_rect()
	assert vr.x == 0 && vr.y == 0 && vr.w == 100 && vr.h == 100

	// Детализация 50x50 красная поверх правой нижней четверти буфера
	red := []u8{len: 50 * 50 * 4, init: if index % 4 == 0 || index % 4 == 3 {
		u8(255)
	} else {
		u8(0)
	}}
	cv.set_detail(red.data, red.len, 50, 50, 50, 50, 50, 50)
	assert cv.has_detail()
	win.invalidate_all()
	win.render()
	buf, pitch := detail_capture(mut win)
	assert buf.len > 0
	ox := int(cv.disp_x)
	oy := int(cv.disp_y)
	s := cv.screen_scale()
	assert s > 1.9 && s < 2.1
	// Середина правой нижней четверти - красная, левой верхней - синяя
	r1, g1, b1 := detail_rgb(buf, pitch, ox + int(75 * s), oy + int(75 * s))
	assert r1 == 255 && g1 == 0 && b1 == 0
	r2, _, b2 := detail_rgb(buf, pitch, ox + int(25 * s), oy + int(25 * s))
	assert r2 == 0 && b2 == 255

	// Неверный размер - слой снимается
	cv.set_detail(red.data, 10, 50, 50, 0, 0, 10, 10)
	assert !cv.has_detail()
	cv.set_detail(red.data, red.len, 50, 50, 50, 50, 50, 50)
	cv.clear_detail()
	assert !cv.has_detail()
	win.invalidate_all()
	win.render()
	buf2, pitch2 := detail_capture(mut win)
	r3, _, b3 := detail_rgb(buf2, pitch2, ox + int(75 * s), oy + int(75 * s))
	assert r3 == 0 && b3 == 255

	// Увеличение: видна только часть буфера
	cv.set_zoom(8)
	win.invalidate_all()
	win.render()
	vz := cv.visible_buf_rect()
	assert vz.w > 0 && vz.w < 100 && vz.h > 0 && vz.h < 100

	win.cleanup()
	app.cleanup()
}
