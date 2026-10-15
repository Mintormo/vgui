module vgui

// CodeEditor: Tab/Shift+Tab и раскрытие табов (аудит 2026-10, 1.2 и 2.4).
// Чистая логика редактора, окна и SDL не нужны.
//
// Запуск (из корня vgui): v test code_editor_keys_test.v

// Отступ брался срезом готовой строки пробелов: tab_size больше её длины
// (4 у key_tab, 16 у ce_expand_tabs) ронял программу паникой.
fn test_large_tab_size_does_not_panic() {
	mut e := code_editor()
	e.tab_size = 20
	e.set_text('x')
	e.key_tab()
	assert e.get_line(0) == ' '.repeat(20) + 'x'
	assert ce_expand_tabs('\ta', 20) == ' '.repeat(20) + 'a'
	assert ce_expand_tabs('\ta', -3) == 'a'
}

// Shift+Tab на строке без отступа ничего не меняет и не трогает историю:
// раньше он сохранял пустой шаг undo и обрывал ветку redo.
fn test_shift_tab_without_indent_keeps_redo() {
	mut e := code_editor()
	e.set_text('a')
	e.insert_text('b')
	assert e.undo()
	assert e.can_redo()
	e.key_shift_tab()
	assert e.can_redo()
	assert e.get_line(0) == 'a'
}

// Shift+Tab убирает не больше tab_size ведущих пробелов и отменяется одним шагом.
fn test_shift_tab_removes_indent_with_undo() {
	mut e := code_editor()
	e.tab_size = 2
	e.set_text('     x')
	e.key_shift_tab()
	assert e.get_line(0) == '   x'
	assert e.undo()
	assert e.get_line(0) == '     x'
}
