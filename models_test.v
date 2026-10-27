module vgui

// Реактивные данные (models.v, model_views.v): Observable, RowsModel в ListBox и
// TableView, своя модель через ModelBase, TreeModel в TreeView с сохранением
// раскрытия и выбора, и что изменение данных само просит перерисовку окна.
//
// Запуск (из корня vgui): SDL_VIDEODRIVER=dummy v test models_test.v

struct ObsLog {
mut:
	seen []string
}

fn test_observable_bind_set_unsubscribe() {
	mut title := observable('a')
	mut log := &ObsLog{}
	id := title.bind(fn [mut log] (s string) {
		log.seen << s
	})
	assert log.seen == ['a'], 'bind сразу отдаёт текущее значение'
	title.set('b')
	title.set('b') // то же значение - без уведомления
	assert log.seen == ['a', 'b']
	title.unsubscribe(id)
	title.set('c')
	assert log.seen == ['a', 'b']
	assert title.get() == 'c'

	mut n := observable(1)
	mut sum := &ObsLog{}
	n.subscribe(fn [mut sum] (v int) {
		sum.seen << v.str()
	})
	n.set(5)
	assert sum.seen == ['5']
}

fn test_rows_model_edits() {
	mut m := rows_model([['a', '1'], ['b', '2']])
	v0 := m.version()
	m.append(['c', '3'])
	m.insert(0, ['z'])
	m.set_cell(0, 2, 'x')
	assert m.row(0) == ['z', '', 'x']
	m.remove(1)
	assert m.row_count() == 3
	assert m.cell_text(0, 0) == 'z' && m.cell_text(2, 1) == '3'
	assert m.cell_text(9, 0) == '' && m.cell_text(0, 9) == ''
	assert m.version() == v0 + 4
	m.clear()
	assert m.row_count() == 0
}

// Изменение модели перерисовывает окно само, без invalidate: таблица
// показывает новую строку на ближайшем кадре.
fn test_table_view_follows_model() {
	mut t := new_test_ui(width: 240, height: 160)!
	defer {
		t.close()
	}
	mut m := rows_model([['a', '1'], ['b', '2']])
	mut tbl := table_view()
	tbl.add_column('Имя', 100)
	tbl.add_column('N', 60)
	tbl.set_model(m)
	t.add(tbl)
	assert tbl.row_count() == 2
	assert tbl.cell_at(1, 0).text == 'b'

	take_data_changed()
	m.append(['c', '3'])
	assert t.app.needs_animation_now(), 'изменение модели просит кадр'
	t.frame()
	assert tbl.row_count() == 3
	assert tbl.cell_at(2, 1).text == '3'
	assert !t.app.needs_animation_now()

	// Выбор за новым концом переезжает (set_virtual_count)
	tbl.sel_row = 2
	m.remove(2)
	t.frame()
	assert tbl.row_count() == 2
	assert tbl.sel_row == 1

	// clear_rows снимает модель - вид снова обычный
	tbl.clear_rows()
	m.append(['d'])
	t.frame()
	assert tbl.row_count() == 0
}

fn test_list_box_follows_model() {
	mut t := new_test_ui(width: 200, height: 160)!
	defer {
		t.close()
	}
	mut m := rows_model([['один'], ['два']])
	mut lb := list_box()
	lb.set_model(m)
	t.add(lb)
	assert lb.row_total() == 2
	m.append(['три'])
	t.frame()
	assert lb.row_total() == 3
	assert lb.cell_text(2, 0) == 'три'
}

// Своя модель: ModelBase даёт version()/changed().
struct DirModel {
	ModelBase
mut:
	kids map[string][]string
}

fn (m &DirModel) child_ids(parent string) []string {
	return m.kids[parent] or { []string{} }
}

fn (m &DirModel) item_text(id string) string {
	return id.all_after_last('/')
}

fn test_tree_view_follows_model() {
	mut t := new_test_ui(width: 240, height: 200)!
	defer {
		t.close()
	}
	mut m := &DirModel{
		kids: {
			'':     ['/a', '/b']
			'/a':   ['/a/x']
			'/a/x': ['/a/x/deep']
		}
	}
	mut tv := tree_view()
	tv.set_tree_model(m)
	t.add(tv)
	assert tv.roots.len == 2
	assert tv.roots[0].text == 'a' && tv.roots[0].tag == '/a'
	assert !tv.roots[0].expanded, 'новые узлы модели свёрнуты'

	// Раскрытие и выбор переживают перестройку по новой версии.
	tv.roots[0].expanded = true
	tv.selected = tv.roots[0].children[0]
	m.kids['/a'] = ['/a/x', '/a/y']
	m.changed()
	t.frame()
	assert tv.roots[0].children.len == 2
	assert tv.roots[0].expanded
	assert unsafe { tv.selected != nil } && tv.selected.tag == '/a/x'
	assert tv.roots[0].children[0].children[0].tag == '/a/x/deep'

	// Выбранный узел исчез из модели - выбора нет.
	m.kids['/a'] = ['/a/y']
	m.changed()
	t.frame()
	assert unsafe { tv.selected == nil }
}

// Цикл в модели (узел среди своих потомков) не уводит в бесконечную рекурсию.
fn test_tree_model_cycle_is_bounded() {
	mut m := &DirModel{
		kids: {
			'':      ['/loop']
			'/loop': ['/loop']
		}
	}
	mut tv := tree_view()
	tv.set_tree_model(m)
	mut depth := 0
	mut n := tv.roots[0]
	for n.children.len > 0 {
		n = n.children[0]
		depth++
	}
	assert depth == tree_model_max_depth
}

// Инвалидация в сеттерах (widget_changed): публичный set_* просит кадр сам,
// без invalidate; после кадра приложение затихает - сеттеры, которые виджеты
// зовут по ходу отрисовки (ListBox с моделью), новых кадров не заказывают.
fn test_setters_request_redraw() {
	mut t := new_test_ui(width: 240, height: 200)!
	defer {
		t.close()
	}
	mut root := create_vbox_fill()
	mut bar := progress_bar()
	mut lbl := label('a')
	mut lb := list_box()
	lb.set_model(rows_model([['x'], ['y']]))
	root.add(lbl)
	root.add(bar)
	root.add(lb, flex: 1)
	t.add(root)
	t.settle(20)
	assert !t.app.needs_animation_now(), 'после кадра без изменений - тишина'
	bar.set_value(0.5)
	assert t.app.needs_animation_now(), 'сеттер попросил кадр'
	t.frame()
	assert !t.app.needs_animation_now()
	lbl.set_text('длиннее')
	assert t.app.needs_animation_now()
	t.frame()
	assert lbl.bounds.w > 0
	t.frame()
	assert !t.app.needs_animation_now()
}
