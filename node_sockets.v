module vgui

// Файл node_sockets.v: свои сокеты отдельной ноды - входы и выходы сверх тех, что задаёт её тип
// (нода «Объединить» с растущим числом входов, «Математика» с выбранным числом аргументов).
//
// Модель: у GraphNode списки extra_inputs / extra_outputs идут после сокетов типа, номера слотов
// сквозные (вход 0..типа-1 - входы типа, дальше - свои). Полный список сокетов ноды - def_of: им
// пользуются проверка связей, значения полей, высота карточки и весь вид, поэтому свои сокеты
// ничем не отличаются от сокетов типа. Удалять можно только свои сокеты: при удалении номера
// следующих слотов в связях сдвигаются, связи удалённого слота удаляются.
//
// Интерфейс (NodeEditor): у типа с шаблоном grow_input внизу карточки - строка «+», она добавляет
// вход по шаблону; у своего неподключённого входа под курсором - «×», он удаляет вход.
// Раздел PROJECT.md - «NodeEditor: редактор графа из нод», «Свои сокеты ноды».

const ne_remove_btn = f32(16) // кнопка «×» своего входа: квадрат у правого края строки

// ─── Модель ────────────────────────────────────────────

// def_of - описание сокетов ноды: тип с добавленными своими сокетами ноды (тип неизвестен -
// пустое описание с id типа). Копия: менять сокеты - add_input / add_output / remove_*.
pub fn (g &NodeGraph) def_of(n &GraphNode) NodeTypeDef {
	mut t := g.types[n.type_id] or {
		NodeTypeDef{
			id:    n.type_id
			title: n.type_id
		}
	}
	if n.extra_inputs.len > 0 {
		mut inputs := t.inputs.clone()
		inputs << n.extra_inputs
		t.inputs = inputs
	}
	if n.extra_outputs.len > 0 {
		mut outputs := t.outputs.clone()
		outputs << n.extra_outputs
		t.outputs = outputs
	}
	return t
}

// row_count - строк в карточке развёрнутой ноды: выходы, входы и строка «+» (если у типа есть
// шаблон grow_input). Общая для высоты модели (content_height) и разметки вида.
fn (g &NodeGraph) row_count(n &GraphNode) int {
	t := g.def_of(n)
	grow := if t.grow_input.typ != '' { 1 } else { 0 }
	return t.outputs.len + t.inputs.len + grow
}

// type_inputs - сколько входов у ноды от типа (свои начинаются с этого номера).
fn (g &NodeGraph) type_inputs(n &GraphNode) int {
	t := g.types[n.type_id] or { return 0 }
	return t.inputs.len
}

fn (g &NodeGraph) type_outputs(n &GraphNode) int {
	t := g.types[n.type_id] or { return 0 }
	return t.outputs.len
}

// add_input - свой вход ноды (после всех входов) со значением поля по умолчанию; возвращает его
// номер слота. Ошибка - ноды нет или тип сокета пустой.
pub fn (mut g NodeGraph) add_input(node int, def NodeSocketDef) !int {
	widget_changed()
	mut n := g.node(node) or { return error('no node ${node}') }
	if def.typ == '' {
		return error('socket type is empty')
	}
	n.extra_inputs << def
	n.values << node_default_value(def.field)
	return n.values.len - 1
}

// add_output - свой выход ноды (после всех выходов); возвращает номер слота.
pub fn (mut g NodeGraph) add_output(node int, def NodeSocketDef) !int {
	widget_changed()
	mut n := g.node(node) or { return error('no node ${node}') }
	if def.typ == '' {
		return error('socket type is empty')
	}
	n.extra_outputs << def
	return g.def_of(n).outputs.len - 1
}

// remove_input удаляет свой вход slot (входы типа удалять нельзя - false): его связь и значение
// удаляются, у связей в следующие свои входы номер слота уменьшается на 1. Возвращает false,
// если удалять нечего.
pub fn (mut g NodeGraph) remove_input(node int, slot int) bool {
	widget_changed()
	mut n := g.node(node) or { return false }
	base := g.type_inputs(n)
	if slot < base || slot >= base + n.extra_inputs.len {
		return false
	}
	n.extra_inputs.delete(slot - base)
	n.values.delete(slot)
	mut kept := []NodeLink{cap: g.links.len}
	for l in g.links {
		if l.to_node == node && l.to_slot == slot {
			continue
		}
		if l.to_node == node && l.to_slot > slot {
			kept << NodeLink{
				...l
				to_slot: l.to_slot - 1
			}
			continue
		}
		kept << l
	}
	g.links = kept
	return true
}

// remove_output удаляет свой выход slot (как remove_input: связи с него удаляются, номера
// следующих своих выходов в связях сдвигаются).
pub fn (mut g NodeGraph) remove_output(node int, slot int) bool {
	widget_changed()
	mut n := g.node(node) or { return false }
	base := g.type_outputs(n)
	if slot < base || slot >= base + n.extra_outputs.len {
		return false
	}
	n.extra_outputs.delete(slot - base)
	mut kept := []NodeLink{cap: g.links.len}
	for l in g.links {
		if l.from_node == node && l.from_slot == slot {
			continue
		}
		if l.from_node == node && l.from_slot > slot {
			kept << NodeLink{
				...l
				from_slot: l.from_slot - 1
			}
			continue
		}
		kept << l
	}
	g.links = kept
	return true
}

// grow_socket - вход по шаблону grow_input типа ноды: {n} в имени - номер нового входа среди
// своих (с 1).
fn (g &NodeGraph) grow_socket(n &GraphNode) NodeSocketDef {
	t := g.types[n.type_id] or { return NodeSocketDef{} }
	return NodeSocketDef{
		...t.grow_input
		name: t.grow_input.name.replace('{n}', '${n.extra_inputs.len + 1}')
	}
}

// ─── JSON своих сокетов ────────────────────────────────

struct NodeSocketJson {
	name    string
	typ     string @[json: 'type']
	kind    int
	number  f64
	min     f64
	max     f64
	step    f64
	digits  int
	flag    bool
	color   []int
	choices []string
	choice  int
}

fn socket_to_json(d NodeSocketDef) NodeSocketJson {
	f := d.field
	return NodeSocketJson{
		name:    d.name
		typ:     d.typ
		kind:    int(f.kind)
		number:  f.number
		min:     f.min
		max:     f.max
		step:    f.step
		digits:  f.digits
		flag:    f.flag
		color:   [int(f.color.r), int(f.color.g), int(f.color.b), int(f.color.a)]
		choices: f.choices
		choice:  f.choice
	}
}

// socket_from_json - сокет из записи; неизвестный вид поля - без поля (int -> enum через unsafe
// только после проверки диапазона).
fn socket_from_json(j NodeSocketJson) NodeSocketDef {
	kind := if j.kind >= 0 && j.kind <= int(NodeFieldKind.choice) {
		unsafe { NodeFieldKind(j.kind) }
	} else {
		NodeFieldKind.none
	}
	return NodeSocketDef{
		name:  j.name
		typ:   j.typ
		field: NodeField{
			kind:    kind
			number:  j.number
			min:     j.min
			max:     j.max
			step:    j.step
			digits:  j.digits
			flag:    j.flag
			color:   node_json_color(j.color, Color{200, 200, 200, 255})
			choices: j.choices
			choice:  j.choice
		}
	}
}

// ─── Вид и ввод (методы NodeEditor) ────────────────────

// grow_rect - строка «+» внизу карточки (пустой Rect - у типа нет шаблона или нода свёрнута).
fn (ne &NodeEditor) grow_rect(n &GraphNode) Rect {
	t := ne.type_of(n)
	if n.collapsed || t.grow_input.typ == '' {
		return Rect{}
	}
	y := ne_row_y(n, t.outputs.len + t.inputs.len)
	return Rect{n.x + ne_field_inset, y + 2, ne.graph.width_of(n) - ne_field_inset * 2, ne_row_h - 4}
}

// remove_rect - кнопка «×» своего входа slot (пустой Rect - вход типа, подключён или нода
// свёрнута: подключённый вход сначала отцепляют).
fn (ne &NodeEditor) remove_rect(n &GraphNode, slot int) Rect {
	if n.collapsed || slot < ne.graph.type_inputs(n) || slot >= ne.type_of(n).inputs.len {
		return Rect{}
	}
	if _ := ne.graph.link_into(n.id, slot) {
		return Rect{}
	}
	t := ne.type_of(n)
	y := ne_row_y(n, t.outputs.len + slot)
	x := n.x + ne.graph.width_of(n) - ne_field_inset * 0.5 - ne_remove_btn
	return Rect{x, y + (ne_row_h - ne_remove_btn) * 0.5, ne_remove_btn, ne_remove_btn}
}

// grow_input_of - добавить ноде вход по шаблону типа (строка «+»), одна команда отмены.
pub fn (mut ne NodeEditor) grow_input_of(id int) {
	n := ne.graph.node(id) or { return }
	def := ne.graph.grow_socket(n)
	if def.typ == '' {
		return
	}
	ne.begin_change()
	slot := ne.graph.add_input(id, def) or { return }
	ne.touch()
	ne.emit(.sockets_changed, id, slot, NodeLink{})
	ne.commit_change('Add input')
}

// remove_input_of - удалить свой вход ноды (кнопка «×»), одна команда отмены.
pub fn (mut ne NodeEditor) remove_input_of(id int, slot int) {
	ne.begin_change()
	if ne.graph.remove_input(id, slot) {
		ne.touch()
		ne.emit(.sockets_changed, id, slot, NodeLink{})
	}
	ne.commit_change('Remove input')
}

// draw_socket_buttons - строка «+» и кнопки «×» своих входов (их видно, пока курсор над нодой:
// постоянные крестики на каждой строке шумели бы).
fn (ne &NodeEditor) draw_socket_buttons(n &GraphNode, mut ctx RenderContext) {
	c := ctx.theme.eff_ne_node_text()
	gr := ne.grow_rect(n)
	if gr.w > 0 {
		r := ne.screen_rect(gr)
		hot := ne.hover.kind == .grow && ne.hover.node == n.id
		bg := ctx.theme.eff_ne_field_bg()
		ctx.fill_rounded_rect(r, if hot { bg.brighten(0.12) } else { bg }, 3 * ne.zoom)
		ne_draw_plus(r.x + r.w * 0.5, r.y + r.h * 0.5, 4 * ne.zoom, c, mut ctx)
	}
	if ne.hover.node != n.id {
		return
	}
	for slot in ne.graph.type_inputs(n) .. ne.type_of(n).inputs.len {
		rr := ne.remove_rect(n, slot)
		if rr.w <= 0 {
			continue
		}
		r := ne.screen_rect(rr)
		hot := ne.hover.kind == .socket_remove && ne.hover.slot == slot
		if hot {
			ctx.fill_rounded_rect(r, ctx.theme.error_color.with_alpha(160), 3 * ne.zoom)
		}
		s := 3.5 * ne.zoom
		cx, cy := r.x + r.w * 0.5, r.y + r.h * 0.5
		ctx.draw_line_thick(cx - s, cy - s, cx + s, cy + s, 2, c)
		ctx.draw_line_thick(cx - s, cy + s, cx + s, cy - s, 2, c)
	}
}

// ne_draw_plus - знак «+» с центром (cx, cy) и полудлиной s.
fn ne_draw_plus(cx f32, cy f32, s f32, c Color, mut ctx RenderContext) {
	ctx.draw_line_thick(cx - s, cy, cx + s, cy, 2, c)
	ctx.draw_line_thick(cx, cy - s, cx, cy + s, 2, c)
}
