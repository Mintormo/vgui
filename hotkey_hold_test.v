module vgui

// Клавиатура по образцу Qt (hotkeys.v, event_route.v; PROJECT.md «Доставка
// событий»): удержание клавиши (bind_hold - отпускание, автоповтор, потеря
// фокуса окном), ShortcutOverride (печатная клавиша - полю ввода, а не
// горячей клавише), фильтры событий окна и приложения, сочетания меню в
// русской раскладке.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test hotkey_hold_test.v

// scancode клавиши «\» (USB HID)
const sc_backslash_key = 49

struct HoldLog {
mut:
	events []string
}

fn test_hold_hotkey_press_repeat_release() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut log := &HoldLog{}
	t.win.bind_hold_hotkey('\\', fn [mut log] () {
		log.events << 'press'
	}, fn [mut log] () {
		log.events << 'release'
	})
	t.key_press(int(`\\`), sc_backslash_key, 0)
	t.key_repeat(int(`\\`), sc_backslash_key, 0)
	t.key_repeat(int(`\\`), sc_backslash_key, 0)
	assert log.events == ['press'], 'автоповтор - не новое нажатие'
	t.key_release(int(`\\`), sc_backslash_key, 0)
	assert log.events == ['press', 'release']
	// отпускание без нажатия - ничего
	t.key_release(int(`\\`), sc_backslash_key, 0)
	assert log.events.len == 2
}

// Окно потеряло фокус с зажатой клавишей: отпускание придёт другому окну,
// поэтому удержание отпускается сразу.
fn test_hold_released_on_focus_lost() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut log := &HoldLog{}
	t.app.bind_hold_hotkey('\\', fn [mut log] () {
		log.events << 'press'
	}, fn [mut log] () {
		log.events << 'release'
	})
	t.key_press(int(`\\`), sc_backslash_key, 0)
	t.win.dispatch_event_with_app(&GuiEvent{ typ: .window_focus_lost }, t.app)
	assert log.events == ['press', 'release']
}

// ShortcutOverride: однобуквенная горячая клавиша не срабатывает, пока в
// фокусе поле ввода (буква - полю), а с Ctrl - срабатывает.
fn test_text_field_overrides_printable_hotkeys() {
	mut t := new_test_ui(width: 300, height: 120)!
	defer {
		t.close()
	}
	mut log := &HoldLog{}
	t.win.bind_hotkey('Q', fn [mut log] () {
		log.events << 'q'
	})
	t.win.bind_hotkey('Ctrl+Q', fn [mut log] () {
		log.events << 'ctrl+q'
	})
	mut root := create_vbox_fill()
	mut input := text_input('')
	root.add(input)
	t.add(root)
	t.key(int(`q`), 0)
	assert log.events == ['q'], 'без фокуса в поле - горячая клавиша'
	t.click_widget(input)
	t.key(int(`q`), 0)
	assert log.events == ['q'], 'поле в фокусе - буква его'
	t.key(int(`q`), sdl_kmod_ctrl)
	assert log.events == ['q', 'ctrl+q'], 'с Ctrl - сочетание'
}

// Фильтр событий видит событие раньше маршрута и может его поглотить;
// фильтр приложения - раньше фильтра окна.
fn test_event_filters_run_first() {
	mut t := new_test_ui(width: 300, height: 120)!
	defer {
		t.close()
	}
	mut log := &HoldLog{}
	t.app.add_event_filter(fn [mut log] (ev &GuiEvent) bool {
		if ev.typ == .key_down {
			log.events << 'app'
		}
		return false
	})
	t.win.add_event_filter(fn [mut log] (ev &GuiEvent) bool {
		if ev.typ == .key_down && ev.keycode == `x` {
			log.events << 'win'
			return true
		}
		return false
	})
	mut root := create_vbox_fill()
	mut input := text_input('')
	root.add(input)
	t.add(root)
	t.click_widget(input)
	t.key(int(`x`), 0)
	assert log.events == ['app', 'win']
	// x поглощён фильтром - поле его не получило (текст идёт отдельным
	// событием, но и Backspace-подобные клавиши поле не увидело бы)
	t.key(sdl_k_backspace, 0)
	assert log.events == ['app', 'win', 'app']
}

// Сочетания меню и горячих клавиш в русской раскладке: для каждой клавиши,
// которую умеет называть vgui (shortcut_key_name), событие с кириллицей в
// keycode совпадает с сочетанием, построенным по месту клавиши
// (shortcut_from_event) - тем, что хранят настройки и меню.
fn test_shortcuts_match_in_russian_layout() {
	// буква US -> символ ЙЦУКЕН на той же клавише
	ru := {
		`a`: `ф`
		`b`: `и`
		`c`: `с`
		`d`: `в`
		`e`: `у`
		`f`: `а`
		`g`: `п`
		`h`: `р`
		`i`: `ш`
		`j`: `о`
		`k`: `л`
		`l`: `д`
		`m`: `ь`
		`n`: `т`
		`o`: `щ`
		`p`: `з`
		`q`: `й`
		`r`: `к`
		`s`: `ы`
		`t`: `е`
		`u`: `г`
		`v`: `м`
		`w`: `ц`
		`x`: `ч`
		`y`: `н`
		`z`: `я`
	}
	ru_sym := {
		47: `х` // [
		48: `ъ` // ]
		51: `ж` // ;
		52: `э` // '
		53: `ё` // `
		54: `б` // ,
		55: `ю` // .
		56: `.` // /
	}
	mut scancodes := []int{}
	for sc in 4 .. 40 {
		scancodes << sc
	}
	for sc in 58 .. 70 {
		scancodes << sc
	}
	for sc, _ in shortcut_sc_names {
		scancodes << sc
	}
	for sc in scancodes {
		name := shortcut_key_name(sc)
		if name.len == 0 {
			continue
		}
		keycode := if sc >= 4 && sc <= 29 {
			int(ru[rune(`a` + sc - 4)] or { 0 })
		} else if c := ru_sym[sc] {
			int(c)
		} else if name.len == 1 {
			int(name.to_lower()[0])
		} else {
			// служебные клавиши: keycode SDL = scancode | 1 << 30
			match name {
				'Enter' { 13 }
				'Escape' { 27 }
				'Backspace' { 8 }
				'Tab' { 9 }
				'Space' { 32 }
				'Delete' { 127 }
				else { sc | (1 << 30) }
			}
		}
		for mods in [u16(0), sdl_kmod_ctrl, sdl_kmod_ctrl | sdl_kmod_shift] {
			ev := GuiEvent{
				typ:      .key_down
				keycode:  keycode
				scancode: sc
				mod_keys: mods
			}
			combo := shortcut_from_event(&ev)
			assert menu_shortcut_matches(combo, &ev), '${combo} (scancode ${sc}, keycode ${keycode}) не совпало'
		}
	}
}
