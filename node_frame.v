module vgui

// Файл node_frame.v: фреймы редактора нод - подписанные рамки, которые группируют ноды на холсте
// (как фреймы Blender и комментарии-рамки Unreal Blueprints). Здесь и модель (методы NodeGraph:
// фреймы хранятся в графе, сохраняются в JSON и входят в снимки отмены), и вид с вводом (методы
// NodeEditor: отрисовка за нодами, попадание, перемещение с нодами внутри, изменение размера,
// переименование, Ctrl+J). Остальной граф - node_graph.v, редактор - node_editor.v.
//
// Принадлежность нод фрейму не хранится: «внутри» - нода, чья карточка целиком лежит в
// прямоугольнике фрейма (frame_nodes). Так нечего поддерживать при перемещении, удалении и
// вставке нод, а пользователь видит ровно то, что получит: что внутри рамки - то и едет с ней.
// Раздел PROJECT.md - «NodeEditor: редактор графа из нод», «Фреймы».

const ne_frame_header_h = f32(26) // шапка фрейма с заголовком (за неё фрейм тянут)
const ne_frame_min_w = f32(80)
const ne_frame_min_h = f32(50)
const ne_frame_pad = f32(20) // отступ рамки вокруг нод при Ctrl+J (под шапкой - ещё её высота)

// NodeFrame - фрейм: устойчивый id (своя нумерация, не пересекается с id нод по смыслу), заголовок,
// прямоугольник на холсте, цвет (альфа 0 - цвет из темы, Theme.ne_frame_bg / CSS
// `nodes { frame-background }`).
@[heap]
pub struct NodeFrame {
pub mut:
	id    int
	title string
	x     f32
	y     f32
	w     f32
	h     f32
	color Color = Color{0, 0, 0, 0} // явная альфа 0: у Color по умолчанию a = 255
}

// rect - прямоугольник фрейма на холсте.
pub fn (f &NodeFrame) rect() Rect {
	return Rect{f.x, f.y, f.w, f.h}
}

// ─── Модель ────────────────────────────────────────────

// add_frame - новый фрейм поверх прежних (размер не меньше ne_frame_min_w x ne_frame_min_h);
// возвращает его id.
pub fn (mut g NodeGraph) add_frame(title string, x f32, y f32, w f32, h f32) int {
	widget_changed()
	f := &NodeFrame{
		id:    g.next_frame
		title: title
		x:     x
		y:     y
		w:     max_f32(w, ne_frame_min_w)
		h:     max_f32(h, ne_frame_min_h)
	}
	g.next_frame++
	g.frames << f
	return f.id
}

// remove_frame удаляет фрейм (ноды внутри остаются на месте). false - фрейма нет.
pub fn (mut g NodeGraph) remove_frame(id int) bool {
	widget_changed()
	for i, f in g.frames {
		if f.id == id {
			g.frames.delete(i)
			return true
		}
	}
	return false
}

// frame - фрейм по id (none - нет). Поля можно читать; менять - сеттерами (они просят перерисовку).
pub fn (g &NodeGraph) frame(id int) ?&NodeFrame {
	for f in g.frames {
		if f.id == id {
			return f
		}
	}
	return none
}

// frames - фреймы в порядке отрисовки (копия списка).
pub fn (g &NodeGraph) frames() []&NodeFrame {
	return g.frames.clone()
}

// set_frame_rect - прямоугольник фрейма (размер зажимается снизу ne_frame_min_*). Ноды не
// двигаются: «переехать вместе с нодами» - жест редактора (или move_frame).
pub fn (mut g NodeGraph) set_frame_rect(id int, x f32, y f32, w f32, h f32) bool {
	widget_changed()
	mut f := g.frame(id) or { return false }
	f.x, f.y = x, y
	f.w = max_f32(w, ne_frame_min_w)
	f.h = max_f32(h, ne_frame_min_h)
	return true
}

// move_frame - сдвинуть фрейм на (dx, dy) вместе с нодами внутри него (frame_nodes).
pub fn (mut g NodeGraph) move_frame(id int, dx f32, dy f32) bool {
	widget_changed()
	inside := g.frame_nodes(id)
	mut f := g.frame(id) or { return false }
	f.x += dx
	f.y += dy
	for mut n in g.nodes {
		if n.id in inside {
			n.x += dx
			n.y += dy
		}
	}
	return true
}

pub fn (mut g NodeGraph) set_frame_title(id int, title string) bool {
	widget_changed()
	mut f := g.frame(id) or { return false }
	f.title = title
	return true
}

// set_frame_color - свой цвет фрейма (альфа 0 - цвет из темы). Цвет рисуется как есть, вместе с
// альфой: фрейм лежит за нодами и сетка должна просвечивать.
pub fn (mut g NodeGraph) set_frame_color(id int, c Color) bool {
	widget_changed()
	mut f := g.frame(id) or { return false }
	f.color = c
	return true
}

// frame_nodes - id нод, чьи карточки целиком внутри фрейма (размер карточки - как у вида:
// width_of / height_of).
pub fn (g &NodeGraph) frame_nodes(id int) []int {
	f := g.frame(id) or { return []int{} }
	mut out := []int{}
	for n in g.nodes {
		w, h := g.width_of(n), g.height_of(n)
		if n.x >= f.x && n.y >= f.y && n.x + w <= f.x + f.w && n.y + h <= f.y + f.h {
			out << n.id
		}
	}
	return out
}

// ─── JSON фреймов ──────────────────────────────────────

struct NodeFrameJson {
	id    int
	title string
	x     f32
	y     f32
	w     f32
	h     f32
	color []int
}

fn frame_to_json(f &NodeFrame) NodeFrameJson {
	return NodeFrameJson{
		id:    f.id
		title: f.title
		x:     f.x
		y:     f.y
		w:     f.w
		h:     f.h
		color: [int(f.color.r), int(f.color.g), int(f.color.b), int(f.color.a)]
	}
}

// load_frames_json - фреймы из сохранения (часть load_json): прежние заменяются, битые id и
// повторы пропускаются, размер зажимается снизу.
fn (mut g NodeGraph) load_frames_json(list []NodeFrameJson) {
	g.frames = []&NodeFrame{}
	mut max_id := 0
	for jf in list {
		if jf.id <= 0 || g.frames.any(it.id == jf.id) {
			continue
		}
		g.frames << &NodeFrame{
			id:    jf.id
			title: jf.title
			x:     jf.x
			y:     jf.y
			w:     max_f32(jf.w, ne_frame_min_w)
			h:     max_f32(jf.h, ne_frame_min_h)
			color: node_json_color(jf.color, Color{0, 0, 0, 0})
		}
		max_id = max_int(max_id, jf.id)
	}
	g.next_frame = max_id + 1
}

// ─── Вид и ввод (методы NodeEditor) ────────────────────

// ne_frame_title_rect - место заголовка в шапке фрейма (на холсте); там же поле переименования.
fn ne_frame_title_rect(f &NodeFrame) Rect {
	return Rect{f.x + 8, f.y + 3, f.w - 16, ne_frame_header_h - 6}
}

// frame_hit - попадание по фреймам (hit_test зовёт его после всех нод: фреймы лежат под ними).
// Сверху вниз: край или угол - .frame_edge, шапка - .frame_header; пустое место внутри фрейма -
// холст (NodeHit{}): там работают рамка выделения и меню добавления.
fn (ne &NodeEditor) frame_hit(wx f32, wy f32) NodeHit {
	for i := ne.graph.frames.len - 1; i >= 0; i-- {
		f := ne.graph.frames[i]
		r := f.rect()
		edges := ne.edge_mask(r, false, wx, wy)
		if edges != 0 {
			return NodeHit{.frame_edge, f.id, edges}
		}
		if !r.contains(wx, wy) {
			continue
		}
		if wy < f.y + ne_frame_header_h {
			return NodeHit{.frame_header, f.id, 0}
		}
		return NodeHit{}
	}
	return NodeHit{}
}

// select_frame - выбрать фрейм (0 - снять выбор). Выбор фрейма снимает выделение нод.
pub fn (mut ne NodeEditor) select_frame(id int) {
	if id == ne.selected_frame {
		return
	}
	widget_changed()
	ne.selected_frame = id
	if id != 0 {
		ne.selected = map[int]bool{}
		ne.active = 0
	}
	ne.emit(.selection_changed, 0, 0, NodeLink{})
}

// press_frame - нажатие на шапку (перемещение) или край фрейма (размер): выбрать фрейм и начать
// жест. Для перемещения запоминаются ноды, лежащие внутри в момент нажатия (frame_nodes) - они
// едут с фреймом, даже если по дороге фрейм наедет на другие ноды.
fn (mut ne NodeEditor) press_frame(hit NodeHit) {
	f := ne.graph.frame(hit.node) or { return }
	ne.select_frame(f.id)
	ne.begin_change()
	ne.frame_drag = f.id
	ne.frame_start = f.rect()
	if hit.kind == .frame_header {
		ne.drag = .move_frame
		ne.move_start = map[int]Vec2{}
		for id in ne.graph.frame_nodes(f.id) {
			n := ne.graph.node(id) or { continue }
			ne.move_start[id] = Vec2{n.x, n.y}
		}
	} else {
		ne.drag = .resize_frame
		ne.resize_edges = hit.slot
	}
}

// drag_frame - шаг жеста фрейма от точки нажатия (как drag_move / drag_resize у нод): перемещение
// двигает фрейм и запомненные ноды на один сдвиг (при snap на сетку встаёт угол фрейма); размер -
// тянущиеся края, противоположные стоят, размер не меньше ne_frame_min_*.
fn (mut ne NodeEditor) drag_frame(x f32, y f32, snap bool) {
	s := ne.frame_start
	dx := (x - ne.press_x) / ne.zoom
	dy := (y - ne.press_y) / ne.zoom
	if ne.drag == .move_frame {
		ox := ne_snap(s.x + dx, snap) - s.x
		oy := ne_snap(s.y + dy, snap) - s.y
		ne.graph.set_frame_rect(ne.frame_drag, s.x + ox, s.y + oy, s.w, s.h)
		for mut n in ne.graph.nodes {
			if p := ne.move_start[n.id] {
				n.x = p.x + ox
				n.y = p.y + oy
			}
		}
		ne.touch()
		return
	}
	edges := ne.resize_edges
	mut nx, mut ny, mut nw, mut nh := s.x, s.y, s.w, s.h
	if edges & ne_edge_left != 0 {
		nw = max_f32(s.x + s.w - ne_snap(s.x + dx, snap), ne_frame_min_w)
		nx = s.x + s.w - nw
	} else if edges & ne_edge_right != 0 {
		nw = max_f32(ne_snap(s.x + s.w + dx, snap) - s.x, ne_frame_min_w)
	}
	if edges & ne_edge_top != 0 {
		nh = max_f32(s.y + s.h - ne_snap(s.y + dy, snap), ne_frame_min_h)
		ny = s.y + s.h - nh
	} else if edges & ne_edge_bottom != 0 {
		nh = max_f32(ne_snap(s.y + s.h + dy, snap) - s.y, ne_frame_min_h)
	}
	ne.graph.set_frame_rect(ne.frame_drag, nx, ny, nw, nh)
	ne.touch()
}

// frame_selected - обвести выделенные ноды новым фреймом (Ctrl+J): рамка вокруг их карточек с
// отступом ne_frame_pad и местом под шапку. Новый фрейм выбирается - F2 сразу его переименует.
pub fn (mut ne NodeEditor) frame_selected() {
	ids := ne.selected_nodes()
	if ids.len == 0 {
		return
	}
	mut x0, mut y0 := f32(1.0e9), f32(1.0e9)
	mut x1, mut y1 := f32(-1.0e9), f32(-1.0e9)
	for id in ids {
		n := ne.graph.node(id) or { continue }
		r := ne.node_world_rect(n)
		x0 = min_f32(x0, r.x)
		y0 = min_f32(y0, r.y)
		x1 = max_f32(x1, r.x + r.w)
		y1 = max_f32(y1, r.y + r.h)
	}
	ne.begin_change()
	top := y0 - ne_frame_pad - ne_frame_header_h
	id := ne.graph.add_frame(tr('Frame'), x0 - ne_frame_pad, top, x1 - x0 + ne_frame_pad * 2,
		y1 - top + ne_frame_pad)
	ne.touch()
	ne.emit(.frame_added, id, 0, NodeLink{})
	ne.commit_change('Add frame')
	ne.select_frame(id)
}

// delete_frame - удалить фрейм (ноды внутри остаются), одна команда отмены.
pub fn (mut ne NodeEditor) delete_frame(id int) {
	ne.begin_change()
	if !ne.graph.remove_frame(id) {
		ne.commit_change('Delete frame')
		return
	}
	ne.touch()
	ne.emit(.frame_removed, id, 0, NodeLink{})
	if ne.selected_frame == id {
		ne.selected_frame = 0
	}
	ne.commit_change('Delete frame')
}

// rename_frame - поле ввода поверх заголовка фрейма (F2 по выбранному, двойной щелчок по шапке).
pub fn (mut ne NodeEditor) rename_frame(id int, app &App) {
	f := ne.graph.frame(id) or { return }
	ne.open_edit(id, f.title, app)
	ne.edit_frame = true
	ne.edit_title = false
}

// commit_frame_rename - заголовок фрейма из поля ввода (не изменился - ни команды, ни события).
fn (mut ne NodeEditor) commit_frame_rename() {
	text := ne.edit_ti.get_text().trim_space()
	id := ne.edit_node
	ne.cancel_text_edit()
	ne.edit_frame = false
	f := ne.graph.frame(id) or { return }
	if text == f.title {
		return
	}
	ne.begin_change()
	ne.graph.set_frame_title(id, text)
	ne.touch()
	ne.emit(.frame_changed, id, 0, NodeLink{})
	ne.commit_change('Rename frame')
}

// draw_frames - фреймы под связями и нодами: полупрозрачная заливка (свой цвет или темы),
// шапка той же краской вдвое плотнее, заголовок; выбранный - рамкой выделения.
fn (ne &NodeEditor) draw_frames(mut ctx RenderContext) {
	rad := ctx.theme.eff_ne_node_radius() * ne.zoom
	fpx := ne.font_px(ctx)
	for f in ne.graph.frames {
		r := ne.screen_rect(f.rect())
		if !r.intersects(ne.bounds) {
			continue
		}
		c := if f.color.a > 0 { f.color } else { ctx.theme.eff_ne_frame_bg() }
		ctx.fill_rounded_rect(r, c, rad)
		head := Rect{r.x, r.y, r.w, ne_frame_header_h * ne.zoom}
		ctx.fill_rounded_rect(head, c.with_alpha(u8(min_int(255, int(c.a) * 2))), rad)
		if f.id == ne.selected_frame {
			ctx.draw_rounded_rect(r.expanded(1), ctx.theme.eff_ne_selected(), rad)
		}
		renaming := ne.editing && ne.edit_frame && ne.edit_node == f.id
		if fpx > 0 && !renaming && f.title != '' {
			font := ctx.get_font(.bold, fpx)
			tr_rect := ne.screen_rect(ne_frame_title_rect(f))
			fh := ctx.font_height_of(font)
			title := bc_truncate_text(ctx, f.title, tr_rect.w, font)
			ctx.draw_text_with_font(title, tr_rect.x, tr_rect.y + (tr_rect.h - fh) * 0.5,
				ctx.theme.eff_ne_frame_text(), font)
		}
	}
}
