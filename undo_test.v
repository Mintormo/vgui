module vgui

// Тесты undo.v: UndoHistory[T] (встроенная отмена виджетов) и UndoStack
// (стек команд приложения). SDL не нужен.

// Счётчик — именованная структура: указатель на анонимную даёт невалидный C.
@[heap]
struct UndoProbe {
mut:
	value    int
	log      []string
	released []string
	changes  int
}

// add_cmd — команда «прибавить n» к probe.value.
fn add_cmd(mut p UndoProbe, n int, text string, merge_id int) UndoCommand {
	redo_fn := fn [mut p, n, text] () {
		p.value += n
		p.log << 'redo ${text}'
	}
	undo_fn := fn [mut p, n, text] () {
		p.value -= n
		p.log << 'undo ${text}'
	}
	release_fn := fn [mut p, text] () {
		p.released << text
	}
	return UndoCommand{
		text:     text
		merge_id: merge_id
		redo:     redo_fn
		undo:     undo_fn
		release:  release_fn
	}
}

fn test_history_basic() {
	mut h := UndoHistory[int]{
		limit: 3
	}
	assert !h.can_undo()
	h.save(1)
	h.save(2)
	h.save(3)
	h.save(4) // 1 выпадает по limit
	assert h.undo_stack == [2, 3, 4]
	got := h.undo(5) or { -1 }
	assert got == 4
	assert h.can_redo()
	back := h.redo(4) or { -1 }
	assert back == 5
	h.save(6) // новая правка обрывает повтор
	assert !h.can_redo()
	h.clear()
	assert !h.can_undo()
	none_got := h.undo(0) or { -1 }
	assert none_got == -1
}

fn test_history_rune_snap() {
	mut h := UndoHistory[RuneSnap]{}
	h.save(RuneSnap{
		buf: 'ab'.runes()
		cur: 2
	})
	got := h.undo(RuneSnap{ buf: 'abc'.runes(), cur: 3 }) or { panic('пусто') }
	assert got.buf.string() == 'ab'
	assert got.cur == 2
	assert h.redo_stack[0].buf.string() == 'abc'
}

fn test_stack_push_undo_redo() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	on_change := fn [mut p] () {
		p.changes++
	}
	s.on_change = on_change
	assert s.push(add_cmd(mut p, 5, 'a', 0)) // push выполняет redo
	assert p.value == 5
	assert s.record(add_cmd(mut p, 0, 'b', 0)) // record — нет
	assert p.log == ['redo a']
	assert s.count() == 2 && s.index() == 2
	assert s.undo_text() == 'b'
	assert s.undo() && s.undo()
	assert p.value == 0
	assert !s.can_undo() && !s.undo()
	assert s.redo_text() == 'a'
	assert s.redo()
	assert p.value == 5
	// новая команда обрывает ветку повтора и освобождает её
	s.push(add_cmd(mut p, 1, 'c', 0))
	assert p.released == ['b']
	assert !s.can_redo()
	assert p.changes == 6
}

fn test_stack_merge() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	s.push(add_cmd(mut p, 1, 'x', 0))
	s.push(add_cmd(mut p, 1, 's1', 7))
	s.push(add_cmd(mut p, 2, 's2', 7))
	s.push(add_cmd(mut p, 3, 's3', 7))
	assert s.count() == 2 // x + один слитый шаг
	assert s.undo_text() == 's3'
	assert p.value == 7
	s.undo()
	assert p.value == 1
	assert p.log#[-3..] == ['undo s3', 'undo s2', 'undo s1']
	s.redo()
	assert p.value == 7
	// другой merge_id — новый шаг
	s.push(add_cmd(mut p, 1, 'o', 8))
	assert s.count() == 3
}

fn test_stack_no_merge_across_clean() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	s.push(add_cmd(mut p, 1, 's1', 7))
	s.set_clean()
	s.push(add_cmd(mut p, 1, 's2', 7))
	assert s.count() == 2
	assert !s.is_clean()
	s.undo()
	assert s.is_clean()
}

fn test_stack_clean_unreachable() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	assert s.is_clean()
	s.push(add_cmd(mut p, 1, 'a', 0))
	s.push(add_cmd(mut p, 1, 'b', 0))
	s.set_clean()
	s.undo()
	s.undo()
	s.push(add_cmd(mut p, 1, 'c', 0)) // ветка с чистым состоянием оборвана
	assert !s.is_clean()
	s.undo()
	assert !s.is_clean()
}

fn test_stack_limit() {
	mut p := &UndoProbe{}
	mut s := undo_stack(2)
	s.push(add_cmd(mut p, 1, 'a', 0))
	s.set_clean()
	s.push(add_cmd(mut p, 1, 'b', 0))
	s.push(add_cmd(mut p, 1, 'c', 0))
	assert s.count() == 2
	assert p.released == ['a']
	s.undo()
	s.undo()
	assert !s.can_undo()
	assert s.is_clean() // «после a» по-прежнему достижимо: это pos 0
	assert p.value == 1
	s.set_limit(1) // ветка повтора длиннее limit — режется её конец
	assert s.count() == 1
	assert p.released == ['a', 'c']
	assert s.redo_text() == 'b'
	// чистое состояние «до всего» выпадает вместе с первой командой
	mut s2 := undo_stack(1)
	assert s2.is_clean()
	s2.push(add_cmd(mut p, 1, 'x', 0))
	s2.push(add_cmd(mut p, 1, 'y', 0))
	s2.undo()
	assert !s2.is_clean()
}

fn test_stack_group() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	assert s.begin_group('G')
	s.push(add_cmd(mut p, 1, 'a', 0))
	s.begin_group('inner')
	s.push(add_cmd(mut p, 10, 'b', 0))
	s.end_group()
	assert !s.can_undo() // группа открыта
	s.push(add_cmd(mut p, 100, 'c', 0))
	assert s.end_group()
	assert s.count() == 1 && s.undo_text() == 'G'
	assert p.value == 111
	s.undo()
	assert p.value == 0
	assert p.log#[-3..] == ['undo c', 'undo b', 'undo a']
	s.redo()
	assert p.value == 111
	// пустая группа шага не добавляет
	s.begin_group('empty')
	s.end_group()
	assert s.count() == 1
	assert !s.end_group() // лишний end_group
}

// Команда, которая во время своего redo пытается положить в стек ещё одну.
@[heap]
struct ReentryProbe {
mut:
	stack     &UndoStack = unsafe { nil }
	nested_ok bool       = true
}

fn test_stack_reentry_refused() {
	mut r := &ReentryProbe{}
	mut s := undo_stack(0)
	r.stack = s
	redo_fn := fn [mut r] () {
		mut st := r.stack
		r.nested_ok = st.push(UndoCommand{
			text: 'nested'
		})
	}
	s.push(UndoCommand{
		text: 'outer'
		redo: redo_fn
	})
	assert !r.nested_ok
	assert s.count() == 1
}

fn test_stack_clear_and_destroy_release() {
	mut p := &UndoProbe{}
	mut s := undo_stack(0)
	s.push(add_cmd(mut p, 1, 'a', 0))
	s.push(add_cmd(mut p, 1, 'b', 0))
	s.undo()
	s.begin_group('g')
	s.push(add_cmd(mut p, 1, 'in_group', 0))
	assert s.clear()
	assert p.released == ['a', 'b', 'in_group']
	assert s.count() == 0 && s.is_clean() && !s.in_group()
	s.push(add_cmd(mut p, 1, 'c', 0))
	changes_before := p.changes
	s.destroy()
	assert p.released == ['a', 'b', 'in_group', 'c']
	assert p.changes == changes_before
}

// ───────────── встроенная отмена виджетов ──────────────

fn test_text_input_undo_redo() {
	mut t := text_input('')
	assert !t.can_undo() && !t.undo()
	t.insert('ab')
	t.insert('c')
	assert t.get_text() == 'abc'
	assert t.undo()
	assert t.get_text() == 'ab'
	assert t.can_redo()
	assert t.redo()
	assert t.get_text() == 'abc'
	t.clear_undo()
	assert !t.can_undo() && !t.can_redo()
	// set_text тоже забывает историю
	t.insert('d')
	t.set_text('x')
	assert !t.can_undo()
}

// Вставка, из которой фильтр выкинул всё, — не правка: выделение цело,
// ветка повтора не оборвана.
fn test_text_input_filtered_insert_is_noop() {
	mut t := text_input('')
	t.input_filter = '[0-9]'
	t.input_filter_mode = .whitelist
	t.insert('12')
	t.insert('3')
	t.undo()
	assert t.can_redo()
	t.sel_a = 0
	t.sel_b = 2
	t.insert('ab')
	assert t.get_text() == '12'
	assert t.can_redo()
	// упёрлись в max_len — тоже без снимка
	t.max_len = 2
	t.sel_a = -1
	t.sel_b = -1
	t.insert('5')
	assert t.can_redo()
	assert t.redo()
	assert t.get_text() == '123'
}

fn test_text_area_undo_redo() {
	mut ta := text_area('')
	ta.insert_text('one')
	ta.insert_text('\ntwo')
	assert ta.get_text() == 'one\ntwo'
	assert ta.undo()
	assert ta.get_text() == 'one'
	assert ta.redo()
	assert ta.get_text() == 'one\ntwo'
	ta.clear_undo()
	assert !ta.can_undo()
}

fn test_code_editor_undo_redo() {
	mut e := code_editor()
	e.insert_text('fn main() {}')
	e.insert_text('\n// x')
	assert e.get_text() == 'fn main() {}\n// x'
	assert e.undo()
	assert e.get_text() == 'fn main() {}'
	assert e.can_redo()
	assert e.redo()
	assert e.get_text() == 'fn main() {}\n// x'
	e.set_text('')
	assert !e.can_undo() && !e.can_redo()
}

// ─── Слияние набора по словам (UndoHistory.save_typing) ───

// t_type — набор строки посимвольно, как с клавиатуры (событие ввода на
// каждый символ - так набор приходит от SDL).
fn t_type(mut t TestUi, s string) {
	for r in s.runes() {
		t.type_text(r.str())
	}
}

// Набор подряд - один шаг на слово: «привет мир» отменяется как «мир», затем
// «привет »; Backspace подряд - один шаг; перемещение курсора начинает новый.
fn test_typing_merges_by_words() {
	mut t := new_test_ui(width: 300, height: 260)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut ti := text_input('')
	mut ta := text_area('')
	mut ce := code_editor()
	root.add(ti)
	root.add(ta, flex: 1)
	root.add(ce, flex: 1)
	t.add(root)

	t.click_widget(ti)
	t_type(mut t, 'привет мир')
	assert ti.get_text() == 'привет мир'
	assert ti.undo() && ti.get_text() == 'привет '
	assert ti.undo() && ti.get_text() == ''
	assert ti.redo() && ti.get_text() == 'привет '
	assert ti.redo() && ti.get_text() == 'привет мир'
	// три Backspace - один шаг
	for _ in 0 .. 3 {
		t.key(sdl_k_backspace, 0)
	}
	assert ti.get_text() == 'привет '
	assert ti.undo() && ti.get_text() == 'привет мир'
	// курсор сдвинули - новый шаг: «аб», Home, «в» отменяются по отдельности
	ti.set_text('')
	t_type(mut t, 'аб')
	t.key(sdl_k_home, 0)
	t_type(mut t, 'в')
	assert ti.get_text() == 'ваб'
	assert ti.undo() && ti.get_text() == 'аб'
	assert ti.undo() && ti.get_text() == ''

	t.click_widget(ta)
	t_type(mut t, 'раз два')
	assert ta.undo() && ta.get_text() == 'раз '
	assert ta.undo() && ta.get_text() == ''

	t.click_widget(ce)
	t_type(mut t, 'fn main')
	assert ce.get_text() == 'fn main'
	assert ce.undo() && ce.get_text() == 'fn '
	assert ce.undo() && ce.get_text() == ''
}

// ─── Ctrl+Z окна и стек команд (Window.set_undo_stack) ───

struct UndoCounter {
mut:
	value int
}

fn test_window_undo_stack_shortcuts() {
	mut t := new_test_ui(width: 300, height: 160)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut ti := text_input('')
	root.add(ti)
	t.add(root)
	mut doc := &UndoCounter{}
	mut stack := undo_stack(0)
	t.win.set_undo_stack(stack)
	stack.push(UndoCommand{
		text: 'плюс'
		redo: fn [mut doc] () {
			doc.value++
		}
		undo: fn [mut doc] () {
			doc.value--
		}
	})
	assert doc.value == 1
	// фокуса нет - Ctrl+Z отменяет команду стека, Ctrl+Y повторяет
	t.key(int(`z`), sdl_kmod_ctrl)
	assert doc.value == 0
	t.key(int(`y`), sdl_kmod_ctrl)
	assert doc.value == 1
	t.key(int(`z`), sdl_kmod_ctrl)
	t.key(int(`z`), sdl_kmod_ctrl | sdl_kmod_shift)
	assert doc.value == 1
	// поле ввода в фокусе - Ctrl+Z его, стек не трогается
	t.click_widget(ti)
	t_type(mut t, 'абв')
	t.key(int(`z`), sdl_kmod_ctrl)
	assert ti.get_text() == '' && doc.value == 1
	// связь снята - Ctrl+Z окна ничего не делает
	t.win.set_undo_stack(unsafe { nil })
	t.click(150, 150)
	t.key(int(`z`), sdl_kmod_ctrl)
	assert doc.value == 1
}
