module vgui

import os

// Размер окна в логических единицах (аудит 2026-10, 2.15): set_size умножает на
// ui_scale, а config.width/height везде хранят логический размер.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v -enable-globals test window_size_test.v

fn test_set_size_is_logical() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'size', width: 300, height: 200)!
	app.add_window(win)
	win.set_ui_scale(2.0)
	win.set_size(150, 100)
	mut sw := 0
	mut sh := 0
	C.SDL_GetWindowSize(win.sdl_window, &sw, &sh)
	assert sw == 300 && sh == 200, 'окно SDL = логический размер × ui_scale'
	assert win.config.width == 150 && win.config.height == 100
	assert win.ctx.screen_width == 150

	// События развернуть/восстановить приходят с SDL-размером - в config он логический.
	win.apply_sdl_size(500, 300)
	assert win.config.width == 250 && win.config.height == 150
	assert win.ctx.screen_height == 150

	win.cleanup()
	app.cleanup()
}
