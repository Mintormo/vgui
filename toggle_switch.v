module vgui

// Шапка файла.
// ToggleSwitch - переключатель «вкл/выкл» в виде таблетки с ползунком (в стиле iOS)
// и подписью справа. Состояние - булево поле on. Переключение - по клику
// (срабатывает при ОТПУСКАНИИ кнопки над виджетом, как у Button) или клавишами
// Space/Enter при фокусе.
//
// Связь с библиотекой: размер считает measure() (layout_measure.v,
// labeled_control_size - вместе с CheckBox/RadioButton); bounds выдаёт контейнер;
// фокус - FocusManager (register_toggle_switch / focus_toggle_switch); цвета -
// тема (eff_tog_*); колбэк on_change(новое_состояние); C-ABI - vgui_toggle_switch_*.
// Поля: on - текущее состояние; slide_anim - плавное движение ползунка (0 = выкл,
// 1 = вкл), им же смешиваются цвета дорожки; focus_anim - кольцо фокуса;
// pressed - левая кнопка нажата над виджетом; track_w/track_h - размеры
// дорожки-таблетки; gap - зазор между дорожкой и подписью.
@[heap]
pub struct ToggleSwitch {
pub mut:
	type_tag    int = kind_toggle_switch // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	text        string
	on          bool
	visible     bool = true
	enabled     bool = true
	hovered     bool
	focus_anim  Anim = Anim{
		tau_ms:  anim_tau_focus
		epsilon: 0.02
	}
	slide_anim  Anim = Anim{
		tau_ms:  anim_tau_hover
		epsilon: 0.02
	}
	pressed     bool // левая кнопка нажата над виджетом; действие - по mouse_up
	focus_group int
	track_w     f32       = 40
	track_h     f32       = 22
	gap         f32       = 8
	on_change   fn (bool) = unsafe { nil }
}

pub fn toggle_switch(text string) &ToggleSwitch {
	return &ToggleSwitch{
		text: text
	}
}

pub fn (ts &ToggleSwitch) is_on() bool {
	return ts.on
}

// Программно задаёт состояние: колбэк on_change НЕ вызывается, а анимация ползунка
// запустится при следующей отрисовке (кадр сам не инвалидируется).
pub fn (mut ts ToggleSwitch) set_on(v bool) {
	ts.on = v
}

// Инвертирует состояние и вызывает on_change(новое_состояние). Именно этот метод
// вызывают клик и клавиши.
pub fn (mut ts ToggleSwitch) toggle() {
	ts.on = !ts.on
	if ts.on_change != unsafe { nil } {
		ts.on_change(ts.on)
	}
}

// Прямоугольник дорожки: по вертикали по центру bounds, по горизонтали у левого края
// (со сдвигом 1 px).
fn (ts &ToggleSwitch) track_rect() Rect {
	ty := ts.bounds.y + (ts.bounds.h - ts.track_h) * 0.5
	// Inset by 1px so the outer border contour doesn't get clipped by the container.
	return Rect{ts.bounds.x + 1, ty, ts.track_w, ts.track_h}
}

// Отрисовка: регистрация в FocusManager -> обновление анимаций фокуса и ползунка
// (пока хоть одна не дошла до цели - mark_anim_rect) -> дорожка (цвет плавно переходит
// между «выкл» и «вкл», при наведении подмешивается цвет hover) -> контур ->
// кольцо фокуса -> круглый ползунок (его центр движется по линии между краями
// дорожки) -> подпись справа под клипом bounds. У выключенного (disabled) виджета
// цвета приглушены.
pub fn (mut ts ToggleSwitch) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(ts.enabled)
	if !ts.visible {
		return
	}
	if !ctx.is_in_clip(ts.bounds) {
		return
	}

	if en {
		ctx.focus.register_toggle_switch(&ts, ts.focus_group)
	} else {
		ctx.focus_block(&ts)
	}

	is_focused := ctx.focus.is_focused(unsafe { &ts })
	target_focus := if is_focused && en { f32(1.0) } else { f32(0.0) }
	mut animating := ts.focus_anim.update(target_focus, ctx)

	target_slide := if ts.on { f32(1.0) } else { f32(0.0) }
	animating = ts.slide_anim.update(target_slide, ctx) || animating

	// Mark animation only when not yet settled (о mark_anim_rect — см. button.v)
	if animating {
		ctx.mark_anim_rect('toggle', ts.bounds)
	}

	trk := ts.track_rect()
	track_rad := trk.h * 0.5

	off_c := if en {
		ctx.theme.eff_tog_track_off().blend(ctx.theme.button_hover, if ts.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	} else {
		ctx.theme.button_disabled_bg
	}
	on_c := if en {
		ctx.theme.eff_tog_track_on().blend(ctx.theme.accent_hover, if ts.hovered {
			f32(0.3)
		} else {
			f32(0)
		})
	} else {
		ctx.disabled_color(ctx.theme.eff_tog_track_on())
	}
	track_c := off_c.blend(on_c, ts.slide_anim.value)
	ctx.fill_rounded_rect(trk, track_c, track_rad)

	tbc0 := if ts.slide_anim.value > 0.5 {
		ctx.theme.eff_tog_track_on().darken(0.1)
	} else {
		ctx.theme.eff_tog_track_off()
	}
	tbc := if en { tbc0 } else { ctx.disabled_color(tbc0) }
	ctx.draw_rounded_rect(trk, tbc, track_rad)

	// expanded(4) so the inset ring lands at the original expanded(2) geometry around the pill
	ctx.draw_focus_ring(trk.expanded(4), track_rad + 4, ts.focus_anim.value)

	// Ползунок: радиус = половина высоты дорожки минус отступ thumb_pad; крайние положения
	// центра отстоят от краёв дорожки на thumb_pad + радиус, между ними интерполяция по slide_anim.
	thumb_pad := f32(2)
	thumb_r := (trk.h - thumb_pad * 2) * 0.5
	thumb_min_x := trk.x + thumb_pad + thumb_r
	thumb_max_x := trk.x + trk.w - thumb_pad - thumb_r
	thumb_cx := lerp(thumb_min_x, thumb_max_x, ts.slide_anim.value)
	thumb_cy := trk.y + trk.h * 0.5
	thumb_c := if en { ctx.theme.eff_tog_thumb() } else { ctx.theme.text_disabled }
	ctx.fill_circle(thumb_cx, thumb_cy, thumb_r, thumb_c)

	if ts.text.len > 0 {
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		tx := trk.x + trk.w + ts.gap
		ty := ts.bounds.y + (ts.bounds.h - fh) * 0.5
		tc := if en { ctx.theme.text_primary } else { ctx.theme.text_disabled }
		ctx.push_clip(ts.bounds)
		ctx.draw_text_with_font(ts.text, tx, ty, tc, font)
		ctx.pop_clip()
	}
}

// События (true = поглощено): mouse_move обновляет hovered и отменяет начатый клик,
// если мышь ушла; mouse_down по виджету берёт фокус и взводит pressed;
// mouse_up над виджетом при pressed вызывает toggle(); key_down при наличии
// фокуса: Tab - передать фокус, Space/Enter - переключить.
pub fn (mut ts ToggleSwitch) handle_event(event &GuiEvent, app &App) bool {
	if !ts.visible || !ts.enabled {
		return false
	}

	match event.typ {
		.mouse_move {
			ts.hovered = ts.bounds.contains(event.mouse_x, event.mouse_y)
			if !ts.hovered {
				ts.pressed = false
			}
		}
		// Как у Button: нажатие только фокусирует, переключение - по
		// отпусканию над виджетом. Тяжёлый on_change не выполняется, пока
		// кнопка зажата, а увод курсора с виджета отменяет клик.
		.mouse_down {
			if event.mouse_btn == .left && ts.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_toggle_switch(&ts, ts.focus_group)
				}
				ts.pressed = true
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && ts.pressed {
				ts.pressed = false
				if ts.hovered {
					ts.toggle()
				}
				return true
			}
		}
		.key_down {
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
				if ctx_mut.focus.is_focused(unsafe { &ts }) {
					if event.keycode == sdl_k_tab {
						ctx_mut.focus.tab(event.shift())
						return true
					}
					if event.keycode == sdl_k_space || event.keycode == sdl_k_return {
						ts.toggle()
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
