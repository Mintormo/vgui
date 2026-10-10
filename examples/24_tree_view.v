module main

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	mut win := vgui.create_window(title: 'TreeView - demo')!

	mut status := vgui.label('Узел: -')
	status.color = vgui.Color{180, 180, 180, 255}

	// Дерево строится из узлов TreeNode. add_child возвращает новый узел.
	mut tv := vgui.tree_view()

	mut project := vgui.tree_node('project')
	mut src := project.add_child('src')
	src.add_child('main.v')
	mut ui := src.add_child('ui')
	ui.add_child('window.v')
	ui.add_child('button.v')
	mut assets := project.add_child('assets')
	assets.add_child('fonts')
	assets.add_child('icons')
	project.add_child('v.mod')
	tv.add_root(project)

	tv.on_select = fn [mut status] (node &vgui.TreeNode) {
		status.text = 'Выбран: ${node.text}'
		status.color = vgui.Color{66, 165, 245, 255}
	}

	mut b_expand := vgui.button('Развернуть всё')
	b_expand.on_click = fn [mut tv] () {
		tv.expand_all()
	}
	mut b_collapse := vgui.button('Свернуть всё')
	b_collapse.style = .outline
	b_collapse.on_click = fn [mut tv] () {
		tv.collapse_all()
	}

	mut row := vgui.create_hbox_fill()
	row.set_spacing(6)
	row.add(b_expand, flex: 1)
	row.add(b_collapse, flex: 1)

	mut root := vgui.create_vbox_fill()
	root.set_padding(16)
	root.set_spacing(8)
	root.add(status)
	root.add(tv, flex: 1)
	root.add(row)

	win.add_widget(root)
	win.set_ui_scale(1.25)
	app.add_window(win)
	app.run()
}
