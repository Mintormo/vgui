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
