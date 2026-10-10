module vgui

// Тесты областей модальности (аудит 3.D): модальный диалог блокирует только
// своё дерево владения. Окна здесь — просто идентификаторы, SDL не нужен.

// Окно 1 и окно 2 — независимые верхнеуровневые окна; диалог 10 модален для
// окна 1 и не должен трогать окно 2.
fn test_modal_blocks_only_its_own_window() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 1) == 0
	assert modal_blocker_index(entries, 2) == -1
	// Событие самого диалога тоже уходит в него.
	assert modal_blocker_index(entries, 10) == 0
}

// Диалог без родителя модален для всего приложения — поведение до 3.D.
fn test_parentless_modal_blocks_everything() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 0
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 1) == 0
	assert modal_blocker_index(entries, 2) == 0
}

// Немодальный диалог не блокирует ничего.
fn test_modeless_dialog_blocks_nothing() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     false
		},
	]
	assert modal_blocker_index(entries, 1) == -1
}

// Диалог 11, открытый поверх модального диалога 10, сам этим диалогом не
// блокируется, а окно-родитель 1 по-прежнему заблокировано.
fn test_child_of_modal_is_not_blocked() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     true
		},
		ModalScopeEntry{
			wid:       11
			parent_id: 10
			modal:     false
		},
	]
	assert modal_blocker_index(entries, 11) == -1
	assert modal_blocker_index(entries, 1) == 0
}

// Вложенный модальный диалог 11 (поверх модального 10) перехватывает события
// всего дерева: и окна 1, и диалога 10.
fn test_nested_modal_wins() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     true
		},
		ModalScopeEntry{
			wid:       11
			parent_id: 10
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 1) == 1
	assert modal_blocker_index(entries, 10) == 1
	assert modal_blocker_index(entries, 11) == 1
}

// Два окна, у каждого свой модальный диалог: каждое блокируется своим.
fn test_two_windows_two_modals() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     true
		},
		ModalScopeEntry{
			wid:       20
			parent_id: 2
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 1) == 0
	assert modal_blocker_index(entries, 2) == 1
	assert modal_blocker_index(entries, 3) == -1
}

// Диалог-сосед того же окна тоже блокируется: модальность распространяется на
// всё дерево владения, а не только на прямого родителя.
fn test_sibling_dialog_is_blocked() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     false
		},
		ModalScopeEntry{
			wid:       11
			parent_id: 1
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 10) == 1
}

// Модальный диалог, открытый над диалогом второго окна, не трогает первое.
fn test_deep_chain_stays_in_its_tree() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     false
		},
		ModalScopeEntry{
			wid:       20
			parent_id: 2
			modal:     false
		},
		ModalScopeEntry{
			wid:       21
			parent_id: 20
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 2) == 2
	assert modal_blocker_index(entries, 20) == 2
	assert modal_blocker_index(entries, 1) == -1
	assert modal_blocker_index(entries, 10) == -1
}

// Кольцо в цепочке родителей (в норме недостижимо) не должно вешать обход.
fn test_cycle_does_not_hang() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 11
			modal:     true
		},
		ModalScopeEntry{
			wid:       11
			parent_id: 10
			modal:     false
		},
	]
	assert modal_blocker_index(entries, 1) == -1
	assert owner_root(entries, 10) != 0
}

// Закрытый модальный диалог (modal: false в снимке) не мешает событиям, но
// остаётся частью цепочки владения для своих детей.
fn test_closed_modal_is_not_a_blocker() {
	entries := [
		ModalScopeEntry{
			wid:       10
			parent_id: 1
			modal:     false
		},
		ModalScopeEntry{
			wid:       11
			parent_id: 10
			modal:     true
		},
	]
	assert modal_blocker_index(entries, 1) == 1
	assert modal_blocker_index(entries, 2) == -1
	assert owner_root(entries, 11) == 1
}
