module vgui

// Файл node_reroute.v: reroute-точки редактора нод - точки перегиба на проводах, чтобы аккуратно
// разводить длинные связи (как Reroute в Blender и Knot в Unreal Blueprints).
//
// Точка - обычная нода встроенного типа node_reroute_type (его регистрирует node_graph(), в меню
// добавления его нет): один вход и один выход типа `*`. Поэтому сохранение, отмена, буфер обмена,
// удаление и перемещение работают без особых случаев. Своего типа у точки нет: её выход несёт
// тип того, что в неё входит (out_type), а вход должен подходить всем, кого точка питает
// (in_types) - check_link проверяет связь по реальным типам сквозь цепочку точек. Приложению,
// которое считает граф, нужен настоящий источник входа - source_of проходит точки насквозь.
//
// Ввод (NodeEditor): двойной щелчок по проводу ставит в это место точку; центр точки тащит её,
// кольцо вокруг тянет новую связь с её выхода; провод, отпущенный на точку, входит в неё.
// Раздел PROJECT.md - «NodeEditor: редактор графа из нод», «Reroute-точки».

pub const node_reroute_type = '@reroute'
const ne_reroute_size = f32(12) // сторона квадрата точки на холсте (рисуется кругом)
const ne_reroute_ring_px = f32(7) // ширина кольца «тянуть связь» вокруг точки, экранные px

// ─── Модель ────────────────────────────────────────────

// add_reroute - reroute-точка с центром в (cx, cy) на холсте; возвращает id её ноды.
pub fn (mut g NodeGraph) add_reroute(cx f32, cy f32) int {
	half := ne_reroute_size * 0.5
	return g.add_node(node_reroute_type, cx - half, cy - half) or { 0 }
}

// is_reroute - нода id - reroute-точка.
pub fn (g &NodeGraph) is_reroute(id int) bool {
	n := g.node(id) or { return false }
	return n.type_id == node_reroute_type
}

// out_type - тип выхода slot ноды node; у reroute-точки - тип того, что в неё входит (сквозь
// цепочку точек), у неподключённой точки - `*`. depth ограничивает обход на случай цикла из
// точек (при allow_cycles).
pub fn (g &NodeGraph) out_type(node int, slot int) string {
	return g.out_type_depth(node, slot, 0)
}

fn (g &NodeGraph) out_type_depth(node int, slot int, depth int) string {
	n := g.node(node) or { return '*' }
	if n.type_id != node_reroute_type {
		t := g.types[n.type_id] or { return '*' }
		return if slot >= 0 && slot < t.outputs.len { t.outputs[slot].typ } else { '*' }
	}
	if depth > 256 {
		return '*'
	}
	l := g.link_into(node, 0) or { return '*' }
	return g.out_type_depth(l.from_node, l.from_slot, depth + 1)
}

// in_types - типы, которым должен подходить источник, подключаемый ко входу slot ноды node:
// у обычной ноды - тип входа; у reroute-точки - типы всех настоящих входов, которые она питает
// (сквозь цепочку точек). Пусто - подходит всё (точка ещё никого не питает).
pub fn (g &NodeGraph) in_types(node int, slot int) []string {
	mut out := []string{}
	g.collect_in_types(node, slot, 0, mut out)
	return out
}

fn (g &NodeGraph) collect_in_types(node int, slot int, depth int, mut out []string) {
	n := g.node(node) or { return }
	if n.type_id != node_reroute_type {
		t := g.types[n.type_id] or { return }
		if slot >= 0 && slot < t.inputs.len {
			out << t.inputs[slot].typ
		}
		return
	}
	if depth > 256 {
		return
	}
	for l in g.links_from(node, 0) {
		g.collect_in_types(l.to_node, l.to_slot, depth + 1, mut out)
	}
}

// source_of - что на самом деле питает вход slot ноды node: связь, у которой from_node/from_slot -
// настоящий выход (reroute-точки пройдены насквозь), а to_node/to_slot - этот вход. none - вход
// не подключён или цепочка точек ни к чему не подключена. Так приложение считает граф, не зная о
// точках: значение входа берётся с from_node/from_slot.
pub fn (g &NodeGraph) source_of(node int, slot int) ?NodeLink {
	mut l := g.link_into(node, slot) or { return none }
	for _ in 0 .. 256 {
		if !g.is_reroute(l.from_node) {
			return NodeLink{
				id:        l.id
				from_node: l.from_node
				from_slot: l.from_slot
				to_node:   node
				to_slot:   slot
			}
		}
		l = g.link_into(l.from_node, 0) or { return none }
	}
	return none
}

// ─── Вид и ввод (методы NodeEditor) ────────────────────

// reroute_hit - попадание по точке n в экранной точке (sx, sy). Пока тянут связь, вся точка с
// кольцом - сокет, подходящий для её конца (вход, если тянут с выхода). Иначе центр - тело
// (тащить точку), кольцо вокруг - выход (тянуть новую связь). none - мимо.
fn (ne &NodeEditor) reroute_hit(n &GraphNode, sx f32, sy f32) ?NodeHit {
	cx, cy := ne.reroute_center(n)
	dx, dy := sx - cx, sy - cy
	d2 := dx * dx + dy * dy
	inner := max_f32(ne_reroute_size * 0.5 * ne.zoom, 4)
	outer := inner + ne_reroute_ring_px
	if d2 > outer * outer {
		return none
	}
	if ne.drag == .link {
		return NodeHit{if ne.link_from_out { NodeHitKind.socket_in } else { .socket_out }, n.id, 0}
	}
	if d2 <= inner * inner {
		return NodeHit{.body, n.id, 0}
	}
	return NodeHit{.socket_out, n.id, 0}
}

// reroute_center - центр точки на экране.
fn (ne &NodeEditor) reroute_center(n &GraphNode) (f32, f32) {
	half := ne_reroute_size * 0.5
	return ne.to_screen(n.x + half, n.y + half)
}

// draw_reroute - точка цветом типа, который через неё идёт; выделенная - в кольце выделения,
// под курсором в зоне «тянуть связь» - в тонком кольце-подсказке.
fn (ne &NodeEditor) draw_reroute(n &GraphNode, mut ctx RenderContext) {
	cx, cy := ne.reroute_center(n)
	r := max_f32(ne_reroute_size * 0.5 * ne.zoom, 4)
	c := ne.graph.socket_type(ne.graph.out_type(n.id, 0)).color
	if n.id in ne.selected {
		ctx.fill_circle(cx, cy, r + 3, ctx.theme.eff_ne_selected())
	} else if ne.drag == .none && ne.hover.node == n.id && ne.hover.kind == .socket_out {
		ctx.fill_circle(cx, cy, r + ne_reroute_ring_px, c.with_alpha(60))
	}
	ctx.fill_circle(cx, cy, r + 1, ctx.theme.eff_ne_socket_outline())
	ctx.fill_circle(cx, cy, r, c)
}

// link_at - связь, проходящая рядом с экранной точкой (sx, sy) (в пределах 6 px), ближайшая;
// 0 - нет.
fn (ne &NodeEditor) link_at(sx f32, sy f32) int {
	mut best := 0
	mut best_d := f32(36) // 6 px в квадрате
	for l in ne.graph.links {
		d := ne_dist2_to_polyline(ne.link_points(l), sx, sy)
		if d <= best_d {
			best_d = d
			best = l.id
		}
	}
	return best
}

// split_link - поставить reroute-точку на связь link_id в экранной точке (sx, sy): A -> B
// становится A -> точка -> B. Одна команда отмены; точка выделяется.
pub fn (mut ne NodeEditor) split_link(link_id int, sx f32, sy f32) {
	l := ne.graph.link_by_id(link_id) or { return }
	wx, wy := ne.to_world(sx, sy)
	// Свой снимок для отката: снимок begin_change есть только при заданном undo_stack
	before := ne.graph.snapshot()
	ne.begin_change()
	id := ne.graph.add_reroute(wx, wy)
	ne.graph.disconnect(l.id)
	// Типы прежние (точка их только проводит) - связи пройдут проверку; вето приложения может
	// отказать - тогда граф возвращается как был (правки не было - команды тоже)
	first := ne.graph.connect(l.from_node, l.from_slot, id, 0) or {
		ne.graph.restore(before)
		ne.commit_change('Add reroute')
		return
	}
	second := ne.graph.connect(id, 0, l.to_node, l.to_slot) or {
		ne.graph.restore(before)
		ne.commit_change('Add reroute')
		return
	}
	ne.touch()
	ne.emit(.node_added, id, 0, NodeLink{})
	ne.emit(.link_removed, 0, 0, l)
	ne.emit(.link_added, 0, 0, first.link)
	ne.emit(.link_added, 0, 0, second.link)
	ne.selected = {
		id: true
	}
	ne.active = id
	ne.commit_change('Add reroute')
	ne.emit(.selection_changed, id, 0, NodeLink{})
}
