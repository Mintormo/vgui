module vgui

import strconv

// Файл number_field.v: NumberField - числовое поле с протяжкой, как поля значений Blender и Figma:
// тянешь мышью влево-вправо - значение меняется, щёлкнул без протяжки - вводишь число с клавиатуры.
// Отдельно от Spinbox (кнопки-стрелки) и Slider (дорожка): поле занимает место одной подписи, а
// умеет и точный ввод, и быструю грубую правку.
//
// Протяжка считается от точки нажатия, а не шагами мыши: значение = начальное + сдвиг / drag_px *
// step (Shift - в 10 раз точнее, Ctrl - кратно step). Так зажим в границы и округление не копят
// ошибку. Ввод - во внутреннее поле TextInput поверх виджета (фокус - ему, поле - FocusOwner, как
// у NodeEditor): Enter - применить, Esc - отменить, щелчок мимо (потеря фокуса) - применить.
// Принимаются цифры, знак и одна точка или запятая; не число - правки нет.
//
// Колбэки: on_change - каждое изменение (шаг протяжки, ввод, стрелки), on_commit - конец правки
// (отпустили мышь, Enter, стрелка). set_value кодом колбэков не вызывает: поле часто зеркалит
// другой виджет (ползунок), и колбэк в set_value замкнул бы их друг на друга.
//
// Рисование - примитивы RenderContext (PROJECT.md, «Бэкенд рисования»), цвета - поля ввода темы
// (input_bg, input_border, input_focus) и акцент для полоски доли; имя в CSS - `number`.
// Тег типа kind_number_field - widget_kinds.v.

const nf_drag_threshold = f32(3) // сдвиг, после которого нажатие - протяжка, а не щелчок

// NumberField - числовое поле. min/max - границы (по умолчанию нет); step - шаг стрелок и
// изменение за drag_px пикселей протяжки; digits - знаков после запятой в тексте и при вводе;
// label - подпись слева внутри поля ('' - нет, значение по align); show_fill - полоска доли
// значения в границах (если обе заданы); format - свой текст значения (единицы, знак «+»);
// chars - ширина под столько символов (0 - по тексту границ).
@[heap]
pub struct NumberField {
pub mut:
	type_tag    int = kind_number_field // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focused     bool
	focus_group int
	value       f64
	min         f64 = -1.0e30
	max         f64 = 1.0e30
	step        f64 = 0.1
	drag_px     f32 = 8
	digits      int = 2
	label       string
	align       TextAlign = .center
	show_fill   bool      = true
	chars       int
	format      fn (f64) string = unsafe { nil }
	on_change   fn (f64)        = unsafe { nil }
	on_commit   fn (f64)        = unsafe { nil }
mut:
	edit_ti      &TextInput = unsafe { nil }
	editing      bool
	pressing     bool
	dragging     bool
	press_x      f32
	press_value  f64
	hovered      bool
	saved_cursor voidptr
	focus_anim   Anim = Anim{
		role:    .focus
		epsilon: 0.02
	}
}

// NumberFieldConfig - параметры number_field (остальные поля - присваиванием).
@[params]
pub struct NumberFieldConfig {
pub:
	value  f64
	min    f64 = -1.0e30
	max    f64 = 1.0e30
	step   f64 = 0.1
	digits int = 2
	label  string
}

// number_field создаёт поле: number_field(value: 0.5, min: 0, max: 1, step: 0.01).
pub fn number_field(cfg NumberFieldConfig) &NumberField {
	mut nf := &NumberField{
		min:    cfg.min
		max:    cfg.max
		step:   cfg.step
		digits: cfg.digits
		label:  cfg.label
	}
	nf.value = nf.clamp(cfg.value)
	return nf
}

// set_value - значение кодом (зажимается в границы). Колбэки не вызываются (см. шапку файла).
pub fn (mut nf NumberField) set_value(v f64) {
	widget_changed()
	nf.value = nf.clamp(v)
}

// set_range - новые границы (min > max меняются местами); значение зажимается в них.
pub fn (mut nf NumberField) set_range(min f64, max f64) {
	widget_changed()
	nf.min, nf.max = if min <= max { min, max } else { max, min }
	nf.value = nf.clamp(nf.value)
}

// text - значение строкой: своя format или digits знаков после запятой.
pub fn (nf &NumberField) text() string {
	if !isnil(nf.format) {
		return nf.format(nf.value)
	}
	return nf_format(nf.value, nf.digits)
}

// is_dragging - поле сейчас тянут мышью (для зеркальных виджетов: приложение может вести правку
// протяжкой как перетаскивание своего ползунка - без пересчёта на каждом шаге, итог - в on_commit).
pub fn (nf &NumberField) is_dragging() bool {
	return nf.dragging
}

// is_editing - открыт ввод числа с клавиатуры.
pub fn (nf &NumberField) is_editing() bool {
	return nf.editing
}

// owns_focus - фокус у внутреннего поля ввода: клавиши ему доставляются через поле
// (FocusOwner, event_route.v).
pub fn (nf &NumberField) owns_focus(ptr voidptr) bool {
	return !isnil(nf.edit_ti) && voidptr(nf.edit_ti) == ptr
}

fn (nf &NumberField) clamp(v f64) f64 {
	if nf.min >= nf.max {
		return v
	}
	return if v < nf.min {
		nf.min
	} else if v > nf.max {
		nf.max
	} else {
		v
	}
}

// bounded - заданы обе границы (иначе полоски доли нет).
fn (nf &NumberField) bounded() bool {
	return nf.min > -1.0e29 && nf.max < 1.0e29 && nf.max > nf.min
}

// nf_format - число с digits (0..6) знаками после запятой.
fn nf_format(v f64, digits int) string {
	return match clamp_int(digits, 0, 6) {
		0 { '${v:.0f}' }
		1 { '${v:.1f}' }
		2 { '${v:.2f}' }
		3 { '${v:.3f}' }
		4 { '${v:.4f}' }
		5 { '${v:.5f}' }
		else { '${v:.6f}' }
	}
}

// nf_edit_text - число для поля ввода: digits знаков после запятой без хвостовых нулей («1.50» ->
// «1.5», «2.00» -> «2»), минус ноль - «0». Короче набирать поверх и видно, что значение круглое.
fn nf_edit_text(v f64, digits int) string {
	mut s := nf_format(v, digits)
	if s.contains('.') {
		s = s.trim_right('0').trim_right('.')
	}
	if s == '-0' {
		s = '0'
	}
	return s
}

// nf_number_prefix - строка годится как (недописанное) число: знак в начале, цифры, одна точка
// или запятая. Фильтр ввода внутреннего поля (TextInput.accept).
fn nf_number_prefix(s string) bool {
	mut sep := false
	for i, c in s {
		if (c == `-` || c == `+`) && i == 0 {
			continue
		}
		if c == `.` || c == `,` {
			if sep {
				return false
			}
			sep = true
			continue
		}
		if !c.is_digit() {
			return false
		}
	}
	return true
}

// nf_parse - введённое число (запятая = точка); none - не число (пусто, одинокий знак).
fn nf_parse(s string) ?f64 {
	t := s.trim_space().replace(',', '.')
	if !nf_number_prefix(t) || !t.bytes().any(it.is_digit()) {
		return none
	}
	return strconv.atof64(t) or { return none }
}

// change - новое значение от пользователя: зажать, и если изменилось - on_change.
fn (mut nf NumberField) change(v f64) {
	nv := nf.clamp(v)
	if nv == nf.value {
		return
	}
	widget_changed()
	nf.value = nv
	if !isnil(nf.on_change) {
		nf.on_change(nv)
	}
}

fn (nf &NumberField) commit() {
	if !isnil(nf.on_commit) {
		nf.on_commit(nf.value)
	}
}

// ─── Рисование ─────────────────────────────────────────

pub fn (mut nf NumberField) draw(mut ctx RenderContext) {
	if !nf.visible {
		return
	}
	en := ctx.is_enabled(nf.enabled)
	if en {
		ctx.focus.register_number_field(&nf, nf.focus_group)
	} else {
		ctx.focus_block(&nf)
	}
	nf.focused = ctx.focus.is_focused(&nf) || (nf.editing && !isnil(nf.edit_ti)
		&& nf.edit_ti.focused)
	// Щелчок по другому виджету снял фокус с поля ввода - применить введённое
	if nf.editing && !isnil(nf.edit_ti) && !nf.edit_ti.focused {
		nf.commit_edit()
	}
	target := if nf.focused && en { f32(1) } else { f32(0) }
	if nf.focus_anim.update(target, ctx) {
		ctx.mark_anim_rect('number-field', nf.bounds.expanded(4))
	}
	b := nf.bounds
	rad := ctx.theme.border_radius
	if nf.editing && !isnil(nf.edit_ti) {
		mut ti := nf.edit_ti
		ti.bounds = b
		ti.draw(mut ctx)
		return
	}
	mut bg := ctx.theme.input_bg
	if en && (nf.hovered || nf.dragging) {
		bg = bg.brighten(0.06)
	}
	ctx.fill_rounded_rect(b, bg, rad)
	if nf.show_fill && nf.bounded() {
		frac := f32((nf.value - nf.min) / (nf.max - nf.min))
		fill := ctx.theme.accent.with_alpha(if en { u8(90) } else { u8(40) })
		ctx.fill_rounded_rect(Rect{b.x, b.y, b.w * clamp_f32(frac, 0, 1), b.h}, fill, rad)
	}
	border := if nf.focused && en { ctx.theme.input_focus } else { ctx.theme.input_border }
	ctx.draw_rounded_rect(b, border, rad)
	ctx.draw_focus_ring(b.expanded(2), rad + 2, nf.focus_anim.value)
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	ty := b.y + (b.h - fh) * 0.5
	pad := ctx.css_pad_of(&nf, 8)
	tc := if en { ctx.theme.text_primary } else { ctx.theme.text_disabled }
	val := nf.text()
	vw := ctx.measure_text_with_font(val, font).x
	inner_w := b.w - pad.left - pad.right
	if nf.label != '' {
		// Подпись слева, значение справа (подпись уступает место значению)
		name := bc_truncate_text(ctx, nf.label, inner_w - vw - 8, font)
		ctx.draw_text_with_font(name, b.x + pad.left, ty, ctx.theme.text_secondary, font)
		ctx.draw_text_with_font(val, b.x + b.w - pad.right - vw, ty, tc, font)
		return
	}
	shown := bc_truncate_text(ctx, val, inner_w, font)
	sw := ctx.measure_text_with_font(shown, font).x
	x := match nf.align {
		.left { b.x + pad.left }
		.center { b.x + (b.w - sw) * 0.5 }
		.right { b.x + b.w - pad.right - sw }
	}
	ctx.draw_text_with_font(shown, x, ty, tc, font)
}

// ─── Ввод с клавиатуры ─────────────────────────────────

// start_edit - внутреннее поле ввода поверх виджета: текущее значение числом (nf_edit_text: digits
// знаков без хвостовых нулей, без format - в поле то, что можно ввести), выделено целиком, фокус -
// ему.
pub fn (mut nf NumberField) start_edit(app &App) {
	if nf.editing {
		return
	}
	widget_changed()
	if isnil(nf.edit_ti) {
		mut ti := text_input('')
		ti.accept = nf_number_prefix
		nf.edit_ti = ti
	}
	mut ti := nf.edit_ti
	ti.set_text(nf_edit_text(nf.value, nf.digits))
	ti.sel_a = 0
	ti.sel_b = ti.buf.len
	ti.cur = ti.buf.len
	ti.focus_group = nf.focus_group
	ti.bounds = nf.bounds
	nf.editing = true
	nf.restore_cursor()
	ctx_ptr := app.get_active_ctx()
	if !isnil(ctx_ptr) {
		mut ctx := unsafe { &RenderContext(ctx_ptr) }
		ctx.focus.focus_text_input(ti, nf.focus_group)
	}
	ti.focused = true
}

// commit_edit - применить введённое (не число - без правки) и закрыть поле.
fn (mut nf NumberField) commit_edit() {
	if !nf.editing {
		return
	}
	text := nf.edit_ti.get_text()
	nf.cancel_edit()
	v := nf_parse(text) or { return }
	nf.change(v)
	nf.commit()
}

fn (mut nf NumberField) cancel_edit() {
	if !nf.editing {
		return
	}
	widget_changed()
	nf.editing = false
	mut ti := nf.edit_ti
	ti.focused = false
}

// focus_self - фокус самому полю (после ввода и по нажатию).
fn (mut nf NumberField) focus_self(app &App) {
	ctx_ptr := app.get_active_ctx()
	if isnil(ctx_ptr) {
		return
	}
	mut ctx := unsafe { &RenderContext(ctx_ptr) }
	ctx.focus.focus_number_field(&nf, nf.focus_group)
	nf.focused = true
}

// ─── События ───────────────────────────────────────────

pub fn (mut nf NumberField) handle_event(event &GuiEvent, app &App) bool {
	if !nf.visible {
		return false
	}
	if !nf.enabled && is_input_event(event) {
		nf.pressing = false
		nf.dragging = false
		return false
	}
	// Идёт ввод: Enter - применить, Esc - отменить, щелчок мимо - применить и обработать
	// щелчок как обычно, остальное - внутреннему полю
	if nf.editing && !isnil(nf.edit_ti) {
		mut ti := nf.edit_ti
		if event.typ == .key_down && event.keycode in [sdl_k_return, sdl_k_kp_enter] {
			nf.commit_edit()
			nf.focus_self(app)
			return true
		}
		if event.typ == .key_down && event.keycode == sdl_k_escape {
			nf.cancel_edit()
			nf.focus_self(app)
			return true
		}
		if event.typ == .mouse_down {
			if nf.bounds.contains(event.mouse_x, event.mouse_y) {
				ti.handle_event(event, app)
				return true
			}
			nf.commit_edit()
			return false
		}
		if event.typ in [.key_down, .key_up, .text_input] {
			ti.handle_event(event, app)
			return true
		}
		return ti.handle_event(event, app)
	}
	match event.typ {
		.mouse_down {
			if event.mouse_btn != .left || !nf.bounds.contains(event.mouse_x, event.mouse_y) {
				return false
			}
			nf.focus_self(app)
			nf.pressing = true
			nf.dragging = false
			nf.press_x = event.mouse_x
			nf.press_value = nf.value
			return true
		}
		.mouse_move {
			if nf.pressing {
				nf.drag_to(event.mouse_x, event.shift(), event.ctrl())
				return true
			}
			nf.set_hover(nf.bounds.contains(event.mouse_x, event.mouse_y))
			return false
		}
		.mouse_up {
			if !nf.pressing || event.mouse_btn != .left {
				return false
			}
			nf.pressing = false
			if nf.dragging {
				nf.dragging = false
				nf.commit()
			} else {
				nf.start_edit(app) // щелчок без протяжки - ввод с клавиатуры
			}
			return true
		}
		.mouse_leave {
			if !nf.pressing {
				nf.set_hover(false)
			}
			return false
		}
		.key_down {
			if nf.focused {
				return nf.on_key(event, app)
			}
		}
		else {}
	}
	return false
}

// drag_to - шаг протяжки: значение от точки нажатия; fine (Shift) - в 10 раз точнее, snap (Ctrl) -
// кратно step. Пока сдвиг меньше порога - это ещё щелчок.
fn (mut nf NumberField) drag_to(x f32, fine bool, snap bool) {
	dx := x - nf.press_x
	if !nf.dragging {
		if abs_f32(dx) < nf_drag_threshold {
			return
		}
		nf.dragging = true
	}
	scale := if fine { 0.1 } else { 1.0 }
	mut v := nf.press_value + f64(dx / max_f32(nf.drag_px, 1)) * nf.step * scale
	if snap && nf.step > 0 {
		v = f64(i64(v / nf.step + if v >= 0 { 0.5 } else { -0.5 })) * nf.step
	}
	nf.change(v)
}

// on_key - стрелки вправо/вверх и влево/вниз - на step (с Shift - на десятую), Enter и F2 - ввод.
fn (mut nf NumberField) on_key(event &GuiEvent, app &App) bool {
	k := event.keycode
	delta := if event.shift() { nf.step * 0.1 } else { nf.step }
	match k {
		sdl_k_right, sdl_k_up {
			nf.change(nf.value + delta)
			nf.commit()
			return true
		}
		sdl_k_left, sdl_k_down {
			nf.change(nf.value - delta)
			nf.commit()
			return true
		}
		sdl_k_return, sdl_k_kp_enter, sdl_k_f2 {
			nf.start_edit(app)
			return true
		}
		else {}
	}
	return false
}

// set_hover - наведение: курсор «влево-вправо» (поле тянется) и подсветка.
fn (mut nf NumberField) set_hover(on bool) {
	if on == nf.hovered {
		return
	}
	nf.hovered = on
	if on {
		if nf.saved_cursor == unsafe { nil } {
			nf.saved_cursor = current_cursor()
		}
		set_cursor(sdl_system_cursor_sizewe)
	} else {
		nf.restore_cursor()
	}
}

fn (mut nf NumberField) restore_cursor() {
	if nf.saved_cursor != unsafe { nil } {
		restore_cursor_handle(nf.saved_cursor)
		nf.saved_cursor = unsafe { nil }
	}
}
