module vgui

// ═══════════════════════════════════════════════════════
// RadioButton — mutually exclusive selection within a group
//
// Radio buttons with the same `radio_group` string
// are mutually exclusive. Setting one deselects others
// that share the same radio_group and have been registered
// in the same FocusManager (i.e. same window).
// ═══════════════════════════════════════════════════════
//
// Как это устроено. Отдельного объекта «группа» нет: группа — это просто
// строка radio_group. Список соседей берётся из фокус-учёта активного окна
// (ctx.focus.entries, focus.v): каждый RadioButton регистрируется там в
// draw(), поэтому при выборе select_in_group перебирает записи kind
// .radio_button и снимает выбор с тех, у кого та же radio_group.
// Следствие: кнопка, которая ещё ни разу не рисовалась включённой (enabled)
// в этом окне, в учёте отсутствует, и select_in_group её не сбросит.
//
// Раскладка: размер считает measure() в layout_measure.v; виджет рисует
// кружок слева (circle_size) и подпись справа через отступ gap.
// Клик срабатывает по отпусканию кнопки мыши — PROJECT.md, «Клик
// срабатывает по отпусканию». Анимации фокуса и выбора — через Anim
// (anim.v), перерисовка только своего прямоугольника (mark_anim_rect).

// RadioButton — одна радиокнопка. Взаимоисключение с соседями задаёт
// radio_group (см. шапку файла).
@[heap]
pub struct RadioButton {
pub mut:
	type_tag    int = kind_radio_button // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	text        string
	selected    bool
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	hovered     bool
	focus_anim  Anim = anim_smooth(anim_tau_focus)  // 0→1: кольцо фокуса и подсветка рамки
	sel_anim    Anim = anim_smooth(anim_tau_toggle) // 0→1: радиус внутренней точки выбора
	pressed     bool // левая кнопка нажата над виджетом; действие - по mouse_up
	focus_group int  // группа Tab-обхода в FocusManager (не путать с radio_group)
	radio_group string    = 'default' // строковый ключ взаимоисключения, см. шапку
	circle_size f32       = 18
	gap         f32       = 8            // отступ между кружком и подписью
	on_change   fn (bool) = unsafe { nil } // true — выбрана, false — выбор снят соседом
}

// radio_button создаёт радиокнопку с подписью text в группе 'default'.
// Выбор снимается/ставится только через клик, клавиши или set_selected.
pub fn radio_button(text string) &RadioButton {
	return &RadioButton{
		text: text
	}
}

// is_selected сообщает, выбрана ли кнопка сейчас.
pub fn (rb &RadioButton) is_selected() bool {
	return rb.selected
}

// set_selected ставит флаг выбора напрямую: соседей по группе НЕ сбрасывает,
// on_change не зовёт и кадр не инвалидирует (в своём цикле зовите Window.invalidate*).
pub fn (mut rb RadioButton) set_selected(v bool) {
	rb.selected = v
}

// circle_center возвращает центр кружка: у левого края bounds, по вертикали
// посередине высоты.
fn (rb &RadioButton) circle_center() (f32, f32) {
	// +1 inset so the outer border contour doesn't get clipped by the container.
	cx := rb.bounds.x + rb.circle_size * 0.5 + 1
	cy := rb.bounds.y + rb.bounds.h * 0.5
	return cx, cy
}

// select_in_group выбирает кнопку и снимает выбор с соседей той же radio_group
// (список соседей — из фокус-учёта активного окна, см. шапку файла).
// Сначала зовётся on_change(false) у сброшенных соседей, затем on_change(true)
// у самой кнопки. Если кнопка уже выбрана — ничего не делает (on_change не зовётся).
fn (mut rb RadioButton) select_in_group(app &App) {
	if rb.selected {
		return
	}
	rb.selected = true

	// Deselect siblings — scan FocusManager for other RadioButtons in same radio_group
	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr != nil } {
		for e in ctx_ptr.focus.entries {
			if e.kind == .radio_button && e.ptr != unsafe { voidptr(&rb) } {
				mut other := unsafe { &RadioButton(e.ptr) }
				if other.radio_group == rb.radio_group && other.selected {
					other.selected = false
					if other.on_change != unsafe { nil } {
						other.on_change(false)
					}
				}
			}
		}
	}

	if rb.on_change != unsafe { nil } {
		rb.on_change(true)
	}
}

// draw рисует кружок, кольцо фокуса, точку выбора и подпись; регистрирует
// кнопку в фокус-учёте (только если enabled) и шагает анимации focus_anim/sel_anim.
pub fn (mut rb RadioButton) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(rb.enabled)
	if !rb.visible {
		return
	}
	if !ctx.is_in_clip(rb.bounds) {
		return
	}

	if en {
		ctx.focus.register_radio_button(&rb, rb.focus_group)
	} else {
		ctx.focus_block(&rb)
	}

	is_focused := ctx.focus.is_focused(unsafe { &rb })
	target_focus := if is_focused && en { f32(1.0) } else { f32(0.0) }
	mut animating := rb.focus_anim.update(target_focus, ctx)

	target_sel := if rb.selected { f32(1.0) } else { f32(0.0) }
	animating = rb.sel_anim.update(target_sel, ctx) || animating

	// Mark animation only when not yet settled (о mark_anim_rect — см. button.v)
	if animating {
		ctx.mark_anim_rect('radio', rb.bounds)
	}

	cx, cy := rb.circle_center()
	radius := rb.circle_size * 0.5

	// Outer circle
	outer_c := if !en {
		ctx.theme.button_disabled_border
	} else {
		ctx.theme.eff_rad_border().blend(ctx.theme.eff_rad_dot(), max_f32(rb.sel_anim.value,
			rb.focus_anim.value * 0.5))
	}
	bg := if !en {
		ctx.theme.button_disabled_bg
	} else {
		ctx.theme.eff_rad_bg().blend(ctx.theme.button_hover, if rb.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	}
	ctx.fill_circle(cx, cy, radius, bg)
	ctx.draw_circle(cx, cy, radius, outer_c)

	// Focus ring
	if rb.focus_anim.value > 0.05 {
		fc := ctx.theme.eff_rad_dot().brighten(0.3).with_alpha(u8(200.0 * rb.focus_anim.value))
		ctx.draw_circle(cx, cy, radius + 2, fc)
	}

	// Inner dot
	if rb.sel_anim.value > 0.05 {
		dot_r := radius * 0.45 * rb.sel_anim.value
		dc := if en { ctx.theme.eff_rad_dot() } else { ctx.theme.text_disabled }
		ctx.fill_circle(cx, cy, dot_r, dc)
	}

	// Text label
	if rb.text.len > 0 {
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		tx := rb.bounds.x + rb.circle_size + rb.gap + 1
		ty := rb.bounds.y + (rb.bounds.h - fh) * 0.5
		tc := if en { ctx.theme.text_primary } else { ctx.theme.text_disabled }
		ctx.push_clip(rb.bounds)
		ctx.draw_text_with_font(rb.text, tx, ty, tc, font)
		ctx.pop_clip()
	}
}

// handle_event обрабатывает мышь (нажатие фокусирует, отпускание над виджетом
// выбирает), Tab и Space/Enter у сфокусированной кнопки. Возвращает true, если
// событие поглощено.
pub fn (mut rb RadioButton) handle_event(event &GuiEvent, app &App) bool {
	if !rb.visible || !rb.enabled {
		return false
	}

	match event.typ {
		.mouse_move {
			rb.hovered = rb.bounds.contains(event.mouse_x, event.mouse_y)
			if !rb.hovered {
				rb.pressed = false
			}
		}
		// Как у Button: нажатие только фокусирует, переключение - по
		// отпусканию над виджетом. Тяжёлый on_change не выполняется, пока
		// кнопка зажата, а увод курсора с виджета отменяет клик.
		.mouse_down {
			if event.mouse_btn == .left && rb.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_radio_button(&rb, rb.focus_group)
				}
				rb.pressed = true
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && rb.pressed {
				rb.pressed = false
				if rb.hovered {
					rb.select_in_group(app)
				}
				return true
			}
		}
		.key_down {
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_ref := unsafe { &RenderContext(ctx_ptr) }
				if ctx_ref.focus.is_focused(unsafe { &rb }) {
					if event.keycode == sdl_k_tab {
						ctx_ref.focus.tab(event.shift())
						return true
					}
					if event.keycode == sdl_k_space || event.keycode == sdl_k_return {
						rb.select_in_group(app)
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
