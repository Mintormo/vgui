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
//
// Два экземпляра HotkeyManager: Window.hotkeys (sdl3_window.v) и App.hotkeys
// (sdl3_app.v); публичный доступ - через bind_hotkey/unbind_hotkey/
// set_hotkey_enabled/clear_hotkeys у Window и App. Цепочку приоритетов
// реализует обработка событий окна (sdl3_window.v): сначала оверлей и
// виджеты, затем w.hotkeys.try_match, затем app.hotkeys.try_match. Разбор
// строки сочетания и сравнение с событием - общие с меню
// (menu_shortcut_matches), поэтому формат строк один и тот же.

// HotkeyEntry - одна привязка: строка сочетания в исходном виде (как её
// передал пользователь), обработчик и флаг включённости. Поля неизменяемые,
// поэтому set_enabled пересоздаёт запись целиком.
struct HotkeyEntry {
	shortcut string
	handler  fn () = unsafe { nil }
	enabled  bool
}

// HotkeyManager - таблица горячих клавиш одного уровня (окно или приложение).
// Записи проверяются по порядку добавления; срабатывает первая подходящая.
pub struct HotkeyManager {
mut:
	entries []HotkeyEntry
}

// ─── Public API ────────────────────────────────────────

// Register a hotkey. `shortcut` uses the same format as
// menu shortcuts: "Ctrl+S", "Ctrl+Shift+Z", "F5", "Alt+Q".
pub fn (mut hm HotkeyManager) bind(shortcut string, handler fn ()) {
	// Remove existing binding for same shortcut (rebind)
	// Сравнение строк - только без учёта регистра и крайних пробелов.
	// Семантически одинаковые, но по-разному записанные сочетания
	// ("Shift+Ctrl+S" и "Ctrl+Shift+S") здесь считаются разными привязками.
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
// Смотрит только key_down; выключенные записи пропускаются. Вызывается
// окном лишь для событий, которые не поглотили оверлей и виджеты.
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
