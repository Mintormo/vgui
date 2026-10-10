module vgui

// ═══════════════════════════════════════════════════════════
//  Undo/redo — два уровня (PROJECT.md, «Undo/redo»):
//
//  UndoHistory[T] — история снимков состояния для встроенной отмены
//    виджетов (TextInput, TextArea, CodeEditor, редакторы ячеек
//    TableView/TreeView). Виджет сам решает, что такое снимок.
//
//  UndoStack — стек команд для приложения (аналог QUndoStack):
//    у каждой команды пара действий undo/redo, текст для меню,
//    слияние подряд идущих команд (merge_id), группы, «чистое»
//    состояние для пометки «документ изменён».
// ═══════════════════════════════════════════════════════════

// ───────────── UndoHistory[T] ──────────────────────────

// UndoHistory — две стопки снимков. `limit` > 0 ограничивает глубину
// отмены (самые старые снимки выбрасываются); 0 — без ограничения.
struct UndoHistory[T] {
	limit int
mut:
	undo_stack []T
	redo_stack []T
}

// save кладёт снимок состояния ДО правки. Новая правка обрывает ветку
// повтора.
fn (mut h UndoHistory[T]) save(snap T) {
	if h.limit > 0 && h.undo_stack.len >= h.limit {
		h.undo_stack.delete(0)
	}
	h.undo_stack << snap
	h.redo_stack.clear()
}

// undo принимает текущее состояние (оно уходит в повтор) и возвращает
// снимок, который нужно восстановить; none — отменять нечего.
fn (mut h UndoHistory[T]) undo(cur T) ?T {
	if h.undo_stack.len == 0 {
		return none
	}
	h.redo_stack << cur
	return h.undo_stack.pop()
}

// redo — зеркально undo.
fn (mut h UndoHistory[T]) redo(cur T) ?T {
	if h.redo_stack.len == 0 {
		return none
	}
	h.undo_stack << cur
	return h.redo_stack.pop()
}

fn (h &UndoHistory[T]) can_undo() bool {
	return h.undo_stack.len > 0
}

fn (h &UndoHistory[T]) can_redo() bool {
	return h.redo_stack.len > 0
}

fn (mut h UndoHistory[T]) clear() {
	h.undo_stack.clear()
	h.redo_stack.clear()
}

// RuneSnap — снимок однострочного редактора: TextInput и редакторы
// ячеек TableView/TreeView.
struct RuneSnap {
	buf []rune
	cur int
}

// ───────────── UndoStack ───────────────────────────────

// UndoCommand — одно отменяемое действие приложения.
//
// - `undo`/`redo` — действия; `redo` выполняет действие (повторно),
//   `undo` его откатывает. Любое из них может быть nil.
// - `text` — подпись для меню («Отменить: <text>»).
// - `merge_id` != 0 — подряд идущие команды с одинаковым id сливаются в
//   один шаг отмены (перетаскивание ползунка, ввод по буквам). Слитый шаг
//   откатывает все вошедшие команды в обратном порядке, поэтому слияние
//   корректно для любых команд, без особого «mergeWith».
// - `release` — вызывается, когда команда выбрасывается из стека навсегда
//   (обрезка по limit, обрыв ветки повтора, clear): освободить ресурсы.
pub struct UndoCommand {
pub mut:
	text     string
	merge_id int
	undo     fn () = unsafe { nil }
	redo     fn () = unsafe { nil }
	release  fn () = unsafe { nil }
mut:
	children []UndoCommand
	merged   bool // контейнер слитых команд: следующая с тем же id — в children
}

// redo: собственное действие, затем дети по порядку.
fn (c &UndoCommand) run_redo() {
	if c.redo != unsafe { nil } {
		c.redo()
	}
	for i in 0 .. c.children.len {
		c.children[i].run_redo()
	}
}

// undo: дети в обратном порядке, затем собственное действие.
fn (c &UndoCommand) run_undo() {
	for i := c.children.len - 1; i >= 0; i-- {
		c.children[i].run_undo()
	}
	if c.undo != unsafe { nil } {
		c.undo()
	}
}

fn (c &UndoCommand) run_release() {
	for i in 0 .. c.children.len {
		c.children[i].run_release()
	}
	if c.release != unsafe { nil } {
		c.release()
	}
}

// UndoStack — стек отменяемых команд приложения.
//
// Команды [0, pos) применены, [pos, len) — ветка повтора. Новая команда
// обрывает ветку повтора. Пока выполняется undo/redo команды, стек занят:
// push/record/undo/redo из её действий отклоняются (возвращают false).
@[heap]
pub struct UndoStack {
pub mut:
	// on_change — после любого изменения состояния стека: обновить пункты
	// меню «Отменить/Повторить», звёздочку «изменено» в заголовке.
	on_change fn () = unsafe { nil }
mut:
	max_steps   int // 0 — без ограничения
	cmds        []UndoCommand
	pos         int
	clean_index int           // pos «чистого» состояния; -1 — недостижимо
	groups      []UndoCommand // открытые группы, вложенные
	busy        bool
}

// undo_stack создаёт стек. `limit` > 0 — максимум шагов отмены.
pub fn undo_stack(limit int) &UndoStack {
	return &UndoStack{
		max_steps: if limit > 0 { limit } else { 0 }
	}
}

// push выполняет `cmd.redo` и кладёт команду в стек.
pub fn (mut s UndoStack) push(cmd UndoCommand) bool {
	if s.busy {
		return false
	}
	s.busy = true
	cmd.run_redo()
	s.busy = false
	s.add(cmd)
	return true
}

// record кладёт в стек уже выполненное действие (redo не вызывается).
pub fn (mut s UndoStack) record(cmd UndoCommand) bool {
	if s.busy {
		return false
	}
	s.add(cmd)
	return true
}

fn (mut s UndoStack) add(cmd UndoCommand) {
	if s.groups.len > 0 {
		s.groups[s.groups.len - 1].children << cmd
		return
	}
	s.drop_redo_branch()
	if cmd.merge_id != 0 && s.pos > 0 && s.pos != s.clean_index
		&& s.cmds[s.pos - 1].merge_id == cmd.merge_id {
		if s.cmds[s.pos - 1].merged {
			s.cmds[s.pos - 1].children << cmd
			s.cmds[s.pos - 1].text = cmd.text
		} else {
			old := s.cmds[s.pos - 1]
			s.cmds[s.pos - 1] = UndoCommand{
				text:     cmd.text
				merge_id: cmd.merge_id
				children: [old, cmd]
				merged:   true
			}
		}
		s.changed()
		return
	}
	s.cmds << cmd
	s.pos++
	s.enforce_limit()
	s.changed()
}

fn (mut s UndoStack) drop_redo_branch() {
	if s.pos >= s.cmds.len {
		return
	}
	for i in s.pos .. s.cmds.len {
		s.cmds[i].run_release()
	}
	s.cmds.trim(s.pos)
	if s.clean_index > s.pos {
		s.clean_index = -1
	}
}

// enforce_limit выбрасывает лишнее: сначала самые старые применённые
// команды, затем (если ветка повтора одна длиннее limit) — её конец.
fn (mut s UndoStack) enforce_limit() {
	if s.max_steps <= 0 {
		return
	}
	for s.cmds.len > s.max_steps && s.pos > 0 {
		s.cmds[0].run_release()
		s.cmds.delete(0)
		s.pos--
		if s.clean_index >= 0 {
			s.clean_index--
		}
	}
	for s.cmds.len > s.max_steps {
		s.cmds.last().run_release()
		s.cmds.delete_last()
		if s.clean_index > s.cmds.len {
			s.clean_index = -1
		}
	}
}

fn (mut s UndoStack) changed() {
	if s.on_change != unsafe { nil } {
		s.on_change()
	}
}

pub fn (mut s UndoStack) undo() bool {
	if !s.can_undo() {
		return false
	}
	s.busy = true
	s.cmds[s.pos - 1].run_undo()
	s.busy = false
	s.pos--
	s.changed()
	return true
}

pub fn (mut s UndoStack) redo() bool {
	if !s.can_redo() {
		return false
	}
	s.busy = true
	s.cmds[s.pos].run_redo()
	s.busy = false
	s.pos++
	s.changed()
	return true
}

// can_undo/can_redo — false и во время открытой группы, и внутри
// выполняющейся команды.
pub fn (s &UndoStack) can_undo() bool {
	return s.pos > 0 && s.groups.len == 0 && !s.busy
}

pub fn (s &UndoStack) can_redo() bool {
	return s.pos < s.cmds.len && s.groups.len == 0 && !s.busy
}

// undo_text — подпись команды, которую отменит undo(); '' — нечего.
pub fn (s &UndoStack) undo_text() string {
	return if s.pos > 0 { s.cmds[s.pos - 1].text } else { '' }
}

pub fn (s &UndoStack) redo_text() string {
	return if s.pos < s.cmds.len { s.cmds[s.pos].text } else { '' }
}

// count — шагов в стеке (применённых и ветки повтора).
pub fn (s &UndoStack) count() int {
	return s.cmds.len
}

// index — сколько шагов применено.
pub fn (s &UndoStack) index() int {
	return s.pos
}

// set_clean помечает текущее состояние как сохранённое.
pub fn (mut s UndoStack) set_clean() {
	s.clean_index = s.pos
	s.changed()
}

// is_clean — состояние совпадает с помеченным set_clean (или со стартом).
pub fn (s &UndoStack) is_clean() bool {
	return s.pos == s.clean_index
}

pub fn (s &UndoStack) limit() int {
	return s.max_steps
}

// set_limit меняет глубину отмены (0 — без ограничения), лишнее
// выбрасывается сразу.
pub fn (mut s UndoStack) set_limit(n int) {
	s.max_steps = if n > 0 { n } else { 0 }
	before := s.cmds.len
	s.enforce_limit()
	if s.cmds.len != before {
		s.changed()
	}
}

// begin_group открывает группу: команды до парного end_group станут одним
// шагом отмены с подписью `text`. Группы вкладываются.
pub fn (mut s UndoStack) begin_group(text string) bool {
	if s.busy {
		return false
	}
	s.groups << UndoCommand{
		text: text
	}
	return true
}

// end_group закрывает группу. Пустая группа шага не добавляет.
pub fn (mut s UndoStack) end_group() bool {
	if s.busy || s.groups.len == 0 {
		return false
	}
	g := s.groups.pop()
	if g.children.len == 0 {
		return true
	}
	if s.groups.len > 0 {
		s.groups[s.groups.len - 1].children << g
	} else {
		s.add(g)
	}
	return true
}

pub fn (s &UndoStack) in_group() bool {
	return s.groups.len > 0
}

// clear выбрасывает все команды (и незакрытые группы); пустой стек — чистый.
pub fn (mut s UndoStack) clear() bool {
	if s.busy {
		return false
	}
	s.release_all()
	s.changed()
	return true
}

fn (mut s UndoStack) release_all() {
	for i in 0 .. s.cmds.len {
		s.cmds[i].run_release()
	}
	for i in 0 .. s.groups.len {
		s.groups[i].run_release()
	}
	s.cmds.clear()
	s.groups.clear()
	s.pos = 0
	s.clean_index = 0
}

// destroy освобождает команды без on_change (C-ABI: vgui_undo_stack_destroy).
pub fn (mut s UndoStack) destroy() {
	s.on_change = unsafe { nil }
	s.release_all()
}
