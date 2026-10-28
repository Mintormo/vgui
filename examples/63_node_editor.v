module main

// Пример 63. Редактор графа из нод (NodeEditor, node_editor.v; модель - NodeGraph, node_graph.v).
//
// Что показано:
//   - типы сокетов с цветом и формой значка (float, color, vector - круги, surface - ромб) и
//     неявное преобразование float -> color;
//   - типы нод по категориям (Input, Texture, Color, Converter, Surface, Output) с полями значений на
//     входах: число, флажок, цвет, выбор из списка;
//   - начальный граф «материала», собранный кодом;
//   - мышь: тянуть ноды, связи из сокета в сокет (с подключённого входа связь отцепляется),
//     рамка выделения, средняя кнопка - панорама, колесо - зум к курсору, Ctrl + правая кнопка -
//     разрез связей, правая кнопка по пустому месту - меню добавления с поиском;
//   - связь, отпущенная на пустом месте, открывает меню подходящих нод - новая нода подключится;
//   - ноду без связей, отпущенную на провод, редактор вставляет в его разрыв;
//   - Ctrl во время перемещения или изменения размера - привязка к сетке (snap_to_grid);
//   - подсказка над сокетом: имя, тип, значение или откуда подключён;
//   - фреймы: Ctrl+J обводит выделенные ноды рамкой; шапка фрейма тянет его с нодами внутри,
//     края меняют размер, двойной щелчок по шапке или F2 - переименовать, Delete - удалить;
//   - reroute-точки: двойной щелчок по проводу ставит точку; центр точки тащит её, кольцо вокруг
//     тянет новую связь;
//   - двойной щелчок по шапке или F2 - переименовать ноду;
//   - клавиши: Shift+A - меню добавления, Delete/X - удалить, Shift+D - дублировать, H - свернуть,
//     Home - показать всё, Ctrl+C / Ctrl+X / Ctrl+V - буфер обмена (JSON графа: можно вставить и в
//     другой запуск примера), Ctrl+Z / Ctrl+Shift+Z - отмена и повтор (стек команд окна);
//   - края и углы ноды тянутся мышью, как у окна: ширина и высота (не меньше содержимого);
//   - Style включает и выключает таблицу стилей CSS для селектора `nodes` (цвета холста, карточек,
//     сетки, рамок, толщина связей) - вид нод меняется без правки кода редактора;
//   - Save запоминает граф в JSON, Load возвращает его; строка внизу - последнее событие.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/63_node_editor.v

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится
	mut win := vgui.create_window(title: 'Node editor - demo', width: 1100, height: 680)!

	mut g := build_graph()!
	mut ne := vgui.node_editor(g)
	mut stack := vgui.undo_stack(200)
	ne.set_undo_stack(stack)
	win.set_undo_stack(stack)
	ne.frame_all() // вид подгонится под граф в первой раскладке

	mut status := vgui.label('Shift+A or right click on empty space - add a node')
	ne.on_event = fn [mut status, mut g] (e vgui.NodeEvent) {
		status.text = 'Last event: ${e.kind}  |  nodes: ${g.nodes().len}, links: ${g.links().len}'
	}

	// ── Кнопки ──
	mut bar := vgui.create_hbox_fill()
	bar.set_spacing(6)
	mut undo_btn := vgui.button('Undo')
	undo_btn.on_click = fn [mut stack] () {
		stack.undo()
	}
	mut redo_btn := vgui.button('Redo')
	redo_btn.on_click = fn [mut stack] () {
		stack.redo()
	}
	mut frame_btn := vgui.button('Frame all')
	frame_btn.on_click = fn [mut ne] () {
		ne.frame_all()
	}
	mut saved := &Saved{
		json: g.to_json()
	}
	mut save_btn := vgui.button('Save')
	save_btn.on_click = fn [mut g, mut saved, mut status] () {
		saved.json = g.to_json()
		status.text = 'Saved: ${saved.json.len} bytes of JSON'
	}
	mut load_btn := vgui.button('Load')
	load_btn.on_click = fn [mut g, saved, mut status, mut stack] () {
		g.load_json(saved.json) or {
			status.text = err.msg()
			return
		}
		// Граф заменён кодом: прежние шаги отмены относятся к другому графу
		stack.clear()
		status.text = 'Loaded: ${g.nodes().len} nodes, ${g.links().len} links'
	}
	mut style := &StyleState{}
	mut style_btn := vgui.button('Style')
	style_btn.on_click = fn [mut win, mut style, mut status] () {
		style.on = !style.on
		if style.on {
			ss := vgui.parse_stylesheet(node_css, 'nodes.css') or {
				status.text = err.msg()
				return
			}
			win.set_stylesheet(ss)
		} else {
			win.set_stylesheet(unsafe { nil }) // назад к стилям приложения (их нет)
		}
	}
	bar.add(undo_btn)
	bar.add(redo_btn)
	bar.add(frame_btn)
	bar.add(style_btn)
	bar.add(vgui.create_spacer())
	bar.add(save_btn)
	bar.add(load_btn)

	mut root := vgui.create_vbox_fill()
	root.set_padding(8)
	root.set_spacing(6)
	root.add(bar)
	root.add(ne, flex: 1)
	root.add(status)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}

// build_graph - типы сокетов и нод и начальный граф: Coordinates и Noise -> Blend Colors ->
// Matte -> Mix Surfaces -> Output. Названия нод условные: граф ничего не вычисляет.
fn build_graph() !&vgui.NodeGraph {
	mut g := vgui.node_graph()
	g.define_socket_type('float', vgui.Color{150, 160, 175, 255}, .circle)
	g.define_socket_type('color', vgui.Color{232, 170, 60, 255}, .circle)
	g.define_socket_type('vector', vgui.Color{110, 140, 240, 255}, .circle)
	g.define_socket_type('surface', vgui.Color{80, 200, 150, 255}, .diamond)
	g.allow_conversion('float', 'color')

	input := vgui.Color{150, 80, 170, 255}
	color := vgui.Color{70, 130, 180, 255}
	conv := vgui.Color{90, 110, 130, 255}
	surface := vgui.Color{50, 140, 120, 255}
	output := vgui.Color{170, 70, 80, 255}

	g.define_node(vgui.NodeTypeDef{
		id:       'value'
		title:    'Value'
		category: 'Input'
		color:    input
		inputs:   [vgui.node_socket('Value', 'float', kind: .number, number: 0.5)]
		outputs:  [vgui.node_socket('Value', 'float')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'rgb'
		title:    'RGB'
		category: 'Input'
		color:    input
		inputs:   [vgui.node_socket('Color', 'color',
			kind:  .color
			color: vgui.Color{80, 140, 220, 255}
		)]
		outputs:  [vgui.node_socket('Color', 'color')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'texcoord'
		title:    'Coordinates'
		category: 'Input'
		color:    input
		width:    170
		outputs:  [vgui.node_socket('Position', 'vector'), vgui.node_socket('UV', 'vector'),
			vgui.node_socket('Normal', 'vector')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'noise'
		title:    'Noise'
		category: 'Texture'
		color:    vgui.Color{190, 110, 60, 255}
		width:    170
		inputs:   [
			vgui.node_socket('Vector', 'vector'),
			vgui.node_socket('Scale', 'float',
				kind:   .number
				number: 5
				min:    0
				max:    100
				step:   0.5
				digits: 2
			),
			vgui.node_socket('Detail', 'float',
				kind:   .number
				number: 2
				min:    0
				max:    15
				digits: 1
			),
			vgui.node_socket('Normalize', 'float', kind: .toggle, flag: true),
		]
		outputs:  [vgui.node_socket('Factor', 'float'), vgui.node_socket('Color', 'color')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'mix'
		title:    'Blend Colors'
		category: 'Color'
		color:    color
		width:    160
		inputs:   [
			vgui.node_socket('Blend', 'float',
				kind:    .choice
				choices: ['Mix', 'Multiply', 'Add', 'Screen']
			),
			vgui.node_socket('Factor', 'float', kind: .number, number: 0.5, min: 0, max: 1),
			vgui.node_socket('A', 'color', kind: .color, color: vgui.Color{200, 200, 200, 255}),
			vgui.node_socket('B', 'color', kind: .color, color: vgui.Color{30, 30, 30, 255}),
		]
		outputs:  [vgui.node_socket('Result', 'color')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'math'
		title:    'Math'
		category: 'Converter'
		color:    conv
		inputs:   [
			vgui.node_socket('Operation', 'float',
				kind:    .choice
				choices: ['Add', 'Subtract', 'Multiply', 'Power']
			),
			vgui.node_socket('Value', 'float', kind: .number, number: 0.5),
			vgui.node_socket('Value', 'float', kind: .number, number: 0.5),
		]
		outputs:  [vgui.node_socket('Value', 'float')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'matte'
		title:    'Matte'
		category: 'Surface'
		color:    surface
		inputs:   [
			vgui.node_socket('Color', 'color', kind: .color, color: vgui.Color{204, 204, 204, 255}),
			vgui.node_socket('Roughness', 'float', kind: .number, number: 0, min: 0, max: 1),
		]
		outputs:  [vgui.node_socket('Surface', 'surface')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'shiny'
		title:    'Shiny'
		category: 'Surface'
		color:    surface
		inputs:   [
			vgui.node_socket('Color', 'color', kind: .color, color: vgui.Color{255, 255, 255, 255}),
			vgui.node_socket('Roughness', 'float', kind: .number, number: 0.2, min: 0, max: 1),
		]
		outputs:  [vgui.node_socket('Surface', 'surface')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'mixsurf'
		title:    'Mix Surfaces'
		category: 'Surface'
		color:    surface
		inputs:   [
			vgui.node_socket('Factor', 'float', kind: .number, number: 0.5, min: 0, max: 1),
			vgui.node_socket('Surface', 'surface'),
			vgui.node_socket('Surface', 'surface'),
		]
		outputs:  [vgui.node_socket('Surface', 'surface')]
	})!
	g.define_node(vgui.NodeTypeDef{
		id:       'output'
		title:    'Output'
		category: 'Output'
		color:    output
		inputs:   [
			vgui.node_socket('Surface', 'surface'),
			vgui.node_socket('Offset', 'vector'),
		]
	})!

	// ── Начальный граф ──
	tc := g.add_node('texcoord', 20, 60)!
	noise := g.add_node('noise', 230, 40)!
	mix := g.add_node('mix', 450, 60)!
	matte := g.add_node('matte', 660, 40)!
	shiny := g.add_node('shiny', 660, 200)!
	mixsurf := g.add_node('mixsurf', 860, 100)!
	out := g.add_node('output', 1060, 110)!
	g.connect(tc, 0, noise, 0)!
	g.connect(noise, 0, mix, 1)!
	g.connect(mix, 0, matte, 0)!
	g.connect(matte, 0, mixsurf, 1)!
	// Провод Shiny -> Mix Surfaces - через reroute-точку (двойной щелчок по проводу ставит такую же)
	knot := g.add_reroute(835, 250)
	g.connect(shiny, 0, knot, 0)!
	g.connect(knot, 0, mixsurf, 2)!
	g.connect(mixsurf, 0, out, 0)!
	// Фрейм вокруг нод входа - подписанная рамка, тянется за шапку вместе с нодами
	g.add_frame('Pattern', 0, -6, 650, 220)
	return g
}

// node_css - стиль «чертёж» для редактора нод (PROJECT.md, «NodeEditor», «Вид из темы и CSS»).
// Цвета шапок задают типы нод в build_graph - они сильнее стиля.
const node_css = '
nodes {
	background: #14284a;
	grid-color: #24406e;
	major-grid-color: #36598f;
	node-background: #1d3560;
	border-color: #5d7fb8;
	color: #e6eeff;
	field-background: #12223f;
	field-fill-color: #3d78d8;
	socket-outline-color: #0b1830;
	border-radius: 2;
	link-width: 3;
}
nodes:selected { border-color: #ffd166; }
'

// StyleState - включён ли стиль (в куче: кнопка Style его переключает).
@[heap]
struct StyleState {
mut:
	on bool
}

// Saved - сохранённый JSON графа (в куче: Save его меняет, Load читает).
@[heap]
struct Saved {
mut:
	json string
}
