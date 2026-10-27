module vgui

// ═══════════════════════════════════════════════════════
// Application — main loop, manages multiple SDL3 windows
// ═══════════════════════════════════════════════════════

// Файл sdl3_app.v: объект приложения App и главный цикл. App владеет списками окон (Window),
// диалогов (Dialog) и трей-иконок, менеджером горячих клавиш, очередью post() для замыканий из
// фоновых потоков. Здесь же: инициализация SDL/SDL_ttf (create_app), разбор событий SDL и маршрутизация
// их по окнам с учётом модальных диалогов (process_events), перерисовка всех окон (render_all),
// порядок завершения (cleanup). Цикл однопоточный: всё, кроме post(), вызывается только из главного
// потока (PROJECT.md, «Контракт потоков»). Окно/диалог получают события через
// Window.dispatch_event_with_app (sdl3_window.v); модальность - modal_scope.v; рендер - sdl3_render.v.

// Настройки приложения. font_path/bold_path/... - пути к файлам шрифтов, font_data/... - те же
// шрифты байтами (используются, если заданы; см. sdl3_fonts.v). font_size/mono_size - базовые
// размеры обычного и моноширинного шрифтов, theme - тема по умолчанию для окон без своей.
@[params]
pub struct AppConfig {
pub mut:
	font_path        string
	bold_path        string
	italic_path      string
	bold_italic_path string
	mono_path        string
	mono_bold_path   string
	font_data        []u8
	bold_data        []u8
	italic_data      []u8
	bold_italic_data []u8
	mono_data        []u8
	mono_bold_data   []u8
	font_size        int   = 14
	mono_size        int   = 13
	theme            Theme = light_theme()
	// target_fps - потолок частоты кадров, пока идёт анимация (run() выдерживает бюджет
	// кадра 1000 / target_fps мс). Без анимации кадры рисуются только по событиям.
	// Значения вне 1..1000 зажимаются (frame_budget_ms).
	target_fps int = 60
}

// Минимальный интерфейс любого виджета: нарисоваться и обработать событие (true - событие
// поглощено). Остальные возможности (раскладка, hit-test, измерение) - отдельные интерфейсы в
// widget_tree.v / layout_measure.v.
pub interface Widget {
mut:
	draw(mut ctx RenderContext)
	handle_event(event &GuiEvent, app &App) bool
}

// Posted wraps a closure for the app.post() channel. A struct on purpose:
// `chan fn ()` (even via a type alias) miscompiles in V — pushing into such
// a channel segfaults (checked up to V 0.5.1 075cb03, 2026-07-06);
// channels of structs work.
struct Posted {
	f fn () = unsafe { nil }
}

// Приложение. Один экземпляр на процесс. active_ctx - контекст окна, чьё событие обрабатывается
// прямо сейчас (nil вне обработки); виджеты берут его через get_active_ctx() для расчёта
// геометрии в handle_event. cleaned защищает cleanup() от повторного вызова.
pub struct App {
pub mut:
	config     AppConfig
	windows    []&Window
	dialogs    []&Dialog
	running    bool
	active_ctx &RenderContext = unsafe { nil }
	hotkeys    HotkeyManager
	cleaned    bool
	// Таблица стилей приложения (css_apply.v; nil - нет) и слежение за её
	// файлом: css_path непуст при load_stylesheet(path, true).
	stylesheet     &Stylesheet = unsafe { nil }
	css_path       string
	css_mtime      i64
	css_next_check u64
	trays          []&Tray
	// When a tray is active the loop must keep running even with every
	// window hidden (hide-to-tray), so don't auto-quit on "no open windows".
	keep_alive bool
	// post(): closures queued from worker threads, drained on the main
	// thread each loop iteration. wake_event is a custom SDL event type
	// whose only job is to wake WaitEventTimeout immediately.
	posted     chan Posted
	wake_event u32
	// Идущие шкалы анимации приложения (timeline.v, app.play) и время их
	// прошлого шага по часам now_ms().
	timelines        []&Timeline
	timeline_last_ms u64
}

// Инициализирует SDL (видео + события) и SDL_ttf и возвращает приложение. Ошибка SDL_Init/TTF_Init
// возвращается как error с текстом SDL_GetError. Регистрирует пользовательский тип события
// wake_event (нужен только для пробуждения цикла из post()).
pub fn create_app(config AppConfig) !&App {
	// X11: SDL sets the UTF-8 window title (_NET_WM_NAME) only after the
	// title converts to the C locale's charset. Without setlocale that is
	// the "C" locale, and a title with e.g. Vietnamese letters fails the
	// conversion - SDL then leaves _NET_WM_NAME unset and the window
	// manager shows mojibake. Take the character set from the environment
	// (LC_CTYPE only: number formatting stays "C").
	$if linux {
		C.setlocale(C.LC_CTYPE, c'')
	}
	if !C.SDL_Init(sdl_init_video | sdl_init_events) {
		err_msg := unsafe { cstring_to_vstring(C.SDL_GetError()) }
		return error('SDL_Init failed: ${err_msg}')
	}

	if !C.TTF_Init() {
		err_msg := unsafe { cstring_to_vstring(C.SDL_GetError()) }
		return error('TTF_Init failed: ${err_msg}')
	}

	return &App{
		config:     config
		running:    true
		posted:     chan Posted{cap: 64}
		wake_event: C.SDL_RegisterEvents(1)
	}
}

// post schedules f to run on the main (App) thread, between event
// processing and rendering of the current loop iteration. This is the
// ONLY vgui call that is safe from other threads: the channel is
// thread-safe by definition and SDL_PushEvent is documented thread-safe,
// so the pushed wake event pulls the loop out of WaitEventTimeout at
// once. Inside f the whole vgui surface is available (it runs on the
// main thread); a render always follows, no needs_animation tricks
// needed. Capture data by value: f runs later, after the caller moved on.
// Closures posted after run() returned are never executed (they stay in
// the buffered channel); with cap 64 a post-quit post() does not block.
pub fn (mut app App) post(f fn ()) {
	app.posted <- Posted{
		f: f
	}
	mut ev := C.SDL_Event{}
	unsafe {
		ev.@type = app.wake_event
	}
	C.SDL_PushEvent(&ev)
}

// drain_posted runs every closure queued by post(); true if any ran.
fn (mut app App) drain_posted() bool {
	mut ran := false
	for {
		mut p := Posted{}
		if app.posted.try_pop(mut p) != .success {
			break
		}
		if !isnil(p.f) {
			p.f()
		}
		ran = true
	}
	return ran
}

// add_window регистрирует окно. Окно без явной темы (WindowConfig.theme
// не задан, set_theme не вызывался) получает тему приложения.
pub fn (mut app App) add_window(w &Window) {
	mut win := unsafe { w }
	if !win.theme_explicit {
		win.apply_theme(app.config.theme)
	}
	if !isnil(app.stylesheet) {
		win.follow_app_stylesheet(app.stylesheet)
	}
	app.windows << win
}

// add_dialog - как add_window: диалог без явной темы и без родителя
// получает тему приложения.
pub fn (mut app App) add_dialog(d &Dialog) {
	mut dlg := unsafe { d }
	if !dlg.win.theme_explicit {
		dlg.win.apply_theme(app.config.theme)
	}
	if !isnil(app.stylesheet) {
		dlg.win.follow_app_stylesheet(app.stylesheet)
	}
	app.dialogs << dlg
}

// set_theme меняет тему приложения: запоминает её для будущих окон и
// применяет ко всем окнам и диалогам, у которых нет своей (явной) темы.
pub fn (mut app App) set_theme(theme Theme) {
	app.config.theme = theme
	for mut w in app.windows {
		if !w.theme_explicit {
			w.apply_theme(theme)
		}
	}
	for mut d in app.dialogs {
		if !d.win.theme_explicit {
			d.win.apply_theme(theme)
		}
	}
}

// remove_dialog detaches a dialog from the app's dialog list (pointer
// identity, no-op if absent). It does NOT free SDL resources — callers that
// own a temporary dialog (message_box, file/color/date dialogs) call
// dlg.win.cleanup() themselves. Without this, every temporary dialog stayed
// in app.dialogs forever: a hidden SDL window + renderer per call, scanned
// by every loop iteration.
pub fn (mut app App) remove_dialog(d &Dialog) {
	target := voidptr(d)
	for i, dlg in app.dialogs {
		if voidptr(dlg) == target {
			app.dialogs.delete(i)
			return
		}
	}
}

// remove_window detaches a window from the app's window list (pointer
// identity, no-op if absent). Same rationale as remove_dialog.
pub fn (mut app App) remove_window(w &Window) {
	target := voidptr(w)
	for i, win in app.windows {
		if voidptr(win) == target {
			app.windows.delete(i)
			return
		}
	}
}

// add_tray registers a tray with the app so it is pumped each loop and
// destroyed at cleanup. Registering a tray also enables keep_alive, so the
// app survives hide-to-tray (all windows hidden) until app.quit().
pub fn (mut app App) add_tray(t &Tray) {
	app.trays << unsafe { t }
	app.keep_alive = true
}

// Явное включение/выключение keep_alive (приложение не завершается при отсутствии открытых окон).
pub fn (mut app App) set_keep_alive(v bool) {
	app.keep_alive = v
}

// Контекст окна, обрабатывающего событие сейчас; nil вне dispatch (проверять через unsafe).
pub fn (app &App) get_active_ctx() &RenderContext {
	return app.active_ctx
}

// invalidate_all_windows forces a full repaint of every open window/dialog on
// their NEXT render(). Used for state changes that trigger a render without
// going through dispatch_event_with_app (which invalidates itself) — namely
// app.post() closures and tray activity (see run()). PROJECT.md documents
// app.post() as guaranteeing a render follows; without this, that render
// could be a no-op partial frame if the closure changed a widget the dirty
// tracker doesn't know about.
pub fn (mut app App) invalidate_all_windows() {
	for mut w in app.windows {
		w.ctx.invalidate_all()
	}
	for mut d in app.dialogs {
		d.win.ctx.invalidate_all()
	}
}

// unregister_focus снимает виджет с фокус-учёта во ВСЕХ окнах и диалогах
// приложения. Вызывается из vgui_destroy до освобождения структуры.
//
// Почему по всем окнам, а не по «своему»: указателя на родителя у виджета нет
// намеренно (PROJECT.md, «Дерево виджетов»), поэтому от voidptr виджета до его
// FocusManager дойти нечем. Проход дешёвый — окон единицы, а сам unregister
// выходит по хеш-проверке, если виджет в этом окне не регистрировался.
pub fn (mut app App) unregister_focus(ptr voidptr) {
	for mut w in app.windows {
		w.ctx.focus.unregister(ptr)
	}
	for mut d in app.dialogs {
		d.win.ctx.focus.unregister(ptr)
	}
}

// pump_events выполняет ОДИН шаг цикла: обрабатывает накопившиеся SDL-события,
// выгребает замыкания из post() и прокачивает трей. Возвращает true, если
// что-то произошло и кадр нужно перерисовать.
//
// Это ровно та часть итерации run(), что предшествует render_all(). Вынесена
// отдельно, чтобы «свой» цикл событий (в том числе из Python, через
// vgui_app_process_events) вёл себя так же, а не терял post()-замыкания,
// клики по трею и инвалидацию после них.
pub fn (mut app App) pump_events() bool {
	had_events := app.process_events()

	// Closures from app.post() — always on the main thread, before
	// rendering, so they may touch widgets freely.
	posted := app.drain_posted()

	// Файл стилей изменился (load_stylesheet(path, true)) - перечитать.
	// set_stylesheet сам инвалидирует окна; true - нужен кадр. Цикл run()
	// просыпается минимум раз в 100 мс (SDL_WaitEventTimeout), так что
	// опрос идёт и в простое.
	restyled := app.poll_stylesheet()

	// Pump tray menus — required on some platforms (notably macOS)
	// for entry state changes to take effect. A tray click is delivered
	// here (via DBus on Linux) and fires its callback synchronously, but
	// generates no SDL event, so force a render if anything happened.
	mut tray_acted := false
	if app.trays.len > 0 {
		C.SDL_UpdateTrays()
		if g_tray_activity {
			g_tray_activity = false
			tray_acted = true
		}
	}

	// Neither path above goes through dispatch_event_with_app (there is
	// no GuiEvent), so neither invalidates on its own. Force a full
	// repaint so the guarantee ("a render always follows post()", tray
	// clicks) actually shows whatever the closure/callback changed,
	// instead of a partial frame with an empty dirty region doing
	// nothing visible.
	if posted || tray_acted {
		app.invalidate_all_windows()
	}

	// Подсказке пора показаться (tooltip_manager.v): событий не было, но кадр
	// нужен - его tip_frame и поставит подсказку на экран.
	tip_due := app.tooltip_wait_ms() == 0

	return had_events || posted || tray_acted || restyled || tip_due
}

// update_running гасит running, когда не осталось ни одного открытого окна.
// With a tray, the app stays alive even when all windows are hidden
// (hide-to-tray). Quitting is then explicit, via app.quit().
pub fn (mut app App) update_running() {
	if app.keep_alive {
		return
	}
	for w in app.windows {
		if w.open {
			return
		}
	}
	app.running = false
}

// frame_budget_ms - длительность кадра анимации в мс по AppConfig.target_fps (зажатому в
// 1..1000): 60 fps - 16 мс, как было до появления настройки.
fn frame_budget_ms(target_fps int) u64 {
	fps := if target_fps < 1 {
		1
	} else if target_fps > 1000 {
		1000
	} else {
		target_fps
	}
	return u64(1000 / fps)
}

// needs_animation_now — есть ли окно/диалог, просящее следующий кадр.
fn (app &App) needs_animation_now() bool {
	// Шкалы приложения (timeline.v) двигаются только в render_all - пока
	// они идут, кадры нужны, даже если ни один виджет не анимируется.
	if app.timelines.len > 0 {
		return true
	}
	// Данные моделей/Observable изменились (models.v) - нужен кадр.
	if g_data_changed {
		return true
	}
	for w in app.windows {
		if w.open && w.ctx.needs_animation {
			return true
		}
	}
	for d in app.dialogs {
		if d.is_open() && d.win.ctx.needs_animation {
			return true
		}
	}
	return false
}

// Главный цикл: первый кадр -> повторять { пауза до бюджета кадра при анимации -> pump_events() ->
// render_all(), если были события или идёт анимация -> update_running() } -> cleanup().
// Кадр рисуется только при необходимости; без анимации цикл спит в SDL_WaitEventTimeout
// (до 100 мс), так что простаивающее приложение почти не грузит процессор.
pub fn (mut app App) run() {
	app.render_all()

	mut last_render_ms := C.SDL_GetTicks()
	budget := frame_budget_ms(app.config.target_fps)

	for app.running {
		any_anim := app.needs_animation_now()

		// Потолок частоты кадров анимации: выждать остаток бюджета кадра (AppConfig.target_fps).
		if any_anim {
			now := C.SDL_GetTicks()
			elapsed := now - last_render_ms
			if elapsed < budget {
				C.SDL_Delay(u32(budget - elapsed))
			}
		}

		acted := app.pump_events()

		if acted || any_anim {
			app.render_all()
			last_render_ms = C.SDL_GetTicks()
		}

		app.update_running()
	}
	app.cleanup()
}

// modal_loop_step_ms - шаг собственного цикла модального диалога (~60 кадров/с).
const modal_loop_step_ms = u32(16)

// modal_loop_pause - пауза между итерациями собственного цикла модального
// диалога (DatePicker, ColorPicker: process_events + render_all в while).
// Без неё такой цикл мог бы крутиться вхолостую и грузить ядро: process_events
// возвращается, как только очередь пуста. Живёт здесь, в
// платформенном слое: виджеты не зовут SDL сами (PROJECT.md, «Бэкенд
// рисования: виджеты не зовут SDL напрямую»).
pub fn (app &App) modal_loop_pause() {
	C.SDL_Delay(modal_loop_step_ms)
}

// Забирает все накопившиеся события SDL и раздаёт их. Возвращает true, если хотя бы одно событие
// было получено (даже если оно ничего не изменило) и false, если за время ожидания событий нет.
// Приоритет маршрутизации для каждого события: (1) сброс render-target - полная перерисовка;
// (2) expose окна - немедленный render (без мерцания при ресайзе); (3) quit; (4) если есть
// открытый модальный диалог, блокирующий окно-адресат, - событие уходит диалогу (Esc и закрытие
// окна закрывают его с результатом 0), клики по заблокированным окнам лишь поднимают диалог;
// (5) обычный диалог; (6) обычное окно. Координаты мыши и размеры делятся на ui_scale
// окна/диалога: виджеты работают в логических, а SDL сообщает физические пиксели.
// Во время обработки active_ctx указывает на контекст окна-адресата. В конце проверяется
// двойной клик по заголовку безрамочных окон (развернуть/восстановить).
pub fn (mut app App) process_events() bool {
	// Первое событие берём блокирующим вызовом (ожидание/опрос), остальные - в цикле PollEvent.
	raw_event := C.SDL_Event{}

	needs_animation := app.needs_animation_now()

	// When animating, poll without waiting so VSync alone throttles the frame rate.
	// When idle, block for up to 100ms to avoid busy-looping.
	mut first := true
	if needs_animation {
		if !C.SDL_PollEvent(&raw_event) {
			return false
		}
	} else {
		// Спим до события, но не дольше 100 мс и не дольше, чем до срока
		// ближайшей подсказки (tooltip_manager.v): иначе она появлялась бы с
		// опозданием до 100 мс.
		mut timeout := i32(100)
		until_tip := app.tooltip_wait_ms()
		if until_tip >= 0 && until_tip < 100 {
			timeout = i32(until_tip)
		}
		if !C.SDL_WaitEventTimeout(&raw_event, timeout) {
			return false
		}
	}

	for {
		mut current_event := C.SDL_Event{}
		if first {
			current_event = raw_event
			first = false
		} else {
			if !C.SDL_PollEvent(&current_event) {
				break
			}
		}

		ev := parse_sdl_event(&current_event)

		// Fast path: handle expose immediately for flicker-free resize
		etype := unsafe { current_event.@type }
		// Render target content lost (Direct3D resets its device on resize,
		// device loss, driver update...): the persistent target `rt` is now
		// blank, and partial repaints would leave everything not dirty
		// empty - repaint every window in full.
		if etype == sdl_event_render_targets_reset || etype == sdl_event_render_device_reset {
			app.invalidate_all_windows()
			continue
		}
		// Для expose окно рисуется сразу же, а не в конце итерации: при изменении размера
		// иначе виден мерцающий/растянутый кадр.
		if etype == sdl_event_window_exposed {
			we := unsafe { &C.SDL_WindowEvent(&current_event) }
			for mut w in app.windows {
				if w.open && w.sdl_id == we.windowID {
					w.render()
					break
				}
			}
			for mut d in app.dialogs {
				if d.is_open() && d.win.sdl_id == we.windowID {
					d.win.render()
					break
				}
			}
		}

		match ev.typ {
			.quit {
				app.running = false
				return true
			}
			else {}
		}

		event_wid := get_event_window_id(&current_event)

		// Модальный диалог гасит события не всего приложения, а только
		// своего дерева владения — см. «Область модальности» в modal_scope.v.
		// Ищем диалог, блокирующий окно-адресат: modal_blocker_index по списку записей (id окна,
		// id родителя, флаг модальности) возвращает индекс блокирующего диалога или -1.
		mut modal_dialog := unsafe { &Dialog(nil) }
		mut has_modal := false
		for d in app.dialogs {
			if d.is_open() && d.modal {
				has_modal = true
				break
			}
		}
		if has_modal {
			mut entries := []ModalScopeEntry{cap: app.dialogs.len}
			for d in app.dialogs {
				entries << ModalScopeEntry{
					wid:       d.win.sdl_id
					parent_id: d.parent_id
					modal:     d.is_open() && d.modal
				}
			}
			idx := modal_blocker_index(entries, event_wid)
			if idx >= 0 {
				modal_dialog = unsafe { app.dialogs[idx] }
			}
		}

		if unsafe { modal_dialog != nil } {
			if event_wid == modal_dialog.win.sdl_id {
				if ev.typ == .window_close {
					modal_dialog.close_with_result(0)
					continue
				}
				if ev.typ == .key_down && ev.keycode == sdl_k_escape {
					modal_dialog.close_with_result(0)
					continue
				}

				// Копия события в логических координатах (делим на ui_scale диалога).
				mut dlg_ev := ev
				dlg_scale := modal_dialog.win.ctx.ui_scale
				if dlg_scale != 1.0 {
					dlg_ev.mouse_x = ev.mouse_x / dlg_scale
					dlg_ev.mouse_y = ev.mouse_y / dlg_scale
					if dlg_ev.typ == .window_resize {
						dlg_ev.win_w = int(f32(ev.win_w) / dlg_scale)
						dlg_ev.win_h = int(f32(ev.win_h) / dlg_scale)
					}
				}

				if dlg_ev.typ == .window_resize {
					if dlg_ev.win_w > 0 && dlg_ev.win_h > 0 {
						modal_dialog.win.ctx.screen_width = f32(dlg_ev.win_w)
						modal_dialog.win.ctx.screen_height = f32(dlg_ev.win_h)
					}
					modal_dialog.win.render()
				}

				if dlg_ev.typ == .mouse_move {
					modal_dialog.win.mouse_x = dlg_ev.mouse_x
					modal_dialog.win.mouse_y = dlg_ev.mouse_y
					modal_dialog.win.ctx.mouse_x = dlg_ev.mouse_x
					modal_dialog.win.ctx.mouse_y = dlg_ev.mouse_y
				}
				app.active_ctx = &modal_dialog.win.ctx
				modal_dialog.win.dispatch_event_with_app(&dlg_ev, &app)
				app.active_ctx = unsafe { nil }
			} else {
				if ev.typ == .mouse_down || ev.typ == .window_focus_gained {
					C.SDL_RaiseWindow(modal_dialog.win.sdl_window)
				}
			}
			continue
		}

		// Не модальный путь: событие диалогу, чьё окно является адресатом.
		mut routed := false
		for mut d in app.dialogs {
			if d.is_open() && event_wid == d.win.sdl_id {
				if ev.typ == .window_close {
					d.close_with_result(0)
					routed = true
					break
				}
				if ev.typ == .key_down && ev.keycode == sdl_k_escape {
					d.close_with_result(0)
					routed = true
					break
				}

				mut dlg_ev := ev
				ds := d.win.ctx.ui_scale
				if ds != 1.0 {
					dlg_ev.mouse_x = ev.mouse_x / ds
					dlg_ev.mouse_y = ev.mouse_y / ds
					if dlg_ev.typ == .window_resize {
						dlg_ev.win_w = int(f32(ev.win_w) / ds)
						dlg_ev.win_h = int(f32(ev.win_h) / ds)
					}
				}

				if dlg_ev.typ == .window_resize {
					if dlg_ev.win_w > 0 && dlg_ev.win_h > 0 {
						d.win.ctx.screen_width = f32(dlg_ev.win_w)
						d.win.ctx.screen_height = f32(dlg_ev.win_h)
					}
					d.win.render()
				}

				if dlg_ev.typ == .mouse_move {
					d.win.mouse_x = dlg_ev.mouse_x
					d.win.mouse_y = dlg_ev.mouse_y
					d.win.ctx.mouse_x = dlg_ev.mouse_x
					d.win.ctx.mouse_y = dlg_ev.mouse_y
				}
				app.active_ctx = &d.win.ctx
				d.win.dispatch_event_with_app(&dlg_ev, &app)
				app.active_ctx = unsafe { nil }
				routed = true
				break
			}
		}

		if routed {
			continue
		}

		// Обычные окна. Сначала служебная обработка (размер, мышь, перетаскивание безрамочного окна),
		// затем общая передача события виджетам через dispatch_event_with_app.
		for mut w in app.windows {
			if !w.open {
				continue
			}
			if event_wid == w.sdl_id {
				if ev.typ == .window_close {
					w.close()
					break
				}
				mut scaled_ev := ev
				if w.ctx.ui_scale != 1.0 {
					scaled_ev.mouse_x = ev.mouse_x / w.ctx.ui_scale
					scaled_ev.mouse_y = ev.mouse_y / w.ctx.ui_scale
					if scaled_ev.typ == .window_resize {
						scaled_ev.win_w = int(f32(ev.win_w) / w.ctx.ui_scale)
						scaled_ev.win_h = int(f32(ev.win_h) / w.ctx.ui_scale)
					}
				}

				match scaled_ev.typ {
					.window_resize {
						if scaled_ev.win_w > 0 && scaled_ev.win_h > 0 {
							w.ctx.screen_width = f32(scaled_ev.win_w)
							w.ctx.screen_height = f32(scaled_ev.win_h)
							w.config.width = scaled_ev.win_w
							w.config.height = scaled_ev.win_h
						}
						w.render()
					}
					.mouse_move {
						w.mouse_x = scaled_ev.mouse_x
						w.mouse_y = scaled_ev.mouse_y
						w.ctx.mouse_x = scaled_ev.mouse_x
						w.ctx.mouse_y = scaled_ev.mouse_y
						if w.hittest_data != unsafe { nil } {
							w.in_drag_zone = borderless_point_in_drag_rect(w, scaled_ev.mouse_x,
								scaled_ev.mouse_y)
							borderless_on_drag_move(w)
							borderless_update_cursor(w)
						}
					}
					.mouse_down {
						if w.hittest_data != unsafe { nil } && scaled_ev.mouse_btn == .left {
							if borderless_point_in_drag_rect(w, scaled_ev.mouse_x,
								scaled_ev.mouse_y)
							{
								borderless_on_drag_start(w)
							}
						}
					}
					.mouse_up {
						if w.hittest_data != unsafe { nil } && scaled_ev.mouse_btn == .left {
							borderless_on_mouse_up(w, scaled_ev.mouse_x, scaled_ev.mouse_y)
						}
					}
					else {}
				}

				app.handle_window_state_event(&current_event, mut w)
				app.active_ctx = &w.ctx
				w.dispatch_event_with_app(&scaled_ev, &app)
				app.active_ctx = unsafe { nil }
				break
			}
		}
	}

	for mut w in app.windows {
		if w.open && w.hittest_data != unsafe { nil } {
			if borderless_check_dbl_click(w) {
				flags := C.SDL_GetWindowFlags(w.sdl_window)
				is_max := (flags & sdl_window_maximized) != 0
				if is_max {
					w.restore()
				} else {
					w.maximize()
				}
			}
		}
	}

	return true
}

// Синхронизирует флаги окна (minimized/maximized/visible) и его размеры с событиями SDL
// свёрнуто / развёрнуто / восстановлено / показано / скрыто. При развороте и восстановлении
// читает реальный размер окна у SDL и переводит в логические единицы (делит на ui_scale).
fn (app &App) handle_window_state_event(raw &C.SDL_Event, mut w Window) {
	etype := unsafe { raw.@type }
	match etype {
		sdl_event_window_minimized {
			w.minimized = true
			w.maximized = false
		}
		sdl_event_window_maximized {
			w.maximized = true
			w.minimized = false
			mut ww := 0
			mut wh := 0
			C.SDL_GetWindowSize(w.sdl_window, &ww, &wh)
			w.apply_sdl_size(ww, wh)
		}
		sdl_event_window_restored {
			w.minimized = false
			w.maximized = false
			mut ww := 0
			mut wh := 0
			C.SDL_GetWindowSize(w.sdl_window, &ww, &wh)
			w.apply_sdl_size(ww, wh)
		}
		sdl_event_window_shown {
			w.visible = true
		}
		sdl_event_window_hidden {
			w.visible = false
		}
		else {}
	}
}

// render_all перерисовывает все окна и открытые диалоги. Публичная, потому что
// её зовёт «свой» цикл событий (Python: app.render_all()).
pub fn (mut app App) render_all() {
	// Recompute modal-backdrop flags from scratch each frame, so closing a
	// dialog automatically clears the parent window's dimming.
	for mut w in app.windows {
		w.has_modal_child = false
	}
	for mut d in app.dialogs {
		d.win.has_modal_child = false
	}
	for d in app.dialogs {
		if d.is_open() && d.modal && unsafe { d.parent != nil } {
			mut found := false
			for mut w in app.windows {
				if voidptr(w) == voidptr(d.parent) {
					w.has_modal_child = true
					found = true
					break
				}
			}
			// Родителем может быть и окно другого диалога (модальный
			// диалог поверх диалога) — затемнять надо и его.
			if !found {
				for mut pd in app.dialogs {
					if voidptr(&pd.win) == voidptr(d.parent) {
						pd.win.has_modal_child = true
						break
					}
				}
			}
		}
	}
	// Шкалы анимации приложения - до кадра: их колбэки меняют виджеты, и
	// кадр должен показать уже новые значения (step_timelines сам
	// инвалидирует окна).
	app.step_timelines()
	// Изменились данные моделей или Observable (models.v): они не знают своих
	// окон, поэтому перерисовываются все.
	if take_data_changed() {
		app.invalidate_all_windows()
	}
	for mut w in app.windows {
		w.render()
	}
	for mut d in app.dialogs {
		if d.is_open() {
			d.win.render()
		}
	}
}

// Освобождает всё в порядке: трей-иконки -> диалоги -> окна -> кэш шрифтов -> TTF_Quit ->
// SDL_Quit. Порядок важен: текстуры/рендереры окон должны быть уничтожены до выключения
// SDL, а шрифты - до TTF_Quit. Идемпотентна (флаг cleaned). run() зовёт её сам при выходе
// из цикла; при своём цикле её вызывает вызывающий код.
pub fn (mut app App) cleanup() {
	if app.cleaned {
		return
	}
	app.cleaned = true
	for mut t in app.trays {
		t.destroy()
	}
	for mut d in app.dialogs {
		d.win.cleanup()
	}
	for mut w in app.windows {
		w.cleanup()
	}
	destroy_font_cache()
	C.TTF_Quit()
	C.SDL_Quit()
}

// Просит цикл завершиться (running = false); окна закроются в cleanup().
pub fn (mut app App) quit() {
	app.running = false
}

// ─── Clipboard helpers via App ───

// Текст из буфера обмена или пустая строка. Память SDL освобождается здесь.
pub fn (app &App) get_clipboard() string {
	ptr := C.SDL_GetClipboardText()
	if ptr == unsafe { nil } {
		return ''
	}
	text := unsafe { cstring_to_vstring(ptr) }
	C.SDL_free(ptr)
	return text
}

pub fn (app &App) set_clipboard(text string) {
	C.SDL_SetClipboardText(text.str)
}

// ─── App-level hotkey convenience methods ─────────────────

// Делегаты к HotkeyManager (hotkeys.v): регистрация, снятие, включение/выключение и очистка
// горячих клавиш приложения. shortcut - строка вида из HotkeyManager.bind.
pub fn (mut app App) bind_hotkey(shortcut string, handler fn ()) {
	app.hotkeys.bind(shortcut, handler)
}

pub fn (mut app App) unbind_hotkey(shortcut string) {
	app.hotkeys.unbind(shortcut)
}

pub fn (mut app App) set_hotkey_enabled(shortcut string, enabled bool) {
	app.hotkeys.set_enabled(shortcut, enabled)
}

pub fn (mut app App) clear_hotkeys() {
	app.hotkeys.clear()
}
