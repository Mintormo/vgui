module vgui

import os

// Файл dock_area.v: DockArea - область с перетаскиваемыми панелями (docking), как в Visual Studio,
// VS Code, Qt Advanced Docking. Панель (DockPanel) - заголовок, иконка и виджет-содержимое; сама
// панель НЕ виджет, это запись, которой владеет область (как MenuItem у меню).
//
// Устройство. Внутри области - двоичное дерево узлов DockNode:
//   - узел-разбиение (.split) делит прямоугольник на две части (как Splitter: доля ratio и полоса
//     между частями, которую можно тянуть);
//   - узел-группа (.group) - лист дерева: полоса вкладок сверху и содержимое активной панели под ней.
// Узлы - внутренние структуры области, не виджеты: в дереве виджетов окна у DockArea дети - только
// содержимое панелей (child_widgets/hit_children в widget_tree.v).
//
// Перестройка дерева мышью. Вкладку тянут за пределы порога (dnd_threshold) - начинается перенос
// панели: на каждом движении считается место сброса (DockDrop) и рисуется его предпросмотр:
//   - над полосой вкладок группы - вставка вкладкой в эту группу (линия вставки);
//   - над содержимым группы - центр (вкладкой в группу) или край (разделить группу: панель встанет
//     слева/справа/сверху/снизу от неё, предпросмотр - половина группы);
//   - у края всей области - панель встаёт вдоль этого края всей области.
// Отпускание применяет сброс (apply_drop): панель снимается со старого места (detach_panel; пустая
// группа схлопывается - её место занимает соседний узел) и вставляется на новое.
//
// Почему перенос - свой жест, а не общий drag-and-drop (dnd.v): цели - не виджеты, а части одного
// виджета (зоны групп), и предпросмотр зависит от геометрии дерева. Жест ведёт сам DockArea через
// захват мыши окна (event_route.v): нажатие на вкладку поглощается, и движения до отпускания идут ему.
// Чтобы предок-источник общего DnD не перехватил жест, DockArea - в dnd_owns_drag (когда нажали на
// саму область, а не на содержимое панели).
//
// Раскладку можно сохранить строкой (save_layout) и восстановить (load_layout), то же - в файл
// (save_layout_file / load_layout_file); панели опознаются по id. Сама область раскладку не
// сохраняет - когда и куда, решает приложение. Закрытая панель область помнит (panels) и может вернуть её на прежнее место (show_panel).
//
// Рисование - только примитивами RenderContext (PROJECT.md, «Бэкенд рисования: виджеты не зовут SDL
// напрямую»): заливки, линии, текст, иконки ItemIcon; курсор - set_cursor/current_cursor. Цвета -
// из темы вкладок (eff_tab_*) и разделителя (eff_splitter_*), отдельных полей темы у области нет.
// Тег типа kind_dock_area - widget_kinds.v. Раздел PROJECT.md - «Docking: DockArea и DockPanel».

// DockSide - куда поставить панель относительно цели: слева/справа/сверху/снизу от неё (разделить)
// или в центр (добавить вкладкой в ту же группу).
pub enum DockSide {
	center
	left
	right
	top
	bottom
}

// DockPanel - одна панель области: id (ключ в сохранённой раскладке, должен быть уникальным и без
// символов ` [](),*`), заголовок вкладки, необязательная иконка, содержимое и флаг closable (рисовать
// ли крестик на вкладке). Поля restore_* - куда вернуть закрытую панель (заполняет close_panel).
@[heap]
pub struct DockPanel {
pub mut:
	id       string
	title    string
	icon     ItemIcon
	content  &Widget = unsafe { nil }
	closable bool    = true
mut:
	// Место, откуда панель закрыли: рядом с какой панелью (id) и с какой стороны, и доля новой
	// части (size для dock). Пустой restore_near - вернуть в первую группу.
	restore_near string
	restore_side DockSide
	restore_size f32 = 0.5
}

// dock_panel создаёт панель. Добавить её в область - DockArea.add_panel / dock.
pub fn dock_panel(id string, title string, content &Widget) &DockPanel {
	return &DockPanel{
		id:      id
		title:   title
		content: unsafe { content }
	}
}

// set_title меняет заголовок вкладки панели.
pub fn (mut p DockPanel) set_title(title string) {
	widget_changed()
	p.title = title
}

// DockNodeKind - вид узла дерева: группа вкладок (лист) или разбиение на две части.
enum DockNodeKind {
	group
	split
}

// DockNode - узел дерева области. У разбиения: dir (.horizontal - части слева и справа, как у
// Splitter), ratio - доля первой части от полезного места (без полосы), first/second. У группы:
// panels и номер активной. Поля геометрии (rect, bar, strip, content, tab_rects, close_rects)
// пересчитывает arrange() области - события и draw() читают их, а не считают заново.
@[heap]
struct DockNode {
mut:
	kind   DockNodeKind
	dir    SplitDir  = .horizontal
	ratio  f32       = 0.5
	first  &DockNode = unsafe { nil }
	second &DockNode = unsafe { nil }
	panels []&DockPanel
	active int
	// геометрия последней раскладки
	rect        Rect
	bar         Rect // полоса разбиения
	strip       Rect // полоса вкладок группы
	content     Rect // содержимое активной панели группы
	tab_rects   []Rect
	close_rects []Rect // Rect{} - у вкладки нет крестика
}

// DockDropKind - что сделает отпускание перетаскиваемой вкладки.
enum DockDropKind {
	none  // сбросить некуда (или сброс ничего не изменил бы)
	tab   // вставить вкладкой в группу на позицию index
	split // разделить группу: панель встанет со стороны side
	edge  // встать вдоль края side всей области
}

// DockDrop - место сброса под курсором и прямоугольник его предпросмотра.
struct DockDrop {
	kind    DockDropKind
	group   &DockNode = unsafe { nil }
	side    DockSide
	index   int
	preview Rect
}

// Размеры области (логические пиксели).
const dock_edge_zone = f32(28) // ширина зоны «к краю всей области»
const dock_close_size = f32(16) // крестик закрытия на вкладке
const dock_tab_min_w = f32(48) // уже вкладка не сжимается при нехватке места
const dock_edge_size = f32(0.3) // доля области у панели, поставленной к её краю

// DockArea - область с панелями. root - корень дерева (nil, пока не добавлено ни одной панели);
// panels - все известные области панели, в том числе закрытые. Колбэки: on_layout_change - после
// того, как пользователь изменил раскладку (перенёс или закрыл панель, отпустил полосу) - момент
// сохранить save_layout(); on_panel_close(p) - перед закрытием крестиком или средней кнопкой,
// false - не закрывать (спросить «сохранить изменения?»).
@[heap]
pub struct DockArea {
pub mut:
	type_tag int = kind_dock_area // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	visible  bool = true
	enabled  bool = true // false - вкладки и полосы не реагируют, содержимое неактивно (enabled.v)
	tooltip  string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd      &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	bar_size f32       = 4            // толщина полосы между частями разбиения
	min_pane f32       = 60           // меньше этого часть разбиения полосой не сжать
	tab_pad  f32       = 10           // поле слева и справа внутри вкладки
	// allow_float - вкладку можно вытащить в отдельное окно (за пределы окна или двойным щелчком)
	allow_float bool = true
	// Колбэки
	on_layout_change fn ()                = unsafe { nil }
	on_panel_close   fn (&DockPanel) bool = unsafe { nil }
mut:
	root   &DockNode = unsafe { nil }
	panels []&DockPanel
	// Наведение: группа и вкладка под курсором, крестик под курсором, полоса под курсором
	hover_group &DockNode = unsafe { nil }
	hover_tab   int       = -1
	hover_close bool
	hover_bar   &DockNode = unsafe { nil }
	// Нажатие на вкладку: группа, номер, точка нажатия; press_close - нажали на крестик
	press_group &DockNode = unsafe { nil }
	press_tab   int       = -1
	press_close bool
	press_x     f32
	press_y     f32
	// Перенос панели: идёт ли, где курсор, куда упадёт
	tab_dragging bool
	drag_x       f32
	drag_y       f32
	drop         DockDrop
	// Перетаскивание полосы разбиения: узел и смещение курсора от центра полосы
	resize_node &DockNode = unsafe { nil }
	drag_offset f32
	// Курсор до входа на полосу (как у Splitter): nil - свой курсор не ставили
	saved_cursor voidptr
	// Плавающие панели (dock_float.v). floats - окна главной области; float_owner - у области
	// плавающего окна: главная область (nil - это главная). app и own_win - приложение и окно
	// области, их приносит контекст в arrange() (RenderContext.app/window).
	floats      []&DockFloat
	float_owner &DockArea = unsafe { nil }
	app         &App      = unsafe { nil }
	own_win     &Window   = unsafe { nil }
	// Перенос в другое окно: область под курсором в чужом окне (nil - нет) и предпросмотр,
	// который рисует сама та область (ext_drop - его ставит переносящая область)
	ext_target &DockArea = unsafe { nil }
	ext_drop   DockDrop
}

// dock_area создаёт пустую область. Панели - add_panel / dock.
pub fn dock_area() &DockArea {
	return &DockArea{}
}

// ─── Публичный API ─────────────────────────────────────

// DockAt - необязательные параметры dock(): target - панель, рядом с которой встать (nil - край
// всей области; при side == .center - первая группа); size - доля новой части в разбиении (0..1).
@[params]
pub struct DockAt {
pub:
	target &DockPanel = unsafe { nil }
	size   f32        = 0.5
}

// add_panel добавляет панель вкладкой в первую группу (или делает её первой группой).
pub fn (mut da DockArea) add_panel(p &DockPanel) {
	da.dock(p, .center)
}

// dock ставит панель p со стороны side от панели at.target (или от всей области). Уже открытая
// панель переносится. Примеры:
//   da.dock(files, .left, size: 0.25)              // слева во всю высоту области
//   da.dock(console, .bottom, target: editor, size: 0.3) // под редактором
//   da.dock(outline, .center, target: files)       // вкладкой в группу files
pub fn (mut da DockArea) dock(p &DockPanel, side DockSide, at DockAt) {
	widget_changed()
	da.register(p)
	da.take_panel(p) // снять с прежнего места - в этой области, главной или плавающем окне
	da.reset_pointer_state()
	if isnil(da.root) {
		da.root = &DockNode{
			kind: .group
		}
	}
	// Группа цели: группа панели target, если та открыта; иначе - вся область
	mut target_group := unsafe { &DockNode(nil) }
	if !isnil(at.target) {
		if g := da.group_of(at.target) {
			target_group = g
		}
	}
	size := clamp_f32(at.size, 0.05, 0.95)
	if side == .center {
		mut g := if isnil(target_group) { da.first_group() } else { target_group }
		g.panels << unsafe { p }
		g.active = g.panels.len - 1
		return
	}
	if isnil(target_group) {
		da.split_node(da.root, p, side, size)
	} else {
		da.split_node(target_group, p, side, size)
	}
}

// close_panel закрывает панель программно (без on_panel_close): она уходит из дерева, но область
// её помнит - show_panel вернёт её примерно на то же место.
pub fn (mut da DockArea) close_panel(p &DockPanel) {
	widget_changed()
	if da.is_floating(p) {
		// Место в области запомнено, когда панель уплыла (float_panel): show_panel вернёт её туда
		da.take_from_float(p)
		return
	}
	da.remember_place(p)
	da.detach_panel(p)
	da.reset_pointer_state()
}

// show_panel показывает панель: открытую делает активной в её группе, закрытую возвращает на
// запомненное место (рядом с той же соседней панелью), а если соседа уже нет - в первую группу.
pub fn (mut da DockArea) show_panel(p &DockPanel) {
	widget_changed()
	da.register(p)
	if mut g := da.group_of(p) {
		g.active = dock_panel_index(g.panels, p)
		return
	}
	if da.show_floating(p) {
		return // плавающая: вкладка активна, окно поднято (dock_float.v)
	}
	if near_panel := da.open_panel_by_id(p.restore_near) {
		da.dock(p, p.restore_side, target: near_panel, size: p.restore_size)
	} else {
		da.dock(p, .center)
	}
}

// is_open - панель сейчас открыта: вкладкой в области или в плавающем окне.
pub fn (da &DockArea) is_open(p &DockPanel) bool {
	return da.group_of(p) != none || da.is_floating(p)
}

// is_active - панель открыта и её вкладка активна в своей группе (её содержимое видно).
pub fn (da &DockArea) is_active(p &DockPanel) bool {
	// Главная область спрашивает плавающее окно; область окна - только своё дерево (иначе она
	// нашла бы через главную саму себя и ушла в бесконечную рекурсию)
	if isnil(da.float_owner) {
		if f := da.float_of(p) {
			return f.area.is_active(p)
		}
	}
	g := da.group_of(p) or { return false }
	return g.active == dock_panel_index(g.panels, p)
}

// panel_by_id - известная области панель с таким id (открытая или закрытая).
pub fn (da &DockArea) panel_by_id(id string) ?&DockPanel {
	for p in da.panels {
		if p.id == id {
			return p
		}
	}
	return none
}

// all_panels - все известные области панели в порядке добавления (для меню «Вид → Панели»).
pub fn (da &DockArea) all_panels() []&DockPanel {
	return da.panels.clone()
}

// save_layout - раскладка строкой. Формат (читается человеком):
//   узел       = разбиение | группа
//   разбиение  = ('h' | 'v') доля '(' узел ',' узел ')'   // h - части слева/справа, v - сверху/снизу
//   группа     = '[' id (' ' id)* ']', активная панель помечена '*'
// Пример: h0.250([*files outline],v0.700([*editor],[*console]))
// Пустая область - пустая строка.
pub fn (da &DockArea) save_layout() string {
	mut sb := []string{}
	if !isnil(da.root) {
		dock_save_node(da.root, mut sb)
	}
	// Плавающие окна - хвостом `+F(x,y,w,h)раскладка` (dock_float.v; только у главной области)
	if isnil(da.float_owner) {
		sb << da.save_floats()
	}
	return sb.join('')
}

// load_layout восстанавливает раскладку из строки save_layout. Панели ищутся по id среди
// известных области (добавленных раньше add_panel/dock/show_panel); неизвестные id пропускаются,
// а известные, но не упомянутые панели становятся закрытыми. Ошибка разбора - error с позицией,
// раскладка при этом не меняется.
pub fn (mut da DockArea) load_layout(s string) ! {
	widget_changed()
	// Хвост плавающих окон (`+F(...)`, dock_float.v) отделяется до разбора: ошибка в нём или в
	// главной части - error до каких-либо изменений
	text, specs := dock_split_float_specs(s.trim_space())!
	mut root := unsafe { &DockNode(nil) }
	if text != '' {
		mut parser := DockLayoutParser{
			src:  text
			area: unsafe { &da }
		}
		root = parser.parse_node()!
		parser.skip_spaces()
		if parser.pos < parser.src.len {
			return error('dock layout: unexpected `${parser.src[parser.pos..]}` at ${parser.pos}')
		}
	}
	da.root = if isnil(root) { root } else { dock_prune(root) }
	da.reset_pointer_state()
	if isnil(da.float_owner) {
		da.load_floats(specs)
	}
}

// save_layout_file записывает раскладку (строку save_layout) в файл path; недостающие папки
// создаются. Сама область ничего не сохраняет - когда писать (on_layout_change, выход из
// программы), решает приложение.
pub fn (da &DockArea) save_layout_file(path string) ! {
	dir := os.dir(path)
	if dir != '' && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	os.write_file(path, da.save_layout() + '\n')!
}

// load_layout_file восстанавливает раскладку из файла, записанного save_layout_file. Нет файла или
// ошибка в нём - error, раскладка при этом не меняется (приложение остаётся с раскладкой по
// умолчанию, построенной до вызова).
pub fn (mut da DockArea) load_layout_file(path string) ! {
	text := os.read_file(path)!
	da.load_layout(text)!
}

// ─── Дерево: поиск ─────────────────────────────────────

// dock_same - один и тот же объект (сравнение адресов: `==` у ссылок V сравнивает содержимое).
fn dock_same(a voidptr, b voidptr) bool {
	return a == b
}

// dock_panel_index - номер панели p в срезе (по адресу), -1 - нет.
fn dock_panel_index(panels []&DockPanel, p &DockPanel) int {
	for i, q in panels {
		if dock_same(q, p) {
			return i
		}
	}
	return -1
}

// register запоминает панель в списке известных (повторно не добавляет).
fn (mut da DockArea) register(p &DockPanel) {
	if dock_panel_index(da.panels, p) < 0 {
		da.panels << unsafe { p }
	}
}

// groups - все группы дерева слева направо / сверху вниз (обход в глубину).
fn (da &DockArea) groups() []&DockNode {
	mut out := []&DockNode{}
	if !isnil(da.root) {
		dock_collect_groups(da.root, mut out)
	}
	return out
}

fn dock_collect_groups(n &DockNode, mut out []&DockNode) {
	if n.kind == .group {
		out << unsafe { n }
		return
	}
	dock_collect_groups(n.first, mut out)
	dock_collect_groups(n.second, mut out)
}

// first_group - самая левая/верхняя группа (корень области всегда есть, когда зовут).
fn (da &DockArea) first_group() &DockNode {
	mut n := da.root
	for n.kind == .split {
		n = n.first
	}
	return n
}

// group_of - группа, в которой открыта панель.
fn (da &DockArea) group_of(p &DockPanel) ?&DockNode {
	for g in da.groups() {
		if dock_panel_index(g.panels, p) >= 0 {
			return g
		}
	}
	return none
}

// open_panel_by_id - открытая панель с таким id.
fn (da &DockArea) open_panel_by_id(id string) ?&DockPanel {
	if id == '' {
		return none
	}
	for g in da.groups() {
		for p in g.panels {
			if p.id == id {
				return p
			}
		}
	}
	return none
}

// parent_of - узел-разбиение, у которого n - прямой ребёнок (nil - n корень или не в дереве).
// Указателя на родителя у узлов нет: дерево маленькое, обход дешевле второго источника правды.
fn dock_parent_of(from &DockNode, n &DockNode) &DockNode {
	if from.kind == .group {
		return unsafe { nil }
	}
	if dock_same(from.first, n) || dock_same(from.second, n) {
		return unsafe { from }
	}
	p := dock_parent_of(from.first, n)
	if !isnil(p) {
		return p
	}
	return dock_parent_of(from.second, n)
}

// ─── Дерево: изменение ─────────────────────────────────

// replace_node ставит узел repl на место old (в слот родителя или в корень). Сами объекты-узлы
// при перестройке не копируются: на группу могут ссылаться место сброса и наведение.
fn (mut da DockArea) replace_node(old &DockNode, repl &DockNode) {
	mut parent := unsafe { dock_parent_of(da.root, old) }
	if isnil(parent) {
		da.root = unsafe { repl }
	} else if dock_same(parent.first, old) {
		parent.first = unsafe { repl }
	} else {
		parent.second = unsafe { repl }
	}
}

// split_node разделяет узел target: новая группа с панелью p встаёт со стороны side и получает
// долю size. target остаётся тем же объектом, но уходит ребёнком в новое разбиение.
fn (mut da DockArea) split_node(target &DockNode, p &DockPanel, side DockSide, size f32) {
	fresh := &DockNode{
		kind:   .group
		panels: [unsafe { p }]
	}
	dir := if side in [.left, .right] { SplitDir.horizontal } else { SplitDir.vertical }
	new_first := side in [.left, .top]
	split := &DockNode{
		kind:   .split
		dir:    dir
		ratio:  if new_first { size } else { 1 - size }
		first:  if new_first { fresh } else { unsafe { target } }
		second: if new_first { unsafe { target } } else { fresh }
	}
	da.replace_node(target, split)
}

// detach_panel снимает панель с её места. Группа без панелей схлопывается: её разбиение заменяет
// соседний узел. Пустой остаётся только группа-корень (пустая область). Закрытой панели - no-op.
fn (mut da DockArea) detach_panel(p &DockPanel) {
	mut g := da.group_of(p) or { return }
	idx := dock_panel_index(g.panels, p)
	g.panels.delete(idx)
	// Активной остаётся та же вкладка; закрыли саму активную - соседняя слева
	if g.active > idx || g.active >= g.panels.len {
		g.active = g.active - 1
	}
	if g.active < 0 {
		g.active = 0
	}
	if g.panels.len > 0 {
		return
	}
	parent := dock_parent_of(da.root, g)
	if isnil(parent) {
		return
	}
	sibling := if dock_same(parent.first, g) { parent.second } else { parent.first }
	da.replace_node(parent, sibling)
}

// remember_place записывает в панель, куда её вернуть после закрытия: в той же группе есть другие
// панели - вкладкой к одной из них; панель одна в группе - со стороны схлопывающегося разбиения
// рядом с первой панелью соседнего узла.
fn (mut da DockArea) remember_place(p &DockPanel) {
	mut mp := unsafe { p }
	g := da.group_of(p) or { return }
	for q in g.panels {
		if !dock_same(q, p) {
			mp.restore_near = q.id
			mp.restore_side = .center
			return
		}
	}
	parent := dock_parent_of(da.root, g)
	if isnil(parent) {
		mp.restore_near = ''
		return
	}
	was_first := dock_same(parent.first, g)
	sibling := if was_first { parent.second } else { parent.first }
	mut leaf := unsafe { sibling }
	for leaf.kind == .split {
		leaf = leaf.first
	}
	mp.restore_near = if leaf.panels.len > 0 { leaf.panels[leaf.active].id } else { '' }
	mp.restore_side = match parent.dir {
		.horizontal {
			if was_first { DockSide.left } else { DockSide.right }
		}
		.vertical {
			if was_first { DockSide.top } else { DockSide.bottom }
		}
	}
	mp.restore_size = if was_first { parent.ratio } else { 1 - parent.ratio }
}

// dock_prune убирает из дерева пустые группы (после load_layout с неизвестными id). Возвращает
// новый корень; nil - не осталось ни одной панели.
fn dock_prune(n &DockNode) &DockNode {
	if n.kind == .group {
		return if n.panels.len > 0 { unsafe { n } } else { unsafe { nil } }
	}
	a := dock_prune(n.first)
	b := dock_prune(n.second)
	if isnil(a) {
		return b
	}
	if isnil(b) {
		return a
	}
	mut m := unsafe { n }
	m.first = a
	m.second = b
	return m
}

// reset_pointer_state забывает наведение, нажатие и перенос: после перестройки дерева группы,
// на которые они ссылались, могли уйти из него.
fn (mut da DockArea) reset_pointer_state() {
	da.hover_group = unsafe { nil }
	da.hover_tab = -1
	da.hover_close = false
	da.hover_bar = unsafe { nil }
	da.press_group = unsafe { nil }
	da.press_tab = -1
	da.press_close = false
	da.tab_dragging = false
	da.drop = DockDrop{}
	da.resize_node = unsafe { nil }
}

// fire_change - пользователь изменил раскладку.
fn (da &DockArea) fire_change() {
	if da.on_layout_change != unsafe { nil } {
		da.on_layout_change()
	}
}

// ─── Раскладка ─────────────────────────────────────────

// arrange раскладывает дерево в bounds области и выдаёт bounds содержимому активных панелей групп
// (только им: неактивные вкладки не рисуются, их bounds устаревают - см. hit_children).
pub fn (mut da DockArea) arrange(mut ctx RenderContext) {
	// Окно и приложение области (для плавающих окон, dock_float.v) - раньше раннего выхода:
	// пустой области тоже нужно знать, куда вернуть панели
	da.learn_context(ctx)
	if !da.visible {
		return
	}
	if is_bounds_unset(da.bounds) {
		da.bounds = Rect{0, 0, ctx.screen_width, ctx.screen_height}
	}
	if isnil(da.root) {
		return
	}
	da.layout_node(mut da.root, da.bounds, ctx)
	for mut g in da.groups() {
		if g.panels.len == 0 {
			continue
		}
		mut p := g.panels[g.active]
		if !isnil(p.content) {
			arrange_child(mut p.content, g.content, mut ctx)
		}
	}
}

// layout_node - геометрия узла в прямоугольнике r. Разбиение делит r как Splitter: полезное место
// (без полосы) по доле ratio, обе части не меньше min_pane (если влезают). Группа - полоса вкладок
// высотой стандартного контрола, линия под ней и содержимое.
fn (mut da DockArea) layout_node(mut n DockNode, r Rect, ctx &RenderContext) {
	n.rect = r
	if n.kind == .group {
		da.layout_group(mut n, r, ctx)
		return
	}
	main := if n.dir == .horizontal { r.w } else { r.h }
	usable := max_f32(main - da.bar_size, 0)
	min_part := min_f32(da.min_pane, usable * 0.5)
	first_sz := clamp_f32(n.ratio * usable, min_part, usable - min_part)
	if n.dir == .horizontal {
		n.bar = Rect{r.x + first_sz, r.y, da.bar_size, r.h}
		da.layout_node(mut n.first, Rect{r.x, r.y, first_sz, r.h}, ctx)
		second_x := r.x + first_sz + da.bar_size
		da.layout_node(mut n.second, Rect{second_x, r.y, r.x + r.w - second_x, r.h}, ctx)
	} else {
		n.bar = Rect{r.x, r.y + first_sz, r.w, da.bar_size}
		da.layout_node(mut n.first, Rect{r.x, r.y, r.w, first_sz}, ctx)
		second_y := r.y + first_sz + da.bar_size
		da.layout_node(mut n.second, Rect{r.x, second_y, r.w, r.y + r.h - second_y}, ctx)
	}
}

// layout_group - полоса вкладок и прямоугольники вкладок. Ширина вкладки - по содержимому (поля,
// иконка, текст, крестик); не помещаются - все сжимаются пропорционально, но не уже dock_tab_min_w
// (тогда хвост полосы обрезается клипом). Текст, не влезший в сжатую вкладку, рисуется с «…».
fn (mut da DockArea) layout_group(mut g DockNode, r Rect, ctx &RenderContext) {
	tab_h := ctx.control_h()
	g.strip = Rect{r.x, r.y, r.w, min_f32(tab_h, r.h)}
	content_y := r.y + tab_h + 1 // +1 - линия под полосой вкладок
	g.content = Rect{r.x, content_y, r.w, max_f32(r.y + r.h - content_y, 0)}

	font := ctx.get_font_immut(.regular, 0)
	mut widths := []f32{cap: g.panels.len}
	mut total := f32(0)
	for p in g.panels {
		w := da.tab_natural_w(p, font, ctx)
		widths << w
		total += w
	}
	// Не помещаются - сжать пропорционально
	if total > r.w && total > 0 {
		scale := r.w / total
		for i in 0 .. widths.len {
			widths[i] = max_f32(widths[i] * scale, dock_tab_min_w)
		}
	}
	g.tab_rects = []Rect{cap: g.panels.len}
	g.close_rects = []Rect{cap: g.panels.len}
	mut x := r.x
	for i, p in g.panels {
		tab_r := Rect{x, g.strip.y, widths[i], g.strip.h}
		g.tab_rects << tab_r
		if p.closable {
			cy := tab_r.y + (tab_r.h - dock_close_size) * 0.5
			g.close_rects << Rect{tab_r.x + tab_r.w - da.tab_pad * 0.5 - dock_close_size, cy, dock_close_size, dock_close_size}
		} else {
			g.close_rects << Rect{}
		}
		x += widths[i]
	}
}

// tab_natural_w - ширина вкладки, при которой заголовок виден целиком.
fn (da &DockArea) tab_natural_w(p &DockPanel, font voidptr, ctx &RenderContext) f32 {
	mut w := da.tab_pad * 2 + ctx.measure_text_with_font(p.title, font).x
	if p.icon.is_set() {
		w += dock_close_size + 4
	}
	if p.closable {
		w += dock_close_size + 2
	}
	return w
}

// hits_self - точка на полосе разбиения (с запасом по 4 px в стороны - тонкую полосу трудно
// поймать). Запас заходит на содержимое панелей, поэтому без HitsSelf нажатие ушло бы в ребёнка.
pub fn (da &DockArea) hits_self(x f32, y f32) bool {
	return !isnil(da.bar_at(x, y))
}

// bar_at - разбиение, чья полоса (с запасом) под точкой.
fn (da &DockArea) bar_at(x f32, y f32) &DockNode {
	if isnil(da.root) {
		return unsafe { nil }
	}
	return dock_bar_at(da.root, x, y)
}

fn dock_bar_at(n &DockNode, x f32, y f32) &DockNode {
	if n.kind == .group {
		return unsafe { nil }
	}
	if dock_bar_hit_rect(n).contains(x, y) {
		return unsafe { n }
	}
	a := dock_bar_at(n.first, x, y)
	if !isnil(a) {
		return a
	}
	return dock_bar_at(n.second, x, y)
}

fn dock_bar_hit_rect(n &DockNode) Rect {
	grab := f32(4)
	return if n.dir == .horizontal {
		Rect{n.bar.x - grab, n.bar.y, n.bar.w + grab * 2, n.bar.h}
	} else {
		Rect{n.bar.x, n.bar.y - grab, n.bar.w, n.bar.h + grab * 2}
	}
}

// group_at - группа, чей прямоугольник содержит точку.
fn (da &DockArea) group_at(x f32, y f32) &DockNode {
	for g in da.groups() {
		if g.rect.contains(x, y) {
			return g
		}
	}
	return unsafe { nil }
}

// tab_at - номер вкладки группы под точкой (-1 - не над вкладкой).
fn dock_tab_at(g &DockNode, x f32, y f32) int {
	if !g.strip.contains(x, y) {
		return -1
	}
	for i, tr in g.tab_rects {
		if tr.contains(x, y) {
			return i
		}
	}
	return -1
}

// ─── Место сброса ──────────────────────────────────────

// compute_drop - куда упадёт панель p, если отпустить её в (x, y). Порядок проверок:
//   1. полоса вкладок группы - вставка вкладкой (позиция - перед вкладкой, чья середина правее);
//   2. зона у края всей области (кроме полос вкладок; в том числе над полосой разбиения) - к краю
//      области; она главнее краёв групп, которые к ней прилегают;
//   3. содержимое группы: середина (по 30% от краёв) - вкладкой в группу, иначе ближайший край
//      группы - разделить её.
// Сброс, который ничего не изменил бы (панель - единственная в своей группе и её же делим или
// кладём в неё), даёт .none: предпросмотр не рисуется, отпускание ничего не делает.
fn (da &DockArea) compute_drop(p &DockPanel, x f32, y f32) DockDrop {
	if !da.bounds.contains(x, y) {
		return DockDrop{}
	}
	// Пустая область (все панели уплыли в плавающие окна или закрыты) - вся она место сброса:
	// панель станет первой группой
	if isnil(da.root) || (da.root.kind == .group && da.root.panels.len == 0) {
		return DockDrop{
			kind:    .tab
			preview: da.bounds
		}
	}
	// Панель из другой области (перенос из другого окна, dock_float.v) здесь не открыта: группы-
	// источника нет, и любой сброс что-то меняет
	src := da.group_of(p) or { unsafe { &DockNode(nil) } }
	alone := !isnil(src) && src.panels.len == 1
	g := da.group_at(x, y)
	// 1. полоса вкладок
	if !isnil(g) && g.strip.contains(x, y) {
		if dock_same(g, src) && alone {
			return DockDrop{}
		}
		mut index := g.panels.len
		for i, tr in g.tab_rects {
			if x < tr.x + tr.w * 0.5 {
				index = i
				break
			}
		}
		line_x := if index < g.tab_rects.len {
			g.tab_rects[index].x
		} else if g.tab_rects.len > 0 {
			g.tab_rects.last().x + g.tab_rects.last().w
		} else {
			g.strip.x
		}
		return DockDrop{
			kind:    .tab
			group:   g
			index:   index
			preview: Rect{line_x - 1, g.strip.y + 3, 3, g.strip.h - 6}
		}
	}
	// 2. край всей области (имеет смысл, только если в области больше одной группы или панелей)
	if side := da.edge_side_at(x, y) {
		if !(da.root.kind == .group && alone) {
			return DockDrop{
				kind:    .edge
				side:    side
				preview: dock_side_part(da.bounds, side, dock_edge_size)
			}
		}
	}
	// 3. содержимое группы (точка на полосе разбиения - ни в одной группе)
	if isnil(g) {
		return DockDrop{}
	}
	cr := g.content
	if cr.w <= 0 || cr.h <= 0 {
		return DockDrop{}
	}
	fx := (x - cr.x) / cr.w
	fy := (y - cr.y) / cr.h
	if fx > 0.3 && fx < 0.7 && fy > 0.3 && fy < 0.7 {
		if dock_same(g, src) {
			return DockDrop{}
		}
		return DockDrop{
			kind:    .tab
			group:   g
			index:   g.panels.len
			preview: cr
		}
	}
	if dock_same(g, src) && alone {
		return DockDrop{}
	}
	side := dock_nearest_side(fx, fy)
	return DockDrop{
		kind:    .split
		group:   g
		side:    side
		preview: dock_side_part(g.rect, side, 0.5)
	}
}

// edge_side_at - край всей области, у которого точка (в пределах dock_edge_zone).
fn (da &DockArea) edge_side_at(x f32, y f32) ?DockSide {
	b := da.bounds
	zone := min_f32(dock_edge_zone, min_f32(b.w, b.h) * 0.15)
	if x < b.x + zone {
		return .left
	}
	if x > b.x + b.w - zone {
		return .right
	}
	if y < b.y + zone {
		return .top
	}
	if y > b.y + b.h - zone {
		return .bottom
	}
	return none
}

// dock_nearest_side - ближайший край по относительным координатам точки в прямоугольнике.
fn dock_nearest_side(fx f32, fy f32) DockSide {
	mut side := DockSide.left
	mut best := fx
	if 1 - fx < best {
		side, best = .right, 1 - fx
	}
	if fy < best {
		side, best = .top, fy
	}
	if 1 - fy < best {
		side = .bottom
	}
	return side
}

// dock_side_part - часть прямоугольника r с доли frac у края side (предпросмотр сброса).
fn dock_side_part(r Rect, side DockSide, frac f32) Rect {
	return match side {
		.left { Rect{r.x, r.y, r.w * frac, r.h} }
		.right { Rect{r.x + r.w * (1 - frac), r.y, r.w * frac, r.h} }
		.top { Rect{r.x, r.y, r.w, r.h * frac} }
		.bottom { Rect{r.x, r.y + r.h * (1 - frac), r.w, r.h * frac} }
		.center { r }
	}
}

// apply_drop переносит панель p на место d. Перед вставкой панель снимается со старого места -
// группа-цель при этом не схлопнется: такие сбросы compute_drop отдаёт как .none.
fn (mut da DockArea) apply_drop(p &DockPanel, d DockDrop) {
	if d.kind == .tab && isnil(d.group) {
		// Сброс в пустую область (compute_drop): панель - первой группой
		da.dock(p, .center)
		da.fire_change()
		return
	}
	match d.kind {
		.none {
			return
		}
		.tab {
			mut g := d.group
			mut index := d.index
			// Перестановка внутри своей группы: после снятия панели позиции правее сдвинутся
			old := dock_panel_index(g.panels, p)
			if old >= 0 && old < index {
				index--
			}
			da.detach_panel(p)
			index = if index > g.panels.len { g.panels.len } else { index }
			g.panels.insert(index, unsafe { p })
			g.active = index
		}
		.split {
			da.detach_panel(p)
			da.split_node(d.group, p, d.side, 0.5)
		}
		.edge {
			da.detach_panel(p)
			da.split_node(da.root, p, d.side, dock_edge_size)
		}
	}
	widget_changed()
	da.fire_change()
}

// ─── Рисование ─────────────────────────────────────────

// draw: группы (полоса вкладок, содержимое активной панели), затем полосы разбиений и поверх всего
// - предпросмотр сброса и «призрак» переносимой вкладки у курсора.
pub fn (mut da DockArea) draw(mut ctx RenderContext) {
	if !da.visible {
		return
	}
	if isnil(da.root) {
		da.draw_ext_drop(mut ctx) // в пустую область тоже можно бросить панель из другого окна
		return
	}
	if !ctx.is_in_clip(da.bounds) {
		return
	}
	en := ctx.is_enabled(da.enabled)
	for mut g in da.groups() {
		da.draw_group(mut g, en, mut ctx)
	}
	da.draw_bars(da.root, en, mut ctx)
	if da.tab_dragging && en {
		da.draw_drag(mut ctx)
	}
	da.draw_ext_drop(mut ctx)
}

// draw_group - полоса вкладок группы, линия под ней и содержимое активной панели в его клипе.
fn (mut da DockArea) draw_group(mut g DockNode, en bool, mut ctx RenderContext) {
	ctx.fill_rect(g.strip, ctx.theme.eff_tab_strip_bg())
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	ctx.push_clip(g.strip)
	for i, p in g.panels {
		if i >= g.tab_rects.len {
			break
		}
		tab_r := g.tab_rects[i]
		is_active := i == g.active
		is_hover := en && dock_same(da.hover_group, &g) && da.hover_tab == i
		bg := if is_active {
			ctx.theme.eff_tab_active_bg()
		} else if is_hover {
			ctx.theme.eff_tab_hover_bg()
		} else {
			color_transparent
		}
		if bg.a > 0 {
			ctx.fill_rect(tab_r, bg)
		}
		// Тонкая черта активной вкладки снизу и разделитель справа
		if is_active {
			ctx.fill_rect(Rect{tab_r.x, tab_r.y + tab_r.h - 2, tab_r.w, 2}, ctx.theme.eff_tab_indicator())
		}
		ctx.fill_rect(Rect{tab_r.x + tab_r.w - 1, tab_r.y + 4, 1, tab_r.h - 8}, ctx.theme.eff_tab_border())
		tc := if !en {
			ctx.theme.eff_tab_disabled_text()
		} else if is_active {
			ctx.theme.eff_tab_active_text()
		} else {
			ctx.theme.eff_tab_inactive_text()
		}
		// Содержимое вкладки слева направо: иконка, текст (с «…»), крестик
		mut x := tab_r.x + da.tab_pad
		if p.icon.is_set() {
			ctx.draw_item_icon(p.icon, Rect{x, tab_r.y, dock_close_size, tab_r.h}, dock_close_size,
				tc)
			x += dock_close_size + 4
		}
		close_r := g.close_rects[i]
		text_end := if p.closable { close_r.x - 2 } else { tab_r.x + tab_r.w - da.tab_pad }
		title := bc_truncate_text(ctx, p.title, text_end - x, font)
		ctx.draw_text_with_font(title, x, tab_r.y + (tab_r.h - fh) * 0.5, tc, font)
		// Крестик - у активной вкладки и под курсором (как в VS Code), иначе полоса пестрит
		if p.closable && (is_active || is_hover) {
			if is_hover && da.hover_close {
				ctx.fill_rounded_rect(close_r, ctx.theme.eff_tab_hover_bg().brighten(-0.08),
					3)
			}
			ctx.draw_item_icon(item_icon('x'), close_r, 14, tc)
		}
	}
	ctx.pop_clip()
	ctx.fill_rect(Rect{g.rect.x, g.strip.y + g.strip.h, g.rect.w, 1}, ctx.theme.eff_tab_border())

	if g.panels.len == 0 {
		return
	}
	mut p := g.panels[g.active]
	if isnil(p.content) || g.content.w <= 0 || g.content.h <= 0 {
		return
	}
	ctx.push_clip(g.content)
	ctx.begin_disabled(da.enabled)
	ctx.draw_child(mut p.content)
	ctx.end_disabled(da.enabled)
	ctx.pop_clip()
}

// draw_bars - полосы разбиений: в покое тонкая линия границы, при наведении и перетаскивании -
// подсветка во всю толщину (цвета Splitter).
fn (da &DockArea) draw_bars(n &DockNode, en bool, mut ctx RenderContext) {
	if n.kind == .group {
		return
	}
	b := n.bar
	if en && dock_same(da.resize_node, n) {
		ctx.fill_rect(b, ctx.theme.eff_splitter_hover().with_alpha(180))
	} else if en && dock_same(da.hover_bar, n) && isnil(da.resize_node) {
		ctx.fill_rect(b, ctx.theme.eff_splitter_hover().with_alpha(120))
	} else {
		line := if n.dir == .horizontal {
			Rect{b.x + b.w * 0.5 - 0.5, b.y, 1, b.h}
		} else {
			Rect{b.x, b.y + b.h * 0.5 - 0.5, b.w, 1}
		}
		ctx.fill_rect(line, ctx.theme.eff_tab_border())
	}
	da.draw_bars(n.first, en, mut ctx)
	da.draw_bars(n.second, en, mut ctx)
}

// draw_drag - предпросмотр места сброса (полупрозрачная заливка цветом акцента с рамкой; для
// вставки вкладкой - линия) и «призрак» вкладки правее-ниже курсора.
fn (mut da DockArea) draw_drag(mut ctx RenderContext) {
	accent := ctx.theme.eff_tab_indicator()
	ctx.push_clip(da.bounds)
	if da.drop.kind != .none {
		r := da.drop.preview
		if da.drop.kind == .tab && r.w <= 3 {
			ctx.fill_rect(r, accent)
		} else {
			ctx.fill_rect(r, accent.with_alpha(60))
			ctx.draw_rect(r, accent)
		}
	}
	if !isnil(da.press_group) && da.press_tab >= 0 && da.press_tab < da.press_group.panels.len {
		p := da.press_group.panels[da.press_tab]
		font := ctx.get_font(.regular, 0)
		sz := ctx.measure_text_with_font(p.title, font)
		gr := Rect{da.drag_x + 14, da.drag_y + 10, sz.x + 16, sz.y + 8}
		ctx.fill_rounded_rect(gr, ctx.theme.eff_tab_active_bg().with_alpha(230), 4)
		ctx.draw_rounded_rect(gr, accent, 4)
		ctx.draw_text_with_font(p.title, gr.x + 8, gr.y + 4, ctx.theme.eff_tab_active_text(),
			font)
	}
	ctx.pop_clip()
}

// ─── События ───────────────────────────────────────────

// handle_event - свои части области: вкладки (активация, закрытие, перенос) и полосы разбиений.
// Содержимому панелей события доставляет окно по маршруту (event_route.v); сюда они всплывают,
// только если ребёнок их не поглотил, - тогда область их не трогает (точка не на вкладке/полосе).
pub fn (mut da DockArea) handle_event(event &GuiEvent, app &App) bool {
	if !da.visible || isnil(da.root) {
		return false
	}
	if !da.enabled && is_input_event(event) {
		da.reset_pointer_state()
		return false
	}
	if isnil(da.app) {
		da.app = unsafe { app }
	}
	match event.typ {
		.mouse_dbl_click {
			return da.on_dbl_click(event.mouse_x, event.mouse_y)
		}
		.mouse_leave {
			// курсор ушёл с области (event_route.v); идущий жест ведёт захват - не сбрасываем
			if isnil(da.resize_node) && da.press_tab < 0 {
				da.hover_group = unsafe { nil }
				da.hover_tab = -1
				da.hover_close = false
				da.set_bar_hover(unsafe { nil })
			}
			return false
		}
		.mouse_move {
			return da.on_mouse_move(event.mouse_x, event.mouse_y)
		}
		.mouse_down {
			return da.on_mouse_down(event)
		}
		.mouse_up {
			if event.mouse_btn == .left {
				return da.on_mouse_up(event.mouse_x, event.mouse_y)
			}
		}
		else {}
	}
	return false
}

// on_mouse_move: тянут полосу - новая доля; нажали на вкладку - после порога начинается перенос,
// дальше пересчитывается место сброса; иначе - наведение на вкладку, крестик и полосу. Наведение
// не поглощает событие (движение и так идёт всем на пути).
fn (mut da DockArea) on_mouse_move(x f32, y f32) bool {
	if !isnil(da.resize_node) {
		da.drag_bar_to(x, y)
		return true
	}
	if da.press_tab >= 0 && !da.press_close {
		if !da.tab_dragging {
			dx := x - da.press_x
			dy := y - da.press_y
			if dx * dx + dy * dy >= dnd_threshold * dnd_threshold {
				da.tab_dragging = true
			}
		}
		if da.tab_dragging {
			da.drag_x = x
			da.drag_y = y
			p := da.press_group.panels[da.press_tab]
			da.drop = da.compute_drop(p, x, y)
			// Вне своей области - цель может быть в другом окне (главном или плавающем)
			if da.bounds.contains(x, y) {
				da.set_ext_target(unsafe { nil }, DockDrop{})
			} else {
				da.track_ext_target(p, x, y)
			}
		}
		return true
	}
	g := da.group_at(x, y)
	da.hover_group = g
	da.hover_tab = if isnil(g) { -1 } else { dock_tab_at(g, x, y) }
	da.hover_close = da.hover_tab >= 0 && g.close_rects[da.hover_tab].contains(x, y)
	da.set_bar_hover(da.bar_at(x, y))
	return false
}

// on_mouse_down: левая на полосе - начать её перетаскивание; левая на вкладке - сделать панель
// активной и запомнить нажатие (перенос начнётся движением, закрытие крестиком - отпусканием);
// средняя на вкладке - закрыть панель (как в браузерах и VS Code).
fn (mut da DockArea) on_mouse_down(event &GuiEvent) bool {
	x, y := event.mouse_x, event.mouse_y
	if event.mouse_btn == .left {
		bar := da.bar_at(x, y)
		if !isnil(bar) {
			da.resize_node = bar
			da.drag_offset = if bar.dir == .horizontal {
				x - (bar.bar.x + bar.bar.w * 0.5)
			} else {
				y - (bar.bar.y + bar.bar.h * 0.5)
			}
			da.set_bar_hover(bar)
			return true
		}
	}
	mut g := da.group_at(x, y)
	if isnil(g) {
		return false
	}
	idx := dock_tab_at(g, x, y)
	if idx < 0 {
		return false
	}
	if event.mouse_btn == .middle {
		if g.panels[idx].closable {
			da.request_close(g.panels[idx])
		}
		return true
	}
	if event.mouse_btn != .left {
		return false
	}
	da.press_group = g
	da.press_tab = idx
	da.press_x = x
	da.press_y = y
	da.press_close = g.close_rects[idx].contains(x, y)
	if !da.press_close {
		g.active = idx
	}
	return true
}

// on_mouse_up: конец перетаскивания полосы (on_layout_change), закрытие по крестику (если
// отпустили на нём же), применение сброса переносимой панели.
fn (mut da DockArea) on_mouse_up(x f32, y f32) bool {
	if !isnil(da.resize_node) {
		da.resize_node = unsafe { nil }
		if !dock_bar_hit_rect(da.hover_bar).contains(x, y) {
			da.set_bar_hover(unsafe { nil })
		}
		da.fire_change()
		return true
	}
	if da.press_tab < 0 {
		return false
	}
	g := da.press_group
	idx := da.press_tab
	if idx >= g.panels.len {
		da.reset_pointer_state()
		return true
	}
	p := g.panels[idx]
	if da.press_close {
		if g.close_rects[idx].contains(x, y) {
			da.reset_pointer_state()
			da.request_close(p)
			return true
		}
	} else if da.tab_dragging {
		drop := da.compute_drop(p, x, y)
		// Вне своей области: в другую область (другое окно) или в новое плавающее окно
		// (dock_float.v); финиш жеста там же
		if !da.bounds.contains(x, y) {
			da.release_outside(p, x, y)
			return true
		}
		da.set_ext_target(unsafe { nil }, DockDrop{})
		da.reset_pointer_state()
		da.apply_drop(p, drop)
		return true
	}
	da.reset_pointer_state()
	return true
}

// request_close - закрытие пользователем: спросить on_panel_close, закрыть, сообщить об изменении.
fn (mut da DockArea) request_close(p &DockPanel) {
	if da.on_panel_close != unsafe { nil } && !da.on_panel_close(p) {
		return
	}
	da.close_panel(p)
	da.fire_change()
}

// drag_bar_to - новая доля перетаскиваемого разбиения по курсору (минимумы частей - в layout_node).
fn (mut da DockArea) drag_bar_to(x f32, y f32) {
	mut n := da.resize_node
	main := if n.dir == .horizontal { n.rect.w } else { n.rect.h }
	usable := main - da.bar_size
	if usable <= 0 {
		return
	}
	bar_center := if n.dir == .horizontal { x - n.rect.x } else { y - n.rect.y } - da.drag_offset
	min_part := min_f32(da.min_pane, usable * 0.5)
	first_sz := clamp_f32(bar_center - da.bar_size * 0.5, min_part, usable - min_part)
	n.ratio = first_sz / usable
}

// set_bar_hover - полоса под курсором; ставит курсор изменения размера при входе на полосу и
// возвращает прежний при уходе (как Splitter).
fn (mut da DockArea) set_bar_hover(bar &DockNode) {
	if dock_same(bar, da.hover_bar) {
		return
	}
	da.hover_bar = bar
	if !isnil(bar) {
		if da.saved_cursor == unsafe { nil } {
			da.saved_cursor = current_cursor()
		}
		set_cursor(if bar.dir == .horizontal {
			sdl_system_cursor_sizewe
		} else {
			sdl_system_cursor_sizens
		})
	} else if da.saved_cursor != unsafe { nil } {
		restore_cursor_handle(da.saved_cursor)
		da.saved_cursor = unsafe { nil }
	}
}

// ─── Сохранение раскладки ──────────────────────────────

// dock_save_node - узел в формате save_layout.
fn dock_save_node(n &DockNode, mut sb []string) {
	if n.kind == .group {
		sb << '['
		for i, p in n.panels {
			if i > 0 {
				sb << ' '
			}
			if i == n.active {
				sb << '*'
			}
			sb << p.id
		}
		sb << ']'
		return
	}
	sb << if n.dir == .horizontal { 'h' } else { 'v' }
	sb << '${n.ratio:.3f}('
	dock_save_node(n.first, mut sb)
	sb << ','
	dock_save_node(n.second, mut sb)
	sb << ')'
}

// DockLayoutParser - разбор строки save_layout рекурсивным спуском. area - откуда брать панели по
// id; used - id, уже попавшие в раскладку (повтор пропускается: панель не бывает в двух местах).
struct DockLayoutParser {
	src string
mut:
	pos  int
	area &DockArea
	used map[string]bool
}

fn (mut ps DockLayoutParser) skip_spaces() {
	for ps.pos < ps.src.len && ps.src[ps.pos] == ` ` {
		ps.pos++
	}
}

// expect - обязательный символ c на текущей позиции.
fn (mut ps DockLayoutParser) expect(c u8) ! {
	ps.skip_spaces()
	if ps.pos >= ps.src.len || ps.src[ps.pos] != c {
		return error('dock layout: expected `${c.ascii_str()}` at ${ps.pos}')
	}
	ps.pos++
}

// parse_node: 'h'/'v' - разбиение, '[' - группа.
fn (mut ps DockLayoutParser) parse_node() !&DockNode {
	ps.skip_spaces()
	if ps.pos >= ps.src.len {
		return error('dock layout: unexpected end')
	}
	c := ps.src[ps.pos]
	if c == `[` {
		return ps.parse_group()
	}
	if c != `h` && c != `v` {
		return error('dock layout: expected `h`, `v` or `[` at ${ps.pos}')
	}
	ps.pos++
	start := ps.pos
	for ps.pos < ps.src.len && (ps.src[ps.pos].is_digit() || ps.src[ps.pos] == `.`) {
		ps.pos++
	}
	if start == ps.pos {
		return error('dock layout: expected ratio at ${start}')
	}
	ratio := clamp_f32(ps.src[start..ps.pos].f32(), 0.0, 1.0)
	ps.expect(`(`)!
	first := ps.parse_node()!
	ps.expect(`,`)!
	second := ps.parse_node()!
	ps.expect(`)`)!
	return &DockNode{
		kind:   .split
		dir:    if c == `h` { SplitDir.horizontal } else { SplitDir.vertical }
		ratio:  ratio
		first:  first
		second: second
	}
}

// parse_group: '[' id* ']', '*' перед id - активная панель.
fn (mut ps DockLayoutParser) parse_group() !&DockNode {
	ps.expect(`[`)!
	mut g := &DockNode{
		kind: .group
	}
	for {
		ps.skip_spaces()
		if ps.pos >= ps.src.len {
			return error('dock layout: missing `]`')
		}
		if ps.src[ps.pos] == `]` {
			ps.pos++
			break
		}
		active := ps.src[ps.pos] == `*`
		if active {
			ps.pos++
		}
		start := ps.pos
		for ps.pos < ps.src.len && ps.src[ps.pos] !in [` `, `]`, `[`, `(`, `)`, `,`] {
			ps.pos++
		}
		id := ps.src[start..ps.pos]
		if id == '' {
			return error('dock layout: empty panel id at ${start}')
		}
		if id in ps.used {
			continue
		}
		p := ps.area.panel_by_id(id) or { continue }
		ps.used[id] = true
		if active {
			g.active = g.panels.len
		}
		g.panels << p
	}
	return g
}
