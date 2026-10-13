module vgui

import os

// Тесты ItemIcon (item_icon.v): значение иконки, кэш текстур (в том числе
// кэширование неудачной загрузки) и отрисовка глифа Lucide и картинки из байтов.
//
// Запуск: v -enable-globals test item_icon_test.v

fn make_item_icon_window(w int, h int) !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'item icon test', width: w, height: h, theme: light_theme())!
	app.add_window(win)
	return app, win
}

// item_icon_capture читает кадр окна (persistent render target) в RGBA.
fn item_icon_capture(mut w Window) ([]u8, int, int, int) {
	C.SDL_SetRenderTarget(w.renderer, w.rt)
	raw := C.SDL_RenderReadPixels(w.renderer, unsafe { nil })
	C.SDL_SetRenderTarget(w.renderer, unsafe { nil })
	if unsafe { raw == nil } {
		return []u8{}, 0, 0, 0
	}
	conv := C.SDL_ConvertSurface(raw, sdl_pixelformat_abgr8888)
	C.SDL_DestroySurface(raw)
	s := unsafe { &C.SDL_Surface(conv) }
	n := s.pitch * s.h
	mut buf := []u8{len: n}
	unsafe { vmemcpy(buf.data, s.pixels, n) }
	w_, h_, pitch := s.w, s.h, s.pitch
	C.SDL_DestroySurface(conv)
	return buf, w_, h_, pitch
}

// count_px - сколько пикселей прямоугольника (x, y, w, h) близки к цвету c.
fn count_px(buf []u8, pitch int, x int, y int, w int, h int, c Color) int {
	mut n := 0
	for yy in y .. y + h {
		for xx in x .. x + w {
			off := yy * pitch + xx * 4
			if iabs_i(int(buf[off]) - int(c.r)) < 40 && iabs_i(int(buf[off + 1]) - int(c.g)) < 40
				&& iabs_i(int(buf[off + 2]) - int(c.b)) < 40 {
				n++
			}
		}
	}
	return n
}

fn iabs_i(v int) int {
	return if v < 0 { -v } else { v }
}

// solid_bmp - BMP 24 бит w×h одного цвета (ширина кратна 4 - строки без выравнивания).
fn solid_bmp(w int, h int, c Color) []u8 {
	data_len := w * h * 3
	file_len := 54 + data_len
	mut b := []u8{}
	le32 := fn (v int) []u8 {
		return [u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)]
	}
	b << [u8(`B`), `M`]
	b << le32(file_len)
	b << le32(0)
	b << le32(54)
	b << le32(40)
	b << le32(w)
	b << le32(h)
	b << [u8(1), 0, 24, 0] // planes = 1, bpp = 24
	b << le32(0) // BI_RGB
	b << le32(data_len)
	b << le32(2835)
	b << le32(2835)
	b << le32(0)
	b << le32(0)
	for _ in 0 .. w * h {
		b << [c.b, c.g, c.r]
	}
	return b
}

// ItemIconProbe рисует две иконки: глиф Lucide и картинку из байтов.
struct ItemIconProbe {
mut:
	glyph ItemIcon
	image ItemIcon
}

fn (mut p ItemIconProbe) draw(mut ctx RenderContext) {
	ctx.fill_rect(Rect{0, 0, 200, 100}, Color{255, 255, 255, 255})
	ctx.draw_item_icon(p.glyph, Rect{10, 10, 32, 32}, 32, Color{0, 0, 0, 255})
	ctx.draw_item_icon(p.image, Rect{60, 10, 16, 16}, 16, Color{0, 0, 0, 255})
}

fn (mut p ItemIconProbe) handle_event(event &GuiEvent, app &App) bool {
	return false
}

fn test_item_icon_value() {
	assert !ItemIcon{}.is_set()
	assert item_icon('save').is_set()
	assert item_icon_file('a.png').is_set()
	assert !item_icon('').is_set()
	assert !item_icon_data([]u8{}).is_set()

	mut raw := [u8(1), 2, 3]
	a := item_icon_data(raw)
	raw[0] = 99 // байты скопированы: правка исходного буфера иконку не трогает
	assert a.data[0] == 1
	b := item_icon_data([u8(1), 2, 3])
	c := item_icon_data([u8(1), 2, 4])
	assert a.data_key == b.data_key // одинаковые картинки - одна текстура
	assert a.data_key != c.data_key

	red := item_icon('save').with_color(Color{255, 0, 0, 255})
	assert red.name == 'save' && red.color.r == 255
}

// Непрочитанная картинка кэшируется как nil: иначе IMG_Load шёл бы с диска на
// каждой отрисовке (так было с узлами файлового диалога).
fn test_failed_load_is_cached() {
	_, mut win := make_item_icon_window(100, 60)!
	path := '/nonexistent/vgui_item_icon.png'
	assert win.ctx.load_icon_texture(path) == unsafe { nil }
	assert path in win.ctx.icon_cache
	assert win.ctx.load_icon_texture(path) == unsafe { nil }
	assert win.ctx.load_icon_texture_data('mem:bad', [u8(1), 2, 3]) == unsafe { nil }
	assert 'mem:bad' in win.ctx.icon_cache
	win.cleanup()
}

fn test_draw_glyph_and_bytes_image() {
	_, mut win := make_item_icon_window(200, 100)!
	red := Color{220, 20, 20, 255}
	blue := Color{20, 40, 220, 255}
	mut probe := &ItemIconProbe{
		glyph: item_icon('square').with_color(red)
		image: item_icon_data(solid_bmp(4, 4, blue))
	}
	win.add_widget(probe)
	win.render()
	buf, _, _, pitch := item_icon_capture(mut win)
	assert buf.len > 0
	// Глиф красится цветом иконки, а не fallback (чёрным)
	assert count_px(buf, pitch, 10, 10, 32, 32, red) > 20
	assert count_px(buf, pitch, 10, 10, 32, 32, Color{0, 0, 0, 255}) == 0
	// Картинка 4×4 растянута в 16×16
	assert count_px(buf, pitch, 60, 10, 16, 16, blue) >= 200
	win.cleanup()
}

// Иконка строки ListBox едет вместе со строкой при сортировке.
fn test_list_box_row_icon_follows_sort() {
	mut lb := list_box()
	lb.add_column_sortable('Имя', 100)
	lb.add_item_icon('b', item_icon('file'))
	lb.add_item_icon('a', item_icon('folder'))
	lb.set_column_sort(0, .asc)
	assert lb.rows[0].cells[0].text == 'a'
	assert lb.rows[0].icon.name == 'folder'
	assert lb.rows[1].icon.name == 'file'
	// с активной сортировкой новая строка встаёт на своё место вместе с иконкой
	lb.add_item_icon('0', item_icon('star'))
	assert lb.rows[0].cells[0].text == '0'
	assert lb.rows[0].icon.name == 'star'
}
