module vgui

// ═══════════════════════════════════════════════════════
// System tray — cross-platform via SDL3's SDL_Tray API.
//
// A Tray is NOT a Widget: it has no bounds and is never drawn
// by the vgui render pipeline. It is an OS-level object owned
// by the application. SDL handles the platform specifics
// (StatusItem on macOS, AppIndicator/StatusNotifier on Linux,
// Shell_NotifyIcon on Windows).
//
// SDL_UpdateTrays() must be pumped from the event loop (see
// sdl3_app.v); on some platforms the menu will not refresh
// otherwise.
// ═══════════════════════════════════════════════════════

// TrayEntry wraps a single SDL_TrayEntry. We pass &TrayEntry as the SDL
// userdata pointer, so the native trampoline can recover the handler and
// whether the entry is a checkbox.
//
// The API is closure-based at its core: an entry carries a plain V `on_click`
// / `on_toggle`. The Python layer doesn't get a second set of methods — its
// capi bridge (vgui-capi/vgui_capi.v) builds a closure that forwards to the Python
// dispatcher and feeds it through the very same on_item/on_checkbox path.
pub struct TrayEntry {
pub mut:
	handle      voidptr // SDL_TrayEntry*
	is_checkbox bool
	submenu     voidptr // SDL_TrayMenu* if this entry opens a submenu
	// SDL's DBus tray backend stores the label POINTER without copying
	// (entry_dbus->item->utf8 = label). The string must outlive the entry,
	// so we own a stable copy here for its whole lifetime. Same hazard as
	// the font-data lifetime issue documented in PROJECT.md.
	label string
	// The handler. Exactly one is set depending on entry kind.
	on_click  fn ()     = unsafe { nil }
	on_toggle fn (bool) = unsafe { nil }
}

pub struct Tray {
pub mut:
	handle   voidptr      // SDL_Tray*
	menu     voidptr      // SDL_TrayMenu* (root)
	entries  []&TrayEntry // owned, kept alive for process lifetime
	submenus []voidptr    // SDL_TrayMenu* of created submenus
}

// The native trampoline SDL invokes for every entry. It runs on the
// SDL event-pump thread (the same thread that calls SDL_UpdateTrays),
// so dispatching straight into the Python callback registry is safe.
// Set whenever a tray entry fires, so the event loop knows to re-render even
// though tray clicks (delivered via DBus) generate no SDL event. Without this,
// a callback that does win.show() leaves the window shown by SDL but never
// painted by vgui — it appears blank or stays invisible.
__global g_tray_activity = false

fn tray_entry_trampoline(userdata voidptr, entry voidptr) {
	if userdata == unsafe { nil } {
		return
	}
	g_tray_activity = true
	te := unsafe { &TrayEntry(userdata) }
	if te.is_checkbox {
		if te.on_toggle != unsafe { nil } {
			te.on_toggle(C.SDL_GetTrayEntryChecked(entry))
		}
	} else {
		if te.on_click != unsafe { nil } {
			te.on_click()
		}
	}
}

// create_tray builds the OS tray icon. `icon` may be a surface loaded
// from a file path or raw bytes (or nil — some platforms then show a
// blank/default icon). The root menu is created immediately.
pub fn create_tray(icon voidptr, tooltip string) &Tray {
	t := C.SDL_CreateTray(icon, tooltip.str)
	if t == unsafe { nil } {
		return &Tray{}
	}
	menu := C.SDL_CreateTrayMenu(t)
	return &Tray{
		handle: t
		menu:   menu
	}
}

// create_tray_embedded builds the OS tray icon from raw image bytes (PNG/etc),
// e.g. a file embedded into the binary with `$embed_file`. SDL decodes the
// bytes into its own surface immediately, so this frees the temporary surface
// before returning — the icon survives without keeping the source bytes alive.
//
// Typical use:
//   icon := $embed_file('assets/tray.png')
//   mut tray := vgui.create_tray_embedded(icon.to_bytes(), 'My App')
pub fn create_tray_embedded(data []u8, tooltip string) &Tray {
	surf := load_tray_icon_data(data)
	t := create_tray(surf, tooltip)
	if surf != unsafe { nil } {
		C.SDL_DestroySurface(surf)
	}
	return t
}

pub fn (mut t Tray) set_tooltip(tooltip string) {
	if t.handle == unsafe { nil } {
		return
	}
	C.SDL_SetTrayTooltip(t.handle, tooltip.str)
}

pub fn (mut t Tray) set_icon(icon voidptr) {
	if t.handle == unsafe { nil } {
		return
	}
	C.SDL_SetTrayIcon(t.handle, icon)
}

// set_icon_data replaces the tray icon from raw image bytes (e.g. an embedded
// PNG). SDL copies the surface, so the temporary one is freed right after.
pub fn (mut t Tray) set_icon_data(data []u8) {
	if t.handle == unsafe { nil } {
		return
	}
	surf := load_tray_icon_data(data)
	C.SDL_SetTrayIcon(t.handle, surf)
	if surf != unsafe { nil } {
		C.SDL_DestroySurface(surf)
	}
}

fn (mut t Tray) target_menu(menu voidptr) voidptr {
	if menu == unsafe { nil } {
		return t.menu
	}
	return menu
}

// add_entry is the single insertion path for every clickable/checkbox entry.
// It owns a stable copy of the label (SDL's DBus backend keeps the pointer),
// stores the handler, registers the trampoline, and keeps the entry alive in
// Tray.entries for the process lifetime.
// entry - a heap entry; parameter is not `mut te &TrayEntry`: the new V compiler
// passes the pointer without `&` to a method expecting `TrayEntry**` (crash,
// vlang/v#28864).
fn (mut t Tray) add_entry(menu voidptr, label string, flags u32, entry &TrayEntry) &TrayEntry {
	mut te := unsafe { entry }
	target := t.target_menu(menu)
	if target == unsafe { nil } {
		return te
	}
	te.label = label.clone()
	t.entries << te
	// pos -1 → append at the end
	handle := C.SDL_InsertTrayEntryAt(target, -1, te.label.str, flags)
	te.handle = handle
	C.SDL_SetTrayEntryCallback(handle, voidptr(tray_entry_trampoline), voidptr(te))
	return te
}

// on_item adds a clickable button whose handler is a plain V closure.
pub fn (mut t Tray) on_item(menu voidptr, label string, handler fn ()) &TrayEntry {
	te := &TrayEntry{
		on_click: handler
	}
	return t.add_entry(menu, label, sdl_trayentry_button, te)
}

// on_checkbox adds a checkbox whose handler is a plain V closure receiving the
// new checked state.
pub fn (mut t Tray) on_checkbox(menu voidptr, label string, checked bool, handler fn (bool)) &TrayEntry {
	mut flags := sdl_trayentry_checkbox
	if checked {
		flags |= sdl_trayentry_checked
	}
	te := &TrayEntry{
		is_checkbox: true
		on_toggle:   handler
	}
	return t.add_entry(menu, label, flags, te)
}

// add_separator inserts a divider. SDL renders an entry with a nil/empty
// label as a separator.
pub fn (mut t Tray) add_separator(menu voidptr) {
	target := t.target_menu(menu)
	if target == unsafe { nil } {
		return
	}
	C.SDL_InsertTrayEntryAt(target, -1, &char(unsafe { nil }), sdl_trayentry_button)
}

// add_submenu inserts a submenu-bearing entry and returns its SDL_TrayMenu*,
// which callers pass back as the `menu` argument of add_item/add_checkbox.
pub fn (mut t Tray) add_submenu(menu voidptr, label string) voidptr {
	target := t.target_menu(menu)
	if target == unsafe { nil } {
		return unsafe { nil }
	}
	mut te := &TrayEntry{
		label: label.clone()
	}
	t.entries << te
	entry := C.SDL_InsertTrayEntryAt(target, -1, te.label.str, sdl_trayentry_submenu)
	te.handle = entry
	sub := C.SDL_CreateTraySubmenu(entry)
	te.submenu = sub
	t.submenus << sub
	return sub
}

pub fn (mut t Tray) destroy() {
	if t.handle == unsafe { nil } {
		return
	}
	C.SDL_DestroyTray(t.handle)
	t.handle = unsafe { nil }
	t.menu = unsafe { nil }
}

// load_tray_icon loads an icon surface from a file path. Caller owns the
// surface and must keep it alive while the tray uses it, then free it.
pub fn load_tray_icon(path string) voidptr {
	if path == '' {
		return unsafe { nil }
	}
	return C.IMG_Load(path.str)
}

// load_tray_icon_data loads an icon surface from raw image bytes (PNG/etc).
// The bytes only need to live for the duration of this call — SDL decodes
// into its own surface.
pub fn load_tray_icon_data(data []u8) voidptr {
	if data.len == 0 {
		return unsafe { nil }
	}
	io := C.SDL_IOFromConstMem(data.data, usize(data.len))
	if io == unsafe { nil } {
		return unsafe { nil }
	}
	// closeio = true → SDL_IOStream is closed automatically after load
	return C.IMG_Load_IO(io, true)
}
