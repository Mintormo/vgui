module vgui

// ═══════════════════════════════════════════════════════
// Spinbox — integer input with increment/decrement buttons
//
// Features:
//   - Min/max range (integers)
//   - Step size for increment/decrement (integer)
//   - Editable text input (digits and optional leading minus only)
//   - Optional prefix/suffix text
//   - Callbacks on value change
// ═══════════════════════════════════════════════════════

// Файл spinbox.v: Spinbox - поле ввода целого числа с кнопками [-] и [+] справа. Устроен как
// составной виджет: рамку, фон и кнопки рисует сам Spinbox, а редактирование текста делегируется
// внутреннему TextInput (text_input) в "плоском" режиме. Поэтому фокус и клавиатурный ввод живут
// в text_input (Spinbox сам в фокус-менеджере не регистрируется), а Spinbox лишь подсвечивает
// рамку по состоянию text_input. Связи: раскладка - bounds выставляет контейнер, ширина текстового
// поля = ширина - 2 * высота (две квадратные кнопки со стороной = высоте); тема - eff_spinbox_*;
// анимация кольца фокуса - Anim (anim.v). Тег типа kind_spinbox - widget_tag.v.

import strconv

// Целочисленный счётчик. value всегда держится в [min, max] (set_value ограничивает); step -
// шаг кнопок и стрелок. prefix/suffix добавляются к числу в тексте (например "$" и " шт.").
// hovered_*/active_* - состояние кнопок (наведение/нажатие). on_change(value) вызывается при
// каждом изменении значения - в том числе во время набора текста.
@[heap]
pub struct Spinbox {
pub mut:
	type_tag    int = kind_spinbox // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	value       int
	min         int
	max         int  = 100
	step        int  = 1
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focus_group int
	focus_anim  Anim = Anim{
		tau_ms:  anim_tau_focus
		epsilon: 0.02
	} // animated focus ring strength (0..1)
	hovered_dec bool // hover state for decrement button
	hovered_inc bool // hover state for increment button
	active_dec  bool // pressed state for decrement button
	active_inc  bool // pressed state for increment button
	// Text input part for editing
	text_input &TextInput = unsafe { nil }
	prefix     string
	suffix     string
	on_change  fn (int) = unsafe { nil }
	// Tracks the previous focus state of the embedded text input so we
	// can normalize (clamp + reformat) the entered text exactly once,
	// on the focused→unfocused transition.
	was_ti_focused bool
}

// ─── Constructors ──────────────────────────────────────

// Создаёт Spinbox (0..100, шаг 1) с внутренним TextInput: плоский (чтобы не было скруглённого
// прямоугольника внутри скруглённого), максимум 64 символа (число плюс prefix/suffix),
// ввод проверяет accepts_text: целое с необязательным минусом, окружённое необязательными
// prefix и suffix. Колбэк text_input.on_change во время набора просто обновляет value
// без ограничения диапазоном и форматирования: ограничение посреди ввода запретило бы
// промежуточные строки вроде "" или "-"; нормализация делается при потере фокуса.
pub fn spinbox() &Spinbox {
	mut s := &Spinbox{}
	mut ti := text_input('')
	ti.max_len = 64
	// Spinbox draws its own rounded background and border; the inner
	// text input must blend in with square edges, otherwise we get a
	// rounded rectangle inside a rounded rectangle.
	ti.flat = true
	// Только целое число - но текст поля включает prefix/suffix ("$5", "5 шт."),
	// поэтому регулярное выражение по всей строке не годится (оно отклоняло любой
	// ввод при заданном префиксе): кандидат проверяет accepts_text.
	ti.accept = fn [s] (candidate string) bool {
		return s.accepts_text(candidate)
	}
	// While the user is typing, just track the parsed value without
	// clamping or reformatting — clamping during entry would block
	// transitional strings like "" or "-" before the user types the
	// rest of the number. Normalization happens on blur.
	ti.on_change = fn [mut s] (txt string) {
		num := s.number_part(txt)
		if num.len == 0 || num == '-' {
			return
		}
		val := strconv.atoi(num) or { return }
		s.value = val
		if s.on_change != unsafe { nil } {
			s.on_change(s.value)
		}
	}
	s.text_input = ti
	s.update_text_input()
	return s
}

// ─── Internal ──────────────────────────────────────────

// Прямоугольники кнопок (уменьшение, увеличение): две квадратные кнопки со стороной = высоте
// виджета у правого края. (Имя "init_" историческое - функция ничего не инициализирует.)
fn (mut s Spinbox) init_buttons_bounds() (Rect, Rect) {
	btn_w := s.bounds.h
	dec_r := Rect{s.bounds.x + s.bounds.w - btn_w * 2, s.bounds.y, btn_w, s.bounds.h}
	inc_r := Rect{s.bounds.x + s.bounds.w - btn_w, s.bounds.y, btn_w, s.bounds.h}
	return dec_r, inc_r
}

// number_part - числовая часть текста поля: без prefix в начале и suffix в конце (каждый
// снимается, только если он действительно там стоит) и без пробелов по краям.
fn (s &Spinbox) number_part(txt string) string {
	mut t := txt
	if s.prefix.len > 0 && t.starts_with(s.prefix) {
		t = t[s.prefix.len..]
	}
	if s.suffix.len > 0 && t.ends_with(s.suffix) {
		t = t[..t.len - s.suffix.len]
	}
	return t.trim_space()
}

// accepts_text - допустим ли текст поля во время набора: числовая часть пуста, "-" или
// целое с необязательным ведущим минусом. Промежуточные "" и "-" разрешены, иначе
// поле нельзя было бы очистить и набрать отрицательное число.
fn (s &Spinbox) accepts_text(txt string) bool {
	num := s.number_part(txt)
	digits := if num.starts_with('-') { num[1..] } else { num }
	for c in digits {
		if !c.is_digit() {
			return false
		}
	}
	return true
}

// Текст для поля: prefix + число + suffix.
fn (s &Spinbox) format_value() string {
	return '${s.prefix}${s.value}${s.suffix}'
}

// Синхронизирует текст поля со значением; set_text вызывается только при расхождении, чтобы
// не сбрасывать курсор и выделение лишний раз.
fn (mut s Spinbox) update_text_input() {
	if s.text_input != unsafe { nil } {
		txt := s.format_value()
		if txt != s.text_input.get_text() {
			mut ti := unsafe { s.text_input }
			ti.set_text(txt)
		}
	}
}

// ─── Drawing ───────────────────────────────────────────

// Порядок: анимация кольца фокуса (по фокусу text_input) -> фон -> рамка (цвет input_focus при
// фокусе) -> кольцо фокуса -> внутренний TextInput (ему здесь же назначаются bounds, т.е. раскладка
// дочернего поля делается прямо в draw) -> подсветка нажатых/наведённых кнопок в клипе по общей
// форме -> знаки "-" и "+" линиями.
pub fn (mut s Spinbox) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(s.enabled)
	if !s.visible {
		return
	}
	if !ctx.is_in_clip(s.bounds) {
		return
	}

	rad := ctx.theme.border_radius

	// Animated focus ring strength — real focus lives on the embedded
	// text input, not on Spinbox itself (see `focused` field removal note).
	ti_has_focus := s.text_input != unsafe { nil } && unsafe { s.text_input.focused }
	target_focus := if ti_has_focus && en { f32(1.0) } else { f32(0.0) }
	if s.focus_anim.update(target_focus, ctx) {
		// mark_anim_rect — см. button.v; кольцо фокуса рисуется внутрь bounds.
		ctx.mark_anim_rect('spinbox', s.bounds)
	}

	// Background
	bg := if en {
		ctx.theme.eff_spinbox_bg()
	} else {
		ctx.theme.eff_spinbox_bg().darken(0.1)
	}
	ctx.fill_rounded_rect(s.bounds, bg, rad)

	// Border
	bc := if ti_has_focus {
		ctx.theme.input_focus
	} else {
		ctx.theme.eff_spinbox_border()
	}
	ctx.draw_rounded_rect(s.bounds, bc, rad)

	// Focus ring
	ctx.draw_focus_ring_edge(s.bounds, rad, s.focus_anim.value)

	// Draw text input
	mut ti := unsafe { s.text_input }
	if ti != unsafe { nil } {
		ti.bounds = Rect{s.bounds.x, s.bounds.y, s.bounds.w - s.bounds.h * 2, s.bounds.h}
		// Поле внутри неактивного Spinbox - тоже неактивно: серый текст, вне Tab-обхода
		ctx.begin_disabled(s.enabled)
		ti.draw(mut ctx)
		ctx.end_disabled(s.enabled)
	}

	// Draw buttons [+] and [-]
	dec_rect, inc_rect := s.init_buttons_bounds()

	// Flat buttons: no permanent background or border. We only paint a
	// subtle overlay on hover/press so the buttons feel responsive but
	// stay visually merged with the Spinbox surface.
	transparent := Color{0, 0, 0, 0}
	dec_bg := if !en {
		transparent
	} else if s.active_dec {
		ctx.theme.button_pressed
	} else if s.hovered_dec {
		ctx.theme.eff_spinbox_btn_hover()
	} else {
		transparent
	}

	inc_bg := if !en {
		transparent
	} else if s.active_inc {
		ctx.theme.button_pressed
	} else if s.hovered_inc {
		ctx.theme.eff_spinbox_btn_hover()
	} else {
		transparent
	}

	// Clip to the outer rounded shape so the hover/press overlay never
	// pokes past the rounded edge when the widget is small.
	ctx.push_clip(s.bounds)
	if dec_bg.a > 0 {
		ctx.fill_rect(dec_rect, dec_bg)
	}
	if inc_bg.a > 0 {
		ctx.fill_rect(inc_rect, inc_bg)
	}
	ctx.pop_clip()

	sign_c := if en { ctx.theme.eff_spinbox_text() } else { ctx.theme.text_disabled }
	// Draw minus sign
	mx := dec_rect.x + dec_rect.w * 0.5
	my := dec_rect.y + dec_rect.h * 0.5
	sign_size := dec_rect.h * 0.4
	ctx.draw_line(mx - sign_size * 0.5, my, mx + sign_size * 0.5, my, sign_c)

	// Draw plus sign
	px := inc_rect.x + inc_rect.w * 0.5
	py := inc_rect.y + inc_rect.h * 0.5
	ctx.draw_line(px - sign_size * 0.5, py, px + sign_size * 0.5, py, sign_c)
	ctx.draw_line(px, py - sign_size * 0.5, px, py + sign_size * 0.5, sign_c)
}

// ─── Events ────────────────────────────────────────────

// События. Кнопки "нажимаются" по паре mouse_down/mouse_up: на down запоминается active_dec/inc,
// шаг выполняется на up (отпускание может быть и вне кнопки - состояние сбрасывается всегда).
// Остальное делегируется text_input. Клавиши при фокусе в поле: Up/Down - шаг, Home/End -
// min/max, Tab/Escape - управление фокусом. Потеря фокуса полем (переход true -> false)
// запускает normalize_text() ровно один раз. Возвращает true для событий над кнопками и когда
// событие обработал text_input.
pub fn (mut s Spinbox) handle_event(event &GuiEvent, app &App) bool {
	if !s.visible || !s.enabled {
		return false
	}

	ctx_ptr := app.get_active_ctx()
	// Внутреннее поле получает событие ровно один раз (ti_handled - его ответ). Раньше
	// в конце метода оно звалось ещё раз, и mouse_move/mouse_down доходили до поля дважды.
	mut ti_handled := false

	match event.typ {
		.mouse_move {
			dec_rect, inc_rect := s.init_buttons_bounds()
			s.hovered_dec = dec_rect.contains(event.mouse_x, event.mouse_y)
			s.hovered_inc = inc_rect.contains(event.mouse_x, event.mouse_y)

			if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
				mut ti := unsafe { s.text_input }
				ti_handled = ti.handle_event(event, app)
			}
		}
		.mouse_down {
			if event.mouse_btn == .left {
				dec_rect, inc_rect := s.init_buttons_bounds()
				if dec_rect.contains(event.mouse_x, event.mouse_y) {
					s.active_dec = true
					return true
				}
				if inc_rect.contains(event.mouse_x, event.mouse_y) {
					s.active_inc = true
					return true
				}
				if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
					mut ti := unsafe { s.text_input }
					ti_handled = ti.handle_event(event, app)
				}
			} else if s.text_input != unsafe { nil } {
				mut ti := unsafe { s.text_input }
				ti_handled = ti.handle_event(event, app)
			}
		}
		.mouse_up {
			if event.mouse_btn == .left {
				// handled - отпускание кнопки, начатое нажатием на [-]/[+]: событие поглощаем.
				handled := s.active_dec || s.active_inc
				// Commit any text the user typed but never blurred. If
				// the typed value was out of range, clamping it counts
				// as the user action — don't ALSO step. Stepping only
				// happens when the typed value was already valid (or
				// the field hadn't been edited).
				// Переменная названа по смыслу "значение было принудительно исправлено при коммите текста".
				mut stepped_value_was_clamped := false
				if handled {
					before := s.value
					s.normalize_text()
					if s.value != before {
						stepped_value_was_clamped = true
					}
				}
				if !stepped_value_was_clamped {
					if s.active_dec && s.value > s.min {
						s.set_value(s.value - s.step)
					}
					if s.active_inc && s.value < s.max {
						s.set_value(s.value + s.step)
					}
				}
				s.active_dec = false
				s.active_inc = false

				if unsafe { ctx_ptr != nil } && s.text_input != unsafe { nil } {
					mut ti := unsafe { s.text_input }
					ti.handle_event(event, app)
				}

				return handled
			}
			if s.text_input != unsafe { nil } {
				mut ti := unsafe { s.text_input }
				ti_handled = ti.handle_event(event, app)
			}
		}
		.key_down {
			if unsafe { ctx_ptr != nil } {
				mut ti := unsafe { s.text_input }
				if ti != unsafe { nil } && ti.handle_event(event, app) {
					ti_handled = true
				}
			}
			if !ti_handled && unsafe { ctx_ptr != nil } {
				if s.text_input != unsafe { nil } && unsafe { s.text_input.focused } {
					match event.keycode {
						sdl_k_up {
							s.set_value(s.value + s.step)
							return true
						}
						sdl_k_down {
							s.set_value(s.value - s.step)
							return true
						}
						sdl_k_home {
							s.set_value(s.min)
							return true
						}
						sdl_k_end {
							s.set_value(s.max)
							return true
						}
						sdl_k_tab {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.tab(event.shift())
							return true
						}
						sdl_k_escape {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							ctx_mut.focus.blur_current()
							return true
						}
						else {}
					}
				}
			}
		}
		else {
			// Остальное (ввод текста, двойной клик, колесо...) - полю как есть.
			if s.text_input != unsafe { nil } {
				mut ti := unsafe { s.text_input }
				ti_handled = ti.handle_event(event, app)
			}
		}
	}

	// Detect focused→unfocused on the embedded text input and run a
	// one-shot normalization (clamp into [min, max] + reformat). Doing
	// it only on blur means the field is not rewritten on every key
	// press, so the caret and selection are preserved while typing.
	if s.text_input != unsafe { nil } {
		ti_focused := unsafe { s.text_input.focused }
		if s.was_ti_focused && !ti_focused {
			s.normalize_text()
		}
		s.was_ti_focused = ti_focused
	}

	// Наведение на кнопки поглощает только само движение мыши; раньше при курсоре над
	// кнопками поглощалось любое событие, в том числе горячие клавиши окна.
	return ti_handled || (event.typ == .mouse_move && (s.hovered_dec || s.hovered_inc))
}

// normalize_text clamps the parsed value into [min, max] and rewrites
// the text input so it matches `format_value()`. Called on blur so that
// half-typed strings like "" or "-" are never persisted.
fn (mut s Spinbox) normalize_text() {
	if s.text_input == unsafe { nil } {
		return
	}
	num := s.number_part(unsafe { s.text_input.get_text() })
	mut v := s.value
	if num.len == 0 || num == '-' {
		v = s.min
	} else {
		v = strconv.atoi(num) or { s.value }
	}
	s.set_value(v)
	s.update_text_input()
}

// ─── Public API ────────────────────────────────────────

pub fn (s &Spinbox) get_value() int {
	return s.value
}

// Задаёт значение с ограничением [min, max]. Если значение изменилось - обновляет текст и
// вызывает on_change; если нет (в том числе после ограничения до прежнего) - ничего не делает.
pub fn (mut s Spinbox) set_value(v int) {
	mut clamped := v
	if clamped < s.min {
		clamped = s.min
	}
	if clamped > s.max {
		clamped = s.max
	}
	if clamped != s.value {
		s.value = clamped
		if s.text_input != unsafe { nil } {
			s.update_text_input()
		}
		if s.on_change != unsafe { nil } {
			s.on_change(s.value)
		}
	}
}

// min > max меняются местами — так же, как в Slider.set_range.
// Текущее значение подтягивается в новый диапазон через set_value, поэтому on_change
// вызывается, если значение пришлось изменить.
pub fn (mut s Spinbox) set_range(min int, max int) {
	s.min = if min <= max { min } else { max }
	s.max = if min <= max { max } else { min }
	if s.value < s.min {
		s.set_value(s.min)
	}
	if s.value > s.max {
		s.set_value(s.max)
	}
}

// Шаг должен быть положительным; нулевой и отрицательный игнорируются.
pub fn (mut s Spinbox) set_step(step int) {
	if step > 0 {
		s.step = step
	}
}

// Префикс и суффикс текста (например единицы измерения); поле обновляется сразу.
pub fn (mut s Spinbox) set_prefix(p string) {
	s.prefix = p
	if s.text_input != unsafe { nil } {
		s.update_text_input()
	}
}

pub fn (mut s Spinbox) set_suffix(suf string) {
	s.suffix = suf
	if s.text_input != unsafe { nil } {
		s.update_text_input()
	}
}
