module vgui

// Тесты перетаскивания между виджетами (dnd.v): порог, отмена жеста
// источника, общий источник/цель по полю dnd, Esc, ListBox и TreeView
// (перестановка, вынос в другую цель), сбросы из других приложений и
// перенос между окнами. Ввод - настоящим путём (testkit.v).
//
// Запуск: SDL_VIDEODRIVER=dummy v test dnd_test.v

// DndLog - что пришло в колбэки (замыкания захватывают копию - лог по указателю).
@[heap]
struct DndLog {
mut:
	drops    []DropInfo
	ends     []bool // accepted из on_drag_end
	clicks   int
	reorders []string
}

// dnd_press_move - навести и нажать в (x0, y0) и провести в (x1, y1) за 4
// кадра, НЕ отпуская: тест проверяет состояние посреди перетаскивания
// (цель, линию вставки, Esc) и отпускает сам.
fn dnd_press_move(mut t TestUi, x0 f32, y0 f32, x1 f32, y1 f32) {
	t.move(x0, y0)
	t.press(x0, y0)
	for i in 1 .. 5 {
		k := f32(i) / 4
		sim_push_motion(t.win, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, sim_button_mask(.left))
		sim_pump(mut t.app, 0)
	}
}

// Источник - кнопка, цель - метка. Кнопка после перетаскивания не
// нажимается (её жест гасится), цель получает данные, источник - accepted.
fn test_generic_source_and_target() {
	mut t := new_test_ui(width: 300, height: 120)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut src := button('Тяни меня')
	src.on_click = fn [mut log] () {
		log.clicks++
	}
	set_drag_source(mut src, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/item'
			text: 'привет'
		}
	})
	widget_dnd_spec(mut src).on_drag_end = fn [mut log] (d DragData, accepted bool) {
		log.ends << accepted
	}
	mut dst := label('Сюда')
	set_drop_target(mut dst, ['test/*'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut row := create_hbox_fill()
	row.add(src, flex: 1)
	row.add(dst, flex: 1)
	t.add(row)

	x0, y0 := t.center_of(src)
	x1, y1 := t.center_of(dst)
	dnd_press_move(mut t, x0, y0, x1, y1)
	assert dnd_active()
	assert dnd_target() == voidptr(dst)
	t.release(x1, y1)
	assert !dnd_active()
	assert log.drops.len == 1
	assert log.drops[0].data.text == 'привет'
	assert !log.drops[0].external
	assert log.drops[0].from(src)
	assert log.ends == [true]
	assert log.clicks == 0, 'кнопка-источник не должна нажаться'
}

// Сдвиг меньше порога - это клик, а не перетаскивание.
fn test_below_threshold_is_click() {
	mut t := new_test_ui(width: 200, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut b := button('OK')
	b.on_click = fn [mut log] () {
		log.clicks++
	}
	set_drag_source(mut b, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/item'
			text: 'x'
		}
	})
	mut col := create_vbox_fill()
	col.add(b, flex: 1)
	t.add(col)
	x, y := t.center_of(b)
	t.drag(x, y, x + 3, y + 2)
	assert log.clicks == 1
	assert !dnd_active()
}

// Цель с другим kind не подходит: сброса нет, источнику - accepted = false.
// Отключённая цель тоже пропускается.
fn test_target_kind_and_enabled() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut src := label('Источник')
	set_drag_source(mut src, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/a'
			text: 'a'
		}
	})
	widget_dnd_spec(mut src).on_drag_end = fn [mut log] (d DragData, accepted bool) {
		log.ends << accepted
	}
	mut other := label('Другой тип')
	set_drop_target(mut other, ['test/b'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut off := label('Отключена')
	set_drop_target(mut off, ['test/a'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	off.enabled = false
	mut row := create_hbox_fill()
	row.add(src, flex: 1)
	row.add(other, flex: 1)
	row.add(off, flex: 1)
	t.add(row)

	x0, y0 := t.center_of(src)
	x1, y1 := t.center_of(other)
	t.drag(x0, y0, x1, y1)
	x2, y2 := t.center_of(off)
	t.drag(x0, y0, x2, y2)
	assert log.drops.len == 0
	assert log.ends == [false, false]
}

// Esc отменяет перетаскивание: отпускание над целью уже ничего не сбрасывает.
fn test_escape_cancels() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut src := label('Источник')
	set_drag_source(mut src, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/a'
			text: 'a'
		}
	})
	mut dst := label('Цель')
	set_drop_target(mut dst, ['*'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut row := create_hbox_fill()
	row.add(src, flex: 1)
	row.add(dst, flex: 1)
	t.add(row)
	x0, y0 := t.center_of(src)
	x1, y1 := t.center_of(dst)
	dnd_press_move(mut t, x0, y0, x1, y1)
	assert dnd_active()
	t.key(sdl_k_escape, 0)
	assert !dnd_active()
	t.release(x1, y1)
	assert log.drops.len == 0
}

// Источник в родителе: нажатие на дочерней метке тянет ближайшего предка с
// источником, а отключённый предок источником быть не может.
fn test_source_from_ancestor() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut inner := label('Ребёнок')
	mut box := create_hbox_fill()
	box.add(inner, flex: 1)
	set_drag_source(mut box, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/row'
			text: 'ряд'
		}
	})
	mut dst := label('Цель')
	set_drop_target(mut dst, ['test/row'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut row := create_hbox_fill()
	row.add(box, flex: 1)
	row.add(dst, flex: 1)
	t.add(row)
	x0, y0 := t.center_of(inner)
	x1, y1 := t.center_of(dst)
	t.drag(x0, y0, x1, y1)
	assert log.drops.len == 1
	assert log.drops[0].data.text == 'ряд'
}

// Ползунок внутри ряда-источника: нажатие - жест ползунка, ряд не тянется.
fn test_no_drag_over_own_gesture() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut sl := slider_horizontal(0, 100, 50)
	mut box := create_hbox_fill()
	box.add(sl, flex: 1)
	set_drag_source(mut box, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/row'
			text: 'ряд'
		}
	})
	t.add(box)
	x, y := t.center_of(sl)
	dnd_press_move(mut t, x, y, x + 40, y)
	assert !dnd_active()
	t.release(x + 40, y)
	assert sl.value > 50, 'ползунок поехал своим жестом'
}

// list_row_center - центр строки i списка (однострочный режим, без шапки).
fn list_row_center(lb &ListBox, i int) (f32, f32) {
	vp := lb.viewport_rect()
	return vp.x + vp.w * 0.5, vp.y + f32(i) * lb.item_height + lb.item_height * 0.5
}

// Перестановка строк внутри списка: строка 0 на место после строки 2.
// Выбор едет вместе со строкой.
fn test_listbox_reorder() {
	mut t := new_test_ui(width: 200, height: 200)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut lb := list_box()
	lb.add_items(['a', 'b', 'c', 'd'])
	lb.reorder = true
	lb.on_reorder = fn [mut log] (from int, to int) {
		log.reorders << '${from}->${to}'
	}
	mut col := create_vbox_fill()
	col.add(lb, flex: 1)
	t.add(col)

	x0, y0 := list_row_center(lb, 0)
	// нижняя половина строки 2 - вставка перед строкой 3
	_, y2 := list_row_center(lb, 2)
	dnd_press_move(mut t, x0, y0, x0, y2 + 6)
	assert lb.dnd_insert == 3
	t.release(x0, y2 + 6)
	assert lb.items == ['b', 'c', 'a', 'd']
	assert log.reorders == ['0->2']
	assert lb.selected == 2, 'выбранная нажатием строка уехала вместе с собой'
	assert lb.dnd_insert == -1

	// Вверх: строка 3 (d) - перед строкой 0
	_, y3 := list_row_center(lb, 3)
	_, y0b := list_row_center(lb, 0)
	t.drag(x0, y3, x0, y0b - 6)
	assert lb.items == ['d', 'b', 'c', 'a']

	// Отсортированный по колонке список строки не переставляет: после
	// перестановки сортировка вернула бы строку на место
	mut sorted := list_box()
	sorted.add_column_sortable('Имя', 100)
	sorted.add_row_texts(['b'])
	sorted.add_row_texts(['a'])
	sorted.reorder = true
	assert sorted.can_reorder()
	sorted.set_column_sort(0, .asc)
	assert !sorted.can_reorder()
}

// Строку из одного списка - в другой: цель получает текст, номер строки у
// источника и позицию вставки; источник узнаёт об успехе в on_drag_end.
fn test_listbox_between_lists() {
	mut t := new_test_ui(width: 400, height: 200)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut a := list_box()
	a.add_items(['один', 'два', 'три'])
	a.drag_rows = true
	widget_dnd_spec(mut a).on_drag_end = fn [mut log] (d DragData, accepted bool) {
		log.ends << accepted
	}
	mut b := list_box()
	b.add_items(['x', 'y'])
	set_drop_target(mut b, [lb_drag_kind], fn [mut log, mut b] (info DropInfo) {
		log.drops << info
		b.items.insert(info.index, info.data.text)
	})
	mut row := create_hbox_fill()
	row.add(a, flex: 1)
	row.add(b, flex: 1)
	t.add(row)

	x0, y0 := list_row_center(a, 1)
	x1, y1 := list_row_center(b, 0)
	t.drag(x0, y0, x1, y1 + 6) // нижняя половина строки 0 - вставка на 1
	assert log.drops.len == 1
	assert log.drops[0].data.text == 'два'
	assert log.drops[0].data.index == 1
	assert log.drops[0].index == 1
	assert log.drops[0].from(a)
	assert b.items == ['x', 'два', 'y']
	assert log.ends == [true]
	// Без reorder список-источник в себя не принимает
	ax, ay := list_row_center(a, 0)
	_, ay2 := list_row_center(a, 2)
	t.drag(ax, ay, ax, ay2)
	assert a.items == ['один', 'два', 'три']
	assert log.ends == [true, false]
}

// tree_row_y - середина строки i видимого плоского списка дерева.
fn tree_row_y(tv &TreeView, i int) f32 {
	return tv.inner_rect().y + f32(i) * tv.item_height + tv.item_height * 0.5
}

// Перенос узлов внутри дерева: внутрь (середина строки), перед узлом
// (верхняя четверть); в собственное поддерево - нельзя.
fn test_treeview_reorder() {
	mut t := new_test_ui(width: 240, height: 240)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut tv := tree_view()
	mut a := tree_node('A')
	a1 := a.add_child('a1')
	b := tree_node('B')
	c := tree_node('C')
	tv.add_root(a)
	tv.add_root(b)
	tv.add_root(c)
	tv.reorder = true
	tv.on_node_moved = fn [mut log] (n &TreeNode, p &TreeNode, idx int) {
		pname := if unsafe { p == nil } { '-' } else { p.text }
		log.reorders << '${n.text}:${pname}:${idx}'
	}
	mut col := create_vbox_fill()
	col.add(tv, flex: 1)
	t.add(col)
	x := tv.inner_rect().x + 40
	// строки: 0 A, 1 a1, 2 B, 3 C. C - внутрь B (середина строки 2)
	t.drag(x, tree_row_y(tv, 3), x, tree_row_y(tv, 2))
	assert tv.roots.len == 2
	assert b.children.len == 1 && voidptr(b.children[0]) == voidptr(c)
	assert voidptr(c.parent) == voidptr(b)
	assert log.reorders == ['C:B:0']
	// строки: 0 A, 1 a1, 2 B, 3 C. B - перед A (верхняя четверть строки 0)
	top := tv.inner_rect().y + 2
	t.drag(x, tree_row_y(tv, 2), x, top)
	assert voidptr(tv.roots[0]) == voidptr(b)
	assert voidptr(tv.roots[1]) == voidptr(a)
	// строки: 0 B, 1 C, 2 A, 3 a1. A - внутрь своего ребёнка a1: нельзя
	t.drag(x, tree_row_y(tv, 2), x, tree_row_y(tv, 3))
	assert voidptr(a1.parent) == voidptr(a)
	assert a.children.len == 1
	assert tv.roots.len == 2
	assert !tv.dnd_show
}

// Сброс из другого приложения: цель с accepts 'files' получает каждый файл
// отдельно (external), оконный обработчик не зовётся; мимо цели - зовётся.
fn test_external_drop_to_target() {
	mut t := new_test_ui(width: 300, height: 100)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut dst := label('Файлы сюда')
	set_drop_target(mut dst, [dnd_kind_files], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut free := label('Мимо')
	mut row := create_hbox_fill()
	row.add(dst, flex: 1)
	row.add(free, flex: 1)
	t.add(row)
	t.win.set_on_drop_file(fn [mut log] (path string) {
		log.clicks++
	})
	x, y := t.center_of(dst)
	t.drop_files(x, y, ['/tmp/a.txt', '/tmp/b.txt'])
	assert log.drops.len == 2
	assert log.drops[0].external
	assert log.drops[0].data.kind == dnd_kind_files
	assert log.drops[1].data.text == '/tmp/b.txt'
	assert log.clicks == 0
	assert dnd_ext_target() == unsafe { nil }
	// Текст цель с одними 'files' не принимает - уходит окну? Нет: у окна
	// только on_drop_file, текст просто никому не нужен
	t.drop_text(x, y, 'строка')
	assert log.drops.len == 2
	fx, fy := t.center_of(free)
	t.drop_files(fx, fy, ['/tmp/c.txt'])
	assert log.clicks == 1
}

// Внешний сброс в ListBox: позиция вставки приходит в index.
fn test_external_drop_into_listbox() {
	mut t := new_test_ui(width: 200, height: 200)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut lb := list_box()
	lb.add_items(['a', 'b'])
	set_drop_target(mut lb, [dnd_kind_text], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut col := create_vbox_fill()
	col.add(lb, flex: 1)
	t.add(col)
	x, y := list_row_center(lb, 1)
	t.drop_text(x, y + 6, 'новая')
	assert log.drops.len == 1
	assert log.drops[0].index == 2
	assert log.drops[0].data.text == 'новая'
	assert lb.dnd_insert == -1
}

// Перенос между окнами: окна стоят рядом на экране, курсор уходит из окна-
// источника (мышь захвачена - события идут ему, точка за его краем) в другое.
fn test_drag_between_windows() {
	mut t := new_test_ui(width: 200, height: 100)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut src := label('Из первого')
	set_drag_source(mut src, fn (x f32, y f32) DragData {
		return DragData{
			kind: 'test/x'
			text: 'груз'
		}
	})
	mut col := create_vbox_fill()
	col.add(src, flex: 1)
	t.add(col)

	mut w2 := create_window(title: 'second', width: 200, height: 100)!
	w2.ctx.anim_fixed_dt = anim_nominal_dt
	t.app.add_window(w2)
	mut dst := label('Во второе')
	set_drop_target(mut dst, ['test/x'], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut col2 := create_vbox_fill()
	col2.add(dst, flex: 1)
	w2.add_widget(col2)
	C.SDL_SetWindowPosition(t.win.sdl_window, 100, 100)
	C.SDL_SetWindowPosition(w2.sdl_window, 400, 100)
	t.frame()

	// (50, 50) во втором окне = экран (450, 150) = (350, 50) в первом
	t.drag(50, 50, 350, 50)
	assert log.drops.len == 1
	assert log.drops[0].data.text == 'груз'
	assert log.drops[0].x == 50 && log.drops[0].y == 50
	assert !dnd_active()
	// Мимо обоих окон - сброса нет
	t.drag(50, 50, 250, 50)
	assert log.drops.len == 1
}

fn test_kind_matches() {
	assert dnd_kind_matches(['*'], 'a/b')
	assert dnd_kind_matches(['a/b'], 'a/b')
	assert dnd_kind_matches(['a/*'], 'a/b')
	assert !dnd_kind_matches(['a/*'], 'ab/c')
	assert !dnd_kind_matches(['a/b'], 'a/c')
	assert !dnd_kind_matches(['*'], ''), 'пустой kind - не данные'
}

// Поле dnd есть у каждого виджета, кроме служебных слоёв (Tooltip,
// ContextMenu, Notification, NotificationManager) и не-виджетов (MenuItem,
// TreeNode, Property). Проверка - при компиляции: тип без поля не
// приводится к HasDnd. Новый виджет - добавить и сюда.
fn test_every_widget_type_has_dnd_field() {
	with_dnd := [
		HasDnd(&Label{}),
		HasDnd(&Button{}),
		HasDnd(&VBox{}),
		HasDnd(&HBox{}),
		HasDnd(&Panel{}),
		HasDnd(&Spacer{}),
		HasDnd(&TextInput{}),
		HasDnd(&CheckBox{}),
		HasDnd(&Slider{}),
		HasDnd(&ProgressBar{}),
		HasDnd(&Separator{}),
		HasDnd(&ToggleSwitch{}),
		HasDnd(&Spinner{}),
		HasDnd(&RadioButton{}),
		HasDnd(&Spinbox{}),
		HasDnd(&ComboBox{}),
		HasDnd(&ImageView{}),
		HasDnd(&ListBox{}),
		HasDnd(&TabBox{}),
		HasDnd(&Accordion{}),
		HasDnd(&Breadcrumbs{}),
		HasDnd(&ColorPicker{}),
		HasDnd(&DatePicker{}),
		HasDnd(&Splitter{}),
		HasDnd(&DockArea{}),
		HasDnd(&NodeEditor{}),
		HasDnd(&CodeEditor{}),
		HasDnd(&MarkdownView{}),
		HasDnd(&MenuButton{}),
		HasDnd(&MenuBar{}),
		HasDnd(&PlotView{}),
		HasDnd(&PropertyGrid{}),
		HasDnd(&TableView{}),
		HasDnd(&TreeView{}),
		HasDnd(&Stack{}),
		HasDnd(&Centered{}),
		HasDnd(&WindowTitleDrag{}),
		HasDnd(&ScrollBox{}),
		HasDnd(&TextArea{}),
		HasDnd(&Badge{}),
		HasDnd(&Calendar{}),
		HasDnd(&GridLayout{}),
		HasDnd(&DropZone{}),
		HasDnd(&ImageBackground{}),
		HasDnd(&Canvas{}),
		HasDnd(&Icon{}),
		HasDnd(&CurveEditor{}),
		HasDnd(&ShortcutInput{}),
	]
	// все kind_* минус 7 служебных и не-виджетов (см. комментарий выше)
	assert with_dnd.len == css_max_kind - 7
	mut w := Widget(&Tooltip{})
	assert unsafe { widget_dnd_spec(mut w) == nil }, 'у самого Tooltip поля нет'
}

// insert_item / remove_row: выбор сдвигается вместе со строками, удалённая
// выбранная строка выбор теряет.
fn test_listbox_insert_remove() {
	mut lb := list_box()
	lb.add_items(['a', 'b', 'c'])
	lb.set_selected(1)
	lb.insert_item(0, 'z')
	assert lb.items == ['z', 'a', 'b', 'c']
	assert lb.rows.len == 4
	assert lb.selected == 2
	lb.insert_item(99, 'end')
	assert lb.items.last() == 'end'
	assert lb.remove_row(0)
	assert lb.items == ['a', 'b', 'c', 'end']
	assert lb.selected == 1
	assert lb.remove_row(1)
	assert lb.selected == -1
	assert !lb.remove_row(10)
}

// remove_node снимает поддерево; выбор внутри него сбрасывается.
fn test_tree_remove_node() {
	mut tv := tree_view()
	mut a := tree_node('A')
	a1 := a.add_child('a1')
	b := tree_node('B')
	tv.add_root(a)
	tv.add_root(b)
	tv.set_selected(a1)
	assert tv.remove_node(a)
	assert tv.roots.len == 1
	assert unsafe { tv.selected == nil }
	assert tv.remove_node(b)
	assert tv.roots.len == 0
	assert !tv.remove_node(b), 'уже снят'
	// move_node: на верхний уровень и обратно, в своё поддерево - нельзя
	tv.add_root(a)
	assert tv.move_node(a1, unsafe { nil }, 0)
	assert tv.roots.len == 2 && unsafe { a1.parent == nil }
	assert tv.move_node(a1, a, 0)
	assert a.children.len == 1
	assert !tv.move_node(a, a1, 0)
}

// Встроенный приём: файл извне в TextInput - путь вставляется в точку
// сброса; текст склеивается в одну строку; accept_drops = false - сброс
// уходит окну.
fn test_builtin_text_input_accepts_drops() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut ti := text_input('')
	mut col := create_vbox_fill()
	col.add(ti)
	t.add(col)
	t.win.set_on_drop_file(fn [mut log] (path string) {
		log.clicks++
	})
	x, y := t.center_of(ti)
	t.drop_files(x, y, ['/tmp/a.txt'])
	assert ti.get_text() == '/tmp/a.txt'
	assert log.clicks == 0
	// Текст в начало поля (левый край) - перед имеющимся
	b := get_widget_bounds(ti)
	t.drop_text(b.x + 2, y, 'два\nслова ')
	assert ti.get_text() == 'два слова /tmp/a.txt'
	// Отмена одним шагом
	assert ti.undo()
	assert ti.get_text() == '/tmp/a.txt'
	ti.accept_drops = false
	t.drop_files(x, y, ['/tmp/b.txt'])
	assert ti.get_text() == '/tmp/a.txt'
	assert log.clicks == 1
}

// Явная цель (поле dnd) главнее встроенного приёма.
fn test_builtin_yields_to_spec() {
	mut t := new_test_ui(width: 300, height: 80)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut ti := text_input('')
	set_drop_target(mut ti, [dnd_kind_files], fn [mut log] (info DropInfo) {
		log.drops << info
	})
	mut col := create_vbox_fill()
	col.add(ti)
	t.add(col)
	x, y := t.center_of(ti)
	t.drop_files(x, y, ['/tmp/a.txt'])
	assert log.drops.len == 1
	assert ti.get_text() == ''
	// текст поле dnd не принимает - его берёт встроенный приём
	t.drop_text(x, y, 'abc')
	assert ti.get_text() == 'abc'
}

// TextArea - многострочный текст как есть; CodeEditor readonly не принимает.
fn test_builtin_text_area_and_readonly_editor() {
	mut t := new_test_ui(width: 400, height: 200)!
	defer {
		t.close()
	}
	mut ta := text_area('')
	mut ce := code_editor()
	ce.readonly = true
	mut row := create_hbox_fill()
	row.add(ta, flex: 1)
	row.add(ce, flex: 1)
	t.add(row)
	x, y := t.center_of(ta)
	t.drop_text(x, y, 'строка 1\nстрока 2')
	assert ta.get_text() == 'строка 1\nстрока 2'
	ex, ey := t.center_of(ce)
	t.drop_text(ex, ey, 'нельзя')
	assert ce.get_text() == ''
	ce.readonly = false
	t.drop_files(ex, ey, ['/tmp/x.v'])
	assert ce.get_text() == '/tmp/x.v'
}

// ImageView открывает брошенную картинку, не-картинку отдаёт окну.
fn test_builtin_image_view() {
	mut t := new_test_ui(width: 200, height: 200)!
	defer {
		t.close()
	}
	mut log := &DndLog{}
	mut iv := image_view()
	mut col := create_vbox_fill()
	col.add(iv, flex: 1)
	t.add(col)
	t.win.set_on_drop_file(fn [mut log] (path string) {
		log.clicks++
	})
	x, y := t.center_of(iv)
	t.drop_files(x, y, ['/tmp/photo.JPG'])
	assert iv.path == '/tmp/photo.JPG'
	assert log.clicks == 0
	t.drop_files(x, y, ['/tmp/notes.txt'])
	assert iv.path == '/tmp/photo.JPG'
	assert log.clicks == 1
}

// Внутренний перенос: текст из виджета-источника в TextInput другого окна
// той же точкой входа (dnd_drop с контекстом окна цели).
fn test_builtin_internal_text_drag() {
	mut t := new_test_ui(width: 400, height: 80)!
	defer {
		t.close()
	}
	mut src := label('Перетащи')
	set_drag_source(mut src, fn (x f32, y f32) DragData {
		return DragData{
			kind: dnd_kind_text
			text: 'перенесено'
		}
	})
	mut ti := text_input('')
	mut row := create_hbox_fill()
	row.add(src, flex: 1)
	row.add(ti, flex: 1)
	t.add(row)
	x0, y0 := t.center_of(src)
	x1, y1 := t.center_of(ti)
	t.drag(x0, y0, x1, y1)
	assert ti.get_text() == 'перенесено'
}
