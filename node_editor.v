module vgui

// Файл node_editor.v: NodeEditor - редактор графа из нод (как в редакторах шейдеров, процедурной
// графики, визуального программирования). Модель графа - NodeGraph (node_graph.v); здесь только
// вид и ввод.
//
// Холст бесконечный: вид задают view_x/view_y (точка холста в левом верхнем углу виджета) и zoom.
// Координаты нод - в единицах холста; на экран: screen = bounds.xy + (world - view) * zoom.
//
// Ввод:
//   - левая кнопка: по ноде - выделить и тащить (Shift - добавить/убрать из выделения); по выходу -
//     тянуть новую связь; по подключённому входу - отцепить связь и тянуть её дальше (брошенная
//     мимо - удаляется); по свободному входу - тянуть связь к выходу; по пустому месту - рамка
//     выделения (Shift - добавить); по треугольнику в шапке - свернуть/развернуть;
//   - поля входов: число - протяжка меняет значение, щелчок без протяжки - ввод с клавиатуры;
//     флажок - щелчок; цвет - диалог выбора; выбор - выпадающий список;
//   - средняя кнопка - панорама, колесо - зум к курсору;
//   - Ctrl + правая кнопка - жест «разрез»: связи, пересечённые линией, удаляются;
//     правая кнопка по пустому месту и Shift+A - меню добавления ноды с поиском;
//   - клавиши (в фокусе): Delete/X - удалить выделенное, Shift+D - дублировать, Ctrl+A - выделить
//     всё, H - свернуть/развернуть выделенные, Home - показать всё, Esc - отменить жест.
//
// Отмена: если задан undo_stack, каждая правка пользователя - одна команда стека. Команда хранит
// снимки графа до и после (NodeGraphState) - как memento-команды QUndoStack в Qt Nodes; для графов
// в сотни нод это дёшево и не требует отдельной команды на каждый вид правки.
//
// События для приложения - один колбэк on_event(NodeEvent) (как запросы imnodes «связь создана /
// удалена»): правки пользователя; после отмены/повтора - .graph_restored. Правки, сделанные кодом
// через NodeGraph, событий не дают - о них приложение знает само.
//
// Рисование - только примитивы RenderContext (PROJECT.md, «Бэкенд рисования»). При мелком зуме
// текст не рисуется: шрифт размером в пару пикселей нечитаем и дорог.
// Тег типа kind_node_editor - widget_kinds.v. Раздел PROJECT.md - «NodeEditor: редактор графа из нод».

// Геометрия ноды в единицах холста.
const ne_header_h = f32(24) // шапка с заголовком
const ne_row_h = f32(22) // строка сокета
const ne_pad_bottom = f32(6) // поле под последней строкой
const ne_socket_r = f32(5) // радиус значка сокета
const ne_field_inset = f32(10) // отступ поля значения от краёв ноды
const ne_grid = f32(20) // шаг мелкой сетки
const ne_socket_hit_px = f32(9) // захват сокета мышью, экранные px
const ne_edge_hit_px = f32(4) // захват края ноды (изменение размера), экранные px по обе стороны
const ne_corner_hit_px = f32(8) // захват угла снаружи карточки - угол ловить легче, как у окна

// Края ноды под курсором при изменении размера - битовая маска (NodeHit.slot у .edge): угол -
// два бита сразу (низ + право - правый нижний угол).
const ne_edge_left = 1
const ne_edge_right = 2
const ne_edge_top = 4
const ne_edge_bottom = 8
const ne_drag_threshold = f32(3) // сдвиг, после которого нажатие становится протяжкой, px
const ne_text_min_zoom = f32(0.45) // мельче - текст не рисуется
const ne_menu_w = f32(260) // ширина меню добавления
const ne_menu_row_h = f32(24)
const ne_menu_rows = 12 // видимых строк меню

// NodeEventKind - что изменил пользователь (NodeEvent.kind).
pub enum NodeEventKind {
	node_added
	node_removed
	nodes_moved
	link_added
	link_removed
	value_changed
	collapsed
	selection_changed
	graph_restored // отмена/повтор вернули граф к снимку
	node_resized   // пользователь изменил размер ноды, потянув край или угол
	node_renamed   // пользователь задал ноде свой заголовок (F2 / двойной щелчок по шапке)
}

// NodeEvent - событие редактора: вид, нода и слот (вход), связь (для link_*).
pub struct NodeEvent {
pub:
	kind NodeEventKind
	node int
	slot int
	link NodeLink
}

// NodeHitKind - что под курсором (hit_test).
enum NodeHitKind {
	none
	socket_in
	socket_out
	field
	collapse
	header
	body
	edge // край или угол ноды (NodeHit.slot - маска ne_edge_*): тянуть - менять размер
}

struct NodeHit {
	kind NodeHitKind
	node int
	slot int
}

// NodeDrag - текущий жест мыши.
enum NodeDrag {
	none
	pan
	move
	box
	link
	cut
	number
	resize
}

// NodeAddMenu - состояние меню добавления ноды: где открыто (экран), куда ставить ноду (холст),
// отфильтрованные типы, выбранная строка и прокрутка.
struct NodeAddMenu {
mut:
	open    bool
	x       f32
	y       f32
	world_x f32
	world_y f32
	items   []string // id типов, прошедших фильтр
	hover   int
	scroll  int
	// Меню открыто связью, отпущенной в пустоте (link_node != 0): в списке - только типы с
	// подходящим сокетом, новая нода сразу подключается к этой связи
	link_node     int
	link_slot     int
	link_from_out bool // связь тянули с выхода: у новой ноды нужен вход
}

// NodeEditor - виджет редактора графа. graph - модель (её можно менять и кодом); undo_stack -
// необязательный стек команд для отмены правок пользователя; on_event - события правок.
@[heap]
pub struct NodeEditor {
pub mut:
	type_tag    int = kind_node_editor // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focused     bool
	focus_group int
	graph       &NodeGraph = unsafe { nil }
	undo_stack  &UndoStack = unsafe { nil }
	show_grid   bool       = true
	min_zoom    f32        = 0.2
	max_zoom    f32        = 3
	// Вид: точка холста в левом верхнем углу и масштаб
	view_x f32
	view_y f32
	zoom   f32 = 1
	// Колбэк правок пользователя
	on_event fn (NodeEvent) = unsafe { nil }
mut:
	selected map[int]bool
	active   int // последняя выбранная нода (0 - нет)
	hover    NodeHit
	// Жест мыши
	drag       NodeDrag
	drag_moved bool // жест сдвинулся дальше порога
	press_x    f32
	press_y    f32
	last_x     f32
	last_y     f32
	box_add    bool // рамка добавляет к выделению (Shift)
	// Тянущаяся связь: якорь (нода, слот), с выхода ли тянут, отцеплённая связь (0 - нет)
	link_node     int
	link_slot     int
	link_from_out bool
	link_detached int
	cut_pts       []Vec2
	// Изменение размера: нода, какие края тянут (маска ne_edge_*), прямоугольник ноды в начале
	// жеста (единицы холста); курсор до того, как над краем поставили «стрелку» (nil - не меняли)
	resize_node  int
	resize_edges int
	resize_start Rect
	saved_cursor voidptr
	// Протяжка числа: нода, вход, значение в начале
	num_node  int
	num_slot  int
	num_start f64
	// Ввод числа с клавиатуры
	editing    bool
	edit_ti    &TextInput = unsafe { nil }
	edit_node  int
	edit_slot  int
	edit_title bool // поле правит заголовок ноды (F2), а не число входа edit_slot
	// Меню добавления ноды и его поле поиска
	menu        NodeAddMenu
	menu_ti     &TextInput     = unsafe { nil }
	menu_ctx    &RenderContext = unsafe { nil }
	choice_menu &ContextMenu   = unsafe { nil }
	// Отмена: снимок до правки и счётчик правок (снимок «после» кладётся, только если он вырос)
	// frame_all до первой раскладки (размер неизвестен) - выполнить в arrange
	frame_pending bool
	pending       NodeGraphState
	has_pending   bool
	changes       int
	pending_from  int
}

// node_editor - редактор графа g (nil - пустой граф без типов).
pub fn node_editor(g &NodeGraph) &NodeEditor {
	return &NodeEditor{
		graph: if isnil(g) { node_graph() } else { unsafe { g } }
	}
}

// owns_focus - фокус у внутреннего поля (ввод числа или поиск в меню): клавиши ему доставляются
// через редактор (FocusOwner, event_route.v).
pub fn (ne &NodeEditor) owns_focus(ptr voidptr) bool {
	return (!isnil(ne.edit_ti) && voidptr(ne.edit_ti) == ptr)
		|| (!isnil(ne.menu_ti) && voidptr(ne.menu_ti) == ptr)
}

// ─── Публичный API ─────────────────────────────────────

// set_undo_stack - стек команд для отмены правок пользователя (nil - без отмены).
pub fn (mut ne NodeEditor) set_undo_stack(s &UndoStack) {
	widget_changed()
	ne.undo_stack = unsafe { s }
}

// selected_nodes - id выделенных нод в порядке отрисовки.
pub fn (ne &NodeEditor) selected_nodes() []int {
	mut out := []int{}
	for n in ne.graph.nodes {
		if n.id in ne.selected {
			out << n.id
		}
	}
	return out
}

// select_node выделяет ноду (add - добавить к выделению, иначе - только её).
pub fn (mut ne NodeEditor) select_node(id int, add bool) {
	widget_changed()
	if !add {
		ne.selected = map[int]bool{}
	}
	if _ := ne.graph.node(id) {
		ne.selected[id] = true
		ne.active = id
	}
}

// clear_selection снимает выделение.
pub fn (mut ne NodeEditor) clear_selection() {
	widget_changed()
	ne.selected = map[int]bool{}
	ne.active = 0
}

// set_view - вид: точка холста (x, y) в левом верхнем углу и масштаб.
pub fn (mut ne NodeEditor) set_view(x f32, y f32, zoom f32) {
	widget_changed()
	ne.view_x = x
	ne.view_y = y
	ne.zoom = clamp_f32(zoom, ne.min_zoom, ne.max_zoom)
}

// frame_all - вид, в который помещаются все ноды (масштаб не больше 1). Пустой граф - начало
// холста. До первой раскладки размер виджета неизвестен - тогда вид подгоняется в ней (arrange):
// так «показать всё» можно звать сразу после построения графа.
pub fn (mut ne NodeEditor) frame_all() {
	widget_changed()
	if ne.bounds.w <= 0 || ne.bounds.h <= 0 {
		ne.frame_pending = true
		return
	}
	ne.frame_pending = false
	if ne.graph.nodes.len == 0 {
		ne.view_x, ne.view_y, ne.zoom = 0, 0, 1
		return
	}
	mut x0, mut y0 := f32(1.0e9), f32(1.0e9)
	mut x1, mut y1 := f32(-1.0e9), f32(-1.0e9)
	for n in ne.graph.nodes {
		r := ne.node_world_rect(n)
		x0 = min_f32(x0, r.x)
		y0 = min_f32(y0, r.y)
		x1 = max_f32(x1, r.x + r.w)
		y1 = max_f32(y1, r.y + r.h)
	}
	margin := f32(40)
	w := x1 - x0 + margin * 2
	h := y1 - y0 + margin * 2
	ne.zoom = clamp_f32(min_f32(1, min_f32(ne.bounds.w / w, ne.bounds.h / h)), ne.min_zoom,
		ne.max_zoom)
	// По центру: середина нод - в середину виджета
	ne.view_x = (x0 + x1) * 0.5 - ne.bounds.w * 0.5 / ne.zoom
	ne.view_y = (y0 + y1) * 0.5 - ne.bounds.h * 0.5 / ne.zoom
}

// delete_selected удаляет выделенные ноды с их связями (одна команда отмены).
pub fn (mut ne NodeEditor) delete_selected() {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	widget_changed()
	ne.begin_change()
	for id in ids {
		for l in ne.graph.remove_node(id) {
			ne.emit(.link_removed, 0, 0, l)
		}
		ne.emit(.node_removed, id, 0, NodeLink{})
	}
	ne.selected = map[int]bool{}
	ne.active = 0
	ne.touch()
	ne.commit_change('Delete nodes')
}

// arrange - отложенный frame_all: размер виджета стал известен. Здесь, а не в draw(): раскладка
// идёт и перед событиями, и первый же щелчок видит подогнанный вид.
pub fn (mut ne NodeEditor) arrange(mut ctx RenderContext) {
	if ne.frame_pending && ne.bounds.w > 0 && ne.bounds.h > 0 {
		ne.frame_all()
	}
}

// ─── Вид: холст <-> экран ──────────────────────────────

fn (ne &NodeEditor) to_screen(wx f32, wy f32) (f32, f32) {
	return ne.bounds.x + (wx - ne.view_x) * ne.zoom, ne.bounds.y + (wy - ne.view_y) * ne.zoom
}

fn (ne &NodeEditor) to_world(sx f32, sy f32) (f32, f32) {
	return ne.view_x + (sx - ne.bounds.x) / ne.zoom, ne.view_y + (sy - ne.bounds.y) / ne.zoom
}

fn (ne &NodeEditor) screen_rect(r Rect) Rect {
	x, y := ne.to_screen(r.x, r.y)
	return Rect{x, y, r.w * ne.zoom, r.h * ne.zoom}
}

// zoom_at - масштаб z с неподвижной точкой экрана (sx, sy): точка холста под курсором остаётся
// под курсором.
fn (mut ne NodeEditor) zoom_at(sx f32, sy f32, z f32) {
	wx, wy := ne.to_world(sx, sy)
	ne.zoom = clamp_f32(z, ne.min_zoom, ne.max_zoom)
	ne.view_x = wx - (sx - ne.bounds.x) / ne.zoom
	ne.view_y = wy - (sy - ne.bounds.y) / ne.zoom
}

// ─── Геометрия нод (в единицах холста) ─────────────────

fn (ne &NodeEditor) type_of(n &GraphNode) NodeTypeDef {
	return ne.graph.types[n.type_id] or {
		NodeTypeDef{
			id:    n.type_id
			title: n.type_id
		}
	}
}

// node_world_rect - карточка ноды на холсте: размеры - своя ширина/высота или по типу и
// содержимому (NodeGraph.width_of / height_of).
fn (ne &NodeEditor) node_world_rect(n &GraphNode) Rect {
	return Rect{n.x, n.y, ne.graph.width_of(n), ne.graph.height_of(n)}
}

// row_y - верх строки row (выходы - строки 0..outputs-1, затем входы).
fn ne_row_y(n &GraphNode, row int) f32 {
	return n.y + ne_header_h + f32(row) * ne_row_h
}

// socket_pos - центр значка сокета (вход или выход slot) в единицах холста. У свёрнутой ноды
// все сокеты - на середине шапки, по краям.
fn (ne &NodeEditor) socket_pos(n &GraphNode, out bool, slot int) (f32, f32) {
	t := ne.type_of(n)
	x := if out { n.x + ne.graph.width_of(n) } else { n.x }
	if n.collapsed {
		return x, n.y + ne_header_h * 0.5
	}
	row := if out { slot } else { t.outputs.len + slot }
	return x, ne_row_y(n, row) + ne_row_h * 0.5
}

// field_rect - поле значения входа slot (пустой Rect - поля нет: не задано, вход подключён или
// нода свёрнута).
fn (ne &NodeEditor) field_rect(n &GraphNode, slot int) Rect {
	t := ne.type_of(n)
	if n.collapsed || slot < 0 || slot >= t.inputs.len || t.inputs[slot].field.kind == .none {
		return Rect{}
	}
	if _ := ne.graph.link_into(n.id, slot) {
		return Rect{}
	}
	y := ne_row_y(n, t.outputs.len + slot)
	return Rect{n.x + ne_field_inset, y + 2, ne.graph.width_of(n) - ne_field_inset * 2, ne_row_h - 4}
}

fn ne_collapse_rect(n &GraphNode) Rect {
	return Rect{n.x + 4, n.y + 4, 16, ne_header_h - 8}
}

// ─── Попадание ─────────────────────────────────────────

// hit_test - что под точкой экрана. Сначала сокеты всех нод сверху вниз (значки выступают за
// край карточки и не должны теряться под соседней нодой), затем сами ноды сверху вниз; у каждой
// ноды - сначала её края и углы (изменение размера, edge_mask), потом содержимое. Сокеты стоят
// на боковых краях, но проверены раньше: край тянется там, где их нет.
fn (ne &NodeEditor) hit_test(sx f32, sy f32) NodeHit {
	if !ne.bounds.contains(sx, sy) {
		return NodeHit{}
	}
	wx, wy := ne.to_world(sx, sy)
	tol := ne_socket_hit_px / ne.zoom
	for i := ne.graph.nodes.len - 1; i >= 0; i-- {
		n := ne.graph.nodes[i]
		t := ne.type_of(n)
		for s in 0 .. t.outputs.len {
			px, py := ne.socket_pos(n, true, s)
			if ne_near(wx, wy, px, py, tol) {
				return NodeHit{.socket_out, n.id, s}
			}
		}
		for s in 0 .. t.inputs.len {
			px, py := ne.socket_pos(n, false, s)
			if ne_near(wx, wy, px, py, tol) {
				return NodeHit{.socket_in, n.id, s}
			}
		}
	}
	for i := ne.graph.nodes.len - 1; i >= 0; i-- {
		n := ne.graph.nodes[i]
		r := ne.node_world_rect(n)
		edges := ne.edge_mask(n, r, wx, wy)
		if edges != 0 {
			return NodeHit{.edge, n.id, edges}
		}
		if !r.contains(wx, wy) {
			continue
		}
		if ne_collapse_rect(n).contains(wx, wy) {
			return NodeHit{.collapse, n.id, 0}
		}
		if wy < n.y + ne_header_h {
			return NodeHit{.header, n.id, 0}
		}
		t := ne.type_of(n)
		for s in 0 .. t.inputs.len {
			if ne.field_rect(n, s).contains(wx, wy) {
				return NodeHit{.field, n.id, s}
			}
		}
		return NodeHit{.body, n.id, 0}
	}
	return NodeHit{}
}

// edge_mask - какие края ноды под точкой холста (wx, wy): маска ne_edge_*, 0 - не край.
// Край ловится в полоске ne_edge_hit_px по обе стороны линии края, угол - ещё и снаружи до
// ne_corner_hit_px (как у окна: в угол легче попасть). У свёрнутой ноды высота не меняется:
// верх и низ не ловятся, а угол тянет только ширину - на боковых краях свёрнутой ноды почти всю
// высоту шапки занимают сокеты, и без углов ширину было бы не ухватить.
fn (ne &NodeEditor) edge_mask(n &GraphNode, r Rect, wx f32, wy f32) int {
	tol := ne_edge_hit_px / ne.zoom
	ctol := ne_corner_hit_px / ne.zoom
	// Расстояния до краёв: положительные - снаружи карточки, отрицательные - внутри
	out_l := r.x - wx
	out_r := wx - (r.x + r.w)
	out_t := r.y - wy
	out_b := wy - (r.y + r.h)
	near_l, near_r := out_l >= -tol && out_l <= tol, out_r >= -tol && out_r <= tol
	near_t, near_b := out_t >= -tol && out_t <= tol, out_b >= -tol && out_b <= tol
	// Угол: у обоих краёв, снаружи - с большим запасом
	corner_x := if out_l >= -tol && out_l <= ctol {
		ne_edge_left
	} else if out_r >= -tol && out_r <= ctol {
		ne_edge_right
	} else {
		0
	}
	corner_y := if out_t >= -tol && out_t <= ctol {
		ne_edge_top
	} else if out_b >= -tol && out_b <= ctol {
		ne_edge_bottom
	} else {
		0
	}
	if corner_x != 0 && corner_y != 0 {
		return if n.collapsed { corner_x } else { corner_x | corner_y }
	}
	inside_y := wy >= r.y && wy <= r.y + r.h
	inside_x := wx >= r.x && wx <= r.x + r.w
	if inside_y && near_l {
		return ne_edge_left
	}
	if inside_y && near_r {
		return ne_edge_right
	}
	if n.collapsed {
		return 0
	}
	if inside_x && near_t {
		return ne_edge_top
	}
	if inside_x && near_b {
		return ne_edge_bottom
	}
	return 0
}

fn ne_near(x f32, y f32, px f32, py f32, tol f32) bool {
	dx := x - px
	dy := y - py
	return dx * dx + dy * dy <= tol * tol
}

// ─── Связи: кривые ─────────────────────────────────────

// ne_bezier - точки кривой связи (экран) от выхода (x0, y0) к входу (x1, y1): касательные
// горизонтальные, их длина растёт с расстоянием, но не короче min_dx - иначе
// связь «назад» (вход левее выхода) превращается в острый излом.
fn ne_bezier(x0 f32, y0 f32, x1 f32, y1 f32, min_dx f32) []Vec2 {
	dx := max_f32(abs_f32(x1 - x0) * 0.5, min_dx)
	c0x, c1x := x0 + dx, x1 - dx
	segments := 24
	mut pts := []Vec2{cap: segments + 1}
	for i in 0 .. segments + 1 {
		t := f32(i) / f32(segments)
		u := 1 - t
		a := u * u * u
		b := 3 * u * u * t
		c := 3 * u * t * t
		d := t * t * t
		pts << Vec2{a * x0 + b * c0x + c * c1x + d * x1, a * y0 + b * y0 + c * y1 + d * y1}
	}
	return pts
}

// link_points - кривая связи l на экране (пусто - нет одной из нод).
fn (ne &NodeEditor) link_points(l NodeLink) []Vec2 {
	a := ne.graph.node(l.from_node) or { return []Vec2{} }
	b := ne.graph.node(l.to_node) or { return []Vec2{} }
	ax, ay := ne.socket_pos(a, true, l.from_slot)
	bx, by := ne.socket_pos(b, false, l.to_slot)
	sx0, sy0 := ne.to_screen(ax, ay)
	sx1, sy1 := ne.to_screen(bx, by)
	return ne_bezier(sx0, sy0, sx1, sy1, 30 * ne.zoom)
}

// ne_segments_cross - пересекаются ли отрезки (p1, p2) и (p3, p4).
fn ne_segments_cross(p1 Vec2, p2 Vec2, p3 Vec2, p4 Vec2) bool {
	d1 := ne_cross(p3, p4, p1)
	d2 := ne_cross(p3, p4, p2)
	d3 := ne_cross(p1, p2, p3)
	d4 := ne_cross(p1, p2, p4)
	return ((d1 > 0) != (d2 > 0)) && ((d3 > 0) != (d4 > 0))
}

fn ne_cross(a Vec2, b Vec2, p Vec2) f32 {
	return (b.x - a.x) * (p.y - a.y) - (b.y - a.y) * (p.x - a.x)
}

// ─── Отмена и события ──────────────────────────────────

// begin_change запоминает граф до правки (только при заданном undo_stack).
fn (mut ne NodeEditor) begin_change() {
	if isnil(ne.undo_stack) || ne.has_pending {
		return
	}
	ne.pending = ne.graph.snapshot()
	ne.has_pending = true
	ne.pending_from = ne.changes
}

// touch - граф изменён правкой пользователя.
fn (mut ne NodeEditor) touch() {
	ne.changes++
}

// commit_change кладёт в стек команду «снимок до -> снимок после», если с begin_change граф
// менялся (щелчок по ноде без сдвига команды не даёт).
fn (mut ne NodeEditor) commit_change(text string) {
	if !ne.has_pending {
		return
	}
	ne.has_pending = false
	if ne.changes == ne.pending_from || isnil(ne.undo_stack) {
		return
	}
	before := ne.pending
	after := ne.graph.snapshot()
	// Замыкания - через локальные переменные (обход vlang/v#28795, PROJECT.md, «Компилятор V»)
	undo := fn [mut ne, before] () {
		ne.restore_state(before)
	}
	redo := fn [mut ne, after] () {
		ne.restore_state(after)
	}
	mut history := ne.undo_stack
	history.record(UndoCommand{
		text: text
		undo: undo
		redo: redo
	})
}

// restore_state - граф к снимку (отмена/повтор): жесты и правка обрываются, выделение
// сохраняется только у нод, которые есть в снимке.
fn (mut ne NodeEditor) restore_state(s NodeGraphState) {
	widget_changed()
	ne.cancel_gesture()
	ne.cancel_text_edit()
	ne.graph.restore(s)
	mut kept := map[int]bool{}
	for id, _ in ne.selected {
		if _ := ne.graph.node(id) {
			kept[id] = true
		}
	}
	ne.selected = kept
	if ne.active !in kept {
		ne.active = 0
	}
	ne.emit(.graph_restored, 0, 0, NodeLink{})
}

fn (ne &NodeEditor) emit(kind NodeEventKind, node int, slot int, link NodeLink) {
	if ne.on_event != unsafe { nil } {
		ne.on_event(NodeEvent{
			kind: kind
			node: node
			slot: slot
			link: link
		})
	}
}

// ─── Рисование ─────────────────────────────────────────

pub fn (mut ne NodeEditor) draw(mut ctx RenderContext) {
	if !ne.visible || !ctx.is_in_clip(ne.bounds) {
		return
	}
	en := ctx.is_enabled(ne.enabled)
	if en {
		ctx.focus.register_node_editor(&ne, ne.focus_group)
	} else {
		ctx.focus_block(&ne)
	}
	ne.focused = ctx.focus.is_focused(&ne) || (ne.editing && !isnil(ne.edit_ti) && ne.edit_ti.focused)
	// Щелчок по другому виджету снял фокус с поля ввода числа - применить введённое
	if ne.editing && !isnil(ne.edit_ti) && !ne.edit_ti.focused {
		ne.commit_text_edit()
	}

	ctx.push_clip(ne.bounds)
	ne.draw_background(mut ctx)
	ne.draw_links(mut ctx)
	for n in ne.graph.nodes {
		ne.draw_node(n, mut ctx)
	}
	ne.draw_gesture(mut ctx)
	if ne.editing && !isnil(ne.edit_ti) {
		if n := ne.graph.node(ne.edit_node) {
			mut ti := ne.edit_ti
			r := ne.screen_rect(ne.edit_rect(n))
			ti.bounds = Rect{r.x, r.y, max_f32(r.w, 60), max_f32(r.h, ctx.control_h() * 0.8)}
			ti.draw(mut ctx)
		}
	}
	if !en {
		ctx.draw_disabled_veil(ne.bounds, 0)
	}
	ctx.pop_clip()
}

// draw_background - фон и сетка: мелкая (ne_grid) и крупная (каждая пятая). Мелкая не рисуется,
// когда её линии ближе 8 px (сетка превратилась бы в сплошной фон).
fn (ne &NodeEditor) draw_background(mut ctx RenderContext) {
	b := ne.bounds
	ctx.fill_rect(b, ctx.theme.eff_ne_bg())
	if !ne.show_grid {
		return
	}
	minor := ctx.theme.eff_ne_grid()
	major := ctx.theme.eff_ne_grid_major()
	step := ne_grid * ne.zoom
	if step < 8 {
		ne.draw_grid_lines(ne_grid * 5, major, mut ctx)
		return
	}
	ne.draw_grid_lines(ne_grid, minor, mut ctx)
	ne.draw_grid_lines(ne_grid * 5, major, mut ctx)
}

fn (ne &NodeEditor) draw_grid_lines(spacing f32, c Color, mut ctx RenderContext) {
	b := ne.bounds
	wx0, wy0 := ne.to_world(b.x, b.y)
	wx1, wy1 := ne.to_world(b.x + b.w, b.y + b.h)
	mut x := f32(int(wx0 / spacing)) * spacing
	for x <= wx1 {
		sx, _ := ne.to_screen(x, 0)
		ctx.fill_rect(Rect{f32(int(sx)), b.y, 1, b.h}, c)
		x += spacing
	}
	mut y := f32(int(wy0 / spacing)) * spacing
	for y <= wy1 {
		_, sy := ne.to_screen(0, y)
		ctx.fill_rect(Rect{b.x, f32(int(sy)), b.w, 1}, c)
		y += spacing
	}
}

// draw_links - связи цветом типа выхода; связи выделенных нод ярче. Отцеплённая и тянущаяся
// связь рисуется в draw_gesture.
fn (ne &NodeEditor) draw_links(mut ctx RenderContext) {
	for l in ne.graph.links {
		if ne.drag == .link && l.id == ne.link_detached {
			continue
		}
		pts := ne.link_points(l)
		a := ne.graph.node(l.from_node) or { continue }
		t := ne.type_of(a)
		mut c := ne.graph.socket_type(t.outputs[l.from_slot].typ).color
		hot := l.from_node in ne.selected || l.to_node in ne.selected
		c = if hot { c.brighten(0.25) } else { c.with_alpha(210) }
		width := ctx.theme.eff_ne_link_width() + if hot { f32(1) } else { f32(0) }
		ctx.draw_polyline(pts, c, width)
	}
}

// ne_header_text - цвет заголовка на шапке цвета c: из темы (ne_header_text), иначе светлый или
// тёмный по яркости шапки (у типов шапки разного цвета, одного цвета текста на все не подобрать).
fn ne_header_text(ctx &RenderContext, c Color) Color {
	if ctx.theme.ne_header_text.a > 0 {
		return ctx.theme.ne_header_text
	}
	return ne_text_color(c)
}

// ne_text_color - светлый или тёмный текст на фоне c (по яркости).
fn ne_text_color(c Color) Color {
	lum := f32(c.r) * 0.299 + f32(c.g) * 0.587 + f32(c.b) * 0.114
	return if lum > 150 { Color{20, 20, 20, 255} } else { Color{240, 240, 240, 255} }
}

// font_px - размер шрифта при текущем масштабе (0 - текст не рисуется).
fn (ne &NodeEditor) font_px(ctx &RenderContext) int {
	if ne.zoom < ne_text_min_zoom {
		return 0
	}
	return int(f32(ctx.fonts.size) * ne.zoom + 0.5)
}

// draw_node - карточка: тень, тело, шапка цветом типа с заголовком и треугольником
// сворачивания, строки выходов и входов (с полями значений), значки сокетов, рамка выделения.
fn (ne &NodeEditor) draw_node(n &GraphNode, mut ctx RenderContext) {
	t := ne.type_of(n)
	r := ne.screen_rect(ne.node_world_rect(n))
	if !r.intersects(ne.bounds) {
		return
	}
	rad := ctx.theme.eff_ne_node_radius() * ne.zoom
	head := if t.color.a > 0 { t.color } else { ctx.theme.eff_ne_header_bg() }
	ctx.draw_shadow(r, rad)
	ctx.fill_rounded_rect(r, ctx.theme.eff_ne_node_bg(), rad)
	// Шапка: скруглена сверху, у развёрнутой ноды низ шапки прямой
	hr := Rect{r.x, r.y, r.w, ne_header_h * ne.zoom}
	ctx.fill_rounded_rect(hr, head, rad)
	if !n.collapsed {
		ctx.fill_rect(Rect{hr.x, hr.y + hr.h * 0.5, hr.w, hr.h * 0.5}, head)
	}
	head_text := ne_header_text(ctx, head)
	ne.draw_collapse_arrow(n, head_text, mut ctx)
	fpx := ne.font_px(ctx)
	renaming := ne.editing && ne.edit_title && ne.edit_node == n.id // поверх - поле ввода
	if fpx > 0 && !renaming {
		font := ctx.get_font(.bold, fpx)
		fh := ctx.font_height_of(font)
		tx := hr.x + 22 * ne.zoom
		title := bc_truncate_text(ctx, ne.graph.node_title(n.id), hr.x + hr.w - tx - 6 * ne.zoom,
			font)
		ctx.draw_text_with_font(title, tx, hr.y + (hr.h - fh) * 0.5, head_text, font)
	}
	if !n.collapsed {
		ne.draw_rows(n, t, fpx, mut ctx)
	}
	// Сокеты
	for s in 0 .. t.outputs.len {
		ne.draw_socket(n, true, s, t.outputs[s].typ, mut ctx)
	}
	for s in 0 .. t.inputs.len {
		ne.draw_socket(n, false, s, t.inputs[s].typ, mut ctx)
	}
	// Рамка: выделенная - акцентом, активная - светлее
	if n.id in ne.selected {
		c := if n.id == ne.active { ctx.theme.eff_ne_active() } else { ctx.theme.eff_ne_selected() }
		ctx.draw_rounded_rect(r.expanded(1), c, rad)
		ctx.draw_rounded_rect(r.expanded(2), c.with_alpha(140), rad)
	} else {
		ctx.draw_rounded_rect(r, ctx.theme.eff_ne_node_border(), rad)
	}
}

fn (ne &NodeEditor) draw_collapse_arrow(n &GraphNode, c Color, mut ctx RenderContext) {
	ar := ne.screen_rect(ne_collapse_rect(n))
	cx := ar.x + ar.w * 0.5
	cy := ar.y + ar.h * 0.5
	s := 4 * ne.zoom
	if n.collapsed {
		ctx.fill_triangle(cx - s * 0.6, cy - s, cx - s * 0.6, cy + s, cx + s * 0.9, cy, c)
	} else {
		ctx.fill_triangle(cx - s, cy - s * 0.6, cx + s, cy - s * 0.6, cx, cy + s * 0.9, c)
	}
}

// draw_rows - подписи выходов (справа) и входов (слева); у неподключённого входа с полем -
// поле значения вместо подписи.
fn (ne &NodeEditor) draw_rows(n &GraphNode, t NodeTypeDef, fpx int, mut ctx RenderContext) {
	if fpx <= 0 {
		// Мелкий масштаб: только плашки полей, без текста
		for s in 0 .. t.inputs.len {
			fr := ne.field_rect(n, s)
			if fr.w > 0 {
				ctx.fill_rounded_rect(ne.screen_rect(fr), ctx.theme.eff_ne_field_bg(), 3 * ne.zoom)
			}
		}
		return
	}
	font := ctx.get_font(.regular, fpx)
	fh := ctx.font_height_of(font)
	tc := ctx.theme.eff_ne_node_text()
	pad := ne_field_inset * ne.zoom
	for s, o in t.outputs {
		ry := ne_row_y(n, s)
		_, sy := ne.to_screen(0, ry)
		sx_right, _ := ne.to_screen(n.x + ne.graph.width_of(n), 0)
		// Узкую ноду (пользователь сузил) подпись не переходит: обрезается многоточием
		name := bc_truncate_text(ctx, o.name, ne.graph.width_of(n) * ne.zoom - pad * 2, font)
		tw := ctx.measure_text_with_font(name, font).x
		ctx.draw_text_with_font(name, sx_right - pad - tw, sy + (ne_row_h * ne.zoom - fh) * 0.5,
			tc, font)
	}
	for s, inp in t.inputs {
		fr := ne.field_rect(n, s)
		if fr.w > 0 {
			ne.draw_field(n, s, inp, ne.screen_rect(fr), font, mut ctx)
			continue
		}
		ry := ne_row_y(n, t.outputs.len + s)
		sx, sy := ne.to_screen(n.x, ry)
		name := bc_truncate_text(ctx, inp.name, ne.graph.width_of(n) * ne.zoom - pad * 2, font)
		ctx.draw_text_with_font(name, sx + pad, sy + (ne_row_h * ne.zoom - fh) * 0.5, tc, font)
	}
}

// draw_field - поле значения входа: число (подпись слева, значение справа), флажок, цвет
// (образец), выбор (текст варианта и стрелка).
fn (ne &NodeEditor) draw_field(n &GraphNode, slot int, def NodeSocketDef, r Rect, font voidptr, mut ctx RenderContext) {
	if ne.editing && !ne.edit_title && ne.edit_node == n.id && ne.edit_slot == slot {
		return // поверх - поле ввода
	}
	v := n.values[slot]
	f := def.field
	rad := 3 * ne.zoom
	fh := ctx.font_height_of(font)
	ty := r.y + (r.h - fh) * 0.5
	pad := 6 * ne.zoom
	tc := ctx.theme.eff_ne_node_text()
	hot := ne.hover.kind == .field && ne.hover.node == n.id && ne.hover.slot == slot
	field_bg := ctx.theme.eff_ne_field_bg()
	bg := if hot { field_bg.brighten(0.08) } else { field_bg }
	match f.kind {
		.number {
			ctx.fill_rounded_rect(r, bg, rad)
			// Доля значения в границах - полоска заполнения, как у ползунка
			if f.min > -1.0e29 && f.max < 1.0e29 && f.max > f.min {
				frac := f32((v.number - f.min) / (f.max - f.min))
				ctx.fill_rounded_rect(Rect{r.x, r.y, r.w * clamp_f32(frac, 0, 1), r.h},
					ctx.theme.eff_ne_field_fill(), rad)
			}
			val := ne_format_number(v.number, f.digits)
			vw := ctx.measure_text_with_font(val, font).x
			name := bc_truncate_text(ctx, def.name, r.w - vw - pad * 3, font)
			ctx.draw_text_with_font(name, r.x + pad, ty, tc, font)
			ctx.draw_text_with_font(val, r.x + r.w - pad - vw, ty, tc, font)
		}
		.toggle {
			box := r.h * 0.7
			br := Rect{r.x, r.y + (r.h - box) * 0.5, box, box}
			ctx.fill_rounded_rect(br, if v.flag { ctx.theme.accent } else { bg }, rad)
			if v.flag {
				m := box * 0.25
				ctx.draw_line_thick(br.x + m, br.y + box * 0.5, br.x + box * 0.42, br.y + box - m,
					2, ctx.theme.accent_text)
				ctx.draw_line_thick(br.x + box * 0.42, br.y + box - m, br.x + box - m, br.y + m,
					2, ctx.theme.accent_text)
			}
			ctx.draw_text_with_font(bc_truncate_text(ctx, def.name, r.w - box - pad, font),
				br.x + box + pad, ty, tc, font)
		}
		.color {
			name_w := r.w * 0.45
			ctx.draw_text_with_font(bc_truncate_text(ctx, def.name, name_w - pad, font), r.x, ty,
				tc, font)
			sw := Rect{r.x + name_w, r.y, r.w - name_w, r.h}
			ctx.fill_rounded_rect(sw, v.color, rad)
			ctx.draw_rounded_rect(sw, ctx.theme.eff_ne_node_border(), rad)
		}
		.choice {
			ctx.fill_rounded_rect(r, bg, rad)
			text := if v.choice >= 0 && v.choice < f.choices.len { f.choices[v.choice] } else { '' }
			ctx.draw_text_with_font(bc_truncate_text(ctx, text, r.w - pad * 3, font), r.x + pad,
				ty, tc, font)
			s := 3 * ne.zoom
			cx := r.x + r.w - pad - s
			cy := r.y + r.h * 0.5
			ctx.fill_triangle(cx - s, cy - s * 0.5, cx + s, cy - s * 0.5, cx, cy + s * 0.7,
				ctx.theme.text_secondary)
		}
		.none {}
	}
}

// ne_format_number - число с digits знаками после запятой (0..6).
fn ne_format_number(v f64, digits int) string {
	return match clamp_int(digits, 0, 6) {
		0 { '${v:.0f}' }
		1 { '${v:.1f}' }
		2 { '${v:.2f}' }
		3 { '${v:.3f}' }
		4 { '${v:.4f}' }
		5 { '${v:.5f}' }
		else { '${v:.6f}' }
	}
}

// draw_socket - значок сокета формой и цветом типа. Подходящий сокет под тянущейся связью -
// крупнее.
fn (ne &NodeEditor) draw_socket(n &GraphNode, out bool, slot int, typ string, mut ctx RenderContext) {
	wx, wy := ne.socket_pos(n, out, slot)
	cx, cy := ne.to_screen(wx, wy)
	st := ne.graph.socket_type(typ)
	mut r := ne_socket_r * ne.zoom
	target := ne.drag == .link && ne.hover.node == n.id && ne.hover.slot == slot
		&& ((out && ne.hover.kind == .socket_out) || (!out && ne.hover.kind == .socket_in))
	if target && ne.link_target_ok(ne.hover) {
		r *= 1.5
	}
	outline := ctx.theme.eff_ne_socket_outline()
	match st.shape {
		.circle {
			ctx.fill_circle(cx, cy, r + 1, outline)
			ctx.fill_circle(cx, cy, r, st.color)
		}
		.square {
			ctx.fill_rect(Rect{cx - r - 1, cy - r - 1, r * 2 + 2, r * 2 + 2}, outline)
			ctx.fill_rect(Rect{cx - r, cy - r, r * 2, r * 2}, st.color)
		}
		.diamond {
			o := r + 1.5
			ctx.fill_triangles([Vec2{cx, cy - o}, Vec2{cx + o, cy}, Vec2{cx, cy + o}, Vec2{cx, cy - o},
				Vec2{cx, cy + o}, Vec2{cx - o, cy}], outline)
			ctx.fill_triangles([Vec2{cx, cy - r}, Vec2{cx + r, cy}, Vec2{cx, cy + r}, Vec2{cx, cy - r},
				Vec2{cx, cy + r}, Vec2{cx - r, cy}], st.color)
		}
	}
}

// draw_gesture - следы жеста: тянущаяся связь, рамка выделения, линия разреза.
fn (ne &NodeEditor) draw_gesture(mut ctx RenderContext) {
	match ne.drag {
		.link {
			n := ne.graph.node(ne.link_node) or { return }
			t := ne.type_of(n)
			typ := if ne.link_from_out {
				t.outputs[ne.link_slot].typ
			} else {
				t.inputs[ne.link_slot].typ
			}
			wx, wy := ne.socket_pos(n, ne.link_from_out, ne.link_slot)
			ax, ay := ne.to_screen(wx, wy)
			pts := if ne.link_from_out {
				ne_bezier(ax, ay, ne.last_x, ne.last_y, 30 * ne.zoom)
			} else {
				ne_bezier(ne.last_x, ne.last_y, ax, ay, 30 * ne.zoom)
			}
			ctx.draw_polyline(pts, ne.graph.socket_type(typ).color.brighten(0.2), 2)
		}
		.box {
			if ne.drag_moved {
				r := ne_rect_of(ne.press_x, ne.press_y, ne.last_x, ne.last_y)
				ctx.fill_rect(r, ctx.theme.accent.with_alpha(40))
				ctx.draw_rect(r, ctx.theme.accent)
			}
		}
		.cut {
			ctx.draw_polyline(ne.cut_pts, ctx.theme.error_color, 2)
		}
		else {}
	}
}

fn ne_rect_of(x0 f32, y0 f32, x1 f32, y1 f32) Rect {
	return Rect{min_f32(x0, x1), min_f32(y0, y1), abs_f32(x1 - x0), abs_f32(y1 - y0)}
}

// ─── События ───────────────────────────────────────────

pub fn (mut ne NodeEditor) handle_event(event &GuiEvent, app &App) bool {
	if !ne.visible {
		return false
	}
	if !ne.enabled && is_input_event(event) {
		ne.cancel_gesture()
		return false
	}
	// Ввод числа с клавиатуры: Enter - применить, Esc - отменить, щелчок мимо - применить и
	// обработать щелчок как обычно, остальное - полю
	if ne.editing && !isnil(ne.edit_ti) {
		mut ti := ne.edit_ti
		if event.typ == .key_down && event.keycode in [sdl_k_return, sdl_k_kp_enter] {
			ne.commit_text_edit()
			ne.focus_self(app)
			return true
		}
		if event.typ == .key_down && event.keycode == sdl_k_escape {
			ne.cancel_text_edit()
			ne.focus_self(app)
			return true
		}
		if event.typ == .mouse_down {
			if ti.bounds.contains(event.mouse_x, event.mouse_y) {
				ti.handle_event(event, app)
				return true
			}
			ne.commit_text_edit()
		} else if event.typ in [.key_down, .key_up, .text_input] {
			ti.handle_event(event, app)
			return true
		} else if ti.handle_event(event, app) {
			return true
		}
	}
	match event.typ {
		.mouse_down {
			return ne.on_mouse_down(event, app)
		}
		.mouse_move {
			return ne.on_mouse_move(event.mouse_x, event.mouse_y)
		}
		.mouse_up {
			return ne.on_mouse_up(event, app)
		}
		.mouse_dbl_click {
			return ne.on_dbl_click(event, app)
		}
		.mouse_wheel {
			ctx := app.get_active_ctx()
			mx := if isnil(ctx) { event.mouse_x } else { ctx.mouse_x }
			my := if isnil(ctx) { event.mouse_y } else { ctx.mouse_y }
			if !ne.bounds.contains(mx, my) || event.wheel_y == 0 {
				return false
			}
			factor := if event.wheel_y > 0 { f32(1.1) } else { f32(1) / f32(1.1) }
			ne.zoom_at(mx, my, ne.zoom * factor)
			return true
		}
		.mouse_leave {
			if ne.drag == .none {
				ne.hover = NodeHit{}
				ne.update_cursor()
			}
			return false
		}
		.key_down {
			if ne.focused {
				return ne.on_key(event, app)
			}
		}
		else {}
	}
	return false
}

// focus_self - фокус редактору (после правки числа и по нажатию мыши на холсте).
fn (mut ne NodeEditor) focus_self(app &App) {
	ctx_ptr := app.get_active_ctx()
	if isnil(ctx_ptr) {
		return
	}
	mut ctx := unsafe { &RenderContext(ctx_ptr) }
	ctx.focus.focus_node_editor(&ne, ne.focus_group)
	ne.focused = true
}

// on_dbl_click - двойной щелчок по шапке - переименовать ноду. Приходит добавкой сразу после
// mouse_down второго щелчка (PROJECT.md, «Двойной клик»): тот уже начал перемещение ноды -
// жест закрывается без правки (команды отмены не будет), и открывается поле заголовка.
// Треугольник сворачивания не трогается: второй щелчок по нему уже снова свернул/развернул.
fn (mut ne NodeEditor) on_dbl_click(event &GuiEvent, app &App) bool {
	if event.mouse_btn != .left || ne.editing {
		return false
	}
	hit := ne.hit_test(event.mouse_x, event.mouse_y)
	if hit.kind != .header {
		return false
	}
	if ne.drag == .move {
		ne.drag = .none
		ne.commit_change('Move nodes')
	}
	ne.rename_node(hit.node, app)
	return true
}

fn (mut ne NodeEditor) on_mouse_down(event &GuiEvent, app &App) bool {
	x, y := event.mouse_x, event.mouse_y
	if !ne.bounds.contains(x, y) {
		return false
	}
	if !ne.editing {
		ne.focus_self(app)
	}
	ne.press_x, ne.press_y = x, y
	ne.last_x, ne.last_y = x, y
	ne.drag_moved = false
	hit := ne.hit_test(x, y)
	match event.mouse_btn {
		.middle {
			ne.drag = .pan
			return true
		}
		.right {
			if event.ctrl() {
				ne.drag = .cut
				ne.cut_pts = [Vec2{x, y}]
			} else if hit.kind == .none {
				ne.open_add_menu(x, y, app)
			}
			return true
		}
		.left {}
		else {
			return false
		}
	}
	match hit.kind {
		.socket_out {
			ne.start_link(hit.node, hit.slot, true, 0)
		}
		.socket_in {
			if l := ne.graph.link_into(hit.node, hit.slot) {
				// Отцепить: связь тянется дальше от своего выхода
				ne.start_link(l.from_node, l.from_slot, true, l.id)
			} else {
				ne.start_link(hit.node, hit.slot, false, 0)
			}
		}
		.collapse {
			ne.begin_change()
			mut n := ne.graph.node(hit.node) or { return true }
			n.collapsed = !n.collapsed
			ne.touch()
			ne.emit(.collapsed, n.id, 0, NodeLink{})
			ne.commit_change('Collapse node')
		}
		.field {
			ne.select_press(hit.node, false)
			ne.press_field(hit.node, hit.slot, app)
		}
		.header, .body {
			ne.select_press(hit.node, event.shift())
			ne.begin_change()
			ne.drag = .move
		}
		.edge {
			n := ne.graph.node(hit.node) or { return true }
			ne.select_press(hit.node, false)
			ne.begin_change()
			ne.drag = .resize
			ne.resize_node = hit.node
			ne.resize_edges = hit.slot
			ne.resize_start = ne.node_world_rect(n)
		}
		.none {
			ne.drag = .box
			ne.box_add = event.shift()
		}
	}
	return true
}

// select_press - выделение по нажатию на ноду: с Shift - переключить её в выделении; без -
// оставить выделение, если нода уже в нём (тащат группу), иначе выделить только её. Нода
// поднимается наверх.
fn (mut ne NodeEditor) select_press(id int, shift bool) {
	if shift {
		if id in ne.selected && ne.active == id {
			ne.selected.delete(id)
			ne.active = 0
		} else {
			ne.selected[id] = true
			ne.active = id
		}
	} else if id !in ne.selected {
		ne.selected = {
			id: true
		}
		ne.active = id
	} else {
		ne.active = id
	}
	ne.graph.raise_node(id)
	ne.emit(.selection_changed, id, 0, NodeLink{})
}

fn (mut ne NodeEditor) start_link(node int, slot int, from_out bool, detached int) {
	ne.drag = .link
	ne.link_node = node
	ne.link_slot = slot
	ne.link_from_out = from_out
	ne.link_detached = detached
}

fn (mut ne NodeEditor) on_mouse_move(x f32, y f32) bool {
	dx := x - ne.last_x
	dy := y - ne.last_y
	if ne.drag != .none && !ne.drag_moved {
		mx := x - ne.press_x
		my := y - ne.press_y
		ne.drag_moved = mx * mx + my * my >= ne_drag_threshold * ne_drag_threshold
	}
	ne.last_x, ne.last_y = x, y
	match ne.drag {
		.none {
			ne.hover = ne.hit_test(x, y)
			ne.update_cursor()
			return false
		}
		.pan {
			ne.view_x -= dx / ne.zoom
			ne.view_y -= dy / ne.zoom
		}
		.move {
			if ne.drag_moved {
				for mut n in ne.graph.nodes {
					if n.id in ne.selected {
						n.x += dx / ne.zoom
						n.y += dy / ne.zoom
					}
				}
				ne.touch()
			}
		}
		.link {
			ne.hover = ne.hit_test(x, y)
		}
		.cut {
			last := ne.cut_pts.last()
			if abs_f32(x - last.x) + abs_f32(y - last.y) > 4 {
				ne.cut_pts << Vec2{x, y}
			}
		}
		.number {
			if ne.drag_moved {
				ne.drag_number(x)
			}
		}
		.resize {
			if ne.drag_moved {
				ne.drag_resize(x, y)
			}
		}
		.box {}
	}
	return true
}

fn (mut ne NodeEditor) on_mouse_up(event &GuiEvent, app &App) bool {
	if ne.drag == .none {
		return false
	}
	x, y := event.mouse_x, event.mouse_y
	drag := ne.drag
	moved := ne.drag_moved
	ne.drag = .none
	match drag {
		.move {
			if moved {
				ne.emit(.nodes_moved, ne.active, 0, NodeLink{})
			}
			ne.commit_change('Move nodes')
		}
		.box {
			ne.finish_box(x, y, moved)
		}
		.link {
			ne.finish_link(x, y, app)
		}
		.cut {
			ne.finish_cut()
		}
		.number {
			if moved {
				ne.commit_change('Change value')
			} else {
				ne.has_pending = false
				ne.start_text_edit(ne.num_node, ne.num_slot, app)
			}
		}
		.resize {
			if moved {
				ne.emit(.node_resized, ne.resize_node, 0, NodeLink{})
			}
			ne.commit_change('Resize node')
		}
		else {}
	}
	ne.hover = ne.hit_test(x, y)
	ne.update_cursor()
	return true
}

// finish_box - выделение рамкой; щелчок по пустому месту без Shift снимает выделение.
fn (mut ne NodeEditor) finish_box(x f32, y f32, moved bool) {
	if !moved {
		if !ne.box_add && ne.selected.len > 0 {
			ne.selected = map[int]bool{}
			ne.active = 0
			ne.emit(.selection_changed, 0, 0, NodeLink{})
		}
		return
	}
	if !ne.box_add {
		ne.selected = map[int]bool{}
	}
	sel := ne_rect_of(ne.press_x, ne.press_y, x, y)
	for n in ne.graph.nodes {
		if ne.screen_rect(ne.node_world_rect(n)).intersects(sel) {
			ne.selected[n.id] = true
		}
	}
	ne.emit(.selection_changed, 0, 0, NodeLink{})
}

// link_target_ok - можно ли закончить тянущуюся связь на сокете h.
fn (ne &NodeEditor) link_target_ok(h NodeHit) bool {
	if ne.link_from_out {
		if h.kind != .socket_in {
			return false
		}
		// Отцеплённую связь вернули на тот же вход - допустимо (ничего не меняется)
		if l := ne.graph.link_by_id(ne.link_detached) {
			if l.to_node == h.node && l.to_slot == h.slot {
				return true
			}
		}
		ne.graph.check_link(ne.link_node, ne.link_slot, h.node, h.slot) or { return false }
		return true
	}
	if h.kind != .socket_out {
		return false
	}
	ne.graph.check_link(h.node, h.slot, ne.link_node, ne.link_slot) or { return false }
	return true
}

// menu_link_slot - первый сокет типа t, к которому подключается связь меню (вход, если связь
// тянули с выхода, иначе выход); -1 - такого нет. Только проверка типов: вето приложения и
// циклы проверит connect, когда нода уже будет создана.
fn (ne &NodeEditor) menu_link_slot(t NodeTypeDef) int {
	n := ne.graph.node(ne.menu.link_node) or { return -1 }
	nt := ne.type_of(n)
	if ne.menu.link_from_out {
		if ne.menu.link_slot >= nt.outputs.len {
			return -1
		}
		from := nt.outputs[ne.menu.link_slot].typ
		for i, inp in t.inputs {
			if ne.graph.types_compatible(from, inp.typ) {
				return i
			}
		}
		return -1
	}
	if ne.menu.link_slot >= nt.inputs.len {
		return -1
	}
	to := nt.inputs[ne.menu.link_slot].typ
	for i, o in t.outputs {
		if ne.graph.types_compatible(o.typ, to) {
			return i
		}
	}
	return -1
}

// finish_link - отпускание тянущейся связи: на подходящий сокет - связь (замена на занятом
// входе); мимо - отцеплённая связь удаляется. Всё - одна команда отмены. Новая (не
// отцеплённая) связь, отпущенная на пустом холсте, открывает меню добавления с подходящими
// типами: выбранная нода подключится к ней (add_from_menu).
fn (mut ne NodeEditor) finish_link(x f32, y f32, app &App) {
	h := ne.hit_test(x, y)
	ok := ne.link_target_ok(h)
	if !ok && ne.link_detached == 0 && h.kind == .none && ne.bounds.contains(x, y) {
		ne.open_menu(x, y, ne.link_node, ne.link_slot, ne.link_from_out, app)
		return
	}
	detached := ne.graph.link_by_id(ne.link_detached) or { NodeLink{} }
	// Вернули отцеплённую связь на её же вход - ничего не изменилось
	if detached.id != 0 && ok && h.node == detached.to_node && h.slot == detached.to_slot {
		return
	}
	if !ok && detached.id == 0 {
		return
	}
	ne.begin_change()
	if detached.id != 0 {
		ne.graph.disconnect(detached.id)
		ne.touch()
		ne.emit(.link_removed, 0, 0, detached)
	}
	if ok {
		from_node, from_slot, to_node, to_slot := if ne.link_from_out {
			ne.link_node, ne.link_slot, h.node, h.slot
		} else {
			h.node, h.slot, ne.link_node, ne.link_slot
		}
		if res := ne.graph.connect(from_node, from_slot, to_node, to_slot) {
			if res.replaced.id != 0 {
				ne.emit(.link_removed, 0, 0, res.replaced)
			}
			ne.touch()
			ne.emit(.link_added, 0, 0, res.link)
		}
	}
	ne.commit_change(if ok { 'Connect' } else { 'Disconnect' })
}

// finish_cut - удалить связи, пересечённые линией разреза.
fn (mut ne NodeEditor) finish_cut() {
	if ne.cut_pts.len < 2 {
		return
	}
	mut doomed := []NodeLink{}
	for l in ne.graph.links {
		pts := ne.link_points(l)
		if ne_polylines_cross(pts, ne.cut_pts) {
			doomed << l
		}
	}
	ne.cut_pts = []Vec2{}
	if doomed.len == 0 {
		return
	}
	ne.begin_change()
	for l in doomed {
		ne.graph.disconnect(l.id)
		ne.emit(.link_removed, 0, 0, l)
	}
	ne.touch()
	ne.commit_change('Cut links')
}

fn ne_polylines_cross(a []Vec2, b []Vec2) bool {
	for i in 1 .. a.len {
		for j in 1 .. b.len {
			if ne_segments_cross(a[i - 1], a[i], b[j - 1], b[j]) {
				return true
			}
		}
	}
	return false
}

// cancel_gesture - оборвать жест (Esc, потеря фокуса, отмена): сдвинутые ноды остаются, где
// их бросили, - как при отпускании; несостоявшиеся связь/рамка/разрез пропадают.
fn (mut ne NodeEditor) cancel_gesture() {
	match ne.drag {
		.move { ne.commit_change('Move nodes') }
		.number { ne.commit_change('Change value') }
		.resize { ne.commit_change('Resize node') }
		else {}
	}
	ne.drag = .none
	ne.cut_pts = []Vec2{}
	ne.hover = NodeHit{}
	ne.update_cursor()
}

// drag_resize - шаг изменения размера: по каждой тянущейся оси новый размер = начальный ± сдвиг
// мыши от нажатия (в единицах холста; от точки нажатия, а не от прошлого шага - зажим не копит
// ошибку). Противоположный край стоит на месте: тянут левый (верхний) край - x (y) сдвигается на
// столько, на сколько изменился размер уже после зажима, иначе упёршаяся в предел нода поехала бы.
fn (mut ne NodeEditor) drag_resize(x f32, y f32) {
	n := ne.graph.node(ne.resize_node) or { return }
	s := ne.resize_start
	dx := (x - ne.press_x) / ne.zoom
	dy := (y - ne.press_y) / ne.zoom
	mut nx, mut ny := s.x, s.y
	edges := ne.resize_edges
	if edges & (ne_edge_left | ne_edge_right) != 0 {
		left := edges & ne_edge_left != 0
		want := if left { s.w - dx } else { s.w + dx }
		// Не меньше 1: ширина <= 0 для set_node_width значит «вернуть ширину типа», а мышь,
		// сжавшая ноду до упора, должна дать минимальную ширину
		ne.graph.set_node_width(n.id, max_f32(want, 1))
		if left {
			nx = s.x + s.w - ne.graph.width_of(n)
		}
	}
	if edges & (ne_edge_top | ne_edge_bottom) != 0 {
		top := edges & ne_edge_top != 0
		want := if top { s.h - dy } else { s.h + dy }
		// Так же: 0 и меньше - «по содержимому», а сжатая до упора нода и есть по содержимому
		ne.graph.set_node_height(n.id, max_f32(want, 1))
		if top {
			ny = s.y + s.h - ne.graph.height_of(n)
		}
	}
	ne.graph.set_node_pos(n.id, nx, ny)
	ne.touch()
}

// resize_cursor - системный курсор для краёв маски edges: «влево-вправо», «вверх-вниз» или
// диагональ для угла (левый верхний и правый нижний - одна диагональ, два других - другая).
fn ne_resize_cursor(edges int) int {
	horiz := edges & (ne_edge_left | ne_edge_right) != 0
	vert := edges & (ne_edge_top | ne_edge_bottom) != 0
	if horiz && vert {
		main_diag := edges in [ne_edge_left | ne_edge_top, ne_edge_right | ne_edge_bottom]
		return if main_diag { sdl_system_cursor_sizenwse } else { sdl_system_cursor_sizenesw }
	}
	return if vert { sdl_system_cursor_sizens } else { sdl_system_cursor_sizewe }
}

// update_cursor - курсор изменения размера над краем или углом ноды и во время жеста; иначе -
// курсор, который был до него (как у полос DockArea и Splitter).
fn (mut ne NodeEditor) update_cursor() {
	edges := if ne.drag == .resize {
		ne.resize_edges
	} else if ne.drag == .none && ne.hover.kind == .edge {
		ne.hover.slot
	} else {
		0
	}
	if edges != 0 {
		if ne.saved_cursor == unsafe { nil } {
			ne.saved_cursor = current_cursor()
		}
		set_cursor(ne_resize_cursor(edges))
	} else if ne.saved_cursor != unsafe { nil } {
		restore_cursor_handle(ne.saved_cursor)
		ne.saved_cursor = unsafe { nil }
	}
}

// on_key - сочетания редактора в фокусе. Буквы - по физической клавише в нелатинской
// раскладке (ctrl_letter, PROJECT.md «Сочетания Ctrl+буква»).
fn (mut ne NodeEditor) on_key(event &GuiEvent, app &App) bool {
	k := event.keycode
	if k == sdl_k_escape && ne.drag != .none {
		ne.cancel_gesture()
		return true
	}
	if k == sdl_k_delete || (!event.ctrl() && !event.shift() && ctrl_letter(event, `x`, 27)) {
		ne.delete_selected()
		return true
	}
	if k == sdl_k_home {
		ne.frame_all()
		return true
	}
	if k == sdl_k_f2 && ne.active != 0 && ne.active in ne.selected {
		ne.rename_node(ne.active, app)
		return true
	}
	if event.ctrl() && ctrl_letter(event, `a`, 4) {
		ne.selected = map[int]bool{}
		for n in ne.graph.nodes {
			ne.selected[n.id] = true
		}
		ne.emit(.selection_changed, 0, 0, NodeLink{})
		return true
	}
	if event.shift() && !event.ctrl() && ctrl_letter(event, `a`, 4) {
		ctx := app.get_active_ctx()
		mx := if isnil(ctx) { ne.bounds.x + ne.bounds.w * 0.5 } else { ctx.mouse_x }
		my := if isnil(ctx) { ne.bounds.y + ne.bounds.h * 0.5 } else { ctx.mouse_y }
		ne.open_add_menu(mx, my, app)
		return true
	}
	if event.shift() && !event.ctrl() && ctrl_letter(event, `d`, 7) {
		ne.duplicate_selected()
		return true
	}
	// Буфер обмена: Ctrl+C / Ctrl+X / Ctrl+V (сканкоды C = 6, X = 27, V = 25)
	if event.ctrl() && !event.shift() && ctrl_letter(event, `c`, 6) {
		ne.copy_selected(app)
		return true
	}
	if event.ctrl() && !event.shift() && ctrl_letter(event, `x`, 27) {
		ne.cut_selected(app)
		return true
	}
	if event.ctrl() && !event.shift() && ctrl_letter(event, `v`, 25) {
		ne.paste(app)
		return true
	}
	if !event.ctrl() && !event.shift() && ctrl_letter(event, `h`, 11) {
		ne.toggle_collapse_selected()
		return true
	}
	return false
}

// ─── Буфер обмена ──────────────────────────────────────

// copy_selected кладёт выделенные ноды и связи между ними в системный буфер обмена строкой JSON
// (NodeGraph.copy_json): её вставит этот же редактор, другой редактор или другой запуск
// приложения, а снаружи она читается как текст. Без выделения буфер не трогается.
pub fn (mut ne NodeEditor) copy_selected(app &App) {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	app.set_clipboard(ne.graph.copy_json(ids))
}

// cut_selected - копировать в буфер и удалить (удаление - одна команда отмены, как Delete).
pub fn (mut ne NodeEditor) cut_selected(app &App) {
	if ne.selected.len == 0 {
		return
	}
	ne.copy_selected(app)
	ne.delete_selected()
}

// paste вставляет ноды из буфера обмена (NodeGraph.paste_json): левый верхний угол вставленной
// группы - под курсором, если он над редактором, иначе в середине видимой части. Вставленные
// ноды выделяются; всё - одна команда отмены. Не граф в буфере (обычный текст) - ничего не
// происходит: Ctrl+V не должен ни ломать граф, ни ругаться на чужой текст.
pub fn (mut ne NodeEditor) paste(app &App) {
	text := app.get_clipboard()
	if text == '' {
		return
	}
	ctx := app.get_active_ctx()
	mut sx, mut sy := ne.bounds.x + ne.bounds.w * 0.5, ne.bounds.y + ne.bounds.h * 0.5
	if !isnil(ctx) && ne.bounds.contains(ctx.mouse_x, ctx.mouse_y) {
		sx, sy = ctx.mouse_x, ctx.mouse_y
	}
	wx, wy := ne.to_world(sx, sy)
	ne.begin_change()
	res := ne.graph.paste_json(text, wx, wy) or {
		ne.commit_change('Paste nodes') // граф не менялся - команды не будет
		return
	}
	for id in res.nodes {
		ne.emit(.node_added, id, 0, NodeLink{})
	}
	for l in res.links {
		ne.emit(.link_added, 0, 0, l)
	}
	ne.selected = map[int]bool{}
	for id in res.nodes {
		ne.selected[id] = true
	}
	ne.active = if res.nodes.len > 0 { res.nodes.last() } else { 0 }
	ne.touch()
	ne.commit_change('Paste nodes')
	ne.emit(.selection_changed, 0, 0, NodeLink{})
}

// duplicate_selected - копии выделенных нод (со значениями) и связей между ними, сдвинутые на
// 20 единиц; выделяются копии.
pub fn (mut ne NodeEditor) duplicate_selected() {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	widget_changed()
	ne.begin_change()
	mut copy_of := map[int]int{}
	for id in ids {
		src := ne.graph.node(id) or { continue }
		nid := ne.graph.add_node(src.type_id, src.x + 20, src.y + 20) or { continue }
		mut dst := ne.graph.node(nid) or { continue }
		dst.values = src.values.clone()
		dst.collapsed = src.collapsed
		dst.width = src.width
		dst.height = src.height
		dst.title = src.title
		copy_of[id] = nid
		ne.emit(.node_added, nid, 0, NodeLink{})
	}
	for l in ne.graph.links.clone() {
		a := copy_of[l.from_node] or { continue }
		b := copy_of[l.to_node] or { continue }
		if res := ne.graph.connect(a, l.from_slot, b, l.to_slot) {
			ne.emit(.link_added, 0, 0, res.link)
		}
	}
	ne.selected = map[int]bool{}
	for _, nid in copy_of {
		ne.selected[nid] = true
	}
	ne.touch()
	ne.commit_change('Duplicate nodes')
	ne.emit(.selection_changed, 0, 0, NodeLink{})
}

// toggle_collapse_selected - свернуть выделенные (если хоть одна развёрнута), иначе развернуть.
fn (mut ne NodeEditor) toggle_collapse_selected() {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	mut any_open := false
	for id in ids {
		n := ne.graph.node(id) or { continue }
		any_open = any_open || !n.collapsed
	}
	ne.begin_change()
	for id in ids {
		mut n := ne.graph.node(id) or { continue }
		n.collapsed = any_open
		ne.emit(.collapsed, id, 0, NodeLink{})
	}
	ne.touch()
	ne.commit_change('Collapse nodes')
}

// ─── Поля значений ─────────────────────────────────────

// press_field - нажатие на поле: флажок переключается, цвет и выбор открывают диалог и список,
// число начинает протяжку (щелчок без протяжки - ввод с клавиатуры, on_mouse_up).
fn (mut ne NodeEditor) press_field(node int, slot int, app &App) {
	n := ne.graph.node(node) or { return }
	t := ne.type_of(n)
	f := t.inputs[slot].field
	v := n.values[slot]
	match f.kind {
		.number {
			ne.drag = .number
			ne.num_node = node
			ne.num_slot = slot
			ne.num_start = v.number
			ne.begin_change()
		}
		.toggle {
			ne.set_field(node, slot, NodeValue{ ...v, flag: !v.flag }, 'Toggle value')
		}
		.color {
			ne.open_color_dialog(node, slot, app)
		}
		.choice {
			ne.open_choice_menu(node, slot, f.choices, v.choice, app)
		}
		.none {}
	}
}

// set_field - значение входа как одна правка (отмена, событие).
fn (mut ne NodeEditor) set_field(node int, slot int, v NodeValue, text string) {
	ne.begin_change()
	if ne.graph.set_value(node, slot, v) {
		ne.touch()
		ne.emit(.value_changed, node, slot, NodeLink{})
	}
	ne.commit_change(text)
}

// drag_number - протяжка числа: шаг поля на каждые 10 px сдвига (с Shift - в 10 раз мельче
// не делаем: протяжка и так плавная).
fn (mut ne NodeEditor) drag_number(x f32) {
	n := ne.graph.node(ne.num_node) or { return }
	t := ne.type_of(n)
	f := t.inputs[ne.num_slot].field
	mut v := n.values[ne.num_slot]
	v.number = ne.num_start + f64(x - ne.press_x) / 10.0 * f.step
	if ne.graph.set_value(ne.num_node, ne.num_slot, v) {
		ne.touch()
		ne.emit(.value_changed, ne.num_node, ne.num_slot, NodeLink{})
	}
}

// start_text_edit - ввод числа с клавиатуры: внутреннее поле поверх поля значения с текущим
// значением, выделенным целиком; фокус - полю (редактор - его владелец, FocusOwner).
fn (mut ne NodeEditor) start_text_edit(node int, slot int, app &App) {
	n := ne.graph.node(node) or { return }
	t := ne.type_of(n)
	ne.open_edit(node, ne_format_number(n.values[slot].number, t.inputs[slot].field.digits), app)
	ne.edit_slot = slot
	ne.edit_title = false
}

// rename_node - ввод своего заголовка ноды поверх шапки (F2 по активной ноде, двойной щелчок по
// шапке): Enter или щелчок мимо - применить, Esc - отменить. Пустой текст или заголовок типа -
// вернуть заголовок типа (set_node_title(id, '')).
pub fn (mut ne NodeEditor) rename_node(id int, app &App) {
	_ := ne.graph.node(id) or { return }
	ne.open_edit(id, ne.graph.node_title(id), app)
	ne.edit_title = true
}

// edit_rect - где на холсте стоит поле ввода: поверх поля числа или поверх заголовка в шапке
// (правее треугольника сворачивания).
fn (ne &NodeEditor) edit_rect(n &GraphNode) Rect {
	if ne.edit_title {
		return Rect{n.x + 20, n.y + 2, ne.graph.width_of(n) - 24, ne_header_h - 4}
	}
	return ne.field_rect(n, ne.edit_slot)
}

// open_edit - показать внутреннее поле ввода с текстом text (выделен целиком) для ноды node и
// отдать ему фокус. Общий шаг ввода числа и заголовка.
fn (mut ne NodeEditor) open_edit(node int, text string, app &App) {
	if isnil(ne.edit_ti) {
		mut ti := text_input('')
		ti.pad = 3
		ne.edit_ti = ti
	}
	mut ti := ne.edit_ti
	ti.set_text(text)
	ti.sel_a = 0
	ti.sel_b = ti.buf.len
	ti.cur = ti.buf.len
	ti.focus_group = ne.focus_group
	ne.editing = true
	ne.edit_node = node
	ctx_ptr := app.get_active_ctx()
	if !isnil(ctx_ptr) {
		mut ctx := unsafe { &RenderContext(ctx_ptr) }
		ctx.focus.focus_text_input(ti, ne.focus_group)
	}
	ti.focused = true
}

// commit_text_edit - применить введённое: заголовок (commit_rename) или число (нечисловой текст -
// правки нет).
fn (mut ne NodeEditor) commit_text_edit() {
	if !ne.editing {
		return
	}
	if ne.edit_title {
		ne.commit_rename()
		return
	}
	text := ne.edit_ti.get_text().trim_space().replace(',', '.')
	node, slot := ne.edit_node, ne.edit_slot
	ne.cancel_text_edit()
	if text == '' || !(text[0].is_digit() || text[0] in [`-`, `+`, `.`]) {
		return
	}
	v := ne.graph.value(node, slot) or { return }
	ne.set_field(node, slot, NodeValue{ ...v, number: text.f64() }, 'Change value')
}

// commit_rename - свой заголовок ноды из поля ввода. Совпал с заголовком типа или пуст - свой
// заголовок снимается (иначе переименование «в то же самое» навсегда отвязало бы ноду от
// заголовка типа). Не изменился - команды отмены и события нет.
fn (mut ne NodeEditor) commit_rename() {
	text := ne.edit_ti.get_text().trim_space()
	id := ne.edit_node
	ne.cancel_text_edit()
	n := ne.graph.node(id) or { return }
	t := ne.type_of(n)
	title := if text == t.title { '' } else { text }
	if title == n.title {
		return
	}
	ne.begin_change()
	ne.graph.set_node_title(id, title)
	ne.touch()
	ne.emit(.node_renamed, id, 0, NodeLink{})
	ne.commit_change('Rename node')
}

fn (mut ne NodeEditor) cancel_text_edit() {
	if !ne.editing {
		return
	}
	ne.editing = false
	mut ti := ne.edit_ti
	ti.focused = false
}

// open_choice_menu - выпадающий список вариантов под полем (ContextMenu в слоте оверлея окна).
fn (mut ne NodeEditor) open_choice_menu(node int, slot int, choices []string, current int, app &App) {
	ctx_ptr := app.get_active_ctx()
	if isnil(ctx_ptr) || choices.len == 0 {
		return
	}
	mut ctx := unsafe { &RenderContext(ctx_ptr) }
	n := ne.graph.node(node) or { return }
	mut cm := context_menu()
	for i, text in choices {
		mut item := menu_checkbox(text, i == current)
		// Замыкание - через локальную переменную (обход vlang/v#28795)
		handler := fn [mut ne, node, slot, i] (_ bool) {
			v := ne.graph.value(node, slot) or { return }
			if v.choice != i {
				ne.set_field(node, slot, NodeValue{ ...v, choice: i }, 'Change value')
			}
		}
		item.on_toggle = handler
		cm.add(item)
	}
	ne.choice_menu = cm
	r := ne.screen_rect(ne.field_rect(n, slot))
	cm.show(r.x, r.y + r.h, mut ctx)
}

// open_color_dialog - модальный выбор цвета над окном редактора (как у PropertyGrid).
fn (mut ne NodeEditor) open_color_dialog(node int, slot int, app &App) {
	parent := ne_active_window(app) or { return }
	v := ne.graph.value(node, slot) or { return }
	mut mapp := unsafe { &App(app) }
	chosen, ok := color_dialog(parent, mut mapp, ColorDialogConfig{ color: v.color })
	if ok && chosen != v.color {
		ne.set_field(node, slot, NodeValue{ ...v, color: chosen }, 'Change color')
	}
}

// ne_active_window - окно (или диалог), чей контекст сейчас активен: родитель для модального
// диалога.
fn ne_active_window(app &App) ?&Window {
	if isnil(app) {
		return none
	}
	ctx_ptr := app.get_active_ctx()
	if isnil(ctx_ptr) {
		return none
	}
	for w in app.windows {
		if w.open && unsafe { &w.ctx == ctx_ptr } {
			return w
		}
	}
	for d in app.dialogs {
		if d.is_open() && unsafe { &d.win.ctx == ctx_ptr } {
			return &d.win
		}
	}
	return none
}

// ─── Меню добавления ноды ──────────────────────────────

// open_add_menu - меню добавления с поиском в точке экрана (x, y); нода встанет туда же.
// Меню живёт в слоте оверлея окна (PROJECT.md, «Оверлеи попапов»): получает события раньше
// виджетов, поэтому ввод в поле поиска и стрелки обрабатывает само.
pub fn (mut ne NodeEditor) open_add_menu(x f32, y f32, app &App) {
	ne.open_menu(x, y, 0, 0, false, app)
}

// open_menu - меню добавления в точке экрана (x, y); link_node != 0 - меню для связи, отпущенной в
// пустоте (с выхода, если link_from_out, иначе со входа link_slot ноды link_node).
fn (mut ne NodeEditor) open_menu(x f32, y f32, link_node int, link_slot int, link_from_out bool, app &App) {
	ctx_ptr := app.get_active_ctx()
	if isnil(ctx_ptr) || ne.graph.type_order.len == 0 {
		return
	}
	mut ctx := unsafe { &RenderContext(ctx_ptr) }
	ne.menu_ctx = ctx
	wx, wy := ne.to_world(x, y)
	ne.menu = NodeAddMenu{
		open:          true
		x:             x
		y:             y
		world_x:       wx
		world_y:       wy
		link_node:     link_node
		link_slot:     link_slot
		link_from_out: link_from_out
	}
	if isnil(ne.menu_ti) {
		mut ti := text_input(tr('Search...'))
		ti.pad = 4
		ne.menu_ti = ti
	}
	mut ti := ne.menu_ti
	ti.set_text('')
	ne.filter_menu()
	ctx.focus.focus_text_input(ti, ne.focus_group)
	ti.focused = true
	draw := fn [mut ne] (mut c RenderContext) {
		ne.draw_add_menu(mut c)
	}
	ev := fn [mut ne] (e &GuiEvent, a &App) bool {
		return ne.add_menu_event(e, a)
	}
	close := fn [mut ne] (mut _ RenderContext) {
		ne.menu.open = false
		mut t := ne.menu_ti
		t.focused = false
	}
	ctx.set_overlay(voidptr(&ne), draw, ev, close)
}

// close_add_menu - закрыть меню и вернуть фокус редактору.
fn (mut ne NodeEditor) close_add_menu() {
	if !ne.menu.open {
		return
	}
	ne.menu.open = false
	mut ti := ne.menu_ti
	ti.focused = false
	if !isnil(ne.menu_ctx) {
		mut ctx := ne.menu_ctx
		ctx.clear_overlay(voidptr(&ne))
		ctx.focus.focus_node_editor(&ne, ne.focus_group)
		ctx.invalidate_all()
	}
}

// filter_menu - типы, в заголовке или категории которых есть текст поиска (без учёта регистра),
// по категориям в порядке описания.
fn (mut ne NodeEditor) filter_menu() {
	query := ne.menu_ti.get_text().trim_space().to_lower()
	mut cats := []string{}
	for id in ne.graph.type_order {
		t := ne.graph.types[id] or { continue }
		if t.category !in cats {
			cats << t.category
		}
	}
	mut items := []string{}
	for cat in cats {
		for id in ne.graph.type_order {
			t := ne.graph.types[id] or { continue }
			if t.category != cat {
				continue
			}
			if ne.menu.link_node != 0 && ne.menu_link_slot(t) < 0 {
				continue // к связи из меню этот тип не подключить
			}
			if query == '' || t.title.to_lower().contains(query) || cat.to_lower().contains(query) {
				items << id
			}
		}
	}
	ne.menu.items = items
	ne.menu.hover = 0
	ne.menu.scroll = 0
}

// menu_rect / menu_row_rect - попап меню (сдвинут, чтобы влезть в окно) и строка i списка.
fn (ne &NodeEditor) menu_rect(ctx &RenderContext) Rect {
	rows := if ne.menu.items.len == 0 { 1 } else { min_int(ne.menu.items.len, ne_menu_rows) }
	h := ctx.control_h() + 8 + f32(rows) * ne_menu_row_h + 4
	x := clamp_f32(ne.menu.x, 0, max_f32(0, ctx.screen_width - ne_menu_w))
	y := clamp_f32(ne.menu.y, 0, max_f32(0, ctx.screen_height - h))
	return Rect{x, y, ne_menu_w, h}
}

fn (ne &NodeEditor) menu_row_rect(ctx &RenderContext, i int) Rect {
	r := ne.menu_rect(ctx)
	top := r.y + ctx.control_h() + 8
	return Rect{r.x + 2, top + f32(i - ne.menu.scroll) * ne_menu_row_h, r.w - 4, ne_menu_row_h}
}

fn (mut ne NodeEditor) draw_add_menu(mut ctx RenderContext) {
	if !ne.menu.open {
		return
	}
	r := ne.menu_rect(ctx)
	rad := ctx.theme.border_radius
	ctx.draw_shadow(r, rad)
	ctx.fill_rounded_rect(r, ctx.theme.surface, rad)
	ctx.draw_rounded_rect(r, ctx.theme.border, rad)
	mut ti := ne.menu_ti
	ti.bounds = Rect{r.x + 4, r.y + 4, r.w - 8, ctx.control_h()}
	ti.draw(mut ctx)
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	if ne.menu.items.len == 0 {
		row := ne.menu_row_rect(ctx, 0)
		ctx.draw_text_with_font(tr('Nothing found'), row.x + 8, row.y + (row.h - fh) * 0.5,
			ctx.theme.text_hint, font)
		return
	}
	last := min_int(ne.menu.items.len, ne.menu.scroll + ne_menu_rows)
	for i in ne.menu.scroll .. last {
		row := ne.menu_row_rect(ctx, i)
		t := ne.graph.types[ne.menu.items[i]] or { continue }
		if i == ne.menu.hover {
			ctx.fill_rounded_rect(row, ctx.theme.accent, 4)
		}
		tc := if i == ne.menu.hover { ctx.theme.accent_text } else { ctx.theme.text_primary }
		cc := if i == ne.menu.hover { ctx.theme.accent_text } else { ctx.theme.text_secondary }
		// Метка цвета категории, заголовок, справа - категория
		ctx.fill_rounded_rect(Rect{row.x + 6, row.y + 7, 4, row.h - 14}, t.color, 2)
		cw := ctx.measure_text_with_font(t.category, font).x
		ctx.draw_text_with_font(bc_truncate_text(ctx, t.title, row.w - cw - 30, font), row.x + 16,
			row.y + (row.h - fh) * 0.5, tc, font)
		ctx.draw_text_with_font(t.category, row.x + row.w - cw - 8, row.y + (row.h - fh) * 0.5,
			cc, font)
	}
}

// add_menu_event - события, пока меню открыто: Esc - закрыть, стрелки/Enter - выбор, печать -
// в поле поиска (список фильтруется), щелчок по строке - добавить, щелчок мимо - закрыть.
fn (mut ne NodeEditor) add_menu_event(ev &GuiEvent, app &App) bool {
	if !ne.menu.open || isnil(ne.menu_ctx) {
		return false
	}
	ctx := ne.menu_ctx
	mut ti := ne.menu_ti
	r := ne.menu_rect(ctx)
	match ev.typ {
		.key_down {
			match ev.keycode {
				sdl_k_escape {
					ne.close_add_menu()
				}
				sdl_k_up {
					ne.menu_move(-1)
				}
				sdl_k_down {
					ne.menu_move(1)
				}
				sdl_k_return, sdl_k_kp_enter {
					ne.add_from_menu(ne.menu.hover)
				}
				else {
					before := ti.get_text()
					ti.handle_event(ev, app)
					if ti.get_text() != before {
						ne.filter_menu()
					}
				}
			}
			return true
		}
		.key_up {
			return true
		}
		.text_input {
			ti.handle_event(ev, app)
			ne.filter_menu()
			return true
		}
		.mouse_move {
			for i in ne.menu.scroll .. min_int(ne.menu.items.len, ne.menu.scroll + ne_menu_rows) {
				if ne.menu_row_rect(ctx, i).contains(ev.mouse_x, ev.mouse_y) {
					ne.menu.hover = i
				}
			}
			ti.handle_event(ev, app)
			return r.contains(ev.mouse_x, ev.mouse_y)
		}
		.mouse_down {
			if !r.contains(ev.mouse_x, ev.mouse_y) {
				ne.close_add_menu()
				return true
			}
			if ti.bounds.contains(ev.mouse_x, ev.mouse_y) {
				ti.handle_event(ev, app)
				return true
			}
			for i in ne.menu.scroll .. min_int(ne.menu.items.len, ne.menu.scroll + ne_menu_rows) {
				if ne.menu_row_rect(ctx, i).contains(ev.mouse_x, ev.mouse_y) {
					ne.add_from_menu(i)
					break
				}
			}
			return true
		}
		.mouse_up, .mouse_dbl_click {
			ti.handle_event(ev, app)
			return r.contains(ev.mouse_x, ev.mouse_y)
		}
		.mouse_wheel {
			if r.contains(ctx.mouse_x, ctx.mouse_y) {
				max_scroll := max_int(0, ne.menu.items.len - ne_menu_rows)
				ne.menu.scroll = clamp_int(ne.menu.scroll - int(ev.wheel_y), 0, max_scroll)
				return true
			}
			return false
		}
		else {
			return false
		}
	}
}

// menu_move - выбор строки стрелками; список прокручивается за выбором.
fn (mut ne NodeEditor) menu_move(delta int) {
	if ne.menu.items.len == 0 {
		return
	}
	ne.menu.hover = clamp_int(ne.menu.hover + delta, 0, ne.menu.items.len - 1)
	if ne.menu.hover < ne.menu.scroll {
		ne.menu.scroll = ne.menu.hover
	} else if ne.menu.hover >= ne.menu.scroll + ne_menu_rows {
		ne.menu.scroll = ne.menu.hover - ne_menu_rows + 1
	}
}

// add_from_menu - добавить ноду типа строки i меню туда, где меню открыли (шапкой под
// курсор), выделить её и закрыть меню.
fn (mut ne NodeEditor) add_from_menu(i int) {
	if i < 0 || i >= ne.menu.items.len {
		return
	}
	type_id := ne.menu.items[i]
	t := ne.graph.types[type_id] or { return }
	menu := ne.menu
	slot := if menu.link_node != 0 { ne.menu_link_slot(t) } else { -1 }
	mut wx := menu.world_x - t.width * 0.5
	mut wy := menu.world_y - ne_header_h * 0.5
	if slot >= 0 {
		// Сокет новой ноды - под точкой, где отпустили связь: вход - на левом краю, выход - на
		// правом; по высоте - середина его строки (выходы - верхние строки, входы - под ними)
		row := if menu.link_from_out { t.outputs.len + slot } else { slot }
		wx = if menu.link_from_out { menu.world_x } else { menu.world_x - t.width }
		wy = menu.world_y - ne_header_h - f32(row) * ne_row_h - ne_row_h * 0.5
	}
	ne.close_add_menu()
	ne.begin_change()
	id := ne.graph.add_node(type_id, wx, wy) or { return }
	ne.touch()
	ne.emit(.node_added, id, 0, NodeLink{})
	if slot >= 0 {
		// Связь может не пройти вето приложения или проверку цикла - нода тогда остаётся без неё
		res := if menu.link_from_out {
			ne.graph.connect(menu.link_node, menu.link_slot, id, slot)
		} else {
			ne.graph.connect(id, slot, menu.link_node, menu.link_slot)
		}
		if r := res {
			if r.replaced.id != 0 {
				ne.emit(.link_removed, 0, 0, r.replaced)
			}
			ne.emit(.link_added, 0, 0, r.link)
		}
	}
	ne.selected = {
		id: true
	}
	ne.active = id
	ne.commit_change('Add node')
	ne.emit(.selection_changed, id, 0, NodeLink{})
	widget_changed()
}
