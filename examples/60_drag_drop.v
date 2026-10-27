module main

// Пример 60. Перетаскивание между виджетами (drag-and-drop, dnd.v).
//
// Что показано:
//   - два списка задач: строки переставляются внутри списка (reorder) и
//     переносятся из одного в другой (drag_rows + поле dnd у цели);
//   - дерево: узлы переносятся перед/после другого узла или внутрь него;
//   - корзина: обычная метка-цель, принимает и строки, и узлы;
//   - второе окно «Inbox»: принимает строки из первого окна (перенос между
//     окнами) и файлы/текст, брошенные из других приложений;
//   - встроенный приём без настройки: поле ввода вставляет путь брошенного
//     файла или текст, ImageView открывает брошенную картинку.
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/60_drag_drop.v

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится
	mut win := vgui.create_window(title: 'Drag and drop - demo', width: 820, height: 520)!

	mut status := vgui.label('Drag rows, tree nodes, or files from your file manager')

	// ── Два списка: перестановка и перенос ──
	mut todo := vgui.list_box()
	todo.add_items(['Write the report', 'Call the bank', 'Buy coffee', 'Fix the bike'])
	mut done := vgui.list_box()
	done.add_items(['Water the plants'])
	// reorder - строки переставляются внутри списка; строку можно утащить и
	// в другую цель (reorder включает drag_rows)
	todo.reorder = true
	done.reorder = true
	// Цель для строк из ДРУГОГО списка: вставить на место линии вставки
	// (info.index) и убрать из списка-источника (data.index - номер там).
	// Свои строки список переставляет сам (reorder), сюда они не приходят.
	vgui.set_drop_target(mut todo, [vgui.lb_drag_kind], fn [mut todo, mut done, mut status] (info vgui.DropInfo) {
		move_between(mut done, mut todo, info, mut status)
	})
	vgui.set_drop_target(mut done, [vgui.lb_drag_kind], fn [mut todo, mut done, mut status] (info vgui.DropInfo) {
		move_between(mut todo, mut done, info, mut status)
	})
	todo.on_reorder = fn [mut status] (from int, to int) {
		status.text = 'To do: row ${from + 1} moved to position ${to + 1}'
	}

	// ── Дерево с переносом узлов ──
	mut tree := vgui.tree_view()
	tree.editable = false
	mut proj := vgui.tree_node('Project')
	mut src := proj.add_child('src')
	src.add_child('main.v')
	src.add_child('ui.v')
	proj.add_child('README.md')
	mut assets := vgui.tree_node('assets')
	assets.add_child('logo.png')
	tree.add_root(proj)
	tree.add_root(assets)
	tree.reorder = true
	tree.on_node_moved = fn [mut status] (node &vgui.TreeNode, parent &vgui.TreeNode, index int) {
		where := if unsafe { parent == nil } { 'top level' } else { parent.text }
		status.text = '"${node.text}" moved into ${where}, position ${index + 1}'
	}

	// ── Корзина: метка, принимающая строки и узлы ──
	mut trash := vgui.label('Trash - drop rows or nodes here')
	trash.tooltip = 'Accepts list rows and tree nodes'
	vgui.set_drop_target(mut trash, [vgui.lb_drag_kind, vgui.tv_drag_kind], fn [mut todo, mut done, mut tree, mut status] (info vgui.DropInfo) {
		if info.data.kind == vgui.tv_drag_kind {
			tree.remove_node(info.data.node)
		} else if info.from(todo) {
			todo.remove_row(info.data.index)
		} else if info.from(done) {
			done.remove_row(info.data.index)
		}
		status.text = 'Deleted: ${info.data.text}'
	})

	mut lists := vgui.create_hbox_fill()
	lists.set_spacing(8)
	lists.add(column('To do', todo), flex: 1)
	lists.add(column('Done', done), flex: 1)
	lists.add(column('Tree', tree), flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(lists, flex: 1)
	root.add(trash)
	win.add_widget(root)
	app.add_window(win)

	// ── Второе окно: строки из первого окна и файлы извне ──
	mut win2 := vgui.create_window(title: 'Inbox', width: 340, height: 520)!
	mut inbox := vgui.list_box()
	vgui.set_drop_target(mut inbox, [vgui.lb_drag_kind, vgui.dnd_kind_files, vgui.dnd_kind_text], fn [mut inbox, mut status] (info vgui.DropInfo) {
		// Строку из списка первого окна копируем (источник её не теряет),
		// файл - по одному вызову на каждый брошенный файл
		text := if info.data.kind == vgui.dnd_kind_files {
			'File: ${info.data.text}'
		} else {
			info.data.text
		}
		inbox.insert_item(info.index, text)
		from := if info.external { 'another application' } else { 'the main window' }
		status.text = 'Inbox received an item from ${from}'
	})
	// Встроенный приём (accept_drops = true по умолчанию): ничего настраивать
	// не нужно - поле вставит путь файла или текст, ImageView откроет картинку
	mut path_input := vgui.text_input('Drop a file or text here')
	mut preview := vgui.image_view()
	preview.tooltip = 'Drop an image file here'

	mut root2 := vgui.create_vbox_fill()
	root2.set_padding(16)
	root2.set_spacing(8)
	root2.add(vgui.label('Drop rows from the main window,\nor files from your file manager'))
	root2.add(inbox, flex: 1)
	root2.add(path_input)
	root2.add(preview, flex: 1)
	win2.add_widget(root2)
	app.add_window(win2)

	app.run()
}

// column - заголовок над виджетом списка/дерева, растянутым на всю высоту.
fn column(title string, w &vgui.Widget) &vgui.VBox {
	mut col := vgui.create_vbox_fill()
	col.set_spacing(4)
	col.add(vgui.label(title))
	col.add(w, flex: 1)
	return col
}

// move_between переносит строку, брошенную в список to: вставляет её на место
// линии вставки и убирает из списка from, если строка пришла оттуда. Строки
// из чужого окна или виджета просто копируются.
fn move_between(mut from vgui.ListBox, mut to vgui.ListBox, info vgui.DropInfo, mut status vgui.Label) {
	to.insert_item(info.index, info.data.text)
	if info.from(from) {
		from.remove_row(info.data.index)
	}
	status.text = 'Moved: ${info.data.text}'
}
