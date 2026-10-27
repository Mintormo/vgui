module vgui

// ShortcutInput - поле ввода сочетания клавиш (как QKeySequenceEdit в Qt): кнопка с текущим
// сочетанием; щелчок (или Enter/пробел в фокусе) - ожидание нажатия, следующее сочетание
// становится значением. В ожидании: Esc - отмена, Backspace/Delete - снять сочетание,
// модификатор сам по себе - ждать дальше, сочетание из reserved - отказ (on_reject),
// ожидание продолжается. Щелчок мимо поля или потеря фокуса окном - отмена.
//
// Сочетание пишется в каноническом виде shortcut_from_event: «Ctrl+Shift+Alt+Клавиша»,
// клавиша - по МЕСТУ (scancode, раскладка US), поэтому в русской раскладке P - это «P», а не
// «З». Такие строки понимают меню (MenuItem.shortcut) и HotkeyManager.bind - их сравнение
// тоже идёт по физической клавише (menu_shortcut_matches).
//
// Устройство. Рисует и принимает щелчки внутренняя кнопка (btn): вид, наведение, нажатие,
// фокус и Tab, неактивность - как у обычной Button. На время ожидания поле занимает слот
// оверлея окна (overlay.v, владелец - само поле): обработчик оверлея получает события
// ПЕРВЫМ, раньше меню, горячих клавиш окна и любых виджетов, - нажатое сочетание не уйдёт
// в меню и не сработает как действие. Открытие другого попапа (меню, список) вытесняет
// ожидание (close-хук), как один попап вытесняет другой.
//
// Внутренняя кнопка - отдельный объект в фокус-учёте окна: мост при уничтожении поля
// снимает с учёта и её (vgui-capi, vgui_destroy).

// ShortcutInput - см. шапку файла. shortcut - текущее сочетание ("" - нет); reserved -
// сочетания, которые назначить нельзя (в каноническом виде); empty_text/wait_text - надписи
// «нет сочетания» и «ждём нажатия» ("" - встроенные «нет» / «Нажмите сочетание...»).
// on_change(s) - назначено s ("" - снято); on_reject(s) - нажато занятое s, ожидание
// продолжается; on_wait(w) - ожидание началось (true) или кончилось (false).
@[heap]
pub struct ShortcutInput {
pub mut:
	type_tag   int = kind_shortcut_input // тег типа, см. widget_tag.v
	css        CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds     Rect
	shortcut   string
	reserved   []string
	empty_text string
	wait_text  string
	visible    bool = true
	enabled    bool = true // false - не нажимается, ожидание прерывается (enabled.v)
	tooltip    string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd        &DragSpec   = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	on_change  fn (string) = unsafe { nil }
	on_reject  fn (string) = unsafe { nil }
	on_wait    fn (bool)   = unsafe { nil }
	// btn - внутренняя кнопка: рисует поле и принимает щелчки (создаётся в shortcut_input)
	btn &Button = unsafe { nil }
mut:
	waiting bool
	// toggle_req - щелчок по кнопке попросил начать/прервать ожидание; выполняется в
	// handle_event после кнопки (там есть App и контекст окна для слота оверлея)
	toggle_req bool
	// ctx - контекст окна, чей слот оверлея занят ожиданием (nil - не ждём)
	ctx &RenderContext = unsafe { nil }
}

// owns_focus — фокус у внутренней кнопки (FocusOwner, event_route.v).
pub fn (si &ShortcutInput) owns_focus(ptr voidptr) bool {
	return !isnil(si.btn) && voidptr(si.btn) == ptr
}

// shortcut_input создаёт поле с сочетанием shortcut (приводится к каноническому виду).
pub fn shortcut_input(shortcut string) &ShortcutInput {
	mut si := &ShortcutInput{
		shortcut: shortcut_normalize(shortcut)
	}
	mut b := button('')
	// Замыкание - через локальную переменную (PROJECT.md, «Компилятор V»)
	request := fn [mut si] () {
		si.toggle_req = true
	}
	b.on_click = request
	si.btn = b
	return si
}

// is_waiting - поле ждёт нажатия.
pub fn (si &ShortcutInput) is_waiting() bool {
	return si.waiting
}

// set_shortcut задаёт сочетание (в каноническом виде; неизвестная клавиша - ""). on_change
// не зовёт: это значение от программы, а не от пользователя.
pub fn (mut si ShortcutInput) set_shortcut(s string) {
	widget_changed()
	si.shortcut = shortcut_normalize(s)
}

// cancel прерывает ожидание (если поле ждёт): значение не меняется, on_wait(false).
pub fn (mut si ShortcutInput) cancel() {
	si.stop_waiting()
}

// display_text - надпись поля сейчас: ожидание, сочетание или «нет».
fn (si &ShortcutInput) display_text() string {
	if si.waiting {
		return if si.wait_text.len > 0 { si.wait_text } else { tr('si.wait') }
	}
	if si.shortcut.len > 0 {
		return si.shortcut
	}
	return if si.empty_text.len > 0 { si.empty_text } else { tr('si.none') }
}

// sync_btn - внутренняя кнопка по состоянию поля: надпись, акцент в ожидании, видимость.
fn (mut si ShortcutInput) sync_btn() {
	mut b := si.btn
	b.text = si.display_text()
	b.style = if si.waiting { ButtonStyle.accent } else { ButtonStyle.normal }
	b.visible = si.visible
	b.bounds = si.bounds
}

// ─── Ожидание нажатия ──────────────────────────────────

// start_waiting занимает слот оверлея окна ctx: его обработчик (shortcut_wait_event)
// получает события раньше всех. close-хук срабатывает, когда слот забирает другой попап.
fn (mut si ShortcutInput) start_waiting(mut ctx RenderContext) {
	if si.waiting {
		return
	}
	si.waiting = true
	si.ctx = unsafe { &ctx }
	owner := voidptr(si)
	draw := fn (mut _ RenderContext) {}
	ev := fn [mut si] (e &GuiEvent, _ &App) bool {
		return si.wait_event(e)
	}
	close := fn [mut si] (mut _ RenderContext) {
		// Слот уже освобождён (set_overlay вытеснил ожидание) - только состояние поля
		si.ctx = unsafe { nil }
		si.end_wait()
	}
	ctx.set_overlay(owner, draw, ev, close)
	if si.on_wait != unsafe { nil } {
		si.on_wait(true)
	}
}

// stop_waiting - выйти из ожидания: освободить слот оверлея (свой) и сообщить on_wait.
fn (mut si ShortcutInput) stop_waiting() {
	if !si.waiting {
		return
	}
	if si.ctx != unsafe { nil } {
		mut c := si.ctx
		c.clear_overlay(voidptr(si))
		// Окно перерисовать целиком: надпись поля меняется вне события ввода
		c.invalidate_all()
		si.ctx = unsafe { nil }
	}
	si.end_wait()
}

// end_wait - состояние «не ждём» и on_wait(false).
fn (mut si ShortcutInput) end_wait() {
	si.waiting = false
	if si.on_wait != unsafe { nil } {
		si.on_wait(false)
	}
}

// accept - сочетание s назначено ("" - снято): выход из ожидания, затем on_change.
fn (mut si ShortcutInput) accept(s string) {
	si.shortcut = s
	si.stop_waiting()
	if si.on_change != unsafe { nil } {
		si.on_change(s)
	}
}

// wait_event - обработчик слота оверлея на время ожидания. Клавиши (key_down/key_up/
// text_input) поглощаются все: нажатое сочетание - значение поля, а не команда. Щелчок по
// самому полю отдаётся кнопке (она прервёт ожидание), мимо - отмена и щелчок идёт дальше.
fn (mut si ShortcutInput) wait_event(e &GuiEvent) bool {
	match e.typ {
		.key_down {
			si.wait_key(e)
			return true
		}
		.key_up, .text_input {
			return true
		}
		.mouse_down {
			if !si.bounds.contains(e.mouse_x, e.mouse_y) {
				si.stop_waiting()
			}
			return false
		}
		.window_focus_lost {
			si.stop_waiting()
			return false
		}
		else {
			return false
		}
	}
}

// wait_key - нажатие в ожидании: Esc - отмена, Backspace/Delete - снять, модификатор сам
// по себе - ждать, занятое - on_reject, иначе - новое значение.
fn (mut si ShortcutInput) wait_key(e &GuiEvent) {
	name := shortcut_from_event(e)
	if name.len == 0 {
		return
	}
	if name == 'Escape' {
		si.stop_waiting()
		return
	}
	if name == 'Backspace' || name == 'Delete' {
		si.accept('')
		return
	}
	if name in si.reserved {
		if si.on_reject != unsafe { nil } {
			si.on_reject(name)
		}
		return
	}
	si.accept(name)
}

// ─── Widget ────────────────────────────────────────────

// draw - внутренняя кнопка по состоянию поля; неактивное поле гасит её (begin_disabled).
// Неактивность прерывает ожидание.
pub fn (mut si ShortcutInput) draw(mut ctx RenderContext) {
	if !si.visible || si.btn == unsafe { nil } {
		return
	}
	if !ctx.is_enabled(si.enabled) && si.waiting {
		si.stop_waiting()
	}
	si.sync_btn()
	ctx.begin_disabled(si.enabled)
	mut b := si.btn
	b.draw(mut ctx)
	ctx.end_disabled(si.enabled)
}

// handle_event - событие кнопке; если её щелчок попросил переключить ожидание, оно
// начинается (слот оверлея окна - из активного контекста App) или прерывается.
pub fn (mut si ShortcutInput) handle_event(event &GuiEvent, app &App) bool {
	if !si.visible || si.btn == unsafe { nil } {
		return false
	}
	if !si.enabled {
		if si.waiting {
			si.stop_waiting()
		}
		return false
	}
	si.sync_btn()
	mut b := si.btn
	handled := b.handle_event(event, app)
	if si.toggle_req {
		si.toggle_req = false
		if si.waiting {
			si.stop_waiting()
		} else {
			mut ctx := app.get_active_ctx()
			if ctx != unsafe { nil } {
				si.start_waiting(mut ctx)
			}
		}
	}
	return handled
}

// ─── Имена сочетаний ───────────────────────────────────

// Места клавиш (scancode SDL, USB HID usage page 0x07) -> имя в сочетании. Буквы, цифры и
// F1..F12 считаются в shortcut_key_name.
const shortcut_sc_names = {
	45: '-'
	46: '='
	47: '['
	48: ']'
	49: '\\'
	51: ';'
	52: "'"
	53: '`'
	54: ','
	55: '.'
	56: '/'
	40: 'Enter'
	41: 'Escape'
	42: 'Backspace'
	43: 'Tab'
	44: 'Space'
	73: 'Insert'
	74: 'Home'
	75: 'PageUp'
	76: 'Delete'
	77: 'End'
	78: 'PageDown'
	79: 'Right'
	80: 'Left'
	81: 'Down'
	82: 'Up'
}

// shortcut_key_name - имя клавиши по месту (scancode): «A».. «Z», «0».. «9», «F1».. «F12»,
// знаки основного ряда US, именованные (Enter, PageUp...); "" - модификатор или клавиша,
// которой в сочетаниях нет.
pub fn shortcut_key_name(scancode int) string {
	if scancode >= 4 && scancode <= 29 {
		return u8(`A` + scancode - 4).ascii_str()
	}
	if scancode >= 30 && scancode <= 38 {
		return u8(`1` + scancode - 30).ascii_str()
	}
	if scancode == 39 {
		return '0'
	}
	if scancode >= 58 && scancode <= 69 {
		return 'F${scancode - 57}'
	}
	return shortcut_sc_names[scancode] or { '' }
}

// shortcut_compose - каноническое сочетание: модификаторы в порядке Ctrl, Shift, Alt, затем
// клавиша; пустая клавиша - "".
pub fn shortcut_compose(ctrl bool, shift bool, alt bool, key string) string {
	if key.len == 0 {
		return ''
	}
	mut s := ''
	if ctrl {
		s += 'Ctrl+'
	}
	if shift {
		s += 'Shift+'
	}
	if alt {
		s += 'Alt+'
	}
	return s + key
}

// shortcut_from_event - сочетание нажатия key_down по месту клавиши (не зависит от
// раскладки); "" - модификатор сам по себе или клавиша без имени.
pub fn shortcut_from_event(e &GuiEvent) string {
	return shortcut_compose(e.ctrl(), e.shift(), e.alt(), shortcut_key_name(e.scancode))
}

// shortcut_normalize - сочетание из текста (настройки, код) в каноническом виде: регистр и
// порядок модификаторов не важны, «esc»/«return»/«del» - синонимы; неизвестная клавиша - "".
// «Ctrl++» не поддерживается: клавиша «+» - это «=» с Shift.
pub fn shortcut_normalize(s string) string {
	mut ctrl := false
	mut shift := false
	mut alt := false
	mut key := ''
	for p in s.split('+') {
		t := p.trim_space()
		match t.to_lower() {
			'ctrl' { ctrl = true }
			'shift' { shift = true }
			'alt' { alt = true }
			'' {}
			else { key = shortcut_canon_key(t) }
		}
	}
	return shortcut_compose(ctrl, shift, alt, key)
}

// shortcut_canon_key - имя клавиши так, как его даёт shortcut_key_name (буквы - заглавные).
fn shortcut_canon_key(t string) string {
	if t.len == 1 {
		c := t[0]
		if c >= `a` && c <= `z` {
			return u8(c - 32).ascii_str()
		}
		if (c >= `A` && c <= `Z`) || (c >= `0` && c <= `9`) {
			return t
		}
	}
	l := t.to_lower()
	if l.len >= 2 && l.len <= 3 && l[0] == `f` {
		n := l[1..].int()
		if n >= 1 && n <= 12 && '${n}' == l[1..] {
			return 'F${n}'
		}
	}
	for _, name in shortcut_sc_names {
		if name.to_lower() == l {
			return name
		}
	}
	return match l {
		'esc' { 'Escape' }
		'return' { 'Enter' }
		'del' { 'Delete' }
		'pgup' { 'PageUp' }
		'pgdn' { 'PageDown' }
		'ins' { 'Insert' }
		else { '' }
	}
}
