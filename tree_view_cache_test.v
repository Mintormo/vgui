module vgui

// TreeView: кэш плоского списка по отпечатку дерева (аудит 2026-10, 3.3). Кэш обязан
// замечать любые изменения, которые делаются через узлы в обход TreeView.
//
// Запуск (из корня vgui): v test tree_view_cache_test.v

fn test_flat_cache_tracks_tree_changes() {
	mut tv := tree_view()
	mut root := tree_node('root')
	mut a := root.add_child('a')
	a.add_child('a1')
	tv.add_root(root)
	assert tv.build_flat().len == 3
	assert tv.build_flat().len == 3 // из кэша

	a.expanded = false
	assert tv.build_flat().len == 2, 'сворачивание ветки'
	root.add_child('b')
	assert tv.build_flat().len == 3, 'новый узел'
	a.expanded = true
	root.remove_at(0)
	assert tv.build_flat().len == 2, 'удаление узла'
	mut b := root.children[0]
	b.text = 'переименован'
	assert tv.build_flat()[1].node.text == 'переименован'
}
