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
//     преобразование, объявленное приложением (allow_conversion - например, float в color;
//     type converters в Qt Nodes);
//   - вето приложения на новую связь - can_connect (isValidConnection в React Flow, accept/reject
//     в imgui-node-editor);
//   - циклы по умолчанию запрещены (граф шейдеров - DAG); allow_cycles разрешает;
//   - на вход - одна связь (новая заменяет старую), с выхода - сколько угодно (как в Qt Nodes).
//
// Перерисовка: каждый изменяющий метод графа первой строкой зовёт widget_changed() (PROJECT.md,
// «Инвалидация и dirty regions») - правка кодом видна сразу, в том числе из своего цикла. Прямое
// присваивание полей GraphNode (n.x = ...) этого не делает: для позиции, свёрнутости, заголовка и
// данных есть сеттеры (set_node_pos, set_collapsed, set_node_title, set_node_data).
//
// Значения полей входов (число, флажок, цвет, выбор) хранятся в ноде (GraphNode.values, по одному
// на вход); у подключённого входа поле не показывается, но значение сохраняется. Снимки для отмены
// (snapshot / restore) - копия нод и связей: команды UndoStack восстанавливают граф целиком.

// SocketShape - форма значка сокета (например, круг - значение, ромб - поле; смысл форм задаёт
// приложение).
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
// добавления), цвет шапки (альфа 0 - цвет шапки из темы, Theme.ne_header_bg / CSS
// `nodes { header-background }`), ширина карточки по умолчанию (в единицах холста), входы и выходы.
// min_width/max_width - пределы ширины, которую пользователь задаёт, перетаскивая край ноды
// (max_width = 0 - без верхнего предела).
pub struct NodeTypeDef {
pub mut:
	id        string
	title     string
	category  string
	color     Color = Color{0, 0, 0, 0} // явная альфа 0: у Color по умолчанию a = 255
	width     f32   = 150
	min_width f32   = 80
	max_width f32
	inputs    []NodeSocketDef
	outputs   []NodeSocketDef
	// grow_input - шаблон входа, который пользователь добавляет ноде строкой «+» внизу карточки
	// (нода «Объединить» с растущим числом входов; node_sockets.v). typ = '' - строки нет.
	// В имени {n} заменяется номером входа.
	grow_input NodeSocketDef
	// body_height - место под своё содержимое (превью, график) ниже строк сокетов, в единицах
	// холста; рисует его приложение (NodeEditor.set_body_painter, node_body.v). 0 - места нет.
	body_height f32
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
// свёрнута ли, значения полей входов (по одному на вход типа), свои ширина и высота.
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
	// width - своя ширина ноды (пользователь потянул край; 0 - ширина типа). Читать - node_width.
	width f32
	// height - своя высота (0 - по содержимому). Меньше содержимого (шапка и строки сокетов) не
	// бывает: лишнее место - пустое поле внизу карточки. Читать - node_height.
	height f32
	// Свои сокеты этой ноды - после сокетов типа (node_sockets.v: add_input / add_output).
	// Полный список сокетов ноды - def_of. Значения своих входов - в values после входов типа.
	extra_inputs  []NodeSocketDef
	extra_outputs []NodeSocketDef
	// group - внутренний граф ноды-группы (node_group.v; у остальных нод nil). Снимки отмены
	// делят его с живой нодой (правки внутри - свои команды), копии нод - клонируют.
	group &NodeGraph = unsafe { nil }
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
	frames       []&NodeFrame // рамки-группы (node_frame.v), в порядке отрисовки
	next_node    int = 1
	next_link    int = 1
	next_frame   int = 1
}

// node_graph - пустой граф без типов.
pub fn node_graph() &NodeGraph {
	mut g := &NodeGraph{}
	// Встроенный тип reroute-точки (node_reroute.v): в типах есть всегда - его ноды загружаются
	// из JSON и вставляются из буфера, как любые; в type_order его нет - меню его не показывает
	g.types[node_reroute_type] = NodeTypeDef{
		id:        node_reroute_type
		title:     'Reroute'
		width:     ne_reroute_size
		min_width: ne_reroute_size
		max_width: ne_reroute_size
		inputs:    [node_socket('', '*')]
		outputs:   [node_socket('', '*')]
	}
	// Встроенные типы групп (node_group.v): сокеты у них только свои (extra_*), их задаёт
	// группировка
	g.types[node_group_type] = NodeTypeDef{
		id:    node_group_type
		title: 'Group'
		color: Color{60, 110, 90, 255}
		width: 160
	}
	g.types[node_group_in_type] = NodeTypeDef{
		id:    node_group_in_type
		title: 'Group Input'
		color: Color{70, 70, 80, 255}
	}
	g.types[node_group_out_type] = NodeTypeDef{
		id:    node_group_out_type
		title: 'Group Output'
		color: Color{70, 70, 80, 255}
	}
	return g
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

// node_width - ширина ноды на холсте: своя (если задана), иначе ширина типа.
pub fn (g &NodeGraph) node_width(id int) f32 {
	n := g.node(id) or { return 0 }
	return g.width_of(n)
}

// width_of - ширина ноды по её записи (без поиска по id; для отрисовки и попадания).
fn (g &NodeGraph) width_of(n &GraphNode) f32 {
	if n.type_id == node_reroute_type {
		return ne_reroute_size
	}
	if n.width > 0 {
		return n.width
	}
	t := g.types[n.type_id] or { return 150 }
	return t.width
}

// node_height - высота ноды на холсте: у свёрнутой - шапка, иначе своя (если задана), но не
// меньше содержимого.
pub fn (g &NodeGraph) node_height(id int) f32 {
	n := g.node(id) or { return 0 }
	return g.height_of(n)
}

// height_of - высота ноды по её записи (для отрисовки и попадания).
fn (g &NodeGraph) height_of(n &GraphNode) f32 {
	if n.type_id == node_reroute_type {
		return ne_reroute_size
	}
	if n.collapsed {
		return ne_header_h
	}
	return max_f32(n.height, g.content_height(n))
}

// content_height - наименьшая высота развёрнутой ноды: шапка, строка на каждый выход и вход и
// поле снизу. Константы геометрии (ne_header_h, ne_row_h, ne_pad_bottom) - в node_editor.v:
// высоту модели и вида считает одна формула.
fn (g &NodeGraph) content_height(n &GraphNode) f32 {
	if n.type_id !in g.types {
		return ne_header_h
	}
	t := g.types[n.type_id] or { NodeTypeDef{} }
	return ne_header_h + f32(g.row_count(n)) * ne_row_h + t.body_height + ne_pad_bottom
}

// set_node_height - высота ноды (0 и меньше - по содержимому). Меньше содержимого не
// становится: зажимается снизу. Как и у ширины, верхний край не двигается. false - ноды нет.
pub fn (mut g NodeGraph) set_node_height(id int, h f32) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	n.height = if h <= 0 { f32(0) } else { max_f32(h, g.content_height(n)) }
	return true
}

// set_node_width - ширина ноды (0 - вернуть ширину типа). Значение зажимается в
// min_width..max_width типа. Левый верхний угол не двигается - тянуть левый край (сдвигая и x)
// - забота вида. Возвращает false, если ноды нет.
pub fn (mut g NodeGraph) set_node_width(id int, w f32) bool {
	widget_changed()
	mut n := g.node(id) or { return false }
	if w <= 0 {
		n.width = 0
		return true
	}
	t := g.types[n.type_id] or { return false }
	n.width = node_clamp_width(t, w)
	return true
}

// node_clamp_width - ширина в пределах типа (нижний предел не меньше 20: ноду не сжать в линию).
fn node_clamp_width(t NodeTypeDef, w f32) f32 {
	lo := max_f32(t.min_width, 20)
	mut r := max_f32(w, lo)
	if t.max_width > 0 {
		r = min_f32(r, max_f32(t.max_width, lo))
	}
	return r
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
	g.frames = []&NodeFrame{}
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
	t := g.def_of(n)
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
	if fnode.type_id !in g.types || tnode.type_id !in g.types {
		return error('unknown node type')
	}
	// Сокеты ноды - тип и её собственные (def_of)
	ft := g.def_of(fnode)
	tt := g.def_of(tnode)
	if from_slot < 0 || from_slot >= ft.outputs.len {
		return error('no output ${from_slot}')
	}
	if to_slot < 0 || to_slot >= tt.inputs.len {
		return error('no input ${to_slot}')
	}
	// Типы - сквозь reroute-точки (node_reroute.v): у точки нет своего типа, выход несёт тип
	// того, что в неё входит, а вход должен подходить всем, кого точка питает
	from_typ := g.out_type(from_node, from_slot)
	for to_typ in g.in_types(to_node, to_slot) {
		if !g.types_compatible(from_typ, to_typ) {
			return error('`${from_typ}` cannot be connected to `${to_typ}`')
		}
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
// они и всё, от чего они зависят, - лишние ветки не считаются. Без targets - весь граф. Среди
// готовых к вычислению нод порядок - как в nodes() (детерминированно). Ошибка - в графе цикл (возможен только при allow_cycles).
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
	nodes      []GraphNode
	links      []NodeLink
	frames     []NodeFrame
	next_node  int
	next_link  int
	next_frame int
}

// snapshot - глубокая копия нод, связей и фреймов (типы не копируются: они не меняются правками).
fn (g &NodeGraph) snapshot() NodeGraphState {
	mut nodes := []GraphNode{cap: g.nodes.len}
	for n in g.nodes {
		mut c := *n
		// Массивы - копией, как и values: снимок не должен делить память с живой нодой, что бы с
		// её массивами ни делали дальше (сейчас delete в V и так выделяет новую память - это
		// проверено мутацией, - но на это поведение снимок не полагается)
		c.values = n.values.clone()
		c.extra_inputs = n.extra_inputs.clone()
		c.extra_outputs = n.extra_outputs.clone()
		nodes << c
	}
	return NodeGraphState{
		nodes:      nodes
		links:      g.links.clone()
		frames:     g.frames.map(*it)
		next_node:  g.next_node
		next_link:  g.next_link
		next_frame: g.next_frame
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
		c.extra_inputs = n.extra_inputs.clone()
		c.extra_outputs = n.extra_outputs.clone()
		nodes << c
	}
	g.nodes = nodes
	g.links = s.links.clone()
	// Фреймы - тоже заново (снимок не делит с графом ни одной записи)
	g.frames = s.frames.map(&NodeFrame{
		...it
	})
	g.next_node = s.next_node
	g.next_link = s.next_link
	g.next_frame = s.next_frame
}

// ─── JSON ──────────────────────────────────────────────

// Формат сохранения (версия 1):
//   {"version":1,
//    "nodes":[{"id":1,"type":"add","x":10,"y":20,"collapsed":false,
//              "values":[{"number":0.5,"flag":false,"color":[200,200,200,255],"choice":0}],
//              "title":"","data":"","width":0,"height":0}],
//    "links":[{"id":1,"from":1,"out":0,"to":2,"in":1}]}
// Типы не сохраняются: их описывает приложение кодом. title и data появились позже: в старых
// сохранениях их нет, и они читаются пустыми. width и height (свои размеры, 0 - по типу и
// содержимому) - тоже позже.
// Новые поля добавляются так, чтобы старые сохранения читались, - версия остаётся 1.

struct NodeValueJson {
	number f64
	flag   bool
	color  []int
	choice int
}

struct GraphNodeJson {
mut:
	id        int
	typ       string @[json: 'type']
	x         f32
	y         f32
	collapsed bool
	values    []NodeValueJson
	title     string
	data      string
	width     f32
	height    f32
	// Свои сокеты ноды (node_sockets.v); в старых сохранениях их нет - пусто
	extra_inputs  []NodeSocketJson
	extra_outputs []NodeSocketJson
	// Внутренний граф группы (node_group.v) - строкой JSON того же формата: вложенная структура
	// сделала бы тип рекурсивным, а декодер x.json2 разворачивает типы при компиляции
	group string
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
	frames  []NodeFrameJson // появились позже: в старых сохранениях их нет - пусто
}

// to_json - граф строкой JSON.
pub fn (g &NodeGraph) to_json() string {
	mut doc := NodeGraphJson{
		version: 1
	}
	for n in g.nodes {
		doc.nodes << node_to_json(n)
	}
	for l in g.links {
		doc.links << link_to_json(l)
	}
	for fr in g.frames {
		doc.frames << frame_to_json(fr)
	}
	return json2.encode(doc)
}

fn node_to_json(n &GraphNode) GraphNodeJson {
	return GraphNodeJson{
		id:            n.id
		typ:           n.type_id
		x:             n.x
		y:             n.y
		collapsed:     n.collapsed
		title:         n.title
		data:          n.data
		width:         n.width
		height:        n.height
		extra_inputs:  n.extra_inputs.map(socket_to_json(it))
		extra_outputs: n.extra_outputs.map(socket_to_json(it))
		group:         if isnil(n.group) { '' } else { n.group.to_json() }
		values:        n.values.map(NodeValueJson{
			number: it.number
			flag:   it.flag
			color:  [int(it.color.r), int(it.color.g), int(it.color.b), int(it.color.a)]
			choice: it.choice
		})
	}
}

fn link_to_json(l NodeLink) NodeLinkJson {
	return NodeLinkJson{
		id:        l.id
		from_node: l.from_node
		from_slot: l.from_slot
		to_node:   l.to_node
		to_slot:   l.to_slot
	}
}

// node_from_json - нода из записи JSON с id = id (при загрузке - id из записи, при вставке -
// новый). none - тип ноды не описан. Значения входов, которых в записи нет (тип с тех пор
// дополнен), - по умолчанию; ширина - в пределах типа, высота - не меньше содержимого.
fn (g &NodeGraph) node_from_json(jn GraphNodeJson, id int) ?&GraphNode {
	t := g.types[jn.typ] or { return none }
	// Свои сокеты ноды - до значений: значения идут по всем входам, типа и своим
	extra_in := jn.extra_inputs.map(socket_from_json(it))
	extra_out := jn.extra_outputs.map(socket_from_json(it))
	mut inputs := t.inputs.clone()
	inputs << extra_in
	mut values := inputs.map(node_default_value(it.field))
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
	mut n := &GraphNode{
		id:            id
		type_id:       jn.typ
		x:             jn.x
		y:             jn.y
		collapsed:     jn.collapsed
		values:        values
		title:         jn.title
		data:          jn.data
		width:         if jn.width > 0 { node_clamp_width(t, jn.width) } else { 0 }
		extra_inputs:  extra_in
		extra_outputs: extra_out
	}
	if jn.height > 0 {
		n.height = max_f32(jn.height, g.content_height(n))
	}
	if jn.group != '' {
		// Внутренний граф группы: типы - общие с этим графом; не читается - группа пустая
		mut inner := g.new_child()
		inner.load_json(jn.group) or {}
		n.group = inner
	}
	return n
}

// ─── Буфер обмена: часть графа ─────────────────────────

// copy_json - выбранные ноды ids и связи между ними строкой JSON того же формата, что to_json
// (её можно и загрузить load_json, и вставить paste_json). Связи с нодами вне выбора не
// попадают: у вставленной копии им не к чему подключиться. Строка данных приложения (data) не
// копируется - там может быть ссылка на объект приложения, и две ноды делили бы его (как и в
// NodeEditor.duplicate_selected). Несуществующие id пропускаются.
pub fn (g &NodeGraph) copy_json(ids []int) string {
	mut doc := NodeGraphJson{
		version: 1
	}
	mut chosen := map[int]bool{}
	for n in g.nodes {
		if n.id in ids {
			mut jn := node_to_json(n)
			jn.data = ''
			doc.nodes << jn
			chosen[n.id] = true
		}
	}
	for l in g.links {
		if l.from_node in chosen && l.to_node in chosen {
			doc.links << link_to_json(l)
		}
	}
	return json2.encode(doc)
}

// NodePaste - итог paste_json: id вставленных нод (в порядке записи) и проведённые связи.
pub struct NodePaste {
pub:
	nodes []int
	links []NodeLink
}

// paste_json добавляет к графу ноды и связи из JSON (copy_json или to_json) с новыми id: левый
// верхний угол рамки вокруг вставленных нод встаёт в точку холста (at_x, at_y), взаимное
// расположение сохраняется. Это правка пользователя, а не загрузка: связи проводятся через
// connect - с вето приложения (can_connect) и проверкой циклов. Ноды неизвестных типов и связи,
// не прошедшие проверку, пропускаются. Ошибка - текст не JSON графа или в нём ни одной ноды
// известного типа; граф при этом не меняется.
pub fn (mut g NodeGraph) paste_json(text string, at_x f32, at_y f32) !NodePaste {
	doc := json2.decode[NodeGraphJson](text) or { return error('node graph: ${err.msg()}') }
	if doc.version != 1 {
		return error('node graph: unsupported version ${doc.version}')
	}
	// Сначала - только ноды известных типов: рамка считается по тем, что будут вставлены
	mut known := []GraphNodeJson{}
	for jn in doc.nodes {
		if jn.typ in g.types {
			known << jn
		}
	}
	if known.len == 0 {
		return error('node graph: no node of a known type')
	}
	widget_changed()
	mut min_x, mut min_y := known[0].x, known[0].y
	for jn in known {
		min_x = min_f32(min_x, jn.x)
		min_y = min_f32(min_y, jn.y)
	}
	// Новые id: старый id из буфера -> id в этом графе
	mut new_id := map[int]int{}
	mut added := []int{}
	for jn in known {
		mut n := g.node_from_json(jn, g.next_node) or { continue }
		n.x = jn.x - min_x + at_x
		n.y = jn.y - min_y + at_y
		g.nodes << n
		g.next_node++
		new_id[jn.id] = n.id
		added << n.id
	}
	mut links := []NodeLink{}
	for jl in doc.links {
		from := new_id[jl.from_node] or { continue }
		to := new_id[jl.to_node] or { continue }
		res := g.connect(from, jl.from_slot, to, jl.to_slot) or { continue }
		links << res.link
	}
	return NodePaste{
		nodes: added
		links: links
	}
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
		if jn.id <= 0 || g.node_index(jn.id) >= 0 {
			continue // повторный или битый id
		}
		n := g.node_from_json(jn, jn.id) or { continue } // тип не описан
		g.nodes << n
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
	g.load_frames_json(doc.frames)
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
