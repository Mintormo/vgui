module vgui

// ═══════════════════════════════════════════════════════
// Button — clickable button widget with optional icon
//
// Modes:
//   - Normal (momentary): click fires on_click
//   - Toggle (toggle=true): click toggles active state,
//     fires on_toggle(bool); visually stays pressed when active
//
// Icon support:
//   - icon_path: file icon (png, svg, webp via SDL2_image)
//   - icon_text: text-based icon (emoji/symbol prefix)
//   - icon_name: имя глифа из встроенного шрифта Lucide (icon.v)
//
// Связи с остальной библиотекой:
//   - фокус: draw() регистрирует кнопку в ctx.focus (register_button) в
//     группе focus_group, если кнопка enabled и не no_focus (focus.v);
//   - события: клик срабатывает по ОТПУСКАНИЮ над кнопкой, нажатие только
//     фокусирует и взводит pressed (PROJECT.md, "Клик срабатывает по
//     отпусканию"); Space/Enter при фокусе активируют кнопку;
//   - анимации: четыре Anim (hover/press/focus/active, anim.v); кадр просится
//     точечно через mark_anim_rect(bounds) (PROJECT.md, "Анимации" и
//     "Инвалидация и dirty regions");
//   - раскладка: размер кнопки считает measure() в layout_measure.v, bounds
//     выставляет контейнер (Layouted, widget_tree.v).
// ═══════════════════════════════════════════════════════

// ButtonStyle - цветовая схема кнопки (фон/текст/рамка берутся из темы):
// normal - обычная; accent - залитая акцентным цветом; outline - только
// рамка акцента; flat - без фона и рамки до наведения; danger/success -
// красная/зелёная заливка с белым текстом.
pub enum ButtonStyle {
	normal
	accent
	outline
	flat
	danger
	success
}

// Button - кнопка: обычная (momentary) или переключаемая (toggle).
// Содержимое рисуется в порядке приоритета иконок: icon_name (Lucide) >
// icon_path (файл) > icon_text (эмодзи-префикс) > только текст.
// @[heap], как у остальных виджетов: на кнопку ссылаются по адресу (дерево виджетов,
// фокус-учёт, реестр моста), значение на стеке оставило бы висячий указатель.
@[heap]
pub struct Button {
pub mut:
	type_tag int = kind_button // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	text     string
	style    ButtonStyle = .normal
	visible  bool        = true
	enabled  bool        = true
	hovered  bool
	pressed  bool
	// Toggle mode
	toggle    bool // if true, button works as toggle (push on/push off)
	active    bool // current toggle state (true = pressed/on)
	on_toggle fn (bool) = unsafe { nil } // called when toggle state changes
	// Icon from file (png, svg, webp)
	icon_path string // path to icon file; "" = no icon
	icon_size f32 = 16 // icon width/height in logical pixels
	icon_gap  f32 = 6  // gap between icon and text
	// Icon from the embedded Lucide icon font (see icon.v / icon_names.v).
	// Takes priority over icon_path/icon_text when set. icon_size/icon_gap
	// are shared with the file-icon path above.
	icon_name string
	// Legacy: text-based icon (emoji/symbol prefix)
	icon_text string
	// tooltip - всплывающая подсказка ("" - без подсказки). Поле есть у всех
	// виджетов; показывает подсказку окно (tooltip_manager.v), сама кнопка её
	// не рисует.
	tooltip      string
	dnd          &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	radius       f32       = -1           // < 0 - брать радиус из темы (eff_radius)
	border_width f32       = 1
	font_style   FontStyle = .regular
	font_size    int // 0 - размер по умолчанию
	on_click     fn () = unsafe { nil }
	// Animation: значения 0..1, двигаются в draw() через Anim.update
	hover_anim  Anim
	press_anim  Anim = anim_role(.press)
	focus_anim  Anim = anim_role(.focus)
	active_anim Anim // smooth animation for toggle active state
	focus_group int
	no_focus    bool // if true, button is excluded from focus chain and focus
}

// ─── Constructors ──────────────────────────────────────

// button - обычная кнопка с текстом.
pub fn button(text string) &Button {
	return &Button{
		text: text
	}
}

// button_with_icon - кнопка с текстом и иконкой из файла (icon_path).
pub fn button_with_icon(text string, icon_path string) &Button {
	return &Button{
		text:      text
		icon_path: icon_path
	}
}

// icon_button - кнопка только с иконкой из файла (без текста).
pub fn icon_button(icon_path string) &Button {
	return &Button{
		icon_path: icon_path
	}
}

// icon_button_sized - то же, но с заданным размером иконки (логические px).
pub fn icon_button_sized(icon_path string, icon_size f32) &Button {
	return &Button{
		icon_path: icon_path
		icon_size: icon_size
	}
}

// Toggle button constructors: кнопка-переключатель (toggle = true)
pub fn toggle_button(text string) &Button {
	return &Button{
		text:   text
		toggle: true
	}
}

pub fn toggle_button_with_icon(text string, icon_path string) &Button {
	return &Button{
		text:      text
		icon_path: icon_path
		toggle:    true
	}
}

// ─── Public helpers ────────────────────────────────────

// is_active - состояние toggle-кнопки (у обычной кнопки поле не используется).
pub fn (b &Button) is_active() bool {
	return b.active
}

// set_text меняет надпись кнопки; окно перерисуется само (widget_changed) -
// в отличие от прямого присваивания поля text.
pub fn (mut b Button) set_text(text string) {
	widget_changed()
	b.text = text
}

// set_active ставит состояние toggle программно: on_toggle НЕ вызывается,
// окно перерисуется само (widget_changed).
pub fn (mut b Button) set_active(v bool) {
	widget_changed()
	b.active = v
}

// ─── Internal ──────────────────────────────────────────

fn (b &Button) eff_radius(ctx &RenderContext) f32 {
	if b.radius >= 0 {
		return b.radius
	}
	return ctx.theme.border_radius
}

fn (b &Button) has_file_icon() bool {
	return b.icon_path.len > 0
}

fn (b &Button) has_lucide_icon() bool {
	return b.icon_name.len > 0
}

fn (b &Button) has_text_icon() bool {
	return b.icon_text.len > 0
}

fn (b &Button) has_label() bool {
	return b.text.len > 0
}

// Effective "visually pressed" state: momentary press OR toggle active
fn (b &Button) is_visually_pressed() bool {
	if b.toggle {
		return b.active
	}
	return b.pressed
}

// draw: регистрация в фокус-учёте, шаг четырёх анимаций, расчёт цветов по
// style (смешивание bg с hover/pressed-цветами пропорционально значению Anim),
// тень при наведении, фон, рамка, кольцо фокуса, содержимое (draw_content).
pub fn (mut b Button) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(b.enabled)
	if !b.visible {
		return
	}
	if !ctx.is_in_clip(b.bounds) {
		return
	}

	// Register in focus only if not excluded
	if en && !b.no_focus {
		ctx.focus.register_button(&b, b.focus_group)
	} else {
		ctx.focus_block(&b)
	}

	is_focused := if b.no_focus { false } else { ctx.focus.is_focused(unsafe { &b }) }

	// Animate
	target_hover := if b.hovered && en { f32(1.0) } else { f32(0.0) }
	target_press := if b.is_visually_pressed() && en { f32(1.0) } else { f32(0.0) }
	target_focus := if is_focused && en { f32(1.0) } else { f32(0.0) }
	target_active := if b.active && b.toggle && en { f32(1.0) } else { f32(0.0) }
	// Все четыре шага — обязательно (не через ||: он бы не шагнул остальные).
	mut animating := b.hover_anim.update(target_hover, ctx)
	animating = b.press_anim.update(target_press, ctx) || animating
	animating = b.focus_anim.update(target_focus, ctx) || animating
	animating = b.active_anim.update(target_active, ctx) || animating
	// Mark animation only when not yet settled. mark_anim_rect, а не
	// mark_anim: анимации кнопки (hover/press/focus/active) целиком лежат
	// внутри её bounds, и полный кадр ради них означал бы, что наведение
	// мышью по-прежнему перерисовывает всё окно — ровно то, ради чего
	// mouse_move перевели на точечную инвалидацию (аудит 3.C).
	// Собственную проверку is_in_clip mark_anim_rect делает сам.
	if animating {
		ctx.mark_anim_rect('button', b.bounds)
	}

	mut bg := Color{}
	mut fg := Color{}
	mut border_c := Color{}

	if !en {
		bg = ctx.theme.button_disabled_bg
		fg = ctx.theme.text_disabled
		border_c = ctx.theme.button_disabled_border
	} else {
		match b.style {
			.normal {
				bg = ctx.theme.button_bg.blend(ctx.theme.button_hover, b.hover_anim.value)
				bg = bg.blend(ctx.theme.button_pressed, b.press_anim.value)
				fg = ctx.theme.button_text
				border_c = ctx.theme.button_border.blend(ctx.theme.accent, b.hover_anim.value * 0.5)
				// Toggle active: tint with accent
				if b.active_anim.value > 0.05 {
					bg = bg.blend(ctx.theme.accent.darken(0.15), b.active_anim.value * 0.6)
					border_c = border_c.blend(ctx.theme.accent, b.active_anim.value)
				}
			}
			.accent {
				bg = ctx.theme.accent.blend(ctx.theme.accent_hover, b.hover_anim.value)
				bg = bg.blend(ctx.theme.accent_pressed, b.press_anim.value)
				fg = ctx.theme.accent_text
				border_c = bg.darken(0.1)
				if b.active_anim.value > 0.05 {
					bg = bg.blend(ctx.theme.accent_pressed, b.active_anim.value * 0.5)
				}
			}
			.outline {
				bg = color_transparent.blend(ctx.theme.button_hover.with_alpha(80), b.hover_anim.value)
				fg = ctx.theme.accent.blend(ctx.theme.text_primary, b.hover_anim.value * 0.3)
				border_c = ctx.theme.accent
				if b.active_anim.value > 0.05 {
					bg = bg.blend(ctx.theme.accent.with_alpha(60), b.active_anim.value)
					fg = ctx.theme.accent_text.blend(fg, 1.0 - b.active_anim.value)
				}
			}
			.flat {
				bg = color_transparent.blend(ctx.theme.button_hover.with_alpha(60), b.hover_anim.value)
				fg = ctx.theme.text_primary
				border_c = color_transparent
				if b.active_anim.value > 0.05 {
					bg = bg.blend(ctx.theme.accent.with_alpha(50), b.active_anim.value)
				}
			}
			.danger {
				bg = ctx.theme.error_color.blend(ctx.theme.error_color.brighten(0.1), b.hover_anim.value)
				bg = bg.blend(ctx.theme.error_color.darken(0.1), b.press_anim.value)
				fg = color_white
				border_c = bg.darken(0.1)
			}
			.success {
				bg = ctx.theme.success.blend(ctx.theme.success.brighten(0.1), b.hover_anim.value)
				bg = bg.blend(ctx.theme.success.darken(0.1), b.press_anim.value)
				fg = color_white
				border_c = bg.darken(0.1)
			}
		}
	}

	radius := b.eff_radius(ctx)

	// Shadow (not for active toggle — looks "pushed in")
	if b.style != .flat && b.style != .outline && ctx.theme.shadow_offset > 0 {
		if b.hovered && en && !b.is_visually_pressed() {
			ctx.draw_shadow(b.bounds, radius)
		}
	}

	// Background
	ctx.fill_rounded_rect(b.bounds, bg, radius)

	// Border
	if border_c.a > 0 && b.border_width > 0 {
		ctx.draw_rounded_rect(b.bounds, border_c, radius)
	}

	// Focus ring
	ctx.draw_focus_ring_soft(b.bounds, radius, b.focus_anim.value)

	// Content
	b.draw_content(mut ctx, fg)
}

// draw_content рисует иконку и/или текст по центру bounds цветом fg.
// Все ветки заканчиваются pop_clip() ровно один раз (парный push_clip выше),
// поэтому каждый ранний return сначала снимает клип.
fn (b &Button) draw_content(mut ctx RenderContext, fg Color) {
	// A lucide icon_name that doesn't resolve to a known glyph (typo, etc.)
	// must not blank out the button — fall through to the file/text icon or
	// plain-text rendering below exactly as if icon_name had been empty.
	lucide_codepoint, lucide_found := if b.has_lucide_icon() {
		icon_codepoint(b.icon_name)
	} else {
		u32(0), false
	}
	has_lucide := lucide_found
	has_icon := !has_lucide && b.has_file_icon()
	has_ticon := !has_lucide && !has_icon && b.has_text_icon()
	has_text := b.has_label()

	ctx.push_clip(b.bounds)

	if has_lucide {
		if has_text {
			font := ctx.get_font(b.font_style, b.font_size)
			text_sz := ctx.measure_text_with_font(b.text, font)
			total_w := b.icon_size + b.icon_gap + text_sz.x
			start_x := b.bounds.x + (b.bounds.w - total_w) * 0.5
			icon_y := b.bounds.y + (b.bounds.h - b.icon_size) * 0.5
			ctx.draw_icon_glyph(lucide_codepoint, Rect{start_x, icon_y, b.icon_size, b.icon_size},
				int(b.icon_size), fg)
			text_x := start_x + b.icon_size + b.icon_gap
			text_y := b.bounds.y + (b.bounds.h - text_sz.y) * 0.5
			ctx.draw_text_with_font(b.text, text_x, text_y, fg, font)
		} else {
			ctx.draw_icon_glyph(lucide_codepoint, b.bounds, int(b.icon_size), fg)
		}
		ctx.pop_clip()
		return
	}

	if has_icon {
		icon_tex := ctx.load_icon_texture(b.icon_path)
		if has_text {
			font := ctx.get_font(b.font_style, b.font_size)
			text_sz := ctx.measure_text_with_font(b.text, font)
			total_w := b.icon_size + b.icon_gap + text_sz.x
			start_x := b.bounds.x + (b.bounds.w - total_w) * 0.5
			icon_y := b.bounds.y + (b.bounds.h - b.icon_size) * 0.5
			ctx.draw_icon(icon_tex, start_x, icon_y, b.icon_size, b.icon_size)
			text_x := start_x + b.icon_size + b.icon_gap
			text_y := b.bounds.y + (b.bounds.h - text_sz.y) * 0.5
			ctx.draw_text_with_font(b.text, text_x, text_y, fg, font)
		} else {
			icon_x := b.bounds.x + (b.bounds.w - b.icon_size) * 0.5
			icon_y := b.bounds.y + (b.bounds.h - b.icon_size) * 0.5
			ctx.draw_icon(icon_tex, icon_x, icon_y, b.icon_size, b.icon_size)
		}
		ctx.pop_clip()
		return
	}

	if has_ticon {
		full := '${b.icon_text}  ${b.text}'
		font := ctx.get_font(b.font_style, b.font_size)
		sz := ctx.measure_text_with_font(full, font)
		tx := b.bounds.x + (b.bounds.w - sz.x) * 0.5
		ty := b.bounds.y + (b.bounds.h - sz.y) * 0.5
		ctx.draw_text_with_font(full, tx, ty, fg, font)
		ctx.pop_clip()
		return
	}

	if has_text {
		font := ctx.get_font(b.font_style, b.font_size)
		sz := ctx.measure_text_with_font(b.text, font)
		tx := b.bounds.x + (b.bounds.w - sz.x) * 0.5
		ty := b.bounds.y + (b.bounds.h - sz.y) * 0.5
		ctx.draw_text_with_font(b.text, tx, ty, fg, font)
	}

	ctx.pop_clip()
}

// do_activate - "сработала" кнопка (отпускание мыши над ней или Space/Enter):
// для toggle сначала переключает active и зовёт on_toggle, затем всегда on_click.
fn (mut b Button) do_activate() {
	if b.toggle {
		b.active = !b.active
		if b.on_toggle != unsafe { nil } {
			b.on_toggle(b.active)
		}
	}
	if b.on_click != unsafe { nil } {
		b.on_click()
	}
}

// handle_event обрабатывает мышь и клавиатуру; true - событие поглощено.
// mouse_move обновляет hovered (уход курсора отменяет нажатие); mouse_down
// фокусирует (если не no_focus) и взводит pressed; mouse_up над кнопкой
// активирует; Tab двигает фокус; Space/Enter активируют сфокусированную.
pub fn (mut b Button) handle_event(event &GuiEvent, app &App) bool {
	if !b.visible || !b.enabled {
		return false
	}

	match event.typ {
		.mouse_leave {
			// курсор ушёл с виджета (event_route.v) - как движение за его пределы
			b.hovered = false
			b.pressed = false
		}
		.mouse_move {
			b.hovered = b.bounds.contains(event.mouse_x, event.mouse_y)
			if !b.hovered {
				b.pressed = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && b.hovered {
				if !b.no_focus {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.focus_button(&b, b.focus_group)
					}
				}
				b.pressed = true
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && b.pressed {
				b.pressed = false
				if b.hovered {
					b.do_activate()
				}
				return true
			}
		}
		.key_down {
			if b.no_focus {
				return false
			}
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_ref := unsafe { &RenderContext(ctx_ptr) }
				is_focused := ctx_ref.focus.is_focused(unsafe { &b })
				if is_focused {
					if event.keycode == sdl_k_tab {
						ctx_ref.focus.tab(event.shift())
						return true
					}
					if event.keycode == sdl_k_return || event.keycode == sdl_k_space {
						b.do_activate()
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
