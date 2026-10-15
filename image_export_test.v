module vgui

import os

// Экспорт кадра (аудит 2026-10, 2.18): неизвестное расширение - ошибка, а не PNG под
// чужим именем; обрезка области - по физическому размеру цели рендеринга.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test image_export_test.v

fn test_format_from_path() {
	assert image_format_from_path('a.PNG')? == .png
	assert image_format_from_path('a.jpeg')? == .jpg
	assert image_format_from_path('a.tif')? == .tiff
	if _ := image_format_from_path('a.gif') {
		assert false, 'gif не поддерживается'
	}
	if _ := image_format_from_path('noext') {
		assert false, 'без расширения - none'
	}
}

fn test_save_window_whole_frame_at_scale() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'export', width: 100, height: 80)!
	app.add_window(win)
	win.set_ui_scale(2.0)
	win.render()
	dir := os.join_path(os.temp_dir(), 'vgui_export_test_${os.getpid()}')
	os.mkdir_all(dir)!
	defer {
		os.rmdir_all(dir) or {}
	}
	assert !win.save_window_to_image(os.join_path(dir, 'x.gif'), 0)
	png := os.join_path(dir, 'x.png')
	assert win.save_window_to_image(png, 0)
	// весь кадр в физических пикселях: 100x80 логических при ui_scale 2
	surf := C.IMG_Load(png.str)
	assert surf != unsafe { nil }
	s := unsafe { &C.SDL_Surface(surf) }
	assert s.w == 200 && s.h == 160
	C.SDL_DestroySurface(surf)

	win.cleanup()
	app.cleanup()
}
