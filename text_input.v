module vgui

// Шапка файла.
// TextInput - однострочное поле ввода: выделение мышью и с Shift, перемещение по
// словам (Ctrl+стрелки), буфер обмена, undo/redo (UndoHistory[RuneSnap]), режим
// пароля, плейсхолдер, ограничение длины и фильтр вводимых символов по regexp.
//
// Связь с остальной библиотекой:
//   - раскладка: bounds выдаёт контейнер; поле `chars` (ширина в символах) и
//     measure() живут в layout_measure.v;
//   - отрисовка: шрифт подбирается под высоту виджета (fit_font_size), текст
//     клипируется внутри bounds с отступом pad, прокрутка по X - scroll_x;
//   - фокус: каждый draw регистрирует поле в ctx.focus (focus.v); Tab/Escape
//     передаются FocusManager'у;
//   - события: handle_event() -> on_mouse_*/on_text/on_key; true = событие поглощено;
//   - колбэки on_change (при каждом изменении текста, в т.ч. undo/redo) и on_submit (Enter).
//
// Текст хранится как []rune (индексы курсора и выделения - в рунах, не в байтах).
// Выделение - пара sel_a (якорь) / sel_b (подвижный конец); -1 = нет выделения.
import regex

// ═══════════════════════════════════════════════════════════
//  TextInput — single-line editable text field with undo/redo
// ═══════════════════════════════════════════════════════════

const ti_max_undo = 100

// Коды клавиш/сканкодов для Home/End (в т.ч. цифровой блок KP 7/KP 1), которых нет
// среди общих sdl_k_* констант. Сканкоды нужны потому, что keycode зависит от
// раскладки, а физическая клавиша - нет. Используются также из tree_view.v.
const sdl_k_kp_1 = 1073741913
const sdl_k_kp_7 = 1073741919

const sc_home = 74
const sc_end = 77
const sc_kp_7 = 95
const sc_kp_1 = 89

// SDL2 physical scancodes for letter keys — used to recognise Ctrl+A/C/V/X/Z
// regardless of the active keyboard layout (when a non-Latin layout is active
// SDL's keysym.sym returns a non-Latin codepoint instead of 'a'/'z').
const ti_sc_letter_a = 4
const ti_sc_letter_c = 6
const ti_sc_letter_v = 25
const ti_sc_letter_x = 27
const ti_sc_letter_z = 29

// ctrl_letter - нажата ли буква letter (в паре с Ctrl - проверяет вызывающий). Если
// клавиша даёт латинскую букву (keycode a..z), сравнивается сама буква: так Ctrl+Z
// работает на месте Z в любой латинской раскладке (AZERTY, Dvorak). Иначе - нелатинская
// раскладка (русская и т.п.), и буква определяется по физической клавише (scancode
// позиции в QWERTY): Ctrl+Я остаётся Ctrl+Z. Раньше сравнивался только scancode, и в
// AZERTY/Dvorak сочетания срабатывали не на тех клавишах.
fn ctrl_letter(ev &GuiEvent, letter rune, scancode int) bool {
	if ev.keycode >= `a` && ev.keycode <= `z` {
		return ev.keycode == int(letter)
	}
	return ev.scancode == scancode
}

// Режим фильтра input_filter (регулярное выражение V-модуля regex):
// whitelist/blacklist фильтруют каждый вводимый символ отдельно, pattern проверяет
// всю строку целиком после вставки.
pub enum InputFilterMode {
	whitelist // разрешить только символы, совпадающие с паттерном
	blacklist // запретить символы, совпадающие с паттерном
	pattern   // вся строка должна соответствовать паттерну после вставки
}

// TextInput - поле ввода. Примечания к полям:
//   buf       - текст как руны; pw_mode показывает вместо символов точки (см. disp);
//   max_len   - предельная длина в рунах (вставка обрезается);
//   chars     - ширина в символах для раскладки (0 - занять всё место);
//   cur       - позиция курсора (0..buf.len);
//   sel_a/b   - выделение (-1 = нет); drag - идёт выделение мышью;
//   scroll_x  - горизонтальная прокрутка текста, когда он не помещается;
//   focus_t   - анимация фокуса (0..1) для рамки;
//   flat      - рисовать без фона и рамки (встраивание в другие виджеты);
//   cursor_color - прозрачный (a == 0) = акцентный цвет темы.
@[heap]
pub struct TextInput {
pub mut:
	type_tag    int = kind_text_input // тег типа, см. widget_tag.v
	bounds      Rect
	pad         f32 = 6
	buf         []rune
	placeholder string
	visible     bool = true
	enabled     bool = true
	focused     bool
	hovered     bool
	pw_mode     bool
	max_len     int = 4096
	// Ширина поля в символах (как size у HTML-поля): > 0 - поле
	// такой ширины и не растягивается; 0 - заполняет место в ряду
	chars             int
	cur               int
	sel_a             int = -1
	sel_b             int = -1
	scroll_x          f32
	drag              bool
	focus_t           Anim  = anim_smooth(anim_tau_focus)
	cursor_color      Color = Color{0, 0, 0, 0}
	flat              bool
	input_filter      string
	input_filter_mode InputFilterMode
	// accept - проверка строки-кандидата «как будет после вставки» кодом, а не
	// регулярным выражением (как режим pattern). false - вставка отклоняется.
	// Нужна, когда допустимый текст не выразить паттерном: Spinbox принимает число
	// с произвольными префиксом и суффиксом. Если задана - input_filter не применяется.
	accept      fn (string) bool      = unsafe { nil }
	history     UndoHistory[RuneSnap] = UndoHistory[RuneSnap]{
		limit: ti_max_undo
	}
	on_change   fn (string) = unsafe { nil }
	on_submit   fn (string) = unsafe { nil }
	focus_group int
}

// For use inside containers (bounds set by layout)
pub fn text_input(placeholder string) &TextInput {
	return &TextInput{
		placeholder: placeholder
	}
}

// ───────────── public helpers ───────────────────────────

pub fn (t &TextInput) get_text() string {
	if t.buf.len == 0 {
		return ''
	}
	return t.buf.string()
}

// Программно задаёт текст: курсор в конец, выделение и прокрутка сброшены, история
// undo очищена. Колбэк on_change НЕ вызывается.
pub fn (mut t TextInput) set_text(s string) {
	t.buf = s.runes()
	t.cur = t.buf.len
	t.sel_a = -1
	t.sel_b = -1
	t.scroll_x = 0
	t.history.clear()
}

// ───────────── undo / redo ─────────────────────────────

// Undo/redo: снимок (буфер, курсор) кладётся в историю ПЕРЕД каждой правкой
// (save_undo), а undo()/redo() обменивают текущее состояние со снимком.
// restore() после отката вызывает on_change, как и обычная правка.
fn (t &TextInput) snap() RuneSnap {
	return RuneSnap{
		buf: t.buf.clone()
		cur: t.cur
	}
}

fn (mut t TextInput) save_undo() {
	t.history.save(t.snap())
}

fn (mut t TextInput) restore(entry RuneSnap) {
	t.buf = entry.buf.clone()
	t.cur = clamp_int(entry.cur, 0, t.buf.len)
	t.clear_sel()
	t.fire()
}

// undo отменяет последнюю правку (как Ctrl+Z); false — отменять нечего.
pub fn (mut t TextInput) undo() bool {
	entry := t.history.undo(t.snap()) or { return false }
	t.restore(entry)
	return true
}

// redo повторяет отменённую правку (как Ctrl+Shift+Z).
pub fn (mut t TextInput) redo() bool {
	entry := t.history.redo(t.snap()) or { return false }
	t.restore(entry)
	return true
}

pub fn (t &TextInput) can_undo() bool {
	return t.history.can_undo()
}

pub fn (t &TextInput) can_redo() bool {
	return t.history.can_redo()
}

// clear_undo забывает историю правок (например, после загрузки документа).
pub fn (mut t TextInput) clear_undo() {
	t.history.clear()
}

// ───────────── low-level rune ops ──────────────────────

// rslice - безопасная подстрока рун [a, b): индексы зажимаются в границы, пустой
// или перевёрнутый диапазон даёт ''.
fn rslice(r []rune, a int, b int) string {
	s := clamp_int(a, 0, r.len)
	e := clamp_int(b, s, r.len)
	if s >= e {
		return ''
	}
	return r[s..e].string()
}

// rsplice - новый срез рун: src с заменой диапазона [a, b) на ins (удаление - пустой
// ins, вставка - a == b). Исходный срез не меняется.
fn rsplice(src []rune, a int, b int, ins []rune) []rune {
	s := clamp_int(a, 0, src.len)
	e := clamp_int(b, s, src.len)
	mut out := []rune{cap: src.len - (e - s) + ins.len}
	for i in 0 .. s {
		out << src[i]
	}
	for r in ins {
		out << r
	}
	for i in e .. src.len {
		out << src[i]
	}
	return out
}

// ───────────── display helpers ─────────────────────────

// Отображаемые руны: в режиме пароля - маркеры «•» (U+2022) вместо символов.
// Позиции курсора совпадают с buf, т.к. длина одинакова.
fn (t &TextInput) disp() []rune {
	if t.pw_mode && t.buf.len > 0 {
		mut o := []rune{cap: t.buf.len}
		for _ in 0 .. t.buf.len {
			o << rune(0x2022)
		}
		return o
	}
	return t.buf
}

// ───────────── selection helpers ───────────────────────

fn (t &TextInput) has_sel() bool {
	return t.sel_a >= 0 && t.sel_b >= 0 && t.sel_a != t.sel_b
}

fn (t &TextInput) sel_lo() int {
	return min_int(t.sel_a, t.sel_b)
}

fn (t &TextInput) sel_hi() int {
	return max_int(t.sel_a, t.sel_b)
}

fn (mut t TextInput) clear_sel() {
	t.sel_a = -1
	t.sel_b = -1
}

// Если выделения нет, заводит выделение нулевой длины в позиции курсора - точку
// отсчёта для расширения Shift+стрелкой/Home/End.
fn (mut t TextInput) ensure_sel() {
	if t.sel_a < 0 {
		t.sel_a = t.cur
		t.sel_b = t.cur
	}
}

fn (t &TextInput) selected_text() string {
	if !t.has_sel() {
		return ''
	}
	return rslice(t.buf, t.sel_lo(), t.sel_hi())
}

// ───────────── font size for widget height ─────────────

// Размер шрифта под высоту виджета: доступная высота (h - 2*pad) делится на 1.25
// (отношение высоты строки к кеглю), результат зажат в [8, 72]. Благодаря этому
// поле, растянутое по высоте, получает крупный текст.
fn (t &TextInput) fit_font_size() int {
	avail := t.bounds.h - t.pad * 2.0
	if avail < 6 {
		return 8
	}
	sz := int(avail / 1.25)
	if sz < 8 {
		return 8
	}
	if sz > 72 {
		return 72
	}
	return sz
}

// ───────────── drawing ─────────────────────────────────

// Отрисовка поля. Порядок: регистрация в FocusManager и синхронизация focused ->
// перезаказ анимации курсора -> проверка клипа -> фон/рамка/кольцо фокуса (если не
// flat) -> текст под клипом области содержимого: плейсхолдер (пусто, нет фокуса),
// одинокий курсор (пусто, есть фокус) или текст с выделением и курсором. У
// нефокусного поля прокрутка сбрасывается в 0 и текст рисуется вторичным цветом.
// Курсор мигает с периодом 1060 мс (видим первые 530 мс); поэтому у сфокусированного
// поля каждый кадр заказывается перерисовка его области (mark_anim_rect).
pub fn (mut t TextInput) draw(mut ctx RenderContext) {
	if !t.visible {
		return
	}

	// Registration + focus-sync run regardless of whether this widget falls
	// inside the current (possibly partial) frame's clip — neither is pixel
	// output, both determine tab order / focused state, which must stay
	// correct even for a widget a partial frame happens not to touch.
	//
	// BEHAVIOR CHANGE from before dirty regions: registration used to happen
	// only past the (now-later) is_in_clip check, so a fully-clipped-out
	// TextInput was invisible to the FocusManager and Tab would skip it.
	// Now it registers unconditionally (as long as `enabled`), so Tab can
	// reach it even while it is entirely clipped away — a side effect of
	// moving this block ahead of is_in_clip for the cursor-blink fix below,
	// not an intentional focus-order redesign.
	if t.enabled {
		ctx.focus.register_text_input(&t, t.focus_group)
	}
	should_focus := ctx.focus.is_focused(unsafe { &t })
	if t.focused && !should_focus {
		t.focused = false
		t.drag = false
		t.clear_sel()
	} else if !t.focused && should_focus {
		t.focused = true
	}

	// Re-arm the cursor-blink animation independent of clip: a partial
	// frame's dirty rect can legitimately miss this widget (some OTHER
	// widget's small area changed this frame). If re-invalidation only
	// happened from inside the "in clip" drawing path below, a TextInput
	// skipped by one partial frame would never re-request its own rect for
	// the next one — the blink would freeze permanently the first time it
	// isn't part of the dirty region.
	if t.focused {
		ctx.mark_anim_rect('textinput', t.bounds)
	}

	if !ctx.is_in_clip(t.bounds) {
		return
	}

	wanted_sz := t.fit_font_size()
	ti_font := ctx.get_font(.regular, wanted_sz)

	cc := if t.cursor_color.a > 0 { t.cursor_color } else { ctx.theme.accent }

	tgt := if t.focused { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if t.focus_t.update(tgt, ctx) {
		ctx.mark_anim_rect('textinput', t.bounds.expanded(1))
	}

	rad := ctx.theme.border_radius
	if !t.flat {
		bg := if t.enabled { ctx.theme.input_bg } else { ctx.theme.input_bg.darken(0.05) }
		ctx.fill_rounded_rect(t.bounds, bg, rad)
		bc := ctx.theme.input_border.blend(ctx.theme.input_focus, t.focus_t.value)
		ctx.draw_rounded_rect(t.bounds, bc, rad)
		ctx.draw_focus_ring_edge(t.bounds, rad, t.focus_t.value)
	}

	cr := t.bounds.shrunk(t.pad)
	ctx.push_clip(cr)

	dr := t.disp()
	fh := ctx.font_height_of(ti_font)
	ty := cr.y + (cr.h - fh) * 0.5

	if dr.len == 0 && !t.focused {
		ctx.draw_text_with_font(t.placeholder, cr.x, ty, ctx.theme.text_hint, ti_font)
	} else if dr.len == 0 && t.focused {
		ms := C.SDL_GetTicks()
		phase := ms % u64(1060)
		if phase < 530 {
			ctx.fill_rect(Rect{cr.x, ty, 2, fh}, cc)
		}
	} else {
		if t.focused {
			t.fix_scroll(ctx, cr.w, dr, ti_font)

			if t.has_sel() {
				lo := t.sel_lo()
				hi := t.sel_hi()
				x1 := ctx.measure_text_with_font(rslice(dr, 0, lo), ti_font).x - t.scroll_x
				x2 := ctx.measure_text_with_font(rslice(dr, 0, hi), ti_font).x - t.scroll_x
				sr := Rect{
					x: cr.x + x1
					y: ty - 1
					w: x2 - x1
					h: fh + 2
				}
				ctx.fill_rounded_rect(sr, cc.with_alpha(80), 2)
			}

			ds := dr.string()
			ctx.draw_text_with_font(ds, cr.x - t.scroll_x, ty, ctx.theme.text_primary, ti_font)

			ms := C.SDL_GetTicks()
			phase := ms % u64(1060)
			if phase < 530 {
				cx := ctx.measure_text_with_font(rslice(dr, 0, t.cur), ti_font).x - t.scroll_x
				ctx.fill_rect(Rect{cr.x + cx, ty, 2, fh}, cc)
			}
		} else {
			t.scroll_x = 0
			ds := dr.string()
			ctx.draw_text_with_font(ds, cr.x, ty, ctx.theme.text_secondary, ti_font)
		}
	}

	ctx.pop_clip()
}

// Подбирает scroll_x так, чтобы курсор оставался в видимой области ширины cw (с
// запасом 20 px при сдвиге); если весь текст помещается - прокрутка 0.
// Вызывается из draw(), т.е. отрисовка меняет состояние виджета.
fn (mut t TextInput) fix_scroll(ctx &RenderContext, cw f32, dr []rune, font voidptr) {
	cx := ctx.measure_text_with_font(rslice(dr, 0, t.cur), font).x
	if cx - t.scroll_x > cw - 2 {
		t.scroll_x = cx - cw + 20
	}
	if cx - t.scroll_x < 0 {
		t.scroll_x = max_f32(0, cx - 20)
	}
	tw := ctx.measure_text_with_font(if dr.len > 0 { dr.string() } else { '' }, font).x
	if tw <= cw {
		t.scroll_x = 0
	}
	if t.scroll_x < 0 {
		t.scroll_x = 0
	}
}

// ───────────── event dispatch ──────────────────────────

// Диспетчер событий; true - событие поглощено. Нефокусное или скрытое/выключенное
// поле события не берёт (mouse_move обновляет hovered даже без фокуса).
pub fn (mut t TextInput) handle_event(ev &GuiEvent, app &App) bool {
	if !t.visible || !t.enabled {
		return false
	}

	match ev.typ {
		.mouse_move {
			return t.on_mouse_move(ev, app)
		}
		.mouse_down {
			return t.on_mouse_down(ev, app)
		}
		.mouse_up {
			return t.on_mouse_up(ev)
		}
		.mouse_dbl_click {
			if !t.focused || !t.hovered {
				return false
			}
			t.select_word()
			t.drag = false
			return true
		}
		.text_input {
			return t.on_text(ev)
		}
		.key_down {
			return t.on_key(ev, app)
		}
		else {
			return false
		}
	}
}

// Движение: обновляет hovered; при перетаскивании двигает конец выделения. Событие
// поглощается только во время выделения мышью.
fn (mut t TextInput) on_mouse_move(ev &GuiEvent, app &App) bool {
	t.hovered = t.bounds.contains(ev.mouse_x, ev.mouse_y)
	if t.drag && t.focused {
		t.cur = t.hit_pos(ev.mouse_x, app)
		t.sel_b = t.cur
		return true
	}
	return false
}

// Левая кнопка: внутри поля - взять фокус (через FocusManager), поставить курсор
// под мышью и начать выделение; вне поля при наличии фокуса - снять фокус. Клик
// снаружи не поглощается (false), чтобы он дошёл до других виджетов.
fn (mut t TextInput) on_mouse_down(ev &GuiEvent, app &App) bool {
	if ev.mouse_btn != .left {
		return false
	}
	if t.hovered {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.focus_text_input(&t, t.focus_group)
		}
		t.focused = true
		t.cur = t.hit_pos(ev.mouse_x, app)
		t.sel_a = t.cur
		t.sel_b = t.cur
		t.drag = true
		return true
	}
	if t.focused && !t.hovered {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.blur_current()
		}
		t.focused = false
		t.drag = false
		t.clear_sel()
		return false
	}
	return false
}

// Конец перетаскивания; пустое выделение (a == b) сбрасывается, чтобы не рисовалась
// подсветка нулевой ширины.
fn (mut t TextInput) on_mouse_up(ev &GuiEvent) bool {
	if ev.mouse_btn != .left {
		return false
	}
	if t.drag {
		t.drag = false
		if t.sel_a == t.sel_b {
			t.clear_sel()
		}
		return t.focused
	}
	return false
}

// Ввод символов (SDL text_input): вставка с учётом фильтра и max_len.
fn (mut t TextInput) on_text(ev &GuiEvent) bool {
	if !t.focused {
		return false
	}
	t.insert(ev.text)
	return true
}

// Home/End: срабатывают по keycode и по scancode (раскладко-независимо), включая
// KP 7 / KP 1 цифрового блока. Используются также TableView (table.v).
fn is_home_key(keycode int, scancode int) bool {
	return keycode == sdl_k_home || keycode == sdl_k_kp_7 || scancode == sc_home
		|| scancode == sc_kp_7
}

fn is_end_key(keycode int, scancode int) bool {
	return keycode == sdl_k_end || keycode == sdl_k_kp_1 || scancode == sc_end
		|| scancode == sc_kp_1
}

// Обработка нажатий клавиш (только при фокусе). Порядок: Tab (передать фокус) ->
// Home/End -> Ctrl+буква по scancode -> остальные клавиши по keycode.
// Ctrl+A/C/X/V/Z проверяются по ФИЗИЧЕСКОМУ scancode, чтобы шорткаты работали и при
// нелатинской раскладке (keycode там - кириллическая буква); ветки sdl_k_a/c/x/v/z
// ниже - запасной путь по keycode. Ctrl+Shift+Z - redo. Ctrl+Insert копирует,
// Shift+Insert вставляет. Enter вызывает on_submit, Escape снимает фокус. Возвращает
// false для неизвестных клавиш, чтобы их обработали выше (например, горячие клавиши
// окна).
fn (mut t TextInput) on_key(ev &GuiEvent, app &App) bool {
	if !t.focused {
		return false
	}

	c := ev.ctrl()
	s := ev.shift()

	if ev.keycode == sdl_k_tab {
		ctx_ptr := app.get_active_ctx()
		if unsafe { ctx_ptr != nil } {
			mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
			ctx_mut.focus.tab(s)
		}
		return true
	}

	if is_home_key(ev.keycode, ev.scancode) {
		t.key_home(s)
		return true
	}
	if is_end_key(ev.keycode, ev.scancode) {
		t.key_end(s)
		return true
	}

	// Layout-independent Ctrl+letter handling (works on Cyrillic, etc.)
	if c {
		if ctrl_letter(ev, `a`, ti_sc_letter_a) {
			t.sel_a = 0
			t.sel_b = t.buf.len
			t.cur = t.buf.len
			return true
		}
		if ctrl_letter(ev, `c`, ti_sc_letter_c) {
			if t.has_sel() {
				app.set_clipboard(t.selected_text())
			}
			return true
		}
		if ctrl_letter(ev, `x`, ti_sc_letter_x) {
			if t.has_sel() {
				app.set_clipboard(t.selected_text())
				t.save_undo()
				t.del_sel_no_undo()
				t.fire()
			}
			return true
		}
		if ctrl_letter(ev, `v`, ti_sc_letter_v) {
			cl := app.get_clipboard()
			if cl.len > 0 {
				t.insert(cl)
			}
			return true
		}
		if ctrl_letter(ev, `z`, ti_sc_letter_z) {
			if s {
				t.redo()
			} else {
				t.undo()
			}
			return true
		}
	}

	match ev.keycode {
		sdl_k_backspace {
			t.key_backspace(c)
			return true
		}
		sdl_k_delete {
			t.key_delete(c)
			return true
		}
		sdl_k_left {
			t.key_left(c, s)
			return true
		}
		sdl_k_right {
			t.key_right(c, s)
			return true
		}
		sdl_k_return {
			if t.on_submit != unsafe { nil } {
				t.on_submit(t.get_text())
			}
			return true
		}
		sdl_k_insert {
			if c {
				if t.has_sel() {
					app.set_clipboard(t.selected_text())
				}
			} else if s {
				cl := app.get_clipboard()
				if cl.len > 0 {
					t.insert(cl)
				}
			} else {
				return false
			}
			return true
		}
		sdl_k_a {
			if c {
				t.sel_a = 0
				t.sel_b = t.buf.len
				t.cur = t.buf.len
				return true
			}
		}
		sdl_k_c {
			if c {
				if t.has_sel() {
					app.set_clipboard(t.selected_text())
				}
				return true
			}
		}
		sdl_k_x {
			if c {
				if t.has_sel() {
					app.set_clipboard(t.selected_text())
					t.save_undo()
					t.del_sel_no_undo()
					t.fire()
				}
				return true
			}
		}
		sdl_k_v {
			if c {
				cl := app.get_clipboard()
				if cl.len > 0 {
					t.insert(cl)
				}
				return true
			}
		}
		sdl_k_z {
			if c && s {
				t.redo()
				return true
			} else if c {
				t.undo()
				return true
			}
		}
		sdl_k_escape {
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				ctx_mut.focus.blur_current()
			}
			return true
		}
		else {}
	}

	return false
}

// ───────────── key actions ─────────────────────────────

// Backspace/Delete: с выделением удаляют его; без выделения - один символ, а с
// Ctrl - слово слева (wl) / справа (wr). Перед правкой сохраняется undo, после -
// вызывается on_change.
fn (mut t TextInput) key_backspace(ctrl bool) {
	if t.has_sel() {
		t.save_undo()
		t.del_sel_no_undo()
		t.fire()
		return
	}
	if ctrl {
		if t.cur > 0 {
			t.save_undo()
			b := t.wl()
			t.buf = rsplice(t.buf, b, t.cur, [])
			t.cur = b
			t.fire()
		}
	} else if t.cur > 0 {
		t.save_undo()
		t.buf = rsplice(t.buf, t.cur - 1, t.cur, [])
		t.cur--
		t.fire()
	}
}

fn (mut t TextInput) key_delete(ctrl bool) {
	if t.has_sel() {
		t.save_undo()
		t.del_sel_no_undo()
		t.fire()
		return
	}
	if ctrl {
		if t.cur < t.buf.len {
			t.save_undo()
			b := t.wr()
			t.buf = rsplice(t.buf, t.cur, b, [])
			t.fire()
		}
	} else if t.cur < t.buf.len {
		t.save_undo()
		t.buf = rsplice(t.buf, t.cur, t.cur + 1, [])
		t.fire()
	}
}

// Стрелки: Ctrl - по словам, Shift - расширяют выделение. Без Shift при активном
// выделении стрелка схлопывает его к соответствующему краю, не двигая курсор дальше.
fn (mut t TextInput) key_left(ctrl bool, shift bool) {
	if shift {
		t.ensure_sel()
	}
	if ctrl {
		t.cur = t.wl()
	} else if !shift && t.has_sel() {
		t.cur = t.sel_lo()
		t.clear_sel()
		return
	} else {
		t.cur = max_int(0, t.cur - 1)
	}
	if shift {
		t.sel_b = t.cur
	} else {
		t.clear_sel()
	}
}

fn (mut t TextInput) key_right(ctrl bool, shift bool) {
	if shift {
		t.ensure_sel()
	}
	if ctrl {
		t.cur = t.wr()
	} else if !shift && t.has_sel() {
		t.cur = t.sel_hi()
		t.clear_sel()
		return
	} else {
		t.cur = min_int(t.buf.len, t.cur + 1)
	}
	if shift {
		t.sel_b = t.cur
	} else {
		t.clear_sel()
	}
}

fn (mut t TextInput) key_home(shift bool) {
	if shift {
		t.ensure_sel()
	}
	t.cur = 0
	if shift {
		t.sel_b = 0
	} else {
		t.clear_sel()
	}
}

fn (mut t TextInput) key_end(shift bool) {
	if shift {
		t.ensure_sel()
	}
	t.cur = t.buf.len
	if shift {
		t.sel_b = t.buf.len
	} else {
		t.clear_sel()
	}
}

// ───────────── editing helpers ─────────────────────────

// Вставка текста в позицию курсора с заменой выделения. Порядок: режим pattern
// уходит в отдельную проверку всей строки; иначе текст фильтруется посимвольно
// (whitelist/blacklist), считается свободное место до max_len (выделение при
// замене освобождает место), и вставляется то, что поместилось. Если вставлять
// нечего (всё отфильтровано / нет места) - правка не происходит: ни undo-снимка,
// ни удаления выделения, ни on_change.
fn (mut t TextInput) insert(s string) {
	if s.len == 0 {
		return
	}
	if t.accept != unsafe { nil } {
		t.insert_checked(s, t.accept)
		return
	}
	if t.input_filter.len > 0 && t.input_filter_mode == .pattern {
		pattern := t.input_filter
		t.insert_checked(s, fn [pattern] (candidate string) bool {
			// Некорректное регулярное выражение - ввод отклоняется.
			mut re := regex.regex_opt(pattern) or { return false }
			return re.matches_string(candidate)
		})
		return
	}
	rr := if t.input_filter.len > 0 { t.filter_runes(s.runes()) } else { s.runes() }
	sel_len := if t.has_sel() { t.sel_hi() - t.sel_lo() } else { 0 }
	room := t.max_len - (t.buf.len - sel_len)
	// Нечего вставлять — правки нет: ни снимка, ни удаления выделения.
	if rr.len == 0 || room <= 0 {
		return
	}
	t.save_undo()
	if t.has_sel() {
		t.del_sel_no_undo()
	}
	ins := if rr.len > room { rr[..room] } else { rr }
	t.buf = rsplice(t.buf, t.cur, t.cur, ins)
	t.cur += ins.len
	t.fire()
}

// Режим pattern и accept: собирается строка-кандидат «как будет после вставки» и
// целиком отдаётся check; false - вставка отклоняется. Проверяется весь кандидат,
// поэтому проверка должна допускать и промежуточные состояния ввода ("" или "-").
fn (mut t TextInput) insert_checked(s string, check fn (string) bool) {
	lo := if t.has_sel() { t.sel_lo() } else { t.cur }
	hi := if t.has_sel() { t.sel_hi() } else { t.cur }
	rr := s.runes()
	room := t.max_len - (t.buf.len - (hi - lo))
	if room <= 0 {
		return
	}
	ins := if rr.len > room { rr[..room] } else { rr }
	candidate := rsplice(t.buf, lo, hi, ins).string()
	if !check(candidate) {
		return
	}
	t.save_undo()
	if t.has_sel() {
		t.del_sel_no_undo()
	}
	t.buf = rsplice(t.buf, t.cur, t.cur, ins)
	t.cur += ins.len
	t.fire()
}

// Посимвольный фильтр whitelist/blacklist. При некорректном регулярном выражении
// текст проходит без фильтрации.
fn (t &TextInput) filter_runes(rr []rune) []rune {
	mut re := regex.regex_opt(t.input_filter) or { return rr }
	mut out := []rune{cap: rr.len}
	for r in rr {
		ch := r.str()
		matched := re.matches_string(ch)
		if (t.input_filter_mode == .whitelist && matched)
			|| (t.input_filter_mode == .blacklist && !matched) {
			out << r
		}
	}
	return out
}

// Удаляет выделение без записи в undo - вызывающий уже сделал save_undo() (так одна
// операция «заменить выделение» откатывается одним шагом). on_change не вызывается.
fn (mut t TextInput) del_sel_no_undo() {
	if !t.has_sel() {
		return
	}
	lo := t.sel_lo()
	hi := t.sel_hi()
	t.buf = rsplice(t.buf, lo, hi, [])
	t.cur = lo
	t.clear_sel()
}

// Вызывает on_change с текущим текстом, если колбэк задан.
fn (mut t TextInput) fire() {
	if t.on_change != unsafe { nil } {
		t.on_change(t.get_text())
	}
}

// ───────────── word boundaries ─────────────────────────

// Символ «слова» для Ctrl+стрелок, Ctrl+Backspace/Delete и двойного клика:
// латиница, цифры, «_» и кириллица. Другие алфавиты (греческий и т.д.) считаются
// разделителями. Используется также в tree_view.v и text_area.v.
fn is_word(r rune) bool {
	return (r >= `a` && r <= `z`) || (r >= `A` && r <= `Z`) || (r >= `0` && r <= `9`)
		|| r == `_` || (r >= `а` && r <= `я`) || (r >= `А` && r <= `Я`)
		|| r == `ё` || r == `Ё`
}

// Границы слов: wl - начало слова слева от курсора (сначала пропускает разделители
// слева, затем само слово); wr - позиция начала СЛЕДУЮЩЕГО слова справа (пропускает
// остаток слова и разделители после него), либо конец текста.
fn (t &TextInput) wl() int {
	if t.cur == 0 {
		return 0
	}
	mut p := t.cur - 1
	for p > 0 && !is_word(t.buf[p]) {
		p--
	}
	for p > 0 && is_word(t.buf[p - 1]) {
		p--
	}
	return p
}

fn (t &TextInput) wr() int {
	n := t.buf.len
	if t.cur >= n {
		return n
	}
	mut p := t.cur
	for p < n && is_word(t.buf[p]) {
		p++
	}
	for p < n && !is_word(t.buf[p]) {
		p++
	}
	return p
}

// Выделяет слово под курсором (двойной клик). В пустом буфере ничего не делает.
fn (mut t TextInput) select_word() {
	if t.buf.len == 0 {
		return
	}
	p := clamp_int(t.cur, 0, t.buf.len - 1)
	mut a := p
	mut b := p
	for a > 0 && is_word(t.buf[a - 1]) {
		a--
	}
	for b < t.buf.len && is_word(t.buf[b]) {
		b++
	}
	t.sel_a = a
	t.sel_b = b
	t.cur = b
}

// ───────────── hit-test (mouse → rune index) ──────────

// Переводит x-координату мыши в индекс руны: из локальной x (с учётом pad и
// scroll_x) перебором префиксов выбирается ближайшая граница между рунами.
// O(n) измерений текста на вызов (нажатие/движение при выделении). Без активного
// контекста возвращает 0.
fn (mut t TextInput) hit_pos(mx f32, app &App) int {
	lx := mx - t.bounds.x - t.pad + t.scroll_x
	dr := t.disp()
	if dr.len == 0 {
		return 0
	}

	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return 0
	}

	wanted_sz := t.fit_font_size()
	ti_font := ctx_ptr.get_font_immut(.regular, wanted_sz)

	mut best := 0
	mut bd := abs_f32(lx)
	for i := 1; i <= dr.len; i++ {
		w := ctx_ptr.measure_text_with_font(rslice(dr, 0, i), ti_font).x
		d := abs_f32(w - lx)
		if d < bd {
			bd = d
			best = i
		}
	}
	return best
}
