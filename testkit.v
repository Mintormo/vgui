module vgui

import os

// ═══════════════════════════════════════════════════════
// testkit — инструменты для тестов интерфейса: синтетический ввод, снимок
// кадра, сравнение с эталонным PNG. Публичные: ими пользуются и тесты самой
// библиотеки (*_test.v), и приложения на vgui (через C-ABI - и Python).
// ═══════════════════════════════════════════════════════
//
// Ввод идёт НАСТОЯЩИМ путём: sim_* кладут SDL-события в очередь окна
// (SDL_PushEvent) и прогоняют app.process_events(), а затем кадр. Значит,
// работает всё, что работает у пользователя: parse_sdl_event, деление на
// ui_scale, область модальности, горячие клавиши, фокус, двойной клик.
// Прямой вызов handle_event/dispatch_event этого не проверяет.
//
// Координаты - логические (как bounds виджетов): sim_* сами умножают их на
// ui_scale окна. Модификаторы (sdl_kmod_*) выставляются глобально через
// SDL_SetModState на время разбора события - так их читает parse_sdl_event - и
// сбрасываются после.
//
// Кадр (Frame) читается из persistent render target окна (Window.rt) - ровно
// то, что показано на экране, - в физических пикселях, RGBA по байтам.
//
// Обычный тест:
//   mut t := new_test_ui(width: 200, height: 100)!
//   mut b := button('OK')
//   t.add(b)
//   t.click_widget(b)
//   t.match_snapshot('testdata/snapshots/ok_button.png')!
//   t.close()

// ─── Синтетический ввод (без TestUi: годится для любого App/Window) ───

fn C.SDL_SetModState(modstate u16)

// sim_pump разбирает очередь событий и рисует кадр - как одна итерация
// главного цикла. Модификаторы mods действуют на время разбора.
fn sim_pump(mut app App, mods u16) {
	C.SDL_SetModState(mods)
	app.process_events()
	C.SDL_SetModState(u16(0))
	app.render_all()
}

fn sim_scale(w &Window) f32 {
	return if w.ctx.ui_scale > 0 { w.ctx.ui_scale } else { f32(1) }
}

fn sim_push_motion(w &Window, x f32, y f32, buttons u32) {
	s := sim_scale(w)
	mut ev := C.SDL_Event{}
	mut me := unsafe { &C.SDL_MouseMotionEvent(&ev) }
	me.@type = sdl_mousemotion
	me.windowID = w.sdl_id
	me.state = buttons
	me.x = x * s
	me.y = y * s
	C.SDL_PushEvent(&ev)
}

fn sim_push_button(w &Window, down bool, x f32, y f32, btn MouseButton, clicks int) {
	s := sim_scale(w)
	mut ev := C.SDL_Event{}
	mut be := unsafe { &C.SDL_MouseButtonEvent(&ev) }
	be.@type = if down { sdl_mousebuttondown } else { sdl_mousebuttonup }
	be.windowID = w.sdl_id
	be.button = match btn {
		.right { sdl_button_right }
		.middle { sdl_button_middle }
		else { sdl_button_left }
	}
	be.down = down
	be.clicks = u8(clicks)
	be.x = x * s
	be.y = y * s
	C.SDL_PushEvent(&ev)
}

fn sim_button_mask(btn MouseButton) u32 {
	return match btn {
		.right { u32(1) << (sdl_button_right - 1) }
		.middle { u32(1) << (sdl_button_middle - 1) }
		else { u32(1) << (sdl_button_left - 1) }
	}
}

// sim_move - указатель в точку (x, y) окна w.
pub fn sim_move(mut app App, w &Window, x f32, y f32, mods u16) {
	sim_push_motion(w, x, y, 0)
	sim_pump(mut app, mods)
}

// sim_press / sim_release - нажать / отпустить кнопку мыши в точке (без
// предварительного движения). clicks - номер быстрого клика (1, 2 - двойной).
pub fn sim_press(mut app App, w &Window, x f32, y f32, btn MouseButton, clicks int, mods u16) {
	sim_push_button(w, true, x, y, btn, clicks)
	sim_pump(mut app, mods)
}

pub fn sim_release(mut app App, w &Window, x f32, y f32, btn MouseButton, mods u16) {
	sim_push_button(w, false, x, y, btn, 1)
	sim_pump(mut app, mods)
}

// sim_click - движение в точку, нажатие и отпускание (клик срабатывает по
// отпусканию у Button и подобных). clicks = 2 - второй клик двойного.
pub fn sim_click(mut app App, w &Window, x f32, y f32, btn MouseButton, clicks int, mods u16) {
	sim_push_motion(w, x, y, 0)
	sim_push_button(w, true, x, y, btn, clicks)
	sim_push_button(w, false, x, y, btn, clicks)
	sim_pump(mut app, mods)
}

// sim_drag - нажать в (x0, y0), провести за steps шагов (каждый - отдельный
// кадр) в (x1, y1) с зажатой кнопкой и отпустить.
pub fn sim_drag(mut app App, w &Window, x0 f32, y0 f32, x1 f32, y1 f32, steps int, btn MouseButton, mods u16) {
	sim_push_motion(w, x0, y0, 0)
	sim_push_button(w, true, x0, y0, btn, 1)
	sim_pump(mut app, mods)
	n := if steps < 1 { 1 } else { steps }
	for i in 1 .. n + 1 {
		k := f32(i) / f32(n)
		sim_push_motion(w, x0 + (x1 - x0) * k, y0 + (y1 - y0) * k, sim_button_mask(btn))
		sim_pump(mut app, mods)
	}
	sim_push_button(w, false, x1, y1, btn, 1)
	sim_pump(mut app, mods)
}

// sim_wheel - колесо в точке (x, y): указатель сначала переезжает туда (колесо
// адресуется по последней позиции мыши). dy > 0 - от себя (вверх).
pub fn sim_wheel(mut app App, w &Window, x f32, y f32, dx f32, dy f32, mods u16) {
	sim_push_motion(w, x, y, 0)
	mut ev := C.SDL_Event{}
	mut we := unsafe { &C.SDL_MouseWheelEvent(&ev) }
	we.@type = sdl_mousewheel
	we.windowID = w.sdl_id
	we.x = dx
	we.y = dy
	s := sim_scale(w)
	we.mouse_x = x * s
	we.mouse_y = y * s
	C.SDL_PushEvent(&ev)
	sim_pump(mut app, mods)
}

// sim_key - нажатие и отпускание клавиши keycode (sdl_k_*; для букв -
// код символа, например `a`) с модификаторами mods (sdl_kmod_*).
pub fn sim_key(mut app App, w &Window, keycode int, mods u16) {
	for down in [true, false] {
		mut ev := C.SDL_Event{}
		mut kb := unsafe { &C.SDL_KeyboardEvent(&ev) }
		kb.@type = if down { sdl_keydown } else { sdl_keyup }
		kb.windowID = w.sdl_id
		kb.key = keycode
		kb.down = down
		C.SDL_PushEvent(&ev)
	}
	sim_pump(mut app, mods)
}

// sim_text - ввод текста (событие SDL_EVENT_TEXT_INPUT), как от раскладки или
// IME. Текст получает виджет с фокусом.
pub fn sim_text(mut app App, w &Window, text string) {
	if text.len == 0 {
		return
	}
	// SDL хранит указатель, а не копию - строка живёт до конца функции,
	// а событие разбирается внутри sim_pump
	ctext := text.clone()
	mut ev := C.SDL_Event{}
	mut ti := unsafe { &C.SDL_TextInputEvent(&ev) }
	ti.@type = sdl_textinput
	ti.windowID = w.sdl_id
	ti.text = &char(ctext.str)
	C.SDL_PushEvent(&ev)
	sim_pump(mut app, 0)
}

// ─── Кадр ──────────────────────────────────────────────

// Frame - снимок кадра в физических пикселях: pixels - RGBA построчно
// (pitch байт на строку).
pub struct Frame {
pub:
	w      int
	h      int
	pitch  int
	pixels []u8
}

// FrameDiff - итог сравнения двух кадров: сколько пикселей отличаются больше
// допуска и наибольшая разница по каналу (0..255). Кадры разного размера -
// size_mismatch.
pub struct FrameDiff {
pub:
	count         int
	max_delta     int
	size_mismatch bool
}

// capture_frame читает показанный кадр окна (persistent render target).
// Пустой Frame (w == 0), если окно ещё ни разу не рисовалось.
pub fn capture_frame(mut w Window) Frame {
	if unsafe { w.renderer == nil || w.rt == nil } {
		return Frame{}
	}
	C.SDL_SetRenderTarget(w.renderer, w.rt)
	raw := C.SDL_RenderReadPixels(w.renderer, unsafe { nil })
	C.SDL_SetRenderTarget(w.renderer, unsafe { nil })
	return frame_from_surface(raw, true)
}

// frame_from_surface копирует поверхность в Frame (RGBA); free - освободить её.
fn frame_from_surface(surface voidptr, free bool) Frame {
	if unsafe { surface == nil } {
		return Frame{}
	}
	conv := C.SDL_ConvertSurface(surface, sdl_pixelformat_abgr8888)
	if free {
		C.SDL_DestroySurface(surface)
	}
	if unsafe { conv == nil } {
		return Frame{}
	}
	s := unsafe { &C.SDL_Surface(conv) }
	n := s.pitch * s.h
	mut buf := []u8{len: n}
	unsafe { vmemcpy(buf.data, s.pixels, n) }
	f := Frame{
		w:      s.w
		h:      s.h
		pitch:  s.pitch
		pixels: buf
	}
	C.SDL_DestroySurface(conv)
	return f
}

// load_frame_png читает PNG (и любой формат SDL_image) в Frame.
pub fn load_frame_png(path string) !Frame {
	surface := C.IMG_Load(path.str)
	if unsafe { surface == nil } {
		return error('не удалось прочитать картинку ${path}')
	}
	f := frame_from_surface(surface, true)
	if f.w == 0 {
		return error('не удалось преобразовать картинку ${path}')
	}
	return f
}

// save_png сохраняет кадр в PNG (каталоги создаются).
pub fn (f &Frame) save_png(path string) ! {
	if f.w <= 0 || f.h <= 0 {
		return error('пустой кадр')
	}
	dir := os.dir(path)
	if dir.len > 0 && !os.exists(dir) {
		os.mkdir_all(dir)!
	}
	surface := C.SDL_CreateSurface(f.w, f.h, sdl_pixelformat_abgr8888)
	if unsafe { surface == nil } {
		return error('SDL_CreateSurface')
	}
	defer {
		C.SDL_DestroySurface(surface)
	}
	s := unsafe { &C.SDL_Surface(surface) }
	row := f.w * 4
	for y in 0 .. f.h {
		unsafe { vmemcpy(&u8(s.pixels) + y * s.pitch, &f.pixels[y * f.pitch], row) }
	}
	if !C.IMG_SavePNG(surface, path.str) {
		return error('не удалось записать ${path}')
	}
}

// px - цвет пикселя (x, y); за пределами кадра - прозрачный.
pub fn (f &Frame) px(x int, y int) Color {
	if x < 0 || y < 0 || x >= f.w || y >= f.h {
		return Color{0, 0, 0, 0}
	}
	o := y * f.pitch + x * 4
	return Color{f.pixels[o], f.pixels[o + 1], f.pixels[o + 2], f.pixels[o + 3]}
}

// count - сколько пикселей прямоугольника r (физические пиксели, обрезается
// по кадру) отличаются от c не больше чем на tol по каждому из R, G, B.
pub fn (f &Frame) count(r Rect, c Color, tol int) int {
	x0 := max_int(0, int(r.x))
	y0 := max_int(0, int(r.y))
	x1 := min_int(f.w, int(r.x + r.w))
	y1 := min_int(f.h, int(r.y + r.h))
	mut n := 0
	for y in y0 .. y1 {
		for x in x0 .. x1 {
			o := y * f.pitch + x * 4
			if abs_int(int(f.pixels[o]) - int(c.r)) <= tol
				&& abs_int(int(f.pixels[o + 1]) - int(c.g)) <= tol
				&& abs_int(int(f.pixels[o + 2]) - int(c.b)) <= tol {
				n++
			}
		}
	}
	return n
}

// diff сравнивает два кадра: пиксель отличается, если хоть один канал (с
// альфой) разошёлся больше чем на tol.
pub fn (f &Frame) diff(other &Frame, tol int) FrameDiff {
	if f.w != other.w || f.h != other.h {
		return FrameDiff{
			size_mismatch: true
		}
	}
	mut n := 0
	mut maxd := 0
	for y in 0 .. f.h {
		for x in 0 .. f.w {
			a := y * f.pitch + x * 4
			b := y * other.pitch + x * 4
			mut worst := 0
			for k in 0 .. 4 {
				d := abs_int(int(f.pixels[a + k]) - int(other.pixels[b + k]))
				if d > worst {
					worst = d
				}
			}
			if worst > maxd {
				maxd = worst
			}
			if worst > tol {
				n++
			}
		}
	}
	return FrameDiff{
		count:     n
		max_delta: maxd
	}
}


// ─── Снапшоты ──────────────────────────────────────────

// SnapshotOpts - допуски сравнения с эталоном: tol - разница канала, которая
// ещё не считается отличием; max_pixels - сколько отличающихся пикселей
// терпимо (сглаживание шрифтов на другой машине).
@[params]
pub struct SnapshotOpts {
pub:
	tol        int = 2
	max_pixels int
}

// snapshot_update - перезаписывать эталоны вместо сравнения (переменная
// окружения VGUI_UPDATE_SNAPSHOTS=1).
fn snapshot_update() bool {
	v := os.getenv('VGUI_UPDATE_SNAPSHOTS')
	return v.len > 0 && v != '0'
}

// match_frame_snapshot сравнивает кадр f с эталонным PNG path. Эталона нет или
// VGUI_UPDATE_SNAPSHOTS=1 - кадр записывается эталоном (успех). Расхождение -
// ошибка с числами, а рядом пишется <path>.actual.png для разбора; при
// совпадении старый .actual.png удаляется.
pub fn match_frame_snapshot(f &Frame, path string, opts SnapshotOpts) ! {
	actual := path.all_before_last('.png') + '.actual.png'
	if snapshot_update() || !os.exists(path) {
		f.save_png(path)!
		os.rm(actual) or {}
		return
	}
	golden := load_frame_png(path)!
	d := f.diff(&golden, opts.tol)
	if d.size_mismatch {
		f.save_png(actual)!
		return error('снапшот ${path}: размер ${f.w}x${f.h}, а у эталона ${golden.w}x${golden.h} (кадр - ${actual})')
	}
	if d.count > opts.max_pixels {
		f.save_png(actual)!
		return error('снапшот ${path}: отличаются ${d.count} пикс. (допуск ${opts.max_pixels}), наибольшая разница ${d.max_delta} (кадр - ${actual}; обновить эталоны - VGUI_UPDATE_SNAPSHOTS=1)')
	}
	os.rm(actual) or {}
}

// ─── TestUi: окно для теста ────────────────────────────

// TestUiConfig - окно теста. theme по умолчанию светлая (снапшоты не зависят
// от темы системы).
@[params]
pub struct TestUiConfig {
pub:
	width    int   = 320
	height   int   = 240
	theme    Theme = light_theme()
	ui_scale f32   = 1
}

// TestUi - App + окно на dummy-драйвере SDL (дисплей не нужен) с
// фиксированным шагом анимаций: результат не зависит от скорости машины.
// Методы ввода - обёртки над sim_* для этого окна; mods - по желанию.
@[heap]
pub struct TestUi {
pub mut:
	app &App
	win &Window
}

// new_test_ui создаёт App и окно. Каждому тесту - свой TestUi, в конце -
// close(); второе окно в том же тесте создайте сами и t.app.add_window.
pub fn new_test_ui(cfg TestUiConfig) !&TestUi {
	os.setenv('SDL_VIDEODRIVER', 'dummy', true)
	mut app := create_app()!
	mut win := create_window(
		title:  'vgui test'
		width:  cfg.width
		height: cfg.height
		theme:  cfg.theme
	)!
	win.ctx.anim_fixed_dt = anim_nominal_dt
	app.add_window(win)
	if cfg.ui_scale != 1 {
		win.set_ui_scale(cfg.ui_scale)
	}
	return &TestUi{
		app: app
		win: win
	}
}

// add кладёт корневой виджет в окно и рисует кадр (bounds раздаются в arrange,
// до первого кадра попасть кликом по виджету нельзя).
pub fn (mut t TestUi) add(w &Widget) {
	t.win.add_widget(w)
	t.frame()
}

// frame - один кадр (с dirty regions, как в живом цикле).
pub fn (mut t TestUi) frame() {
	t.app.render_all()
}

// redraw - полный кадр: всё окно помечается грязным.
pub fn (mut t TestUi) redraw() {
	t.win.invalidate_all()
	t.app.render_all()
}

// settle рисует кадры, пока идут анимации (не больше max_frames), - перед
// снапшотом, чтобы наведение/раскрытие доехали до конца.
pub fn (mut t TestUi) settle(max_frames int) {
	for _ in 0 .. max_frames {
		if !t.app.needs_animation_now() {
			break
		}
		t.app.render_all()
	}
}

pub fn (mut t TestUi) move(x f32, y f32) {
	sim_move(mut t.app, t.win, x, y, 0)
}

pub fn (mut t TestUi) click(x f32, y f32) {
	sim_click(mut t.app, t.win, x, y, .left, 1, 0)
}

// click_mods - клик с модификаторами (sdl_kmod_ctrl | sdl_kmod_shift...).
pub fn (mut t TestUi) click_mods(x f32, y f32, mods u16) {
	sim_click(mut t.app, t.win, x, y, .left, 1, mods)
}

pub fn (mut t TestUi) right_click(x f32, y f32) {
	sim_click(mut t.app, t.win, x, y, .right, 1, 0)
}

// dbl_click - два быстрых клика (второй с clicks = 2, как от SDL).
pub fn (mut t TestUi) dbl_click(x f32, y f32) {
	sim_click(mut t.app, t.win, x, y, .left, 1, 0)
	sim_click(mut t.app, t.win, x, y, .left, 2, 0)
}

pub fn (mut t TestUi) press(x f32, y f32) {
	sim_press(mut t.app, t.win, x, y, .left, 1, 0)
}

pub fn (mut t TestUi) release(x f32, y f32) {
	sim_release(mut t.app, t.win, x, y, .left, 0)
}

pub fn (mut t TestUi) drag(x0 f32, y0 f32, x1 f32, y1 f32) {
	sim_drag(mut t.app, t.win, x0, y0, x1, y1, 8, .left, 0)
}

// wheel - колесо в точке; dy > 0 - вверх.
pub fn (mut t TestUi) wheel(x f32, y f32, dy f32) {
	sim_wheel(mut t.app, t.win, x, y, 0, dy, 0)
}

// key - клавиша с модификаторами: t.key(sdl_k_tab, 0), t.key(`s`, sdl_kmod_ctrl).
pub fn (mut t TestUi) key(keycode int, mods u16) {
	sim_key(mut t.app, t.win, keycode, mods)
}

// type_text - ввод текста в виджет с фокусом.
pub fn (mut t TestUi) type_text(text string) {
	sim_text(mut t.app, t.win, text)
}

// center_of - центр bounds виджета (логические координаты).
pub fn (t &TestUi) center_of(w &Widget) (f32, f32) {
	b := get_widget_bounds(w)
	return b.x + b.w * 0.5, b.y + b.h * 0.5
}

// click_widget - клик по центру виджета.
pub fn (mut t TestUi) click_widget(w &Widget) {
	x, y := t.center_of(w)
	t.click(x, y)
}

// capture - показанный кадр.
pub fn (mut t TestUi) capture() Frame {
	return capture_frame(mut t.win)
}

// match_snapshot - capture + match_frame_snapshot; перед снимком анимации
// доводятся до конца (settle).
pub fn (mut t TestUi) match_snapshot(path string, opts SnapshotOpts) ! {
	t.settle(120)
	f := t.capture()
	match_frame_snapshot(&f, path, opts)!
}

// close закрывает окно и App (SDL_Quit) - следующий тест создаст свой.
pub fn (mut t TestUi) close() {
	t.app.cleanup()
}
