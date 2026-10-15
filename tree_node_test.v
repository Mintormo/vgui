module vgui

// TreeNode: целостность дерева (аудит 2026-10, 1.5). Добавление предка в
// потомка давало цикл и бесконечную рекурсию в flatten; узел, добавленный
// второму родителю, жил в дереве дважды; снятый узел помнил старого родителя.
//
// Запуск (из корня vgui): v test tree_node_test.v

fn test_cycle_is_rejected() {
	mut root := tree_node('root')
	mut child := root.add_child('child')
	mut grandchild := child.add_child('grandchild')
	assert !grandchild.add(root)
	assert !child.insert_at(0, child)
	assert !grandchild.add(grandchild)
	assert grandchild.children.len == 0
	assert child.children.len == 1
	assert root.parent == unsafe { nil }
}

fn test_node_moves_from_old_parent() {
	mut a := tree_node('a')
	mut b := tree_node('b')
	mut x := tree_node('x')
	assert a.add(x)
	assert b.insert_at(5, x)
	assert a.children.len == 0
	assert b.children.len == 1
	assert x.parent == b
}

fn test_remove_at_clears_parent() {
	mut root := tree_node('root')
	mut c := root.add_child('c')
	root.remove_at(0)
	assert c.parent == unsafe { nil }
	// снятый узел снова можно добавить куда угодно, в том числе обратно
	assert root.add(c)
	assert c.parent == root
}
