module vgui

struct FocusEntry {
mut:
	ptr   voidptr
	kind  FocusKind
	group int
}

pub enum FocusKind {
	text_input
	text_area
	button
	menu_button
	list_box
	combo_box
	checkbox
	radio_button
	toggle_switch
	tab_box
	tree_view
	code_editor
	slider
	property_grid
	calendar
	canvas
}

pub struct FocusManager {
pub mut:
	entries []FocusEntry
	current int = -1
	// registered — быстрый индекс «этот указатель уже в entries», значение
	// хранит kind ЭТОЙ регистрации (а не просто bool): по нему register_ptr
	// за O(1) ловит переиспользование адреса под виджет другого типа — см.
	// комментарий там же.
	registered map[voidptr]FocusKind
}

// ─── Регистрация (идемпотентная — дубликаты игнорируются) ───

fn (mut fm FocusManager) register_ptr(ptr voidptr, kind FocusKind, group int) {
	if ptr == unsafe { nil } {
		return
	}
	if ptr in fm.registered {
		if fm.registered[ptr] == kind {
			return
		}
		// Тот же адрес, но виджет ДРУГОГО типа — аллокатор отдал память
		// освобождённой структуры под новую (ABA). Старая запись хранит
		// старый kind, и любой cast по ней (blur_current / focus_index /
		// is_entry_available) прочитал бы чужой тип. Снимаем её и
		// регистрируем заново с актуальным типом.
		//
		// Штатный путь такого не допускает: vgui_destroy снимает регистрацию
		// до освобождения структуры (см. unregister ниже). Это страховка на
		// случай виджета, который до vgui_destroy не дошёл.
		fm.unregister(ptr)
	}
	fm.registered[ptr] = kind
	fm.entries << FocusEntry{
		ptr:   ptr
		kind:  kind
		group: group
	}
}

// unregister снимает регистрацию виджета — вызывается из vgui_destroy ДО
// освобождения структуры (см. capi_unregister_focus_everywhere).
//
// Зачем это обязательно: FocusEntry хранит voidptr на структуру виджета, а
// Boehm-GC консервативен — он считает такой указатель живой ссылкой. Пока
// запись висит в entries, структура уничтоженного виджета не собирается
// (утечка), продолжает участвовать в Tab-цикле (фокус «пропадает в никуда»)
// и может получить cast чужого типа, если её адрес переиспользуют.
//
// Виджет НЕ блюрится: его поля уже нельзя трогать (структура вот-вот будет
// освобождена), поэтому фокус на удаляемой записи просто сбрасывается в -1.
pub fn (mut fm FocusManager) unregister(ptr voidptr) {
	if ptr == unsafe { nil } || ptr !in fm.registered {
		return
	}
	fm.registered.delete(ptr)
	for i, e in fm.entries {
		if e.ptr == ptr {
			// current — ИНДЕКС в entries, а не указатель: после delete
			// элементы правее съезжают на один влево, поэтому его нужно
			// поправить, иначе фокус «переедет» на соседний виджет.
			if fm.current == i {
				fm.current = -1
			} else if fm.current > i {
				fm.current--
			}
			fm.entries.delete(i)
			break
		}
	}
}

pub fn (mut fm FocusManager) register_text_input(ti &TextInput, group int) {
	fm.register_ptr(unsafe { voidptr(ti) }, .text_input, group)
}

pub fn (mut fm FocusManager) register_button(b &Button, group int) {
	fm.register_ptr(unsafe { voidptr(b) }, .button, group)
}

// MenuButton — СВОЙ kind, а не .button. Раньше menu_button.v регистрировался
// как `&Button(&mb)`: раскладки полей не совпадают (sizeof 176 против 240,
// расхождение начинается с `placeholder`), поэтому is_entry_available читал
// visible/enabled по чужим смещениям и всегда возвращал false — MenuButton
// никогда не попадал в Tab-цикл, — а blur_current писал байт в чужое поле.
pub fn (mut fm FocusManager) register_menu_button(mb &MenuButton, group int) {
	fm.register_ptr(unsafe { voidptr(mb) }, .menu_button, group)
}

pub fn (mut fm FocusManager) focus_menu_button(mb &MenuButton, group int) {
	fm.focus_ptr(unsafe { voidptr(mb) }, .menu_button, group)
}

pub fn (mut fm FocusManager) register_list_box(lb &ListBox, group int) {
	fm.register_ptr(unsafe { voidptr(lb) }, .list_box, group)
}

pub fn (mut fm FocusManager) register_combo_box(cb &ComboBox, group int) {
	fm.register_ptr(unsafe { voidptr(cb) }, .combo_box, group)
}

pub fn (mut fm FocusManager) register_checkbox(cb &CheckBox, group int) {
	fm.register_ptr(unsafe { voidptr(cb) }, .checkbox, group)
}

pub fn (mut fm FocusManager) register_radio_button(rb &RadioButton, group int) {
	fm.register_ptr(unsafe { voidptr(rb) }, .radio_button, group)
}

pub fn (mut fm FocusManager) register_toggle_switch(ts &ToggleSwitch, group int) {
	fm.register_ptr(unsafe { voidptr(ts) }, .toggle_switch, group)
}

pub fn (mut fm FocusManager) register_tab_box(tb &TabBox, group int) {
	fm.register_ptr(unsafe { voidptr(tb) }, .tab_box, group)
}

pub fn (mut fm FocusManager) register_tree_view(tv &TreeView, group int) {
	fm.register_ptr(unsafe { voidptr(tv) }, .tree_view, group)
}

pub fn (mut fm FocusManager) focus_tree_view(tv &TreeView, group int) {
	fm.focus_ptr(unsafe { voidptr(tv) }, .tree_view, group)
}

pub fn (mut fm FocusManager) register_code_editor(ce &CodeEditor, group int) {
	fm.register_ptr(unsafe { voidptr(ce) }, .code_editor, group)
}

pub fn (mut fm FocusManager) focus_code_editor(ce &CodeEditor, group int) {
	fm.focus_ptr(unsafe { voidptr(ce) }, .code_editor, group)
}

pub fn (mut fm FocusManager) register_slider(s &Slider, group int) {
	fm.register_ptr(unsafe { voidptr(s) }, .slider, group)
}

pub fn (mut fm FocusManager) focus_slider(s &Slider, group int) {
	fm.focus_ptr(unsafe { voidptr(s) }, .slider, group)
}

// ─── Фокус с авто-регистрацией ───

fn (mut fm FocusManager) focus_ptr(ptr voidptr, kind FocusKind, group int) {
	fm.register_ptr(ptr, kind, group)
	for i, e in fm.entries {
		if e.ptr == ptr {
			fm.focus_index(i)
			return
		}
	}
}

pub fn (mut fm FocusManager) focus_text_input(ti &TextInput, group int) {
	fm.focus_ptr(unsafe { voidptr(ti) }, .text_input, group)
}

pub fn (mut fm FocusManager) register_text_area(ta &TextArea, group int) {
	fm.register_ptr(unsafe { voidptr(ta) }, .text_area, group)
}

pub fn (mut fm FocusManager) focus_text_area(ta &TextArea, group int) {
	fm.focus_ptr(unsafe { voidptr(ta) }, .text_area, group)
}

pub fn (mut fm FocusManager) focus_button(b &Button, group int) {
	fm.focus_ptr(unsafe { voidptr(b) }, .button, group)
}

pub fn (mut fm FocusManager) focus_list_box(lb &ListBox, group int) {
	fm.focus_ptr(unsafe { voidptr(lb) }, .list_box, group)
}

pub fn (mut fm FocusManager) focus_combo_box(cb &ComboBox, group int) {
	fm.focus_ptr(unsafe { voidptr(cb) }, .combo_box, group)
}

pub fn (mut fm FocusManager) focus_checkbox(cb &CheckBox, group int) {
	fm.focus_ptr(unsafe { voidptr(cb) }, .checkbox, group)
}

pub fn (mut fm FocusManager) focus_radio_button(rb &RadioButton, group int) {
	fm.focus_ptr(unsafe { voidptr(rb) }, .radio_button, group)
}

pub fn (mut fm FocusManager) focus_toggle_switch(ts &ToggleSwitch, group int) {
	fm.focus_ptr(unsafe { voidptr(ts) }, .toggle_switch, group)
}

pub fn (mut fm FocusManager) focus_tab_box(tb &TabBox, group int) {
	fm.focus_ptr(unsafe { voidptr(tb) }, .tab_box, group)
}

pub fn (mut fm FocusManager) register_property_grid(pg &PropertyGrid, group int) {
	fm.register_ptr(unsafe { voidptr(pg) }, .property_grid, group)
}

pub fn (mut fm FocusManager) focus_property_grid(pg &PropertyGrid, group int) {
	fm.focus_ptr(unsafe { voidptr(pg) }, .property_grid, group)
}

pub fn (mut fm FocusManager) register_calendar(cal &Calendar, group int) {
	fm.register_ptr(unsafe { voidptr(cal) }, .calendar, group)
}

pub fn (mut fm FocusManager) focus_calendar(cal &Calendar, group int) {
	fm.focus_ptr(unsafe { voidptr(cal) }, .calendar, group)
}

pub fn (mut fm FocusManager) register_canvas(cv &Canvas, group int) {
	fm.register_ptr(unsafe { voidptr(cv) }, .canvas, group)
}

pub fn (mut fm FocusManager) focus_canvas(cv &Canvas, group int) {
	fm.focus_ptr(unsafe { voidptr(cv) }, .canvas, group)
}

// ─── Снять фокус ───

pub fn (mut fm FocusManager) blur_current() {
	if fm.current < 0 || fm.current >= fm.entries.len {
		return
	}
	e := fm.entries[fm.current]
	match e.kind {
		.text_input {
			mut ti := unsafe { &TextInput(e.ptr) }
			ti.focused = false
			ti.drag = false
			ti.clear_sel()
		}
		.text_area {
			mut ta := unsafe { &TextArea(e.ptr) }
			ta.focused = false
			ta.drag = false
			ta.clear_sel()
		}
		.button {
			mut b := unsafe { &Button(e.ptr) }
			b.pressed = false
		}
		.menu_button {
			mut mb := unsafe { &MenuButton(e.ptr) }
			mb.pressed = false
			mb.pressed_arrow = false
			mb.open = false
		}
		.list_box {
			mut lb := unsafe { &ListBox(e.ptr) }
			lb.focused = false
		}
		.combo_box {
			mut cb := unsafe { &ComboBox(e.ptr) }
			cb.focused = false
			cb.open = false
		}
		.checkbox {}
		.radio_button {}
		.toggle_switch {}
		.tab_box {
			mut tb := unsafe { &TabBox(e.ptr) }
			tb.focused = false
		}
		.tree_view {
			mut tv := unsafe { &TreeView(e.ptr) }
			tv.focused = false
		}
		.code_editor {
			mut ce := unsafe { &CodeEditor(e.ptr) }
			ce.focused = false
			ce.drag = false
			ce.clear_sel()
		}
		.slider {
			mut s := unsafe { &Slider(e.ptr) }
			s.focused = false
			s.dragging = false
		}
		.property_grid {
			mut pg := unsafe { &PropertyGrid(e.ptr) }
			pg.focused = false
		}
		.calendar {
			mut cal := unsafe { &Calendar(e.ptr) }
			cal.focused = false
		}
		.canvas {
			mut cv := unsafe { &Canvas(e.ptr) }
			cv.focused = false
			cv.drawing = false
			cv.draw_button = .none_
		}
	}

	fm.current = -1
}

// ─── Установить фокус по индексу ───

fn (mut fm FocusManager) focus_index(idx int) {
	if idx < 0 || idx >= fm.entries.len {
		return
	}
	fm.blur_current()
	fm.current = idx
	e := fm.entries[idx]
	match e.kind {
		.text_input {
			mut ti := unsafe { &TextInput(e.ptr) }
			ti.focused = true
		}
		.text_area {
			mut ta := unsafe { &TextArea(e.ptr) }
			ta.focused = true
		}
		.button {}
		.menu_button {}
		.list_box {
			mut lb := unsafe { &ListBox(e.ptr) }
			lb.focused = true
		}
		.combo_box {
			mut cb := unsafe { &ComboBox(e.ptr) }
			cb.focused = true
		}
		.checkbox {}
		.radio_button {}
		.toggle_switch {}
		.tab_box {
			mut tb := unsafe { &TabBox(e.ptr) }
			tb.focused = true
		}
		.tree_view {
			mut tv := unsafe { &TreeView(e.ptr) }
			tv.focused = true
		}
		.code_editor {
			mut ce := unsafe { &CodeEditor(e.ptr) }
			ce.focused = true
		}
		.slider {
			mut s := unsafe { &Slider(e.ptr) }
			s.focused = true
		}
		.property_grid {
			mut pg := unsafe { &PropertyGrid(e.ptr) }
			pg.focused = true
		}
		.calendar {
			mut cal := unsafe { &Calendar(e.ptr) }
			cal.focused = true
		}
		.canvas {
			mut cv := unsafe { &Canvas(e.ptr) }
			cv.focused = true
		}
	}
}

// ─── Tab / Shift+Tab ───

pub fn (mut fm FocusManager) tab(reverse bool) {
	if fm.entries.len == 0 {
		return
	}

	group := if fm.current >= 0 && fm.current < fm.entries.len {
		fm.entries[fm.current].group
	} else {
		0
	}

	mut indices := []int{cap: fm.entries.len}
	for i, e in fm.entries {
		if e.group == group {
			if fm.is_entry_available(e) {
				indices << i
			}
		}
	}

	if indices.len == 0 {
		return
	}

	mut pos := -1
	for i, idx in indices {
		if idx == fm.current {
			pos = i
			break
		}
	}

	mut next_pos := 0
	if pos < 0 {
		next_pos = if reverse { indices.len - 1 } else { 0 }
	} else if reverse {
		next_pos = if pos > 0 { pos - 1 } else { indices.len - 1 }
	} else {
		next_pos = if pos < indices.len - 1 { pos + 1 } else { 0 }
	}

	fm.focus_index(indices[next_pos])
}

// ─── Проверки ───

fn (fm &FocusManager) is_entry_available(e FocusEntry) bool {
	match e.kind {
		.text_input {
			ti := unsafe { &TextInput(e.ptr) }
			return ti.visible && ti.enabled
		}
		.text_area {
			ta := unsafe { &TextArea(e.ptr) }
			return ta.visible && ta.enabled
		}
		.button {
			b := unsafe { &Button(e.ptr) }
			return b.visible && b.enabled
		}
		.menu_button {
			mb := unsafe { &MenuButton(e.ptr) }
			return mb.visible && mb.enabled
		}
		.list_box {
			lb := unsafe { &ListBox(e.ptr) }
			return lb.visible && lb.enabled
		}
		.combo_box {
			cb := unsafe { &ComboBox(e.ptr) }
			return cb.visible && cb.enabled
		}
		.checkbox {
			cb := unsafe { &CheckBox(e.ptr) }
			return cb.visible && cb.enabled
		}
		.radio_button {
			rb := unsafe { &RadioButton(e.ptr) }
			return rb.visible && rb.enabled
		}
		.toggle_switch {
			ts := unsafe { &ToggleSwitch(e.ptr) }
			return ts.visible && ts.enabled
		}
		.tab_box {
			tb := unsafe { &TabBox(e.ptr) }
			return tb.visible && tb.enabled
		}
		.tree_view {
			tv := unsafe { &TreeView(e.ptr) }
			return tv.visible && tv.enabled
		}
		.code_editor {
			ce := unsafe { &CodeEditor(e.ptr) }
			return ce.visible && ce.enabled
		}
		.slider {
			s := unsafe { &Slider(e.ptr) }
			return s.visible && s.enabled
		}
		.property_grid {
			pg := unsafe { &PropertyGrid(e.ptr) }
			return pg.visible && pg.enabled
		}
		.calendar {
			cal := unsafe { &Calendar(e.ptr) }
			return cal.visible && cal.enabled
		}
		.canvas {
			cv := unsafe { &Canvas(e.ptr) }
			return cv.visible && cv.enabled
		}
	}
}

// wants_text - виджету в фокусе нужен текстовый ввод SDL (Window.
// sync_text_input): поле ввода (в т.ч. внутри Spinbox и PropertyGrid),
// текстовая область, редактор кода; дерево и сетка свойств - только во
// время правки
pub fn (fm &FocusManager) wants_text() bool {
	if fm.current < 0 || fm.current >= fm.entries.len {
		return false
	}
	e := fm.entries[fm.current]
	return match e.kind {
		.text_input, .text_area, .code_editor {
			true
		}
		.tree_view {
			tv := unsafe { &TreeView(e.ptr) }
			tv.editing
		}
		.property_grid {
			pg := unsafe { &PropertyGrid(e.ptr) }
			pg.editing
		}
		else {
			false
		}
	}
}

pub fn (fm &FocusManager) is_focused(ptr voidptr) bool {
	if fm.current < 0 || fm.current >= fm.entries.len {
		return false
	}
	return fm.entries[fm.current].ptr == ptr
}
