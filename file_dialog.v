module vgui

import os

pub enum FileDialogMode {
	open
	save
	folder
}

@[params]
pub struct FileDialogConfig {
pub mut:
	title        string
	start_dir    string
	default_name string
	mode         FileDialogMode = .open
}

enum FdSortMode {
	name_asc
	name_desc
	ext_asc
	size_asc
	size_desc
}

struct FdState {
mut:
	result_path      string
	confirmed        bool
	show_hidden      bool
	mode             FileDialogMode
	default_name     string
	start_dir        string
	selected_path    string
	pending_refocus  bool
	pending_rename   bool
	sort_mode        FdSortMode = .name_asc
	tree_view        &TreeView  = unsafe { nil }
	rename_path      string
	rename_active    bool
	delete_confirmed bool
	delete_pending   bool
	delete_path      string
	dlg_ptr          &Dialog = unsafe { nil }
	app_ptr          &App    = unsafe { nil }
}

fn fd_node_path(node &TreeNode) string {
	ip := node.icon_path
	if ip.starts_with('dir:') {
		return ip[4..]
	}
	if ip.starts_with('file:') {
		return ip[5..]
	}
	return ''
}

fn fd_is_dir(node &TreeNode) bool {
	return node.icon_path.starts_with('dir:')
}

fn fd_is_file(node &TreeNode) bool {
	return node.icon_path.starts_with('file:')
}

fn fd_is_hidden(name string) bool {
	return name.len > 0 && name[0] == `.`
}

fn fd_get_ext(name string) string {
	dot := name.last_index('.') or { return '' }
	return name[dot..].to_lower()
}

fn fd_sort_names(mut names []string, sort_mode FdSortMode) {
	match sort_mode {
		.name_asc {
			names.sort()
		}
		.name_desc {
			names.sort()
			mut i := 0
			mut j := names.len - 1
			for i < j {
				names[i], names[j] = names[j], names[i]
				i++
				j--
			}
		}
		.ext_asc {
			names.sort_with_compare(fn (a &string, b &string) int {
				ea := fd_get_ext(*a)
				eb := fd_get_ext(*b)
				if ea < eb {
					return -1
				}
				if ea > eb {
					return 1
				}
				if *a < *b {
					return -1
				}
				if *a > *b {
					return 1
				}
				return 0
			})
		}
		.size_asc, .size_desc {
			names.sort()
		}
	}
}

fn fd_sort_files_by_size(mut files []string, dir_path string, descending bool) {
	for i in 1 .. files.len {
		key := files[i]
		key_size := fd_file_size(os.join_path(dir_path, key))
		mut j := i - 1
		for j >= 0 {
			j_size := fd_file_size(os.join_path(dir_path, files[j]))
			should_swap := if descending { j_size < key_size } else { j_size > key_size }
			if !should_swap {
				break
			}
			files[j + 1] = files[j]
			j--
		}
		files[j + 1] = key
	}
}

fn fd_file_size(path string) i64 {
	return i64(os.file_size(path))
}

// ─── Populate ──────────────────────────────────────────

fn fd_populate_impl(node &TreeNode, state &FdState, shallow bool) {
	mut n := unsafe { node }
	if n.children.len > 0 {
		if !shallow {
			fd_ensure_children_prepopulated(node, state)
		}
		return
	}
	dir_path := fd_node_path(node)
	if dir_path.len == 0 {
		return
	}
	raw := os.ls(dir_path) or { return }
	mut dirs := []string{cap: raw.len}
	mut files := []string{cap: raw.len}
	for name in raw {
		if !state.show_hidden && fd_is_hidden(name) {
			continue
		}
		full := os.join_path(dir_path, name)
		if os.is_dir(full) {
			dirs << name
		} else {
			if state.mode == .folder {
				continue
			}
			files << name
		}
	}
	dirs.sort()
	match state.sort_mode {
		.size_asc { fd_sort_files_by_size(mut files, dir_path, false) }
		.size_desc { fd_sort_files_by_size(mut files, dir_path, true) }
		else { fd_sort_names(mut files, state.sort_mode) }
	}

	for d in dirs {
		full := os.join_path(dir_path, d)
		mut child := tree_node(d)
		child.icon_path = 'dir:${full}'
		child.expanded = false
		child.text_color = Color{130, 190, 255, 255}
		n.add(child)
	}
	for f in files {
		full := os.join_path(dir_path, f)
		mut child := tree_node(f)
		child.icon_path = 'file:${full}'
		child.expanded = false
		n.add(child)
	}
	if !shallow {
		fd_ensure_children_prepopulated(node, state)
	}
}

fn fd_populate(node &TreeNode, state &FdState) {
	fd_populate_impl(node, state, false)
}

fn fd_ensure_children_prepopulated(node &TreeNode, state &FdState) {
	for ch in node.children {
		if fd_is_dir(ch) && ch.children.len == 0 {
			fd_populate_impl(ch, state, true)
		}
	}
}

fn fd_populate_shallow(node &TreeNode, state &FdState) {
	fd_populate_impl(node, state, true)
}

// ─── FS roots ──────────────────────────────────────────

fn fd_build_roots(_ &FdState) []&TreeNode {
	mut roots := []&TreeNode{}
	$if windows {
		for letter in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'.runes() {
			drive := '${rune(letter)}:\\'
			if os.is_dir(drive) {
				mut r := tree_node('${rune(letter)}:')
				r.icon_path = 'dir:${drive}'
				r.expanded = false
				r.text_color = Color{130, 190, 255, 255}
				roots << r
			}
		}
	} $else {
		mut r := tree_node('/')
		r.icon_path = 'dir:/'
		r.expanded = false
		r.text_color = Color{130, 190, 255, 255}
		roots << r
	}
	return roots
}

// fd_is_root reports a filesystem root: '/' or a Windows drive ('C:\\').
fn fd_is_root(path string) bool {
	if path == '/' {
		return true
	}
	$if windows {
		p := path.trim_right('\\/')
		return p.len == 2 && p[1] == `:`
	}
	return false
}

fn fd_center_selected(mut tv TreeView, ctx_ptr &RenderContext) {
	if unsafe { tv.selected == nil } || unsafe { ctx_ptr == nil } {
		return
	}
	idx := tv.flat_index_of(tv.selected)
	if idx < 0 {
		return
	}
	inner := tv.inner_rect()
	item_center := f32(idx) * tv.item_height + tv.item_height * 0.5
	tv.scroll_y = clamp_f32(item_center - inner.h * 0.5, 0, tv.max_scroll_y(ctx_ptr))
}

fn fd_expand_to_dir(mut tv TreeView, target string, state &FdState) {
	if target.len == 0 {
		return
	}
	normalized := os.real_path(target)
	// Windows: C:\Users\... -> ['C:', 'Users', ...] (tree roots are 'C:')
	mut parts := $if windows { normalized.replace('/', '\\').split('\\') } $else {
		normalized.split('/')
	}
	if parts.len > 0 && parts[0] == '' {
		parts[0] = '/'
	}
	for parts.len > 0 && parts[parts.len - 1] == '' {
		parts.delete(parts.len - 1)
	}
	mut current := tv.roots.clone()
	mut last := unsafe { &TreeNode(nil) }
	for part in parts {
		mut found := false
		for node in current {
			np := fd_node_path(node)
			mn := if fd_is_root(np) { np.trim_right('\\') } else { os.base(np) }
			if mn == part && fd_is_dir(node) {
				mut mn2 := unsafe { node }
				mn2.expanded = true
				fd_populate(node, state)
				current = mn2.children.clone()
				last = mn2
				found = true
				break
			}
		}
		if !found {
			break
		}
	}
	if unsafe { last != nil } {
		tv.set_selected(last)
	}
}

fn fd_locate_and_select(mut tv TreeView, target string, state &FdState) {
	if target.len == 0 {
		return
	}
	normalized := os.real_path(target)
	if os.is_dir(normalized) {
		fd_expand_to_dir(mut tv, normalized, state)
		return
	}
	parent_path := os.dir(normalized)
	fd_expand_to_dir(mut tv, parent_path, state)
	parent_node := tv.get_selected()
	if unsafe { parent_node == nil } {
		return
	}
	if !fd_is_dir(parent_node) {
		return
	}
	fd_populate(parent_node, state)
	for ch in parent_node.children {
		if fd_node_path(ch) == normalized {
			tv.set_selected(ch)
			return
		}
	}
	base := os.base(normalized)
	mut best := unsafe { &TreeNode(nil) }
	mut best_found := false
	for i in 0 .. parent_node.children.len {
		ch := parent_node.children[i]
		if fd_is_file(ch) && ch.text >= base && !best_found {
			best = unsafe { ch }
			best_found = true
			break
		}
	}
	if unsafe { best == nil } {
		for i in 0 .. parent_node.children.len {
			ch := parent_node.children[i]
			if fd_is_file(ch) {
				best = unsafe { ch }
				break
			}
		}
	}
	if unsafe { best == nil } && parent_node.children.len > 0 {
		best = unsafe { parent_node.children[0] }
	}
	if unsafe { best != nil } {
		tv.set_selected(best)
	}
}

fn fd_rebuild_tree(mut state FdState) {
	if unsafe { state.tree_view == nil } {
		return
	}
	target := state.selected_path
	fallback := state.start_dir
	state.tree_view.clear()
	roots := fd_build_roots(state)
	for r in roots {
		state.tree_view.add_root(r)
	}
	if target.len > 0 {
		fd_locate_and_select(mut state.tree_view, target, state)
	} else if fallback.len > 0 {
		fd_expand_to_dir(mut state.tree_view, fallback, state)
	}
	sel := state.tree_view.get_selected()
	if unsafe { sel != nil } {
		state.selected_path = fd_node_path(sel)
	}
	state.pending_refocus = true
}

fn fd_selected_parent_dir(state &FdState) string {
	if state.selected_path.len == 0 {
		return state.start_dir
	}
	if os.is_dir(state.selected_path) {
		return state.selected_path
	}
	return os.dir(state.selected_path)
}

// ─── Create new folder ─────────────────────────────────

fn fd_create_folder(mut state FdState) {
	parent := fd_selected_parent_dir(state)
	if parent.len == 0 {
		return
	}
	mut name := 'New Folder'
	mut full := os.join_path(parent, name)
	mut counter := 1
	for os.exists(full) {
		counter++
		name = 'New Folder ${counter}'
		full = os.join_path(parent, name)
	}
	os.mkdir(full) or { return }
	state.selected_path = full
	fd_rebuild_tree(mut state)
}

// ─── Rename — force TreeView into inline edit mode ─────

fn fd_start_rename(mut state FdState) {
	if state.selected_path.len == 0 {
		return
	}
	if !os.exists(state.selected_path) {
		return
	}
	base := os.base(state.selected_path)
	if base.len == 0 || base == '/' || fd_is_root(state.selected_path) {
		return
	}
	if unsafe { state.tree_view == nil } {
		return
	}
	sel := state.tree_view.get_selected()
	if unsafe { sel == nil } {
		return
	}
	node_path := fd_node_path(sel)
	if node_path != state.selected_path {
		return
	}
	state.pending_rename = true
}

fn fd_do_pending_rename(mut state FdState) {
	state.pending_rename = false

	if state.selected_path.len == 0 {
		return
	}
	if !os.exists(state.selected_path) {
		return
	}
	if unsafe { state.tree_view == nil } {
		return
	}
	if unsafe { state.dlg_ptr == nil } {
		return
	}

	mut tv := state.tree_view
	sel := tv.get_selected()
	if unsafe { sel == nil } {
		return
	}

	node_path := fd_node_path(sel)
	if node_path != state.selected_path {
		return
	}

	state.dlg_ptr.win.ctx.focus.focus_tree_view(tv, 0)
	tv.focused = true

	state.rename_active = true
	state.rename_path = state.selected_path

	tv.editable = true
	tv.editing = true
	tv.edit_node = unsafe { sel }
	tv.edit_original = sel.text
	tv.edit_buf = sel.text.runes()
	tv.edit_cur = tv.edit_buf.len
	tv.edit_scroll_x = 0
	tv.edit_sel_a = 0
	tv.edit_sel_b = tv.edit_buf.len
	tv.edit_drag = false
	tv.edit_history.clear()
}

fn fd_finish_rename(mut state FdState, _ string, new_text string) {
	was_active := state.rename_active
	state.rename_active = false
	if unsafe { state.tree_view != nil } {
		state.tree_view.editable = false
	}
	if !was_active {
		return
	}
	if state.rename_path.len == 0 {
		return
	}
	new_name := new_text.trim_space()
	if new_name.len == 0 {
		return
	}
	old_base := os.base(state.rename_path)
	if new_name == old_base {
		state.rename_path = ''
		return
	}

	parent_dir := os.dir(state.rename_path)
	new_path := os.join_path(parent_dir, new_name)
	if os.exists(new_path) {
		state.rename_path = ''
		return
	}

	os.rename(state.rename_path, new_path) or {
		state.rename_path = ''
		return
	}
	state.selected_path = new_path
	state.rename_path = ''
	fd_rebuild_tree(mut state)
}

fn fd_cancel_rename(mut state FdState) {
	was_active := state.rename_active
	state.rename_active = false
	state.rename_path = ''
	if unsafe { state.tree_view != nil } {
		mut tv := state.tree_view
		tv.editable = false
		if tv.editing {
			if unsafe { tv.edit_node != nil } {
				mut n := unsafe { tv.edit_node }
				n.text = tv.edit_original
			}
			tv.editing = false
			tv.edit_node = unsafe { nil }
		}
	}
	_ = was_active
}

// ─── Delete with confirmation dialog ───────────────────

fn fd_delete_selected(mut state FdState, parent_win &Window, mut app App) {
	if state.selected_path.len == 0 {
		return
	}
	if !os.exists(state.selected_path) {
		return
	}
	base := os.base(state.selected_path)
	if base.len == 0 || base == '/' || fd_is_root(state.selected_path) {
		return
	}

	is_dir := os.is_dir(state.selected_path)
	item_type := if is_dir { 'folder' } else { 'file' }
	msg := 'Delete ${item_type} "${base}"?'

	state.delete_path = state.selected_path
	state.delete_pending = true
	state.delete_confirmed = false

	mut confirm_dlg := create_dialog(DialogConfig{
		title:     'Confirm Delete'
		parent:    unsafe { parent_win }
		theme:     parent_win.ctx.theme
		font_path: parent_win.config.font_path
		mono_path: parent_win.config.mono_path
		font_data: parent_win.config.font_data
		mono_data: parent_win.config.mono_data
		font_size: parent_win.config.font_size
		mono_size: parent_win.config.mono_size
		ui_scale:  parent_win.ctx.ui_scale
	}) or { return }

	mut lbl := label_wrap(msg)
	lbl.align = .center
	lbl.valign = .middle

	mut btn_yes := button('Delete')
	btn_yes.style = .danger
	mut btn_no := button('Cancel')

	btn_yes.on_click = fn [mut state] () {
		state.delete_confirmed = true
	}

	btn_no.on_click = fn [mut state] () {
		state.delete_pending = false
	}

	mut btn_row := create_hbox_fill()
	btn_row.set_spacing(10)
	btn_row.set_padding(0)
	btn_row.add(create_spacer(), flex: 1)
	btn_row.add(btn_yes)
	btn_row.add(btn_no)

	mut main := create_vbox_fill()
	main.set_spacing(8)
	main.set_padding(16)
	main.add(lbl)
	main.add(btn_row)

	confirm_dlg.add_widget(main)
	app.add_dialog(confirm_dlg)
	confirm_dlg.show()

	for app.running && confirm_dlg.is_open() && state.delete_pending && !state.delete_confirmed {
		app.process_events()
		app.render_all()
		if state.delete_confirmed || !state.delete_pending {
			confirm_dlg.close_with_result(if state.delete_confirmed { 1 } else { 0 })
			break
		}
		C.SDL_Delay(16)
	}

	// Single-use dialog: free its SDL window/renderer and drop from app.dialogs.
	app.remove_dialog(confirm_dlg)
	confirm_dlg.win.cleanup()

	if state.delete_confirmed && state.delete_path.len > 0 {
		del_path := state.delete_path
		if os.is_dir(del_path) {
			os.rmdir_all(del_path) or {}
		} else {
			os.rm(del_path) or {}
		}
		state.selected_path = os.dir(del_path)
		fd_rebuild_tree(mut state)
	}

	state.delete_pending = false
	state.delete_confirmed = false
	state.delete_path = ''
}

// ─── Delete without confirmation (Shift+Del) ───────────

fn fd_delete_no_confirm(mut state FdState) {
	if state.selected_path.len == 0 {
		return
	}
	if !os.exists(state.selected_path) {
		return
	}
	base := os.base(state.selected_path)
	if base.len == 0 || base == '/' || fd_is_root(state.selected_path) {
		return
	}

	del_path := state.selected_path
	if os.is_dir(del_path) {
		os.rmdir_all(del_path) or {}
	} else {
		os.rm(del_path) or {}
	}
	state.selected_path = os.dir(del_path)
	fd_rebuild_tree(mut state)
}

// ─── Build dialog ──────────────────────────────────────

fn fd_build(mut state FdState, parent &Window, mut app App) &Dialog {
	title := if state.mode == .open {
		tr('fd.title.open')
	} else if state.mode == .save {
		tr('fd.title.save')
	} else {
		tr('fd.title.folder')
	}

	dlg_w := 720
	dlg_h := 560

	pfont := if parent.config.font_size < 14 { 14 } else { parent.config.font_size }
	pmono := if parent.config.mono_size < 13 { 13 } else { parent.config.mono_size }

	mut dlg := create_dialog(DialogConfig{
		title:     title
		width:     dlg_w
		height:    dlg_h
		parent:    unsafe { parent }
		theme:     parent.ctx.theme
		font_path: parent.config.font_path
		mono_path: parent.config.mono_path
		font_data: parent.config.font_data
		mono_data: parent.config.mono_data
		font_size: pfont
		mono_size: pmono
		ui_scale:  parent.ctx.ui_scale
	}) or { return unsafe { &Dialog(nil) } }

	state.dlg_ptr = dlg
	state.app_ptr = unsafe { &app }

	// ── Hotkeys ──
	dlg.win.bind_hotkey('F2', fn [mut state] () {
		if state.rename_active {
			return
		}
		fd_start_rename(mut state)
	})

	dlg.win.bind_hotkey('Delete', fn [mut state] () {
		if state.rename_active {
			return
		}
		if unsafe { state.dlg_ptr == nil } || unsafe { state.app_ptr == nil } {
			return
		}
		fd_delete_selected(mut state, &state.dlg_ptr.win, mut state.app_ptr)
	})

	dlg.win.bind_hotkey('Shift+Delete', fn [mut state] () {
		if state.rename_active {
			return
		}
		fd_delete_no_confirm(mut state)
	})

	mut tv := tree_view()
	tv.editable = false
	tv.show_lines = true
	tv.line_solid = true
	tv.item_height = 26
	tv.indent = 20
	tv.pad = 6
	state.tree_view = tv

	roots := fd_build_roots(state)
	for r in roots {
		tv.add_root(r)
	}

	// ── Context menu ──
	mut ctx_menu := context_menu()

	mut mi_new_folder := menu_action(tr('fd.ctx.new_folder'))
	mut mi_rename := menu_action(tr('fd.ctx.rename'))
	mi_rename.shortcut = 'F2'
	mut mi_delete := menu_action(tr('fd.ctx.delete'))
	mi_delete.shortcut = 'Del'
	mut mi_delete_noconfirm := menu_action(tr('fd.ctx.delete_force'))
	mi_delete_noconfirm.shortcut = 'Shift+Del'

	mut sort_sub := menu_submenu(tr('fd.ctx.sort'))
	mut mi_sort_name_asc := menu_action('Name A→Z')
	mut mi_sort_name_desc := menu_action('Name Z→A')
	mut mi_sort_ext := menu_action(tr('fd.sort.type'))
	mut mi_sort_size_asc := menu_action(tr('fd.sort.size_asc'))
	mut mi_sort_size_desc := menu_action(tr('fd.sort.size_desc'))
	sort_sub.add(mi_sort_name_asc)
	sort_sub.add(mi_sort_name_desc)
	sort_sub.add(mi_sort_ext)
	sort_sub.add(mi_sort_size_asc)
	sort_sub.add(mi_sort_size_desc)

	mut mi_hidden := menu_action(tr('fd.ctx.show_hidden'))

	ctx_menu.add(mi_new_folder)
	ctx_menu.add(menu_separator())
	ctx_menu.add(mi_rename)
	ctx_menu.add(mi_delete)
	ctx_menu.add(mi_delete_noconfirm)
	ctx_menu.add(menu_separator())
	ctx_menu.add(sort_sub)
	ctx_menu.add(menu_separator())
	ctx_menu.add(mi_hidden)

	mi_new_folder.on_click = fn [mut state] () {
		fd_create_folder(mut state)
	}

	mi_rename.on_click = fn [mut state] () {
		if state.rename_active {
			fd_cancel_rename(mut state)
		} else {
			fd_start_rename(mut state)
		}
	}

	mi_delete.on_click = fn [mut state] () {
		if unsafe { state.dlg_ptr != nil } && unsafe { state.app_ptr != nil } {
			fd_delete_selected(mut state, &state.dlg_ptr.win, mut state.app_ptr)
		}
	}

	mi_delete_noconfirm.on_click = fn [mut state] () {
		fd_delete_no_confirm(mut state)
	}

	mi_sort_name_asc.on_click = fn [mut state] () {
		state.sort_mode = .name_asc
		fd_rebuild_tree(mut state)
	}
	mi_sort_name_desc.on_click = fn [mut state] () {
		state.sort_mode = .name_desc
		fd_rebuild_tree(mut state)
	}
	mi_sort_ext.on_click = fn [mut state] () {
		state.sort_mode = .ext_asc
		fd_rebuild_tree(mut state)
	}
	mi_sort_size_asc.on_click = fn [mut state] () {
		state.sort_mode = .size_asc
		fd_rebuild_tree(mut state)
	}
	mi_sort_size_desc.on_click = fn [mut state] () {
		state.sort_mode = .size_desc
		fd_rebuild_tree(mut state)
	}

	mi_hidden.on_click = fn [mut state] () {
		state.show_hidden = !state.show_hidden
		fd_rebuild_tree(mut state)
	}

	ctx_menu.attach(tv)
	dlg.win.add_widget(ctx_menu)

	ok_text := if state.mode == .save { tr('fd.btn.save') } else { tr('fd.btn.select') }

	mut btn_ok := button(ok_text)
	btn_ok.style = .accent
	mut btn_cancel := button(tr('fd.btn.cancel'))

	// ── TreeView callbacks ──

	tv.on_expand = fn [mut state] (node &TreeNode, expanded bool) {
		if expanded && fd_is_dir(node) {
			fd_populate(node, state)
		}
	}

	tv.on_dbl_click = fn [mut state] (node &TreeNode) {
		if state.rename_active {
			return
		}
		if fd_is_file(node) && state.mode != .folder {
			state.result_path = fd_node_path(node)
			state.confirmed = true
		}
	}

	tv.on_select = fn [mut state] (node &TreeNode) {
		if state.rename_active {
			p := fd_node_path(node)
			if p != state.rename_path {
				fd_cancel_rename(mut state)
			}
		}
		p := fd_node_path(node)
		state.selected_path = p
		if fd_is_dir(node) {
			state.start_dir = p
		} else if fd_is_file(node) {
			state.start_dir = os.dir(p)
		}
	}

	tv.on_edit_commit = fn [mut state] (node &TreeNode, old_text string, new_text string) {
		if state.rename_active {
			fd_finish_rename(mut state, old_text, new_text)
		}
	}

	tv.on_edit_cancel = fn [mut state] (node &TreeNode) {
		if state.rename_active {
			state.rename_active = false
			state.rename_path = ''
			if unsafe { state.tree_view != nil } {
				state.tree_view.editable = false
			}
		}
	}

	btn_ok.on_click = fn [mut state] () {
		if unsafe { state.tree_view == nil } {
			return
		}
		sel := state.tree_view.get_selected()
		if unsafe { sel == nil } {
			return
		}
		if state.mode == .folder {
			if fd_is_dir(sel) {
				state.result_path = fd_node_path(sel)
				state.confirmed = true
			}
			return
		}
		if fd_is_file(sel) {
			state.result_path = fd_node_path(sel)
			state.confirmed = true
		} else if fd_is_dir(sel) && state.mode == .save && state.default_name.len > 0 {
			state.result_path = os.join_path(fd_node_path(sel), state.default_name)
			state.confirmed = true
		}
	}

	btn_cancel.on_click = fn [mut state] () {
		state.result_path = ''
		state.confirmed = true
	}

	// ── Layout ──

	mut btn_row := create_hbox_fill()
	btn_row.set_spacing(10)
	btn_row.set_padding(8)
	btn_row.add(create_spacer(), flex: 1)
	btn_row.add(btn_ok)
	btn_row.add(btn_cancel)

	mut main := create_vbox_fill()
	main.set_spacing(4)
	main.set_padding(10)
	main.add(tv, flex: 1)
	main.add(hseparator())
	main.add(btn_row)

	dlg.add_widget(main)
	app.add_dialog(dlg)

	return dlg
}

pub fn file_dialog(parent &Window, mut app App, cfg FileDialogConfig) string {
	return fd_run(parent, mut app, cfg)
}

pub fn open_file_dialog(parent &Window, mut app App, cfg FileDialogConfig) string {
	return fd_run(parent, mut app, FileDialogConfig{ ...cfg, mode: .open })
}

pub fn save_file_dialog(parent &Window, mut app App, cfg FileDialogConfig) string {
	return fd_run(parent, mut app, FileDialogConfig{ ...cfg, mode: .save })
}

pub fn select_folder_dialog(parent &Window, mut app App, cfg FileDialogConfig) string {
	return fd_run(parent, mut app, FileDialogConfig{ ...cfg, mode: .folder })
}

fn fd_run(parent &Window, mut app App, cfg FileDialogConfig) string {
	start := if cfg.start_dir.len > 0 && os.is_dir(cfg.start_dir) {
		os.real_path(cfg.start_dir)
	} else {
		os.getwd()
	}

	mut state := &FdState{
		mode:          cfg.mode
		default_name:  cfg.default_name
		start_dir:     start
		selected_path: start
	}

	mut dlg := fd_build(mut state, parent, mut app)
	if unsafe { dlg == nil } {
		return ''
	}

	dlg.show()

	if unsafe { state.tree_view != nil } {
		dlg.win.ctx.focus.focus_tree_view(state.tree_view, 0)
		state.tree_view.focused = true
		dlg.win.render()
		fd_expand_to_dir(mut state.tree_view, start, state)
		fd_center_selected(mut state.tree_view, &dlg.win.ctx)
		sel := state.tree_view.get_selected()
		if unsafe { sel != nil } {
			state.selected_path = fd_node_path(sel)
		}
	}

	for app.running && dlg.is_open() && !state.confirmed {
		app.process_events()

		if state.pending_refocus && unsafe { state.tree_view != nil } {
			state.pending_refocus = false
			dlg.win.ctx.focus.focus_tree_view(state.tree_view, 0)
			state.tree_view.focused = true
			dlg.win.render()
			fd_center_selected(mut state.tree_view, &dlg.win.ctx)
		}

		if state.pending_rename && unsafe { state.tree_view != nil } {
			fd_do_pending_rename(mut state)
		}

		app.render_all()

		if state.confirmed {
			dlg.close_with_result(if state.result_path.len > 0 { 1 } else { 0 })
			break
		}
		C.SDL_Delay(16)
	}

	// Single-use dialog: free its SDL window/renderer and drop from app.dialogs.
	app.remove_dialog(dlg)
	dlg.win.cleanup()

	if !state.confirmed {
		return ''
	}
	return state.result_path
}
