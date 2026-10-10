module vgui

// Юнит-тесты FocusManager (focus.v).
//
// SDL и шрифты не нужны: литералы `&Type{}` дают виджеты с нулевыми полями,
// а register/unregister/tab читают только `visible`/`enabled` и пишут флаг
// `focused`.
//
// Запуск: v -enable-globals test vgui/focus_test.v

// ─── Регистрация снимается симметрично ─────────────────
//
// Главный инвариант пункта 2.1 аудита: после unregister в менеджере не
// остаётся ни записи в entries, ни ключа в registered. Запись хранит сырой
// voidptr, и консервативный Boehm-GC считает её живой ссылкой — оставленная
// запись означает и утечку структуры виджета, и мёртвый виджет в Tab-цикле.

fn test_unregister_clears_both_structures() {
	mut fm := FocusManager{}
	mut b := &Button{
		visible: true
		enabled: true
	}
	fm.register_button(b, 0)
	assert fm.entries.len == 1
	assert fm.registered.len == 1

	fm.unregister(unsafe { voidptr(b) })
	assert fm.entries.len == 0
	assert fm.registered.len == 0
	assert fm.current == -1
}

fn test_unregister_is_idempotent_and_nil_safe() {
	mut fm := FocusManager{}
	mut b := &Button{
		visible: true
		enabled: true
	}
	fm.register_button(b, 0)
	fm.unregister(unsafe { voidptr(b) })
	// Повторное снятие и nil — просто no-op, без паники и порчи состояния.
	fm.unregister(unsafe { voidptr(b) })
	fm.unregister(unsafe { nil })
	assert fm.entries.len == 0
	assert fm.registered.len == 0
}

fn test_unregister_of_focused_widget_drops_focus() {
	mut fm := FocusManager{}
	mut ti := &TextInput{
		visible: true
		enabled: true
	}
	fm.focus_text_input(ti, 0)
	assert fm.current == 0
	assert ti.focused

	fm.unregister(unsafe { voidptr(ti) })
	assert fm.current == -1
	assert fm.entries.len == 0
	// Виджет НЕ блюрится: его структура вот-вот будет освобождена, трогать её
	// поля нельзя. Флаг остаётся как был — это ожидаемо.
	assert ti.focused
}

// ─── fm.current — индекс, а не указатель ───────────────
//
// entries.delete(i) сдвигает всё правее на одну позицию, поэтому при удалении
// элемента ЛЕВЕЕ текущего индекс нужно уменьшать, иначе фокус молча переедет
// на соседний виджет.

fn test_current_follows_widget_when_earlier_entry_removed() {
	mut fm := FocusManager{}
	mut a := &Button{
		visible: true
		enabled: true
	}
	mut b := &Button{
		visible: true
		enabled: true
	}
	mut c := &TextInput{
		visible: true
		enabled: true
	}
	fm.register_button(a, 0)
	fm.register_button(b, 0)
	fm.focus_text_input(c, 0)
	assert fm.current == 2

	fm.unregister(unsafe { voidptr(a) })
	assert fm.entries.len == 2
	assert fm.current == 1
	// Фокус остался на том же виджете, а не съехал на соседа.
	assert fm.is_focused(unsafe { voidptr(c) })
	assert !fm.is_focused(unsafe { voidptr(b) })
}

fn test_current_untouched_when_later_entry_removed() {
	mut fm := FocusManager{}
	mut a := &Button{
		visible: true
		enabled: true
	}
	mut b := &Button{
		visible: true
		enabled: true
	}
	fm.focus_button(a, 0)
	fm.register_button(b, 0)
	assert fm.current == 0

	fm.unregister(unsafe { voidptr(b) })
	assert fm.current == 0
	assert fm.is_focused(unsafe { voidptr(a) })
}

// ─── Уничтоженный виджет уходит из Tab-цикла ───────────

fn test_tab_skips_unregistered_widget() {
	mut fm := FocusManager{}
	mut a := &Button{
		visible: true
		enabled: true
	}
	mut b := &Button{
		visible: true
		enabled: true
	}
	mut c := &Button{
		visible: true
		enabled: true
	}
	fm.register_button(a, 0)
	fm.register_button(b, 0)
	fm.register_button(c, 0)

	fm.unregister(unsafe { voidptr(b) })
	fm.tab(false)
	assert fm.is_focused(unsafe { voidptr(a) })
	fm.tab(false)
	// b снят с учёта — следующий по Tab это c, а не он.
	assert fm.is_focused(unsafe { voidptr(c) })
	fm.tab(false)
	assert fm.is_focused(unsafe { voidptr(a) })
}

// ─── ABA: тот же адрес под виджетом другого типа ───────
//
// Штатно такого не бывает (vgui_destroy снимает регистрацию до освобождения
// структуры), но если виджет до vgui_destroy не дошёл, аллокатор может отдать
// его адрес под виджет ДРУГОГО типа. Старая запись хранила бы старый kind, и
// cast по ней прочитал бы чужой тип. register_ptr обязан такую запись
// заменить, а не проигнорировать регистрацию.

fn test_same_pointer_different_kind_replaces_entry() {
	mut fm := FocusManager{}
	ptr := unsafe { voidptr(usize(0xDEAD0000)) }
	fm.register_ptr(ptr, .text_input, 0)
	assert fm.entries.len == 1
	assert fm.entries[0].kind == .text_input

	fm.register_ptr(ptr, .button, 3)
	assert fm.entries.len == 1
	assert fm.entries[0].kind == .button
	assert fm.entries[0].group == 3
	assert fm.registered.len == 1
}

fn test_same_pointer_same_kind_is_idempotent() {
	mut fm := FocusManager{}
	ptr := unsafe { voidptr(usize(0xBEEF0000)) }
	fm.register_ptr(ptr, .button, 0)
	fm.register_ptr(ptr, .button, 0)
	fm.register_ptr(ptr, .button, 0)
	assert fm.entries.len == 1
	assert fm.registered.len == 1
}

// ─── Реестр не растёт от цикла жизни виджетов ──────────
//
// Тот самый сценарий из замера 6.2 аудита, только без SDL: 50 000 раз
// «зарегистрировать → снять». До правки entries рос линейно и навсегда.

fn test_register_unregister_cycle_leaves_nothing() {
	mut fm := FocusManager{}
	for i in 0 .. 50000 {
		p := unsafe { voidptr(usize(0x100000) + usize(i * 64)) }
		fm.register_ptr(p, .button, 0)
		fm.unregister(p)
	}
	assert fm.entries.len == 0
	assert fm.registered.len == 0
	assert fm.current == -1
}

// ─── MenuButton — собственный FocusKind ────────────────
//
// Пункт 2.2 аудита: раньше MenuButton регистрировался как `&Button(&mb)`.
// Раскладки полей не совпадают (sizeof 176 против 240), поэтому
// is_entry_available читал visible/enabled по чужим смещениям и всегда
// возвращал false — MenuButton не попадал в Tab-цикл никогда.

fn test_menu_button_availability_follows_its_own_fields() {
	mut fm := FocusManager{}
	mut mb := &MenuButton{
		visible: true
		enabled: true
	}
	fm.register_menu_button(mb, 0)
	assert fm.entries.len == 1
	assert fm.entries[0].kind == .menu_button
	assert fm.is_entry_available(fm.entries[0])

	mb.enabled = false
	assert !fm.is_entry_available(fm.entries[0])
	mb.enabled = true
	mb.visible = false
	assert !fm.is_entry_available(fm.entries[0])
	mb.visible = true
	assert fm.is_entry_available(fm.entries[0])
}

fn test_tab_reaches_menu_button() {
	mut fm := FocusManager{}
	mut b := &Button{
		visible: true
		enabled: true
	}
	mut mb := &MenuButton{
		visible: true
		enabled: true
	}
	fm.register_button(b, 0)
	fm.register_menu_button(mb, 0)

	fm.tab(false)
	assert fm.is_focused(unsafe { voidptr(b) })
	fm.tab(false)
	assert fm.is_focused(unsafe { voidptr(mb) })
}

fn test_blur_menu_button_closes_its_menu() {
	mut fm := FocusManager{}
	mut mb := &MenuButton{
		visible: true
		enabled: true
	}
	fm.focus_menu_button(mb, 0)
	mb.pressed = true
	mb.pressed_arrow = true
	mb.open = true

	fm.blur_current()
	assert !mb.pressed
	assert !mb.pressed_arrow
	assert !mb.open
	assert fm.current == -1
}
