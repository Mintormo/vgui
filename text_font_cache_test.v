module vgui

import os

// Тесты кэша текстовых текстур (обработка коллизий FNV-1a) и кэша
// шрифтов по размерам (учёт физического масштаба окна).
//
// Запуск: v test vgui/text_font_cache_test.v
// Требует SDL3 (видеодрайвер dummy — без дисплея).

fn make_test_window() !(&App, &Window) {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(title: 'cache test', width: 320, height: 240)!
	app.add_window(win)
	return app, win
}

fn test_text_cache_collision_is_treated_as_miss() {
	_, mut win := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	font := win.ctx.fonts.regular
	assert unsafe { font != nil }
	c := Color{10, 20, 30, 255}

	// 1. Рендерим textA — в кэше появляется запись под его настоящим ключом.
	text_a := 'collision-victim-A'
	win.ctx.draw_text_with_font(text_a, 5, 5, c, font)
	info := win.ctx.fonts.handle_map[font] or { FontHandleInfo{99, win.ctx.fonts.size} }
	key_a := text_cache_key(text_a, info.font_size, info.style_int, c)
	entry_a := win.ctx.text_cache[key_a] or {
		assert false, 'entry for textA not cached'
		return
	}
	assert entry_a.text == text_a
	assert unsafe { entry_a.texture != nil }

	// 2. Имитируем коллизию хэша: подсовываем запись textA под ключ textB.
	//    (Настоящую 64-битную коллизию не подобрать — переносим запись вручную.)
	text_b := 'collision-victim-B'
	key_b := text_cache_key(text_b, info.font_size, info.style_int, c)
	assert key_a != key_b
	win.ctx.text_cache.delete(key_a) // textA больше не ссылается на текстуру
	win.ctx.text_cache[key_b] = entry_a

	// 3. Рендер textB обязан распознать чужую запись (поля не совпадают),
	//    перерисовать и перезаписать её — а не молча отдать текстуру textA.
	win.ctx.draw_text_with_font(text_b, 5, 25, c, font)
	entry_b := win.ctx.text_cache[key_b] or {
		assert false, 'entry for textB missing after redraw'
		return
	}
	assert entry_b.text == text_b
	assert unsafe { entry_b.texture != nil }
	assert entry_b.texture != entry_a.texture

	// 4. Контроль: совпадающая запись остаётся на месте (обычный хит).
	win.ctx.draw_text_with_font(text_b, 5, 45, c, font)
	entry_b2 := win.ctx.text_cache[key_b] or {
		assert false, 'entry for textB missing after hit'
		return
	}
	assert entry_b2.texture == entry_b.texture

	win.cleanup()
}

fn test_size_cache_keyed_by_physical_size() {
	_, mut win := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	// Нестандартный логический размер (не равен базовому) при масштабе 1.0.
	win.ctx.ui_scale = 1.0
	font_1x := win.ctx.get_font(.regular, 17)
	assert unsafe { font_1x != nil }

	// Тот же логический размер при масштабе 2.0 — физический размер другой,
	// поэтому и шрифт обязан быть другим (до исправления возвращался font_1x).
	win.ctx.ui_scale = 2.0
	font_2x := win.ctx.get_font(.regular, 17)
	assert unsafe { font_2x != nil }
	assert font_1x != font_2x

	// Повторные запросы попадают в кэш и стабильны для каждого масштаба.
	assert win.ctx.get_font(.regular, 17) == font_2x
	assert win.ctx.get_font_immut(.regular, 17) == font_2x
	win.ctx.ui_scale = 1.0
	assert win.ctx.get_font(.regular, 17) == font_1x
	assert win.ctx.get_font_immut(.regular, 17) == font_1x

	win.cleanup()
}

fn test_measure_text_available_before_first_frame() {
	_, mut win := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	// Ни одного кадра не отрисовано: измерение обязано работать сразу
	// после create_window - раскладку считают по фактическому тексту.
	assert win.measure_text('').x == 0
	short := win.measure_text('id')
	long := win.measure_text('заметно более длинная строка')
	assert short.x > 0
	assert short.y > 0
	assert long.x > short.x

	// Варианты шрифта: жирный не уже обычного, больший кегль строго шире.
	assert win.measure_text('id', style: .bold).x >= short.x
	assert win.measure_text('id', size: win.ctx.fonts.size * 2).x > short.x

	win.cleanup()
}

// ─── Время жизни FontSet в g_font_cache (аудит 2.3) ───

fn embedded_regular_bytes() []u8 {
	ptr, n := embedded_regular_font()
	return unsafe { (&u8(ptr)).vbytes(n) }.clone()
}

fn test_ui_scale_sweep_does_not_accumulate_font_sets() {
	_, mut win := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	before := font_cache_len()
	// Один жест зума: 70 разных масштабов. До исправления каждый оставлял
	// в кэше свой FontSet навсегда (+70 записей).
	for i in 0 .. 70 {
		win.set_ui_scale(0.5 + f32(i) * 0.05)
	}
	assert font_cache_len() == before, 'кэш вырос с ${before} до ${font_cache_len()}'
	assert win.ctx.fonts.refs == 1
	assert unsafe { win.ctx.fonts.regular != nil }
	// Текущий набор рабочий: текст измеряется.
	assert win.measure_text('abc').x > 0

	// Тот же масштаб повторно — набор не пересоздаётся.
	fs := win.ctx.fonts
	win.set_ui_scale(win.ctx.ui_scale)
	assert win.ctx.fonts == fs

	win.cleanup()
	assert font_cache_len() == before - 1, 'cleanup не освободил набор окна'
}

fn test_common_font_set_is_reference_counted() {
	app, mut a := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut b := create_window(title: 'second', width: 320, height: 240) or {
		assert false, 'second window failed: ${err}'
		return
	}
	_ = app
	// Одинаковые параметры шрифтов — один общий набор на два окна.
	assert a.ctx.fonts == b.ctx.fonts
	common := a.ctx.fonts
	assert common.refs == 2
	key := common.cache_key

	// Одно окно сменило масштаб: общий набор жив и не тронут для второго.
	a.set_ui_scale(2.0)
	assert a.ctx.fonts != common
	assert common.refs == 1
	assert font_cache_entry(key) == voidptr(common)
	assert unsafe { b.ctx.fonts.regular != nil }
	assert b.ctx.fonts.size == b.config.font_size

	// Закрытие последнего владельца удаляет запись; повторный cleanup — no-op
	// (счётчик не уходит в минус и не трогает чужие наборы).
	b.cleanup()
	assert font_cache_entry(key) == unsafe { nil }
	b.cleanup()
	a.cleanup()
	a.cleanup()
}

fn test_hidpi_reload_does_not_mutate_common_set() {
	_, mut base := make_test_window() or {
		assert false, 'window creation failed: ${err}'
		return
	}
	mut hi := create_window(title: 'hidpi', width: 320, height: 240) or {
		assert false, 'second window failed: ${err}'
		return
	}
	common := base.ctx.fonts
	assert hi.ctx.fonts == common
	// Имитируем HiDPI-экран: окно берёт отдельный масштабированный набор.
	// Раньше reload_fonts_for_dpi переинициализировал общий набор на месте —
	// у соседнего окна молча удваивался шрифт, а старые TTF-хэндлы текли.
	hi.ctx.dpi_scale = 2.0
	hi.reload_scaled_fonts()
	assert hi.ctx.fonts != common
	assert hi.ctx.fonts.size == hi.config.font_size * 2
	assert common.size == base.config.font_size
	assert common.refs == 1

	hi.cleanup()
	base.cleanup()
}

fn test_font_cache_key_uses_content_not_address() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	_ := create_app() or {
		assert false, 'app creation failed: ${err}'
		return
	}
	data1 := embedded_regular_bytes()
	data2 := embedded_regular_bytes()
	assert data1.data != data2.data
	cfg1 := FontConfig{
		font_data: data1
	}
	cfg2 := FontConfig{
		font_data: data2
	}
	// Разные буферы с одинаковыми байтами — один ключ и один общий набор.
	assert font_cache_key(cfg1) == font_cache_key(cfg2)
	mut altered := data1.clone()
	altered[altered.len / 2] ^= 0xff
	assert font_cache_key(FontConfig{ font_data: altered }) != font_cache_key(cfg1)

	fs1 := get_or_load_fonts(cfg1) or {
		assert false, 'load failed: ${err}'
		return
	}
	fs2 := get_or_load_fonts(cfg2) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert fs1 == fs2
	assert fs1.refs == 2
	release_fonts(voidptr(fs2))
	release_fonts(voidptr(fs1))
	assert font_cache_entry(font_cache_key(cfg1)) == unsafe { nil }
}

fn test_font_cache_hash_hit_with_other_bytes_is_a_miss() {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	_ := create_app() or {
		assert false, 'app creation failed: ${err}'
		return
	}
	cfg := FontConfig{
		font_data: embedded_regular_bytes()
	}
	key := font_cache_key(cfg)
	// Настоящую коллизию FNV-1a не подобрать — кладём под тот же ключ набор
	// из других байтов, как если бы хэши совпали.
	impostor := &FontSet{
		font_data: [u8(1), 2, 3]
		cache_key: key
		refs:      1
	}
	font_cache_put(key, voidptr(impostor))

	fs := get_or_load_fonts(cfg) or {
		assert false, 'load failed: ${err}'
		return
	}
	assert voidptr(fs) != voidptr(impostor), 'отдан набор из чужих байтов'
	assert fs.font_data == cfg.font_data
	assert fs.cache_key != key
	assert font_cache_entry(key) == voidptr(impostor)

	release_fonts(voidptr(fs))
	assert font_cache_entry(fs.cache_key) == unsafe { nil }
	font_cache_drop(key)
}
