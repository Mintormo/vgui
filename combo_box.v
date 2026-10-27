// Файл: ./combo_box.v
module vgui

// ═══════════════════════════════════════════════════════
// ComboBox — drop-down select widget with overlay popup.
// Items can be plain text OR arbitrary widgets (including
// containers). Backward-compatible with the old text API.
// ═══════════════════════════════════════════════════════

// DropDir - в какую сторону раскрывается список: вниз (по умолчанию) или вверх, если снизу нет места
// (выбирается при открытии в calc_drop_direction).
enum DropDir {
	down
	up
}

// ComboItem - один элемент выпадающего списка: либо просто текст, либо произвольный виджет-ячейка
// (в этом случае text всё равно хранится - он показывается в закрытом комбобоксе и отдаётся в on_change).
//   widget    - если не nil, рисуется вместо текста; ComboBox не владеет им (время жизни - у вызывающего)
//   height    - высота строки; 0 = ComboBox.item_height
//   user_data - произвольный указатель пользователя (set_item_data/get_item_data)
pub struct ComboItem {
pub mut:
	text      string
	widget    &Widget = unsafe { nil } // if set, drawn instead of text
	height    f32      // 0 = use ComboBox.item_height
	icon      ItemIcon // иконка слева от текста (item_icon.v); у пункта-виджета не рисуется
	user_data voidptr = unsafe { nil }
}

// ComboBox - выпадающий список. Закрытый вид - поле с выбранным текстом и стрелкой; по клику/Enter/Space
// открывается popup, который рисуется как ОВЕРЛЕЙ окна (ctx.set_overlay с владельцем &cb), поэтому
// перекрывает соседние виджеты и перехватывает события раньше остальных (см. open_dropdown).
// Данные хранятся в entries; items - устаревшее зеркало только текстов (для обратной совместимости).
// selected = -1 - ничего не выбрано (рисуется placeholder). on_change вызывается при каждой смене
// selected, в том числе стрелками на закрытом списке (fire_change).
@[heap]
pub struct ComboBox {
pub mut:
	type_tag int = kind_combo_box // тег типа, см. widget_tag.v
	css      CssTags // #id и классы для селекторов CSS (css_apply.v)
	bounds   Rect
	entries  []ComboItem
	// Legacy mirror — kept in sync with entries for back-compat
	// Устаревшее зеркало текстов entries; обновляют add_entry/set_items/clear. Изменять напрямую нельзя - разойдётся с entries.
	items       []string
	selected    int = -1
	open        bool
	visible     bool = true
	enabled     bool = true
	tooltip     string // всплывающая подсказка ("" - нет); показывает окно (tooltip_manager.v)
	dnd         &DragSpec = unsafe { nil } // роль в перетаскивании (nil - нет); ведёт окно, см. dnd.v
	focused     bool
	hovered     bool
	hover_index int = -1
	// Плавная подсветка рамки/кольцо фокуса, 0..1 (см. Anim).
	focus_anim  Anim = anim_role(.focus)
	focus_group int
	item_height f32 = 26
	// размер иконки пункта и зазор до текста (если у пунктов есть иконки)
	icon_size f32 = 16
	icon_gap  f32 = 6
	// Сколько строк видно в popup без прокрутки (по первым max_visible строкам считается высота popup).
	max_visible int = 8
	scroll_y    f32
	// Пикселей прокрутки за один «щелчок» колеса.
	scroll_speed f32 = 26
	pad          f32 = 6
	placeholder  string // '' - перевод ключа combo.placeholder (eff_placeholder)
	on_change    fn (int, string) = unsafe { nil }
	// Internal: dropdown direction & scrollbar drag
	// Внутреннее состояние popup: направление раскрытия и перетаскивание ползунка полосы прокрутки
	// (sb_drag_start_* - позиция мыши и scroll_y в момент нажатия).
	drop_dir             DropDir = .down
	sb_dragging          bool
	sb_hovered           bool
	sb_drag_start_y      f32
	sb_drag_start_scroll f32
}

// eff_placeholder - подсказка пустого выбора: заданная placeholder или перевод
// combo.placeholder на язык интерфейса (раньше по умолчанию стояла русская строка).
pub fn (cb &ComboBox) eff_placeholder() string {
	return if cb.placeholder.len > 0 { cb.placeholder } else { tr('combo.placeholder') }
}

// ─── Constructors ──────────────────────────────────────

pub fn combo_box() &ComboBox {
	return &ComboBox{}
}

// ─── Item management (new widget-capable API) ──────────

// add_entry добавляет элемент и синхронно обновляет зеркало items. Остальные add_* сводятся к нему.
pub fn (mut cb ComboBox) add_entry(entry ComboItem) {
	cb.entries << entry
	cb.items << entry.text
}

pub fn (mut cb ComboBox) add_text_item(text string) {
	cb.add_entry(ComboItem{ text: text })
}

// add_icon_item - текстовый пункт с иконкой слева (Lucide, файл, байты - item_icon.v).
pub fn (mut cb ComboBox) add_icon_item(text string, ic ItemIcon) {
	cb.add_entry(ComboItem{ text: text, icon: ic })
}

// set_item_icon меняет иконку пункта idx (ItemIcon{} - убрать); неверный индекс игнорируется.
pub fn (mut cb ComboBox) set_item_icon(idx int, ic ItemIcon) {
	if idx >= 0 && idx < cb.entries.len {
		cb.entries[idx].icon = ic
	}
}

// add_widget_item - элемент-виджет: в popup рисуется widget (ему раздаются bounds ячейки), text - подпись для закрытого вида.
pub fn (mut cb ComboBox) add_widget_item(text string, widget &Widget) {
	cb.add_entry(ComboItem{ text: text, widget: unsafe { widget } })
}

// add_widget_item_sized - то же с собственной высотой строки height.
pub fn (mut cb ComboBox) add_widget_item_sized(text string, widget &Widget, height f32) {
	cb.add_entry(ComboItem{ text: text, widget: unsafe { widget }, height: height })
}

// set_item_widget / set_item_height / set_item_data меняют элемент по индексу; неверный индекс молча игнорируется.
pub fn (mut cb ComboBox) set_item_widget(idx int, widget &Widget) {
	if idx >= 0 && idx < cb.entries.len {
		cb.entries[idx].widget = unsafe { widget }
	}
}

pub fn (mut cb ComboBox) set_item_height(idx int, h f32) {
	if idx >= 0 && idx < cb.entries.len {
		cb.entries[idx].height = h
	}
}

pub fn (mut cb ComboBox) set_item_data(idx int, data voidptr) {
	if idx >= 0 && idx < cb.entries.len {
		cb.entries[idx].user_data = data
	}
}

// get_item_data возвращает user_data элемента или nil при неверном индексе.
pub fn (cb &ComboBox) get_item_data(idx int) voidptr {
	if idx >= 0 && idx < cb.entries.len {
		return cb.entries[idx].user_data
	}
	return unsafe { nil }
}

// get_entry возвращает копию элемента; для неверного индекса - пустой ComboItem.
pub fn (cb &ComboBox) get_entry(idx int) ComboItem {
	if idx >= 0 && idx < cb.entries.len {
		return cb.entries[idx]
	}
	return ComboItem{}
}

// ─── Legacy text API (preserved) ───────────────────────

// set_items заменяет весь список текстами, сбрасывает выбор (-1) и прокрутку. on_change не вызывается.
pub fn (mut cb ComboBox) set_items(items []string) {
	cb.entries.clear()
	cb.items.clear()
	for s in items {
		cb.add_text_item(s)
	}
	cb.selected = -1
	cb.scroll_y = 0
}

pub fn (mut cb ComboBox) add_item(text string) {
	cb.add_text_item(text)
}

pub fn (mut cb ComboBox) add_items(items []string) {
	for item in items {
		cb.add_text_item(item)
	}
}

// set_selected выбирает элемент программно (on_change не вызывается); неверный индекс игнорируется.
pub fn (mut cb ComboBox) set_selected(idx int) {
	if idx >= 0 && idx < cb.entries.len {
		cb.selected = idx
	}
}

// set_selected_text выбирает первый элемент с точно таким текстом; если не найден - выбор не меняется.
pub fn (mut cb ComboBox) set_selected_text(text string) {
	for i, e in cb.entries {
		if e.text == text {
			cb.selected = i
			return
		}
	}
}

pub fn (cb &ComboBox) get_selected_text() string {
	if cb.selected >= 0 && cb.selected < cb.entries.len {
		return cb.entries[cb.selected].text
	}
	return ''
}

// clear очищает список, выбор и прокрутку и помечает список закрытым. Оверлей при этом не снимается;
// если popup был открыт, он погаснет сам (draw/ev оверлея проверяют cb.open).
pub fn (mut cb ComboBox) clear() {
	cb.entries.clear()
	cb.items.clear()
	cb.selected = -1
	cb.scroll_y = 0
	cb.open = false
}

// ─── Geometry helpers ──────────────────────────────────

// eff_item_h - эффективная высота строки: собственная height элемента или общая item_height.
fn (cb &ComboBox) eff_item_h(idx int) f32 {
	if idx >= 0 && idx < cb.entries.len && cb.entries[idx].height > 0 {
		return cb.entries[idx].height
	}
	return cb.item_height
}

fn (cb &ComboBox) content_height() f32 {
	mut h := f32(0)
	for i in 0 .. cb.entries.len {
		h += cb.eff_item_h(i)
	}
	return h
}

// item_offset - сдвиг верха строки idx от начала содержимого (сумма высот предыдущих строк).
fn (cb &ComboBox) item_offset(idx int) f32 {
	mut y := f32(0)
	for i in 0 .. idx {
		y += cb.eff_item_h(i)
	}
	return y
}

// dropdown_height - высота popup: сумма высот первых max_visible строк плюс отступы pad сверху и снизу.
fn (cb &ComboBox) dropdown_height() f32 {
	if cb.entries.len == 0 {
		return cb.pad * 2
	}
	// Sum heights of up to max_visible items
	count := min_int(cb.entries.len, cb.max_visible)
	mut h := f32(0)
	for i in 0 .. count {
		h += cb.eff_item_h(i)
	}
	return h + cb.pad * 2
}

// dropdown_rect - прямоугольник popup под (или над) полем с зазором 2 px; ширина равна ширине поля.
fn (cb &ComboBox) dropdown_rect() Rect {
	dh := cb.dropdown_height()
	match cb.drop_dir {
		.down {
			return Rect{cb.bounds.x, cb.bounds.y + cb.bounds.h + 2, cb.bounds.w, dh}
		}
		.up {
			return Rect{cb.bounds.x, cb.bounds.y - dh - 2, cb.bounds.w, dh}
		}
	}
}

// max_scroll - максимальный scroll_y: высота всего содержимого минус видимая высота (не меньше 0).
fn (cb &ComboBox) max_scroll() f32 {
	dr := cb.dropdown_rect()
	inner_h := dr.h - cb.pad * 2
	return max_f32(0, cb.content_height() - inner_h)
}

// hit_dropdown_item - индекс строки под экранной координатой Y мыши или -1 (над списком/ниже последней).
// rel_y переводит Y в систему координат содержимого с учётом отступа и прокрутки.
fn (cb &ComboBox) hit_dropdown_item(my f32) int {
	dr := cb.dropdown_rect()
	rel_y := my - dr.y - cb.pad + cb.scroll_y
	if rel_y < 0 {
		return -1
	}
	mut acc := f32(0)
	for i in 0 .. cb.entries.len {
		h := cb.eff_item_h(i)
		if rel_y >= acc && rel_y < acc + h {
			return i
		}
		acc += h
	}
	return -1
}

fn (cb &ComboBox) has_dropdown_scrollbar() bool {
	dr := cb.dropdown_rect()
	inner_h := dr.h - cb.pad * 2
	return cb.content_height() > inner_h
}

// scrollbar_rects - прямоугольники дорожки и ползунка полосы прокрутки popup (пара пустых Rect, если всё
// помещается). Высота ползунка пропорциональна доле видимого, но не меньше 20 px; положение - по
// отношению scroll_y / max_scroll.
fn (cb &ComboBox) scrollbar_rects() (Rect, Rect) {
	dr := cb.dropdown_rect()
	inner := dr.shrunk(cb.pad)
	ch := cb.content_height()
	vis_h := inner.h

	if ch <= vis_h {
		return Rect{}, Rect{}
	}

	sb_w := f32(8)
	track := Rect{
		x: dr.x + dr.w - cb.pad - sb_w - 1
		y: inner.y
		w: sb_w
		h: vis_h
	}

	thumb_h := max_f32(20, vis_h * (vis_h / ch))
	ms := cb.max_scroll()
	ratio := if ms > 0 { cb.scroll_y / ms } else { f32(0) }
	thumb_y := track.y + ratio * (vis_h - thumb_h)

	thumb := Rect{
		x: track.x + 1
		y: thumb_y
		w: sb_w - 2
		h: thumb_h
	}

	return track, thumb
}

// ensure_visible_in_dropdown подкручивает popup так, чтобы выбранная строка была видна целиком.
fn (mut cb ComboBox) ensure_visible_in_dropdown() {
	if cb.selected < 0 || cb.entries.len == 0 {
		return
	}
	dr := cb.dropdown_rect()
	inner_h := dr.h - cb.pad * 2
	item_top := cb.item_offset(cb.selected)
	item_bot := item_top + cb.eff_item_h(cb.selected)
	if item_top < cb.scroll_y {
		cb.scroll_y = item_top
	}
	if item_bot > cb.scroll_y + inner_h {
		cb.scroll_y = item_bot - inner_h
	}
	cb.scroll_y = clamp_f32(cb.scroll_y, 0, cb.max_scroll())
}

// fire_change вызывает on_change(индекс, текст) для текущего выбора, если колбэк задан и выбор корректен.
fn (mut cb ComboBox) fire_change() {
	if cb.on_change != unsafe { nil } && cb.selected >= 0 && cb.selected < cb.entries.len {
		cb.on_change(cb.selected, cb.entries[cb.selected].text)
	}
}

// close_dropdown закрывает popup: сбрасывает состояние полосы прокрутки и снимает оверлей (владелец - адрес виджета).
fn (mut cb ComboBox) close_dropdown(mut ctx RenderContext) {
	cb.open = false
	cb.sb_dragging = false
	cb.sb_hovered = false
	ctx.clear_overlay(voidptr(&cb))
}

// calc_drop_direction выбирает направление раскрытия: вниз, если popup помещается под полем; иначе вверх,
// если помещается над; иначе туда, где места больше (popup тогда обрежется краем окна).
fn (mut cb ComboBox) calc_drop_direction(ctx &RenderContext) {
	dh := cb.dropdown_height()
	space_below := ctx.screen_height - (cb.bounds.y + cb.bounds.h + 2)
	space_above := cb.bounds.y - 2

	if dh <= space_below {
		cb.drop_dir = .down
	} else if dh <= space_above {
		cb.drop_dir = .up
	} else {
		cb.drop_dir = if space_below >= space_above { .down } else { .up }
	}
}

// Dispatch an event to the visible cell widgets. Returns true if handled.
fn (mut cb ComboBox) dispatch_to_item_widgets(event &GuiEvent, app &App) bool {
	if cb.entries.len == 0 {
		return false
	}
	dr := cb.dropdown_rect()
	inner := dr.shrunk(cb.pad)
	sb_w := if cb.has_dropdown_scrollbar() { f32(8) } else { f32(0) }
	text_w := inner.w - (if sb_w > 0 { sb_w + 4 } else { f32(0) })

	mut acc := f32(0)
	for i in 0 .. cb.entries.len {
		h := cb.eff_item_h(i)
		iy := inner.y + acc - cb.scroll_y
		acc += h
		if unsafe { cb.entries[i].widget == nil } {
			continue
		}
		if iy + h < inner.y || iy > inner.y + inner.h {
			continue
		}
		r := Rect{inner.x, iy, text_w, h}
		mut w := unsafe { cb.entries[i].widget }
		set_widget_bounds(mut w, r)
		if w.handle_event(event, app) {
			return true
		}
	}
	return false
}

// open_dropdown открывает popup и регистрирует оверлей окна: три замыкания draw / ev / close,
// захватывающие cb. Пока оверлей установлен, события окна сначала получает ev; он должен вернуть
// true, чтобы «съесть» событие. Положение popup пересчитывается на каждом кадре из bounds поля,
// так что оно следует за виджетом.
fn (mut cb ComboBox) open_dropdown(mut ctx RenderContext) {
	cb.open = true
	cb.sb_dragging = false
	cb.sb_hovered = false
	cb.calc_drop_direction(ctx)
	cb.ensure_visible_in_dropdown()

	// Отрисовка popup: тень, фон, рамка, затем строки внутри clip-области; строки вне видимой части пропускаются (continue/break). Виджет-ячейке на каждый кадр выдаются bounds строки.
	// ─── Overlay draw ─────────────────────────────────
	draw := fn [mut cb] (mut ctx RenderContext) {
		if !cb.open || cb.entries.len == 0 {
			return
		}
		font := ctx.get_font(.regular, 0)
		fh := ctx.font_height_of(font)
		dr := cb.dropdown_rect()
		rad := ctx.theme.border_radius

		if ctx.theme.shadow_offset > 0 {
			ctx.draw_shadow(dr, rad)
		}
		ctx.fill_rounded_rect(dr, ctx.theme.eff_cb_dropdown_bg(), rad)
		ctx.draw_rounded_rect(dr, ctx.theme.eff_cb_dropdown_border(), rad)

		inner := dr.shrunk(cb.pad)
		sb_w := f32(8)
		text_w := if cb.has_dropdown_scrollbar() { inner.w - sb_w - 4 } else { inner.w }

		ctx.push_clip(inner)

		mut acc := f32(0)
		for i, entry in cb.entries {
			h := cb.eff_item_h(i)
			iy := inner.y + acc - cb.scroll_y
			acc += h
			if iy + h < inner.y {
				continue
			}
			if iy > inner.y + inner.h {
				break
			}

			item_r := Rect{inner.x, iy, text_w, h}

			if i == cb.selected {
				ctx.fill_rounded_rect(item_r, ctx.theme.eff_cb_item_selected().with_alpha(180), 3)
			} else if i == cb.hover_index {
				ctx.fill_rounded_rect(item_r, ctx.theme.eff_cb_item_hover().with_alpha(100), 3)
			}

			if unsafe { entry.widget != nil } {
				mut w := unsafe { entry.widget }
				set_widget_bounds(mut w, item_r)
				ctx.push_clip(item_r)
				ctx.draw_child(mut w)
				ctx.pop_clip()
			} else {
				tc := if i == cb.selected {
					ctx.theme.eff_cb_item_sel_text()
				} else {
					ctx.theme.eff_cb_item_text()
				}
				ty := iy + (h - fh) * 0.5
				mut tx := inner.x + 6
				if entry.icon.is_set() {
					ctx.draw_item_icon(entry.icon, Rect{tx, iy, cb.icon_size, h}, cb.icon_size,
						tc)
					tx += cb.icon_size + cb.icon_gap
				}
				ctx.draw_text_with_font(entry.text, tx, ty, tc, font)
			}
		}

		ctx.pop_clip()

		// ── Scrollbar ──
		if cb.has_dropdown_scrollbar() {
			track, thumb := cb.scrollbar_rects()
			track_c := ctx.theme.scrollbar_bg
			if track_c.a > 0 {
				ctx.fill_rounded_rect(track, track_c, 3)
			}
			thumb_c := if cb.sb_dragging {
				ctx.theme.scrollbar_drag
			} else if cb.sb_hovered {
				ctx.theme.scrollbar_hover
			} else {
				ctx.theme.scrollbar_thumb
			}
			ctx.fill_rounded_rect(thumb, thumb_c, 3)
		}
	}

	// Обработчик событий popup. Порядок: (1) идущее перетаскивание ползунка поглощает всё; (2) move/up/wheel
	// сперва пробуются на виджетах-ячейках; (3) по типу события: наведение, клик (ползунок / страницы по
	// дорожке / ячейка / выбор строки; клик вне popup закрывает его и поглощается), колесо (возвращает
	// false на границе - событие уйдёт дальше), клавиши (работают только при focused).
	// ─── Overlay event handler ────────────────────────
	ev := fn [mut cb] (event &GuiEvent, app &App) bool {
		if !cb.open {
			return false
		}

		// Перетаскивание ползунка: смещение мыши dy переводится в прокрутку через масштаб max_scroll / (длина дорожки - высота ползунка).
		// ── Scrollbar drag in progress ──
		if cb.sb_dragging {
			match event.typ {
				.mouse_move {
					track, _ := cb.scrollbar_rects()
					if track.h <= 0 {
						return true
					}
					ch := cb.content_height()
					vis_h := track.h
					thumb_h := max_f32(20, vis_h * (vis_h / ch))
					drag_range := vis_h - thumb_h
					if drag_range <= 0 {
						return true
					}
					dy := event.mouse_y - cb.sb_drag_start_y
					ms := cb.max_scroll()
					cb.scroll_y = clamp_f32(cb.sb_drag_start_scroll + dy * (ms / drag_range), 0, ms)
					return true
				}
				.mouse_up {
					if event.mouse_btn == .left {
						cb.sb_dragging = false
						return true
					}
				}
				else {}
			}

			return true
		}

		dr := cb.dropdown_rect()

		// ── Forward to cell widgets first (mouse move / up / wheel) ──
		if event.typ == .mouse_move || event.typ == .mouse_up || event.typ == .mouse_wheel {
			if cb.dispatch_to_item_widgets(event, app) {
				return true
			}
		}

		match event.typ {
			.mouse_move {
				if dr.contains(event.mouse_x, event.mouse_y) {
					if cb.has_dropdown_scrollbar() {
						track, _ := cb.scrollbar_rects()
						if track.contains(event.mouse_x, event.mouse_y) {
							cb.sb_hovered = true
							cb.hover_index = -1
							return true
						} else {
							cb.sb_hovered = false
						}
					}
					cb.hover_index = cb.hit_dropdown_item(event.mouse_y)
				} else {
					cb.hover_index = -1
					cb.sb_hovered = false
				}
				return true
			}
			.mouse_down {
				if event.mouse_btn == .left {
					if dr.contains(event.mouse_x, event.mouse_y) {
						// Клик по ползунку начинает перетаскивание; по дорожке выше/ниже ползунка - прокрутка на страницу.
						// Scrollbar thumb drag
						if cb.has_dropdown_scrollbar() {
							track, thumb := cb.scrollbar_rects()
							if thumb.contains(event.mouse_x, event.mouse_y) {
								cb.sb_dragging = true
								cb.sb_drag_start_y = event.mouse_y
								cb.sb_drag_start_scroll = cb.scroll_y
								return true
							}
							if track.contains(event.mouse_x, event.mouse_y) {
								vis_h := track.h
								if event.mouse_y < thumb.y {
									cb.scroll_y = max_f32(0, cb.scroll_y - vis_h)
								} else {
									cb.scroll_y = min_f32(cb.max_scroll(), cb.scroll_y + vis_h)
								}
								return true
							}
						}

						// Try cell widget first — if it handles the click, don't select
						if cb.dispatch_to_item_widgets(event, app) {
							return true
						}

						// Выбор строки: фиксируем selected, уведомляем и закрываем popup (даже при idx < 0, т.е. клик в отступ).
						idx := cb.hit_dropdown_item(event.mouse_y)
						if idx >= 0 {
							cb.selected = idx
							cb.fire_change()
						}
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							cb.close_dropdown(mut ctx_mut)
						}
						return true
					} else {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							cb.close_dropdown(mut ctx_mut)
						}
						return true
					}
				}
			}
			.mouse_wheel {
				// Колесо: координаты берём из активного контекста (там актуальная позиция мыши), событие - запасной вариант.
				ctx_ptr := app.get_active_ctx()
				mut mx := event.mouse_x
				mut my := event.mouse_y
				if unsafe { ctx_ptr != nil } {
					mx = ctx_ptr.mouse_x
					my = ctx_ptr.mouse_y
				}
				if dr.contains(mx, my) {
					old := cb.scroll_y
					cb.scroll_y -= event.wheel_y * cb.scroll_speed
					cb.scroll_y = clamp_f32(cb.scroll_y, 0, cb.max_scroll())
					if cb.scroll_y != old {
						return true
					}
				}
			}
			.key_down {
				if !cb.focused {
					return false
				}

				// Клавиши в открытом popup: Home/End/PgUp/PgDn/стрелки сразу меняют selected и вызывают on_change (без отдельного «подтверждения»); стрелки циклические. Enter/Space/Esc закрывают, Tab закрывает и не поглощается (фокус уйдёт дальше).
				if is_home_key(event.keycode, event.scancode) {
					if cb.entries.len > 0 {
						cb.selected = 0
						cb.ensure_visible_in_dropdown()
						cb.fire_change()
					}
					return true
				}
				if is_end_key(event.keycode, event.scancode) {
					if cb.entries.len > 0 {
						cb.selected = cb.entries.len - 1
						cb.ensure_visible_in_dropdown()
						cb.fire_change()
					}
					return true
				}

				if tv_is_pageup_key(event.keycode, event.scancode) {
					if cb.entries.len > 0 {
						step := max_int(1, cb.max_visible)
						cb.selected = max_int(0, cb.selected - step)
						cb.ensure_visible_in_dropdown()
						cb.fire_change()
					}
					return true
				}
				if tv_is_pagedown_key(event.keycode, event.scancode) {
					if cb.entries.len > 0 {
						step := max_int(1, cb.max_visible)
						cb.selected = min_int(cb.entries.len - 1, cb.selected + step)
						cb.ensure_visible_in_dropdown()
						cb.fire_change()
					}
					return true
				}

				match event.keycode {
					sdl_k_escape {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							cb.close_dropdown(mut ctx_mut)
						}
						return true
					}
					sdl_k_return, sdl_k_space {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							cb.close_dropdown(mut ctx_mut)
						}
						return true
					}
					sdl_k_up {
						if cb.entries.len > 0 {
							if cb.selected <= 0 {
								cb.selected = cb.entries.len - 1
							} else {
								cb.selected -= 1
							}
							cb.ensure_visible_in_dropdown()
							cb.fire_change()
						}
						return true
					}
					sdl_k_down {
						if cb.entries.len > 0 {
							if cb.selected >= cb.entries.len - 1 {
								cb.selected = 0
							} else {
								cb.selected += 1
							}
							cb.ensure_visible_in_dropdown()
							cb.fire_change()
						}
						return true
					}
					sdl_k_tab {
						ctx_ptr := app.get_active_ctx()
						if unsafe { ctx_ptr != nil } {
							mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
							cb.close_dropdown(mut ctx_mut)
						}
						return false
					}
					else {}
				}
			}
			else {}
		}

		return false
	}

	ctx.set_overlay(voidptr(&cb), draw, ev, fn [mut cb] (mut ctx RenderContext) {
		cb.close_dropdown(mut ctx)
	})
}

// ───────────── Drawing ─────────────────────────────────

// draw рисует закрытое поле: регистрирует себя в фокус-учёте (если enabled), синхронизирует
// cb.focused с ctx.focus (потеря фокуса закрывает popup), анимирует рамку и рисует выбранный текст
// (или placeholder) с обрезкой по полю и стрелку-треугольник (вниз/вверх по open). Сам popup
// рисуется оверлеем, а не здесь.
pub fn (mut cb ComboBox) draw(mut ctx RenderContext) {
	en := ctx.is_enabled(cb.enabled)
	if !cb.visible {
		return
	}
	if !ctx.is_in_clip(cb.bounds) {
		return
	}

	if en {
		ctx.focus.register_combo_box(&cb, cb.focus_group)
	} else {
		if cb.open {
			cb.close_dropdown(mut ctx)
		}
		ctx.focus_block(&cb)
	}

	should_focus := ctx.focus.is_focused(unsafe { &cb })
	if cb.focused && !should_focus {
		cb.focused = false
		if cb.open {
			cb.close_dropdown(mut ctx)
		}
	} else if !cb.focused && should_focus {
		cb.focused = true
	}

	target_focus := if cb.focused && en { f32(1.0) } else { f32(0.0) }
	// Кольцо фокуса и подсветка рамки — внутри bounds (+1 px свечения).
	if cb.focus_anim.update(target_focus, ctx) {
		ctx.mark_anim_rect('combobox', cb.bounds.expanded(1))
	}

	rad := ctx.theme.border_radius
	bg := if en { ctx.theme.eff_cb_bg() } else { ctx.theme.eff_cb_bg().darken(0.05) }
	ctx.fill_rounded_rect(cb.bounds, bg, rad)

	bc := ctx.theme.eff_cb_border().blend(ctx.theme.input_focus, cb.focus_anim.value)
	ctx.draw_rounded_rect(cb.bounds, bc, rad)

	ctx.draw_focus_ring(cb.bounds, rad, cb.focus_anim.value)

	// ── Text ──
	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)
	ty := cb.bounds.y + (cb.bounds.h - fh) * 0.5

	arrow_w := f32(24)
	text_w := cb.bounds.w - cb.pad * 2 - arrow_w

	text_clip := Rect{cb.bounds.x + cb.pad, cb.bounds.y, text_w, cb.bounds.h}
	ctx.push_clip(text_clip)

	if cb.selected >= 0 && cb.selected < cb.entries.len {
		sel := cb.entries[cb.selected]
		stc := if en { ctx.theme.eff_cb_text() } else { ctx.theme.text_disabled }
		mut tx := cb.bounds.x + cb.pad
		if sel.icon.is_set() {
			ctx.draw_item_icon(sel.icon, Rect{tx, cb.bounds.y, cb.icon_size, cb.bounds.h},
				cb.icon_size, stc)
			tx += cb.icon_size + cb.icon_gap
		}
		ctx.draw_text_with_font(sel.text, tx, ty, stc, font)
	} else {
		ptc := if en { ctx.theme.text_secondary } else { ctx.theme.text_disabled }
		ctx.draw_text_with_font(cb.eff_placeholder(), cb.bounds.x + cb.pad, ty, ptc, font)
	}

	ctx.pop_clip()

	// ── Arrow ──
	ax := cb.bounds.x + cb.bounds.w - arrow_w
	ay := cb.bounds.y
	ah := cb.bounds.h

	cx := ax + arrow_w * 0.5
	cy := ay + ah * 0.5
	aw := f32(8)
	ahh := f32(5)
	ac := if en { ctx.theme.eff_cb_arrow() } else { ctx.theme.text_disabled }

	if cb.open {
		ctx.fill_triangle(cx, cy - ahh * 0.5, cx - aw * 0.5, cy + ahh * 0.5, cx + aw * 0.5, cy +
			ahh * 0.5, ac)
	} else {
		ctx.fill_triangle(cx, cy + ahh * 0.5, cx - aw * 0.5, cy - ahh * 0.5, cx + aw * 0.5,
			cy - ahh * 0.5, ac)
	}
}

// ───────────── Events ──────────────────────────────────

// handle_event обрабатывает события ЗАКРЫТОГО списка (пока popup открыт, события перехватывает оверлей).
// ЛКМ по полю: фокус и открытие/закрытие. С клавиатуры при фокусе: Enter/Space открывают, стрелки и
// Home/End меняют выбор без открытия, Tab/Esc двигают/снимают фокус. Возвращает true, если событие обработано.
pub fn (mut cb ComboBox) handle_event(event &GuiEvent, app &App) bool {
	if !cb.visible || !cb.enabled {
		return false
	}

	match event.typ {
		.mouse_move {
			cb.hovered = cb.bounds.contains(event.mouse_x, event.mouse_y)
		}
		.mouse_down {
			if event.mouse_btn == .left && cb.hovered {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					ctx_mut.focus.focus_combo_box(&cb, cb.focus_group)
					cb.focused = true
					if cb.open {
						cb.close_dropdown(mut ctx_mut)
					} else if cb.entries.len > 0 {
						cb.open_dropdown(mut ctx_mut)
					}
				}
				return true
			}
		}
		.key_down {
			if !cb.focused {
				return false
			}
			if cb.open {
				return false
			}

			if is_home_key(event.keycode, event.scancode) {
				if cb.entries.len > 0 {
					cb.selected = 0
					cb.fire_change()
				}
				return true
			}
			if is_end_key(event.keycode, event.scancode) {
				if cb.entries.len > 0 {
					cb.selected = cb.entries.len - 1
					cb.fire_change()
				}
				return true
			}

			match event.keycode {
				sdl_k_return, sdl_k_space {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						cb.open_dropdown(mut ctx_mut)
					}
					return true
				}
				sdl_k_up {
					if cb.entries.len > 0 {
						if cb.selected <= 0 {
							cb.selected = cb.entries.len - 1
						} else {
							cb.selected -= 1
						}
						cb.fire_change()
					}
					return true
				}
				sdl_k_down {
					if cb.entries.len > 0 {
						if cb.selected >= cb.entries.len - 1 {
							cb.selected = 0
						} else {
							cb.selected += 1
						}
						cb.fire_change()
					}
					return true
				}
				sdl_k_tab {
					ctx_ptr := app.get_active_ctx()
					if unsafe { ctx_ptr != nil } {
						mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
						ctx_mut.focus.tab(event.shift())
					}
					return true
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
		}
		else {}
	}

	return false
}
