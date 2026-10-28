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

// sample_editor_graph - типы float/color/surface (float -> color разрешено), ноды value, mix, out.
fn sample_editor_graph() &NodeGraph {
	mut g := node_graph()
	g.define_socket_type('float', Color{150, 160, 175, 255}, .circle)
	g.define_socket_type('color', Color{232, 170, 60, 255}, .circle)
	g.define_socket_type('surface', Color{80, 200, 150, 255}, .diamond)
	g.allow_conversion('float', 'color')
	g.define_node(NodeTypeDef{
		id:       'value'
		title:    'Value'
		category: 'Input'
		color:    Color{150, 80, 170, 255}
		outputs:  [node_socket('Value', 'float')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:       'mix'
		title:    'Blend'
		category: 'Color'
		color:    Color{70, 130, 180, 255}
		inputs:   [
			node_socket('Factor', 'float', kind: .number, number: 0.5, min: 0, max: 1),
			node_socket('Color', 'color', kind: .color, color: Color{200, 60, 60, 255}),
			node_socket('Clamp', 'float', kind: .toggle),
		]
		outputs:  [node_socket('Result', 'color')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:       'out'
		title:    'Output'
		category: 'Output'
		color:    Color{170, 70, 80, 255}
		inputs:   [node_socket('Surface', 'surface')]
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
	// color -> surface нельзя: mix.Result -> out.Surface (вход в (40, 64 + 11 = 235))
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

// Ширина ноды мышью: правый край - x стоит; левый край - стоит правый край; зажим по min_width;
// одна команда отмены на жест; событие node_resized. Боковые края берутся в шапке (y = 50): на
// высоте строк по краям стоят сокеты, и там тянется связь.
fn test_node_editor_resize_by_edges() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	assert ne.hit_test(190, 50) == NodeHit{.edge, 1, ne_edge_right}
	assert ne.hit_test(300, 50) == NodeHit{.edge, 2, ne_edge_left}
	assert ne.hit_test(190, 75).kind == .socket_out, 'сокет на краю - главнее края'
	// Правый край value: 150 -> 200
	t.drag(190, 50, 240, 50)
	v := ne.graph.node(1) or { panic('v') }
	assert ne.graph.node_width(1) == 200 && v.x == 40
	assert counter.count(.node_resized) == 1
	// Левый край mix (x 300, ширина 150) на 20 влево: x 280, ширина 170, правый край на 450
	t.drag(300, 50, 280, 50)
	m := ne.graph.node(2) or { panic('m') }
	assert m.x == 280 && ne.graph.node_width(2) == 170
	// Сжать дальше предела: ширина 80 (min_width), правый край всё так же на 450
	t.drag(280, 50, 600, 50)
	m3 := ne.graph.node(2) or { panic('m') }
	assert ne.graph.node_width(2) == 80 && m3.x == 370
	// Каждый жест - одна команда
	assert stack.undo()
	assert ne.graph.node_width(2) == 170
	n2 := ne.graph.node(2) or { panic('m') }
	assert n2.x == 280
	t.close()
}

// Высота и углы: value (40, 40) 150x52 - низ на 92; mix (300, 40) 150x118. Верх и низ, четыре
// угла (снаружи угол ловится дальше, чем край), зажим высоты снизу содержимым, у свёрнутой ноды
// высота не тянется.
fn test_node_editor_resize_height_and_corners() {
	mut t, mut ne, _, mut stack := new_node_ui()!
	assert ne.hit_test(100, 92) == NodeHit{.edge, 1, ne_edge_bottom}
	assert ne.hit_test(100, 40) == NodeHit{.edge, 1, ne_edge_top}
	assert ne.hit_test(190, 92).slot == ne_edge_right | ne_edge_bottom
	assert ne.hit_test(196, 98).slot == ne_edge_right | ne_edge_bottom, 'угол снаружи - с запасом'
	assert ne.hit_test(100, 98).kind == .none, 'край снаружи - без запаса'
	assert ne.hit_test(40, 40).slot == ne_edge_left | ne_edge_top
	assert ne.hit_test(300, 158).slot == ne_edge_left | ne_edge_bottom
	// Низ value: 52 -> 92, верх стоит
	t.drag(100, 92, 100, 132)
	assert ne.graph.node_height(1) == 92
	assert (ne.graph.node(1) or { panic('v') }).y == 40
	// Верх mix на 20 вверх: y 20, высота 138, низ на месте
	t.drag(375, 40, 375, 20)
	assert ne.graph.node_height(2) == 138
	assert (ne.graph.node(2) or { panic('m') }).y == 20
	// Сжать верх ниже содержимого: высота 118 (содержимое), низ всё так же на 158
	t.drag(375, 20, 375, 300)
	assert ne.graph.node_height(2) == 118
	assert (ne.graph.node(2) or { panic('m') }).y == 40
	assert stack.undo()
	assert ne.graph.node_height(2) == 138
	// Правый нижний угол value (190, 132): обе оси сразу
	t.drag(190, 132, 230, 152)
	assert ne.graph.node_width(1) == 190 && ne.graph.node_height(1) == 112
	v := ne.graph.node(1) or { panic('v') }
	assert v.x == 40 && v.y == 40
	// Свёрнутая нода: высота - шапка, верх и низ не тянутся
	ne.graph.set_collapsed(1, true)
	t.frame()
	assert ne.graph.node_height(1) == 24
	assert ne.hit_test(100, 64).kind != .edge
	// Ширина уже 190: край на 40 + 190. У свёрнутой сокеты - на середине шапки (y 52) и занимают
	// почти весь край; угол над шапкой тянет только ширину
	assert ne.hit_test(230, 52).kind == .socket_out
	assert ne.hit_test(232, 36) == NodeHit{.edge, 1, ne_edge_right}
	t.close()
}

// Вид из CSS: `nodes { ... }` красит холст, тело карточки и шапку типа без своего цвета;
// тип со своим цветом шапки (value) его сохраняет. Без стилей - прежние цвета темы.
fn test_node_editor_css_colors() {
	mut t, mut ne, _, _ := new_node_ui()!
	ne.graph.define_node(NodeTypeDef{
		id:      'plain'
		title:   'P'
		outputs: [node_socket('Out', 'float')]
	})!
	ne.graph.add_node('plain', 300, 200)!
	t.frame()
	before := t.capture()
	assert before.px(553, 383) != blue
	assert before.px(430, 205) == Color{90, 90, 100, 255}, 'шапка без цвета - запасной цвет темы'
	t.app.set_stylesheet(parse_stylesheet('nodes { background: #0000ff; node-background: #00ff00; header-background: #ff0000; }',
		't.css')!)
	t.frame()
	f := t.capture()
	assert f.px(553, 383) == blue, 'холст'
	assert f.px(60, 80) == green, 'тело ноды value'
	assert f.px(430, 205) == red, 'шапка типа без цвета'
	assert f.px(150, 45) == before.px(150, 45), 'свой цвет шапки типа сильнее CSS'
	// Тема после редактора восстановлена
	assert t.win.ctx.theme.ne_bg.a == 0
	t.close()
}

const blue = Color{0, 0, 255, 255}
const green = Color{0, 255, 0, 255}
const red = Color{255, 0, 0, 255}

// Ctrl+C / Ctrl+V / Ctrl+X через буфер обмена: вставка под курсор с новыми id и выделением,
// одна команда отмены; вырезание удаляет; обычный текст в буфере ничего не вставляет.
fn test_node_editor_clipboard() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	ne.graph.connect(1, 0, 2, 0)!
	t.click(500, 350) // фокус редактору
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.key(sdl_k_c, sdl_kmod_ctrl)
	assert t.app.get_clipboard().contains('"type":"mix"')
	t.move(100, 250)
	t.key(sdl_k_v, sdl_kmod_ctrl)
	assert ne.graph.nodes().len == 4
	assert ne.graph.links().len == 2
	sel := ne.selected_nodes()
	assert sel.len == 2 && 1 !in sel && 2 !in sel, 'выделены вставленные'
	pv := ne.graph.node(sel[0]) or { panic('pv') }
	assert pv.x == 100 && pv.y == 250, 'угол группы под курсором'
	assert counter.count(.node_added) == 2
	assert stack.undo()
	assert ne.graph.nodes().len == 2
	// Ctrl+X: выделенная value - в буфер и удаляется
	t.click(100, 50)
	t.key(sdl_k_x, sdl_kmod_ctrl)
	assert ne.graph.nodes().len == 1
	t.key(sdl_k_v, sdl_kmod_ctrl)
	assert ne.graph.nodes().len == 2
	// Чужой текст в буфере - ничего не происходит, команды отмены нет
	t.app.set_clipboard('hello')
	before := stack.count()
	t.key(sdl_k_v, sdl_kmod_ctrl)
	assert ne.graph.nodes().len == 2
	assert stack.count() == before
	t.close()
}

// Переименование: двойной щелчок по шапке и F2 - поле поверх заголовка; Enter - свой заголовок
// (одна команда отмены, событие node_renamed, нода не сдвинулась); заголовок типа или пусто -
// свой заголовок снимается; Esc - отмена.
fn test_node_editor_rename() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	before := stack.count()
	t.dbl_click(100, 50)
	assert ne.editing && ne.edit_title
	assert stack.count() == before, 'двойной щелчок не сдвинул ноду'
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('Source')
	t.key(sdl_k_return, 0)
	assert !ne.editing
	assert ne.graph.node_title(1) == 'Source'
	assert counter.count(.node_renamed) == 1
	assert stack.count() == before + 1
	// F2 по активной ноде, Esc - без изменений
	t.key(sdl_k_f2, 0)
	assert ne.editing && ne.edit_title && ne.edit_node == 1
	t.type_text('zzz')
	t.key(sdl_k_escape, 0)
	assert ne.graph.node_title(1) == 'Source'
	// Ввести заголовок типа - свой снимается
	t.key(sdl_k_f2, 0)
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('Value')
	t.key(sdl_k_return, 0)
	assert (ne.graph.node(1) or { panic('n') }).title == ''
	assert stack.undo()
	assert ne.graph.node_title(1) == 'Source'
	t.close()
}

// Связь, отпущенная в пустоте, открывает меню только с подходящими типами; выбранная нода встаёт
// сокетом под точку отпускания и подключается - одна команда отмены. Со входа - нужен выход.
fn test_node_editor_link_to_empty_opens_menu() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	// value.Value (float) -> пусто: вход float есть только у mix (out - surface)
	t.drag(190, 75, 250, 300)
	assert ne.menu.open
	assert ne.menu.items == ['mix']
	t.key(sdl_k_return, 0)
	assert !ne.menu.open
	assert ne.graph.nodes().len == 3
	added := ne.graph.nodes().last()
	// Вход Factor (строка 1 после выхода) - под точкой: y = 300 - 24 - 22 - 11
	assert added.type_id == 'mix' && added.x == 250 && added.y == 243
	l := ne.graph.link_into(added.id, 0) or { panic('нет связи') }
	assert l.from_node == 1
	assert counter.count(.link_added) == 1
	assert stack.undo()
	assert ne.graph.nodes().len == 2 && ne.graph.links().len == 0
	// Со свободного входа mix.Clamp (float) -> пусто: выход float только у value
	t.drag(300, 141, 100, 300)
	assert ne.menu.items == ['value']
	t.key(sdl_k_return, 0)
	v := ne.graph.nodes().last()
	assert v.type_id == 'value' && v.x == -50 && v.y == 265
	assert (ne.graph.link_into(2, 2) or { panic('нет связи') }).from_node == v.id
	// Отцеплённая связь, брошенная мимо, по-прежнему удаляется, меню нет
	t.drag(300, 141, 100, 350)
	assert !ne.menu.open
	assert ne.graph.links().len == 0
	t.close()
}

// Вставка в связь: одиночную ноду без связей отпустили на провод value -> mix.Color - она
// встаёт в разрыв (value -> новая.Factor, новая.Result -> mix.Color); вместе с перемещением -
// одна команда отмены. С выключенным auto_insert - только перемещение.
fn test_node_editor_insert_into_link() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	ne.graph.connect(1, 0, 2, 1)!
	n3 := ne.graph.add_node('mix', 40, 250)!
	t.frame()
	t.press(100, 260)
	t.move(150, 200)
	t.move(245, 80)
	assert ne.insert_link != 0, 'провод под нодой подсвечен'
	t.release(245, 80)
	assert ne.insert_link == 0
	links := ne.graph.links()
	assert links.len == 2
	a := ne.graph.link_into(n3, 0) or { panic('нет входа') }
	assert a.from_node == 1
	b := ne.graph.link_into(2, 1) or { panic('нет выхода') }
	assert b.from_node == n3 && b.from_slot == 0
	assert counter.count(.link_removed) == 1 && counter.count(.link_added) == 2
	assert stack.undo()
	assert ne.graph.links().len == 1
	assert (ne.graph.node(n3) or { panic('n3') }).y == 250
	// Выключено - нода просто переезжает
	ne.auto_insert = false
	t.drag(100, 260, 245, 80)
	assert ne.graph.links().len == 1
	assert (ne.graph.link_into(2, 1) or { panic('l') }).from_node == 1
	t.close()
}

// Привязка к сетке (шаг 20): на сетку встаёт нода, за которую тянут; Ctrl переключает привязку
// на время жеста; при изменении размера на линию сетки встаёт тянущийся край.
fn test_node_editor_snap_to_grid() {
	mut t, mut ne, _, _ := new_node_ui()!
	// Выключена: как есть
	t.drag(100, 50, 133, 67)
	v := ne.graph.node(1) or { panic('v') }
	assert v.x == 73 && v.y == 57
	// С Ctrl - привязка включается на этот жест: (73 + 9, 57 + 9) -> (80, 60)
	sim_drag(mut t.app, t.win, 140, 70, 149, 79, 4, .left, sdl_kmod_ctrl)
	assert v.x == 80 && v.y == 60
	// Включена: группа сдвигается вместе - на сетку встаёт активная, mix едет на столько же
	ne.snap_to_grid = true
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.drag(150, 70, 157, 73) // активная - value (под курсором): (87, 63) -> (80, 60)
	assert v.x == 80 && v.y == 60
	m := ne.graph.node(2) or { panic('m') }
	assert m.x == 300 && m.y == 40, 'сдвиг 0 - группа на месте'
	// Правый край mix (450) тянут до 463 - встаёт на 460: ширина 160
	t.click(500, 350)
	t.drag(450, 50, 463, 50)
	assert ne.graph.node_width(2) == 160
	t.close()
}

// Подсказки сокетов (TipAtPoint): имя и тип, у входа - значение поля или откуда подключён,
// у выхода - число связей; не над сокетом - ''. Окно берёт их тем же обходом (hit_at), свой
// текст приложения - socket_tooltip.
fn test_node_editor_socket_tooltips() {
	mut t, mut ne, _, _ := new_node_ui()!
	assert ne.tooltip_at(300, 97) == 'Factor (float) = 0.500'
	assert ne.tooltip_at(300, 141) == 'Clamp (float) = false'
	assert ne.tooltip_at(190, 75) == 'Value (float)'
	assert ne.tooltip_at(100, 300) == ''
	ne.graph.connect(1, 0, 2, 1)!
	ne.graph.set_node_title(1, 'Src')
	assert ne.tooltip_at(300, 119) == 'Color (color)\n<- Src: Value'
	assert ne.tooltip_at(190, 75) == 'Value (float)\n-> 1'
	t.frame()
	assert t.win.hit_at(300, 119).text == 'Color (color)\n<- Src: Value'
	// Над пустым холстом - общая подсказка виджета
	ne.tooltip = 'canvas'
	assert t.win.hit_at(100, 300).text == 'canvas'
	ne.socket_tooltip = fn (node int, slot int, out bool) string {
		return if out { 'computed: 42' } else { '' }
	}
	assert ne.tooltip_at(190, 75) == 'computed: 42'
	assert ne.tooltip_at(300, 97) == 'Factor (float) = 0.500', "'' - подсказка по умолчанию"
	t.close()
}

// Фреймы в редакторе: Ctrl+J обводит выделенные ноды; шапка тянет фрейм с нодами внутри (одна
// команда); край меняет размер; пустое место внутри - холст (рамка выделения); двойной щелчок по
// шапке - переименовать; Delete удаляет фрейм, ноды остаются.
fn test_node_editor_frames() {
	mut t, mut ne, counter, mut stack := new_node_ui()!
	t.click(500, 350)
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.key(`j`, sdl_kmod_ctrl)
	assert counter.count(.frame_added) == 1
	frames := ne.graph.frames()
	assert frames.len == 1
	f := frames[0]
	// Ноды 40..450 x 40..158, отступ 20, шапка 26: (20, -6) 450 x 184
	assert f.x == 20 && f.y == -6 && f.w == 450 && f.h == 184
	assert ne.selected_frame == f.id && ne.selected_nodes().len == 0
	assert ne.hit_test(250, 5).kind == .frame_header
	assert ne.hit_test(250, 150).kind == .none, 'внутри фрейма - холст'
	// Тянуть за шапку: фрейм и обе ноды на (+20, +20)
	t.drag(250, 5, 270, 25)
	assert f.x == 40 && f.y == 14
	assert (ne.graph.node(1) or { panic('1') }).x == 60
	assert (ne.graph.node(2) or { panic('2') }).y == 60
	assert counter.count(.frame_changed) == 1
	assert stack.undo()
	g1 := ne.graph.frame(f.id) or { panic('f') }
	assert g1.x == 20 && (ne.graph.node(1) or { panic('1') }).x == 40
	// Правый край (470) - на 30 правее
	t.drag(470, 100, 500, 100)
	assert (ne.graph.frame(f.id) or { panic('f') }).w == 480
	// Рамка выделения изнутри фрейма выделяет ноды
	t.drag(250, 150, 30, 30)
	assert ne.selected_nodes() == [1]
	assert ne.selected_frame == 0
	// Переименование двойным щелчком по шапке
	t.dbl_click(250, 5)
	assert ne.editing && ne.edit_frame
	t.key(sdl_k_a, sdl_kmod_ctrl)
	t.type_text('Group')
	t.key(sdl_k_return, 0)
	assert (ne.graph.frame(f.id) or { panic('f') }).title == 'Group'
	// Delete по выбранному фрейму - ноды остаются
	t.click(250, 5)
	t.key(sdl_k_delete, 0)
	assert ne.graph.frames().len == 0 && ne.graph.nodes().len == 2
	assert counter.count(.frame_removed) == 1
	assert stack.undo()
	assert ne.graph.frames().len == 1
	t.close()
}

// Reroute-точки в редакторе: двойной щелчок по проводу ставит точку (одна команда); кольцо
// вокруг точки тянет новую связь, центр - саму точку; провод, отпущенный на точку, входит в неё.
fn test_node_editor_reroute() {
	mut t, mut ne, _, mut stack := new_node_ui()!
	ne.graph.connect(1, 0, 2, 1)! // value (190, 75) -> mix.Color (300, 119)
	t.frame()
	// Середина кривой: x 245, y между 75 и 119
	t.dbl_click(245, 97)
	nodes := ne.graph.nodes()
	assert nodes.len == 3
	r := nodes.last().id
	assert ne.graph.is_reroute(r)
	assert ne.graph.links().len == 2
	assert (ne.graph.source_of(2, 1) or { panic('src') }).from_node == 1
	assert stack.undo()
	assert ne.graph.nodes().len == 2 && ne.graph.links().len == 1
	assert stack.redo()
	// Центр точки - тащить; кольцо - связь в mix.Factor (300, 97)
	pt := ne.graph.node(r) or { panic('r') }
	cx, cy := pt.x + 6, pt.y + 6 // копии: pt - ссылка на ноду, её поля меняются
	assert ne.hit_test(cx, cy).kind == .body
	assert ne.hit_test(cx + 9, cy).kind == .socket_out
	t.drag(cx + 9, cy, 300, 97)
	assert (ne.graph.link_into(2, 0) or { panic('кольцо') }).from_node == r
	t.drag(cx, cy, cx, cy + 100)
	assert (ne.graph.node(r) or { panic('r') }).y == cy - 6 + 100
	assert ne.tooltip_at(cx, cy + 100) == 'Reroute (float)'
	t.close()
}
