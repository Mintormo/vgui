module vgui

import os

// Тесты DockArea (dock_area.v): построение дерева из кода, сохранение/загрузка раскладки и жесты
// мыши настоящим путём событий (testkit.v): вкладки, крестик, перенос панели, полоса разбиения.

// rect_center - середина прямоугольника (куда «кликнуть»).
fn rect_center(r Rect) (f32, f32) {
	return r.x + r.w * 0.5, r.y + r.h * 0.5
}

// DockCounter - счётчик вызовов колбэка: замыкание V захватывает копию переменной, поэтому
// считает объект в куче.
@[heap]
struct DockCounter {
mut:
	n int
}

// new_dock_ui - окно 400x300 с областью на весь экран и панелями a, b (b справа от a).
fn new_dock_ui() !(&TestUi, &DockArea, &DockPanel, &DockPanel) {
	mut t := new_test_ui(width: 400, height: 300)!
	mut da := dock_area()
	a := dock_panel('a', 'Alpha', label('A'))
	b := dock_panel('b', 'Beta', label('B'))
	da.add_panel(a)
	da.dock(b, .right, target: a)
	t.add(da)
	return t, da, a, b
}

fn test_dock_build_and_save() {
	mut da := dock_area()
	a := dock_panel('a', 'Alpha', label('A'))
	b := dock_panel('b', 'Beta', label('B'))
	c := dock_panel('c', 'Gamma', label('C'))
	da.add_panel(a)
	da.dock(b, .right, target: a, size: 0.25)
	da.dock(c, .center, target: a)
	assert da.save_layout() == 'h0.750([a *c],[*b])'
	// Сторона «слева» от всей области - новое разбиение над корнем
	d := dock_panel('d', 'Delta', label('D'))
	da.dock(d, .left, size: 0.2)
	assert da.save_layout() == 'h0.200([*d],h0.750([a *c],[*b]))'
}

fn test_dock_load_layout_roundtrip_and_unknown_ids() {
	mut da := dock_area()
	for id in ['a', 'b', 'c'] {
		da.add_panel(dock_panel(id, id, label(id)))
	}
	da.load_layout('v0.600([*a b],[*c])')!
	assert da.save_layout() == 'v0.600([*a b],[*c])'
	// Неизвестный id пропускается, пустая группа схлопывается, неупомянутая панель закрыта
	da.load_layout('h0.500([*a],[zzz])')!
	assert da.save_layout() == '[*a]'
	b := da.panel_by_id('b') or { panic('b') }
	assert !da.is_open(b)
	// Ошибка разбора не меняет раскладку
	if _ := da.load_layout('h0.5([a]') {
		assert false
	}
	assert da.save_layout() == '[*a]'
}

fn test_dock_click_tab_activates() {
	mut t, mut da, a, _ := new_dock_ui()!
	c := dock_panel('c', 'Gamma', label('C'))
	da.dock(c, .center, target: a)
	t.frame()
	assert da.is_active(c)
	g := da.group_of(a) or { panic('a') }
	x, y := rect_center(g.tab_rects[0])
	t.click(x, y)
	assert da.is_active(a)
	assert !da.is_active(c)
}

fn test_dock_close_button_and_show_restores() {
	mut t, mut da, a, b := new_dock_ui()!
	mut changes := &DockCounter{}
	da.on_layout_change = fn [mut changes] () {
		changes.n++
	}
	g := da.group_of(b) or { panic('b') }
	x, y := rect_center(g.close_rects[0])
	t.click(x, y)
	assert !da.is_open(b)
	assert da.save_layout() == '[*a]'
	assert changes.n == 1
	// Вернуть на прежнее место - справа от a
	da.show_panel(b)
	assert da.save_layout() == 'h0.500([*a],[*b])'
}

fn test_dock_close_can_be_vetoed() {
	mut t, mut da, _, b := new_dock_ui()!
	da.on_panel_close = fn (p &DockPanel) bool {
		return p.id != 'b'
	}
	g := da.group_of(b) or { panic('b') }
	x, y := rect_center(g.close_rects[0])
	t.click(x, y)
	assert da.is_open(b)
}

fn test_dock_drag_tab_splits_group() {
	mut t, mut da, a, b := new_dock_ui()!
	// b тащится к нижней части содержимого группы a (выше зоны края всей области) - встанет под ней
	gb := da.group_of(b) or { panic('b') }
	ga := da.group_of(a) or { panic('a') }
	x0, y0 := rect_center(gb.tab_rects[0])
	cx := ga.content.x + ga.content.w * 0.5
	cy := ga.content.y + ga.content.h * 0.8
	t.drag(x0, y0, cx, cy)
	assert da.save_layout() == 'v0.500([*a],[*b])'
}

fn test_dock_drag_tab_into_group_center_and_strip() {
	mut t, mut da, a, b := new_dock_ui()!
	gb := da.group_of(b) or { panic('b') }
	ga := da.group_of(a) or { panic('a') }
	x0, y0 := rect_center(gb.tab_rects[0])
	cx, cy := rect_center(ga.content)
	t.drag(x0, y0, cx, cy)
	assert da.save_layout() == '[a *b]'
	// Внутри группы: b - на место перед a, бросив на левую половину вкладки a
	t.frame()
	g := da.group_of(a) or { panic('a') }
	bx, by := rect_center(g.tab_rects[1])
	t.drag(bx, by, g.tab_rects[0].x + 4, by)
	assert da.save_layout() == '[*b a]'
}

fn test_dock_drag_to_area_edge() {
	mut t, mut da, a, b := new_dock_ui()!
	c := dock_panel('c', 'Gamma', label('C'))
	da.dock(c, .center, target: a)
	t.frame()
	g := da.group_of(c) or { panic('c') }
	x0, y0 := rect_center(g.tab_rects[1])
	// к нижнему краю всей области
	t.drag(x0, y0, 200, 296)
	assert da.save_layout() == 'v0.700(h0.500([*a],[*b]),[*c])'
}

fn test_dock_drop_on_own_single_group_is_noop() {
	mut t, mut da, _, b := new_dock_ui()!
	gb := da.group_of(b) or { panic('b') }
	x0, y0 := rect_center(gb.tab_rects[0])
	// правая часть своей группы, но не у края всей области
	cx := gb.content.x + gb.content.w * 0.75
	cy := gb.content.y + gb.content.h * 0.5
	t.drag(x0, y0, cx, cy)
	assert da.save_layout() == 'h0.500([*a],[*b])'
}

fn test_dock_bar_drag_changes_ratio() {
	mut t, mut da, _, _ := new_dock_ui()!
	bar := da.root.bar
	x, y := rect_center(bar)
	t.drag(x, y, 100, y)
	assert da.root.ratio < 0.3
	// Не уже min_pane
	t.frame()
	x2, _ := rect_center(da.root.bar)
	t.drag(x2, y, 0, y)
	assert da.root.first.rect.w >= da.min_pane - 0.5
}

fn test_dock_content_receives_clicks() {
	mut t := new_test_ui(width: 400, height: 300)!
	mut da := dock_area()
	mut clicks := &DockCounter{}
	mut btn := button('Go')
	btn.on_click = fn [mut clicks] () {
		clicks.n++
	}
	p := dock_panel('p', 'Panel', btn)
	da.add_panel(p)
	t.add(da)
	t.click_widget(btn)
	assert clicks.n == 1
}

// Вид области: три группы, вкладки с крестиком и иконкой; и предпросмотр переноса (панель
// тащится к нижней части группы a - подсвечена нижняя половина, у курсора - «призрак» вкладки).
fn test_dock_snapshot() {
	mut t := new_test_ui(width: 420, height: 280)!
	mut da := dock_area()
	mut files := dock_panel('files', 'Files', label('file list'))
	files.icon = item_icon('folder')
	editor := dock_panel('editor', 'main.v', label('fn main() {}'))
	mut log := dock_panel('log', 'Output', label('build ok'))
	log.closable = false
	da.add_panel(editor)
	da.dock(files, .left, size: 0.3)
	da.dock(log, .bottom, target: editor, size: 0.35)
	da.dock(dock_panel('notes', 'Notes', label('todo')), .center, target: editor)
	t.add(da)
	t.match_snapshot('testdata/snapshots/dock_area.png', SnapshotOpts{})!

	gl := da.group_of(log) or { panic('log') }
	ge := da.group_of(editor) or { panic('editor') }
	x0, y0 := rect_center(gl.tab_rects[0])
	t.press(x0, y0)
	t.move(x0 + 20, y0 - 20)
	t.move(ge.content.x + ge.content.w * 0.5, ge.content.y + ge.content.h * 0.8)
	t.frame()
	t.match_snapshot('testdata/snapshots/dock_area_drag.png', SnapshotOpts{})!
	t.release(ge.content.x + ge.content.w * 0.5, ge.content.y + ge.content.h * 0.8)
}

fn test_dock_layout_file_roundtrip() {
	mut da := dock_area()
	a := dock_panel('a', 'Alpha', label('A'))
	b := dock_panel('b', 'Beta', label('B'))
	da.add_panel(a)
	da.dock(b, .bottom, target: a, size: 0.4)
	dir := os.join_path(os.temp_dir(), 'vgui_dock_test_${os.getpid()}')
	path := os.join_path(dir, 'sub', 'layout.txt')
	da.save_layout_file(path)!
	defer {
		os.rmdir_all(dir) or {}
	}
	// Другая раскладка в памяти, затем - из файла
	da.load_layout('[*a b]')!
	da.load_layout_file(path)!
	assert da.save_layout() == 'v0.600([*a],[*b])'
	// Нет файла - ошибка, раскладка прежняя
	if _ := da.load_layout_file(os.join_path(dir, 'missing.txt')) {
		assert false
	}
	assert da.save_layout() == 'v0.600([*a],[*b])'
}
