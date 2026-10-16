module vgui

// Тесты трёх доработок для приложений с панелями и настройками:
//   - ShortcutInput (shortcut_input.v): ожидание, Esc/Backspace, занятые сочетания, место
//     клавиши вместо символа раскладки, сочетание не уходит в меню, щелчок мимо - отмена;
//   - Splitter.keep: панель держит размер в пикселях при изменении окна и после перетаскивания;
//   - ScrollBox.fit_content и Dialog «не больше экрана».

// Места клавиш (scancode USB HID)
const sc_p = 19 // «P» (в русской раскладке - «З»)
const sc_s = 22
const sc_left = 80

// ShortcutLog - что сообщило поле (замыкания захватывают копию - журнал по указателю)
@[heap]
struct ShortcutLog {
mut:
	changes []string
	rejects []string
	waits   []bool
	menu    int
}

fn shortcut_ui() (&TestUi, &ShortcutInput, &ShortcutLog) {
	mut t := new_test_ui(width: 360, height: 160) or { panic(err) }
	mut log := &ShortcutLog{}
	ui := ui_parse('
vbox pad=8 gap=8
  menubar
    menu "Файл"
      item "Сохранить" shortcut=Ctrl+S #save
  hbox
    shortcut "Ctrl+O" #si
    spacer flex=1
  button "Мимо" #other
', 't') or { panic(err) }
	mut si := ui.get[ShortcutInput]('si') or { panic(err) }
	si.reserved = ['Left']
	si.on_change = fn [mut log] (s string) {
		log.changes << s
	}
	si.on_reject = fn [mut log] (s string) {
		log.rejects << s
	}
	si.on_wait = fn [mut log] (w bool) {
		log.waits << w
	}
	mut save := ui.item('save') or { panic('нет #save') }
	save.on_click = fn [mut log] () {
		log.menu++
	}
	t.add(ui.root)
	return t, si, log
}

fn test_shortcut_input_captures_by_key_place() {
	mut t, mut si, log := shortcut_ui()
	defer {
		t.close()
	}
	assert si.shortcut == 'Ctrl+O'
	t.click_widget(si)
	assert si.is_waiting()
	assert si.btn.text == tr('si.wait')
	// русская раскладка: символ «з», клавиша - P
	t.key_sc(int(`з`), sc_p, sdl_kmod_ctrl)
	assert !si.is_waiting()
	assert si.shortcut == 'Ctrl+P'
	assert log.changes == ['Ctrl+P']
	assert log.waits == [true, false]
	t.frame()
	assert si.btn.text == 'Ctrl+P'
}

fn test_shortcut_input_does_not_leak_to_menu() {
	mut t, mut si, log := shortcut_ui()
	defer {
		t.close()
	}
	// без ожидания Ctrl+S - команда меню
	t.key_sc(int(`s`), sc_s, sdl_kmod_ctrl)
	assert log.menu == 1
	// в ожидании - значение поля, меню его не получает
	t.click_widget(si)
	t.key_sc(int(`s`), sc_s, sdl_kmod_ctrl)
	assert si.shortcut == 'Ctrl+S'
	assert log.menu == 1
}

fn test_shortcut_input_escape_backspace_reserved() {
	mut t, mut si, log := shortcut_ui()
	defer {
		t.close()
	}
	t.click_widget(si)
	t.key_sc(sdl_k_escape, 41, 0)
	assert !si.is_waiting(), 'Esc - отмена'
	assert si.shortcut == 'Ctrl+O'
	assert log.changes.len == 0

	t.click_widget(si)
	t.key_sc(sdl_k_left, sc_left, 0)
	assert si.is_waiting(), 'занятое - ожидание продолжается'
	assert log.rejects == ['Left']
	// модификатор сам по себе - ждать дальше
	t.key_sc(0x400000E0, 224, sdl_kmod_ctrl) // левый Ctrl
	assert si.is_waiting()
	t.key_sc(sdl_k_backspace, 42, 0)
	assert !si.is_waiting()
	assert si.shortcut == '', 'Backspace - снять'
	assert log.changes == ['']
}

fn test_shortcut_input_click_elsewhere_cancels() {
	mut t, mut si, log := shortcut_ui()
	defer {
		t.close()
	}
	t.click_widget(si)
	assert si.is_waiting()
	// второй щелчок по полю - тоже отмена
	t.click_widget(si)
	assert !si.is_waiting()
	t.click_widget(si)
	assert si.is_waiting()
	// щелчок мимо поля
	r := si.bounds
	t.click(r.x + r.w + 60, r.y + r.h / 2)
	assert !si.is_waiting()
	assert si.shortcut == 'Ctrl+O'
	assert log.changes.len == 0
	// неактивное поле не ждёт
	si.enabled = false
	t.frame()
	t.click_widget(si)
	assert !si.is_waiting()
}

fn test_shortcut_names() {
	// канонический вид: регистр и порядок модификаторов не важны (перенесено из vraw)
	assert shortcut_normalize('ctrl+shift+o') == 'Ctrl+Shift+O'
	assert shortcut_normalize('alt+shift+f5') == 'Shift+Alt+F5'
	assert shortcut_normalize('r') == 'R'
	assert shortcut_normalize('Ctrl+0') == 'Ctrl+0'
	assert shortcut_normalize('pagedown') == 'PageDown'
	assert shortcut_normalize('Ctrl+[') == 'Ctrl+['
	assert shortcut_normalize('') == ''
	assert shortcut_normalize('Ctrl+') == ''
	assert shortcut_normalize('F13') == ''
	assert shortcut_key_name(21) == 'R'
	assert shortcut_key_name(29) == 'Z'
	assert shortcut_key_name(30) == '1'
	assert shortcut_key_name(58) == 'F1'
	rus := GuiEvent{
		scancode: 21
		keycode:  int(`к`) // русская раскладка
		mod_keys: sdl_kmod_ctrl | sdl_kmod_shift
	}
	assert shortcut_from_event(&rus) == 'Ctrl+Shift+R'
	assert shortcut_normalize('shift+ctrl+s') == 'Ctrl+Shift+S'
	assert shortcut_normalize('Alt+f4') == 'Alt+F4'
	assert shortcut_normalize('ctrl+pgdn') == 'Ctrl+PageDown'
	assert shortcut_normalize('esc') == 'Escape'
	assert shortcut_normalize('Ctrl+Ё') == '', 'клавиши без места - нет'
	assert shortcut_key_name(4) == 'A'
	assert shortcut_key_name(39) == '0'
	assert shortcut_key_name(69) == 'F12'
	assert shortcut_key_name(47) == '['
	assert shortcut_key_name(224) == '', 'модификатор'
	// канонические имена понимает меню
	ev := GuiEvent{
		typ:      .key_down
		keycode:  int(`х`)
		scancode: 47
	}
	assert menu_shortcut_matches(shortcut_from_event(&ev), &ev)
}

// ─── Splitter.keep ─────────────────────────────────────

fn test_splitter_keep_holds_pixel_size() {
	mut t := new_test_ui(width: 800, height: 200)!
	defer {
		t.close()
	}
	mut sp := splitter_horizontal()
	sp.bar_size = 4
	sp.set_first(label('просмотр'))
	sp.set_second(label('панель'))
	sp.set_keep(.second, 300)
	t.add(sp)
	assert int(sp.second_rect().w + 0.5) == 300
	// окно шире - растёт только первая панель
	t.win.ctx.screen_width = 1200
	t.win.invalidate_all()
	t.frame()
	assert int(sp.second_rect().w + 0.5) == 300
	assert int(sp.first_rect().w + 0.5) == 1200 - 300 - 4
	// узкое окно ужимает панель до min, но keep_size не меняется
	sp.min_first = 200
	t.win.ctx.screen_width = 400
	t.win.invalidate_all()
	t.frame()
	assert sp.second_rect().w < 300
	assert sp.keep_size == 300
	t.win.ctx.screen_width = 1000
	t.win.invalidate_all()
	t.frame()
	assert int(sp.second_rect().w + 0.5) == 300
}

fn test_splitter_keep_follows_drag() {
	mut t := new_test_ui(width: 800, height: 200)!
	defer {
		t.close()
	}
	mut sp := splitter_horizontal()
	sp.bar_size = 4
	sp.set_first(label('a'))
	sp.set_second(label('b'))
	sp.set_keep(.second, 300)
	t.add(sp)
	bar := sp.bar_rect()
	cx := bar.x + bar.w / 2
	cy := bar.y + bar.h / 2
	t.drag(cx, cy, cx - 100, cy)
	assert int(sp.keep_size + 0.5) == 400, 'перетащили - панель шире на 100'
	t.win.ctx.screen_width = 1000
	t.win.invalidate_all()
	t.frame()
	assert int(sp.second_rect().w + 0.5) == 400
}

// ─── ScrollBox.fit_content и диалог по экрану ──────────

fn test_scroll_box_fit_content_measures_content() {
	mut t := new_test_ui()!
	defer {
		t.close()
	}
	mut col := create_vbox_fill()
	for i in 0 .. 30 {
		col.add(label('строка ${i}'))
	}
	mut sb := scroll_box(0)
	sb.pad = 0
	sb.add(col)
	plain := sb.measure(&t.win.ctx)
	assert plain.h == 160, 'без fit_content - прежние 160 px'
	sb.fit_content = true
	fit := sb.measure(&t.win.ctx)
	content := measure_widget(col, &t.win.ctx)
	assert fit.h == content.h
	assert fit.w == content.w, 'поперёк - без места под полосу'
	assert fit.min_h == 40
}

fn test_dialog_not_taller_than_screen() {
	mut t := new_test_ui()!
	defer {
		t.close()
	}
	mut col := create_vbox_fill()
	for i in 0 .. 200 {
		col.add(label('длинная строка настроек номер ${i}'))
	}
	mut sb := scroll_box(0)
	sb.pad = 0
	sb.fit_content = true
	sb.add(col)
	mut d := create_dialog(title: 'Настройки', parent: t.win)!
	t.app.add_dialog(d)
	d.add_widget(sb)
	d.show()
	defer {
		d.close_with_result(0)
	}
	room_w, room_h := d.screen_room(1)
	assert room_h > 0, 'экран dummy-драйвера известен'
	content := measure_widget(col, &d.win.ctx)
	assert content.h > room_h, 'содержимое выше экрана'
	assert d.win.config.height == room_h
	assert d.win.config.width == int(content.w) + int(sb.eff_sb_width() + 0.999),
		'по высоте не влезло - шире на полосу'
	assert d.base_height == int(content.h), 'base - полный размер, на большом экране вернётся'
	_ = room_w
	// refit открытого диалога - тот же размер
	d.refit()
	assert d.win.config.height == room_h
}
