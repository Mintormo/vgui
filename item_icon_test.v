module vgui

// Тесты ItemIcon (item_icon.v): значение иконки, кэш текстур (в том числе
// кэширование неудачной загрузки) и отрисовка глифа Lucide и картинки из байтов.
//
// Запуск: v test item_icon_test.v

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

// Непрочитанная картинка кэшируется как пустая Texture: иначе IMG_Load шёл бы с диска на
// каждой отрисовке (так было с узлами файлового диалога).
fn test_failed_load_is_cached() {
	mut t := new_test_ui(width: 120, height: 80)!
	defer {
		t.close()
	}
	path := '/nonexistent/vgui_item_icon.png'
	assert !t.win.ctx.load_icon_texture(path).is_valid()
	assert path in t.win.ctx.icon_cache
	assert !t.win.ctx.load_icon_texture(path).is_valid()
	assert !t.win.ctx.load_icon_texture_data('mem:bad', [u8(1), 2, 3]).is_valid()
	assert 'mem:bad' in t.win.ctx.icon_cache
}

fn test_draw_glyph_and_bytes_image() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	red := Color{220, 20, 20, 255}
	blue := Color{20, 40, 220, 255}
	mut probe := &ItemIconProbe{
		glyph: item_icon('square').with_color(red)
		image: item_icon_data(solid_bmp(4, 4, blue))
	}
	t.add(probe)
	f := t.capture()
	// Глиф красится цветом иконки, а не fallback (чёрным)
	assert f.count(Rect{10, 10, 32, 32}, red, 40) > 20
	assert f.count(Rect{10, 10, 32, 32}, Color{0, 0, 0, 255}, 40) == 0
	// Картинка 4×4 растянута в 16×16
	assert f.count(Rect{60, 10, 16, 16}, blue, 40) >= 200
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
