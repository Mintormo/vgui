module vgui

// Тесты модели графа NodeGraph (node_graph.v): совместимость типов, циклы, одна связь на вход,
// вето приложения, значения полей, снимки для отмены и JSON. SDL не нужен.

// sample_graph - типы float/color/shader, неявное float -> color, и типы нод value (выход float),
// mix (входы float с полем, color, выход color), out (вход shader).
fn sample_graph() &NodeGraph {
	mut g := node_graph()
	g.define_socket_type('float', Color{160, 160, 160, 255}, .circle)
	g.define_socket_type('color', Color{200, 200, 40, 255}, .circle)
	g.define_socket_type('shader', Color{100, 200, 100, 255}, .diamond)
	g.allow_conversion('float', 'color')
	g.define_node(NodeTypeDef{
		id:       'value'
		title:    'Value'
		category: 'Input'
		outputs:  [node_socket('Value', 'float')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:       'mix'
		title:    'Mix'
		category: 'Color'
		inputs:   [
			node_socket('Factor', 'float', kind: .number, number: 0.5, min: 0, max: 1),
			node_socket('Color', 'color', kind: .color),
			node_socket('Mode', 'float', kind: .choice, choices: ['Mix', 'Add']),
		]
		outputs:  [node_socket('Result', 'color')]
	}) or { panic(err) }
	g.define_node(NodeTypeDef{
		id:     'out'
		title:  'Output'
		inputs: [node_socket('Surface', 'shader')]
	}) or { panic(err) }
	return g
}

fn test_node_graph_types_and_links() {
	mut g := sample_graph()
	v := g.add_node('value', 0, 0)!
	m := g.add_node('mix', 200, 0)!
	o := g.add_node('out', 400, 0)!
	// float -> float, float -> color (преобразование), color -> shader - нельзя
	g.connect(v, 0, m, 0)!
	g.connect(v, 0, m, 1)!
	if _ := g.connect(m, 0, o, 0) {
		assert false
	}
	assert g.links().len == 2
	// Нода сама с собой и несуществующий слот
	if _ := g.connect(m, 0, m, 1) {
		assert false
	}
	if _ := g.connect(v, 3, m, 0) {
		assert false
	}
	// Неизвестный тип ноды
	if _ := g.add_node('nope', 0, 0) {
		assert false
	}
}

fn test_node_graph_input_takes_one_link() {
	mut g := sample_graph()
	a := g.add_node('value', 0, 0)!
	b := g.add_node('value', 0, 100)!
	m := g.add_node('mix', 200, 0)!
	first := g.connect(a, 0, m, 0)!
	assert first.replaced.id == 0
	second := g.connect(b, 0, m, 0)!
	assert second.replaced.id == first.link.id
	assert g.links().len == 1
	into := g.link_into(m, 0) or { panic('no link') }
	assert into.from_node == b
	// Та же связь повторно не создаётся
	again := g.connect(b, 0, m, 0)!
	assert again.link.id == second.link.id
	assert g.links().len == 1
}

fn test_node_graph_cycles_and_veto() {
	mut g := sample_graph()
	a := g.add_node('mix', 0, 0)!
	b := g.add_node('mix', 200, 0)!
	g.connect(a, 0, b, 1)!
	// b -> a замкнула бы цикл
	if _ := g.connect(b, 0, a, 1) {
		assert false
	}
	g.allow_cycles = true
	g.connect(b, 0, a, 1)!
	g.allow_cycles = false
	// Вето приложения: не на вход Color
	mut h := sample_graph()
	x := h.add_node('value', 0, 0)!
	y := h.add_node('mix', 0, 0)!
	h.can_connect = fn (l NodeLink) bool {
		return l.to_slot != 1
	}
	if _ := h.connect(x, 0, y, 1) {
		assert false
	}
	h.connect(x, 0, y, 0)!
}

fn test_node_graph_values_and_remove() {
	mut g := sample_graph()
	v := g.add_node('value', 0, 0)!
	m := g.add_node('mix', 0, 0)!
	assert (g.value(m, 0) or { panic('v') }).number == 0.5
	// Число - в границы поля, выбор - в список
	assert g.set_value(m, 0, NodeValue{ number: 7 })
	assert (g.value(m, 0) or { panic('v') }).number == 1
	assert g.set_value(m, 2, NodeValue{ choice: 9 })
	assert (g.value(m, 2) or { panic('v') }).choice == 1
	assert !g.set_value(m, 9, NodeValue{})
	g.connect(v, 0, m, 0)!
	removed := g.remove_node(v)
	assert removed.len == 1
	assert g.links().len == 0
	assert g.nodes().len == 1
}

fn test_node_graph_snapshot_restore() {
	mut g := sample_graph()
	v := g.add_node('value', 0, 0)!
	m := g.add_node('mix', 0, 0)!
	snap := g.snapshot()
	g.connect(v, 0, m, 0)!
	g.set_value(m, 0, NodeValue{ number: 0.9 })
	g.remove_node(v)
	g.restore(snap)
	assert g.nodes().len == 2
	assert g.links().len == 0
	assert (g.value(m, 0) or { panic('v') }).number == 0.5
	// Правка после restore не портит снимок: второе восстановление даёт то же
	g.set_value(m, 0, NodeValue{ number: 0.1 })
	g.restore(snap)
	assert (g.value(m, 0) or { panic('v') }).number == 0.5
	// Новые id не совпадают с восстановленными
	w := g.add_node('value', 0, 0)!
	assert w > m
}

fn test_node_graph_json_roundtrip() {
	mut g := sample_graph()
	v := g.add_node('value', 10, 20)!
	m := g.add_node('mix', 210.5, 20)!
	g.connect(v, 0, m, 1)!
	g.set_value(m, 1, NodeValue{ color: Color{10, 20, 30, 255} })
	mut n := g.node(m) or { panic('m') }
	n.collapsed = true
	text := g.to_json()
	mut h := sample_graph()
	h.load_json(text)!
	assert h.to_json() == text
	hm := h.node(m) or { panic('m') }
	assert hm.x == 210.5 && hm.collapsed
	assert (h.value(m, 1) or { panic('v') }).color == Color{10, 20, 30, 255}
	// Новые id - после загруженных
	assert h.add_node('value', 0, 0)! > m
}

fn test_node_graph_json_skips_bad_parts() {
	mut g := sample_graph()
	// Нода неизвестного типа, связь на неё и несовместимая связь пропускаются
	text := '{"version":1,"nodes":[{"id":1,"type":"mix","x":0,"y":0,"collapsed":false,"values":[]},{"id":2,"type":"ghost","x":0,"y":0,"collapsed":false,"values":[]},{"id":3,"type":"out","x":0,"y":0,"collapsed":false,"values":[]}],"links":[{"id":1,"from":2,"out":0,"to":1,"in":0},{"id":2,"from":1,"out":0,"to":3,"in":0}]}'
	g.load_json(text)!
	assert g.nodes().len == 2
	assert g.links().len == 0
	// Пустые значения - по умолчанию
	assert (g.value(1, 0) or { panic('v') }).number == 0.5
	// Не JSON - ошибка, граф прежний
	if _ := g.load_json('nope') {
		assert false
	}
	assert g.nodes().len == 2
}
