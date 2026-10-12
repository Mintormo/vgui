module vgui

// ═══════════════════════════════════════════════════════
// Menu system — MenuBar + ContextMenu
// ═══════════════════════════════════════════════════════

// MenuItemKind — тип пункта меню: action (обычный пункт с on_click), checkbox
// (пункт с галочкой и on_toggle), separator (линия-разделитель, не выбирается),
// submenu (пункт, раскрывающий children во вложенном попапе).
pub enum MenuItemKind {
	action
	checkbox
	separator
	submenu
}

// MenuItem — один пункт меню. Не виджет в смысле раскладки: добавляется во
// владельца (MenuBar.add_menu, ContextMenu.add, MenuButton.add, MenuItem.add для
// подменю), а не в контейнер; тег типа нужен для C-ABI (vgui_resolve_widget).
//
// Меню общее для MenuBar, ContextMenu и MenuButton: все три рисуют попапы одними
// и теми же функциями menu_* из этого файла и хранят состояние в MenuState.
@[heap]
pub struct MenuItem {
pub mut:
	type_tag  int = kind_menu_item // тег типа, см. widget_tag.v
	text      string
	icon_path string
	// текст сочетания клавиш, например 'Ctrl+Shift+S'; и показывается справа в пункте, и разбирается menu_shortcut_matches
	shortcut  string
	kind      MenuItemKind = .action
	enabled   bool         = true
	checked   bool
	children  []&MenuItem
	on_click  fn ()     = unsafe { nil }
	on_toggle fn (bool) = unsafe { nil }
	// hovered / sub_open — состояние отрисовки/навигации, меняется самим меню (menu_update_hover, open_submenu); снаружи не трогать
	hovered  bool
	sub_open bool
}

// menu_action создаёт обычный пункт. Действие задаётся полем on_click.
pub fn menu_action(text string) &MenuItem {
	return &MenuItem{
		text: text
		kind: .action
	}
}

// menu_action_icon — обычный пункт с иконкой слева (icon_path — путь к картинке).
pub fn menu_action_icon(text string, icon_path string) &MenuItem {
	return &MenuItem{
		text:      text
		icon_path: icon_path
		kind:      .action
	}
}

// menu_checkbox создаёт пункт с галочкой; начальное состояние — checked, смена приходит в on_toggle(bool).
pub fn menu_checkbox(text string, checked bool) &MenuItem {
	return &MenuItem{
		text:    text
		kind:    .checkbox
		checked: checked
	}
}

// menu_separator создаёт разделитель (высота menu_sep_h, в навигации клавишами пропускается).
pub fn menu_separator() &MenuItem {
	return &MenuItem{
		kind: .separator
	}
}

// menu_submenu создаёт пункт-подменю; вложенные пункты добавляются через MenuItem.add.
pub fn menu_submenu(text string) &MenuItem {
	return &MenuItem{
		text: text
		kind: .submenu
	}
}

// add добавляет дочерний пункт (имеет смысл для kind == .submenu; рекурсия не ограничена).
pub fn (mut mi MenuItem) add(child &MenuItem) {
	mi.children << unsafe { child }
}

// Геометрия попапа меню (логические пиксели, до ui_scale): высота пункта и
// разделителя, внутренний отступ попапа, размер и ширина колонки иконки/галочки
// (слева от текста), ширина колонки стрелки подменю, зазор перед шорткатом.
const menu_item_h = f32(26)
const menu_sep_h = f32(9)
const menu_pad = f32(4)
const menu_icon_sz = f32(16)
const menu_icon_col_w = f32(24)
const menu_arrow_w = f32(16)
const menu_shortcut_gap = f32(24)
const menu_check_sz = f32(12)

// menu_popup_size считает размер попапа для items: высота — сумма высот пунктов и
// разделителей плюс отступы; ширина — колонка иконки + самый широкий текст
// (+ зазор и самый широкий шорткат, если они есть) + колонка стрелки, если есть
// подменю, но не меньше 120. Шрифт берётся через get_font_immut
// (ctx здесь неизменяемый).
fn menu_popup_size(items []&MenuItem, ctx &RenderContext) Vec2 {
	font := ctx.get_font_immut(.regular, 0)
	mut max_text_w := f32(0)
	mut max_sc_w := f32(0)
	mut total_h := menu_pad * 2
	for mi in items {
		if mi.kind == .separator {
			total_h += menu_sep_h
			continue
		}
		tw := ctx.measure_text_with_font(mi.text, font).x
		if tw > max_text_w {
			max_text_w = tw
		}
		if mi.shortcut.len > 0 {
			sw := ctx.measure_text_with_font(mi.shortcut, font).x
			if sw > max_sc_w {
				max_sc_w = sw
			}
		}
		total_h += menu_item_h
	}
	mut w := menu_icon_col_w + max_text_w + menu_pad * 2 + 8
	if max_sc_w > 0 {
		w += menu_shortcut_gap + max_sc_w
	}
	mut has_sub := false
	for mi in items {
		if mi.kind == .submenu {
			has_sub = true
			break
		}
	}
	if has_sub {
		w += menu_arrow_w
	}
	w = max_f32(w, 120)
	return Vec2{w, total_h}
}

// menu_adjust_rect сдвигает прямоугольник попапа так, чтобы он помещался в окно
// (ctx.screen_width/height) с зазором 2 px; приоритет у левого/верхнего края —
// если попап больше окна, он прижмётся к (2, 2) и обрежется справа/снизу.
fn menu_adjust_rect(x f32, y f32, w f32, h f32, ctx &RenderContext) Rect {
	mut rx := x
	mut ry := y
	if rx + w > ctx.screen_width {
		rx = ctx.screen_width - w - 2
	}
	if rx < 0 {
		rx = 2
	}
	if ry + h > ctx.screen_height {
		ry = ctx.screen_height - h - 2
	}
	if ry < 0 {
		ry = 2
	}
	return Rect{rx, ry, w, h}
}

// menu_item_rect возвращает прямоугольник пункта idx в попапе с углом (px, py) и
// шириной popup_w (разделитель — на всю ширину, обычный пункт — с отступом
// menu_pad по краям). Пустой Rect, если индекс вне списка.
fn menu_item_rect(items []&MenuItem, idx int, px f32, py f32, popup_w f32) Rect {
	mut iy := py + menu_pad
	for i in 0 .. items.len {
		mi := items[i]
		if mi.kind == .separator {
			if i == idx {
				return Rect{px, iy, popup_w, menu_sep_h}
			}
			iy += menu_sep_h
		} else {
			if i == idx {
				return Rect{px + menu_pad, iy, popup_w - menu_pad * 2, menu_item_h}
			}
			iy += menu_item_h
		}
	}
	return Rect{}
}

// menu_hit_item возвращает индекс пункта под точкой (mx, my) или -1.
// Разделители не попадаются (их высота пропускается, но не проверяется).
fn menu_hit_item(items []&MenuItem, mx f32, my f32, px f32, py f32, popup_w f32) int {
	mut iy := py + menu_pad
	for i, mi in items {
		if mi.kind == .separator {
			iy += menu_sep_h
			continue
		}
		ir := Rect{px + menu_pad, iy, popup_w - menu_pad * 2, menu_item_h}
		if ir.contains(mx, my) {
			return i
		}
		iy += menu_item_h
	}
	return -1
}

// menu_draw_popup рисует один уровень меню: тень, фон с рамкой, затем пункты
// сверху вниз. Отключённый пункт рисуется серым без подсветки и без иконки.
// Подсвечен hovered-пункт и пункт с открытым подменю (sub_open). Шорткаты
// выравниваются по общему правому краю sc_right, чтобы колонка была ровной.
fn menu_draw_popup(items []&MenuItem, popup Rect, mut ctx RenderContext) {
	rad := ctx.theme.border_radius
	if ctx.theme.shadow_offset > 0 {
		ctx.draw_shadow(popup, rad)
	}
	ctx.fill_rounded_rect(popup, ctx.theme.eff_menu_bg(), rad)
	ctx.draw_rounded_rect(popup, ctx.theme.eff_menu_border(), rad)

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)

	// Determine right-side reserved width: arrow column + right padding
	mut has_sub := false
	for mi in items {
		if mi.kind == .submenu {
			has_sub = true
			break
		}
	}
	arrow_col := if has_sub { menu_arrow_w } else { f32(0) }
	// Right edge for shortcut text (shared across all items for alignment)
	// ir right edge = popup.x + menu_pad + (popup.w - menu_pad*2) = popup.x + popup.w - menu_pad
	sc_right := popup.x + popup.w - menu_pad - arrow_col - 4

	mut iy := popup.y + menu_pad
	for mi in items {
		if mi.kind == .separator {
			sep_y := iy + menu_sep_h * 0.5
			ctx.fill_rect(Rect{popup.x + menu_pad + 4, sep_y, popup.w - menu_pad * 2 - 8, 1},
				ctx.theme.eff_menu_separator())
			iy += menu_sep_h
			continue
		}

		ir := Rect{popup.x + menu_pad, iy, popup.w - menu_pad * 2, menu_item_h}

		if !mi.enabled {
			ty := iy + (menu_item_h - fh) * 0.5
			ctx.draw_text_with_font(mi.text, ir.x + menu_icon_col_w, ty, ctx.theme.text_disabled,
				font)
			iy += menu_item_h
			continue
		}

		if mi.hovered || mi.sub_open {
			ctx.fill_rounded_rect(ir, ctx.theme.eff_menu_item_hover().with_alpha(180), 3)
		}

		tc := if mi.hovered || mi.sub_open {
			ctx.theme.eff_menu_item_sel_text()
		} else {
			ctx.theme.eff_menu_item_text()
		}

		icon_x := ir.x + 4
		icon_cy := iy + menu_item_h * 0.5

		if mi.kind == .checkbox {
			cb_sz := menu_check_sz
			cb_x := icon_x
			cb_y := icon_cy - cb_sz * 0.5
			if mi.checked {
				s := cb_sz * 0.3
				cx := cb_x + cb_sz * 0.5
				cy := cb_y + cb_sz * 0.5
				ctx.draw_line_thick(cx - s, cy, cx - s * 0.3, cy + s * 0.7, 2, tc)
				ctx.draw_line_thick(cx - s * 0.3, cy + s * 0.7, cx + s, cy - s * 0.5, 2, tc)
			}
		} else if mi.icon_path.len > 0 {
			icon_tex := ctx.load_icon_texture(mi.icon_path)
			ctx.draw_icon(icon_tex, icon_x, icon_cy - menu_icon_sz * 0.5, menu_icon_sz,
				menu_icon_sz)
		}

		ty := iy + (menu_item_h - fh) * 0.5
		ctx.draw_text_with_font(mi.text, ir.x + menu_icon_col_w, ty, tc, font)

		if mi.shortcut.len > 0 {
			sw := ctx.measure_text_with_font(mi.shortcut, font).x
			sc_tc := if mi.hovered { tc } else { ctx.theme.eff_menu_shortcut_text() }
			ctx.draw_text_with_font(mi.shortcut, sc_right - sw, ty, sc_tc, font)
		}

		if mi.kind == .submenu && mi.children.len > 0 {
			ax := ir.x + ir.w - 10
			ay := icon_cy
			as_ := f32(4)
			ctx.fill_triangle(ax, ay - as_, ax, ay + as_, ax + as_, ay, tc)
		}

		iy += menu_item_h
	}
}

// Помощники над списком пунктов. Пункты хранятся как []&MenuItem; мутация идёт через unsafe-копию указателя, потому что элементы массива неизменяемы по правилам V.
// ─── MenuItem helpers ──────────────────────────────────

fn menu_set_hovered(items []&MenuItem, idx int, val bool) {
	if idx >= 0 && idx < items.len {
		mut mi := unsafe { items[idx] }
		mi.hovered = val
	}
}

// menu_clear_all_hover снимает подсветку со всех пунктов списка.
fn menu_clear_all_hover(items []&MenuItem) {
	for i in 0 .. items.len {
		mut mi := unsafe { items[i] }
		mi.hovered = false
	}
}

// menu_clear_all_state снимает подсветку и признак открытого подменю (при закрытии уровня).
fn menu_clear_all_state(items []&MenuItem) {
	for i in 0 .. items.len {
		mut mi := unsafe { items[i] }
		mi.hovered = false
		mi.sub_open = false
	}
}

fn menu_set_sub_open(items []&MenuItem, idx int, val bool) {
	if idx >= 0 && idx < items.len {
		mut mi := unsafe { items[idx] }
		mi.sub_open = val
	}
}

fn menu_toggle_checked(items []&MenuItem, idx int) {
	if idx >= 0 && idx < items.len {
		mut mi := unsafe { items[idx] }
		mi.checked = !mi.checked
	}
}

fn menu_get_checked(items []&MenuItem, idx int) bool {
	if idx >= 0 && idx < items.len {
		return items[idx].checked
	}
	return false
}

// menu_update_hover подсвечивает ровно один пункт found_idx (если он включён и не разделитель), у остальных подсветку снимает.
fn menu_update_hover(items []&MenuItem, found_idx int) {
	for i in 0 .. items.len {
		mi := items[i]
		val := i == found_idx && mi.enabled && mi.kind != .separator
		menu_set_hovered(items, i, val)
	}
}

// ─── Shortcut matching (NEW) ───────────────────────────

// menu_shortcut_matches проверяет, соответствует ли key_down-событие строке
// шортката вида 'Ctrl+Shift+S', 'Alt+F4', 'F5'. Регистр не важен, части делятся
// по '+'. Модификаторы должны совпадать ТОЧНО (лишний Shift — не совпадение).
// Одиночный символ сравнивается с keycode как есть (SDL-коды букв и цифр
// совпадают с ASCII в нижнем регистре); именованные клавиши — через таблицу
// ниже; неизвестное имя клавиши — не совпадение.
fn menu_shortcut_matches(shortcut string, event &GuiEvent) bool {
	if shortcut.len == 0 {
		return false
	}
	parts := shortcut.to_lower().split('+')
	mut need_ctrl := false
	mut need_shift := false
	mut need_alt := false
	mut key_part := ''
	for p in parts {
		t := p.trim_space()
		if t == 'ctrl' {
			need_ctrl = true
		} else if t == 'shift' {
			need_shift = true
		} else if t == 'alt' {
			need_alt = true
		} else {
			key_part = t
		}
	}
	if need_ctrl != event.ctrl() {
		return false
	}
	if need_shift != event.shift() {
		return false
	}
	if need_alt != event.alt() {
		return false
	}
	if key_part.len == 0 {
		return false
	}

	// ── Single character keys (a-z, 0-9) ──
	if key_part.len == 1 {
		ch := key_part[0]
		// Letters a-z → SDLK codes 97-122
		if ch >= `a` && ch <= `z` {
			return event.keycode == int(ch)
		}
		// Digits 0-9 → SDLK codes 48-57
		if ch >= `0` && ch <= `9` {
			return event.keycode == int(ch)
		}
		// Other single chars (-, =, [, ], etc.)
		return event.keycode == int(ch)
	}

	// ── Named keys ──
	expected := match key_part {
		'space' { sdl_k_space }
		'return', 'enter' { sdl_k_return }
		'escape', 'esc' { sdl_k_escape }
		'backspace' { sdl_k_backspace }
		'tab' { sdl_k_tab }
		'delete', 'del' { sdl_k_delete }
		'insert', 'ins' { sdl_k_insert }
		'home' { sdl_k_home }
		'end' { sdl_k_end }
		'pageup', 'pgup' { sdl_k_pageup }
		'pagedown', 'pgdn' { sdl_k_pagedown }
		'up' { sdl_k_up }
		'down' { sdl_k_down }
		'left' { sdl_k_left }
		'right' { sdl_k_right }
		'f1' { sdl_k_f1 }
		'f2' { sdl_k_f2 }
		'f3' { sdl_k_f3 }
		'f4' { sdl_k_f4 }
		'f5' { sdl_k_f5 }
		'f6' { sdl_k_f6 }
		'f7' { sdl_k_f7 }
		'f8' { sdl_k_f8 }
		'f9' { sdl_k_f9 }
		'f10' { sdl_k_f10 }
		'f11' { sdl_k_f11 }
		'f12' { sdl_k_f12 }
		else { -1 }
	}

	if expected < 0 {
		return false
	}
	return event.keycode == expected
}

// menu_try_shortcut ищет в items (с обходом подменю в глубину) включённый пункт
// с подходящим шорткатом и выполняет его: у checkbox переключает галочку и зовёт
// on_toggle, у action зовёт on_click. Возвращает true, если пункт сработал
// (тогда событие считается обработанным). Зовётся, когда попап закрыт.
fn menu_try_shortcut(items []&MenuItem, event &GuiEvent) bool {
	for mi in items {
		if mi.kind == .separator || !mi.enabled {
			continue
		}
		if mi.kind == .submenu {
			if menu_try_shortcut(mi.children, event) {
				return true
			}
			continue
		}
		if mi.shortcut.len > 0 && menu_shortcut_matches(mi.shortcut, event) {
			if mi.kind == .checkbox {
				mut mmi := unsafe { mi }
				mmi.checked = !mmi.checked
				if mi.on_toggle != unsafe { nil } {
					mi.on_toggle(mmi.checked)
				}
			} else {
				if mi.on_click != unsafe { nil } {
					mi.on_click()
				}
			}
			return true
		}
	}
	return false
}

// ─── Navigate selectable items (NEW) ───────────────────

// menu_next_selectable ищет следующий выбираемый пункт (не разделитель и
// включённый) от позиции from в направлении dir (+1/-1) с циклическим
// переходом через края. from = -1 при dir = 1 даёт первый пункт. Возвращает -1,
// если выбирать нечего.
fn menu_next_selectable(items []&MenuItem, from int, dir int) int {
	n := items.len
	if n == 0 {
		return -1
	}
	mut idx := from
	for _ in 0 .. n {
		idx += dir
		if idx < 0 {
			idx = n - 1
		}
		if idx >= n {
			idx = 0
		}
		mi := items[idx]
		if mi.kind != .separator && mi.enabled {
			return idx
		}
	}
	return -1
}

// ─── Activate hovered item (NEW) ───────────────────────

// menu_activate_hovered выполняет пункт idx уровня level (Enter/Space или клик).
// submenu — раскрывает (меню остаётся открытым); checkbox — переключает галочку,
// зовёт on_toggle и закрывает меню; action — СНАЧАЛА закрывает меню, потом
// зовёт on_click (так обработчик, открывающий другой попап, видит уже
// свободный слот оверлея). Отключённый пункт: возвращает true и
// ничего не делает. false — только при неверных level/idx.
fn menu_activate_hovered(mut ms MenuState, level int, idx int, mut ctx RenderContext) bool {
	if level >= ms.levels.len || idx < 0 || idx >= ms.levels[level].items.len {
		return false
	}
	mi := ms.levels[level].items[idx]
	if !mi.enabled {
		return true
	}
	if mi.kind == .submenu {
		if !mi.sub_open {
			ms.open_submenu(level, idx, ctx)
		}
		return true
	}
	if mi.kind == .checkbox {
		menu_toggle_checked(ms.levels[level].items, idx)
		checked := menu_get_checked(ms.levels[level].items, idx)
		if mi.on_toggle != unsafe { nil } {
			mi.on_toggle(checked)
		}
		ms.close_all(mut ctx)
		return true
	}
	ms.close_all(mut ctx)
	if mi.on_click != unsafe { nil } {
		mi.on_click()
	}
	return true
}

// Transit zone — защита от «схлопывания» подменю при диагональном движении мыши.
// Когда курсор едет от пункта-родителя к раскрывшемуся подменю, он на пути
// пересекает другие пункты родителя, и без защиты подменю закрылось бы. Поэтому
// mouse_move внутри «коридора» (треугольника от середины края пункта-родителя до
// ближней стороны подменю + прямоугольник зазора) игнорируется.
// ─── Transit zone: точная проверка треугольником ───────
// Проверяет, находится ли мышь в треугольном "коридоре"
// от правого края parent item к child popup.
// Это предотвращает закрытие при движении мыши по диагонали.

// point_in_triangle: точка (px, py) внутри (или на границе) треугольника ABC — по знакам трёх векторных произведений (все одного знака => внутри).
fn point_in_triangle(px f32, py f32, ax f32, ay f32, bx f32, by f32, cx f32, cy f32) bool {
	d1 := (px - bx) * (ay - by) - (ax - bx) * (py - by)
	d2 := (px - cx) * (by - cy) - (bx - cx) * (py - cy)
	d3 := (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
	has_neg := d1 < 0 || d2 < 0 || d3 < 0
	has_pos := d1 > 0 || d2 > 0 || d3 > 0
	return !(has_neg && has_pos)
}

// menu_in_submenu_transit: true, если точка (mx, my) лежит в коридоре перехода от
// подсвеченного пункта любого уровня к следующему уровню. Подменю может открыться
// справа или слева (если справа не хватило места) — направление определяется
// сравнением cp.x и pp.x. v_pad = 12 расширяет коридор по вертикали, gap_pad — по
// горизонтали, перекрывая 2-пиксельный зазор между попапами.
fn menu_in_submenu_transit(ms &MenuState, mx f32, my f32) bool {
	if ms.levels.len < 2 {
		return false
	}
	for li := 0; li < ms.levels.len - 1; li++ {
		parent_idx := ms.levels[li].hover_idx
		if parent_idx < 0 {
			continue
		}
		pp := ms.levels[li].popup
		ir := menu_item_rect(ms.levels[li].items, parent_idx, pp.x, pp.y, pp.w)
		cp := ms.levels[li + 1].popup

		// Определяем, с какой стороны child popup
		child_is_right := cp.x >= pp.x

		// Строим треугольник от края parent item к ближним углам child popup
		// с щедрым расширением по вертикали
		v_pad := f32(12)

		if child_is_right {
			// Apex: правый край parent item (середина)
			apex_x := ir.x + ir.w
			apex_y := ir.y + ir.h * 0.5
			// Два угла child popup (расширенные)
			top_x := cp.x
			top_y := cp.y - v_pad
			bot_x := cp.x
			bot_y := cp.y + cp.h + v_pad
			if point_in_triangle(mx, my, apex_x, apex_y, top_x, top_y, bot_x, bot_y) {
				return true
			}
		} else {
			// Apex: левый край parent item (середина)
			apex_x := ir.x
			apex_y := ir.y + ir.h * 0.5
			// Два угла child popup (расширенные)
			top_x := cp.x + cp.w
			top_y := cp.y - v_pad
			bot_x := cp.x + cp.w
			bot_y := cp.y + cp.h + v_pad
			if point_in_triangle(mx, my, apex_x, apex_y, top_x, top_y, bot_x, bot_y) {
				return true
			}
		}

		// Также проверяем прямой зазор между popup'ами (gap ~2px)
		gap_pad := f32(4)
		if child_is_right {
			gap := Rect{pp.x + pp.w - gap_pad, ir.y - v_pad, cp.x - pp.x - pp.w + gap_pad * 2, ir.h + v_pad * 2}
			if gap.w > 0 && gap.contains(mx, my) {
				return true
			}
		} else {
			gap := Rect{cp.x + cp.w - gap_pad, ir.y - v_pad, pp.x - cp.x - cp.w + gap_pad * 2, ir.h + v_pad * 2}
			if gap.w > 0 && gap.contains(mx, my) {
				return true
			}
		}
	}
	return false
}

// ═══════════════════════════════════════════════════════
// MenuState
// ═══════════════════════════════════════════════════════

// MenuLevel — один открытый уровень меню (корневой попап или подменю): список
// пунктов, прямоугольник попапа на экране и индекс подсвеченного пункта (-1 — нет).
struct MenuLevel {
mut:
	items     []&MenuItem
	popup     Rect
	hover_idx int = -1
}

// MenuState — состояние открытого меню владельца (MenuBar/ContextMenu/MenuButton).
// levels — стек открытых уровней (levels[0] — корень, последний — самое глубокое
// подменю); open — меню показано; bar_active — индекс активного заголовка
// MenuBar (-1 для остальных). Живёт внутри структуры владельца, поэтому
// замыкания оверлея держат mut-ссылку на него.
@[heap]
struct MenuState {
mut:
	levels     []MenuLevel
	open       bool
	bar_active int = -1
	// Виджет-владелец (ContextMenu/MenuBar/MenuButton) — ключ слота оверлея
	// окна (overlay.v). Ставится владельцем перед открытием.
	owner voidptr
}

// close_all закрывает все уровни, сбрасывает подсветки и снимает оверлей, если
// он принадлежит owner (clear_overlay сам проверяет владельца, так что вызов на
// уже вытесненном меню безопасен). Идемпотентна. Кадр не инвалидирует.
fn (mut ms MenuState) close_all(mut ctx RenderContext) {
	for lvl in ms.levels {
		menu_clear_all_state(lvl.items)
	}
	ms.levels.clear()
	ms.open = false
	ms.bar_active = -1
	ctx.clear_overlay(ms.owner)
}

// close_submenus_from закрывает все уровни глубже level (сам level остаётся) и снимает sub_open с пунктов-родителей.
fn (mut ms MenuState) close_submenus_from(level int) {
	for i := ms.levels.len - 1; i > level; i-- {
		menu_clear_all_state(ms.levels[i].items)
		if i > 0 {
			pidx := ms.levels[i - 1].hover_idx
			if pidx >= 0 && pidx < ms.levels[i - 1].items.len {
				menu_set_sub_open(ms.levels[i - 1].items, pidx, false)
			}
		}
		ms.levels.delete(i)
	}
}

// open_submenu раскрывает подменю пункта item_idx уровня level: помечает пункт
// sub_open и добавляет новый MenuLevel справа от родителя (если справа не
// помещается — слева), по вертикали выровненный по пункту. Пустое подменю
// (children.len == 0) не открывается.
fn (mut ms MenuState) open_submenu(level int, item_idx int, ctx &RenderContext) {
	if level >= ms.levels.len {
		return
	}
	mi := ms.levels[level].items[item_idx]
	if mi.kind != .submenu || mi.children.len == 0 {
		return
	}
	menu_set_sub_open(ms.levels[level].items, item_idx, true)

	parent_popup := ms.levels[level].popup
	ir := menu_item_rect(ms.levels[level].items, item_idx, parent_popup.x, parent_popup.y,
		parent_popup.w)
	sz := menu_popup_size(mi.children, ctx)

	mut sx := ir.x + ir.w
	if sx + sz.x > ctx.screen_width {
		sx = parent_popup.x - sz.x
	}
	if sx < 0 {
		sx = 2
	}
	sub_rect := menu_adjust_rect(sx, ir.y, sz.x, sz.y, ctx)

	ms.levels << MenuLevel{
		items: mi.children
		popup: sub_rect
	}
}

// ─── Install overlay (CHANGED: transit zone + keyboard nav) ─

// menu_install_overlay включает отрисовку и обработку событий уже подготовленного
// ms.levels через слот оверлея окна (overlay.v): ставит draw-замыкание (рисует все
// уровни), ev-замыкание (мышь, клавиши, переход в подменю) и close-хук
// (close_all). ms.owner должен быть выставлен заранее — это ключ слота.
// Используется ContextMenu; MenuBar и MenuButton содержат собственные копии
// этого же кода (с добавками: переключение заголовков бара, клик по самой
// кнопке). События ev в оверлее приходят раньше обычных виджетов окна.
fn menu_install_overlay(mut ms MenuState, mut ctx RenderContext) {
	ms.open = true

	draw := fn [mut ms] (mut ctx RenderContext) {
		if !ms.open {
			return
		}
		for lvl in ms.levels {
			menu_draw_popup(lvl.items, lvl.popup, mut ctx)
		}
	}

	ev := fn [mut ms, mut ctx] (event &GuiEvent, app &App) bool {
		if !ms.open {
			return false
		}

		// Для колеса позиция курсора берётся из ctx (последняя известная), для
		// остальных событий — из самого события.
		mx := if event.typ == .mouse_wheel { ctx.mouse_x } else { event.mouse_x }
		my := if event.typ == .mouse_wheel { ctx.mouse_y } else { event.mouse_y }

		match event.typ {
			.mouse_move {
				// Check transit FIRST — if mouse is in transit corridor,
				// don't process anything else (keeps submenu alive)
				if ms.levels.len >= 2 && menu_in_submenu_transit(ms, mx, my) {
					return true
				}

				// Ищем попап под курсором, начиная с самого глубокого уровня (он рисуется поверх).
				mut in_any_popup := false
				mut found_level := -1
				mut found_idx := -1
				for li := ms.levels.len - 1; li >= 0; li-- {
					lvl := ms.levels[li]
					if lvl.popup.contains(mx, my) {
						in_any_popup = true
						found_level = li
						found_idx = menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y,
							lvl.popup.w)
						break
					}
				}

				// Курсор над попапом: если подсвеченный пункт сменился, уровни глубже закрываются;
				// пункт-подменю раскрывается сразу при наведении.
				if in_any_popup {
					if found_level < ms.levels.len - 1 {
						current_hover := ms.levels[found_level].hover_idx
						if found_idx != current_hover {
							ms.close_submenus_from(found_level)
						}
					}
					menu_update_hover(ms.levels[found_level].items, found_idx)
					ms.levels[found_level].hover_idx = found_idx

					if found_idx >= 0 {
						mi := ms.levels[found_level].items[found_idx]
						if mi.kind == .submenu && mi.enabled && !mi.sub_open {
							ms.open_submenu(found_level, found_idx, ctx)
						}
					}
					return true
				}

				// Курсор вне всех попапов: подсветка последнего уровня снимается, но меню остаётся
				// открытым, событие не поглощаем (false).
				// Mouse is outside everything
				if ms.levels.len > 0 {
					last := ms.levels.len - 1
					menu_clear_all_hover(ms.levels[last].items)
					ms.levels[last].hover_idx = -1
				}
				return false
			}
			// Не левая кнопка: закрываем меню и пропускаем событие дальше (false), чтобы,
			// например, правый клик мог открыть другое контекстное меню.
			.mouse_down {
				if event.mouse_btn != .left {
					ms.close_all(mut ctx)
					return false
				}
				// Клик внутри попапа: по пункту — выполнить; мимо пункта (отступ/разделитель) —
				// поглотить. Клик вне всех попапов закрывает меню и НЕ поглощается.
				for li := ms.levels.len - 1; li >= 0; li-- {
					lvl := ms.levels[li]
					if lvl.popup.contains(mx, my) {
						idx := menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y,
							lvl.popup.w)
						if idx >= 0 {
							return menu_activate_hovered(mut ms, li, idx, mut ctx)
						}
						return true
					}
				}
				ms.close_all(mut ctx)
				return false
			}
			// Клавиатура: Esc закрывает самый глубокий уровень (или всё меню), Вверх/Вниз двигают
			// подсветку по выбираемым пунктам, Вправо раскрывает подменю и подсвечивает его
			// первый пункт, Влево закрывает подменю, Enter/Space выполняют подсвеченный пункт.
			// Перечисленные клавиши поглощаются (true); остальные идут дальше.
			.key_down {
				match event.keycode {
					sdl_k_escape {
						if ms.levels.len > 1 {
							ms.close_submenus_from(ms.levels.len - 2)
							return true
						}
						ms.close_all(mut ctx)
						return true
					}
					sdl_k_up {
						if ms.levels.len > 0 {
							last := ms.levels.len - 1
							cur := ms.levels[last].hover_idx
							next := menu_next_selectable(ms.levels[last].items, cur, -1)
							if next >= 0 {
								menu_update_hover(ms.levels[last].items, next)
								ms.levels[last].hover_idx = next
							}
						}
						return true
					}
					sdl_k_down {
						if ms.levels.len > 0 {
							last := ms.levels.len - 1
							cur := ms.levels[last].hover_idx
							next := menu_next_selectable(ms.levels[last].items, cur, 1)
							if next >= 0 {
								menu_update_hover(ms.levels[last].items, next)
								ms.levels[last].hover_idx = next
							}
						}
						return true
					}
					sdl_k_right {
						if ms.levels.len > 0 {
							last := ms.levels.len - 1
							idx := ms.levels[last].hover_idx
							if idx >= 0 && idx < ms.levels[last].items.len {
								mi := ms.levels[last].items[idx]
								if mi.kind == .submenu && mi.enabled && !mi.sub_open {
									ms.open_submenu(last, idx, ctx)
									if ms.levels.len > last + 1 {
										new_last := ms.levels.len - 1
										first := menu_next_selectable(ms.levels[new_last].items,
											-1, 1)
										if first >= 0 {
											menu_update_hover(ms.levels[new_last].items, first)
											ms.levels[new_last].hover_idx = first
										}
									}
									return true
								}
							}
						}
						return true
					}
					sdl_k_left {
						if ms.levels.len > 1 {
							ms.close_submenus_from(ms.levels.len - 2)
							return true
						}
						return true
					}
					sdl_k_return, sdl_k_space {
						if ms.levels.len > 0 {
							last := ms.levels.len - 1
							idx := ms.levels[last].hover_idx
							if idx >= 0 {
								return menu_activate_hovered(mut ms, last, idx, mut ctx)
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

	ctx.set_overlay(ms.owner, draw, ev, fn [mut ms] (mut ctx RenderContext) {
		ms.close_all(mut ctx)
	})
}

// ═══════════════════════════════════════════════════════
// ContextMenu
// ═══════════════════════════════════════════════════════

// ContextMenu — контекстное меню по правому клику. Хитбокс — bounds виджета target
// (attach), а у несвязанного меню — собственный bounds. ВАЖНО: само меню должно
// быть добавлено в окно через win.add_widget(menu), иначе события к нему не
// дойдут (draw() у него пустой — рисует оверлей). Шорткаты пунктов работают,
// пока меню закрыто.
@[heap]
pub struct ContextMenu {
pub mut:
	type_tag int = kind_context_menu // тег типа, см. widget_tag.v
	bounds   Rect
	items    []&MenuItem
	state    MenuState
	visible  bool    = true
	enabled  bool    = true
	target   &Widget = unsafe { nil }
	// Цель уничтожена (detach_target): меню больше не открывается правым кликом.
	// Отдельный флаг, а не просто target = nil: меню без цели открывается по всему
	// своему bounds, то есть обычно по всему окну.
	target_lost bool
	// Called with the click coordinates right before the menu opens on a
	// right-click. Lets the app prepare state (e.g. select the list row
	// under the cursor) before any item action runs.
	on_open fn (f32, f32) = unsafe { nil }
}

// context_menu создаёт пустое контекстное меню.
pub fn context_menu() &ContextMenu {
	return &ContextMenu{}
}

// add добавляет пункт верхнего уровня.
pub fn (mut cm ContextMenu) add(item &MenuItem) {
	cm.items << unsafe { item }
}

// attach привязывает меню к виджету: правый клик открывает меню только в его bounds.
pub fn (mut cm ContextMenu) attach(target &Widget) {
	cm.target = unsafe { target }
	cm.target_lost = false
}

// detach_target разрывает связь с уничтоженной целью: ссылка держала бы её память, а
// правый клик по месту, где она была, открывал бы меню. После этого меню правым
// кликом не открывается, пока его не привяжут заново (attach); show() работает.
// Мост зовёт это в vgui_destroy для каждого меню, привязанного к уничтожаемому виджету.
pub fn (mut cm ContextMenu) detach_target() {
	cm.target = unsafe { nil }
	cm.target_lost = true
}

// is_attached_to сообщает, привязано ли меню к объекту виджета по адресу obj.
pub fn (cm &ContextMenu) is_attached_to(obj voidptr) bool {
	return obj != unsafe { nil } && cm.target != unsafe { nil }
		&& widget_object_addr(cm.target) == obj
}

// show открывает меню в точке (x, y), сдвигая его так, чтобы оно поместилось в окно. Пустое меню не открывается. Закрывает ранее открытое меню этого владельца.
pub fn (mut cm ContextMenu) show(x f32, y f32, mut ctx RenderContext) {
	if cm.items.len == 0 {
		return
	}
	cm.state.owner = voidptr(&cm)
	cm.state.close_all(mut ctx)
	sz := menu_popup_size(cm.items, ctx)
	popup := menu_adjust_rect(x, y, sz.x, sz.y, ctx)
	cm.state.levels << MenuLevel{
		items: cm.items
		popup: popup
	}
	menu_install_overlay(mut cm.state, mut ctx)
}

// close закрывает меню (если открыто).
pub fn (mut cm ContextMenu) close(mut ctx RenderContext) {
	cm.state.close_all(mut ctx)
}

// is_open: меню сейчас показано.
pub fn (cm &ContextMenu) is_open() bool {
	return cm.state.open
}

// draw ничего не рисует: попап рисует оверлей окна.
pub fn (mut cm ContextMenu) draw(mut ctx RenderContext) {
}

// Раньше это был ручной if-is по типам, со старым неполным списком:
// Icon/Canvas/TableView/CodeEditor/TextArea/GridLayout/Accordion и
// другие типы, добавленные позже, в него не попадали и откатывались
// на cm.bounds — а это bounds самого ContextMenu (обычно устанавливается
// равным всему экрану виджетом-владельцем), поэтому правый клик по
// ЛЮБОЙ точке окна ошибочно открывал меню, привязанное к такому
// виджету. Теперь схлопнуто в get_widget_bounds (widget_tree.v) —
// единственный источник правды для bounds любого Widget-типа; cm.bounds
// остаётся только запасным вариантом для nil target (меню, ни к чему
// не привязанное — попадание по всему cm.bounds осталось намеренным).
// context_menu_get_target_bounds возвращает область, в которой правый клик открывает меню (подробности — комментарий ниже).
fn context_menu_get_target_bounds(cm &ContextMenu) Rect {
	if cm.target_lost {
		return Rect{}
	}
	if unsafe { cm.target == nil } {
		return cm.bounds
	}
	return get_widget_bounds(cm.target)
}

// handle_event: правый клик в хитбоксе открывает меню (предварительно зовётся
// on_open с координатами клика); key_down при закрытом меню проверяет шорткаты
// пунктов. Пока меню открыто, события обрабатывает оверлей, а не этот метод.
pub fn (mut cm ContextMenu) handle_event(event &GuiEvent, app &App) bool {
	if !cm.visible || !cm.enabled {
		return false
	}

	// Right-click opens context menu
	if event.typ == .mouse_down && event.mouse_btn == .right {
		hit_rect := context_menu_get_target_bounds(cm)
		if hit_rect.contains(event.mouse_x, event.mouse_y) {
			if cm.items.len > 0 {
				ctx_ptr := app.get_active_ctx()
				if unsafe { ctx_ptr != nil } {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					if cm.on_open != unsafe { nil } {
						cm.on_open(event.mouse_x, event.mouse_y)
					}
					cm.show(event.mouse_x, event.mouse_y, mut ctx_mut)
					return true
				}
			}
		}
	}

	// Shortcut dispatch (NEW) — when menu is NOT open, check key_down
	if event.typ == .key_down && !cm.state.open {
		if menu_try_shortcut(cm.items, event) {
			return true
		}
	}

	return false
}

// ═══════════════════════════════════════════════════════
// MenuBar
// ═══════════════════════════════════════════════════════

// MenuBarEntry — один заголовок строки меню ('Файл', 'Правка') с его пунктами; hovered — наведение на заголовок.
struct MenuBarEntry {
mut:
	title   string
	items   []&MenuItem
	hovered bool
}

// MenuBar — горизонтальная строка меню (заголовки + выпадающие попапы).
// Заголовки идут слева направо подряд, ширина = текст + 2*pad. Высота полосы —
// max(bar_height, bounds.h). Попап рисуется оверлеем окна; пока он открыт,
// наведение на другой заголовок переключает меню (как в десктопных ОС), а
// стрелки влево/вправо листают заголовки.
@[heap]
pub struct MenuBar {
pub mut:
	type_tag   int = kind_menu_bar // тег типа, см. widget_tag.v
	bounds     Rect
	entries    []MenuBarEntry
	visible    bool = true
	enabled    bool = true
	state      MenuState
	bar_height f32 = 26
	pad        f32 = 8
	// keys_when_hidden - сочетания клавиш пунктов работают и у скрытой
	// полосы (visible = false: не рисуется, места не занимает, мышь не
	// берёт) - полноэкранный режим без меню
	keys_when_hidden bool
}

// menu_bar создаёт пустую строку меню.
pub fn menu_bar() &MenuBar {
	return &MenuBar{}
}

// add_menu добавляет заголовок title с выпадающим списком items.
pub fn (mut mb MenuBar) add_menu(title string, items []&MenuItem) {
	mb.entries << MenuBarEntry{
		title: title
		items: items
	}
}

// set_items заменяет пункты меню idx (номер в порядке add_menu) - для
// меню, которое меняется на ходу (список файлов, пресетов). Уже открытое
// меню держит свою копию списка и покажет новые пункты при следующем
// открытии. Индекс вне списка игнорируется.
pub fn (mut mb MenuBar) set_items(idx int, items []&MenuItem) {
	if idx < 0 || idx >= mb.entries.len {
		return
	}
	mb.entries[idx].items = items.clone()
}

// Эффективная высота бара: растягивается под bounds, если bounds.h больше
fn (mb &MenuBar) eff_bar_height() f32 {
	if mb.bounds.h > mb.bar_height {
		return mb.bounds.h
	}
	return mb.bar_height
}

// entry_rect возвращает прямоугольник заголовка idx: ширина по тексту + pad с обеих сторон, высота — eff_bar_height. Пустой Rect, если индекс вне списка. Позиции считаются заново на каждый вызов (кэша нет).
fn (mb &MenuBar) entry_rect(idx int, ctx &RenderContext) Rect {
	font := ctx.get_font_immut(.regular, 0)
	mut x := mb.bounds.x
	for i in 0 .. mb.entries.len {
		tw := ctx.measure_text_with_font(mb.entries[i].title, font).x
		entry_w := tw + mb.pad * 2
		if i == idx {
			return Rect{x, mb.bounds.y, entry_w, mb.eff_bar_height()}
		}
		x += entry_w
	}
	return Rect{}
}

// hit_entry возвращает индекс заголовка под точкой или -1.
fn (mb &MenuBar) hit_entry(mx f32, my f32, ctx &RenderContext) int {
	bh := mb.eff_bar_height() // ← НОВОЕ
	if my < mb.bounds.y || my > mb.bounds.y + bh {
		return -1
	}
	for i in 0 .. mb.entries.len {
		r := mb.entry_rect(i, ctx)
		if r.contains(mx, my) {
			return i
		}
	}
	return -1
}

// Collect all menu items from all entries (for shortcut matching)
fn (mb &MenuBar) all_items() []&MenuItem {
	mut result := []&MenuItem{}
	for e in mb.entries {
		for item in e.items {
			result << item
		}
	}
	return result
}

// open_entry открывает попап заголовка idx под ним (или переключает на него уже
// открытое меню): закрывает прежнее, ставит bar_active и уровень 0, устанавливает
// оверлей. Пустой список пунктов: bar_active ставится, но
// попап не открывается и меню остаётся закрытым (state.open = false). Замыкания draw/ev — копия логики
// menu_install_overlay плюс: наведение на другой заголовок переключает меню;
// клик по заголовку закрывает меню; Влево/Вправо листают заголовки (с зацикливанием).
fn (mut mb MenuBar) open_entry(idx int, mut ctx RenderContext) {
	if idx < 0 || idx >= mb.entries.len {
		return
	}
	mb.state.owner = voidptr(&mb)
	mb.state.close_all(mut ctx)
	mb.state.bar_active = idx

	er := mb.entry_rect(idx, ctx) // er.h теперь = eff_bar_height
	items := mb.entries[idx].items
	if items.len == 0 {
		return
	}
	sz := menu_popup_size(items, ctx)
	popup := menu_adjust_rect(er.x, er.y + er.h, sz.x, sz.y, ctx)
	mb.state.levels << MenuLevel{
		items: items
		popup: popup
	}

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
				bar_hit := mb.hit_entry(mx, my, ctx)
				if bar_hit >= 0 && bar_hit != mb.state.bar_active {
					mb.open_entry(bar_hit, mut ctx)
					return true
				}

				// Check transit FIRST
				if mb.state.levels.len >= 2 && menu_in_submenu_transit(mb.state, mx, my) {
					return true
				}

				mut in_any_popup := false
				mut found_level := -1
				mut found_idx := -1
				for li := mb.state.levels.len - 1; li >= 0; li-- {
					lvl := mb.state.levels[li]
					if lvl.popup.contains(mx, my) {
						in_any_popup = true
						found_level = li
						found_idx = menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y,
							lvl.popup.w)
						break
					}
				}

				if in_any_popup {
					if found_level < mb.state.levels.len - 1 {
						current_hover := mb.state.levels[found_level].hover_idx
						if found_idx != current_hover {
							mb.state.close_submenus_from(found_level)
						}
					}
					menu_update_hover(mb.state.levels[found_level].items, found_idx)
					mb.state.levels[found_level].hover_idx = found_idx
					if found_idx >= 0 {
						mi := mb.state.levels[found_level].items[found_idx]
						if mi.kind == .submenu && mi.enabled && !mi.sub_open {
							mb.state.open_submenu(found_level, found_idx, ctx)
						}
					}
					return true
				}

				if mb.state.levels.len > 0 {
					last := mb.state.levels.len - 1
					menu_clear_all_hover(mb.state.levels[last].items)
					mb.state.levels[last].hover_idx = -1
				}

				if mb.bounds.contains(mx, my) {
					return true
				}
				return false
			}
			.mouse_down {
				if event.mouse_btn != .left {
					mb.state.close_all(mut ctx)
					return false
				}

				bar_hit := mb.hit_entry(mx, my, ctx)
				if bar_hit >= 0 {
					mb.state.close_all(mut ctx)
					return true
				}

				for li := mb.state.levels.len - 1; li >= 0; li-- {
					lvl := mb.state.levels[li]
					if lvl.popup.contains(mx, my) {
						idx := menu_hit_item(lvl.items, mx, my, lvl.popup.x, lvl.popup.y,
							lvl.popup.w)
						if idx >= 0 {
							return menu_activate_hovered(mut mb.state, li, idx, mut ctx)
						}
						return true
					}
				}
				mb.state.close_all(mut ctx)
				return false
			}
			.key_down {
				match event.keycode {
					sdl_k_escape {
						if mb.state.levels.len > 1 {
							mb.state.close_submenus_from(mb.state.levels.len - 2)
							return true
						}
						mb.state.close_all(mut ctx)
						return true
					}
					sdl_k_left {
						// If in submenu, close it; otherwise switch bar entry
						if mb.state.levels.len > 1 {
							mb.state.close_submenus_from(mb.state.levels.len - 2)
							return true
						}
						new_idx := if mb.state.bar_active > 0 {
							mb.state.bar_active - 1
						} else {
							mb.entries.len - 1
						}
						mb.open_entry(new_idx, mut ctx)
						return true
					}
					sdl_k_right {
						// If hovered item is submenu, open it; otherwise switch bar entry
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
						new_idx := if mb.state.bar_active < mb.entries.len - 1 {
							mb.state.bar_active + 1
						} else {
							0
						}
						mb.open_entry(new_idx, mut ctx)
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
					sdl_k_return, sdl_k_space {
						if mb.state.levels.len > 0 {
							last := mb.state.levels.len - 1
							idx := mb.state.levels[last].hover_idx
							if idx >= 0 {
								return menu_activate_hovered(mut mb.state, last, idx, mut ctx)
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
		mb.state.close_all(mut ctx)
	})
}

// ─── Drawing ───────────────────────────────────────────

// draw рисует фон полосы с нижней границей, заголовки (активный и наведённый подсвечены) и ничего больше — попапы рисует оверлей.
pub fn (mut mb MenuBar) draw(mut ctx RenderContext) {
	if !mb.visible {
		return
	}

	bh := mb.eff_bar_height() // ← НОВОЕ
	bar_r := Rect{mb.bounds.x, mb.bounds.y, mb.bounds.w, bh}
	ctx.fill_rect(bar_r, ctx.theme.eff_menubar_bg())
	ctx.fill_rect(Rect{bar_r.x, bar_r.y + bar_r.h - 1, bar_r.w, 1}, ctx.theme.eff_menu_border())

	font := ctx.get_font(.regular, 0)
	fh := ctx.font_height_of(font)

	for i in 0 .. mb.entries.len {
		er := mb.entry_rect(i, ctx)
		is_active := mb.state.open && mb.state.bar_active == i
		is_hov := mb.entries[i].hovered

		if is_active {
			ctx.fill_rect(er, ctx.theme.eff_menubar_item_active().with_alpha(180))
		} else if is_hov {
			ctx.fill_rect(er, ctx.theme.eff_menubar_item_hover())
		}

		tc := if is_active {
			ctx.theme.eff_menu_item_sel_text()
		} else {
			ctx.theme.eff_menubar_item_text()
		}
		ty := er.y + (er.h - fh) * 0.5 // ← теперь центрируется по реальной высоте
		tx := er.x + mb.pad
		ctx.draw_text_with_font(mb.entries[i].title, tx, ty, tc, font)
	}
}

// ─── Events (CHANGED: added shortcut dispatch) ─────────

// handle_event: при скрытой полосе работают только шорткаты (если keys_when_hidden);
// иначе — подсветка заголовков по mouse_move, клик по заголовку открывает/закрывает
// его меню, key_down при закрытом меню проверяет шорткаты всех пунктов.
pub fn (mut mb MenuBar) handle_event(event &GuiEvent, app &App) bool {
	if !mb.enabled {
		return false
	}
	if !mb.visible {
		if mb.keys_when_hidden && event.typ == .key_down {
			return menu_try_shortcut(mb.all_items(), event)
		}
		return false
	}

	ctx_ptr := app.get_active_ctx()
	if unsafe { ctx_ptr == nil } {
		return false
	}

	match event.typ {
		.mouse_move {
			bar_r := Rect{mb.bounds.x, mb.bounds.y, mb.bounds.w, mb.bar_height}
			in_bar := bar_r.contains(event.mouse_x, event.mouse_y)
			for i in 0 .. mb.entries.len {
				r := mb.entry_rect(i, ctx_ptr)
				mb.entries[i].hovered = r.contains(event.mouse_x, event.mouse_y)
			}
			if in_bar && mb.state.open {
				hit := mb.hit_entry(event.mouse_x, event.mouse_y, ctx_ptr)
				if hit >= 0 && hit != mb.state.bar_active {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					mb.open_entry(hit, mut ctx_mut)
					return true
				}
			}
		}
		.mouse_down {
			if event.mouse_btn == .left {
				hit := mb.hit_entry(event.mouse_x, event.mouse_y, ctx_ptr)
				if hit >= 0 {
					mut ctx_mut := unsafe { &RenderContext(ctx_ptr) }
					if mb.state.open && mb.state.bar_active == hit {
						mb.state.close_all(mut ctx_mut)
					} else {
						mb.open_entry(hit, mut ctx_mut)
					}
					return true
				}
			}
		}
		.key_down {
			// Shortcut dispatch when menu is NOT open (NEW)
			if !mb.state.open {
				all := mb.all_items()
				if menu_try_shortcut(all, event) {
					return true
				}
			}
		}
		else {}
	}

	return false
}
