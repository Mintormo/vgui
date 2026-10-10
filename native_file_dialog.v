module vgui

import os

// Native OS file dialogs via SDL3's SDL_ShowOpenFileDialog /
// SDL_ShowSaveFileDialog / SDL_ShowOpenFolderDialog (SDL >= 3.2).
//
// SDL's dialog API is asynchronous — it spawns the OS dialog and calls the
// supplied C callback later, from the event loop, when the user finishes.
// To keep vgui's public API synchronous (matching the custom file_dialog),
// we register a pending request keyed by a monotonic id, hand that id to SDL
// as `userdata`, and then pump the app event loop until the callback marks
// the request done. Same shape as fd_run's wait loop.

// ─── Pending-request registry ──────────────────────────

struct NativeFdRequest {
mut:
	done   bool
	paths  []string
	filter int = -1
}

// Monotonic ids — never reused (same ABA-defence rationale as the Python
// callback registry in vguipy/_lib.py). A late callback for a request that already
// timed out / was abandoned simply finds nothing and is dropped.
__global (
	g_native_fd_requests map[u64]&NativeFdRequest
	g_native_fd_counter  u64
)

fn native_fd_register() (u64, &NativeFdRequest) {
	g_native_fd_counter++
	id := g_native_fd_counter
	req := &NativeFdRequest{}
	g_native_fd_requests[id] = req
	return id, req
}

// ─── C-ABI trampoline ──────────────────────────────────
//
// SDL calls: void callback(void *userdata, const char * const *filelist, int filter)
// `filelist` is a null-terminated array of C strings; nil on error, or an
// array whose first element is nil when the user cancelled.

fn native_fd_trampoline(userdata voidptr, filelist &&char, filter int) {
	id := u64(usize(userdata))
	req := g_native_fd_requests[id] or { return }
	mut r := unsafe { req }
	if unsafe { filelist != nil } {
		mut i := 0
		for {
			p := unsafe { filelist[i] }
			if unsafe { p == nil } {
				break
			}
			r.paths << unsafe { cstring_to_vstring(p) }
			i++
		}
	}
	r.filter = filter
	r.done = true
}

// ─── Filter conversion ─────────────────────────────────
//
// Filters arrive from the capi layer as two parallel C-string arrays
// (names[], patterns[]) of length n. SDL keeps the SDL_DialogFileFilter
// pointers only for the lifetime of the call, but the strings they point at
// must outlive the *async* dialog. We clone them into stable V strings held
// for the duration of the wait loop.

struct NativeFilterSet {
mut:
	names     []string
	patterns  []string
	cnames    []&char
	cpatterns []&char
	filters   []C.SDL_DialogFileFilter
}

fn build_filter_set(names []string, patterns []string) NativeFilterSet {
	mut fs := NativeFilterSet{}
	n := if names.len < patterns.len { names.len } else { patterns.len }
	for i in 0 .. n {
		fs.names << names[i].clone()
		fs.patterns << patterns[i].clone()
	}
	for i in 0 .. fs.names.len {
		fs.cnames << &char(fs.names[i].str)
		fs.cpatterns << &char(fs.patterns[i].str)
	}
	for i in 0 .. fs.names.len {
		fs.filters << C.SDL_DialogFileFilter{
			name:    fs.cnames[i]
			pattern: fs.cpatterns[i]
		}
	}
	return fs
}

// ─── Wait loop ─────────────────────────────────────────

fn native_fd_wait(mut app App, id u64, req &NativeFdRequest) {
	for app.running && !req.done {
		app.process_events()
		app.render_all()
		if req.done {
			break
		}
		C.SDL_Delay(16)
	}
	g_native_fd_requests.delete(id)
}

// ─── Public config ─────────────────────────────────────

@[params]
pub struct NativeFileDialogConfig {
pub mut:
	title           string // unused by SDL (OS provides), kept for API parity
	start_dir       string
	default_name    string
	mode            FileDialogMode = .open
	allow_many      bool
	filter_names    []string
	filter_patterns []string
}

// Returns the chosen paths. Empty slice on cancel/error.
pub fn native_fd_run(parent &Window, mut app App, cfg NativeFileDialogConfig) []string {
	mut win_ptr := voidptr(unsafe { nil })
	if unsafe { parent != nil } {
		win_ptr = parent.sdl_window
	}

	mut default_loc := ''
	if cfg.mode == .save && cfg.default_name.len > 0 {
		base := if cfg.start_dir.len > 0 { cfg.start_dir } else { '' }
		default_loc = if base.len > 0 {
			os.join_path(base, cfg.default_name)
		} else {
			cfg.default_name
		}
	} else if cfg.start_dir.len > 0 {
		default_loc = cfg.start_dir
	}

	id, req := native_fd_register()
	userdata := voidptr(usize(id))

	fs := build_filter_set(cfg.filter_names, cfg.filter_patterns)
	filters_ptr := if fs.filters.len > 0 {
		unsafe { &fs.filters[0] }
	} else {
		&C.SDL_DialogFileFilter(unsafe { nil })
	}

	loc_cstr := if default_loc.len > 0 { default_loc.str } else { &u8(unsafe { nil }) }

	match cfg.mode {
		.open {
			C.SDL_ShowOpenFileDialog(native_fd_trampoline, userdata, win_ptr,
				filters_ptr, fs.filters.len, &char(loc_cstr), cfg.allow_many)
		}
		.save {
			C.SDL_ShowSaveFileDialog(native_fd_trampoline, userdata, win_ptr,
				filters_ptr, fs.filters.len, &char(loc_cstr))
		}
		.folder {
			C.SDL_ShowOpenFolderDialog(native_fd_trampoline, userdata, win_ptr,
				&char(loc_cstr), cfg.allow_many)
		}
	}

	native_fd_wait(mut app, id, req)
	return req.paths.clone()
}

// ─── Public V API ──────────────────────────────────────

// native_open_file_dialog shows the OS open-file dialog and returns the
// chosen path (empty on cancel). For multi-select use native_open_files_dialog.
pub fn native_open_file_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) string {
	paths := native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .open, allow_many: false })
	return if paths.len > 0 { paths[0] } else { '' }
}

pub fn native_open_files_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) []string {
	return native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .open, allow_many: true })
}

pub fn native_save_file_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) string {
	paths := native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .save, allow_many: false })
	return if paths.len > 0 { paths[0] } else { '' }
}

pub fn native_select_folder_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) string {
	paths := native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .folder, allow_many: false })
	return if paths.len > 0 { paths[0] } else { '' }
}

// ─── Custom message box (modal Dialog) ─────────────────
//
// Built on vgui's own Dialog rather than SDL_ShowMessageBox: the native
// SDL message box blocks the thread until dismissed, so our parent window
// stops repainting and leaves black damage artifacts when the box is
// dragged over it. A Dialog is a normal vgui window that keeps rendering
// in the wait loop, so it composites cleanly.

pub enum MessageBoxKind {
	info
	warning
	error
}

@[params]
pub struct MessageBoxConfig {
pub mut:
	title          string
	message        string
	kind           MessageBoxKind = .info
	buttons        []string       = ['OK']
	default_button int            = -1 // index of Return-default button; -1 = none
	cancel_button  int            = -1 // index of Escape-default button; -1 = none
}

@[heap]
struct MsgBoxState {
mut:
	result   int = -1
	answered bool
}

// Shows a modal message box. Returns the index of the clicked button, or
// -1 if closed without a button (window close / Escape with no cancel
// button defined).
pub fn message_box(parent &Window, mut app App, cfg MessageBoxConfig) int {
	if unsafe { parent == nil } {
		return -1
	}

	mut labels := cfg.buttons.clone()
	if labels.len == 0 {
		labels << 'OK'
	}

	// Accent colour for the icon glyph by severity.
	icon_glyph, icon_color := match cfg.kind {
		.info { 'i', Color{90, 160, 240, 255} }
		.warning { '!', Color{235, 175, 60, 255} }
		.error { 'x', Color{225, 90, 90, 255} }
	}

	mut dlg := create_dialog(DialogConfig{
		title:     cfg.title
		parent:    unsafe { parent }
		theme:     parent.ctx.theme
		font_path: parent.config.font_path
		mono_path: parent.config.mono_path
		font_data: parent.config.font_data
		mono_data: parent.config.mono_data
		font_size: parent.config.font_size
		mono_size: parent.config.mono_size
		ui_scale:  parent.ctx.ui_scale
	}) or { return -1 }

	mut state := &MsgBoxState{}

	// ── Icon + message row ──
	mut icon_lbl := label(icon_glyph)
	icon_lbl.align = .center
	icon_lbl.valign = .middle
	icon_lbl.font_size = 28
	icon_lbl.color = icon_color

	mut msg_lbl := label_wrap(cfg.message)
	msg_lbl.valign = .middle

	mut msg_row := create_hbox_fill()
	msg_row.set_spacing(12)
	msg_row.set_padding(0)
	msg_row.add(icon_lbl)
	msg_row.add(msg_lbl, flex: 1)

	// ── Button row ──
	mut btn_row := create_hbox_fill()
	btn_row.set_spacing(10)
	btn_row.set_padding(0)
	btn_row.add(create_spacer(), flex: 1)

	for i in 0 .. labels.len {
		mut b := button(labels[i])
		if i == cfg.default_button {
			b.style = .accent
		}
		idx := i
		b.on_click = fn [mut state, idx] () {
			state.result = idx
			state.answered = true
		}
		btn_row.add(b)
	}

	mut main := create_vbox_fill()
	main.set_spacing(12)
	main.set_padding(16)
	main.add(msg_row, flex: 1)
	main.add(btn_row)

	dlg.add_widget(main)

	// Escape closes with the cancel button's index (or -1 if none).
	cancel_idx := cfg.cancel_button
	dlg.win.bind_hotkey('Escape', fn [mut state, cancel_idx] () {
		state.result = cancel_idx
		state.answered = true
	})

	app.add_dialog(dlg)
	dlg.show()

	for app.running && dlg.is_open() && !state.answered {
		app.process_events()
		app.render_all()
		if state.answered {
			break
		}
		C.SDL_Delay(16)
	}

	if dlg.is_open() {
		dlg.close_with_result(if state.result >= 0 { 1 } else { 0 })
	}

	// The dialog is single-use: release its SDL window/renderer now and drop
	// it from app.dialogs, otherwise every message_box leaks a hidden window.
	app.remove_dialog(dlg)
	dlg.win.cleanup()

	return state.result
}
