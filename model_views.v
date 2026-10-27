module vgui

// ═══════════════════════════════════════════════════════════
//  Модели данных в видах: ListBox, TableView, TreeView (models.v;
//  PROJECT.md, «Реактивные данные: Observable и модели»).
// ═══════════════════════════════════════════════════════════
//
//  ListBox и TableView показывают TableModel через свой виртуальный режим:
//  текст видимых ячеек спрашивается у модели на каждом кадре, а число строк
//  вид сверяет с моделью, когда у неё новая версия (sync_model в начале
//  draw и handle_event). TreeView узлы хранит, поэтому при новой версии
//  TreeModel перестраивает их, сохраняя раскрытие, выбор и прокрутку по id
//  узла (TreeNode.tag).
//
//  set_model / set_tree_model заменяют прежнее содержимое вида; clear()
//  (clear_rows у таблицы) снимает модель.

// set_model показывает в таблице модель m: колонки задаются как обычно
// (add_column), ячейки - m.cell_text. Прежние строки удаляются; правка ячейки
// в виртуальном режиме уходит в on_change, и данные меняет приложение (в
// модели) - иначе ячейка покажет прежний текст.
pub fn (mut t TableView) set_model(m TableModel) {
	t.set_virtual(m.row_count(), fn [m] (row int, col int) string {
		return m.cell_text(row, col)
	})
	t.model = m
	t.model_ver = m.version()
}

// sync_model - новая версия модели: число строк сверяется с моделью
// (set_virtual_count сам поправит выбор, правку и прокрутку). Текст ячеек
// перечитывать не нужно - он спрашивается на каждом кадре.
fn (mut t TableView) sync_model() {
	m := t.model or { return }
	ver := m.version()
	if ver == t.model_ver {
		return
	}
	t.model_ver = ver
	t.set_virtual_count(m.row_count())
}

// set_model показывает в списке модель m: строка - m.cell_text(row, col) по
// колонкам (без колонок - колонка 0). Прежние строки удаляются.
pub fn (mut lb ListBox) set_model(m TableModel) {
	lb.set_virtual(m.row_count(), fn [m] (row int, col int) string {
		return m.cell_text(row, col)
	})
	lb.model = m
	lb.model_ver = m.version()
}

// sync_model - то же, что у TableView.
fn (mut lb ListBox) sync_model() {
	m := lb.model or { return }
	ver := m.version()
	if ver == lb.model_ver {
		return
	}
	lb.model_ver = ver
	lb.set_virtual_count(m.row_count())
}

// tree_model_max_depth - защита от цикла в модели (узел среди своих потомков):
// глубже этого узлы не строятся.
const tree_model_max_depth = 64

// set_tree_model показывает в дереве модель m. Узлы строятся от корней
// (m.child_ids('')), у каждого tag = id; новые узлы свёрнуты. Прежние корни
// убираются.
pub fn (mut tv TreeView) set_tree_model(m TreeModel) {
	tv.clear()
	tv.tree_model = m
	tv.tree_model_ver = m.version()
	tv.rebuild_from_model(m)
}

// clear_tree_model снимает модель; узлы остаются как есть (обычное дерево).
pub fn (mut tv TreeView) clear_tree_model() {
	tv.tree_model = none
}

// sync_model - новая версия модели: узлы перестраиваются.
fn (mut tv TreeView) sync_model() {
	m := tv.tree_model or { return }
	ver := m.version()
	if ver == tv.tree_model_ver {
		return
	}
	tv.tree_model_ver = ver
	tv.rebuild_from_model(m)
}

// rebuild_from_model строит узлы заново по модели. Раскрытие, выбор и
// прокрутка переживают перестройку: они запоминаются по id (tag) старых
// узлов и восстанавливаются у новых с тем же id. Узел, исчезнувший из
// модели, теряет выбор (выбора нет, on_select не зовётся).
fn (mut tv TreeView) rebuild_from_model(m TreeModel) {
	mut expanded := map[string]bool{}
	for root in tv.roots {
		collect_expanded(root, mut expanded)
	}
	selected_id := if unsafe { tv.selected != nil } { tv.selected.tag } else { '' }
	had_selection := unsafe { tv.selected != nil }
	scroll_x := tv.scroll_x
	scroll_y := tv.scroll_y

	tv.clear()
	for id in m.child_ids('') {
		tv.add_root(build_model_node(m, id, expanded, 0))
	}

	if had_selection {
		tv.selected = find_node_by_tag(tv.roots, selected_id)
	}
	// clear() обнулил прокрутку; draw() сам обрежет её по новой высоте
	tv.scroll_x = scroll_x
	tv.scroll_y = scroll_y
}

// collect_expanded запоминает раскрытие узла и его потомков по tag.
fn collect_expanded(n &TreeNode, mut out map[string]bool) {
	out[n.tag] = n.expanded
	for c in n.children {
		collect_expanded(c, mut out)
	}
}

// build_model_node строит узел id с потомками. Раскрытие - как было у узла
// с тем же id, новый узел - свёрнут.
fn build_model_node(m TreeModel, id string, expanded map[string]bool, depth int) &TreeNode {
	mut n := tree_node(m.item_text(id))
	n.tag = id
	n.expanded = expanded[id] or { false }
	if depth < tree_model_max_depth {
		for child in m.child_ids(id) {
			n.add(build_model_node(m, child, expanded, depth + 1))
		}
	}
	return n
}

// find_node_by_tag - первый узел с данным tag (обход в глубину) или nil.
fn find_node_by_tag(nodes []&TreeNode, tag string) &TreeNode {
	for n in nodes {
		if n.tag == tag {
			return n
		}
		found := find_node_by_tag(n.children, tag)
		if unsafe { found != nil } {
			return found
		}
	}
	return unsafe { nil }
}
