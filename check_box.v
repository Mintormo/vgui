module vgui

// ═══════════════════════════════════════════════════════
// CheckBox - флажок с подписью (kind_check_box).
//
// Связи с остальной библиотекой:
//   - фокус: в draw() регистрируется в ctx.focus (register_checkbox) с
//     focus_group, поэтому Tab обходит флажки в порядке отрисовки (focus.v);
//   - события: клик срабатывает по отпусканию кнопки (PROJECT.md, "Клик
//     срабатывает по отпусканию"), клавиши Space/Enter переключают при фокусе;
//   - анимации: фокус-кольцо и галочка идут через Anim (anim.v), кадр просится
//     точечно - mark_anim_rect по bounds, чтобы не перерисовывать всё окно;
//   - раскладка: bounds выставляет контейнер (Layouted в widget_tree.v).
// ═══════════════════════════════════════════════════════

// CheckBox - флажок. checked меняет toggle()/set_checked(); on_change зовётся
// только из toggle() (то есть по действию пользователя), set_checked() колбэк
// не вызывает.
@[heap]
pub struct CheckBox {
pub mut:
	type_tag    int = kind_check_box // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	text        string
	checked     bool
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	hovered     bool
	focus_anim  Anim = anim_role(.focus)
	check_anim  Anim = anim_role(.toggle)
	pressed     bool // левая кнопка нажата над виджетом; действие - по mouse_up
	focus_group int
	box_size    f32       = 18
	gap         f32       = 8
	on_change   fn (bool) = unsafe { nil }
}

// checkbox создаёт флажок с подписью text (изначально снят, включён, виден).
pub fn checkbox(text string) &CheckBox {
	return &CheckBox{
		text: text
	}
}

pub fn (cb &CheckBox) is_checked() bool {
	return cb.checked
}

// set_checked выставляет состояние программно: on_change НЕ вызывается,
// окно перерисуется само (widget_changed).
pub fn (mut cb CheckBox) set_checked(v bool) {
	widget_changed()
	cb.checked = v
}

// toggle инвертирует флажок и вызывает on_change(новое_значение), если он задан.
pub fn (mut cb CheckBox) toggle() {
	cb.checked = !cb.checked
	if cb.on_change != unsafe { nil } {
		cb.on_change(cb.checked)
	}
}

// box_rect - квадрат самого флажка: прижат к левому краю bounds (отступ 2 px)
// и центрирован по вертикали; подпись рисуется правее него.
fn (cb &CheckBox) box_rect() Rect {
	cy := cb.bounds.y + (cb.bounds.h - cb.box_size) * 0.5
	return Rect{cb.bounds.x + 2, cy, cb.box_size, cb.box_size}
}

// draw рисует флажок: регистрация в фокус-учёте, шаг анимаций фокуса и
// галочки, фон (с подмешиванием hover-цвета), рамка, фокус-кольцо, галочка
// из двух линий (размер пропорционален check_anim.value - "вырастает"), текст.
pub fn (mut cb CheckBox) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(cb.enabled)
	if !cb.visible {
		return
	}
	if !ctx.is_in_clip(cb.bounds) {
		return
	}

	if en {
		ctx.focus.register_checkbox(&cb, cb.focus_group)
	} else {
		ctx.focus_block(&cb)
	}

	is_focused := ctx.focus.is_focused(unsafe { &cb })
	target_focus := if is_focused && en { f32(1.0) } else { f32(0.0) }
	mut animating := cb.focus_anim.update(target_focus, ctx)

	target_check := if cb.checked { f32(1.0) } else { f32(0.0) }
	animating = cb.check_anim.update(target_check, ctx) || animating

	// Mark animation only when not yet settled (о mark_anim_rect — см.
	// button.v: анимация не выходит за bounds, полный кадр ради неё
	// обнулял бы точечную инвалидацию hover).
	if animating {
		ctx.mark_anim_rect('checkbox', cb.bounds)
	}

	br := cb.box_rect()
	rad := max_f32(ctx.theme.border_radius * 0.5, 3)

	// Порог 0.5 по check_anim.value: цвет фона/рамки переключается на "включён"
	// на середине анимации галочки, а не мгновенно при смене checked.
	bg := if !en {
		ctx.theme.button_disabled_bg
	} else if cb.check_anim.value > 0.5 {
		ctx.theme.eff_chk_bg_checked().blend(ctx.theme.accent_hover, if cb.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	} else {
		ctx.theme.eff_chk_bg().blend(ctx.theme.button_hover, if cb.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	}
	ctx.fill_rounded_rect(br, bg, rad)

	bc := if cb.check_anim.value > 0.5 {
		ctx.theme.eff_chk_bg_checked()
	} else {
		ctx.theme.eff_chk_border().blend(ctx.theme.eff_chk_bg_checked(), cb.focus_anim.value * 0.5)
	}
	ctx.draw_rounded_rect(br, bc, rad)

	// expanded(4) so the inset ring lands at the original expanded(2) geometry
	ctx.draw_focus_ring(br.expanded(4), rad + 4, cb.focus_anim.value)

	if cb.check_anim.value > 0.05 {
		cc := if en { ctx.theme.eff_chk_mark() } else { ctx.theme.text_disabled }
		cx := br.x + br.w * 0.5
		cy := br.y + br.h * 0.5
		s := br.w * 0.3 * cb.check_anim.value
		ctx.draw_line_thick(cx - s, cy, cx - s * 0.3, cy + s * 0.7, 2, cc)
		ctx.draw_line_thick(cx - s * 0.3, cy + s * 0.7, cx + s, cy - s * 0.5, 2, cc)
	}

	if cb.text.len > 0 {
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		tx := br.x + br.w + cb.gap
		ty := cb.bounds.y + (cb.bounds.h - fh) * 0.5
		tc := if en { ctx.theme.text_primary } else { ctx.theme.text_disabled }
		ctx.push_clip(cb.bounds)
		ctx.draw_text_with_font(cb.text, tx, ty, tc, font)
		ctx.pop_clip()
	}
}

// handle_event обрабатывает мышь и клавиатуру. Возвращает true, если событие
// поглощено. mouse_move только обновляет hovered (и отменяет нажатие при уходе
// курсора); mouse_down фокусирует и взводит pressed; mouse_up над виджетом
// переключает; Tab двигает фокус; Space/Enter переключают, если флажок в фокусе.
pub fn (mut cb CheckBox) handle_event(event &GuiEvent, app &App) bool {
	if !cb.visible || !cb.enabled {
		return false
	}

	match event.typ {
		.mouse_leave {
			// курсор ушёл с виджета (event_route.v) - как движение за его пределы
			cb.hovered = false
			cb.pressed = false
		}
		.mouse_move {
			cb.hovered = cb.bounds.contains(event.mouse_x, event.mouse_y)
			if !cb.hovered {
				cb.pressed = false
			}
		}
		// Как у Button: нажатие только фокусирует, переключение - по
		// отпусканию над виджетом. Тяжёлый on_change не выполняется, пока
		// кнопка зажата, а увод курсора с виджета отменяет клик.
		.mouse_down {
			if event.mouse_btn == .left && cb.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_checkbox(&cb, cb.focus_group)
				}
				cb.pressed = true
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && cb.pressed {
				cb.pressed = false
				if cb.hovered {
					cb.toggle()
				}
				return true
			}
		}
		.key_down {
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				if ctx_mut.focus.is_focused(unsafe { &cb }) {
					if event.keycode == sdl_k_tab {
						ctx_mut.focus.tab(event.shift())
						return true
					}
					if event.keycode == sdl_k_space || event.keycode == sdl_k_return {
						cb.toggle()
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
