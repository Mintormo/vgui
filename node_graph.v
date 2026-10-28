module vgui

import x.json2

// Файл node_graph.v: модель графа для NodeEditor (node_editor.v) - отдельно от отрисовки, как в
// Qt Nodes (AbstractGraphModel) и imnodes. Приложение описывает типы сокетов и нод, редактор
// показывает граф и меняет его через этот API; сохранение - JSON (to_json / load_json).
//
// Опыт других библиотек, на который опирается устройство:
//   - id нод и связей - устойчивые целые (imnodes, Qt Nodes): сохранение, C-ABI и события не
//     зависят от адресов в памяти; связь - четвёрка (нода-выход, слот, нода-вход, слот), как
//     ConnectionId в Qt Nodes;
//   - совместимость сокетов: одинаковый тип, тип-«джокер» `*` (litegraph.js) или неявное
//     преобразование, объявленное приложением (allow_conversion - float в color, как в Blender;
//     type converters в Qt Nodes);
//   - вето приложения на новую связь - can_connect (isValidConnection в React Flow, accept/reject
//     в imgui-node-editor);
//   - циклы по умолчанию запрещены (граф шейдеров - DAG); allow_cycles разрешает;
//   - на вход - одна связь (новая заменяет старую), с выхода - сколько угодно (Blender, Qt Nodes).
//
// Перерисовка: каждый изменяющий метод графа первой строкой зовёт widget_changed() (PROJECT.md,
// «Инвалидация и dirty regions») - правка кодом видна сразу, в том числе из своего цикла. Прямое
// присваивание полей GraphNode (n.x = ...) этого не делает: для позиции, свёрнутости, заголовка и
// данных есть сеттеры (set_node_pos, set_collapsed, set_node_title, set_node_data).
//
// Значения полей входов (число, флажок, цвет, выбор) хранятся в ноде (GraphNode.values, по одному
// на вход); у подключённого входа поле не показывается, но значение сохраняется. Снимки для отмены
// (snapshot / restore) - копия нод и связей: команды UndoStack восстанавливают граф целиком.

// SocketShape - форма значка сокета (как в Blender: круг - значение, ромб - поле и т.п.;
// смысл форм задаёт приложение).
pub enum SocketShape {
	circle
	square
	diamond
}

// NodeFieldKind - редактор значения на входе ноды: нет, число, флажок, цвет, выбор из списка.
pub enum NodeFieldKind {
	none
	number
	toggle
	color
	choice
}

// SocketTypeDef - тип данных сокета: имя (ключ совместимости), цвет и форма значка.
pub struct SocketTypeDef {
pub:
	name  string
	color Color
	shape SocketShape
}

// NodeField - поле значения на входе: вид и значение по умолчанию. Для числа - границы,
// шаг (на сколько меняет значение протяжка мышью на 10 px) и число знаков после запятой.
@[params]
pub struct NodeField {
pub:
	kind    NodeFieldKind
	number  f64
	min     f64 = -1.0e30
	max     f64 = 1.0e30
	step    f64 = 0.1
	digits  int = 3
	flag    bool
	color   Color = Color{200, 200, 200, 255}
	choices []string
	choice  int
}

// NodeSocketDef - вход или выход в описании типа ноды: подпись, тип сокета и поле значения
// (у выхода поле не используется).
pub struct NodeSocketDef {
pub:
	name  string
	typ   string
	field NodeField
}

// node_socket - описание сокета: node_socket('Factor', 'float', kind: .number, number: 0.5, max: 1).
pub fn node_socket(name string, typ string, field NodeField) NodeSocketDef {
	return NodeSocketDef{
		name:  name
		typ:   typ
		field: field
	}
}

// NodeTypeDef - тип ноды: id (ключ в сохранённом графе), заголовок, категория (группа в меню
// добавления), цвет шапки, ширина карточки (в единицах холста), входы и выходы.
pub struct NodeTypeDef {
pub mut:
	id       string
	title    string
	category string
	color    Color = Color{90, 90, 100, 255}
	width    f32   = 150
	inputs   []NodeSocketDef
	outputs  []NodeSocketDef
}

// NodeValue - значение поля одного входа ноды (используется поле по виду NodeField).
pub struct NodeValue {
pub mut:
	number f64
	flag   bool
	color  Color
	choice int
}

// GraphNode - нода графа: устойчивый id, тип, позиция левого верхнего угла на холсте,
// свёрнута ли, значения полей входов (по одному на вход типа).
@[heap]
pub struct GraphNode {
pub mut:
	id        int
	type_id   string
	x         f32
	y         f32
	collapsed bool
	values    []NodeValue
	// title - свой заголовок этой ноды ('' - заголовок типа); data - строка приложения (параметры,
	// ссылка на свой объект по ключу). Оба сохраняются в JSON.
	title string
	data  string
}

// NodeLink - связь: выход from_slot ноды from_node -> вход to_slot ноды to_node.
pub struct NodeLink {
pub:
	id        int
	from_node int
	from_slot int
	to_node   int
	to_slot   int
}

// NodeGraph - граф: описания типов и сами ноды со связями. nodes - в порядке отрисовки
// (последняя - сверху). can_connect - необязательное вето приложения на новую связь.
@[heap]
pub struct NodeGraph {
pub mut:
	allow_cycles bool
	can_connect  fn (NodeLink) bool = unsafe { nil }
mut:
	socket_types map[string]SocketTypeDef
	conversions  map[string]bool // ключ 'из>в'
	types        map[string]NodeTypeDef
	type_order   []string
	nodes        []&GraphNode
	links        []NodeLink
	next_node    int = 1
	next_link    int = 1
}

// node_graph - пустой граф без типов.
pub fn node_graph() &NodeGraph {
	return &NodeGraph{}
}

// ─── Описание типов ────────────────────────────────────

// define_socket_type - тип сокета name с цветом и формой значка. Повторное описание заменяет.
pub fn (mut g NodeGraph) define_socket_type(name string, color Color, shape SocketShape) {
	widget_changed()
	g.socket_types[name] = SocketTypeDef{
		name:  name
		color: color
		shape: shape
	}
}

// allow_conversion - выход типа from можно подключать ко входу типа to (неявное преобразование).
pub fn (mut g NodeGraph) allow_conversion(from string, to string) {
	widget_changed()
	g.conversions['${from}>${to}'] = true
}

// define_node - тип ноды. Ошибка: пустой или повторный id.
pub fn (mut g NodeGraph) define_node(t NodeTypeDef) ! {
	widget_changed()
	if t.id == '' {
		return error('node type: empty id')
	}
	if t.id in g.types {
		return error('node type `${t.id}` is already defined')
	}
	g.types[t.id] = t
	g.type_order << t.id
}

// node_type - описание типа ноды по id.
pub fn (g &NodeGraph) node_type(id string) ?NodeTypeDef {
	return g.types[id] or { return none }
}

// node_types - все типы нод в порядке описания (для меню добавления).
pub fn (g &NodeGraph) node_types() []NodeTypeDef {
	mut out := []NodeTypeDef{cap: g.type_order.len}
	for id in g.type_order {
		out << g.types[id] or { continue }
	}
	return out
}

// socket_type - тип сокета по имени; неизвестный - серый круг (граф не падает от опечатки).
pub fn (g &NodeGraph) socket_type(name string) SocketTypeDef {
	return g.socket_types[name] or {
		SocketTypeDef{
			name:  name
			color: Color{160, 160, 160, 255}
		}
	}
}

// ─── Ноды ──────────────────────────────────────────────

// add_node - новая нода типа type_id в точке (x, y) холста; значения полей - по умолчанию.
// Возвращает id. Ошибка - неизвестный тип.
pub fn (mut g NodeGraph) add_node(type_id string, x f32, y f32) !int {
	widget_changed()
	t := g.types[type_id] or { return error('unknown node type `${type_id}`') }
	n := &GraphNode{
		id:      g.next_node
		type_id: type_id
		x:       x
		y:       y
		values:  t.inputs.map(node_default_value(it.field))
	}
	g.next_node++
	g.nodes << n
	return n.id
}

// node_default_value - значение поля по умолчанию из его описания.
fn node_default_value(f NodeField) NodeValue {
	return NodeValue{
		number: f.number
		flag:   f.flag
		color:  f.color
		choice: f.choice
	}
}

// remove_node удаляет ноду и все её связи; возвращает удалённые связи (для событий).
pub fn (mut g NodeGraph) remove_node(id int) []NodeLink {
	widget_changed()
	idx := g.node_index(id)
	if idx < 0 {
		return []NodeLink{}
	}
	mut removed := []NodeLink{}
	mut kept := []NodeLink{cap: g.links.len}
	for l in g.links {
		if l.from_node == id || l.to_node == id {
			removed << l
		} else {
			kept << l
		}
	}
	g.links = kept
	g.nodes.delete(idx)
	return removed
}

// node - нода по id.
pub fn (g &NodeGraph) node(id int) ?&GraphNode {
	idx := g.node_index(id)
	if idx < 0 {
		return none
	}
	return g.nodes[idx]
}

fn (g &NodeGraph) node_index(id int) int {
	for i, n in g.nodes {
		if n.id == id {
			return i
		}
	}
	return -1
}

// nodes - все ноды в порядке отрисовки (последняя - сверху).
pub fn (g &NodeGraph) nodes() []&GraphNode {
	return g.nodes.clone()
}

// raise_node поднимает ноду наверх (в конец порядка отрисовки) - выбранная нода не прячется
// под соседними.
pub fn (mut g NodeGraph) raise_node(id int) {
	widget_changed()
	idx := g.node_index(id)
	if idx < 0 || idx == g.nodes.len - 1 {
		return
	}
	n := g.nodes[idx]
	g.nodes.delete(idx)
	g.nodes << n
}

// set_node_pos - переместить ноду (левый верхний угол, единицы холста).
pub fn (mut g NodeGraph) set_node_pos(id int, x f32, y f32) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	n.x = x
	n.y = y
	return true
}

// set_collapsed - свернуть или развернуть ноду.
pub fn (mut g NodeGraph) set_collapsed(id int, collapsed bool) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	n.collapsed = collapsed
	return true
}

// set_node_title - свой заголовок ноды ('' - вернуть заголовок типа).
pub fn (mut g NodeGraph) set_node_title(id int, title string) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	n.title = title
	return true
}

// set_node_data - строка данных приложения у ноды (граф её не читает, только хранит и сохраняет).
pub fn (mut g NodeGraph) set_node_data(id int, data string) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	n.data = data
	return true
}

// node_title - заголовок ноды для показа: свой, иначе заголовок типа.
pub fn (g &NodeGraph) node_title(id int) string {
	n := g.node(id) or { return '' }
	if n.title != '' {
		return n.title
	}
	t := g.types[n.type_id] or { return n.type_id }
	return t.title
}

// clear - убрать все ноды и связи (типы остаются).
pub fn (mut g NodeGraph) clear() {
	widget_changed()
	g.nodes = []&GraphNode{}
	g.links = []NodeLink{}
}

// ─── Значения ──────────────────────────────────────────

// value - значение поля входа slot ноды node (none - нет такой ноды или входа).
pub fn (g &NodeGraph) value(node int, slot int) ?NodeValue {
	n := g.node(node) or { return none }
	if slot < 0 || slot >= n.values.len {
		return none
	}
	return n.values[slot]
}

// set_value - новое значение поля входа; число зажимается в границы поля, выбор - в список.
pub fn (mut g NodeGraph) set_value(node int, slot int, v NodeValue) bool {
	widget_changed()
	mut n := g.node(node) or { return false }
	t := g.types[n.type_id] or { return false }
	if slot < 0 || slot >= n.values.len || slot >= t.inputs.len {
		return false
	}
	f := t.inputs[slot].field
	mut nv := v
	nv.number = if nv.number < f.min {
		f.min
	} else if nv.number > f.max {
		f.max
	} else {
		nv.number
	}
	if f.choices.len > 0 {
		nv.choice = if nv.choice < 0 {
			0
		} else if nv.choice >= f.choices.len {
			f.choices.len - 1
		} else {
			nv.choice
		}
	}
	n.values[slot] = nv
	return true
}

// ─── Связи ─────────────────────────────────────────────

// links - все связи графа.
pub fn (g &NodeGraph) links() []NodeLink {
	return g.links.clone()
}

// link_into - связь, приходящая на вход slot ноды node.
pub fn (g &NodeGraph) link_into(node int, slot int) ?NodeLink {
	for l in g.links {
		if l.to_node == node && l.to_slot == slot {
			return l
		}
	}
	return none
}

// links_from - связи, выходящие из выхода slot ноды node (с выхода их может быть сколько угодно),
// в порядке создания.
pub fn (g &NodeGraph) links_from(node int, slot int) []NodeLink {
	return g.links.filter(it.from_node == node && it.from_slot == slot)
}

// link_by_id - связь по id.
pub fn (g &NodeGraph) link_by_id(id int) ?NodeLink {
	for l in g.links {
		if l.id == id {
			return l
		}
	}
	return none
}

// types_compatible - выход типа from можно подключить ко входу типа to.
pub fn (g &NodeGraph) types_compatible(from string, to string) bool {
	return from == to || from == '*' || to == '*' || '${from}>${to}' in g.conversions
}

// check_link - можно ли провести связь (from_node.from_slot -> to_node.to_slot). Ошибка с
// причиной: нет ноды/сокета, нода сама с собой, несовместимые типы, цикл, вето приложения.
// Занятый вход ошибкой не считается - connect заменит связь.
pub fn (g &NodeGraph) check_link(from_node int, from_slot int, to_node int, to_slot int) ! {
	if from_node == to_node {
		return error('a node cannot be linked to itself')
	}
	fnode := g.node(from_node) or { return error('no node ${from_node}') }
	tnode := g.node(to_node) or { return error('no node ${to_node}') }
	ft := g.types[fnode.type_id] or { return error('unknown node type') }
	tt := g.types[tnode.type_id] or { return error('unknown node type') }
	if from_slot < 0 || from_slot >= ft.outputs.len {
		return error('no output ${from_slot}')
	}
	if to_slot < 0 || to_slot >= tt.inputs.len {
		return error('no input ${to_slot}')
	}
	from_typ := ft.outputs[from_slot].typ
	to_typ := tt.inputs[to_slot].typ
	if !g.types_compatible(from_typ, to_typ) {
		return error('`${from_typ}` cannot be connected to `${to_typ}`')
	}
	if !g.allow_cycles && g.reaches(to_node, from_node) {
		return error('the link would make a cycle')
	}
	if g.can_connect != unsafe { nil } {
		probe := NodeLink{
			from_node: from_node
			from_slot: from_slot
			to_node:   to_node
			to_slot:   to_slot
		}
		if !g.can_connect(probe) {
			return error('the application rejected the link')
		}
	}
}

// reaches - из ноды start по связям вперёд можно дойти до target (поиск в глубину). Связь
// to -> from замкнула бы цикл, если from уже достижима из to.
fn (g &NodeGraph) reaches(start int, target int) bool {
	mut seen := map[int]bool{}
	mut todo := [start]
	for todo.len > 0 {
		cur := todo.pop()
		if cur == target {
			return true
		}
		if cur in seen {
			continue
		}
		seen[cur] = true
		for l in g.links {
			if l.from_node == cur {
				todo << l.to_node
			}
		}
	}
	return false
}

// NodeConnect - результат connect: новая связь и связь, которую она заменила на занятом входе
// (replaced.id == 0 - вход был свободен). Редактор сообщает о замене событием.
pub struct NodeConnect {
pub:
	link     NodeLink
	replaced NodeLink
}

// connect проводит связь (проверка - check_link). Связь на занятый вход заменяет прежнюю.
// Та же связь, что уже есть, повторно не создаётся (link - она же, replaced пустая).
pub fn (mut g NodeGraph) connect(from_node int, from_slot int, to_node int, to_slot int) !NodeConnect {
	widget_changed()
	g.check_link(from_node, from_slot, to_node, to_slot)!
	mut replaced := NodeLink{}
	if old := g.link_into(to_node, to_slot) {
		if old.from_node == from_node && old.from_slot == from_slot {
			return NodeConnect{
				link: old
			}
		}
		g.disconnect(old.id)
		replaced = old
	}
	l := NodeLink{
		id:        g.next_link
		from_node: from_node
		from_slot: from_slot
		to_node:   to_node
		to_slot:   to_slot
	}
	g.next_link++
	g.links << l
	return NodeConnect{
		link:     l
		replaced: replaced
	}
}

// disconnect удаляет связь по id; false - такой нет.
pub fn (mut g NodeGraph) disconnect(link_id int) bool {
	widget_changed()
	for i, l in g.links {
		if l.id == link_id {
			g.links.delete(i)
			return true
		}
	}
	return false
}

// ─── Порядок вычисления ────────────────────────────────

// eval_order - id нод в порядке вычисления: каждая нода идёт после всех, от чьих выходов зависят
// её входы (топологическая сортировка, алгоритм Кана). Так приложение считает граф: проходит
// список по порядку, и значения входов к моменту ноды уже готовы.
//
// targets - ноды, ради которых считают (например, нода Output): тогда в список входят только
// они и всё, от чего они зависят, - лишние ветки не считаются (как Blender считает шейдер от
// выхода). Без targets - весь граф. Среди готовых к вычислению нод порядок - как в nodes()
// (детерминированно). Ошибка - в графе цикл (возможен только при allow_cycles).
pub fn (g &NodeGraph) eval_order(targets ...int) ![]int {
	// Какие ноды считать: все или только предки целей
	mut wanted := map[int]bool{}
	if targets.len == 0 {
		for n in g.nodes {
			wanted[n.id] = true
		}
	} else {
		mut todo := targets.clone()
		for todo.len > 0 {
			cur := todo.pop()
			if cur in wanted {
				continue
			}
			if _ := g.node(cur) {
				wanted[cur] = true
				for l in g.links {
					if l.to_node == cur {
						todo << l.from_node
					}
				}
			}
		}
	}
	// Число ещё не посчитанных поставщиков у каждой ноды (связи между нужными нодами)
	mut waiting := map[int]int{}
	for id, _ in wanted {
		waiting[id] = 0
	}
	for l in g.links {
		if l.from_node in wanted && l.to_node in wanted {
			waiting[l.to_node]++
		}
	}
	mut order := []int{cap: wanted.len}
	mut done := map[int]bool{}
	for order.len < wanted.len {
		// Первая в порядке nodes() нода, у которой все поставщики посчитаны
		mut next := 0
		for n in g.nodes {
			if n.id in wanted && n.id !in done && waiting[n.id] == 0 {
				next = n.id
				break
			}
		}
		if next == 0 {
			return error('node graph: the graph has a cycle')
		}
		order << next
		done[next] = true
		for l in g.links {
			if l.from_node == next && l.to_node in wanted {
				waiting[l.to_node]--
			}
		}
	}
	return order
}

// ─── Снимки (отмена) ───────────────────────────────────

// NodeGraphState - копия содержимого графа (ноды, связи, счётчики id) для отмены.
struct NodeGraphState {
	nodes     []GraphNode
	links     []NodeLink
	next_node int
	next_link int
}

// snapshot - глубокая копия нод и связей (типы не копируются: они не меняются правками).
fn (g &NodeGraph) snapshot() NodeGraphState {
	mut nodes := []GraphNode{cap: g.nodes.len}
	for n in g.nodes {
		mut c := *n
		c.values = n.values.clone()
		nodes << c
	}
	return NodeGraphState{
		nodes:     nodes
		links:     g.links.clone()
		next_node: g.next_node
		next_link: g.next_link
	}
}

// restore - вернуть граф к снимку. Ноды создаются заново (снимок не должен меняться правками
// после восстановления - его ещё раз восстановит redo/undo).
fn (mut g NodeGraph) restore(s NodeGraphState) {
	widget_changed()
	mut nodes := []&GraphNode{cap: s.nodes.len}
	for n in s.nodes {
		mut c := &GraphNode{
			...n
		}
		c.values = n.values.clone()
		nodes << c
	}
	g.nodes = nodes
	g.links = s.links.clone()
	g.next_node = s.next_node
	g.next_link = s.next_link
}

// ─── JSON ──────────────────────────────────────────────

// Формат сохранения (версия 1):
//   {"version":1,
//    "nodes":[{"id":1,"type":"add","x":10,"y":20,"collapsed":false,
//              "values":[{"number":0.5,"flag":false,"color":[200,200,200,255],"choice":0}],
//              "title":"","data":""}],
//    "links":[{"id":1,"from":1,"out":0,"to":2,"in":1}]}
// Типы не сохраняются: их описывает приложение кодом. title и data появились позже: в старых
// сохранениях их нет, и они читаются пустыми.

struct NodeValueJson {
	number f64
	flag   bool
	color  []int
	choice int
}

struct GraphNodeJson {
	id        int
	typ       string @[json: 'type']
	x         f32
	y         f32
	collapsed bool
	values    []NodeValueJson
	title     string
	data      string
}

struct NodeLinkJson {
	id        int
	from_node int @[json: 'from']
	from_slot int @[json: 'out']
	to_node   int @[json: 'to']
	to_slot   int @[json: 'in']
}

struct NodeGraphJson {
mut:
	version int
	nodes   []GraphNodeJson
	links   []NodeLinkJson
}

// to_json - граф строкой JSON.
pub fn (g &NodeGraph) to_json() string {
	mut doc := NodeGraphJson{
		version: 1
	}
	for n in g.nodes {
		doc.nodes << GraphNodeJson{
			id:        n.id
			typ:       n.type_id
			x:         n.x
			y:         n.y
			collapsed: n.collapsed
			title:     n.title
			data:      n.data
			values:    n.values.map(NodeValueJson{
				number: it.number
				flag:   it.flag
				color:  [int(it.color.r), int(it.color.g), int(it.color.b), int(it.color.a)]
				choice: it.choice
			})
		}
	}
	for l in g.links {
		doc.links << NodeLinkJson{
			id:        l.id
			from_node: l.from_node
			from_slot: l.from_slot
			to_node:   l.to_node
			to_slot:   l.to_slot
		}
	}
	return json2.encode(doc)
}

// load_json заменяет ноды и связи графа содержимым JSON (типы должны быть уже описаны).
// Ноды неизвестных типов и связи, не проходящие проверку типов, пропускаются; значения входов,
// которых в сохранении нет (тип ноды с тех пор дополнен), - по умолчанию. Ошибка - текст не
// JSON графа; граф при этом не меняется.
pub fn (mut g NodeGraph) load_json(text string) ! {
	widget_changed()
	doc := json2.decode[NodeGraphJson](text) or { return error('node graph: ${err.msg()}') }
	if doc.version != 1 {
		return error('node graph: unsupported version ${doc.version}')
	}
	before := g.snapshot()
	g.nodes = []&GraphNode{}
	g.links = []NodeLink{}
	mut max_node := 0
	for jn in doc.nodes {
		t := g.types[jn.typ] or { continue }
		if jn.id <= 0 || g.node_index(jn.id) >= 0 {
			continue // повторный или битый id
		}
		mut values := t.inputs.map(node_default_value(it.field))
		for i, jv in jn.values {
			if i >= values.len {
				break
			}
			values[i] = NodeValue{
				number: jv.number
				flag:   jv.flag
				color:  node_json_color(jv.color, values[i].color)
				choice: jv.choice
			}
		}
		g.nodes << &GraphNode{
			id:        jn.id
			type_id:   jn.typ
			x:         jn.x
			y:         jn.y
			collapsed: jn.collapsed
			values:    values
			title:     jn.title
			data:      jn.data
		}
		max_node = if jn.id > max_node { jn.id } else { max_node }
	}
	g.next_node = max_node + 1
	// Связи проводятся через check_link: битое сохранение не даёт графа, который нельзя
	// построить руками (цикл, несовместимые типы, второй провод на вход)
	saved_veto := g.can_connect
	g.can_connect = unsafe { nil } // вето приложения - для правок пользователя, не для загрузки
	mut max_link := 0
	for jl in doc.links {
		g.check_link(jl.from_node, jl.from_slot, jl.to_node, jl.to_slot) or { continue }
		if _ := g.link_into(jl.to_node, jl.to_slot) {
			continue
		}
		g.links << NodeLink{
			id:        jl.id
			from_node: jl.from_node
			from_slot: jl.from_slot
			to_node:   jl.to_node
			to_slot:   jl.to_slot
		}
		max_link = if jl.id > max_link { jl.id } else { max_link }
	}
	g.can_connect = saved_veto
	g.next_link = max_link + 1
	if g.nodes.len == 0 && doc.nodes.len > 0 {
		// Ни одной известной ноды - вероятно, не тот граф: вернуть прежнее
		g.restore(before)
		return error('node graph: no node of a known type')
	}
}

// node_json_color - цвет из массива [r, g, b, a]; иначе - fallback.
fn node_json_color(c []int, fallback Color) Color {
	if c.len != 4 {
		return fallback
	}
	return Color{u8(clamp_int(c[0], 0, 255)), u8(clamp_int(c[1], 0, 255)), u8(clamp_int(c[2],
		0, 255)), u8(clamp_int(c[3], 0, 255))}
}
