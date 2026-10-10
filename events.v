module vgui

pub enum EventType {
	none_
	quit
	key_down
	key_up
	text_input
	mouse_down
	mouse_up
	mouse_move
	mouse_wheel
	mouse_dbl_click
	window_resize
	window_close
	window_minimized
	window_maximized
	window_restored
	window_focus_gained
	window_focus_lost
	drop_begin
	drop_file
	drop_text
	drop_position
	drop_complete
}

pub enum MouseButton {
	left
	middle
	right
	none_
}

pub struct GuiEvent {
pub mut:
	typ       EventType
	window_id u32
	keycode   int
	scancode  int
	mod_keys  u16
	text      string
	mouse_x   f32
	mouse_y   f32
	mouse_dx  f32
	mouse_dy  f32
	mouse_btn MouseButton
	// Маска зажатых кнопок мыши на момент события (SDL_MouseMotionEvent.state).
	// Заполняется только для mouse_move: в отличие от mouse_btn, который
	// говорит, какая кнопка была нажата/отпущена ИМЕННО ЭТИМ событием, здесь
	// видно, тянут ли что-то мышью прямо сейчас. Нужна точечной инвалидации
	// hover (sdl3_window.v, invalidate_hover_change): во время перетаскивания
	// (слайдер, сплиттер, выделение текста, панорама Canvas) виджет меняет
	// вид, даже когда курсор ушёл далеко за его пределы, поэтому такой кадр
	// обязан остаться полным.
	mouse_buttons u32
	clicks        int
	wheel_x       f32
	wheel_y       f32
	win_w         int
	win_h         int
	timestamp     u64
}

pub fn (e &GuiEvent) ctrl() bool {
	return (e.mod_keys & sdl_kmod_ctrl) != 0
}

// rctrl reports whether specifically the RIGHT Ctrl key is held (as opposed to
// ctrl(), which is true for either Ctrl key). Lets a tool reserve right-Ctrl
// gestures (e.g. brush-size wheel) without colliding with the conventional
// left-Ctrl shortcuts (zoom, etc).
pub fn (e &GuiEvent) rctrl() bool {
	return (e.mod_keys & sdl_kmod_rctrl) != 0
}

pub fn (e &GuiEvent) shift() bool {
	return (e.mod_keys & sdl_kmod_shift) != 0
}

pub fn (e &GuiEvent) alt() bool {
	return (e.mod_keys & sdl_kmod_alt) != 0
}

// Extract SDL window_id from raw event.
// SDL3: window events each have their own type, so we match by type range.
pub fn get_event_window_id(raw &C.SDL_Event) u32 {
	etype := unsafe { raw.@type }
	match etype {
		sdl_keydown, sdl_keyup {
			kb := unsafe { &C.SDL_KeyboardEvent(raw) }
			return kb.windowID
		}
		sdl_textinput {
			ti := unsafe { &C.SDL_TextInputEvent(raw) }
			return ti.windowID
		}
		sdl_mousemotion {
			mm := unsafe { &C.SDL_MouseMotionEvent(raw) }
			return mm.windowID
		}
		sdl_mousebuttondown, sdl_mousebuttonup {
			mb := unsafe { &C.SDL_MouseButtonEvent(raw) }
			return mb.windowID
		}
		sdl_mousewheel {
			mw := unsafe { &C.SDL_MouseWheelEvent(raw) }
			return mw.windowID
		}
		// SDL3 window events (0x202..0x21F range) all use SDL_WindowEvent layout
		sdl_event_window_shown, sdl_event_window_hidden, sdl_event_window_exposed,
		sdl_event_window_resized, sdl_event_window_pixel_size_changed, sdl_event_window_minimized,
		sdl_event_window_maximized, sdl_event_window_restored, sdl_event_window_focus_gained,
		sdl_event_window_focus_lost, sdl_event_window_close_requested {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			return we.windowID
		}
		sdl_event_drop_file, sdl_event_drop_text, sdl_event_drop_begin, sdl_event_drop_complete,
		sdl_event_drop_position {
			de := unsafe { &C.SDL_DropEvent(raw) }
			return de.windowID
		}
		else {
			return 0
		}
	}
}

pub fn parse_sdl_event(raw &C.SDL_Event) GuiEvent {
	mut ev := GuiEvent{}
	ev.window_id = get_event_window_id(raw)

	etype := unsafe { raw.@type }

	match etype {
		sdl_quit_event {
			ev.typ = .quit
		}
		sdl_keydown {
			kb := unsafe { &C.SDL_KeyboardEvent(raw) }
			ev.typ = .key_down
			ev.keycode = kb.key
			ev.scancode = kb.scancode
			ev.mod_keys = C.SDL_GetModState()
			ev.timestamp = kb.timestamp
		}
		sdl_keyup {
			kb := unsafe { &C.SDL_KeyboardEvent(raw) }
			ev.typ = .key_up
			ev.keycode = kb.key
			ev.scancode = kb.scancode
			ev.mod_keys = C.SDL_GetModState()
			ev.timestamp = kb.timestamp
		}
		sdl_textinput {
			ti := unsafe { &C.SDL_TextInputEvent(raw) }
			ev.typ = .text_input
			// SDL3: text is a pointer (not fixed array)
			if unsafe { ti.text != nil } {
				ev.text = unsafe { cstring_to_vstring(ti.text) }
			}
			ev.timestamp = ti.timestamp
		}
		sdl_mousemotion {
			mm := unsafe { &C.SDL_MouseMotionEvent(raw) }
			ev.typ = .mouse_move
			ev.mouse_x = mm.x
			ev.mouse_y = mm.y
			ev.mouse_dx = mm.xrel
			ev.mouse_dy = mm.yrel
			ev.mouse_buttons = mm.state
			ev.mod_keys = C.SDL_GetModState()
			ev.timestamp = mm.timestamp
		}
		sdl_mousebuttondown {
			mb := unsafe { &C.SDL_MouseButtonEvent(raw) }
			ev.typ = if mb.clicks >= u8(2) {
				EventType.mouse_dbl_click
			} else {
				EventType.mouse_down
			}
			ev.mouse_x = mb.x
			ev.mouse_y = mb.y
			ev.mod_keys = C.SDL_GetModState()
			ev.mouse_btn = match mb.button {
				sdl_button_left { MouseButton.left }
				sdl_button_middle { MouseButton.middle }
				sdl_button_right { MouseButton.right }
				else { MouseButton.none_ }
			}

			ev.clicks = int(mb.clicks)
			ev.timestamp = mb.timestamp
		}
		sdl_mousebuttonup {
			mb := unsafe { &C.SDL_MouseButtonEvent(raw) }
			ev.typ = .mouse_up
			ev.mouse_x = mb.x
			ev.mouse_y = mb.y
			ev.mod_keys = C.SDL_GetModState()
			ev.mouse_btn = match mb.button {
				sdl_button_left { MouseButton.left }
				sdl_button_middle { MouseButton.middle }
				sdl_button_right { MouseButton.right }
				else { MouseButton.none_ }
			}

			ev.timestamp = mb.timestamp
		}
		sdl_mousewheel {
			mw := unsafe { &C.SDL_MouseWheelEvent(raw) }
			ev.typ = .mouse_wheel
			ev.wheel_x = mw.x
			ev.wheel_y = mw.y
			ev.mod_keys = C.SDL_GetModState()
			ev.timestamp = mw.timestamp
		}
		// SDL3: window events are each separate event types
		sdl_event_window_resized {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_resize
			ev.win_w = we.data1
			ev.win_h = we.data2
			ev.timestamp = we.timestamp
		}
		sdl_event_window_pixel_size_changed {
			ev.typ = .none_
		}
		sdl_event_window_exposed {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_resize
			ev.win_w = 0
			ev.win_h = 0
			ev.timestamp = we.timestamp
		}
		sdl_event_window_close_requested {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_close
			ev.timestamp = we.timestamp
		}
		sdl_event_window_minimized {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_minimized
			ev.timestamp = we.timestamp
		}
		sdl_event_window_maximized {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_maximized
			ev.timestamp = we.timestamp
		}
		sdl_event_window_restored {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_restored
			ev.timestamp = we.timestamp
		}
		sdl_event_window_focus_gained {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_focus_gained
			ev.timestamp = we.timestamp
		}
		sdl_event_window_focus_lost {
			we := unsafe { &C.SDL_WindowEvent(raw) }
			ev.typ = .window_focus_lost
			ev.timestamp = we.timestamp
		}
		// SDL3 drag-and-drop. x/y are window-relative (logical pixels),
		// same space as mouse coords, so reuse mouse_x/mouse_y. The file
		// path (DROP_FILE) or text (DROP_TEXT) goes into ev.text.
		sdl_event_drop_begin {
			de := unsafe { &C.SDL_DropEvent(raw) }
			ev.typ = .drop_begin
			ev.mouse_x = de.x
			ev.mouse_y = de.y
			ev.timestamp = de.timestamp
		}
		sdl_event_drop_file {
			de := unsafe { &C.SDL_DropEvent(raw) }
			ev.typ = .drop_file
			ev.mouse_x = de.x
			ev.mouse_y = de.y
			if unsafe { de.data != nil } {
				ev.text = unsafe { cstring_to_vstring(de.data) }
			}
			ev.timestamp = de.timestamp
		}
		sdl_event_drop_text {
			de := unsafe { &C.SDL_DropEvent(raw) }
			ev.typ = .drop_text
			ev.mouse_x = de.x
			ev.mouse_y = de.y
			if unsafe { de.data != nil } {
				ev.text = unsafe { cstring_to_vstring(de.data) }
			}
			ev.timestamp = de.timestamp
		}
		sdl_event_drop_position {
			de := unsafe { &C.SDL_DropEvent(raw) }
			ev.typ = .drop_position
			ev.mouse_x = de.x
			ev.mouse_y = de.y
			ev.timestamp = de.timestamp
		}
		sdl_event_drop_complete {
			de := unsafe { &C.SDL_DropEvent(raw) }
			ev.typ = .drop_complete
			ev.mouse_x = de.x
			ev.mouse_y = de.y
			ev.timestamp = de.timestamp
		}
		else {}
	}

	return ev
}
