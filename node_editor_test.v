module vgui

// Тесты NodeEditor (node_editor.v) настоящим путём событий (testkit.v): связи мышью, отцепление,
// проверка типов, перемещение и отмена, рамка, удаление, разрез, зум, сворачивание, поля
// значений, меню добавления с поиском; снапшоты вида.
//
// Вид по умолчанию (view 0,0, zoom 1), редактор на всё окно: экран = холст. Нода 'value' в
// (40, 40): выход - (190, 75). Нода 'mix' в (300, 40): выход Result - (450, 75), входы Factor /
// Color / Mode - (300, 97) / (300, 119) / (300, 141), поля входов - x 310..440.

// NeCounter - события редактора по видам (замыкание V захватывает копию переменной, поэтому
// счётчик - объект в куче).
@[heap]
struct NeCounter {
mut:
	kinds []NodeEventKind
}

fn (c &NeCounter) count(k NodeEventKind) int {
	return c.kinds.filter(it == k).len
}

// new_node_ui - окно 600x400, граф sample_editor_graph с нодами value (id 1) и mix (id 2),
// стек отмены и счётчик событий.
fn new_node_ui() !(&TestUi, &NodeEditor, &NeCounter, &UndoStack) {
	mut t := new_test_ui(width: 600, height: 400)!
	mut g := sample_editor_graph()
	g.add_node('value', 40, 40)!
	g.add_node('mix', 300, 40)!
	mut ne := node_editor(g)
	mut stack := undo_stack(100)
	ne.set_undo_stack(stack)
	mut counter := &NeCounter{}
	ne.on_event = fn [mut counter] (e NodeEvent) {
		counter.kinds << e.kind
	}
	t.add(ne)
	return t, ne, counter, stack
}

// sample_editor_graph - типы float/color/shader (float -> color разрешено), ноды value, mix, out.
fn sample_editor_graph() &NodeGraph {
	mut g := node_graph()
	g.define_socket_type('float', Color{160, 160, 160, 255}, .circle)
	g.define_socket_type('color', Color{199, 199, 41, 255}, .circle)
	g.define_socket_type('shader', Color{99, 199, 99, 255}, .diamond)
	g.allow_conversion('float', 'color')
	g.define_node(NodeTypeDef{
		id:       'value'
		title:    'Value'
		category: 'Input'
		color:    Color{120, 60, 60, 255}
		outputs:  [node_socket('Value', 'float')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:       'mix'
		title:    'Mix Color'
		category: 'Color'
		color:    Color{110, 110, 40, 255}
		inputs:   [
			node_socket('Factor', 'float', kind: .number, number: 0.5, min: 0, max: 1),
			node_socket('Color', 'color', kind: .color, color: Color{200, 60, 60, 255}),
			node_socket('Clamp', 'float', kind: .toggle),
		]
		outputs:  [node_socket('Result', 'color')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:       'out'
		title:    'Material Output'
		category: 'Output'
		color:    Color{60, 100, 60, 255}
		inputs:   [node_socket('Surface', 'shader')]
	}) or { panic(err) }
	return g
}

fn test_node_editor_bounds() {
	mut t, ne, _, _ := new_node_ui()!
	assert ne.bounds == Rect{0, 0, 600, 400}
	t.close()
}

fn test_node_editor_drag_link_and_detach() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	// value.Value -> mix.Factor
	t.drag(190, 75, 300, 97)
	assert ne.graph.links().len == 1
	assert counter.count(.link_added) == 1
	l := ne.graph.links()[0]
	assert l.from_node == 1 && l.to_node == 2 && l.to_slot == 0
	// Отцепить от входа и бросить мимо - связь удаляется
	t.drag(300, 97, 250, 300)
	assert ne.graph.links().len == 0
	assert counter.count(.link_removed) == 1
	// Отмена возвращает связь
	assert stack.undo()
	assert ne.graph.links().len == 1
	// Отцепить и перенести на другой вход (float -> color - преобразование)
	t.drag(300, 97, 300, 119)
	links := ne.graph.links()
	assert links.len == 1 && links[0].to_slot == 1
	t.close()
}

fn test_node_editor_link_from_input_and_types() {
	mut t, mut ne, _, _ := new_node_ui()!
	o := ne.graph.add_node('out', 40, 200)!
	t.frame()
	// От свободного входа к выходу: mix.Clamp <- value.Value
	t.drag(300, 141, 190, 75)
	assert ne.graph.links().len == 1
	// color -> shader нельзя: mix.Result -> out.Surface (вход в (40, 64 + 11 = 235))
	t.drag(450, 75, 40, 235)
	assert ne.graph.links().len == 1
	_ = o
	t.close()
}

fn test_node_editor_move_select_undo() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	// Тянуть ноду value за шапку
	t.drag(100, 50, 160, 90)
	n := ne.graph.node(1) or { panic('n') }
	assert n.x == 100 && n.y == 80
	assert ne.selected_nodes() == [1]
	assert counter.count(.nodes_moved) == 1
	assert stack.undo()
	m := ne.graph.node(1) or { panic('n') }
	assert m.x == 40 && m.y == 40
	assert stack.redo()
	assert (ne.graph.node(1) or { panic('n') }).x == 100
	// Щелчок по ноде без сдвига команды не даёт
	count := stack.count()
	t.click(350, 50)
	assert stack.count() == count
	assert ne.selected_nodes() == [2]
	t.close()
}

fn test_node_editor_box_select_delete_and_keys() {
	mut t, mut ne, _, mut stack := new_node_ui()!
	t.drag(450, 75, 300, 97) // связь mix -> mix нельзя (сама с собой), лишь бы не мешала
	// Рамка через обе ноды
	t.drag(20, 20, 500, 300)
	assert ne.selected_nodes().len == 2
	// Щелчок по пустому месту снимает выделение
	t.click(500, 350)
	assert ne.selected_nodes().len == 0
	// Ctrl+A, затем Delete
	t.key(sdl_k_a, sdl_kmod_ctrl)
	assert ne.selected_nodes().len == 2
	t.key(sdl_k_delete, 0)
	assert ne.graph.nodes().len == 0
	assert stack.undo()
	assert ne.graph.nodes().len == 2
	t.close()
}

fn test_node_editor_cut_links() {
	mut t, mut ne, _, _ := new_node_ui()!
	ne.graph.connect(1, 0, 2, 0)!
	t.frame()
	// Ctrl + правая кнопка - линия поперёк связи
	sim_drag(mut t.app, t.win, 245, 20, 245, 200, 8, .right, sdl_kmod_ctrl)
	assert ne.graph.links().len == 0
	t.close()
}

fn test_node_editor_zoom_keeps_point_under_cursor() {
	mut t, mut ne, _, _ := new_node_ui()!
	wx, wy := ne.to_world(300, 200)
	t.wheel(300, 200, 2)
	assert ne.zoom > 1
	wx2, wy2 := ne.to_world(300, 200)
	assert abs_f32(wx - wx2) < 0.01 && abs_f32(wy - wy2) < 0.01
	t.close()
}

fn test_node_editor_collapse_and_frame_all() {
	mut t, mut ne, _, _ := new_node_ui()!
	t.click(52, 52) // треугольник в шапке value
	assert (ne.graph.node(1) or { panic('n') }).collapsed
	ne.frame_all()
	assert ne.zoom <= 1
	// До первой раскладки frame_all откладывается и выполняется в ней
	mut t2 := new_test_ui(width: 300, height: 200)!
	mut g := sample_editor_graph()
	g.add_node('value', 0, 0)!
	g.add_node('mix', 900, 600)!
	mut ne2 := node_editor(g)
	ne2.frame_all()
	assert ne2.zoom == 1
	t2.add(ne2)
	assert ne2.zoom < 0.5
	t2.close()
	t.close()
}

fn test_node_editor_fields() {
	mut t, mut ne, counter, _ := new_node_ui()!
	// Протяжка числа на 20 px: шаг 0.1 на 10 px -> 0.5 + 0.2
	t.drag(375, 97, 395, 97)
	assert abs_f32(f32((ne.graph.value(2, 0) or { panic('v') }).number) - 0.7) < 1e-5
	assert counter.count(.value_changed) > 0
	// Щелчок без протяжки - ввод с клавиатуры
	t.click(375, 97)
	assert ne.editing
	t.type_text('0.25')
	t.key(sdl_k_return, 0)
	assert !ne.editing
	assert abs_f32(f32((ne.graph.value(2, 0) or { panic('v') }).number) - 0.25) < 1e-5
	// Флажок
	t.click(318, 141)
	assert (ne.graph.value(2, 2) or { panic('v') }).flag
	t.close()
}

fn test_node_editor_add_menu_search() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	t.click(500, 300) // фокус редактору
	t.move(500, 300)
	t.key(sdl_k_a, sdl_kmod_shift)
	assert ne.menu.open
	assert ne.menu.items.len == 3
	t.type_text('outp')
	assert ne.menu.items == ['out']
	t.key(sdl_k_return, 0)
	assert !ne.menu.open
	assert ne.graph.nodes().len == 3
	assert counter.count(.node_added) == 1
	added := ne.graph.nodes().last()
	assert added.type_id == 'out'
	assert ne.selected_nodes() == [added.id]
	assert stack.undo()
	assert ne.graph.nodes().len == 2
	// Esc закрывает без добавления; правый щелчок по пустому месту открывает
	t.right_click(500, 300)
	assert ne.menu.open
	t.key(sdl_k_escape, 0)
	assert !ne.menu.open
	assert ne.graph.nodes().len == 2
	t.close()
}

// Вид редактора: две ноды со связью и полями, выделение; и тянущаяся связь.
fn test_node_editor_snapshot() {
	mut t := new_test_ui(width: 520, height: 260, theme: dark_theme())!
	mut g := sample_editor_graph()
	g.add_node('value', 30, 40)!
	g.add_node('mix', 250, 30)!
	g.connect(1, 0, 2, 1)!
	mut ne := node_editor(g)
	t.add(ne)
	ne.select_node(2, false)
	t.redraw()
	t.match_snapshot('testdata/snapshots/node_editor.png', SnapshotOpts{})!
	t.press(180, 75) // выход Value: (30 + 150, 40 + 24 + 11)
	t.move(200, 120)
	t.move(260, 200)
	t.redraw()
	t.match_snapshot('testdata/snapshots/node_editor_link.png', SnapshotOpts{})!
	t.release(260, 200)
	t.close()
}
