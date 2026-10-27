module vgui

import os

// image_io.v и Canvas.load_*/save_file: картинка, записанная в файл, читается
// обратно теми же пикселями (PNG без потерь), байты из памяти декодируются так
// же, как файл, битые данные и tiff на запись дают отказ, а не исключение.
// SDL-рендерер не нужен (декодирование без окна), но SDL_image - да.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test image_io_test.v

fn image_io_tmp(name string) string {
	return os.join_path(os.temp_dir(), 'vgui_image_io_${os.getpid()}_${name}')
}

fn test_canvas_png_round_trip() {
	path := image_io_tmp('round.png')
	defer {
		os.rm(path) or {}
	}
	mut c := canvas(5, 3)
	c.fill(Color{10, 20, 30, 255})
	c.set_pixel(0, 0, Color{255, 0, 0, 255})
	c.set_pixel(4, 2, Color{0, 0, 255, 128})
	assert c.save_file(path)

	// Холст другого размера принимает размер картинки.
	mut back := canvas(1, 1)
	assert back.load_file(path)
	assert back.width == 5 && back.height == 3
	assert back.get_pixel(0, 0) == Color{255, 0, 0, 255}
	assert back.get_pixel(4, 2) == Color{0, 0, 255, 128}
	assert back.get_pixel(2, 1) == Color{10, 20, 30, 255}

	// Те же байты из памяти - тот же результат.
	data := os.read_bytes(path)!
	img := decode_image_bytes(data) or { panic('не декодировалось из памяти') }
	assert img.w == 5 && img.h == 3 && img.pixels == back.pixels
}

fn test_bad_input_is_refused() {
	mut c := canvas(2, 2)
	assert !c.load_file('/nonexistent/vgui.png')
	assert !c.load_data([u8(1), 2, 3])
	assert !c.load_data([]u8{})
	// Неудачная загрузка не трогает буфер.
	assert c.width == 2 && c.height == 2
	// tiff SDL_image только читает.
	assert !c.save_file(image_io_tmp('x.tiff'))
	assert !encode_image_file(image_io_tmp('short.png'), 4, 4, []u8{len: 3})
}
