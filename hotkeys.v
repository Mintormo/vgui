module vgui

// ═══════════════════════════════════════════════════════
// HotkeyManager — global and per-window keyboard shortcuts
//
// Priority chain (highest to lowest):
//   0. Event filters (App, then Window - add_event_filter)
//   1. Overlay (open menu/combo popup)
//   2. Focused widget (TextInput eats Ctrl+C etc.); while a text widget has
//      focus, printable keys without Ctrl/Alt stop here (ShortcutOverride,
//      event_route.v) - neither menus nor hotkeys see them
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

// EventFilter — фильтр событий окна или приложения (add_event_filter): true -
// событие поглощено, дальше (виджетам, меню, горячим клавишам) оно не идёт.
pub type EventFilter = fn (ev &GuiEvent) bool

// HotkeyEntry - одна привязка: строка сочетания в исходном виде (как её
// передал пользователь), обработчик и флаг включённости. Поля неизменяемые,
// поэтому set_enabled пересоздаёт запись целиком.
struct HotkeyEntry {
	shortcut string
	handler  fn () = unsafe { nil }
	enabled  bool
	// on_release — у привязки удержания (bind_hold): отпускание клавиши.
	// nil - обычная горячая клавиша.
	on_release fn () = unsafe { nil }
}

// HeldKey — удерживаемая сейчас клавиша привязки bind_hold: её отпускание
// (scancode - ключ в HotkeyManager.held).
struct HeldKey {
	on_release fn () = unsafe { nil }
}

// HotkeyManager - таблица горячих клавиш одного уровня (окно или приложение).
// Записи проверяются по порядку добавления; срабатывает первая подходящая.
pub struct HotkeyManager {
mut:
	entries []HotkeyEntry
	// held — клавиши привязок удержания, нажатые и ещё не отпущенные, по
	// scancode (место клавиши: отпускание приходит с тем же scancode, а
	// keycode мог смениться вместе с раскладкой)
	held map[int]HeldKey
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

// bind_hold — привязка удержания: on_press при нажатии, on_release при
// отпускании той же клавиши («показать исходник, пока держишь»). Повторы
// клавиши при удержании (GuiEvent.repeat) on_press не зовут; потеря фокуса
// окном отпускает все удержания (release_all) - иначе отпускание в другом
// окне не пришло бы и удержание «зависло». Как и bind, срабатывает только для
// клавиши, которую не забрали виджеты.
pub fn (mut hm HotkeyManager) bind_hold(shortcut string, on_press fn (), on_release fn ()) {
	hm.bind(shortcut, on_press)
	last := hm.entries.len - 1
	hm.entries[last] = HotkeyEntry{
		...hm.entries[last]
		on_release: on_release
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
				...hm.entries[i]
				enabled: enabled
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
fn (mut hm HotkeyManager) try_match(event &GuiEvent) bool {
	if event.typ != .key_down {
		return false
	}
	for entry in hm.entries {
		if !entry.enabled {
			continue
		}
		if menu_shortcut_matches(entry.shortcut, event) {
			if entry.on_release != unsafe { nil } {
				// удержание: повтор той же клавиши - уже нажата, только поглотить
				if event.scancode in hm.held {
					return true
				}
				hm.held[event.scancode] = HeldKey{
					on_release: entry.on_release
				}
			}
			entry.handler()
			return true
		}
	}
	return false
}

// try_release — отпускание клавиши привязки удержания: её on_release. Окно
// зовёт для каждого key_up, даже поглощённого виджетом, - удержание не
// должно зависнуть. true - это было отпускание удержания.
fn (mut hm HotkeyManager) try_release(event &GuiEvent) bool {
	if event.typ != .key_up {
		return false
	}
	held := hm.held[event.scancode] or { return false }
	hm.held.delete(event.scancode)
	held.on_release()
	return true
}

// release_all — отпустить все удержания (окно потеряло фокус: отпускание
// придёт уже другому окну).
fn (mut hm HotkeyManager) release_all() {
	if hm.held.len == 0 {
		return
	}
	held := hm.held.clone()
	hm.held.clear()
	for _, h in held {
		h.on_release()
	}
}
