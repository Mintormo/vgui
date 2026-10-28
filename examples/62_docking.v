module main

// Пример 62. Перетаскиваемые панели (docking, dock_area.v).
//
// Что показано:
//   - область DockArea с пятью панелями: дерево файлов слева, редактор и заметки вкладками в
//     центре, вывод снизу, свойства справа;
//   - вкладку можно утащить: на полосу вкладок другой группы (вставить вкладкой), на край или в
//     середину группы (разделить её / добавить вкладкой), к краю всего окна;
//   - полосы между группами тянутся мышью;
//   - крестик и средняя кнопка мыши закрывают панель («Output» закрыть нельзя), кнопки сверху
//     возвращают закрытую панель на прежнее место;
//   - Save запоминает раскладку строкой, Restore возвращает её (строка видна внизу окна).
//
// Запуск (из корня репозитория):
//   ~/soft/v/v run examples/62_docking.v

import vgui

fn main() {
	mut app := vgui.create_app(theme: vgui.dark_theme())!
	// В заголовке - дефис-минус: глиф длинного тире не рендерится
	mut win := vgui.create_window(title: 'Docking - demo', width: 1000, height: 640)!

	// ── Содержимое панелей ──
	mut tree := vgui.tree_view()
	tree.editable = false
	mut proj := vgui.tree_node('vgui')
	proj.add_child('dock_area.v')
	proj.add_child('splitter.v')
	proj.add_child('tab_box.v')
	tree.add_root(proj)

	mut editor := vgui.code_editor()
	editor.set_text('fn main() {\n\tprintln("drag the tabs around")\n}\n')

	mut notes := vgui.text_area('Notes...')
	mut output := vgui.text_area('')
	output.set_text('Build finished.\n')
	mut props := vgui.property_grid()
	props.add_string('Name', 'DockArea')
	props.add_bool('Visible', true)

	// ── Панели ──
	mut files_p := vgui.dock_panel('files', 'Files', tree)
	files_p.icon = vgui.item_icon('folder')
	mut editor_p := vgui.dock_panel('editor', 'main.v', editor)
	editor_p.icon = vgui.item_icon('file-code')
	mut notes_p := vgui.dock_panel('notes', 'Notes', notes)
	mut output_p := vgui.dock_panel('output', 'Output', output)
	output_p.closable = false
	mut props_p := vgui.dock_panel('props', 'Properties', props)

	// ── Начальная раскладка ──
	mut dock := vgui.dock_area()
	dock.add_panel(editor_p)
	dock.dock(notes_p, .center, target: editor_p)
	dock.dock(files_p, .left, size: 0.22)
	dock.dock(props_p, .right, target: editor_p, size: 0.3)
	dock.dock(output_p, .bottom, target: editor_p, size: 0.3)
	dock.show_panel(editor_p) // активная вкладка центральной группы - редактор

	mut status := vgui.label('')
	status.text = 'Layout: ${dock.save_layout()}'
	dock.on_layout_change = fn [mut dock, mut status] () {
		status.text = 'Layout: ${dock.save_layout()}'
	}

	// ── Кнопки: вернуть закрытые панели, сохранить и восстановить раскладку ──
	mut bar := vgui.create_hbox_fill()
	bar.set_spacing(6)
	for p in [files_p, editor_p, notes_p, props_p] {
		mut btn := vgui.button(p.title)
		show := fn [mut dock, p, mut status] () {
			dock.show_panel(p)
			status.text = 'Layout: ${dock.save_layout()}'
		}
		btn.on_click = show
		bar.add(btn)
	}
	bar.add(vgui.create_spacer())
	mut saved := &Saved{
		layout: dock.save_layout()
	}
	mut save_btn := vgui.button('Save')
	save_btn.on_click = fn [mut dock, mut saved, mut status] () {
		saved.layout = dock.save_layout()
		status.text = 'Saved: ${saved.layout}'
	}
	mut restore_btn := vgui.button('Restore')
	restore_btn.on_click = fn [mut dock, saved, mut status] () {
		dock.load_layout(saved.layout) or {
			status.text = err.msg()
			return
		}
		status.text = 'Restored: ${saved.layout}'
	}
	bar.add(save_btn)
	bar.add(restore_btn)

	mut root := vgui.create_vbox_fill()
	root.set_padding(8)
	root.set_spacing(6)
	root.add(bar)
	root.add(dock, flex: 1)
	root.add(status)
	win.add_widget(root)
	app.add_window(win)
	app.run()
}

// Saved - сохранённая строка раскладки (в куче: замыкания кнопок захватывают копию значения,
// а менять его должна одна кнопка, а читать - другая).
@[heap]
struct Saved {
mut:
	layout string
}
