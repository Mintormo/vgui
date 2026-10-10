module vgui

// MenuBar.set_items: пункты меню заменяются, индекс вне списка - игнор
fn test_menu_bar_set_items() {
	mut mb := menu_bar()
	mb.add_menu('A', [menu_action('a1')])
	mb.add_menu('B', []&MenuItem{})
	mb.set_items(1, [menu_action('b1'), menu_separator(), menu_action('b2')])
	assert mb.entries[1].items.len == 3
	assert mb.entries[1].items[2].text == 'b2'
	mb.set_items(5, [menu_action('x')])
	assert mb.entries.len == 2 && mb.entries[0].items.len == 1
}
