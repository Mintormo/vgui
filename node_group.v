module vgui

// Файл node_group.v: группы нод - несколько нод, свёрнутых в одну ноду со своим внутренним
// графом (Node Groups в Blender, свёрнутые подграфы в Houdini/Unreal).
//
// Модель. Группа - нода встроенного типа node_group_type с полем group - внутренним графом. Внутри
// - ноды Group Input (её выходы - входы группы) и Group Output (её входы - выходы группы). Сокеты
// всех трёх - свои сокеты нод (extra_*, node_sockets.v), их задаёт группировка: каждая связь,
// пересекавшая границу выделения, становится сокетом группы (один на каждый внешний выход, как в
// Blender: две связи из одного выхода - один вход группы). Типы (описания нод, сокетов,
// преобразований) у внутреннего графа - копия типов внешнего (new_child) и обновляются при входе
// в группу (sync_types).
//
// Отмена: снимок внешнего графа держит ноду-группу с тем же указателем на внутренний граф, а
// правки внутри - свои команды над внутренним графом (NodeEditor помнит, к какому графу команда).
// Группировка и разгруппировка внутренний граф не меняют (разгруппировка копирует его ноды),
// поэтому отмена возвращает группу целой. Копии нод (дублирование, вставка, JSON) клонируют
// внутренний граф.
//
// Вид (NodeEditor): Ctrl+G - сгруппировать выделенное, Ctrl+Alt+G - разгруппировать, Tab - войти в
// выбранную группу / выйти; путь от корня - строкой вверху редактора.
// Раздел PROJECT.md - «NodeEditor: редактор графа из нод», «Группы нод».

pub const node_group_type = '@group'
pub const node_group_in_type = '@group_in'
pub const node_group_out_type = '@group_out'

// ─── Модель ────────────────────────────────────────────

// new_child - пустой граф с копией типов этого (для внутреннего графа группы).
fn (g &NodeGraph) new_child() &NodeGraph {
	mut c := &NodeGraph{
		allow_cycles: g.allow_cycles
	}
	c.sync_types(g)
	return c
}

// sync_types - типы, типы сокетов и преобразования - как у from (вложенные группы - тоже):
// внутренний граф видит типы, описанные во внешнем после группировки.
fn (mut g NodeGraph) sync_types(from &NodeGraph) {
	g.socket_types = from.socket_types.clone()
	g.conversions = from.conversions.clone()
	g.types = from.types.clone()
	g.type_order = from.type_order.clone()
	for n in g.nodes {
		if !isnil(n.group) {
			mut inner := n.group
			inner.sync_types(g)
		}
	}
}

// clone_graph - глубокая копия графа (ноды, связи, фреймы, вложенные группы); типы - копией.
pub fn (g &NodeGraph) clone_graph() &NodeGraph {
	mut c := g.new_child()
	c.can_connect = g.can_connect
	c.restore(g.snapshot())
	for mut n in c.nodes {
		if !isnil(n.group) {
			n.group = n.group.clone_graph()
		}
	}
	return c
}

// is_group - нода id - группа.
pub fn (g &NodeGraph) is_group(id int) bool {
	n := g.node(id) or { return false }
	return n.type_id == node_group_type && !isnil(n.group)
}

// group_graph - внутренний граф группы id (none - это не группа).
pub fn (g &NodeGraph) group_graph(id int) ?&NodeGraph {
	n := g.node(id) or { return none }
	if n.type_id != node_group_type || isnil(n.group) {
		return none
	}
	return n.group
}

// group_io - id нод Group Input и Group Output внутри графа группы (0 - нет). Вход k группы -
// выход k Group Input, выход k группы - вход k Group Output: так приложение, считающее граф,
// передаёт значения внутрь и забирает наружу.
pub fn (g &NodeGraph) group_io() (int, int) {
	mut gin, mut gout := 0, 0
	for n in g.nodes {
		if n.type_id == node_group_in_type {
			gin = n.id
		} else if n.type_id == node_group_out_type {
			gout = n.id
		}
	}
	return gin, gout
}

// is_group_io - нода id - Group Input или Group Output (их нельзя удалить или скопировать: без них
// группа теряет свои сокеты).
pub fn (g &NodeGraph) is_group_io(id int) bool {
	n := g.node(id) or { return false }
	return n.type_id in [node_group_in_type, node_group_out_type]
}

// NodeGroupSocket - сокет группы при группировке: внешний выход-источник (для входа группы) или
// внутренний выход (для выхода группы), имя и тип.
struct NodeGroupSocket {
	node int
	slot int
	name string
	typ  string
}

// group_nodes сворачивает ноды ids в группу с заголовком title; возвращает id ноды-группы.
// Связи внутри выделения уходят внутрь; каждая связь через границу становится сокетом группы:
// внешний выход -> вход группы (одна пара на каждый внешний выход) и выход группы -> внешний вход
// (одна пара на каждый внутренний выход). Group Input / Output встают слева и справа от нод,
// группа - в середину их рамки. Ошибка - среди ids нет ни одной ноды, которую можно группировать
// (Group Input / Output не группируются).
pub fn (mut g NodeGraph) group_nodes(ids []int, title string) !int {
	mut chosen := map[int]bool{}
	for n in g.nodes {
		if n.id in ids && n.type_id !in [node_group_in_type, node_group_out_type] {
			chosen[n.id] = true
		}
	}
	if chosen.len == 0 {
		return error('node graph: nothing to group')
	}
	widget_changed()
	// Сокеты группы по связям через границу
	mut ins := []NodeGroupSocket{}
	mut outs := []NodeGroupSocket{}
	for l in g.links {
		from_in, to_in := l.from_node in chosen, l.to_node in chosen
		if !from_in && to_in && !ins.any(it.node == l.from_node && it.slot == l.from_slot) {
			to := g.node(l.to_node) or { continue }
			ins << NodeGroupSocket{l.from_node, l.from_slot, g.def_of(to).inputs[l.to_slot].name, g.out_type(l.from_node,
				l.from_slot)}
		}
		if from_in && !to_in && !outs.any(it.node == l.from_node && it.slot == l.from_slot) {
			from := g.node(l.from_node) or { continue }
			outs << NodeGroupSocket{l.from_node, l.from_slot, g.def_of(from).outputs[l.from_slot].name, g.out_type(l.from_node,
				l.from_slot)}
		}
	}
	// Внутренний граф: сами ноды (с прежними id), связи между ними
	mut inner := g.new_child()
	inner.can_connect = g.can_connect
	mut x0, mut y0, mut x1, mut y1 := f32(1.0e9), f32(1.0e9), f32(-1.0e9), f32(-1.0e9)
	mut max_id := 0
	for n in g.nodes {
		if n.id in chosen {
			inner.nodes << n
			max_id = max_int(max_id, n.id)
			x0 = min_f32(x0, n.x)
			y0 = min_f32(y0, n.y)
			x1 = max_f32(x1, n.x + g.width_of(n))
			y1 = max_f32(y1, n.y + g.height_of(n))
		}
	}
	inner.next_node = max_id + 1
	for l in g.links {
		if l.from_node in chosen && l.to_node in chosen {
			inner.add_link_raw(l.from_node, l.from_slot, l.to_node, l.to_slot)
		}
	}
	cy := (y0 + y1) * 0.5
	gin := inner.add_node(node_group_in_type, x0 - 220, cy - 40) or { 0 }
	gout := inner.add_node(node_group_out_type, x1 + 70, cy - 40) or { 0 }
	mut gin_node := inner.node(gin) or { return error('node graph: group input') }
	mut gout_node := inner.node(gout) or { return error('node graph: group output') }
	gin_node.extra_outputs = ins.map(node_socket(it.name, it.typ))
	gout_node.extra_inputs = outs.map(node_socket(it.name, it.typ))
	gout_node.values = outs.map(NodeValue{})
	for l in g.links {
		if l.from_node !in chosen && l.to_node in chosen {
			k := ins.index(ins.filter(it.node == l.from_node && it.slot == l.from_slot)[0])
			inner.add_link_raw(gin, k, l.to_node, l.to_slot)
		}
	}
	for k, o in outs {
		inner.add_link_raw(o.node, o.slot, gout, k)
	}
	// Снаружи: нода-группа вместо выделения, связи через границу - к её сокетам
	old_links := g.links.clone()
	g.nodes = g.nodes.filter(it.id !in chosen)
	g.links = g.links.filter(it.from_node !in chosen && it.to_node !in chosen)
	gid := g.add_node(node_group_type, (x0 + x1) * 0.5 - 80, cy - 40)!
	mut gnode := g.node(gid) or { return error('node graph: group node') }
	gnode.group = inner
	gnode.title = title
	gnode.extra_inputs = ins.map(node_socket(it.name, it.typ))
	gnode.extra_outputs = outs.map(node_socket(it.name, it.typ))
	gnode.values = ins.map(NodeValue{})
	for k, i in ins {
		g.add_link_raw(i.node, i.slot, gid, k)
	}
	for l in old_links {
		if l.from_node in chosen && l.to_node !in chosen {
			k := outs.index(outs.filter(it.node == l.from_node && it.slot == l.from_slot)[0])
			g.add_link_raw(gid, k, l.to_node, l.to_slot)
		}
	}
	return gid
}

// ungroup разворачивает группу id обратно: копии внутренних нод (с новыми id этого графа) встают
// на место группы, внутренние связи переносятся, связи через Group Input / Output соединяются
// напрямую с внешними. Внутренний граф не меняется (его держит снимок отмены). Возвращает id
// новых нод. Ошибка - это не группа.
pub fn (mut g NodeGraph) ungroup(id int) ![]int {
	gnode := g.node(id) or { return error('node graph: no node ${id}') }
	if gnode.type_id != node_group_type || isnil(gnode.group) {
		return error('node graph: node ${id} is not a group')
	}
	widget_changed()
	inner := gnode.group
	gin, gout := inner.group_io()
	// Сдвиг: середина внутренних нод - в середину ноды-группы
	mut x0, mut y0, mut x1, mut y1 := f32(1.0e9), f32(1.0e9), f32(-1.0e9), f32(-1.0e9)
	for n in inner.nodes {
		if n.id in [gin, gout] {
			continue
		}
		x0 = min_f32(x0, n.x)
		y0 = min_f32(y0, n.y)
		x1 = max_f32(x1, n.x + inner.width_of(n))
		y1 = max_f32(y1, n.y + inner.height_of(n))
	}
	dx := gnode.x + g.width_of(gnode) * 0.5 - (x0 + x1) * 0.5
	dy := gnode.y + g.height_of(gnode) * 0.5 - (y0 + y1) * 0.5
	// Копии нод с новыми id
	mut new_id := map[int]int{}
	mut added := []int{}
	for n in inner.nodes {
		if n.id in [gin, gout] {
			continue
		}
		mut c := &GraphNode{
			...*n
			id: g.next_node
			x:  n.x + dx
			y:  n.y + dy
		}
		c.values = n.values.clone()
		c.extra_inputs = n.extra_inputs.clone()
		c.extra_outputs = n.extra_outputs.clone()
		if !isnil(n.group) {
			c.group = n.group.clone_graph()
		}
		g.next_node++
		g.nodes << c
		new_id[n.id] = c.id
		added << c.id
	}
	// Внешние источники входов группы: вход k -> (нода, выход) снаружи
	mut outer_src := map[int]NodeLink{}
	for l in g.links {
		if l.to_node == id {
			outer_src[l.to_slot] = l
		}
	}
	// Источник внутренней связи снаружи: обычная нода - её копия; Group Input k - внешний
	// источник входа k группы (none - вход группы не подключён)
	for l in inner.links {
		if l.to_node == gout {
			continue // выходы группы - ниже
		}
		to := new_id[l.to_node] or { continue }
		if l.from_node == gin {
			src := outer_src[l.from_slot] or { continue }
			g.add_link_raw(src.from_node, src.from_slot, to, l.to_slot)
		} else if from := new_id[l.from_node] {
			g.add_link_raw(from, l.from_slot, to, l.to_slot)
		}
	}
	// Выходы группы: внутренний источник входа k Group Output -> все внешние цели выхода k
	for l in inner.links {
		if l.to_node != gout {
			continue
		}
		mut src_node, mut src_slot := 0, 0
		if l.from_node == gin {
			src := outer_src[l.from_slot] or { continue }
			src_node, src_slot = src.from_node, src.from_slot
		} else {
			src_node = new_id[l.from_node] or { continue }
			src_slot = l.from_slot
		}
		for ol in g.links.clone() {
			if ol.from_node == id && ol.from_slot == l.to_slot {
				g.add_link_raw(src_node, src_slot, ol.to_node, ol.to_slot)
			}
		}
	}
	g.nodes = g.nodes.filter(it.id != id)
	g.links = g.links.filter(it.from_node != id && it.to_node != id)
	return added
}

// add_link_raw - связь без проверок (перестройка графа группировкой: связи уже были корректными,
// и вето приложения на перенос не спрашивается).
fn (mut g NodeGraph) add_link_raw(from_node int, from_slot int, to_node int, to_slot int) {
	g.links << NodeLink{
		id:        g.next_link
		from_node: from_node
		from_slot: from_slot
		to_node:   to_node
		to_slot:   to_slot
	}
	g.next_link++
}

// ─── Вид и ввод (методы NodeEditor) ────────────────────

// NodeGroupLevel - уровень пути вглубь групп: граф уровня, нода-группа, через которую вошли
// глубже, и вид уровня (вернуть его при выходе).
struct NodeGroupLevel {
	graph  &NodeGraph
	node   int
	view_x f32
	view_y f32
	zoom   f32
}

// root_graph - корневой граф редактора (тот, что передали в node_editor).
pub fn (ne &NodeEditor) root_graph() &NodeGraph {
	return if ne.group_path.len > 0 { ne.group_path[0].graph } else { ne.graph }
}

// enter_group - показать внутренний граф группы id (Tab): типы внутреннего графа обновляются
// из текущего, выделение снимается, вид подгоняется под содержимое.
pub fn (mut ne NodeEditor) enter_group(id int) {
	mut inner := ne.graph.group_graph(id) or { return }
	widget_changed()
	ne.cancel_gesture()
	ne.cancel_text_edit()
	inner.sync_types(ne.graph)
	ne.group_path << NodeGroupLevel{
		graph:  ne.graph
		node:   id
		view_x: ne.view_x
		view_y: ne.view_y
		zoom:   ne.zoom
	}
	ne.graph = inner
	ne.selected = map[int]bool{}
	ne.active = 0
	ne.selected_frame = 0
	ne.frame_all()
	ne.emit(.group_entered, id, 0, NodeLink{})
}

// exit_group - на уровень выше (Tab внутри группы): вид уровня - как был, выбрана группа, из
// которой вышли.
pub fn (mut ne NodeEditor) exit_group() {
	if ne.group_path.len == 0 {
		return
	}
	widget_changed()
	ne.cancel_gesture()
	ne.cancel_text_edit()
	level := ne.group_path.pop()
	ne.graph = level.graph
	ne.view_x, ne.view_y, ne.zoom = level.view_x, level.view_y, level.zoom
	ne.selected = {
		level.node: true
	}
	ne.active = level.node
	ne.selected_frame = 0
	ne.emit(.group_exited, level.node, 0, NodeLink{})
}

// validate_path - после отмены: каждый уровень пути должен по-прежнему вести в показанный граф
// (группа есть и её внутренний граф - тот же). Иначе - выйти на последний целый уровень.
fn (mut ne NodeEditor) validate_path() {
	for i, level in ne.group_path {
		next := if i + 1 < ne.group_path.len { ne.group_path[i + 1].graph } else { ne.graph }
		inner := level.graph.group_graph(level.node) or { unsafe { nil } }
		if isnil(inner) || inner != next {
			for ne.group_path.len > i + 1 {
				ne.exit_group()
			}
			ne.exit_group()
			return
		}
	}
}

// group_selected - свернуть выделенные ноды в группу (Ctrl+G), одна команда отмены; группа
// выделяется.
pub fn (mut ne NodeEditor) group_selected() {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	ne.begin_change()
	gid := ne.graph.group_nodes(ids, tr('Group')) or {
		ne.commit_change('Group nodes')
		return
	}
	ne.touch()
	ne.emit(.grouped, gid, 0, NodeLink{})
	ne.selected = {
		gid: true
	}
	ne.active = gid
	ne.commit_change('Group nodes')
	ne.emit(.selection_changed, gid, 0, NodeLink{})
}

// ungroup_selected - развернуть активную группу (Ctrl+Alt+G), одна команда отмены; выделяются
// её бывшие ноды.
pub fn (mut ne NodeEditor) ungroup_selected() {
	id := ne.active
	if id == 0 || !ne.graph.is_group(id) {
		return
	}
	ne.begin_change()
	added := ne.graph.ungroup(id) or {
		ne.commit_change('Ungroup')
		return
	}
	ne.touch()
	ne.emit(.ungrouped, id, 0, NodeLink{})
	ne.selected = map[int]bool{}
	for nid in added {
		ne.selected[nid] = true
	}
	ne.active = if added.len > 0 { added.last() } else { 0 }
	ne.commit_change('Ungroup')
	ne.emit(.selection_changed, 0, 0, NodeLink{})
}

// group_path_text - путь «Root > Группа > Вложенная» для строки над холстом.
pub fn (ne &NodeEditor) group_path_text() string {
	mut parts := [tr('Root')]
	for level in ne.group_path {
		parts << level.graph.node_title(level.node)
	}
	return parts.join(' > ')
}

// draw_group_path - внутри группы: путь от корня и подсказка выхода в левом верхнем углу.
fn (ne &NodeEditor) draw_group_path(mut ctx RenderContext) {
	if ne.group_path.len == 0 {
		return
	}
	text := '${ne.group_path_text()}   (Tab - ${tr('exit group')})'
	font := ctx.get_font(.bold, 0)
	sz := ctx.measure_text_with_font(text, font)
	r := Rect{ne.bounds.x + 8, ne.bounds.y + 8, sz.x + 16, sz.y + 8}
	ctx.fill_rounded_rect(r, ctx.theme.eff_ne_node_bg().with_alpha(230), 4)
	ctx.draw_rounded_rect(r, ctx.theme.eff_ne_node_border(), 4)
	ctx.draw_text_with_font(text, r.x + 8, r.y + 4, ctx.theme.eff_ne_node_text(), font)
}
