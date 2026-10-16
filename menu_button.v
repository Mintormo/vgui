module vgui

// ═══════════════════════════════════════════════════════
// MenuButton — split button with a dropdown menu
//
// Behaves like a "split button": the main (left) area runs
// the currently selected action directly, while a separate
// arrow zone (right) opens a popup menu to pick a new action
// (reusing the existing MenuItem/MenuState system).
//
// Features:
//   - action items, checkboxes, separators, submenus, icons
//   - clicking the main area fires the active action's
//     on_click + the on_select callback
//   - picking an item in the menu makes it the active action
//     and updates the button text
//   - separate hover highlight for the action zone and the
//     arrow zone, divided by a vertical line
//   - on_select callback (index, text) for action items
//   - full keyboard navigation via overlay
//
// Usage:
//   mut mb := vgui.menu_button('Choose...')
//   mb.add(vgui.menu_action('Option A'))
//   mb.add(vgui.menu_action_icon('Option B', 'icon.png'))
//   mb.add(vgui.menu_separator())
//   mb.add(vgui.menu_checkbox('Dark mode', false))
//   mut sub := vgui.menu_submenu('More')
//   sub.add(vgui.menu_action('Sub 1'))
//   mb.add(sub)
// ═══════════════════════════════════════════════════════

// MenuButton — «split button»: слева зона действия, справа зона стрелки с выпадающим
// меню. Использует общую систему меню из menu.v (MenuItem, MenuState, menu_*),
// но с собственной копией обработчика оверлея (open_menu).
//
// Состояния: open — флаг, который ведёт сам виджет (подсветка стрелки, переключение
// по повторному клику); state.open — флаг системы меню (его читает is_open()).
// active_idx / active_click — «активное действие», запускаемое кликом по левой зоне;
// -1 до первого выбора (тогда клик по левой зоне открывает меню).
// Размер считает measure() в layout_measure.v; фокус — через FocusManager
// (register_menu_button), Tab/Down/Enter/Space — см. handle_event.
@[heap]
pub struct MenuButton {
pub mut:
	type_tag    int = kind_menu_button // тег типа, см. widget_tag.v
	css         CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds      Rect
	text        string // current display text (updated on action selection)
	placeholder string // shown when no action selected
	items       []&MenuItem
	style       ButtonStyle = .normal
	visible     bool        = true
	enabled     bool        = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	hovered     bool   // mouse over the widget as a whole
	// hovered_arrow — курсор над зоной стрелки (подмножество hovered); pressed / pressed_arrow — какая зона зажата (клик срабатывает по отпусканию)
	hovered_arrow bool // mouse over the arrow zone specifically
	pressed       bool // action zone pressed
	pressed_arrow bool // arrow zone pressed
	open          bool
	icon          ItemIcon // иконка слева от текста (item_icon.v); ItemIcon{} - нет
	icon_size     f32       = 16
	icon_gap      f32       = 6
	radius        f32       = -1
	border_width  f32       = 1
	font_style    FontStyle = .regular
	font_size     int
	focus_group   int
	// no_focus: не участвовать в Tab-обходе и не реагировать на клавиатуру
	no_focus bool
	pad      f32 = 6
	// arrow_w — ширина правой зоны со стрелкой, pad — внутренний отступ слева
	arrow_w f32 = 24
	// Active action: the item the main button runs when clicked.
	// -1 means nothing selected yet (main click opens the menu).
	// active_idx — «плоский» индекс (без разделителей) выбранного действия в items; -1, пока ничего не выбрано
	active_idx   int   = -1
	active_click fn () = unsafe { nil }
	// Animation
	hover_anim       Anim // action zone hover
	arrow_hover_anim Anim // arrow zone hover
	press_anim       Anim = anim_smooth(anim_tau_press)
	focus_anim       Anim = anim_smooth(anim_tau_focus)
	// Menu state (reuses MenuState from menu.v)
	// state.levels / state.open — открытые уровни меню; owner = адрес виджета (ключ слота оверлея)
	state MenuState
	// Callbacks
	on_select fn (int, string) = unsafe { nil } // fired when an action item is picked or re-run
	on_click  fn ()            = unsafe { nil } // fired on every main-area click (after active action)
}

// ─── Constructors ──────────────────────────────────────

// menu_button создаёт кнопку; placeholder показывается серым, пока действие не выбрано.
pub fn menu_button(placeholder string) &MenuButton {
	return &MenuButton{
		placeholder: placeholder
		text:        placeholder
	}
}

// menu_button_with_icon — то же, с иконкой слева от текста (icon_path).
pub fn menu_button_with_icon(placeholder string, icon_path string) &MenuButton {
	return &MenuButton{
		placeholder: placeholder
		text:        placeholder
		icon:        item_icon_file(icon_path)
	}
}

// set_icon задаёт иконку слева от текста (ItemIcon{} - убрать).
pub fn (mut mb MenuButton) set_icon(ic ItemIcon) {
	mb.icon = ic
}

// ─── Public API ────────────────────────────────────────

// add добавляет пункт в корень выпадающего меню (любой MenuItem, в т.ч. подменю).
pub fn (mut mb MenuButton) add(item &MenuItem) {
	mb.items << unsafe { item }
}

// add_separator добавляет разделитель.
pub fn (mut mb MenuButton) add_separator() {
	mb.items << menu_separator()
}

// is_open: выпадающее меню сейчас показано (по state.open).
pub fn (mb &MenuButton) is_open() bool {
	return mb.state.open
}

// set_text меняет отображаемый текст кнопки, не трогая активное действие. Кадр не инвалидирует.
pub fn (mut mb MenuButton) set_text(text string) {
	mb.text = text
}

pub fn (mb &MenuButton) get_text() string {
	return mb.text
}

// ─── Internal helpers ──────────────────────────────────

// eff_radius: radius < 0 означает «радиус темы».
fn (mb &MenuButton) eff_radius(ctx &RenderContext) f32 {
	if mb.radius >= 0 {
		return mb.radius
	}
	return ctx.theme.border_radius
}

// display_text: текст кнопки или placeholder, если текст пуст.
fn (mb &MenuButton) display_text() string {
	return if mb.text.len > 0 { mb.text } else { mb.placeholder }
}

// arrow_rect returns the bounds of the dropdown-arrow zone (right side).
fn (mb &MenuButton) arrow_rect() Rect {
	return Rect{mb.bounds.x + mb.bounds.w - mb.arrow_w, mb.bounds.y, mb.arrow_w, mb.bounds.h}
}

// action_rect returns the bounds of the main action zone (left side).
fn (mb &MenuButton) action_rect() Rect {
	return Rect{mb.bounds.x, mb.bounds.y, mb.bounds.w - mb.arrow_w, mb.bounds.h}
}

// run_active fires the active action (its on_click) plus the on_select /
// on_click callbacks. Called when the main action zone is clicked.
fn (mut mb MenuButton) run_active() {
	if mb.active_idx >= 0 {
		if mb.active_click != unsafe { nil } {
			mb.active_click()
		}
		if mb.on_select != unsafe { nil } {
			mb.on_select(mb.active_idx, mb.text)
		}
	}
	if mb.on_click != unsafe { nil } {
		mb.on_click()
	}
}

// choose_action выбирает пункт-действие mi (мышью или Enter/Space): он становится
// активным действием кнопки (текст, active_idx - «плоский» индекс без разделителей,
// active_click), меню закрывается, затем зовутся mi.on_click и on_select. Меню
// закрывается ДО колбэков, как в menu_activate_hovered: обработчик, открывающий другой
// попап, видит уже свободный слот оверлея. Раньше Enter шёл мимо этого пути: пункт не
// становился активным, а open оставался true (стрелка «открыта», следующий клик
// работал как закрытие).
fn (mut mb MenuButton) choose_action(mi &MenuItem, mut ctx RenderContext) {
	mb.text = mi.text
	mut flat_idx := 0
	for fmi in mb.items {
		if fmi == unsafe { mi } {
			break
		}
		if fmi.kind != .separator {
			flat_idx++
		}
	}
	mb.active_idx = flat_idx
	mb.active_click = mi.on_click
	mb.close_menu(mut ctx)
	if mi.on_click != unsafe { nil } {
		mi.on_click()
	}
	if mb.on_select != unsafe { nil } {
		mb.on_select(flat_idx, mi.text)
	}
}

// close_menu закрывает меню (снимает оверлей через state.close_all) и сбрасывает open.
fn (mut mb MenuButton) close_menu(mut ctx RenderContext) {
	mb.state.close_all(mut ctx)
	mb.open = false
}

// open_menu открывает выпадающее меню под кнопкой (шире кнопки не уже; если снизу
// нет места — над кнопкой) и ставит оверлей окна. Пустой список items — ничего не
// делает. Старое состояние меню предварительно закрывается. Замыкания draw/ev —
// копия menu_install_overlay (menu.v) с отличием: наведение на саму кнопку не
// закрывает меню, а клик по ней закрывает; при выборе action-пункта он становится
// активным действием кнопки.
fn (mut mb MenuButton) open_menu(mut ctx RenderContext) {
	if mb.items.len == 0 {
		return
	}
	// owner — адрес виджета: по нему слот оверлея окна узнаёт, чей попап стоит в слоте (overlay.v).
	mb.state.owner = voidptr(&mb)
	mb.state.close_all(mut ctx)

	sz := menu_popup_size(mb.items, ctx)
	// Position below the button, same width minimum
	popup_w := max_f32(sz.x, mb.bounds.w)
	mut popup_x := mb.bounds.x
	mut popup_y := mb.bounds.y + mb.bounds.h + 2

	// Flip up if not enough space below
	if popup_y + sz.y > ctx.screen_height - 2 {
		popup_y = mb.bounds.y - sz.y - 2
	}

	popup := menu_adjust_rect(popup_x, popup_y, popup_w, sz.y, ctx)

	mb.state.levels << MenuLevel{
		items: mb.items
		popup: popup
	}
	// Далее меню ставится в слот оверлея окна; события оверлея приходят раньше обычных виджетов.
	mb.open = true

	// Install overlay — reuse menu system's overlay with custom close hook
	mb.state.open = true

	draw := fn [mut mb] (mut ctx RenderContext) {
		if !mb.state.open {
			return
		}
		for lvl in mb.state.levels {
			menu_draw_popup(lvl.items, lvl.popup, mut ctx)
		}
	}

	ev := fn [mut mb, mut ctx] (event &GuiEvent, app &App) bool {
		if !mb.state.open {
			return false
		}

		// Для колеса позиция курсора берётся из ctx (последняя известная), для
		// остальных событий — из самого события.
		mx := if event.typ == .mouse_wheel { ctx.mouse_x } else { event.mouse_x }
		my := if event.typ == .mouse_wheel { ctx.mouse_y } else { event.mouse_y }

		match event.typ {
			.mouse_move {
				if mb.state.levels.len >= 2 && menu_in_submenu_transit(mb.state, mx, my) {
					return true
				}
				mut in_any := false
				mut fl := -1
				mut fi := -1
				for li := mb.state.levels.len - 1; li >= 0; li-- {
					lvl := mb.state.levels[li]
					if lvl.popup.contains(mx, my) {
						in_any = true
						fl = li
						fi = menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y, lvl.popup.w)
						break
					}
				}
				if in_any {
					if fl < mb.state.levels.len - 1 {
						if fi != mb.state.levels[fl].hover_idx {
							mb.state.close_submenus_from(fl)
						}
					}
					menu_update_hover(mb.state.levels[fl].items, fi)
					mb.state.levels[fl].hover_idx = fi
					if fi >= 0 {
						mi := mb.state.levels[fl].items[fi]
						if mi.kind == .submenu && mi.enabled && !mi.sub_open {
							mb.state.open_submenu(fl, fi, ctx)
						}
					}
					return true
				}
				if mb.state.levels.len > 0 {
					last := mb.state.levels.len - 1
					menu_clear_all_hover(mb.state.levels[last].items)
					mb.state.levels[last].hover_idx = -1
				}
				// If mouse is over the button itself, don't close
				if mb.bounds.contains(mx, my) {
					return true
				}
				return false
			}
			.mouse_down {
				if event.mouse_btn != .left {
					mb.close_menu(mut ctx)
					return false
				}
				// Click on button itself → close
				if mb.bounds.contains(mx, my) {
					mb.close_menu(mut ctx)
					return true
				}
				for li := mb.state.levels.len - 1; li >= 0; li-- {
					lvl := mb.state.levels[li]
					if lvl.popup.contains(mx, my) {
						idx := menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y,
							lvl.popup.w)
						if idx >= 0 {
							mi := lvl.items[idx]
							if !mi.enabled {
								return true
							}
							if mi.kind == .submenu {
								if !mi.sub_open {
									mb.state.open_submenu(li, idx, ctx)
								}
								return true
							}
							if mi.kind == .checkbox {
								menu_toggle_checked(lvl.items, idx)
								checked := menu_get_checked(lvl.items, idx)
								if mi.on_toggle != unsafe { nil } {
									mi.on_toggle(checked)
								}
								mb.close_menu(mut ctx)
								return true
							}
							mb.choose_action(mi, mut ctx)
							return true
						}
						return true
					}
				}
				mb.close_menu(mut ctx)
				return false
			}
			.key_down {
				match event.keycode {
					sdl_k_escape {
						if mb.state.levels.len > 1 {
							mb.state.close_submenus_from(mb.state.levels.len - 2)
							return true
						}
						mb.close_menu(mut ctx)
						return true
					}
					sdl_k_up {
						if mb.state.levels.len > 0 {
							last := mb.state.levels.len - 1
							cur := mb.state.levels[last].hover_idx
							next := menu_next_selectable(mb.state.levels[last].items, cur, -1)
							if next >= 0 {
								menu_update_hover(mb.state.levels[last].items, next)
								mb.state.levels[last].hover_idx = next
							}
						}
						return true
					}
					sdl_k_down {
						if mb.state.levels.len > 0 {
							last := mb.state.levels.len - 1
							cur := mb.state.levels[last].hover_idx
							next := menu_next_selectable(mb.state.levels[last].items, cur, 1)
							if next >= 0 {
								menu_update_hover(mb.state.levels[last].items, next)
								mb.state.levels[last].hover_idx = next
							}
						}
						return true
					}
					sdl_k_right {
						if mb.state.levels.len > 0 {
							last := mb.state.levels.len - 1
							idx := mb.state.levels[last].hover_idx
							if idx >= 0 && idx < mb.state.levels[last].items.len {
								mi := mb.state.levels[last].items[idx]
								if mi.kind == .submenu && mi.enabled && !mi.sub_open {
									mb.state.open_submenu(last, idx, ctx)
									if mb.state.levels.len > last + 1 {
										new_last := mb.state.levels.len - 1
										first := menu_next_selectable(mb.state.levels[new_last].items,
											-1, 1)
										if first >= 0 {
											menu_update_hover(mb.state.levels[new_last].items,
												first)
											mb.state.levels[new_last].hover_idx = first
										}
									}
									return true
								}
							}
						}
						return true
					}
					sdl_k_left {
						if mb.state.levels.len > 1 {
							mb.state.close_submenus_from(mb.state.levels.len - 2)
							return true
						}
						return true
					}
					sdl_k_return, sdl_k_space {
						if mb.state.levels.len > 0 {
							last := mb.state.levels.len - 1
							idx := mb.state.levels[last].hover_idx
							if idx >= 0 && idx < mb.state.levels[last].items.len {
								mi := mb.state.levels[last].items[idx]
								// Пункт-действие с клавиатуры - тот же путь, что и мышью:
								// он становится активным действием кнопки.
								if mi.kind == .action && mi.enabled {
									mb.choose_action(mi, mut ctx)
									return true
								}
								handled := menu_activate_hovered(mut mb.state, last, idx, mut
									ctx)
								// Флажок закрывает меню через state; open кнопки
								// сбрасываем вслед, иначе стрелка осталась бы «открытой».
								if !mb.state.open {
									mb.open = false
								}
								return handled
							}
						}
						return true
					}
					else {}
				}
			}
			else {}
		}

		return false
	}

	ctx.set_overlay(voidptr(&mb), draw, ev, fn [mut mb] (mut ctx RenderContext) {
		mb.close_menu(mut ctx)
	})
}

// ─── Drawing ───────────────────────────────────────────

// draw: регистрирует кнопку в фокус-учёте, шагает четыре Anim (hover действия,
// hover стрелки, нажатие, фокус), рисует фон, подсветку каждой зоны (с clip-ом по
// зоне, чтобы сохранить скруглённые углы), рамку, кольцо фокуса, разделитель,
// иконку + текст и стрелку (вверх, когда меню открыто). Сам попап рисует оверлей.
pub fn (mut mb MenuButton) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(mb.enabled)
	if !mb.visible {
		return
	}
	if !ctx.is_in_clip(mb.bounds) {
		return
	}

	if en && !mb.no_focus {
		ctx.focus.register_menu_button(&mb, mb.focus_group)
	} else {
		ctx.focus_block(&mb)
	}

	is_focused := if mb.no_focus { false } else { ctx.focus.is_focused(unsafe { &mb }) }

	// Animate — action zone and arrow zone highlight independently
	action_hot := mb.hovered && !mb.hovered_arrow && en
	arrow_hot := (mb.hovered_arrow || mb.open) && en
	target_h := if action_hot { f32(1.0) } else { f32(0.0) }
	target_ah := if arrow_hot { f32(1.0) } else { f32(0.0) }
	target_p := if (mb.pressed || mb.pressed_arrow || mb.open) && en {
		f32(1.0)
	} else {
		f32(0.0)
	}
	target_f := if is_focused && en { f32(1.0) } else { f32(0.0) }
	mut animating := mb.hover_anim.update(target_h, ctx)
	animating = mb.arrow_hover_anim.update(target_ah, ctx) || animating
	animating = mb.press_anim.update(target_p, ctx) || animating
	animating = mb.focus_anim.update(target_f, ctx) || animating

	// Под dirty regions кадр без грязи не рисуется вообще, поэтому виджет с
	// незавершённой анимацией обязан помечать себя сам — иначе она замирает
	// после первого же кадра (см. PROJECT.md, «Инвалидация и dirty regions»).
	// mark_anim_rect — см. button.v. Само меню рисуется оверлеем вне этих
	// bounds, но его кадры форсирует render() (overlay_cb != nil — полный
	// кадр), а здесь речь только об анимации самой кнопки.
	if animating {
		ctx.mark_anim_rect('menu_button', mb.bounds)
	}

	mut bg := Color{}
	mut fg := Color{}
	mut bc := Color{}

	if !en {
		bg = ctx.theme.button_disabled_bg
		fg = ctx.theme.text_disabled
		bc = ctx.theme.button_disabled_border
	} else {
		bg = ctx.theme.button_bg
		fg = ctx.theme.button_text
		bc = ctx.theme.button_border.blend(ctx.theme.accent, max_f32(mb.hover_anim.value,
			mb.arrow_hover_anim.value) * 0.5)
	}

	rad := mb.eff_radius(ctx)

	if mb.style != .flat && ctx.theme.shadow_offset > 0 {
		if mb.hovered && en && !mb.open {
			ctx.draw_shadow(mb.bounds, rad)
		}
	}

	// Base background
	ctx.fill_rounded_rect(mb.bounds, bg, rad)

	// Per-zone hover/press highlight, clipped to each zone so the
	// rounded corners are respected.
	if en {
		arect := mb.action_rect()
		brect := mb.arrow_rect()
		if mb.hover_anim.value > 0.01 || (mb.pressed && action_hot) {
			ahl := if mb.pressed { ctx.theme.button_pressed } else { ctx.theme.button_hover }
			amt := if mb.pressed { f32(1.0) } else { mb.hover_anim.value }
			ctx.push_clip(arect)
			ctx.fill_rounded_rect(mb.bounds, bg.blend(ahl, amt), rad)
			ctx.pop_clip()
		}
		if mb.arrow_hover_anim.value > 0.01 || mb.open || mb.pressed_arrow {
			bhl := if mb.open || mb.pressed_arrow {
				ctx.theme.button_pressed
			} else {
				ctx.theme.button_hover
			}
			amt := if mb.open || mb.pressed_arrow { f32(1.0) } else { mb.arrow_hover_anim.value }
			ctx.push_clip(brect)
			ctx.fill_rounded_rect(mb.bounds, bg.blend(bhl, amt), rad)
			ctx.pop_clip()
		}
	}

	if bc.a > 0 && mb.border_width > 0 {
		ctx.draw_rounded_rect(mb.bounds, bc, rad)
	}

	// Focus ring
	ctx.draw_focus_ring(mb.bounds, rad, mb.focus_anim.value)

	// Divider between the action zone and the arrow zone
	if mb.arrow_w > 0 && mb.bounds.w > mb.arrow_w {
		dx := mb.bounds.x + mb.bounds.w - mb.arrow_w
		dy0 := mb.bounds.y + mb.pad * 0.5
		dy1 := mb.bounds.y + mb.bounds.h - mb.pad * 0.5
		dc := if en { bc } else { ctx.theme.button_disabled_border }
		ctx.draw_line(dx, dy0, dx, dy1, dc)
	}

	// Content: icon + text + arrow
	font := ctx.get_font(mb.font_style, mb.font_size)
	fh := ctx.font_height_of(font)
	disp := mb.display_text()

	// Clip text area (excluding arrow)
	text_area_w := mb.bounds.w - mb.pad * 2 - mb.arrow_w
	text_clip := Rect{mb.bounds.x + mb.pad, mb.bounds.y, text_area_w, mb.bounds.h}
	ctx.push_clip(text_clip)

	mut tx := mb.bounds.x + mb.pad
	ty := mb.bounds.y + (mb.bounds.h - fh) * 0.5

	tc := if mb.text == mb.placeholder && en {
		ctx.theme.text_secondary
	} else {
		fg
	}
	if mb.icon.is_set() {
		ctx.draw_item_icon(mb.icon, Rect{tx, mb.bounds.y, mb.icon_size, mb.bounds.h},
			mb.icon_size, tc)
		tx += mb.icon_size + mb.icon_gap
	}
	ctx.draw_text_with_font(disp, tx, ty, tc, font)
	ctx.pop_clip()

	// Down arrow
	ax := mb.bounds.x + mb.bounds.w - mb.arrow_w
	acx := ax + mb.arrow_w * 0.5
	acy := mb.bounds.y + mb.bounds.h * 0.5
	aw := f32(7)
	ah := f32(4)
	ac := if en { ctx.theme.text_secondary } else { ctx.theme.text_disabled }
	if mb.open {
		ctx.fill_triangle(acx, acy - ah * 0.5, acx - aw * 0.5, acy + ah * 0.5, acx + aw * 0.5,

			acy + ah * 0.5, ac)
	} else {
		ctx.fill_triangle(acx, acy + ah * 0.5, acx - aw * 0.5, acy - ah * 0.5, acx + aw * 0.5,
			acy - ah * 0.5, ac)
	}
}

// ─── Events ────────────────────────────────────────────

// handle_event: наведение считает зоны (действие/стрелка); нажатие запоминает зону,
// действие срабатывает по отпусканию над той же зоной (как у Button). Стрелка
// переключает меню; левая зона запускает активное действие либо, если ничего не
// выбрано, открывает меню. С клавиатуры (у сфокусированной кнопки): Down открывает
// меню, Enter/Space — как клик по левой зоне, Tab — следующий фокус.
pub fn (mut mb MenuButton) handle_event(event &GuiEvent, app &App) bool {
	if !mb.visible || !mb.enabled {
		return false
	}

	match event.typ {
		.mouse_move {
			mb.hovered = mb.bounds.contains(event.mouse_x, event.mouse_y)
			mb.hovered_arrow = mb.hovered
				&& mb.arrow_rect().contains(event.mouse_x, event.mouse_y)
			if !mb.hovered {
				mb.pressed = false
				mb.pressed_arrow = false
			}
		}
		.mouse_down {
			if event.mouse_btn == .left && mb.hovered {
				if mb.arrow_rect().contains(event.mouse_x, event.mouse_y) {
					mb.pressed_arrow = true
				} else {
					mb.pressed = true
				}
				return true
			}
		}
		.mouse_up {
			if event.mouse_btn == .left && (mb.pressed || mb.pressed_arrow) {
				was_action := mb.pressed
				was_arrow := mb.pressed_arrow
				mb.pressed = false
				mb.pressed_arrow = false
				if !mb.hovered {
					return true
				}
				over_arrow := mb.arrow_rect().contains(event.mouse_x, event.mouse_y)
				if was_arrow && over_arrow {
					// Toggle the dropdown menu
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						if mb.open {
							mb.close_menu(mut ctx_mut)
						} else {
							mb.open_menu(mut ctx_mut)
						}
					}
				} else if was_action && !over_arrow {
					// Run the active action, or open the menu if nothing
					// has been selected yet.
					if mb.active_idx < 0 {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							mb.open_menu(mut ctx_mut)
						}
					} else {
						mb.run_active()
					}
				}
				return true
			}
		}
		.key_down {
			if mb.no_focus {
				return false
			}
			ctx_ptr := app.get_active_ctx()
			if unsafe { ctx_ptr != nil } {
				mut ctx_ref := unsafe { &RenderContext(ctx_ptr) }
				if ctx_ref.focus.is_focused(unsafe { &mb }) {
					// Down arrow always opens the menu (pick a new action)
					if event.keycode == sdl_k_down {
						if !mb.open {
							mb.open_menu(mut ctx_ref)
						}
						return true
					}
					// Enter/Space run the active action, or open the menu
					// if nothing has been selected yet.
					if event.keycode == sdl_k_return || event.keycode == sdl_k_space {
						if mb.active_idx < 0 {
							if !mb.open {
								mb.open_menu(mut ctx_ref)
							}
						} else {
							mb.run_active()
						}
						return true
					}
					if event.keycode == sdl_k_tab {
						ctx_ref.focus.tab(event.shift())
						return true
					}
				}
			}
		}
		else {}
	}

	return false
}
