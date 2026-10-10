module vgui

// ═══════════════════════════════════════════════════════
// HotkeyManager — global and per-window keyboard shortcuts
//
// Priority chain (highest to lowest):
//   1. Overlay (open menu/combo popup)
//   2. Focused widget (TextInput eats Ctrl+C etc.)
//   3. Window hotkeys
//   4. App (global) hotkeys
//
// Shortcut format — same as menu: "Ctrl+Shift+S", "F5",
// "Alt+F4", "Ctrl+Z" etc. Case-insensitive.
//
// If a shortcut string matches a menu item shortcut,
// the menu item fires first (widgets dispatch before
// hotkey manager). Hotkeys only fire for unhandled keys.
// ═══════════════════════════════════════════════════════

struct HotkeyEntry {
	shortcut string
	handler  fn () = unsafe { nil }
	enabled  bool
}

pub struct HotkeyManager {
mut:
	entries []HotkeyEntry
}

// ─── Public API ────────────────────────────────────────

// Register a hotkey. `shortcut` uses the same format as
// menu shortcuts: "Ctrl+S", "Ctrl+Shift+Z", "F5", "Alt+Q".
pub fn (mut hm HotkeyManager) bind(shortcut string, handler fn ()) {
	// Remove existing binding for same shortcut (rebind)
	normalized := shortcut.to_lower().trim_space()
	for i := hm.entries.len - 1; i >= 0; i-- {
		if hm.entries[i].shortcut.to_lower().trim_space() == normalized {
			hm.entries.delete(i)
		}
	}
	hm.entries << HotkeyEntry{
		shortcut: shortcut
		handler:  handler
		enabled:  true
	}
}

// Remove a hotkey binding by shortcut string
pub fn (mut hm HotkeyManager) unbind(shortcut string) {
	normalized := shortcut.to_lower().trim_space()
	for i := hm.entries.len - 1; i >= 0; i-- {
		if hm.entries[i].shortcut.to_lower().trim_space() == normalized {
			hm.entries.delete(i)
		}
	}
}

// Enable/disable a hotkey without removing it
pub fn (mut hm HotkeyManager) set_enabled(shortcut string, enabled bool) {
	normalized := shortcut.to_lower().trim_space()
	for i in 0 .. hm.entries.len {
		if hm.entries[i].shortcut.to_lower().trim_space() == normalized {
			hm.entries[i] = HotkeyEntry{
				shortcut: hm.entries[i].shortcut
				handler:  hm.entries[i].handler
				enabled:  enabled
			}
		}
	}
}

// Remove all bindings
pub fn (mut hm HotkeyManager) clear() {
	hm.entries.clear()
}

// Try to match event against registered hotkeys.
// Returns true if a hotkey was fired.
fn (hm &HotkeyManager) try_match(event &GuiEvent) bool {
	if event.typ != .key_down {
		return false
	}
	for entry in hm.entries {
		if !entry.enabled {
			continue
		}
		if menu_shortcut_matches(entry.shortcut, event) {
			entry.handler()
			return true
		}
	}
	return false
}
