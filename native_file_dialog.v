module vgui

import os

// Native OS file dialogs via SDL3's SDL_ShowOpenFileDialog /
// SDL_ShowSaveFileDialog / SDL_ShowOpenFolderDialog (SDL >= 3.2).
//
// SDL's dialog API is asynchronous — it spawns the OS dialog and calls the
// supplied C callback later, from the event loop, when the user finishes.
// To keep vgui's public API synchronous, we register a pending request keyed
// by a monotonic id, hand that id to SDL as `userdata`, and then pump the app
// event loop until the callback marks the request done.
//
// Это единственные файловые диалоги vgui: собственный виджетный диалог
// (file_dialog.v) удалён 13.10.2026 - нативный выглядит привычно для ОС и не
// требует поддержки.

// FileDialogMode - что выбирает диалог: .open - существующий файл, .save - путь
// для сохранения (файл может не существовать), .folder - каталог.
pub enum FileDialogMode {
	open
	save
	folder
}

// ─── Pending-request registry ──────────────────────────

// NativeFdRequest — состояние одного ожидающего запроса к нативному диалогу.
// Заполняется колбэком SDL (native_fd_trampoline), читается циклом ожидания.
// done — пользователь закончил (выбрал или отменил), paths — выбранные пути
// (пусто при отмене/ошибке). Индекс выбранного фильтра, который сообщает SDL, не
// хранится: наружу native_fd_run отдаёт только пути.
struct NativeFdRequest {
mut:
	done  bool
	paths []string
}

// Monotonic ids — never reused (same ABA-defence rationale as the Python
// callback registry in vguipy/_lib.py). A late callback for a request that already
// timed out / was abandoned simply finds nothing and is dropped.
__global (
	g_native_fd_requests map[u64]&NativeFdRequest
	g_native_fd_counter  u64
)

// native_fd_register выдаёт новый id (монотонный счётчик) и кладёт свежий запрос в реестр. id уходит в SDL как userdata.
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

// native_fd_trampoline — C-колбэк для SDL_Show*Dialog. Находит запрос по id из
// userdata (нет в реестре — молча выходит: запрос уже снят), копирует пути из
// C-массива в []string (массив оканчивается nil) и ставит done; номер фильтра
// (третий аргумент) не нужен. SDL зовёт его из цикла событий, т.е. из того же главного потока
// в момент process_events() в native_fd_wait.
fn native_fd_trampoline(userdata voidptr, filelist &&char, _ int) {
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
	r.done = true
}

// ─── Filter conversion ─────────────────────────────────
//
// Filters arrive from the capi layer as two parallel C-string arrays
// (names[], patterns[]) of length n. SDL keeps the SDL_DialogFileFilter
// pointers only for the lifetime of the call, but the strings they point at
// must outlive the *async* dialog. We clone them into stable V strings held
// for the duration of the wait loop.

// NativeFilterSet — владелец данных для массива SDL_DialogFileFilter. Хранит
// V-копии строк (names/patterns), C-указатели на них (cnames/cpatterns) и
// собранные структуры фильтров. Должен жить, пока идёт ожидание диалога.
struct NativeFilterSet {
mut:
	names     []string
	patterns  []string
	cnames    []&char
	cpatterns []&char
	filters   []C.SDL_DialogFileFilter
}

// build_filter_set собирает NativeFilterSet из двух параллельных списков (имя,
// шаблон вроде 'png;jpg'). Если длины различаются, берётся меньшая. Строки
// клонируются: SDL хранит указатели на них, пока диалог открыт.
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

// native_fd_wait крутит цикл событий приложения, пока колбэк не поставит done
// (или пока приложение не закрылось), и затем удаляет запрос из реестра. Поздний
// колбэк после этого ничего не найдёт и будет проигнорирован. Окна при этом
// продолжают перерисовываться (render_all), шаг ~16 мс (C.SDL_Delay(16)).
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

// NativeFileDialogConfig — параметры нативного диалога. mode выбирает
// open/save/folder; allow_many — множественный выбор (open, folder); start_dir —
// стартовая папка; default_name — имя файла по умолчанию (только save);
// filter_names/filter_patterns — параллельные списки фильтров.
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
// native_fd_run — общая точка входа: показывает нативный диалог режима cfg.mode,
// блокирует вызывающий код (но не перерисовку) до закрытия диалога и возвращает
// список выбранных путей (пусто при отмене или ошибке). parent — родительское окно
// (может быть nil — тогда диалог без родителя). Стартовое расположение: для save
// с default_name — start_dir/default_name, иначе просто start_dir.
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

// native_open_files_dialog — диалог открытия с множественным выбором; пусто при отмене.
pub fn native_open_files_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) []string {
	return native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .open, allow_many: true })
}

// native_save_file_dialog — диалог сохранения; возвращает выбранный путь или '' при отмене.
pub fn native_save_file_dialog(parent &Window, mut app App, cfg NativeFileDialogConfig) string {
	paths := native_fd_run(parent, mut app, NativeFileDialogConfig{ ...cfg, mode: .save, allow_many: false })
	return if paths.len > 0 { paths[0] } else { '' }
}

// native_select_folder_dialog — выбор папки; возвращает путь или '' при отмене.
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

// MessageBoxKind — важность сообщения; определяет букву и цвет значка в message_box.
pub enum MessageBoxKind {
	info
	warning
	error
}

// MessageBoxConfig — параметры message_box: заголовок, текст, вид, подписи кнопок
// (по умолчанию одна 'OK'), default_button — кнопка с акцентным стилем, которую
// нажимает Enter (-1 — нет), cancel_button — индекс, возвращаемый по Escape (-1 — нет).
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

// MsgBoxState — общий между message_box и обработчиками кнопок результат: индекс нажатой кнопки и признак, что ответ получен. Куча нужна, потому что на него ссылаются замыкания.
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

	// Диалог создаётся с темой, шрифтами и масштабом родителя, чтобы выглядеть как часть родительского окна.
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

	// state общий для обработчиков кнопок и Escape; цикл ниже ждёт state.answered.
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
	// Enter - кнопка по умолчанию. Раньше default_button только красил кнопку, и Enter
	// ничего не делал. Горячая клавиша окна срабатывает после виджетов, поэтому Enter
	// на кнопке в фокусе по-прежнему нажимает именно её.
	if cfg.default_button >= 0 && cfg.default_button < labels.len {
		default_idx := cfg.default_button
		dlg.win.bind_hotkey('Return', fn [mut state, default_idx] () {
			state.result = default_idx
			state.answered = true
		})
	}

	app.add_dialog(dlg)
	dlg.show()

	// Модальное ожидание: диалог — обычное окно vgui, поэтому цикл событий и рендер продолжают работать.
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
